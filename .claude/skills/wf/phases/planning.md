# planning — Phase 1 [wf-planner]

Spawn an Agent with:
- **subagent_type**: `wf-planner`
- **description**: `Planning phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Features
  <technical_note>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  Honor the Features constraints above throughout planning. Then follow
  instructions/planning.md; module docs are discovered there (Step 2) from the issue.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` is the `Features` subsection forwarded by Step 3. The agent also reads `CLAUDE.md` via its Required reading.
