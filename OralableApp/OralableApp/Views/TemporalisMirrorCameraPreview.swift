//
//  TemporalisMirrorCameraPreview.swift
//  OralableApp
//
//  Front-camera preview for Temporalis Fit Guide (Face ID–style mirror).
//

import AVFoundation
import SwiftUI

final class FrontMirrorCaptureSession: NSObject, ObservableObject {
    let session = AVCaptureSession()

    override init() {
        super.init()
        configure()
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

final class PreviewHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct FrontMirrorCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHostView {
        let host = PreviewHostView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.isVideoMirrored = true
        host.layer.insertSublayer(layer, at: 0)
        host.previewLayer = layer
        return host
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}
}
