---
name: wf-epic
description: >
  Run one phase of the epic workflow for a group-level GitLab epic.
  Usage: /wf-epic <phase> Epic#<id>
  Phases: research, design, split, implementation, status
  Examples: /wf-epic research Epic#60 | /wf-epic implementation Epic#116 | /wf-epic status Epic#116
---

## Parse args

`<phase>` is the first token, `<ref>` the rest. With no args, print this and stop:

```
Usage: /wf-epic <phase> Epic#<id>

  research        Phase 1 — 3 lenses + consolidator          -> _strategy.md
  design          Phase 2 — draft/review/fix loop, <=3 rounds -> _design.md
  split           Phase 3 — reconcile existing + new tickets  (human confirms)
  implementation  Phase 4 — AGENT TEAM, streams every ticket  -> MRs
  status          Show the implementation queue

Epics are GROUP-level: Epic#60 -> ${GL_URL}/groups/${GL_NAMESPACE}/-/epics/60
For a single issue or MR use /wf instead.
```

## Prepare context (before any phase)

**Step 0 — paths.** `WORKSPACE_ROOT` is the parent of `claude_workflow/`.
`WF_EPIC` = `$WORKSPACE_ROOT/claude_workflow/wf_epic`.

**Step 1 — identifiers.** `<ref>` must match `Epic#<id>` (case-insensitive). If it looks like
`<project>#<id>` or `<project>#MR!<id>`, stop and point the user at `/wf` — this skill is for
epics only.

- `<epic-id>` = the number after `Epic#`
- `<epic-slug>` = `epic-<epic-id>`
- `<epic-dir>` = `$WORKSPACE_ROOT/claude_workflow/.tmp/<epic-slug>/`

**Step 2 — no worktree.** Phases 1–3 produce documents and tickets, never code: they read the main
checkouts and commit nothing. Worktrees are per **child ticket** and are created by phase 4's seed
script. Never `git checkout` or commit in a main checkout.

**Step 3 — state.** Read `<epic-dir>/<epic-slug>_state.md` if it exists.

**Step 4 — project scope.** An epic is group-level and may span projects. Resolve the scope with
`python3 $WF_EPIC/tools/fetch_epic.py <ref>` and record it in `_state.md` as `Projects:`. For each
project in scope, read `projects/<project>_must_read.md` — **this skill is its only reader** — and
forward `<technical_note>` and `<setup_commands>` into every agent prompt.

## Dispatch

| Phase | File |
|-------|------|
| `research` | `$WF_EPIC/phases/1_research.md` |
| `design` | `$WF_EPIC/phases/2_design.md` |
| `split` | `$WF_EPIC/phases/3_split.md` |
| `implementation` | `$WF_EPIC/phases/4_implementation.md` |
| `status` | run `graph.py --queue <epic-dir>/<epic-slug>_queue.md status` and report |

Read the file and follow it exactly. The authority for all of it is
`template/epic_workflow.md`; the phase files are its executable form.

## Guardrails

- **Phase gates are real.** Do not start a phase whose input artifact is missing — say what is
  missing and which phase produces it.
- **Never create GitLab tickets without explicit confirmation** (phase 3). Show every title, its
  project and the parent epic, and wait for a yes.
- **Never push without explicit confirmation.**
- **Commit messages: ≤5 lines, no Claude/Anthropic attribution. Code comments: ≤3 lines.**
- **Conflicts between agents go to the human**, never averaged into a third answer nobody proposed.

## After each phase

Update `<epic-dir>/<epic-slug>_state.md` with the phase, the artifacts written, and the next step.
