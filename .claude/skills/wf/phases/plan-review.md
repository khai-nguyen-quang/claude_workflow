# plan-review — Phase 2

Run inline:
1. Read all files in `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/`.
2. Check for conflicts or inconsistencies between `_strategy.md` and `_design.md`.
3. Report findings. If conflicts exist, list them and ask the user for confirmation before continuing.
4. Update the state file with the review outcome.
