#!/usr/bin/env python3
"""Drive rendered visual plans in a real browser and write screenshots.

Usage: check_plan_page.py <dir> --shots <dir> [--channel msedge]

Serves <dir> on a loopback port (clipboard and storage need a real origin),
opens every `*.plan.html` in it at 1440 and 390 px in light and dark, and checks
the page's behaviour: disclosures, keyboard, deep links, the mobile menu, the
prompt copy, the source link, the review export, console errors and overflow.
Silent on success apart from one summary line; every failure is printed as
`<page> <viewport> <theme>: <problem>` and the exit code is 1. Needs the
`playwright` package; exits 3 when it is missing so the caller can SKIP loudly.
"""

import argparse
import functools
import http.server
import sys
import threading
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

sys.dont_write_bytecode = True

try:
    from playwright.sync_api import sync_playwright
except ImportError:  # the caller decides whether a missing browser is a failure
    print("check_plan_page: the playwright package is not installed", file=sys.stderr)
    sys.exit(3)

VIEWPORTS = {"1440": (1440, 900), "390": (390, 844)}
# records the text each clipboard write is handed, then writes it as usual
RECORD_COPY = """(() => { const c = navigator.clipboard; if (!c) return; const w = c.writeText.bind(c);
  c.writeText = (t) => { window.__planCopied = t; return w(t); }; })();"""
THEMES = ("light", "dark")


class Quiet(http.server.SimpleHTTPRequestHandler):
    """Static files without access logs; the favicon request a browser makes on
    its own gets an empty answer, as it would never be made for a file opened from disk."""

    def log_message(self, *args) -> None:
        pass

    def do_GET(self) -> None:
        if self.path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()


def serve(root: Path):
    handler = functools.partial(Quiet, directory=str(root))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class View:
    """One page at one viewport in one theme; collects problems instead of raising."""

    def __init__(self, context, url: str, root: Path, label: str):
        self.page, self.url, self.root, self.label = context.new_page(), url, root, label
        self.problems, self.errors = [], []
        self.page.on("console", lambda m: self.errors.append(m.text) if m.type == "error" else None)
        self.page.on("pageerror", lambda e: self.errors.append(str(e)))
        self.page.goto(url, wait_until="load")

    def expect(self, ok: bool, problem: str) -> None:
        if not ok:
            self.problems.append("%s: %s" % (self.label, problem))

    def js(self, script: str, arg=None):
        return self.page.evaluate(script, arg)


def check_layout(v: View) -> None:
    v.expect(v.js("document.querySelectorAll('h1').length") == 1, "the page has more or fewer than one h1")
    width = v.js("[document.documentElement.scrollWidth, innerWidth]")
    v.expect(width[0] <= width[1], "page overflows horizontally (%d > %d px)" % tuple(width))


def check_disclosures(v: View) -> None:
    v.page.click('button[data-action="expand"]')
    v.expect(v.js("[...document.querySelectorAll('main details')].every(d => d.open)"), "Expand all left a disclosure closed")
    v.page.click('button[data-action="collapse"]')
    v.expect(v.js("[...document.querySelectorAll('main details')].every(d => !d.open)"), "Collapse all left a disclosure open")


def check_keyboard(v: View) -> None:
    v.page.goto(v.url, wait_until="load")  # a fresh load: earlier checks moved focus
    v.page.keyboard.press("Tab")
    v.expect(v.js("document.activeElement.classList.contains('skip')"), "the first Tab stop is not the skip link")
    summary = v.page.locator("main details > summary").first
    if summary.count():
        before = v.js("document.querySelector('main details').open")
        summary.focus()
        v.page.keyboard.press("Enter")
        after = v.js("document.querySelector('main details').open")
        v.expect(before != after, "Enter on a summary does not toggle its disclosure")


def check_deep_link(v: View) -> None:
    target = v.js("""(() => { const d = document.querySelector('main details:not([open]) [id]');
                      return d ? d.id : null; })()""")
    if not target:
        return
    v.page.goto(v.url + "#" + target, wait_until="load")
    v.expect(v.js("(id) => { let n = document.getElementById(id).parentElement.closest('details');"
                  " while (n) { if (!n.open) return false; n = n.parentElement.closest('details'); } return true; }",
                  target), "deep link #%s left its section collapsed" % target)
    v.page.goto(v.url, wait_until="load")


def check_menu(v: View) -> None:
    if v.page.viewport_size["width"] >= 768:
        v.expect(v.js("document.querySelector('.toc-menu').open"), "the contents menu is closed on a wide screen")
        return
    v.expect(not v.js("document.querySelector('.toc-menu').open"), "the mobile contents menu starts open")
    v.page.click(".toc-menu > summary")
    v.page.locator(".toc a").last.click()
    v.expect(not v.js("document.querySelector('.toc-menu').open"), "choosing a contents link does not close the mobile menu")
    v.page.goto(v.url, wait_until="load")


def check_prompt(v: View) -> None:
    button = v.page.locator('button.copy[data-copy-from="build-prompt-text"]')
    if not button.count():
        return
    if button.is_disabled():
        v.expect(v.js("document.querySelector('.card-prompt').classList.contains('not-ready')"),
                 "copy is disabled but the panel does not say it is not ready")
        return
    v.js("document.querySelectorAll('details').forEach(d => d.open = true)")
    button.click()
    # What the page hands the clipboard, not what the OS reads back: Windows turns LF into CRLF.
    copied = v.js("window.__planCopied")
    v.expect(copied == v.js("document.getElementById('build-prompt-text').textContent"),
             "Copy build prompt did not copy the prompt text exactly")
    v.page.wait_for_timeout(100)
    v.expect(button.text_content() == "Copied", "Copy build prompt did not report the copy (%r)" % button.text_content())


def check_source(v: View) -> None:
    href = v.js("document.querySelector('.source a') && document.querySelector('.source a').getAttribute('href')")
    v.expect(bool(href), "the header has no source link")
    if href:
        path = v.root / unquote(urlparse(urljoin(v.url, href)).path).lstrip("/")
        v.expect(path.is_file(), "the source link %s does not resolve to the spec" % href)


def check_review(v: View) -> None:
    first = v.page.locator(".review[data-review]").first
    if not first.count():
        return
    item = first.get_attribute("data-review")
    v.js("document.querySelectorAll('details').forEach(d => d.open = true)")
    first.locator('button[data-mark="ok"]').click()
    v.page.click('button[data-action="export-review"]')
    text = v.js("document.getElementById('review-export').textContent")
    v.expect(text.startswith("Review of ") and ("\n%s: ok" % item) in text, "Export review did not list %s: ok" % item)
    v.expect(v.js("Object.keys(localStorage).some(k => k.startsWith('jplugin-plan-review:'))"), "review marks were not stored")
    v.js("localStorage.clear()")


CHECKS = (check_layout, check_disclosures, check_keyboard, check_deep_link, check_menu, check_prompt,
          check_source, check_review)


def check_view(browser, base: str, page: Path, root: Path, size: str, theme: str, shots: Path):
    w, h = VIEWPORTS[size]
    context = browser.new_context(viewport={"width": w, "height": h}, color_scheme=theme,
                                  reduced_motion="reduce", permissions=["clipboard-read", "clipboard-write"])
    context.add_init_script(RECORD_COPY)
    view = View(context, base + page.name, root, "%s %s %s" % (page.name, size, theme))
    view.page.screenshot(path=str(shots / ("%s-%s-%s.png" % (page.stem.replace(".plan", ""), size, theme))), full_page=True)
    for check in CHECKS:
        check(view)
    view.expect(not view.errors, "console errors: %s" % "; ".join(view.errors[:3]))
    context.close()
    return view.problems


def check_pages(pages, args) -> list:
    """Every page at every viewport and theme, served from args.root; the problems found."""
    server = serve(args.root)
    base = "http://127.0.0.1:%d/" % server.server_address[1]
    problems = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel=args.channel)
        for page in pages:
            for size in VIEWPORTS:
                for theme in THEMES:
                    problems += check_view(browser, base, page, args.root, size, theme, args.shots)
        browser.close()
    server.shutdown()
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="Check rendered visual plans in a browser.")
    parser.add_argument("root", type=Path)
    parser.add_argument("--shots", type=Path, required=True)
    parser.add_argument("--channel", default=None, help="browser channel, e.g. msedge or chrome")
    args = parser.parse_args()
    pages = sorted(args.root.glob("*.plan.html"))
    if not pages:
        print("check_plan_page: no *.plan.html in %s" % args.root, file=sys.stderr)
        return 1
    args.shots.mkdir(parents=True, exist_ok=True)
    problems = check_pages(pages, args)
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print("✓ Checked %d views of %d pages; screenshots in %s" % (len(pages) * 4, len(pages), args.shots))
    return 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")
    sys.exit(main())
