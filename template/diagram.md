# Diagram template (Mermaid)

Use this template whenever a design is produced (e.g. `/wf planning`, `/wf design`).
Pick the diagram types that fit the design and drop the rest — most designs need at
least an **architectural** diagram plus a **sequence** diagram for the main flow.

Conventions:
- Always wrap diagrams in a fenced ```` ```mermaid ```` block so they render.
- Label every node and edge; edges describe *what* crosses them (data, call, event).
- Keep one diagram per concern. Split rather than crowd a single diagram.
- Name nodes after real components/modules from the design, not generic placeholders.

---

## 1. Block diagram

High-level building blocks and how they connect. Use for "what are the pieces".

```mermaid
flowchart LR
    subgraph Input
        A[Source / Sensor]
    end
    subgraph Processing
        B[Component B<br/>responsibility]
        C[Component C<br/>responsibility]
    end
    subgraph Output
        D[(Store / Sink)]
    end

    A -->|raw data| B
    B -->|processed events| C
    C -->|result| D
```

---

## 2. Architectural diagram

Components, their grouping (process / service / container boundaries), and the
interfaces between them. Use for "how is it structured and deployed".

```mermaid
flowchart TB
    subgraph Device["Device / Process boundary"]
        direction TB
        api[API Layer]
        svc[Service / Domain Logic]
        repo[Repository / Adapter]
    end

    ext[External System]:::external
    db[(Database)]

    api -->|calls| svc
    svc -->|reads/writes| repo
    repo -->|SQL| db
    svc -->|IPC / HTTP| ext

    classDef external fill:#eee,stroke:#999,stroke-dasharray: 4 2;
```

---

## 3. Sequence diagram

Ordered interactions over time for one concrete flow. Use for "what happens, step
by step" — include the success path and at least one error/alt branch.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant API
    participant Service
    participant Store

    User->>API: request(payload)
    API->>Service: handle(payload)
    Service->>Store: query(key)
    alt found
        Store-->>Service: record
        Service-->>API: result
        API-->>User: 200 OK
    else not found
        Store-->>Service: empty
        Service-->>API: error
        API-->>User: 404 Not Found
    end
```
