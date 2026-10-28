import CoreImage
import Foundation
import ImageIO

/// File helpers for the Core Image pipeline. Foundation, Core Image, and ImageIO
/// only, so it builds on macOS as well as iOS.
enum ImagingIO {

    /// One context for the whole app. Creating a `CIContext` is expensive and each
    /// native module used to build its own.
    static let context = CIContext(options: nil)

    static let jpegQuality = 0.95

    /// Loads an image with its EXIF orientation applied to the pixels, so later
    /// stages (and Vision) always see an upright image.
    static func load(path: String) -> CIImage? {
        CIImage(contentsOf: URL(fileURLWithPath: path),
                options: [.applyOrientationProperty: true])
    }

    /// Renders `image` straight to a JPEG in the temp directory, with no
    /// intermediate `CGImage` or `UIImage`. Returns the file path.
    static func writeJPEG(_ image: CIImage, prefix: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString).jpg")

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try context.writeJPEGRepresentation(
            of: image,
            to: url,
            colorSpace: colorSpace,
            options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): jpegQuality
            ])

        return url.path
    }
}
