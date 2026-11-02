import Foundation

/// Peeling decoder for the fountain stream.
///
/// Feed it scanned QR strings with `addText`. When `isDone` is true, `result()` returns the bundle.
/// A frame from a different session (the sender started a new batch) resets it.
/// Not thread-safe: call it from one queue only.
public final class FountainDecoder {
    /// A stored packet that still mixes more than one unknown block.
    private struct Pending {
        var indices: Set<Int>
        var data: [UInt8]
    }

    public private(set) var blockCount = 0
    public private(set) var knownBlocks = 0

    private var session: UInt32?
    private var length: UInt32 = 0
    private var blockSize = 0
    private var blocks: [[UInt8]?] = []
    private var pending: [Pending] = []
    private var seen = Set<UInt32>()

    public init() {}

    public var isDone: Bool { blockCount > 0 && knownBlocks == blockCount }

    /// Share of blocks recovered, 0 to 1.
    public var progress: Double { blockCount == 0 ? 0 : Double(knownBlocks) / Double(blockCount) }

    /// Returns true if `text` was a valid frame (even a repeat), false if it was foreign or damaged.
    @discardableResult
    public func addText(_ text: String) -> Bool {
        guard let frame = Frame.parse(text: text) else { return false }
        add(frame)
        return true
    }

    public func add(_ frame: Frame) {
        if session != frame.session || length != frame.bundleLength || blockSize != frame.blockSize {
            reset(for: frame)
        }
        if isDone || !seen.insert(frame.esi).inserted { return }
        let indices = Fountain.decoderIndices(
            esi: frame.esi, session: frame.session, n: blockCount, degree: frame.degree
        )
        addPacket(Set(indices), frame.payload)
    }

    /// The rebuilt bundle bytes. Only valid when `isDone`.
    public func result() -> [UInt8] {
        precondition(isDone, "decoder is not finished")
        var out = [UInt8]()
        out.reserveCapacity(blockCount * blockSize)
        for block in blocks { out += block! }
        return Array(out.prefix(Int(length)))
    }

    private func reset(for frame: Frame) {
        session = frame.session
        length = frame.bundleLength
        blockSize = frame.blockSize
        blockCount = max(1, (Int(length) + blockSize - 1) / blockSize)
        blocks = [[UInt8]?](repeating: nil, count: blockCount)
        knownBlocks = 0
        pending = []
        seen = []
    }

    /// Removes already-known blocks from the packet, then either stores it or, if exactly one
    /// unknown block is left, recovers that block and propagates the result through stored packets.
    private func addPacket(_ packetIndices: Set<Int>, _ payload: [UInt8]) {
        var indices = packetIndices
        var data = payload
        for i in packetIndices {
            if let known = blocks[i] {
                xor(&data, known)
                indices.remove(i)
            }
        }
        if indices.isEmpty { return }
        if indices.count > 1 {
            pending.append(Pending(indices: indices, data: data))
            return
        }

        var queue: [(Int, [UInt8])] = [(indices.first!, data)]
        while let (index, block) = queue.popLast() {
            if blocks[index] != nil { continue }
            blocks[index] = block
            knownBlocks += 1
            var stillPending = [Pending]()
            for var packet in pending {
                if packet.indices.remove(index) != nil { xor(&packet.data, block) }
                switch packet.indices.count {
                case 0: break // fully explained, nothing new
                case 1: queue.append((packet.indices.first!, packet.data))
                default: stillPending.append(packet)
                }
            }
            pending = stillPending
        }
    }

    private func xor(_ a: inout [UInt8], _ b: [UInt8]) {
        for j in 0..<a.count { a[j] ^= b[j] }
    }
}
