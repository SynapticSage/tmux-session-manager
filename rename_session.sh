#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

get_saved_sessions() {
	for file in "$SAVE_DIR"/*_last*; do
		if [[ "$file" =~ _last$ ]]; then
			basename "${file%%_last}"
		else
			basename "${file%%_last_archived}"
		fi
	done
}

old_name=$(select_session "$(get_saved_sessions)")
if [[ -z "$old_name" ]]; then
	exit 0
fi

# Show preview so the user sees what they're about to rename. Resurrect
# save files don't encode the session name internally — only in filenames —
# so this preview is purely for confirmation, not for editing content.
printf '\n\033[1;36m--- Session "%s" ---\033[0m\n\n' "$old_name"
render_session_preview "$SAVE_DIR/${old_name}_last"

# Collect all files belonging to this session (matches delete_session.sh).
files=()
for candidate in \
	"$SAVE_DIR/${old_name}_last" \
	"$SAVE_DIR/${old_name}_last_archived"; do
	[[ -e "$candidate" ]] && files+=("$candidate")
done
for f in "$SAVE_DIR/${old_name}"_[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]; do
	[[ -e "$f" ]] && files+=("$f")
done

if [[ ${#files[@]} -eq 0 ]]; then
	tmux display-message "No saved files found for session '$old_name'"
	exit 0
fi

printf '\n\033[1;33m--- %d file(s) will be renamed ---\033[0m\n' "${#files[@]}"
printf '\nCurrent name: %s\n' "$old_name"
read -r -p "New name (empty to cancel): " new_name

if [[ -z "$new_name" ]]; then
	echo "Aborted — no rename performed."
	sleep 1
	exit 0
fi

if [[ "$new_name" == "$old_name" ]]; then
	echo "New name matches current name. Nothing to do."
	sleep 1
	exit 0
fi

# Reject path separators and names that would be hidden or flag-like.
# Filenames with '/' can't coexist in the save dir; leading dot or '-'
# creates confusing ls output and potential shell/arg-parsing footguns.
if [[ "$new_name" == */* || "$new_name" == .* || "$new_name" == -* ]]; then
	echo "Invalid name. Must not contain '/' or start with '.' or '-'."
	sleep 2
	exit 1
fi

# Refuse if any target file already exists, to avoid half-renamed state.
conflicts=()
[[ -e "$SAVE_DIR/${new_name}_last" ]]          && conflicts+=("${new_name}_last")
[[ -e "$SAVE_DIR/${new_name}_last_archived" ]] && conflicts+=("${new_name}_last_archived")
for f in "$SAVE_DIR/${new_name}"_[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]; do
	[[ -e "$f" ]] && conflicts+=("$(basename "$f")")
done

if [[ ${#conflicts[@]} -gt 0 ]]; then
	echo
	echo "Target name collides with existing saved files:"
	printf '  %s\n' "${conflicts[@]}"
	echo
	echo "Rename refused. Pick a different name or delete the existing session first."
	sleep 3
	exit 1
fi

# Soft warning if the target matches a currently running tmux session.
# Not a blocker — user may have intentionally killed/renamed the live one —
# but next save of that running session would merge into these renamed
# files, so flag it.
if tmux has-session -t "=$new_name" 2>/dev/null; then
	echo
	echo "Note: a tmux session named '$new_name' is currently running."
	echo "Future saves of that live session will append to the renamed files."
	read -r -p "Proceed anyway? [y/N] " ack
	case "$ack" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; sleep 1; exit 0 ;; esac
fi

# Build the rename plan: for each source file, compute the new basename by
# stripping the old_name prefix (substring-based, so pattern metacharacters
# in session names don't misbehave) and prepending the new name.
echo
echo "Rename plan:"
declare -a old_paths new_paths
for f in "${files[@]}"; do
	old_base=$(basename "$f")
	suffix="${old_base:${#old_name}}"  # everything after the old name
	new_base="${new_name}${suffix}"
	old_paths+=("$f")
	new_paths+=("$SAVE_DIR/$new_base")
	printf '  %s  ->  %s\n' "$old_base" "$new_base"
done
echo
read -r -p "Proceed? [y/N] " response

case "$response" in
	[yY]|[yY][eE][sS])
		start_spinner "Renaming session"
		for i in "${!old_paths[@]}"; do
			mv -- "${old_paths[$i]}" "${new_paths[$i]}"
		done
		stop_spinner "Session renamed: $old_name -> $new_name"
		;;
	*)
		echo "Aborted — no files renamed."
		sleep 1
		;;
esac
