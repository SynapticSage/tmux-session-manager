#!/usr/bin/env bash
# Browse saved sessions with live layout preview. Read-only — nothing is
# mutated regardless of which row the user selects. Esc or Enter exits.
#
# Self-invocation: when called with a session-name argument, this script
# emits that session's preview and exits. That arg-branch is what fzf's
# --preview calls per highlighted row, so we don't need a separate helper.

cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

# Preview callback — fzf invokes the script this way for each row.
if [[ -n "${1:-}" ]]; then
	render_session_preview "$SAVE_DIR/${1}_last"
	exit 0
fi

get_saved_sessions() {
	for file in "$SAVE_DIR"/*_last*; do
		if [[ "$file" =~ _last$ ]]; then
			basename "${file%%_last}"
		else
			basename "${file%%_last_archived}"
		fi
	done
}

sessions=$(get_saved_sessions | sort -u)
if [[ -z "$sessions" ]]; then
	tmux display-message "No saved sessions found."
	exit 0
fi

SELF="$(pwd)/$(basename "${BASH_SOURCE[0]}")"

if command -v fzf >/dev/null; then
	echo "$sessions" | fzf \
		--preview "$SELF {}" \
		--preview-window=right:65%:wrap \
		--prompt="preview saved session > " \
		--header="Browse with arrows or type to filter | Esc/Enter exits (read-only)" >/dev/null
else
	# Plain listing fallback when fzf isn't installed.
	for s in $sessions; do
		echo "=== $s ==="
		render_session_preview "$SAVE_DIR/${s}_last"
		echo
	done
	read -r -p "Press Enter to close..." _
fi
