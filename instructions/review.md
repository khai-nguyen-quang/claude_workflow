# Review instructions

## Goal

Review code changes for correctness, safety, and production readiness. Produce severity-graded findings with concrete fixes. Every finding must include a fix — a finding without a fix is incomplete.

## Inputs (from task context)

- Review target: a GitLab MR ref (e.g. `projectX#MR!177`) **or** local code changes
- `WORKSPACE_ROOT` — absolute path to the workspace root
- `REPO_ROOT` — absolute path to the checkout to work in: the ticket's own worktree
  (`$WORKSPACE_ROOT/<project>-worktree/<slug>`) for a GitLab issue or MR, otherwise
  `$WORKSPACE_ROOT/<project>`. Never operate on a different checkout.
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
- **Requirements traceability** (mandatory on every review): every obligation stated by the
  linked issue — numbered or prose, code or documentation — must trace to something in the
  deliverable, and every requirement in a governing spec doc must trace to both a satisfying
  code path **and** a test. See **Requirements traceability** under Step 2.
- **Referential integrity** (documentation): anchors, cross-file links, `§` pointers, cited
  `file:line` and commit SHAs must resolve. Checked mechanically, never by eye. See **Pass 8**.
- **Downstream consumer impact**: any interface, schema, or behavioural change — including one
  a design doc only *proposes* — must be walked into every existing consumer. "Nothing
  downstream changes" is a claim to verify, not to accept. See **Pass 9**.
- **Claim provenance**: a statement in the artifact under review that originated from this
  workflow's own earlier output is **unverified**, no matter how many passes have repeated it.
  See **Evidence and verification discipline** #6.

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

5. **Trace actual execution, not just the lines as written.** Read for what the code *does at
   runtime*, not what the text appears to say. A line is a defect only if it actually runs, with
   the values it actually receives, on the path you claim. Before flagging, confirm:
   - **Reachability** — the guard/flag/branch gating the line can be true at runtime. It is not
     dead code, an `if (false)` / compile-time-disabled branch, or an unregistered handler.
   - **Actual values** — trace where each variable is *set* (default, override, env var, prior
     assignment), don't assume the literal at its declaration. A const that looks wrong may be
     reassigned; a pointer that looks null may be initialised before use; a config default may be
     overridden upstream.
   - **Dynamic dispatch / overrides** — virtual calls, overridden methods, monkey-patches,
     callbacks, and DI/registry bindings may execute a different body than the one textually in
     front of you. Resolve which implementation actually runs.
   - **Macros / templates / generated code / decorators** — review the *expansion*, not the
     surface form; the generated behaviour is what executes.
   If you cannot trace the actual execution to the failure, the finding is unconfirmed (rule #3) —
   do not assert it as a runtime defect.

6. **Prior findings are claims, not evidence — verify against source every time.** A previous
   review pass, a `_review.md` file, a `_state.md` file, a brainstorm doc, or an MR description
   is **not** ground truth. Their assertions carry no more weight than the diff's own comments.
   Re-derive every load-bearing claim from the code, however many passes have already "confirmed"
   it. Concretely, never write or endorse a finding whose only support is that an earlier pass
   said so.

   **The self-confirming loop is the failure this rule exists to break.** A review finding gets
   written into the artifact (doc, spec, MR description); the next pass reads the artifact,
   sees its own earlier claim, and marks it verified. Each pass increases apparent confidence
   while adding zero evidence. On openpilot MR!230 this ran for four passes: pass 1 invented
   "the mock path is the fork's default runtime state", the claim was propagated into the
   brainstorm, the design doc and the MR description, pass 4 "corrected" it to a different
   wrong state, and the doc's trap T2 was written from the review's own finding. A human broke
   it with one `grep` of `car_helpers.py` (`candidate = "mock"` on fingerprint failure).

   **Provenance rule.** When a claim in the artifact under review can be traced to a prior
   review pass or to this workflow's own earlier output, treat it as **unverified** and mark it
   so in the finding table (`Source: wf (provenance: pass N)`). Verify it against source before
   relying on it — and if it is wrong, the finding is that *the workflow wrote an error into the
   deliverable*, graded by the consequence of that error, not by its origin.

7. **Cite source, not the artifact.** Every finding's evidence must be a `file:line` in the
   **codebase** (or a `git show <sha>:<path>` for historical claims), never a section number in
   the document under review. "§4 says X, so X" is not verification. If a finding's only citation
   is to the reviewed artifact, it is unconfirmed under rule #3.

---

## Structured review passes (mandatory — Pass 0 once per module, then all nine passes on every file)

To ensure consistent coverage regardless of code size or complexity, first build a model of each touched module in **Pass 0**, then review each file in exactly **nine sequential passes**. Do not merge passes or skip one because the file "looks clean". Passes 6–9 (test adequacy, observability, referential integrity, downstream impact) are the passes the wf review historically skipped — they are not optional add-ons, they carry the same weight as Passes 1–5, and on documentation deliverables they carry **more**.

### Reviewing a documentation or design deliverable

Passes 1–5 are written for code. When the diff is documentation — a planning doc, design doc,
spec, or architecture note — **the review is not lighter, it moves**: P1–P5 shrink to
"is the described design sound?" while **P6, P8 and P9 plus the requirements-traceability sweep
carry the whole review**, and they must be run at full depth. Additionally, for a design doc:

- **Every factual claim about the codebase is a claim under discipline rule #7** — verify each
  against `file:line`, including claims about upstream/historical code (`git show <sha>:<path>`).
  A design doc's authority comes entirely from these being right; implementers act on them.
- **Internal contradiction is a first-class defect.** A document that states a contract in one
  section and describes an implementation that cannot produce it in another has a **Major**
  defect, because the reader cannot tell which half is the plan. Read the document whole and
  cross-check its own claims against each other — schema promises vs the code the doc says to
  port vs the open questions it records.
- **An "open question" that a later section has already answered as settled is a defect** — the
  contract was written before the decision. Grade **Medium**, or **Major** when it is a wire
  format or other expensive-to-revisit interface.
- **A stated bound or guarantee must be checked against every channel it could break**, not only
  the one the document argues over. Ask what else changes that the bound does not mention.

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
- **Falsifiability of the proposed verification** — when the diff *proposes* a test, a
  verification plan, or a replay/CI check (common in design docs), ask **"can this check
  actually fail?"** Open the harness it names and read its configuration. A check whose
  comparison ignores the field it claims to prove, that runs against fixtures containing no
  instance of the condition, or whose threshold is left as an open question, is **not a proof**
  — grade it **Major** when a stated bound rests on it. On openpilot MR!230 the plan claimed
  replay proved the FCW bound mechanically; `process_replay.py:286` declares
  `ignore=[..., "valid", ...]` for that process, so the check could not fail. Likewise a
  mitigation whose threshold the same document lists as an open question cannot be asserted
  against and cannot be tested as specified.

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

### Pass 8 — Internal & referential integrity (mandatory for every `.md` file; mechanical)

Every cross-reference in the diff is a claim that resolves or does not. These are cheap to check
and are never caught by reading for meaning — check them **mechanically**, with `grep`/`ls`, not
by eye:

- **Intra-document anchors** — for each `](#...)` link, confirm a heading in the same file
  generates that anchor (lowercase, spaces→`-`, punctuation dropped). A link to
  `#12-stage-2--clustering-x` when the heading reads "1.2 Stage 2 — Filter" is a **Minor** dead
  link, but it is **Medium** when the orphaned section is the argument another finding turns on.
- **Cross-file links** — `ls` every `](path.md)` target. A link to a file this same MR deletes,
  or to one that never existed, is **Medium**.
- **Section pointers** — every `§N.M` reference must land on the section that contains the
  claimed content. Check each one against the file's actual heading list; drift by one
  subsection is the common case. **Medium** when a pointer sends an implementer to the wrong
  contract.
- **Cited `file:line` and commit SHAs** — spot-check that each cited path exists and the cited
  content is at/near that line; for `git show <sha>` claims, run it. **Attribution of a change
  to the wrong commit is Medium** — implementers are sent to that SHA to recover code.
- **Self-consistency across the document set** — when the MR ships or edits several documents,
  grep the *unedited* parts of every touched file for statements the diff contradicts. A new
  paragraph asserting a capability while three untouched passages in the same file deny it is
  **Medium**.

### Pass 9 — Downstream consumer impact (mandatory for every file)

Passes 1–5 ask "is this correct?". This pass asks **"if this is adopted as written, what breaks
in code that already exists?"** — the second-order question that a per-line pass structurally
cannot reach. For every interface, schema, data contract, or behavioural change in the diff
(including one a *design document* merely proposes):

1. **Enumerate the consumers.** `grep` for every reader of the field, message, topic, or
   function. List them by `file:line` in the finding.
2. **For each consumer, ask what changes underneath it.** Does it branch on a field the change
   makes newly variable? Does it hold state across cycles that the change now discontinues? Does
   it assume a value's provenance (measured vs derived vs defaulted) that the change alters?
3. **Challenge every "nothing downstream changes" claim in the diff or MR description.** That
   sentence is a claim under discipline rule #6 and must be verified consumer by consumer. It is
   the single most common false statement in a design doc. When it is wrong, the finding is
   **Major** — it steers implementers away from the one file that needs the change.

Watch specifically for **state held across cycles**: filters, integrators, least-squares windows,
debounce counters, latches. A consumer that differentiates or accumulates a value is sensitive to
*discontinuities* in that value, not just to its range — so a change that swaps a field's source
between two individually-valid producers injects a step the consumer reads as real motion.

On openpilot MR!230 the design proposed feeding `LeadData` from radar when a match exists and
from vision otherwise, and asserted "no downstream file should need to change".
`FcwEstimate` differentiates `lead.dRel` into `_d_cont` over a least-squares window and resets
only on `prev_lead_present` / `LEAD_JUMP_DIST` — `fcw_estimate.py` contains **zero** occurrences
of "radar" — so every source flip fabricates a closing rate. One `grep` for the consumer, one
read of its state machine.

### Coverage table (required after each file)

After completing all nine passes on a file, append a one-line coverage table to the review document:

```
| File | P1 Architecture | P2 Correctness | P3 Safety | P4 Performance | P5 Idioms | P6 Test adequacy | P7 Observability | P8 Integrity | P9 Downstream |
|------|-----------------|----------------|-----------|----------------|-----------|------------------|------------------|--------------|---------------|
| path/to/file.cc | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ N findings | ✓ n/a | ✓ N findings |
```

Write `✓ clean` when a pass produced no findings, and `✓ n/a` only for P8 on a non-`.md` file.
For a non-test source file, P6 records the test-adequacy verdict for *that file's* behaviour (is
it covered by some test?); for a test file, P1–P5 may legitimately be `✓ clean` while P6 carries
the real analysis. **Never leave a cell blank** — a blank means the pass was skipped, not that it
was clean. A row with P6, P7, P8 or P9 blank is an incomplete review and must not be delivered.

---

## Finding format

Present findings in two parts: a **summary table** for at-a-glance overview, followed by **numbered fix blocks** with concrete code.

### Summary table

| # | Status | Severity | Source | File | Line | Issue | Rule |
|---|--------|----------|--------|------|------|-------|------|
| 1 | Open | Critical | wf | foo.cc | 42 | Null pointer dereferenced before null check | C.149 |
| 2 | Open | Major | wf | bar.py | 17 | Socket fd leaked on error path | resource-leak |
| 3 | Open | Medium | wf | baz.sh | 8 | Unquoted variable expansion | SC2086 |

Sort rows: Critical first, then Major, Medium, Minor.

**Status column.** Track each finding's posting state: `Open` (in the report, not posted — the
default at first write), `Posted (<note-id>)` (uploaded to the MR), or `N/A` (withdrawn/disputed).
The skill/cross-check writes every row as `Open`; **Step 4 — Upload findings to MR** flips cells to
`Posted (<id>)` after upload. Keep the column in sync with the MR on every re-post.

**Provenance annotation.** When a finding concerns a claim that this workflow itself wrote into
the artifact (discipline rule #6), append `(provenance: pass N)` to the Source cell — e.g.
`wf (provenance: pass 1)`. This marks a finding the workflow is correcting in its *own* output,
so a later pass cannot mistake it for independently established fact.

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
| **Major** | Blocking issues that must be fixed before merge: logic errors, broken contracts, missing error handling at boundaries, **a missing test for a critical/sentinel branch or a safety-relevant state transition**, **a requirement with no satisfying code path or a topic the linked issue mandated and the deliverable omits**, **a false "nothing downstream changes" claim**, **a stated bound resting on a check that cannot fail**, **a document whose contract and implementation sections contradict each other** |
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

### Step 0 — Scope-change gate (mandatory when a prior review exists)

Before reading anything else, determine whether the artifact you are about to review is the
same artifact the previous pass reviewed. If a report file or `<state_context>` from a prior
run exists:

```bash
cd "$REPO_ROOT"
git log --oneline $(git merge-base origin/master HEAD)..HEAD
git diff --stat $(git merge-base origin/master HEAD)...HEAD
```

Compare the files in that diff against the files the prior report's findings cite. Then classify:

| Situation | Action |
|-----------|--------|
| Every previously reviewed file still exists and changed only incrementally | Normal re-review. Carry prior findings forward, re-verifying each against source (discipline rule #6). |
| **A previously reviewed file was deleted, renamed, or replaced** | **Full fresh review. Discard the prior finding set entirely** — do not carry rows forward, do not mark them "resolved". Findings against a file that no longer exists are moot, not fixed. State this explicitly in the report. |
| The diff grew by a new file or a substantial section the prior pass never saw | Review the new material from scratch at full depth; do not let the prior verdict set the depth. |

**"The findings no longer apply" is not the same as "the concerns were addressed."** When an
artifact is rewritten, the replacement is **unreviewed** and starts at zero, regardless of how
many passes ran against its predecessor. Say so in the verdict.

On openpilot MR!230 the reviewed `docs/radar-integration.md` was deleted (-435) and replaced by
three new documents (+940) that changed the proposed architecture. Four passes' worth of
findings were reported as resolved; the replacement had never been reviewed, and a human found
18 findings in it.

---

### Step 1 — Establish context

1. **Change summary** — write these sections to the top of the report file, in this order:
   - `## How the module works` — a brief paragraph on how the module(s) the diff touches
     (e.g. `updated`, `camerad`, `fcw`, `streamerd`) normally operates: its responsibility,
     where it sits in the system, and the normal workflow / data flow it drives. Pitch it so a
     reader unfamiliar with the module can follow the rest of the review. Draw on the **Pass 0 —
     Module comprehension** map and the module docs scanned in step 2 — do not invent behaviour.
   - `## How this MR changes the workflow` — how the diff alters that normal workflow: which step
     in the module's flow is added, removed, reordered, or now behaves differently, and the net
     effect on the module's operation.
   - `## Why the change is needed` — the motivation.
   - `## Brief of changes` — what the diff changes.

   **(MR only)** Source these from GitLab: fetch the MR description (`fetch_mr_content.sh`) and the
   linked issue (`fetch_issue_from_mr.py`) with tools in
   `$WF_TOOLS/` (`tools/gitlab/` or `tools/github/`); if a needed tool is missing, implement it per
   `$WORKSPACE_ROOT/claude_workflow/instructions/gitlab.md`. For a **local** review, derive the two
   paragraphs from the branch's commit messages and the intent stated in your task context — no
   GitLab fetch.

2. **Project context** — apply the Technical note constraints provided in your task context (the
   skill forwards them; it is the single source). Scan `$REPO_ROOT/docs/` for
   documentation of the modules the diff touches and read the relevant files.

3. **Language skills** — for each changed file, detect the language and load the matching skill:
   - `.cc` / `.h` → `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
   - `.py` → `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
   - `.sh` → `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`
   - other file types → review for logic, structure, and obvious issues without a language skill

   If the language is ambiguous, ask before proceeding.

---

### Step 2 — Review the diff

First, for each module the diff touches, emit its **Pass 0 — Module comprehension** "Module map" (see **Structured review passes**). Do not begin the per-file passes for a module until its Module map is written. Then, for each changed file, run all nine passes (Architecture → Correctness → Safety → Performance → Idioms → Test adequacy → Observability → Referential integrity → Downstream impact). Findings must be about changed lines, but **read enough surrounding and caller context to judge each change correctly** — a changed block is reviewed in the context of the unchanged code that calls it and that it calls (see Evidence and verification discipline #1), and against its module's phase/timing map (Pass 0). Flag each violation with its rule code; append the nine-column coverage table row after each file.

When the diff is documentation, apply **Reviewing a documentation or design deliverable** (under **Structured review passes**) — the pass weights move, they do not shrink.

**Writing the report file is mandatory and is not optional on any run** — for MR *and* local reviews. Write findings into `## Review` of the report file. If the file already exists from a prior run, **overwrite it** with the current run's results — never skip writing because a file is present, and never deliver findings only in the chat response. The chat summary is in addition to the file, not a substitute for it.

**Traceability cross-check**: for every claimed fix — **(MR)** from the MR description or linked issue (e.g. "fixed #319"), or **(local)** from the branch's commit messages — confirm the change is present in `git diff origin/master...HEAD` (discipline rule #2). Record any claimed-but-absent fix as a Major finding.

#### Requirements traceability (mandatory on every review — two sources)

Run this sweep *before* writing the verdict, always. Requirements come from **two** places and
both must be swept:

**Source A — the linked issue / MR acceptance criteria (mandatory whenever a `<ref>` exists).**
Fetch the linked issue (`fetch_issue_from_mr.py`) and extract **every** obligation it states,
whether or not it is numbered. Treat as a requirement any heading under a "must cover" /
"acceptance criteria" / "scope" section, every bullet under such a heading, and any sentence
using *must* / *shall* / *required*. **A requirement does not have to look like `R1` to be one** —
a `##` heading in an issue that says "the document **must** cover the following topics" makes
each heading below it a requirement.

For a **deliverable that is a document** (planning doc, design doc, spec), the "satisfying code
path" is the section of the deliverable that covers the topic. Verify coverage by `grep`, not by
impression: search the deliverable for the topic's key identifiers (protocol names, function
names, file names the issue mentions). **Zero hits is a finding, not an oversight to mention in
passing.**

| Verdict | Severity |
|---------|----------|
| A mandated topic is **absent** from the deliverable | **Major** — the deliverable does not meet its own acceptance criteria. List every absent topic by name. |
| A mandated topic is **named but not explained** (the term appears, its mechanism/provenance never does) | **Medium** — partial coverage; say precisely what is missing. |
| Scope was deliberately cut | **Medium** — the issue must be amended to record the cut; settling it only in the MR description is not traceable. |

On openpilot MR!230 the issue mandated six topics; three (vehicle-fingerprint detection and its
failure path, UDS radar-ECU detection, new-vehicle adoption) had **zero** occurrences across all
three delivered documents. No review pass checked, because the traceability sweep was written as
code-vs-numbered-requirement and the issue's requirements were prose headings.

**Source B — the project's spec/definition doc, when one governs the touched module** (a rubric
`R1–Rn`, ISO clauses, an acceptance list — e.g. `docs/fcw-definition.md`). Read that doc, then
for **each requirement** build one row:

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

**Every posted finding MUST include its suggested fix.** Each comment carries two parts: (1) the finding statement (what is wrong and why), and (2) the corresponding **fix block from the review file**, reproduced verbatim — the concrete `Fix #N` code/snippet, not a paraphrase. A finding posted without its fix block is incomplete; do not post it bare. Prefer **inline** comments anchored to the file/line (`upload_review_comment.py --inline-file <path> --new-line <N>`) so each becomes a resolvable thread, falling back to a general comment only when no diff line applies. If you re-post a finding (e.g. a first post omitted the fix, or a prior post was too long), **delete the prior note first** so the thread is not duplicated — there is no helper for this; call the API directly:

```python
# DELETE /projects/<url-encoded path>/merge_requests/<iid>/notes/<note_id>
# token via _common.get_token(); a 204 confirms deletion.
```

#### Comment length — keep it to Issue + Suggested fix

**An MR comment is not the review report.** The report file carries the analysis; the comment
carries only what the author needs to act. Each posted comment has exactly three parts and nothing
else:

1. **A bold one-line heading** — `**[Severity] — <short title>**`
2. **The issue** — 1–3 sentences: what is wrong, and the one fact that establishes it (the failing
   grep, the mutation that stayed green, the line that contradicts it). Add the consequence only
   when it is not obvious from the defect itself.
3. **`**Suggested fix**`** — the verbatim fix block.

Target **under 15 lines of prose** per comment, excluding the code block. If a comment needs more,
the extra belongs in the report file, not on the MR.

**Cut these from every comment** — they read as padding to the author, who already knows the
codebase:
- Re-explaining what the code under review does, or how the module works
- Restating the design rationale the author wrote
- Reachability essays, severity-calibration arguments, cross-references to other findings
- Evidence the author can trivially re-run (paste the *conclusion* — "replacing this branch with
  `return True` leaves the suite green" — never the full grep transcript that got you there)
- Praise, hedging, or apology framing

Keep a severity justification only when the grade is likely to surprise — one clause, not a
paragraph (e.g. *"Low reachability (needs a stale dir at our own job key, impossible in CI with a
unique `$CI_JOB_ID`), hence Minor."*).

Judge each drafted comment by: **would the author have to read a single sentence twice to know what
to change?** If yes, cut until they do not.

If the user wants to select a subset, ask which specific comments to upload. Only post after explicit confirmation. Never post automatically.

**Record posting status back into the report file (mandatory, part of the post action — not a
separate request).** Whenever the user asks to post findings — including an explicit subset such as
*"Post finding #1, #2, #3"* — updating the report is **part of fulfilling that request**, performed
in the same turn without waiting to be asked again. Posting to the MR and updating the report's
Status column are one atomic action: a finding is not "posted" until both the MR thread exists **and**
its report row says so. The report's summary table carries a **Status** column (see *Finding format →
Summary table*). Immediately after each upload returns its note id, update the Status cell of every
affected finding — never leave the report out of sync with what is on the MR:

| Status | Meaning |
|--------|---------|
| `Posted (<note-id>)` | Uploaded to the MR as a comment/thread; record the returned note/discussion id. |
| `Open` | In the report, not posted (default for every finding until it is posted). |
| `N/A` | Withdrawn or disputed (`wf (disputed)`) — not actionable, intentionally not posted. |

Default every finding to `Open` when the table is first written (Step 2). Flip to `Posted (<id>)`
only after the upload tool confirms the note id. If a thread is later resolved/deleted, reflect that
here too. Close the step by printing the posted/open tally (e.g. "8 posted, 9 open").

---

## Output files

- The **report file** — `<project>-mr-<id>_review.md` for an MR review, or `<project>-<id>_review.md`
  (`<project>_review.md` when `<ref>` has no `#<id>`) for a local review — under
  `$WORKSPACE_ROOT/claude_workflow/.tmp/<dir>/`. **Always written**, on every run including
  re-reviews and local reviews (overwrite a stale file from a prior run). A review that produces no
  report file is incomplete, regardless of what was delivered in chat.
