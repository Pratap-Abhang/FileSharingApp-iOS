import FileSharingCodec
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Shrinks a photo so it is quick to send through the screen.
///
/// A 12 MP photo is several MB, which would take minutes as QR codes. Scaling the long edge to
/// `maxEdge` pixels and saving as JPEG gives roughly 150 to 350 KB. (iOS has no built-in WebP
/// encoder, so the iPhone sends JPEG; the Android app sends WebP. Both can read both.)
enum ImageCompressor {
    static let maxEdge: CGFloat = 1600
    static let quality: CGFloat = 0.7

    /// Loads the picked photo, shrinks it and returns it ready for the bundle, or `nil` if it
    /// cannot be read. The caller skips such photos rather than failing the whole batch.
    static func compress(_ provider: NSItemProvider) async -> BundleFile? {
        await withCheckedContinuation { continuation in
            // The file URL is only valid inside this callback, so all the work happens in here.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url, let jpeg = shrink(url) else {
                    continuation.resume(returning: nil)
                    return
                }
                let name = sanitize(provider.suggestedName ?? "photo") + ".jpg"
                continuation.resume(returning: BundleFile(name: name, mime: "image/jpeg", data: Array(jpeg)))
            }
        }
    }

    /// Decodes straight to a downscaled bitmap (never the full-size image) and applies the EXIF
    /// rotation, so memory stays low and the photo is the right way up.
    private static func shrink(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        // Never upscale a photo that is already small.
        let target = width > 0 ? min(maxEdge, CGFloat(max(width, height))) : maxEdge

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// Keeps names safe on any file system.
    private static func sanitize(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let cleaned = String(base.map { $0.isLetter || $0.isNumber || "._- ".contains($0) ? $0 : "_" }.prefix(60))
        return cleaned.isEmpty ? "photo" : cleaned
    }
}
