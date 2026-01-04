#!/usr/bin/env bash
# load_window.sh - Load a window from a saved session into current session
#
# Usage: load_window.sh [--copy]
#
# Options:
#   --copy    Keep window in source file after loading (copy semantics)
#             Default is move semantics (removes from source)

cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

# Parse arguments
COPY_MODE=false
if [[ "${1:-}" == "--copy" ]]; then
	COPY_MODE=true
fi

# Get list of saved sessions
get_saved_sessions() {
	for file in "$SAVE_DIR"/*_last; do
		[[ -f "$file" ]] && basename "${file%%_last}"
	done
}

# Select a session file
select_source_session() {
	local sessions
	sessions=$(get_saved_sessions)

	if [[ -z "$sessions" ]]; then
		tmux display-message "No saved sessions found"
		exit 1
	fi

	if command -v fzf &>/dev/null; then
		echo "$sessions" | fzf --prompt="Load from session: " --height=40% --reverse || true
	else
		PS3="Select session (0 to cancel): "
		local IFS=$'\n'
		local -a options
		mapfile -t options <<< "$sessions"
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

# Select a window from a session file
select_window() {
	local file="$1"
	local windows
	windows=$(get_windows_from_file "$file")

	if [[ -z "$windows" ]]; then
		tmux display-message "No windows in session file"
		exit 1
	fi

	if command -v fzf &>/dev/null; then
		echo "$windows" | fzf --prompt="Select window: " --height=40% --reverse || true
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

# Main
source_session=$(select_source_session)
[[ -z "$source_session" ]] && exit 0

SOURCE_FILE="$SAVE_DIR/${source_session}_last"

if [[ ! -f "$SOURCE_FILE" ]]; then
	tmux display-message "Session file not found: $SOURCE_FILE"
	exit 1
fi

selected=$(select_window "$SOURCE_FILE")
[[ -z "$selected" ]] && exit 0

# Extract window index from "idx: name" format
WINDOW_IDX="${selected%%:*}"
WINDOW_IDX="${WINDOW_IDX// /}"  # Trim whitespace

# Load the window
load_window_from_file "$SOURCE_FILE" "$WINDOW_IDX"

# Remove from source file unless copy mode
if [[ "$COPY_MODE" == "false" ]]; then
	remove_window_from_file "$SOURCE_FILE" "$WINDOW_IDX"
	tmux display-message "Window loaded and removed from '$source_session'"
else
	tmux display-message "Window loaded (copy mode - kept in '$source_session')"
fi
