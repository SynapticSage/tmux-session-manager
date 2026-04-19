#!/usr/bin/env bash
# Toggle @recon-ignore on the current tmux pane. When set to "on", the
# recon_cycle.sh wrappers skip this pane (in both modes) until it's
# unmarked. Status-bar blurb confirms the new state.
#
# Storage: pane-scoped tmux user option. Lives and dies with the pane,
# so there's no stale state to garbage-collect when panes close.

set -euo pipefail

TMUX_BIN=/opt/homebrew/bin/tmux

pane=$("$TMUX_BIN" display-message -p '#{pane_id}')
label=$("$TMUX_BIN" display-message -p '#{session_name}:#{window_index}.#{pane_index}')
state=$("$TMUX_BIN" display-message -p -t "$pane" '#{@recon-ignore}')

if [[ "$state" == "on" ]]; then
  # -u unsets the option entirely rather than setting it to "off", which
  # keeps format-string checks simple (truthy == "on", everything else
  # is "not ignored").
  "$TMUX_BIN" set-option -p -t "$pane" -u '@recon-ignore'
  "$TMUX_BIN" display-message "recon: $label back in cycle"
else
  "$TMUX_BIN" set-option -p -t "$pane" '@recon-ignore' 'on'
  "$TMUX_BIN" display-message "recon: $label ignored (skipped in cycle)"
fi
