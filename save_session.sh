#!/usr/bin/env bash
session_cwd="$(tmux -c pwd)"
cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

# Separator for tmux format strings
declare S=$SEPARATOR

# Tmux format string for windows
WINDOW_FORMAT="window$S#{window_index}$S#{window_name}$S#{window_layout}$S#{window_active}"

# Tmux format string for panes
PANE_FORMAT="pane$S#{pane_index}$S#{pane_current_path}$S#{pane_active}$S#{window_index}$S#{pane_pid}"

# Path B: per-pane Claude session_id capture for precise restoration.
# One `recon json` call up front yields a pane_target -> session_id
# map that the pane loop below looks up via awk. If recon isn't
# installed or fails, the map is empty and the rewriter falls back
# to `--continue` (Path A's cwd-scoped resume).
RECON_MAP=$(mktemp "${TMPDIR:-/tmp}/recon_map.XXXXXX")
trap 'rm -f "$RECON_MAP"' EXIT
if command -v recon >/dev/null 2>&1; then
	recon json 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for s in d.get("sessions", []):
    t = s.get("pane_target", "")
    sid = s.get("session_id", "")
    if t and sid:
        print(f"{t}\t{sid}")
' > "$RECON_MAP" 2>/dev/null || true
fi

start_spinner "Saving current session"
if [[ -e "${NEW_SAVE_FILE}_archived" ]]; then
	mv "${NEW_SAVE_FILE}_archived" "$NEW_SAVE_FILE"
fi
echo "version$S$VERSION" > "$NEW_SAVE_FILE"
echo "$session_cwd" >> "$NEW_SAVE_FILE"
tmux list-windows -F "$WINDOW_FORMAT" >> "$NEW_SAVE_FILE"
tmux list-panes -s -F "$PANE_FORMAT" | while IFS="$SEPARATOR" read -r line; do
	pane_pid=$(cut -f6 <<< "$line")
	# Immediate children of the pane's shell. Using awk for exact
	# PPID match avoids the false positives that `grep "^$pid"`
	# picked up (e.g. PPID 1234 matching pid=123).
	pids=$(ps -ao "ppid,pid" | awk -v p="$pane_pid" 'NR>1 && $1==p {print $2}')

	command=""
	for pid in $pids; do
		proc_cmd=""
		# NixOS' nvim wrapper hides its real args behind extra argv
		# entries that need to be stripped via /proc/$pid/cmdline.
		# Keep this special case Linux-only; every other platform
		# (including macOS, which has no /proc) falls through to the
		# portable `ps -p` path below.
		if [[ -r "/proc/$pid/cmdline" \
			&& "$(grep ^ID= /etc/os-release 2>/dev/null | cut -d'=' -f2)" == "nixos" \
			&& "$(get_tmux_option "@session-manager-diable-nixos-nvim-check" "off")" != "on" \
			&& "$(cut -d' ' -f1 <<< "$(ps -p $pid -o cmd)" | tail +2 | xargs basename)" == "nvim" ]]; then
			proc_cmd="nvim"
			while read -r arg; do
				if [ -n "$arg" ]; then
					proc_cmd+=" '$arg'"
				fi
			done <<< "$(xargs -0L1 < /proc/$pid/cmdline | tail +8)"
		else
			# Portable: `ps -p <pid> -o args=` prints the full command
			# line (program + args, space-joined) on both macOS BSD
			# and Linux. Arg boundaries are lossy for args with
			# embedded spaces — a known limitation, acceptable because
			# shell re-parses on restore and typical agent invocations
			# don't use space-bearing args.
			proc_cmd=$(ps -p "$pid" -o args= 2>/dev/null | sed 's/^ *//; s/ *$//')
		fi
		[[ -n "$proc_cmd" ]] && command="${command:+$command; }$proc_cmd"
	done

	# Agent-aware restoration: rewrite claude / codex invocations so
	# the restored pane resumes the prior session instead of spawning
	# a new one. See rewrite_agent_command in common_utils.sh.
	#
	# For claude panes, look up the specific session_id via the recon
	# map built at script start. Empty lookup → rewriter falls back
	# to --continue (works when there's only one claude per cwd).
	pane_idx=$(cut -f2 <<< "$line")
	window_idx=$(cut -f5 <<< "$line")
	pane_target="${CURRENT_SESSION}:${window_idx}.${pane_idx}"
	session_id=$(awk -F'\t' -v t="$pane_target" '$1==t {print $2; exit}' "$RECON_MAP")
	command=$(rewrite_agent_command "$command" "$session_id")

	awk -v command="$command" \
		'BEGIN {FS=OFS="\t"} {$6=command; print}'\
		<<< "$line" >> "$NEW_SAVE_FILE"
done
if ! cmp -s "$NEW_SAVE_FILE" "$LAST_SAVE_FILE"; then
	ln -sf "$NEW_SAVE_FILE" "$LAST_SAVE_FILE"
else
	rm "$NEW_SAVE_FILE"
fi
stop_spinner "Session saved"
