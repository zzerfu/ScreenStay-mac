#!/usr/bin/env python3
"""Generate the ScreenStay app icon (requires Pillow).

Matches the product web palette (paper / sage / ink).
Applies a flush continuous-corner alpha mask so Finder previews look
rounded like macOS Dock icons; no large inset tile margin.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = ROOT / ".build" / "AppIcon.iconset"

SCALE = 2
SIZE = 1024 * SCALE

PAPER = (248, 249, 245)
PAPER_SOFT = (255, 255, 255)
ACCENT_SOFT = (234, 241, 233)
GREEN = (57, 116, 94)  # --green #39745e
INK = (36, 59, 52)      # --ink #243b34
LINE = (220, 228, 220)  # --line #dce4dc


def gradient(size: int, c0: tuple[int, int, int], c1: tuple[int, int, int]) -> Image.Image:
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    r0, g0, b0 = c0
    r1, g1, b1 = c1
    denom = float(small - 1)
    for y in range(small):
        for x in range(small):
            t = (x / denom) * 0.35 + (y / denom) * 0.65
            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
            px[x, y] = (
                int(r0 + (r1 - r0) * t),
                int(g0 + (g1 - g0) * t),
                int(b0 + (b1 - b0) * t),
            )
    return img.resize((size, size), Image.Resampling.BICUBIC)


def continuous_corner_mask(size: int) -> Image.Image:
    """Flush macOS-like continuous corner (~22.3% radius)."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(size * 0.223)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(1, size // 512)))
    mask = mask.point(lambda p: 255 if p > 20 else 0)
    return mask.filter(ImageFilter.GaussianBlur(max(1, size // 900)))


def draw_icon() -> Image.Image:
    face = gradient(SIZE, PAPER, ACCENT_SOFT).convert("RGBA")

    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-SIZE * 0.15, -SIZE * 0.25, SIZE * 0.55, SIZE * 0.45), fill=(*GREEN, 32))
    gd.ellipse((SIZE * 0.45, SIZE * 0.55, SIZE * 1.2, SIZE * 1.25), fill=(*LINE, 100))
    face.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(80 * SCALE))))

    left = int(130 * SCALE)
    top = int(155 * SCALE)
    right = int(894 * SCALE)
    bottom = int(655 * SCALE)
    stroke = int(34 * SCALE)
    display_radius = int(60 * SCALE)
    outline = (*INK, 255)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (left + int(20 * SCALE), top + int(30 * SCALE), right + int(12 * SCALE), bottom + int(40 * SCALE)),
        radius=display_radius,
        fill=(36, 59, 52, 30),
    )
    face.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(26 * SCALE))))

    draw = ImageDraw.Draw(face)
    draw.rounded_rectangle((left, top, right, bottom), radius=display_radius, outline=outline, width=stroke)

    inner = int(38 * SCALE)
    draw.rounded_rectangle(
        (left + inner, top + inner, right - inner, bottom - inner),
        radius=max(display_radius - inner // 2, 8),
        fill=(*PAPER_SOFT, 235),
    )
    wash = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wash)
    wd.rounded_rectangle(
        (left + inner, top + inner, right - inner, bottom - inner),
        radius=max(display_radius - inner // 2, 8),
        fill=(*ACCENT_SOFT, 170),
    )
    face.alpha_composite(wash)

    stem_width = int(62 * SCALE)
    draw = ImageDraw.Draw(face)
    draw.rounded_rectangle(
        (
            SIZE // 2 - stem_width // 2,
            bottom - int(2 * SCALE),
            SIZE // 2 + stem_width // 2,
            int(735 * SCALE),
        ),
        radius=int(14 * SCALE),
        fill=outline,
    )
    draw.rounded_rectangle(
        (int(330 * SCALE), int(720 * SCALE), int(694 * SCALE), int(778 * SCALE)),
        radius=int(22 * SCALE),
        fill=outline,
    )

    center = (SIZE // 2, int(405 * SCALE))
    play_radius = int(155 * SCALE)
    play_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pd = ImageDraw.Draw(play_layer)
    pd.ellipse(
        (
            center[0] - play_radius,
            center[1] - play_radius,
            center[0] + play_radius,
            center[1] + play_radius,
        ),
        fill=(*GREEN, 255),
    )
    face.alpha_composite(play_layer.filter(ImageFilter.GaussianBlur(int(16 * SCALE))))
    face.alpha_composite(play_layer)

    draw = ImageDraw.Draw(face)
    tri_left = center[0] - int(46 * SCALE)
    tri_right = center[0] + int(76 * SCALE)
    tri_top = center[1] - int(80 * SCALE)
    tri_bottom = center[1] + int(80 * SCALE)
    draw.polygon(
        [(tri_left, tri_top), (tri_left, tri_bottom), (tri_right, center[1])],
        fill=(*PAPER_SOFT, 255),
    )

    dot_center = (int(820 * SCALE), int(220 * SCALE))
    dot_radius = int(24 * SCALE)
    draw.ellipse(
        (
            dot_center[0] - dot_radius,
            dot_center[1] - dot_radius,
            dot_center[0] + dot_radius,
            dot_center[1] + dot_radius,
        ),
        fill=(*GREEN, 255),
    )

    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.arc(
        (int(28 * SCALE), int(18 * SCALE), SIZE - int(28 * SCALE), SIZE - int(18 * SCALE)),
        start=200,
        end=340,
        fill=(255, 255, 255, 80),
        width=int(12 * SCALE),
    )
    face.alpha_composite(highlight.filter(ImageFilter.GaussianBlur(int(5 * SCALE))))

    mask = continuous_corner_mask(SIZE)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(face, (0, 0), mask)
    return out.resize((1024, 1024), Image.Resampling.LANCZOS)


def main() -> None:
    icon = draw_icon()
    RESOURCES.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for name, size in sizes.items():
        icon.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / name)

    icon.save(RESOURCES / "AppIcon-1024.png")
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(RESOURCES / "AppIcon.icns")],
        check=True,
    )
    shutil.rmtree(ICONSET)
    print(f"wrote {RESOURCES / 'AppIcon.icns'}")


if __name__ == "__main__":
    main()
