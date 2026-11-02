import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Turns frame text into a QR image with a white quiet zone.
///
/// The image is one pixel per module; SwiftUI scales it up without smoothing (`.interpolation(.none)`)
/// so module edges stay sharp for the other phone's camera.
enum QRRenderer {
    /// The QR spec asks for a 4-module quiet zone around the code.
    private static let quietZone = 4
    private static let context = CIContext()

    /// Error correction is the lowest level, "L": it gives the most payload per code, and the
    /// fountain code already tolerates whole lost frames.
    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }

        let modules = cgImage.width
        let side = CGFloat(modules + 2 * quietZone)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // exactly one pixel per module
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage: cgImage).draw(in: CGRect(
                x: CGFloat(quietZone), y: CGFloat(quietZone),
                width: CGFloat(modules), height: CGFloat(modules)
            ))
        }
    }
}
