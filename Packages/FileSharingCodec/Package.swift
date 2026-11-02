// swift-tools-version:5.9
import PackageDescription

// Pure-Swift fountain codec shared by the app and its tests. It has no UIKit dependency, so
// `swift test` runs it on a Mac in seconds, without a simulator.
let package = Package(
    name: "FileSharingCodec",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "FileSharingCodec", targets: ["FileSharingCodec"]),
    ],
    targets: [
        .target(name: "FileSharingCodec"),
        .testTarget(name: "FileSharingCodecTests", dependencies: ["FileSharingCodec"]),
    ]
)
