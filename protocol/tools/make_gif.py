#!/usr/bin/env python3
"""Makes an animated GIF of the QR stream, so the receiver apps can be tested without a sender phone.

The GIF contains real protocol-v1 frames (see ../spec.md) for a small demo bundle: packets
0..N-1 in order, looping forever. Open it full screen on a computer and point the app's Receive
screen at it. The receiver collects packets over several loops (repeats are ignored), so it can
start at any moment.

Usage:  python3 make_gif.py [--out demo.gif] [--fps 10] [--block-size 1000] [--photo my.jpg]
Needs:  pip install segno pillow
"""
import argparse
import io
import math
import os
import random
import sys

import segno
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference as ref  # the protocol reference implementation


def demo_photo(width=480, height=320, quality=55) -> bytes:
    """A small synthetic JPEG, so no real photo is needed."""
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y in range(height):
        for x in range(width):
            px[x, y] = (int(255 * x / width), int(255 * y / height), 160)
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, width - 20, height - 20], outline=(255, 255, 255), width=4)
    d.text((40, height // 2 - 10), "FileSharingApp demo photo", fill=(255, 255, 255))
    out = io.BytesIO()
    img.save(out, "JPEG", quality=quality)
    return out.getvalue()


def qr_image(text: str, scale: int) -> Image.Image:
    """Alphanumeric-mode QR, error correction L, 4-module quiet zone (matches the apps)."""
    code = segno.make(text, error="L", mode="alphanumeric", boost_error=False)
    buf = io.BytesIO()
    code.save(buf, kind="png", scale=scale, border=4)
    buf.seek(0)
    return Image.open(buf).convert("L")


def success_rate(frames_per_loop, n, k, session, loss=0.3, trials=200) -> float:
    """Simulates a receiver that starts at a random point, loses `loss` of the frames and
    keeps looping, and returns how often it finishes within 6 loops."""
    enc_frames = [None] * frames_per_loop
    enc = ref.Encoder(b"\0" * (n * k), session, k)  # content is irrelevant to which packets help
    for i in range(frames_per_loop):
        enc_frames[i] = enc.frame(i)
    rnd = random.Random(1)
    ok = 0
    for _ in range(trials):
        dec = ref.Decoder()
        pos = rnd.randrange(frames_per_loop)
        for _ in range(6 * frames_per_loop):
            if rnd.random() >= loss:
                dec.add_frame(enc_frames[pos % frames_per_loop])
                if dec.done:
                    ok += 1
                    break
            pos += 1
    return ok / trials


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="qr-stream-demo.gif")
    p.add_argument("--fps", type=int, default=10)
    p.add_argument("--block-size", type=int, default=1000)
    p.add_argument("--photo", help="JPEG/WebP file to send (default: a generated demo photo)")
    p.add_argument("--loops-of-redundancy", type=float, default=3.0,
                   help="packets in the GIF = this x number of blocks")
    p.add_argument("--scale", type=int, default=6, help="pixels per QR module")
    args = p.parse_args()

    if args.photo:
        data = open(args.photo, "rb").read()
        name, mime = os.path.basename(args.photo), "image/jpeg" if args.photo.lower().endswith((".jpg", ".jpeg")) else "image/webp"
    else:
        data, name, mime = demo_photo(), "demo.jpg", "image/jpeg"

    bundle = ref.make_bundle([(name, mime, data)])
    session = 0x0D0E0F10
    enc = ref.Encoder(bundle, session, args.block_size)
    count = math.ceil(enc.n * args.loops_of_redundancy)
    print(f"photo {len(data)} bytes, bundle {len(bundle)} bytes, {enc.n} blocks, {count} frames in the GIF")

    images = []
    for esi in range(count):
        images.append(qr_image(ref.b45encode(enc.frame(esi)), args.scale))
    print(f"each frame {images[0].size[0]}x{images[0].size[1]} px")

    rate = success_rate(count, enc.n, args.block_size, session)
    print(f"simulated receiver (random start, 30% frame loss) finishes within 6 loops in {rate:.0%} of runs")

    images[0].save(
        args.out, save_all=True, append_images=images[1:],
        duration=int(1000 / args.fps), loop=0,  # loop=0 means loop forever
        optimize=False, disposal=1,
    )
    print("wrote", args.out, f"({os.path.getsize(args.out) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
