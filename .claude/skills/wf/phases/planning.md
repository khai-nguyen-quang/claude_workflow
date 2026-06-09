# planning — Phase 1 [wf-planner]

Spawn an Agent with:
- **subagent_type**: `wf-planner`
- **description**: `Planning phase for <ref>`
- **prompt**:
  ```
  ## Project context
  <project_context>

  ## Technical note
  <technical_note>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  After fetching the issue, identify the modules it touches and read the relevant
  docs under `$WORKSPACE_ROOT/<project>/docs/`, `<project>/README.md`, and any
  `<module>/README.md` before drafting the design (per instructions/planning.md Step 2).

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```
