#!/usr/bin/env python3
"""Print the dominant readable colour from an image as #rrggbb."""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--threshold", type=int, default=24)
    parser.add_argument("path")
    args = parser.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("sample-accent: Pillow not installed, using theme accent",
              file=sys.stderr)
        return 1

    try:
        img = Image.open(args.path)
        if img.format == "JPEG":
            img.draft("RGB", (64, 64))
        rgb = img.convert("RGB")
    except (FileNotFoundError, OSError) as exc:
        print(f"sample-accent: unreadable image: {exc}", file=sys.stderr)
        return 1

    rgb.thumbnail((64, 64))
    quantized = rgb.quantize(16)
    colors = quantized.getcolors(16 * 16)
    if not colors:
        print("sample-accent: no colours found", file=sys.stderr)
        return 1

    dominant = max(colors, key=lambda item: item[0])[1]
    if isinstance(dominant, int):
        dominant = quantized.getpalette()[dominant * 3:dominant * 3 + 3]
    red, green, blue = dominant
    luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    if luminance < args.threshold or luminance > 255 - args.threshold:
        print("sample-accent: colour rejected by threshold", file=sys.stderr)
        return 1

    print(f"#{red:02x}{green:02x}{blue:02x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
