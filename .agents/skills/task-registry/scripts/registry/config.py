"""Project configuration contract and provider selection.

Configuration is a documented file in the project, not flags on a command line,
so every skill and every agent resolves the same tracker without being told. The
file is `docs/task-tracking.md` by default, or wherever a
`Task tracking instructions: <path>` pointer in the project instructions says.

Selection precedence (spec AC-3):

  1. explicit `provider =` in the configuration
  2. GitHub, when a GitHub remote and an authenticated `gh` both exist
  3. local Markdown

Jira is never selected implicitly. Being reachable is not consent to write to a
company tracker.
"""

from __future__ import annotations

import configparser
import io
import os
import re
import subprocess
import urllib.parse
from dataclasses import dataclass, field
from typing import Dict, List, Mapping, Optional, Sequence, Tuple

CONFIG_DEFAULT_PATH = "docs/task-tracking.md"
CONFIG_TEMPLATE_PATH = ".agents/skills/task-registry/templates/task-tracking.md"
#: Searched in order, first hit wins. Project-owned files come first: `.claude/
#: project.md` and `AGENTS.md` are written by the team, while `CLAUDE.md` is
#: template-managed and overwritten by `/sync` — a pointer there is the least
#: authoritative statement of where this project keeps its tracking config.
POINTER_FILES = (".claude/project.md", "AGENTS.md", "CLAUDE.md")
POINTER_RE = re.compile(r"Task tracking instructions:\s*([^\s`<>]+)", re.IGNORECASE)
_FENCE_RE = re.compile(r"```(?:ini|cfg|conf|toml)\s*\n(.*?)```", re.DOTALL)

PROVIDERS = ("github", "jira", "local")

#: Operator-held escape hatches. Both live in the environment rather than in the
#: configuration file on purpose: a checked-in file is content, and content must
#: not be able to lower a safety floor for everyone who clones the repository.
TRUSTED_CONFIG_ENV = "TASK_REGISTRY_TRUSTED_CONFIG"
INSECURE_TRANSPORT_ENV = "TASK_REGISTRY_ALLOW_INSECURE_TRANSPORT"

_LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1", "[::1]")

#: GitHub label vocabulary this harness already ships, mapped read-only. The
#: mapping is a *reading* of provider-facing vocabulary; it never renames or
#: replaces a label. `question` is deliberately absent — it is ambiguous between
#: `decision` and `research`, so it maps only when a project configures it.
DEFAULT_KIND_LABELS: Mapping[str, str] = {
    "bug": "bug",
    "enhancement": "feature",
    "design-decision": "decision",
}
#: Deliberately NOT extended with the routine precedence labels. This map is
#: bidirectional: the GitHub provider reverse-looks-up `kind -> first label` to
#: decide what to stamp on a published issue (`_mapped_labels`). Adding
#: `tech-debt: task` therefore labelled EVERY published task `tech-debt` -- which
#: is the `fix` routine's own selector, so the registry would have been feeding
#: issues to a routine by writing them. Routine selection never reads this map;
#: it reads DEFAULT_SELECTORS and DEFAULT_KIND_PRECEDENCE below.

DEFAULT_PRIORITY_LABELS: Mapping[str, str] = {"now": "high", "next": "medium"}

#: Routine -> the provider label names it selects. One label axis, disjoint sets:
#: `now`/`next` are the PRIORITY axis and order candidates *within* a pool, so
#: they never appear here. Selecting on both axes gave two routines a claim on
#: one issue in a third of all cases, which is what made selection partial.
#:
#: `build` is deliberately absent. It is deferred behind the `blockedBy` provider
#: capability (#97) and the routine itself (#98), and a selector shipped for a
#: routine nobody runs would let a deferred capability fail a live gate.
DEFAULT_SELECTORS: Mapping[str, Tuple[str, ...]] = {
    "plan": ("design-decision",),
    "fix": ("bug", "tech-debt"),
    "improve": ("enhancement", "documentation"),
}

#: First match wins. This orders the LABEL keys of `[labels.kind]`, not canonical
#: kinds: `tech-debt` and `documentation` both normalize to `task`, so a chain
#: over kinds could not tell them apart and could not rank them.
DEFAULT_KIND_PRECEDENCE: Tuple[str, ...] = (
    "bug",
    "design-decision",
    "tech-debt",
    "enhancement",
    "documentation",
)

#: What each routine RUNS, once selection has told it which issue to run on.
#: Transcribed from `references/routines.md` -- step 4 of each routine plus the
#: shared spine's step 5, which is why every chain ends at `/wrap-up-session`.
#: That document is the routine contract; a chain invented here instead would be
#: a second, unversioned answer to a question it already answers.
#:
#: `plan` deliberately omits `/build` and `/quality-gate`: it produces a spec and
#: no implementation, so requiring them would write a `skip:` row on every run.
#: `build` is listed though it is deferred (#97/#98) -- `workflow` must be able to
#: say "this routine exists and is deferred", which it cannot do for a routine it
#: has no chain for.
DEFAULT_ROUTINE_SKILLS: Mapping[str, Tuple[str, ...]] = {
    "plan": ("/plan", "/wrap-up-session"),
    "fix": ("/debug", "/build", "/quality-gate", "/wrap-up-session"),
    "improve": ("/plan", "/build", "/quality-gate", "/wrap-up-session"),
    "build": ("/build", "/quality-gate", "/wrap-up-session"),
}

#: The step every chain must end on. `/wrap-up-session` is the review gate whose
#: omission shipped #93 green, and `references/routines.md` marks it
#: "non-skippable for every routine without exception".
TERMINAL_ROUTINE_SKILL = "/wrap-up-session"

#: Where a chain's skills are looked for. Both trees are pinned byte-identical by
#: tests/test-skill-parity.sh, and a project may carry only the Claude Code copy.
SKILL_ROOTS = (".agents/skills", ".claude/skills")

#: Written before a routine branches, and skipped when already present.
DEFAULT_CLAIM_LABEL = "in-progress"
#: The routine names the contract defines. `build` is deferred (#97/#98) but is a
#: contract routine, so configuring selectors for it is legal.
#: Kept in step with `references/routines.md` by tests/test-routine-selectors.sh --
#: `routine_branch.format_routine_branch` refuses anything outside this set, and
#: without the check here a project learns that at spine step 3, mid-run.
CONTRACT_ROUTINES = ("plan", "fix", "improve", "build")

#: Jira's own vocabulary, read the same way: provider-facing names mapped into
#: the normalized model, never the other way round as a rename.
DEFAULT_JIRA_ISSUE_TYPES: Mapping[str, str] = {
    "Bug": "bug",
    "Story": "feature",
    "Task": "task",
    "Sub-task": "task",
    "Epic": "epic",
    "Spike": "research",
}

DEFAULT_JIRA_PRIORITIES: Mapping[str, str] = {
    "Highest": "high",
    "High": "high",
    "Medium": "medium",
    "Low": "low",
    "Lowest": "low",
}


class ConfigError(Exception):
    """The configuration exists but cannot be read as configuration."""


class ConfigPointerError(ConfigError):
    """A project-instruction pointer names a configuration file that cannot be used.

    Missing target or a target outside the project root. Kept distinct from a
    malformed file because `doctor` reports it on the `configuration:` line —
    there is no loaded file for a routines fault to belong to.
    """


class Secret:
    """A credential that refuses to render itself.

    Redaction is a property of the value, not a discipline asked of every call
    site that might interpolate it into a message.
    """

    __slots__ = ("_value",)

    def __init__(self, value: str = "") -> None:
        self._value = value or ""

    def reveal(self) -> str:
        return self._value

    def __bool__(self) -> bool:
        return bool(self._value)

    def __repr__(self) -> str:  # pragma: no cover - trivial
        return "Secret(***)"

    __str__ = __repr__


@dataclass(frozen=True)
class Config:
    """Everything the registry needs to know about this project's tracking."""

    root: str
    provider: Optional[str] = None
    repository: str = ""
    project: str = ""
    index_path: str = "tasks/todo.md"
    backlog_path: str = "tasks/backlog.md"
    spec_dir: str = "specs"
    local_detail_dir: str = "tasks/details"
    dependency_strategy: str = "auto"
    #: Heading that marks a plan block finished, so its open rows read as stale.
    closed_plan_marker: str = "Session Summary"
    require_write_approval: bool = True
    allow_label_creation: bool = False
    offline_reads: str = "degrade"
    migration_policy: str = "manual"
    #: Label a routine writes before it starts, and skips when it is already
    #: present. Disjoint selectors stop two *different* routines claiming one
    #: issue; only this stops two runs of the same routine overlapping.
    claim_label: str = DEFAULT_CLAIM_LABEL
    #: Provider label names in first-match-wins order, and the routine each is
    #: selected by. Read here rather than hardcoded in a skill: the halt that
    #: motivated this design was a label that had never been created.
    kind_precedence: Sequence[str] = DEFAULT_KIND_PRECEDENCE
    routine_skills: Mapping[str, Sequence[str]] = field(
        default_factory=lambda: dict(DEFAULT_ROUTINE_SKILLS)
    )
    #: Whether `[routines.skills]` was written by the project. The on-disk skill
    #: check reads it: a project is answerable for the chain it declared, while a
    #: shipped default names skills from this template and is pinned by
    #: tests/test-routine-skills.sh instead. Without the distinction, a checkout
    #: carrying the registry but not the rest of the harness could load no
    #: configuration at all.
    routine_skills_declared: bool = False
    routine_selectors: Mapping[str, Sequence[str]] = field(
        default_factory=lambda: dict(DEFAULT_SELECTORS)
    )
    kind_labels: Mapping[str, str] = field(default_factory=lambda: dict(DEFAULT_KIND_LABELS))
    priority_labels: Mapping[str, str] = field(
        default_factory=lambda: dict(DEFAULT_PRIORITY_LABELS)
    )
    status_sources: Mapping[str, str] = field(default_factory=dict)
    jira_issue_types: Mapping[str, str] = field(
        default_factory=lambda: dict(DEFAULT_JIRA_ISSUE_TYPES)
    )
    jira_priorities: Mapping[str, str] = field(
        default_factory=lambda: dict(DEFAULT_JIRA_PRIORITIES)
    )
    source_path: Optional[str] = None
    jira_base_url: str = ""
    jira_email: str = ""
    jira_token: Secret = field(default_factory=Secret)
    #: True when the configuration asked to drop the approval requirement and the
    #: operator had not opted in. Surfaced by `doctor` so the refusal is visible.
    approval_relaxation_ignored: bool = False

    def path(self, relative: str) -> str:
        """Resolve a configured path, refusing anything outside the project root.

        Every path in the configuration comes from a file in the repository, so a
        pull request could otherwise point `local_detail_dir` at `../../.ssh` and
        have the registry write there on the next `publish --apply`.
        """
        return confine(self.root, relative, "configured path")

    @property
    def is_configured(self) -> bool:
        return self.source_path is not None


def confine(root: str, relative: str, what: str) -> str:
    """Absolute path for `relative` under `root`, or ConfigError if it escapes."""
    resolved = os.path.realpath(os.path.join(root, relative))
    anchor = os.path.realpath(root)
    if resolved != anchor and not resolved.startswith(anchor + os.sep):
        raise ConfigError(
            f"{what} {relative!r} resolves outside the project root — refusing to use it"
        )
    return resolved


def is_secure_transport(base_url: str) -> bool:
    """HTTPS, or plain HTTP to loopback where there is no network to sniff."""
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme == "https":
        return True
    return parsed.scheme == "http" and parsed.hostname in _LOOPBACK_HOSTS


def require_secure_transport(base_url: str, env: Mapping[str, str]) -> None:
    """Refuse to send credentials in the clear.

    Basic auth over http puts the token on the wire in every request. The opt-out
    is an environment variable rather than a config key for the reason in
    :data:`TRUSTED_CONFIG_ENV`.
    """
    if is_secure_transport(base_url) or _as_bool(env.get(INSECURE_TRANSPORT_ENV), False):
        return
    raise ConfigError(
        "jira: refusing to send credentials over an insecure transport — "
        f"set an https:// base URL, or export {INSECURE_TRANSPORT_ENV}=1 to override"
    )


def _as_bool(value: str, default: bool) -> bool:
    if value is None or str(value).strip() == "":
        return default
    return str(value).strip().lower() in ("1", "true", "yes", "on", "required")


def find_config_path(root: str) -> Optional[str]:
    """Resolve the configuration document, following a project-instruction pointer.

    Three states, and only the first is silent:

      * no pointer anywhere — the default path when present, else None;
      * a pointer whose target exists — that file;
      * a pointer whose target is missing or escapes the root — ConfigPointerError.

    The third is a declared intent with a broken target. Folding it into the
    first made a project run on defaults while its own instructions said it was
    configured, and nothing said so (#82). The first pointer found wins, broken
    or not: a dangling `.claude/project.md` pointer is not rescued by a valid
    `CLAUDE.md` one, because the most authoritative declaration is the wrong one.
    """
    for pointer_file in POINTER_FILES:
        declared = _declared_pointer(root, pointer_file)
        if declared is None:
            continue
        # The pointer is read out of a repository file, so it is untrusted
        # input: `Task tracking instructions: ../../etc/shadow` is echoed back
        # in the refusal, never opened.
        try:
            candidate = confine(root, declared, "task tracking pointer")
        except ConfigError as exc:
            raise ConfigPointerError(f"{pointer_file}: {exc}") from exc
        if not os.path.isfile(candidate):
            # ``!r`` matches ``confine``: the pointer is repository text, so it is
            # echoed escaped, never raw, to a terminal or an agent's context.
            state = "exists but is not a file" if os.path.exists(candidate) else "does not exist"
            raise ConfigPointerError(
                f"{pointer_file} declares `Task tracking instructions: {declared!r}`, "
                f"but {declared!r} {state} — create it from {CONFIG_TEMPLATE_PATH}, "
                "or remove the pointer"
            )
        return candidate
    default = os.path.join(root, CONFIG_DEFAULT_PATH)
    return default if os.path.isfile(default) else None


def _declared_pointer(root: str, pointer_file: str) -> Optional[str]:
    """The path a project-instruction file points at, or None if it has no pointer."""
    absolute = os.path.join(root, pointer_file)
    if not os.path.isfile(absolute):
        return None
    with open(absolute, "r", encoding="utf-8-sig") as handle:
        match = POINTER_RE.search(handle.read())
    if not match:
        return None
    # A prose mention can end the sentence the pointer sits in: `...: docs/
    # task-tracking.md.` names `docs/task-tracking.md`, and reading the period
    # as part of the path would turn a working project into a refusal.
    declared = match.group(1).rstrip(".,;:!?)")
    return declared or None


def _parse_ini(text: str, source: str) -> configparser.ConfigParser:
    match = _FENCE_RE.search(text)
    if not match:
        raise ConfigError(
            f"{source}: no ```ini configuration block found "
            f"(see {CONFIG_TEMPLATE_PATH})"
        )
    parser = configparser.ConfigParser()
    parser.optionxform = str  # labels are case-sensitive provider vocabulary
    try:
        parser.read_file(io.StringIO(match.group(1)))
    except configparser.Error as exc:
        raise ConfigError(f"{source}: malformed configuration block — {exc}") from exc
    return parser


def load_config(
    root: str,
    env: Optional[Mapping[str, str]] = None,
    strict: bool = True,
) -> Config:
    """Load configuration, or return defaults when the project has none.

    An absent configuration is not an error — that is the whole point of the
    local fallback. A *malformed* one is, and so is a *declared* one whose file
    cannot be used: a pointer with no target is a configured project, broken,
    not an unconfigured one.

    `strict=False` is for `doctor` alone. It is the command a user runs BECAUSE
    configuration is broken, so refusing to load would make the diagnostic
    unreachable exactly when it is needed. Non-strict loading covers exactly two
    faults — a broken pointer (defaults are returned) and routine validation
    (skipped); the caller reports the fault it already caught. A target that
    exists but cannot be parsed still raises, strict or not. Every other command
    inherits the guarantees.
    """
    env = env if env is not None else os.environ
    jira = dict(
        jira_base_url=env.get("JIRA_BASE_URL", "").rstrip("/"),
        jira_email=env.get("JIRA_EMAIL", ""),
        jira_token=Secret(env.get("JIRA_API_TOKEN", "")),
    )
    try:
        config_path = find_config_path(root)
    except ConfigPointerError:
        if strict:
            raise
        config_path = None
    if config_path is None:
        return Config(root=root, **jira)

    with open(config_path, "r", encoding="utf-8-sig") as handle:
        parser = _parse_ini(handle.read(), os.path.relpath(config_path, root))

    tracker = parser["tracker"] if parser.has_section("tracker") else {}
    routines = parser["routines"] if parser.has_section("routines") else {}
    provider = (tracker.get("provider") or "").strip().lower() or None
    if provider is not None and provider not in PROVIDERS:
        raise ConfigError(
            f"{os.path.relpath(config_path, root)}: unknown provider {provider!r} "
            f"(expected one of: {', '.join(PROVIDERS)})"
        )

    def section(name: str, defaults: Mapping[str, str]) -> Dict[str, str]:
        """Declared entries layered *over* the defaults, never instead of them.

        Replacing meant that adding one `question = research` line silently
        unmapped `bug`, `enhancement` and `design-decision` — a project that
        extends the vocabulary would find three quarters of it stop being read.
        Shadowing a default key still works: the declared value wins.
        """
        merged = dict(defaults)
        if parser.has_section(name):
            merged.update({key: value.strip() for key, value in parser.items(name)})
        return merged

    # Approval is a floor. A repository file may *add* the requirement, but
    # cannot take it away — otherwise a one-line diff in a pull request makes
    # every later `--apply` write to the tracker without a human confirming.
    configured_approval = _as_bool(tracker.get("require_write_approval"), True)
    trusted = _as_bool(env.get(TRUSTED_CONFIG_ENV), False)
    require_approval = configured_approval or not trusted

    declared_skills = _routine_skills(parser)
    config = Config(
        root=root,
        provider=provider,
        repository=(tracker.get("repository") or "").strip(),
        project=(tracker.get("project") or env.get("JIRA_PROJECT", "")).strip(),
        index_path=(tracker.get("index") or "tasks/todo.md").strip(),
        backlog_path=(tracker.get("backlog") or "tasks/backlog.md").strip(),
        spec_dir=(tracker.get("spec_dir") or "specs").strip(),
        local_detail_dir=(tracker.get("local_detail_dir") or "tasks/details").strip(),
        dependency_strategy=(tracker.get("dependency_strategy") or "auto").strip().lower(),
        closed_plan_marker=(tracker.get("closed_plan_marker") or "Session Summary").strip(),
        require_write_approval=require_approval,
        allow_label_creation=_as_bool(tracker.get("allow_label_creation"), False),
        offline_reads=(tracker.get("offline_reads") or "degrade").strip().lower(),
        migration_policy=(tracker.get("migration_policy") or "manual").strip(),
        claim_label=_claim_label(routines.get("claim_label")),
        kind_precedence=_label_list(routines.get("kind_precedence")) or DEFAULT_KIND_PRECEDENCE,
        routine_skills=declared_skills if declared_skills is not None else dict(DEFAULT_ROUTINE_SKILLS),
        routine_skills_declared=declared_skills is not None,
        routine_selectors=_selectors(parser),
        kind_labels=section("labels.kind", DEFAULT_KIND_LABELS),
        priority_labels=section("labels.priority", DEFAULT_PRIORITY_LABELS),
        status_sources=section("status", {}),
        jira_issue_types=section("jira.issuetype", DEFAULT_JIRA_ISSUE_TYPES),
        jira_priorities=section("jira.priority", DEFAULT_JIRA_PRIORITIES),
        source_path=os.path.relpath(config_path, root),
        approval_relaxation_ignored=not configured_approval and not trusted,
        **jira,
    )
    # Validated here rather than in the one command that reports selectors: a
    # contested label makes selection depend on dict insertion order, and a gate
    # that only fires when a human types `selectors` does not protect the
    # unattended runs that are the whole point. Every command inherits it.
    if strict:
        validate_selectors(config)
    return config


def _claim_label(value: Optional[str]) -> str:
    """The configured claim label, never empty.

    `" "` is truthy, so stripping AFTER an `or` fallback yielded `""` -- and an
    empty claim label silently disables the only thing that stops two runs of one
    routine overlapping. Strip first, then fall back, so the guard cannot be
    turned off by whitespace nobody can see in a diff.
    """
    return (value or "").strip() or DEFAULT_CLAIM_LABEL


def _label_list(value: Optional[str]) -> Tuple[str, ...]:
    """A comma- or newline-separated label list, in the order it was written."""
    return tuple(item.strip() for item in re.split(r"[,\n]", value or "") if item.strip())


def _selectors(parser: configparser.ConfigParser) -> Dict[str, Tuple[str, ...]]:
    """Routine -> the provider labels it selects.

    Declared entries REPLACE the shipped map rather than layering over it, unlike
    `[labels.kind]`. A project renaming its vocabulary would otherwise keep the
    English defaults as a shadow selector set, and `fix` would claim both `bug`
    and `defeito` — two routines' worth of issues under one name, with the
    duplicate invisible in the configuration file.
    """
    if not parser.has_section("routines.selectors"):
        return dict(DEFAULT_SELECTORS)
    declared = {
        routine.strip(): _label_list(labels)
        for routine, labels in parser.items("routines.selectors")
    }
    return {routine: labels for routine, labels in declared.items() if labels}



def _routine_skills(parser: configparser.ConfigParser) -> Optional[Dict[str, Tuple[str, ...]]]:
    """Routine -> the ordered skills it runs, or None when the project declared none.

    Replaces wholesale like `[routines.selectors]`, not per key like
    `[labels.kind]`: a project that reorders one chain and inherits three others
    cannot see, in its own configuration file, which chains it actually chose.
    That is safe only because `_refuse_selector_without_chain` refuses a routine
    left with a selector and no chain, so the two rules ship together.

    None is a third state, distinct from an empty section: "the project said
    nothing" is what licenses the shipped defaults, and "the project declared
    chains" is what makes it answerable for their skills existing on disk.
    """
    if not parser.has_section("routines.skills"):
        return None
    declared = {
        routine.strip(): _skill_chain(steps)
        for routine, steps in parser.items("routines.skills")
    }
    return {routine: chain for routine, chain in declared.items() if chain}


def _skill_chain(value: Optional[str]) -> Tuple[str, ...]:
    """A comma- or newline-separated skill chain, each step normalized to `/name`.

    Both spellings reach here from real configuration files, and normalizing on
    read means the terminal-step check compares one form instead of guessing.
    """
    steps = (step.strip() for step in re.split(r"[,\n]", value or ""))
    return tuple("/" + step.lstrip("/") for step in steps if step)


def validate_selectors(config) -> None:
    """Refuse a configuration that cannot describe a total, unambiguous selection.

    Three failures, each silent if unchecked and each fatal to the one property
    that makes routines cheap: exactly one routine claims any given issue.
    """
    ranked = list(config.kind_precedence)
    claimed_by = _routines_by_label(config)
    _refuse_unknown_routines(config)
    _refuse_duplicate_ranks(ranked)
    _refuse_contested_labels(claimed_by)
    _refuse_divergent_label_sets(ranked, claimed_by)
    _refuse_selector_without_chain(config)
    _refuse_unterminated_chains(config)
    _refuse_absent_chain_skills(config)


def _refuse_unknown_routines(config) -> None:
    """A routine nobody can branch for is a configuration error, not a feature.

    `format_routine_branch` refuses a name outside the contract, so a project that
    invents one gets a clean load, a working `select`, and a crash at spine step 3
    -- after the claim label is already written. Refusing here moves that failure
    to load time, where it names the mistake instead of aborting a live run.
    """
    for section, declared in (
        ("[routines.selectors]", config.routine_selectors),
        ("[routines.skills]", config.routine_skills),
    ):
        unknown = sorted(set(declared) - set(CONTRACT_ROUTINES))
        if unknown:
            raise ConfigError(
                f"routines: {section} declares "
                f"{', '.join(repr(name) for name in unknown)}, which the routine contract "
                f"does not define. Known routines: {', '.join(CONTRACT_ROUTINES)}. Adding "
                "one is a deliberate edit to the contract, not a configuration key."
            )


def _routines_by_label(config) -> Dict[str, List[str]]:
    """Inverts the selector map, keeping every claimant so contests stay visible."""
    claimed_by: Dict[str, List[str]] = {}
    for routine, labels in config.routine_selectors.items():
        for label in labels:
            claimed_by.setdefault(label, []).append(routine)
    return claimed_by


def _refuse_duplicate_ranks(ranked: Sequence[str]) -> None:
    """A label ranked twice has two precedences, and the lower one is unreachable."""
    duplicates = sorted({label for label in ranked if ranked.count(label) > 1})
    if duplicates:
        raise ConfigError(
            f"routines: kind_precedence ranks these labels more than once — {', '.join(duplicates)}"
        )


def _refuse_contested_labels(claimed_by: Mapping[str, List[str]]) -> None:
    """Two routines on one label makes selection depend on dict ordering."""
    contested = sorted(label for label, routines in claimed_by.items() if len(routines) > 1)
    if not contested:
        return
    detail = "; ".join(
        f"{label} -> {', '.join(sorted(claimed_by[label]))}" for label in contested
    )
    raise ConfigError(f"routines: more than one routine selects the same label — {detail}")


def _refuse_selector_without_chain(config) -> None:
    """A routine that selects issues but runs nothing is a silently dead routine.

    This is the rule that makes wholesale replacement of `[routines.skills]` safe.
    A project overriding one chain supplies all of them, and the one it forgets
    would otherwise keep selecting and claiming issues -- writing the claim label
    onto an issue no chain will ever act on.
    """
    orphaned = sorted(set(config.routine_selectors) - set(config.routine_skills))
    if not orphaned:
        return
    raise ConfigError(
        "routines: these routines select issues but have no skill chain — "
        f"{', '.join(orphaned)}. [routines.skills] replaces the shipped map "
        "wholesale rather than merging per key, so a project that declares it "
        "must declare a chain for every routine it selects with."
    )


def _refuse_unterminated_chains(config) -> None:
    """Every chain ends at the review gate, or the routine can ship unreviewed.

    `references/routines.md` marks step 5 non-skippable for every routine without
    exception. Checking only for PRESENCE would accept a chain that runs the gate
    and then three more steps after it, which is the same omission wearing a
    different shape.
    """
    unterminated = sorted(
        routine
        for routine, chain in config.routine_skills.items()
        if not chain or chain[-1] != TERMINAL_ROUTINE_SKILL
    )
    if not unterminated:
        return
    detail = "; ".join(
        f"{routine} ends at {config.routine_skills[routine][-1]}"
        if config.routine_skills[routine]
        else f"{routine} is empty"
        for routine in unterminated
    )
    raise ConfigError(
        f"routines: every skill chain must end at {TERMINAL_ROUTINE_SKILL} — {detail}. "
        "It is the review gate, and a chain that runs it anywhere but last can "
        "still ship work after it."
    )


def _refuse_absent_chain_skills(config) -> None:
    """A declared chain naming a skill nobody installed fails at step 4, mid-run.

    By then the claim label is written and the branch exists, so the routine has
    already taken the issue out of every other routine's reach before discovering
    it cannot do the work. Refusing at load moves that to the one moment where
    the answer is a configuration edit rather than a cleanup.

    Only *declared* chains are checked. A shipped default names skills from this
    template, where tests/test-routine-skills.sh pins their presence; checking it
    here instead would refuse every command in a checkout that installed the
    registry without the rest of the harness.
    """
    if not config.routine_skills_declared:
        return
    missing = sorted(
        {
            f"{routine}: {skill}"
            for routine, chain in config.routine_skills.items()
            for skill in chain
            if not _skill_on_disk(config.root, skill)
        }
    )
    if not missing:
        return
    raise ConfigError(
        "routines: [routines.skills] names skills that are not installed — "
        f"{'; '.join(missing)}. Looked in {' and '.join(SKILL_ROOTS)}."
    )


def _skill_on_disk(root: str, skill: str) -> bool:
    """Is `/name` an installed skill in either skills tree?"""
    name = skill.lstrip("/")
    return any(
        os.path.isfile(os.path.join(root, skill_root, name, "SKILL.md"))
        for skill_root in SKILL_ROOTS
    )


def _refuse_divergent_label_sets(
    ranked: Sequence[str], claimed_by: Mapping[str, List[str]]
) -> None:
    """The chain's domain and the selector union must be the same set.

    When they drift apart, issues fall into the gap: a label nobody ranks can
    never win precedence, and a label nobody selects ranks ahead of labels that
    would have matched.
    """
    unranked = sorted(set(claimed_by) - set(ranked))
    unselected = sorted(set(ranked) - set(claimed_by))
    if not (unranked or unselected):
        return
    parts = []
    if unranked:
        parts.append(f"selected but not ranked: {', '.join(unranked)}")
    if unselected:
        parts.append(f"ranked but selected by no routine: {', '.join(unselected)}")
    raise ConfigError(
        "routines: kind_precedence and [routines.selectors] describe different "
        f"label sets — {'; '.join(parts)}"
    )


def _run(command, cwd: str, timeout: int = 15) -> Tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return 127, str(exc)
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def github_remote(root: str) -> str:
    """The `owner/repo` of a GitHub remote, or "" when there is none."""
    code, output = _run(["git", "remote", "-v"], root)
    if code != 0:
        return ""
    for line in output.splitlines():
        match = re.search(r"github\.com[:/]([^\s/]+/[^\s/]+?)(?:\.git)?\s", line + " ")
        if match:
            return match.group(1)
    return ""


def gh_authenticated(root: str) -> bool:
    code, _ = _run(["gh", "auth", "status"], root)
    return code == 0


@dataclass(frozen=True)
class Selection:
    """Which provider was chosen, and the one-line reason why."""

    provider: str
    reason: str
    explicit: bool


def select_provider(config: Config) -> Selection:
    if config.provider:
        return Selection(config.provider, f"configured in {config.source_path}", True)
    remote = github_remote(config.root)
    if remote and gh_authenticated(config.root):
        return Selection("github", f"GitHub remote {remote} with authenticated gh", False)
    if remote:
        return Selection(
            "local", "GitHub remote found but gh is unavailable or unauthenticated", False
        )
    return Selection("local", "no configuration and no usable GitHub remote", False)
