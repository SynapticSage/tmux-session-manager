#!/usr/bin/env bash
# pull_window.sh - Pull a window from any session (running or saved) into current
#
# Usage: pull_window.sh
#
# Shows a two-step picker:
#   1. Select source session (running or saved)
#   2. Select window from that session
# Then moves/loads the window into the current session

cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

CURRENT_SESSION=$(tmux display-message -p "#{session_name}")

# Step 1: Select source session
select_source_session() {
	local targets
	targets=$(get_move_targets)

	if [[ -z "$targets" ]]; then
		tmux display-message "No other sessions available"
		exit 1
	fi

	if command -v fzf &>/dev/null; then
		echo "$targets" | column -t -s $'\t' | fzf --prompt="Pull from session: " --height=40% --reverse || true
	else
		PS3="Select session (0 to cancel): "
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

# Step 2: Select window from chosen session
select_window_from() {
	local session="$1"
	local is_saved="$2"
	local windows
	windows=$(get_windows_from_session "$session" "$is_saved")

	if [[ -z "$windows" ]]; then
		tmux display-message "No windows in session '$session'"
		exit 1
	fi

	if command -v fzf &>/dev/null; then
		echo "$windows" | fzf --prompt="Select window from '$session': " --height=40% --reverse || true
	else
		PS3="Select window (0 to cancel): "
		local IFS=$'\n'
		local -a options
		mapfile -t options <<< "$windows"
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

# Main flow
source_selection=$(select_source_session)
[[ -z "$source_selection" ]] && exit 0

# Parse selection - extract session name and check if saved
source_session=$(echo "$source_selection" | awk '{print $1}')
is_saved=false
if echo "$source_selection" | grep -q '\[saved\]'; then
	is_saved=true
fi

# Select window from that session
window_selection=$(select_window_from "$source_session" "$is_saved")
[[ -z "$window_selection" ]] && exit 0

# Extract window index from "idx: name" format
window_idx="${window_selection%%:*}"
window_idx="${window_idx// /}"  # Trim whitespace
window_name="${window_selection#*: }"

# Execute the pull
if [[ "$is_saved" == "false" ]]; then
	# Source is running - use tmux move-window
	tmux move-window -s "$source_session:$window_idx" -t ":"
	tmux display-message "Pulled window '$window_name' from session '$source_session'"
else
	# Source is saved - load from file and remove
	SOURCE_FILE="$SAVE_DIR/${source_session}_last"
	load_window_from_file "$SOURCE_FILE" "$window_idx"
	remove_window_from_file "$SOURCE_FILE" "$window_idx"
	tmux display-message "Pulled window '$window_name' from saved session '$source_session'"
fi
