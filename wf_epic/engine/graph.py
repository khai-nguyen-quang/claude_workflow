#!/usr/bin/env python3
"""
Task graph engine for the epic implementation phase (template/epic_workflow.md §6).

The queue file is the SOURCE OF TRUTH. The Claude Code task list is a projection of
it: team names are session-derived, so a fresh session starts with an empty task list
and the graph must be rebuildable from disk.

The graph is not stored as edges. It is DERIVED from an ordered ticket list plus each
ticket's state, which keeps the on-disk format small enough for a human to edit:

  pending -> coding -> review(r1) -+-> done                    (PRODUCTION READY)
                                   +-> fixing(r1) -> review(r2) -+-> done
                                                                 +-> blocked

  done and blocked are TERMINAL and both release WIP backpressure. That is the whole
  point of `blocked`: without a terminal state for a non-converging ticket, the WIP
  edge would stall the coder forever and freeze the epic.

WIP backpressure: ticket at position n may only start coding once the ticket at
position n-WIP has reached a terminal state.
"""

import argparse
import datetime
import json
import re
import sys
from pathlib import Path

MAX_ROUNDS = 2  # review rounds per ticket; see §6 "Exit conditions"
WIP = 2

STATES = ("pending", "coding", "review", "fixing", "done", "blocked")
TERMINAL = ("done", "blocked")
LANES = {"coding": "code", "review": "review", "fixing": "fix"}

COLUMNS = ["#", "ticket", "project", "state", "round", "findings", "worktree", "updated", "note"]


def _now():
    return datetime.datetime.now().replace(microsecond=0).isoformat()


class Queue:
    def __init__(self, path, epic=None, rows=None):
        self.path = Path(path)
        self.epic = epic
        self.rows = rows or []

    # ---------- persistence ----------

    @classmethod
    def load(cls, path):
        p = Path(path)
        if not p.exists():
            sys.exit(f"queue file not found: {p}\nRun `graph.py seed` first.")
        text = p.read_text()
        m = re.search(r"^#\s*Queue:\s*(\S+)", text, re.M)
        epic = m.group(1) if m else None
        rows = []
        for line in text.splitlines():
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != len(COLUMNS) or cells[0] in ("#", "---") or set(cells[0]) <= {"-", ":"}:
                continue
            row = dict(zip(COLUMNS, cells))
            row["#"] = int(row["#"])
            row["round"] = int(row["round"])
            rows.append(row)
        rows.sort(key=lambda r: r["#"])
        return cls(p, epic, rows)

    def save(self):
        w = {c: max(len(c), *(len(str(r[c])) for r in self.rows)) if self.rows else len(c)
             for c in COLUMNS}
        out = [f"# Queue: {self.epic}", "",
               "Source of truth for the implementation task graph. The Claude Code task list is a",
               "projection of this file; rebuild it with `graph.py next` after any restart.", "",
               "| " + " | ".join(c.ljust(w[c]) for c in COLUMNS) + " |",
               "|" + "|".join("-" * (w[c] + 2) for c in COLUMNS) + "|"]
        for r in self.rows:
            out.append("| " + " | ".join(str(r[c]).ljust(w[c]) for c in COLUMNS) + " |")
        out += ["", self._summary_line(), ""]
        self.path.write_text("\n".join(out))

    def _summary_line(self):
        c = {s: sum(1 for r in self.rows if r["state"] == s) for s in STATES}
        parts = [f"{s}={c[s]}" for s in STATES if c[s]]
        return f"<!-- {' '.join(parts)} drained={str(self.drained()).lower()} -->"

    # ---------- queries ----------

    def find(self, ticket):
        for r in self.rows:
            if r["ticket"] == ticket:
                return r
        sys.exit(f"ticket not in queue: {ticket}")

    def drained(self):
        return all(r["state"] in TERMINAL for r in self.rows)

    def _wip_ok(self, row):
        """A ticket may start coding only once the one WIP positions earlier is terminal."""
        gate_pos = row["#"] - WIP
        if gate_pos < 1:
            return True
        for other in self.rows:
            if other["#"] == gate_pos:
                return other["state"] in TERMINAL
        return True

    def next_tasks(self):
        """Tasks that should exist right now — one active task per non-terminal ticket."""
        tasks = []
        for r in self.rows:
            st = r["state"]
            if st in TERMINAL:
                continue
            if st == "pending":
                if not self._wip_ok(r):
                    continue
                tid, lane = f"code:{r['ticket']}", "code"
            else:
                lane = LANES[st]
                tid = f"{lane}:{r['ticket']}"
                if st in ("review", "fixing"):
                    tid += f".r{r['round']}"
            tasks.append({"task": tid, "lane": lane, "ticket": r["ticket"],
                          "project": r["project"], "worktree": r["worktree"],
                          "round": r["round"], "state": st})
        return tasks

    # ---------- transitions ----------

    def advance(self, ticket, event, findings=None, note=""):
        r = self.find(ticket)
        st, rnd = r["state"], r["round"]

        if event == "claim-code":
            self._require(r, "pending", event)
            if not self._wip_ok(r):
                sys.exit(f"WIP limit: {ticket} blocked behind position {r['#'] - WIP}")
            r["state"], r["round"] = "coding", 0

        elif event == "code-done":
            self._require(r, "coding", event)
            r["state"], r["round"] = "review", 1

        elif event == "review-ok":
            self._require(r, "review", event)
            r["state"], r["note"] = "done", note or "PRODUCTION READY"

        elif event == "review-findings":
            self._require(r, "review", event)
            if findings is None:
                sys.exit("--findings <n> is required for review-findings (divergence check)")
            prev = self._findings(r).get(rnd - 1)
            self._set_findings(r, rnd, findings)
            if prev is not None and findings >= prev:
                r["state"] = "blocked"
                r["note"] = f"diverging: r{rnd-1}={prev} r{rnd}={findings}"
            elif rnd >= MAX_ROUNDS:
                r["state"] = "blocked"
                r["note"] = f"round cap {MAX_ROUNDS} reached with {findings} findings"
            else:
                r["state"] = "fixing"

        elif event == "fix-done":
            self._require(r, "fixing", event)
            r["state"], r["round"] = "review", rnd + 1

        elif event == "block":
            r["state"], r["note"] = "blocked", note or "blocked"

        elif event == "reopen":
            if r["state"] != "blocked":
                sys.exit(f"{ticket} is not blocked")
            r["state"], r["note"] = "review", note or "reopened by human"

        else:
            sys.exit(f"unknown event: {event}")

        r["updated"] = _now()
        return r

    @staticmethod
    def _require(row, want, event):
        if row["state"] != want:
            sys.exit(f"{row['ticket']}: event '{event}' needs state '{want}', found '{row['state']}'")

    @staticmethod
    def _findings(row):
        out = {}
        for part in row["findings"].split(","):
            m = re.fullmatch(r"r(\d+)=(\d+)", part.strip())
            if m:
                out[int(m.group(1))] = int(m.group(2))
        return out

    def _set_findings(self, row, rnd, n):
        f = self._findings(row)
        f[rnd] = n
        row["findings"] = ",".join(f"r{k}={f[k]}" for k in sorted(f)) or "-"


def cmd_seed(a):
    rows = []
    for i, spec in enumerate(a.tickets, 1):
        ticket = spec.split("=")[0]
        worktree = spec.split("=", 1)[1] if "=" in spec else "-"
        project = ticket.rsplit("-", 1)[0] if "-" in ticket else ticket
        rows.append({"#": i, "ticket": ticket, "project": project, "state": "pending",
                     "round": 0, "findings": "-", "worktree": worktree,
                     "updated": _now(), "note": "-"})
    q = Queue(a.queue, a.epic, rows)
    if q.path.exists() and not a.force:
        sys.exit(f"{q.path} exists; pass --force to overwrite (this discards progress)")
    q.save()
    print(f"seeded {len(rows)} tickets -> {q.path}")


def cmd_status(a):
    q = Queue.load(a.queue)
    if a.json:
        print(json.dumps({"epic": q.epic, "drained": q.drained(), "tickets": q.rows}, indent=2))
        return
    print(f"Epic {q.epic} — {'DRAINED' if q.drained() else 'in progress'}")
    for r in q.rows:
        rd = f"r{r['round']}" if r["round"] else "-"
        print(f"  {r['#']:>2}. {r['ticket']:<20} {r['state']:<8} {rd:<4} {r['findings']:<12} {r['note']}")
    blocked = [r for r in q.rows if r["state"] == "blocked"]
    if blocked:
        print(f"\n{len(blocked)} BLOCKED — needs a human:")
        for r in blocked:
            print(f"  {r['ticket']}: {r['note']}")


def cmd_next(a):
    q = Queue.load(a.queue)
    tasks = q.next_tasks()
    if a.json:
        print(json.dumps(tasks, indent=2))
    else:
        for t in tasks:
            print(f"{t['task']}\t{t['lane']}\t{t['worktree']}")
    if not tasks and q.drained():
        print("# queue drained", file=sys.stderr)


def cmd_advance(a):
    q = Queue.load(a.queue)
    r = q.advance(a.ticket, a.event, a.findings, a.note or "")
    q.save()
    print(f"{r['ticket']}: {a.event} -> {r['state']} r{r['round']} {r['note']}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--queue", required=True, help="path to <epic-slug>_queue.md")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("seed", help="create the queue from a ticket list")
    s.add_argument("--epic", required=True)
    s.add_argument("--tickets", nargs="+", required=True, metavar="SLUG[=WORKTREE]")
    s.add_argument("--force", action="store_true")
    s.set_defaults(func=cmd_seed)

    s = sub.add_parser("status", help="human-readable state of every ticket")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_status)

    s = sub.add_parser("next", help="tasks that should exist right now (respects WIP)")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_next)

    s = sub.add_parser("advance", help="apply a state transition")
    s.add_argument("--ticket", required=True)
    s.add_argument("--event", required=True,
                   choices=["claim-code", "code-done", "review-ok", "review-findings",
                            "fix-done", "block", "reopen"])
    s.add_argument("--findings", type=int, help="blocking+major count; required for review-findings")
    s.add_argument("--note", default="")
    s.set_defaults(func=cmd_advance)

    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
