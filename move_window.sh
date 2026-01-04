#!/usr/bin/env bash
# move_window.sh - Move current window to another session (running or saved)
#
# Usage: move_window.sh
#
# Shows a picker with:
#   - Running sessions (can move window there directly via tmux)
#   - Saved-but-inactive sessions (marked with [saved], saves to file)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

# Get current context
CURRENT_SESSION=$(tmux display-message -p "#{session_name}")
CURRENT_WINDOW=$(tmux display-message -p "#{window_index}")
CURRENT_WINDOW_NAME=$(tmux display-message -p "#{window_name}")

# Check if this is the last window
if is_last_window; then
	tmux display-message "Cannot move: this is the last window in the session"
	exit 1
fi

# Build target list and show picker
select_target() {
	local targets
	targets=$(get_move_targets)

	if [[ -z "$targets" ]]; then
		echo ""
		return
	fi

	if command -v fzf &>/dev/null; then
		echo "$targets" | column -t -s $'\t' | fzf --prompt="Move '$CURRENT_WINDOW_NAME' to: " --height=40% --reverse
	else
		# Fallback to select menu
		PS3="Select target (0 to cancel): "
		local IFS=$'\n'
		local -a options
		mapfile -t options <<< "$targets"
		select opt in "${options[@]}"; do
			if [[ "$REPLY" == "0" ]]; then
				echo ""
				return
			elif [[ -n "$opt" ]]; then
				echo "$opt"
				return
			fi
		done
	fi
}

# Main
target=$(select_target)

if [[ -z "$target" ]]; then
	exit 0
fi

# Parse target - extract session name (first field) and check if saved
target_session=$(echo "$target" | awk '{print $1}')
is_saved=false
if echo "$target" | grep -q '\[saved\]'; then
	is_saved=true
fi

if [[ "$is_saved" == "false" ]]; then
	# Target is a running session - use native tmux move
	tmux move-window -t "$target_session:"
	tmux display-message "Moved window '$CURRENT_WINDOW_NAME' to session '$target_session'"
else
	# Target is a saved (inactive) session - save to file and kill window
	save_window_to_file "$target_session"
	tmux kill-window -t ":$CURRENT_WINDOW"
	tmux display-message "Moved window '$CURRENT_WINDOW_NAME' to saved session '$target_session'"
fi
