# Policy Bot Architecture

> Technical architecture documentation for the Policy Bot solution

---

## Overview

Policy Bot uses a **Retrieval-Augmented Generation (RAG)** architecture powered by Microsoft Foundry and Azure AI Search. This design ensures all responses are grounded in actual policy documents with verifiable citations.

---

## High-Level Architecture

```mermaid
flowchart TB
    subgraph Users["👥 Users"]
        U1["Web Browser"]
        U2["Teams"]
        U3["API Client"]
    end
    
    subgraph Foundry["Microsoft Foundry Platform"]
        direction TB
        subgraph Agent["Policy Bot Agent"]
            IQ["Foundry IQ\n(Orchestration)"]
            LLM["Azure OpenAI\nGPT-4o"]
            SYS["System Prompt\n(Grounding Rules)"]
        end
    end
    
    subgraph Search["Azure AI Search"]
        IDX["Search Index\n(Vector + Full-text)"]
        CRAWL["Web Crawler\n(Scheduled)"]
        SEM["Semantic Ranker"]
    end
    
    subgraph Sources["Government Sources"]
        GOV1["Ohio Revised Code"]
        GOV2["Regulations"]
        GOV3["Policy Updates"]
    end
    
    U1 & U2 & U3 --> IQ
    IQ <--> LLM
    IQ --> SYS
    IQ <--> IDX
    IDX --> SEM
    CRAWL --> IDX
    GOV1 & GOV2 & GOV3 --> CRAWL
    
    style Foundry fill:#e8f4fd,stroke:#0078d4
    style Search fill:#fff4e8,stroke:#ff8c00
    style Sources fill:#e8fde8,stroke:#00a86b
```

---

## Component Details

### 1. Microsoft Foundry Agent

The core agent is built using **Foundry IQ** (no-code approach) with the following configuration:

| Configuration | Value | Purpose |
|--------------|-------|---------|
| **Agent Type** | Prompt Agent | Low-code, rapid deployment |
| **Model** | GPT-4o | High accuracy for policy interpretation |
| **Temperature** | 0.1 | Low creativity for factual responses |
| **Knowledge Source** | Azure AI Search | Grounded retrieval |

#### System Prompt Architecture

```mermaid
flowchart LR
    subgraph Prompt["System Prompt Components"]
        A["Role Definition\n'Policy Expert'"]
        B["Grounding Rules\n'Only cite sources'"]
        C["Citation Format\n'Include quotes'"]
        D["Fallback Behavior\n'Say I don't know'"]
    end
    
    A --> B --> C --> D
```

### 2. Azure AI Search

Handles document ingestion and intelligent retrieval:

```mermaid
flowchart TB
    subgraph Ingestion["Document Ingestion Pipeline"]
        C1["Web Crawler"]
        C2["HTML Parser"]
        C3["Chunk Splitter\n(512 tokens)"]
        C4["Embedding Generator\n(text-embedding-ada-002)"]
        C5["Index Writer"]
    end
    
    subgraph Index["Search Index Schema"]
        F1["content: String"]
        F2["contentVector: Vector(1536)"]
        F3["url: String"]
        F4["title: String"]
        F5["lastModified: DateTime"]
        F6["breadcrumb: String"]
    end
    
    subgraph Query["Query Pipeline"]
        Q1["User Query"]
        Q2["Query Embedding"]
        Q3["Hybrid Search\n(Vector + BM25)"]
        Q4["Semantic Reranker"]
        Q5["Top-K Results"]
    end
    
    C1 --> C2 --> C3 --> C4 --> C5 --> Index
    Q1 --> Q2 --> Q3 --> Q4 --> Q5
    Index --> Q3
```

#### Index Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Chunking Size** | 512 tokens | Balance between context and precision |
| **Overlap** | 128 tokens | Maintain context across chunks |
| **Embedding Model** | text-embedding-ada-002 | Cost-effective, high quality |
| **Search Type** | Hybrid (Vector + Keyword) | Best recall for legal text |
| **Semantic Ranker** | Enabled | Improved relevance scoring |

### 3. Web Crawler Configuration

Designed for deep navigation of government websites:

```mermaid
flowchart TB
    subgraph Crawler["Web Crawler Settings"]
        START["Seed URL\ncodes.ohio.gov"]
        L1["Level 1: /ohio-revised-code"]
        L2["Level 2: /title-{n}"]
        L3["Level 3: /chapter-{n}"]
        L4["Level 4: /section-{n}"]
        L5["Level 5: /subsection-{n}"]
        L6["Level 6+: Deep Content"]
    end
    
    START --> L1 --> L2 --> L3 --> L4 --> L5 --> L6
    
    style L5 fill:#ffd700
    style L6 fill:#ffd700
```

| Setting | Value | Purpose |
|---------|-------|---------|
| **Max Depth** | 10 | Reach deeply nested content |
| **Crawl Scope** | `codes.ohio.gov/*` | Stay within domain |
| **Schedule** | Weekly | Keep content fresh |
| **Delay** | 1 second | Respectful crawling |

---

## Data Flow

### Query Processing Flow

```mermaid
sequenceDiagram
    participant User
    participant Foundry as Foundry IQ
    participant Search as AI Search
    participant LLM as GPT-4o
    
    User->>Foundry: "What are the requirements for..."
    
    Foundry->>Search: Hybrid search query
    Search-->>Foundry: Top 5 relevant chunks
    
    Foundry->>LLM: Context + Query + System Prompt
    Note over LLM: Generate grounded response<br/>with citations
    
    LLM-->>Foundry: Response with quotes & URLs
    Foundry-->>User: Formatted answer with citations
```

### Citation Generation Flow

```mermaid
flowchart LR
    subgraph Input
        Q["User Question"]
        C["Retrieved Chunks\n(with metadata)"]
    end
    
    subgraph Processing
        LLM["GPT-4o\n+ Citation Prompt"]
    end
    
    subgraph Output
        A["Answer Text"]
        CIT["Citations:\n• URL\n• Title\n• Exact Quote"]
    end
    
    Q --> LLM
    C --> LLM
    LLM --> A
    LLM --> CIT
```

---

## Security Architecture

```mermaid
flowchart TB
    subgraph Network["Network Security"]
        VNET["Virtual Network\n(Optional)"]
        PE["Private Endpoints"]
        NSG["Network Security Groups"]
    end
    
    subgraph Identity["Identity & Access"]
        MI["Managed Identity"]
        RBAC["Azure RBAC"]
        AAD["Entra ID Authentication"]
    end
    
    subgraph Data["Data Protection"]
        ENC["Encryption at Rest\n(Microsoft-managed keys)"]
        TLS["TLS 1.3 in Transit"]
        CMK["Customer-Managed Keys\n(Optional)"]
    end
    
    Network --> Identity --> Data
```

### Security Controls

| Control | Implementation | Notes |
|---------|---------------|-------|
| **Authentication** | Entra ID | Required for Foundry access |
| **Authorization** | Azure RBAC | Least privilege principle |
| **Network** | Public (default) or Private Endpoints | See enterprise deployment |
| **Data Encryption** | AES-256 | Automatic, no configuration needed |

---

## Scalability

### Load Handling

| Component | Scaling Method | Limits |
|-----------|---------------|--------|
| **Foundry Agent** | Automatic | Based on Foundry tier |
| **AI Search** | Manual (replica count) | Up to 12 replicas |
| **Azure OpenAI** | TPM (tokens per minute) | Configurable quota |

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| **Response Time** | < 5 seconds | 95th percentile |
| **Availability** | 99.9% | Multi-region recommended for production |
| **Concurrent Users** | 100+ | Depends on tier |

---

## Monitoring & Observability

```mermaid
flowchart LR
    subgraph Apps["Applications"]
        A1["Foundry Agent"]
        A2["AI Search"]
        A3["OpenAI"]
    end
    
    subgraph Monitor["Azure Monitor"]
        AI["Application Insights"]
        LA["Log Analytics"]
        AL["Alerts"]
    end
    
    subgraph Dashboards["Visibility"]
        D1["Usage Dashboard"]
        D2["Performance Metrics"]
        D3["Cost Analytics"]
    end
    
    Apps --> AI --> LA
    LA --> AL
    LA --> Dashboards
```

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| **Query Latency** | End-to-end response time | > 10 seconds |
| **Error Rate** | Failed requests percentage | > 1% |
| **Token Usage** | OpenAI consumption | > 80% quota |
| **Index Freshness** | Last successful crawl | > 7 days |

---

## Disaster Recovery

| Aspect | Strategy | RPO/RTO |
|--------|----------|---------|
| **Index Data** | Re-crawl from source | RPO: 7 days |
| **Configuration** | Infrastructure as Code (Bicep) | RPO: 0 |
| **Agent Settings** | Exported JSON configuration | RPO: 0 |

---

## Next Steps

- [Deployment Guide](deployment-guide.md) - Deploy this architecture
- [Cost Estimation](cost-estimation.md) - Understand pricing
- [Pain Points Addressed](pain-points-addressed.md) - Technical deep-dive
