# debug — Bug Investigation

**Ref types:**
- GitLab issue `<project>#<id>` → fetch bug description from GitLab, project known
- Free-form slug (no `#`) → user describes bug in the prompt message, project may be inferred

**Step 1 — derive debug identifiers**

If `<ref>` contains `#`:
- `<project>` = part before `#`, `<id>` = part after `#`
- `<debug_slug>` = `<project>-<id>`
- `<bug_source>` = `gitlab-issue`

Else:
- `<debug_slug>` = `<ref>` (use as-is)
- `<bug_source>` = `user-prompt`
- Try to infer `<project>` from the slug prefix (e.g. `projectX-fcw` → `projectX`) or from the only entry in `$WORKSPACE_ROOT/claude_workflow/projects/`. If no project can be determined, set `<project>` = `(unknown)` and skip project-specific steps.

`<debug_folder>` = `$WORKSPACE_ROOT/claude_workflow/.tmp/debug/<debug_slug>/`
`<debug_prefix>` = `<debug_slug>`

**Step 2 — load debug state** (if resuming)

Read `<debug_folder>/<debug_prefix>_state.md` if it exists → `<debug_state>`.

**Step 3 — fetch bug description**

- GitLab issue: run `python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>` → `<bug_description>`.
- Free-form: `<bug_description>` = text the user provided describing the bug.

**Step 4 — discover relevant module docs**

Scan `<bug_description>` for module/subsystem keywords (e.g. `sim`, `managerd`, `camerad`, `loggerd`, `ui`). For each candidate:
- Check `$WORKSPACE_ROOT/<project>/docs/<module>.md`
- Check `$WORKSPACE_ROOT/<project>/tools/<module>/README.md`
- Check `$WORKSPACE_ROOT/<project>/<module>/README.md`

Read all found files → `<module_docs_content>`.

**Step 5 — spawn wf-debugger subagent**

Spawn an Agent with:
- **subagent_type**: `wf-debugger`
- **description**: `Debug investigation: <debug_slug>`
- **prompt**:
  ```
  ## Bug report
  Slug: <debug_slug>
  Source: <bug_source>

  <bug_description>

  ## Debug workspace
  Project: <project — or "(unknown)">
  WORKSPACE_ROOT: <WORKSPACE_ROOT>
  Debug folder: <debug_folder>
  State file: <debug_folder>/<debug_prefix>_state.md
  Findings file: <debug_folder>/<debug_prefix>_findings.md
  RCA file: <debug_folder>/<debug_prefix>_rca.md

  ## Technical note
  <technical_note — entire `# Technical note`; "(not available)" if project unknown>

  ## Setup commands (from must_read — build / test / lint)
  <setup_commands — entire `# Setup instructions`; "(not available)" if project unknown>

  The agent also reads `CLAUDE.md` via its Required reading (skip if Project is "(unknown)").
  Both blocks above are forwarded by the skill's Step 3 — the sole reader of must_read.

  ## Relevant module docs
  <module_docs_content — each file as "### <path>\n<content>"; omit section if no docs found>

  <if debug_state exists>
  ## Current investigation state (resuming)
  <debug_state>
  </if>
  ```

After the subagent finishes, report the RCA summary to the user and the path to `<debug_prefix>_rca.md`.
