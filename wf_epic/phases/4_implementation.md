# Phase 4 — Implementation

Spec: `template/epic_workflow.md` §6. Announce: **"Entering Epic Implementation phase."**

**Mechanism: an agent team.** This is the one phase that is a *stream* rather than a join — tickets
flow continuously and an agent that frees up pulls the next one. Subagents cannot express that.

It is the merger of what used to be coding, review and fix_review: at any instant all three are
running, on different tickets.

## Why the fixer is a separate agent

Throughput is `1/max(stage)`, so the only thing that matters is that **the coder never idles**.
While T1 is reviewed and fixed, the coder is already on T2. If the coder did its own fixes its
per-ticket work would be `code + fix` and the overlap would buy nothing.

## Step 0 — Preconditions

Agent teams must be enabled and the session **interactive** (`claude -p` silently downgrades
teammates to ordinary subagents). See `wf_epic/settings.snippet.json`.

## Step 1 — Seed (once, before any teammate starts)

```bash
python3 $WF_EPIC/tools/seed_epic.py Epic#<id>
```

Creates every worktree **serialized** (`worktree.sh ensure` races on the main checkout's
`index.lock`; a new worktree takes ~2 minutes, so 7 tickets is a ~15-minute setup), then writes
`epic-<id>_queue.md`. Export what it prints:

```bash
export WF_EPIC_QUEUE=.../epic-<id>_queue.md
export WF_EPIC_ROOT=/home/khainguyen/workspace
```

## Step 2 — Spawn the team

Three teammates from subagent definitions. **Name them exactly** `coder`, `reviewer`, `fixer` —
`hooks/_payload.py` maps those names to lanes.

| Teammate | Definition | Claims | Brief |
|----------|-----------|--------|-------|
| `coder` | `wf-coder` | `code:*` only | one ticket end-to-end: implementation **plus** its unit and integration tests, written against the design's `## Interfaces` |
| `reviewer` | `wf-reviewer` | `review:*` only | **persistent across every ticket**; maintains `epic-<id>_reviewer_notes.md` |
| `fixer` | `wf-coder` | `fix:*` only | applies findings; **escalates design-level findings** as a task in the coder's lane rather than guessing |

Scale by adding coders — it is the bottleneck, and nothing else in the graph changes.

Every spawn prompt carries: `REPO_ROOT` for its ticket, the design document, the `## Interfaces`
section, and `<technical_note>` / `<setup_commands>` for the project.

### The persistent reviewer is why this is a team

Today every ticket is reviewed by an amnesiac — nothing can notice that T3 reimplements a helper T1
added. Instruct the reviewer to **append to `epic-<id>_reviewer_notes.md` after every ticket and
re-read it before the next**: conventions accepted, patterns rejected, cross-ticket concerns. Its
judgement must outlive its own compaction. That file is the evidence for whether the team was worth
its cost.

### Freshness inverts here

Unlike phase 2, the reviewer stays **warm** on re-review. The reason is concrete: `TaskCompleted`
runs build, test, lint and sanitizer on every round, so *those* are the regression detector. The
reviewer judges design fidelity and maintainability on a small targeted diff — exactly what a warm
agent does well. A document has no such gates; code does.

## Step 3 — Create the initial tasks

```bash
python3 $WF_EPIC/engine/graph.py --queue "$WF_EPIC_QUEUE" next
```

Create one task per line, titled **exactly** as the first column (`code:tvi-linux-56`). The hooks
find our tasks by that shape. Do not retitle them.

## The report contract — the hooks parse these files

Reviewer writes `.tmp/<ticket>/<ticket>_review_r<N>.md`:

```markdown
- [blocking] <finding>
- [major] <finding>
- [minor] <finding>
VERDICT: PRODUCTION READY | NEEDS WORK
```

Fixer replies **under every blocking/major finding** in the same file:

```markdown
  - reply: fixed — <what changed>
  - reply: rejected — <why>
```

This is phase 2's ledger, per ticket, and it is the same convention as the MR-thread replies in
`fix_review` — these replies become the MR threads later. The `fix:` gate counts replies against
findings and rejects the completion if any are missing.

## The loop, and how it ends

```
code:T ─▶ review:T.r1 ─┬─ PRODUCTION READY ──────────▶ done:T
                       └─ findings ─▶ fix:T.r1 ─▶ review:T.r2 ─┬─▶ done:T
                                                               └─▶ blocked:T
```

Rounds are created **dynamically** — no driver is in the loop. The graph decides:

1. **Converged** — `PRODUCTION READY`.
2. **Diverging** — round N has as many blocking+major findings as round N−1.
3. **Capped** — 2 rounds. A ticket needing a third usually has a *design* problem; raise it as a
   finding against `_design.md` rather than grinding it down in review.

`done` and `blocked` are both terminal and **both release WIP backpressure**. That is the point of
`blocked`: the WIP edge (`code:T(n+2)` waits on `T(n)`) combined with an unbounded loop would
otherwise stall the coder forever and freeze the whole epic.

## The engine

`engine/graph.py` owns `_queue.md` — the **source of truth**. The Claude Code task list is a
projection: team names are session-derived, so a fresh session starts with an empty task list.

The hooks do the rest and there is no bash driver:

| Hook | Role |
|------|------|
| `TaskCompleted` | **the gate** — build/test/lint/asan/tsan per lane, verdict present, findings replied. **Exit 2** with the real output, which the agent gets as feedback. Then advances the graph |
| `TeammateIdle` | **the loop** — claimable work in your lane → **exit 2**, "claim the next task". Idling is allowed when the lane is genuinely empty |

## Monitoring

```bash
python3 $WF_EPIC/engine/graph.py --queue "$WF_EPIC_QUEUE" status
```

Watch for a task **in progress and untouched for a long time**. In a fan-out that is one slow
report; in a stream it blocks every dependent silently and the pipeline is dead. Nudge the teammate
or `advance --event block`.

## Restart — test this deliberately

Teammates are never restored, not even by `/resume`. The task list survives a resume but **not** a
fresh session. Recovery:

1. `graph.py next` — the tasks that should exist.
2. Re-create them and re-spawn the three teammates with identical prompts.
3. They read the queue, `_state.md` and `_reviewer_notes.md`, and continue.

Kill the session mid-run once and restart it. If that does not work cold, this is not an automated
pipeline but a session you cannot afford to lose.

## Gate

Queue drained: every ticket `done` or `blocked`, every `done` ticket has an MR. Report blocked
tickets to the human with their outstanding findings.
