import Foundation
import UIKit
import CoreImage
import React

@objc(ToneMappingModule)
class ToneMappingModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func applyToneMapping(_ imagePath: NSString,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let inputImage = UIImage(contentsOfFile: path) else {
                    reject("TONE_MAP_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                guard let cgImage = inputImage.cgImage else {
                    reject("TONE_MAP_ERROR", "Image does not contain a CGImage", nil)
                    return
                }

                let ciImage = CIImage(cgImage: cgImage)

                guard let output = self.processToneMapping(input: ciImage) else {
                    reject("TONE_MAP_ERROR", "Tone mapping failed", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(output, from: output.extent) else {
                    reject("TONE_MAP_ERROR", "Could not render tone mapped image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "tone_mapped") else {
                    reject("TONE_MAP_ERROR", "Could not save tone mapped output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func processToneMapping(input: CIImage) -> CIImage? {
        guard let exposure = CIFilter(name: "CIExposureAdjust"),
              let contrast = CIFilter(name: "CIColorControls"),
              let highlightShadows = CIFilter(name: "CIHighlightShadowAdjust") else {
            return nil
        }

        exposure.setValue(input, forKey: kCIInputImageKey)
        exposure.setValue(0.15, forKey: kCIInputEVKey)

        guard let exposed = exposure.outputImage else {
            return nil
        }

        highlightShadows.setValue(exposed, forKey: kCIInputImageKey)
        highlightShadows.setValue(0.25, forKey: "inputShadowAmount")
        highlightShadows.setValue(0.15, forKey: "inputHighlightAmount")

        guard let shadowAdjusted = highlightShadows.outputImage else {
            return nil
        }

        contrast.setValue(shadowAdjusted, forKey: kCIInputImageKey)
        contrast.setValue(1.08, forKey: kCIInputContrastKey)
        contrast.setValue(1.02, forKey: kCIInputSaturationKey)
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