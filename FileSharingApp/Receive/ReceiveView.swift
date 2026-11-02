import AVFoundation
import SwiftUI

/// Receive flow: ask for the camera, scan the sender's screen, show progress, save the photos.
struct ReceiveView: View {
    @StateObject private var model = ReceiveViewModel()
    @State private var cameraAllowed: Bool?

    var body: some View {
        Group {
            switch model.state {
            case .scanning:
                scanning
            case .saving:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Saving photos…")
                }
            case let .done(count):
                VStack(spacing: 16) {
                    Text("Received \(count) photo(s)").font(.title.bold())
                    Text("They are in your Photos library.")
                    Button("Receive more") { model.reset() }.buttonStyle(.borderedProminent)
                }
            case let .failed(message):
                VStack(spacing: 16) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try again") { model.reset() }.buttonStyle(.borderedProminent)
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .task { await requestCamera() }
    }

    @ViewBuilder
    private var scanning: some View {
        switch cameraAllowed {
        case .none:
            ProgressView()
        case .some(false):
            VStack(spacing: 16) {
                Text("The camera is needed to read the other phone's screen. Please allow it in Settings.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        case .some(true):
            ZStack(alignment: .bottom) {
                CameraScanner(onText: model.onQRText)
                    .ignoresSafeArea()
                VStack(spacing: 8) {
                    Text(model.framesSeen == 0
                         ? "Point the camera at the other phone's QR code and hold steady."
                         : "Receiving… \(Int(model.progress * 100))%")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                    ProgressView(value: model.progress)
                }
                .padding()
                .background(Color.black.opacity(0.55))
            }
        }
    }

    private func requestCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAllowed = true
        case .notDetermined:
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraAllowed = false
        }
    }
}
