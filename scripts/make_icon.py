#!/usr/bin/env python3
"""Generate the ScreenStay app icon (requires Pillow)."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = ROOT / ".build" / "AppIcon.iconset"

SCALE = 2
SIZE = 1024 * SCALE


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def gradient(size: int, top_left: tuple[int, int, int], bottom_right: tuple[int, int, int]) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    t = (x / size * 0.45) + (y / size * 0.55)
    t = np.clip(t, 0.0, 1.0)[..., None]
    top = np.array(top_left, dtype=np.float32)
    bottom = np.array(bottom_right, dtype=np.float32)
    array = (top + (bottom - top) * t).astype(np.uint8)
    return Image.fromarray(array, "RGB")

def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    margin = int(86 * SCALE)
    tile_size = SIZE - margin * 2
    radius = int(210 * SCALE)
    mask = rounded_mask(tile_size, radius)

    # Soft shadow under the rounded tile.
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (margin, margin + int(20 * SCALE), SIZE - margin, SIZE - margin + int(20 * SCALE)),
        radius=radius,
        fill=(0, 0, 0, 165),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(28 * SCALE)))
    canvas.alpha_composite(shadow)

    background = gradient(tile_size, (10, 21, 39), (7, 78, 73)).convert("RGBA")
    canvas.paste(background, (margin, margin), mask)

    # Subtle glow in the top-left and bottom-right.
    glow = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (-tile_size * 0.20, -tile_size * 0.32, tile_size * 0.52, tile_size * 0.42),
        fill=(82, 255, 208, 55),
    )
    glow_draw.ellipse(
        (tile_size * 0.68, tile_size * 0.65, tile_size * 1.25, tile_size * 1.28),
        fill=(36, 150, 255, 38),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(int(62 * SCALE)))
    glow.putalpha(ImageChops.multiply(glow.getchannel("A"), mask))
    canvas.alpha_composite(glow, (margin, margin))

    draw = ImageDraw.Draw(canvas)

    # Display outline.
    left = int(226 * SCALE)
    top = int(286 * SCALE)
    right = int(798 * SCALE)
    bottom = int(660 * SCALE)
    stroke = int(24 * SCALE)
    display_radius = int(58 * SCALE)
    draw.rounded_rectangle(
        (left, top, right, bottom),
        radius=display_radius,
        outline=(207, 255, 238, 255),
        width=stroke,
    )

    # Inner screen tint.
    inner = int(30 * SCALE)
    draw.rounded_rectangle(
        (left + inner, top + inner, right - inner, bottom - inner),
        radius=display_radius - inner // 2,
        fill=(12, 44, 52, 185),
    )

    # Stand.
    stem_width = int(54 * SCALE)
    draw.rounded_rectangle(
        (
            SIZE // 2 - stem_width // 2,
            bottom - int(2 * SCALE),
            SIZE // 2 + stem_width // 2,
            int(714 * SCALE),
        ),
        radius=int(12 * SCALE),
        fill=(207, 255, 238, 255),
    )
    draw.rounded_rectangle(
        (int(390 * SCALE), int(704 * SCALE), int(634 * SCALE), int(741 * SCALE)),
        radius=int(18 * SCALE),
        fill=(207, 255, 238, 255),
    )

    # Play circle.
    center = (SIZE // 2, int(474 * SCALE))
    play_radius = int(118 * SCALE)
    play_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    play_draw = ImageDraw.Draw(play_layer)
    play_draw.ellipse(
        (
            center[0] - play_radius,
            center[1] - play_radius,
            center[0] + play_radius,
            center[1] + play_radius,
        ),
        fill=(64, 235, 170, 255),
    )
    play_layer = play_layer.filter(ImageFilter.GaussianBlur(int(1.5 * SCALE)))
    canvas.alpha_composite(play_layer)
    draw = ImageDraw.Draw(canvas)

    # Play triangle.
    tri_left = center[0] - int(37 * SCALE)
    tri_right = center[0] + int(55 * SCALE)
    tri_top = center[1] - int(62 * SCALE)
    tri_bottom = center[1] + int(62 * SCALE)
    draw.polygon(
        [(tri_left, tri_top), (tri_left, tri_bottom), (tri_right, center[1])],
        fill=(8, 52, 48, 255),
    )

    # Live/awake dot in the upper-right of the display.
    dot_center = (int(744 * SCALE), int(340 * SCALE))
    dot_radius = int(19 * SCALE)
    draw.ellipse(
        (
            dot_center[0] - dot_radius,
            dot_center[1] - dot_radius,
            dot_center[0] + dot_radius,
            dot_center[1] + dot_radius,
        ),
        fill=(112, 255, 202, 255),
    )

    # Thin top highlight on the tile.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.arc(
        (margin + int(34 * SCALE), margin + int(22 * SCALE),
         SIZE - margin - int(34 * SCALE), SIZE - margin - int(22 * SCALE)),
        start=200,
        end=340,
        fill=(255, 255, 255, 55),
        width=int(8 * SCALE),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(int(5 * SCALE)))
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
