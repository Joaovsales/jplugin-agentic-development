---
name: playwright-cli
display_name: Playwright CLI
fidelity: full
screenshot: file
detect_command: "command -v playwright-cli"
platforms: [linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64, windows-x86_64]
license: Apache-2.0
pinned_version: "0.1.22"
---

# Playwright CLI — first-choice e2e browser

> Adapter runbook for `/verify-evidence --scope e2e`. The frontmatter above is the
> machine-readable contract; this body is the human-readable operating notes.
> Optional: if `playwright-cli` is absent, `/verify-evidence` falls through to the
> next tier and that is **not** an error.

[`@playwright/cli`](https://www.npmjs.com/package/@playwright/cli) is Microsoft's
shell-driven version of Playwright MCP: the same browser tools, one shell
command per step, with a browser session that lives between commands. It drives
a real headless Chromium, so it has full rendering fidelity, and its
`screenshot` writes a **file** — which is why it goes first in the resolution
order. A VISUAL AC passes only with its PNG on disk, and Chrome MCP's
screenshots are session ids that never reach the disk.

## Why the CLI and not `@playwright/mcp`

Every agent has a shell; not every agent has MCP. Pi would need
`pi-mcp-adapter`, and Codex its own `config.toml` registration, so the MCP
server means three setup paths where the CLI needs none. Detection is therefore
`command -v playwright-cli`, never the presence of MCP tools. Do not register
`@playwright/mcp` for this workflow — it would be a second way to reach the same
browser, and a second way for the tier to be misconfigured.

## Install

`install.sh` installs the pinned version when `npm` is present. By hand:

```bash
npm install -g @playwright/cli@<pinned_version>
playwright-cli install-browser chromium
```

**Pin the version.** The CLI is 0.x and its command surface can change between
releases. Bumping `pinned_version` above is a deliberate edit, made in one
commit with a re-run of the crib below; `install.sh` reads it from here.

## The command crib

Headless is the default, so the same commands run in `/yolo`, routines and cloud
containers. The session persists between commands until `close`.

| Step | Command |
|---|---|
| Launch and load | `playwright-cli open http://localhost:3000/login` |
| Navigate | `playwright-cli goto http://localhost:3000/settings` |
| Find element refs | `playwright-cli snapshot` (writes a YAML snapshot with `e<N>` refs) |
| Click | `playwright-cli click '#submit'` (a selector or a snapshot ref) |
| Type into a field | `playwright-cli fill '#email' 'user@example.com'` |
| Assert state | `playwright-cli eval "() => document.querySelector('h1').textContent"` |
| Console errors | `playwright-cli console error` |
| Screenshot (after) | `playwright-cli screenshot --filename=tasks/e2e-artifacts/<short-sha>/<AC-id>.png` |
| Shut down | `playwright-cli close` |

Take the screenshot **after** the walkthrough reaches the state the AC describes
— one per VISUAL AC. There is no "before" shot: it would mean running the base
commit's app and doubling every walkthrough. `--full-page` captures the whole
scrollable page when the AC is about content below the fold.

Every command also writes its snapshot and console logs under `.playwright-cli/`
in the working directory. That directory and `tasks/e2e-artifacts/` are
gitignored: screenshots are committed only to the `e2e-evidence` branch.

## Troubleshooting

**The first command fails with a missing-browser error.** The CLI is installed
but its Chromium is not. Report it as a step failure naming the remedy,
`playwright-cli install-browser chromium`. Do **not** fall through to Chrome
MCP: the resolution order chose this backend because it can write the PNG, and
a silent fallback would turn every VISUAL AC into `BLOCKED` without saying why.

**A command hangs or reports a stale session.** `playwright-cli close-all`, or
`playwright-cli kill-all` for a zombie browser, then `open` again.

**Several walkthroughs at once.** Give each its own session with
`playwright-cli -s=<name> <command>`, so two agents never drive one page.
