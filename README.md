# Introduction

This repository defines a workflow for Claude that works across multiple projects.

When a user invokes `claude` from any project (e.g. `cd workspace/<project> && claude`), Claude automatically imports `claude_workflow/` and uses it when the user runs the `/wf` command.

The workflow is designed to resume reliably after context compaction.

The workflow spawns subagents, passing appropriate context to perform heavy tasks (planning, coding, review, fix review, debug).

The workflow supports the following phases:
```
  planning      Phase 1 — strategy + design document
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
