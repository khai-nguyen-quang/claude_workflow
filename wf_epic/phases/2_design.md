# Phase 2 — Design

Spec: `template/epic_workflow.md` §4. Announce: **"Entering Epic Design phase."**

**Mechanism: subagent fan-out, in a loop of at most 3 rounds.**

```
                    ┌──────────────────────────────────────────┐
                    ▼                                          │
_strategy.md ─▶ author ─▶ draft ─▶ 3 reviewers ─▶ consolidate ─┤ findings
                (WARM)             (FRESH)          │          │
                                                DESIGN OK      │
                                                    ▼          │
                                              write_design ────┘
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
`_design_review_r<N-1>.md`. Writes `epic-<id>_design_draft.md` (overwritten each round).

**b. Three reviewers, in one message, silent until their file is written.**

| Lens | Reviews | Writes |
|------|---------|--------|
| usecases | all necessary user cases covered; **is `## Interfaces` complete enough to code against** | `_design_review_r<N>_usecases.md` |
| scale | is it easy to scale up in future | `_design_review_r<N>_scale.md` |
| corners | which corner cases are missing | `_design_review_r<N>_corners.md` |

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

Author turns the converged draft into `epic-<id>_design.md`: house style,
Mermaid per `template/diagram.md`, and the normative `## Interfaces` section.

**Assembly only — no design decisions.** Nothing reviews this step, so anything requiring judgement
belongs in a round instead.

## `## Interfaces` is mandatory

Signatures, message types, file paths, error cases — precise enough to be a contract between agents
who cannot see each other's work. **Phase 4's coder and its tests are written against this
section in parallel.** Without it phase 4 silently degrades into a sequential pipeline.

## Gate

`epic-<id>_design.md` exists, contains `## Interfaces`, and the last consolidated review says
`DESIGN OK`.

Update `_state.md`. Next: `/wf-epic split Epic#<id>`.
