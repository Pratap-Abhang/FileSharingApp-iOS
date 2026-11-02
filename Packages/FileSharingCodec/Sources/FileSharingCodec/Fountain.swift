import Foundation

/// xorshift32 pseudo-random generator, see protocol/spec.md section 3.2.
/// The sender and receiver both run it from the same seed, so they agree on which blocks a
/// packet contains without the packet having to list them.
public struct XorShift32 {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    public mutating func next() -> UInt32 {
        // Swift's << on fixed-width integers silently drops the shifted-out bits, as the spec needs.
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }
}

/// Packet-to-block mapping for the fountain code (protocol/spec.md section 3).
public enum Fountain {
    /// Per-packet PRNG seed. `&*` and `&+` wrap around modulo 2^32, exactly like the spec.
    public static func packetSeed(esi: UInt32, session: UInt32) -> UInt32 {
        var s = esi &* 0x9E37_79B1 &+ session
        s ^= s >> 16
        return s == 0 ? 0x6D2B_79F5 : s
    }

    /// Robust soliton cumulative distribution; element `d - 1` is P(degree <= d).
    public static func solitonCDF(n: Int, c: Double = 0.1, delta: Double = 0.5) -> [Double] {
        if n == 1 { return [1.0] }
        var rho = [Double](repeating: 0, count: n + 1)
        rho[1] = 1.0 / Double(n)
        for d in 2...n { rho[d] = 1.0 / (Double(d) * Double(d - 1)) }

        let r = c * log(Double(n) / delta) * Double(n).squareRoot()
        let spike = min(max(Int((Double(n) / r).rounded(.down)), 1), n)
        var tau = [Double](repeating: 0, count: n + 1)
        if spike > 1 {
            for d in 1..<spike { tau[d] = r / (Double(d) * Double(n)) }
        }
        tau[spike] = max(0.0, r * log(r / delta) / Double(n))

        var total = 0.0
        for d in 1...n { total += rho[d] + tau[d] }
        var cdf = [Double](repeating: 0, count: n)
        var acc = 0.0
        for d in 1...n {
            acc += (rho[d] + tau[d]) / total
            cdf[d - 1] = acc
        }
        cdf[n - 1] = 1.0
        return cdf
    }

    /// Encoder side: picks the degree from `cdf`, then the block indices.
    public static func encoderIndices(esi: UInt32, session: UInt32, n: Int, cdf: [Double]) -> [Int] {
        if Int(esi) < n { return [Int(esi)] }
        var rng = XorShift32(seed: packetSeed(esi: esi, session: session))
        let u = Double(rng.next()) / 4_294_967_296.0
        var degree = n
        for d in 1...n where cdf[d - 1] >= u {
            degree = d
            break
        }
        return draw(&rng, degree: degree, n: n)
    }

    /// Decoder side: the degree is read from the frame header instead of being recomputed.
    public static func decoderIndices(esi: UInt32, session: UInt32, n: Int, degree: Int) -> [Int] {
        if Int(esi) < n { return [Int(esi)] }
        var rng = XorShift32(seed: packetSeed(esi: esi, session: session))
        _ = rng.next() // the degree draw; its value is not needed here
        return draw(&rng, degree: degree, n: n)
    }

    /// Draws `degree` distinct block indices.
    private static func draw(_ rng: inout XorShift32, degree: Int, n: Int) -> [Int] {
        var chosen = [Int]()
        chosen.reserveCapacity(degree)
        while chosen.count < degree {
            let i = Int(rng.next() % UInt32(n))
            if !chosen.contains(i) { chosen.append(i) }
        }
        return chosen
    }
}
