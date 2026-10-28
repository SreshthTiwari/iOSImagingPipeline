import Foundation
import CoreImage
import React

@objc(BlurMetricsModule)
class BlurMetricsModule: NSObject {
    static func moduleName() -> String! {
        return "BlurMetricsModel"
    }

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func computeBlurScore(_ imagePath: String,
                          resolver resolve: @escaping RCTPromiseResolveBlock,
                          rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let score = self.blurScore(at: imagePath) else {
                    throw NSError(domain: "BlurMetricsModule",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Unable to compute blur score"])
                }

                DispatchQueue.main.async {
                    resolve(score)
                }
            } catch {
                DispatchQueue.main.async {
                    reject("BLUR_SCORE_ERROR", error.localizedDescription, error)
                }
            }
        }
    }

    private func blurScore(at imagePath: String) -> Double? {
        guard let image = ImagingIO.load(path: imagePath) else {
            return nil
        }
        return SharpnessMetric.laplacianVariance(of: image)
    }
}
