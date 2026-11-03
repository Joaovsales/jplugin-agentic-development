"""Capture the three design studies with Playwright and record browser checks."""

import json
from pathlib import Path

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parent
SCREENSHOTS = ROOT / "screenshots"
VIEWPORTS = {"desktop": (1440, 900), "mobile": (390, 844)}


def inspect(page):
    return page.evaluate(
        """() => ({
          title: document.title,
          h1: [...document.querySelectorAll('h1')].map(node => node.innerText),
          width: document.documentElement.scrollWidth,
          viewport: innerWidth,
          anchors: document.querySelectorAll('a[href^="#"]').length,
          canvases: document.querySelectorAll('canvas').length,
          images: [...document.images]
            .filter(image => !image.complete || image.naturalWidth === 0)
            .map(image => image.src)
        })"""
    )


def capture(browser, variant, viewport_name, dimensions):
    page = browser.new_page(
        viewport={"width": dimensions[0], "height": dimensions[1]},
        device_scale_factor=1,
        reduced_motion="reduce",
    )
    errors = []
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" else None)
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto((ROOT / "prototypes" / variant / "index.html").as_uri(), wait_until="load")
    page.wait_for_timeout(900)
    result = {"variant": variant, "viewport": viewport_name, **inspect(page), "errors": errors}
    page.screenshot(path=str(SCREENSHOTS / f"{variant}-{viewport_name}.png"), full_page=True)
    page.close()
    return result


def main():
    SCREENSHOTS.mkdir(exist_ok=True)
    results = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, args=["--no-sandbox"])
        for variant in ("brutalist", "minimalist", "spatial"):
            for viewport_name, dimensions in VIEWPORTS.items():
                results.append(capture(browser, variant, viewport_name, dimensions))
        browser.close()
    (ROOT / "qa-results.json").write_text(json.dumps(results, indent=2) + "\n")
    for result in results:
        assert len(result["h1"]) == 1, result
        assert result["width"] <= result["viewport"], result
        assert not result["images"] and not result["errors"], result
        if result["variant"] == "spatial":
            assert result["canvases"] == 1, result
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
