# MR title
<Gitlab Issue description>. Ref #<iid>

# MR Description
```
# Summary

---

# Implementation Details

## Important note

## Core changes

## Simulation support (if applicable)

## Document

## Known bug

---

# How It Was Tested
- Manual validation
    - [x] Functionality testing evidence on docker
    - [x] Functionality testing evidence on device
    - [ ] Test log attached
    - [ ] CPU/Memory consumption log
- Automated validation
    - [x] CI pipeline passed successfully
    - [ ] HIL tested
    - [ ] Regression test
```

# Writing style — "Implementation Details"

The structure above is fixed; this is how to fill in `# Implementation Details` so a
reviewer can read it once and know what the change does. Derived from the author's own
rewrites (openpilot !239).

**Shape**

- Open with **one short paragraph**: what the change does overall, in plain words. No
  file names in it.
- Then a series of **bold labels**, each followed by **2–3 bullets** — not `##`/`###`
  headings, and not prose paragraphs.
- One idea per bullet, one sentence per bullet.
- No tables. No file-by-file tour.

```
**How frames are copied**
- A copy is either a plain `memcpy`, a hardware DMA copy through `/dev/dmacopy`, or a
  `memcpy` bracketed by dma-buf cache maintenance
- Engine create per-camera copier following `io_mode` declared in config file
```

**Naming the labels**

Name each label for what actually happens, in the words a reviewer would say out loud —
`**How frames travel**`, `**How frames are copied**`, `**Cameras in same group publishing
the 1st frame together**`. Not abstract noun phrases (`The frame path`, `Copying frames`,
`Publishing together`), which read like a table of contents rather than a claim.

Use the code's own component names (capture session, engine, supervisor), not generic
substitutes (backend, module, handler).

**What to leave out**

- Anything the diff already shows: per-file descriptions, config field lists, "what is
  not implemented yet".
- Constants — timeouts, retry counts, thresholds. Say the behaviour ("retried a few
  times", "restarts are bounded"); the code and `docs/` carry the numbers, and a
  description that repeats them goes stale silently.
- New files: list the **paths only**, under a bold label. Do not describe each one.

**What to keep**

- Anything a reviewer cannot see in the diff: dependencies on other MRs/issues, which
  path is actually exercised today, what is deliberately additive/dead code.
- Edge-case behaviour that is part of the mechanism (e.g. "retired cameras are removed
  from the group"), even when it costs a bullet.

# MR state
**Mark as draft**

# MR labels
- product/vertical::ctkv
- type::feature



