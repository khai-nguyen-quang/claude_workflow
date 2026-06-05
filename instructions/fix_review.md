# Instructions

Fix code based on review findings. Two sources are supported: online (GitLab MR comments) and offline (local review file).

`$WORKSPACE_ROOT` is provided in your task context (`claude_workflow/` is always a direct child of `WORKSPACE_ROOT`).

---

## Prerequisites (complete before any step)

Derive `<project>` from the GitLab ref in your task context (the part before `#`).
Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
Apply every constraint in its `# Technical note` section throughout the entire fix.
**Do not proceed to any step below until this file is read.**

---

## Step 1 — Determine review source

| Input | Source |
|---|---|
| A GitLab MR ref (e.g. `projectX#MR!186`) | **Online** — fetch comments from GitLab |
| A project/issue ref (e.g. `projectX#186`) or no ref | **Offline** — read local review file |

---

## Online workflow

### Step 1.O — Fetch MR comments

Run:
```bash
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_mr_content.sh <ref> --notes
```

Save the output to:
```
$WORKSPACE_ROOT/claude_workflow/.tmp/online-review/<project>-mr-<id>/<project>-mr-<id>-comment.md
```

Where `<project>` and `<id>` are derived from the MR ref (e.g. for `projectX#MR!186`: folder `projectX-mr-186/`, file `projectX-mr-186-comment.md`).

Also check out the MR branch so the code matches the review:
```bash
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/checkout_mr_branch.sh <ref>
```

### Step 2.O — Parse comments

Read `$WORKSPACE_ROOT/claude_workflow/.tmp/online-review/<project>-mr-<id>/<project>-mr-<id>-comment.md`.

Extract actionable comments: ignore system notes and pure praise. For each actionable comment record:
- **File and line** (if the comment references one)
- **What the reviewer flagged**
- **Author and timestamp** (for tracking)
- **Resolved status** (GitLab marks discussion threads as resolved — note this per comment)

Also check whether a previous fix run exists by looking for a `## Fix resolution` section in the comment file or a tracking file at `$WORKSPACE_ROOT/claude_workflow/.tmp/online-review/<project>-mr-<id>/<project>-mr-<id>-resolution.md`. If found, cross-reference its `Status` column to identify already-fixed items.

**Present a triage summary to the user before applying any fixes:**

```
## Triage summary — <project>#MR!<id>

### Already resolved (<N>)
| # | Thread / File:Line | Resolved by |
|---|-------------------|-------------|
| 1 | foo.cc:42 — data race | Marked resolved in GitLab |
| 2 | bar.py:17 — missing check | Fixed in previous run (resolution file) |

### Still open (<N>)
| # | Severity | Thread / File:Line | Comment |
|---|----------|--------------------|---------|
| 1 | Critical | baz.cc:10 | … |
| 2 | Major    | qux.py:5  | … |
```

Wait for the user to confirm before proceeding to Step 2 (load context) and Step 3 (apply fixes). This allows the user to exclude any items from the fix scope.

Organise open items by severity: Critical → Major → Medium → Minor. If a comment does not state severity, infer it from the language ("crash", "data race" → Critical; "must fix" → Major; "consider" → Medium; "nit" → Minor).

---

## Offline workflow

### Step 1.F — Locate review file

Look for the review file at:
- Issue: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_review.md`
- MR: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md`

If no file is found, stop and ask the user to provide the path.

### Step 2.F — Parse review findings

Read the review file. Extract all findings that have a `Fix:` block. Group by severity (Critical → Major → Medium → Minor).

---

## Step 2 — Load project context and language skills

Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` and extract:
- `<compile_cmd>` for build verification
- `<unit_tests_all>` for test verification

If the file does not exist, fall back to the project's `CLAUDE.md`.

For each finding, detect the language of the affected file and load the matching skill:
- `.cc` / `.h` → `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- `.py` → `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- `.sh` → `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`

---

## Step 3 — Apply fixes

Work through findings in severity order: Critical first, then Major, Medium, Minor.

For each finding:
1. Read the affected file and locate the flagged lines.
2. Apply the fix described in the `Fix:` block, following the loaded language skill conventions.
3. Do not change lines outside the scope of the fix.
4. After each fix, run `<compile_cmd>`. If it fails, fix the compilation error before moving to the next finding.

---

## Step 4 — Verify

After all fixes are applied:
1. Run `<compile_cmd>` — must pass with no errors.
2. Run `<unit_tests_all>` — must pass.
3. Run `<itests_all>` — must pass.
4. Run `<lint_all>` — must pass.
5. If tests fail, diagnose and fix before proceeding.

---

## Step 5 — Present final summary and update tracking file

**The resolution file MUST use the exact table format shown below. No prose narrative, no per-item sub-sections, no extra headings — tables only.**

Output the following to the user AND write identical content to the tracking file:

```
## Fix review complete — <project>#MR!<id> — <date>

### Already resolved before this run (<N>)
| # | Severity | Thread / File:Line | Resolved by |
|---|----------|--------------------|-------------|
| 1 | Major    | foo.cc:42          | Marked resolved in GitLab |
| 2 | Medium   | bar.py:17          | Fixed in prior run |

### Fixed in this run (<N>)
| # | Severity | File:Line | Change summary |
|---|----------|-----------|----------------|
| 1 | Critical | baz.cc:10 | Added poll() timeout before recv() |
| 2 | Major    | qux.py:5  | Initialised steer_angle before drain loop |

### Skipped (<N>)
| # | Severity | File:Line | Reason |
|---|----------|-----------|--------|
| 1 | Minor    | nit.cc:3  | Pre-existing, out of scope |
```

Rules for the table:
- Each finding is exactly **one row**. Do not expand rows into sub-bullets or paragraphs.
- `Change summary` must be a single sentence of ≤ 15 words.
- If a finding has no specific file/line, write `—` in that cell.

Write this content to:
```
$WORKSPACE_ROOT/claude_workflow/.tmp/online-review/<project>-mr-<id>/<project>-mr-<id>-resolution.md
```
(online workflow) or append it to the offline review file.

Use `Skipped` with a reason for any finding intentionally not fixed (pre-existing issue, out of scope, won't fix).

---

## Step 6 — Ask before posting (online only)

For the online workflow: after presenting the fix summary, ask:
**"Shall I post a resolution comment to MR `<ref>`?"**

Only if the user confirms, post a summary comment using:
```bash
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/upload_review_comment.py <ref> --file <resolution_summary.md>
```

Never post automatically.
