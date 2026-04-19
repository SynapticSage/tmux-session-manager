# tmux-manage — CLAUDE.md

Repository-level notes for Claude Code. This file documents the project's
concrete conventions and the active design work.

---

## What this repo is

A collection of bash scripts and tmux hooks that augment tmux for running
many concurrent Claude Code sessions. Two overlapping layers:

- **Session manager** (`save_session.sh`, `restore_session.sh`,
  `move_window.sh`, `load_window.sh`, `pull_window.sh`,
  `delete_session.sh`) — persist, restore, and shuffle whole tmux
  sessions and individual windows between them.
- **Recon wrappers** (`recon_cycle.sh`, `recon_ignore_toggle.sh`,
  `recon_ignore_picker.sh`) — thin UX layer over the external `recon`
  CLI (Rust, in `~/.cargo/bin/recon`) that inventories live Claude
  sessions across the tmux server.

Top-level entry point for tmux is `session_manager.tmux`, which binds
keys by reading `@session-manager-*` user options. Key reference:
`KEYBINDINGS.md`.

---

## External tools this repo assumes

| Tool | Purpose | How it's used |
|------|---------|---------------|
| `recon` (cargo bin) | JSON inventory of Claude sessions | `recon json` emits all sessions with `status` ∈ {`Idle`, `Working`, `New`, …}, `pane_target`, `token_ratio`, etc. Consumed by `recon_cycle.sh`. |
| `tmux-agent-indicator` (TPM plugin) | Per-pane Claude Code state via hooks | `~/.claude/settings.json` hooks call `agent-state.sh` on `UserPromptSubmit` / `PermissionRequest` / `Stop`. State lives in tmux global env vars `TMUX_AGENT_PANE_<pane_id>_STATE`. |
| `fzf` | Interactive pickers | Required by restore/delete/move/load popups and `recon_ignore_picker.sh`. |

---

## Conventions

- All scripts are `set -euo pipefail` (except the `delete_session.sh`
  exception noted in commit `3b16f92` — strict mode crashed popups in
  some cases; verify before re-adding).
- Scripts locate tmux via an absolute path (`TMUX_BIN=/opt/homebrew/bin/tmux`)
  because some are invoked from Claude hooks where `PATH` is minimal.
- User options: pane/window/session scope uses the `@recon-ignore`
  namespace; session-manager configuration uses `@session-manager-*`.
  Inheritance follows tmux's pane → window → session → global chain.
- New features should be keyboard-reachable via a documented binding in
  `KEYBINDINGS.md` and, where applicable, configurable via a
  `@<feature>-*-key` user option, matching the existing pattern.

---

## Per-window agent status badges (implemented, prototype)

**Goal.** Each tmux window in the status bar carries a compact badge
showing how many panes in that window are Claude Code sessions and
what state each is in (idle / working / waiting-for-input / done /
new / ignored). A user scanning the status bar can see at a glance
which window has something waiting, which is grinding away, and which
are asleep — without opening `recon view`.

**Design ground rules (from the user, for any rework):**
- **Do not reuse the old `@claude_<N>_status` attempt** (commented in
  `~/.tmux.conf:165`). It failed and is not a restart point.
- **Extensibility is a first-class requirement.** The system must
  accept signal sources beyond recon / tmux-agent-indicator without
  touching core code — dropping a new executable into
  `window_badge_providers/` is all it should take.

### Files

```
window_badge.sh                        hot path (status-format #() call)
window_badge_refresh.sh                cold path (invokes providers, merges,
                                       atomic-writes cache)
hook_agent_state.sh                    Claude Code hook handler — writes
                                       TMUX_BADGE_PANE_<id>_STATE
window_badge_providers/
    10-claude-hooks.sh                 reads TMUX_BADGE_PANE_*_STATE env vars
    20-recon.sh                        `recon json` with pane_target→pane_id
    30-tmux-ignore.sh                  @recon-ignore option inheritance
    40-codex.sh                        OpenAI Codex sessions (polled, no hooks)
```

Cache: `/tmp/tmux-window-badge-$(id -u).cache`.

### Hook chain (event-driven source, repo-owned)

`~/.claude/settings.json` hooks invoke `hook_agent_state.sh`:

| Hook | State written |
|------|---------------|
| `UserPromptSubmit` (first matcher) | `off` (clears prior `done`) |
| `UserPromptSubmit` (second matcher) | `running` |
| `PermissionRequest` | `needs-input` |
| `Stop` | `done` |

`hook_agent_state.sh` writes `TMUX_BADGE_PANE_<pane_id>_STATE=<state>`
into tmux global env and calls `refresh-client -S` so the status bar
repaints immediately — no waiting on the next status-interval tick.

The repo owns this end-to-end. **No dependency on `tmux-agent-indicator`.**
The plugin was unwired on 2026-04-19: `@plugin 'accessd/tmux-agent-indicator'`
commented out in `~/.tmux.conf`, its `@agent-indicator-*` options
commented out, its interpolation widget (`@onedark_widgets`) nulled,
its live hooks (`pane-focus-in`/`after-select-window`/
`after-select-pane`/`client-session-changed`) unset, and 18 stale
`TMUX_AGENT_PANE_*` env vars purged. Plugin files remain on disk —
run `~/.tmux/plugins/tpm/bin/clean_plugins` to fully remove.

### Provider contract (the extension point)

Any executable in `window_badge_providers/` that emits TSV to stdout
in this shape is a valid provider:

```
<pane_id>\t<state>\t<ignored>
```

- `pane_id`: tmux `#{pane_id}` format, `%<N>`. Stable across window
  moves. This is the canonical key.
- `state`: one of `needs-input`, `working`, `new`, `done`, `idle`,
  `none`.
- `ignored`: `y` or `n`.

One line per observation. A provider can emit observations for any
subset of panes it knows about — it is not required to cover all
panes. Providers that aren't installed (their binary missing)
silently exit 0 with no output; the system degrades gracefully.

**Merge rule** (in `window_badge_refresh.sh`):
- Per `pane_id`, keep the highest-priority `state` across providers.
  Priority (high → low): `needs-input > working > new > done > idle > none`.
- OR the `ignored` flag: any `y` wins.

**Why this contract.** The merger does not know or care about which
provider observed what. New signals (e.g., a CI-status probe, an
opencode session poller, a per-project custom health check) can ship
as a single executable. Removing `tmux-agent-indicator` from the
system is `rm window_badge_providers/10-agent-indicator.sh`.

### Data sources (event-driven + reconciliation)

Two complementary signals today:

1. **`10-claude-hooks.sh` (event-driven, fast, lossy).** Reads
   `TMUX_BADGE_PANE_<pane_id>_STATE` env vars written by
   `hook_agent_state.sh` (see *Hook chain* above). Latency ~10ms.
   Fails silently if hooks didn't run (externally-killed Claude,
   session pre-dating the hook registration).

2. **`20-recon.sh` (polled, authoritative for Claude).** Calls
   `recon json`, translates `pane_target` → `pane_id`. Catches
   everything the Claude hooks miss. Cost: ~50ms for ~20 sessions.

3. **`40-codex.sh` (polled, best-effort for Codex).** Codex has no
   hook system and isn't observed by `recon`. This provider does
   one `ps -ax` pass to find TTYs running `codex`, maps them to
   pane_ids, and infers state by sampling `tmux capture-pane`. The
   pattern set is deliberately narrow (braille-spinner glyphs only)
   to avoid false `working` on panes that merely contain the word
   "thinking" in text. Default when codex is present but no pattern
   matches: `idle`.

The cache TTL (default 5s) controls how often `recon json` gets
called. The reconciliation is implicit in the merge step: any pane
the hooks marked `done` that `recon` no longer sees will be dropped
from the next cache write — no stale state.

### Rendering

**Target surface: `window-status-format` / `window-status-current-format`.**
Not `rename-window`. Rationale: renaming windows pollutes ssh titlebars,
vim's `set title`, and anything else that reads `$WINDOW`. Status-bar
formatting is scoped, reversible, and re-rendered on tmux's own cadence
(`status-interval 2` is already set).

**Format-string wiring** (add to `~/.tmux.conf`):

```tmux
set -ag window-status-format \
  ' #(/Users/ryoung/Code/repos/tmux-manage/window_badge.sh #{window_id})'
set -ag window-status-current-format \
  ' #(/Users/ryoung/Code/repos/tmux-manage/window_badge.sh #{window_id})'
```

`#(...)` is evaluated once per window on every status redraw (your
`status-interval` is 2s). `window_badge.sh` reads the cache file only
on the hot path; it never calls `recon` directly. When the cache is
older than TTL, it kicks an async refresh in the background and
renders with the current (stale) cache this tick. First-ever render
synchronously refreshes once.

Thundering-herd guard: the hot path `touch`es the cache file before
forking the refresh so concurrent window renders see a "fresh" mtime
and skip their own refresh attempt. No `flock` needed — `flock` isn't
shipped on macOS by default.

### Aggregation modes

Configurable at runtime via `@window-badge-mode` (read per-render):

| Mode | Example | When to use |
|------|---------|-------------|
| `counts` (default) | `⌨1 ⚙2 💤1` | Multi-pane windows, dashboard-style |
| `worst` | `⌨` | Minimal noise; priority waiting > working > new > done > idle |
| `off` | *(empty)* | Disable the badge, keep native window title |

Change at runtime with `tmux set-option -g @window-badge-mode worst`;
takes effect on the next status redraw.

Symbol conventions (override via `@window-badge-symbols-<state>` options):

| State | Symbol | Meaning |
|-------|--------|---------|
| `needs-input` / `Waiting` | `⌨` | User action required |
| `running` / `Working` | `⚙` | Actively computing |
| `done` | `✓` | Finished; unread |
| `Idle` | `💤` | Claude sitting at prompt |
| `New` | `✳` | Freshly spawned |
| `@recon-ignore = on` | `∅` (dim) | Hidden from cycle; shown dim so you don't forget why nothing pages you |

### Refresh cadence

No daemon. The hot path (`window_badge.sh`) is the refresh trigger:
when it notices the cache is stale, it forks the refresh async and
renders with stale data this tick. This removes the "who owns the
heartbeat" question entirely — the first rendering call after TTL
expiry does the work, and then the mtime-bump tells everyone else
to stand down.

Effective cadence: every ~TTL seconds (default 5), assuming at least
one window is rendering (which is always true when tmux is active).

### Resolved decisions (were choice points; locked in)

- **Default mode: `counts`.** Dashboard-style, multi-pane visible.
  `worst` available via the runtime option.
- **Ignored panes: hide from counts, show trailing dim `∅N`.** So
  `main:0 ⚙1 ∅1` means one working agent plus one you've told the
  system to shush.
- **No daemon; cached-read with hot-path async refresh.** See above.
- **Coexist with `tmux-agent-indicator` colors.** The badge is
  additive text in `window-status-format`; the plugin's
  `window-status-style` coloring still applies for the focused-pane
  state. Two signals, two channels.

### Future: `@window-badge-split-by-agent` mode

Today all providers emit states into a single shared vocabulary, so a
pane running Claude-working and another running Codex-working both
count into the same `⚙2`. Users who run heterogeneous agent fleets
have asked (2026-04-19) for an opt-in split mode that prefixes each
state count with an agent glyph — e.g. `C⚙1 🧠⚙1` instead of `⚙2` —
to distinguish sources visually.

Implementation sketch when this lands:
- Extend the provider TSV contract to a 4th optional column: `agent`
  (values: `claude`, `codex`, or a short user-defined tag). Existing
  3-column providers default their agent from the filename prefix
  (`10-claude-hooks.sh` → `claude`, `40-codex.sh` → `codex`).
- Add `@window-badge-split-by-agent` (default `off`). When `on`, the
  hot path groups counts by (state, agent) and emits one styled run
  per combination.
- Symbols remain state-level; agent is a prefix glyph read from
  `@window-badge-agent-glyph-<agent>`.

Not implemented. Captured here so future maintainers don't invent a
different 4th column for the same purpose.

### Adding a new provider

Example: add a "current branch dirty" indicator sourced from `git`:

```bash
# window_badge_providers/40-git-dirty.sh
#!/usr/bin/env bash
tmux list-panes -a -F '#{pane_id}|#{pane_current_path}' | while IFS='|' read -r p path; do
  [[ -d "$path/.git" ]] || continue
  if (cd "$path" && [[ -n "$(git status --porcelain 2>/dev/null)" ]]); then
    # No canonical "dirty" state yet — either add one to the vocab
    # or piggyback on "new" / coin a new one.
    printf '%s\tdirty\tn\n' "$p"
  fi
done
```

This implies extending the canonical state vocabulary. If a provider
emits a state not in the priority table, the merger drops it
silently — so new states need to be added to BOTH the merger's
`priority` dict and the hot path's `symbols` map before they render.

### Prior art in this repo

The commented-out line in `~/.tmux.conf:165` shows an earlier attempt
using per-window-index user options (`@claude_<N>_status`). Per the
user's instruction, that attempt is **not a restart point** and this
prototype does not reuse any of it. Documented here so future
maintainers don't rediscover it and mistake it for scaffolding.

---

## Testing

Any change to a script's contract (flags, output format) must be
exercised end-to-end in a live tmux session — unit-testing bash wrappers
against tmux is low-value. Minimum smoke path for the badge feature
when it lands:

1. Start 3 windows, each with a different Claude state (idle / working
   / waiting). Confirm the badge renders correctly for each.
2. Close a Claude pane without the hook firing (e.g. `kill -9 <pid>`).
   Within one poll interval, the badge should clear that pane's state.
3. Mark a pane `@recon-ignore` via `Prefix+i`. Badge should update on
   next status redraw (≤2s).
4. Restart the tmux server. Badges should repopulate within one poll
   interval without manual intervention.
