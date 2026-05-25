import Foundation
import UIKit
import CoreImage
import React

@objc(BlurMetricsModule)
class BlurMetricsModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    func computeBlurScore(_ imagePath: String,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            reject("IMAGE_LOAD_ERROR", "Could not load image at path: \(imagePath)", nil)
            return
        }

        let score = calculateSharpnessScore(cgImage: cgImage)
        resolve(score)
    }

    private func calculateSharpnessScore(cgImage: CGImage) -> Double {
        // Very simple starter metric:
        // Convert to grayscale and estimate edge strength using Core Image filters.
        // This is not true Laplacian variance, but is a useful placeholder.

        let inputImage = CIImage(cgImage: cgImage)

        // Grayscale
        let grayFilter = CIFilter(name: "CIPhotoEffectMono")
        grayFilter?.setValue(inputImage, forKey: kCIInputImageKey)

        guard let grayOutput = grayFilter?.outputImage else {
            return 0.0
        }

        // Edge detect
        let edgesFilter = CIFilter(name: "CIEdges")
        edgesFilter?.setValue(grayOutput, forKey: kCIInputImageKey)
        edgesFilter?.setValue(10.0, forKey: kCIInputIntensityKey)

        guard let edgeOutput = edgesFilter?.outputImage else {
            return 0.0
        }

        // Render to bitmap
        let extent = edgeOutput.extent
        guard let edgeCGImage = ciContext.createCGImage(edgeOutput, from: extent) else {
            return 0.0
        }

        let width = edgeCGImage.width
        let height = edgeCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return 0.0
        }

        context.draw(edgeCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Compute average intensity as a rough edge-energy score
        var sum: Double = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let intensity = (r + g + b) / 3.0
            sum += intensity
        }

        let numPixels = Double(width * height)
        return numPixels > 0 ? sum / numPixels : 0.0
    }

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }
}