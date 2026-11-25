"""Render dashboard mockups from docs/preview/src/*.html to PNG.

Requires Playwright:  pip install playwright && playwright install chromium
Usage:               python scripts/make_previews.py
"""

from __future__ import annotations

from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs" / "preview" / "src"
OUT = ROOT / "docs" / "preview"

PAGES = {
    "attendance": (1400, 760),
    "employee": (1400, 760),
    "pipeline": (1400, 760),
}


def main() -> int:
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for name, (width, height) in PAGES.items():
            page = browser.new_page(viewport={"width": width, "height": height})
            page.goto((SRC / f"{name}.html").as_uri())
            page.screenshot(path=str(OUT / f"{name}.png"), full_page=True)
            page.close()
            print("rendered", name)
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
