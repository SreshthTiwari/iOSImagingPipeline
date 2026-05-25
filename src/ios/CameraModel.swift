import Foundation
import AVFoundation
import UIKit
import React

@objc(CameraModel)
class CameraModel: NSObject {

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var isRunning = false

    @objc
    func startCamera(_ resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
        sessionQueue.async {
            if self.isRunning {
                resolve("Camera already running")
                return
            }

            // Placeholder setup
            // In a real implementation you would:
            // 1. request permissions
            // 2. configure AVCaptureDevice
            // 3. add AVCaptureInput and AVCaptureOutput
            // 4. startRunning()

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo
            self.captureSession.commitConfiguration()

            self.captureSession.startRunning()
            self.isRunning = true

            DispatchQueue.main.async {
                resolve("Camera started")
            }
        }
    }

    @objc
    func stopCamera(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
        sessionQueue.async {
            if !self.isRunning {
                resolve("Camera already stopped")
                return
            }

            self.captureSession.stopRunning()
            self.isRunning = false

            DispatchQueue.main.async {
                resolve("Camera stopped")
            }
        }
    }

    @objc
    func captureFrame(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
        // later this will return a captured frame from AVCaptureOutput.
        // for now, return dummy result so the JS side has an API to call.

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("captured_frame_stub.jpg")

        if let placeholderImage = UIImage(systemName: "camera.fill"),
           let imageData = placeholderImage.jpegData(compressionQuality: 1.0) {
            do {
                try imageData.write(to: tempURL)
                resolve(tempURL.path)
            } catch {
                reject("CAPTURE_ERROR", "Could not write captured frame stub", error)
            }
        } else {
            reject("CAPTURE_ERROR", "Could not create placeholder image", nil)
        }
    }

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return true
    }
}