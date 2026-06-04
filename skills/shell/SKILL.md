---
name: shell
description: >
  Write, review, and refactor shell scripts following best practices for this project.
  Use this skill whenever the user asks to write, edit, fix, review, or refactor any shell
  script (.sh files), asks about bash patterns or idioms, wants a new script or function
  implemented, or is debugging a shell script in this codebase. Also trigger when the user
  asks about argument parsing, error handling, Docker invocation patterns, or CI scripting
  in shell.
---

You are writing Bash following shellcheck-clean practices and defensive scripting conventions.
The goal is robust, readable scripts that survive errors, handle edge cases, and pass shellcheck with zero warnings.

> **Before writing any code**, check the project's `# Technical note` in `<project>_must_read.md` for project-specific scripting conventions, logging helpers, and linting scope. Use the lint command from the project's `<project>_must_read.md` — never invoke shellcheck directly.

## Every Script Must Start With

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
```

- `set -e`: exit immediately on any error — don't silently continue after failures.
- `set -u`: treat unset variables as errors — catches typos in variable names.
- `set -o pipefail`: a pipe fails if any command in it fails, not just the last.
- `SCRIPT_DIR`: always resolve the repo root relative to `BASH_SOURCE[0]`, not `$0` or `pwd` — scripts may be sourced or called from any directory.

Adjust the `/../..` depth to match the script's location in the repo.

## Variable and String Safety

- Quote every variable expansion: `"${var}"`, `"${array[@]}"`. Unquoted expansions split on whitespace and glob-expand — both are usually bugs.
- Use `${var:-default}` for optional variables with defaults; use `${var:?error message}` to fail fast on required-but-missing variables.
- Prefer `[[ ... ]]` over `[ ... ]` for conditionals — `[[` is safer (no word-splitting, supports `=~`, `&&`/`||`).
- Prefer `$(command)` over backticks — cleaner nesting and quoting.
- Use `local` for all variables inside functions — avoids polluting the global scope.

```bash
# good
local output
output="$(some_command "${arg}")"

# bad
output=`some_command $arg`
```

## Error Handling and Cleanup

Use `trap` to clean up on exit — don't rely on the happy path:

```bash
container_name="build_$$"
cleanup() { docker stop "${container_name}" 2>/dev/null || true; }
trap cleanup EXIT
```

- Suppress expected errors with `2>/dev/null || true` (e.g., stopping a container that may not exist).
- Use `|| true` only when failure is genuinely acceptable — not as a blanket error suppressor.
- Always handle the case where external commands are missing (`command -v tool || { echo "tool not found"; exit 1; }`) when the script can't proceed without them.

## Argument Parsing

Use `while [[ $# -gt 0 ]]; do case "$1" in ... esac; done` for flag parsing — it handles combined flags, positional args, and unknown flags cleanly:

```bash
debug=false
paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)    debug=true; shift ;;
    --help|-h)  _show_help; exit 0 ;;
    --*)        echo "Unknown flag: $1" >&2; exit 1 ;;
    *)          paths+=("$1"); shift ;;
  esac
done
```

Always handle `--help`/`-h`. Always error on unknown flags with a usage hint.

## Help Text

Use a heredoc so help text stays readable and doesn't require escaping:

```bash
_show_help() {
  cat << 'EOF'
Usage: script.sh [--flag] <arg>

Commands:
    --flag    What this flag does

Examples:
    script.sh --flag value
EOF
}
```

Single-quote the heredoc delimiter (`<< 'EOF'`) to prevent variable expansion inside help text.

## Functions

- Prefix internal/private functions with `_` (e.g., `_init_vars`, `_show_help`).
- Use `local` for every variable declared inside a function.
- Keep functions focused — one logical operation per function.
- Name functions with verbs: `_run_build`, `_clean_artifacts`, `_parse_args`.

## Command Dispatch (multi-subcommand scripts)

Use a `case` at the bottom of the script to dispatch subcommands — keeps the main flow readable:

```bash
case "${1:-}" in
  build)    shift; _cmd_build "$@" ;;
  clean)    shift; _cmd_clean "$@" ;;
  --help|-h) _show_help; exit 0 ;;
  *) echo "ERROR: unknown command '${1:-}'" >&2; exit 1 ;;
esac
```

Shift before calling the handler so the handler receives only its own arguments.

## Sourcing Other Scripts

When sourcing a file, add a shellcheck directive so shellcheck can follow it:

```bash
# shellcheck source=path/to/sourced_script.sh
source "${SCRIPT_DIR}/path/to/sourced_script.sh"
```

The path in the directive must be relative to the repo root (matching your `.shellcheckrc` `source-path` setting).

## Arrays

Use arrays for lists of arguments — never build command strings as a single variable:

```bash
# good — each element is a separate word
targets=("file1.sh" "file2.sh")
shellcheck "${targets[@]}"

# bad — breaks on spaces, glob-expands
targets="file1.sh file2.sh"
shellcheck $targets
```

Iterate with `for item in "${array[@]}"; do` — note the double quotes and `[@]`.

## Shellcheck Suppressions

Only suppress a shellcheck warning when you understand why it fires and are certain it's a false positive. Add an inline comment explaining why:

```bash
# SC2034: var is passed by name via nameref
# shellcheck disable=SC2034
local my_var=("${cmd}")
```

Never add a blanket disable at the top of the file.

## Logging

If the project defines logging helpers (check the Technical note in `<project>_must_read.md`), use them instead of raw `echo`. Otherwise:
- Informational output → `echo "..." ` to stdout
- Errors and warnings → `echo "ERROR: ..." >&2`

## Portability

- Target **bash** (not sh) — the shebang is `#!/usr/bin/env bash`.
- Don't rely on GNU-only flags without checking — scripts may run on macOS (dev machines) and Linux (CI/device).
- Use `command -v` instead of `which` for checking tool availability.

## What to Avoid

- `set -e` without `|| true` on commands that are expected to fail — combine both correctly.
- Unquoted `$variables` anywhere — always `"${var}"`.
- `[ ... ]` — use `[[ ... ]]`.
- Backticks — use `$(...)`.
- `cd` without checking success — prefer constructing full paths with `SCRIPT_DIR`.
- Hardcoded paths — derive everything from `SCRIPT_DIR`.
- `echo` for errors without redirecting to stderr — always use `>&2`.

## Before Finishing Any Shell Task

1. Script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
2. `SCRIPT_DIR` derived from `BASH_SOURCE[0]`, not `$0` or `pwd`.
3. All variables quoted: `"${var}"`, `"${array[@]}"`.
4. `trap cleanup EXIT` for any resource that needs cleanup.
5. `--help`/`-h` handled; unknown flags exit with a usage message.
6. All sourced files have `# shellcheck source=` directives.
