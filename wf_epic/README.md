# wf_epic — multi-agent graph engine for epics

Executable form of `template/epic_workflow.md`. Takes a group-level GitLab epic from a question to
merged code in four phases.

```
/wf-epic research       Epic#60    3 lenses + consolidator        -> _strategy.md
/wf-epic design         Epic#60    draft/review/fix loop, <=3     -> _design.md
/wf-epic split          Epic#60    reconcile existing + new (you confirm)
/wf-epic implementation Epic#60    AGENT TEAM, streams tickets    -> MRs
/wf-epic status         Epic#60    the queue
```

**Phases 1–3 are joins** — N agents work independently, one merges. Subagent fan-out.
**Phase 4 is a stream** — tickets flow continuously, an agent that frees up pulls the next.
Only an agent team can express a stream; that is the sole reason phase 4 uses one.

## Layout

```
wf_epic/
├── SKILL.md                  /wf-epic dispatcher       (symlinked into .claude/skills/)
├── phases/1_research.md … 4_implementation.md          what Claude follows
├── agents/wf-web-researcher.md, wf-consolidator.md     (symlinked into .claude/agents/)
├── engine/graph.py           the task graph + queue file (source of truth)
├── engine/gates.sh           gate commands, anchored to .gitlab-ci.yml's validate stage
├── hooks/task_completed.sh   THE GATE   — exit 2 rejects and feeds back
├── hooks/teammate_idle.sh    THE LOOP   — exit 2 keeps a teammate working
├── hooks/_payload.py         payload extraction by shape, not by key name
├── tools/fetch_epic.py       group-level epic + children
├── tools/create_issue.py     create + link to epic (global id, verified)
├── tools/seed_epic.py        epic -> worktrees -> queue
└── settings.snippet.json     merge into .claude/settings.json
```

## The engine

The graph is **not stored as edges**. It is derived from an ordered ticket list plus each ticket's
state, so the on-disk format stays small enough for you to read and edit:

```
pending -> coding -> review(r1) -+-> done
                                 +-> fixing(r1) -> review(r2) -+-> done
                                                               +-> blocked
```

`_queue.md` is the **source of truth**; the Claude Code task list is a projection of it. Team names
are session-derived, so a fresh session starts with an empty task list — without the queue file the
graph would be lost on every restart.

**`done` and `blocked` are both terminal and both release WIP backpressure.** That is the entire
purpose of `blocked`: the WIP edge (`code:T(n+2)` waits on `T(n)`) combined with an unbounded review
loop would otherwise stall the coder forever and freeze the epic behind one bad ticket.

```bash
G="python3 wf_epic/engine/graph.py --queue .tmp/epic-116/epic-116_queue.md"
$G status                                    # every ticket, blocked ones called out
$G next                                      # tasks that should exist now (respects WIP)
$G advance --ticket tvi-linux-56 --event review-findings --findings 3
```

## Setup

1. Merge `settings.snippet.json` into `.claude/settings.json` (absolute paths in hook commands).
2. Agents and the skill are already symlinked into `.claude/`.
3. Phase 4 needs an **interactive** session — `claude -p` silently downgrades teammates to ordinary
   subagents and you get no team at all.

## Verified

Run against `gitlab.cartrack.com` on 2026-09-03:

- **`fetch_epic.py`** — works on the live instance. GitLab 19.3.1-ee, epics licensed, no deprecation
  headers. `Epic#116` resolves to 7 children spanning **both** `openpilot` and `tvi-linux`, which is
  what the cross-project scope rule is built on.
- **`graph.py`** — full scenario: WIP holds at 2, a terminal ticket releases position 3, divergence
  (`r1=5, r2=5`) blocks with a reason, illegal transitions are refused.
- **`task_completed.sh`** — a missing review file exits 2 with feedback; a `NEEDS WORK` report with
  3 findings advances to `fixing r1` counting 2 (blocking+major, minor excluded).
- **`teammate_idle.sh`** — pushes the fixer back when its lane has work, allows the reviewer to idle
  when it does not.
- **`create_issue.py`** — dry run only. **No issue has been created.**

## Not verified — read before trusting it

- **Hook payload schema.** Hook JSON differs between Claude Code versions. `_payload.py` therefore
  finds our task id and teammate name **by shape** (`^(code|review|fix):`, and the names
  `coder`/`reviewer`/`fixer`) rather than by guessing key paths — a wrong key path fails silently,
  and for `TaskCompleted` that means a gate that never runs. Confirm what your version sends:

  ```bash
  WF_EPIC_DEBUG=1 WF_EPIC_TMP=/tmp  # then inspect /tmp/hook_payload.json after a task completes
  ```

- **The gates have never run a real build.** `gates.sh` calls `./dev.sh build|test|lint|--asan|--tsan`
  from `openpilot_must_read.md`, but no worktree has been built through this engine. A repo with no
  `./dev.sh` is reported **SKIPPED, never passed**.
- **No team has been run end to end.** The topology, prompts and hook contract are written; the
  three teammates have not yet worked a real ticket.
- **Restart is untested.** Kill a session mid-run and restart it deliberately before trusting the
  pipeline unattended. If it does not recover cold, this is a session you cannot afford to lose
  rather than an automated pipeline.
- **Model IDs.** The two new agents pin `claude-opus-5` / `claude-sonnet-5`; the existing `wf-*`
  agents still pin 4.x ids. Align them if you want one convention.

## First run

Order matters — the cheapest real signal first.

1. **Dry-run the split against epic 116.** It already has 7 human-made tickets across both projects,
   so you can diff the model's breakdown against one a human actually made, at no risk.
2. **`create_issue.py` for real**, on one throwaway ticket, and check `epic_iid` reads back.
3. **Phase 4 on the three `tvi-linux` tickets** — shake out the gates and the restart path before
   pointing it at a full epic.
