import Foundation
import UIKit
import CoreImage
import CoreVideo
import Accelerate
import React

@objc(BlurMetricsModule)
class BlurMetricsModule: NSObject {
    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func computeBlurScore(_ imagePath: String,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let score = self.blurScore(at: imagePath) else {
                    throw NSError(domain: "BlurMetricsModule",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Unable to compute blur score"])
                }

                DispatchQueue.main.async {
                    resolve(score)
                }
            } catch {
                DispatchQueue.main.async {
                    reject("BLUR_SCORE_ERROR", error.localizedDescription, error)
                }
            }
        }
    }

    private func blurScore(at imagePath: String) -> Double? {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
            return nil
        }

        guard let pixelBuffer = pixelBuffer(from: cgImage) else {
            return nil
        }

        return laplacianVariance(pixelBuffer: pixelBuffer)
    }

    private func pixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: baseAddress,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: bytesPerRow,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func laplacianVariance(pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0.0
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let raw = baseAddress.assumingMemoryBound(to: UInt8.self)

        var grayscale = [Float](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let b = Float(raw[offset + 0])
                let g = Float(raw[offset + 1])
                let r = Float(raw[offset + 2])
                grayscale[y * width + x] = 0.114 * b + 0.587 * g + 0.299 * r
            }
        }

        var laplacian = [Float](repeating: 0, count: width * height)

        if width < 3 || height < 3 {
            return 0.0
        }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x

                let center = grayscale[idx]
                let left = grayscale[idx - 1]
                let right = grayscale[idx + 1]
                let top = grayscale[idx - width]
                let bottom = grayscale[idx + width]

                laplacian[idx] = (4.0 * center) - left - right - top - bottom
            }
        }

        let values = laplacian[width + 1..<(laplacian.count - width - 1)]
        if values.isEmpty { return 0.0 }

        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { $0 + (($1 - mean) * ($1 - mean)) } / Float(values.count)

        return Double(variance)
    }
}
