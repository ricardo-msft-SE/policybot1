---
layout: default
title: Workflow Architecture
nav_order: 3
---

# Workflow Architecture
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Why this is the recommended design

This design uses **Microsoft Foundry Workflow** as the orchestration layer and a
**backend API** as the security and integration boundary. The workflow performs
scope checks, intent routing, and clarification handling before invoking a domain agent.

Use this architecture when you need:

- more deterministic routing behavior
- node-level observability and troubleshooting
- easier A/B tests for routing policy
- strict pre- and post-processing gates

---

## Key Principles

- Backend API is the orchestration and security boundary
- Foundry workflow owns routing policy, not prompt-only logic
- Domain agents are specialized by intent
- The system can ask follow-up clarification questions before final routing
- All answers remain grounded with citations

---

## Backend and Workflow Topology

```mermaid
flowchart LR
    U[User] --> UI[Client UI Layer]
    UI --> API[Backend API Layer]
    API --> WF[Foundry Workflow]
    WF --> LEGAL[Primary Agent Legal Reference]
    WF --> FAQ[Secondary Agent BMV FAQ]
    LEGAL --> OUT[Response and citations]
    FAQ --> OUT
    OUT --> API
    API --> UI
```

---

## Workflow Reference Design

```mermaid
flowchart TD
    A[Start User question] --> B{Title 45 scope check}
    B -- No --> B1[Out of scope refusal]
    B -- Yes --> C[Intent classification]

    C --> D{Confidence meets threshold}
    D -- No --> FQ[Ask follow-up clarification]
    FQ --> UA[User clarification answer]
    UA --> RC[Reclassify intent]
    RC --> E{Route decision}
    D -- Yes --> E{Route decision}

    E -- legal reference --> D1[Invoke Primary Agent Legal Reference]
    E -- bmv faq --> D2[Invoke Secondary Agent BMV FAQ]

    D1 --> S[Synthesis and citation preservation]
    D2 --> S

    S --> Q{Citations present}
    Q -- No --> Q1[Return grounded not found response]
    Q -- Yes --> M[Emit telemetry and return]

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
    participant UI as Client UI
    participant API as Backend API
    participant WF as Foundry Workflow
    participant Agent as Domain Agent

    User->>UI: Ask question
    UI->>API: POST question
    API->>WF: Start workflow
    WF->>WF: Scope and intent checks

    alt out_of_scope
      WF-->>API: Scope refusal
      API-->>UI: Refusal payload
    else in_scope
      alt confidence low
        WF-->>API: Clarification question
        API-->>UI: Ask follow-up question
        UI->>API: Clarification response
        API->>WF: Continue workflow
      end
      WF->>Agent: Invoke selected domain agent
      Agent-->>WF: Grounded answer and citations
      WF-->>API: Final payload and route metadata
      API-->>UI: Final response
    end
```

### Static Sequence Image

For environments where Mermaid rendering is unavailable, this static sequence diagram
shows the same execution path:

![Workflow sequence](assets/images/workflow-sequence-static.svg)

---

## Workflow Possibilities (Design Variants)

### 1) Single classifier router (simplest)

```mermaid
flowchart LR
    Q[Question] --> C[Classifier]
    C --> R{Route}
  R --> A1[Primary Legal Reference]
  R --> A2[Secondary BMV FAQ]
```

Best when you need predictable behavior with minimal operational overhead.

### 2) Two-stage router with clarification loop

```mermaid
flowchart LR
    Q[Question] --> G{In Title 45?}
    G -- No --> X[Refuse]
    G -- Yes --> C[Classifier]
    C --> V{High confidence?}
  V -- No --> F[Ask follow-up question then reclassify]
  V -- Yes --> R{Route}
  R --> A1[Primary Legal Reference]
  R --> A2[Secondary BMV FAQ]
```

Best when reducing misroutes is more important than raw latency.

### 3) Parallel candidate plus ranker

```mermaid
flowchart LR
    Q[Question] --> P[Parallel candidate retrieval top two routes]
    P --> S1[Candidate response A]
    P --> S2[Candidate response B]
    S1 --> K[Ranker and policy checker]
    S2 --> K
    K --> O[Best grounded response]
```

Best for ambiguous questions, but highest cost and latency.

---

## Mapping to Domain Agents

| Workflow route label | Domain agent |
|----------------------|-------------|
| `legal_reference` | Primary Agent Legal Reference |
| `bmv_faq` | Secondary Agent BMV FAQ |

---

## Non-Goals

- No authentication workflows for end users in this release
- No transactional operations
- No database writes from agent responses
- No legal advice output
- No use of PDF files as grounding source
- No unrestricted general internet knowledge
- No autonomous agentic actions

---

## Operational Benefits and Trade-offs

| Dimension | Prompt-only Orchestrator | Workflow-Orchestrated Design |
|-----------|----------------------------|-----------------------------------|
| Routing transparency | Prompt-dependent | Explicit decision nodes |
| Determinism | Medium | High |
| Observability | Aggregate response-level | Per-node metrics and traces |
| Change management | Prompt edits | Node policy updates |
| Latency | Lower | Slightly higher (extra nodes) |
| Cost | Lower | Slightly higher |

---

## Follow-Up Question Policy

- Ask follow-up questions only when classification confidence is below threshold
- Limit to one or two clarification turns per user query
- If ambiguity remains, route to Primary Agent Legal Reference with explicit uncertainty text
- Preserve user context and citations across clarification turns

---

## Related Documentation

- [Architecture]({{ site.baseurl }}/architecture)
- [Configuration Reference]({{ site.baseurl }}/configuration)
- [Deployment Guide]({{ site.baseurl }}/deployment-guide)
- [Evaluation Guide]({{ site.baseurl }}/evaluation-guide)
