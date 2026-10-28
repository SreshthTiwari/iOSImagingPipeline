import Foundation
import UIKit

final class NativeImageUtils {

    static func saveImageToTemp(_ image: UIImage, filename: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    static func loadImage(from path: String) -> UIImage? {
        return UIImage(contentsOfFile: path)
    }

    static func tempFileURL(filename: String, ext: String = "jpg") -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(ext)
    }

    static func saveDataToTemp(_ data: Data, filename: String, ext: String = "jpg") -> String? {
        let url = tempFileURL(filename: filename, ext: ext)
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let longest = max(size.width, size.height)

        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}