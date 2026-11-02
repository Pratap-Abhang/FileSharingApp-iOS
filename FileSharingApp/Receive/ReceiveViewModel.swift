import FileSharingCodec
import Foundation

/// Collects scanned QR text into a `FountainDecoder` and saves the photos when it finishes.
///
/// The camera delivers codes on its own queue and `FountainDecoder` is not thread-safe, so all
/// decoder work happens on one serial queue. Published properties are only touched on the main queue.
final class ReceiveViewModel: ObservableObject {
    enum State: Equatable {
        case scanning
        case saving
        case done(photoCount: Int)
        case failed(String)
    }

    @Published private(set) var state: State = .scanning
    /// Share of the photo data collected so far, 0 to 1.
    @Published private(set) var progress: Double = 0
    /// Number of valid frames received, to show the user that scanning works.
    @Published private(set) var framesSeen = 0

    private let decodeQueue = DispatchQueue(label: "FileSharingApp.decode")
    // The three below belong to `decodeQueue`.
    private var decoder = FountainDecoder()
    private var lastText: String?
    private var finished = false

    /// Called by the camera for every QR code it reads, up to about 30 times a second.
    /// Safe to call from any thread.
    func onQRText(_ text: String) {
        decodeQueue.async { self.process(text) }
    }

    /// Discards everything collected so far and returns to scanning.
    func reset() {
        decodeQueue.async {
            self.decoder = FountainDecoder()
            self.lastText = nil
            self.finished = false
            DispatchQueue.main.async {
                self.progress = 0
                self.framesSeen = 0
                self.state = .scanning
            }
        }
    }

    // MARK: on decodeQueue

    private func process(_ text: String) {
        guard !finished else { return }
        // The sender's frame stays on screen for several camera frames; skip exact repeats cheaply.
        guard text != lastText else { return }
        lastText = text
        // Not ours, or damaged: ignore it. The fountain code makes up for lost frames.
        guard decoder.addText(text) else { return }

        let progress = decoder.progress
        DispatchQueue.main.async {
            self.progress = progress
            self.framesSeen += 1
        }
        if decoder.isDone {
            finished = true
            finish(bundle: decoder.result())
        }
    }

    /// Unpacks the finished bundle (which checks its SHA-256) and saves the photos.
    private func finish(bundle: [UInt8]) {
        DispatchQueue.main.async { self.state = .saving }
        let files: [BundleFile]
        do {
            files = try PhotoBundle.unpack(bundle)
        } catch {
            publish(.failed("The photos arrived damaged. Please try again."))
            return
        }
        Task {
            do {
                let count = try await PhotoSaver.save(files)
                publish(.done(photoCount: count))
            } catch {
                publish(.failed(error.localizedDescription))
            }
        }
    }

    private func publish(_ newState: State) {
        DispatchQueue.main.async { self.state = newState }
    }
}
