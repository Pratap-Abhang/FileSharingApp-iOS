import SwiftUI

/// Send flow: pick photos, wait while they are packed, then show the looping QR codes.
/// While the codes are on screen the display stays awake at full brightness, because a dim or
/// sleeping screen is the most common reason a scan fails.
struct SendView: View {
    @StateObject private var model = SendViewModel()
    @State private var showPicker = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                VStack(spacing: 16) {
                    Text("Send photos").font(.title.bold())
                    Text("Pick up to \(SendViewModel.maxPhotos) photos. They are shrunk first, so each one takes about 10 to 20 seconds to send.")
                        .multilineTextAlignment(.center)
                    Button("Choose photos") { showPicker = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)

            case let .preparing(done, total):
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing photo \(done + 1) of \(total)")
                }

            case let .failed(message):
                VStack(spacing: 16) {
                    Text(message).multilineTextAlignment(.center)
                    Button("Try again") { model.reset() }.buttonStyle(.borderedProminent)
                }
                .padding(24)

            case let .streaming(info):
                streaming(info)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPicker) {
            PhotoPicker(selectionLimit: SendViewModel.maxPhotos) { model.start($0) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            model.reset()
            keepAwake(false)
        }
    }

    private func streaming(_ info: SendViewModel.StreamInfo) -> some View {
        VStack(spacing: 8) {
            Text("\(info.photoCount) photo(s), about \(info.estimatedSeconds) s. Point the other phone's camera at this screen.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
            if let image = model.frameImage {
                // .interpolation(.none) keeps module edges sharp when the 1 px/module image is scaled up.
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("QR code carrying the photos")
            } else {
                ProgressView()
            }
            Text("Speed: \(Int(model.fps)) frames/s").font(.footnote).foregroundColor(.black)
            Slider(value: $model.fps, in: SendViewModel.minFPS...SendViewModel.maxFPS, step: 1)
            Text("If the other phone struggles, slide left to slow down.")
                .font(.caption)
                .foregroundColor(.gray)
            Button("Stop") { model.reset() }
        }
        .padding(12)
        .background(Color.white.ignoresSafeArea())
        .onAppear { keepAwake(true) }
        .onDisappear { keepAwake(false) } // also runs when "Stop" leaves the streaming state
    }

    /// Full brightness and no auto-lock while codes are showing; restored afterwards.
    private func keepAwake(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
        if on {
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        } else {
            UIScreen.main.brightness = savedBrightness
        }
    }
}
