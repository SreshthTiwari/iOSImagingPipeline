import Foundation
import CoreImage
import React

@objc(PipelineModule)
class PipelineModule: NSObject {

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return false
    }

    /// Runs tone mapping, scene enhancement, sharpening and bokeh as a single Core
    /// Image graph and renders it once, straight to a JPEG.
    @objc
    func runFullPipeline(_ imagePath: NSString,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let path = imagePath as String

                guard let source = ImagingIO.load(path: path) else {
                    reject("PIPELINE_ERROR", "Could not load image at path: \(path)", nil)
                    return
                }

                let start = CFAbsoluteTimeGetCurrent()

                do {
                    let output = try ImagingStages.fullPipeline(source)
                    let outputPath = try ImagingIO.writeJPEG(output, prefix: "pipeline")

                    let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    NSLog("[PipelineModule] full pipeline: %.0f ms (%.1f MP)",
                          elapsedMs, source.extent.width * source.extent.height / 1_000_000)

                    resolve(outputPath)
                } catch {
                    reject("PIPELINE_ERROR", error.localizedDescription, error)
                }
            }
        }
    }
}
