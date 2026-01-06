# Tmux Session Manager (Extended)

> Fork of [PhilVoel/tmux-session-manager](https://github.com/PhilVoel/tmux-session-manager) with **window-level operations**.

We all love tmux. But whenever you close a session (for instance, by restarting your system), you lose all the windows, panes and programs you had open.\
The easy solution: Just save the entire tmux environment and restore it (that's what [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) does).\
But what if you have multiple sessions that you use for multiple projects? What if you don't need all those sessions open at the same time? What if you don't *want* them open because your laptop is a decade old and you can't afford to start dozens of programs at once?\
This plugin aims to solve that problem by only saving the session you are currently in as well as providing a fzf-based session switcher that allows you to not only switch between running sessions but also seamlessly restore a previously saved session and switch to it.\
You can also archive sessions you'd like to keep but won't return to for a while. Archived sessions don't show up in the regular restore selection and can be unarchived whenever you're ready to open them again. If you won't need the session again, you can permanently delete it.

## New in This Fork: Window-Level Operations

This fork adds the ability to **move and load individual windows** between sessions:

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

### Quick Setup

Add to your `.tmux.conf`:

```bash
# Use this fork instead of the original
set -g @plugin 'SynapticSage/tmux-session-manager'

# Optional: customize keybindings (these are the defaults)
# set -g @session-manager-move-window-key 'C-w'
# set -g @session-manager-load-window-key 'C-y'
# set -g @session-manager-load-window-copy-key 'M-y'
# set -g @session-manager-pull-window-key 'C-p'
```

### Window Commands Summary

| Key | Command | Description |
|-----|---------|-------------|
| `C-w` | Move | Push current window → another session |
| `C-y` | Load | Pull window from saved sessions only |
| `C-p` | Pull | Pull window from anywhere (running or saved) |

Then reload tmux: `tmux source ~/.tmux.conf` and press `prefix + I` to install.

Originally just a fork of `tmux-resurrect`, this plugin has since been rewritten from scratch (although the inspiration is still obvious and I might have borrowed from them in a few places) to be a more compact codebase that I can more easily maintain and extend if necessary.

## About

This plugin tries to save the current session status as precisely as possible. Here's what's been taken care of:

- windows, panes and their layout
- current working directory for each pane
- active window
- active pane for each window
- programs running within a pane
  - taking care of NixOS' Neovim wrapper. As NixOS wraps some programs and starts them with additional arguments, the plugin removes those arguments when it detects Neovim running on NixOS. If you're using the unwrapped version of Neovim, you can disable this check in the [Configuration](#Configuration).

## Dependencies

- [`tmux`](https://github.com/tmux/tmux) (3.2 or higher)
- [`fzf`](https://github.com/junegunn/fzf) (0.13.0 or higher; optional but recommended)

> [!note]
> This plugin only uses standard functionality in fzf which was present in its initial release. In theory, every version should work but this is untested.

## Installation

### Installation with [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to the list of TPM plugins in `.tmux.conf`:

    set -g @plugin 'PhilVoel/tmux-session-manager'

Hit `prefix + I` to install the plugin.

### Manual Installation

Clone the repo:

    $ git clone https://github.com/PhilVoel/tmux-session-manager ~/clone/path

Add this line to your `.tmux.conf`:

    run-shell ~/clone/path/session_manager.tmux

Reload TMUX environment with `$ tmux source ~/.tmux.conf`.

### Nix/NixOS

Beginning with release `25.11` this plugin is also available in `nixpkgs` as `tmuxPlugins.tmux-session-manager`.

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
| `session-manager-delete-key`               | Any key binding       | Not set                         | Which key binding to set for deleting a saved session.                                                                  |
| `session-manager-delete-key-root`          | Any key binding       | Not set                         | Which key binding to set in root table for deleting a saved session. Using `prefix` is **not** necessary.               |
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

As already stated, this plugin is heavily inspired by [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and I've taken small liberties with some of their code while rewriting.

## License
This software is licensed under [MIT](LICENSE.md).
