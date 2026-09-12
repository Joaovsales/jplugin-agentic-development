# Registry maintenance

This repository contains a provider-neutral task registry extracted from our workflow tooling. Source lives in registry/. Use Python's standard library; no new dependencies. Fix shared behavior centrally and preserve provider-owned state and unmanaged text. Work locally, with no network calls, commits, or pushes. The user has approved implementation of the requested correction.

### Source exploration
Read the relevant source directly in your own context. Do not delegate source exploration to a scout. Inspect implementations, callers, and contracts needed for a correct change; whole-file reads are allowed.

Workspace scope: source exploration must stay inside this checkout. Do not inspect parent directories, sibling projects, global agent files, session logs, or files outside this checkout. If local coverage is absent, create it here.
