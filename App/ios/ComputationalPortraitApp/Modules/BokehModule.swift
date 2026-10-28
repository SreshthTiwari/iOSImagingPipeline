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

                guard let ciImage = CIImage(image: inputImage) else {
                    reject("BOKEH_ERROR", "Could not create CIImage from input image", nil)
                    return
                }

                guard let matte = self.generatePersonMask(for: ciImage) else {
                    reject("BOKEH_ERROR", "Could not generate person mask", nil)
                    return
                }

                guard matte.hasPerson else {
                    reject("BOKEH_NO_SUBJECT", "No person found in the image", nil)
                    return
                }

                let composited = ImagingStages.bokeh(ciImage, mask: matte.mask)

                guard let outputCG = self.ciContext.createCGImage(composited, from: composited.extent) else {
                    reject("BOKEH_ERROR", "Could not render composited image", nil)
                    return
                }

                let outputUIImage = UIImage(cgImage: outputCG, scale: inputImage.scale, orientation: inputImage.imageOrientation)

                guard let savedPath = self.saveToTemp(image: outputUIImage, prefix: "bokeh") else {
                    reject("BOKEH_ERROR", "Could not save bokeh output", nil)
                    return
                }

                resolve(savedPath)
            }
        }
    }

    private func generatePersonMask(for ciImage: CIImage) -> ImagingStages.PersonMatte? {
        do {
            return try ImagingStages.personMask(for: ciImage)
        } catch {
            print("Bokeh segmentation failed:", error)
            return nil
        }
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