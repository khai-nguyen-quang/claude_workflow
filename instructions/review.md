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
Apply the **Technical note constraints provided in your task context** throughout the entire
review — the skill forwards the relevant subsection and is the single source for them. If they
are absent or marked `(not available)`, note the gap and continue (do not read the must_read
file yourself).
**Do not proceed to any step below until these constraints are loaded.**

---

## Review criteria

All code is reviewed against:
- **C++**: [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines)
- **Python**: PEP 8 and PEP 20
- **Memory safety** (critical): raw `new`/`delete`, buffer overflows, use-after-free
- **Concurrency** (critical): thread safety, mutex acquisition order, data races
- **Test adequacy** (critical for behavioural changes): the test suite is a first-class
  review artifact, not background. Every behaviour the diff adds or changes must have a test
  that proves it, every critical/sentinel branch must be exercised, and every claim of
  coverage (docstring, rubric row, comment) must have an implementing test. See **Pass 6**.
- **Observability / operability**: the system must be diagnosable and tunable from its own
  outputs in the field — symmetric event logging, enough state emitted to tune thresholds,
  no config default that silently mutates inherited state. See **Pass 7**.
- **Requirements traceability**: when the project ships a spec/definition doc with numbered
  requirements (e.g. a rubric `R1–Rn`), every requirement must trace to both a satisfying
  code path **and** a test. See **Requirements traceability** under Step 4.

> **What "review the diff" does not mean.** A clean per-line pass over the changed code is
> *necessary but not sufficient*. The highest-value findings are usually about what is
> **absent** — the test that should exist and doesn't, the falling-edge log that was never
> written, the requirement whose code path has a reachable false-negative. Code that reads
> correctly line-by-line can still be unmergeable because it is untestable, undiagnosable, or
> silently violates a requirement. Hunt for absence, not just defects in what is present.

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

2. **Verify claimed fixes against the diff, then grade by what you find.** When the MR
   description or the linked issue says a bug was fixed (e.g. "fixed #319"), confirm the
   corresponding change is actually present in `git diff origin/master...HEAD`. Grade the result
   by the *state of the code on master*, not merely by the claim's absence from the diff:
   - **Fix genuinely missing → Major (traceability).** The diff does not contain the fix **and**
     the buggy behaviour still exists on master (the changed region is byte-identical to the
     still-broken master code, or the defect is otherwise reachable). A latent bug remains; the
     claim is false. Block on it.
   - **Fix pre-existing / claim mislabelled → Informational.** The behaviour is already correct
     on master (the "fixed" code predates this MR and works), so the MR changelog is inaccurate
     but no defect exists. Record it as Informational and recommend correcting the MR/issue text;
     do **not** block merge.
   - **When unsure which case applies**, verify by reading the master version of the code and the
     linked issue's actual symptom before grading — do not default to Major.

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

## Structured review passes (mandatory — Pass 0 once per module, then all seven passes on every file)

To ensure consistent coverage regardless of code size or complexity, first build a model of each touched module in **Pass 0**, then review each file in exactly **seven sequential passes**. Do not merge passes or skip one because the file "looks clean". Passes 6 and 7 (test adequacy, observability) are the passes the wf review historically skipped — they are not optional add-ons, they carry the same weight as Passes 1–5.

### Pass 0 — Module comprehension (mandatory, before any per-file pass)

A changed line is correct or buggy only relative to the whole-module picture. Before flagging anything in a module, build and **emit a "Module map"** for it:

- **State machine / phases**: the states or phases the module moves through and what transitions them (e.g. `idle → rebootPending → ...`).
- **Lifecycle events**: when code runs — startup, reboot, restart, recovery, teardown, per-tick — and which phase each touched function executes in.
- **Data ownership & timing**: for each field/file/resource the diff touches, who writes it, who reads it, and *at which phase/boot/tick*. Note any value that differs by phase (a file that holds the pre-OTA version at one phase and a new version at another).
- **Invariants**: what must always hold across the module (preconditions a branch relies on).
- **The diff on the map**: place each changed block onto the above — which phase it runs in, what it reads/writes, what it assumes.

**Temporal-phase rule**: never claim two code paths contradict each other (e.g. "the same file can't return two values") without showing they run in the *same* phase/boot/tick. Two accesses in different phases, separated by a state reset or reboot, are not a contradiction. A finding that assumes simultaneity must cite the phase/tick in which both paths run.

Emit the Module map per touched module before the per-file passes for files in that module.

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

### Pass 6 — Test adequacy (audit the test suite, not just the code)

The diff adds or changes behaviour; this pass asks **"what test proves each change, and what
should be tested but isn't?"** Read the test files in the diff *and* the existing test files
for the touched module. For every changed/added behaviour, run this checklist and file a
finding for each gap (the fix block must give the concrete missing test — inputs and the
assertion, not "add a test"):

- **New behaviour / new code path** added by the MR (a new source, mode, counter, branch) →
  is there a direct **isolation/regression test** that exercises *only* it? New behaviour with
  no targeted test is **Major** (it is the part most likely to regress).
- **Critical & sentinel branches** — degenerate/boundary inputs (`-inf`, `0`, empty,
  `d <= 0`, overflow edge, the "already failing" path) → is each **directly** exercised,
  *including the side effect it triggers* (e.g. a sentinel that bypasses a suppression must
  have a test asserting the bypass)? The most numerically extreme branch is usually the least
  tested — check it explicitly. Missing → **Major**.
- **State-transition pairs** — if `X→Y` is tested, is the **reverse `Y→X`** tested? Latch/
  release, suppress/unsuppress, arm/disarm, set/clear. A regression that *latches* a
  suppressed state is a silent false-negative; only the reverse-transition test catches it.
  Missing the reverse → **Major** when the latched state is safety-relevant, else **Medium**.
- **Counter / flag isolation** — when several counters or flags coexist, is there a test
  asserting that the **correct one moves and the others stay zero**? This catches swapped-
  increment regressions. Missing → **Medium**.
- **Coverage claims vs reality** — any docstring, rubric/`Rn` table, test-class description,
  or comment that *claims* a scenario is covered → `grep` for the implementing test. A claim
  with no test is a finding: implement the test **or** delete the claim. Missing → **Medium**.

### Pass 7 — Observability & operability (can the field diagnose and tune this?)

A correct algorithm that emits nothing useful cannot be tuned or debugged after deployment.
Check that the change can be operated:

- **Event-edge symmetry** — if a state's **onset** is logged or published, its **clearance /
  falling edge** must be too, carrying *why it cleared* and the *final state* needed to tune
  it (e.g. FCW logs the rising edge but not the clear → post-hoc analysis can't tell how long
  it held or what cleared it). Asymmetric event logging is **Medium**.
- **Diagnosability of new tunables** — new thresholds / debounce / suppression logic should
  emit the values an operator needs to tune them post-hoc. Silent tunables are **Medium**.
- **Config / env side-effects across process boundaries** — a config or env-var **default that
  overwrites inherited state** is a defect: e.g. `LOGPRINT` defaulting to `WARNING` and calling
  `setLevel(WARNING)` when unset silently downgrades a child process that inherited `DEBUG`.
  Defaults must be **opt-in** (early-return / leave inherited state untouched when unset), not
  state-mutating. **Major** when it suppresses diagnostics or changes behaviour silently.

### Coverage table (required after each file)

After completing all seven passes on a file, append a one-line coverage table to the review document:

```
| File | P1 Architecture | P2 Correctness | P3 Safety | P4 Performance | P5 Idioms | P6 Test adequacy | P7 Observability |
|------|-----------------|----------------|-----------|----------------|-----------|------------------|------------------|
| path/to/file.cc | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings |
```

Write `✓ clean` when a pass produced no findings. For a non-test source file, P6 records the
test-adequacy verdict for *that file's* behaviour (is it covered by some test?); for a test
file, P1–P5 may legitimately be `✓ clean` while P6 carries the real analysis. **Never leave a
cell blank** — a blank means the pass was skipped, not that it was clean. A row with P6 or P7
blank is an incomplete review and must not be delivered.

---

## Finding format

Present findings in two parts: a **summary table** for at-a-glance overview, followed by **numbered fix blocks** with concrete code.

### Summary table

| # | Severity | Source | File | Line | Issue | Rule |
|---|----------|--------|------|------|-------|------|
| 1 | Critical | wf | foo.cc | 42 | Null pointer dereferenced before null check | C.149 |
| 2 | Major | wf | bar.py | 17 | Socket fd leaked on error path | resource-leak |
| 3 | Medium | wf | baz.sh | 8 | Unquoted variable expansion | SC2086 |

Sort rows: Critical first, then Major, Medium, Minor.

**Source column.** Write `wf` for every finding you (the wf-reviewer) report. After you finish,
the skill runs a **superpowers cross-check** (see `phases/review.md`) that reconciles this file and
rewrites the column to one of: `wf + sp` (cross-check independently found it too — highest
confidence), `sp` (cross-check found it, you missed it), or `wf (disputed)` (cross-check judged
your finding a likely false positive — the row is kept with the cross-check's reasoning appended).
You always emit `wf`; the cross-check stage owns the other values.

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
| **Critical** | Security vulnerabilities, data loss, crashes, correctness bugs that will trigger in normal use, **or a latent false-negative / silent failure in a safety, alerting, watchdog, or fail-safe function** (code that fails to act when it must) |
| **Major** | Blocking issues that must be fixed before merge: logic errors, broken contracts, missing error handling at boundaries, **a missing test for a critical/sentinel branch or a safety-relevant state transition**, **a requirement (`Rn`) with no satisfying code path** |
| **Medium** | Non-blocking issues worth fixing: suboptimal patterns, missing tests for ordinary behaviour, missing/asymmetric diagnostic logging, a coverage claim with no implementing test, style violations that affect readability |
| **Minor** | Nits: naming, formatting, comment clarity — won't cause defects |

**Safety / fail-safe severity calibration (read before grading).** Grade by the *consequence
of the failure mode*, not by whether the happy path works. When code whose job is to **act on
a condition** (fire a warning, trip a watchdog, arm a guard, brake) can reach a state where it
**fails to act** on a real instance of that condition, that is **Critical** — "fails to act
when required" ranks with "acts wrongly", even with no crash or data loss. **Never down-grade
such a finding to Medium because it only manifests on an edge or cut-in path — the edge path
is the safety case.** (In MR!202 the reviewer graded a reachable FCW false-negative *High*;
the wf pass graded the same finding *Medium*. That under-grade is the failure this rule fixes.)

---

## Review workflow

This **single** workflow applies to both a GitLab MR ref and a local code review. Every step is
identical except the sub-steps marked **(MR only)**. First fix the review target:

- **MR review** — `<ref>` contains `MR!`. The branch is already checked out by the skill's
  pre-step; the diff under review is `git diff origin/master...HEAD`. Report file:
  `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-mr-<id>/<project>-mr-<id>_review.md`.
- **Local review** — `<ref>` has no `MR!`. The diff under review is the current branch vs
  `origin/master`, plus any uncommitted changes (`git diff`, `git diff --staged`). Report file:
  `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_review.md`
  (`<project>_review.md` when `<ref>` carries no `#<id>`).

Below, **"the report file"** means whichever path the target above selects.

### Step 1 — Establish context

1. **Change summary** — write two paragraphs to the top of the report file:
   - `## Why the change is needed` — the motivation.
   - `## Brief of changes` — what the diff changes.

   **(MR only)** Source these from GitLab: fetch the MR description (`fetch_mr_content.sh`) and the
   linked issue (`fetch_issue_from_mr.py`) with tools in
   `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/`; if a needed tool is missing, implement it per
   `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`. For a **local** review, derive the two
   paragraphs from the branch's commit messages and the intent stated in your task context — no
   GitLab fetch.

2. **Project context** — apply the Technical note constraints provided in your task context (the
   skill forwards them; it is the single source). Scan `$WORKSPACE_ROOT/<project>/docs/` for
   documentation of the modules the diff touches and read the relevant files.

3. **Language skills** — for each changed file, detect the language and load the matching skill:
   - `.cc` / `.h` → `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
   - `.py` → `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
   - `.sh` → `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`
   - other file types → review for logic, structure, and obvious issues without a language skill

   If the language is ambiguous, ask before proceeding.

---

### Step 2 — Review the diff

First, for each module the diff touches, emit its **Pass 0 — Module comprehension** "Module map" (see **Structured review passes**). Do not begin the per-file passes for a module until its Module map is written. Then, for each changed file, run all seven passes (Architecture → Correctness → Safety → Performance → Idioms → Test adequacy → Observability). Findings must be about changed lines, but **read enough surrounding and caller context to judge each change correctly** — a changed block is reviewed in the context of the unchanged code that calls it and that it calls (see Evidence and verification discipline #1), and against its module's phase/timing map (Pass 0). Flag each violation with its rule code; append the seven-column coverage table row after each file.

**Writing the report file is mandatory and is not optional on any run** — for MR *and* local reviews. Write findings into `## Review` of the report file. If the file already exists from a prior run, **overwrite it** with the current run's results — never skip writing because a file is present, and never deliver findings only in the chat response. The chat summary is in addition to the file, not a substitute for it.

**Traceability cross-check**: for every claimed fix — **(MR)** from the MR description or linked issue (e.g. "fixed #319"), or **(local)** from the branch's commit messages — confirm the change is present in `git diff origin/master...HEAD` (discipline rule #2). Record any claimed-but-absent fix as a Major finding.

#### Requirements traceability (mandatory when the project has a spec/definition doc)

If the touched module is governed by a spec/definition doc with **numbered requirements** (a
rubric `R1–Rn`, ISO clauses, an acceptance list — e.g. `docs/fcw-definition.md`), do a
dedicated traceability sweep *before* writing the verdict. Read that doc, then for **each
requirement** build one row:

```
| Req | Satisfying code path (file:line) | Test (file:line) | Verdict |
|-----|----------------------------------|------------------|---------|
| R2.1 cut-in | fcw_estimate.py:301 (arm window) | — none — | FALSE-NEGATIVE: out-of-corridor lead never arms Source C → Critical |
```

- **No satisfying code path, or a path with a reachable false-negative** → **Critical/Major**
  per the safety calibration above. This is the single highest-value class of finding and the
  one a per-line pass misses — you only catch it by walking the requirement *down* into the
  code, not the code up to a requirement.
- **Code path exists but no test** → **Medium** (a `Medium` if ordinary, `Major` if the
  requirement is safety-relevant; see Pass 6).
- **Spec/definition doc completeness** — while reading the doc, flag any requirement that
  **references a parameter, threshold, or term without giving its concrete value/definition**
  where the doc's own purpose is to define it (e.g. a clause that mentions `v_min` / `margin`
  but never specifies them). An under-specified requirement cannot be tested or verified →
  **Medium**.

Write the requirements-traceability table into the report file alongside the findings.

---

### Step 3 — Production Readiness Verdict

Reprint the consolidated findings table (all files, sorted Critical → Major → Medium → Minor) followed by all fix blocks. Then close with a summary table of all changed files and one of:
- **PRODUCTION READY** — all criteria pass, safe to merge.
- **NEEDS WORK** — list the critical/major issues that must be fixed before merge.
- **NOT PRODUCTION READY** — fundamental problems; recommend rewrite of affected sections.

Write the verdict into the report file.

> After this step the skill runs the **superpowers cross-check** (see `phases/review.md`) and
> reconciles both sources into the report file's `Source` column — for MR and local reviews alike.

---

### Step 4 — Upload findings to MR (MR only — after user approval)

After presenting the review, ask: **"Shall I post these review findings to the MR?"**

Post only the **findings** (severity-grouped comments). Do not post summary text, production-readiness verdicts, or informational context — only actionable findings that belong as inline or general MR comments.

**Every posted finding MUST include its suggested fix.** Each comment carries two parts: (1) the finding statement (what is wrong and why), and (2) the corresponding **fix block from the review file**, reproduced verbatim — the concrete `Fix #N` code/snippet, not a paraphrase. A finding posted without its fix block is incomplete; do not post it bare. Prefer **inline** comments anchored to the file/line (`upload_review_comment.py --inline-file <path> --new-line <N>`) so each becomes a resolvable thread, falling back to a general comment only when no diff line applies. If you re-post a finding (e.g. a first post omitted the fix), delete the prior bare note first so the thread is not duplicated.

If the user wants to select a subset, ask which specific comments to upload. Only post after explicit confirmation. Never post automatically.

---

## Output files

- The **report file** — `<project>-mr-<id>_review.md` for an MR review, or `<project>-<id>_review.md`
  (`<project>_review.md` when `<ref>` has no `#<id>`) for a local review — under
  `$WORKSPACE_ROOT/claude_workflow/.tmp/<dir>/`. **Always written**, on every run including
  re-reviews and local reviews (overwrite a stale file from a prior run). A review that produces no
  report file is incomplete, regardless of what was delivered in chat.
