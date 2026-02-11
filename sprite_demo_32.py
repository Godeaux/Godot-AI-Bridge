#!/usr/bin/env python3
"""
32x32 pixel art adventurer — proof of concept for higher-resolution
"paint by numbers" sprite generation. Zero external dependencies.
"""
import struct, zlib, os


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
    return hdr + ihdr + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


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


# ═══════════════════════════════════════════════════════════════════
#  PALETTE — 22 colors
# ═══════════════════════════════════════════════════════════════════
T = (0, 0, 0, 0)  # transparent

PALETTE = [
    T,                          # 0   transparent
    (20,  20,  35,  255),       # 1   outline (dark blue-black)
    (232, 170, 128, 255),       # 2   skin mid
    (198, 138, 100, 255),       # 3   skin shadow
    (248, 200, 168, 255),       # 4   skin highlight
    (60,  36,  34,  255),       # 5   hair dark
    (95,  58,  46,  255),       # 6   hair mid
    (130, 82,  60,  255),       # 7   hair light
    (148, 100, 72,  255),       # 8   hair highlight
    (255, 255, 255, 255),       # 9   eye white
    (55,  90,  160, 255),       # 10  iris blue
    (30,  80,  55,  255),       # 11  tunic dark
    (42,  110, 78,  255),       # 12  tunic mid
    (60,  148, 105, 255),       # 13  tunic light
    (78,  172, 125, 255),       # 14  tunic highlight
    (72,  48,  26,  255),       # 15  boot dark
    (100, 68,  36,  255),       # 16  boot mid
    (128, 92,  50,  255),       # 17  boot light
    (85,  55,  30,  255),       # 18  belt leather
    (120, 120, 135, 255),       # 19  metal dark
    (170, 170, 190, 255),       # 20  metal bright
    (190, 70,  75,  255),       # 21  mouth/lips
    (175, 125, 90,  255),       # 22  nose shadow
]

# Palette index aliases for readability
_ = 0    # transparent
X = 1    # outline
s = 2    # skin
d = 3    # skin shadow
h = 4    # skin highlight
D = 5    # hair dark
H = 6    # hair mid
L = 7    # hair light
A = 8    # hair highlight
W = 9    # eye white
I = 10   # iris
Z = 11   # tunic dark
t = 12   # tunic mid
l = 13   # tunic light
q = 14   # tunic highlight
B = 15   # boot dark
b = 16   # boot mid
p = 17   # boot light
E = 18   # belt
M = 19   # metal dark
m = 20   # metal bright
R = 21   # mouth
n = 22   # nose shadow

# ═══════════════════════════════════════════════════════════════════
#  32×32 ADVENTURER — front-facing, green tunic, leather belt
# ═══════════════════════════════════════════════════════════════════
#  Light source: top-left
#  Head ~12px wide, body ~14px, arms extend to ~18px
#  Columns:  0         1         2         3
#            0123456789012345678901234567890 1

GRID = [
 #0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
 [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  # 0
 [_,_,_,_,_,_,_,_,_,_,_,_,X,X,X,X,X,X,X,X,_,_,_,_,_,_,_,_,_,_,_,_],  # 1  hair crown outline
 [_,_,_,_,_,_,_,_,_,_,_,X,A,L,L,A,L,L,L,L,X,_,_,_,_,_,_,_,_,_,_,_],  # 2  hair top (highlight left=light)
 [_,_,_,_,_,_,_,_,_,_,X,L,L,A,L,L,L,L,L,H,H,X,_,_,_,_,_,_,_,_,_,_],  # 3  hair expanding
 [_,_,_,_,_,_,_,_,_,X,H,L,L,L,L,L,L,L,H,H,D,D,X,_,_,_,_,_,_,_,_,_],  # 4  hair full width (14px)
 [_,_,_,_,_,_,_,_,_,X,D,H,L,L,L,L,L,L,L,H,D,D,X,_,_,_,_,_,_,_,_,_],  # 5  hair lower
 [_,_,_,_,_,_,_,_,_,X,D,H,H,h,h,h,h,h,h,H,H,D,X,_,_,_,_,_,_,_,_,_],  # 6  forehead + hair frame
 [_,_,_,_,_,_,_,_,_,X,D,h,W,W,I,h,h,W,W,I,h,D,X,_,_,_,_,_,_,_,_,_],  # 7  eyes — whites + iris
 [_,_,_,_,_,_,_,_,_,X,D,s,W,I,X,s,s,W,I,X,s,D,X,_,_,_,_,_,_,_,_,_],  # 8  eyes lower — iris + lash
 [_,_,_,_,_,_,_,_,_,X,D,s,s,s,n,n,n,s,s,s,s,D,X,_,_,_,_,_,_,_,_,_],  # 9  nose
 [_,_,_,_,_,_,_,_,_,_,X,s,s,s,R,R,R,s,s,s,X,_,_,_,_,_,_,_,_,_,_,_],  # 10 mouth
 [_,_,_,_,_,_,_,_,_,_,X,d,s,s,s,s,s,s,s,d,X,_,_,_,_,_,_,_,_,_,_,_],  # 11 chin
 [_,_,_,_,_,_,_,_,_,_,_,X,d,s,s,s,s,s,d,X,_,_,_,_,_,_,_,_,_,_,_,_],  # 12 jaw
 [_,_,_,_,_,_,_,_,_,_,_,_,X,X,s,s,X,X,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  # 13 neck
 [_,_,_,_,_,_,_,_,_,X,X,t,l,l,l,l,l,l,l,t,X,X,_,_,_,_,_,_,_,_,_,_],  # 14 collar/shoulders
 [_,_,_,_,_,_,_,_,X,s,X,t,l,q,l,l,l,l,q,t,X,s,X,_,_,_,_,_,_,_,_,_],  # 15 upper chest + arms
 [_,_,_,_,_,_,_,_,X,s,X,t,l,l,l,l,l,l,l,t,X,s,X,_,_,_,_,_,_,_,_,_],  # 16 chest + arms
 [_,_,_,_,_,_,_,_,X,d,X,Z,t,l,l,l,l,l,t,Z,X,d,X,_,_,_,_,_,_,_,_,_],  # 17 mid torso + arms
 [_,_,_,_,_,_,_,_,X,d,X,Z,t,l,l,l,l,l,t,Z,X,d,X,_,_,_,_,_,_,_,_,_],  # 18 lower torso + arms
 [_,_,_,_,_,_,_,_,_,X,X,Z,t,t,l,l,l,t,t,Z,X,X,_,_,_,_,_,_,_,_,_,_],  # 19 arms end
 [_,_,_,_,_,_,_,_,_,_,X,E,E,M,m,m,m,M,E,E,X,_,_,_,_,_,_,_,_,_,_,_],  # 20 belt + buckle
 [_,_,_,_,_,_,_,_,_,_,X,Z,t,t,l,l,l,t,t,Z,X,_,_,_,_,_,_,_,_,_,_,_],  # 21 below belt
 [_,_,_,_,_,_,_,_,_,_,X,Z,t,t,l,l,l,t,t,Z,X,_,_,_,_,_,_,_,_,_,_,_],  # 22 tunic bottom
 [_,_,_,_,_,_,_,_,_,_,X,Z,t,t,X,_,X,t,t,Z,X,_,_,_,_,_,_,_,_,_,_,_],  # 23 tunic splits for legs
 [_,_,_,_,_,_,_,_,_,_,X,Z,t,Z,X,_,X,Z,t,Z,X,_,_,_,_,_,_,_,_,_,_,_],  # 24 upper legs
 [_,_,_,_,_,_,_,_,_,_,_,X,b,b,X,_,X,b,b,X,_,_,_,_,_,_,_,_,_,_,_,_],  # 25 legs
 [_,_,_,_,_,_,_,_,_,_,_,X,b,b,X,_,X,b,b,X,_,_,_,_,_,_,_,_,_,_,_,_],  # 26 legs
 [_,_,_,_,_,_,_,_,_,_,X,B,b,p,b,X,X,b,p,b,B,X,_,_,_,_,_,_,_,_,_,_],  # 27 boot tops (wider)
 [_,_,_,_,_,_,_,_,_,_,X,B,b,p,b,X,X,b,p,b,B,X,_,_,_,_,_,_,_,_,_,_],  # 28 boots
 [_,_,_,_,_,_,_,_,_,_,X,B,B,b,B,X,X,B,b,B,B,X,_,_,_,_,_,_,_,_,_,_],  # 29 boot soles
 [_,_,_,_,_,_,_,_,_,_,_,X,X,X,X,_,_,X,X,X,X,_,_,_,_,_,_,_,_,_,_,_],  # 30 feet
 [_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_],  # 31
]


def main():
    out_dir = "/home/user/Godot-AI-Bridge/demo_sprites"
    os.makedirs(out_dir, exist_ok=True)

    # Verify grid dimensions
    assert len(GRID) == 32, f"Grid has {len(GRID)} rows, expected 32"
    for i, row in enumerate(GRID):
        assert len(row) == 32, f"Row {i} has {len(row)} cols, expected 32"

    pixels = render_grid(PALETTE, GRID)

    # 1x
    png_1x = make_png(32, 32, pixels)
    with open(os.path.join(out_dir, "adventurer32_32x32.png"), "wb") as f:
        f.write(png_1x)

    # 8x for viewing
    big = scale_up(pixels, 8)
    path_big = os.path.join(out_dir, "adventurer32_256x256.png")
    with open(path_big, "wb") as f:
        f.write(make_png(256, 256, big))

    # 16x for detail inspection
    huge = scale_up(pixels, 16)
    path_huge = os.path.join(out_dir, "adventurer32_512x512.png")
    with open(path_huge, "wb") as f:
        f.write(make_png(512, 512, huge))

    print(f"32x32 adventurer saved to {out_dir}/")
    print(f"  adventurer32_32x32.png   (native)")
    print(f"  adventurer32_256x256.png (8x)")
    print(f"  adventurer32_512x512.png (16x)")


if __name__ == "__main__":
    main()
