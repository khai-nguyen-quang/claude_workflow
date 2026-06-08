# collect — Project context collection

`<project>` is the bare project name from `<ref>` (no `#`).

**Goal**: read all relevant documents of the project, extract operational details, and produce
`$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` following
the template at `$WORKSPACE_ROOT/claude_workflow/projects/template_must_read.md`.

The template has two sections:
- **`# Abbreviation`** — placeholder reference table (for extraction guidance only; do NOT copy into output)
- **`# Setup instructions`** — the actual output format; the output file starts here

**Steps**:

1. **Discover and read all relevant documents** (skip missing files silently):
   - `$WORKSPACE_ROOT/<project>/CLAUDE.md`
   - `$WORKSPACE_ROOT/<project>/README.md`
   - `$WORKSPACE_ROOT/<project>/docs/SETUP.md`
   - `$WORKSPACE_ROOT/<project>/docs/SCons.md`
   - Any other `.md` files under `$WORKSPACE_ROOT/<project>/docs/` relevant to building, testing, or running the project
   - Any `dev.sh`, `build.sh`, `Makefile`, or similar that expose build/test commands

2. **Preserve existing free-form notes** (if file already exists):
   - Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
   - Extract only `## Others` sub-section content → `<existing_others>`.
   - `## Unit test framework` and `## Integration test framework` are always re-generated.

3. **Extract values** from documents read in step 1. Write `(unknown)` for anything not found.

   | Placeholder | Meaning |
   |---|---|
   | `<git_clone_cmd>` | git command to clone project source code |
   | `<compile_cmd>` | bash command to compile source code |
   | `<unit_tests_all>` | bash command to run all unit tests at once |
   | `<unit_tests_file>` | bash command to run a specific unit test file |
   | `<itest_all>` | bash command to run all integration tests at once |
   | `<itest_file>` | bash command to run a particular integration test |
   | `<lint_all>` | bash command to run lint on all files |
   | `<lint_file>` | bash command to run lint on a specific file |
   | `<other_tests>` | any other test/validation commands not covered above |
   | `<unit_test_framework>` | framework name, file naming pattern/location, registration step |
   | `<itest_framework>` | framework name, file naming pattern/location, required environment |

4. **Write** `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md`.
   - `# Setup instructions` block must exactly follow the template — same headings, bash block structure, `cd <project>` / `cd ../` lines.
   - `# Technical note` must contain: `## Unit test framework (if any)`, `## Integration test framework (if any)`, `## Others` (restore `<existing_others>` verbatim).

5. **Report** which placeholders were filled, which were left as `(unknown)`, and whether `## Others` was preserved.
