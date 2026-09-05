# coding — Phase 3 [wf-coder]

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Coding phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Design overview: $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design_overview.md
  Detailed design: $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design_detailed.md

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```
