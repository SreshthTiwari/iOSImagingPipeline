import CoreImage
import Vision

enum ImagingError: LocalizedError {
    case segmentationFailed(String)

    var errorDescription: String? {
        switch self {
        case .segmentationFailed(let reason):
            return "Person segmentation failed: \(reason)"
        }
    }
}

/// The image-processing stages, expressed as lazy Core Image graph transforms.
///
/// Every function takes a `CIImage` and returns a new `CIImage` without rendering
/// anything, so stages can be chained freely and rendered once at the end. This is
/// the single place filter parameters live: the per-stage React Native modules and
/// the full pipeline both call into it, so they cannot drift apart.
///
/// Each stage clamps its result to the displayable 0...1 range. A lazy float graph
/// otherwise carries out-of-range values forward, which the old render-to-JPEG chain
/// clipped implicitly between stages. `CISharpenLuminance` in particular scales colour
/// by a luminance ratio and produces huge values in near-black pixels; unclamped, the
/// background blur smears them into coloured blobs.
///
/// Only Core Image and Vision are used here (no UIKit or React) so the file also
/// compiles on macOS, which `tools/pipeline-bench` relies on.
enum ImagingStages {

    static let backgroundBlurRadius = 12.0
    static let maskSoftenRadius = 2.5

    /// Vision's person matte is never an error when nobody is in frame: it just comes back
    /// empty, which would make the whole image "background" and blur all of it. A matte
    /// covering less than this fraction of the frame is treated as "no person".
    static let minimumPersonCoverage = 0.01

    struct PersonMatte {
        /// Soft matte (white = person) scaled to the source image's extent.
        var mask: CIImage
        /// Fraction of the frame the matte marks as person, 0...1.
        var coverage: Double

        var hasPerson: Bool { coverage >= ImagingStages.minimumPersonCoverage }
    }

    static func toneMap(_ input: CIImage) -> CIImage {
        clampToDisplayRange(input
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: 0.15
            ])
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": 0.25,
                "inputHighlightAmount": 0.15
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.08,
                kCIInputSaturationKey: 1.02,
                kCIInputBrightnessKey: 0.0
            ]))
    }

    static func sceneEnhance(_ input: CIImage) -> CIImage {
        clampToDisplayRange(input
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: 0.2
            ])
            .applyingFilter("CIVibrance", parameters: [
                "inputAmount": 0.3
            ])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.1,
                kCIInputSaturationKey: 1.04,
                kCIInputBrightnessKey: 0.0
            ]))
    }

    static func sharpen(_ input: CIImage) -> CIImage {
        clampToDisplayRange(input.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: 1.0
        ]))
    }

    private static func clampToDisplayRange(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
    }

    /// Runs Vision person segmentation and returns a soft matte (white = person) scaled to
    /// `image`'s extent, with how much of the frame it covers. This is the only stage that
    /// has to execute eagerly, because Vision needs pixels.
    static func personMask(for image: CIImage) throws -> PersonMatte {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw ImagingError.segmentationFailed(error.localizedDescription)
        }

        guard let buffer = request.results?.first?.pixelBuffer else {
            throw ImagingError.segmentationFailed("Vision returned no mask")
        }

        let coverage = coverageFraction(of: buffer)

        let raw = CIImage(cvPixelBuffer: buffer)
        let scaled = raw
            .transformed(by: CGAffineTransform(
                scaleX: image.extent.width / raw.extent.width,
                y: image.extent.height / raw.extent.height))
            .cropped(to: image.extent)

        let mask = scaled
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.0,
                kCIInputSaturationKey: 0.0,
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: maskSoftenRadius
            ])
            .cropped(to: image.extent)

        return PersonMatte(mask: mask, coverage: coverage)
    }

    /// Share of pixels at or above mid-grey in Vision's one-byte-per-pixel matte.
    private static func coverageFraction(of buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return 0 }

        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var covered = 0
        for y in 0..<height {
            let row = pixels + y * rowBytes
            for x in 0..<width where row[x] >= 128 { covered += 1 }
        }
        return Double(covered) / Double(width * height)
    }

    /// Keeps the masked subject sharp and Gaussian-blurs everything else.
    static func bokeh(_ input: CIImage, mask: CIImage) -> CIImage {
        let background = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: backgroundBlurRadius
            ])
            .cropped(to: input.extent)

        return input
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: input.extent)
    }

    /// Tone map, scene enhance, sharpen, then bokeh, as one lazy graph. If no person is
    /// found the bokeh step is skipped, rather than blurring the whole frame.
    ///
    /// The segmentation runs on the unprocessed source rather than on the sharpened
    /// image the old chain used. Person matting is insensitive to these mild tonal
    /// changes, and it means Vision never has to force the earlier stages to render.
    static func fullPipeline(_ source: CIImage) throws -> CIImage {
        let matte = try personMask(for: source)
        let processed = sharpen(sceneEnhance(toneMap(source)))
        return matte.hasPerson ? bokeh(processed, mask: matte.mask) : processed
    }
}
