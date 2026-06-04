# Debug instructions

## Goal

Investigate a reported bug. Produce a root cause analysis (RCA) document with a concrete fix suggestion.

## Inputs (from task context)

- `<bug_description>` — full bug report text (from GitLab or user prompt)
- `<debug_folder>` — working directory for all output files
- `<debug_prefix>` — file-name prefix (e.g. `projectX-123` or `fcw_not_alert`)
- `<technical_note>` — `# Technical note` section from `<project>_must_read.md` (may be absent)
- `<project_context>` — project CLAUDE.md content (may be absent)
- `<module_doc_paths>` — list of relevant module documentation file paths to read
- `<debug_state>` — previous state file content (present only when resuming)

---

## Process

### Step 0 — Initialize state

Immediately write `<debug_folder>/<debug_prefix>_state.md` with:

```markdown
# Debug state: <debug_prefix>

## Bug summary
<one-line description — fill after reading bug report>

## Investigation status
- **Phase**: initial-analysis
- **Source**: <gitlab-issue | user-prompt>

## Completed steps
- [ ] Bug description understood
- [ ] Module docs read
- [ ] Code search completed
- [ ] Hypotheses formed
- [ ] Root cause identified
- [ ] RCA written

## Hypotheses
(none yet)

## Next step
Read bug description and module documentation.
```

If a state file already exists (resuming), read it and continue from the last incomplete step.

---

### Step 1 — Understand the bug

Read `<bug_description>` carefully. Extract:
- **Expected behavior**: what should happen?
- **Actual behavior**: what is observed?
- **Affected module/subsystem**: which component is involved?
- **Reproduction conditions**: trigger, frequency, environment
- **Clues**: error messages, log lines, stack traces, linked code

Update the state file's `## Bug summary` line.

---

### Step 2 — Read module documentation

Read every path listed under `## Relevant module docs` in your task context. These files contain critical operational details about how the affected subsystem works. Note any invariants, timing constraints, or known limitations that relate to the bug.

---

### Step 3 — Search source code

Use `Grep` and `Glob` to locate:
1. The entry point or trigger of the affected code path
2. The component(s) most likely responsible
3. Any existing tests that reveal expected behavior

Write all search results, file paths, and relevant code snippets to `<debug_folder>/<debug_prefix>_findings.md`:

```markdown
# Findings: <debug_prefix>

## Code search results

### <module / file>
File: <path>:<line>
Relevance: <why this is relevant>
```
<code snippet>
```

...
```

Update state: mark "Code search completed" and note key files found.

---

### Step 4 — Form hypotheses

Based on findings, write 1–3 hypotheses about the root cause. For each:

1. State the hypothesis clearly (one sentence)
2. Cite the specific code that supports or contradicts it
3. Identify what additional check would confirm or rule it out

Add to `<debug_prefix>_findings.md`:

```markdown
## Hypotheses

### H1: <hypothesis statement>
- Supporting evidence: <file:line — quote>
- Contradicting evidence: <file:line — quote or "none">
- Status: open
```

Update state with the hypotheses list.

---

### Step 5 — Validate hypotheses

For each hypothesis, trace the execution path through the code:
- Follow call chains with Grep to confirm the path exists
- Check boundary conditions, lock semantics, timing windows
- Look for related past fixes in git log if relevant

Mark each hypothesis as `confirmed`, `ruled out`, or `uncertain`.

Update `<debug_prefix>_findings.md` with validation results. Update state after each hypothesis is resolved.

---

### Step 6 — Write RCA document

When root cause is identified (or best hypothesis confirmed), write `<debug_folder>/<debug_prefix>_rca.md`:

```markdown
# Root Cause Analysis: <debug_prefix>

## Bug summary
<one-line description>

## Root cause
**File**: `<path>:<line>`
**Cause**: <precise description of what the code does wrong>

<quote the problematic code block>

## Reproduction path
1. <trigger condition>
2. <code path step-by-step to the failure>
3. <observed failure point>

## Fix suggestion
<Describe the fix. Show a diff or before/after code block.>

```diff
- <old code>
+ <new code>
```

## Confidence
**Level**: high | medium | low
**Reason**: <why>

## Related areas to check
- <other files or modules that may be affected or need similar fixes>
```

---

### Step 7 — Final state update

Update `<debug_folder>/<debug_prefix>_state.md`:
- Mark all completed steps
- Set phase to `rca-done`
- Set next step to "Review RCA and apply fix"

Report to the user: summarize the root cause, the affected file/line, and the suggested fix.
