# coding — Phase 3 [wf-coder]

This phase accepts **two input variants**; every step is the same except the branch-setup
sub-step marked **(GitLab issue only)** in `instructions/coding.md`:

- **GitLab issue** — `<ref>` contains `#` (e.g. `projectX#309`).
- **Free-form** — `<ref>` has no `#` (e.g. `projectX` or a slug like `fcw_alert_tuning`), the same
  free-form work the planning phase designed.

## Step 0 — Derive work identifiers

If `<ref>` contains `#`:
- `<project>` = part before `#`, `<id>` = part after `#`
- `<work_slug>` = `<project>-<id>`, `<work_source>` = `gitlab-issue`

Else:
- `<work_slug>` = `<ref>` (use as-is), `<work_source>` = `user-prompt`, `<id>` = empty
- Infer `<project>` from the slug prefix or the only entry in
  `$WORKSPACE_ROOT/claude_workflow/projects/`; if none, `<project>` = `(unknown)` (then
  `<technical_note>` / `<setup_commands>` may be `(not available)`).

`<work_slug>` equals the planning phase's `<plan_slug>` — the design and state artifacts already
live under `$WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/`. **Resume**: the skill's
`<state_context>` is loaded from `.tmp/<project>-<id>/` (= `<work_slug>` for a GitLab issue); for a
free-form run, if `<state_context>` is empty and `.tmp/<work_slug>/<work_slug>_state.md` exists,
read it and treat it as `<state_context>`.

## Step 1 — Spawn the coder agent

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Coding phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Coding and Testing
  <technical_note>

  ## Setup commands (from must_read — build / test / lint)
  <setup_commands>

  ## Task
  Work ref/slug: <ref>  (source: <work_source>)
  Project: <project — or "(unknown)">
  Work slug: <work_slug>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Design document: $WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/<work_slug>_design.md

  Honor the Coding and Testing constraints above. Then follow instructions/coding.md
  against the design document.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` (Coding and Testing) and `<setup_commands>` (Setup instructions) are forwarded by Step 3 — the sole reader of must_read. The agent also reads `CLAUDE.md` via its Required reading.
