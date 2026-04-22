# tmux-attic

> Curate your tmux sessions — save, browse, preview, rename, delete, and
> move windows between sessions with layout previews at every destructive
> step. Pairs with [Recon](https://github.com/anthropics/recon) for
> navigating live Claude Code agents: `tmux-attic` persists state on
> disk, Recon navigates processes in running panes.

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

## Per-Window Agent Status Badges

The badge system that used to ship alongside the attic has been
extracted into its own TPM plugin:
**[SynapticSage/tmux-agent-tracker](https://github.com/SynapticSage/tmux-agent-tracker)**.

```tmux
set -g @plugin 'SynapticSage/tmux-agent-tracker'
```

That plugin covers:

- **Per-window state badges** — `⌨ ⚙ ✳ ✓ 💤 ∅` symbols + counts,
  event-driven via Claude Code hooks and polled via `recon` / `codex`.
- **Per-pane marks** — tag individual Claude/Codex panes with a short
  label (1-6 chars) or an emoji. `prefix + m` opens a popup; Ctrl-E
  switches to an fzf-based emoji picker. Marked panes render
  individually alongside the aggregated counts for unmarked panes.

Muting windows via `@recon-ignore` is still driven from this repo —
the badge plugin's `30-tmux-ignore.sh` provider reads the
`@recon-ignore` option that the toggles below flip. The two
repositories are intentionally decoupled: the attic handles
persistence and recon-ignore UX; tmux-agent-tracker handles the
live status-bar rendering. Use either or both.

### Muting windows and panes

Three bindings toggle `@recon-ignore` at different scopes:

| Key            | Scope   | Effect                                             |
|----------------|---------|----------------------------------------------------|
| `prefix + i`   | pane    | Mute one pane (siblings keep reporting)            |
| `prefix + e`   | window  | Mute every pane in the window via inheritance      |
| `prefix + I`   | picker  | fzf popup for session/window scope, non-focused    |

```tmux
bind-key i run-shell "/path/to/tmux-attic/recon_ignore_toggle.sh --pane"
bind-key e run-shell "/path/to/tmux-attic/recon_ignore_toggle.sh --window"
bind-key I display-popup -w 85% -h 75% -E "/path/to/tmux-attic/recon_ignore_picker.sh"
```

`prefix + e` overrides `tmux-text-macros`' default `split-window`
binding; pick a different key if you use the macro launcher.

See [`KEYBINDINGS.md`](KEYBINDINGS.md) for the full project-wide
binding reference.

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

Reload tmux: `tmux source ~/.tmux.conf` and press `prefix + I` to
install.

## Pairing with Recon for Claude Code Sessions

[Recon](https://github.com/anthropics/recon) is a Rust TUI for managing
live Claude Code agents running inside tmux. The two tools cover
complementary axes:

| Concern                                         | Tool         |
|-------------------------------------------------|--------------|
| Save / restore tmux state                       | This plugin  |
| Delete / rename / browse saved sessions         | This plugin  |
| Dashboard of currently-running Claude agents    | `recon` / `recon view` |
| Jump to next agent waiting for input            | `recon next` |

A typical Claude Code workflow leans on both:

1. Spin up agents across multiple tmux windows as usual.
2. Bind Recon's commands to keys you'll actually use —
   `display-popup -E 'recon'` for the dashboard, `run-shell 'recon next'`
   to jump between agents.
3. When you want to step away, `prefix + C-s` saves the tmux layout;
   Recon's own `park` / `unpark` subcommands handle agent-side state.
4. Coming back later, `prefix + C-v` lets you browse saved tmux sessions
   to pick the one matching the project you want to continue.

Recon ships with its own CLI commands (`recon view`, `recon next`,
`recon resume`, `recon park`, etc.). The authoring of tmux keybindings
around those commands is user-scoped — build wrappers that match your
own workflow rather than importing one-size-fits-all bindings.

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

### Agent-aware session restoration

Naïvely re-running the captured command for a Claude or Codex pane
spawns a **new** conversation rather than continuing the one that was
live at save time. When saving, this fork rewrites claude and codex
invocations so the restored pane resumes the running session:

| Captured command                                         | Saved (rewritten) form                |
|----------------------------------------------------------|---------------------------------------|
| `claude`                                                 | `claude --continue`                   |
| `claude --dangerously-skip-permissions`                  | `claude --continue --dangerously-skip-permissions` |
| `claude --resume <id>` (conflicting flag stripped)       | `claude --continue`                   |
| `codex -m gpt-5.4`                                       | `codex resume --last -m gpt-5.4`      |
| `npm exec @openai/codex@latest -m gpt-5.4`               | `codex resume --last -m gpt-5.4`      |
| `node /path/to/codex -m gpt-5.4`                         | `codex resume --last -m gpt-5.4`      |
| `/abs/path/.../codex/codex -m gpt-5.4`                   | `codex resume --last -m gpt-5.4`      |

For Claude, the rewriter also looks up the specific `session_id` per
pane via a one-shot `recon json` call at save time. When recon knows
the pane's session, the saved command becomes
`claude --resume <uuid> [preserved flags]` instead of
`claude --continue`. This matters when you run multiple Claude
sessions in the same directory: `--continue` picks whichever is
most-recent and collapses all restored panes onto one conversation;
`--resume <uuid>` restores each pane to its own session.

If recon isn't installed or hasn't observed the pane yet, the
rewriter falls back to `--continue`. Either way, `pane_current_path`
is still captured so cwd-based resolution works as a safety net.

Codex's `resume --last` is still cwd-based because Codex has no hook
API and no per-pane session observer equivalent to recon — we can't
correlate pane → session ID without writing a dedicated observer
(parse `~/.codex/history.jsonl` plus process-tree + start-time
heuristics). For single-codex-per-cwd workflows `--last` is fine;
multi-codex precision is a future enhancement.

The rewriter lives in `rewrite_agent_command` (see
`common_utils.sh`) — unit tests worth 16 input patterns live inline
in that file's header comment. Non-agent commands pass through
unchanged.

### Caveat: tmux-continuum / tmux-resurrect auto-save

This fork's augmented save runs only when the user triggers it
(`prefix + C-s` by default). If you also use
[`tmux-continuum`](https://github.com/tmux-plugins/tmux-continuum)
for its 15-minute auto-save loop, those saves are made by
`tmux-resurrect` into a separate directory
(`~/.local/share/tmux/resurrect/`) and do **not** go through this
agent-aware logic — a resurrect-driven restore will re-launch
`claude` / `codex` as fresh sessions.

Options:

- Save manually (`prefix + C-s`) before any detach you care about —
  the augmented save file wins on restore since it lives under
  `~/.local/share/tmux/sessions/` and this repo's bindings override
  resurrect's.
- If you want continuum's cadence with agent-aware capture, Path B
  in the roadmap (drop-in `@resurrect-strategy-claude` and
  `@resurrect-strategy-codex` scripts that integrate with resurrect's
  hook system) would give you both.

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
