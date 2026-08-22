# ClaudePet

A native macOS floating companion pet for [Claude Code](https://claude.com/claude-code), cloning the UX of OpenAI Codex's built-in desktop pets. It lives in a small always-on-top panel, reacts to what your Claude Code session is doing in real time, keeps track of your usage, and lets you manage sessions without leaving your terminal.

There's no first-party API for this — Claude Code is a CLI. The bridge is entirely **hooks (writing state) + a menu-bar app (watching state)**: a small Python script wired into `~/.claude/settings.json` hook events writes a JSON file per session, and the Swift app watches that directory and renders it.

## What it does

### Reacting to your session
- **Five states**: idle, working, needs your permission, ready for review, or failed — each with its own animation/emoji, a color-matched menu-bar icon, and a plain-English status line.
- **Custom pets**: drop a Codex-format `pet.json` + spritesheet into `~/.claude/pets/<name>/` (or it'll pick up real Codex pets from `~/.codex/pets/`) and it just works. Falls back to a built-in emoji pet if none is installed.
- **Per-project pet skins**: assign a different pet to each project from the Pet Gallery's scope picker, so you know at a glance which repo is talking to you.
- **Idle animation variety**: stretch, look around, or wander to a new spot along the screen's bottom edge and settle — like real Codex pets "finding a spot to sleep."
- **Speech bubble**: shows the current tool and a short summary, plus a task progress ring (`N/M`) when Claude Code is working through a plan.
- **Right-click quick actions** on the bubble or any Activity Tray row: bring the terminal forward, copy the summary, reveal the raw transcript in Finder, or end the session.
- **Wave on wake, jump on click**, and respects **Reduce Motion** (freezes on a still frame instead of animating).

### Personality & progress
- **Streaks & levels**: a daily streak (consecutive days you've actually used Claude Code) and an XP/level system derived from finished sessions and completed tasks, shown as a badge in Session Stats and a subtle warm tint on the pet itself at higher levels. All computed locally from your own history log.

### Insight & accountability
- **Session Stats v2**: sessions/tasks today and this week, time worked, a 14-day spend trend chart, and a per-project cost breakdown.
- **Budget alerts**: set a daily spend threshold in Preferences; get one notification per day the first time your estimated spend crosses it.
- **Weekly digest**: an optional once-a-week notification summarizing sessions, tasks, hours worked, and estimated cost.
- **Claude usage tracking (opt-in)**: shows Claude Code's own 5-hour/7-day rate-limit quota, both in Session Stats and as a color-coded row in the menu bar dropdown. This works by claiming Claude Code's `statusLine` setting — if you already have your own statusLine script, ClaudePet chains through to it transparently, so your terminal's own output is unaffected. Turn it on from **Hook Setup & Diagnostics**.

### Workflow
- **Activity Tray**: click the pet (single-pet mode) to see every active session, ranked by urgency, click a row to bring that session's terminal/IDE forward, and end a session directly from the tray (two-click confirm, then `SIGTERM`→`SIGKILL`). Each row also shows an estimated token count and cost, read from Claude Code's own transcript files.
- **Command palette (⌘⇧K)**: a Spotlight-style fuzzy jump to any active session by project name.
- **Multi-Session Pets** (optional mode): instead of one aggregate pet, show one floating pet per active session, laid out in a row.
- **Multi-monitor docking**: pin the pet to a specific display and corner from Preferences; it re-clamps automatically when you plug or unplug a screen.

### Notifications
- **Permission notifications, not decisions**: when Claude Code actually needs a decision (not on every tool call, and rarely at all under `defaultMode: "auto"`), the pet shows its waiting pose and a native macOS notification fires immediately — ClaudePet never decides on your behalf, it just makes sure you notice, then Claude Code's own terminal prompt handles the actual choice with zero added delay.
- **Session-completed notifications**: fires unconditionally (even while you're looking right at the pet) the moment a session actually ends, with task/duration info — a rarer, more significant event than a single turn finishing.
- **State-change notifications**: optional per-state toggles (fails / ready for review / starts running) for when the pet isn't visible.
- Every notification uses a consistent style: an emoji-prefixed title and a project-name subtitle where relevant.

### Thoughtful by design
- **Guided first run**: a short welcome tour explains every pet state and hotkey before handing off to the one-click hook installer.
- **Accessible**: VoiceOver labels on the pet bubble, tray rows, and stats tiles.
- **Localization groundwork**: `Localizable.strings` infrastructure in place, starting with the menu bar.
- **Hook Setup & Diagnostics**: a one-click installer that wires the hooks into `~/.claude/settings.json` for you (backing it up first) and points them at a fixed, checkout-independent script location, plus a health check for "the pet just isn't reacting."
- **Preferences window**: behavior, alerts (notifications/sounds/budget/digest), and display (multi-monitor docking), all in one place.
- **Pet Gallery**: browse and preview every installed pet before applying it, per-project or globally.
- **Launch at Login**, via `SMAppService`.
- Every number ClaudePet shows you is computed locally from files already on your Mac. Nothing is ever uploaded.

## Requirements

- macOS 13+
- Swift 5.9+ toolchain (Xcode Command Line Tools is enough — no Xcode project needed)
- Claude Code CLI, with hooks enabled

## Install

**Homebrew** (installs a tagged release build from GitHub Releases):

```bash
brew tap MOHAMEDSAMEER78/claudepet https://github.com/MOHAMEDSAMEER78/claudepet
brew install --cask claudepet
```

**Direct download**: grab the latest `.zip` from the [website](https://mohamedsameer78.github.io/claudepet/) or [Releases](https://github.com/MOHAMEDSAMEER78/claudepet/releases/latest), unzip, and drag `ClaudePet.app` to `/Applications`.

**Build from source:**

```bash
git clone https://github.com/MOHAMEDSAMEER78/claudepet
cd claudepet
./build_app.sh release
open ClaudePet.app
```

The app is a plain, unsigned (ad-hoc signed) `.app` bundle — there's no installer. Since it isn't notarized, macOS Gatekeeper will show an "unidentified developer" warning on first launch either way — approve it once via System Settings → Privacy & Security → Open Anyway.

Once installed, "Check for Updates…" in the menu bar checks for newer tagged releases automatically (via Sparkle) — this only covers checking/downloading updates, not the first-run Gatekeeper prompt above.

### Wire up the hooks

The easiest way: open the app, and either follow the first-run welcome tour into **Hook Setup & Diagnostics**, or open it directly from the menu bar and click **Install Hooks Automatically**. It copies the hook script to a fixed, checkout-independent location (`~/.claude/pet/bin/pet-hook.py`), merges the hook config into `~/.claude/settings.json` (backing it up first), and re-runs safely if you ever need to repair it.

To wire it up by hand instead, merge `hooks/settings-snippet.json` into your `~/.claude/settings.json` under the `"hooks"` key — if you already have hooks configured, **append** the new entries as additional matcher groups rather than replacing the key outright; hooks for the same event can have multiple groups and all of them run. `pet-hook.py` is a stdlib-only Python script; no `pip install` needed, just make sure it's executable.

### Claude usage tracking (optional)

From the same **Hook Setup & Diagnostics** window, "Enable Usage Tracking" installs a second script (`pet-hook/pet-statusline.py`) that claims Claude Code's `statusLine` setting. It snapshots the 5-hour/7-day rate-limit and cost fields Claude Code exposes there into `~/.claude/pet/usage.json`, then chains through to whatever statusLine command you already had configured (saved at install time), so your terminal's own status line output is completely unaffected. Disable it from the same window to restore your original statusLine setting.

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

- **Push, not poll, for the common case**: after every session/request file write, `pet-hook.py` also fires a best-effort datagram at a local Unix socket (`~/.claude/pet/notify-{sessions,requests}.sock`) the app is listening on, so the UI usually updates within milliseconds instead of waiting on the FSEvent watcher or the poll timer. The socket ping is purely additive — if it fails for any reason, the existing FSEvent watcher and a much-slower poll timer still catch the change on their own.
- **Hooks used**: `SessionStart`/`SessionEnd` (register/deregister), `UserPromptSubmit`/`PreToolUse`/`PostToolUse` (running), `Notification(permission_prompt)` + `PermissionRequest` (waiting), `Stop`/`SubagentStop` (review), `PostToolUseFailure`/`StopFailure` (failed), `TaskCreated`/`TaskCompleted` (progress ring counter).
- **Why `Stop`→decay instead of `idle_prompt`**: Claude Code's `idle_prompt` notification is documented as unreliable. Instead, `Stop` sets a "review" state that decays to idle after 20 seconds locally in the app — no dependency on that heuristic.
- **`PermissionRequest` is used for the waiting pose/notification, not `PreToolUse`**: `PreToolUse` fires on *every* tool call regardless of whether `permissions.defaultMode` auto-approves it. `PermissionRequest` only fires when Claude Code actually needs a human decision, so it never adds latency to auto-approved tool calls.
- **Priority when multiple sessions are active** (single-pet mode): needs-permission > failed > ready-for-review > running > idle — the same ordering used for the Activity Tray's sort order.
- **`statusLine` is a separate, single-slot mechanism**: it's the only place Claude Code exposes rate-limit usage, so the optional usage-tracking wrapper (see above) claims that slot itself rather than trying to piggyback on the hook events above, which never receive that data.

### Permission notifications, technically

`pet-hook.py await-permission` writes a request file to `~/.claude/pet/requests/<uuid>.json`, pings the app so a native notification fires, and returns **immediately** — no blocking, no polling, no in-app decision. It prints no `hookSpecificOutput`, which Claude Code treats exactly like a hook with no opinion: its own terminal prompt appears right away. ClaudePet never answers a permission request on your behalf, on purpose.

### Kill session, technically

The tray's kill button sends `SIGTERM` (escalating to `SIGKILL` after 1.5s if still alive) to the Claude Code CLI process. This only works when the hook's logical `session_id` matches the live process's own session id — true for normal `claude` invocations in a terminal, but **not** for daemon-managed/forked-resume sessions (some IDE integrations), where the button is inertly disabled rather than risk killing the wrong process.

### Mood, streaks, and spend, technically

All of it is derived on read from a local, append-only log (`~/.claude/pet/history.jsonl`) written once per finished session — there is no separate persisted aggregate to keep in sync. Streak = consecutive calendar days with at least one recorded session end. XP = `10 × tasks completed + 5 × sessions finished`; level = `floor(sqrt(xp / 100))`. Spend/token figures are snapshotted from Claude Code's own transcript file for that session at the moment it ends, using a hardcoded per-model pricing table (see "Known limitations").

## Custom pets

Drop a folder into `~/.claude/pets/<name>/` containing:
- `pet.json` — a manifest (Codex's real schema is just `id`/`displayName`/`description`/`spritesheetPath`; ClaudePet also accepts an explicit `rows`/`fps` override if you're hand-rolling one)
- a spritesheet PNG/WebP — 8 columns × 9 rows of 192×208px cells, rows in order: `idle, running-right, running-left, waving, jumping, failed, waiting, running, review`. Two more optional rows (`stretching`, `looking-around`) are picked up automatically if present, for extra idle variety. Frame count per row is auto-detected by scanning for the first fully-transparent cell (matching Codex's own convention) unless you declare `rows` explicitly.

Use the Pet Gallery (menu bar → **Pet Gallery…**) to browse, apply globally, or assign per-project.

## Menu bar

- **Wake/Tuck Away Pet (⌘⇧P)** — show/hide
- **Jump to Session… (⌘⇧K)** — command palette
- **Multi-Session Pets** — toggle one-panel-per-session mode
- **Wander When Idle** — toggle idle animations
- **Pet Gallery… / Session Stats… / Hook Setup & Diagnostics… / Welcome Tour…**
- **Preferences…**
- A read-only Claude usage row (5h/7d quota), shown only once usage tracking is enabled and has data
- **Check for Updates… / Quit Claude Pet**

## Known limitations

- No first-party integration — this breaks if Anthropic changes hook payload shapes, event names, or the `statusLine` JSON schema.
- `Notification`/permission-hook latency can be a couple of seconds in some Claude Code versions.
- Click-to-focus and kill-session both rely on process-tree/command-line heuristics to find the right terminal/process; they degrade gracefully (button does nothing / is disabled) rather than acting on a guess when the heuristic can't resolve. tmux sessions resolve to the right pane on a best-effort basis; VS Code/Cursor, Warp, Alacritty, and Ghostty don't expose a per-tab tty at all, so clicking one of those sessions only raises the app's window, not the specific tab (the tray row's tooltip says so).
- Not code-signed for distribution — ad-hoc signed locally by `build_app.sh` (or by the release CI job), fine for running on your own Mac, not for handing to someone else without re-signing. Sparkle auto-update covers checking/downloading newer releases, but doesn't remove the first-run Gatekeeper "unidentified developer" warning, since that specifically requires notarization.
- Token/cost estimates are read from Claude Code's own transcript files (`~/.claude/projects/*/<session_id>.jsonl`), which are an undocumented, internal format, not a stable API — this can break silently if that layout changes. Pricing is a hardcoded per-model table (standard tier) that will drift out of date; treat the numbers as a ballpark, not a bill.
- The weekly digest and budget-alert checks only run while the app is actually open/running — there's no OS-level scheduling, so a digest due while the app was quit fires (or doesn't) based on when it's next launched, not a fixed calendar time.
- **Platform support**: macOS 13+ only, by design — the app is built on AppKit (`NSPanel`, `NSStatusItem`), AppleScript (terminal-tab focusing), and `SMAppService` (Launch at Login) throughout, none of which have a Windows/Linux equivalent. There's no cross-platform version planned.

## Testing

`Sources/ClaudePetCore` holds the pure session-state logic (priority ordering, review decay, staleness, bubble text, streak/progress/spend aggregation) with no AppKit/file-I/O dependencies, unit tested in `Tests/ClaudePetCoreTests` via `swift test`. Running the suite needs a full Xcode install, not just Command Line Tools — CLT alone doesn't ship a working Swift Testing runtime by default. CI (`.github/workflows/ci.yml`) runs the full suite on every PR and posts a pass/fail summary with per-test failure detail to the run's Summary tab.

## Project layout

```
Sources/ClaudePet/       Swift app (AppKit NSPanel + SwiftUI content)
Sources/ClaudePetCore/   Pure session-state logic, unit tested, no AppKit dependency
Tests/ClaudePetCoreTests/  swift test suite for ClaudePetCore
hooks/pet-hook.py        The hook↔app bridge script (stdlib-only Python)
hooks/pet-statusline.py  Optional statusLine wrapper for Claude usage tracking
hooks/settings-snippet.json   Hook config to merge into ~/.claude/settings.json
docs/                    The project website (GitHub Pages, served from this folder on main)
build_app.sh             Builds Sources/ into ClaudePet.app
.github/workflows/       CI (build + test) and the tag-triggered release pipeline
```
