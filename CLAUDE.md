# Claude Workflow

This repo contains a multi-project Claude Code workflow for GitLab-based development.

## How to use

Include this workflow in any project by adding to that project's CLAUDE.md:

```
@path/to/claude_workflow/workflow.md
```

## Workflow overview

See `workflow.md` for the full phase-by-phase workflow (Planning → Planning Review → Coding → Write Tests → Code QA → Review).

## Instructions

- `instructions/planning.md` — Planning phase
- `instructions/coding.md` — Coding phase (selects model by complexity)
- `instructions/testing.md` — Test writing phase
- `instructions/lint.md` — Lint/QA phase
- `instructions/review.md` — Code review phase (MR or local)
- `instructions/gitlab.md` — GitLab tool conventions and input format

## Skills

- `skills/cpp/SKILL.md` — C++20 coding standards
- `skills/python/SKILL.md` — Python coding standards
- `skills/shell/SKILL.md` — Bash scripting standards

## Tools

All GitLab interaction tools live in `tools/gitlab/`. Credentials are read from a `.env`
file three levels above this repo (next to the project being worked on). Required variable: `GL_TOKEN`.
