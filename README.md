# ClaudePet

A native macOS floating companion pet for [Claude Code](https://claude.com/claude-code), cloning the UX of OpenAI Codex's built-in desktop pets. It lives in a small always-on-top panel, reacts to what your Claude Code session is doing in real time, and lets you manage sessions without leaving your terminal.

There's no first-party API for this — Claude Code is a CLI. The bridge is entirely **hooks (writing state) + a menu-bar app (watching state)**: a small Python script wired into `~/.claude/settings.json` hook events writes a JSON file per session, and the Swift app watches that directory and renders it.

## What it does

- **Reacts to your session**: idle, working, needs your permission, ready for review, or failed — each with its own animation/emoji.
- **Custom pets**: drop a Codex-format `pet.json` + spritesheet into `~/.claude/pets/<name>/` (or it'll pick up real Codex pets from `~/.codex/pets/`) and it just works. Falls back to a built-in emoji pet if none is installed.
- **Speech bubble**: shows the current tool and a short summary (e.g. `my-project · Bash · npm test`).
- **Task progress ring**: shows N/M when Claude Code is working through a plan/task list.
- **In-bubble permission Allow/Deny**: when Claude Code actually needs a decision (not on every tool call), a bubble with Allow/Deny buttons appears on the pet itself and answers the CLI directly — no need to switch back to the terminal.
- **Activity Tray**: click the pet (single-pet mode) to see every active session, ranked by urgency, click a row to bring that session's terminal/IDE forward, and end a session directly from the tray (two-click confirm, then `SIGTERM`→`SIGKILL`). Each row also shows an estimated token count and cost, read from Claude Code's own transcript files.
- **Multi-Session Pets** (optional mode): instead of one aggregate pet, show one floating pet per active session, laid out in a row.
- **Idle wandering**: when idle, the pet occasionally strolls to a new spot along the screen's bottom edge and settles — like real Codex pets "finding a spot to sleep."
- **Wave on wake, jump on click**, and respects **Reduce Motion** (freezes on a still frame instead of animating).
- Global hotkey **⌘⇧P** to show/hide the pet; **⌘⇧K** opens a Spotlight-style **command palette** to jump straight to any active session by project name.
- **Native notifications**: if a permission decision needs you and the app isn't frontmost, you get a real macOS notification instead of a bubble no one saw. State-changing sound cues (review/failed/waiting-permission) are available too, off by default.
- **State-aware menu-bar icon**: the status item itself changes glyph and tint (idle/working/waiting/review/failed) — no need to open the panel just to check.
- **Hook Setup & Diagnostics**: a one-click installer that wires the hooks into `~/.claude/settings.json` for you (backing it up first) and points them at a fixed, checkout-independent script location, plus a health check for "the pet just isn't reacting."
- **Preferences window**: wander, sounds, notifications, and Launch at Login, all in one place.
- **Pet Gallery**: browse and preview every installed pet before applying it, instead of cycling blind.
- **Local session stats**: sessions today/this week, tasks completed, permission approval rate, and estimated spend on currently active sessions — local-only, never leaves the Mac.
- **Launch at Login**, via `SMAppService`.

## Requirements

- macOS 13+
- Swift 5.9+ toolchain (Xcode Command Line Tools is enough — no Xcode project needed)
- Claude Code CLI, with hooks enabled

## Install

```bash
cd ~/claude-code-pet
./build_app.sh          # builds ClaudePet.app into this directory
open ClaudePet.app
```

The app is a plain, unsigned (ad-hoc signed) `.app` bundle — there's no installer. Move it to `/Applications` if you want it there; it'll keep working from anywhere as long as the hook commands below still point at `~/claude-code-pet/hooks/pet-hook.py`.

### Wire up the hooks

Merge `hooks/settings-snippet.json` into your `~/.claude/settings.json` under the `"hooks"` key. If you already have hooks configured (as this setup does — an existing `Stop` hook, for example), **append** the new entries as additional matcher groups rather than replacing the key outright; hooks for the same event can have multiple groups and all of them run.

```bash
python3 - <<'EOF'
import json

settings_path = "/Users/YOU/.claude/settings.json"
snippet_path = "/Users/YOU/claude-code-pet/hooks/settings-snippet.json"

with open(settings_path) as f:
    settings = json.load(f)
with open(snippet_path) as f:
    snippet = json.load(f)

hooks = settings.setdefault("hooks", {})
for event, groups in snippet["hooks"].items():
    hooks.setdefault(event, []).extend(groups)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
EOF
```

(Back up `~/.claude/settings.json` first — `cp ~/.claude/settings.json ~/.claude/settings.json.bak`.)

`pet-hook.py` is a stdlib-only Python script; no `pip install` needed. Make sure it's executable: `chmod +x ~/claude-code-pet/hooks/pet-hook.py`.

## How it works

```
Claude Code hook event  →  pet-hook.py  →  ~/.claude/pet/sessions/<session_id>.json
                                    │                    │
                          Unix socket ping     DispatchSource (FSEvent) + 20s poll fallback
                                    └──────────┬─────────┘
                                               ▼
                                        SessionStore (Swift)
                                               ▼
                                     NSPanel(s) hosting SwiftUI
```

- **Push, not poll, for the common case**: after every session/request file write, `pet-hook.py` also fires a best-effort datagram at a local Unix socket (`~/.claude/pet/notify-{sessions,requests}.sock`) the app is listening on, so the UI usually updates within milliseconds instead of waiting on the FSEvent watcher or the poll timer. The socket ping is purely additive - if it fails for any reason (old `pet-hook.py`, socket not up yet), the existing FSEvent watcher and a much-slower poll timer still catch the change on their own. This can never be the only thing standing between a permission request and it being shown - it's strictly a latency improvement layered on top of the file-based state.
- **Hooks used**: `SessionStart`/`SessionEnd` (register/deregister), `UserPromptSubmit`/`PreToolUse`/`PostToolUse` (running), `Notification(permission_prompt)` + `PermissionRequest` (waiting), `Stop`/`SubagentStop` (review), `PostToolUseFailure`/`StopFailure` (failed), `TaskCreated`/`TaskCompleted` (progress ring counter).
- **Why `Stop`→decay instead of `idle_prompt`**: Claude Code's `idle_prompt` notification is documented as unreliable (fires after every response, or not at all, depending on version). Instead, `Stop` sets a "review" state that decays to idle after 20 seconds locally in the app — no dependency on that heuristic.
- **`PermissionRequest` is used for the interactive bubble, not `PreToolUse`**: `PreToolUse` fires on *every* tool call regardless of whether your `permissions.defaultMode` auto-approves it. `PermissionRequest` only fires when Claude Code actually needs a human decision, so the blocking hook (see below) never adds latency to auto-approved tool calls.
- **Priority when multiple sessions are active** (single-pet mode): needs-permission > failed > ready-for-review > running > idle — the same ordering used for the Activity Tray's sort order.

### The permission bubble, technically

`pet-hook.py await-permission` writes a request file to `~/.claude/pet/requests/<uuid>.json`, then **blocks**, polling for `~/.claude/pet/responses/<uuid>.json` (up to 290s — configured hook `timeout` is 300s). Clicking Allow/Deny in the app writes the response file; the hook picks it up and prints:

```json
{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "permissionDecision": "allow", "permissionDecisionReason": "..."}}
```

If nothing responds before the timeout, the hook exits with no special output and Claude Code falls back to its normal terminal prompt — it can never silently auto-allow something on your behalf.

### Kill session, technically

The tray's kill button sends `SIGTERM` (escalating to `SIGKILL` after 1.5s if still alive) to the Claude Code CLI process resolved by matching `--session-id <id>` on the process's command line via `ps`. This only works when the hook's logical `session_id` matches the live process's `--session-id` argument — true for normal `claude` invocations in a terminal, but **not** for daemon-managed/forked-resume sessions (some IDE integrations), where the button is inertly disabled rather than risk killing the wrong process.

## Custom pets

Drop a folder into `~/.claude/pets/<name>/` containing:
- `pet.json` — a manifest (Codex's real schema is just `id`/`displayName`/`description`/`spritesheetPath`; ClaudePet also accepts an explicit `rows`/`fps` override if you're hand-rolling one)
- a spritesheet PNG/WebP — 8 columns × 9 rows of 192×208px cells, rows in order: `idle, running-right, running-left, waving, jumping, failed, waiting, running, review`. Frame count per row is auto-detected by scanning for the first fully-transparent cell (matching Codex's own convention) unless you declare `rows` explicitly.

Use the menu bar icon → **Next Pet** / **Use Emoji Pet** / **Reload Pets** / **Reveal Pets Folder**.

## Menu bar

- **Wake/Tuck Away Pet (⌘⇧P)** — show/hide
- **Multi-Session Pets** — toggle one-panel-per-session mode
- **Next Pet / Use Emoji Pet / Reload Pets / Reveal Pets Folder** — custom pet management
- **Quit Claude Pet**

## Known limitations

- No first-party integration — this breaks if Anthropic changes hook payload shapes or event names.
- `Notification`/permission-hook latency can be a couple of seconds in some Claude Code versions.
- Click-to-focus and kill-session both rely on process-tree/command-line heuristics to find the right terminal/process; they degrade gracefully (button does nothing / is disabled) rather than acting on a guess when the heuristic can't resolve.
- Not code-signed for distribution — ad-hoc signed locally by `build_app.sh`, fine for running on your own Mac, not for handing to someone else without re-signing. No auto-update mechanism either; a new build means re-running `build_app.sh`.
- Session stats deliberately don't show "time worked" — the hook payloads give a last-write timestamp per session, not a trustworthy session-start time, so a duration would mean making a number up.
- Token/cost estimates are read from Claude Code's own transcript files (`~/.claude/projects/*/<session_id>.jsonl`), which are an undocumented, internal format, not a stable API — this can break silently if that layout changes. Pricing is a hardcoded per-model table (standard tier) that will drift out of date; treat the numbers as a ballpark, not a bill.

## Testing

`Sources/ClaudePetCore` holds the pure session-state logic (priority ordering, review decay, staleness, bubble text) with no AppKit/file-I/O dependencies, unit tested in `Tests/ClaudePetCoreTests` via `swift test`. Note: running the suite needs a full Xcode install, not just Command Line Tools — CLT alone doesn't ship a working XCTest/Testing runtime, independent of anything in this repo.

## Project layout

```
Sources/ClaudePet/       Swift app (AppKit NSPanel + SwiftUI content)
Sources/ClaudePetCore/   Pure session-state logic, unit tested, no AppKit dependency
Tests/ClaudePetCoreTests/  swift test suite for ClaudePetCore
hooks/pet-hook.py        The hook↔app bridge script (stdlib-only Python)
hooks/settings-snippet.json   Hook config to merge into ~/.claude/settings.json
build_app.sh             Builds Sources/ into ClaudePet.app
```
