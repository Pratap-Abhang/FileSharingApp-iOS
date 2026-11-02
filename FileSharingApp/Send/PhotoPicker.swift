import PhotosUI
import SwiftUI

/// SwiftUI wrapper around the system photo picker (PHPicker). It needs no photo-library
/// permission because the user's choice itself grants access to just those photos.
struct PhotoPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPicked: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([PHPickerResult]) -> Void

        init(onPicked: @escaping ([PHPickerResult]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            onPicked(results) // empty when the user cancels
        }
    }
}
