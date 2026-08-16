#!/usr/bin/env python3
"""
Bridge between Claude Code hooks and the ClaudePet menu-bar app.

Invoked by ~/.claude/settings.json hook entries as:
    pet-hook.py <state>
where <state> is one of: running, waiting-permission, review, idle,
session-start, session-end, await-permission, task-created, task-completed.

task-created/task-completed track a per-turn task-list progress counter
(tasks_done/tasks_total in the session file), mirroring the "N/M" progress
badge on Codex's activity cards. The counter resets to 0/0 whenever a
UserPromptSubmit hook fires (start of a new turn) so it reflects the
current turn's plan, not a running total across the whole session.

`await-permission` is special: it's meant for the PermissionRequest hook,
which only fires when Claude Code actually needs a decision (not on every
tool call). It blocks, polling for the user's Allow/Deny click on the pet's
bubble, and relays the decision back via hookSpecificOutput so the CLI can
continue without its own terminal prompt. On timeout or no PID-tracked
response, it exits quietly so Claude Code falls back to its normal prompt
- this hook can never make an unintended decision on your behalf, only
either defer to your bubble click or defer to the normal CLI flow.

Reads the hook's JSON payload from stdin, extracts session_id/cwd/tool
info, and writes/removes ~/.claude/pet/sessions/<session_id>.json for the
ClaudePet app to pick up (it watches that directory).

Keep this fast and dependency-free (stdlib only) - it must return in a
few milliseconds so it never blocks the agent turn.
"""
import json
import os
import subprocess
import sys
import time
import uuid

SESSIONS_DIR = os.path.expanduser("~/.claude/pet/sessions")
REQUESTS_DIR = os.path.expanduser("~/.claude/pet/requests")
RESPONSES_DIR = os.path.expanduser("~/.claude/pet/responses")

# How long to block waiting for an Allow/Deny click before giving up and
# falling back to Claude Code's normal permission prompt. Keep comfortably
# under the "timeout" configured for this hook in settings.json. Kept short
# (not the full hook timeout) because if the user answers Claude Code's own
# terminal prompt instead of the pet's bubble, this process has no way to
# detect that directly - the shorter this is, the sooner the pet's stuck
# "waiting for permission" pose clears itself instead of sitting there for
# minutes after the decision was actually already made elsewhere.
AWAIT_PERMISSION_TIMEOUT_SECONDS = 45
POLL_INTERVAL_SECONDS = 0.15

# GUI apps we recognize as "the terminal" when walking up the process tree.
# This is a best-effort heuristic (see gmr/claude-status precedent) - good
# enough to bring the right app forward, not necessarily the exact tab/pane.
#
# Only the TOP-LEVEL app process name goes here. Electron apps (VS Code,
# Cursor) run many "<App> Helper" child processes (renderer/GPU/utility
# subprocesses) that sit between the shell and the real app in the process
# tree - those are not real NSRunningApplication-activatable windows, so we
# must climb PAST any "<name> Helper..." process rather than stop on it,
# or NSRunningApplication.activate() silently no-ops on a helper pid that
# has no window to raise.
TOP_LEVEL_APP_COMMS = {
    "Terminal", "iTerm2", "WezTerm", "Alacritty", "kitty", "Hyper",
    "Code", "Cursor",
}


def find_terminal_ancestor(pid, max_hops=25):
    """Walk parent PIDs looking for a recognizable terminal/IDE app, and
    along the way remember the tty of the last real (non-GUI) ancestor -
    that's the specific pty this Claude Code session is attached to, which
    is what lets us focus the exact tab/window rather than just the app.
    Returns (terminal_pid, terminal_comm, tty) - tty is like "/dev/ttys001"
    or None if this ancestor chain never touches a real tty (e.g. some IDE
    integrations run fully detached from a pty).
    """
    current = pid
    last_real_tty = None
    for _ in range(max_hops):
        try:
            out = subprocess.run(
                ["ps", "-o", "ppid=,tty=,comm=", "-p", str(current)],
                capture_output=True, text=True, timeout=1,
            ).stdout.strip()
        except Exception:
            return None, None, last_real_tty
        if not out:
            return None, None, last_real_tty
        parts = out.split(None, 2)
        if len(parts) != 3:
            return None, None, last_real_tty
        ppid_str, tty, comm = parts
        if tty and tty != "??":
            last_real_tty = f"/dev/{tty}"
        comm_base = os.path.basename(comm)
        if comm_base in TOP_LEVEL_APP_COMMS:
            return int(current), comm_base, last_real_tty
        try:
            ppid = int(ppid_str)
        except ValueError:
            return None, None, last_real_tty
        if ppid <= 1:
            return None, None, last_real_tty
        current = ppid
    return None, None, last_real_tty


def find_claude_pid(session_id):
    """Find the actual Claude Code CLI process for this session, so the pet's
    tray can offer a real "kill session" action. Claude Code launches each
    session as its own process with `--session-id <id>` on the command line
    (visible even through --fork-session/--resume), so we match on that
    rather than walking the hook's own ancestry - far more precise than the
    terminal-app heuristic used for click-to-focus.
    """
    if not session_id or session_id == "unknown":
        return None
    try:
        out = subprocess.run(
            ["ps", "-eo", "pid=,command="],
            capture_output=True, text=True, timeout=1,
        ).stdout
    except Exception:
        return None
    needle = f"--session-id {session_id}"
    for line in out.splitlines():
        line = line.strip()
        if needle in line and "bg-pty-host" not in line and "bg-spare" not in line:
            pid_str = line.split(None, 1)[0]
            try:
                return int(pid_str)
            except ValueError:
                continue
    return None


def load_existing_status(session_file):
    try:
        with open(session_file) as f:
            return json.load(f)
    except Exception:
        return {}


def resolved_title(payload, existing):
    """The session's display title: frozen to the first user prompt of the
    conversation (like ChatGPT/Codex auto-titling a chat), not overwritten
    on later turns. We don't know Claude Code's exact field name for the
    submitted prompt text, so we try several plausible keys.
    """
    if existing.get("title"):
        return existing["title"]
    if payload.get("hook_event_name") != "UserPromptSubmit":
        return None
    for key in ("prompt", "message", "user_prompt", "input", "text"):
        val = payload.get(key)
        if isinstance(val, str) and val.strip():
            cleaned = " ".join(val.split())
            if len(cleaned) > 60:
                cleaned = cleaned[:57] + "..."
            return cleaned
    return None


def resolved_task_counts(payload, existing):
    """Carries the running tasks_done/tasks_total forward, incrementing for
    task-created/task-completed and resetting on a fresh turn.
    """
    done = existing.get("tasks_done") or 0
    total = existing.get("tasks_total") or 0
    if payload.get("hook_event_name") == "UserPromptSubmit":
        done, total = 0, 0
    return done, total


def summarize_tool(payload):
    tool_name = payload.get("tool_name")
    tool_input = payload.get("tool_input") or {}
    if not tool_name:
        return tool_name, None

    for key in ("file_path", "command", "path", "pattern", "url"):
        if key in tool_input and tool_input[key]:
            value = str(tool_input[key])
            if len(value) > 60:
                value = value[:57] + "..."
            return tool_name, value
    return tool_name, None


def _truncate(value, limit=48):
    value = str(value).strip()
    if len(value) > limit:
        value = value[: limit - 3] + "..."
    return value


def humanize_action(tool_name, tool_input):
    """A short, present-tense, natural-language sentence describing what the
    agent is doing right now - e.g. "Editing SessionStore.swift" instead of
    the raw "Edit · SessionStore.swift" ('tool · arg') the bubble showed
    before. Mirrors the plain-English progress lines Codex's own activity
    card shows (e.g. "Done. I made a simplified Codex pet from the dragon
    image, using the...") rather than surfacing tool/arg internals.
    """
    if not tool_name:
        return None
    ti = tool_input or {}

    if tool_name == "Bash":
        cmd = ti.get("command")
        return f"Running `{_truncate(cmd)}`" if cmd else "Running a command"
    if tool_name in ("Edit", "Write", "MultiEdit"):
        path = ti.get("file_path")
        name = os.path.basename(path) if path else None
        return f"Editing {name}" if name else "Editing a file"
    if tool_name == "NotebookEdit":
        path = ti.get("notebook_path")
        name = os.path.basename(path) if path else None
        return f"Editing {name}" if name else "Editing a notebook"
    if tool_name == "Read":
        path = ti.get("file_path")
        name = os.path.basename(path) if path else None
        return f"Reading {name}" if name else "Reading a file"
    if tool_name == "Grep":
        pattern = ti.get("pattern")
        return f'Searching for "{_truncate(pattern, 30)}"' if pattern else "Searching the codebase"
    if tool_name == "Glob":
        pattern = ti.get("pattern")
        return f"Finding files matching {_truncate(pattern, 30)}" if pattern else "Finding files"
    if tool_name in ("WebFetch", "WebSearch"):
        target = ti.get("url") or ti.get("query")
        return f"Looking up {_truncate(target, 40)}" if target else "Searching the web"
    if tool_name == "TodoWrite":
        return "Updating the task list"
    if tool_name == "Task":
        desc = ti.get("description")
        return f"Delegating: {_truncate(desc, 40)}" if desc else "Running a subtask"
    if tool_name.startswith("mcp__"):
        return f"Using {tool_name.split('__')[-1]}"
    return f"Using {tool_name}"


def await_permission_decision(session_id, session_file, cwd, tool, summary):
    """Write a request file, block polling for the app's response, and print
    the hookSpecificOutput Claude Code expects. Exits 0 in every case -
    worst case (timeout, bad response, no app running) is silent fallback
    to the normal CLI permission prompt, never an unreviewed auto-allow.

    On timeout (most commonly: the user answered Claude Code's own terminal
    prompt instead of the pet's bubble), the session file gets explicitly
    reset off "waiting-permission" - otherwise the pet would keep showing
    its waiting pose/bubble indefinitely, since nothing else touches this
    session's state until whatever hook happens to fire next.
    """
    os.makedirs(REQUESTS_DIR, exist_ok=True)
    os.makedirs(RESPONSES_DIR, exist_ok=True)

    request_id = str(uuid.uuid4())
    request = {
        "request_id": request_id,
        "session_id": session_id,
        "cwd": cwd,
        "tool": tool,
        "summary": summary,
        "ts": time.time(),
    }
    request_path = os.path.join(REQUESTS_DIR, f"{request_id}.json")
    tmp_path = request_path + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(request, f)
    os.replace(tmp_path, request_path)

    response_path = os.path.join(RESPONSES_DIR, f"{request_id}.json")
    deadline = time.time() + AWAIT_PERMISSION_TIMEOUT_SECONDS
    decision = None
    while time.time() < deadline:
        if os.path.exists(response_path):
            try:
                with open(response_path) as f:
                    decision = json.load(f).get("decision")
            except Exception:
                decision = None
            try:
                os.remove(response_path)
            except FileNotFoundError:
                pass
            break
        time.sleep(POLL_INTERVAL_SECONDS)

    try:
        os.remove(request_path)
    except FileNotFoundError:
        pass

    if decision not in ("allow", "deny"):
        # Timed out or unreadable - fall back to Claude Code's normal prompt,
        # and clear our own "waiting-permission" state so the pet doesn't
        # keep showing that pose/bubble after the decision was made outside
        # the app (e.g. answered directly in the terminal).
        existing = load_existing_status(session_file)
        if existing.get("state") == "waiting-permission":
            existing["state"] = "running"
            existing["ts"] = time.time()
            tmp_path = session_file + ".tmp"
            with open(tmp_path, "w") as f:
                json.dump(existing, f)
            os.replace(tmp_path, session_file)
        return

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "permissionDecision": decision,
            "permissionDecisionReason": "Decided via ClaudePet overlay",
        }
    }))


def main():
    state = sys.argv[1] if len(sys.argv) > 1 else "idle"

    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}

    session_id = payload.get("session_id", "unknown")
    os.makedirs(SESSIONS_DIR, exist_ok=True)
    session_file = os.path.join(SESSIONS_DIR, f"{session_id}.json")

    if state == "session-end":
        try:
            os.remove(session_file)
        except FileNotFoundError:
            pass
        return

    existing = load_existing_status(session_file)
    tasks_done, tasks_total = resolved_task_counts(payload, existing)
    title = resolved_title(payload, existing)

    if state == "await-permission":
        tool, summary = summarize_tool(payload)
        action = humanize_action(tool, payload.get("tool_input"))
        action = f"Needs permission: {action[0].lower()}{action[1:]}" if action else "Needs your permission to continue"
        # Still surface the waiting-permission pet state immediately so the
        # bubble/animation shows up without waiting on the blocking call below.
        terminal_pid, terminal_app, tty = find_terminal_ancestor(os.getpid())
        claude_pid = find_claude_pid(session_id)
        status = {
            "session_id": session_id, "state": "waiting-permission",
            "cwd": payload.get("cwd"), "tool": tool, "summary": summary, "action": action,
            "ts": time.time(), "terminal_pid": terminal_pid, "terminal_app": terminal_app,
            "tty": tty, "tasks_done": tasks_done, "tasks_total": tasks_total, "title": title,
            "claude_pid": claude_pid,
        }
        tmp_path = session_file + ".tmp"
        with open(tmp_path, "w") as f:
            json.dump(status, f)
        os.replace(tmp_path, session_file)

        await_permission_decision(session_id, session_file, payload.get("cwd"), tool, summary)
        return

    if state == "task-created":
        tasks_total += 1
    elif state == "task-completed":
        tasks_done += 1

    if state in ("task-created", "task-completed"):
        # Purely a counter update - keep whatever pet state/tool/cwd/summary
        # was already showing rather than overwriting it.
        effective_state = existing.get("state", "running")
        tool = existing.get("tool")
        summary = existing.get("summary")
        cwd = existing.get("cwd")
        action = existing.get("action")
    else:
        effective_state = "idle" if state == "session-start" else state
        tool, summary = summarize_tool(payload)
        cwd = payload.get("cwd")
        action = humanize_action(tool, payload.get("tool_input"))
        if not action:
            # No tool call in this event (e.g. UserPromptSubmit, Stop,
            # PostToolUseFailure) - fall back to a plain-English sentence for
            # the state itself, matching Codex's "Done. I made a..." style
            # instead of leaving the bubble blank or showing raw internals.
            action = {
                "idle": "Waiting for your next message",
                "running": "Thinking...",
                "review": "Done - ready for your review",
                "failed": "Something went wrong",
            }.get(effective_state)

    terminal_pid, terminal_app, tty = find_terminal_ancestor(os.getpid())
    claude_pid = find_claude_pid(session_id)

    status = {
        "session_id": session_id,
        "state": effective_state,
        "cwd": cwd,
        "tool": tool,
        "summary": summary,
        "action": action,
        "ts": time.time(),
        "terminal_pid": terminal_pid,
        "terminal_app": terminal_app,
        "tty": tty,
        "tasks_done": tasks_done,
        "tasks_total": tasks_total,
        "title": title,
        "claude_pid": claude_pid,
    }

    tmp_path = session_file + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(status, f)
    os.replace(tmp_path, session_file)


if __name__ == "__main__":
    main()
