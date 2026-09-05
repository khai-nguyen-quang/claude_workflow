# Design document template

The normative structure for every design produced by `/wf planning` and `/wf-epic design`.
Both phases write **two files**, never one:

| File | Answers | Read by |
|------|---------|---------|
| `<slug>_design_overview.md` | *How does this system fit together?* | a human deciding whether the design is right; anyone joining the work |
| `<slug>_design_detailed.md` | *What exactly do I build?* | the coder, the test author, the reviewer |

**Why two.** A single document forces one text to serve two readers and it serves neither: the
architecture drowns in signatures, and the signatures are scattered across prose. Split them and
each file gets one job. The overview must be readable start to finish in one sitting; the detailed
document is a reference, entered at whichever component you are implementing.

---

## The three rules that make a design readable

These are the failure modes this template exists to prevent. They apply to both files.

**1. Overview before detail — always.** The reader must be able to picture the whole system before
meeting any component. A document that opens with a component is unreadable, because nothing tells
the reader where that component sits.

**2. Diagram before prose.** Every level of the document draws before it explains. A component
section without its place in a diagram is an orphan.

**3. No component is described in isolation.** Every component section names what feeds it and what
it feeds, *by component name*, with a one-line reason. If a section can be read without ever
mentioning another component, either it is a standalone tool or the section is wrong.

---

## File 1 — `<slug>_design_overview.md`

Target: **2–5 pages**. No function signatures, no struct fields, no error codes — those belong in
file 2. If a paragraph here cannot be understood without a type definition, it is in the wrong file.

### 1. Purpose and scope

What problem this solves, in a few sentences. Then two explicit lists:

- **In scope** — what this design delivers.
- **Out of scope** — what it deliberately does not, and where that work lives instead (a later
  epic, an existing system, a decision deferred). An unstated exclusion is read as an omission.

### 2. Architecture at a glance

One paragraph naming the major pieces and the single sentence that explains the shape of the
system — the organising idea a reader needs before any diagram makes sense ("a capture stage fans
frames out to independent per-model workers over shared memory, and every result converges on one
event bus").

Then the **architecture / component diagram**, per `template/diagram.md`. Label every edge with
what crosses it (data, call, event), not just an arrow.

### 3. Primary flow

The **sequence diagram** for the system's main flow, followed by one short paragraph naming the
steps in words. This is the caption, not the walkthrough — the full end-to-end trace lives at the
end of file 2, where the component detail it refers to already exists.

Add a second sequence diagram only for a flow that is genuinely different in shape (an error or
recovery path, a second actor). Do not draw a variant that differs by one step.

### 4. Component map

Every component in one table — the index into file 2. One row per component, one sentence each.

| # | Component | Responsibility (one sentence) | Receives from | Produces for |
|---|-----------|-------------------------------|---------------|--------------|
| 1 | `capture` | Owns each camera device and publishes frames into the pool. | camera driver (V4L2) | `pipeline`, `record` |
| 2 | `pipeline` | Fans frames out to the model workers and collects results. | `capture` | `perception` |

The **Receives from / Produces for** columns are what turn a list of parts into a system. Order the
rows in dataflow order — file 2 uses the same order, and the numbers are the cross-reference.

### 5. Key decisions

Each decision that shapes the design: what was chosen, what was rejected, and the one reason.
Three lines each, not an essay. A reader who disagrees with the design usually disagrees with one
of these, and this is where they find it.

### 6. Assumptions and open risks

What this design takes as true about the rest of the system, the hardware, or the workload, and
what breaks if an assumption is false. Mark anything unverified explicitly — an unverified number
presented as fact is the most expensive error a design document can contain.

---

## File 2 — `<slug>_design_detailed.md`

Opens with one line linking back: *"Architecture and flow: see `<slug>_design_overview.md`."*
Then one section per component, **in the same order as the overview's component map**, followed by
the interfaces, build, tests, and the end-to-end walkthrough.

### One section per component — the required shape

Every component section uses these headings, in this order. No component skips one; write
"none" where a heading genuinely does not apply.

```markdown
## <N>. <Component name>

*Overview map row <N>. Upstream: <component(s)>. Downstream: <component(s)>.*

### Receives
- **Inputs** — each with its exact type, and the range or invariant that makes it valid.
- **Triggers** — what causes this component to run: a call, a timer, an event, a signal, a
  file appearing. Name the mechanism, not just the occasion.
- **Upstream dependencies** — which components or external systems must be running, and what
  this component does if one is not.

### Produces
- **Outputs** — exact return types and message/record types, including the empty and
  error-carrying variants.
- **Side effects** — files written, state mutated, IPC sent, resources acquired, metrics or
  logs emitted. A side effect nobody documented is the classic cross-component bug.
- **Downstream consumers** — which components read each output, and what they do with it.
  Name them; "the rest of the system" is not a consumer.

### Assumes about the rest of the system
Every belief this component holds about things it does not own: ordering guarantees, lifetimes
("the pool outlives every reader"), threading and reentrancy, clock source, back-pressure
behaviour, config validity. **Each assumption must be satisfied by a named component**, and that
component's section must actually deliver it. This heading is where cross-component bugs are
caught before they are written.

### Types and signatures
The exact declarations — classes, functions, structs, message schemas, config keys. Precise
enough to implement against without inference: no `// ...`, no "similar to the above".

### Error conditions
Every way this component can fail, as a table:

| Condition | Detected how | Reported as | Recovery |
|-----------|--------------|-------------|----------|

"Reported as" must name the concrete mechanism — a return code, an exception type, an error
event, a log level. "Handled gracefully" is not an answer.

### Edge cases and failure modes
The inputs and states that are legal but unusual: empty, zero, maximum, duplicate, out of order,
arriving during shutdown, arriving before initialisation. Then the failure modes proper — what
this component looks like when it is degraded rather than dead (dropping frames, growing a queue,
serving stale data), and how a downstream component can tell.
```

### `## Interfaces` — the cross-component contract

After the component sections, one consolidated section carrying every signature, message type,
file path and error case that crosses a component boundary. It repeats what the component sections
declared, gathered in one place.

This section is **normative and mandatory**. It is the contract between people — or agents — who
cannot see each other's work: an implementer and a test author work from this section in parallel.
If it is incomplete, that parallelism silently collapses into guesswork.

### Build integration

How new files enter the build: `SConscript` / `CMakeLists` / packaging entries, new dependencies,
and whether the change applies to the container build only or to the cross-build as well.

### Test strategy

- **Automated** — unit tests per component (framework, naming, which edge cases from the sections
  above), and integration tests naming the boundaries they exercise.
- **Manual** — the steps a human runs to confirm the feature works end to end.

### End-to-end walkthrough

**The section that makes the whole document click.** For each of the 1–3 most important user
actions, trace the request through every component *in order*, naming the section number of each
component as you pass through it:

```markdown
#### Walkthrough: driver triggers a manual recording

1. **`api` (§7)** receives `POST /record` ... produces a `RecordRequest{...}` on ...
2. **`record` (§4)** is triggered by ... reads from the pool filled by `capture` (§1) ...
3. ...
9. **Failure branch** — if the disk is full at step 4, `record` emits `DiskFull` ...
```

Requirements: one numbered step per component hop; state what data crosses each hop; end with at
least one **failure branch** showing what the user sees when a step fails. If a step cannot be
written without inventing a detail, the corresponding component section is incomplete — fix the
section, not the walkthrough.

---

## Checklist before the design is done

- [ ] Overview reads start to finish without opening the detailed file.
- [ ] Architecture diagram and primary-flow sequence diagram both present, edges labelled.
- [ ] Component map ordered by dataflow; its numbering matches the detailed sections.
- [ ] Every component section has all six headings filled.
- [ ] Every assumption names the component that satisfies it, and that component delivers it.
- [ ] Every error condition names a concrete reporting mechanism.
- [ ] `## Interfaces` complete enough to code and test against in parallel.
- [ ] At least one end-to-end walkthrough, with a failure branch.
