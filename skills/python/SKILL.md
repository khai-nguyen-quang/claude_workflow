---
name: python
description: >
  Write, review, and refactor Python code following Python Core Guidelines for this project.
  Use this skill whenever the user asks to write, edit, fix, review, or refactor any Python
  code (.py files), asks about Python design decisions, wants a new class or function
  implemented, or is debugging Python in this codebase. Also trigger when the user asks about
  type annotations, error handling patterns, testing with pytest, or code style in Python.
---

You are writing Python following PEP 8, PEP 20, and the project's conventions.
The goal is clear, safe, maintainable code that passes all linting checks before commit.

> **Before writing any code**, check the project's `# Technical note` in `<project>_must_read.md` for project-specific linter configuration, test commands, naming conventions, and any framework-specific patterns. Those take precedence over the defaults below. Use the lint and test commands from the project's `<project>_must_read.md` — never invoke linters or test runners directly by name.

## Style and Formatting

- Line length: **120 characters** (default — check Technical note for overrides)
- Indentation: **4 spaces**
- Naming: `snake_case` for functions, methods, variables, modules; `PascalCase` for classes; `UPPER_CASE` for module-level constants
- Imports: sorted by isort rules — stdlib → third-party → first-party, with a blank line between groups. No wildcard imports (`from x import *`).
- Prefer f-strings over `%` formatting or `.format()` (ruff FLY rule enforces this).
- No trailing `print()` statements in production code (T20); use `logging` instead.
- No commented-out code (ERA rule) — delete it or use a TODO comment.

## Type Annotations

Annotate all function signatures (parameters and return types). Use the built-in generics (`list[int]`, `dict[str, int]`, `tuple[int, ...]`) — not `typing.List`, `typing.Dict` (pyupgrade UP rule). Use `typing.Optional[T]` or `T | None` (prefer `T | None` in Python 3.10+). Use `typing.Protocol` for structural subtyping rather than ABCs where duck typing fits better.

```python
def parse_frame(data: bytes, width: int, height: int) -> FrameHeader | None:
    ...
```

## Error Handling

- Catch specific exceptions, not bare `except:` or `except Exception:`.
- Don't swallow exceptions silently — at minimum log them.
- Use `contextlib.suppress(ExceptionType)` for intentional suppress-and-continue patterns.
- Raise meaningful exception types; include context in the message (TRY rule).
- Don't use exceptions for normal control flow.

```python
try:
    value = config["key"]
except KeyError as e:
    raise RuntimeError(f"Missing required config key: {e}") from e
```

## Functions and Methods

- Max **5 arguments** (pylint `max-args`). If you need more, group related args into a dataclass or named tuple.
- Max **50 statements** and **12 branches** per function (pylint limits). Split long functions into focused helpers.
- Max **6 return paths** per function. Flatten early-return patterns rather than deep nesting.
- Mark functions that return a value the caller must not ignore with appropriate patterns (consider `@property` or raising on misuse).
- Avoid unused arguments — if a parameter is required by a signature but unused, name it `_` or `_name`.

## Classes

- Use `@dataclass` or `@dataclass(frozen=True)` for plain data containers — avoids boilerplate `__init__`.
- Prefer `__slots__` on classes that will be instantiated many times (SLOT rule).
- Class names: `PascalCase`. Keep class hierarchies shallow.
- Don't access protected members (`_attr`) of other classes (SLF rule) — respect encapsulation.
- Max **7 attributes** and **20 public methods** per class (pylint limits). Split large classes.

## Imports

- Absolute imports only — no relative imports (`from . import x`).
- First-party package list is project-specific — check `ruff.toml` or the Technical note.
- No unused imports — ruff F401 will flag them.
- In `__init__.py`, unused re-exports are allowed (F401 ignored there).

## File I/O and Paths

Use `pathlib.Path` over `os.path` — ruff PTH rule enforces this.

```python
# good
from pathlib import Path
config_path = Path("/data/params") / "key"
data = config_path.read_bytes()

# bad
import os
data = open(os.path.join("/data/params", "key"), "rb").read()
```

## Datetimes

Always use timezone-aware datetimes (DTZ rule). Pass `tz=` explicitly:

```python
from datetime import datetime, timezone
now = datetime.now(tz=timezone.utc)
```

## Performance

- Prefer list/dict/set comprehensions over `map()`/`filter()` with `lambda` (C4 rule).
- Avoid repeated attribute lookups in tight loops — cache with a local variable.
- PERF rules flag common anti-patterns (e.g., `list()` called on a comprehension that could be a generator).

## Testing (pytest)

- Use `pytest` fixtures, not `setUp`/`tearDown`.
- Don't use `print()` in tests — use `capfd` fixture or logging.
- Don't hardcode magic numbers without naming them (PLR2004 — allowed in test files but still a smell).
- Test file naming conventions and mock infrastructure locations are project-specific — check the Technical note.

## What to Avoid

- `global` statements — pass state explicitly or use a class.
- Mutable default arguments (`def f(x=[])`) — use `None` sentinel and assign inside.
- Shadowing builtins (`list`, `id`, `type`, `input` — ruff A rule).
- Implicit string concatenation across lines (ISC rule) — use explicit `+` or parentheses.
- `os.path` — use `pathlib.Path` instead.

## Before Finishing Any Python Task

1. No bare `except:` — catch specific exceptions.
2. All functions have type annotations.
3. No `print()` in production code — use `logging`.
4. Imports sorted, no unused imports.
5. `pathlib.Path` used for all file paths.
