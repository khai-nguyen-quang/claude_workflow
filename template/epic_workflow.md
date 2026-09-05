# Epic workflow

Workflow for taking a GitLab **Epic** from a question to merged code. It sits **above** the
per-ticket workflow in `template/workflow.md`: phases 1–3 produce tickets, phase 4 implements them.

Where this document is silent, `template/workflow.md` applies — its **Global rules** (commit
messages ≤5 lines, no Claude/Anthropic attribution, code comments ≤3 lines) hold in every phase.

---

## 1. Overview

Four phases, plus device testing which is not yet defined.

| # | Phase | Mechanism | Loop | Input | Output |
|---|-------|-----------|------|-------|--------|
| 1 | Research | subagent fan-out | no | `Epic#<id>` | `_strategy.md` |
| 2 | Design | subagent fan-out | yes, ≤3 rounds | `_strategy.md` | `_design_overview.md` + `_design_detailed.md` |
| 3 | Split (reconcile + split) | solo + human confirm | no | the design pair + existing children | tickets on GitLab |
| 4 | Implementation | **agent team** | yes, ≤2 rounds per ticket | tickets | MRs |
| — | Test on device | TBD | | | |

**The rule that decides the mechanism.** Phases 1–3 are *joins*: N agents work independently, one
merges, done. That is subagent fan-out. Phase 4 is a *stream*: tickets flow continuously through
three stages and an agent that frees up pulls the next item, with no barrier. Only an agent team
can express a stream — this is the single reason phase 4 uses one.

Phase 4 is the merger of what were separately coding, review and fix_review. They are not
separable in a stream: at any instant all three are running, on different tickets.

```
session 1: research  ─▶ _strategy.md
session 2: design    ─▶ _design_{overview,detailed}.md   (internally loops)
session 3: split     ─▶ tickets on GitLab
session 4: ══ TEAM ══ coder ∥ reviewer ∥ fixer, streaming every ticket ══▶ MRs
```

One session per phase. Sessions do not share context; **files are the only handoff.**

---

## 2. Identifiers, paths and scope

### Epic ref

Epics are **group-level**, per `instructions/gitlab.md`:

```
Epic#60   →   ${GL_URL}/groups/${GL_NAMESPACE}/-/epics/60
```

- `<epic-id>` = the number after `Epic#`
- `<epic-slug>` = `epic-<epic-id>` (e.g. `epic-60`) — the `.tmp/` folder name and the filename stem

Ref parsing order (an epic ref must be matched **before** the issue pattern):

| Pattern | Kind | Slug |
|---------|------|------|
| `Epic#<id>` (case-insensitive) | epic | `epic-<id>` |
| `<project>#MR!<id>` | merge request | `<project>-mr-<id>` |
| `<project>#<id>` | issue | `<project>-<id>` |
| *(no `#`)* | project or free-form slug | `<ref>` |

### No worktree at epic level

Phases 1–3 produce documents and GitLab tickets, never code. They read the main checkouts and
commit nothing. This is a deliberate exception to the "every phase works inside the ticket's own
worktree" rule; worktrees start at the **child ticket** level and are created by phase 4.

### Project scope

An epic is group-level and may span `openpilot` and `tvi-linux` — this is observed, not assumed
(epic 116 has children in both). Phase 1 resolves the scope up front, from existing child items,
else the epic description, else by asking the human, and records it in `_state.md` as `Projects:`.
Research lenses that read a repository run **once per project in scope**.

### Artifacts

```
.tmp/epic-60/
  epic-60_state.md                          Projects:, phase, next step
  # phase 1
  epic-60_research_web.md
  epic-60_research_docs_<project>.md
  epic-60_research_code_<project>.md
  epic-60_strategy.md                       gate for phase 2
  # phase 2
  epic-60_design_overview_draft.md          overwritten each round
  epic-60_design_detailed_draft.md          overwritten each round
  epic-60_design_review_r<N>_{usecases,scale,corners}.md
  epic-60_design_review_r<N>.md             consolidated, carries verdict
  epic-60_design_decisions.md               ledger, appended every round
  epic-60_design_overview.md                gate for phase 3
  epic-60_design_detailed.md                gate for phase 3
  # phase 3
  epic-60_tickets.md                        dry run, gate for posting
  # phase 4
  epic-60_queue.md                          source of truth for the task graph
  epic-60_reviewer_notes.md                 cross-ticket judgment
```

Per-ticket artifacts stay where they are today, under `.tmp/<project>-<id>/`.

---

## 3. Phase 1 — Research

Answers "what should we build and why" from three independent angles.

```
        ┌─▶ web    (internet: how other products solve this)
Epic ───┼─▶ docs   (project documentation, per project in scope)
        └─▶ code   (project source; writes pseudo code, per project in scope)
                          │
                          ▼
                    consolidate ─▶ _strategy.md
```

**Agents.** `wf-web-researcher` (new) for web; `wf-planner` for docs and code;
`wf-consolidator` (new) for the merge. All three lenses spawned **in one message** so they run
concurrently.

**Silence rule.** No lens communicates with another until its own file is written. Independence is
the reason for having three.

**Consolidator.** Cross-checks the three reports and writes `_strategy.md`: what was investigated,
what was found, the evidence, the recommendation, and an explicit **Open questions** section.
Conflicts between lenses are **put to the human for a decision** — never averaged away, never
silently resolved. This is the phase's one interactive point.

**No loop.** Research produces findings, not a specification later work depends on; there is
nothing for a loop to converge.

**Gate.** `_strategy.md` exists and is newer than all lens files.

---

## 4. Phase 2 — Design

Turns the strategy into the design that phase 3 can split and phase 4 can implement.

**The design is two documents, not one.** `_design_overview.md` answers *how does this fit
together* — architecture, diagrams, the component map, the decisions — and is readable in one
sitting. `_design_detailed.md` answers *what exactly do I build* — one section per component, the
normative `## Interfaces`, build, tests, and the end-to-end walkthrough. `template/design_document.md`
is the normative structure for both. One document cannot serve both readers: the architecture
drowns in signatures and the components read as an isolated list, which is the exact failure this
split exists to fix.

```
                    ┌────────────────────────────────────────────┐
                    ▼                                            │
_strategy.md ─▶ author ─▶ draft ─▶ 3 reviewers ─▶ consolidate ───┤
                (warm,             (fresh each      │            │
                 persistent)        round, silent)  │  findings ─┘
                                                    │
                                                 DESIGN OK
                                                    ▼
                                              write_design ─▶ _design_{overview,detailed}.md
```

### The freshness asymmetry — the core of this phase

**The author remembers; the reviewers forget.**

- **Author** is *one warm agent across all rounds* (`wf-planner`). It knows why each choice was
  made, so it does not undo a deliberate decision while fixing an unrelated finding. Round 1 it
  drafts both documents from `_strategy.md`; round N it revises them from the findings. Draft and
  fix are the same role, seeded differently — not two agents.
- **Reviewers** are *fresh instances every round* (`wf-reviewer` ×3). A warm reviewer checks only
  "did they fix my list"; a cold one re-reads the whole design and catches what the fix broke.
  **Regressions introduced by a fix are the main reason a second round exists**, and only a cold
  reviewer sees them. There are no mechanical gates on a document — the cold reviewer *is* the
  regression detector. (Phase 4 goes the other way, for a stated reason; see §6.)

### Lenses

| Lens | Reviews |
|------|---------|
| usecases | does it cover all necessary user cases; is `## Interfaces` complete enough to code against; does the end-to-end walkthrough trace through the component sections |
| scale | is it easy to scale up in future |
| corners | which corner cases are missing; are error conditions, edge cases and failure modes precise per component |

Reviewers read **both documents as one design**, and all three check the isolation failure: a
component section that never names its upstream and downstream components, or an assumption that
no named component delivers.

Every finding is classified **blocking / major / minor**, so the exit condition is mechanical.

### The decisions ledger — what actually terminates the loop

Fresh reviewers re-raise findings that were consciously rejected, and the loop never converges.
`_design_decisions.md` carries every finding with **accepted / rejected and the reason**, and is
fed into each round's reviewer prompt as *"these were considered; do not re-raise without new
evidence."* The round cap is only a backstop; the ledger is the mechanism.

### Exit conditions, checked in order

1. **Converged** — consolidator emits `DESIGN OK`, defined as *no findings above minor*. Not zero
   findings: LLM reviewers always produce something and zero never arrives.
2. **Diverging** — round N has as many blocking findings as round N−1. Stop; hand to a human.
3. **Capped** — 3 rounds. Hand to a human with the outstanding findings.

Keep per-round review files: `12 → 3 → 0` is the convergence signal and tells you whether the cap
is right.

### write_design

**Assembly only** — each draft becomes its final document one to one: house style, Mermaid per
`template/diagram.md`, and the normative `## Interfaces` section in the detailed document. It makes
**no design decisions**, because nothing reviews it. If it needs to make a call, that call belongs
in a round — including any call about *which document a section belongs in*, which is why the
author drafts the split from round 1 rather than assembling it here.

### `## Interfaces` is mandatory

`_design_detailed.md` must declare signatures, message types, file paths and error cases precisely
enough to act as a contract between agents who cannot see each other's work. Phase 4's test agents
write against it. Without it, phase 4 silently degrades into a sequential pipeline.

**Gate.** `_design_overview.md` and `_design_detailed.md` both exist, the detailed one contains
`## Interfaces`, and the last round's consolidated review says `DESIGN OK`.

---

## 5. Phase 3 — Split (reconcile + split)

Turns the design into a ticket set. **Outward-facing and irreversible** — the phase proposes, the
human approves, and only then does anything reach GitLab.

Two cases, and the second is the normal one:

- **Greenfield epic** (no children) — derive tickets from the design and create them.
- **In-progress epic** (children exist) — **reconcile** the existing set against the design first.
  Epic#91 has 10 children before this phase ever runs.

### Reconcile

1. **Inventory** — `fetch_epic.py Epic#<id> --detail` gives every child's state, **kind**, note count,
   linked MR count, weight, assignee and last update.
2. **Coverage matrix** — map every unit of work in the design (each component, each `## Interfaces`
   entry) onto the existing tickets. Read descriptions, not titles.
3. **Classify** — exactly one action per ticket: `keep`, `update`, `merge`, `defer`, `exclude`
   (non-impl kind), and `create` for each gap.

**Kind gates the queue.** A `design::` / `research::` / `spike::` / `doc::` ticket is not
implementation work. It stays on the epic but never enters the implementation queue — a coder
handed a design ticket will try to implement a design. The marker is detected at the start of the
**title or the description**; humans write it in either.

### Rules that must not be broken

- **Never delete a GitLab issue.** Deletion is not an available action. Irrelevant work is unlinked
  from the epic or closed with a comment — recoverable, and it preserves the discussion.
- **The survivor of a duplicate is the ticket with history** — notes, linked MRs, assignee. Fold the
  other's content into it. Never close a ticket someone has worked on in favour of a freshly
  written one.
- **Never silently rescope a human's ticket.** A design that implies something different from what
  the author wrote is a conflict, not a correction: state both readings and ask.
- **A closed ticket stays closed.** If its work is needed, create a new one linking to it.

### Output

`_tickets.md` carries existing and new tickets together with an action each, a reconcile summary,
and a final **`## Queue`** line — the machine-readable list, in order, that feeds
`seed_epic.py --tickets`.

### Test-ticket rule

Separate unit-test / integration-test tickets break the one-worktree-one-branch invariant: their
tests land on a different branch than the code they cover, so the implementation MR merges untested
and the test MR cannot build until the impl lands. Therefore:

- **Per-feature unit and integration tests ride inside the implementation ticket**, shipping in the
  same MR. Every MR stays self-contained.
- **Separate test tickets only for cross-cutting work** belonging to no single implementation
  ticket: regression suite, test harness, CI wiring, shared fixtures.

### Linking to the epic

Creating the link needs the issue's **global `id`, not its `iid`** (`openpilot#508` is iid 508 but
global id 204759). Create the issue first, then link with the id from the create response, then read
`epic_iid` back to prove the link landed.

**Gate.** `_tickets.md` exists and ends in a `## Queue` line; every `create` has a real iid and a
verified `epic_iid`; no ticket carries an unresolved conflict.

## 6. Phase 4 — Implementation

One **agent team**, one session, streaming every ticket of the epic through three stages.

```
coder ──▶ reviewer ──▶ fixer ──▶ reviewer ──▶ … ──▶ done
  │                                                  or blocked
  └─ meanwhile already on the next ticket
```

The point is that **the bottleneck never idles**: while T1 is being reviewed and fixed, the coder
is already on T2. Throughput is `1/max(stage)`, so a saturated coder is the whole game — which is
also why the fixer is a **separate agent**. If the coder did its own fixes, its per-ticket work
would be `code + fix` and the overlap would buy nothing.

### Team

| Teammate | Claims | Notes |
|----------|--------|-------|
| `coder` | `code:*` | one ticket end-to-end: implementation + unit + integration tests. Scales to k coders with no structural change — it is the bottleneck |
| `reviewer` | `review:*` | **one persistent agent across all tickets** |
| `fixer` | `fix:*` | applies findings; **escalates design-level findings** as a task in the coder's lane rather than guessing |
| lead | — | seeds the graph, watches, integrates. Stays out of the critical path |

Each teammate claims **only its own prefix**. Put the rule in the spawn prompt and verify it in
`TeammateIdle`.

### The persistent reviewer is the reason this is a team

Today every ticket is reviewed by an amnesiac — nothing can notice that T3 reimplements a helper
T1 added. A reviewer that sees every ticket can. Its judgment must outlive its own compaction, so
it appends to `_reviewer_notes.md` after every ticket and re-reads it before the next: conventions
accepted, patterns rejected, cross-ticket concerns. **That file is the evidence for whether the
team was worth its cost.**

### The freshness rule inverts here

The reviewer stays **warm** on re-review, unlike phase 2. The reason is concrete: `TaskCompleted`
runs build, test, lint and sanitizer on every round, so *those* are the regression detector. The
reviewer is judging design fidelity and maintainability on a small targeted diff, which is exactly
what a warm agent does well. A document has no such gates; code does.

### Per-ticket loop

```
code:T1 ─▶ review:T1.r1 ─▶ fix:T1.r1 ─▶ review:T1.r2 ─▶ … ─▶ done:T1
                │                                             or blocked:T1
                └── verdict PRODUCTION READY ────────────────▶ done:T1
```

Rounds are created **dynamically**: a consolidated review carrying findings creates the next
`fix:` task; a fixer finishing creates the next `review:` task. Neither the lead nor any driver is
in the loop.

**The fixer replies to every finding** in the review file — accepted and fixed, or rejected with a
reason — and the next round reads the replies. Same convention as the existing MR-thread behaviour
in `fix_review`; these replies become the MR threads later. This is phase 2's ledger, per ticket.

**Exit conditions, checked in order:**

1. **Converged** — verdict is `PRODUCTION READY`.
2. **Diverging** — round N has as many blocking findings as round N−1.
3. **Capped** — **2 rounds**, lower than design's 3. A ticket needing a third round usually has a
   design problem, not a code problem, and should be raised as a finding against the design
   rather than ground down by review.

### Backpressure, and the deadlock it can cause

Without a limit the coder runs five tickets ahead, and every review finding lands on a ticket
nobody remembers. Limit work in progress with a dependency: **`code:T(n+2)` depends on `T(n)`
reaching a terminal state** (WIP = 2).

**The dependency must be on a terminal state, not on review succeeding.** With the loop above, a
ticket that never converges would otherwise stall the coder forever and freeze the whole epic:

```
done:T1     ← verdict PRODUCTION READY   ┐ both release the WIP dependency
blocked:T1  ← cap hit, or diverging      ┘
```

A blocked ticket keeps its worktree, gets a human, and the pipeline keeps moving. The loop and the
backpressure are individually sensible and jointly fatal without this.

### Hooks are the engine — there is no driver

| Hook | Role | Behaviour |
|------|------|-----------|
| `TaskCompleted` | **the gate** | dispatch on task prefix. `code:` → build + test + lint + sanitizer in that ticket's worktree. `review:` → report file exists and carries a verdict. `fix:` → build still green and every finding has a reply. **Exit 2 with the real failure output**, which the agent receives as feedback |
| `TeammateIdle` | **the loop** | claimable work in your lane → **exit 2**, "claim the next task". Otherwise allow idle. This is what makes it run unattended instead of halting quietly |

Gates are the same commands as today, moved out of a bash driver into a hook.

**Sanitizer** is the one new gate: `./dev.sh test --asan` and `./dev.sh test --tsan`. Anchor the
whole gate set to `.gitlab-ci.yml`'s validate stage (tidy, unit, ASan, TSan, itest, py-lint) so a
green gate means a green pipeline.

**A shared build cache can make cached results look like a run** — every gate must check the test
summary output, not the exit code.

### The queue file, and restart

Team names are session-derived (`session-` + first 8 chars of the session id). Resume the session
and the task list survives; start a **fresh** session and you get a new team name and an **empty
task list** — the whole graph is gone.

So `_queue.md` is the **source of truth**; the runtime task list is a projection of it. The
`TaskCompleted` hook fires on every transition and is the natural place to update it.

**Restart procedure** (teammates are never restored, even on `/resume`):

1. Re-seed the task list from `_queue.md`.
2. Re-spawn the three teammates with identical prompts.
3. They read the queue, the state file and `_reviewer_notes.md`, and continue.

Test this deliberately — kill the session mid-run and restart. If it does not work cold, this is
not an automated pipeline but a session you cannot afford to lose.

### Startup

Worktrees are created **up front, serialized, before any teammate starts**: `worktree.sh ensure`
races on the main checkout's `index.lock`, and a new worktree takes ~2 minutes. For 7 tickets that
is a ~15-minute setup that should happen once, not lazily mid-stream.

### Stall detection

A task marked in-progress and untouched for N minutes blocks every dependent silently. In a
fan-out that is one slow report; in a stream it is a dead pipeline. Check for it, and surface it.

**Gate.** The queue is drained: every ticket is `done` or `blocked`, and every `done` ticket has an
MR. `blocked` tickets are reported to the human with their outstanding findings.

---

## 7. Agents

Two new definitions. The lens is a **prompt**; the agent definition is a **tool/model profile**.
Five near-identical reviewer files would be five files to keep in sync.

| Agent | Status | Used by |
|-------|--------|---------|
| `wf-web-researcher` | **new** — the only agent needing `WebSearch`/`WebFetch` | phase 1 web lens |
| `wf-consolidator` | **new** — `Read, Write, Glob` only; deliberately no `Bash` or source `Grep`, so it merges and flags conflicts rather than re-investigating and adding one more opinion | phases 1, 2 |
| `wf-planner` | reuse | phase 1 docs/code lenses; phase 2 author |
| `wf-reviewer` | reuse | phase 2 lenses ×3; phase 4 reviewer |
| `wf-coder` | reuse | phase 4 coder and fixer |

**Cost.** Reviewers do bounded reading against a fixed artifact; the judgment is in the merge and
the revision. Sonnet for lenses, Opus for consolidator, author and the persistent reviewer. Phase
2 is 3 reviewers × up to 3 rounds — the loop multiplies this.

---

## 8. Tools and configuration

### To build

| Path | Purpose |
|------|---------|
| `tools/gitlab/fetch_epic.py` | `GET /api/v4/groups/<url-encoded GL_NAMESPACE>/epics/<iid>` and `…/epics/<iid>/issues` |
| `tools/gitlab/create_issue.py` | target project + `--epic <id>`, `--dry-run`; links using the issue's **global id** |
| `tools/github/fetch_epic.py` | `GET /repos/<owner>/<repo>/issues/<n>` and `…/issues/<n>/sub_issues` |
| `tools/github/create_issue.py` | target `owner/repo` + `--parent <n>`, `--dry-run`; links using the issue's **global id**, not its number |

Both directories carry the same filenames; `tools/forge/resolve.sh` picks between them, so the
phase steps below are written once and run on either forge.
| `.claude/hooks/task_completed.sh` | the gate (§6) |
| `.claude/hooks/teammate_idle.sh` | the loop (§6) |
| phase 4 seed script | epic → tickets → worktrees → `_queue.md` → task graph with WIP edges |

Add `WebSearch,WebFetch` wherever the tool allowlist is set, or phase 1's web lens silently
returns nothing.

### Settings

```json
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "teammateMode": "tmux",
  "subagentPromptCacheTtl": "1h"
}
```

`subagentPromptCacheTtl` matters more than it looks: in-process teammates default to a 5-minute
cache, and a reviewer idling between tickets would otherwise re-pay the whole CLAUDE.md chain on
every wake. `Bash(*)`, `Edit(*)` and `Write(*)` are already allowed in `.claude/settings.json`, so
the lead does not become a permission-prompt funnel.

### Verified against the instance (2026-09-03, `gitlab.cartrack.com`)

| Check | Result |
|-------|--------|
| Instance | GitLab **19.3.1-ee**, `enterprise: true` — epics licensed |
| Group | `.../vision-camera` = id **1528**, **114 epics** |
| `GET /groups/:id/epics` | 200, no deprecation or sunset headers |
| `GET /groups/:id/epics/:iid/issues` | 200 |
| Token | **maintainer** (40) on `openpilot` |

Epics carry a `work_item_id` alongside `iid` — the work-items migration is underway underneath,
but REST is unaffected today. Pin to REST; revisit if an upgrade starts emitting deprecation
headers.

---

## 9. Build order

Each step is independently useful; the risky ones last.

1. **Phase 3 split, dry run only.** Run against an already-approved design and judge the ticket
   breakdown. No GitLab writes. **Epic 116 is the test case** — it already has 7 human-made child
   tickets across both projects (`tvi-linux#56,57,58,59,60,61`, `openpilot#508`), so a dry-run
   split can be diffed against a split a human actually made. Cheapest possible quality signal.
2. **`create_issue.py` + confirmation.** The seam goes live.
3. **Phase 4 engine** — the two hooks and the seed script, on the 3 `tvi-linux` tickets under epic
   116. Shake out gates and **restart** before pointing it at a real epic.
4. **Phase 2 design loop** — including the ledger and the `## Interfaces` gate.
5. **Phase 1 research fan-out** — adds `wf-web-researcher` and the tool-allowlist fix.
6. **Device testing.** `openpilot_must_read.md` documents
   `python3 tools/scripts/verify_rk3588.py --mvp` as the full-stack smoke test — the likely
   starting point.
