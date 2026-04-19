# tmux Keybinding Reference

All bindings use `Prefix` = whatever tmux prefix you have set (default `C-b`,
many configs rebind to `C-a`). `C-x` = Ctrl+x, `M-x` = Alt/Meta+x.

---

## Session Manager (SynapticSage/tmux-session-manager)

Save, restore, and manipulate whole tmux sessions — including window and
pane layouts — to disk under `~/.local/share/tmux/sessions/`.

- **`Prefix + C-s`** — Save current session (silent; no popup)
- **`Prefix + C-r`** — Restore a saved session (fzf picker in popup)
- **`Prefix + C-v`** — Browse saved sessions with live layout preview.
  Read-only — Esc or Enter just closes the popup, nothing is mutated.
  Use this to explore stale sessions before deciding between delete,
  rename, or restore.
- **`Prefix + C-d`** — Delete a saved session. fzf picker → layout
  preview (per-window name, pane count, and cwd of each pane, plus
  save timestamp) → file-list showing the blast radius → y/N confirm.
- **`Prefix + C-n`** — Rename a saved session. fzf picker → layout
  preview → prompt for new name → validation (no `/`, no leading `.`
  or `-`, no collisions with existing saved files, warning if a live
  tmux session with that name exists) → show rename plan
  (`old_base → new_base` for every file) → y/N confirm.
- **`Prefix + C-w`** — Move current window to another session (running or
  saved)
- **`Prefix + C-y`** — Load a window from a saved session into the
  current session (move semantics)
- **`Prefix + C-p`** — Pull a window from any session (running or saved)

Configurable (not bound by default):

- `@session-manager-archive-key` — archive session (move to archived list)
- `@session-manager-unarchive-key` — restore from archive
- `@session-manager-load-window-copy-key` — load window with copy
  semantics (keeps original in saved session)
- `*-root` variants of each — bind without requiring the prefix

---

## Recon (Claude Code session dashboard)

Recon scans the tmux server for live Claude Code sessions and groups them
by project. The cycle scripts live in `/Users/ryoung/Code/repos/tmux-manage/`.

- **`Prefix + g`** — Cycle to next non-Working agent (Idle **or**
  waiting-for-input). Sorts waiting-first, so if anything is waiting you
  land there on the first press. Skips panes marked with `@recon-ignore`.
- **`Prefix + C-g`** — Cycle only through agents waiting for input.
  Narrow variant of `g`. Shows `"no agents waiting for input"` in the
  status bar when nothing is waiting. Skips ignored panes.
- **`Prefix + G`** — Open the full Recon dashboard (table view) in a 90%
  popup.
- **`Prefix + i`** — Toggle `@recon-ignore` on the **current pane**.
  Silences just that one pane — other agents in the same window keep
  contributing to badge counts and the recon cycle. Overrides tmux
  default `display-message`, which duplicated status-bar info anyway.
- **`Prefix + e`** — Toggle `@recon-ignore` on the **current window**.
  Silences every pane in the window at once via tmux's pane → window
  → session inheritance — all agents inside the window stop
  contributing to badges, and the recon cycle skips them. Overrides
  tmux-text-macros' `split-window` binding; launch text macros via
  their script directly if you use them.
- **`Prefix + I`** — Open fzf popup to toggle `@recon-ignore` at
  **session** or **window** scope for a non-focused target. Overrides
  TPM's plugin-install hotkey; see *Manual TPM Invocation* below for
  replacements.

Both `i` and `e` call `recon_ignore_toggle.sh` under different
`--pane` / `--window` flags, so the scope logic lives in one place.

### How `@recon-ignore` inheritance works

tmux resolves user options through the scope chain `pane → window →
session → global`, returning the first set value. So:

- Setting the option at a session affects every pane in every window of
  that session (unless a leaf scope explicitly sets `off` to override).
- Unsetting at a leaf does not "lift" a parent's ignore — to un-ignore a
  window whose session is marked, unmark the session.

---

## Manual TPM Invocation

`Prefix + I` is taken by the recon ignore picker, so these commands
replace TPM's plugin-management hotkeys. Run from any shell:

- `~/.tmux/plugins/tpm/bin/install_plugins` — install new `@plugin` lines
- `~/.tmux/plugins/tpm/bin/update_plugins all` — update all installed plugins
- `~/.tmux/plugins/tpm/bin/clean_plugins` — remove plugins no longer listed

---

## Vi-style Pane Navigation (custom)

From `~/.tmux.conf` — vi-style movement instead of tmux defaults for
pane selection and resizing.

- **`Prefix + h / j / k / l`** — Select pane left / down / up / right
- **`Prefix + H / J / K / L`** — Resize pane by 5 cells in that direction
  (repeatable via `-r` flag: hold the prefix, press repeatedly)
- **`Prefix + B`** — `last-window` (jump back to previous window)

---

## Copy Mode

- **vi mode enabled** (`set-window-option -g mode-keys vi`)
- **`Prefix + [`** — Enter copy mode (tmux default)
- In copy mode: **`y`** and **`Enter`** copy selection and pipe to
  `xclip -in -selection clipboard` (overrides tmux default of just
  copying to tmux buffer)

---

## Root-Level Bindings (no prefix required)

- **`Shift-Left`** — Swap current window with previous (`swap-window -t -1`)
- **`Shift-Right`** — Swap current window with next (`swap-window -t +1`)

---

## Plugin-Provided Bindings (not customized)

These come with their plugins. Listed for completeness:

- **tmux-sessionist** — `Prefix + g` (originally — now overridden by
  recon), `Prefix + C / X / S / @ / .` for session create/kill/switch/
  promote/rename. Check plugin docs for full list.
- **tmux-resurrect** — `Prefix + C-s` / `Prefix + C-r` (conflicts with
  session-manager; session-manager's bindings win because they're
  configured later).
- **tmux-copycat** — `Prefix + /` (regex search), `Prefix + C-f` (file
  search), various others for URL / git-hash / digit hunting.
- **tmux-yank** — `y` in copy mode (overridden above to pipe through
  xclip).
- **tmux-notify** — no keybindings; watches pane output and displays a
  tmux message on completion.

---

## Customization Hints

- All recon wrapper scripts live at `/Users/ryoung/Code/repos/tmux-manage/recon_*.sh`.
- All session-manager operations use `@session-manager-*-key` tmux
  options — override these before TPM runs to change bindings.
- Setting a session-manager key option with `set -g @session-manager-X-key ''`
  (empty) disables the binding.
- After editing `@session-manager-*` options, run
  `tmux run-shell '~/.tmux/plugins/tmux-session-manager/session_manager.tmux'`
  to re-register bindings without restarting tmux.
