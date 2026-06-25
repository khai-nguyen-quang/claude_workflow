# Testing instructions

## Goal

Write unit and integration tests for the code changes produced in the Coding phase. All tests must pass before the phase is complete.

## Inputs (from task context)

- `<project>` — GitLab project name (e.g. `projectX`)
- `<id>` — GitLab issue number
- `WORKSPACE_ROOT` — absolute path to the workspace root
- Code changes from Phase 3 (Coding)
- `<state_context>` — content of `_state.md` if resuming (may be absent)

---

## Process

### Step 1 — Load project context

Use the two blocks the skill forwarded in your task context — `## Setup commands` and
`## Technical note` — and do not read the must_read file yourself; if a block is `(not available)`,
note the gap and proceed. Extract and store:

- **Test commands** (from `## Setup commands`):
  - Run all unit tests → `## Run unit tests` → `<unit_tests_all>`
  - Run a single unit test file → `## Run unit tests` → `<unit_tests_file>`
  - Run all integration tests → `## Run integration tests` → `<itest_all>`
  - Run a single integration test → `## Run integration tests` → `<itest_file>`

- **Unit test framework** (from `## Technical note`) → `## Unit test framework (if any)`:
  - Framework name (e.g. Catch2, GoogleTest, pytest)
  - Test file naming pattern (e.g. `<module>/tests/test_<name>.cc`)
  - Build system registration step (e.g. `env.UnitTest()` in SConscript)

- **Integration test framework** (from `## Technical note`) → `## Integration test framework (if any)`:
  - Framework name (e.g. pytest)
  - Test file naming pattern (e.g. `<module>/tests/test_<name>_docker.py`)
  - Required environment or infrastructure (e.g. Docker, mock hardware, specific fixtures)

- **Other constraints** (from `## Technical note`) → `## Others`

If the file does not exist, fall back to `$WORKSPACE_ROOT/<project>/CLAUDE.md` or `README.md`.

---

### Step 2 — Load language skill

Detect the language from context (file extension, existing code, or design document), then read and apply the matching skill:

- **C++ / `.cc` / `.h`** → load `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md`
- **Python / `.py`** → load `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md`
- **Shell / `.sh`** → load `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md`

If the language is ambiguous, ask before proceeding.

---

### Step 3 — Write unit tests

Apply all guidelines from the loaded skill. Use the framework and naming convention extracted in Step 1:

- Place test files following the naming pattern from `## Unit test framework` (e.g. `<module>/tests/test_<name>.cc` for Catch2 projects).
- Register the test in the build system using the registration step from `## Unit test framework` (e.g. `env.UnitTest(...)` in SConscript for SCons projects).
- For **shell** scripts: shell scripts are typically not unit-tested — instead verify end-to-end behavior and document any manual verification steps.

Cover the happy path, edge cases, and failure modes. Write tests that would catch regressions if the implementation were broken, not tests that merely mirror the implementation structure.

---

### Step 4 — Write integration tests

Integration tests verify that components work correctly together with mocked or real external dependencies. Use the framework and naming convention extracted in Step 1:

- Place test files following the naming pattern from `## Integration test framework` (e.g. `<module>/tests/test_<name>_docker.py` for pytest+Docker projects).
- Set up the required environment or infrastructure from `## Integration test framework` (e.g. mocked hardware fixtures, Docker container, environment variables).
- Identify the interaction boundaries introduced by the new code (IPC, file I/O, network, hardware).
- Cover the main interaction flow and at least one error/edge case across each boundary.
- Aim for tests that would catch regressions caused by changes in a dependent component, not just in the unit under test.

---

### Step 5 — Verify all tests pass

Use the commands extracted in Step 1 to run the full test suite:

```bash
# Run unit tests
<unit_tests_all>

# Run integration tests
<itest_all>
```

Fix any failures before declaring the phase complete.

Update `_state.md` after tests pass:

```markdown
## Completed steps
- [x] Unit tests written
- [x] Integration tests written
- [x] All tests pass

## Next step
Proceed to Phase 5: Code quality assurance.
```

---

## Output files

- Unit test source files (per naming convention in `## Unit test framework`)
- Integration test source files (per naming convention in `## Integration test framework`)
- `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` — updated after tests pass
