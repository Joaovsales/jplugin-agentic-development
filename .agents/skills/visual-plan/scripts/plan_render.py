#!/usr/bin/env python3
"""Render a spec's markdown into a self-contained visual plan page.

    plan_render.py <spec.md> -o <out.html>
    plan_render.py --hash <spec.md>      # the 12-character SHA-256 prefix the page shows

The spec is the only content source. Known sections (Summary, Decisions,
Acceptance Criteria, Build Order, Risks, Open questions, ...) become typed
components; every other `##` section renders as generic markdown. A malformed
known section or diagram exits 1 with `<spec>:<line>: <reason>` and writes
nothing. Stdlib only: no network, no diagram library.
"""

import sys

sys.dont_write_bytecode = True  # a render must not leave __pycache__ in the skill

import argparse  # noqa: E402
import os  # noqa: E402

from plan_md import SpecError, parse_document  # noqa: E402
from plan_model import analyse, spec_sha256  # noqa: E402
from plan_page import render_page  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render a spec into a visual plan page.")
    parser.add_argument("spec", help="path to specs/<feature>.md")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("-o", "--output", help="path of the HTML page to write")
    target.add_argument("--hash", action="store_true", help="print the spec's SHA-256 prefix and exit")
    return parser


def read_spec(spec_path: str) -> str:
    with open(spec_path, encoding="utf-8") as fh:
        return fh.read()


def render_file(spec_path: str, out_path: str) -> str:
    """Render spec_path to out_path; raises SpecError before writing anything."""
    text = read_spec(spec_path)
    plan = analyse(parse_document(text), text, spec_path, out_path)
    page = render_page(plan)
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(page)
    return os.path.abspath(out_path)


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):  # a cp1252 console cannot print ✓ or spec text
        stream.reconfigure(encoding="utf-8")
    args = build_parser().parse_args(argv)
    try:
        if args.hash:
            print(spec_sha256(read_spec(args.spec))[:12])
            return 0
        written = render_file(args.spec, args.output)
    except SpecError as err:
        print("%s:%d: %s" % (args.spec, err.line, err.reason), file=sys.stderr)
        return 1
    except OSError as err:
        print("%s: %s" % (args.spec, err), file=sys.stderr)
        return 1
    print("✓ Visual written: %s" % written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
