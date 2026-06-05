# Coding instructions

## Goal

Implement the approved design document into production-ready source code. Every logical unit must compile cleanly before moving on to the next.

## Inputs (from task context)

- `<project>` — GitLab project name (e.g. `projectX`)
- `<id>` — GitLab issue number
- `WORKSPACE_ROOT` — absolute path to the workspace root
- Design document: `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md`
- `<state_context>` — content of `_state.md` if resuming a previous session (may be absent)

---

## Prerequisites (complete before any step)

Derive `<project>` from the GitLab ref in your task context (the part before `#`).
Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
Apply every constraint in its `# Technical note` section throughout the entire implementation.
**Do not proceed to any step below until this file is read.**

---

## Process

### Step 1 — Assess complexity and select model

Before writing any code, classify the task using the design document:

| Complexity | Examples | Model |
|------------|----------|-------|
| **Simple** | Add a field, rename, small helper function, boilerplate | `claude-haiku-4-5-20251001` |
| **Moderate** | Implement a feature, refactor a module, add a class | `claude-sonnet-4-6` |
| **Complex** | New subsystem, concurrency, ML pipeline, cross-module architecture, performance-critical code | `claude-opus-4-7` |

State the chosen complexity tier and the reason. If the task spans tiers, use the higher tier.

---

### Step 2 — Load project context

Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`. Extract and store:
- `<compile_cmd>` from `## Compilation`
- Unit test framework, file naming pattern, and registration steps from `# Technical note` → `## Unit test framework (if any)`
- Integration test framework, file naming pattern, and required environment from `# Technical note` → `## Integration test framework (if any)`
- Project-specific constraints and invariants from `# Technical note` → `## Others`

Apply all guidance from `# Technical note` throughout the implementation. If the file does not exist, fall back to `$WORKSPACE_ROOT/<project>/CLAUDE.md` or `README.md`.

---

### Step 3 — Load language skill

Detect the language from context (file extension, design doc, or existing code), then read and apply the matching skill:

- **C++ / `.cc` / `.h`** → load `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- **Python / `.py`** → load `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- **Shell / `.sh`** → load `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`

If the language is ambiguous, ask before proceeding.

---

### Step 4 — Read the design document

Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_design.md` in full.

Identify the implementation units (classes, modules, files) in dependency order — implement lower-level components before the ones that depend on them.

---

### Step 5 — Implement

For each implementation unit listed in the design document:

1. Write the code following the conventions from the loaded language skill.
2. Implement **only** what is specified in the design — no extra features, refactors, or abstractions beyond the scope.
3. After completing each logical unit (class, function, module), compile using `<compile_cmd>`. Fix all errors before moving to the next unit.

Update `_state.md` after each unit is complete:

```markdown
## Completed steps
- [x] <Component A> implemented and compiled
- [ ] <Component B> in progress
```

---

### Step 6 — Final state update

After all units are implemented and the full build is clean, update `_state.md`:

```markdown
## Completed steps
- [x] All components implemented
- [x] Build clean

## Next step
Proceed to Phase 4: Write tests.
```

---

## Output files

- Source code files as specified in the design document
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` — updated after each compiled unit
