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
    func applyPortraitEffect(_ imagePath: String,
                             resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let outputPath = self.portraitEffect(at: imagePath) else {
                    throw NSError(domain: "ProcessingModule",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to apply portrait effect"])
                }

                DispatchQueue.main.async {
                    resolve(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    reject("PORTRAIT_EFFECT_ERROR", error.localizedDescription, error)
                }
            }
        }
    }

    @objc
    func applySharpnessRestore(_ imagePath: String,
                               resolver resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let outputPath = self.sharpnessRestore(at: imagePath) else {
                    throw NSError(domain: "ProcessingModule",
                                  code: -2,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to apply sharpness restore"])
                }

                DispatchQueue.main.async {
                    resolve(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    reject("SHARPNESS_RESTORE_ERROR", error.localizedDescription, error)
                }
            }
        }
    }

    private func portraitEffect(at imagePath: String) -> String? {
        guard let inputImage = UIImage(contentsOfFile: imagePath),
              let cgImage = inputImage.cgImage else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        guard let mask = personMask(for: ciImage) else {
            return nil
        }

        let blurredBackground = ciImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 18.0
            ])
            .cropped(to: ciImage.extent)

        guard let composited = composite(foreground: ciImage, background: blurredBackground, mask: mask),
              let outputCG = ciContext.createCGImage(composited, from: composited.extent) else {
            return nil
        }

        let outputImage = UIImage(cgImage: outputCG)
        return NativeImageUtils.saveImageToTemp(outputImage, filename: "portrait_effect_\(UUID().uuidString).jpg")
    }

    private func sharpnessRestore(at imagePath: String) -> String? {
        guard let inputImage = UIImage(contentsOfFile: imagePath),
              let cgImage = inputImage.cgImage else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)

        let restored = ciImage
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 1.0
            ])

        guard let outputCG = ciContext.createCGImage(restored, from: restored.extent) else {
            return nil
        }

        let outputImage = UIImage(cgImage: outputCG)
        return NativeImageUtils.saveImageToTemp(outputImage, filename: "restored_\(UUID().uuidString).jpg")
    }

    private func personMask(for ciImage: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let maskPixelBuffer = request.results?.first?.pixelBuffer else {
            return nil
        }

        return CIImage(cvPixelBuffer: maskPixelBuffer)
    }

    private func composite(foreground: CIImage, background: CIImage, mask: CIImage) -> CIImage? {
        let scaledMask = mask
            .transformed(by: CGAffineTransform(scaleX: foreground.extent.width / mask.extent.width,
                                               y: foreground.extent.height / mask.extent.height))
            .cropped(to: foreground.extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }

        blend.setValue(background, forKey: kCIInputBackgroundImageKey)
        blend.setValue(foreground, forKey: kCIInputImageKey)
        blend.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        return blend.outputImage?.cropped(to: foreground.extent)
    }
}