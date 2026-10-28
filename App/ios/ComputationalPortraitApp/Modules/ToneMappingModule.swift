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

                guard let ciImage = CIImage(image: inputImage) else {
                    reject("TONE_MAP_ERROR", "Could not create CIImage from input image", nil)
                    return
                }

                guard let output = self.processToneMapping(input: ciImage) else {
                    reject("TONE_MAP_ERROR", "Tone mapping failed", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(output, from: output.extent) else {
                    reject("TONE_MAP_ERROR", "Could not render tone mapped image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "tone_mapped") else {
                    reject("TONE_MAP_ERROR", "Could not save tone mapped output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func processToneMapping(input: CIImage) -> CIImage? {
        return ImagingStages.toneMap(input)
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