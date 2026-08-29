"""Provider-agnostic task registry.

Three layers, deliberately separable:

    model.py / index.py     the normalized task record and the compact local index
    providers/              adapters: github (gh CLI), jira (HTTP), local (Markdown)
    reconcile.py            synchronization, frontier, progressive disclosure
    migrate.py              one-time classification of a pre-registry repository

Nothing above `providers/` imports a provider directly; nothing inside a provider
imports the reconciler. That is what keeps a fourth tracker an addition rather
than a rewrite.
"""

from .config import Config, ConfigError, Secret, load_config, select_provider
from .index import TaskIndex, load_index, render_row
from .migrate import apply_migration, plan_migration
from .model import (
    KINDS,
    PRIORITIES,
    STATUSES,
    ExternalRef,
    Task,
    TaskModelError,
)
from .providers import WriteGate, build_provider
from .reconcile import Registry, Report

__all__ = [
    "Config",
    "ConfigError",
    "ExternalRef",
    "KINDS",
    "PRIORITIES",
    "Registry",
    "Report",
    "STATUSES",
    "Secret",
    "Task",
    "TaskIndex",
    "TaskModelError",
    "WriteGate",
    "apply_migration",
    "build_provider",
    "load_config",
    "load_index",
    "plan_migration",
    "render_row",
    "select_provider",
]
