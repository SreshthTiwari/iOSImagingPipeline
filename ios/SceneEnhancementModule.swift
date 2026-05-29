import Foundation
import UIKit
import CoreImage
import React

@objc(SceneEnhancementModule)
class SceneEnhancementModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func applySceneEnhancement(_ imagePath: NSString,
                                resolver resolve: @escaping RCTPromiseResolveBlock,
                                rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let inputImage = UIImage(contentsOfFile: path) else {
                    reject("SCENE_ENHANCE_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                guard let cgImage = inputImage.cgImage else {
                    reject("SCENE_ENHANCE_ERROR", "Image does not contain a CGImage", nil)
                    return
                }

                let ciImage = CIImage(cgImage: cgImage)

                guard let output = self.processSceneEnhancement(input: ciImage) else {
                    reject("SCENE_ENHANCE_ERROR", "Scene enhancement failed", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(output, from: output.extent) else {
                    reject("SCENE_ENHANCE_ERROR", "Could not render scene enhanced image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "scene_enhanced") else {
                    reject("SCENE_ENHANCE_ERROR", "Could not save scene enhanced output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func processSceneEnhancement(input: CIImage) -> CIImage? {
        // Basic scene-dependent enhancement:
        // improve exposure slightly, increase contrast, and add mild saturation.
        guard let exposure = CIFilter(name: "CIExposureAdjust"),
              let contrast = CIFilter(name: "CIColorControls"),
              let vibrance = CIFilter(name: "CIVibrance") else {
            return nil
        }

        exposure.setValue(input, forKey: kCIInputImageKey)
        exposure.setValue(0.2, forKey: kCIInputEVKey)

        guard let exposed = exposure.outputImage else {
            return nil
        }

        vibrance.setValue(exposed, forKey: kCIInputImageKey)
        vibrance.setValue(0.3, forKey: "inputAmount")

        guard let vibranced = vibrance.outputImage else {
            return nil
        }

        contrast.setValue(vibranced, forKey: kCIInputImageKey)
        contrast.setValue(1.1, forKey: kCIInputContrastKey)
        contrast.setValue(1.04, forKey: kCIInputSaturationKey)
        contrast.setValue(0.0, forKey: kCIInputBrightnessKey)

        return contrast.outputImage
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