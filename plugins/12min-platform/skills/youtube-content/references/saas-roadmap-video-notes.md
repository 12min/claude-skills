# SaaS / marketing YouTube notes for roadmap research

Use this reference for SaaS, microSaaS, growth, marketing, pricing, onboarding, or product videos.

## Goal

These notes are not just summaries. They are source material for a future SaaS roadmap. Extract practical decisions, hypotheses, risks, and roadmap implications.

## Default Obsidian destination

Create/update notes under:

`Knowledge/Sources/Videos/<sanitized title>.md`

Use the resolved Obsidian vault path from the `obsidian` skill.

## Required note shape

Frontmatter:

```yaml
type: source/video
source: "<youtube url>"
author: "<speaker/channel>"
title: "<video title>"
channel: "<channel>"
duration: "<duration>"
upload_date: "<YYYY-MM-DD or raw yyyymmdd>"
captured_at: "<current date>"
topics:
  - SaaS
  - microSaaS
  - marketing
  - growth
  - aquisição
  - produto
  - roadmap
concepts_extracted: []
processed: false
```

Sections:

1. `Resumo`
2. `Ideia principal`
3. Topic-specific breakdown, e.g. steps, framework, playbook, or concepts from the video
4. `Aplicação para roadmap de SaaS`
5. `Hipóteses para testar`
6. `Checklist acionável`
7. `Riscos / críticas`
8. `Conexões`

## Extraction bias

Prefer extracting:

- sequence of work: discovery → validation → acquisition → MVP → activation → pricing → scale
- explicit criteria for choosing ideas
- acquisition channels and suggested budgets
- validation questions and interview scripts
- activation / aha moment mechanics
- pricing logic and free-trial conditions
- instrumentation and metrics
- risks, caveats, and anti-patterns

## Chat response after saving

Keep the chat response concise:

- confirm it was saved and verified
- give the absolute note path
- include 3-5 highlights only

Do not paste the whole note back into chat unless the user explicitly asks.
