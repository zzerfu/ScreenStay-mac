#!/usr/bin/env python3
"""Generate the ScreenStay app icon (requires Pillow).

macOS applies the squircle mask itself — fill the full 1024 canvas.
Do not bake large rounded margins or drop shadows into the asset.
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


def gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    """Fast diagonal gradient: paint small, upsample."""
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    r0, g0, b0 = top_left
    r1, g1, b1 = bottom_right
    denom = float(small - 1)
    for y in range(small):
        for x in range(small):
            t = (x / denom) * 0.40 + (y / denom) * 0.60
            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
            px[x, y] = (
                int(r0 + (r1 - r0) * t),
                int(g0 + (g1 - g0) * t),
                int(b0 + (b1 - b0) * t),
            )
    return img.resize((size, size), Image.Resampling.BICUBIC)


def draw_icon() -> Image.Image:
    # Full-bleed canvas — system mask will clip corners.
    # Palette: midnight indigo → soft violet (screen/always-on), no mint green.
    background = gradient(SIZE, (18, 24, 48), (52, 38, 92)).convert("RGBA")
    canvas = background.copy()

    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (-SIZE * 0.18, -SIZE * 0.28, SIZE * 0.58, SIZE * 0.46),
        fill=(120, 160, 255, 70),
    )
    glow_draw.ellipse(
        (SIZE * 0.55, SIZE * 0.58, SIZE * 1.22, SIZE * 1.28),
        fill=(180, 110, 255, 48),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(72 * SCALE)))
    canvas.alpha_composite(glow)

    draw = ImageDraw.Draw(canvas)

    left = int(150 * SCALE)
    top = int(190 * SCALE)
    right = int(874 * SCALE)
    bottom = int(668 * SCALE)
    stroke = int(30 * SCALE)
    display_radius = int(58 * SCALE)
    outline = (228, 232, 255, 255)
    draw.rounded_rectangle(
        (left, top, right, bottom),
        radius=display_radius,
        outline=outline,
        width=stroke,
    )

    inner = int(34 * SCALE)
    draw.rounded_rectangle(
        (left + inner, top + inner, right - inner, bottom - inner),
        radius=max(display_radius - inner // 2, 8),
        fill=(22, 28, 58, 200),
    )

    stem_width = int(60 * SCALE)
    draw.rounded_rectangle(
        (
            SIZE // 2 - stem_width // 2,
            bottom - int(2 * SCALE),
            SIZE // 2 + stem_width // 2,
            int(740 * SCALE),
        ),
        radius=int(14 * SCALE),
        fill=outline,
    )
    draw.rounded_rectangle(
        (int(340 * SCALE), int(726 * SCALE), int(684 * SCALE), int(776 * SCALE)),
        radius=int(20 * SCALE),
        fill=outline,
    )

    center = (SIZE // 2, int(430 * SCALE))
    play_radius = int(148 * SCALE)
    play_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    play_draw = ImageDraw.Draw(play_layer)
    play_draw.ellipse(
        (
            center[0] - play_radius,
            center[1] - play_radius,
            center[0] + play_radius,
            center[1] + play_radius,
        ),
        fill=(130, 168, 255, 255),
    )
    glow_ring = play_layer.filter(ImageFilter.GaussianBlur(int(20 * SCALE)))
    canvas.alpha_composite(glow_ring)
    canvas.alpha_composite(play_layer)
    draw = ImageDraw.Draw(canvas)

    tri_left = center[0] - int(44 * SCALE)
    tri_right = center[0] + int(70 * SCALE)
    tri_top = center[1] - int(76 * SCALE)
    tri_bottom = center[1] + int(76 * SCALE)
    draw.polygon(
        [(tri_left, tri_top), (tri_left, tri_bottom), (tri_right, center[1])],
        fill=(22, 28, 58, 255),
    )

    dot_center = (int(812 * SCALE), int(246 * SCALE))
    dot_radius = int(22 * SCALE)
    draw.ellipse(
        (
            dot_center[0] - dot_radius,
            dot_center[1] - dot_radius,
            dot_center[0] + dot_radius,
            dot_center[1] + dot_radius,
        ),
        fill=(255, 140, 160, 255),
    )

    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.arc(
        (int(40 * SCALE), int(28 * SCALE), SIZE - int(40 * SCALE), SIZE - int(28 * SCALE)),
        start=200,
        end=340,
        fill=(255, 255, 255, 48),
        width=int(10 * SCALE),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(int(6 * SCALE)))
    canvas.alpha_composite(highlight)

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


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
