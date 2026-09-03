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
from typing import Dict, Mapping, Optional, Tuple

CONFIG_DEFAULT_PATH = "docs/task-tracking.md"
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

DEFAULT_PRIORITY_LABELS: Mapping[str, str] = {"now": "high", "next": "medium"}

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
    autonomy_label: Optional[str] = "auto-mode-allowed"
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
    """Resolve the configuration document, following a project-instruction pointer."""
    for pointer_file in POINTER_FILES:
        absolute = os.path.join(root, pointer_file)
        if not os.path.isfile(absolute):
            continue
        with open(absolute, "r", encoding="utf-8-sig") as handle:
            match = POINTER_RE.search(handle.read())
        if match:
            # The pointer is read out of a repository file, so it is untrusted
            # input: `Task tracking instructions: ../../etc/shadow` would
            # otherwise be opened and echoed back in a parse error.
            try:
                candidate = confine(root, match.group(1), "task tracking pointer")
            except ConfigError:
                continue
            if os.path.isfile(candidate):
                return candidate
    default = os.path.join(root, CONFIG_DEFAULT_PATH)
    return default if os.path.isfile(default) else None


def _parse_ini(text: str, source: str) -> configparser.ConfigParser:
    match = _FENCE_RE.search(text)
    if not match:
        raise ConfigError(
            f"{source}: no ```ini configuration block found "
            "(see .agents/skills/task-registry/templates/task-tracking.md)"
        )
    parser = configparser.ConfigParser()
    parser.optionxform = str  # labels are case-sensitive provider vocabulary
    try:
        parser.read_file(io.StringIO(match.group(1)))
    except configparser.Error as exc:
        raise ConfigError(f"{source}: malformed configuration block — {exc}") from exc
    return parser


def load_config(root: str, env: Optional[Mapping[str, str]] = None) -> Config:
    """Load configuration, or return defaults when the project has none.

    An absent configuration is not an error — that is the whole point of the
    local fallback. A *malformed* one is.
    """
    env = env if env is not None else os.environ
    jira = dict(
        jira_base_url=env.get("JIRA_BASE_URL", "").rstrip("/"),
        jira_email=env.get("JIRA_EMAIL", ""),
        jira_token=Secret(env.get("JIRA_API_TOKEN", "")),
    )
    config_path = find_config_path(root)
    if config_path is None:
        return Config(root=root, **jira)

    with open(config_path, "r", encoding="utf-8-sig") as handle:
        parser = _parse_ini(handle.read(), os.path.relpath(config_path, root))

    tracker = parser["tracker"] if parser.has_section("tracker") else {}
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

    return Config(
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
        autonomy_label=_autonomy_label(tracker.get("autonomy_label")),
        kind_labels=section("labels.kind", DEFAULT_KIND_LABELS),
        priority_labels=section("labels.priority", DEFAULT_PRIORITY_LABELS),
        status_sources=section("status", {}),
        jira_issue_types=section("jira.issuetype", DEFAULT_JIRA_ISSUE_TYPES),
        jira_priorities=section("jira.priority", DEFAULT_JIRA_PRIORITIES),
        source_path=os.path.relpath(config_path, root),
        approval_relaxation_ignored=not configured_approval and not trusted,
        **jira,
    )


def _autonomy_label(value: Optional[str]) -> Optional[str]:
    """Configured label that grants unattended autonomy, or None when disabled."""
    if value is None:
        return "auto-mode-allowed"
    label = value.strip()
    return None if not label or label.lower() == "none" else label


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
