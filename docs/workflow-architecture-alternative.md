---
layout: default
title: Workflow Architecture (Alternative)
nav_order: 4
---

# Workflow Architecture (Alternative)
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Why this alternative exists

The current design uses an **Orchestrator Agent** that classifies intent in its prompt and then
calls one specialist agent. This page documents an alternative where **Microsoft Foundry Workflow**
coordinates routing and control flow explicitly.

Use this alternative when you want:

- more deterministic routing behavior
- node-level observability and troubleshooting
- easier A/B tests for routing policy
- strict pre- and post-processing gates

---

## Current vs Workflow-Orchestrated

```mermaid
flowchart LR
    subgraph Current[Current: Agent-Orchestrated]
      U1[User] --> O1[Orchestrator Agent]
      O1 --> S1[Specialist Agent]
      S1 --> R1[Final Response]
    end

    subgraph Workflow[Alternative: Workflow-Orchestrated]
      U2[User] --> W0[Workflow Entry]
      W0 --> G[Scope Guardrail]
      G --> C[Intent Classifier]
      C --> D{Route Decision}
      D --> SD[Definitions Agent]
      D --> ST[Traffic Violations Agent]
      D --> SL[Licensing Agent]
      D --> SR[Legal Reasoning Agent]
      SD --> F[Synthesis + Format]
      ST --> F
      SL --> F
      SR --> F
      F --> T[Telemetry + Eval]
      T --> R2[Final Response]
    end
```

---

## Workflow Reference Design

```mermaid
flowchart TD
    A[Start: User Question] --> B{Title 45 Scope Check}
  B -- No --> B1[Refusal Template - Out-of-scope response]
  B -- Yes --> C[Intent Classification - Label and Confidence]

  C --> D{Confidence meets threshold?}
  D -- No --> R[Route to legal-reasoning-agent - Fallback for ambiguity]
    D -- Yes --> E{Intent Label}

    E -- definition --> D1[Invoke definitions-agent]
    E -- traffic_violation --> D2[Invoke traffic-violations-agent]
    E -- licensing --> D3[Invoke licensing-agent]
    E -- legal_reasoning --> D4[Invoke legal-reasoning-agent]

    D1 --> S[Synthesis & Citation Preservation]
    D2 --> S
    D3 --> S
    D4 --> S

    S --> Q{Citations present?}
    Q -- No --> Q1[Return grounded not-found response]
    Q -- Yes --> M[Telemetry - route confidence latency]

    B1 --> Z[Return]
    Q1 --> Z
    M --> Z
```

### Static Decision Tree Image

For environments where Mermaid rendering is unavailable, this static diagram provides the
same routing logic view:

![Workflow decision tree](assets/images/workflow-decision-tree.svg)

---

## End-to-End Query Sequence

```mermaid
sequenceDiagram
    participant User
    participant WF as Foundry Workflow
    participant Guard as Scope Guard Node
    participant Clf as Intent Classifier Node
    participant Router as Route Decision Node
    participant Spec as Specialist Agent Node
    participant Synth as Synthesis Node
    participant Obs as Telemetry Node

    User->>WF: Ask question
    WF->>Guard: Validate Title 45 scope
    Guard-->>WF: in_scope / out_of_scope

    alt out_of_scope
      WF-->>User: Scope refusal
    else in_scope
      WF->>Clf: Classify intent
      Clf-->>Router: label + confidence
      Router->>Spec: Invoke selected specialist
      Spec-->>Synth: Grounded answer + citations
      Synth->>Obs: Emit metrics + route outcome
      Synth-->>User: Final response
    end
```

### Static Sequence Image

For environments where Mermaid rendering is unavailable, this static sequence diagram
shows the same execution path:

![Workflow sequence](assets/images/workflow-sequence-static.svg)

---

## Workflow Possibilities (Design Variants)

### 1) Single-Classifer Router (simplest)

```mermaid
flowchart LR
    Q[Question] --> C[Classifier]
    C --> R{Route}
    R --> A1[Definitions]
    R --> A2[Traffic]
    R --> A3[Licensing]
    R --> A4[Legal Reasoning]
```

Best when you need predictable behavior with minimal operational overhead.

### 2) Two-Stage Router (higher precision)

```mermaid
flowchart LR
    Q[Question] --> G{In Title 45?}
    G -- No --> X[Refuse]
    G -- Yes --> C[Classifier]
    C --> V{High confidence?}
    V -- No --> A4[Legal Reasoning]
    V -- Yes --> R{Route}
    R --> A1[Definitions]
    R --> A2[Traffic]
    R --> A3[Licensing]
```

Best when reducing misroutes is more important than raw latency.

### 3) Parallel Candidate + Ranker (maximum robustness)

```mermaid
flowchart LR
  Q[Question] --> P[Parallel candidate retrieval - top 2 specialists]
    P --> S1[Candidate response A]
    P --> S2[Candidate response B]
    S1 --> K[Ranker / policy checker]
    S2 --> K
    K --> O[Best grounded response]
```

Best for ambiguous questions, but highest cost and latency.

---

## Mapping to Existing Agents

This workflow design reuses the existing specialist agents and keeps their role boundaries:

| Workflow route label | Existing connected agent |
|----------------------|--------------------------|
| `definition` | `definitions-agent` |
| `traffic_violation` | `traffic-violations-agent` |
| `licensing` | `licensing-agent` |
| `legal_reasoning` | `legal-reasoning-agent` |

---

## Operational Benefits and Trade-offs

| Dimension | Current Orchestrator Agent | Workflow-Orchestrated Alternative |
|-----------|----------------------------|-----------------------------------|
| Routing transparency | Prompt-dependent | Explicit decision nodes |
| Determinism | Medium | High |
| Observability | Aggregate response-level | Per-node metrics and traces |
| Change management | Prompt edits | Node policy updates |
| Latency | Lower | Slightly higher (extra nodes) |
| Cost | Lower | Slightly higher |

---

## Suggested Adoption Path

1. Keep current architecture as production baseline.
2. Implement a workflow in parallel for shadow traffic.
3. Compare route accuracy, citation completeness, latency, and refusal correctness.
4. Promote workflow to primary path when metrics are equal or better.

---

## Related Documentation

- [Architecture]({{ site.baseurl }}/architecture)
- [Configuration Reference]({{ site.baseurl }}/configuration)
- [Evaluation Guide]({{ site.baseurl }}/evaluation-guide)
