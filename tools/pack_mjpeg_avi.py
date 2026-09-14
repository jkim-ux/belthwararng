#!/usr/bin/env python3
"""JPEG 프레임 폴더(frame_0000.jpg …)를 MJPEG AVI 로 묶는다. 외부 도구 없이 표준 라이브러리만 쓴다.
사용: python3 tools/pack_mjpeg_avi.py <frames_dir> <fps> <out.avi>
프레임 크기는 첫 JPEG 의 SOF 헤더에서 읽는다."""
import os, struct, sys

def jpeg_size(data: bytes):
    i = 2
    while i < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        if marker == 0xD8 or 0xD0 <= marker <= 0xD7 or marker == 0x01:
            i += 2
            continue
        seg = struct.unpack(">H", data[i + 2:i + 4])[0]
        i += 2 + seg
    raise ValueError("SOF not found")

def chunk(fourcc: bytes, payload: bytes) -> bytes:
    pad = b"\0" if len(payload) % 2 else b""
    return fourcc + struct.pack("<I", len(payload)) + payload + pad

def lst(kind: bytes, payload: bytes) -> bytes:
    return chunk(b"LIST", kind + payload)

def main():
    frames_dir, fps, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    names = sorted(n for n in os.listdir(frames_dir) if n.endswith(".jpg"))
    frames = [open(os.path.join(frames_dir, n), "rb").read() for n in names]
    if not frames:
        sys.exit("no frames")
    w, h = jpeg_size(frames[0])
    max_size = max(len(f) for f in frames)
    avih = struct.pack("<IIIIIIIIIIIIII", int(1_000_000 / fps), max_size * fps, 0, 0x10, len(frames), 0, 1, max_size, w, h, 0, 0, 0, 0)
    strh = b"vids" + b"MJPG" + struct.pack("<IHHIIIIIIIIhhhh", 0, 0, 0, 0, 1, fps, 0, len(frames), max_size, 0xFFFFFFFF, 0, 0, 0, w, h)
    strf = struct.pack("<IiiHH4sIiiII", 40, w, h, 1, 24, b"MJPG", w * h * 3, 0, 0, 0, 0)
    hdrl = lst(b"hdrl", chunk(b"avih", avih) + lst(b"strl", chunk(b"strh", strh) + chunk(b"strf", strf)))
    movi_payload = b""
    idx = b""
    for f in frames:
        offset = 4 + len(movi_payload)   # 'movi' fourcc 기준
        movi_payload += chunk(b"00dc", f)
        idx += b"00dc" + struct.pack("<III", 0x10, offset, len(f))
    movi = lst(b"movi", movi_payload)
    idx1 = chunk(b"idx1", idx)
    body = b"AVI " + hdrl + movi + idx1
    with open(out, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    print("wrote %s: %d frames %dx%d @%dfps, %.1f MB" % (out, len(frames), w, h, fps, os.path.getsize(out) / 1e6))

if __name__ == "__main__":
    main()
