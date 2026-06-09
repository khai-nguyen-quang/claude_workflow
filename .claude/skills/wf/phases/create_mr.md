# create_mr — Phase 8 (create the merge request for a completed issue)

Run **inline** (no agent). `<ref>` must be a GitLab **issue** (e.g. `projectX#309`),
not an MR. If `<ref>` contains `MR!`, stop and report: "create_mr expects an issue ref,
not an MR."

**Step 1 — load the MR template**
Read `$WORKSPACE_ROOT/claude_workflow/template/gitlab_mr.md`. It defines the title format,
the description body, and the "Others" section (draft flag + labels). Treat it as the
single source of truth for structure.

**Step 2 — fetch the issue**
```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <ref>
```
Use the issue title and description to fill the template.

**Step 3 — determine the source branch**
Run inside `$WORKSPACE_ROOT/<project>`: `git rev-parse --abbrev-ref HEAD`.
If the branch is the default branch (e.g. `main`/`master`), stop and ask the user which
branch to use. Ensure it is pushed:
```bash
bash $WORKSPACE_ROOT/claude_workflow/tools/gitlab/branch/push_branch.sh
```

**Step 4 — compose the MR body**
- **Title**: per the template — `<concise issue summary>. Ref #<id>`.
- **Description**: start from the template body. Fill `# Summary`, `## Core changes`, and
  the other sections from the design document
  (`$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` if present)
  and the actual `git diff <target>...HEAD`. Leave the testing checklist boxes as the
  template provides them; do not invent test evidence.

Write the composed body to
`$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_mr.md`.

**Step 5 — confirm before creating** (creating an MR is outward-facing)
Show the user the title, target branch, draft flag, labels, and the body file path.
Ask: "Create this merge request?" Wait for confirmation.

**Step 6 — create the MR**
Apply the draft flag and labels from the template's "Others" section.
```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/create_merge_request.py <project> \
  --issue <id> \
  --title "<title>" \
  --description-file $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_mr.md \
  --draft \
  --label "<label>" [--label "<label>" ...] \
  --remove-source-branch
```
(Omit `--draft` / `--label` if the template's "Others" section does not call for them.)
Report the returned MR URL to the user.

**State update**: write `_state.md` noting the MR was created, with its iid/URL.
