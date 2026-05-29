#!/usr/bin/env bash
# sprites-ops.sh — Sprites power subcommands behind `offload <op>`. Sourced by offload.sh.
# Verified against sprite CLI v0.0.1-rc43 (2026-05-29). All ops target the project's sprite
# (offload-<type>) so they line up with `offload run`. Servers use the in-sprite tool
# /.sprite/bin/sprite-env (services), per the official /.sprite/llm.txt convention.
set -euo pipefail
: "${OFFLOAD_WORKDIR:=/work}"

# Parse leading `--root R`, `--sprite NAME`, `--serve`; leave the rest in REST[]. Sets ROOT and SP.
# Run/test/prune target the ephemeral project sprite (offload-<type>); serve targets a separate
# persistent server sprite (offload-srv-<app>) so `offload run`'s golden-restore never wipes a server.
_resolve() {
  ROOT="$PWD"; REST=(); SP_EXPLICIT=0; local ov="" serve=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --root)   ROOT="$2"; shift 2 ;;
      --sprite) ov="$2"; SP_EXPLICIT=1; shift 2 ;;
      --serve)  serve=1; shift ;;
      *) REST+=("$1"); shift ;;
    esac
  done
  have sprite || die "sprite CLI not found — curl -fsSL https://sprites.dev/install.sh | bash"
  local type; type="$(detect_project "$ROOT")"
  if   [ -n "$ov" ]; then SP="$ov"
  elif [ "$serve" = 1 ]; then SP="${OFFLOAD_SPRITE_PREFIX:-offload}-srv-$(basename "$ROOT")"
  else SP="$(project_sprite "$ROOT" "$type")"; fi
}
ensure_sprite() { sprite list 2>/dev/null | grep -qw "$SP" || { log "creating sprite $SP"; sprite create "$SP" --skip-console >/dev/null; }; }
wait_ready() { local i; for i in $(seq 1 30); do sprite exec -s "$SP" -- true >/dev/null 2>&1 && return 0; sleep 3; done; die "sprite '$SP' not ready"; }
sync_tree() {
  log "syncing worktree -> $SP:$OFFLOAD_WORKDIR"
  sprite exec -s "$SP" -- bash -lc "mkdir -p '$OFFLOAD_WORKDIR'"
  worktree_tar "$ROOT" | sprite exec -s "$SP" -- bash -lc "tar -xzf - -C '$OFFLOAD_WORKDIR' --warning=no-unknown-keyword"
  sprite exec -s "$SP" -- bash -lc "find '$OFFLOAD_WORKDIR' -name '._*' -type f -delete 2>/dev/null || true"
}
# Read the authoritative public URL from the API (never hand-construct it).
sprite_url() {
  sprite api /v1/sprites 2>/dev/null | python3 -c "import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print(next((s.get('url','') for s in d.get('sprites',[]) if s.get('name')=='$SP'),''))" 2>/dev/null
}

# ---- status: state + URL + cost posture ----------------------------------------------------
ops_status() {
  _resolve "$@"
  sprite api /v1/sprites 2>/dev/null | python3 -c "import sys,json
d=json.load(sys.stdin); s=next((x for x in d.get('sprites',[]) if x.get('name')=='$SP'),None)
if not s: print('sprite $SP: not created yet (no charges).'); sys.exit(0)
st=s.get('status','?'); print('sprite : '+s['name']); print('status : '+st)
print('url    : '+s.get('url','-')+'   (auth: '+s.get('url_settings',{}).get('auth','?')+')')
print('seen   : last_running_at='+str(s.get('last_running_at','-')))
if st=='running': print('billing: RUNNING — CPU \$0.07/CPU-hr + mem \$0.04375/GB-hr + storage now')
else:             print('billing: IDLE ('+st+') — compute \$0; only storage ~\$0.027/GB-month. Wakes 0.1-2s on next use.')
print('zero   : only \`offload nuke\` (sprite destroy) stops storage billing too (deletes the golden).')" \
  || die "could not read sprite state (is 'sprite' authed? run: offload doctor)"
  local n; n="$(sprite checkpoint list -s "$SP" 2>/dev/null | awk '$1 ~ /^pre-restore/' | wc -l | tr -d ' ' || true)"
  [ "${n:-0}" -gt 3 ] && log "note: $n pre-restore safety checkpoints are accumulating — run 'offload prune' to reclaim storage"
  return 0
}

# ---- url: show / change public URL auth ----------------------------------------------------
ops_url() {
  _resolve "$@"
  local mode=""
  set -- ${REST[@]+"${REST[@]}"}
  while [ $# -gt 0 ]; do case "$1" in --public) mode=public; shift;; --private) mode=sprite; shift;; *) die "url: unknown flag '$1'";; esac; done
  if [ -n "$mode" ]; then log "setting URL auth=$mode"; sprite url update -s "$SP" --auth "$mode" >/dev/null 2>&1 || sprite url update -s "$SP" --auth "$mode"; fi
  printf 'URL : %s\n' "$(sprite_url)"
}

# ---- serve: run CMD as a persistent Service + expose at the Sprite URL ----------------------
ops_serve() {
  _resolve "$@"
  local port=8080 public=0 name=""; local -a cmd=()
  set -- ${REST[@]+"${REST[@]}"}
  while [ $# -gt 0 ]; do case "$1" in
    --port) port="$2"; shift 2 ;;
    --public) public=1; shift ;;
    --name) name="$2"; shift 2 ;;
    --) shift; cmd=("$@"); break ;;
    *) die "serve: unknown flag '$1' (command goes after --)" ;;
  esac; done
  [ ${#cmd[@]} -gt 0 ] || die "serve: no command. e.g. offload serve --port 8080 --public -- node server.js"
  # Persistent server box, isolated from the ephemeral run sprite (no golden-restore here).
  # Honor an explicit --sprite override; otherwise default to the per-app server sprite.
  name="${name:-app}"
  [ "${SP_EXPLICIT:-0}" = 1 ] || SP="${OFFLOAD_SPRITE_PREFIX:-offload}-srv-$(basename "$ROOT")"
  ensure_sprite; wait_ready
  sync_tree
  # Install deps ONCE on the persistent box (they survive; no golden churn).
  case "$(detect_project "$ROOT")" in
    node)   log "ensuring node deps on $SP (first serve only)"
            sprite exec -s "$SP" -- bash -lc "cd '$OFFLOAD_WORKDIR' && [ -d node_modules ] || (corepack enable 2>/dev/null; pnpm install --frozen-lockfile 2>/dev/null || npm ci || npm install)" ;;
    python) log "ensuring python deps on $SP (first serve only)"
            sprite exec -s "$SP" -- bash -lc "cd '$OFFLOAD_WORKDIR' && [ -d .venv ] || (python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt 2>/dev/null || true)" ;;
  esac
  local bin="${cmd[0]}" args
  args="$( IFS=,; printf '%s' "${cmd[*]:1}" )"   # comma-join the args for --args (note: a literal comma in an arg will split — see references)
  log "service '$name' on port $port -> ${cmd[*]}"
  sprite exec -s "$SP" -- /.sprite/bin/sprite-env services delete "$name" >/dev/null 2>&1 || true
  if [ -n "$args" ]; then
    sprite exec -s "$SP" -- /.sprite/bin/sprite-env services create "$name" --cmd "$bin" --args "$args" --http-port "$port" --dir "$OFFLOAD_WORKDIR" --no-stream
  else
    sprite exec -s "$SP" -- /.sprite/bin/sprite-env services create "$name" --cmd "$bin" --http-port "$port" --dir "$OFFLOAD_WORKDIR" --no-stream
  fi
  if [ "$public" = 1 ]; then
    log "URL -> public (STICKY until 'offload url --serve --private')"
    sprite url update -s "$SP" --auth public >/dev/null 2>&1 || log "  WARNING: could not set public — check 'offload url --serve'"
  fi
  # Report the ACTUAL auth from the API (not the requested flag).
  local url auth
  url="$(sprite_url)"
  auth="$(sprite api /v1/sprites 2>/dev/null | python3 -c "import sys,json
try: d=json.load(sys.stdin)
except Exception: print('?'); sys.exit(0)
print(next((s.get('url_settings',{}).get('auth','?') for s in d.get('sprites',[]) if s.get('name')=='$SP'),'?'))" 2>/dev/null)"
  printf '\n\033[1m✓ serving on %s\033[0m\n  url : %s\n  auth: %s%s\n  stop: sprite exec -s %s -- /.sprite/bin/sprite-env services stop %s\n' \
    "$SP" "${url:-<offload status --serve>}" "${auth:-?}" \
    "$([ "${auth:-}" = public ] && echo '   ⚠ PUBLIC & sticky — revoke: offload url --serve --private' || echo ' (org-only; first request wakes it ~0.1-2s, idle=$0)')" \
    "$SP" "$name"
}

# ---- sync / shell / proxy ------------------------------------------------------------------
ops_sync()  { _resolve "$@"; ensure_sprite; wait_ready; sync_tree; log "synced."; }
ops_shell() { _resolve "$@"; ensure_sprite; exec sprite console -s "$SP"; }
ops_proxy() { _resolve "$@"; [ ${#REST[@]} -gt 0 ] || die "proxy: give a port, e.g. offload proxy 5432 or 3001:3000"; exec sprite proxy -s "$SP" ${REST[@]+"${REST[@]}"}; }

# ---- checkpoints / prune -------------------------------------------------------------------
ops_checkpoints() { _resolve "$@"; sprite checkpoint list -s "$SP"; }
ops_prune() {
  _resolve "$@"
  local keep=1
  set -- ${REST[@]+"${REST[@]}"}
  while [ $# -gt 0 ]; do case "$1" in --keep) keep="${2:-}"; shift 2;; *) die "prune: unknown flag '$1'";; esac; done
  [[ "$keep" =~ ^[0-9]+$ ]] || die "prune: --keep needs a non-negative integer (got '$keep')"
  # Delete the platform's accumulating pre-restore safety snapshots (id 'pre-restore-v2-<unixtime>',
  # in column 1), keeping the newest $keep. sort -V keeps chronological order even if the suffix is unpadded.
  local ids; ids="$(sprite checkpoint list -s "$SP" 2>/dev/null | awk '$1 ~ /^pre-restore/ {print $1}' | sort -V)"
  [ -n "$ids" ] || { log "no pre-restore checkpoints to prune."; return 0; }
  local total kill_n
  total="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  kill_n=$(( total - keep )); [ "$kill_n" -lt 0 ] && kill_n=0
  log "pre-restore checkpoints: $total; keeping newest $keep, deleting $kill_n"
  if [ "$kill_n" -gt 0 ]; then
    printf '%s\n' "$ids" | head -n "$kill_n" | while read -r id; do
      [ -n "$id" ] || continue
      sprite checkpoint delete -s "$SP" "$id" >/dev/null 2>&1 && log "  deleted $id" || log "  skip $id"
    done
  fi
  log "prune done (golden + Current kept)."
}

# ---- keepalive: hold the sprite awake for N seconds (bounded; auto-releases) ----------------
ops_keepalive() {
  _resolve "$@"
  local secs=0
  set -- ${REST[@]+"${REST[@]}"}
  while [ $# -gt 0 ]; do case "$1" in --seconds|-n) secs="${2:-}"; shift 2;; *) die "keepalive: unknown flag '$1'";; esac; done
  [[ "$secs" =~ ^[0-9]+$ ]] && [ "$secs" -gt 0 ] || die "keepalive: --seconds N (positive integer) required (billed CPU+mem while held)"
  [ "$secs" -gt 3600 ] && die "keepalive: --seconds capped at 3600 (1h) — re-invoke for longer; never leave an unbounded hold (cost trap)"
  ensure_sprite; wait_ready
  log "holding $SP awake for ${secs}s (billed CPU+mem while held; auto-sleeps after)"
  sprite exec -s "$SP" -- sleep "$secs"
}

# ---- nuke: the only $0 path -----------------------------------------------------------------
ops_nuke() {
  _resolve "$@"
  local yes=0; set -- ${REST[@]+"${REST[@]}"}
  while [ $# -gt 0 ]; do case "$1" in --yes|-y) yes=1; shift;; *) die "nuke: unknown flag '$1'";; esac; done
  if [ "$yes" != 1 ]; then
    printf 'This DESTROYS sprite "%s": files, deps, AND the golden checkpoint. Irreversible.\nRe-run with --yes to confirm: offload nuke --yes\n' "$SP" >&2
    exit 1
  fi
  printf '\033[31m[offload] DESTROYING sprite "%s" — irreversible: files + deps + ALL checkpoints (golden included).\033[0m\n' "$SP" >&2
  sprite destroy "$SP" --force
}

# ---- mcp: optional remote MCP (Fly recommends CLI-first; MCP is the fallback) ---------------
ops_mcp() {
  local add=0; for a in "$@"; do [ "$a" = "--add" ] && add=1; done
  cat >&2 <<'EOF'
Sprites ships a hosted remote MCP, but Fly themselves say CLI/skills are the better default for
agents that can run shell (this skill). Add MCP only for chat agents that CANNOT run commands.
  claude mcp add --transport http sprites https://sprites.dev/mcp
(OAuth via browser on first use — no token to paste. Tools: list/create/destroy sprite, exec,
checkpoints, services, network policy.)
EOF
  if [ "$add" = 1 ]; then have claude || die "claude CLI not found"; claude mcp add --transport http sprites https://sprites.dev/mcp; fi
}

# ---- doctor: instant-integration check + official in-sprite agent docs ----------------------
ops_doctor() {
  _resolve "$@" 2>/dev/null || true
  printf '== offload doctor ==\n'
  have sprite && printf 'sprite : %s\n' "$(sprite --version 2>/dev/null)" || { printf 'sprite : MISSING — curl -fsSL https://sprites.dev/install.sh | bash\n'; return 1; }
  if sprite list >/dev/null 2>&1; then printf 'auth   : OK\nsprites: %s\n' "$(sprite list 2>/dev/null | tr '\n' ' ')"; else printf 'auth   : NOT LOGGED IN — run: sprite login (or auth setup --token ...)\n'; return 1; fi
  printf 'config : %s\n' "$([ -f "$HOME/.config/offload-run/config.sh" ] && echo "$HOME/.config/offload-run/config.sh" || echo '(defaults: linux=sprites, macos=tart)')"
  if [ -n "${SP:-}" ] && sprite list 2>/dev/null | grep -qw "$SP"; then
    printf '\n-- official in-sprite agent docs (%s:/.sprite/llm.txt) --\n' "$SP"
    sprite exec -s "$SP" -- cat /.sprite/llm.txt 2>/dev/null | sed -n '1,40p' || true
  fi
}
