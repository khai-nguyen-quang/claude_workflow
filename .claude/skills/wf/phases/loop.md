# loop — repeat phases until a verdict approves

Runs a list of phases over and over until a verdict-producing phase approves, or until
`--max-iter` rounds are spent. The rounds run **back to back inside this session** — there is
nothing to wait for between a review and the fix that answers it, so nothing waits.

A phase ends a loop by leaving **evidence on disk** — a fresh report carrying a verdict line —
never by claiming success in the transcript.

## Parse args

Args are `loop <phase>... <ref>`, with an optional `--max-iter <n>` anywhere after `loop`.

- `--max-iter <n>` — maximum rounds. Default **3**.
- `<ref>` — the last token once `--max-iter <n>` is removed.
- `<phases>` — every token between `loop` and `<ref>`.

Stop with an error **before running anything** when:

| Condition | Message |
|---|---|
| no phases given | print the usage block below |
| a phase is not a row in the dispatch table of `SKILL.md` | `unknown phase '<x>'` |
| `loop` is one of `<phases>` | `loop cannot be nested` |
| no verdict phase in `<phases>` | `loop needs a verdict phase (review or plan-review) — nothing would end the loop` |

```
Usage: /wf loop <phase>... <ref> [--max-iter <n>]

Phases before the first verdict phase run once; that phase and everything
after it repeat until the verdict approves or <n> rounds are spent.

Verdict phases:  review (PRODUCTION READY)  |  plan-review (DESIGN OK)

  /wf loop review fix_review projectX#MR!261
  /wf loop coding review fix_review projectX#309
  /wf loop planning plan-review projectX#309 --max-iter 2
```

## Split the list

The **first verdict phase** in `<phases>` splits the list:

| Part | Phases | When it runs |
|------|--------|--------------|
| Prelude | everything before the first verdict phase | **once**, before the loop |
| Body | the first verdict phase and everything after it | **every round** |

Coding once and then reviewing it repeatedly is the point of the split — a second round must not
re-run `coding` from scratch.

### Worked examples

| Args | Prelude | Body | Ref | Rounds |
|------|---------|------|-----|--------|
| `loop review fix_review projectX#MR!261` | — | `review`, `fix_review` | `projectX#MR!261` | 3 |
| `loop coding review fix_review projectX#309` | `coding` | `review`, `fix_review` | `projectX#309` | 3 |
| `loop planning plan-review projectX#309 --max-iter 2` | `planning` | `plan-review` | `projectX#309` | 2 |
| `loop fix_review projectX#MR!261` | — | — | — | **error**: no verdict phase |

## Verdict phases

`<slug>` and `<prefix>` come from **Artifact paths** in `template/workflow.md`: an issue gives
`<slug>` = `<project>-<id>` and `<prefix>` = `<project>-<id>_`, an MR gives `<project>-mr-<id>`
and `<project>-mr-<id>_`. Reports live at
`$WORKSPACE_ROOT/claude_workflow/.tmp/<slug>/<prefix><name>.md`.

| Phase | Report | Ends the loop | Keeps looping |
|-------|--------|---------------|---------------|
| `review` | `<prefix>review.md` | `PRODUCTION READY` | `NEEDS WORK`, `NOT PRODUCTION READY` |
| `plan-review` | `<prefix>plan_review.md` | `DESIGN OK` | `CONFLICTS FOUND` |

## Run

Do the skill's **Prepare context** steps once, then announce the plan:

> Entering loop for `<ref>`: `<body phases joined by " → ">`, up to `<n>` rounds.
> Prelude: `<prelude phases>`. (omit when the prelude is empty)

Run each prelude phase once, by reading its file from the dispatch table and following it exactly.
A prelude phase that fails stops the loop before round 1.

Then, for `round` = 1..`<n>`:

**1. Mark the round.** The marker is what makes a stale report detectable:

```bash
touch "$WORKSPACE_ROOT/claude_workflow/.tmp/<slug>/.loop-round-start"
```

**2. Announce** `── Round <round>/<n> ──`.

**3. Run the body phases in order**, each one by reading its file from the dispatch table and
following it exactly — pre-steps included. Immediately after the verdict phase, do step 4; the
phases after it in the body are step 6.

**4. Read the verdict** from the report (`review` shown; use the `plan-review` row for that phase):

```bash
report="$WORKSPACE_ROOT/claude_workflow/.tmp/<slug>/<prefix>review.md"
marker="$WORKSPACE_ROOT/claude_workflow/.tmp/<slug>/.loop-round-start"
[ -f "$report" ] || echo "MISSING"
[ "$report" -nt "$marker" ] || echo "STALE"
grep -qiE '^\W*\**NOT PRODUCTION READY' "$report" && echo "NOT PRODUCTION READY"
grep -qiE '^\W*\**NEEDS WORK'           "$report" && echo "NEEDS WORK"
grep -qiE '^\W*\**PRODUCTION READY'     "$report" && echo "PRODUCTION READY"
```

Test in that order — `PRODUCTION READY` is a substring of `NOT PRODUCTION READY`, so the first
match wins.

**5. Act on it.**

| Verdict | Action |
|---------|--------|
| approving (`PRODUCTION READY` / `DESIGN OK`) | **stop the loop now** — skip the rest of the body, go to **Finish** |
| non-approving | continue to step 6 |
| `MISSING`, `STALE`, or no verdict line at all | **stop the loop now** and report it — the review did not happen, and the fixer would have nothing to act on. Do not retry the round. |

**6. Run the remaining body phases** (`fix_review` and anything after it), then update `_state.md`
and start the next round.

After the last round without an approving verdict, stop: report the final verdict, the report
path, and that `<n>` rounds were spent. Do not raise `--max-iter` on your own — an MR that three
rounds could not make ready is a human's problem.

## Finish

Print a summary and hand back:

```
Loop finished for <ref> — <PRODUCTION READY after 2 round(s) | still NEEDS WORK after 3 round(s)>

  Round 1  NEEDS WORK
  Round 2  PRODUCTION READY

  Report: <absolute path to the report>
```

## State

Update `<prefix>state.md` after **every round**, not only at the end — an interrupted loop must
resume from a recorded verdict rather than from memory. Record the round number, that round's
verdict, and the phases still to run in **Next step**.
