#!/usr/bin/env python3
"""Snapshot checks for the theme generator's staged output."""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_DIR = ROOT / "hypr/.config/hypr/theme"
THEMES = ROOT / "hypr/.config/hypr/themes"

# Import through the stowed package path, exactly like the desktop scripts do.
sys.path.insert(0, str(THEME_DIR))

import generate  # noqa: E402
import themelib as tl  # noqa: E402


KEY_OUTPUTS = (
    "swaync-style.css",
    "wofi-style.css",
    "quickshell-theme.json",
    "kitty-theme.conf",
    "rofi-theme.rasi",
)
FIXTURE_ENV = "THEME_TEST_FIXTURE_DIR"
SNAPSHOT_ENV = "THEME_TEST_SNAPSHOT_JSON"


def loaded_themes() -> dict[str, tl.Theme]:
    """Stable theme order keeps snapshots and test failures reproducible."""
    return dict(sorted(tl.load_all(THEMES).items()))


def render_all(theme: tl.Theme, root: Path) -> list[Path]:
    stage = root / "stage"
    prefix = root / "prefix"
    stage.mkdir(parents=True)
    prefix.mkdir(parents=True)
    staged = generate.build(theme, stage, prefix)
    outputs = [output for output, destination in staged]
    return outputs


def summary(theme: tl.Theme, outputs: list[Path]) -> dict[str, object]:
    """The stable subset worth snapshotting: identity and rendered bytes."""
    files = {
        output.name: hashlib.sha256(output.read_bytes()[:200]).hexdigest()
        for output in outputs
    }
    return {
        "accent": theme.colors["accent"],
        "mode": theme.mode,
        "warning_count": len(theme.warnings),
        "files": files,
    }


class ThemeGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.themes = loaded_themes()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="theme-generator-test.")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

        # Defend against a template or validator deriving a live XDG path.
        env = {
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
        }
        patcher = unittest.mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        generate.CONFIG_HOME = Path(env["XDG_CONFIG_HOME"])
        generate.CACHE_HOME = Path(env["XDG_CACHE_HOME"])
        generate.WALLPAPER_STATE_FILE = self.root / "state/wallpaper"

    def test_renders_every_theme_into_temporary_stage(self) -> None:
        self.assertGreater(len(self.themes), 0, "theme discovery found nothing")

        for slug, theme in self.themes.items():
            with self.subTest(theme=slug):
                outputs = render_all(theme, self.root / slug)
                self.assertEqual(len(outputs), len(list(generate.targets(self.root))))

                accent = theme.colors["accent"]
                self.assertTrue(accent.startswith("#"))
                for name in KEY_OUTPUTS:
                    output = self.root / slug / "stage" / name
                    self.assertTrue(output.is_file(), f"{name} was not rendered")
                    rendered = output.read_text()
                    self.assertTrue(rendered, f"{name} is empty")
                    self.assertNotIn("{{", rendered, f"{name} has unresolved markers")

                css = (self.root / slug / "stage" / "swaync-style.css").read_text()
                css += (self.root / slug / "stage" / "wofi-style.css").read_text()
                self.assertIn(accent, css)
                self.assertIn(accent[1:], css)

                quickshell = json.loads(
                    (self.root / slug / "stage" / "quickshell-theme.json").read_text()
                )
                self.assertEqual(quickshell["colors"]["accent"], accent)
                for name in ("kitty-theme.conf", "rofi-theme.rasi"):
                    self.assertIn(accent, (self.root / slug / "stage" / name).read_text())

    def test_contrast_warnings_match_palette_metadata(self) -> None:
        for slug, theme in self.themes.items():
            with self.subTest(theme=slug):
                self.assertEqual(tl.check_contrast(theme), theme.warnings)

    def test_low_contrast_theme_reports_instead_of_raising(self) -> None:
        colors = {key: "#000000" for key in tl.REQUIRED_COLORS}
        colors.update(background="#000000", foreground="#111111", surface="#000000")
        ansi = {name: "#111111" for name in tl.REQUIRED_ANSI}
        theme = tl.Theme(
            slug="synthetic-low-contrast",
            name="Synthetic Low Contrast",
            mode="dark",
            description="Fixture for contrast warnings",
            family="synthetic",
            wallpaper=None,
            colors=colors,
            ansi=ansi,
            style=dict(tl.STYLE_DEFAULTS),
        )
        for status, fallback in tl.STATUS_DEFAULTS.items():
            theme.colors[status] = colors[fallback]

        warnings = tl.check_contrast(theme)
        self.assertTrue(warnings)
        self.assertEqual(theme.warnings, [])
        self.assertIn("1.11:1", warnings[0])
        self.assertIn(":1", warnings[0])

        render_all(theme, self.root / "synthetic-low-contrast")

    def test_fixture_or_snapshot_mode(self) -> None:
        fixture_dir = os.environ.get(FIXTURE_ENV)
        snapshot_path = os.environ.get(SNAPSHOT_ENV)
        if not fixture_dir and not snapshot_path:
            self.skipTest("fixture mode disabled")

        rendered = {}
        for slug, theme in self.themes.items():
            outputs = render_all(theme, self.root / slug)
            rendered[slug] = summary(theme, outputs)

        if fixture_dir:
            fixture = Path(fixture_dir) / "theme-generator-snapshots.json"
            fixture.parent.mkdir(parents=True, exist_ok=True)
            fixture.write_text(json.dumps(rendered, indent=2, sort_keys=True) + "\n")
            return

        with open(snapshot_path, encoding="utf-8") as handle:
            expected = json.load(handle)
        self.maxDiff = None
        for slug in sorted(set(rendered) | set(expected)):
            self.assertIn(slug, expected, f"unexpected generated theme: {slug}")
            self.assertIn(slug, rendered, f"snapshot theme not generated: {slug}")
            self.assertEqual(
                rendered[slug], expected[slug], f"snapshot mismatch for {slug}"
            )


if __name__ == "__main__":
    unittest.main()
