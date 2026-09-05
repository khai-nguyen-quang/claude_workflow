# Phase 2 — Design

Spec: `template/epic_workflow.md` §4. Announce: **"Entering Epic Design phase."**

**Mechanism: subagent fan-out, in a loop of at most 3 rounds.**

```
                ┌─────────────────────────────────────────────────┐
                ▼                                                 │
_strategy.md ─▶ author ─▶ 2 drafts ─▶ 3 reviewers ─▶ consolidate ─┤ findings
                                                     DESIGN OK    │
                                                         ▼        │
                                                   write_design ──┘
```

## The freshness asymmetry — get this right or the loop is pointless

**The author remembers; the reviewers forget.**

- **Author — ONE warm agent for the whole phase.** Spawn `wf-planner` once with the name
  `design-author`, then continue it each round with `SendMessage` so its context stays intact. It
  knows why each choice was made and will not undo a deliberate decision while fixing an unrelated
  finding. *Draft and fix are the same role, seeded differently — do not spawn a second agent for
  fixes.*
- **Reviewers — FRESH instances every round.** Spawn three new `wf-reviewer` agents per round; never
  reuse or `SendMessage` a previous round's reviewer. A warm reviewer only checks "did they fix my
  list"; a cold one re-reads the whole design and catches **what the fix just broke**. A document
  has no build or test to catch a regression — the cold reviewer *is* the regression detector.
  (Phase 4 inverts this, for a reason stated there.)

## Round N

**a. Author.** Round 1: draft from `_strategy.md`. Round N>1: revise from
`_design_review_r<N-1>.md`. Writes **two** files, both overwritten each round:

| Draft | Contents |
|-------|----------|
| `epic-<id>_design_overview_draft.md` | purpose and scope, architecture at a glance, diagrams, primary flow, component map, key decisions, assumptions |
| `epic-<id>_design_detailed_draft.md` | one section per component, `## Interfaces`, build integration, test strategy, end-to-end walkthrough |

The structure of both is **normative** and lives in
`$WORKSPACE_ROOT/claude_workflow/template/design_document.md` — put it in the author's prompt every
round. A design that reads as a flat list of isolated components is exactly what that template
exists to prevent.

**The split is drafted, not assembled later.** Deciding what belongs in the overview versus the
detail is a judgement call, and judgement calls happen in a round where reviewers see them —
never in `write_design`, which nothing reviews.

**b. Three reviewers, in one message, silent until their file is written.**

Every reviewer reads **both drafts** and judges them as one design.

| Lens | Reviews | Writes |
|------|---------|--------|
| usecases | all necessary user cases covered; **is `## Interfaces` complete enough to code against**; does the end-to-end walkthrough actually trace through the component sections | `_design_review_r<N>_usecases.md` |
| scale | is it easy to scale up in future | `_design_review_r<N>_scale.md` |
| corners | which corner cases are missing; are error conditions, edge cases and failure modes precise per component | `_design_review_r<N>_corners.md` |

One finding class belongs to no single lens, so **every** reviewer checks it: a component section
that never names its upstream and downstream components, or an assumption no named component
delivers. That is the isolation failure the two-file structure exists to catch.

Every prompt must include `_design_decisions.md` (if it exists) as:
*"These findings were already considered — do not re-raise without new evidence."*

Every finding must be classified so the exit condition is mechanical:

```
- [blocking] <finding>
- [major] <finding>
- [minor] <finding>
```

**c. Consolidate.** `wf-consolidator` reads the three files, removes duplicates, resolves
contradictions between reviewers, and writes `_design_review_r<N>.md` ending in:

```
VERDICT: DESIGN OK          (no findings above minor)
VERDICT: NEEDS WORK         (with the blocking/major list)
```

**d. Append the ledger.** Every finding goes into `epic-<id>_design_decisions.md` as
**accepted** (will be fixed) or **rejected** (with the reason). *This file is what terminates the
loop* — without it, next round's fresh reviewers re-raise the same rejected points forever. The
round cap is only a backstop.

## Exit conditions — check in this order

1. **Converged** — `DESIGN OK`. Defined as *no findings above minor*, not zero findings: LLM
   reviewers always produce something and zero never arrives.
2. **Diverging** — round N has **as many or more** blocking+major findings as round N−1. Stop and
   hand to the human; another round will not help.
3. **Capped** — 3 rounds. Stop and hand to the human with the outstanding findings.

Report the convergence trend (`12 → 3 → 0`) to the user at the end.

## write_design

Author turns the two converged drafts into the two final documents, one to one:

- `epic-<id>_design_overview_draft.md` → `epic-<id>_design_overview.md`
- `epic-<id>_design_detailed_draft.md` → `epic-<id>_design_detailed.md`

House style, Mermaid per `template/diagram.md`, and the normative `## Interfaces` section in the
detailed document.

**Assembly only — no design decisions.** Nothing reviews this step, so anything requiring judgement
belongs in a round instead. Moving material between the two documents is a judgement call: if the
split is wrong, that is a finding for the next round, not a fix here.

## `## Interfaces` is mandatory

Lives in `epic-<id>_design_detailed.md`. Signatures, message types, file paths, error cases —
precise enough to be a contract between agents who cannot see each other's work. **Phase 4's coder
and its tests are written against this section in parallel.** Without it phase 4 silently degrades
into a sequential pipeline.

## Gate

`epic-<id>_design_overview.md` and `epic-<id>_design_detailed.md` both exist, the detailed
document contains `## Interfaces`, and the last consolidated review says `DESIGN OK`.

Update `_state.md`. Next: `/wf-epic split Epic#<id>`.
