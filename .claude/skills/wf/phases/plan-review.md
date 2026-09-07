# plan-review — Phase 2

Run inline:
1. Read all files in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/`.
2. Check that `_design_overview.md` **opens with the scenario diagram** (`template/diagram.md` §1)
   before purpose and scope: actors, one node per scenario with an `S<n>` id, the observable
   outcome, at least one failure scenario, no component names. A missing or component-shaped
   scenario diagram is a finding — the design cannot be reviewed against what it never stated.
3. Check for conflicts or inconsistencies between `_brainstorm.md`, `_design_overview.md` and
   `_design_detailed.md` — including between the two design documents themselves: a component in
   the overview's map with no detailed section, a detailed section for a component the overview
   never introduces, an assumption no named component delivers, or a scenario from the overview
   that no test and no walkthrough ever names.
4. Report findings. If conflicts exist, list them and ask the user for confirmation before continuing.
5. Update the state file with the review outcome.
