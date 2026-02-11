#!/usr/bin/env python3
"""
Sword swing animation — 6 frames at 16x16, zero dependencies.
Demonstrates the "paint by numbers" approach for animation.
"""
import struct
import zlib
import os


def make_png(width, height, pixels):
    def chunk(ct, data):
        c = ct + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    hdr = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += struct.pack("BBBB", r, g, b, a)
    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return hdr + ihdr + idat + iend


def scale_up(pixels, factor):
    scaled = []
    for row in pixels:
        big_row = []
        for px in row:
            big_row.extend([px] * factor)
        for _ in range(factor):
            scaled.append(big_row[:])
    return scaled


def render_grid(palette, grid):
    return [[palette[idx] for idx in row] for row in grid]


def make_spritesheet(frames_pixels, frame_w, frame_h):
    """Combine frames into a horizontal sprite sheet."""
    n = len(frames_pixels)
    sheet = []
    for y in range(frame_h):
        row = []
        for f in range(n):
            row.extend(frames_pixels[f][y])
        sheet.append(row)
    return sheet, frame_w * n, frame_h


T = (0, 0, 0, 0)

PALETTE = [
    T,                          # 0  transparent
    (26,  26,  46,  255),       # 1  outline
    (232, 168, 124, 255),       # 2  skin
    (74,  44,  42,  255),       # 3  hair dark
    (106, 62,  50,  255),       # 4  hair mid
    (45,  106, 79,  255),       # 5  tunic dark
    (64,  145, 108, 255),       # 6  tunic light
    (92,  58,  30,  255),       # 7  boots
    (255, 255, 255, 255),       # 8  eye white
    (138, 138, 138, 255),       # 9  metal buckle
    (200, 140, 100, 255),       # 10 skin shadow
    (220, 225, 240, 255),       # 11 blade bright
    (160, 165, 180, 255),       # 12 blade mid
    (100, 105, 120, 255),       # 13 blade dark/edge
    (110, 75,  40,  255),       # 14 hilt/grip
    (180, 140, 50,  255),       # 15 guard (gold)
]

_ = 0

# ─── Frame 0: Idle / Ready ─────────────────────────────────────────
# Character stands, sword held at right side pointing up
FRAME_0 = [
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, 1, 1, 1, 1, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, 1, 3, 4, 4, 3, 1, _, _, _, _, _, _],  # 2
    [_, _, _, _, 1, 3, 4, 4, 4, 1, _, _, _, _, _, _],  # 3
    [_, _, _, _, 1, 2, 8, 2, 8, 1, _, _, _, _, _, _],  # 4  eyes
    [_, _, _, _, 1, 2, 1, 2, 1, 1, _, _, _, _, _, _],  # 5
    [_, _, _, _, _, 1, 2, 2, 1, _, _, _, _, _, _, _],  # 6  chin
    [_, _, _, _, _, _, 1, 1, _, _, _, _, _, _, _, _],  # 7  neck
    [_, _, _, 1, 1, 5, 6, 6, 5, 1, 2, 1, _, _, _, _],  # 8  shoulders+arm
    [_, _, _, 1, 5, 6, 9, 9, 6, 5, 2, 1, _, _, _, _],  # 9  tunic+arm
    [_, _, _, 1, 5, 6, 5, 5, 6, 5,10, 1, _, _, _, _],  # 10 tunic+hand
    [_, _, _, _, 1, 5, 6, 6, 5, 1,15,14, 1, _, _, _],  # 11 waist+hilt
    [_, _, _, _, 1, 5, 5, 5, 5, 1, 1,13, 1, _, _, _],  # 12 legs+blade
    [_, _, _, _, 1, 7, 7, 1, 7, 7, _,12, 1, _, _, _],  # 13 boots+blade
    [_, _, _, _, _, 1, 1, _, 1, 1, _,11, 1, _, _, _],  # 14 feet+blade
    [_, _, _, _, _, _, _, _, _, _, _, 1, _, _, _, _],  # 15 blade tip
]

# ─── Frame 1: Wind-up ──────────────────────────────────────────────
# Sword raised behind head, body leans slightly
FRAME_1 = [
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, 1,11, 1, _, _, _, _, _, _, _, _, _, _],  # 1  blade tip above
    [_, _, _, _,12, 1, 1, 1, 1, _, _, _, _, _, _, _],  # 2  blade+hair
    [_, _, _, _,13, 1, 4, 4, 3, 1, _, _, _, _, _, _],  # 3  blade+hair
    [_, _, _, 1,15,14, 4, 4, 4, 1, _, _, _, _, _, _],  # 4  guard+hair
    [_, _, _, _, 1, 1, 8, 2, 8, 1, _, _, _, _, _, _],  # 5  hilt+eyes
    [_, _, _, _, _, 1, 1, 2, 1, 1, _, _, _, _, _, _],  # 6
    [_, _, _, _, _, _, 1, 2, 1, _, _, _, _, _, _, _],  # 7  chin
    [_, _, _, _, 1, 2, 1, 1, _, _, _, _, _, _, _, _],  # 8  arm raised
    [_, _, _, 1,10, 2, 5, 6, 5, 1, _, _, _, _, _, _],  # 9  arm+shoulders
    [_, _, _, 1, 1, 5, 6, 9, 6, 5, 1, _, _, _, _, _],  # 10 tunic
    [_, _, _, _, 1, 5, 6, 6, 5, 5, 1, _, _, _, _, _],  # 11 tunic
    [_, _, _, _, 1, 5, 5, 5, 5, 1, _, _, _, _, _, _],  # 12 legs
    [_, _, _, _, _, 1, 7, 1, 7, 1, _, _, _, _, _, _],  # 13 boots
    [_, _, _, _, _, 1, 7, 1, 7, 1, _, _, _, _, _, _],  # 14 boots
    [_, _, _, _, _, _, 1, _, 1, _, _, _, _, _, _, _],  # 15 feet
]

# ─── Frame 2: Overhead ─────────────────────────────────────────────
# Sword directly overhead, about to swing down
FRAME_2 = [
    [_, _, _, _, _, _, 1,11,12,13, 1, _, _, _, _, _],  # 0  blade horizontal above
    [_, _, _, _, _, _, _, 1,15, 1, _, _, _, _, _, _],  # 1  guard
    [_, _, _, _, _, _, _, 1,14, 1, _, _, _, _, _, _],  # 2  hilt
    [_, _, _, _, _, 1, 1, 2, 2, 1, _, _, _, _, _, _],  # 3  hands raised
    [_, _, _, _, 1, 3, 4, 2, 4, 3, 1, _, _, _, _, _],  # 4  hair+arms up
    [_, _, _, _, 1, 3, 4, 4, 4, 3, 1, _, _, _, _, _],  # 5  hair
    [_, _, _, _, 1, 2, 8, 2, 8, 2, 1, _, _, _, _, _],  # 6  face
    [_, _, _, _, 1, 2, 1, 2, 1, 2, 1, _, _, _, _, _],  # 7  face
    [_, _, _, _, _, 1, 2, 2, 2, 1, _, _, _, _, _, _],  # 8  chin
    [_, _, _, _, 1, 5, 6, 6, 6, 5, 1, _, _, _, _, _],  # 9  shoulders
    [_, _, _, _, 1, 5, 6, 9, 6, 5, 1, _, _, _, _, _],  # 10 tunic
    [_, _, _, _, 1, 5, 6, 6, 6, 5, 1, _, _, _, _, _],  # 11 tunic
    [_, _, _, _, _, 1, 5, 5, 5, 1, _, _, _, _, _, _],  # 12 waist
    [_, _, _, _, _, 1, 7, 1, 7, 1, _, _, _, _, _, _],  # 13 boots
    [_, _, _, _, _, 1, 7, 1, 7, 1, _, _, _, _, _, _],  # 14 boots
    [_, _, _, _, _, _, 1, _, 1, _, _, _, _, _, _, _],  # 15 feet
]

# ─── Frame 3: Forward Slash (THE HIT) ──────────────────────────────
# Sword extended horizontally to the right — impact frame
# Body lunges forward, arm fully extended
FRAME_3 = [
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, 1, 1, 1, 1, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, 1, 3, 4, 4, 3, 1, _, _, _, _, _, _],  # 2
    [_, _, _, _, 1, 3, 4, 4, 4, 1, _, _, _, _, _, _],  # 3
    [_, _, _, _, 1, 2, 8, 2, 8, 1, _, _, _, _, _, _],  # 4
    [_, _, _, _, 1, 2, 1, 2, 1, 1, _, _, _, _, _, _],  # 5
    [_, _, _, _, _, 1, 2, 2, 1, _, _, _, _, _, _, _],  # 6
    [_, _, _, 1, 5, 6, 6, 1, 2, 2,10,15, 1, _, _, _],  # 7  lunge+arm+guard
    [_, _, _, 1, 5, 6, 9, 9, 6, 1, 1,14,13,12,11, 1],  # 8  tunic+BLADE→
    [_, _, _, 1, 5, 6, 5, 5, 6, 1, _, _, _, _, _, _],  # 9  tunic
    [_, _, _, _, 1, 5, 6, 6, 5, 1, _, _, _, _, _, _],  # 10 waist
    [_, _, _, _, 1, 5, 5, 5, 5, 1, _, _, _, _, _, _],  # 11 legs
    [_, _, _, _, _, 1, 7, 1, 7, 1, _, _, _, _, _, _],  # 12 boots
    [_, _, _, _, 1, 7, 7, 1, 7, 7, 1, _, _, _, _, _],  # 13 boots (wide stance)
    [_, _, _, _, 1, 1, _, _, _, 1, 1, _, _, _, _, _],  # 14 feet
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 15
]

# ─── Frame 4: Follow-through ───────────────────────────────────────
# Sword angled down-right, past the strike
FRAME_4 = [
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, 1, 1, 1, 1, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, 1, 3, 4, 4, 3, 1, _, _, _, _, _, _],  # 2
    [_, _, _, _, 1, 3, 4, 4, 4, 1, _, _, _, _, _, _],  # 3
    [_, _, _, _, 1, 2, 8, 2, 8, 1, _, _, _, _, _, _],  # 4
    [_, _, _, _, 1, 2, 1, 2, 1, 1, _, _, _, _, _, _],  # 5
    [_, _, _, _, _, 1, 2, 2, 1, _, _, _, _, _, _, _],  # 6
    [_, _, _, _, _, _, 1, 1, _, _, _, _, _, _, _, _],  # 7
    [_, _, _, 1, 1, 5, 6, 6, 5, 1, _, _, _, _, _, _],  # 8  shoulders
    [_, _, _, 1, 5, 6, 9, 9, 6, 2, 1, _, _, _, _, _],  # 9  tunic+arm
    [_, _, _, 1, 5, 6, 5, 5, 6,10,15, 1, _, _, _, _],  # 10 tunic+hand+guard
    [_, _, _, _, 1, 5, 6, 6, 5, 1,14, 1, _, _, _, _],  # 11 waist+hilt
    [_, _, _, _, 1, 5, 5, 5, 1, _, 1,13, 1, _, _, _],  # 12 legs+blade
    [_, _, _, _, _, 1, 7, 1, 7, 1, _,12, 1, _, _, _],  # 13 boots+blade
    [_, _, _, _, _, 1, 1, _, 1, 1, _, 1,11, 1, _, _],  # 14 feet+blade
    [_, _, _, _, _, _, _, _, _, _, _, _, 1, _, _, _],  # 15 tip
]

# ─── Frame 5: Recovery ─────────────────────────────────────────────
# Returning to ready, sword low at side
FRAME_5 = [
    [_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _],  # 0
    [_, _, _, _, _, 1, 1, 1, 1, _, _, _, _, _, _, _],  # 1
    [_, _, _, _, 1, 3, 4, 4, 3, 1, _, _, _, _, _, _],  # 2
    [_, _, _, _, 1, 3, 4, 4, 4, 1, _, _, _, _, _, _],  # 3
    [_, _, _, _, 1, 2, 8, 2, 8, 1, _, _, _, _, _, _],  # 4
    [_, _, _, _, 1, 2, 1, 2, 1, 1, _, _, _, _, _, _],  # 5
    [_, _, _, _, _, 1, 2, 2, 1, _, _, _, _, _, _, _],  # 6
    [_, _, _, _, _, _, 1, 1, _, _, _, _, _, _, _, _],  # 7
    [_, _, _, 1, 1, 5, 6, 6, 5, 1, _, _, _, _, _, _],  # 8  shoulders
    [_, _, _, 1, 5, 6, 9, 9, 6, 5, 2, 1, _, _, _, _],  # 9  tunic+arm
    [_, _, _, 1, 5, 6, 5, 5, 6, 5,10, 1, _, _, _, _],  # 10
    [_, _, _, _, 1, 5, 6, 6, 5, 1,15, 1, _, _, _, _],  # 11 guard
    [_, _, _, _, 1, 5, 5, 5, 5, 1,14, 1, _, _, _, _],  # 12 hilt
    [_, _, _, _, 1, 7, 7, 1, 7, 7,13, 1, _, _, _, _],  # 13 boots+blade
    [_, _, _, _, _, 1, 1, _, 1, 1,12, 1, _, _, _, _],  # 14 feet+blade
    [_, _, _, _, _, _, _, _, _, _,11, 1, _, _, _, _],  # 15 blade tip
]

ALL_FRAMES = [FRAME_0, FRAME_1, FRAME_2, FRAME_3, FRAME_4, FRAME_5]
FRAME_NAMES = ["ready", "windup", "overhead", "strike", "follow", "recover"]


def main():
    out_dir = "/home/user/Godot-AI-Bridge/demo_sprites"
    os.makedirs(out_dir, exist_ok=True)

    frame_pixels = []

    for i, (name, grid) in enumerate(zip(FRAME_NAMES, ALL_FRAMES)):
        pixels = render_grid(PALETTE, grid)
        frame_pixels.append(pixels)

        # Save individual frame at 16x
        big = scale_up(pixels, 16)
        png = make_png(256, 256, big)
        path = os.path.join(out_dir, f"swing_{i}_{name}_256.png")
        with open(path, "wb") as f:
            f.write(png)
        print(f"  Frame {i} ({name}): {path}")

        # Also save 1x for game use
        png_1x = make_png(16, 16, pixels)
        with open(os.path.join(out_dir, f"swing_{i}_{name}_16.png"), "wb") as f:
            f.write(png_1x)

    # ─── Sprite sheet (all frames in a horizontal strip) ───────────
    sheet, sw, sh = make_spritesheet(frame_pixels, 16, 16)
    # Save 1x sprite sheet
    png_sheet = make_png(sw, sh, sheet)
    sheet_path = os.path.join(out_dir, "swing_sheet_96x16.png")
    with open(sheet_path, "wb") as f:
        f.write(png_sheet)
    print(f"\n  Sprite sheet (1x): {sheet_path}")

    # Save 8x sprite sheet for viewing
    sheet_big = scale_up(sheet, 8)
    png_sheet_big = make_png(sw * 8, sh * 8, sheet_big)
    sheet_big_path = os.path.join(out_dir, "swing_sheet_768x128.png")
    with open(sheet_big_path, "wb") as f:
        f.write(png_sheet_big)
    print(f"  Sprite sheet (8x): {sheet_big_path}")

    print(f"\nDone! {len(ALL_FRAMES)} frames generated.")


if __name__ == "__main__":
    main()
