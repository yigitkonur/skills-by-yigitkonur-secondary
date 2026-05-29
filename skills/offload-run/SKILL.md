---
name: offload-run
description: Use skill if you are running a project's npm/pnpm install, tests, builds, tsc, eslint, pytest, or macOS/Xcode builds in a remote cloud sandbox instead of on the local machine.
---

# offload-run

Run `npm test` / `pytest` / `xcodebuild` — anything — in a **remote sandbox** instead of on the
local machine. Detects the project type, restores a dependency-warm **golden** environment
(checkpoint/snapshot, so deps aren't reinstalled each run), syncs the working tree, runs the
command remotely, streams stdout/stderr, and returns the **exit code unchanged**. The local Mac
stays a thin orchestrator.

## When to use
- The user wants build/test/install work to NOT consume local CPU/RAM.
- The Mac is overloaded / swap-thrashing during builds.
- Setting up a repeatable remote-run workflow across many projects (node, python, macOS).

## Backends (routed automatically by project type)
| Project type | Default backend | Why |
|---|---|---|
| node / python / generic | **Sprites** (Fly.io) | persistent + ~ms checkpoint/restore, idle-free, Linux microVM |
| node / python (parallel fan-out) | **E2B** (alt) | fork one warm template into many sandboxes; prebuilt Codex/Claude Code |
| macOS / Xcode / Swift / Pods | **Tart** | only Apple hardware can build macOS; `tart clone` = instant CoW checkpoint |

macOS must run on Apple hardware. To keep YOUR Mac free, point Tart at a **remote** host
(`OFFLOAD_TART_HOST`): a spare Apple Silicon Mac, an Orchard cluster, or a managed Tart provider
(e.g. Cirrus Runners). See `references/backends.md`.

## First-time setup (once)
1. `cp config.example.sh ~/.config/offload-run/config.sh` and edit (pick backends, set Tart host).
2. Provision the backend(s) and build the **golden** image/checkpoint per project — `references/setup.md`.
3. Optionally symlink the entry point: `ln -s "$PWD/scripts/offload.sh" ~/bin/offload`.

## Usage
```bash
# from inside a project dir:
offload -- npm test                 # node → Sprites (auto)
offload -- pytest -q                # python → Sprites (auto)
offload -- xcodebuild -scheme App test   # macOS → Tart (auto)
offload --backend e2b -- vitest run      # force E2B (parallel fork)
offload --type macos -- swift build      # force routing
offload --root /path/to/proj -- npm run build
```
The command after `--` runs in the remote env; its exit code becomes `offload`'s exit code, so it
drops into existing scripts/CI/pre-commit transparently.

## How it works (the golden-checkpoint model)
1. **Detect** project type from manifest files (`scripts/detect-project.sh`).
2. **Key** a golden env to `sha256(lockfiles)` (`lib.sh:lockfile_hash`) — rebuilt only when deps change.
3. **Restore/clone** the golden (deps already installed): Sprites `restore` checkpoint · Tart `clone` CoW · E2B fork template.
4. **Sync** the worktree as a git-aware tar (committed+uncommitted, honoring `.gitignore`; never `node_modules`).
5. **Run** the command; **stream** stdout/stderr; **return** the remote exit code.
6. **Discard** the ephemeral clone (or return the sprite to a pool).

## Transparent interception (optional, for agents like Codex/Claude Code)
Put shims earlier on `PATH` so an agent's `npm test` auto-offloads without the agent knowing:
```bash
# ~/.offload/shims/npm   (chmod +x); prepend ~/.offload/shims to PATH for agent sessions
#!/usr/bin/env bash
case "$1" in ci|install|test|run) exec offload -- npm "$@";; *) exec /opt/homebrew/bin/npm "$@";; esac
```
Only offload one-shot commands; let `run dev`/`--watch` fall through to local.

## Pattern B — run the AGENT remotely (max offload)
Bake Codex + Claude Code into the golden (`OFFLOAD_INSTALL_AGENTS=1`), then run the agent itself in
the sandbox (`offload -- codex exec "fix tests"`). The Mac becomes a pure terminal/orchestrator.

## Status
The **Sprites backend is verified end-to-end** (sprite CLI v0.0.1-rc43, 2026-05-28): a real project
bootstrapped a golden checkpoint (`npm ci`), warm-restored it on later runs (~19s, no reinstall),
synced the worktree, ran `vitest` remotely, and propagated exit codes faithfully (0 on pass, 7 on a
forced failure, shell operators preserved). The **Tart (macOS) and E2B backends are scaffolds**, not
yet run end-to-end — follow `references/setup.md` and adjust CLI flags to your installed versions
before relying on them.

## References
- `references/setup.md` — provision each backend + build golden images/checkpoints (the one-time work).
- `references/backends.md` — backend comparison, macOS host options, when to use which.
