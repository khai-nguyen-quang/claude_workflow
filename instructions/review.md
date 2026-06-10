# Review instructions

## Goal

Review code changes for correctness, safety, and production readiness. Produce severity-graded findings with concrete fixes. Every finding must include a fix — a finding without a fix is incomplete.

## Inputs (from task context)

- Review target: a GitLab MR ref (e.g. `projectX#MR!177`) **or** local code changes
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `<state_context>` — content of `_state.md` if resuming (may be absent)

> **Model**: always `claude-opus-4-8` — production readiness review requires deep analysis.

---

## Prerequisites (complete before any step)

Derive `<project>` from the GitLab ref in your task context (the part before `#`).
Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
Apply every constraint in its `# Technical note` section throughout the entire review.
**Do not proceed to any step below until this file is read.**

---

## Review criteria

All code is reviewed against:
- **C++**: [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)
- **Python**: PEP 8 and PEP 20
- **Memory safety** (critical): raw `new`/`delete`, buffer overflows, use-after-free
- **Concurrency** (critical): thread safety, mutex acquisition order, data races

---

## Evidence and verification discipline (read before flagging anything)

A false positive costs the author time, erodes trust in the review, and can mask the real
findings. Every finding you assert is a claim you have verified — not a suspicion. Before a
finding enters the table:

1. **Trace the full control flow, not just the changed lines.** A defect in a changed block
   is only a defect if nothing in the surrounding or *calling* code already handles it. Before
   claiming a resource leak, missing cleanup, unhandled signal/interrupt, or "ignored error",
   open the caller and confirm there is no enclosing `finally` / `try-except` / RAII destructor
   / context manager / `defer` / scope guard that already covers the path. Read the function
   that calls the changed code, and the one that calls *that*, until you reach a level where the
   guarantee is or is not provided. Quote the file:line of the handler you checked (whether it
   exists or not) in the finding.

2. **Verify claimed fixes against the diff.** When the MR description or the linked issue says
   a bug was fixed (e.g. "fixed #319"), confirm the corresponding change is actually present in
   `git diff origin/master...HEAD`. A claimed fix that does not appear in the diff — or whose
   changed region is byte-identical to master — is itself a Major finding (traceability), even
   if the rest of the code is clean.

3. **Calibrate confidence, never bluff.** If you cannot conclusively confirm a finding from the
   code in front of you, do one of: (a) verify it by reading more context or running a quick
   check, or (b) lower its severity and label it explicitly as **"unconfirmed — needs author
   confirmation"** with the exact question to resolve it. Never state a tentative concern in the
   assertive voice of a confirmed defect.

4. **Distinguish defect from intentional design.** Interactive waits, busy-polls behind an
   explicit interactive flag, debug-only branches, and deliberate sentinel values are not
   automatically defects. Check the entry condition (what flag/mode gates the code) and the
   intended UX before flagging. If the behaviour is intended and safe under its guard, do not
   flag it — or flag only the genuine residual nit (e.g. poll interval) at Minor.

---

## Structured review passes (mandatory — do all five passes on every file)

To ensure consistent coverage regardless of code size or complexity, review each file in exactly **five sequential passes**. Do not merge passes or skip one because the file "looks clean".

### Pass 1 — Architecture
- **Responsibility boundaries**: does each class/module do one thing? Flag classes that mix concerns (e.g. parsing + I/O + business logic in one unit)
- **Coupling**: flag direct dependencies on concrete types where an abstraction (interface, callback, template) would decouple; flag two-way dependencies between modules
- **Dependency direction**: dependencies must flow toward stable, lower-level modules — flag any low-level module importing from a higher-level one
- **Interface leakage**: internal implementation details (private types, mutable internals, platform specifics) must not appear in public headers or API surfaces
- **Layering violations**: flag calls that skip layers (e.g. a UI component calling a database directly, bypassing a service layer)
- **Abstraction altitude**: a function should operate at one level of abstraction — flag functions that mix high-level orchestration with low-level bit manipulation
- **Ownership and lifetime**: data ownership must be explicit and unambiguous; flag shared ownership where unique ownership is possible, and unclear lifetime contracts across module boundaries
- **Cohesion**: flag modules whose public surface has unrelated responsibilities that would be better split
- **Extensibility**: flag designs that require modifying existing classes/functions to add new behaviour where the Open/Closed principle applies

### Pass 2 — Correctness
- Logic errors, wrong branching conditions, missing cases in switch/if chains
- Off-by-one errors, incorrect loop bounds
- Contract violations: preconditions not checked, postconditions not guaranteed
- Return value ignored where it carries error state (`[[nodiscard]]` violations)
- Integer overflow / underflow in arithmetic

### Pass 3 — Safety
- **Memory**: raw `new`/`delete`, buffer overflows, use-after-free, dangling references
- **Null / bounds**: pointer dereferences without null checks, unchecked array indexing
- **Concurrency**: shared mutable state accessed without locks, mutex acquisition order, TOCTOU
- **Resource leaks**: file descriptors, sockets, handles not closed on all exit paths
- **Cleanup / interrupt paths**: before flagging a leak, a missing cleanup, or an unhandled
  `KeyboardInterrupt`/signal, apply discipline rule #1 — trace the caller for an enclosing
  `finally`/RAII/context-manager guarantee. The exit path of an exception or Ctrl+C is whatever
  runs in the nearest enclosing `finally`, not necessarily code on the changed line. Only flag
  if no such guarantee exists; cite the file:line you checked.

### Pass 4 — Performance
- Unnecessary copies of large objects (pass by value where reference suffices)
- Allocations inside hot loops (prefer stack or pre-allocated buffers)
- O(n²) or worse algorithms in paths that scale with input
- Repeated expensive calls whose results could be cached

### Pass 5 — Language idioms and style
- **C++**: RAII wrappers over raw resource management; `std::optional` / `std::expected` over sentinel values; prefer range-based for; use `std::span` over pointer+size pairs
- **Python**: type annotations on public functions; f-strings over `.format()`; context managers for resources; no bare `except:`
- **Shell**: quote all variable expansions; `set -euo pipefail`; no `[ ]` where `[[ ]]` works


### Coverage table (required after each file)

After completing all five passes on a file, append a one-line coverage table to the review document:

```
| File | Pass 1 Architecture | Pass 2 Correctness | Pass 3 Safety | Pass 4 Performance | Pass 5 Idioms |
|------|--------------------|---------------|--------------------|---------------|---------------------|
| path/to/file.cc | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings |
```

Write `✓ clean` when a pass produced no findings. **Never leave a cell blank** — a blank means the pass was skipped, not that it was clean.

---

## Finding format

Present findings in two parts: a **summary table** for at-a-glance overview, followed by **numbered fix blocks** with concrete code.

### Summary table

| # | Severity | File | Line | Issue | Rule |
|---|----------|------|------|-------|------|
| 1 | Critical | foo.cc | 42 | Null pointer dereferenced before null check | C.149 |
| 2 | Major | bar.py | 17 | Socket fd leaked on error path | resource-leak |
| 3 | Medium | baz.sh | 8 | Unquoted variable expansion | SC2086 |

Sort rows: Critical first, then Major, Medium, Minor.

### Fix blocks

Immediately after the table, one block per finding, keyed by number:

**Fix #1** — `foo.cc:42`
```cpp
// corrected code snippet
```

**Fix #2** — `bar.py:17`
```python
# corrected code snippet
```

Every fix block is mandatory. A finding with no fix block is incomplete.

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
1. Fetch the MR description (`fetch_mr_content.sh`)
2. Fetch the GitLab issue associated with the MR (`fetch_issue_from_mr.py`)

If a needed tool does not exist, implement it following `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`.

Store the following in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md`:
- `## Why MR is needed` — one-paragraph summary of the associated issue
- `## Brief of changes` — one-paragraph summary of what the MR changes

---

### Step 2 — Load project context

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

For each changed file, run all five passes (Architecture → Correctness → Safety → Performance → Idioms) per **Structured review passes**. Findings must be about changed lines, but **read enough surrounding and caller context to judge each change correctly** — a changed block is reviewed in the context of the unchanged code that calls it and that it calls (see Evidence and verification discipline #1). Flag each violation with its rule code; append the coverage table row after each file. Write findings into `## Review` of `<project>-mr-<id>_review.md`.

**Traceability cross-check**: for every fix the MR description or linked issue claims (e.g. "fixed #319"), confirm the change is present in `git diff origin/master...HEAD` (discipline rule #2). Record any claimed-but-absent fix as a Major finding.

---

### Step 5 — Production Readiness Verdict

Reprint the consolidated findings table (all files, sorted Critical → Major → Medium → Minor) followed by all fix blocks. Then close with a summary table of all changed files and one of:
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

For each changed file, run all five passes (Architecture → Correctness → Safety → Performance → Idioms) per **Structured review passes**. Flag each violation with its rule code and a concrete fix. Append the coverage table row after each file.

---

### Step 3 — Production Readiness Verdict

List all findings ordered by severity (Critical → Major → Medium → Minor), omitting any heading with no findings. Close with one of the three verdicts (PRODUCTION READY / NEEDS WORK / NOT PRODUCTION READY).

---

## Output files

- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md` — review document (MR workflow only)
