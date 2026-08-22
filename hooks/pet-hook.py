#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import time
import uuid

SESSIONS_DIR = os.path.expanduser("~/.claude/pet/sessions")
REQUESTS_DIR = os.path.expanduser("~/.claude/pet/requests")

SCHEMA_VERSION = 1

SESSIONS_NOTIFY_SOCKET = os.path.expanduser("~/.claude/pet/notify-sessions.sock")
REQUESTS_NOTIFY_SOCKET = os.path.expanduser("~/.claude/pet/notify-requests.sock")


def notify(socket_path):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
            sock.settimeout(0.05)
            sock.sendto(b"changed", socket_path)
    except OSError:
        pass

TOP_LEVEL_APP_COMMS = {
    "Terminal", "iTerm2", "WezTerm", "Alacritty", "kitty", "Hyper",
    "Code", "Cursor",
}


def atomic_write_json(path, data):
    tmp_path = f"{path}.{os.getpid()}.{uuid.uuid4().hex[:8]}.tmp"
    with open(tmp_path, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, path)


def find_terminal_ancestor(pid, max_hops=25):
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


def resolve_process_info(existing, session_id, hook_state):
    if hook_state == "session-start" or not existing.get("claude_pid"):
        terminal_pid, terminal_app, tty = find_terminal_ancestor(os.getpid())
        claude_pid = find_claude_pid(session_id)
        return terminal_pid, terminal_app, tty, claude_pid
    return (
        existing.get("terminal_pid"),
        existing.get("terminal_app"),
        existing.get("tty"),
        existing.get("claude_pid"),
    )


def load_existing_status(session_file):
    try:
        with open(session_file) as f:
            return json.load(f)
    except Exception:
        return {}


def resolved_title(payload, existing):
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


def notify_permission_needed(session_id, cwd, tool, summary):
    os.makedirs(REQUESTS_DIR, exist_ok=True)
    request_id = str(uuid.uuid4())
    request = {
        "request_id": request_id,
        "session_id": session_id,
        "cwd": cwd,
        "tool": tool,
        "summary": summary,
        "ts": time.time(),
        "schema": SCHEMA_VERSION,
    }
    atomic_write_json(os.path.join(REQUESTS_DIR, f"{request_id}.json"), request)
    notify(REQUESTS_NOTIFY_SOCKET)


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
            notify(SESSIONS_NOTIFY_SOCKET)
        except FileNotFoundError:
            pass
        return

    existing = load_existing_status(session_file)
    tasks_done, tasks_total = resolved_task_counts(payload, existing)
    title = resolved_title(payload, existing)
    started_ts = existing.get("started_ts") or time.time()

    if state == "await-permission":
        tool, summary = summarize_tool(payload)
        action = humanize_action(tool, payload.get("tool_input"))
        action = f"Needs permission: {action[0].lower()}{action[1:]}" if action else "Needs your permission to continue"
        terminal_pid, terminal_app, tty, claude_pid = resolve_process_info(existing, session_id, state)
        status = {
            "session_id": session_id, "state": "waiting-permission",
            "cwd": payload.get("cwd"), "tool": tool, "summary": summary, "action": action,
            "ts": time.time(), "terminal_pid": terminal_pid, "terminal_app": terminal_app,
            "tty": tty, "tasks_done": tasks_done, "tasks_total": tasks_total, "title": title,
            "claude_pid": claude_pid, "schema": SCHEMA_VERSION, "started_ts": started_ts,
        }
        atomic_write_json(session_file, status)
        notify(SESSIONS_NOTIFY_SOCKET)

        notify_permission_needed(session_id, payload.get("cwd"), tool, summary)
        return

    if state == "task-created":
        tasks_total += 1
    elif state == "task-completed":
        tasks_done += 1

    if state in ("task-created", "task-completed"):
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
            action = {
                "idle": "Waiting for your next message",
                "running": "Thinking...",
                "review": "Done - ready for your review",
                "failed": "Something went wrong",
            }.get(effective_state)

    terminal_pid, terminal_app, tty, claude_pid = resolve_process_info(existing, session_id, state)

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
        "schema": SCHEMA_VERSION,
        "started_ts": started_ts,
    }

    atomic_write_json(session_file, status)
    notify(SESSIONS_NOTIFY_SOCKET)


if __name__ == "__main__":
    main()
