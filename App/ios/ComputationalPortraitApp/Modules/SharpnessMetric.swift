import Accelerate
import CoreImage

/// Variance-of-Laplacian focus measure (Pech-Pacheco et al.): sharp images have strong
/// edges and so a high-variance Laplacian response, blurred images do not.
///
/// This is the only implementation in the app. The score is computed on a copy scaled so
/// its long side is at most `analysisMaxDimension`, because the raw variance grows with
/// resolution: the same photo would otherwise score very differently at 3 MP and 12 MP and
/// a single threshold could not work across camera frames and imported images.
enum SharpnessMetric {

    static let analysisMaxDimension: CGFloat = 1024

    /// Scores below this are labelled blurry. Calibrated with `tools/blur-eval metric`.
    /// Keep in sync with the default in `src/native/BlurMetricsBridge.ts`.
    static let blurryThreshold = 150.0

    static func isBlurry(_ score: Double) -> Bool {
        score < blurryThreshold
    }

    /// Returns nil if the image is too small to have an interior (under 3x3) or cannot
    /// be rendered.
    static func laplacianVariance(of image: CIImage, context: CIContext = ImagingIO.context) -> Double? {
        let luma = lumaPlane(of: image, context: context)
        guard let luma, luma.width >= 3, luma.height >= 3 else { return nil }
        return laplacianVariance(of: luma)
    }

    // MARK: - Pieces

    /// Gamma-encoded luma (Rec. 601 weights) in 0...255, downscaled to the analysis size.
    static func lumaPlane(of image: CIImage, context: CIContext) -> FloatPlane? {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else { return nil }

        let scale = min(1, analysisMaxDimension / max(extent.width, extent.height))
        let scaled = scale < 1
            ? image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0
            ])
            : image

        let bounds = scaled.extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        guard width > 0, height > 0, let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        context.render(scaled, toBitmap: &rgba, rowBytes: width * 4, bounds: bounds,
                       format: .RGBA8, colorSpace: srgb)

        let count = vDSP_Length(width * height)
        var r = [Float](repeating: 0, count: width * height)
        var g = r, b = r
        rgba.withUnsafeBufferPointer { p in
            vDSP_vfltu8(p.baseAddress! + 0, 4, &r, 1, count)
            vDSP_vfltu8(p.baseAddress! + 1, 4, &g, 1, count)
            vDSP_vfltu8(p.baseAddress! + 2, 4, &b, 1, count)
        }

        var luma = [Float](repeating: 0, count: width * height)
        var wr: Float = 0.299, wg: Float = 0.587, wb: Float = 0.114
        vDSP_vsmul(r, 1, &wr, &luma, 1, count)
        vDSP_vsma(g, 1, &wg, luma, 1, &luma, 1, count)
        vDSP_vsma(b, 1, &wb, luma, 1, &luma, 1, count)

        return FloatPlane(width: width, height: height, data: luma)
    }

    /// 4-neighbour Laplacian, variance over interior pixels only (the 1 px border has no
    /// full neighbourhood, and edge-extended values there would bias the result).
    static func laplacianVariance(of plane: FloatPlane) -> Double {
        let w = plane.width, h = plane.height
        var response = [Float](repeating: 0, count: w * h)

        // Kernel is symmetric, so correlation and convolution coincide.
        let kernel: [Float] = [ 0, -1,  0,
                               -1,  4, -1,
                                0, -1,  0]

        plane.data.withUnsafeBufferPointer { src in
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

        var sum = 0.0, sumSquares = 0.0
        let rowCount = vDSP_Length(w - 2)
        for y in 1..<(h - 1) {
            response.withUnsafeBufferPointer { p in
                let row = p.baseAddress! + y * w + 1
                var mean: Float = 0, meanSquare: Float = 0
                vDSP_meanv(row, 1, &mean, rowCount)
                vDSP_measqv(row, 1, &meanSquare, rowCount)
                sum += Double(mean)
                sumSquares += Double(meanSquare)
            }
        }

        let rows = Double(h - 2)
        let mean = sum / rows
        return max(0, sumSquares / rows - mean * mean)
    }
}
