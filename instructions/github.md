# GitHub workflow

The GitHub counterpart of `instructions/gitlab.md`. Same WAT (Workflow, Agent, Tools) framework,
same operation names, different forge.

## Overview

Whenever a Claude agent wants to interact with GitHub it looks in `tools/github/`. If no tool
satisfies its need, the agent may create one there.

`tools/github/` mirrors `tools/gitlab/` **filename for filename**, on purpose: the `/wf` and
`/wf-epic` skills resolve the forge once (`tools/forge/resolve.sh`) and export `$WF_TOOLS`, so
every phase calls `$WF_TOOLS/<tool>` and never branches on which forge it is talking to.

The GitLab vocabulary is kept for the shared names: **`fetch_mr_content.sh` and
`create_merge_request.py` operate on pull requests.** MR ≡ PR.

## .env variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GH_FINEGRAINED_TOKEN` | one of the two | Fine-grained personal access token. **Preferred** when both are set. |
| `GH_TOKEN` | one of the two | Classic personal access token. Used as the fallback. |
| `GH_USERNAME` | No | Your GitHub login, for reference only |

`verify_access.sh` prints which variable supplied the token, because "the wrong
token is in play" is the most common cause of an unexpected 404.

There is no URL or namespace to configure: a GitHub ref always carries its own `owner/repo`.

A **fine-grained** token lists the repositories it may touch explicitly. On each repository the
workflow needs:

| Permission | Why |
|---|---|
| Issues: Read & write | tickets, epics, and **sub-issues** |
| Contents: Read & write | branches and commits |
| Pull requests: Read & write | PRs and review comments |
| Metadata: Read | default branch, repository info |

A 404 on a repository you can clone over SSH almost always means the token's repository access
does not include it — SSH keys and PAT scopes are independent. Note that a fine-grained token
scoped to **"Public repositories"** cannot see a private repo no matter what permissions it
carries: the repository has to be named under **"Only select repositories"**.

# GitHub input format

Links may be given in full URL form or in short form.

GitHub Pull Request
- `khai-nguyen-quang/dash-cam#PR!45` → `https://github.com/khai-nguyen-quang/dash-cam/pull/45`

GitHub Issue (a ticket, or an epic — they are the same object)
- `khai-nguyen-quang/dash-cam#12` → `https://github.com/khai-nguyen-quang/dash-cam/issues/12`

GitHub Epic
- An epic is an ordinary issue whose children are native **sub-issues**. There is no separate
  epic object as there is on GitLab, and no group level: `/wf-epic <phase> owner/repo#1`.

**A ref with no `/` is a GitLab ref.** `camera-daemon#12` resolves to GitLab; the GitHub form is
`khai-nguyen-quang/camera-daemon#12`. `tools/forge/resolve.sh` is the single place this is
decided, and `tools/forge/test_resolve.sh` is its table test.

## For generic tasks

- Verify access: `tools/github/verify_access.sh [--repo owner/repo]`
- Fetch an issue description: `tools/github/fetch_ticket_description.py <ref>`

### Working with branches

Placed at `tools/github/branch/`.

- `create_branch.sh <issue-ref> [--type feature|bug]` — creates `feature/<slug>-<n>` from the
  issue title.
- `push_branch.sh` — a symlink to the GitLab tool: pushing is pure git and carries no forge
  dependency.
- **MUST follow**: **NEVER** push to a remote without confirmation from the user.

### Working with commits

- `tools/github/commit_code.sh` — also a symlink to the GitLab tool, for the same reason.
- **Commit message**: do **not** add any `Co-Authored-By:` trailer or other Claude/Anthropic
  attribution. Keep the message to the change description only.

### Working with an existing pull request

- `checkout_mr_branch.sh <pr-ref>` — fetches the head branch. A PR from a fork has no branch in
  this remote, so it is fetched through `refs/pull/<n>/head` instead.
- `fetch_mr_content.sh <pr-ref> [--diff] [--notes] [--json]` — metadata, description, diff, and
  comments. GitHub keeps three separate comment streams (inline review comments, review
  summaries, and conversation comments); `--notes` shows all three.
- `fetch_issue_from_mr.py <pr-ref>` — the linked issue, from `Ref #N` / `Closes #N` / `Fixes #N`
  / `Resolves #N` in the PR title or body.
- `upload_review_comment.py <pr-ref> <body> [--inline-file <path> --new-line <N>]`
- `reply_and_resolve.py <pr-ref> --list | --plan <plan.json> | --discussion <id> --body <text> [--resolve]`

**Resolving a review thread is GraphQL-only.** REST can post a reply but has no
resolve-thread endpoint, so thread ids in this tool are GraphQL node ids, not the numeric comment
ids REST returns. `--list` prints the ids to use.

### Pull request creation

```
create_merge_request.py <owner/repo> [options]
```

- `--source <branch>`: head branch. Defaults to the current branch of the local repo.
- `--target <branch>`: base branch. Defaults to the repository's default branch.
- `--title <title>`: defaults to the linked issue title, else the latest commit subject.
- `--description <text>` / `--description-file <path>`: body. Defaults to the shared template.
- `--issue <number>`: appends `Closes #<n>` and derives the default title from the issue.
- `--draft`, `--label`, `--dry-run`.
- `--remove-source-branch` and `--squash` are accepted for CLI parity with the GitLab tool, but
  GitHub decides both at merge time; the tool says so and does not apply them.

The source branch must already be pushed; the script pre-flight checks this and aborts with
guidance if the branch is missing.

## Epics and sub-issues

`wf_epic/tools/github/` mirrors `wf_epic/tools/`:

- `fetch_epic.py <owner/repo#n> [--json|--refs-only|--detail]` — the parent issue and its
  sub-issues. Sub-issues may live in another repository, so scope is derived from the children.
- `create_issue.py <owner/repo> --title ... [--parent <n>] [--dry-run]` — creates an issue and
  attaches it to a parent.
- `update_epic.py <owner/repo#n> --description-file <path>`

**The linking trap.** Attaching a sub-issue takes the child's **global `id`**, not its number —
the same distinction the GitLab epic tool documents. `create_issue.py` creates first, links with
the `id` from the create response, then reads the children back to prove the link landed.

# Error handling

If an agent hits an error using a script in `tools/github/`, it clarifies with the user rather
than reaching for an alternative (`gh` CLI, raw curl, a different API).
