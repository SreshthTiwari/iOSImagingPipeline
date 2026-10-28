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

                guard let ciImage = CIImage(image: inputImage) else {
                    reject("SCENE_ENHANCE_ERROR", "Could not create CIImage from input image", nil)
                    return
                }

                guard let output = self.processSceneEnhancement(input: ciImage) else {
                    reject("SCENE_ENHANCE_ERROR", "Scene enhancement failed", nil)
                    return
                }

                guard let outputCG = self.ciContext.createCGImage(output, from: output.extent) else {
                    reject("SCENE_ENHANCE_ERROR", "Could not render scene enhanced image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "scene_enhanced") else {
                    reject("SCENE_ENHANCE_ERROR", "Could not save scene enhanced output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func processSceneEnhancement(input: CIImage) -> CIImage? {
        return ImagingStages.sceneEnhance(input)
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