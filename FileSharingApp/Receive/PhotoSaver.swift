import FileSharingCodec
import Photos
import UIKit

/// Saves received photos to the user's photo library.
enum PhotoSaver {
    enum SaveError: LocalizedError {
        case denied

        var errorDescription: String? {
            "Photos could not be saved because access to the photo library was denied. You can allow it in Settings."
        }
    }

    /// Saves every file in one library change, so either all of them appear or none do.
    /// Returns the number saved.
    static func save(_ files: [BundleFile]) async throws -> Int {
        // .addOnly asks only for permission to add photos, not to read the library.
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }

        try await PHPhotoLibrary.shared().performChanges {
            for file in files {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: libraryData(for: file), options: nil)
            }
        }
        return files.count
    }

    /// The Photos library does not reliably import WebP (what Android sends), so convert it
    /// to high-quality JPEG first. JPEG, PNG and HEIC are saved untouched.
    private static func libraryData(for file: BundleFile) -> Data {
        let original = Data(file.data)
        guard file.mime == "image/webp",
              let image = UIImage(data: original),
              let jpeg = image.jpegData(compressionQuality: 0.95) else { return original }
        return jpeg
    }
}
