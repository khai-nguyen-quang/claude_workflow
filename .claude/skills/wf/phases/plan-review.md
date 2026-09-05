# plan-review — Phase 2

Run inline:
1. Read all files in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/`.
2. Check for conflicts or inconsistencies between `_brainstorm.md`, `_design_overview.md` and
   `_design_detailed.md` — including between the two design documents themselves: a component in
   the overview's map with no detailed section, a detailed section for a component the overview
   never introduces, or an assumption no named component delivers.
3. Report findings. If conflicts exist, list them and ask the user for confirmation before continuing.
4. Update the state file with the review outcome.
