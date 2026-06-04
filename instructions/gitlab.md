# Gitlab workflow
Hey Claude, I want to apply WAT (Workflow, Agent, Tools) framework to write a bunch of scripts (*.sh, *.py) to interact with gitlab

## Overview
Whenever Claude Agents want to interact with Gitlab, it first looks into the `tools/gitlab` folder, if there is not tool satisfy its need, then Agent can ceate a new tool in  `tools/gitlab`

Credential and instance configuration are provided in `claude_workflow/.env`.

## .env variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GL_TOKEN` | Yes | GitLab personal access token |
| `GL_URL` | Yes | GitLab instance base URL (e.g. `https://gitlab.mycompany.com`) |
| `GL_NAMESPACE` | Yes | Default group/namespace prepended to short project refs (e.g. `mygroup/mysubgroup`) |

Example `.env`:
```
GL_TOKEN=glpat-xxxxxxxxxxxx
GL_URL=https://gitlab.mycompany.com
GL_NAMESPACE=mygroup/mysubgroup
```

Short refs like `projectX#MR!177` expand to `${GL_NAMESPACE}/projectX` merge request 177.
Full URLs are accepted as-is regardless of host.

Create different scripts to perform different taks

# Gitlab Input format 

Link to Gitlab repo/issue/mr can be provided in full format as: `${GL_URL}/${GL_NAMESPACE}/projectX/-/merge_requests/177`, or in short format following convention

Gitlab MR
- projectX#MR!177: `${GL_URL}/${GL_NAMESPACE}/projectX/-/merge_requests/177`
- projectB#MR!32: `${GL_URL}/${GL_NAMESPACE}/projectB/-/merge_requests/32`

Gitlab Issue
- projectX#300: `${GL_URL}/${GL_NAMESPACE}/projectX/-/work_items/300`
- tvi-linux#MR!16: `${GL_URL}/${GL_NAMESPACE}/tvi-linux/-/merge_requests/16`

Gitlab Epic
- Epic#60: `${GL_URL}/groups/${GL_NAMESPACE}/-/epics/60`

## For generic task
- Script (*.sh, *.py) to verify access to gitlab repo, placed at `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/verify_access`,
- Script (*.sh, *.py) retrieve a Gitlab issue description, placed at: `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description`

### Working with branch
Placed at  `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/branch`
- Script (*.sh, *.py) to create a new branch to start working on a new ticket.
- Script (*.sh, *.py) to push a new branch to remote.

### Working with commit
- Script (*.sh, *.py) to commit code to current branch: `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/commit_code.sh`

### Working with merge request
Script (*.sh, *.py) to switch to remote branch of merge request
Script (*.sh, *.py) to fetch an particular MR, placed at: `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_mr_content.sh`
Script (*.sh, *.py) to retrive information of Gitlab Issue associated with that merge request. 
- Example: The merge request projectX#MR!178 has title: "[Refactor] Extract DrainQueue from WorkerResultChannel to common. Ref #310", then it is associated with Gitlab Issue projectX#310
Script (*.sh, *.py) to allow upload review comments to that MR, placed at: `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/upload_review_comment`
Script (*.sh, *.py) to retrieve all review comments available on a merge request, store those comments in to file.
 
# Error handling
In case Agent got error while using scripts in `$WORKSPACE_ROOT/claude_workflow/tools/gitlab/`, it will clarify with user, do not to use alternatives.
