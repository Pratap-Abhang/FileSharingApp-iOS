import Foundation

/// Base45 as defined in RFC 9285. The output only uses characters from the QR "alphanumeric"
/// set, and iOS scanners hand back QR content as text, so this is how binary frames travel.
public enum Base45 {
    private static let alphabet: [UInt8] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)

    private static let reverse: [UInt8: Int] = {
        var map = [UInt8: Int]()
        for (index, char) in alphabet.enumerated() { map[char] = index }
        return map
    }()

    /// Encodes every 2 bytes as 3 characters (and a trailing single byte as 2).
    public static func encode(_ data: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(data.count / 2 * 3 + 2)
        var i = 0
        while i + 1 < data.count {
            var n = Int(data[i]) * 256 + Int(data[i + 1])
            let c = n % 45
            n /= 45
            let d = n % 45
            let e = n / 45
            out.append(alphabet[c])
            out.append(alphabet[d])
            out.append(alphabet[e])
            i += 2
        }
        if data.count % 2 == 1 {
            let n = Int(data[data.count - 1])
            out.append(alphabet[n % 45])
            out.append(alphabet[n / 45])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Returns `nil` if `text` is not valid Base45 (bad character, bad length or out-of-range group).
    public static func decode(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        if chars.count % 3 == 1 { return nil }
        var values = [Int]()
        values.reserveCapacity(chars.count)
        for char in chars {
            guard let value = reverse[char] else { return nil }
            values.append(value)
        }
        var out = [UInt8]()
        out.reserveCapacity(values.count / 3 * 2 + 1)
        var i = 0
        while i < values.count {
            if values.count - i >= 3 {
                let n = values[i] + values[i + 1] * 45 + values[i + 2] * 2025
                if n > 0xFFFF { return nil }
                out.append(UInt8(n >> 8))
                out.append(UInt8(n & 0xFF))
                i += 3
            } else {
                let n = values[i] + values[i + 1] * 45
                if n > 0xFF { return nil }
                out.append(UInt8(n))
                i += 2
            }
        }
        return out
    }
}
