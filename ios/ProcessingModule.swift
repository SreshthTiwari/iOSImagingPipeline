import Foundation
import UIKit
import CoreImage
import Vision
import React

@objc(ProcessingModule)
class ProcessingModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func applyPortraitEffect(_ imagePath: NSString,
                             resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
        print("applyPortraitEffect called with:", imagePath)

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String
                print("applyPortraitEffect path:", path)

                guard let inputImage = UIImage(contentsOfFile: path) else {
                    reject("PORTRAIT_EFFECT_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                guard let ciImage = CIImage(image: inputImage) else {
                    reject("PORTRAIT_EFFECT_ERROR", "Could not create CIImage from input image", nil)
                    return
                }

                guard let maskImage = self.generatePersonMask(for: ciImage) else {
                    print("Mask failed, falling back to full-image blur")

                    let blurredBackground = ciImage
                        .clampedToExtent()
                        .applyingFilter("CIGaussianBlur", parameters: [
                            kCIInputRadiusKey: 18.0
                        ])
                        .cropped(to: ciImage.extent)

                    guard let outputCG = self.ciContext.createCGImage(blurredBackground, from: blurredBackground.extent) else {
                        reject("PORTRAIT_EFFECT_ERROR", "Fallback blur rendering failed", nil)
                        return
                    }

                    let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                    guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "portrait_fallback") else {
                        reject("PORTRAIT_EFFECT_ERROR", "Could not save fallback portrait output", nil)
                        return
                    }

                    resolve(savedPath)
                    return
                }

                let blurredBackground = ciImage
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [
                        kCIInputRadiusKey: 18.0
                    ])
                    .cropped(to: ciImage.extent)

                guard let composited = self.composite(foreground: ciImage,
                                                      background: blurredBackground,
                                                      mask: maskImage) else {
                    reject("PORTRAIT_EFFECT_ERROR", "Failed to composite portrait image", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(composited, from: composited.extent) else {
                    reject("PORTRAIT_EFFECT_ERROR", "Could not render final portrait image", nil)
                    return
                }

                    let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "portrait_effect") else {
                    reject("PORTRAIT_EFFECT_ERROR", "Could not save portrait output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    @objc
    func applySharpnessRestore(_ imagePath: NSString,
                               resolver resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
        print("applySharpnessRestore path:", imagePath)

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let inputImage = UIImage(contentsOfFile: path),
                      let ciImage = CIImage(image: inputImage) else {
                    reject("SHARPNESS_RESTORE_ERROR", "Could not create CIImage from input image", nil)
                    return
                }

                let sharpened = ciImage.applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 1.0
                ])

                guard let outputCG = self.ciContext.createCGImage(sharpened, from: sharpened.extent) else {
                    reject("SHARPNESS_RESTORE_ERROR", "Could not render sharpened image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "restored") else {
                    reject("SHARPNESS_RESTORE_ERROR", "Could not save sharpened image", nil)
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
            print("Segmentation request failed:", error)
            return nil
        }

        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            print("No mask pixel buffer returned")
            return nil
        }

        var mask = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Scale the mask to match the source image
        let xScale = ciImage.extent.width / mask.extent.width
        let yScale = ciImage.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
            .cropped(to: ciImage.extent)

        // Clean up the mask a bit
        mask = mask
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.0,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 1.5
            ])
            .cropped(to: ciImage.extent)

        // If the result looks inverted, uncomment this:
        // mask = mask.applyingFilter("CIColorInvert")

        print("Mask extent:", mask.extent)
        return mask
    }

    private func composite(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage? {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            print("Could not create CIBlendWithMask filter")
            return nil
        }

        blendFilter.setValue(foreground, forKey: kCIInputImageKey)
        blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        guard let output = blendFilter.outputImage?.cropped(to: foreground.extent) else {
            print("Blend filter returned nil")
            return nil
        }

        return output
    }

    private func saveToTemp(image: UIImage, prefix: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            print("Could not convert output image to JPEG")
            return nil
        }

        let filename = "\(prefix)_\(UUID().uuidString).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            print("Saved output to:", url.path)
            return url.path
        } catch {
            print("Save error:", error)
            return nil
        }
    }
}