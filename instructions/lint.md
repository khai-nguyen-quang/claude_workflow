# Instructions

Fix lint violations using the appropriate language skill for each language.

## Step 1 — Load project context and lint commands

Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` and extract:
- `<lint_all>` — command to lint all files
- `<lint_file>` — command to lint a specific file

Apply any guidance from the `# Technical note` section throughout this phase.
If the file does not exist, fall back to the project's `CLAUDE.md` or `README.md` for lint commands.

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
