#!/usr/bin/env python3
"""
Seed the implementation phase: epic -> child tickets -> worktrees -> queue file.

Worktrees are created UP FRONT and SERIALIZED. `worktree.sh ensure` races on the main
checkout's index.lock, and a new worktree takes ~2 minutes (fetch + recursive submodule
init), so for 7 tickets this is a ~15-minute setup that must happen once, before any
teammate starts — not lazily mid-stream.

Non-implementation children (design::, research::, spike::, doc:: in the title or
description) are EXCLUDED by default. A coder handed a design ticket will try to
implement a design; --include-all overrides this if you really mean it.

Usage:
    seed_epic.py Epic#116 [--tickets tvi-linux#56 tvi-linux#57] [--skip-worktrees]
"""
import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CW = HERE.parent.parent                       # claude_workflow/
WORKTREE_SH = CW / "tools" / "git" / "worktree.sh"
GRAPH = HERE.parent / "engine" / "graph.py"


def slug(ref: str) -> str:
    project, iid = ref.split("#")
    return f"{project}-{iid}"



def filter_impl(epic: str, refs: list) -> list:
    """Drop non-implementation children (design::, research:: …) from the queue."""
    proc = subprocess.run([sys.executable, str(HERE / "fetch_epic.py"), epic, "--json"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return refs
    import json
    sys.path.insert(0, str(HERE))
    from fetch_epic import child_ref, classify
    kinds = {child_ref(i): classify(i) for i in json.loads(proc.stdout)["issues"]}
    keep, dropped = [], []
    for r in refs:
        (keep if kinds.get(r, "impl") == "impl" else dropped).append(r)
    for r in dropped:
        print(f"  excluded {r} ({kinds[r]}:: — not implementation work)")
    return keep


def ensure_worktree(ref: str) -> str:
    """Returns the worktree path (last line of stdout), or '-' on failure."""
    if not WORKTREE_SH.exists():
        print(f"  ! {WORKTREE_SH} not found — recording '-'", file=sys.stderr)
        return "-"
    t0 = time.time()
    print(f"  {ref}: creating worktree …", flush=True)
    proc = subprocess.run(["bash", str(WORKTREE_SH), "ensure", ref],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"  ! {ref}: worktree.sh failed:\n{proc.stderr.strip()[:400]}", file=sys.stderr)
        return "-"
    path = proc.stdout.strip().splitlines()[-1].strip()
    print(f"  {ref}: {path}  ({time.time() - t0:.0f}s)")
    return path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("epic", help="Epic#<id>")
    ap.add_argument("--tickets", nargs="*", metavar="REF",
                    help="override the child list (default: fetch from the epic)")
    ap.add_argument("--skip-worktrees", action="store_true",
                    help="record '-' instead of creating worktrees (for a dry run)")
    ap.add_argument("--force", action="store_true", help="overwrite an existing queue")
    ap.add_argument("--include-all", action="store_true",
                    help="also queue design::/research:: tickets (normally excluded)")
    a = ap.parse_args()

    m = re.fullmatch(r"(?i)epic#(\d+)", a.epic.strip())
    if not m:
        sys.exit(f"Error: '{a.epic}' is not an epic ref. Expected Epic#<id>.")
    epic_slug = f"epic-{m.group(1)}"

    refs = a.tickets
    if not refs:
        proc = subprocess.run([sys.executable, str(HERE / "fetch_epic.py"), a.epic, "--refs-only"],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            sys.exit(proc.stderr.strip())
        refs = [r for r in proc.stdout.split() if "#" in r]
        if not a.include_all:
            refs = filter_impl(a.epic, refs)
    if not refs:
        sys.exit(f"{a.epic} has no implementation tickets. Run the split phase first.")

    print(f"{a.epic}: {len(refs)} tickets")
    tmp = CW / ".tmp" / epic_slug
    tmp.mkdir(parents=True, exist_ok=True)

    specs = []
    for ref in refs:
        wt = "-" if a.skip_worktrees else ensure_worktree(ref)
        specs.append(f"{slug(ref)}={wt}")

    queue = tmp / f"{epic_slug}_queue.md"
    cmd = [sys.executable, str(GRAPH), "--queue", str(queue), "seed",
           "--epic", epic_slug, "--tickets", *specs]
    if a.force:
        cmd.append("--force")
    subprocess.run(cmd, check=True)
    print(f"\nexport WF_EPIC_QUEUE={queue}")
    print(f"export WF_EPIC_ROOT={CW.parent}")


if __name__ == "__main__":
    main()
