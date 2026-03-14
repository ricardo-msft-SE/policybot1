---
layout: default
title: Assumptions and Constraints
nav_order: 9
---

# Assumptions and Constraints

This page summarizes the core assumptions, scope boundaries, and non-goals used across the architecture, workflow, and deployment guidance.

---

## Assumptions

- Questions are expected to target Ohio ORC Title 45 motor vehicle topics.
- Client applications call the backend API only; they do not call Foundry directly.
- Backend API uses managed identity and RBAC for service-to-service access.
- AI Search index (`ohio-title45-index`) is populated and refreshed on schedule.
- Workflow routing uses confidence-based decisions with optional clarification.

---

## Routing Constraints

- Workflow routes to one of two domain agents:
  - `legal_reference`
  - `bmv_faq`
- Clarification is asked only when confidence is below threshold.
- Clarification turns are capped at 2 per request.
- If ambiguity remains after max turns, route falls back to `legal_reference` with uncertainty note.

---

## Non-Goals

- No legal advice.
- No transactional operations.
- No database writes from agent output.
- No unrestricted internet knowledge source.
- No autonomous actions outside response generation.

---

## Implementation Notes

- Use placeholders in docs (`{YOUR_SUBSCRIPTION_ID}`, `{YOUR_RESOURCE_GROUP}`) and replace with environment-specific values.
- Keep step-by-step procedures in [Deployment Guide]({{ site.baseurl }}/deployment-guide).
- Keep static setting values in [Configuration Reference]({{ site.baseurl }}/configuration).
