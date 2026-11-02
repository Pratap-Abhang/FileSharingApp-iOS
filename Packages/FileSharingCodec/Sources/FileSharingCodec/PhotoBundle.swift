import CryptoKit
import Foundation

/// One photo inside a bundle.
public struct BundleFile: Equatable {
    public let name: String
    public let mime: String
    public let data: [UInt8]

    public init(name: String, mime: String, data: [UInt8]) {
        self.name = name
        self.mime = mime
        self.data = data
    }
}

public enum BundleError: Error, Equatable {
    case tooShort
    case badMagic
    case hashMismatch
    case badManifest
}

/// Named PhotoBundle because Foundation already has a `Bundle` class.
/// Packs photos into one byte string and back (protocol/spec.md section 1):
/// `"FSB1"`, manifest length, manifest JSON, file bytes, SHA-256 of everything before it.
public enum PhotoBundle {
    private static let magic: [UInt8] = Array("FSB1".utf8)

    public static func pack(_ files: [BundleFile]) -> [UInt8] {
        let entries = files.map {
            "{\"name\":\(quote($0.name)),\"size\":\($0.data.count),\"mime\":\(quote($0.mime))}"
        }
        let manifest = Array("{\"v\":1,\"files\":[\(entries.joined(separator: ","))]}".utf8)

        var out = magic
        out += be32(UInt32(manifest.count))
        out += manifest
        for file in files { out += file.data }
        out += sha256(out)
        return out
    }

    /// Checks the hash and splits the bundle back into files. Throws if it is damaged.
    public static func unpack(_ bundle: [UInt8]) throws -> [BundleFile] {
        guard bundle.count >= 40 else { throw BundleError.tooShort }
        guard Array(bundle[0..<4]) == magic else { throw BundleError.badMagic }
        let body = Array(bundle[0..<(bundle.count - 32)])
        guard sha256(body) == Array(bundle[(bundle.count - 32)...]) else { throw BundleError.hashMismatch }

        let manifestLength = Int(read32(bundle, 4))
        guard 8 + manifestLength <= body.count else { throw BundleError.badManifest }
        let manifestData = Data(bundle[8..<(8 + manifestLength)])
        guard let root = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let entries = root["files"] as? [[String: Any]] else { throw BundleError.badManifest }

        var position = 8 + manifestLength
        var files = [BundleFile]()
        for entry in entries {
            guard let name = entry["name"] as? String,
                  let mime = entry["mime"] as? String,
                  let size = (entry["size"] as? NSNumber)?.intValue,
                  size >= 0, position + size <= body.count else { throw BundleError.badManifest }
            files.append(BundleFile(name: name, mime: mime, data: Array(bundle[position..<(position + size)])))
            position += size
        }
        return files
    }

    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(bytes)))
    }

    /// Minimal JSON string escaping, written by hand so key order and spacing stay fixed.
    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
