# Version
export VERSION="1.2.0"

# Get the current tmux session name.
CURRENT_SESSION=$(
	if [ "$(tmux display-message -p "#{session_grouped}")" = 0 ]; then
		tmux display-message -p "#{session_name}"
	else
		tmux display-message -p "#{session_group}"
	fi
)

# Separator in save files
export SEPARATOR=$'\t'

# Get the value of a tmux option or a default value if the option is not set.
# Usage: get_tmux_option "name of option" "default value"
get_tmux_option() {
	local -r option_name="$1"
	local -r default_value="$2"
	local -r tmux_value=$(tmux show-option -gqv "$option_name")
	if [ -n "$tmux_value" ]; then
		echo "$tmux_value"
	else
		echo "$default_value"
	fi
}

# Get the save directory from the tmux options and expand $HOME.
SAVE_DIR=$(get_tmux_option "@session-manager-save-dir" "${HOME}/.local/share/tmux/sessions" | sed "s,\$HOME,$HOME,g; s,\~,$HOME,g")
mkdir -p "$SAVE_DIR"
export SAVE_DIR

# Get the path for the new save file.
NEW_SAVE_FILE="${SAVE_DIR}/${CURRENT_SESSION}_$(date +"%Y-%m-%dT%H:%M:%S")"
export NEW_SAVE_FILE

# Get the path for the last save file for this session.
export LAST_SAVE_FILE="${SAVE_DIR}/${CURRENT_SESSION}_last"

new_spinner() {
	local current=0
	local -r chars="/-\|"
	while true; do
		tmux display-message -- "${chars:$current:1} $1"
		current=$(((current + 1) % 4))
		sleep 0.1
	done
}

# Start a spinner with a message.
# Usage: start_spinner "Some message"
start_spinner() {
	new_spinner "$1"&
	export SPINNER_PID=$!
}

# Stop the current spinner and display a message.
# Usage: stop_spinner "Some message"
stop_spinner() {
	kill "$SPINNER_PID"
	tmux display-message "$1"
}

# Open selection for list of sessions
# Usage: select_session "$(get_sessions)"
select_session() {
	local -r sessions=$(echo "$1" | sort | uniq)
	if command -v fzf 1>/dev/null; then
		echo "$sessions" | fzf
	else
		PS3="Select session or 0 to cancel: "
		select session in $sessions; do
			if (( REPLY == 0 )); then
				exit
			elif (( REPLY > 0 && REPLY <= $(echo "$sessions" | wc -w) )); then
				echo "$session"
				break
			fi
		done
	fi
}

# ============================================================================
# Window-level operations (move/load individual windows)
# ============================================================================

# Check if this is the last window in the session
# Returns 0 (true) if last window, 1 (false) otherwise
is_last_window() {
	local count
	count=$(tmux list-windows | wc -l)
	[[ "$count" -eq 1 ]]
}

# Get list of target sessions for move operation
# Output: session names, saved-only sessions marked with [saved]
get_move_targets() {
	local current_session
	current_session=$(tmux display-message -p "#{session_name}")

	# Running sessions (except current)
	tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^${current_session}$"

	# Saved sessions not currently running
	for file in "$SAVE_DIR"/*_last; do
		[[ ! -f "$file" ]] && continue
		local name
		name=$(basename "${file%%_last}")
		if ! tmux has-session -t "$name" 2>/dev/null; then
			printf "%s\t[saved]\n" "$name"
		fi
	done
}

# Get list of windows from a session file
# Usage: get_windows_from_file "/path/to/file"
get_windows_from_file() {
	local file="$1"
	awk -F"$SEPARATOR" '$1=="window" {printf "%s: %s\n", $2, $3}' "$file"
}

# Get windows from a session (running or saved)
# Usage: get_windows_from_session "session_name" "is_saved"
# Returns: "index: name" format for each window
get_windows_from_session() {
	local session="$1"
	local is_saved="$2"

	if [[ "$is_saved" == "true" ]]; then
		get_windows_from_file "$SAVE_DIR/${session}_last"
	else
		tmux list-windows -t "$session" -F "#{window_index}: #{window_name}"
	fi
}

# Save current window to a session file
# Usage: save_window_to_file "session_name"
save_window_to_file() {
	local target_session="$1"
	local target_file="$SAVE_DIR/${target_session}_last"
	local S=$SEPARATOR

	local window_idx
	window_idx=$(tmux display-message -p "#{window_index}")

	# Capture window line
	local window_line
	window_line=$(tmux display-message -p "window${S}#{window_index}${S}#{window_name}${S}#{window_layout}${S}0")

	# Capture pane data
	local pane_data=""
	local pane_format="#{pane_index}${S}#{pane_current_path}${S}#{pane_active}${S}#{pane_pid}"

	while IFS=$S read -r pane_idx pane_path pane_active pane_pid; do
		# Get child process command (if any)
		local cmd=""
		local child_pids
		child_pids=$(ps -o pid= -o ppid= | awk -v ppid="$pane_pid" '$2 == ppid {print $1}' | head -1)
		if [[ -n "$child_pids" ]]; then
			cmd=$(ps -o args= -p "$child_pids" 2>/dev/null | head -1)
		fi

		pane_data+="pane${S}${pane_idx}${S}${pane_path}${S}${pane_active}${S}${window_idx}${S}${cmd}"$'\n'
	done < <(tmux list-panes -t ":$window_idx" -F "$pane_format")

	# Create file with header if it doesn't exist
	if [[ ! -f "$target_file" ]]; then
		local session_path
		session_path=$(tmux display-message -p "#{pane_current_path}")
		echo "version${S}$VERSION" > "$target_file"
		echo "$session_path" >> "$target_file"
	fi

	# Append window and pane data
	echo "$window_line" >> "$target_file"
	printf "%s" "$pane_data" >> "$target_file"
}

# Load a window from a session file into current session
# Usage: load_window_from_file "/path/to/file" "window_index"
load_window_from_file() {
	local source_file="$1"
	local source_widx="$2"
	local S=$SEPARATOR

	# Extract window line
	local win_line
	win_line=$(awk -F"$S" -v idx="$source_widx" '$1=="window" && $2==idx {print; exit}' "$source_file")

	if [[ -z "$win_line" ]]; then
		tmux display-message "Error: Window $source_widx not found in file"
		return 1
	fi

	local win_name win_layout
	IFS=$S read -r _ _ win_name win_layout _ <<< "$win_line"

	# Find next available window index in current session
	local target_idx
	target_idx=$(( $(tmux list-windows -F "#{window_index}" | sort -n | tail -1) + 1 ))

	# Extract and create panes for this window
	local first_pane=true
	local pane_count=0

	while IFS=$S read -r _ pane_idx pane_path pane_active _ pane_cmd; do
		if $first_pane; then
			tmux new-window -t ":$target_idx" -n "$win_name" -c "$pane_path"
			first_pane=false
		else
			tmux split-window -t ":$target_idx" -c "$pane_path"
		fi

		# Run command if present and not just shell markers
		if [[ -n "$pane_cmd" && "$pane_cmd" != "''" && "$pane_cmd" != "' '" ]]; then
			tmux send-keys -t ":$target_idx" "$pane_cmd" Enter
		fi

		pane_count=$((pane_count + 1))
	done < <(awk -F"$S" -v idx="$source_widx" '$1=="pane" && $5==idx' "$source_file")

	# Apply layout (must be done after all panes exist)
	if [[ -n "$win_layout" ]]; then
		tmux select-layout -t ":$target_idx" "$win_layout" 2>/dev/null || true
	fi

	tmux display-message "Loaded window '$win_name' ($pane_count panes)"
}

# Remove a window from a session file
# Usage: remove_window_from_file "/path/to/file" "window_index"
remove_window_from_file() {
	local file="$1"
	local widx="$2"
	local S=$SEPARATOR
	local tmp
	tmp=$(mktemp)

	awk -F"$S" -v idx="$widx" '
		$1 == "window" && $2 == idx { next }
		$1 == "pane" && $5 == idx { next }
		{ print }
	' "$file" > "$tmp"

	mv "$tmp" "$file"
}
