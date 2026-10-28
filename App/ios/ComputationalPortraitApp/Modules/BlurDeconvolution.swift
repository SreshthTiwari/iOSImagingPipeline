import Accelerate
import CoreImage
import Foundation

/// A single-channel float image, row-major.
struct FloatPlane {
    var width: Int
    var height: Int
    var data: [Float]

    init(width: Int, height: Int, data: [Float]) {
        precondition(data.count == width * height)
        self.width = width
        self.height = height
        self.data = data
    }

    init(width: Int, height: Int, fill: Float = 0) {
        self.width = width
        self.height = height
        self.data = [Float](repeating: fill, count: width * height)
    }
}

/// Uniform linear motion blur: the camera translated `length` pixels along `angleDegrees`
/// during the exposure. Angles are measured in image coordinates (x right, y down) over
/// [0, 180), since a blur direction and its opposite are the same kernel.
struct MotionBlurKernel: Equatable {
    var angleDegrees: Double
    var length: Double
}

struct DeblurResult {
    /// The restored image, or the input unchanged when no significant blur was found.
    var image: CIImage
    /// The estimated kernel, nil when the image was judged sharp and left alone.
    var kernel: MotionBlurKernel?
}

/// Blind motion deblurring: estimate a linear blur kernel, then invert it with a Wiener
/// filter. Everything is classical signal processing on Accelerate/vDSP FFTs.
///
/// Scope, on purpose: this handles *uniform linear* blur (one direction and length across
/// the frame). It cannot undo rotation, non-uniform shake, a moving subject against a
/// still background, or defocus blur, and it amplifies noise and creates some ringing near
/// strong edges, as every linear deconvolution does.
enum BlurDeconvolution {

    // MARK: Tuning

    /// Longest blur considered, in pixels of the input image.
    static let maxLength = 40.0
    /// Wiener noise-to-signal ratio for the final restoration (image in 0...1) as a function
    /// of the estimated noise level. The best value rises with noise (`tools/blur-eval
    /// oracle` restores with the true kernel across a range of values and noise levels):
    /// roughly 0.016 at sigma 0.002, 0.02 to 0.03 at 0.004, and 0.03 or more at 0.01.
    static func restorationNoiseToSignal(noiseSigma: Float) -> Float {
        0.012 + 3 * noiseSigma
    }
    /// Above this noise level (about 3/255) even the true kernel barely helps in testing, and
    /// the estimate is unreliable, so the image is left alone.
    static let maxNoiseSigma: Float = 0.012
    /// Wiener noise-to-signal ratio while scoring candidate kernels. Deliberately larger than
    /// the restoration value: it keeps 8-bit noise amplification from dominating the score.
    static let estimationNoiseToSignal: Float = 0.1

    // A kernel is only applied if it passes all three tests below. They are conservative on
    // purpose: in testing (`tools/blur-eval diagnose`), wrong kernels clustered near the
    // image axes and at short lengths, and a wrong long kernel can wreck a sharp photo.

    /// Shorter blurs are not worth the risk of correcting.
    static let acceptMinLength = 8.0
    /// Kernels within this many degrees of horizontal or vertical are rejected. The pixel
    /// grid, JPEG blocking and dominant horizontal/vertical edges all create false minima
    /// there, so genuine axis-aligned blur is declined rather than guessed at.
    static let acceptMinAxisDistance = 10.0
    /// The winner must beat the best *short* kernel (generic sharpening) by this fraction.
    static let acceptMargin = 0.02

    private static let searchMinLength = 3.0
    private static let coarseAngleStep = 3.0
    private static let coarseLengthStep = 3.0
    private static let windowCount = 4

    // MARK: Public entry point

    static func deblur(_ image: CIImage, context: CIContext = ImagingIO.context) -> DeblurResult? {
        guard let (planes, bounds) = renderPlanes(image, context: context) else { return nil }

        let lumaPlane = luma(of: planes)
        let sigma = estimateNoiseSigma(luma: lumaPlane)
        guard sigma <= maxNoiseSigma,
              let kernel = estimateKernel(luma: lumaPlane)?.kernel else {
            return DeblurResult(image: image, kernel: nil)
        }

        let psf = makePSF(kernel)
        guard let restored = deconvolve(planes: planes, psf: psf,
                                        noiseToSignal: restorationNoiseToSignal(noiseSigma: sigma)),
              let output = makeImage(planes: restored, bounds: bounds) else {
            return nil
        }
        return DeblurResult(image: output, kernel: kernel)
    }

    // MARK: Noise estimation

    /// Robust estimate of the standard deviation of white noise (image in 0...1).
    ///
    /// Convolves with a Laplacian-difference mask that cancels smooth image content (Immerkaer,
    /// 1996), then takes the median absolute response instead of the mean, so edges and
    /// texture, which produce a few large responses, barely move it.
    static func estimateNoiseSigma(luma: FloatPlane) -> Float {
        let w = luma.width, h = luma.height
        guard w >= 3, h >= 3 else { return 0 }

        let kernel: [Float] = [ 1, -2,  1,
                               -2,  4, -2,
                                1, -2,  1]
        var response = [Float](repeating: 0, count: w * h)
        luma.data.withUnsafeBufferPointer { src in
            response.withUnsafeMutableBufferPointer { dst in
                var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress!),
                                          height: vImagePixelCount(h), width: vImagePixelCount(w),
                                          rowBytes: w * MemoryLayout<Float>.stride)
                var output = vImage_Buffer(data: dst.baseAddress!,
                                           height: vImagePixelCount(h), width: vImagePixelCount(w),
                                           rowBytes: w * MemoryLayout<Float>.stride)
                vImageConvolve_PlanarF(&input, &output, nil, 0, 0, kernel, 3, 3, 0,
                                       vImage_Flags(kvImageEdgeExtend))
            }
        }

        // Interior pixels only, subsampled: a few hundred thousand values is plenty.
        let step = max(1, Int((Double(w * h) / 400_000).squareRoot()))
        var magnitudes: [Float] = []
        var y = 1
        while y < h - 1 {
            var x = 1
            while x < w - 1 { magnitudes.append(abs(response[y * w + x])); x += step }
            y += step
        }
        guard !magnitudes.isEmpty else { return 0 }
        magnitudes.sort()
        let median = magnitudes[magnitudes.count / 2]

        // The mask has squared-coefficient sum 36, so white noise of std sigma gives std 6 sigma;
        // for a Gaussian, median(|x|) = 0.6745 std.
        return median / (0.6745 * 6)
    }

    // MARK: Point spread function

    /// Normalised, anti-aliased line of `length` px at `angleDegrees`, in an odd-sized square.
    static func makePSF(_ kernel: MotionBlurKernel) -> FloatPlane {
        let size = max(3, (Int(kernel.length.rounded(.up)) + 2) | 1)
        var psf = FloatPlane(width: size, height: size)
        let c = Double(size / 2)
        let theta = kernel.angleDegrees * .pi / 180
        let dx = cos(theta), dy = sin(theta)

        let steps = max(2, Int(kernel.length * 8))
        for i in 0..<steps {
            let t = (Double(i) / Double(steps - 1) - 0.5) * kernel.length
            let x = c + t * dx, y = c + t * dy
            let x0 = Int(floor(x)), y0 = Int(floor(y))
            let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
            for (ox, oy, w) in [(0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)),
                                (0, 1, (1 - fx) * fy), (1, 1, fx * fy)] {
                let px = x0 + ox, py = y0 + oy
                if px >= 0, px < size, py >= 0, py < size {
                    psf.data[py * size + px] += w
                }
            }
        }

        var sum: Float = 0
        vDSP_sve(psf.data, 1, &sum, vDSP_Length(psf.data.count))
        var scale = 1 / sum
        vDSP_vsmul(psf.data, 1, &scale, &psf.data, 1, vDSP_Length(psf.data.count))
        return psf
    }

    // MARK: Kernel estimation

    struct Estimate {
        /// The kernel to apply, nil if the evidence did not clear every acceptance test.
        var kernel: MotionBlurKernel?
        /// Best candidate found whether or not it was accepted.
        var winner: MotionBlurKernel
        /// Scores (window-normalised sparsity, lower is sharper) of the winner and of the
        /// best short kernel it is compared against.
        var winnerScore: Double
        var shortKernelScore: Double

        /// Relative improvement of the winner over the short-kernel yardstick.
        var improvement: Double {
            shortKernelScore > 0 ? (shortKernelScore - winnerScore) / shortKernelScore : 0
        }
    }

    private static let cropSize = 192
    private static let estimationFFTSize = 256
    private static let scoreBorder = 26

    /// One textured window of the image, ready to be filtered by any candidate kernel.
    private struct Crop {
        var re: [Float]          // spectrum of the reflect-padded window
        var im: [Float]
        var region: (x0: Int, y0: Int, x1: Int, y1: Int)
        var baseline: Double     // sparsity of the untouched window
    }

    /// Searches (angle, length) for the kernel whose Wiener inverse gives the sparsest
    /// gradients (Krishnan, Tay & Fergus, 2011), scored on several independent textured
    /// windows and averaged. A real camera shake is the same in every window; a false
    /// minimum caused by one patch of content is not.
    static func estimateKernel(luma: FloatPlane) -> Estimate? {
        let n = estimationFFTSize
        guard let fft = FFT2D(size: n) else { return nil }
        let crops = prepareCrops(luma: luma, fft: fft)
        guard !crops.isEmpty else { return nil }

        /// Mean over windows of (sparsity after inverting the candidate) / (sparsity of the
        /// window as is). Below 1 means the candidate made the windows sharper.
        func scores(_ candidates: [MotionBlurKernel]) -> [Double] {
            var out = [Double](repeating: 0, count: candidates.count)
            out.withUnsafeMutableBufferPointer { results in
                let sink = results
                DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
                    sink[i] = aggregateScore(candidates[i], crops: crops, fft: fft)
                }
            }
            return out
        }

        func best(_ candidates: [MotionBlurKernel]) -> (MotionBlurKernel, Double) {
            let s = scores(candidates)
            let i = s.indices.min { s[$0] < s[$1] }!
            return (candidates[i], s[i])
        }

        var coarse: [MotionBlurKernel] = []
        for angle in stride(from: 0.0, to: 180.0, by: coarseAngleStep) {
            for length in stride(from: coarseLengthStep, through: maxLength, by: coarseLengthStep) {
                coarse.append(MotionBlurKernel(angleDegrees: angle, length: length))
            }
        }
        let coarseScores = scores(coarse)
        let coarseBest = coarseScores.indices.min { coarseScores[$0] < coarseScores[$1] }!
        var (winner, winnerScore) = (coarse[coarseBest], coarseScores[coarseBest])

        func refine(angleSpan: Double, angleStep: Double, lengthSpan: Double, lengthStep: Double) {
            var grid: [MotionBlurKernel] = []
            for da in stride(from: -angleSpan, through: angleSpan, by: angleStep) {
                for dl in stride(from: -lengthSpan, through: lengthSpan, by: lengthStep) {
                    let length = min(maxLength, max(searchMinLength, winner.length + dl))
                    var angle = (winner.angleDegrees + da).truncatingRemainder(dividingBy: 180)
                    if angle < 0 { angle += 180 }
                    grid.append(MotionBlurKernel(angleDegrees: angle, length: length))
                }
            }
            let (k, s) = best(grid)
            if s < winnerScore { winner = k; winnerScore = s }
        }
        refine(angleSpan: 3, angleStep: 1, lengthSpan: 2, lengthStep: 1)
        refine(angleSpan: 0.75, angleStep: 0.75, lengthSpan: 0.5, lengthStep: 0.5)

        // Yardstick: the best *short* kernel. Any Wiener filter lowers the measure a little by
        // acting as generic sharpening; real blur must beat that by a clear margin.
        var shortKernels: [MotionBlurKernel] = []
        for angle in stride(from: 0.0, to: 180.0, by: 15.0) {
            for length in [2.0, 3.0] { shortKernels.append(MotionBlurKernel(angleDegrees: angle, length: length)) }
        }
        let shortKernelScore = scores(shortKernels).min()!

        var estimate = Estimate(kernel: nil, winner: winner, winnerScore: winnerScore,
                                shortKernelScore: shortKernelScore)
        if winner.length >= acceptMinLength,
           axisDistance(winner.angleDegrees) >= acceptMinAxisDistance,
           estimate.improvement >= acceptMargin {
            estimate.kernel = winner
        }
        return estimate
    }

    /// Degrees between `angle` and the nearest of horizontal (0/180) or vertical (90).
    static func axisDistance(_ angle: Double) -> Double {
        let a = angle.truncatingRemainder(dividingBy: 180)
        let wrapped = a < 0 ? a + 180 : a
        return min(wrapped, abs(wrapped - 90), 180 - wrapped)
    }

    private static func aggregateScore(_ kernel: MotionBlurKernel, crops: [Crop], fft: FFT2D) -> Double {
        windowScores(kernel, crops: crops, fft: fft).reduce(0, +) / Double(crops.count)
    }

    private static func windowScores(_ kernel: MotionBlurKernel, crops: [Crop], fft: FFT2D) -> [Double] {
        let n = fft.n
        let wiener = WienerFilter(psf: makePSF(kernel), fft: fft, noiseToSignal: estimationNoiseToSignal)
        return crops.map { crop in
            var re = crop.re, im = crop.im
            wiener.apply(re: &re, im: &im)
            fft.transform(&re, &im, inverse: true)
            return sparsity(re, n: n, region: crop.region) / crop.baseline
        }
    }

    private static func prepareCrops(luma: FloatPlane, fft: FFT2D) -> [Crop] {
        let n = fft.n
        return texturedWindows(of: luma, size: cropSize, count: windowCount).map { window in
            let pad = (n - window.width) / 2
            var re = [Float](repeating: 0, count: n * n)
            var im = re
            for y in 0..<n {
                let sy = reflect(y - pad, window.height)
                for x in 0..<n {
                    re[y * n + x] = window.data[sy * window.width + reflect(x - pad, window.width)]
                }
            }
            let region = (x0: pad + scoreBorder, y0: pad + scoreBorder,
                          x1: pad + window.width - scoreBorder, y1: pad + window.height - scoreBorder)
            let baseline = sparsity(re, n: n, region: region)
            fft.transform(&re, &im, inverse: false)
            return Crop(re: re, im: im, region: region, baseline: max(baseline, 1e-9))
        }
    }

    /// Normalised sparsity of the gradient field, ||g||1 / ||g||2. Scale invariant, and
    /// lower for sharper images.
    private static func sparsity(_ a: [Float], n: Int,
                                 region: (x0: Int, y0: Int, x1: Int, y1: Int)) -> Double {
        var l1 = 0.0, l2 = 0.0
        for y in region.y0..<(region.y1 - 1) {
            for x in region.x0..<(region.x1 - 1) {
                let v = a[y * n + x]
                let gx = Double(a[y * n + x + 1] - v), gy = Double(a[(y + 1) * n + x] - v)
                l1 += abs(gx) + abs(gy)
                l2 += gx * gx + gy * gy
            }
        }
        return l2 > 0 ? l1 / l2.squareRoot() : .infinity
    }

    /// Up to `count` non-overlapping `size`-square windows with the most gradient energy, so
    /// the estimate is driven by real texture rather than flat sky or wall.
    private static func texturedWindows(of plane: FloatPlane, size: Int, count: Int) -> [FloatPlane] {
        let w = plane.width, h = plane.height
        let cw = min(size, w), ch = min(size, h)
        guard cw >= 64, ch >= 64 else { return [] }
        let stride = max(16, size / 2)

        var candidates: [(x: Int, y: Int, energy: Double)] = []
        var oy = 0
        while oy + ch <= h {
            var ox = 0
            while ox + cw <= w {
                var energy = 0.0
                var y = oy
                while y < oy + ch - 1 {
                    var x = ox
                    while x < ox + cw - 1 {
                        let v = plane.data[y * w + x]
                        let gx = plane.data[y * w + x + 1] - v
                        let gy = plane.data[(y + 1) * w + x] - v
                        energy += Double(gx * gx + gy * gy)
                        x += 2
                    }
                    y += 2
                }
                candidates.append((ox, oy, energy))
                ox += stride
            }
            oy += stride
        }
        candidates.sort { $0.energy > $1.energy }

        var chosen: [(x: Int, y: Int, energy: Double)] = []
        for c in candidates where chosen.count < count {
            if chosen.allSatisfy({ abs($0.x - c.x) >= cw || abs($0.y - c.y) >= ch }) { chosen.append(c) }
        }

        return chosen.map { origin in
            var window = FloatPlane(width: cw, height: ch)
            for y in 0..<ch {
                for x in 0..<cw {
                    window.data[y * cw + x] = plane.data[(origin.y + y) * w + origin.x + x]
                }
            }
            return window
        }
    }

    // MARK: Full-image Wiener deconvolution

    /// Overlap-save tiling: each tile is read with a mirrored margin larger than the kernel,
    /// filtered with one shared FFT'd kernel, and only the uncorrupted core is kept. Memory
    /// stays at a few tile buffers however large the photo is.
    static func deconvolve(planes: [FloatPlane], psf: FloatPlane, noiseToSignal: Float) -> [FloatPlane]? {
        guard let first = planes.first else { return nil }
        let w = first.width, h = first.height

        let margin = max(48, psf.width + 16)
        let needed = max(w, h) + 2 * margin
        var n = 256
        while n < needed && n < 1024 { n *= 2 }
        let core = n - 2 * margin
        guard core > 0, let fft = FFT2D(size: n) else { return nil }

        let wiener = WienerFilter(psf: psf, fft: fft, noiseToSignal: noiseToSignal)
        let tilesX = (w + core - 1) / core, tilesY = (h + core - 1) / core

        var outputs = planes.map { _ in FloatPlane(width: w, height: h) }
        for channel in planes.indices {
            let source = planes[channel].data
            outputs[channel].data.withUnsafeMutableBufferPointer { out in
                let sink = out
                DispatchQueue.concurrentPerform(iterations: tilesX * tilesY) { tile in
                    let x0 = (tile % tilesX) * core, y0 = (tile / tilesX) * core
                    var re = [Float](repeating: 0, count: n * n)
                    var im = [Float](repeating: 0, count: n * n)

                    let columns = (0..<n).map { reflect(x0 - margin + $0, w) }
                    for j in 0..<n {
                        let row = reflect(y0 - margin + j, h) * w
                        for i in 0..<n { re[j * n + i] = source[row + columns[i]] }
                    }

                    fft.transform(&re, &im, inverse: false)
                    wiener.apply(re: &re, im: &im)
                    fft.transform(&re, &im, inverse: true)

                    for j in 0..<min(core, h - y0) {
                        for i in 0..<min(core, w - x0) {
                            sink[(y0 + j) * w + x0 + i] = re[(j + margin) * n + i + margin]
                        }
                    }
                }
            }
        }
        return outputs
    }

    // MARK: Image <-> planes

    /// RGB planes in 0...1 (gamma-encoded sRGB) plus the integer bounds they came from.
    static func renderPlanes(_ image: CIImage, context: CIContext) -> ([FloatPlane], CGRect)? {
        let bounds = image.extent.integral
        let w = Int(bounds.width), h = Int(bounds.height)
        guard w >= 8, h >= 8, let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &rgba, rowBytes: w * 4, bounds: bounds,
                       format: .RGBA8, colorSpace: srgb)

        let count = vDSP_Length(w * h)
        var scale: Float = 1.0 / 255.0
        var planes: [FloatPlane] = []
        for channel in 0..<3 {
            var plane = FloatPlane(width: w, height: h)
            rgba.withUnsafeBufferPointer { vDSP_vfltu8($0.baseAddress! + channel, 4, &plane.data, 1, count) }
            vDSP_vsmul(plane.data, 1, &scale, &plane.data, 1, count)
            planes.append(plane)
        }
        return (planes, bounds)
    }

    static func luma(of planes: [FloatPlane]) -> FloatPlane {
        var out = FloatPlane(width: planes[0].width, height: planes[0].height)
        let count = vDSP_Length(out.data.count)
        var weights: [Float] = [0.299, 0.587, 0.114]
        for c in 0..<3 {
            vDSP_vsma(planes[c].data, 1, &weights[c], out.data, 1, &out.data, 1, count)
        }
        return out
    }

    static func makeImage(planes: [FloatPlane], bounds: CGRect) -> CIImage? {
        let w = planes[0].width, h = planes[0].height
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let count = vDSP_Length(w * h)
        var lo: Float = 0, hi: Float = 255, scale: Float = 255
        var scaled = [Float](repeating: 0, count: w * h)
        for channel in 0..<3 {
            vDSP_vsmul(planes[channel].data, 1, &scale, &scaled, 1, count)
            vDSP_vclip(scaled, 1, &lo, &hi, &scaled, 1, count)
            rgba.withUnsafeMutableBufferPointer { vDSP_vfixru8(scaled, 1, $0.baseAddress! + channel, 4, count) }
        }

        return CIImage(bitmapData: Data(rgba), bytesPerRow: w * 4, size: CGSize(width: w, height: h),
                       format: .RGBA8, colorSpace: srgb)
            .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }
}

// MARK: - FFT and Wiener filter

/// Square power-of-two 2D FFT on split-complex buffers.
final class FFT2D {
    let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup

    init?(size n: Int) {
        guard n > 1, n & (n - 1) == 0 else { return nil }
        let log2n = vDSP_Length(n.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.n = n
        self.log2n = log2n
        self.setup = setup
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// In place. The inverse transform is normalised, so forward then inverse is identity.
    func transform(_ re: inout [Float], _ im: inout [Float], inverse: Bool) {
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft2d_zip(setup, &split, 1, vDSP_Stride(n), log2n, log2n,
                               inverse ? FFTDirection(kFFTDirection_Inverse) : FFTDirection(kFFTDirection_Forward))
            }
        }
        if inverse {
            var s = 1 / Float(n * n)
            let count = vDSP_Length(n * n)
            vDSP_vsmul(re, 1, &s, &re, 1, count)
            vDSP_vsmul(im, 1, &s, &im, 1, count)
        }
    }
}

/// Wiener inverse filter G = conj(H) / (|H|^2 + K) in the frequency domain.
struct WienerFilter {
    private let n: Int
    private let hRe: [Float]
    private let hIm: [Float]
    private let denominator: [Float]

    init(psf: FloatPlane, fft: FFT2D, noiseToSignal k: Float) {
        let n = fft.n
        self.n = n
        var re = [Float](repeating: 0, count: n * n)
        var im = [Float](repeating: 0, count: n * n)

        // Wrap the kernel so its centre sits at the origin; then the filtered result needs
        // no shift to line up with the input.
        let cx = psf.width / 2, cy = psf.height / 2
        for y in 0..<psf.height {
            for x in 0..<psf.width {
                re[((y - cy + n) % n) * n + (x - cx + n) % n] = psf.data[y * psf.width + x]
            }
        }
        fft.transform(&re, &im, inverse: false)

        let count = vDSP_Length(n * n)
        var power = [Float](repeating: 0, count: n * n)
        var imPower = power
        vDSP_vsq(re, 1, &power, 1, count)
        vDSP_vsq(im, 1, &imPower, 1, count)
        vDSP_vadd(power, 1, imPower, 1, &power, 1, count)

        var k = k
        vDSP_vsadd(power, 1, &k, &power, 1, count)
        // Keep unit gain at DC so the filter does not dim the image by 1/(1+K).
        power[0] -= k

        hRe = re
        hIm = im
        denominator = power
    }

    func apply(re: inout [Float], im: inout [Float]) {
        let count = vDSP_Length(n * n)
        var a = [Float](repeating: 0, count: n * n)
        var b = a
        var scratch = a

        // numerator = Y * conj(H):  re = yr*hr + yi*hi,  im = yi*hr - yr*hi
        vDSP_vmul(re, 1, hRe, 1, &a, 1, count)
        vDSP_vmul(im, 1, hIm, 1, &scratch, 1, count)
        vDSP_vadd(a, 1, scratch, 1, &a, 1, count)

        vDSP_vmul(im, 1, hRe, 1, &b, 1, count)
        vDSP_vmul(re, 1, hIm, 1, &scratch, 1, count)
        vDSP_vsub(scratch, 1, b, 1, &b, 1, count)

        vDSP_vdiv(denominator, 1, a, 1, &re, 1, count)
        vDSP_vdiv(denominator, 1, b, 1, &im, 1, count)
    }
}

/// Mirror indexing without repeating the edge sample (a b c | b a b ...).
@inline(__always)
func reflect(_ index: Int, _ count: Int) -> Int {
    if count == 1 { return 0 }
    let period = 2 * (count - 1)
    let i = ((index % period) + period) % period
    return i < count ? i : period - i
}
