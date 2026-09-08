"""Provider-agnostic task registry.

Three layers, deliberately separable:

    model.py / index.py     the normalized task record and the compact local index
    providers/              adapters: github (gh CLI), local (Markdown)
    detail.py               resolving one reference and rendering one task

Nothing above `providers/` imports a provider directly; nothing inside a provider
imports `detail.py`. That is what keeps a fourth tracker an addition rather than
a rewrite.
"""

from .config import Config, ConfigError, load_config, select_provider
from .index import TaskIndex, load_index, render_row
from .model import (
    KINDS,
    PRIORITIES,
    STATUSES,
    ExternalRef,
    Task,
    TaskModelError,
)
from .providers import WriteGate, build_provider
from .detail import Registry, Report

__all__ = [
    "Config",
    "ConfigError",
    "ExternalRef",
    "KINDS",
    "PRIORITIES",
    "Registry",
    "Report",
    "STATUSES",
    "Task",
    "TaskIndex",
    "TaskModelError",
    "WriteGate",
    "build_provider",
    "load_config",
    "load_index",
    "render_row",
    "select_provider",
]
