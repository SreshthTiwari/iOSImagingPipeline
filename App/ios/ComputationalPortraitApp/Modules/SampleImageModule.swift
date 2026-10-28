import Foundation
import React

@objc(SampleImageModule)
class SampleImageModule: NSObject {

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    @objc
    func getSampleImagePath(_ resolver: RCTPromiseResolveBlock,
                            rejecter reject: RCTPromiseRejectBlock) {
        guard let url = Bundle.main.url(forResource: "portrait", withExtension: "jpg") else {
            reject("SAMPLE_IMAGE_ERROR", "Could not find portrait.jpg in app bundle", nil)
            return
        }

        resolver(url.path)
    }
}