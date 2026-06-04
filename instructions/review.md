# Review instructions

## Goal

Review code changes for correctness, safety, and production readiness. Produce severity-graded findings with concrete fixes. Every finding must include a fix — a finding without a fix is incomplete.

## Inputs (from task context)

- Review target: a GitLab MR ref (e.g. `projectX#MR!177`) **or** local code changes
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `<state_context>` — content of `_state.md` if resuming (may be absent)

> **Model**: always `claude-opus-4-7` — production readiness review requires deep analysis.

---

## Review criteria

All code is reviewed against:
- **C++**: [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)
- **Python**: PEP 8 and PEP 20
- **Memory safety** (critical): raw `new`/`delete`, buffer overflows, use-after-free
- **Concurrency** (critical): thread safety, mutex acquisition order, data races

---

## Structured review passes (mandatory — do all four passes on every file)

To ensure consistent coverage regardless of code size or complexity, review each file in exactly **four sequential passes**. Do not merge passes or skip one because the file "looks clean".

### Pass 1 — Correctness
- Logic errors, wrong branching conditions, missing cases in switch/if chains
- Off-by-one errors, incorrect loop bounds
- Contract violations: preconditions not checked, postconditions not guaranteed
- Return value ignored where it carries error state (`[[nodiscard]]` violations)
- Integer overflow / underflow in arithmetic

### Pass 2 — Safety
- **Memory**: raw `new`/`delete`, buffer overflows, use-after-free, dangling references
- **Null / bounds**: pointer dereferences without null checks, unchecked array indexing
- **Concurrency**: shared mutable state accessed without locks, mutex acquisition order, TOCTOU
- **Resource leaks**: file descriptors, sockets, handles not closed on all exit paths

### Pass 3 — Performance
- Unnecessary copies of large objects (pass by value where reference suffices)
- Allocations inside hot loops (prefer stack or pre-allocated buffers)
- O(n²) or worse algorithms in paths that scale with input
- Repeated expensive calls whose results could be cached

### Pass 4 — Language idioms and style
- **C++**: RAII wrappers over raw resource management; `std::optional` / `std::expected` over sentinel values; prefer range-based for; use `std::span` over pointer+size pairs
- **Python**: type annotations on public functions; f-strings over `.format()`; context managers for resources; no bare `except:`
- **Shell**: quote all variable expansions; `set -euo pipefail`; no `[ ]` where `[[ ]]` works

### Coverage table (required after each file)

After completing all four passes on a file, append a one-line coverage table to the review document:

```
| File | Pass 1 Correctness | Pass 2 Safety | Pass 3 Performance | Pass 4 Idioms |
|------|--------------------|---------------|--------------------|---------------|
| path/to/file.cc | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings |
```

Write `✓ clean` when a pass produced no findings. **Never leave a cell blank** — a blank means the pass was skipped, not that it was clean.

---

## Finding format

Each finding **must** follow this format:

```
<severity> — <file>:<line> — <what is wrong and which rule it violates>
---
Fix: <concrete corrected code snippet or exact change required>
```

### Severity levels

| Severity | Criteria |
|----------|----------|
| **Critical** | Security vulnerabilities, data loss, crashes, correctness bugs that will trigger in normal use |
| **Major** | Blocking issues that must be fixed before merge: logic errors, broken contracts, missing error handling at boundaries |
| **Medium** | Non-blocking issues worth fixing: suboptimal patterns, missing tests, style violations that affect readability |
| **Minor** | Nits: naming, formatting, comment clarity — won't cause defects |

---

## MR Review workflow

### Step 1 — Fetch review content

Use tools in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/` to:
1. Switch to the MR's code branch (`checkout_mr_branch.sh` or equivalent)
2. Fetch the MR description (`fetch_mr_content.sh`)
3. Fetch the GitLab issue associated with the MR (`fetch_issue_from_mr.py`)

If a needed tool does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

Store the following in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md`:
- `## Why MR is needed` — one-paragraph summary of the associated issue
- `## Brief of changes` — one-paragraph summary of what the MR changes

---

### Step 2 — Load project context

Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` and apply all guidance from the `# Technical note` section throughout the review. If the file does not exist, skip this step.

Scan `$WORKSPACE_ROOT/<project>/docs/` for documentation of modules touched by the MR. Read any relevant files.

---

### Step 3 — Load language skills

For each changed file, detect the language and load the matching skill:
- `.cc` / `.h` → `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- `.py` → `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- `.sh` → `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`
- Other file types → review for logic, structure, and obvious issues without a language skill

---

### Step 4 — Review the diff

For each changed file, run all four passes from the **Structured review passes** section above in order: Correctness → Safety → Performance → Idioms. Do not skip any pass.

- Review only the **changed lines** in context (do not flag pre-existing issues in untouched lines)
- Flag each violation with the relevant rule code (e.g. `R.11`, `CP.20` for C++; `UP006`, `TRY003` for Python; `SC2086` for shell)
- After finishing all four passes on a file, append its coverage table row to the review document

Write all findings and the coverage table into the `## Review` section of `<project>-mr-<id>_review.md`.

---

### Step 5 — Production Readiness Verdict

List all findings ordered by severity (Critical → Major → Medium → Minor). Omit any heading with no findings. End with a summary table of all changed files and one of:
- **PRODUCTION READY** — all criteria pass, safe to merge.
- **NEEDS WORK** — list the critical/major issues that must be fixed before merge.
- **NOT PRODUCTION READY** — fundamental problems; recommend rewrite of affected sections.

Write the verdict into `<project>-mr-<id>_review.md`.

---

### Step 6 — Upload findings to MR (only after user approval)

After presenting the review, ask: **"Shall I post these review findings to the MR?"**

Post only the **findings** (severity-grouped comments). Do not post summary text, production-readiness verdicts, or informational context — only actionable findings that belong as inline or general MR comments.

If the user wants to select a subset, ask which specific comments to upload. Only post after explicit confirmation. Never post automatically.

---

## Local Code Review workflow

### Step 1 — Load project context and language skill

Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` and apply all guidance from `# Technical note`. If the file does not exist, skip this step.

Detect the language and load the matching skill:
- **C++ / `.cc` / `.h`** → `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- **Python / `.py`** → `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- **Shell / `.sh`** → `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`

If ambiguous, ask before proceeding.

---

### Step 2 — Review the changes

For each changed file, run all four passes from the **Structured review passes** section above in order: Correctness → Safety → Performance → Idioms. Do not skip any pass.

For each violation, flag the rule code and provide a concrete fix using the finding format above. Append the coverage table row for each file after completing its four passes.

---

### Step 3 — Production Readiness Verdict

List all findings ordered by severity (Critical → Major → Medium → Minor), omitting any heading with no findings. Close with one of the three verdicts (PRODUCTION READY / NEEDS WORK / NOT PRODUCTION READY).

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md` — review document (MR workflow only)
