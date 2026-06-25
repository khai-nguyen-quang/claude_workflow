# review — Phase 6 [wf-reviewer → superpowers cross-check]

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

## Cross-check review (superpowers) — run after the wf-reviewer agent returns

Once the `wf-reviewer` agent has written its findings + verdict to **the report file** (the path
selected in `instructions/review.md` → **Review workflow** — `<project>-mr-<id>_review.md` for an
MR, `<project>-<id>_review.md` / `<project>_review.md` for a local review), run an **independent
cross-check in the main session** — a subagent cannot dispatch this, so the skill does it. This
runs for **both** MR and local reviews. The cross-check has two jobs: **verify** the agent's
findings (kill false positives) and **find what the agent missed**.

1. **Derive the review range** (the same range the agent reviewed):
   ```bash
   cd "$WORKSPACE_ROOT/<project>"
   BASE_SHA=$(git merge-base origin/master HEAD)
   HEAD_SHA=$(git rev-parse HEAD)
   ```
   For a local review of uncommitted changes, set `HEAD_SHA=$(git rev-parse HEAD)` and tell the
   reviewer to also inspect `git diff` / `git diff --staged`.

2. **Invoke `superpowers:requesting-code-review`** to dispatch its `general-purpose`
   code-reviewer subagent (fill the skill's `code-reviewer.md` template). Set:
   - `{DESCRIPTION}` = `<mr_summary>` (what the change builds; the brief of changes for a local review)
   - `{PLAN_OR_REQUIREMENTS}` = the linked issue summary + the forwarded `## Technical note — Features`
   - `{BASE_SHA}` / `{HEAD_SHA}` = from step 1

   Append this verification mandate to the dispatched prompt:
   ```
   ## Existing findings to verify (from the wf-reviewer)
   <paste the wf-reviewer's summary table: # / Severity / File / Line / Issue>

   Do BOTH, and keep them separate in your output:
   1. VERIFY each finding above. For each return: Confirmed | Disputed (likely false positive) |
      Uncertain — with one line of reasoning citing the file:line you checked.
   2. INDEPENDENTLY review the diff for findings the list MISSES. Report new findings in your
      standard Output Format with file:line, what's wrong, why it matters, and a fix.
   ```

3. **Reconcile into the same report file.** Update the report file so every finding
   row carries a **Source** column (defined in `instructions/review.md` → Finding format):

   | Source | Meaning |
   |--------|---------|
   | `wf` | only the wf-reviewer found it; cross-check did not dispute it |
   | `wf + sp` | both found it independently — highest confidence |
   | `sp` | only the superpowers cross-check found it (a gap the wf pass missed) |
   | `wf (disputed)` | wf-reviewer found it; cross-check judges it a likely false positive. **Keep the row** and append the cross-check's reasoning under its fix block; **never silently delete it.** Disputed findings are **excluded from auto-posting** to the MR by default. |

   Map the cross-check severities to the wf scale: Critical→Critical, Important→Major, Minor→Minor.
   Prepend a short `## Cross-check summary` block to the report: *N* confirmed, *N* disputed, *N* new
   from cross-check. Keep the consolidated table sorted Critical→Minor. If the cross-check adds
   Critical/Major findings, or disputes a finding the verdict relied on, **update the Production
   Readiness Verdict** (Step 3 of `instructions/review.md`) to match the merged finding set.

**Posting findings (when the user asks to post the review to the MR):** follow
`instructions/review.md` → **Step 4 — Upload findings to MR** exactly — it is the single source
for the posting rule (verbatim fix block per finding, inline-anchored resolvable threads, delete
prior bare notes before re-posting). Skip `wf (disputed)` rows unless the user asks to post them.
