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

session_name=$(select_session "$(get_saved_sessions)")
if [[ -z "$session_name" ]]; then
	exit 0
fi

# Collect every file the rm will unlink, so the user can see the blast
# radius before confirming. Glob patterns mirror what the rm line deletes.
victims=()
for candidate in \
	"$SAVE_DIR/${session_name}_last" \
	"$SAVE_DIR/${session_name}_last_archived"; do
	[[ -e "$candidate" ]] && victims+=("$candidate")
done
for f in "$SAVE_DIR/${session_name}"_[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]; do
	[[ -e "$f" ]] && victims+=("$f")
done

if [[ ${#victims[@]} -eq 0 ]]; then
	tmux display-message "No saved files found for session '$session_name'"
	exit 0
fi

printf '\n\033[1;36m--- Session "%s" ---\033[0m\n\n' "$session_name"
render_session_preview "$SAVE_DIR/${session_name}_last"

printf '\n\033[1;31m--- Deleting %d file(s): ---\033[0m\n\n' "${#victims[@]}"
printf '  %s\n' "${victims[@]}"
printf '\n'
read -r -p "Confirm deletion? [y/N] " response

case "$response" in
	[yY]|[yY][eE][sS])
		start_spinner "Deleting session"
		rm -f -- "${victims[@]}"
		stop_spinner "Session '$session_name' deleted"
		;;
	*)
		echo "Aborted — no files deleted."
		sleep 1.5
		;;
esac
