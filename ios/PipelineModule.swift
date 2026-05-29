import Foundation
import UIKit
import CoreImage
import React

@objc(PipelineModule)
class PipelineModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func runFullPipeline(_ imagePath: NSString,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let originalImage = UIImage(contentsOfFile: path),
                      let originalCG = originalImage.cgImage else {
                    reject("PIPELINE_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                let inputCI = CIImage(cgImage: originalCG)

                // Step 1: tone mapping
                guard let toneMapped = self.applyToneMapping(input: inputCI),
                      let toneMappedCG = self.ciContext.createCGImage(toneMapped, from: toneMapped.extent),
                      let toneMappedUIImage = UIImage(cgImage: toneMappedCG),
                      let toneMappedPath = self.saveToTemp(image: toneMappedUIImage, prefix: "pipeline_tonemapped") else {
                    reject("PIPELINE_ERROR", "Tone mapping step failed", nil)
                    return
                }

                // Step 2: scene enhancement
                guard let sceneEnhanced = self.applySceneEnhancement(path: toneMappedPath),
                      let sceneEnhancedCG = self.ciContext.createCGImage(sceneEnhanced, from: sceneEnhanced.extent),
                      let sceneEnhancedUIImage = UIImage(cgImage: sceneEnhancedCG),
                      let sceneEnhancedPath = self.saveToTemp(image: sceneEnhancedUIImage, prefix: "pipeline_sceneenhanced") else {
                    reject("PIPELINE_ERROR", "Scene enhancement step failed", nil)
                    return
                }

                // Step 3: sharpening restoration
                guard let sharpened = self.applySharpen(path: sceneEnhancedPath),
                      let sharpenedCG = self.ciContext.createCGImage(sharpened, from: sharpened.extent),
                      let sharpenedUIImage = UIImage(cgImage: sharpenedCG),
                      let sharpenedPath = self.saveToTemp(image: sharpenedUIImage, prefix: "pipeline_sharpened") else {
                    reject("PIPELINE_ERROR", "Sharpening step failed", nil)
                    return
                }

                // Step 4: bokeh effect
                guard let bokeh = self.applyBokeh(path: sharpenedPath),
                      let bokehCG = self.ciContext.createCGImage(bokeh, from: bokeh.extent),
                      let bokehUIImage = UIImage(cgImage: bokehCG),
                      let bokehPath = self.saveToTemp(image: bokehUIImage, prefix: "pipeline_bokeh") else {
                    reject("PIPELINE_ERROR", "Bokeh step failed", nil)
                    return
                }

                resolve(bokehPath)
            }
        }
    }

    private func applyToneMapping(input: CIImage) -> CIImage? {
        guard let exposure = CIFilter(name: "CIExposureAdjust"),
              let contrast = CIFilter(name: "CIColorControls"),
              let highlightShadow = CIFilter(name: "CIHighlightShadowAdjust") else {
            return nil
        }

        exposure.setValue(input, forKey: kCIInputImageKey)
        exposure.setValue(0.15, forKey: kCIInputEVKey)

        guard let exposed = exposure.outputImage else { return nil }

        highlightShadow.setValue(exposed, forKey: kCIInputImageKey)
        highlightShadow.setValue(0.25, forKey: "inputShadowAmount")
        highlightShadow.setValue(0.15, forKey: "inputHighlightAmount")

        guard let adjusted = highlightShadow.outputImage else { return nil }

        contrast.setValue(adjusted, forKey: kCIInputImageKey)
        contrast.setValue(1.08, forKey: kCIInputContrastKey)
        contrast.setValue(1.02, forKey: kCIInputSaturationKey)
        contrast.setValue(0.0, forKey: kCIInputBrightnessKey)

        return contrast.outputImage
    }

    private func applySceneEnhancement(path: String) -> CIImage? {
        guard let image = UIImage(contentsOfFile: path),
              let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        guard let exposure = CIFilter(name: "CIExposureAdjust"),
              let vibrance = CIFilter(name: "CIVibrance"),
              let contrast = CIFilter(name: "CIColorControls") else {
            return nil
        }

        exposure.setValue(ciImage, forKey: kCIInputImageKey)
        exposure.setValue(0.2, forKey: kCIInputEVKey)

        guard let exposed = exposure.outputImage else { return nil }

        vibrance.setValue(exposed, forKey: kCIInputImageKey)
        vibrance.setValue(0.3, forKey: "inputAmount")

        guard let vib = vibrance.outputImage else { return nil }

        contrast.setValue(vib, forKey: kCIInputImageKey)
        contrast.setValue(1.1, forKey: kCIInputContrastKey)
        contrast.setValue(1.04, forKey: kCIInputSaturationKey)
        contrast.setValue(0.0, forKey: kCIInputBrightnessKey)

        return contrast.outputImage
    }

    private func applySharpen(path: String) -> CIImage? {
        guard let image = UIImage(contentsOfFile: path),
              let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        guard let sharpen = CIFilter(name: "CISharpenLuminance") else {
            return nil
        }

        sharpen.setValue(ciImage, forKey: kCIInputImageKey)
        sharpen.setValue(1.0, forKey: kCIInputSharpnessKey)

        return sharpen.outputImage
    }

    private func applyBokeh(path: String) -> CIImage? {
        guard let image = UIImage(contentsOfFile: path),
              let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        guard let request = try? VNGeneratePersonSegmentationRequest() else {
            return nil
        }

        request.qualityLevel = .accurate
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

        var mask = CIImage(cvPixelBuffer: maskPixelBuffer)

        let xScale = ciImage.extent.width / mask.extent.width
        let yScale = ciImage.extent.height / mask.extent.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: xScale, y: yScale))
            .cropped(to: ciImage.extent)

        mask = mask
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.0,
                kCIInputSaturationKey: 0.0,
                kCIInputBrightnessKey: 0.0
            ])
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 1.0
            ])
            .cropped(to: ciImage.extent)

        let blurredBackground = ciImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 20.0
            ])
            .cropped(to: ciImage.extent)

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            return nil
        }

        blend.setValue(ciImage, forKey: kCIInputImageKey)
        blend.setValue(blurredBackground, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)

        return blend.outputImage?.cropped(to: ciImage.extent)
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
            return nil
        }
    }
}