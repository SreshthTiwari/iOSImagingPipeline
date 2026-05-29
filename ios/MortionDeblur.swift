import Foundation
import UIKit
import CoreImage
import Accelerate
import React

@objc(MotionDeblurModule)
class MotionDeblurModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func estimateMotionBlur(_ imagePath: NSString,
                            resolver resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let image = UIImage(contentsOfFile: path),
                      let cgImage = image.cgImage else {
                    reject("MOTION_BLUR_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                let score = self.laplacianVariance(cgImage: cgImage)
                let result: [String: Any] = [
                    "blurScore": score,
                    "isBlurry": score < 150.0
                ]

                resolve(result)
            }
        }
    }

    @objc
    func removeMotionBlur(_ imagePath: NSString,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let image = UIImage(contentsOfFile: path),
                      let cgImage = image.cgImage else {
                    reject("MOTION_BLUR_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                let input = CIImage(cgImage: cgImage)

                guard let sharpened = self.deblurApproximation(input: input),
                      let outputCG = self.ciContext.createCGImage(sharpened, from: sharpened.extent) else {
                    reject("MOTION_BLUR_ERROR", "Failed to remove motion blur", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG)

                guard let savedPath = self.saveToTemp(image: outputUIImage) else {
                    reject("MOTION_BLUR_ERROR", "Could not save deblurred image", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func laplacianVariance(cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height

        guard width > 2, height > 2 else { return 0.0 }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &rawData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return 0.0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gray = [Float](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let r = Float(rawData[idx + 0])
                let g = Float(rawData[idx + 1])
                let b = Float(rawData[idx + 2])
                gray[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        var lap = [Float](repeating: 0, count: width * height)

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let center = gray[i]
                let left = gray[i - 1]
                let right = gray[i + 1]
                let top = gray[i - width]
                let bottom = gray[i + width]

                lap[i] = (4.0 * center) - left - right - top - bottom
            }
        }

        let values = lap.filter { $0 != 0 }
        guard !values.isEmpty else { return 0.0 }

        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { $0 + (($1 - mean) * ($1 - mean)) } / Float(values.count)

        return Double(variance)
    }

    private func deblurApproximation(input: CIImage) -> CIImage? {
        // Classical approximation: edge-aware sharpening + mild high-frequency emphasis.
        guard let sharpen = CIFilter(name: "CISharpenLuminance"),
              let unsharp = CIFilter(name: "CIUnsharpMask") else {
            return nil
        }

        sharpen.setValue(input, forKey: kCIInputImageKey)
        sharpen.setValue(1.0, forKey: kCIInputSharpnessKey)

        guard let sharpened = sharpen.outputImage else {
            return nil
        }

        unsharp.setValue(sharpened, forKey: kCIInputImageKey)
        unsharp.setValue(2.0, forKey: kCIInputRadiusKey)
        unsharp.setValue(0.5, forKey: kCIInputIntensityKey)

        return unsharp.outputImage
    }

    private func saveToTemp(image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            return nil
        }

        let filename = "motion_deblur_\(UUID().uuidString).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }
}