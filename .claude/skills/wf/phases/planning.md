# planning — Phase 1 [superpowers:brainstorming → wf-planner]

Planning runs in two steps: an inline **brainstorming** step in the main session that turns
the ticket into an approved design spec, then the **wf-planner** agent that turns that spec
into the formal strategy + design documents.

`<technical_note>` (the `Features` subsection) and `<state_context>` are already loaded by
the skill's **Prepare context** step — hold them as project context throughout.

## Step 1 — Brainstorming (inline)

Fetch the issue (same as-is):

```bash
python3 $WORKSPACE_ROOT/claude_workflow/tools/gitlab/fetch_ticket_description.py <project>#<id>
```

Then invoke the Skill tool with `skill: "superpowers:brainstorming"` and follow it, seeding it
with:

- **The idea**: the fetched issue content above.
- **Project context**: `<technical_note>` (Features constraints) and, if present,
  `<state_context>`. Treat these as already-explored context so the skill does not re-derive
  them — honor the Features constraints throughout.

**Two overrides of the brainstorming skill's defaults** (the skill allows user overrides):

1. **Spec location**: write the approved design spec to
   `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_brainstorm.md`.
2. **Terminal step**: STOP once the spec is written and the user approves it. Do **NOT**
   invoke `writing-plans` — the wf-planner agent does the planning in Step 2. The brainstorming
   skill's normal terminal (`writing-plans`) is replaced by "hand off to wf-planner".

Do not start Step 2 until the user has approved the spec.

## Step 2 — Planning (wf-planner agent)

Spawn an Agent with:
- **subagent_type**: `wf-planner`
- **description**: `Planning phase for <ref>`
- **prompt**:
  ```
  ## Technical note — Features
  <technical_note>

  ## Approved design spec (from brainstorming)
  Read $WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_brainstorm.md —
  this is the approved intent/design; use it as the primary source for the strategy and
  design documents.

  ## Task
  GitLab ref: <ref>
  WORKSPACE_ROOT: $WORKSPACE_ROOT

  Honor the Features constraints above throughout planning. Then follow
  instructions/planning.md; module docs are discovered there (Step 2) from the issue.

  <if state_context exists>
  ## Current state
  <state_context>
  </if>
  ```

`<technical_note>` is the `Features` subsection forwarded by Step 3 of the skill. The agent
also reads `CLAUDE.md` via its Required reading, and the brainstorm spec via the prompt above.
