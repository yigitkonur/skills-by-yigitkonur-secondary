# offload-run

running a project's build/test/install commands in a remote cloud sandbox instead of on your own machine — npm/pnpm, vitest, vite/next, tsc, eslint, pytest, or macOS/Xcode builds.

**Category:** development

## Install

Install this skill individually:

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary/skills/offload-run
```

Or install the full pack:

```bash
npx -y skills add -y -g yigitkonur/skills-by-yigitkonur-secondary
```

## First-time setup (required before first run)

This skill drives the **Sprites** cloud CLI — you provide a token once:

1. Create an org token at https://sprites.dev (dashboard → **New Token / Install Sprites**).
2. Install **and** authenticate the CLI in one step — the dashboard gives you this exact line:
   ```bash
   curl -fsSL https://sprites.dev/install.sh | SETUP_SPRITE_TOKEN="<your-token>" bash
   ```
   Already have the CLI? `sprite auth setup --token <your-token>` (or `sprite login`).
3. Verify everything is wired:
   ```bash
   offload doctor    # sprite version, auth OK, config path
   ```
   If it prints `auth : NOT LOGGED IN`, redo step 2.

The token is stored by the `sprite` CLI under `~/.config` — **this skill never reads a key from env or config**; it just shells out to an already-authed `sprite`. Keep the token out of any repo.
