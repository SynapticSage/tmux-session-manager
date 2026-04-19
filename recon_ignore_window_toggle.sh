#!/usr/bin/env bash
# Toggle @recon-ignore on the current tmux WINDOW (vs the pane-scope
# sibling recon_ignore_toggle.sh). Window-scope ignores cascade to
# every pane in the window via tmux's standard inheritance chain
# (pane -> window -> session -> global), so marking a window silences
# every agent inside it in one keystroke — both in the recon cycle
# rotation and in per-window badge statistics.
#
# To restore a window: rerun this binding; the option flips back off
# via `set-option -u` (unset), which keeps format-string checks
# simple (truthy == "on", everything else == "not ignored").
#
# Inheritance note: if a SESSION is ignored, every window under it is
# effectively ignored regardless of per-window state. Unsetting a
# window's ignore won't override a session-level ignore — the user
# must clear the session via recon_ignore_picker.sh (prefix + I).

set -euo pipefail

TMUX_BIN=/opt/homebrew/bin/tmux

target=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}')
window_name=$("$TMUX_BIN" display-message -p '#W')

# -wv reads the option's value AT THE WINDOW SCOPE ONLY (not the
# inherited value), so we flip only the explicit per-window setting
# rather than being misled by a session-level value.
state=$("$TMUX_BIN" show-options -wvt "$target" '@recon-ignore' 2>/dev/null || true)

if [[ "$state" == "on" ]]; then
  "$TMUX_BIN" set-option -w -t "$target" -u '@recon-ignore'
  "$TMUX_BIN" display-message "recon: window $target ($window_name) back in cycle"
else
  "$TMUX_BIN" set-option -w -t "$target" '@recon-ignore' 'on'
  "$TMUX_BIN" display-message "recon: window $target ($window_name) ignored (all panes muted)"
fi
