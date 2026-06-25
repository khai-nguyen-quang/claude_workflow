# fix_review — Phase 7 [wf-coder]

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Fix review comments for <ref>`
- **prompt**:
  ```
  ## Technical note — Coding and Testing
  <technical_note>

  ## Setup commands (from must_read — build / test / lint)
  <setup_commands>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Instructions: $WORKSPACE_ROOT/claude_workflow/instructions/fix_review.md

  Honor the Coding and Testing constraints above. Then follow the instructions file exactly.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` (Coding and Testing) and `<setup_commands>` (Setup instructions) are forwarded by Step 3 — the sole reader of must_read. The agent also reads `CLAUDE.md` via its Required reading.
