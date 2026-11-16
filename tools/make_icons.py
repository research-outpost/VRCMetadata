"""Regenerate icon16.bin / icon32.bin for VRCMetadata's tray icon.

Output: raw bottom-up 32-bpp BGRA bitmaps (1024 / 4096 bytes) next to
main.zig; @embedFile pulls them in at build time. Run with any stdlib
Python: `python tools/make_icons.py` from the project root.
"""
import math
import os

GRAD_TOP = (0x2A, 0x47, 0x5E)  # Steam blue (top)
GRAD_BOT = (0x10, 0x1B, 0x26)  # Steam navy (bottom)
DK = (0x0D, 0x14, 0x1C)        # dark core
WHITE = (244, 250, 247)


def render(size):
    ss = 8  # 8x8 supersampling per pixel for anti-aliasing
    cx = cy = size / 2.0
    r_out = size * 0.335
    r_in = size * 0.195
    dot_r = size * 0.085
    dot_cx, dot_cy = cx - size * 0.17, cy - size * 0.17

    def tile(x, y):
        return math.hypot(x - cx, y - cy) <= size / 2.0 - 0.5  # full circle

    def col(x, y):
        if math.hypot(x - dot_cx, y - dot_cy) <= dot_r:
            return WHITE
        d = math.hypot(x - cx, y - cy)
        if d <= r_in:
            return DK
        if d <= r_out:
            return WHITE
        t = y / (size - 1.0)  # vertical gradient, top=GRAD_TOP
        return tuple(int(GRAD_TOP[i] + (GRAD_BOT[i] - GRAD_TOP[i]) * t) for i in range(3))

    rows = []
    for y in range(size - 1, -1, -1):  # bottom-up first row, matches DIB
        row = bytearray()
        for x in range(size):
            rs = gs = bs = 0.0
            cov = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = x + (sx + 0.5) / ss
                    py = y + (sy + 0.5) / ss
                    if tile(px, py):
                        c = col(px, py)
                        rs += c[0]
                        gs += c[1]
                        bs += c[2]
                        cov += 1
            if cov:
                b = int(bs / cov)
                g = int(gs / cov)
                r = int(rs / cov)
                a = int(255 * cov / (ss * ss))
            else:
                b = g = r = a = 0
            row += bytes((b, g, r, a))  # BGRA
        rows.append(bytes(row))
    return b"".join(rows)


here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for s in (16, 32):
    data = render(s)
    assert len(data) == s * s * 4
    with open(os.path.join(here, f"icon{s}.bin"), "wb") as f:
        f.write(data)
    print(f"icon{s}.bin {len(data)} bytes")
