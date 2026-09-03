# Phase 1 — Research

Spec: `template/epic_workflow.md` §3. Announce: **"Entering Epic Research phase."**

**Mechanism: subagent fan-out.** Three lenses work independently, one consolidator merges.
This is a join, not a stream — do not use an agent team.

## Step 0 — Resolve the epic and its scope

```bash
python3 $WF_EPIC/tools/fetch_epic.py Epic#<id>
```

Read `Projects in scope` from the output. If the epic has no children yet, derive the scope from
its description; if that is ambiguous, **ask the human** — do not guess, it decides how many lens
agents run.

Create `.tmp/epic-<id>/` and write `_state.md` with `Projects:`.

There is **no worktree** at epic level. Lenses read the main checkouts and commit nothing.

## Step 1 — Fan out (all lenses in ONE message so they run concurrently)

| Lens | Agent | Writes | Runs |
|------|-------|--------|------|
| web | `wf-web-researcher` | `epic-<id>_research_web.md` | once |
| docs | `wf-planner` | `epic-<id>_research_docs_<project>.md` | once per project in scope |
| code | `wf-planner` | `epic-<id>_research_code_<project>.md` | once per project in scope |

Each prompt must carry: the epic title and description, the project's `REPO_ROOT`, and the
`<technical_note>` / `<setup_commands>` blocks from `projects/<project>_must_read.md`.

- **web** — how comparable products solve this; what is standard practice; what the trade-offs are.
- **docs** — what the project's own documentation says this should look like; existing constraints.
- **code** — read the source and write **pseudo code** for how the feature would actually look here;
  say plainly if part of it already exists.

**Silence rule — state it in every prompt:** *do not communicate with any other agent; write your
file and stop.* Independence is the entire reason for having three lenses.

## Step 2 — Consolidate

Spawn `wf-consolidator` with the lens file **paths** (not their contents). It writes
`epic-<id>_strategy.md`:

- what was investigated, what was found, the evidence
- a recommendation
- an explicit **Open questions** section

**Conflicts go to the human.** Where lenses disagree, the consolidator lists the disagreement, the
evidence on each side, and its recommendation — then **stops and asks**. Never average two answers
into a third that nobody proposed. This is the phase's one interactive point.

## No loop

Research produces findings, not a specification later work depends on; there is nothing for a loop
to converge. The design phase is where looping earns its cost.

## Gate

`epic-<id>_strategy.md` exists and is newer than every lens file.

Update `_state.md`. Next: `/wf-epic design Epic#<id>`.
