# Architecture (iOS)

## The big picture

```
SENDER                                                 RECEIVER
Pick photos -> Compress -> Bundle -> Fountain -> QR loop  ~~light~~>  Camera -> Collect -> Decode -> Verify -> Save
(PHPicker)    (ImageIO)  (PhotoBundle)(Encoder)  (CoreImage)           (AVCapture) (Decoder)  (Decoder) (SHA-256) (Photos)
```

The link between the phones is one-way: the receiver cannot ask the sender to repeat a frame. That
single fact explains most of the design. The reasoning behind the fountain code, the frame format and the
overhead numbers is the same on both platforms and is written up in
[the Android architecture doc](https://github.com/Pratap-Abhang/FileSharingApp-Android/blob/main/docs/ARCHITECTURE.md#why-a-fountain-code)
and, byte for byte, in [protocol/spec.md](../protocol/spec.md). This page covers what is specific to iOS.

## Modules

### `Packages/FileSharingCodec` (pure Swift, no UIKit)

| File | Responsibility |
| --- | --- |
| `Base45.swift` | RFC 9285 Base45; its output only uses QR alphanumeric characters |
| `Frame.swift` | One QR frame: header, payload, CRC-32; `parse` rejects anything damaged |
| `Fountain.swift` | xorshift32 PRNG, packet seeds, robust-soliton CDF, block index selection |
| `FountainEncoder.swift` | Bundle bytes to frame number `esi` |
| `FountainDecoder.swift` | Frames to bundle bytes; tracks progress; resets on a new session |
| `PhotoBundle.swift` | Photos + manifest + SHA-256 packed into one byte string, and back |

All 32-bit arithmetic uses Swift's wrapping operators (`&*`, `&+`) so results equal the spec's
"modulo 2^32" exactly. `PhotoBundle` is not called `Bundle` because Foundation already has a `Bundle`.

### `FileSharingApp/Send`

- `SendViewModel` (`@MainActor`): state machine (idle, preparing, streaming, failed) and the frame loop.
  Each frame is built, rendered to a QR image on a background task, then published; the loop sleeps only
  for what is left of the frame's time slot so the rate stays steady.
- `ImageCompressor`: uses ImageIO to decode straight to a thumbnail (never the full image, so memory
  stays low), applying EXIF rotation, then saves JPEG at quality 0.7. iOS has no WebP encoder, so the
  iPhone sends JPEG.
- `QRRenderer`: Core Image's QR generator with error correction "L", drawn at one pixel per module with
  a 4-module quiet zone. SwiftUI scales it with `.interpolation(.none)`.
- `PhotoPicker`: `PHPickerViewController`. It needs no photo-library permission.
- `SendView`: keeps the screen awake at full brightness while codes are showing, and restores brightness after.

### `FileSharingApp/Receive`

- `ScannerController` / `CameraScanner`: `AVCaptureSession` at 1080p with an `AVCaptureMetadataOutput`
  restricted to QR codes, so scanning uses the system detector and works offline. Continuous autofocus is on.
- `ReceiveViewModel`: funnels every scanned string through one serial queue into the (non-thread-safe)
  `FountainDecoder`, publishes progress to the main queue, and unpacks and saves when finished.
- `PhotoSaver`: asks for add-only Photos access and writes all photos in one library change. WebP from
  Android is converted to JPEG first, because Photos does not reliably import WebP.

## Choices worth knowing about

| Choice | Why |
| --- | --- |
| 700-byte blocks (Android uses 1000) | Core Image's QR generator may encode in byte mode, which makes a 1000-byte frame about 25% denser than on Android. The receiver reads the block size from each frame, so mixing sizes works. Raise `SendViewModel.blockSize` if the codes scan well on your devices |
| `AVCaptureMetadataOutput` instead of Vision | Less code, runs on the system's optimised detector, and gives the QR text directly |
| XcodeGen | A hand-edited `.xcodeproj` is unreadable in git; `project.yml` is short and reviewable |
| iOS 15 minimum | The picker is `PHPicker` (iOS 14+) and no iOS 16-only SwiftUI is used |
| No networking code | The app cannot leak data even by mistake |

## Known limits

- **Not yet built or run.** The Swift code was written on a machine with no Swift toolchain, so it has
  never been compiled. Run `swift test` first, then build the app in Xcode, and fix anything the compiler flags.
- Block size 700 and 10 frames per second are safe guesses, not measured values. Tune on real devices.
- Photos only; the picker is capped at 20.
- No pause or resume on the receiver; leaving the screen discards partial progress.
- No app icon yet.
- The sender sends JPEG at quality 0.7 with no option for original quality.

## Troubleshooting

| Symptom | Try |
| --- | --- |
| Receiver stuck near 0% | Move closer or farther until the whole code fits in view; remove glare; lower the sender's speed |
| Progress rises then stalls | Normal near the end; the last blocks need specific packets. Keep the camera steady |
| "Photos arrived damaged" | The final SHA-256 check failed; try again |
| Nothing saved | Settings > FileSharingApp > Photos: allow adding photos |
| `xcodegen: command not found` | `brew install xcodegen` |
| "Untrusted Developer" on the iPhone | Settings > General > VPN & Device Management > trust your certificate |
