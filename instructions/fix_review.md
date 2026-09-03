# Instructions

Fix code based on review findings. Two sources are supported: online (GitLab MR comments) and offline (local review file).

`$WORKSPACE_ROOT` is provided in your task context (`claude_workflow/` is always a direct child of `WORKSPACE_ROOT`).

---

## Prerequisites (complete before any step)

This single workflow fixes review findings from either source; the GitLab steps are gated
**(online / MR only)**. The variant is `<work_source>`:
- **Online** — `<ref>` is a GitLab MR (e.g. `projectX#MR!186`): fetch live comments from the MR.
- **Offline** — `<ref>` is an issue/free-form ref, or none: read the review file already on disk.

`<work_slug>` is the `.tmp/` key for the artifacts this phase reads/writes: `<project>-<id>` for an
issue ref, the free-form slug for a free-form ref, or `<project>-mr-<id>` for an MR. `<project>` may
be `(unknown)` for a free-form slug.

Apply the **`## Technical note` constraints provided in your task context** throughout the entire
fix — the skill forwards them (and the `## Setup commands` block) and is the single source. If
absent or `(not available)`, note the gap and continue; do not read the must_read file yourself.
**Do not proceed to any step below until these constraints are loaded.**

---

## Step 1 — Determine review source

Pick the branch by ref; the GitLab steps in the online branch are gated to MR refs. Then run
**Step 2 onward (shared)** identically for both.

| Input | Branch |
|---|---|
| A GitLab MR ref (e.g. `projectX#MR!186`) | **Online (MR only)** — fetch live comments from GitLab |
| An issue / free-form ref, or no ref | **Offline** — read the review file on disk |

---

## Online branch (GitLab MR only)

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

## Offline branch (review file on disk)

### Step 1.F — Locate review file

Look for the review file at:
- Issue / free-form: `$WORKSPACE_ROOT/claude_workflow/.tmp/<work_slug>/<work_slug>_review.md`
- MR: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md`

If no file is found, stop and ask the user to provide the path.

### Step 2.F — Parse review findings

Read the review file. Extract all findings that have a `Fix:` block. Group by severity (Critical → Major → Medium → Minor).

---

## Step 2 — Load project context and language skills

From the `## Setup commands` block forwarded in your task context (do not read the must_read file
yourself), extract:
- `<compile_cmd>` for build verification
- `<unit_tests_all>` for test verification

If the block is `(not available)`, fall back to the project's `CLAUDE.md`.

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

**This summary is local only — for the chat response and the tracking file. It is never posted
to the MR.** The tracking file exists so a later run can tell what was already fixed (Step 2.O
reads it); it is not a comment draft.

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

## Step 6 — Ask before replying (online only)

For the online workflow: after presenting the fix summary, ask:
**"Shall I reply to the review threads on MR `<ref>`?"**

Never post automatically. **Only if the user confirms** — or when the user asks directly
("post resolution comment", "reply to the review") — carry out the two parts below.

**Reply in the threads and resolve them. Post nothing else.** No standalone summary comment,
no "Fix review complete" note, no table of fixes, no per-file walkthrough — those belong in
the tracking file from Step 5 and nowhere on the MR. The reviewer reads their own threads; a
general comment restating what the replies already say is noise on their MR.

### 6a — Reply to every thread

Every thread that this phase addressed gets its own reply.

List the threads and their ids:
```bash
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/reply_and_resolve.py <ref> --list
```

Build a plan file — one entry per thread, `body` naming **what changed and in which commit**,
one or two sentences, no analysis:
```json
[
  {"discussion_id": "<id>", "body": "Fixed in `<sha>`. <what changed>.", "resolve": true},
  {"discussion_id": "<id>", "body": "Not changed — <reason>.",           "resolve": false}
]
```

Check it before it goes out, then apply:
```bash
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/reply_and_resolve.py <ref> --plan <plan.json> --dry-run
$WORKSPACE_ROOT/claude_workflow/tools/gitlab/reply_and_resolve.py <ref> --plan <plan.json>
```

### 6b — Resolve what is fixed

`"resolve": true` for every thread whose finding is **Fixed**, and only those. A **Skipped**
finding gets a reply explaining why, and stays open — the reviewer decides whether to accept
it. Never resolve a thread whose fix is not actually on the MR's branch.

### Before replying, verify

- The fixes are **on the remote branch the MR shows**, not just in the local tree. Compare
  `git diff <remote-tip> HEAD` — a rebase makes SHAs differ while trees match, which is fine;
  a non-empty diff means something is unpushed and the reply would be false.
- The resolution file carries no stale status line (e.g. "changes are in the working tree,
  not committed") left over from an earlier run.
- No bare `#<number>` anywhere in a body — GitLab autolinks it to an unrelated issue. Refer to
  findings by severity and file, and to commits by SHA.

### Report back

State the count of threads replied to and the count resolved. Then re-run `--list` and confirm
the open/resolved tally matches what you intended.
