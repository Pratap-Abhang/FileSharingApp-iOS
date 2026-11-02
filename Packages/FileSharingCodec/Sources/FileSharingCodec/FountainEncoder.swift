import Foundation

/// Turns a bundle into an endless stream of frames. Ask for `frame(esi: 0)`, `frame(esi: 1)`, ...
public final class FountainEncoder {
    public static let defaultBlockSize = 1000

    public let session: UInt32
    public let blockSize: Int
    public let blockCount: Int
    private let bundle: [UInt8]
    private let cdf: [Double]

    public init(bundle: [UInt8], session: UInt32, blockSize: Int = FountainEncoder.defaultBlockSize) {
        precondition(blockSize > 0 && blockSize <= Int(UInt16.max), "block size must fit in 16 bits")
        self.bundle = bundle
        self.session = session
        self.blockSize = blockSize
        self.blockCount = max(1, (bundle.count + blockSize - 1) / blockSize)
        self.cdf = Fountain.solitonCDF(n: blockCount)
    }

    /// The block numbers XORed together in packet `esi`.
    public func indices(esi: UInt32) -> [Int] {
        Fountain.encoderIndices(esi: esi, session: session, n: blockCount, cdf: cdf)
    }

    /// Builds packet `esi`. The last source block is zero-padded to the block size.
    public func frame(esi: UInt32) -> Frame {
        let chosen = indices(esi: esi)
        var payload = [UInt8](repeating: 0, count: blockSize)
        for block in chosen {
            let start = block * blockSize
            let end = min(start + blockSize, bundle.count)
            for j in start..<end {
                payload[j - start] ^= bundle[j]
            }
        }
        return Frame(
            session: session,
            bundleLength: UInt32(bundle.count),
            blockSize: blockSize,
            esi: esi,
            degree: chosen.count,
            payload: payload
        )
    }
}
