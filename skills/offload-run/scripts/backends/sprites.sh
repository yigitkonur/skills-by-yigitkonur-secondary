#!/usr/bin/env bash
# backends/sprites.sh — Linux backend on Fly.io Sprites (persistent + checkpoint, idle-free).
# Verified against sprite CLI v0.0.1-rc43 (2026-05-28). Base image = Ubuntu with node/npm/python/git
# preinstalled, so the golden only needs `npm ci`/`pip install` baked + a checkpoint.
#
# Model: one persistent sprite per (project-type); a checkpoint (commented with the lockfile-keyed
# golden name) holds warm deps. Per run: restore that checkpoint, sync the worktree on top (deps
# survive), run the command, return its exit code. Real CLI surface used:
#   sprite create NAME --skip-console | sprite list
#   sprite exec -s NAME [--dir D] -- CMD            (stdin piping + exit codes verified)
#   sprite checkpoint create -s NAME --comment TXT  (returns id like v1)
#   sprite checkpoint list -s NAME                  (ID CREATED COMMENT)
#   sprite restore ID   (async restart; gate readiness after)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$HERE/lib.sh"

: "${OFFLOAD_WORKDIR:=/work}"
: "${OFFLOAD_SPRITE_PREFIX:=offload}"

SP=""  # active sprite name (set in sprites_backend)

# Wait until the sprite accepts an exec (covers cold start + post-restore restart + transient 502).
sprite_wait() {
  local i
  for i in $(seq 1 30); do
    sprite exec -s "$SP" -- true >/dev/null 2>&1 && return 0
    sleep 3
  done
  die "sprite '$SP' not ready after ~90s"
}

# Resolve the checkpoint ID whose comment matches the golden name (empty if none).
golden_checkpoint_id() {
  sprite checkpoint list -s "$SP" 2>/dev/null | awk -v c="$1" 'index($0,c){print $1; exit}'
}

sprites_backend() {
  local type="$1" hash="$2" root="$3"; shift 3
  # Shell-quote the argv so the remote bash re-parses it to the exact same args, while still
  # supporting shell operators (&&, |, globs). Plain "$*" would drop inner quotes (e.g. node -e '...').
  local q; printf -v q '%q ' "$@"
  local golden; golden="$(golden_name "$type" "$hash")"
  SP="${OFFLOAD_SPRITE_PREFIX}-${type}"
  ROOT_DIR="$root"

  have sprite || die "sprite CLI not found — curl -fsSL https://sprites.dev/install.sh | bash"

  # 1. Ensure the project sprite exists.
  if ! sprite list 2>/dev/null | grep -qw "$SP"; then
    log "creating sprite $SP"
    sprite create "$SP" --skip-console >/dev/null
  fi
  sprite_wait

  # 2. Restore the golden checkpoint if it exists; else build it once.
  local cid; cid="$(golden_checkpoint_id "$golden")"
  if [ -n "$cid" ]; then
    log "restoring golden $golden (checkpoint $cid)"
    sprite restore -s "$SP" "$cid" >/dev/null
    sprite_wait
    sync_worktree           # refresh source on top of warm node_modules
  else
    log "golden $golden missing — bootstrapping deps + checkpointing (one-time)"
    sprites_bootstrap "$type" "$golden" "$root"
  fi

  # 3. Run the command; stream output; its exit code becomes our exit code.
  log "running in $SP:$OFFLOAD_WORKDIR -> $*"
  sprite exec -s "$SP" --dir "$OFFLOAD_WORKDIR" -- bash -lc "$q"
}

# Extract the current worktree into $OFFLOAD_WORKDIR WITHOUT removing node_modules.
sync_worktree() {
  log "syncing worktree"
  sprite exec -s "$SP" -- bash -lc "mkdir -p $OFFLOAD_WORKDIR"
  worktree_tar "$ROOT_DIR" | sprite exec -s "$SP" -- bash -lc "tar -xzf - -C $OFFLOAD_WORKDIR --warning=no-unknown-keyword"
  # self-heal: drop any stale AppleDouble files (e.g. baked into an older golden)
  sprite exec -s "$SP" -- bash -lc "find $OFFLOAD_WORKDIR -name '._*' -type f -delete 2>/dev/null || true"
}

# One-time golden: fresh /work, sync source, install deps, checkpoint.
sprites_bootstrap() {
  local type="$1" golden="$2" root="$3"; ROOT_DIR="$root"
  sprite exec -s "$SP" -- bash -lc "rm -rf $OFFLOAD_WORKDIR && mkdir -p $OFFLOAD_WORKDIR"
  sync_worktree
  case "$type" in
    node)   sprite exec -s "$SP" --dir "$OFFLOAD_WORKDIR" -- bash -lc \
              '(corepack enable 2>/dev/null; pnpm install --frozen-lockfile) 2>/dev/null || npm ci || npm install' ;;
    python) sprite exec -s "$SP" --dir "$OFFLOAD_WORKDIR" -- bash -lc \
              'python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt 2>/dev/null || true' ;;
  esac
  [ "${OFFLOAD_INSTALL_AGENTS:-0}" = "1" ] && sprite exec -s "$SP" -- bash -lc \
    'npm i -g @openai/codex @anthropic-ai/claude-code 2>/dev/null || true'
  log "checkpointing golden $golden"
  sprite checkpoint create -s "$SP" --comment "$golden" >/dev/null
}
