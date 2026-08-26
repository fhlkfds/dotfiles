from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path


def _pixels(source: Path, width: int, height: int) -> bytes:
    magick = shutil.which("magick")
    if not magick:
        raise RuntimeError("ImageMagick 'magick' is required for PNG/SVG conversion")
    command = [magick, str(source), "-alpha", "remove", "-background", "black", "-colorspace", "Gray",
               "-filter", "Lanczos", "-resize", f"{width}x{height}!", "-depth", "8", "gray:-"]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(f"ImageMagick conversion failed: {detail}")
    expected = width * height
    if len(result.stdout) != expected:
        raise RuntimeError(f"ImageMagick returned {len(result.stdout)} bytes; expected {expected}")
    return result.stdout


def convert_image(source: Path, width: int, height: int, mode: str, threshold: int,
                  invert: bool, glyphs: str = " .:+*#%@") -> str:
    if not source.is_file():
        raise ValueError(f"input image not found: {source}")
    if not 1 <= width <= 500 or not 1 <= height <= 200:
        raise ValueError("width and height must be within 1..500 and 1..200")
    if not 0 <= threshold <= 255:
        raise ValueError("threshold must be within 0..255")
    if mode not in ("blocks", "braille"):
        raise ValueError("mode must be blocks or braille")
    if mode == "blocks":
        pixels = _pixels(source, width, height)
        rows = []
        for y in range(height):
            row = []
            for value in pixels[y * width:(y + 1) * width]:
                value = 255 - value if invert else value
                row.append(" " if value < threshold else glyphs[min(len(glyphs) - 1, value * len(glyphs) // 256)])
            rows.append("".join(row).rstrip())
        return "\n".join(rows).rstrip() + "\n"

    pixel_width, pixel_height = width * 2, height * 4
    pixels = _pixels(source, pixel_width, pixel_height)
    dots = ((0, 0, 1), (0, 1, 2), (0, 2, 4), (1, 0, 8),
            (1, 1, 16), (1, 2, 32), (0, 3, 64), (1, 3, 128))
    rows = []
    for cell_y in range(height):
        row = []
        for cell_x in range(width):
            bits = 0
            for dx, dy, bit in dots:
                value = pixels[(cell_y * 4 + dy) * pixel_width + cell_x * 2 + dx]
                active = value >= threshold
                if invert:
                    active = not active
                if active:
                    bits |= bit
            row.append(chr(0x2800 + bits))
        rows.append("".join(row).rstrip(chr(0x2800)))
    return "\n".join(rows).rstrip() + "\n"


def write_asset(output: Path, text: str, force: bool) -> Path | None:
    output.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    if output.exists():
        if not force:
            raise FileExistsError(f"refusing to overwrite {output}; use --force to create a backup")
        backup = output.with_name(f"{output.name}.bak.{time.strftime('%Y%m%d-%H%M%S')}")
        shutil.copy2(output, backup)
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(output)
    return backup
