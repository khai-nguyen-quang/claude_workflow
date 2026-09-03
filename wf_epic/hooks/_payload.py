#!/usr/bin/env python3
"""
Extract what the hooks need from a Claude Code hook payload.

DELIBERATE DESIGN: we do NOT guess key names. Hook payload schemas differ between
Claude Code versions, and a wrong key path fails silently, which for TaskCompleted
means a gate that never runs. Instead we search the payload recursively for a string
matching a known pattern — our task ids ("code:tvi-linux-56", "review:x.r1") and our
teammate names are distinctive enough to find by shape.

Run any hook with WF_EPIC_DEBUG=1 to dump the raw payload to
$WF_EPIC_TMP/hook_payload.json and confirm what your version actually sends.
"""
import json
import os
import re
import sys

TASK_RE = re.compile(r"^(code|review|fix):[A-Za-z0-9._-]+$")
LANES = {"coder": "code", "reviewer": "review", "fixer": "fix"}


def _walk(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for v in node.values():
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)


def load():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}
    if os.environ.get("WF_EPIC_DEBUG") == "1":
        tmp = os.environ.get("WF_EPIC_TMP", "/tmp")
        with open(os.path.join(tmp, "hook_payload.json"), "w") as fh:
            fh.write(raw)
    return payload


def find_task(payload):
    """First string in the payload shaped like one of our task ids."""
    for s in _walk(payload):
        if TASK_RE.match(s.strip()):
            return s.strip()
    return None


def find_lane(payload):
    """Lane of the teammate this event is about, via its name."""
    for s in _walk(payload):
        lane = LANES.get(s.strip().lower())
        if lane:
            return lane
    return None


def parse_task(task):
    """'review:tvi-linux-56.r2' -> ('review', 'tvi-linux-56', 2)"""
    lane, rest = task.split(":", 1)
    m = re.fullmatch(r"(.+?)\.r(\d+)", rest)
    return (lane, m.group(1), int(m.group(2))) if m else (lane, rest, 0)


if __name__ == "__main__":
    p = load()
    what = sys.argv[1] if len(sys.argv) > 1 else "task"
    print((find_task(p) if what == "task" else find_lane(p)) or "")
