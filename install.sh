#!/usr/bin/env bash
# install.sh — tmux-attic wiring into ~/.tmux.conf.
#
# Does two things, both idempotent:
#   1. Appends a managed options block with opt-in key bindings
#      (view, delete, rename).
#   2. Appends a run-shell line that sources session_manager.tmux —
#      placed AFTER `run '~/.tmux/plugins/tpm/tpm'` if TPM is wired,
#      so attic's bindings override plugin-provided defaults.
#
# TPM users don't need this — `set -g @plugin 'SynapticSage/tmux-attic'`
# in ~/.tmux.conf is sufficient. This script is for non-TPM setups
# that want a single-command install.
#
# Flags:
#   --skip-tmux-wire   don't touch tmux.conf (pointless alone, kept for
#                      orchestration by wrapper scripts)
#   --dry-run          preview everything, touch nothing
#   --uninstall        strip managed blocks from tmux.conf
#   --force            append even if stray unmanaged attic lines exist
#   -h|--help          this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"

OPTS_BEGIN="# >>> tmux-attic options >>>"
OPTS_END="# <<< tmux-attic options <<<"
RUN_BEGIN="# >>> tmux-attic run-shell >>>"
RUN_END="# <<< tmux-attic run-shell <<<"

SKIP_TMUX_WIRE=0
DRY_RUN=0
UNINSTALL=0
FORCE=0

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --skip-tmux-wire) SKIP_TMUX_WIRE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[install] %s\n' "$*"; }

target_conf() {
  if [[ ! -e "$TMUX_CONF" ]]; then
    log "tmux.conf does not exist at $TMUX_CONF — creating empty file"
    (( DRY_RUN )) || : > "$TMUX_CONF"
  fi
  readlink -f "$TMUX_CONF"
}

strip_block() {
  local file="$1" begin="$2" end="$3"
  if ! grep -qF "$begin" "$file" 2>/dev/null; then
    return 0
  fi
  if (( DRY_RUN )); then
    log "  (dry-run) would strip block [$begin ... $end] from $file"
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

detect_stray_attic() {
  # Find attic-shaped lines OUTSIDE managed sentinel blocks. Used to
  # block double-installs when a user previously hand-wired attic.
  local file="$1"
  awk -v ob="$OPTS_BEGIN" -v oe="$OPTS_END" -v rb="$RUN_BEGIN" -v re="$RUN_END" '
    $0 == ob || $0 == rb { inblock=1; next }
    $0 == oe || $0 == re { inblock=0; next }
    !inblock && /^[[:space:]]*set[[:space:]]+-g[[:space:]]+@session-manager-/ { print NR": "$0 }
    !inblock && /^[[:space:]]*run-shell[[:space:]].*session_manager\.tmux/     { print NR": "$0 }
  ' "$file"
}

backup_once() {
  local file="$1"
  local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
  local bak="$file.bak.$stamp"
  if (( DRY_RUN )); then
    log "  (dry-run) would backup $file → $bak"
    return 0
  fi
  cp -p "$file" "$bak"
  log "backup: $bak"
}

wire_tmux() {
  local conf; conf="$(target_conf)"
  log "wiring tmux-attic into $conf"

  local stray; stray="$(detect_stray_attic "$conf")"
  if [[ -n "$stray" ]]; then
    log "found attic-shaped lines OUTSIDE managed sentinel blocks:"
    printf '  %s\n' "$stray" | sed 's/^/  /'
    if (( FORCE )); then
      log "--force set — proceeding anyway (duplicates will coexist until you clean up)"
    else
      log "refusing to append. remove these lines or rerun with --force. dry-run is safe."
      return 1
    fi
  fi

  local had_block=0
  if grep -qF "$OPTS_BEGIN" "$conf" 2>/dev/null || grep -qF "$RUN_BEGIN" "$conf" 2>/dev/null; then
    had_block=1
    log "existing managed block(s) found — stripping before re-adding"
  fi

  (( had_block )) && backup_once "$conf"
  strip_block "$conf" "$OPTS_BEGIN" "$OPTS_END"
  strip_block "$conf" "$RUN_BEGIN" "$RUN_END"

  local opts_block run_block
  opts_block="$(cat <<EOF
$OPTS_BEGIN
# Managed by tmux-attic install.sh — edit between sentinels or remove the
# whole block (sentinels included) to uninstall. See README for full option list.
set -g @session-manager-view-key   'C-v'
set -g @session-manager-delete-key 'C-d'
set -g @session-manager-rename-key 'C-n'
# Window-level defaults (C-w move, C-y load, C-p pull) and scratchpad
# defaults (a window-note, A pane-note, C-q to detach the popup) are
# applied by the plugin automatically — override here if desired.
# set -g @session-manager-scratchpad-editor ''   # empty = use \$EDITOR
$OPTS_END
EOF
)"

  run_block="$(cat <<EOF
$RUN_BEGIN
# Managed by tmux-attic install.sh. Placed after TPM init so attic bindings
# win over plugin-provided defaults.
run-shell '$SCRIPT_DIR/session_manager.tmux'
$RUN_END
EOF
)"

  if (( DRY_RUN )); then
    log "  (dry-run) would append options block:"
    printf '%s\n' "$opts_block"
    log "  (dry-run) would append run-shell block at end (after TPM if present):"
    printf '%s\n' "$run_block"
    return 0
  fi

  (( ! had_block )) && backup_once "$conf"

  printf '\n%s\n' "$opts_block" >> "$conf"

  # run-shell MUST come after TPM init so attic's bindings override plugin
  # defaults. If TPM init is mid-file, EOF-append lands us in the wrong
  # order — detect the TPM line and insert directly after it; fall back
  # to EOF only when TPM isn't wired.
  if grep -Eq "^[[:space:]]*run(-shell)?[[:space:]]+['\"]?[^'\"]*tpm/tpm['\"]?" "$conf"; then
    local tmp; tmp="$(mktemp)"
    awk -v block="$run_block" '
      { print }
      !inserted && /^[[:space:]]*run(-shell)?[[:space:]]+['\''"]?[^'\''"]*tpm\/tpm['\''"]?/ {
        print ""
        print block
        inserted = 1
      }
    ' "$conf" > "$tmp" && mv "$tmp" "$conf"
    log "run-shell inserted after TPM init"
  else
    printf '\n%s\n' "$run_block" >> "$conf"
    log "no TPM init line found — run-shell appended to EOF"
  fi

  log "tmux.conf wired"
}

uninstall_tmux() {
  local conf; conf="$(target_conf)"
  if ! grep -qF "$OPTS_BEGIN" "$conf" 2>/dev/null && ! grep -qF "$RUN_BEGIN" "$conf" 2>/dev/null; then
    log "no managed blocks found in $conf — nothing to strip"
    return 0
  fi
  backup_once "$conf"
  strip_block "$conf" "$OPTS_BEGIN" "$OPTS_END"
  strip_block "$conf" "$RUN_BEGIN" "$RUN_END"
  log "managed blocks stripped"
}

reload_tmux() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux info >/dev/null 2>&1 || { log "no tmux server running — skipping reload"; return 0; }
  if (( DRY_RUN )); then
    log "  (dry-run) would run: tmux source-file $TMUX_CONF"
    return 0
  fi
  tmux source-file "$TMUX_CONF" && log "reloaded tmux config" || log "tmux source-file failed"
}

smoke_test() {
  (( DRY_RUN )) && { log "  (dry-run) skipping smoke test"; return 0; }
  command -v tmux >/dev/null 2>&1 || return 0
  if ! tmux info >/dev/null 2>&1; then
    log "smoke test skipped — no tmux server. Start tmux, then check:"
    log "  - prefix+C-v opens session viewer, prefix+C-s saves, etc."
    return 0
  fi
  log "smoke test:"
  if tmux show-options -gqv @session-manager-view-key | grep -q .; then
    log "  ✓ session-manager options registered"
  else
    log "  ✗ session-manager options NOT registered (run-shell may not have fired)"
  fi
  if tmux list-keys 2>/dev/null | grep -q session_manager.tmux; then
    log "  ✓ session-manager keybindings present"
  else
    log "  ~ session-manager keybindings not visible (may bind on first prefix press)"
  fi
  if tmux list-keys -T scratchpad 2>/dev/null | grep -q detach-client; then
    log "  ✓ scratchpad key table registered (C-q detaches note popup)"
  else
    log "  ✗ scratchpad key table missing (run-shell may not have fired)"
  fi
}

main() {
  if (( UNINSTALL )); then
    uninstall_tmux
    reload_tmux
    log "uninstall complete"
    exit 0
  fi

  local rc=0
  if (( ! SKIP_TMUX_WIRE )); then wire_tmux || rc=$?; fi
  reload_tmux
  smoke_test

  if (( rc == 0 )); then log "done"; else log "finished with non-zero status ($rc)"; fi
  return $rc
}

main "$@"
