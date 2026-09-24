"""The lane catalogue — one markdown file per lane, read by both routers.

A **lane** is what an agent runs next. The scheduled router reaches one through
an issue's kind label (`task-registry workflow`); the interactive router reaches
one through a goal in plain words (`/go`). Both used to hold their own copy of
the answer — routine constants transcribed into `config.py`, playbooks under the
`/go` skill — and the one lane they shared was pinned equal by a test because
nothing else kept it so. specs/lane-catalogue.md makes the file the source: the
frontmatter carries what the registry reads, the numbered steps carry what `/go`
records, and the chain is *derived* from the steps rather than declared beside
them, so there is no second statement to drift.

The grammar is the whole interface between prose and machine, so it is small:

* The **name is the filename stem** — `lanes/fix.md` defines `fix`.
* Frontmatter is `key: value` lines between `---` fences; lists are comma
  separated. Five keys, all optional but `ends`.
* A **step** is a line `N. text` at column 0, numbered from 1 without gaps,
  one line each — an indented line right after a step is refused, not
  silently dropped from the playbook.
* A step whose text opens with a backticked skill (`` `/name`` …) is a **skill
  step** unless it ends with ` — optional`; every other step is **inline**. The
  **chain** is the skill steps' names in order.
* A lane is a routine (`routine:` set), interactive (`cues:` set), or both.
  One with neither is reachable by no router and is refused.
* A `## Reply` section is required — `/go` copies it as what the lane ends
  with, so an empty one would be recorded as evidence.

Loading is lazy. Nothing here runs at import; `catalogue()` reads the shipped
directory on first call and memoises. A lane that breaks a rule raises
:class:`LaneCatalogueError`, a :class:`ConfigError`, so it takes the path every
command already has for a broken configuration — and `doctor`, which loads
non-strictly, can still run and name the file.
"""

from __future__ import annotations

import functools
import os
import re
from dataclasses import dataclass
from typing import Dict, Mapping, NoReturn, Optional, Sequence, Tuple

from .config import TERMINAL_ROUTINE_SKILL, ConfigError

__all__ = [
    "Lane",
    "LaneCatalogue",
    "LaneCatalogueError",
    "SHIPPED_LANES_DIR",
    "catalogue",
    "load_catalogue",
]

#: The directory shipped beside this package. Package data, not project
#: configuration: a project changes a routine's chain through
#: `[routines.skills]`, never by editing these files.
SHIPPED_LANES_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lanes")
)

ROUTINE_KINDS = ("consumer", "producer")
FRONTMATTER_KEYS = ("routine", "selects", "cues", "ends", "deferred")
OPTIONAL_SUFFIX = "— optional"

_STEM_RE = re.compile(r"^[a-z][a-z-]*$")
_STEP_RE = re.compile(r"^(\d+)\. (.*\S)\s*$")
_HEAD_SKILL_RE = re.compile(r"^`(/[a-z][a-z0-9-]*)(?:[ `]|$)")
#: A non-blank line indented under a step: a wrapped step, which the grammar
#: refuses rather than truncates.
_CONTINUATION_RE = re.compile(r"^[ \t]+\S")
_CHECKBOX_RE = re.compile(r"^\s*-?\s*\[[ ~x]\]")
_REPLY_RE = re.compile(r"^## Reply\s*$", re.MULTILINE)


class LaneCatalogueError(ConfigError):
    """A shipped lane file cannot be read as a lane. Names the file."""


@dataclass(frozen=True)
class Lane:
    """One lane, exactly as its file states it."""

    name: str
    ends: str
    steps: Tuple[str, ...]
    chain: Tuple[str, ...]
    reply: str
    routine: Optional[str] = None
    selects: Tuple[str, ...] = ()
    cues: str = ""
    deferred: str = ""

    @property
    def is_routine(self) -> bool:
        return self.routine is not None

    @property
    def is_interactive(self) -> bool:
        return bool(self.cues)


@dataclass(frozen=True)
class LaneCatalogue:
    """Every lane, and the views the two routers read.

    The views are what `config.py` used to hold as literals. Each is derived
    here, once, so a reader of any one of them is reading the lane files.
    """

    lanes: Mapping[str, Lane]

    def lane(self, name: str) -> Lane:
        """The lane called `name`, or a KeyError naming the known lanes."""
        try:
            return self.lanes[name]
        except KeyError:
            raise KeyError(
                f"no lane named {name!r}; known lanes: {', '.join(self.names)}"
            ) from None

    @property
    def names(self) -> Tuple[str, ...]:
        return tuple(sorted(self.lanes))

    @property
    def routines(self) -> Tuple[str, ...]:
        """Names the scheduler may run — the contract routines."""
        return tuple(name for name in self.names if self.lanes[name].is_routine)

    @property
    def producers(self) -> Tuple[str, ...]:
        return tuple(name for name in self.names if self.lanes[name].routine == "producer")

    @property
    def deferred(self) -> Mapping[str, str]:
        return {name: self.lanes[name].deferred for name in self.names if self.lanes[name].deferred}

    @property
    def selectors(self) -> Mapping[str, Tuple[str, ...]]:
        """Consumer name -> the labels it selects. A consumer without labels is absent."""
        return {
            name: self.lanes[name].selects
            for name in self.names
            if self.lanes[name].routine == "consumer" and self.lanes[name].selects
        }

    @property
    def chains(self) -> Mapping[str, Tuple[str, ...]]:
        """Consumer name -> chain: the domain `[routines.skills]` configures.

        Producers are deliberately outside it. Their chain is read through
        `lane(name).chain` and is not project-configurable, which is also why a
        `[routines.skills]` key naming one is refused as unknown.
        """
        return {
            name: self.lanes[name].chain
            for name in self.names
            if self.lanes[name].routine == "consumer"
        }

    @property
    def interactive(self) -> Tuple[Lane, ...]:
        """Lanes with cues — the rows `/go` matches a goal against."""
        return tuple(self.lanes[name] for name in self.names if self.lanes[name].is_interactive)


@functools.lru_cache(maxsize=None)
def catalogue() -> LaneCatalogue:
    """The shipped catalogue, read once. Raises LaneCatalogueError, never at import."""
    return load_catalogue(SHIPPED_LANES_DIR)


def load_catalogue(directory: str) -> LaneCatalogue:
    """Every `*.md` under `directory` as a catalogue, or the first refusal."""
    if not os.path.isdir(directory):
        raise LaneCatalogueError(f"lane catalogue: {directory} is not a directory")
    lanes: Dict[str, Lane] = {}
    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".md"):
            continue
        lane = _read_lane(os.path.join(directory, entry))
        lanes[lane.name] = lane
    if not lanes:
        raise LaneCatalogueError(f"lane catalogue: {directory} holds no lane files")
    return LaneCatalogue(lanes)


def _read_lane(path: str) -> Lane:
    name = os.path.splitext(os.path.basename(path))[0]
    refuse = _Refuser(path)
    if not _STEM_RE.match(name):
        refuse("the filename stem must match [a-z][a-z-]*")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read().replace("\r\n", "\n")
    front, body = _split_frontmatter(text, refuse)
    steps = _steps(body, refuse)
    lane = Lane(
        name=name,
        ends=front.get("ends", ""),
        steps=steps,
        chain=_chain(steps),
        reply=_reply(body, refuse),
        routine=front.get("routine") or None,
        selects=_csv(front.get("selects")),
        cues=front.get("cues", ""),
        deferred=front.get("deferred", ""),
    )
    _validate(lane, refuse)
    return lane


class _Refuser:
    """Raises LaneCatalogueError with the file already named, so rules stay one line."""

    def __init__(self, path: str) -> None:
        self.path = path

    def __call__(self, reason: str) -> NoReturn:
        raise LaneCatalogueError(f"lane catalogue: {self.path}: {reason}")


def _split_frontmatter(text: str, refuse) -> Tuple[Dict[str, str], str]:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        refuse("must open with a --- frontmatter fence")
    try:
        close = lines.index("---", 1)
    except ValueError:
        refuse("frontmatter fence is never closed")
    front: Dict[str, str] = {}
    for line in lines[1:close]:
        if not line.strip():
            continue
        key, separator, value = line.partition(":")
        key = key.strip()
        if not separator or key not in FRONTMATTER_KEYS:
            refuse(
                f"unknown frontmatter line {line.strip()!r}; "
                f"keys are {', '.join(FRONTMATTER_KEYS)}"
            )
        front[key] = value.strip()
    return front, "\n".join(lines[close + 1:])


def _steps(body: str, refuse) -> Tuple[str, ...]:
    steps = []
    previous_was_step = False
    for line in body.split("\n"):
        if _CHECKBOX_RE.match(line):
            refuse(f"checkbox row {line.strip()!r} — /build dispatches every [ ] row it finds")
        if previous_was_step and _CONTINUATION_RE.match(line):
            refuse(
                f"step {len(steps)} wraps onto {line.strip()!r} — a step is one line; "
                "a wrapped tail would vanish from the playbook and the chain"
            )
        match = _STEP_RE.match(line)
        previous_was_step = bool(match)
        if not match:
            continue
        number, text = int(match.group(1)), match.group(2)
        if number != len(steps) + 1:
            refuse(f"step {number} follows step {len(steps)} — steps are numbered from 1 without gaps")
        steps.append(text)
    if not steps:
        refuse("no numbered steps")
    return tuple(steps)


def _chain(steps: Sequence[str]) -> Tuple[str, ...]:
    chain = []
    for text in steps:
        if text.rstrip().endswith(OPTIONAL_SUFFIX):
            continue
        match = _HEAD_SKILL_RE.match(text)
        if match:
            chain.append(match.group(1))
    return tuple(chain)


def _reply(body: str, refuse) -> str:
    match = _REPLY_RE.search(body)
    if not match:
        refuse("no `## Reply` section — /go records it as what the lane ends with")
    return body[match.end():].strip("\n")


def _csv(value: Optional[str]) -> Tuple[str, ...]:
    return tuple(item.strip() for item in (value or "").split(",") if item.strip())


def _validate(lane: Lane, refuse) -> None:
    if not lane.ends:
        refuse("`ends:` is required — every lane names what it ends with")
    if lane.routine is not None and lane.routine not in ROUTINE_KINDS:
        refuse(f"routine: {lane.routine!r} — must be one of {', '.join(ROUTINE_KINDS)}")
    if lane.selects and lane.routine != "consumer":
        refuse("`selects:` is allowed only with `routine: consumer` — only a consumer selects issues")
    if lane.deferred and lane.routine is None:
        refuse("`deferred:` is allowed only on a routine lane — an interactive lane is never scheduled")
    if not lane.is_routine and not lane.is_interactive:
        refuse(
            "a lane is a routine (`routine:`), interactive (`cues:`), or both — "
            "one with neither is reachable by no router"
        )
    # The review gate whose omission shipped #93 green; `config` enforces the
    # same rule on a project's declared chains, from the same constant.
    if lane.is_routine and (not lane.chain or lane.chain[-1] != TERMINAL_ROUTINE_SKILL):
        refuse(
            f"a routine lane's chain must end at {TERMINAL_ROUTINE_SKILL}; this one is "
            f"{' -> '.join(lane.chain) or 'empty'}"
        )
