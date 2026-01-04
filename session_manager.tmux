#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit
source common_utils.sh

if [[ $(get_tmux_option "@session-manager-disable-fzf-warning" "off") != "on" && ! $(command -v fzf) ]]; then
	tmux display-message "Warning: fzf was not found in PATH. Recommended for tmux-session-manager. If that is intentional, you can disable this message."
	exit
fi

declare key
declare bindings

# Save
bindings=$(get_tmux_option "@session-manager-save-key" "C-s")
for key in $bindings; do
	tmux bind-key "$key" run-shell "$(pwd)/save_session.sh"
done
bindings=$(get_tmux_option "@session-manager-save-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "$(pwd)/save_session.sh"
done

# Restore
bindings=$(get_tmux_option "@session-manager-restore-key" "C-r")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/restore_session.sh'"
done
bindings=$(get_tmux_option "@session-manager-restore-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/restore_session.sh'"
done

# Archive
bindings=$(get_tmux_option "@session-manager-archive-key" "")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/archive_session.sh'"
done
bindings=$(get_tmux_option "@session-manager-archive-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/archive_session.sh'"
done

# Unarchive
bindings=$(get_tmux_option "@session-manager-unarchive-key" "")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/restore_session.sh --archived'"
done
bindings=$(get_tmux_option "@session-manager-unarchive-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/restore_session.sh --archived'"
done

# Delete
bindings=$(get_tmux_option "@session-manager-delete-key" "")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/delete_session.sh'"
done
bindings=$(get_tmux_option "@session-manager-delete-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/delete_session.sh'"
done

# Move Window (to running or saved session)
bindings=$(get_tmux_option "@session-manager-move-window-key" "C-w")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/move_window.sh'"
done
bindings=$(get_tmux_option "@session-manager-move-window-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/move_window.sh'"
done

# Load Window (from saved session, move semantics)
bindings=$(get_tmux_option "@session-manager-load-window-key" "C-y")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/load_window.sh'"
done
bindings=$(get_tmux_option "@session-manager-load-window-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/load_window.sh'"
done

# Load Window Copy (from saved session, copy semantics)
bindings=$(get_tmux_option "@session-manager-load-window-copy-key" "")
for key in $bindings; do
	tmux bind-key "$key" run-shell "tmux display-popup -E '$(pwd)/load_window.sh --copy'"
done
bindings=$(get_tmux_option "@session-manager-load-window-copy-key-root" "")
for key in $bindings; do
	tmux bind-key -n "$key" run-shell "tmux display-popup -E '$(pwd)/load_window.sh --copy'"
done
