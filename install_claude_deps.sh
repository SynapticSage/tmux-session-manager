#!/usr/bin/env bash
# install_claude_deps.sh — install tmux-attic's optional Claude-capability
# dependencies: recon (cargo), badge hooks, and @recon-ignore toggle keys.
#
# Idempotent: re-running is safe. Each step skips if already satisfied.
# Flags:
#   --skip-recon     don't touch cargo/recon
#   --skip-badges    don't run install_badges.sh
#   --skip-bindings  don't modify tmux.conf
#   --dry-run        pass through to install_badges.sh; preview binding edits
#   -h|--help        this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECON_REPO="https://github.com/gavraz/recon"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
MARK_BEGIN="# >>> tmux-attic ignore-bindings >>>"
MARK_END="# <<< tmux-attic ignore-bindings <<<"

SKIP_RECON=0
SKIP_BADGES=0
SKIP_BINDINGS=0
DRY_RUN=0
FORCE=0
NO_LOCKED=0

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --skip-recon) SKIP_RECON=1 ;;
    --skip-badges) SKIP_BADGES=1 ;;
    --skip-bindings) SKIP_BINDINGS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --no-locked) NO_LOCKED=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[claude-deps] %s\n' "$*"; }

install_recon() {
  if command -v recon >/dev/null 2>&1; then
    log "recon already on PATH: $(command -v recon) — skipping"
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    log "cargo not found — install rustup/cargo first, then rerun with no flags"
    log "  see: https://rustup.rs"
    return 1
  fi

  log "installing recon from $RECON_REPO via cargo"
  local cargo_flags=(install --git "$RECON_REPO")
  (( NO_LOCKED )) || cargo_flags+=(--locked)
  if (( DRY_RUN )); then
    log "  (dry-run) would run: cargo ${cargo_flags[*]}"
    return 0
  fi
  if ! cargo "${cargo_flags[@]}"; then
    if (( ! NO_LOCKED )); then
      log "cargo install failed — if it was a lockfile version error, retry with --no-locked"
    fi
    return 1
  fi

  if command -v recon >/dev/null 2>&1; then
    log "recon installed: $(command -v recon)"
  else
    log "cargo install finished but recon not on PATH — add \$HOME/.cargo/bin to PATH"
    return 1
  fi
}

install_badges() {
  local installer="$SCRIPT_DIR/install_badges.sh"
  if [[ ! -x "$installer" ]]; then
    log "install_badges.sh not found or not executable at $installer"
    return 1
  fi
  log "running install_badges.sh"
  local flags=(--yes)
  (( DRY_RUN )) && flags+=(--dry-run)
  "$installer" "${flags[@]}"
}

install_bindings() {
  if [[ ! -f "$TMUX_CONF" ]]; then
    log "tmux.conf not found at $TMUX_CONF — skipping bindings"
    return 1
  fi

  # Resolve symlink to edit the real file.
  local target
  target="$(readlink -f "$TMUX_CONF")"
  log "writing ignore-toggle bindings to $target"

  if grep -qF "$MARK_BEGIN" "$target" 2>/dev/null; then
    log "ignore-toggle block already present — skipping (remove between sentinels to re-add)"
    return 0
  fi

  # Detect hand-wired bindings outside sentinels (pre-install state).
  local stray
  stray="$(awk -v mb="$MARK_BEGIN" -v me="$MARK_END" '
    $0 == mb { inblock=1; next }
    $0 == me { inblock=0; next }
    !inblock && /^[[:space:]]*bind-key[[:space:]]+[ieI][[:space:]].*(recon_ignore_toggle|recon_ignore_picker)/ { print NR": "$0 }
  ' "$target")"
  if [[ -n "$stray" ]]; then
    log "found ignore-binding-shaped lines OUTSIDE sentinels:"
    printf '  %s\n' "$stray" | sed 's/^/  /'
    if (( FORCE )); then
      log "--force set — proceeding anyway"
    else
      log "refusing to append. remove those lines or rerun with --force."
      return 1
    fi
  fi

  local block
  block="$(cat <<EOF

$MARK_BEGIN
# Managed by install_claude_deps.sh — edit between sentinels to customize, or
# delete the whole block (sentinels included) to uninstall.
# prefix + i : mute current pane    (siblings keep reporting)
# prefix + e : mute current window  (overrides tmux-text-macros split-window)
# prefix + I : popup picker for session/window scope
bind-key i run-shell "$SCRIPT_DIR/recon_ignore_toggle.sh --pane"
bind-key e run-shell "$SCRIPT_DIR/recon_ignore_toggle.sh --window"
bind-key I display-popup -w 85% -h 75% -E "$SCRIPT_DIR/recon_ignore_picker.sh"
$MARK_END
EOF
)"

  if (( DRY_RUN )); then
    log "  (dry-run) would append:"
    printf '%s\n' "$block"
    return 0
  fi

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  cp -p "$target" "$target.bak.$stamp"
  log "backup: $target.bak.$stamp"

  printf '%s\n' "$block" >> "$target"
  log "bindings appended"

  if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
    tmux source-file "$HOME/.tmux.conf" && log "reloaded tmux config" || log "tmux source-file failed — reload manually"
  fi
}

main() {
  local rc=0
  if (( ! SKIP_RECON )); then install_recon || rc=$?; fi
  if (( ! SKIP_BADGES )); then install_badges || rc=$?; fi
  if (( ! SKIP_BINDINGS )); then install_bindings || rc=$?; fi

  if (( rc == 0 )); then
    log "done"
  else
    log "finished with non-zero status ($rc) — see messages above"
  fi
  return $rc
}

main "$@"
