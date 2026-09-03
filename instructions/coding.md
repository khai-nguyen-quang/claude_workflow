# Coding instructions

## Goal

Implement the approved design document into production-ready source code. Every logical unit must compile cleanly before moving on to the next.

This single workflow serves both input variants — a **GitLab issue** (`<ref>` has `#`) or a **free-form** request (`<ref>` has no `#`, the same work the planning phase designed). Every step is identical; only Step 0's working-tree check differs (a ticket has a worktree, a free-form run may not). The variant is fixed by the phase as `<work_source>` = `gitlab-issue` or `user-prompt`.

## Inputs (from task context)

- `<work_slug>` — canonical identifier for this run (derived by the phase): `<project>-<id>` for a GitLab issue, or the free-form slug otherwise. It equals the planning phase's `<plan_slug>`; design and state artifacts live under `.tmp/<work_slug>/`.
- `<work_source>` — `gitlab-issue` or `user-prompt`.
- `<project>` — GitLab project name (e.g. `projectX`); may be `(unknown)` for a free-form slug.
- `<id>` — GitLab issue number; empty for a free-form request.
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `REPO_ROOT` — absolute path to the checkout to work in: the ticket's own worktree
  (`$WORKSPACE_ROOT/<project>-worktree/<slug>`) for a GitLab issue or MR, otherwise
  `$WORKSPACE_ROOT/<project>`. Never operate on a different checkout.
- Design document: `$WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/<work_slug>_design.md`
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)

---

## Prerequisites (complete before any step)

Apply the **`## Technical note` constraints provided in your task context** throughout the entire
implementation — the skill forwards them (and the `## Setup commands` block) and is the single
source. If absent or `(not available)`, note the gap and continue; do not read the must_read file
yourself.
**Do not proceed to any step below until these constraints are loaded.**

---

## Process

### Step 0 — Confirm the working tree (do this first, before editing any file)

All work happens inside `$REPO_ROOT` — for a GitLab issue that is the ticket's own **worktree**
(`<project>-worktree/<project>-<id>`), already created and checked out on the ticket's branch by
the `/wf` skill. Verify it before touching any source file. **Skip this step entirely when
`<project>` is `(unknown)`** — there is no repo.

```bash
cd "$REPO_ROOT"
git rev-parse --show-toplevel   # must equal $REPO_ROOT
current="$(git rev-parse --abbrev-ref HEAD)"
```

- `git rev-parse --show-toplevel` must print `$REPO_ROOT`. If it prints anything else you are in
  the wrong checkout — **stop** and report it; do not `cd` elsewhere and do not switch branches.
- `current` must end in `-<id>` (issue: `feature/<slug>-<id>` / `bug/<slug>-<id>`) or match
  `feature/<work_slug>` (free-form). Then continue to Step 1.
- If `current` is the default branch (`master`/`main`) or an unrelated branch, the worktree step
  did not run or was overridden. **Stop and report** — ask the user to re-run the phase so the
  skill can create the worktree. The one exception is a free-form run with no worktree, where you
  may `git checkout -b feature/<work_slug>` off the intended base.

**Never create a branch in, or commit from, the shared main checkout
(`$WORKSPACE_ROOT/<project>`).** Other tickets are being worked on in parallel from that same
repository; switching its branch or committing there corrupts their sessions. Every git command in
this phase runs with the working directory inside `$REPO_ROOT`.

Do not proceed to Step 1 until both checks pass.

---

### Step 1 — Assess complexity and select model

Before writing any code, classify the task using the design document:

| Complexity | Examples | Model |
|------------|----------|-------|
| **Simple** | Add a field, rename, small helper function, boilerplate | `claude-haiku-4-5-20251001` |
| **Moderate** | Implement a feature, refactor a module, add a class | `claude-sonnet-4-6` |
| **Complex** | New subsystem, concurrency, ML pipeline, cross-module architecture, performance-critical code | `claude-opus-4-8` |

State the chosen complexity tier and the reason. If the task spans tiers, use the higher tier.

---

### Step 2 — Extract from project context

From the blocks the skill forwarded in your task context — `## Setup commands` and
`## Technical note` (do not read the must_read file yourself) — extract and store:
- `<compile_cmd>` from `## Compilation` (in `## Setup commands`)
- Unit test framework, file naming pattern, and registration steps from `## Unit test framework (if any)`
- Integration test framework, file naming pattern, and required environment from `## Integration test framework (if any)`
- Project-specific constraints from `## Others`

If a forwarded block is `(not available)`, fall back to `$REPO_ROOT/CLAUDE.md` or `README.md`.

---

### Step 3 — Load language skill

Detect the language from context (file extension, design doc, or existing code), then read and apply the matching skill:

- **C++ / `.cc` / `.h`** → load `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- **Python / `.py`** → load `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- **Shell / `.sh`** → load `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`

If the language is ambiguous, ask before proceeding.

---

### Step 4 — Read the design document

Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/<work_slug>_design.md` in full.

Identify the implementation units (classes, modules, files) in dependency order — implement lower-level components before the ones that depend on them.

---

### Step 5 — Implement

For each implementation unit listed in the design document:

1. Write the code following the conventions from the loaded language skill.
2. Implement **only** what is specified in the design — no extra features, refactors, or abstractions beyond the scope.
3. After completing each logical unit (class, function, module), compile using `<compile_cmd>`. Fix all errors before moving to the next unit.

Update `_state.md` after each unit is complete:

```markdown
## Completed steps
- [x] <Component A> implemented and compiled
- [ ] <Component B> in progress
```

---

### Step 6 — Final state update

After all units are implemented and the full build is clean, update `_state.md`:

```markdown
## Completed steps
- [x] All components implemented
- [x] Build clean

## Next step
Proceed to Phase 4: Write tests.
```

---

## Output files

- Source code files as specified in the design document
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/<work_slug>_state.md` — updated after each compiled unit
