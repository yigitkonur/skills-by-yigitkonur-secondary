#!/usr/bin/env bash
# offload.sh — run a project's build/test/install command in a REMOTE sandbox, not locally.
# Detects project type, routes to a backend, restores/clones a lockfile-keyed golden env
# (deps already warm), syncs the worktree, runs the command, streams output, returns its
# exit code unchanged. Goal: never burn local CPU/RAM on npm/python/macOS builds.
#
# Usage:
#   offload.sh -- npm test
#   offload.sh -- pytest -q
#   offload.sh -- xcodebuild -scheme App test
#   offload.sh --backend e2b -- vitest run
#   offload.sh --type macos -- swift build          # force routing
#   offload.sh --root /path/to/proj -- npm run build
set -euo pipefail
# Resolve our own directory even when invoked through a symlink (e.g. ~/bin/offload).
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do
  D="$(cd -P "$(dirname "$SRC")" && pwd)"; SRC="$(readlink "$SRC")"
  [[ "$SRC" != /* ]] && SRC="$D/$SRC"
done
HERE="$(cd -P "$(dirname "$SRC")" && pwd)"
source "$HERE/lib.sh"
# Load user config if present.
for c in "${OFFLOAD_CONFIG:-}" "$HOME/.config/offload-run/config.sh"; do
  [ -n "$c" ] && [ -f "$c" ] && { source "$c"; break; }
done

root="$PWD"; force_type=""; force_backend=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)    root="$2"; shift 2 ;;
    --type)    force_type="$2"; shift 2 ;;
    --backend) force_backend="$2"; shift 2 ;;
    --)        shift; break ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *)         die "unknown flag: $1 (did you forget '--' before the command?)" ;;
  esac
done
[ $# -gt 0 ] || die "no command given. Example: offload.sh -- npm test"

type="${force_type:-$("$HERE/detect-project.sh" "$root")}"
hash="$(lockfile_hash "$root")"

# Route: macOS work must go to a Mac backend; everything else to the Linux backend.
if [ "$type" = "macos" ]; then
  backend="${force_backend:-${OFFLOAD_MACOS_BACKEND:-tart}}"
else
  backend="${force_backend:-${OFFLOAD_LINUX_BACKEND:-sprites}}"
fi

log "project=$type  deps-hash=$hash  backend=$backend  root=$root"

case "$backend" in
  sprites) source "$HERE/backends/sprites.sh"; sprites_backend "$type" "$hash" "$root" "$@" ;;
  e2b)     source "$HERE/backends/e2b.sh";     e2b_backend     "$type" "$hash" "$root" "$@" ;;
  tart)    source "$HERE/backends/tart.sh";    tart_backend    "$type" "$hash" "$root" "$@" ;;
  *)       die "unknown backend: $backend (sprites | e2b | tart)" ;;
esac
# The backend function's exit status is this script's exit status (set -e + last call).
