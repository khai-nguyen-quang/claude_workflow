# Introduction

This repository defines a workflow for Claude that works across multiple projects.

When a user invokes `claude` from any project (e.g. `cd workspace/<project> && claude`), Claude automatically imports `claude_workflow/` and uses it when the user runs the `/wf` command.

The workflow is designed to resume reliably after context compaction.

The workflow spawns subagents, passing appropriate context to perform heavy tasks (planning, coding, review, fix review, debug).

The workflow supports the following phases:
```
  planning      Phase 1 — brainstorm + design document
  plan-review   Phase 2 — review design docs for conflicts
  coding        Phase 3 — implement the approved design
  test          Phase 4 — write unit and integration tests
  lint          Phase 5 — fix lint / code quality violations
  review        Phase 6 — review code or a GitLab MR
  fix_review    Phase 7 — fix review comments (online MR or offline file)
  collect       Utility — collect project context into a must-read file
  debug         Utility — investigate a bug, produce root cause analysis
```
After completing a phase, the workflow stores its state so the user can continue to the next phase without re-running previous phases.


##  Multi-project folder structure

`claude_workflow/` is placed at the same level as other projects (e.g. `projectA`, `projectB`, `projectX`).

Following is the **recommended** folder tree.

```
workspace/
├── claude_workflow
│   ├── .env                  ← credentials and instance config go here
│   ├── CLAUDE.md
│   ├── instructions
│   ├── projects
│   ├── README.md
│   ├── skills
│   ├── tools
│   └── template/workflow.md
├── projectA
│   ├── CLAUDE.md
├── projectB
│   ├── CLAUDE.md
├── projectX
│   ├── CLAUDE.md
├── projectX-worktree         ← one checkout per ticket, created automatically
│   ├── projectX-123          ← issue #123
│   └── projectX-mr-177       ← MR !177
```
>
> <span style="color:red">Content of `claude_workflow/.env` (see `.env_template` for reference):</span>
> ```
> GL_USERNAME=khai.nguyen
> GL_TOKEN=glpat-xxxxxxxxxxxx
> GL_URL=https://gitlab.mycompany.com
> GL_NAMESPACE=mygroup/mysubgroup
> ```
> `claude_workflow/.env` is git-ignored and never committed.

> <span style="color:red">**Setup with one-off command**</span>
> ```
> cd ~/workspace/claude_workflow
> ./setup.sh
> ```

##  Project-specific context

`claude_workflow/` allows users to provide project-specific context via the `projects/<project>_must_read.md` file.

### Project context file

`projects/<project>_must_read.md` has two parts:

- **Generated**: Claude reads `<project>/README.md` and other relevant documents to extract commands for:
   - cloning and compiling source code
   - running unit tests, integration tests, and lint

- **Custom**: The `# Technical note` section where engineers can add project-specific information for Claude.


### How to generate a project context file
```bash
# Go to the project directory
cd <project>
# Launch Claude Code
claude
# Collect project-specific context
/wf collect <project>

# Open projects/<project>_must_read.md
# Add any additional information under the # Technical note section
```

## Parallel tickets

Each ticket is worked on in **its own git worktree**, so several tickets can progress at the same
time in separate Claude sessions without sharing a branch or a build directory.

The workflow creates the worktree itself: any `/wf <phase> <ref>` with a `#` in `<ref>` first runs
`tools/git/worktree.sh ensure <ref>`, which creates
`<project>-worktree/<slug>` on the ticket's branch (an issue gets `feature/<title-slug>-<id>`, an
MR gets its source branch), initialises submodules, and hard-links the gitignored build assets
listed in `projects/<project>_worktree.conf`. It is idempotent, so later phases reuse the same
worktree. Nothing is ever removed automatically.

To run three tickets in parallel, open one Claude session per ticket — from anywhere, since the
phases `cd` into the resolved worktree themselves:

```bash
claude   # session 1 → /wf coding projectX#387
claude   # session 2 → /wf coding projectX#508
claude   # session 3 → /wf review projectX#MR!123
```

Manual management, when needed:

```bash
tools/git/worktree.sh list                # what exists
tools/git/worktree.sh path projectX#387   # where a ticket lives
tools/git/worktree.sh remove projectX#387 # drop the checkout, keep the branch
```

Rules that keep parallel sessions safe:

- The main checkout `workspace/<project>` is never used for ticket work — leave it on the default branch.
- Never run two phases for the same ticket at once; a worktree has a single writer.
- Workflow artifacts stay in `claude_workflow/.tmp/<slug>/`, which is per-ticket and shared across sessions.

To add a project's carried assets, copy `projects/template_worktree.conf` to
`projects/<project>_worktree.conf` and list the gitignored paths a fresh checkout needs (model
files, vendored sources). Never list build output directories — each worktree must build its own.

## Unattended cycle

`tools/auto/run_cycle.sh` is **stage flags + refs**: the flags say what to run, the refs say what
to run it on. There is no default — a run with no stage flag prints the usage and exits.

```bash
tools/auto/run_cycle.sh --design 'projectX#123' 'projectX#456'
tools/auto/run_cycle.sh --code   'projectX#123' 'projectX#456'
tools/auto/run_cycle.sh --verify 'projectX#123'
tools/auto/run_cycle.sh --design --code --verify 'projectX#309'   # the whole cycle
tools/auto/run_cycle.sh --research --doc 'projectX#412'           # a research ticket
tools/auto/run_cycle.sh --review --fix_review 'projectX#MR!123' 'projectX#MR!456'
```

`--research`/`--design`/`--code`/`--verify`/`--doc` take issue refs and combine, always running in
that order. `--research` handles a ticket whose description starts with `research::` — brainstorming
alone, no design document and no code — and `--doc` writes whatever `--research` or `--design`
produced up as a document under the repo's `docs/`, committed on the branch.
`--review`/`--fix_review` take MR refs. The two sets cannot be mixed in one command. Every stage
takes **any number of refs**: each gets its own worktree and its own window, and they all run at
once (`--serial` for one at a time). One ref failing does not stop the others.

`create_mr` is deliberately excluded. It ends in a human gate — the push and create confirmations
— and a driver that answers that gate itself removes the review instead of automating it. `--code`
refuses to start without an approved `_design.md`, and `--verify` finishes by telling you to run
`/wf create_mr` yourself.

**After each phase the driver runs the objective check itself** and refuses to advance until it
passes. A phase reporting success is not evidence:

| Phase | Gate |
|-------|------|
| coding | project build |
| test | test run, **plus proof that tests actually executed** |
| lint | lint for each language the branch touches (never `--all`) |
| review | a fresh review report carrying a production-readiness verdict |
| doc | a fresh record naming a `Document:` that exists in the worktree |

The test gate matters most. Build caches are shared between worktrees, so a test run can exit 0
having restored every result from cache and executed nothing. The driver reads the summary
counts, and when everything was cached it re-runs the test binaries for the changed modules
directly rather than advancing.

On a gate failure the driver resumes **the same session** with the real output and asks for a
fix, up to `--max-repair` times (default 2), with an explicit instruction not to weaken tests or
narrow lint scope to get green. After that it stops and leaves the logs in `.tmp/<slug>/cycle/`.
Re-running a stage is how you resume: name the stage you want.

Several tickets at once is one command — cap the job count so the builds do not thrash:

```bash
tools/auto/run_cycle.sh --code 'projectX#387' 'projectX#508' 'projectX#389' \
  --jobs $(( $(nproc) / 3 ))
```

Never automate a phase that starts the project's live/hardware processes: those containers share
the host IPC namespace, and a second one hijacks the first's publishers.

## Usage

After the setup above, users can use the workflow as follows.

```bash
# Go to the project directory
cd <project>
# Launch Claude Code
claude
```

### Work on a task

```bash
# Plan for ticket #123 in projectX
/wf planning projectX#123

# Review the design
/wf plan-review projectX#123

# Implement the design
/wf coding projectX#123

# Review the code
/wf review projectX#123

# Fix review comments
/wf fix_review projectX#123

# Fix static analysis issues
/wf lint projectX#123

# Run tests
/wf test projectX#123
```

### Review an MR
Run the following command to review an MR:
```bash
/wf review projectX#MR!123
```

### Fix review comments from an MR
To resolve review comments from an MR, run:
```bash
/wf fix_review projectX#MR!123
```
