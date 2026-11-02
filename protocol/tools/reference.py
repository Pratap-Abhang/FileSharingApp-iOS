#!/usr/bin/env python3
"""Reference implementation of the FileSharingApp optical protocol v1.

Run `python3 reference.py` to regenerate ../test-vectors/vectors.json and to
self-test the encoder/decoder with random frame loss. See ../spec.md.
"""
import hashlib
import json
import math
import os
import random
import struct
import zlib

M32 = 0xFFFFFFFF
B45 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"


# ---------- Base45 (RFC 9285) ----------
def b45encode(data: bytes) -> str:
    out = []
    for i in range(0, len(data) - 1, 2):
        n = data[i] * 256 + data[i + 1]
        c, n = n % 45, n // 45
        d, e = n % 45, n // 45
        out += [B45[c], B45[d], B45[e]]
    if len(data) % 2:
        n = data[-1]
        out += [B45[n % 45], B45[n // 45]]
    return "".join(out)


def b45decode(text: str) -> bytes:
    vals = [B45.index(ch) for ch in text]
    if len(vals) % 3 == 1:
        raise ValueError("bad length")
    out = bytearray()
    for i in range(0, len(vals), 3):
        chunk = vals[i:i + 3]
        if len(chunk) == 3:
            n = chunk[0] + chunk[1] * 45 + chunk[2] * 2025
            if n > 0xFFFF:
                raise ValueError("bad chunk")
            out += bytes([n >> 8, n & 0xFF])
        else:
            n = chunk[0] + chunk[1] * 45
            if n > 0xFF:
                raise ValueError("bad chunk")
            out.append(n)
    return bytes(out)


# ---------- PRNG ----------
class XorShift32:
    def __init__(self, seed: int):
        self.x = seed & M32

    def next(self) -> int:
        x = self.x
        x ^= (x << 13) & M32
        x ^= x >> 17
        x ^= (x << 5) & M32
        self.x = x
        return x


def packet_seed(esi: int, session: int) -> int:
    s = (esi * 0x9E3779B1 + session) & M32
    s ^= s >> 16
    return s if s else 0x6D2B79F5


# ---------- Robust soliton ----------
def soliton_cdf(n: int, c: float = 0.1, delta: float = 0.5):
    if n == 1:
        return [1.0]
    rho = [0.0] * (n + 1)
    rho[1] = 1.0 / n
    for d in range(2, n + 1):
        rho[d] = 1.0 / (d * (d - 1))
    R = c * math.log(n / delta) * math.sqrt(n)
    spike = min(max(int(math.floor(n / R)), 1), n)
    tau = [0.0] * (n + 1)
    for d in range(1, spike):
        tau[d] = R / (d * n)
    tau[spike] = max(0.0, R * math.log(R / delta) / n)
    total = sum(rho[d] + tau[d] for d in range(1, n + 1))
    cdf, acc = [], 0.0
    for d in range(1, n + 1):
        acc += (rho[d] + tau[d]) / total
        cdf.append(acc)
    cdf[-1] = 1.0
    return cdf  # cdf[d-1] for degree d


def packet_indices(esi, session, n, cdf=None):
    """Returns (degree, indices). Pass cdf to act as encoder; without it the
    caller must supply the degree via packet_indices_for_degree."""
    if esi < n:
        return 1, [esi]
    rng = XorShift32(packet_seed(esi, session))
    u = rng.next() / 4294967296.0
    degree = n
    for d, p in enumerate(cdf, start=1):
        if p >= u:
            degree = d
            break
    return degree, _draw(rng, degree, n)


def packet_indices_for_degree(esi, session, n, degree):
    if esi < n:
        return [esi]
    rng = XorShift32(packet_seed(esi, session))
    rng.next()  # degree draw, discarded
    return _draw(rng, degree, n)


def _draw(rng, degree, n):
    chosen = []
    while len(chosen) < degree:
        i = rng.next() % n
        if i not in chosen:
            chosen.append(i)
    return chosen


# ---------- Encoder ----------
class Encoder:
    def __init__(self, bundle: bytes, session: int, block_size: int = 1000):
        self.bundle, self.session, self.k = bundle, session, block_size
        self.n = max(1, math.ceil(len(bundle) / block_size))
        padded = bundle + bytes(self.n * block_size - len(bundle))
        self.blocks = [padded[i * block_size:(i + 1) * block_size] for i in range(self.n)]
        self.cdf = soliton_cdf(self.n)

    def frame(self, esi: int) -> bytes:
        degree, idx = packet_indices(esi, self.session, self.n, self.cdf)
        payload = bytearray(self.k)
        for i in idx:
            b = self.blocks[i]
            for j in range(self.k):
                payload[j] ^= b[j]
        head = b"FQ" + bytes([1, 0]) + struct.pack(">IIHIH", self.session, len(self.bundle), self.k, esi, degree)
        body = head + bytes(payload)
        return body + struct.pack(">I", zlib.crc32(body) & M32)


# ---------- Decoder ----------
class Decoder:
    def __init__(self):
        self.session = self.length = self.k = None
        self.n = self.known = 0

    def _reset(self, session, length, k):
        self.session, self.length, self.k = session, length, k
        self.n = max(1, math.ceil(length / k))
        self.blocks = [None] * self.n
        self.known = 0
        self.pending = []  # [set(indices), bytearray]
        self.seen = set()

    def add_frame(self, frame: bytes) -> bool:
        """Returns True if the frame was valid."""
        if len(frame) < 24 or frame[:2] != b"FQ" or frame[2] != 1:
            return False
        session, length, k, esi, degree = struct.unpack(">IIHIH", frame[4:20])
        if len(frame) != 24 + k:
            return False
        if struct.unpack(">I", frame[-4:])[0] != zlib.crc32(frame[:-4]) & M32:
            return False
        if self.session != session or self.length != length or self.k != k:
            self._reset(session, length, k)
        if esi in self.seen or self.done:
            return True
        self.seen.add(esi)
        idx = set(packet_indices_for_degree(esi, session, self.n, degree))
        self._add(idx, bytearray(frame[20:20 + k]))
        return True

    def _add(self, idx, data):
        for i in [i for i in idx if self.blocks[i] is not None]:
            _xor(data, self.blocks[i])
            idx.discard(i)
        if not idx:
            return
        if len(idx) > 1:
            self.pending.append([idx, data])
            return
        queue = [(idx.pop(), data)]
        while queue:
            i, d = queue.pop()
            if self.blocks[i] is not None:
                continue
            self.blocks[i] = bytes(d)
            self.known += 1
            still = []
            for p in self.pending:
                if i in p[0]:
                    _xor(p[1], self.blocks[i])
                    p[0].discard(i)
                if len(p[0]) == 1:
                    queue.append((next(iter(p[0])), p[1]))
                elif p[0]:
                    still.append(p)
            self.pending = still

    @property
    def done(self):
        return self.session is not None and self.known == self.n

    def result(self) -> bytes:
        return b"".join(self.blocks)[:self.length]


def _xor(a: bytearray, b: bytes):
    for j in range(len(a)):
        a[j] ^= b[j]


# ---------- Bundle ----------
def make_bundle(files):
    """files: list of (name, mime, bytes)"""
    manifest = json.dumps({"v": 1, "files": [{"name": n, "size": len(b), "mime": m} for n, m, b in files]},
                          separators=(",", ":")).encode()
    body = b"FSB1" + struct.pack(">I", len(manifest)) + manifest + b"".join(b for _, _, b in files)
    return body + hashlib.sha256(body).digest()


def parse_bundle(bundle: bytes):
    if bundle[:4] != b"FSB1" or hashlib.sha256(bundle[:-32]).digest() != bundle[-32:]:
        raise ValueError("bad bundle")
    mlen = struct.unpack(">I", bundle[4:8])[0]
    manifest = json.loads(bundle[8:8 + mlen])
    pos, out = 8 + mlen, []
    for f in manifest["files"]:
        out.append((f["name"], f["mime"], bundle[pos:pos + f["size"]]))
        pos += f["size"]
    return out


def det_bytes(seed, length):
    rng = XorShift32(seed)
    return bytes(rng.next() & 0xFF for _ in range(length))


# ---------- Vectors + self-test ----------
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(here, "..", "test-vectors", "vectors.json")

    b45_cases = [b"AB", b"Hello!!", b"base-45", b"ietf!", b"", bytes([0, 0]), bytes([255, 255]), bytes([255])]
    crc_cases = [b"123456789", b"", det_bytes(7, 64)]

    files = [("a.webp", "image/webp", det_bytes(11, 1500)), ("b.webp", "image/webp", det_bytes(12, 1200))]
    bundle = make_bundle(files)
    session, k = 0x12345678, 200
    enc = Encoder(bundle, session, k)
    esis = [0, 1, enc.n - 1, enc.n, enc.n + 1, enc.n + 7, 100, 1000, 123456]
    frames = []
    for e in esis:
        f = enc.frame(e)
        degree, idx = packet_indices(e, session, enc.n, enc.cdf)
        frames.append({"esi": e, "degree": degree, "indices": idx, "frameHex": f.hex(), "base45": b45encode(f)})

    vectors = {
        "base45": [{"hex": c.hex(), "text": b45encode(c)} for c in b45_cases],
        "base45Invalid": ["A", "GGW", ":::", "ZZZZ"],
        "crc32": [{"hex": c.hex(), "crc": zlib.crc32(c) & M32} for c in crc_cases],
        "xorshift32": {"seed": 1, "first5": []},
        "packetSeed": [{"esi": e, "session": session, "seed": packet_seed(e, session)} for e in (0, 1, 42, 4294967295)],
        "solitonCdfN20First5": soliton_cdf(20)[:5],
        "bundle": {
            "files": [{"name": n, "mime": m, "dataSeed": s, "size": len(b)} for (n, m, b), s in zip(files, (11, 12))],
            "hex": bundle.hex(),
            "detBytesNote": "file data = low byte of each xorshift32 output starting from state=dataSeed",
        },
        "encoder": {"session": session, "blockSize": k, "n": enc.n, "frames": frames},
    }
    r = XorShift32(1)
    vectors["xorshift32"]["first5"] = [r.next() for _ in range(5)]

    with open(out_path, "w") as fh:
        json.dump(vectors, fh, indent=2)
        fh.write("\n")

    # self-test: loss + random order
    for b45 in vectors["base45"]:
        assert b45decode(b45["text"]).hex() == b45["hex"]
    rnd = random.Random(3)
    for trial in range(40):
        size = rnd.choice([1, 999, 1000, 1001, 25_000, 200_000])
        data = make_bundle([("x.bin", "application/octet-stream", os.urandom(size))])
        e = Encoder(data, rnd.getrandbits(32), 1000)
        d = Decoder()
        esi, used = rnd.randrange(0, 3 * e.n + 1), 0
        while not d.done:
            if rnd.random() < 0.3:  # 30% frame loss
                esi += 1
                continue
            f = e.frame(esi)
            assert d.add_frame(b45decode(b45encode(f)))
            esi += 1
            used += 1
        assert d.result() == data
        parse_bundle(d.result())
        if trial % 10 == 0:
            print(f"n={e.n:4d} frames used={used:4d} overhead={used / e.n - 1:+.1%}")
    print("reference self-test OK; wrote", os.path.normpath(out_path))


if __name__ == "__main__":
    main()
