---
layout: default
title: Appendix - AI Search vs Bing Custom Grounding
nav_order: 10
---

# Appendix - AI Search vs Bing Custom Grounding

This appendix explains why this solution uses Azure AI Search as the primary grounding method for Ohio ORC Title 45.

---

## Recommendation for this project

For this legal-policy use case, **Azure AI Search is the recommended production choice**.

Primary reasons:

- tighter control over retrieval behavior and ranking
- better repeatability for evaluation and regression testing
- stronger governance for scoped content and citation quality
- richer operational tuning and observability

---

## Decision Matrix

| Dimension | Azure AI Search | Bing Custom Grounding |
|----------|------------------|------------------------|
| Corpus control | High - explicit index and fields | Medium - web-grounded and less deterministic |
| Retrieval tuning | High - hybrid/vector/semantic + strictness | Lower - fewer explicit retrieval controls |
| Citation consistency | High - stable metadata fields | Medium - web result variability |
| Evaluation repeatability | High | Medium/Low |
| Setup speed | Medium | High |
| Best fit | Compliance-oriented production systems | Rapid prototypes and broad web discovery |

---

## Why AI Search aligns with ORC use cases

This project prioritizes:

- strict in-scope enforcement (Ohio ORC Title 45 only)
- section-level citation traceability
- refusal behavior for out-of-domain questions
- workflow routing confidence based on stable retrieval context

AI Search supports these directly through index schema control, semantic configuration, strictness settings, and monitored indexing cadence.

---

## When Bing Custom Grounding can still be appropriate

Use Bing Custom Grounding when:

- you need the fastest possible MVP with minimal indexing setup
- you require broad web freshness over strict corpus governance
- deterministic retrieval behavior is not a hard requirement

---

## Hybrid adoption pattern

A practical pattern is:

1. start with AI Search as the primary legal source
2. optionally add Bing-based retrieval for explicitly marked exploratory prompts
3. keep legal answers constrained to AI Search-backed content and citations

---

## Recommended AI Search settings for this repo

| Setting | Recommended value | Purpose |
|--------|--------------------|---------|
| Query type | `vector_semantic_hybrid` | Strong recall + precision on legal text |
| Strictness | `4` | Reduces weak-context answers |
| Top K | `10` | Sufficient context for legal grounding |
| In-scope | `true` | Prevents unsupported domain expansion |
| Semantic config | `policy-semantic-config` | Better legal language relevance |
| Index refresh | Weekly + manual on updates | Keeps legal corpus current |

---

## Cross-references

- [Architecture]({{ site.baseurl }}/architecture)
- [Deployment Guide]({{ site.baseurl }}/deployment-guide)
- [Configuration Reference]({{ site.baseurl }}/configuration)
- [Evaluation Guide]({{ site.baseurl }}/evaluation-guide)
