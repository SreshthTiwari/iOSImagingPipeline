import Foundation
import CoreImage
import React

@objc(MotionDeblurModule)
class MotionDeblurModule: NSObject {

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func estimateMotionBlur(_ imagePath: NSString,
                            resolver resolve: @escaping RCTPromiseResolveBlock,
                            rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let image = ImagingIO.load(path: path),
                      let score = SharpnessMetric.laplacianVariance(of: image) else {
                    reject("MOTION_BLUR_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                resolve([
                    "blurScore": score,
                    "isBlurry": SharpnessMetric.isBlurry(score)
                ])
            }
        }
    }

    /// Estimates a linear motion-blur kernel and inverts it with a Wiener filter. Resolves
    /// with `applied: false` and the original path when the image looks sharp, is too noisy,
    /// or the kernel estimate is not trustworthy (see `BlurDeconvolution` for the rules).
    @objc
    func removeMotionBlur(_ imagePath: NSString,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let image = ImagingIO.load(path: path) else {
                    reject("MOTION_BLUR_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                let start = CFAbsoluteTimeGetCurrent()

                guard let result = BlurDeconvolution.deblur(image) else {
                    reject("MOTION_BLUR_ERROR", "Could not process image at path: \(path)", nil)
                    return
                }

                guard let kernel = result.kernel else {
                    resolve(["applied": false, "path": path])
                    return
                }

                do {
                    let outputPath = try ImagingIO.writeJPEG(result.image, prefix: "motion_deblur")
                    NSLog("[MotionDeblurModule] deblur: %.0f ms, %.1f px at %.1f deg",
                          (CFAbsoluteTimeGetCurrent() - start) * 1000, kernel.length, kernel.angleDegrees)
                    resolve([
                        "applied": true,
                        "path": outputPath,
                        "angleDegrees": kernel.angleDegrees,
                        "lengthPixels": kernel.length
                    ])
                } catch {
                    reject("MOTION_BLUR_ERROR", "Could not save deblurred image", error)
                }
            }
        }
    }
}
