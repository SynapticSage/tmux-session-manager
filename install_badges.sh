#!/usr/bin/env bash
# install_badges.sh — opt-in installer for the per-window Claude Code
# status badge system shipped with this repo.
#
# Wires two changes, each idempotent and individually reversible:
#   1. Appends a marked block to ~/.tmux.conf that registers
#      window_badge.sh in window-status-format.
#   2. Adds four hook entries to ~/.claude/settings.json that call
#      hook_agent_state.sh on Claude Code lifecycle events.
#
# Both files are backed up with a timestamped .bak before any write.
# Re-running with the same action is a no-op; --uninstall strips
# exactly what this script installed.
#
# Usage:
#   install_badges.sh [--install|--uninstall] [--dry-run] [--yes]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="${HOME}/.tmux.conf"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
HOOK_SCRIPT="$REPO_DIR/hook_agent_state.sh"
BADGE_SCRIPT="$REPO_DIR/window_badge.sh"

# Sentinel markers — used by both install and uninstall to identify
# lines this script owns. Do not change these after shipping; existing
# installs depend on them matching.
BEGIN_MARKER='# >>> tmux-attic badges >>>'
END_MARKER='# <<< tmux-attic badges <<<'

# ---------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------
action=install
dry_run=0
assume_yes=0

print_help() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)   action=install;   shift ;;
    --uninstall) action=uninstall; shift ;;
    --dry-run)   dry_run=1;        shift ;;
    --yes|-y)    assume_yes=1;     shift ;;
    -h|--help)   print_help; exit 0 ;;
    *) echo "unknown argument: $1" >&2; print_help >&2; exit 2 ;;
  esac
done

confirm() {
  [[ $assume_yes -eq 1 || $dry_run -eq 1 ]] && return 0
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

backup() {
  local f="$1"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  cp "$f" "${f}.bak.${stamp}"
  echo "  backup: ${f}.bak.${stamp}"
}

# ---------------------------------------------------------------------
# Prereqs
# ---------------------------------------------------------------------
check_prereqs() {
  local missing=()
  command -v tmux    >/dev/null 2>&1 || missing+=("tmux")
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing required tools: ${missing[*]}" >&2
    exit 1
  fi
  command -v recon >/dev/null 2>&1 || \
    echo "note: \`recon\` not found — the polling provider will no-op, hook-driven updates still work"
}

# ---------------------------------------------------------------------
# ~/.tmux.conf
# ---------------------------------------------------------------------
tmux_block() {
cat <<EOF
$BEGIN_MARKER
# Per-window Claude Code session badges. Managed by install_badges.sh
# — do not hand-edit between these markers. To remove cleanly:
#   $REPO_DIR/install_badges.sh --uninstall
set -ag window-status-format         ' #($BADGE_SCRIPT #{window_id})'
set -ag window-status-current-format ' #($BADGE_SCRIPT #{window_id})'
$END_MARKER
EOF
}

tmux_conf_install() {
  echo "[tmux.conf] ${TMUX_CONF}"
  if [[ ! -f "$TMUX_CONF" ]]; then
    echo "  not found — skipping (create it or install tmux first)"
    return
  fi
  if grep -Fq "$BEGIN_MARKER" "$TMUX_CONF"; then
    echo "  already installed (markers found)"
    return
  fi
  # Heuristic safety: catch manual installs without markers so we
  # don't duplicate the window-status-format lines.
  if grep -Fq "$BADGE_SCRIPT" "$TMUX_CONF"; then
    echo "  WARNING: $BADGE_SCRIPT is referenced in $TMUX_CONF but not"
    echo "  inside managed markers. Refusing to add a second block."
    echo "  Wrap the existing lines with:"
    echo "    $BEGIN_MARKER"
    echo "    ...existing set -ag window-status-format lines..."
    echo "    $END_MARKER"
    echo "  then rerun. Or uninstall first."
    return
  fi
  if [[ $dry_run -eq 1 ]]; then
    echo "  would append:"
    tmux_block | sed 's/^/    /'
    return
  fi
  backup "$TMUX_CONF"
  {
    echo ""
    tmux_block
  } >> "$TMUX_CONF"
  echo "  appended block"
}

tmux_conf_uninstall() {
  echo "[tmux.conf] ${TMUX_CONF}"
  if [[ ! -f "$TMUX_CONF" ]]; then
    echo "  not found"
    return
  fi
  if ! grep -Fq "$BEGIN_MARKER" "$TMUX_CONF"; then
    echo "  no managed block (nothing to remove)"
    return
  fi
  if [[ $dry_run -eq 1 ]]; then
    echo "  would strip lines between $BEGIN_MARKER .. $END_MARKER"
    return
  fi
  backup "$TMUX_CONF"
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    index($0, b) { skip=1; next }
    index($0, e) { skip=0; next }
    !skip
  ' "$TMUX_CONF" > "${TMUX_CONF}.tmp"
  mv "${TMUX_CONF}.tmp" "$TMUX_CONF"
  echo "  removed"
}

# ---------------------------------------------------------------------
# ~/.claude/settings.json
# ---------------------------------------------------------------------
# The JSON edit is delegated to a single Python block per action so
# we never hand-craft JSON from shell.
settings_install() {
  echo "[settings.json] ${CLAUDE_SETTINGS}"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "  not found — create Claude Code first, then rerun"
    return
  fi
  if [[ $dry_run -eq 1 ]]; then
    DRY=1 HOOK_SCRIPT="$HOOK_SCRIPT" python3 "$REPO_DIR/install_badges_settings.py" "$CLAUDE_SETTINGS" install 2>/dev/null || \
    HOOK_SCRIPT="$HOOK_SCRIPT" python3 -c "
import json, os, sys
with open(sys.argv[1]) as f: d = json.load(f)
script = os.environ['HOOK_SCRIPT']
events = {'UserPromptSubmit': ['off','running'], 'PermissionRequest': ['needs-input'], 'Stop': ['done']}
def has(arr, state):
    needle = f'{script} --state {state}'
    return any(h.get('command') == needle for g in arr or [] for h in g.get('hooks', []))
pending = []
for ev, states in events.items():
    for st in states:
        if not has(d.get('hooks', {}).get(ev, []), st):
            pending.append(f'{ev} -> --state {st}')
if pending:
    print('  would add:', *pending, sep='\n    ')
else:
    print('  already installed')
" "$CLAUDE_SETTINGS"
    return
  fi
  backup "$CLAUDE_SETTINGS"
  HOOK_SCRIPT="$HOOK_SCRIPT" python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
script = os.environ["HOOK_SCRIPT"]

def cmd(state):   return f"{script} --state {state}"
def entry(state): return {"matcher": "", "hooks": [{"type": "command", "command": cmd(state)}]}
def has(arr, state):
    needle = cmd(state)
    return any(h.get("command") == needle for g in arr or [] for h in g.get("hooks", []))

with open(path) as f:
    d = json.load(f)

H = d.setdefault("hooks", {})
added = []

# UserPromptSubmit: off then running (first clears any lingering done
# indicator, second marks the session as actively running).
for ev, states in [("UserPromptSubmit", ["off", "running"]),
                   ("PermissionRequest", ["needs-input"]),
                   ("Stop", ["done"])]:
    H.setdefault(ev, [])
    for st in states:
        if not has(H[ev], st):
            H[ev].append(entry(st))
            added.append(f"{ev} -> --state {st}")

with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")

if added:
    print("  added:", *added, sep="\n    ")
else:
    print("  already installed")
PY
}

settings_uninstall() {
  echo "[settings.json] ${CLAUDE_SETTINGS}"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "  not found"
    return
  fi
  if [[ $dry_run -eq 1 ]]; then
    HOOK_SCRIPT="$HOOK_SCRIPT" python3 -c "
import json, os, sys
with open(sys.argv[1]) as f: d = json.load(f)
script = os.environ['HOOK_SCRIPT']
matching = []
for ev, groups in d.get('hooks', {}).items():
    for g in groups:
        for h in g.get('hooks', []):
            if (h.get('command', '')).startswith(script):
                matching.append(f'{ev}: {h[\"command\"]}')
if matching:
    print('  would remove:', *matching, sep='\n    ')
else:
    print('  nothing to remove')
" "$CLAUDE_SETTINGS"
    return
  fi
  backup "$CLAUDE_SETTINGS"
  HOOK_SCRIPT="$HOOK_SCRIPT" python3 - "$CLAUDE_SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
script = os.environ["HOOK_SCRIPT"]

with open(path) as f:
    d = json.load(f)

removed = 0
for ev in list(d.get("hooks", {}).keys()):
    new_groups = []
    for g in d["hooks"][ev]:
        kept_hooks = []
        for h in g.get("hooks", []):
            if (h.get("command", "")).startswith(script):
                removed += 1
            else:
                kept_hooks.append(h)
        if kept_hooks:
            g["hooks"] = kept_hooks
            new_groups.append(g)
    if new_groups:
        d["hooks"][ev] = new_groups
    else:
        del d["hooks"][ev]

if not d.get("hooks"):
    d.pop("hooks", None)

with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")

print(f"  removed {removed} hook entries")
PY
}

# ---------------------------------------------------------------------
# Post-install: try to reload tmux so changes are visible immediately.
# ---------------------------------------------------------------------
maybe_reload_tmux() {
  [[ $dry_run -eq 1 ]] && return
  if [[ -z "${TMUX:-}" ]]; then
    echo "note: not inside tmux; reload with 'tmux source-file ~/.tmux.conf' after attaching"
    return
  fi
  if tmux source-file "$TMUX_CONF" 2>/dev/null; then
    echo "tmux config reloaded"
  else
    echo "tmux source-file failed; reload manually"
  fi
}

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------
check_prereqs
echo ""

case "$action" in
  install)
    echo "Install tmux-attic badges (source: $REPO_DIR)"
    echo "  will modify: $TMUX_CONF"
    echo "  will modify: $CLAUDE_SETTINGS"
    echo "  dry-run: $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    tmux_conf_install
    settings_install
    echo ""
    maybe_reload_tmux
    echo ""
    echo "Done. Try: attach to tmux, watch the status bar for per-window badges."
    ;;
  uninstall)
    echo "Uninstall tmux-attic badges"
    echo "  will modify: $TMUX_CONF"
    echo "  will modify: $CLAUDE_SETTINGS"
    echo "  dry-run: $([[ $dry_run -eq 1 ]] && echo yes || echo no)"
    echo ""
    confirm "Proceed?" || { echo "aborted."; exit 1; }
    echo ""
    tmux_conf_uninstall
    settings_uninstall
    echo ""
    maybe_reload_tmux
    echo ""
    echo "Done. Plugin files in this repo are untouched — delete manually if no longer wanted."
    ;;
esac
