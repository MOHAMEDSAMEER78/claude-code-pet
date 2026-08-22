#!/usr/bin/env python3
"""
Claude Code `statusLine` wrapper for the ClaudePet menu-bar app.

`statusLine` is a single-slot Claude Code setting (one command, invoked
once per render with a JSON payload on stdin describing model/cost/
context/rate-limit state, whose stdout becomes the terminal's status
line). That JSON is the only place Claude Code exposes its 5-hour and
7-day rate-limit usage percentages - they aren't available to the
PreToolUse/PostToolUse/etc. hooks pet-hook.py already uses.

Since only one command can hold that slot, this wrapper claims it,
snapshots the usage fields ClaudePet cares about to
~/.claude/pet/usage.json, then chains through to whatever command was
registered before ClaudePet claimed the slot (recorded by HookInstaller
in ~/.claude/pet/original-statusline.json at install time) - so a user
who already had their own statusLine script sees no difference at all.
If there was nothing registered before, this renders a plain equivalent
of Claude Code's own default line instead of leaving the terminal blank.

Keep this fast and dependency-free (stdlib only), same as pet-hook.py -
it runs on every status line render.
"""
import json
import os
import subprocess
import sys
import time

USAGE_FILE = os.path.expanduser("~/.claude/pet/usage.json")
ORIGINAL_CONFIG_FILE = os.path.expanduser("~/.claude/pet/original-statusline.json")


def write_usage(payload):
    rate_limits = payload.get("rate_limits") or {}
    five_hour = (rate_limits.get("five_hour") or {}).get("used_percentage")
    seven_day = (rate_limits.get("seven_day") or {}).get("used_percentage")
    cost = (payload.get("cost") or {}).get("total_cost_usd")
    context = (payload.get("context_window") or {}).get("used_percentage")
    data = {
        "fiveHourUsedPct": five_hour,
        "sevenDayUsedPct": seven_day,
        "costUSD": cost,
        "contextUsedPct": context,
        "updatedAt": time.time(),
    }
    tmp = USAGE_FILE + ".tmp"
    os.makedirs(os.path.dirname(USAGE_FILE), exist_ok=True)
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, USAGE_FILE)


def default_status_line(payload):
    model = (payload.get("model") or {}).get("display_name") or "Claude"
    cost = (payload.get("cost") or {}).get("total_cost_usd") or 0
    five_used = ((payload.get("rate_limits") or {}).get("five_hour") or {}).get("used_percentage") or 0
    return "{} | ${:.3f} | {:.0f}% 5h quota left".format(model, cost, 100 - five_used)


def chained_output(original, raw_stdin):
    if not isinstance(original, dict) or not original.get("command"):
        return None
    try:
        result = subprocess.run(
            original["command"], input=raw_stdin, shell=True,
            capture_output=True, timeout=5
        )
        return result.stdout
    except (OSError, subprocess.SubprocessError):
        return None


def main():
    raw = sys.stdin.buffer.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}

    try:
        write_usage(payload)
    except OSError:
        pass  # usage tracking must never block the status line itself

    original = None
    try:
        with open(ORIGINAL_CONFIG_FILE) as f:
            original = json.load(f)
    except (OSError, ValueError):
        original = None

    output = chained_output(original, raw)
    if output is not None:
        sys.stdout.buffer.write(output)
    else:
        sys.stdout.write(default_status_line(payload))


if __name__ == "__main__":
    main()
