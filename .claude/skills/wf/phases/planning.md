# planning — Phase 1 [superpowers:brainstorming → wf-planner]

Planning runs in two steps: an inline **brainstorming** step in the main session that turns
the request into an approved design spec (the high-level approach — it replaces the old
strategy document), then the **wf-planner** agent that turns that spec into the formal
design document.

This phase accepts **two input variants**; every step is the same except the sub-steps marked
**(GitLab issue only)**:

- **GitLab issue** — `<ref>` contains `#` (e.g. `projectX#309`). The work is described by a GitLab
  issue fetched in Step 1.
- **Free-form** — `<ref>` has no `#` (e.g. `projectX` or a slug like `fcw_alert_tuning`). The user
  describes the feature in the prompt message; no GitLab fetch.

`<technical_note>` (the `Features` subsection), `<setup_commands>` (the `# Setup instructions`
block), and `<state_context>` are already loaded by the skill's **Prepare context** step — hold
them as project context throughout.

## Step 0 — Derive planning identifiers

If `<ref>` contains `#`:
- `<project>` = part before `#`, `<id>` = part after `#`
- `<plan_slug>` = `<project>-<id>`, `<plan_source>` = `gitlab-issue`

Else:
- `<plan_slug>` = `<ref>` (use as-is), `<plan_source>` = `user-prompt`, `<id>` = empty
- Infer `<project>` from the slug prefix (e.g. `projectX-fcw` → `projectX`) or from the only entry
  in `$WORKSPACE_ROOT/claude_workflow/projects/`; if none can be determined, set `<project>` =
  `(unknown)` (then `<technical_note>` / `<setup_commands>` may be `(not available)`).

`<plan_dir>` = `$WORKSPACE_ROOT/claude_workflow/.tmp/<plan_slug>/`. All planning artifacts
(`_brainstorm.md`, `_design.md`, `_state.md`) live under it, prefixed `<plan_slug>`.

**Resume**: the skill's `<state_context>` is loaded from `.tmp/<project>-<id>/` — which equals
`<plan_dir>` for a GitLab issue. For a **free-form** run, if `<state_context>` is empty and
`<plan_dir>/<plan_slug>_state.md` exists, read it and treat it as `<state_context>`.

## Step 1 — Brainstorming (inline)

**(GitLab issue only)** Fetch the issue:

```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>
```

For a **free-form** request, the feature description is the user's prompt message — use it
verbatim as the idea (no fetch).

Then invoke the Skill tool with `skill: "superpowers:brainstorming"` and follow it, seeding it
with:

- **The idea**: the fetched issue content (GitLab issue) or the user's feature description (free-form).
- **Project context**: `<technical_note>` (Features constraints) and, if present,
  `<state_context>`. Treat these as already-explored context so the skill does not re-derive
  them — honor the Features constraints throughout.

**Two overrides of the brainstorming skill's defaults** (the skill allows user overrides):

1. **Spec location**: write the approved design spec to
   `<plan_dir>/<plan_slug>_brainstorm.md`.
2. **Terminal step**: STOP once the spec is written and the user approves it. Do **NOT**
   invoke `writing-plans` — the wf-planner agent does the planning in Step 2. The brainstorming
   skill's normal terminal (`writing-plans`) is replaced by "hand off to wf-planner".

Do not start Step 2 until the user has approved the spec.

## Step 2 — Planning (wf-planner agent)

Spawn an Agent with:
- **subagent_type**: `wf-planner`
- **description**: `Planning phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Features
  <technical_note>

  ## Setup commands (from must_read — build / test / lint)
  <setup_commands>

  ## Approved design spec (from brainstorming)
  Read <plan_dir>/<plan_slug>_brainstorm.md — this is the approved intent/high-level
  approach; use it as the primary source for the design document.

  ## Task
  Planning ref/slug: <ref>  (source: <plan_source>)
  Project: <project — or "(unknown)">
  Plan slug: <plan_slug>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  Honor the Features constraints above throughout planning. Then follow
  instructions/planning.md; module docs are discovered there (Step 2) from the request.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` (Features) and `<setup_commands>` (Setup instructions) are forwarded by Step 3
of the skill — the sole reader of must_read. The agent also reads `CLAUDE.md` via its Required
reading, and the brainstorm spec via the prompt above.
