# claude_workflow

A phase-based development workflow for Claude Code that works across many projects and across
**both GitLab and GitHub**.

Run `claude` from any project next to this repo, and two commands become available:

- **`/wf`** — one ticket, one phase at a time: plan → code → test → lint → review → fix review.
- **`/wf-epic`** — one epic, split into tickets, then implemented by a team of agents.

Each phase spawns subagents with the context they need, and writes its state to disk so the next
phase resumes cleanly — including after a context compaction.

## Phases

```
/wf <phase> <ref>
  planning      Phase 1 — strategy + design document        [wf-planner]
  plan-review   Phase 2 — review design docs for conflicts
  coding        Phase 3 — implement the approved design     [wf-coder]
  test          Phase 4 — write unit and integration tests
  lint          Phase 5 — fix lint / code quality violations
  review        Phase 6 — review code, an MR, or a PR       [wf-reviewer]
  fix_review    Phase 7 — fix review comments               [wf-coder]
  collect       Utility — collect project context into a must-read file
  debug         Utility — investigate a bug, produce root cause analysis [wf-debugger]

/wf-epic <phase> <epic-ref>
  research        Phase 1 — 3 research lenses + a consolidator   -> _strategy.md
  design          Phase 2 — draft/review/fix loop, max 3 rounds  -> _design.md
  split           Phase 3 — reconcile existing + new tickets     (you confirm)
  implementation  Phase 4 — agent team, streams every ticket     -> MRs / PRs
  status          Show the implementation queue
```

## Install

### 1. Folder layout

`claude_workflow/` sits at the same level as the projects it serves:

```
workspace/
├── claude_workflow/
│   ├── .env                    ← credentials (git-ignored, never committed)
│   ├── setup.sh
│   ├── tools/{forge,github,gitlab,git}/
│   ├── projects/               ← per-project context files
│   └── wf_epic/
├── projectA/         CLAUDE.md
├── dash-cam/         CLAUDE.md
└── dash-cam-worktree/          ← one checkout per ticket, created automatically
    ├── dash-cam-12
    └── dash-cam-pr-45
```

### 2. Credentials

```bash
cp .env_template .env
$EDITOR .env
```

Configure only the forge you use — the workflow tolerates the other being absent entirely.

| Variable | Forge | Required | Description |
|----------|-------|----------|-------------|
| `GL_TOKEN` | GitLab | yes | personal access token |
| `GL_URL` | GitLab | yes | instance base URL, e.g. `https://gitlab.company.com` |
| `GL_NAMESPACE` | GitLab | yes | group prefixed to short refs, e.g. `mygroup/mysubgroup` |
| `GL_USERNAME` | GitLab | no | reference only |
| `GH_FINEGRAINED_TOKEN` | GitHub | one of the two | fine-grained token; **preferred** when both are set |
| `GH_TOKEN` | GitHub | one of the two | classic token; used as the fallback |
| `GH_USERNAME` | GitHub | no | reference only |

A **fine-grained** GitHub token lists its repositories explicitly. For each repo the workflow
needs **Issues: Read & write** (sub-issues live here), **Contents: Read & write**,
**Pull requests: Read & write**, **Metadata: Read**.

> A 404 on a repo you can clone over SSH means the token's repository access does not include it.
> SSH keys and token scopes are independent. A fine-grained token scoped to **"Public
> repositories"** cannot see a private repo at all — it must be listed under **"Only select
> repositories"**.

### 3. Run setup

```bash
cd ~/workspace/claude_workflow
./setup.sh
```

It is idempotent — re-run it any time. It:

- symlinks the `wf` and `wf-epic` skills into `~/.claude/skills/`
- symlinks all six agents into `~/.claude/agents/`
- merges permissions and the epic engine's hooks into `~/.claude/settings.json`, rewriting the
  hook paths for your machine
- registers the two `UserPromptSubmit` hooks (sticky `/wf` mode, and the active-state injector)
- registers every sibling git repository (see below)
- creates `.tmp/`

| Flag | Effect |
|------|--------|
| `--no-epic` | Skip `/wf-epic`. Its settings turn on agent teams and tmux teammate mode **globally**, for every Claude session on the machine. |
| `--no-projects` | Skip sibling repository registration. |

Verify a forge afterwards:

```bash
tools/github/verify_access.sh --repo khai-nguyen-quang/dash-cam
tools/gitlab/verify_access.sh --project projectX
```

### 4. Project registration

`setup.sh` scans for sibling git repositories and, for each one, creates whatever is missing:

- `projects/<name>_must_read.md` — the project context file
- `projects/<name>_worktree.conf` — gitignored assets to carry into each ticket worktree
- `<repo>/CLAUDE.md` — importing `@../claude_workflow/template/workflow.md`

**It never edits a file that already exists.** A repository with its own `CLAUDE.md` is reported,
not modified — add the import line yourself:

```markdown
@../claude_workflow/template/workflow.md
```

Then fill in the project context, which is what tells Claude how to build and test:

```bash
cd <project> && claude
/wf collect <project>          # generates projects/<project>_must_read.md
```

Open that file and add anything non-obvious under `# Technical note`. `/wf-epic` is its only
reader, and it forwards the note into every agent prompt.

## Ref formats

The forge is decided from the shape of the ref, by `tools/forge/resolve.sh`.

| Ref | Resolves to |
|-----|-------------|
| `projectX#309` | GitLab issue 309 |
| `projectX#MR!177` | GitLab MR 177 |
| `group/sub/projectX#309` | GitLab, full namespace path |
| `Epic#60` | GitLab group epic 60 |
| `khai-nguyen-quang/dash-cam#12` | **GitHub** issue 12 |
| `khai-nguyen-quang/dash-cam#PR!45` | **GitHub** pull request 45 |
| any full URL | whichever host it names |

**A ref with no `/` is GitLab.** A GitHub ref always carries `owner/repo`. Two path segments mean
GitHub unless the path starts with your `GL_NAMESPACE`; three or more mean GitLab.

`tools/forge/test_resolve.sh` is the table test for all of this — run it if you change the rules.

## Using `/wf`

```bash
cd <project> && claude
```

### Work a ticket

```bash
# GitLab                                  # GitHub
/wf planning    projectX#123              /wf planning    khai-nguyen-quang/dash-cam#12
/wf plan-review projectX#123              /wf plan-review khai-nguyen-quang/dash-cam#12
/wf coding      projectX#123              /wf coding      khai-nguyen-quang/dash-cam#12
/wf test        projectX#123              /wf test        khai-nguyen-quang/dash-cam#12
/wf lint        projectX#123              /wf lint        khai-nguyen-quang/dash-cam#12
/wf review      projectX#123              /wf review      khai-nguyen-quang/dash-cam#12
```

The phases are identical on both forges. Only the ref changes.

### Review an MR or PR

```bash
/wf review     projectX#MR!123
/wf review     khai-nguyen-quang/dash-cam#PR!45
```

### Fix review comments

```bash
/wf fix_review projectX#MR!123
/wf fix_review khai-nguyen-quang/dash-cam#PR!45
```

On GitHub this replies to each review thread and resolves the ones whose fix landed. Resolving a
thread is a GraphQL-only operation, so thread ids are GraphQL node ids — `reply_and_resolve.py
<ref> --list` prints them.

### Other utilities

```bash
/wf collect projectX               # regenerate the project context file
/wf debug   projectX#123           # root-cause a bug from a ticket
/wf debug   fcw_not_alert          # or from a free-form slug, described in your prompt
```

## Using `/wf-epic`

An epic is a large piece of work that becomes many tickets.

- **GitLab** — epics are group-level objects: `Epic#60`.
- **GitHub** — there is no epic object. The epic **is an ordinary issue**, and its children are
  native **sub-issues**: `khai-nguyen-quang/dash-cam#1`.

```bash
# GitLab                                   # GitHub
/wf-epic research       Epic#60            /wf-epic research       khai-nguyen-quang/dash-cam#1
/wf-epic design         Epic#60            /wf-epic design         khai-nguyen-quang/dash-cam#1
/wf-epic split          Epic#60            /wf-epic split          khai-nguyen-quang/dash-cam#1
/wf-epic implementation Epic#60            /wf-epic implementation khai-nguyen-quang/dash-cam#1
/wf-epic status         Epic#60            /wf-epic status         khai-nguyen-quang/dash-cam#1
```

Phases 1–3 write documents into `.tmp/<epic-slug>/` and create tickets. Phase 4 runs an agent
team that streams every ticket through code → review → fix.

Guardrails that are not negotiable:

- **No ticket is ever created without your explicit confirmation** (phase 3 shows you every one).
- **Nothing is ever pushed without your explicit confirmation.**
- A phase whose input artifact is missing refuses to start and tells you which phase produces it.
- Phase 4 needs an **interactive** session: `claude -p` silently downgrades teammates to ordinary
  subagents, and you get no team at all.

## Parallel tickets

Each ticket works in **its own git worktree**, so several can progress at once in separate Claude
sessions without sharing a branch or a build directory.

Any `/wf <phase> <ref>` with a `#` in the ref first runs `tools/git/worktree.sh ensure <ref>`,
creating `<project>-worktree/<slug>` on the ticket's branch, initialising submodules, and
hard-linking the gitignored assets listed in `projects/<project>_worktree.conf`. It is
idempotent, so later phases reuse the same worktree. Nothing is ever removed automatically.

```bash
claude   # session 1 → /wf coding projectX#387
claude   # session 2 → /wf coding khai-nguyen-quang/dash-cam#12
claude   # session 3 → /wf review projectX#MR!123
```

```bash
tools/git/worktree.sh list                # what exists
tools/git/worktree.sh path projectX#387   # where a ticket lives
tools/git/worktree.sh remove projectX#387 # drop the checkout, keep the branch
```

Rules that keep parallel sessions safe:

- The main checkout `workspace/<project>` is never used for ticket work — leave it on the default branch.
- Never run two phases for the same ticket at once; a worktree has a single writer.
- Workflow artifacts stay in `claude_workflow/.tmp/<slug>/`, per-ticket and shared across sessions.
- Never list build output directories in `_worktree.conf` — each worktree must build its own.

## Unattended cycle

`tools/auto/run_cycle.sh` is **stage flags + refs**: the flags say what to run, the refs say what
to run it on. There is no default — a run with no stage flag prints the usage and exits.

```bash
tools/auto/run_cycle.sh --design 'projectX#123' 'projectX#456'
tools/auto/run_cycle.sh --code   'projectX#123' 'projectX#456'
tools/auto/run_cycle.sh --design --code --verify 'projectX#309'   # the whole cycle
tools/auto/run_cycle.sh --review --fix_review 'projectX#MR!123'
```

`--research`/`--design`/`--code`/`--verify`/`--doc` take issue refs and combine, always running in
that order. `--review`/`--fix_review` take MR/PR refs. The two sets cannot be mixed in one
command. Every stage takes any number of refs: each gets its own worktree and window, and they
run at once (`--serial` for one at a time). One ref failing does not stop the others.

`create_mr` is deliberately excluded. It ends in a human gate — the push and create confirmations
— and a driver that answers that gate itself removes the review instead of automating it.

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
having restored every result from cache and executed nothing. The driver reads the summary counts,
and when everything was cached it re-runs the test binaries for the changed modules directly
rather than advancing.

On a gate failure the driver resumes **the same session** with the real output and asks for a fix,
up to `--max-repair` times (default 2), with an explicit instruction not to weaken tests or narrow
lint scope to get green. After that it stops and leaves the logs in `.tmp/<slug>/cycle/`.

```bash
tools/auto/run_cycle.sh --code 'projectX#387' 'projectX#508' --jobs $(( $(nproc) / 3 ))
```

Never automate a phase that starts the project's live/hardware processes: those containers share
the host IPC namespace, and a second one hijacks the first's publishers.

## Tools

```
tools/forge/resolve.sh        decides github vs gitlab for a ref — the only place that decision is made
tools/forge/test_resolve.sh   its table test

tools/gitlab/                 GitLab REST tools
tools/github/                 GitHub REST + GraphQL tools
tools/git/worktree.sh         forge-agnostic worktree management
wf_epic/tools/                GitLab epic tools
wf_epic/tools/github/         GitHub parent-issue / sub-issue tools
```

`tools/github/` mirrors `tools/gitlab/` **filename for filename**. The skills resolve the forge
once and export `$WF_TOOLS`, so every phase calls `$WF_TOOLS/<tool>` and no phase file branches on
which forge it is talking to. That is also why the GitHub directory keeps the GitLab vocabulary:
`fetch_mr_content.sh` and `create_merge_request.py` operate on pull requests. **MR ≡ PR.**

Conventions and the full tool inventory:

- `instructions/gitlab.md` — GitLab refs, tools, `.env`
- `instructions/github.md` — GitHub refs, tools, `.env`

If a tool you need is missing, add it to the right directory — under the same filename in both,
if it applies to both forges.

## Repository layout

| Path | What it is |
|------|-----------|
| `template/workflow.md` | the workflow projects import; authority for `/wf` |
| `template/epic_workflow.md` | authority for `/wf-epic` |
| `.claude/skills/wf/` | `/wf` dispatcher and phase files |
| `wf_epic/` | `/wf-epic` dispatcher, phases, agents, graph engine |
| `instructions/` | per-phase and per-forge conventions |
| `skills/{cpp,python,shell}/` | language coding standards |
| `projects/` | per-project context and worktree configuration |
| `.tmp/` | per-ticket and per-epic state and artifacts |
