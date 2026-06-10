# coding — Phase 3 [wf-coder]

Spawn an Agent with:
- **subagent_type**: `wf-coder`
- **description**: `Coding phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Coding and Testing
  <technical_note>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT
  Design document: $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md

  Honor the Coding and Testing constraints above. Then follow instructions/coding.md
  against the design document.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` is the `Coding and Testing` subsection forwarded by Step 3. The agent also reads `CLAUDE.md` via its Required reading.
