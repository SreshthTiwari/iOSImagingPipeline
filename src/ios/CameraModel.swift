import Foundation
import AVFoundation
import UIKit
import React

@objc(CameraModel)
class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.computationalportrait.camera.session")

    private let photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((String?, Error?) -> Void)?

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var previewView: UIView?

    private var isConfigured = false

    @objc
    static func requiresMainQueueSetup() -> Bool {
        return true
    }

    @objc
    func startCamera(_ resolver: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
        sessionQueue.async {
            do {
                if !self.isConfigured {
                    try self.configureSession()
                    self.isConfigured = true
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                DispatchQueue.main.async {
                    resolver("Camera started")
                }
            } catch {
                DispatchQueue.main.async {
                    reject("CAMERA_START_ERROR", error.localizedDescription, error)
                }
            }
        }
    }

    @objc
    func stopCamera(_ resolver: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                resolver("Camera stopped")
            }
        }
    }

    @objc
    func captureFrame(_ resolver: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
        sessionQueue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async {
                    reject("CAMERA_NOT_RUNNING", "Camera session is not running", nil)
                }
                return
            }

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off

            self.photoCaptureCompletion = { filePath, error in
                DispatchQueue.main.async {
                    if let error = error {
                        reject("CAPTURE_ERROR", error.localizedDescription, error)
                        return
                    }

                    guard let filePath = filePath else {
                        reject("CAPTURE_ERROR", "No file path returned for captured photo", nil)
                        return
                    }

                    resolver(filePath)
                }
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    @objc
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        return previewLayer ?? AVCaptureVideoPreviewLayer(session: session)
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
        }

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else {
            throw NSError(domain: "CameraModel",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Back camera not available"])
        }

        let videoInput = try AVCaptureDeviceInput(device: backCamera)

        guard session.canAddInput(videoInput) else {
            throw NSError(domain: "CameraModel",
                          code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        session.addInput(videoInput)

        guard session.canAddOutput(photoOutput) else {
            throw NSError(domain: "CameraModel",
                          code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add photo output"])
        }
        session.addOutput(photoOutput)
        photoOutput.isHighResolutionCaptureEnabled = true

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            photoCaptureCompletion?(nil, error)
            photoCaptureCompletion = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            photoCaptureCompletion?(nil, NSError(domain: "CameraModel",
                                                 code: -4,
                                                 userInfo: [NSLocalizedDescriptionKey: "Unable to get JPEG data from photo"]))
            photoCaptureCompletion = nil
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("captured_\(UUID().uuidString).jpg")

        do {
            try data.write(to: tempURL, options: .atomic)
            photoCaptureCompletion?(tempURL.path, nil)
        } catch {
            photoCaptureCompletion?(nil, error)
        }

        photoCaptureCompletion = nil
    }
}