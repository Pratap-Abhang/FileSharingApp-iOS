import XCTest
@testable import FileSharingCodec

/// Checks the Swift codec against protocol/test-vectors/vectors.json, which the Python reference
/// (protocol/tools/reference.py) generated. A failure means Swift and the spec disagree.
final class CodecTests: XCTestCase {
    private var vectors: [String: Any] = [:]

    override func setUpWithError() throws {
        // This file is <ios>/Packages/FileSharingCodec/Tests/FileSharingCodecTests/CodecTests.swift
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("protocol/test-vectors/vectors.json")
        let data = try Data(contentsOf: url)
        vectors = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: helpers

    private func hex(_ s: String) -> [UInt8] {
        var out = [UInt8]()
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            out.append(UInt8(s[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func detBytes(seed: UInt32, count: Int) -> [UInt8] {
        var rng = XorShift32(seed: seed)
        return (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    }

    private func array(_ key: String) -> [[String: Any]] { vectors[key] as! [[String: Any]] }

    // MARK: tests

    func testBase45() {
        for c in array("base45") {
            let bytes = hex(c["hex"] as! String)
            let text = c["text"] as! String
            XCTAssertEqual(Base45.encode(bytes), text)
            XCTAssertEqual(Base45.decode(text), bytes)
        }
        for bad in vectors["base45Invalid"] as! [String] {
            XCTAssertNil(Base45.decode(bad), bad)
        }
    }

    func testCRC32() {
        for c in array("crc32") {
            let bytes = hex(c["hex"] as! String)
            XCTAssertEqual(CRC32.checksum(bytes[...]), UInt32(truncating: c["crc"] as! NSNumber))
        }
    }

    func testPRNGSeedsAndSoliton() {
        var rng = XorShift32(seed: 1)
        let first5 = (vectors["xorshift32"] as! [String: Any])["first5"] as! [NSNumber]
        for expected in first5 { XCTAssertEqual(rng.next(), expected.uint32Value) }

        for c in array("packetSeed") {
            let esi = (c["esi"] as! NSNumber).uint32Value
            let session = (c["session"] as! NSNumber).uint32Value
            XCTAssertEqual(Fountain.packetSeed(esi: esi, session: session), (c["seed"] as! NSNumber).uint32Value)
        }

        let cdf = Fountain.solitonCDF(n: 20)
        for (i, expected) in (vectors["solitonCdfN20First5"] as! [NSNumber]).enumerated() {
            XCTAssertEqual(cdf[i], expected.doubleValue, accuracy: 1e-15)
        }
    }

    func testBundleMatchesReference() throws {
        let b = vectors["bundle"] as! [String: Any]
        let files = (b["files"] as! [[String: Any]]).map {
            BundleFile(
                name: $0["name"] as! String,
                mime: $0["mime"] as! String,
                data: detBytes(seed: ($0["dataSeed"] as! NSNumber).uint32Value, count: ($0["size"] as! NSNumber).intValue)
            )
        }
        let packed = PhotoBundle.pack(files)
        XCTAssertEqual(hex(packed), b["hex"] as! String)
        XCTAssertEqual(try PhotoBundle.unpack(packed), files)
    }

    func testFramesMatchReference() throws {
        let e = vectors["encoder"] as! [String: Any]
        let bundle = hex((vectors["bundle"] as! [String: Any])["hex"] as! String)
        let encoder = FountainEncoder(
            bundle: bundle,
            session: (e["session"] as! NSNumber).uint32Value,
            blockSize: (e["blockSize"] as! NSNumber).intValue
        )
        XCTAssertEqual(encoder.blockCount, (e["n"] as! NSNumber).intValue)
        for f in e["frames"] as! [[String: Any]] {
            let esi = (f["esi"] as! NSNumber).uint32Value
            XCTAssertEqual(encoder.indices(esi: esi), (f["indices"] as! [NSNumber]).map(\.intValue), "indices esi=\(esi)")
            let frame = encoder.frame(esi: esi)
            XCTAssertEqual(hex(frame.toBytes()), f["frameHex"] as! String, "frame esi=\(esi)")
            XCTAssertEqual(frame.toText(), f["base45"] as! String)
            let parsed = try XCTUnwrap(Frame.parse(text: f["base45"] as! String))
            XCTAssertEqual(parsed.degree, (f["degree"] as! NSNumber).intValue)
        }
    }

    func testCorruptFramesAreRejected() {
        let encoder = FountainEncoder(bundle: (0..<3000).map { UInt8($0 & 0xFF) }, session: 7, blockSize: 500)
        var bytes = encoder.frame(esi: 9).toBytes()
        bytes[30] ^= 1
        XCTAssertNil(Frame.parse(bytes: bytes))
        XCTAssertNil(Frame.parse(text: "not a frame"))
    }

    func testDecodesWithLossAndLateStart() throws {
        var rng = SystemRandomNumberGenerator()
        for size in [1, 999, 1000, 1001, 25_000, 200_000] {
            let photo = (0..<size).map { _ in UInt8.random(in: 0...255, using: &rng) }
            let bundle = PhotoBundle.pack([BundleFile(name: "x.bin", mime: "application/octet-stream", data: photo)])
            let encoder = FountainEncoder(bundle: bundle, session: UInt32.random(in: 0...UInt32.max, using: &rng))
            let decoder = FountainDecoder()
            var esi = UInt32.random(in: 0...UInt32(3 * encoder.blockCount), using: &rng)
            var used = 0
            while !decoder.isDone {
                if Double.random(in: 0..<1, using: &rng) < 0.3 { esi += 1; continue } // lost frame
                XCTAssertTrue(decoder.addText(encoder.frame(esi: esi).toText()))
                esi += 1
                used += 1
                XCTAssertLessThan(used, encoder.blockCount * 4 + 50, "decoder stalled at size \(size)")
                if used >= encoder.blockCount * 4 + 50 { return }
            }
            XCTAssertEqual(decoder.result(), bundle)
            XCTAssertEqual(try PhotoBundle.unpack(decoder.result()).first?.name, "x.bin")
        }
    }

    func testNewSessionResetsDecoder() {
        let a = FountainEncoder(bundle: [UInt8](repeating: 1, count: 5000), session: 1)
        let b = FountainEncoder(bundle: [UInt8](repeating: 2, count: 2500), session: 2)
        let decoder = FountainDecoder()
        decoder.add(a.frame(esi: 0))
        decoder.add(a.frame(esi: 1))
        for i in 0..<UInt32(b.blockCount) { decoder.add(b.frame(esi: i)) }
        XCTAssertTrue(decoder.isDone)
        XCTAssertEqual(decoder.result(), [UInt8](repeating: 2, count: 2500))
    }

    func testBundleDetectsCorruption() {
        var packed = PhotoBundle.pack([BundleFile(name: "a.jpg", mime: "image/jpeg", data: [1, 2, 3, 4])])
        packed[10] ^= 0xFF
        XCTAssertThrowsError(try PhotoBundle.unpack(packed)) { XCTAssertEqual($0 as? BundleError, .hashMismatch) }
    }
}
