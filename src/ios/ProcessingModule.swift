import Foundation
import UIKit
import CoreImage
import Vision
import React

@objc(ProcessingModule)
class ProcessingModule: NSObject {

    private let ciContext = CIContext(options: nil)

    @objc
    func applyPortraitEffect(_ imagePath: String,
                             resolver resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let inputImage = UIImage(contentsOfFile: imagePath),
              let cgImage = inputImage.cgImage else {
            reject("IMAGE_LOAD_ERROR", "Could not load input image", nil)
            return
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Basic blur effect placeholder:
        // In the final version, this should use Vision person segmentation
        // and composite the blurred background behind the subject.
        let blurred = ciImage.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 15.0
            ])
            .cropped(to: ciImage.extent)

        guard let outputCG = ciContext.createCGImage(blurred, from: blurred.extent) else {
            reject("PROCESS_ERROR", "Could not create blurred image", nil)
            return
        }

        let outputUIImage = UIImage(cgImage: outputCG)

        guard let savedPath = saveToTemp(image: outputUIImage, filename: "portrait_effect.jpg") else {
            reject("SAVE_ERROR", "Could not save processed image", nil)
            return
        }

        resolve(savedPath)
    }

    @objc
    func applySharpnessRestore(_ imagePath: String,
                               resolver resolve: @escaping RCTPromiseResolveBlock,
                               rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let inputImage = UIImage(contentsOfFile: imagePath),
              let cgImage = inputImage.cgImage else {
            reject("IMAGE_LOAD_ERROR", "Could not load input image", nil)
            return
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Simple sharpening baseline
        let sharpened = ciImage.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: 0.8
        ])

        guard let outputCG = ciContext.createCGImage(sharpened, from: sharpened.extent) else {
            reject("PROCESS_ERROR", "Could not create sharpened image", nil)
            return
        }

        let outputUIImage = UIImage(cgImage: outputCG)

        guard let savedPath = saveToTemp(image: outputUIImage, filename: "restored_image.jpg") else {
            reject("SAVE_ERROR", "Could not save restored image", nil)
            return
        }

        resolve(savedPath)
    }

    private func saveToTemp(image: UIImage, filename: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }
}