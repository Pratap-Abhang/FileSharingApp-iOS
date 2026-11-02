import AVFoundation
import SwiftUI

/// Owns the camera session and reads QR codes from it.
///
/// Uses `AVCaptureMetadataOutput`, which decodes QR codes with the system's built-in (and
/// hardware-assisted) detector and works offline. Every code read is handed to `onText`.
final class ScannerController: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "FileSharingApp.camera")
    private let metadataQueue = DispatchQueue(label: "FileSharingApp.metadata")
    private let onText: (String) -> Void
    private var configured = false // only touched on sessionQueue

    init(onText: @escaping (String) -> Void) {
        self.onText = onText
        super.init()
    }

    func start() {
        sessionQueue.async {
            if !self.configured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // A dense QR code needs real resolution to resolve each module.
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        output.metadataObjectTypes = [.qr] // must be set after the output joins the session

        // Keep refocusing: the other phone is hand-held and moves.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for object in metadataObjects {
            if let code = object as? AVMetadataMachineReadableCodeObject, let text = code.stringValue {
                onText(text)
            }
        }
    }
}

/// A view whose backing layer is the camera preview, so it resizes with the view automatically.
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// SwiftUI wrapper: shows the camera and starts/stops it with the view.
struct CameraScanner: UIViewRepresentable {
    let onText: (String) -> Void

    func makeCoordinator() -> ScannerController { ScannerController(onText: onText) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = context.coordinator.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ScannerController) {
        coordinator.stop()
    }
}
