#!/usr/bin/env bash
# lib.sh — shared helpers sourced by offload.sh and backends.
set -euo pipefail

log()  { [ "${OFFLOAD_QUIET:-0}" = "1" ] && return 0; printf '\033[2m[offload]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[offload] %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Detect project type (node|python|macos|generic), callable when lib.sh is sourced.
detect_project() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "$d/detect-project.sh" "${1:-$PWD}"
}

# The sprite name a project maps to (same scheme the run path uses) so status/serve/prune/etc.
# all target the SAME sprite as `offload run`. type = explicit 2nd arg, else detected.
project_sprite() {
  local root="${1:-$PWD}" type="${2:-}"
  [ -n "$type" ] || type="$(detect_project "$root")"
  printf '%s-%s' "${OFFLOAD_SPRITE_PREFIX:-offload}" "$type"
}

# Hash the dependency lockfile so the golden image is keyed to exact deps.
# A change here (and only here) forces a golden rebuild.
lockfile_hash() {
  local root="${1:-$PWD}" f sum=""
  for f in pnpm-lock.yaml package-lock.json yarn.lock bun.lockb \
           poetry.lock requirements.txt Pipfile.lock uv.lock \
           Package.resolved Podfile.lock; do
    [ -f "$root/$f" ] && sum="$sum$(shasum -a 256 "$root/$f" | cut -d' ' -f1)"
  done
  [ -z "$sum" ] && sum="no-lockfile"
  printf '%s' "$sum" | shasum -a 256 | cut -c1-12
}

# Stream the working tree (committed + uncommitted, honoring .gitignore; never node_modules)
# as a single gzip'd tar to stdout. Falls back to a plain tar outside a git repo.
worktree_tar() {
  local root="${1:-$PWD}" macflag=""
  # macOS bsdtar otherwise smuggles AppleDouble "._*" entries + com.apple.* xattr pax headers
  # into the archive; the "._*" files break tools like vitest/rollup on the remote.
  # COPYFILE_DISABLE=1 kills the AppleDouble; --no-mac-metadata (when supported) strips the xattrs.
  tar --no-mac-metadata --version >/dev/null 2>&1 && macflag="--no-mac-metadata"
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ( cd "$root" && git ls-files -co --exclude-standard -z \
        | COPYFILE_DISABLE=1 tar $macflag --null -czf - --no-recursion -T - )
  else
    # Non-git fallback: no .gitignore to honor, so exclude heavy + SECRET paths explicitly
    # (otherwise .env / keys would be uploaded — dangerous with `serve --public`).
    log "not a git repo — taring (excluding node_modules/.git/.venv/dist + .env/keys)"
    ( cd "$root" && COPYFILE_DISABLE=1 tar $macflag -czf - \
        --exclude='./node_modules' --exclude='./.git' --exclude='./.venv' --exclude='./dist' \
        --exclude='./.env' --exclude='./.env.*' --exclude='*.pem' --exclude='*.key' --exclude='./id_rsa*' . )
  fi
}

# Golden image name for a (type, hash) pair.
golden_name() { printf 'golden-%s-%s' "$1" "$2"; }
