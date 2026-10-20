"""Review controls on every reviewable card, and the export panel that collects them.

The markup is static; plan_page.js restores and saves the marks in localStorage
under a key holding the spec's SHA-256 prefix, and composes the export block
`/plan`'s change-request path applies.
"""

import os
import re
from typing import List, Tuple

from plan_md import esc, plain
from plan_model import Plan

LETTERS = "ABCDEFGHIJ"
LETTERED = re.compile(r"(?:^|\s)\(?([A-J])[).:]\s*")


def option_labels(cell: str) -> List[str]:
    """The options a decision lists, in order: `A) x B) y` or `x, y` / `x; y` / `x or y`."""
    text = plain(cell).strip()
    if LETTERED.search(text):
        parts = LETTERED.split(text)[1:]
        return [parts[i + 1].strip(" ,;") for i in range(0, len(parts) - 1, 2)]
    parts = [p.strip() for p in re.split(r"\s*(?:,|;|\bor\b|\bvs\.?)\s*", text) if p.strip()]
    return parts if len(parts) > 1 else []


def _picker(item_id: str, options: str) -> str:
    labels = option_labels(options)
    if not labels:
        return '<label>Pick <input data-field="pick" aria-label="%s pick"></label>' % esc(item_id)
    choices = "".join('<option value="%s">%s — %s</option>' % (LETTERS[i], LETTERS[i], esc(lbl))
                      for i, lbl in enumerate(labels[:len(LETTERS)]))
    return '<label>Pick <select data-field="pick" aria-label="%s pick"><option value="">not picked</option>%s</select></label>' % (
        esc(item_id), choices)


def review_controls(item_id: str, answer: bool = False, pick_from: str = None) -> str:
    """ok / questioned with a note; an answer field for questions, a picker for open decisions."""
    ident = esc(item_id)
    extra = ""
    if answer:
        extra = '<label>Answer <input data-field="answer" aria-label="%s answer"></label>' % ident
    elif pick_from is not None:
        extra = _picker(item_id, pick_from)
    return ('<div class="review" data-review="%s" role="group" aria-label="Review %s">'
            '<button type="button" data-mark="ok" aria-pressed="false">ok</button>'
            '<button type="button" data-mark="questioned" aria-pressed="false">questioned</button>'
            '%s<label>Note <textarea data-field="note" rows="1" aria-label="%s note"></textarea></label></div>'
            % (ident, ident, extra, ident))


def review_attrs(plan: Plan) -> Tuple[str, str]:
    return plan.spec_path.replace(os.sep, "/"), plan.short_sha


def render_review_panel(plan: Plan) -> str:
    spec, sha = review_attrs(plan)
    return ('<section class="review-panel" id="review" aria-labelledby="review-h" data-spec="%s" data-sha="%s">'
            '<h2 id="review-h">Review</h2>'
            '<p class="meta">Mark cards ok or questioned, answer questions and pick open decisions, then '
            'paste the export into the planning session: <code>/plan</code> applies it and re-runs <code>/slice</code>.</p>'
            '<p class="review-status" id="review-status" role="status">Marks are saved in this browser for sha256 %s.</p>'
            '<button type="button" class="btn" data-action="export-review">Export review</button>'
            '<pre><code id="review-export"></code></pre></section>' % (esc(spec), esc(sha), esc(sha)))
