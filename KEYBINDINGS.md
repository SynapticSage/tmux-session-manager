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
- **`Prefix + a`** — Scratchpad note for the current **window**, opened
  in `$EDITOR` inside a popup. **`C-q`** detaches the popup (editor keeps
  running in the background — reopening is instant); quitting the editor
  closes it fully. Notes persist as markdown under
  `<save-dir>/notes/<session>/`, keyed by window index, so they
  re-associate after a save/restore cycle. The latest save's preview
  (`C-v` / `C-d` / `C-n`) shows each note's first line.
- **`Prefix + A`** — Same, scoped to the current **pane**
  (`window_<w>_pane_<p>.md`). Use sparingly — pane indexes are less
  stable than window indexes.

Configurable (not bound by default):

- `@session-manager-archive-key` — archive session (move to archived list)
- `@session-manager-unarchive-key` — restore from archive
- `@session-manager-load-window-copy-key` — load window with copy
  semantics (keeps original in saved session)
- `@session-manager-scratchpad-key` / `@session-manager-scratchpad-pane-key`
  — override the `a` / `A` scratchpad defaults
- `@session-manager-scratchpad-editor` — force a specific editor for
  scratchpad notes (default: `$EDITOR`, falling back to `vi`)
- `*-root` variants of each — bind without requiring the prefix

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

- **tmux-sessionist** — `Prefix + g` (if you also install
  tmux-agent-tracker, `g` is taken by the recon cycle there),
  `Prefix + C / X / S / @ / .` for session create/kill/switch/
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

- All session-manager operations use `@session-manager-*-key` tmux
  options — override these before TPM runs to change bindings.
- Setting a session-manager key option with `set -g @session-manager-X-key ''`
  (empty) disables the binding.
- After editing `@session-manager-*` options, run
  `tmux run-shell '~/.tmux/plugins/tmux-session-manager/session_manager.tmux'`
  to re-register bindings without restarting tmux.
