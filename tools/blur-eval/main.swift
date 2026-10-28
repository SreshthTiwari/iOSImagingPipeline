import Accelerate
import CoreImage
import Foundation

// Evaluation harness for the sharpness metric and the motion deblur.
//
//   run.sh metric <image>...     score vs known Gaussian blur, at several resolutions
//   run.sh evaluate <image>...   blur with known motion kernels, run the real deblur, summarise
//   run.sh oracle <image>...     restoration quality with the TRUE kernel, across noise-to-signal values
//
// Builds the app's real Swift sources on macOS (see run.sh).

let ctx = ImagingIO.context
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ path: String) -> CIImage {
    guard let img = ImagingIO.load(path: path) else { fatalError("cannot load \(path)") }
    return img
}

func scaled(_ image: CIImage, longSide: CGFloat) -> CIImage {
    let s = longSide / max(image.extent.width, image.extent.height)
    return image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: s, kCIInputAspectRatioKey: 1.0])
}

func gaussian(_ image: CIImage, sigma: Double) -> CIImage {
    sigma == 0 ? image : image.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma])
        .cropped(to: image.extent)
}

/// Materialize to 8 bit so scores see what a saved JPEG would.
func bake(_ image: CIImage) -> CIImage {
    let cg = ctx.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB)!
    return CIImage(cgImage: cg)
}

func runMetric(_ paths: [String]) {
    let sigmas: [Double] = [0, 0.5, 1, 1.5, 2, 3, 5, 8]
    let sizes: [CGFloat] = [800, 1600, 3200]
    for path in paths {
        let base = load(path)
        print("\n\(URL(fileURLWithPath: path).lastPathComponent)  (native \(Int(base.extent.width))x\(Int(base.extent.height)))")
        print("| long side | " + sigmas.map { "σ=\($0)" }.joined(separator: " | ") + " |")
        print("|" + String(repeating: " --- |", count: sigmas.count + 1))
        for size in sizes {
            // Blur sigma is specified at 1600 px and scaled with resolution so every row
            // shows the same *visual* amount of blur.
            let img = scaled(base, longSide: size)
            let cells = sigmas.map { sigma -> String in
                let blurred = bake(gaussian(img, sigma: sigma * Double(size) / 1600))
                let score = SharpnessMetric.laplacianVariance(of: blurred) ?? .nan
                return String(format: "%.0f", score)
            }
            print("| \(Int(size)) | " + cells.joined(separator: " | ") + " |")
        }
    }
}


// MARK: - Motion deblur evaluation

/// Ground-truth motion blur, made independently of the deconvolution code: average many
/// sub-pixel-shifted bilinear copies along the path, as an exposure physically would.
func motionBlur(_ planes: [FloatPlane], angle: Double, length: Double) -> [FloatPlane] {
    let shifts = max(2, Int(length * 3))
    let theta = angle * .pi / 180
    return planes.map { plane in
        let w = plane.width, h = plane.height
        var acc = [Float](repeating: 0, count: w * h)
        for s in 0..<shifts {
            let t = (Double(s) / Double(shifts - 1) - 0.5) * length
            let sx = t * cos(theta), sy = t * sin(theta)
            let ix = Int(floor(sx)), iy = Int(floor(sy))
            let fx = Float(sx - Double(ix)), fy = Float(sy - Double(iy))
            let xs0 = (0..<w).map { min(max($0 + ix, 0), w - 1) }
            let xs1 = (0..<w).map { min(max($0 + ix + 1, 0), w - 1) }
            for y in 0..<h {
                let r0 = min(max(y + iy, 0), h - 1) * w, r1 = min(max(y + iy + 1, 0), h - 1) * w
                for x in 0..<w {
                    let top = plane.data[r0 + xs0[x]] * (1 - fx) + plane.data[r0 + xs1[x]] * fx
                    let bottom = plane.data[r1 + xs0[x]] * (1 - fx) + plane.data[r1 + xs1[x]] * fx
                    acc[y * w + x] += top * (1 - fy) + bottom * fy
                }
            }
        }
        var inv = 1 / Float(shifts)
        vDSP_vsmul(acc, 1, &inv, &acc, 1, vDSP_Length(acc.count))
        return FloatPlane(width: w, height: h, data: acc)
    }
}

func addNoise(_ planes: [FloatPlane], sigma: Float) -> [FloatPlane] {
    guard sigma > 0 else { return planes }
    var rng = SystemRandomNumberGenerator()
    return planes.map { p in
        var q = p
        for i in q.data.indices {
            // Box-Muller
            let u1 = Float.random(in: Float.leastNonzeroMagnitude...1, using: &rng), u2 = Float.random(in: 0...1, using: &rng)
            q.data[i] += sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
        return q
    }
}

/// Quantize to 8 bit exactly as a saved JPEG-less photo would be.
func quantized(_ planes: [FloatPlane]) -> CIImage {
    bake(BlurDeconvolution.makeImage(planes: planes, bounds: CGRect(x: 0, y: 0, width: planes[0].width, height: planes[0].height))!)
}

/// PSNR over the interior (borders excluded: blur there depends on edge handling).
func psnr(_ a: [FloatPlane], _ b: [FloatPlane], border: Int = 40) -> Double {
    var se = 0.0, n = 0.0
    for c in 0..<3 {
        let w = a[c].width, h = a[c].height
        for y in border..<(h - border) {
            for x in border..<(w - border) {
                let d = Double(a[c].data[y * w + x] - b[c].data[y * w + x])
                se += d * d; n += 1
            }
        }
    }
    let mse = se / n
    return mse == 0 ? .infinity : 10 * log10(1 / mse)
}

func angleError(_ a: Double, _ b: Double) -> Double {
    var d = abs(a - b).truncatingRemainder(dividingBy: 180)
    if d > 90 { d = 180 - d }
    return d
}

func referencePlanes(_ path: String, longSide: CGFloat) -> [FloatPlane] {
    let base = load(path)
    let img = bake(base.extent.width >= base.extent.height && base.extent.width > longSide || base.extent.height > longSide
                   ? scaled(base, longSide: longSide) : base)
    return BlurDeconvolution.renderPlanes(img, context: ctx)!.0
}

/// Runs the real `BlurDeconvolution.deblur` (acceptance rules included) over images x blur
/// cases and summarises: how many restorations helped, how many hurt, how many were
/// declined, and whether any *unblurred* image was wrongly "fixed".
func runEvaluate(_ paths: [String], noise: Float, cases: [(Double, Double)], verbose: Bool) {
    var gains: [Double] = [], good = 0, harmful = 0, neutral = 0, declined = 0, total = 0
    var sharpTotal = 0, falsePositives = 0
    if verbose {
        print("| image | true θ / L | est θ / L | θ err | PSNR blurred | PSNR restored | gain |")
        print("| --- | --- | --- | --- | --- | --- | --- |")
    }
    for path in paths {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let ref = referencePlanes(path, longSide: 1000)

        // Unblurred control: must be left alone.
        let sharp = quantized(addNoise(ref, sigma: noise))
        sharpTotal += 1
        if BlurDeconvolution.deblur(sharp)!.kernel != nil { falsePositives += 1; print("FALSE POSITIVE on unblurred \(name)") }

        for (angle, length) in cases {
            let photo = quantized(addNoise(motionBlur(ref, angle: angle, length: length), sigma: noise))
            let photoPlanes = BlurDeconvolution.renderPlanes(photo, context: ctx)!.0
            let result = BlurDeconvolution.deblur(photo)!
            total += 1

            var gain = 0.0
            var est = "declined"
            var err = "-"
            var after = psnr(ref, photoPlanes)
            if let k = result.kernel {
                after = psnr(ref, BlurDeconvolution.renderPlanes(result.image, context: ctx)!.0)
                gain = after - psnr(ref, photoPlanes)
                est = String(format: "%.1f° / %.1f", k.angleDegrees, k.length)
                err = String(format: "%.1f°", angleError(k.angleDegrees, angle))
                gains.append(gain)
                if gain > 0.5 { good += 1 } else if gain < -0.3 { harmful += 1 } else { neutral += 1 }
            } else {
                declined += 1
            }
            if verbose {
                print("| \(name) | \(Int(angle))° / \(Int(length)) | \(est) | \(err) | \(String(format: "%.1f", psnr(ref, photoPlanes))) | \(String(format: "%.1f", after)) | \(result.kernel == nil ? "-" : String(format: "%+.1f dB", gain)) |")
            }
        }
    }
    let applied = good + harmful + neutral
    print("\nnoise σ=\(noise) · \(paths.count) images × \(cases.count) blur cases = \(total) blurred cases")
    print("applied \(applied) (\(good) helped >0.5 dB, \(neutral) neutral, \(harmful) hurt <-0.3 dB), declined \(declined)")
    if !gains.isEmpty {
        print(String(format: "mean gain when applied %+.2f dB (best %+.1f, worst %+.1f)", gains.reduce(0, +) / Double(gains.count), gains.max()!, gains.min()!))
    }
    print("false positives on unblurred controls: \(falsePositives) of \(sharpTotal)")
}

/// Per-stage cost of the deblur at a given size. The restoration step is forced with a fixed
/// kernel (30 deg, 21 px) so it runs regardless of image content.
func runTiming(_ path: String, megapixels: Double) {
    func ms(_ body: () -> Void) -> Double {
        let t = DispatchTime.now().uptimeNanoseconds; body()
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
    }
    let base = load(path)
    let scale = (megapixels * 1e6 / (base.extent.width * base.extent.height)).squareRoot()
    let image = bake(base.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]))
    print("\(Int(image.extent.width))x\(Int(image.extent.height)) = \(String(format: "%.1f", image.extent.width * image.extent.height / 1e6)) MP")

    var planes: [FloatPlane] = [], bounds = CGRect.zero
    var luma = FloatPlane(width: 1, height: 1), restored: [FloatPlane] = [], output: CIImage?
    var runs: [[Double]] = []
    for _ in 0..<4 {   // first run is warm-up
        var t: [Double] = []
        t.append(ms { (planes, bounds) = BlurDeconvolution.renderPlanes(image, context: ctx)! })
        t.append(ms { luma = BlurDeconvolution.luma(of: planes) })
        t.append(ms { _ = BlurDeconvolution.estimateNoiseSigma(luma: luma) })
        t.append(ms { _ = BlurDeconvolution.estimateKernel(luma: luma) })
        let psf = BlurDeconvolution.makePSF(MotionBlurKernel(angleDegrees: 30, length: 21))
        t.append(ms { restored = BlurDeconvolution.deconvolve(planes: planes, psf: psf, noiseToSignal: 0.02)! })
        t.append(ms { output = BlurDeconvolution.makeImage(planes: restored, bounds: bounds) })
        t.append(ms { _ = try? ImagingIO.writeJPEG(output!, prefix: "timing") })
        runs.append(t)
    }
    let names = ["render to planes", "luma", "noise estimate", "kernel search", "Wiener restore (3 ch)", "pack to RGBA", "JPEG write"]
    var total = 0.0
    for (i, n) in names.enumerated() {
        let v = runs.dropFirst().map { $0[i] }.sorted()[1]
        total += v
        print("  \(n.padding(toLength: 24, withPad: " ", startingAt: 0)) \(String(format: "%6.0f", v)) ms")
    }
    print("  \("total".padding(toLength: 24, withPad: " ", startingAt: 0)) \(String(format: "%6.0f", total)) ms")
}

/// Does the noise estimator recover the noise we inject (plus the 8-bit quantisation floor)?
func runNoise(_ paths: [String]) {
    let sigmas: [Float] = [0, 0.002, 0.004, 0.01, 0.02]
    print("| image | " + sigmas.map { "σ=\($0)" }.joined(separator: " | ") + " |")
    print("|" + String(repeating: " --- |", count: sigmas.count + 1))
    for path in paths {
        let ref = referencePlanes(path, longSide: 1000)
        let cells = sigmas.map { sigma -> String in
            let photo = quantized(addNoise(ref, sigma: sigma))
            let luma = BlurDeconvolution.luma(of: BlurDeconvolution.renderPlanes(photo, context: ctx)!.0)
            return String(format: "%.4f", BlurDeconvolution.estimateNoiseSigma(luma: luma))
        }
        print("| \(URL(fileURLWithPath: path).lastPathComponent) | " + cells.joined(separator: " | ") + " |")
    }
}

/// Upper bound on restoration quality: use the true kernel, vary only the Wiener parameter.
func runOracle(_ paths: [String], noise: Float) {
    let ks: [Float] = [0.0005, 0.001, 0.002, 0.004, 0.008, 0.016, 0.032]
    print("noise σ = \(noise); PSNR (dB) of restoration with the TRUE kernel\n")
    print("| image | θ / L | blurred | " + ks.map { "K=\($0)" }.joined(separator: " | ") + " |")
    print("|" + String(repeating: " --- |", count: ks.count + 3))
    for path in paths {
        let name = URL(fileURLWithPath: path).lastPathComponent
        let ref = referencePlanes(path, longSide: 1000)
        for (angle, length) in [(0.0, 9.0), (30.0, 15.0), (135.0, 31.0)] {
            let photo = quantized(addNoise(motionBlur(ref, angle: angle, length: length), sigma: noise))
            let planes = BlurDeconvolution.renderPlanes(photo, context: ctx)!.0
            let psf = BlurDeconvolution.makePSF(MotionBlurKernel(angleDegrees: angle, length: length))
            let cells = ks.map { k -> String in
                let restored = BlurDeconvolution.deconvolve(planes: planes, psf: psf, noiseToSignal: k)!
                return String(format: "%.1f", psnr(ref, restored.map { p in
                    var q = p; var lo: Float = 0, hi: Float = 1
                    vDSP_vclip(q.data, 1, &lo, &hi, &q.data, 1, vDSP_Length(q.data.count)); return q }))
            }
            print("| \(name) | \(Int(angle))° / \(Int(length)) | \(String(format: "%.1f", psnr(ref, planes))) | " + cells.joined(separator: " | ") + " |")
        }
    }
}

var args = Array(CommandLine.arguments.dropFirst())
var noise: Float = 0.004
var verbose = false
var cases: [(Double, Double)] = [(30, 15), (50, 25), (75, 21), (135, 31), (160, 12), (0, 9), (100, 39)]
if let i = args.firstIndex(of: "--noise") { noise = Float(args[i + 1]) ?? noise; args.removeSubrange(i...(i + 1)) }
if let i = args.firstIndex(of: "--verbose") { verbose = true; args.remove(at: i) }
if let i = args.firstIndex(of: "--cases") {
    // e.g. --cases 20/11,60/18  (angle/length)
    cases = args[i + 1].split(separator: ",").map { pair in
        let v = pair.split(separator: "/").map { Double($0)! }
        return (v[0], v[1])
    }
    args.removeSubrange(i...(i + 1))
}
guard let command = args.first else {
    FileHandle.standardError.write(Data("usage: run.sh metric|evaluate|oracle|noise <image>... [--noise S] [--cases A/L,...] [--verbose]\n".utf8)); exit(2)
}
switch command {
case "metric": runMetric(Array(args.dropFirst()))
case "evaluate": runEvaluate(Array(args.dropFirst()), noise: noise, cases: cases, verbose: verbose)
case "timing": runTiming(args[1], megapixels: Double(args[2])!)
case "noise": runNoise(Array(args.dropFirst()))
case "oracle": runOracle(Array(args.dropFirst()), noise: noise)
default:
    FileHandle.standardError.write(Data("unknown command \(command)\n".utf8)); exit(2)
}
