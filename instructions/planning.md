# Planning instructions

## Goal

Produce the design documents for a GitLab issue **or a free-form feature request**, building on the approved brainstorm spec. The design is a **pair** of documents — `_design_overview.md` (how the system fits together) and `_design_detailed.md` (what exactly to build) — whose structure is defined by `$WORKSPACE_ROOT/claude_workflow/template/design_document.md`. The brainstorm spec (high-level approach) and both design documents are the inputs the Coding phase accepts; all must be approved by the user before work proceeds.

This single workflow serves both input variants; every step is identical except the sub-steps marked **(GitLab issue only)**. The variant is fixed by the phase as `<plan_source>` = `gitlab-issue` (`<ref>` has `#`) or `user-prompt` (free-form).

## Inputs (from task context)

- `<plan_slug>` — canonical identifier for this planning run (derived by the phase): `<project>-<id>` for a GitLab issue, or the free-form slug otherwise. All artifacts live under `.tmp/<plan_slug>/`.
- `<plan_source>` — `gitlab-issue` or `user-prompt`.
- `<project>` — GitLab project name (e.g. `projectX`); may be `(unknown)` for a free-form slug.
- `<id>` — GitLab issue number (e.g. `309`); empty for a free-form request.
- `<feature_description>` — for a free-form request, the feature text from the user's prompt (the issue fetch is skipped); absent for a GitLab issue.
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `REPO_ROOT` — absolute path to the checkout to work in: the ticket's own worktree
  (`$WORKSPACE_ROOT/<project>-worktree/<slug>`) for a GitLab issue or MR, otherwise
  `$WORKSPACE_ROOT/<project>`. Never operate on a different checkout.
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)
- `<brainstorm_spec>` — `.tmp/<plan_slug>/<plan_slug>_brainstorm.md`, the design spec
  approved during the planning phase's brainstorming step. It is the approved high-level
  approach (replacing a separate strategy document) and the primary source for the design;
  the raw issue/request is supporting context.

---

## Prerequisites (complete before any step)

You have already completed the **Required reading** in your agent definition (`CLAUDE.md`), you
hold the `## Technical note` and `## Setup commands` blocks the skill forwarded, and you emitted
the "Context loaded" gate. Apply every constraint from the forwarded `## Technical note`
throughout the entire planning. If you have not done that reading yet, do it now before continuing.

---

## Process

> **Mode**: Use Claude Plan Mode for planning steps.
> **Model**: `claude-opus-4-8`

### Step 0 — Set up the working branch

Before producing any artifacts, make sure the repo is on a dedicated branch so the whole
lifecycle (planning → coding → MR) stays on one branch. **Skip this step entirely when
`<project>` is `(unknown)`** — there is no repo to branch.

```bash
cd "$REPO_ROOT"
current="$(git rev-parse --abbrev-ref HEAD)"
```

- If `current` already ends in `-<id>` (issue: `feature/<slug>-<id>` / `bug/<slug>-<id>`) or
  matches `feature/<plan_slug>` (free-form), you are on the dedicated branch — continue.
- Otherwise create it:
  - **(issue ref)** `bash $WF_TOOLS/branch/create_branch.sh <ref> --type feature` — enforces the `feature/<slug>-<id>` (or `bug/...`) convention and checks out the new branch.
  - **(Free-form)** `git checkout -b feature/<plan_slug>` off the intended base.

**Base-branch caveat**: branch creation branches off the **current HEAD**, not the default
branch. If this work should start from `master`, check out `master` (or the agreed base branch)
*before* creating; if it stacks on another in-flight ticket, check out that ticket's branch
first. When unsure which base is correct, ask the user.

If the branch already exists from a previous session, `create_branch.sh` aborts — just
`git checkout` it instead.

---

### Step 1 — Capture the request

**(issue refs only)** Fetch the issue description with the forge tools in `$WF_TOOLS/`:

```bash
python3 $WF_TOOLS/fetch_ticket_description.py <ref>
```

For a **free-form** request (`<plan_source>` = `user-prompt`), the source is `<feature_description>` from the prompt — no fetch.

Extract from the issue or the feature description:
- Goal of the work: what problem is being solved?
- Acceptance criteria or expected outcome
- Any linked issues, MRs, or references

If `<brainstorm_spec>` exists, read it first and treat it as the approved design intent; use
the issue/request here only to fill gaps and confirm scope. Do not re-litigate decisions already
settled in the spec.

If you need a tool that does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

---

### Step 2 — Read relevant documentation

Identify which modules and components are touched by this issue/request. For each relevant module:
- Scan `$REPO_ROOT/docs/` for matching `.md` files
- Check `$REPO_ROOT/README.md` for top-level architecture
- Apply the project-specific constraints from the forwarded `## Technical note` block (already in your context — do not read the must_read file)

Read all found documents. Note any build-system conventions, concurrency rules, or architectural invariants that affect the design.

---

### Step 3 — Write the design documents

The brainstorm spec (`_brainstorm.md`) is the approved high-level approach and replaces the
former strategy document. Do not rewrite it — build the design directly on top of it.

**Read `$WORKSPACE_ROOT/claude_workflow/template/design_document.md` first and follow it exactly.**
It is the normative structure; the notes below only say what this phase adds on top of it.

The design is **two files**, never one:

| File | Contents |
|------|----------|
| `.tmp/<plan_slug>/<plan_slug>_design_overview.md` | purpose and scope, architecture at a glance, diagrams, primary flow, component map, key decisions, assumptions |
| `.tmp/<plan_slug>/<plan_slug>_design_detailed.md` | one section per component, `## Interfaces`, build integration, test strategy, end-to-end walkthrough |

Writing only one of them is an incomplete phase. A design that reads as a flat list of isolated
components is the failure this structure exists to prevent — see the template's three rules.

What this phase requires beyond the template:

**Diagrams** — draw with Mermaid following `$WORKSPACE_ROOT/claude_workflow/template/diagram.md`,
embedded inline as ```` ```mermaid ```` fenced blocks. At minimum an architectural diagram and a
sequence diagram for the main flow, both in the overview, **before** any detailed section exists.
Add a block diagram when the component breakdown needs it.

**Component sections** — every component gets all six headings from the template (Receives /
Produces / Assumes about the rest of the system / Types and signatures / Error conditions / Edge
cases and failure modes), and opens with its upstream and downstream components named. Be precise
about types, error conditions, edge cases and failure modes: a component section that a coder has
to guess at has failed its only job.

**Build system integration** — how new files enter the build. Specify whether changes apply to the
Docker build only or to both Docker and the cross-build (rk3588). List any new `SConscript`
entries, CMakeLists changes, or script modifications needed.

**Test strategy** — automated (unit tests: what to test, which framework and naming convention,
which edge cases from the component sections; integration tests: which boundaries and what
environment) and manual (step-by-step verification by hand).

**End-to-end walkthrough** — close the detailed document by tracing the 1–3 most important user
actions through every component in order, naming each component's section number, and include at
least one failure branch.

Write the state file:

```markdown
# State: <plan_slug>

## Active work
- **Project**: <project>
- **Issue/MR**: #<id>   (omit or "—" for a free-form request)
- **Type**: <plan_source>   (issue | user-prompt)
- **Phase**: Phase 1 – Planning (design written, awaiting approval)

## Completed steps
- [x] Request captured (issue fetched / prompt described)
- [x] Relevant docs read
- [x] Brainstorm spec approved
- [x] Design overview written
- [x] Detailed design written
- [ ] Design approved

## Next step
Present design to user for approval.

## Key decisions
(carried from brainstorm spec)
```

**This is the agent's terminal step.** Approval is an interactive, human-in-the-loop step that
happens in the **main session**, not inside this agent — you have no channel to the user and
cannot wait for a reply. Do **not** wait for approval and do **not** update the state to
"approved" yourself. Once both design documents and the state file (`Phase`: *awaiting approval*)
are written, **stop and return** a short summary to the caller: the paths to
`_design_overview.md` and `_design_detailed.md`, the components covered, and any open questions
for the user. The main session owns approval and the
final state update.

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_brainstorm.md` — approved high-level approach (from the brainstorming step; replaces the old strategy doc)
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_design_overview.md` — architecture, diagrams, component map, key decisions
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_design_detailed.md` — per-component detail, `## Interfaces`, build, tests, end-to-end walkthrough
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/<plan_slug>_state.md` — phase state (update after every approved step)
