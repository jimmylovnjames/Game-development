#!/usr/bin/env python3
"""Write the Android launcher PNGs from the style-bible palette.

No third-party image libs — official Godot builds can load SVG, but this
script stays runnable on a bare CI image.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "icons" / "android"

MAGENTA = (255, 45, 149, 255)
CYAN = (0, 229, 255, 255)
YELLOW = (247, 255, 60, 255)
INK = (8, 5, 15, 255)
PLUM = (18, 10, 30, 255)
PLUM_HI = (43, 16, 48, 255)
RUST = (58, 34, 26, 255)
SKYLINE = (7, 6, 13, 255)


def _chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_png(path: Path, width: int, height: int, rgba: bytearray) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter None
        raw.extend(rgba[y * stride : (y + 1) * stride])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", ihdr) + _chunk(
        b"IDAT", zlib.compress(bytes(raw), 9)
    ) + _chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def fill(buf: bytearray, _w: int, _h: int, color: tuple[int, int, int, int]) -> None:
    pixel = bytes(color)
    for i in range(0, len(buf), 4):
        buf[i : i + 4] = pixel


def rect(
    buf: bytearray,
    w: int,
    h: int,
    x: int,
    y: int,
    rw: int,
    rh: int,
    color: tuple[int, int, int, int],
) -> None:
    x0 = max(0, x)
    y0 = max(0, y)
    x1 = min(w, x + rw)
    y1 = min(h, y + rh)
    pixel = bytes(color)
    for yy in range(y0, y1):
        row = yy * w * 4
        for xx in range(x0, x1):
            i = row + xx * 4
            buf[i : i + 4] = pixel


def circle(
    buf: bytearray,
    w: int,
    h: int,
    cx: int,
    cy: int,
    r: int,
    color: tuple[int, int, int, int],
) -> None:
    r2 = r * r
    for yy in range(max(0, cy - r), min(h, cy + r + 1)):
        dy = yy - cy
        for xx in range(max(0, cx - r), min(w, cx + r + 1)):
            dx = xx - cx
            if dx * dx + dy * dy <= r2:
                i = (yy * w + xx) * 4
                buf[i : i + 4] = bytes(color)


def gradient_fill(buf: bytearray, w: int, h: int) -> None:
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(PLUM[0] * (1 - t) + PLUM_HI[0] * t)
        g = int(PLUM[1] * (1 - t) + PLUM_HI[1] * t)
        b = int(PLUM[2] * (1 - t) + PLUM_HI[2] * t)
        pixel = bytes((r, g, b, 255))
        row = y * w * 4
        for x in range(w):
            i = row + x * 4
            buf[i : i + 4] = pixel


def draw_skyline(buf: bytearray, size: int, pad: int) -> None:
    """Skyline in the adaptive-icon safe zone (centred ~66% circle)."""
    inner = size - pad * 2
    s = inner / 128.0

    def sx(v: float) -> int:
        return pad + int(v * s)

    def sy(v: float) -> int:
        return pad + int(v * s)

    def sw(v: float) -> int:
        return max(1, int(v * s))

    buildings = [(14, 58, 20, 52), (40, 38, 18, 72), (64, 50, 22, 60), (92, 30, 20, 80)]
    stroke = max(2, int(2 * s))
    for x, y, bw, bh in buildings:
        rect(buf, size, size, sx(x) - stroke, sy(y) - stroke, sw(bw) + stroke * 2, sw(bh) + stroke * 2, CYAN)
        rect(buf, size, size, sx(x), sy(y), sw(bw), sw(bh), SKYLINE)
    rect(buf, size, size, sx(44), sy(46), sw(10), max(2, sw(3)), MAGENTA)
    rect(buf, size, size, sx(68), sy(60), sw(14), max(2, sw(3)), MAGENTA)
    rect(buf, size, size, sx(96), sy(40), sw(12), max(2, sw(3)), YELLOW)
    circle(buf, size, size, sx(98), sy(18), max(4, sw(9)), MAGENTA)
    rect(buf, size, size, sx(0), sy(108), sw(128), sw(20), RUST)
    rect(buf, size, size, sx(0), sy(108), sw(128), max(2, sw(2)), CYAN)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    icon = bytearray(192 * 192 * 4)
    gradient_fill(icon, 192, 192)
    draw_skyline(icon, 192, 8)
    write_png(OUT / "icon_192.png", 192, 192, icon)

    fg = bytearray(432 * 432 * 4)
    fill(fg, 432, 432, (0, 0, 0, 0))
    # Keep critical art inside the 66% safe circle: pad ~72px on 432.
    draw_skyline(fg, 432, 72)
    write_png(OUT / "adaptive_fg_432.png", 432, 432, fg)

    bg = bytearray(432 * 432 * 4)
    gradient_fill(bg, 432, 432)
    write_png(OUT / "adaptive_bg_432.png", 432, 432, bg)

    print(f"wrote icons under {OUT}")


if __name__ == "__main__":
    main()
