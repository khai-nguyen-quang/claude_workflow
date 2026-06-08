# Fallback — natural language prompt

Reached when the first token is not a recognized phase. Handle the entire args string as a free-form request.

**Step 1 — extract a ref**

Scan the full args for a token that matches any known ref pattern:
- `<word>#MR!<number>` → MR ref
- `<word>#<number>` → issue ref
- `https?://.../-/(merge_requests|issues|work_items)/<number>` → full URL ref

If a ref is found, set `<ref>` to it and treat the remaining words as `<intent>`.
If no ref is found, `<ref>` is empty and the full args is `<intent>`.

**Step 2 — infer and execute**

| Intent keywords | Action |
|---|---|
| verify, check, access, accessible, ping | Run `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/verify_access.sh` with the project from `<ref>` |
| fetch, show, describe, info, what is | Run the appropriate fetch tool (`fetch_ticket_description.py` for issues, `fetch_mr_content.sh` for MRs) |
| diff, changes | Run `fetch_mr_content.sh <ref> --diff` |
| comments, notes, discussion | Run `fetch_mr_content.sh <ref> --notes` |

Execute the inferred tool inline and display the output to the user.

**Step 3 — if intent is still unclear**

Explain what was understood and print the usage block from **Parse args**.
