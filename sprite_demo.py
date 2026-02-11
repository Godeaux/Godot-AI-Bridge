#!/usr/bin/env python3
"""
Proof of concept: AI-generated pixel art using palette-indexed grids.
No external dependencies — raw PNG encoding with stdlib only.
"""
import struct
import zlib
import os

def make_png(width: int, height: int, pixels: list[list[tuple[int,int,int,int]]]) -> bytes:
    """Encode RGBA pixel data as a PNG file. Zero dependencies."""
    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    header = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))

    raw = b""
    for row in pixels:
        raw += b"\x00"  # filter: none
        for r, g, b, a in row:
            raw += struct.pack("BBBB", r, g, b, a)

    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend


def scale_up(pixels: list[list[tuple]], factor: int) -> list[list[tuple]]:
    """Scale pixel grid by integer factor (nearest neighbor)."""
    scaled = []
    for row in pixels:
        big_row = []
        for px in row:
            big_row.extend([px] * factor)
        for _ in range(factor):
            scaled.append(big_row[:])
    return scaled


def render_grid(palette: list[tuple[int,int,int,int]], grid: list[list[int]]) -> list[list[tuple]]:
    """Convert palette-indexed grid to RGBA pixel data."""
    return [[palette[idx] for idx in row] for row in grid]


# ─── Palette ────────────────────────────────────────────────────────
# Define colors as (R, G, B, A)
T = (0, 0, 0, 0)          # 0 = transparent
PALETTE = [
    T,                      # 0  transparent
    (26,  26,  46,  255),   # 1  dark outline
    (232, 168, 124, 255),   # 2  skin
    (74,  44,  42,  255),   # 3  hair dark
    (106, 62,  50,  255),   # 4  hair mid
    (45,  106, 79,  255),   # 5  tunic dark
    (64,  145, 108, 255),   # 6  tunic light
    (92,  58,  30,  255),   # 7  boots/leather
    (255, 255, 255, 255),   # 8  white (eyes)
    (138, 138, 138, 255),   # 9  metal/buckle
    (200, 140, 100, 255),   # 10 skin shadow
    (52,  78,  65,  255),   # 11 tunic shadow
]

# ─── 16×16 RPG Adventurer (front-facing) ───────────────────────────
# Each number is a palette index. 0 = transparent.
# Designed for left-right symmetry with intentional small asymmetries.
_ = 0
ADVENTURER = [
    #0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, _, 1, 1, 1, 1, _, _, _, _, _, _],  # 1  hair top
    [_, _, _, _, _, 1, 3, 3, 3, 3, 1, _, _, _, _, _],  # 2  hair
    [_, _, _, _, 1, 3, 4, 4, 4, 4, 3, 1, _, _, _, _],  # 3  hair sides
    [_, _, _, _, 1, 2, 2, 2, 2, 2, 2, 1, _, _, _, _],  # 4  forehead
    [_, _, _, _, 1, 2, 8, 1, 2, 8, 1, 1, _, _, _, _],  # 5  eyes
    [_, _, _, _, 1, 2, 2, 2,10, 2, 2, 1, _, _, _, _],  # 6  nose/cheeks
    [_, _, _, _, _, 1,10, 2, 2, 2, 1, _, _, _, _, _],  # 7  mouth/chin
    [_, _, _, _, _, _, 1, 2, 2, 1, _, _, _, _, _, _],  # 8  neck
    [_, _, _, 1, 1, 5, 6, 9, 9, 6, 5, 1, 1, _, _, _],  # 9  shoulders + buckle
    [_, _, _, 1, 2, 5, 6, 5, 5, 6, 5, 2, 1, _, _, _],  # 10 tunic + arms
    [_, _, _, 1,10, 5, 6, 5, 5, 6, 5,10, 1, _, _, _],  # 11 tunic + arms
    [_, _, _, _, 1,11, 5, 5, 5, 5,11, 1, _, _, _, _],  # 12 tunic waist
    [_, _, _, _, 1, 5,11, 1, 1,11, 5, 1, _, _, _, _],  # 13 tunic bottom/legs
    [_, _, _, _, 1, 7, 7, 1, 1, 7, 7, 1, _, _, _, _],  # 14 boots
    [_, _, _, _, _, 1, 1, _, _, 1, 1, _, _, _, _, _],  # 15 feet
]

# ─── 16×16 Treasure Chest ──────────────────────────────────────────
CHEST_PALETTE = [
    T,                      # 0  transparent
    (26,  26,  46,  255),   # 1  dark outline
    (139, 90,  43,  255),   # 2  wood mid
    (101, 62,  28,  255),   # 3  wood dark
    (180, 120, 60,  255),   # 4  wood light
    (218, 165, 32,  255),   # 5  gold
    (255, 215, 0,   255),   # 6  gold bright
    (74,  44,  42,  255),   # 7  wood shadow
    (160, 100, 45,  255),   # 8  wood highlight
]

CHEST = [
    #0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 2
    [_, _, _, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, _, _, _],  # 3  lid top
    [_, _, 1, 4, 4, 2, 2, 2, 2, 2, 2, 4, 4, 1, _, _],  # 4  lid
    [_, _, 1, 4, 8, 2, 2, 2, 2, 2, 2, 8, 4, 1, _, _],  # 5  lid
    [_, _, 1, 2, 2, 3, 2, 2, 2, 2, 3, 2, 2, 1, _, _],  # 6  lid bands
    [_, _, 1, 2, 2, 3, 2, 5, 5, 2, 3, 2, 2, 1, _, _],  # 7  lid + lock
    [_, 1, 1, 1, 1, 1, 1, 6, 6, 1, 1, 1, 1, 1, 1, _],  # 8  lid edge + clasp
    [_, 1, 3, 3, 2, 2, 1, 5, 5, 1, 2, 2, 3, 3, 1, _],  # 9  body top + lock
    [_, 1, 3, 2, 8, 2, 3, 1, 1, 3, 2, 8, 2, 3, 1, _],  # 10 body
    [_, 1, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 1, _],  # 11 body
    [_, 1, 7, 3, 3, 2, 2, 2, 2, 2, 2, 3, 3, 7, 1, _],  # 12 body bands
    [_, _, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, _, _],  # 13 base
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 14
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 15
]

# ─── 16×16 Health Potion ───────────────────────────────────────────
POTION_PALETTE = [
    T,                      # 0  transparent
    (26,  26,  46,  255),   # 1  dark outline
    (200, 200, 220, 255),   # 2  glass light
    (160, 160, 185, 255),   # 3  glass mid
    (120, 120, 150, 255),   # 4  glass dark
    (220, 40,  60,  255),   # 5  potion red
    (180, 30,  50,  255),   # 6  potion dark red
    (255, 80,  100, 255),   # 7  potion highlight
    (100, 70,  50,  255),   # 8  cork
    (130, 95,  65,  255),   # 9  cork light
    (255, 220, 240, 255),   # 10 glass shine
]

POTION = [
    #0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, _, _, 1, 1, 1, _, _, _, _, _, _, _],  # 2  cork top
    [_, _, _, _, _, _, 1, 8, 9, 1, _, _, _, _, _, _],  # 3  cork
    [_, _, _, _, _, _, 1, 8, 9, 1, _, _, _, _, _, _],  # 4  cork
    [_, _, _, _, _, 1, 1, 3, 2, 1, 1, _, _, _, _, _],  # 5  neck
    [_, _, _, _, 1, 3, 2,10, 2, 3, 4, 1, _, _, _, _],  # 6  neck flare
    [_, _, _, 1, 3, 5, 7, 7, 5, 5, 6, 4, 1, _, _, _],  # 7  body top
    [_, _, _, 1, 3, 5, 7, 5, 5, 5, 6, 4, 1, _, _, _],  # 8  body
    [_, _, _, 1, 4, 5, 5, 5, 5, 6, 6, 4, 1, _, _, _],  # 9  body
    [_, _, _, 1, 4, 5, 5, 5, 6, 6, 6, 4, 1, _, _, _],  # 10 body
    [_, _, _, 1, 4, 6, 5, 5, 6, 6, 6, 4, 1, _, _, _],  # 11 body
    [_, _, _, _, 1, 4, 6, 6, 6, 6, 4, 1, _, _, _, _],  # 12 body bottom
    [_, _, _, _, _, 1, 1, 1, 1, 1, 1, _, _, _, _, _],  # 13 base
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 14
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 15
]


def main():
    out_dir = "/home/user/Godot-AI-Bridge/demo_sprites"
    os.makedirs(out_dir, exist_ok=True)

    sprites = [
        ("adventurer", PALETTE, ADVENTURER),
        ("chest",      CHEST_PALETTE, CHEST),
        ("potion",     POTION_PALETTE, POTION),
    ]

    for name, palette, grid in sprites:
        pixels = render_grid(palette, grid)

        # 1x (actual game size)
        png_1x = make_png(16, 16, pixels)
        path_1x = os.path.join(out_dir, f"{name}_16x16.png")
        with open(path_1x, "wb") as f:
            f.write(png_1x)

        # 16x scaled (for easy viewing)
        big = scale_up(pixels, 16)
        png_big = make_png(256, 256, big)
        path_big = os.path.join(out_dir, f"{name}_256x256.png")
        with open(path_big, "wb") as f:
            f.write(png_big)

        print(f"  {name}: {path_1x} + {path_big}")

    print(f"\nAll sprites saved to {out_dir}/")


if __name__ == "__main__":
    main()
