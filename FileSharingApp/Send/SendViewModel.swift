import FileSharingCodec
import PhotosUI
import QuartzCore
import UIKit

/// Prepares the selected photos and runs the endless QR loop.
///
/// The loop never ends on its own: the receiver can start at any time and the fountain code means
/// any sufficiently large set of frames is enough. The user stops it by leaving the screen.
@MainActor
final class SendViewModel: ObservableObject {
    struct StreamInfo {
        let photoCount: Int
        let bundleBytes: Int
        let blockCount: Int
        /// Rough time for the receiver to collect enough frames.
        let estimatedSeconds: Int
    }

    enum State {
        case idle
        case preparing(done: Int, total: Int)
        case streaming(StreamInfo)
        case failed(String)
    }

    /// Photo payload bytes per QR frame.
    ///
    /// The Android app uses 1000. This is smaller because Core Image's QR generator may not use
    /// the compact alphanumeric mode, which would make 1000-byte frames too dense to scan. The
    /// receiver reads the block size from each frame, so the two apps still interoperate.
    /// Raise it (toward 1000) if on-device tests show the codes scan well.
    static let blockSize = 700

    static let minFPS = 4.0
    static let maxFPS = 15.0
    static let maxPhotos = 20

    @Published private(set) var state: State = .idle
    @Published private(set) var frameImage: UIImage?
    /// Frames per second; may be changed while streaming.
    @Published var fps: Double = 10

    private var task: Task<Void, Never>?

    /// Compresses the picked photos, packs them and starts looping QR frames.
    func start(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { return }
        task?.cancel()
        task = Task { await run(results) }
    }

    func reset() {
        task?.cancel()
        task = nil
        frameImage = nil
        state = .idle
    }

    private func run(_ results: [PHPickerResult]) async {
        var files = [BundleFile]()
        for (index, result) in results.enumerated() {
            state = .preparing(done: index, total: results.count)
            // A photo that cannot be read is skipped rather than failing the whole batch.
            if let file = await ImageCompressor.compress(result.itemProvider) { files.append(file) }
            if Task.isCancelled { return }
        }
        guard !files.isEmpty else {
            state = .failed("None of the selected photos could be read.")
            return
        }

        let bundle = PhotoBundle.pack(files)
        let encoder = FountainEncoder(bundle: bundle, session: UInt32.random(in: 0...UInt32.max), blockSize: Self.blockSize)
        // Receivers need roughly 25 to 30% more frames than blocks, so budget 1.3x.
        let seconds = Int(Double(encoder.blockCount) * 1.3 / fps) + 1
        state = .streaming(StreamInfo(
            photoCount: files.count, bundleBytes: bundle.count,
            blockCount: encoder.blockCount, estimatedSeconds: seconds
        ))

        var esi: UInt32 = 0
        while !Task.isCancelled {
            let started = CACurrentMediaTime()
            let text = encoder.frame(esi: esi).toText()
            // Render off the main thread so the UI stays responsive.
            let image = await Task.detached(priority: .userInitiated) { QRRenderer.render(text) }.value
            if Task.isCancelled { return }
            frameImage = image
            esi &+= 1
            // Sleep only for what is left of this frame's time slot so the rate stays steady.
            let remaining = 1.0 / fps - (CACurrentMediaTime() - started)
            try? await Task.sleep(nanoseconds: UInt64(max(remaining, 0.001) * 1_000_000_000))
        }
    }
}
