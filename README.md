# FileSharingApp for iOS

Send photos to another phone **with nothing but a screen and a camera**. No Wi-Fi, Bluetooth,
NFC or internet. The sender's screen plays a looping stream of QR codes that carry the photos;
the receiver's camera reads them and rebuilds the photos.

This is the iPhone half of the project. The Android app lives in the
[FileSharingApp-Android](https://github.com/Pratap-Abhang/FileSharingApp-Android) repo. Both apps speak the same
protocol, so an iPhone can send to an Android phone and the other way round.

## How it works in 30 seconds

1. **Send**: pick photos. Each is shrunk to 1600 px and saved as JPEG (about 150 to 350 KB).
2. The photos and a small manifest are packed into one *bundle*.
3. The bundle is cut into 700-byte blocks. A **fountain code** turns the blocks into an endless
   stream of packets; each packet is one QR code. The screen shows about 10 per second.
4. **Receive**: the camera reads QR codes. Each valid packet brings the receiver closer to rebuilding
   the bundle. It does not matter which packets arrive, so it can start at any moment and miss frames.
5. When enough packets have arrived, the bundle is checked (SHA-256) and the photos are saved to
   your Photos library.

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the wire format in
[protocol/spec.md](protocol/spec.md).

## Requirements

- A Mac with Xcode 15 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). It creates the Xcode
  project from `project.yml`, so no generated project file is stored in git.
- An iPhone with iOS 15 or newer. The Simulator has no camera for receiving, so use real iPhones.
  To test with only one iPhone, pair it with an Android phone running the other app.

## Run on your iPhone

1. In Terminal:
   ```
   cd ios            # this folder
   xcodegen generate
   open FileSharingApp.xcodeproj
   ```
2. In Xcode choose the **FileSharingApp** target, open **Signing & Capabilities**, tick
   *Automatically manage signing* and pick your Team (your personal Apple ID works).
   If `com.pratap.FileSharingApp` is already taken, change the bundle identifier to something unique.
3. Plug in your iPhone, unlock it, and choose it as the run destination. Press **Run** (⌘R).
4. First launch only: on the iPhone open *Settings > General > VPN & Device Management*, trust your
   developer certificate. (iOS 16+ also needs *Settings > Privacy & Security > Developer Mode* turned on.)
5. On phone A tap **Send photos** and choose photos. On phone B tap **Receive photos** and point it at phone A.

## Run the tests

The codec is a Swift package, so its tests run on the Mac in seconds, with no iPhone or Simulator:

```
cd Packages/FileSharingCodec
swift test
```

The tests compare every byte the Swift code produces (Base45 text, bundles, QR frames, random
numbers) with `protocol/test-vectors/vectors.json`, which the Python reference implementation in
`protocol/tools/reference.py` generated. If a test fails, the Swift code and the spec disagree.

To regenerate the vectors after a protocol change:

```
python3 protocol/tools/reference.py
```

and copy the updated `protocol/` folder to the Android repo so both apps test against the same data.

## Project layout

```
ios/
  protocol/                  spec, Python reference, shared test vectors (same in the Android repo)
  Packages/FileSharingCodec/ pure Swift: Base45, frames, fountain encoder/decoder, bundle (tested)
  FileSharingApp/            the SwiftUI app
    Send/                    photo picker, compression, QR loop screen
    Receive/                 camera scanner, progress, saving to Photos
  project.yml                XcodeGen project description
  docs/                      architecture and troubleshooting
```

## Permissions

- **Camera**, used when receiving.
- **Add photos to the library**, used when saving received photos. The app never reads your library;
  sending uses the system photo picker, which gives access only to the photos you choose.

The app contains no networking code and requests no network, Bluetooth or local-network permission.

## Tips for a reliable transfer

- Turn the sender's brightness up (the app does this) and hold both phones still, 20 to 30 cm apart.
- Avoid glare on the sender's screen.
- If the receiver is struggling, slide the sender's speed slider down.
- Fewer photos per transfer means shorter waits; each photo takes about 10 to 20 seconds.

## Status

Version 0.1.0. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#known-limits) for what is not done yet.
