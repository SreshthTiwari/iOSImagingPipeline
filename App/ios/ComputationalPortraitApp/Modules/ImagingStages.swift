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

    /// Runs Vision person segmentation and returns a soft matte (white = person)
    /// scaled to `image`'s extent. This is the only stage that has to execute
    /// eagerly, because Vision needs pixels.
    static func personMask(for image: CIImage) throws -> CIImage {
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

        let raw = CIImage(cvPixelBuffer: buffer)
        let scaled = raw
            .transformed(by: CGAffineTransform(
                scaleX: image.extent.width / raw.extent.width,
                y: image.extent.height / raw.extent.height))
            .cropped(to: image.extent)

        return scaled
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.0,
                kCIInputSaturationKey: 0.0,
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: maskSoftenRadius
            ])
            .cropped(to: image.extent)
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

    /// Tone map, scene enhance, sharpen, then bokeh, as one lazy graph.
    ///
    /// The segmentation runs on the unprocessed source rather than on the sharpened
    /// image the old chain used. Person matting is insensitive to these mild tonal
    /// changes, and it means Vision never has to force the earlier stages to render.
    static func fullPipeline(_ source: CIImage) throws -> CIImage {
        let mask = try personMask(for: source)
        let processed = sharpen(sceneEnhance(toneMap(source)))
        return bokeh(processed, mask: mask)
    }
}
