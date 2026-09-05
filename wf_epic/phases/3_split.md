# Phase 3 — Split (reconcile + split)

Spec: `template/epic_workflow.md` §5. Announce: **"Entering Epic Split phase."**

**Mechanism: solo, with a human confirmation gate.** Ticket changes are outward-facing and
irreversible — the phase proposes, the human approves, and only then does anything reach GitLab.

The phase handles both cases:

- **Greenfield epic** (no children) — derive tickets from the design and create them.
- **In-progress epic** (children exist) — **reconcile** the existing set against the design, then
  create only what is genuinely missing.

Most real epics are the second case. Epic#91 has 10 children before this phase ever runs.

---

## Step 1 — Inventory

```bash
python3 $WF_EPIC/tools/fetch_epic.py Epic#<id> --detail
```

Gives every child with the evidence you will reconcile on: state, **kind**, note count, linked MR
count, weight, assignee, last update.

**Kind matters immediately.** A `design::`, `research::`, `spike::` or `doc::` ticket is not
implementation work. It stays on the epic, but it **never enters the implementation queue** — a
coder handed a design ticket will try to implement a design. Kind is detected from a `<kind>::`
marker at the start of the **title or the description**; humans write it in either.

If the epic has no children, skip to Step 4 — everything is `create`.

---

## Step 2 — Coverage matrix

From `epic-<id>_design_detailed.md`, list the units of work: every component section and every
entry in its `## Interfaces` section. Use `epic-<id>_design_overview.md`'s component map to check
you have them all and to get the dataflow order — a ticket that splits a component away from the
one feeding it is a bad split, and the map's *Receives from / Produces for* columns are how you
see that. Map each against the existing tickets:

| Design work | Covered by | Verdict |
|---|---|---|
| `FeatureRequest` IPC message | `openpilot#459` | covered |
| `streamerd` on-demand start | `#392`, `#442` | **overlap — candidates for merge** |
| `encoderd` lifecycle | — | **gap → create** |

Read the ticket **descriptions**, not just titles. Two tickets with different titles that describe
the same change are duplicates; two with similar titles that touch different daemons are not.

---

## Step 3 — Classify each existing ticket

Exactly one action per ticket:

| Action | Meaning | Reaches GitLab? |
|--------|---------|-----------------|
| `keep` | covers design work as written | no-op |
| `update` | right scope, description needs revision to match the design | yes, on confirmation |
| `merge` | duplicate — fold into the survivor | yes, on confirmation |
| `defer` | valid work, but out of this epic's scope | yes, on confirmation (unlink from epic) |
| `exclude` | non-impl kind (`design::` etc.) — stays on the epic, out of the queue | no |
| `create` | a gap in the coverage matrix | yes, on confirmation |

### Rules that must not be broken

**Never delete a GitLab issue.** Deletion is not an available action and must not be proposed.
Irrelevant work is **unlinked from the epic** or closed with a comment — recoverable, and it
preserves whatever discussion the ticket carries.

**The survivor of a duplicate is the ticket with history.** Use the note count, linked MRs and
assignee from Step 1. Fold the other ticket's content into the survivor and close the emptier one.
**Never close a ticket someone has worked on in favour of a freshly written one** — you would be
discarding review discussion and a branch that may already exist.

**Never silently rescope a human's ticket.** If the design implies something different from what
the ticket's author wrote, that is a conflict, not a correction: state both readings and **ask**.

**A closed ticket stays closed.** Do not reopen; if its work is needed, create a new one that
links to it.

---

## Step 4 — Write the combined list

Write `epic-<id>_tickets.md` — existing and new together, in queue order. The human edits **this
file**, not a wall of terminal output.

```markdown
## Reconcile summary
- 10 existing: 5 keep, 1 update, 2 merge, 0 defer, 2 exclude (design::)
- 2 new
- final implementation queue: 8 tickets

## E1 — openpilot#392 — [Impl] On-demand video streaming
- action: keep
- covers: streamerd on-demand start

## E2 — openpilot#442 — On/Off streaming of an attached-but-not-running camera
- action: merge -> openpilot#392
- reason: same change to streamerd; #392 has the weight and the earlier description
- survivor: #392 (neither has notes or MRs; #392 is the broader statement)

## N1 — (new) encoderd lifecycle follows loggerd/streamerd
- action: create
- project: openpilot
- labels: type::feature, product/vertical::ctkv
- description: |
    <what to build, which `## Interfaces` entries it owns, acceptance criteria>

## Queue
openpilot#459 openpilot#391 openpilot#392 openpilot#393 openpilot#394 openpilot#440 openpilot#441
```

The final `## Queue` line is the phase's machine-readable output — it feeds phase 4 directly:

```bash
python3 $WF_EPIC/tools/seed_epic.py Epic#<id> --tickets <the Queue line>
```

### Test-ticket rule — applies to new tickets

Separate unit-test / integration-test tickets break the one-worktree-one-branch invariant: their
tests land on a different branch than the code they cover, so the implementation MR merges untested
and the test MR cannot build until the impl lands.

- **Per-feature unit and integration tests ride inside the implementation ticket**, shipping in the
  same MR. Every MR stays self-contained.
- **Separate test tickets only for cross-cutting work**: regression suite, test harness, CI wiring,
  shared fixtures.

### Sizing

One ticket is one worktree, one branch, one MR. A ticket that cannot state its acceptance criteria
in two lines is too large.

---

## Step 5 — Confirm, then execute

Show the reconcile summary, every action, and what each one does to GitLab. **Wait for an explicit
yes.** Then execute, in this order, confirming destructive-looking actions separately:

```bash
# create — the only bulk action
python3 $WF_EPIC/tools/create_issue.py <project> \
    --title "<title>" --description-file <body.md> \
    --epic <id> --label <label> [--dry-run]
```

`create_issue.py` creates, links using the issue's **global id** (not its iid), and reads
`epic_iid` back to prove the link landed. A `WARNING:` means the ticket exists but is **not**
attached — fix it before continuing, or phase 4 will not see it.

`update`, `merge` and `defer` are done one at a time, each shown before it runs.

Record every created ref back into `_tickets.md`.

---

## Gate

`epic-<id>_tickets.md` exists and ends in a `## Queue` line; every `create` in it has a real GitLab
iid and a verified `epic_iid`; no ticket carries an unresolved conflict. Confirm with:

```bash
python3 $WF_EPIC/tools/fetch_epic.py Epic#<id> --detail
```

Update `_state.md`. Next: `/wf-epic implementation Epic#<id>`.
