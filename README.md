# tmux-attic

> Curate your tmux sessions — save, browse, preview, rename, delete, and
> move windows between sessions with layout previews at every destructive
> step.

Saving and restoring tmux sessions is a solved problem
([tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) does
it well). The unsolved problem is what happens *after* you've been
saving sessions for a few months: a folder of identically-shaped JSON
blobs named after long-forgotten projects, each potentially holding
live work you haven't thought about in weeks. The only way to remember
what's in them is to restore each one — which kills your current state
or spawns new sessions you didn't want.

`tmux-attic` treats saved sessions as first-class objects you can
inspect in place. Every save carries its windows, panes, working
directories, and running commands. A shared preview renderer shows the
session's shape — window names, pane counts, per-pane cwds, save
timestamp — in the same format whether you're browsing, deleting, or
renaming. You decide before you act.

Built on top of
[PhilVoel/tmux-session-manager](https://github.com/PhilVoel/tmux-session-manager),
with its save-file format preserved so existing saves load unchanged.

## Session Lifecycle Tools

Three read/mutate operations for managing saved sessions on disk,
addressing the "I have a pile of saved sessions and don't remember what
each one contains" problem. All three share a common layout preview:
save timestamp, session cwd, per-window name and pane count, per-pane
cwd — enough to recognize a session at a glance without restoring it.

### View (`prefix + C-v`)

Browse saved sessions with **live preview** as you move through the
fzf list. Read-only — Esc or Enter just closes the popup. Use this to
explore stale sessions before deciding between delete, rename, and
restore.

### Delete (`prefix + C-d`)

Pick a session, see its layout preview, then see **every file** slated
for unlink (active save plus all timestamped backups — often 20+ for
long-lived sessions), then `y/N` to confirm. No accidents.

### Rename (`prefix + C-n`)

Pick a session, see its preview, enter a new name. Validates against
collisions with existing saved files (refuses rather than overwrites),
warns if the target name matches a currently-running tmux session
(future `save` would merge into the renamed files), shows the full
rename plan (`old_base → new_base` for every file), then `y/N`.

## Window-Level Operations

Move and load individual windows between sessions — useful when you want
to reshape a session without killing its other work:

### Move Window (`prefix + C-w`)

Move the current window to another session (running or saved):

- Shows a picker with all running sessions and saved-but-inactive sessions
- Saved sessions are marked with `[saved]`
- If target is running: uses native `tmux move-window`
- If target is saved/inactive: appends window to the session's save file and closes it

**Use case:** Park a window in a "buffer" session for later without killing your work.

### Load Window (`prefix + C-y`)

Load a window from any saved session into the current session:

- Pick a saved session file
- Pick a window from that session
- Window is created in the current session with all panes and layout restored
- By default, the window is **removed** from the source file (move semantics)

### Load Window Copy (`prefix + M-y` or configure)

Same as Load Window, but keeps the window in the source file (copy semantics).

### Pull Window (`prefix + C-p`)

Pull a window from **any** session (running or saved) into the current session:

- **Step 1**: Pick a source session (running sessions and saved sessions shown together)
- **Step 2**: Pick a window from that session
- Window is moved into current session and removed from source
- Works seamlessly whether source is running or saved

**Use case:** Unified interface to grab windows from anywhere - no need to remember if the source is running or saved.

### Scratchpad Notes (`prefix + a` / `prefix + A`)

Open a persistent note tied to the current window (`a`) or pane (`A`) in
`$EDITOR`, inside a popup:

- **`C-q`** detaches the popup — the editor keeps running in a background
  tmux session, so reopening restores it instantly, cursor and all
- Quitting the editor closes the note fully
- Notes are markdown files under `<save-dir>/notes/<session>/`, keyed by
  window index — the same identifier save/restore preserves, so notes
  survive tmux restarts and re-attach to their windows after a restore
- Session previews (view/delete/rename) list each note's first line;
  rename and delete carry notes along with the save files
- Known limitation: notes don't yet follow a window moved with
  `C-w`/`C-y`/`C-p` — they stay keyed to the source session
  (integration planned; see `CLAUDE.md` feature plan)

**Use case:** Jot "waiting on CI for PR #142, then rebase" in the window
where that's happening. Two weeks later, the note — not your memory —
tells you where you left off.

## See also

`tmux-attic` is a pure tmux session curator. Anything agent-aware
(live Claude / Codex state in the status bar, per-pane marks,
`@recon-ignore` toggles, recon cycling) lives in a sibling plugin:

**[SynapticSage/tmux-agent-tracker](https://github.com/SynapticSage/tmux-agent-tracker)**

The two are designed to coexist — install either or both, nothing
overlaps.

## Quick Setup

Add to your `.tmux.conf`:

```bash
set -g @plugin 'SynapticSage/tmux-attic'

# Lifecycle tools — not bound by default, opt in as you like
set -g @session-manager-view-key   'C-v'
set -g @session-manager-delete-key 'C-d'
set -g @session-manager-rename-key 'C-n'

# Window-level operations — defaults shown
# set -g @session-manager-move-window-key       'C-w'
# set -g @session-manager-load-window-key       'C-y'
# set -g @session-manager-load-window-copy-key  'M-y'
# set -g @session-manager-pull-window-key       'C-p'

# Scratchpad notes — defaults shown
# set -g @session-manager-scratchpad-key        'a'
# set -g @session-manager-scratchpad-pane-key   'A'
# set -g @session-manager-scratchpad-editor     ''   # empty = use $EDITOR
```

## Commands Summary

| Key    | Command        | Description                                                    |
|--------|----------------|----------------------------------------------------------------|
| `C-s`  | Save           | Persist current session (windows, panes, layout) to disk       |
| `C-r`  | Restore        | Switch to a running session or restore from disk               |
| `C-v`  | View           | Browse saved sessions with live preview (read-only)            |
| `C-d`  | Delete         | Preview a saved session, confirm, then unlink its files        |
| `C-n`  | Rename         | Preview a saved session, validate new name, then rename files  |
| `C-w`  | Move Window    | Push current window → another session (running or saved)       |
| `C-y`  | Load Window    | Pull a window from a saved session into the current one        |
| `C-p`  | Pull Window    | Pull a window from anywhere (running or saved)                 |
| `a`    | Scratchpad     | Persistent per-window note in `$EDITOR` (popup; `C-q` closes)  |
| `A`    | Scratchpad     | Same, scoped to the current pane                               |

Reload tmux: `tmux source ~/.tmux.conf` and press `prefix + I` to
install.

## What Gets Saved

The save format is inherited from
[PhilVoel/tmux-session-manager](https://github.com/PhilVoel/tmux-session-manager)
(itself a compact rewrite of tmux-resurrect). Per-session files capture:

- windows, panes and their layout
- current working directory for each pane
- active window
- active pane for each window
- programs running within a pane
  - taking care of NixOS' Neovim wrapper. As NixOS wraps some programs and starts them with additional arguments, the plugin removes those arguments when it detects Neovim running on NixOS. If you're using the unwrapped version of Neovim, you can disable this check in the [Configuration](#Configuration).

### Command capture: portability fix

The upstream implementation read program command lines from
`/proc/<pid>/cmdline`, which is Linux-only — on macOS and BSD the
`/proc` filesystem does not exist, so every pane's captured command
came out empty and restore re-entered only the directory.

This fork uses `ps -p <pid> -o args=` on non-Linux platforms, falling
back to `/proc` reads only for the NixOS Neovim-wrapper special case
(which genuinely needs argv separation that `ps` flattens). Arg
boundaries are lossy for args with embedded spaces — a known
limitation worth flagging, but rare in typical agent invocations.

## Dependencies

- [`tmux`](https://github.com/tmux/tmux) (3.2 or higher)
- [`fzf`](https://github.com/junegunn/fzf) (0.13.0 or higher; optional but recommended)

> [!note]
> This plugin only uses standard functionality in fzf which was present in its initial release. In theory, every version should work but this is untested.

## Installation

### Installation with [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to the list of TPM plugins in `.tmux.conf`:

    set -g @plugin 'SynapticSage/tmux-attic'

Hit `prefix + I` to install the plugin.

### Manual Installation

Clone the repo:

    $ git clone https://github.com/SynapticSage/tmux-attic ~/clone/path

Add this line to your `.tmux.conf`:

    run-shell ~/clone/path/session_manager.tmux

Reload TMUX environment with `$ tmux source ~/.tmux.conf`.

### Nix/NixOS

The upstream
[PhilVoel/tmux-session-manager](https://github.com/PhilVoel/tmux-session-manager)
is packaged in nixpkgs (release `25.11`+) as
`tmuxPlugins.tmux-session-manager`. That package ships the upstream
feature set only — it does not include tmux-attic's lifecycle tools.
Use the manual-installation path above if you want the curate features
on NixOS.

## Configuration

You can customize the plugin by setting the following options in your `.tmux.conf`:

| Configuration option                       | Options               | Default value                   | Description                                                                                                             |
|------------------------------------------- | --------------------- | ------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `session-manager-save-dir`                 | `~/any/path/you/like` | `~/.local/share/tmux/sessions/` | Specify the directory where session data is saved.                                                                      |
| `session-manager-save-key`                 | Any key binding       | `C-s`                           | Which key binding to set for saving the current session.                                                                |
| `session-manager-save-key-root`            | Any key binding       | Not set                         | Which key binding to set in root table for saving the current session. Using `prefix` is **not** necessary.             |
| `session-manager-restore-key`              | Any key binding       | `C-r`                           | Which key binding to set for restoring or switching to a session.                                                       |
| `session-manager-restore-key-root`         | Any key binding       | Not set                         | Which key binding to set in root table for restoring or switching to a session. Using `prefix` is **not** necessary.    |
| `session-manager-archive-key`              | Any key binding       | Not set                         | Which key binding to set for archiving a session.                                                                       |
| `session-manager-archive-key-root`         | Any key binding       | Not set                         | Which key binding to set in root table for archiving a session. Using `prefix` is **not** necessary.                    |
| `session-manager-unarchive-key`            | Any key binding       | Not set                         | Which key binding to set for unarchiving and switching to a session.                                                    |
| `session-manager-unarchive-key-root`       | Any key binding       | Not set                         | Which key binding to set in root table for unarchiving and switching to a session. Using `prefix` is **not** necessary. |
| `session-manager-delete-key`               | Any key binding       | Not set                         | Which key binding to set for deleting a saved session (preview + y/N confirmation).                                     |
| `session-manager-delete-key-root`          | Any key binding       | Not set                         | Which key binding to set in root table for deleting a saved session. Using `prefix` is **not** necessary.               |
| `session-manager-rename-key`               | Any key binding       | Not set                         | Which key binding to set for renaming a saved session (preview + validation + y/N confirmation).                        |
| `session-manager-rename-key-root`          | Any key binding       | Not set                         | Which key binding to set in root table for renaming a saved session. Using `prefix` is **not** necessary.               |
| `session-manager-view-key`                 | Any key binding       | Not set                         | Which key binding to set for browsing saved sessions with live layout preview (read-only).                              |
| `session-manager-view-key-root`            | Any key binding       | Not set                         | Which key binding to set in root table for browsing saved sessions. Using `prefix` is **not** necessary.                |
| `session-manager-move-window-key`          | Any key binding       | `C-w`                           | Which key binding to set for moving the current window to another session.                                              |
| `session-manager-move-window-key-root`     | Any key binding       | Not set                         | Which key binding to set in root table for moving the current window. Using `prefix` is **not** necessary.              |
| `session-manager-load-window-key`          | Any key binding       | `C-y`                           | Which key binding to set for loading a window from a saved session (move semantics).                                    |
| `session-manager-load-window-key-root`     | Any key binding       | Not set                         | Which key binding to set in root table for loading a window. Using `prefix` is **not** necessary.                       |
| `session-manager-load-window-copy-key`     | Any key binding       | Not set                         | Which key binding to set for loading a window with copy semantics (keeps in source).                                    |
| `session-manager-load-window-copy-key-root`| Any key binding       | Not set                         | Which key binding to set in root table for loading a window with copy semantics. Using `prefix` is **not** necessary.   |
| `session-manager-pull-window-key`          | Any key binding       | `C-p`                           | Which key binding to set for pulling a window from any session (running or saved).                                      |
| `session-manager-pull-window-key-root`     | Any key binding       | Not set                         | Which key binding to set in root table for pulling a window. Using `prefix` is **not** necessary.                       |
| `session-manager-scratchpad-key`           | Any key binding       | `a`                             | Which key binding to set for the per-window scratchpad note (popup in `$EDITOR`; `C-q` detaches, quit closes).          |
| `session-manager-scratchpad-key-root`      | Any key binding       | Not set                         | Which key binding to set in root table for the window scratchpad. Using `prefix` is **not** necessary.                  |
| `session-manager-scratchpad-pane-key`      | Any key binding       | `A`                             | Which key binding to set for the per-pane scratchpad note.                                                              |
| `session-manager-scratchpad-pane-key-root` | Any key binding       | Not set                         | Which key binding to set in root table for the pane scratchpad. Using `prefix` is **not** necessary.                    |
| `session-manager-scratchpad-editor`        | Any editor command    | Not set (uses `$EDITOR`)        | Editor used for scratchpad notes. Falls back to `$EDITOR`, then `vi`.                                                   |
| `session-manager-disable-nixos-nvim-check` | `on` or `off`         | `off`                           | When `on`, disable the check for Neovim on NixOS.                                                                       |
| `session-manager-disable-fzf-warning`      | `on` or `off`         | `off`                           | When `on`, disable the check for fzf on startup.                                                                        |

## Bug reports and contributions

I'm always thankful for bug reports and new ideas. For details, check the [guidelines](CONTRIBUTING.md).

## Credits

`tmux-attic` builds on
[PhilVoel/tmux-session-manager](https://github.com/PhilVoel/tmux-session-manager),
which rewrote [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
into a more compact per-session-file codebase. The save-file format and
the base save/restore/archive/unarchive operations come from that
lineage. The window-level operations (move/load/pull) and the
session-lifecycle tools (view/delete-with-preview/rename) are this
fork's additions.

## License
This software is licensed under [MIT](LICENSE.md).
