import Foundation
import UIKit
import CoreImage
import Vision
import React

@objc(BokehModule)
class BokehModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func applyBokehEffect(_ imagePath: NSString,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let inputImage = UIImage(contentsOfFile: path) else {
                    reject("BOKEH_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                guard let cgImage = inputImage.cgImage else {
                    reject("BOKEH_ERROR", "Image does not contain a CGImage", nil)
                    return
                }

                let ciImage = CIImage(cgImage: cgImage)

                guard let mask = self.generatePersonMask(for: ciImage) else {
                    reject("BOKEH_ERROR", "Could not generate person mask", nil)
                    return
                }

                let blurredBackground = ciImage
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [
                        kCIInputRadiusKey: 20.0
                    ])
                    .cropped(to: ciImage.extent)

                guard let composited = self.composite(foreground: ciImage,
                                                      background: blurredBackground,
                                                      mask: mask) else {
                    reject("BOKEH_ERROR", "Could not composite bokeh image", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(composited, from: composited.extent) else {
                    reject("BOKEH_ERROR", "Could not render composited image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "bokeh") else {
                    reject("BOKEH_ERROR", "Could not save bokeh output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func generatePersonMask(for ciImage: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Bokeh segmentation failed:", error)
            return nil
        }

        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            print("No bokeh mask returned")
            return nil
        }

        var mask = CIImage(cvPixelBuffer: maskPixelBuffer)

        let xScale = ciImage.extent.width / mask.extent.width
        let yScale = ciImage.extent.height / mask.extent.height
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
            .cropped(to: ciImage.extent)

        mask = mask
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.0,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 1.0
            ])
            .cropped(to: ciImage.extent)

        return mask
    }

    private func composite(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage? {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            print("Could not create CIBlendWithMask")
            return nil
        }

        blendFilter.setValue(foreground, forKey: kCIInputImageKey)
        blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage?.cropped(to: foreground.extent)
    }

    private func saveToTemp(image: UIImage, prefix: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            return nil
        }

        let filename = "\(prefix)_\(UUID().uuidString).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            print("Save error:", error)
            return nil
        }
    }
}