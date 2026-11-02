import Foundation

/// CRC-32 (IEEE 802.3, the same as zlib's `crc32`), used to drop frames the camera misread.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// One QR frame, see protocol/spec.md section 4. All integers are big-endian.
public struct Frame {
    public let session: UInt32
    public let bundleLength: UInt32
    public let blockSize: Int
    public let esi: UInt32
    public let degree: Int
    public let payload: [UInt8]

    public static let headerSize = 20
    public static let version: UInt8 = 1

    public init(session: UInt32, bundleLength: UInt32, blockSize: Int, esi: UInt32, degree: Int, payload: [UInt8]) {
        self.session = session
        self.bundleLength = bundleLength
        self.blockSize = blockSize
        self.esi = esi
        self.degree = degree
        self.payload = payload
    }

    /// Serialises the frame, header and payload followed by the CRC-32 of everything before it.
    public func toBytes() -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(Frame.headerSize + blockSize + 4)
        out += [0x46, 0x51, Frame.version, 0] // "FQ", version, flags
        out += be32(session)
        out += be32(bundleLength)
        out += be16(UInt16(blockSize))
        out += be32(esi)
        out += be16(UInt16(degree))
        out += payload
        out += be32(CRC32.checksum(out[...]))
        return out
    }

    /// The text to put in the QR code.
    public func toText() -> String {
        Base45.encode(toBytes())
    }

    /// Returns `nil` for anything that is not a valid, undamaged v1 frame.
    public static func parse(bytes: [UInt8]) -> Frame? {
        guard bytes.count >= headerSize + 4,
              bytes[0] == 0x46, bytes[1] == 0x51, bytes[2] == version else { return nil }
        let blockSize = Int(read16(bytes, 12))
        guard blockSize > 0, bytes.count == headerSize + blockSize + 4 else { return nil }
        let expected = read32(bytes, headerSize + blockSize)
        guard CRC32.checksum(bytes[0..<(headerSize + blockSize)]) == expected else { return nil }
        return Frame(
            session: read32(bytes, 4),
            bundleLength: read32(bytes, 8),
            blockSize: blockSize,
            esi: read32(bytes, 14),
            degree: Int(read16(bytes, 18)),
            payload: Array(bytes[headerSize..<(headerSize + blockSize)])
        )
    }

    /// Decodes the QR text (Base45) and parses it.
    public static func parse(text: String) -> Frame? {
        Base45.decode(text).flatMap { parse(bytes: $0) }
    }
}

func be32(_ v: UInt32) -> [UInt8] {
    [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
}

func be16(_ v: UInt16) -> [UInt8] {
    [UInt8(v >> 8), UInt8(v & 0xFF)]
}

func read32(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
}

func read16(_ b: [UInt8], _ o: Int) -> UInt16 {
    UInt16(b[o]) << 8 | UInt16(b[o + 1])
}
