#!/usr/bin/env bash
# Persistent per-window / per-pane scratchpad notes, opened in $EDITOR
# inside a tmux popup.
#
# Usage (via keybinding):
#   scratchpad.sh window   open the note for the current window
#   scratchpad.sh pane     open the note for the current pane
# Internal:
#   scratchpad.sh attach <note_file> <inner_session>
#
# Notes are markdown files under $SAVE_DIR/notes/<session>/, keyed by
# window (and optionally pane) index — the same identifiers
# save_session.sh/restore_session.sh preserve, so a note re-associates
# with its window across a save/restore cycle without touching the
# upstream save-file format.
#
# The popup attaches a nested tmux session (same server) running the
# editor. C-q detaches: the popup closes but the editor keeps running,
# so reopening is instant. Quitting the editor ends the inner session
# and closes the popup too. Editor resolution:
# @session-manager-scratchpad-editor > $EDITOR > server-wide EDITOR > vi.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit

resolve_editor() {
	local editor
	editor=$(tmux show-option -gqv "@session-manager-scratchpad-editor")
	[[ -z "$editor" ]] && editor="${EDITOR:-}"
	[[ -z "$editor" ]] && editor=$(tmux show-environment -g EDITOR 2>/dev/null | sed -n 's/^EDITOR=//p')
	echo "${editor:-vi}"
}

if [[ "${1:-}" == "attach" ]]; then
	note_file=$2
	inner_session=$3
	editor=$(resolve_editor)
	# The popup shell runs inside tmux; clear $TMUX so the nested attach
	# is allowed. key-table "scratchpad" carries the C-q → detach binding
	# (registered in session_manager.tmux); unbound keys fall through to
	# the editor as usual.
	unset TMUX
	exec tmux new-session -A -s "$inner_session" \
		"exec $editor $(printf '%q' "$note_file")" \; \
		set-option key-table scratchpad \; \
		set-option status off
fi

source common_utils.sh

scope=${1:-window}
window_idx=$(tmux display-message -p "#{window_index}")
window_name=$(tmux display-message -p "#{window_name}")

note_dir="$SAVE_DIR/notes/$CURRENT_SESSION"
if [[ "$scope" == "pane" ]]; then
	pane_idx=$(tmux display-message -p "#{pane_index}")
	note_file="$note_dir/window_${window_idx}_pane_${pane_idx}.md"
	label="$CURRENT_SESSION:$window_idx.$pane_idx ($window_name)"
else
	note_file="$note_dir/window_${window_idx}.md"
	label="$CURRENT_SESSION:$window_idx ($window_name)"
fi

mkdir -p "$note_dir"
[[ -f "$note_file" ]] || printf '# %s\n\n' "$label" > "$note_file"

# Session names may not contain '.' or ':'; derive a unique inner name
# from the note's path relative to the notes root.
inner_session=$(printf '_scratch_%s' "${note_file#"$SAVE_DIR/notes/"}" | tr './: ' '____')

exec tmux display-popup -E -w 80% -h 75% \
	-T " scratchpad: $label — C-q closes " \
	"$(printf '%q' "$(pwd)/scratchpad.sh") attach $(printf '%q' "$note_file") $(printf '%q' "$inner_session")"
