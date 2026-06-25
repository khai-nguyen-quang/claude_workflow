# review — Phase 6 [wf-reviewer]

**Pre-step** (MR refs only — when `<ref>` contains `MR!`):

1. Checkout the MR branch:
   ```bash
   bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/checkout_mr_branch.sh <ref>
   ```
   Announce the branch name to the user. If checkout fails, stop and report the error.

2. Fetch the MR description:
   ```bash
   bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_mr_content.sh <ref>
   ```
   Extract the **Summary** and **Implementation Details** sections. Store as `<mr_summary>` and `<mr_implementation>`.

Spawn an Agent with:
- **subagent_type**: `wf-reviewer`
- **description**: `Review phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Features
  <technical_note>

  ## Setup commands (from must_read — build / test / lint)
  <setup_commands>

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  Review the code against the Features constraints above. Then follow instructions/review.md.

  <if ref contains MR!>
  ## MR context
  ### Summary
  <mr_summary>

  ### Implementation Details
  <mr_implementation>
  </if>

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` (Features) and `<setup_commands>` (Setup instructions) are forwarded by Step 3 — the sole reader of must_read. The agent also reads `CLAUDE.md` via its Required reading.
`<mr_summary>` / `<mr_implementation>` stay injected — dynamic MR data the parent fetches with GitLab tools.

**Posting findings (when the user asks to post the review to the MR):** follow
`instructions/review.md` → **Step 6 — Upload findings to MR** exactly — it is the single source
for the posting rule (verbatim fix block per finding, inline-anchored resolvable threads, delete
prior bare notes before re-posting).
