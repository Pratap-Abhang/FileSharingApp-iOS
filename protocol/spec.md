# FileSharingApp optical transfer protocol, v1

The sender's screen shows a looping stream of QR codes; the receiver's camera
reads them. The link is one-way, so the data is fountain-coded: the receiver
rebuilds the bundle from any large-enough set of frames, in any order.

All integers are unsigned and **big-endian**. Both apps (Swift, Kotlin) and the
Python reference in `tools/reference.py` must produce byte-identical frames for
the vectors in `test-vectors/vectors.json`.

## 1. Bundle

The selected photos are packed into one byte string:

```
"FSB1"                     4 bytes, ASCII magic
manifestLength             u32
manifest                   UTF-8 JSON, manifestLength bytes
file bytes                 every file's bytes, concatenated in manifest order
sha256                     32 bytes, SHA-256 of everything above
```

Manifest JSON:

```json
{"v":1,"files":[{"name":"IMG_0001.webp","size":183422,"mime":"image/webp"}]}
```

## 2. Blocks

- `L` = bundle length in bytes, `K` = block size (default 1000).
- `n = ceil(L / K)` source blocks; the last block is zero-padded to `K`.

## 3. Packets (fountain code)

Each packet has an encoding symbol id `esi` (u32, the sender counts up from 0
and loops forever) and carries the XOR of `degree` source blocks.

### 3.1 Systematic packets

If `esi < n`: degree = 1, the packet is source block `esi` unchanged. With no
loss the receiver is done after exactly `n` frames.

### 3.2 Coded packets (`esi >= n`)

PRNG: xorshift32 on a u32 state `x`:

```
x ^= x << 13;  x ^= x >> 17;  x ^= x << 5;   (all mod 2^32, >> is logical)
return x
```

Seed:

```
s = (esi * 0x9E3779B1 + session) mod 2^32
s ^= s >> 16
if s == 0: s = 0x6D2B79F5
x = s
```

1. The **first** PRNG output picks the degree. Only the encoder uses its value
   (the degree is written into the frame); the decoder draws it and discards it.
   Encoder: `u = first / 2^32`, degree = smallest `d` in `1..n` with
   `cdf[d] >= u`, where `cdf` is the robust soliton CDF below.
2. Following outputs pick the blocks: `i = next() mod n`, skipping any index
   already chosen, until `degree` distinct indices are drawn.

Robust soliton, `c = 0.1`, `delta = 0.5`:

```
rho(1) = 1/n;   rho(d) = 1/(d(d-1))  for d = 2..n
R      = c * ln(n/delta) * sqrt(n)
spike  = clamp(floor(n/R), 1, n)
tau(d) = R/(d*n)                     for d < spike
tau(spike) = max(0, R*ln(R/delta)/n)
tau(d) = 0                           for d > spike
mu(d)  = (rho(d)+tau(d)) / sum over d of (rho+tau)
cdf[d] = mu(1)+...+mu(d);  cdf[n] is forced to 1.0
```

If `n == 1`, every packet is block 0.

## 4. Frame

```
offset  size  field
0       2     magic "FQ" (0x46 0x51)
2       1     version = 1
3       1     flags = 0
4       4     session      random u32 chosen by the sender per batch
8       4     bundleLength L
12      2     blockSize K
14      4     esi
18      2     degree
20      K     payload (XOR of the chosen blocks)
20+K    4     CRC32 (IEEE 802.3, as zlib) of bytes 0 .. 20+K-1
```

Frame size = `24 + K` bytes (1024 at the default K = 1000).

## 5. QR encoding

The frame bytes are encoded with **Base45 (RFC 9285)** and the text is put in a
QR code in **alphanumeric mode**, error correction level **L**. Base45 output
uses only the QR alphanumeric character set, and iOS scanners return the
payload as a string, so this avoids raw-byte issues across platforms.

1024 bytes become 1536 Base45 characters (about QR version 25).

The sender shows frames at 10 to 15 fps (default 12), full screen, at maximum
brightness, with the screen kept awake.

## 6. Receiver

1. Base45-decode each scanned string; drop it if decoding fails, the magic or
   version is wrong, or the CRC does not match.
2. The first valid frame fixes `session`, `L`, `K`. A valid frame with a
   different session resets the receiver.
3. Rebuild the block indices for the packet (3.1 / 3.2) and feed it to a
   peeling decoder: XOR out blocks already known; when one unknown block is
   left, it is recovered, and recovery propagates to stored packets.
4. When all `n` blocks are known: truncate to `L`, check the trailing SHA-256,
   parse the manifest and split out the files.

Progress shown to the user = known blocks / n.
