# wf_epic — multi-agent graph engine for epics

Executable form of `template/epic_workflow.md`. Takes a group-level GitLab epic from a question to
merged code in four phases.

```
/wf-epic research       Epic#60    3 lenses + consolidator        -> _strategy.md
/wf-epic design         Epic#60    draft/review/fix loop, <=3     -> _design_{overview,detailed}.md
/wf-epic split          Epic#60    reconcile existing + new (you confirm)
/wf-epic implementation Epic#60    AGENT TEAM, streams tickets    -> MRs
/wf-epic status         Epic#60    the queue
```

## How it works

One session per phase. Sessions share no context — **files are the only handoff.**

```mermaid
flowchart LR
    E([Epic]) --> P1

    P1["<b>1 · Research</b><br/>subagent fan-out<br/>3 lenses + consolidator"]
    P2["<b>2 · Design</b><br/>subagent fan-out, looped<br/>1 warm author + 3 fresh reviewers"]
    P3["<b>3 · Split</b><br/>solo, you confirm<br/>no agents"]
    P4["<b>4 · Implementation</b><br/>AGENT TEAM<br/>coder ∥ reviewer ∥ fixer"]

    P1 -->|_strategy.md| P2
    P2 -->|_design.md| P3
    P3 -->|tickets on the forge| P4
    P4 --> MR([MRs / PRs])

    classDef fan fill:#f4e6cc,stroke:#8f5b0e,color:#3a2a08;
    classDef solo fill:#e8e8e4,stroke:#767c7f,color:#22262a;
    classDef team fill:#cfe4e1,stroke:#0c6560,color:#062f2c;
    class P1,P2 fan
    class P3 solo
    class P4 team
```

| Phase | Mechanism | Agents spawned | Loop | You are asked |
|---|---|---|---|---|
| 1 Research | subagent fan-out | `wf-web-researcher` ×1, `wf-planner` ×2 per project, `wf-consolidator` ×1 | no | only when lenses conflict |
| 2 Design | subagent fan-out | `wf-planner` ×1 **warm**, `wf-reviewer` ×3 **fresh per round**, `wf-consolidator` ×1 per round | ≤3 rounds | on divergence or the cap |
| 3 Split | solo | none | no | **always** — before anything reaches the forge |
| 4 Implementation | **agent team** | teammates `coder`, `reviewer`, `fixer` | ≤2 rounds per ticket | on a blocked ticket |

**Phases 1–3 are joins** — N agents work independently, one merges, everyone waits at the barrier.
**Phase 4 is a stream** — tickets flow continuously and an agent that frees up pulls the next.
Only an agent team can express a stream; that is the sole reason phase 4 uses one.

### Phase 1 — three lenses, one message, no cross-talk

```mermaid
flowchart LR
    E([Epic]) --> W["web<br/><i>wf-web-researcher</i>"]
    E --> D["docs · per project<br/><i>wf-planner</i>"]
    E --> C["code · per project<br/><i>wf-planner</i>"]
    W --> K["consolidate<br/><i>wf-consolidator</i>"]
    D --> K
    C --> K
    K --> S([_strategy.md])
    K -.->|lenses disagree| H([you decide])
```

Every prompt carries the silence rule: *write your file and stop, talk to nobody.* Independence is
the whole reason for having three. Disagreements are put to you with the evidence on each side —
never averaged into a third answer nobody proposed.

### Phase 2 — the freshness asymmetry

```mermaid
flowchart LR
    S([_strategy.md]) --> A["author · <b>WARM</b><br/>one wf-planner, all rounds"]
    A --> DR([_design_draft.md])
    DR --> U["usecases"]
    DR --> SC["scale"]
    DR --> CO["corners"]
    U --> K["consolidate"]
    SC --> K
    CO --> K
    K -->|DESIGN OK| F([_design.md])
    K -->|findings| L[(_design_decisions.md<br/>accepted / rejected + reason)]
    L -->|next round| A

    classDef fresh fill:#f4e6cc,stroke:#8f5b0e,color:#3a2a08;
    class U,SC,CO fresh
```

**The author remembers; the reviewers forget.** The author is continued with `SendMessage` so it
never undoes a deliberate decision while fixing an unrelated finding. The three reviewers (shaded)
are new instances every round: a warm reviewer only checks "did they fix my list", a cold one
re-reads the whole document and catches *what the fix just broke*. A document has no build or test,
so the cold reviewer **is** the regression detector.

The ledger is what terminates the loop — it is fed to each round as *"already considered, do not
re-raise without new evidence."* The 3-round cap is only a backstop.

### Phase 4 — the stream, and the hooks that drive it

At any instant all three stages are running, on different tickets. The bottleneck is the coder, so
the fixer is a separate agent: if the coder did its own fixes the overlap would buy nothing.

```
time ─────────────────────────────────────────────────▶
coder      [ code:T1 ][ code:T2 ][ code:T3 ][ code:T4 ]
reviewer             [ rev:T1 ]  [ rev:T2 ][ rev:T1.r2 ]
fixer                       [ fix:T1 ]     [ fix:T2 ]
```

```mermaid
flowchart LR
    Q[(_queue.md<br/>source of truth)] --> TL["task list<br/>code: · review: · fix:"]
    TL --> CO["<b>coder</b><br/>claims code:*<br/><i>wf-coder</i>"]
    TL --> RE["<b>reviewer</b><br/>claims review:*<br/><i>persistent across every ticket</i>"]
    TL --> FI["<b>fixer</b><br/>claims fix:*<br/><i>escalates design findings</i>"]
    CO --> G
    RE --> G
    FI --> G
    G["<b>TaskCompleted</b> — THE GATE<br/>build · test · lint · asan · tsan<br/>exit 2 rejects, agent gets the output"]
    G --> Q
    I["<b>TeammateIdle</b> — THE LOOP<br/>work in your lane → exit 2, claim it"]
    I -.-> CO
    I -.-> RE
    I -.-> FI

    classDef hook fill:#cfe4e1,stroke:#0c6560,color:#062f2c;
    class G,I hook
```


## Layout

```
wf_epic/
├── SKILL.md            /wf-epic dispatcher, symlinked into .claude/skills/
├── phases/1…4.md       what Claude follows, one file per phase
├── agents/             wf-web-researcher, wf-consolidator (symlinked into .claude/agents/)
├── engine/graph.py     the task graph; owns _queue.md
├── engine/gates.sh     gate commands, anchored to .gitlab-ci.yml's validate stage
├── hooks/              task_completed.sh (THE GATE), teammate_idle.sh (THE LOOP), _payload.py
└── tools/              fetch_epic.py, create_issue.py, seed_epic.py
```

The graph is **not stored as edges** — it is derived from an ordered ticket list plus each ticket's
state, so `_queue.md` stays small enough for you to read and edit by hand.

## Setup

```
claude_workflow/setup.sh
```

