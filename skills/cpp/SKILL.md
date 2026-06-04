---
name: cpp
description: >
  Write, review, and refactor C++ code following C++20 Core Guidelines for this project.
  Use this skill whenever the user asks to write, edit, fix, review, or refactor any C++ code
  (.cc, .h, .cpp files), asks about C++ design decisions, wants a new class or function
  implemented, or is debugging C++ in this codebase. Also trigger when the user asks about
  resource management, smart pointers, concurrency primitives, or type safety in C++.
---

You are writing C++ following C++20 and the [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines).
The goal is safe, readable code — not pedantic rule-following. When rules conflict, prefer the one that makes the code safer and easier to reason about.

> **Before writing any code**, check the project's `# Technical note` in `<project>_must_read.md` for project-specific compiler flags, style overrides, and constraints. Those take precedence over the defaults below.

## Resource Management

Manage every resource through RAII — if you acquire something (memory, file handle, lock, socket), ownership must live in a destructor. Use `std::unique_ptr` / `std::shared_ptr` for owned heap objects; use `std::make_unique` / `std::make_shared` so allocation and ownership transfer are atomic. Raw `T*` signals "non-owning borrow" only. Never call `malloc`/`free`; avoid explicit `new`/`delete` outside of a managing class. Prefer stack allocation — heap only when lifetime or size genuinely requires it.

## Type Safety

Avoid `void*`; express intent through strong types, `std::variant`, `std::optional`, or templates. No C-style casts — use `static_cast`, `std::bit_cast`, or `reinterpret_cast` (the last sparingly, with a comment). Never cast away `const`. Prefer `enum class` over plain `enum` to prevent implicit integer conversions.

## Bounds Safety

Use `std::array` or `std::vector` over raw arrays. Pass contiguous views as `std::span` rather than pointer + size. Keep pointer arithmetic local and simple; prefer range-for and `<algorithm>` / `<ranges>` instead.

## Error Handling

Use RAII so error paths can't leak. Return `std::optional<T>` for functions that may legitimately produce nothing. Throw exceptions only for truly exceptional conditions (not routine control flow). Let exceptions propagate to a handler that has enough context to deal with them — don't catch-and-ignore at every call site.

## Function Design

One function, one logical operation. For parameter passing:
- Cheap-to-copy types (ints, pointers, `std::string_view`) → pass by value
- Larger types you won't modify → `const T&`
- In-out parameters → `T&`
- Consume/move semantics → `T&&` + `std::move` at the call site
- Never return `T&&` — dangling reference.

Mark functions `[[nodiscard]]` when ignoring the return value is almost certainly a bug.

## Class Design

Use `class` when there's an invariant to enforce; `struct` for plain aggregates. Let the compiler generate default operations whenever possible — only define them when you genuinely need custom behaviour. If you define any of copy-ctor, copy-assign, move-ctor, move-assign, or destructor — define or `=delete` all five (Rule of Five). Prefer in-class member initializers over constructor member-init lists for simple defaults. Expose meaningful abstractions, not raw getters/setters for every member.

## Concurrency

Assume multi-threaded context. Never call `lock()`/`unlock()` directly — use `std::lock_guard` or `std::unique_lock`. Don't call unknown code while holding a lock. Always pass a predicate to `std::condition_variable::wait`. Use `std::atomic<T>` for simple shared state; don't use `volatile` for synchronization.

## Modern C++20 Features — prefer these

- **Concepts** (`concept` / `requires`) over SFINAE for template constraints
- **`std::span`** over raw pointer + size pairs
- **`std::ranges::`** algorithms over raw iterator pairs
- **Designated initializers** for aggregate clarity
- **`[[nodiscard]]`**, **`[[likely]]`/`[[unlikely]]`** where appropriate
- **`std::format`** (when available) over `sprintf` or manual concatenation
- **`constexpr`** / `inline constexpr` instead of `#define` for constants

## Naming and Style

Default: Google C++ style — `snake_case` for variables and functions, `PascalCase` for types and classes. Class member declaration order: type aliases → constructors → assignment → destructor → public methods → private methods → data members.

Check the project's Technical note for any naming overrides (e.g. member variable suffix, brace style, clang-format config location).

## Things to Avoid

- `goto` (only acceptable in C-interop cleanup — add a comment explaining why)
- Global mutable state — use dependency injection or carefully scoped singletons
- `#define` for constants
- Unsigned arithmetic for general math (wrap-around bugs are subtle)
- `std::endl` — use `'\n'` to avoid unnecessary flushes

## Before Finishing Any C++ Task

1. No raw owning pointers — all resources in RAII handles.
2. No C-style casts.
3. No `#define` constants.
4. Concurrency: locks only via `std::lock_guard` / `std::unique_lock`.
