# Instructions

Fix lint violations using the appropriate language skill for each language. This serves a **GitLab issue** and a **free-form** run identically — it operates on the working-tree changes and uses the forwarded `## Setup commands`, so it needs no GitLab ref or per-run slug. (`<project>` may be `(unknown)` for a free-form slug; rely on the forwarded blocks, and fall back to `CLAUDE.md`/`README.md` only when `<project>` resolves.)

## Step 1 — Load project context and lint commands

From the `## Setup commands` block the skill forwarded in your task context (do not read the
must_read file yourself), extract:
- `<lint_all>` — command to lint all files
- `<lint_file>` — command to lint a specific file

Apply any guidance from the forwarded `## Technical note` block throughout this phase.
If a forwarded block is `(not available)`, fall back to the project's `CLAUDE.md` or `README.md` for lint commands.

## Step 2 — Determine scope

Read the arguments the user passed with the command:

| Argument | Run |
|----------|-----|
| `--cpp` | C++ only |
| `--python` | Python only |
| `--shell` | Shell only |
| *(none)* | All three |

## Step 3 — Run lint to collect violations

Use the commands extracted in Step 1:
- To lint all files: use `<lint_all>`
- To lint a specific file: use `<lint_file>`

Run only the commands for the selected scope and capture their output in full.
If a command exits 0 with no output, that language is already clean — skip it.

## Step 4 — Fix each language using its skill

For every language that reported violations, invoke its skill with the full lint output as context. Work one language at a time.

- **C++ violations** → load `$WORKSPACE_ROOT/claude_workflow/skills/cpp/SKILL.md` and fix only the files and lines flagged.
- **Python violations** → load `$WORKSPACE_ROOT/claude_workflow/skills/python/SKILL.md` and fix only the files and lines flagged.
- **Shell violations** → load `$WORKSPACE_ROOT/claude_workflow/skills/shell/SKILL.md` and fix only the files and lines flagged.

Fix only what the tool reported. Do not reformat or refactor code that was not flagged.

## Step 5 — Verify

Re-run the same lint commands from Step 3.

- All pass → report a one-line summary per language (files fixed, violation count).
- Some still fail → fix remaining issues (repeat Step 4 for the still-failing files) and verify again. Stop after three rounds; if violations persist, report what remains and why.
