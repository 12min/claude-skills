---
name: visual-plan
description: >-
  Turn a coding task into a reviewable visual plan as a self-contained HTML file,
  rendered fully locally with no hosted service, account, or external plan tool.
  Use when a change is worth seeing and approving as a scannable artifact (diagrams,
  file maps, callouts, mermaid) before writing code. A privacy-first, in-house
  alternative to /visual-plan — own renderer, own components, offline-friendly.
version: 1.0.0
author: Claude Code (copied for Hermes)
license: MIT
metadata:
  visibility: exported
  hermes:
    tags: [planning, visual-plan, mdx, local-renderer]
    related_skills: [plan]
---

# visual-plan

In-house visual planning for coding agents. Produce the plan you would normally
write in Markdown, but as a **self-contained HTML artifact** with structured
blocks: spatial diagrams, file maps, callouts, and mermaid graphs. Nothing is
sent to any hosted service — the plan is `plan.mdx` on disk, rendered to
`plan.html` by a local renderer you control (`renderer/`).

This is a privacy-first replacement for the Agent-Native `/visual-plan`: same
review discipline, but the renderer and components are ours, so plan content for
proprietary code never leaves the machine and there is no account or CDN-served
app shell (only the mermaid runtime and Prism.js syntax highlighter load from a
public CDN — both are display-only and receive no plan content).

## When To Use

Create a plan when the change is better reviewed as an artifact than a chat
paragraph: multi-file work, an ambiguous or risky change, a data/API decision, or
anything a human should approve before code. Skip it for one-line fixes and
trivially obvious changes — just make the edit.

## Plan Discipline

- **Research first, read-only.** Inspect the real files, schema, and patterns;
  name actual files/symbols, never invented ones. Planning makes NO source edits.
- **Lead with reuse.** For each step, name what it reuses (existing functions,
  components, schema) before what it adds, so the plan shows the genuine delta.
- **Decide hard-to-reverse bets first.** Wire format, public ids, data-model
  shape, auth/ownership — get those right in the plan even if most ships later.
- **The plan is the approval gate.** Present it, name the files it touches, ask
  for sign-off before writing code. Put unresolved decisions in an Open Questions
  section with a recommended default.
- **Optimize diagrams for legibility, not symmetry.** For wide before/after flows,
  prefer vertical `flowchart TD` diagrams with separate stacked subgraphs over
  horizontal left-to-right lanes. If the rendered artifact forces zooming or
  produces tiny text, redraw the Mermaid vertically and re-render before presenting.
- **Turn user decisions into explicit plan state.** When the user resolves an open
  question (provider, naming, HA, cache TTL, extra column, cron cadence), replace
  the open question with a "Decisions made"/"Decisões fechadas" section and
  update the diagrams, file map, rollout steps, and validation checks so stale
  alternatives disappear.

## ClickUp/infrastructure planning pattern

When the plan starts from a ClickUp task rather than an explicit code change:

1. Fetch the ClickUp task details first (description, assignees, status, Definition of Done, comments) using the `clickup-api` skill.
2. Research the current repo read-only and distinguish three evidence classes in the plan:
   - **task requirements** — what ClickUp asks for;
   - **repo evidence** — files/symbols/manifests actually seen in the current checkout;
   - **evidence gaps** — branches, env vars, rake tasks, or scripts mentioned by the task but not present locally.
3. For infra tasks involving Kubernetes Secrets, include a safety callout: patch individual keys or use the cloud/K8s secret manager flow; never apply a minimal Secret manifest over a shared Secret.
4. If task text references code that is absent in the current checkout (for example `PGVECTOR_*` vars or a bootstrap rake task), do not invent file paths. Put it in **Open Questions** and make locating the branch/PR a gate before execution.
5. Render the plan locally and present both `plan.mdx` and `plan.html` paths before asking for approval.

Completion: the plan separates what ClickUp requested from what the repo proves, names concrete files inspected, and highlights all hard-to-reverse infra decisions before execution.

## Block Vocabulary

The plan is `plan.mdx`: markdown plus these JSX block components (provided by the
local renderer). Author markdown normally; drop blocks where they add clarity.

| Block | Shape | Use for |
|-------|-------|---------|
| markdown | `#`, `**`, lists, ` ``` `, GFM tables | prose, the bulk of the plan — fenced code blocks with a language tag (` ```typescript `) get Prism.js syntax highlighting automatically |
| `<Callout>` | `<Callout tone="info\|warn\|danger">…md…</Callout>` | scope notes, warnings |
| `<FileTree>` | `<FileTree title="…" entries={[{path,change,note}]} />` | files touched (change: added\|modified\|removed) |
| `<Diagram>` | `<Diagram data={{ html, css, caption }} />` | spatial diagram via `.diagram-panel`/`.diagram-node` HTML |
| `<Mermaid>` | `<Mermaid chart={\`flowchart LR …\`} />` | flow/sequence/graph where textual grammar is clearer |

## MDX Authoring Rules (must follow or render fails)

- Capitalized components must be **self-closing** (`<FileTree … />`) or have a
  **closing tag** (`<Callout>…</Callout>`). A bare opening tag breaks the parse.
- Put a **blank line** before and after markdown nested inside a JSX block, so it
  parses as markdown:
  ```mdx
  <Callout tone="info">

  This **is** markdown inside the block.

  </Callout>
  ```
- `{ }` is a JS expression; `{{ }}` is an object literal (`data={{ html: '…' }}`).
- Use multiline template literals for mermaid: `chart={\`flowchart LR\n  A --> B\`}`.

## Workflow

1. Research the codebase (read-only). Delegate wide exploration to a sub-agent
   when useful.
2. Write `plan.mdx` into a plans folder for the current task. Prefer
   `plans/<slug>/plan.mdx` to check it into the repo, or
   `/tmp/visual-plan/<slug>/plan.mdx` for a throwaway. Add YAML frontmatter:
   ```mdx
   ---
   title: "Short plan title"
   ---
   ```
3. Render and open:
   ```bash
   node ~/.hermes/skills/software-development/visual-plan/renderer/render.mjs <path>/plan.mdx --open
   ```
   It writes `plan.html` next to the source and opens it in the default browser.
   The renderer prints `{"ok":true,"out":"…/plan.html","title":"…"}`.
4. Present the plan: include the `plan.html` path, name the files the work
   touches, and ask the user to approve before writing code.
5. When scope changes, edit `plan.mdx` and re-run the renderer; the document is
   the source of truth. Treat screenshots/visual feedback from the user as plan
   revisions first, not permission to start coding.
6. When user decisions close open questions (provider, naming, HA, cache TTL,
   extra columns, cron cadence), replace the Open Questions with a Decisions made
   section and update every affected diagram, file map, command block, rollout
   step, and validation. Re-render and verify stale alternatives disappeared.

## Diagram readability preferences

- For before/after architecture, sync pipelines, or parallel responsibilities,
  prefer vertical Mermaid (`flowchart TD`) over wide left-to-right diagrams. Wide
  horizontal diagrams become tiny in the rendered artifact and are hard to review.
- If multiple lanes are needed, use vertical subgraphs stacked in the same Mermaid
  block or separate Mermaid blocks rather than two long horizontal pipelines side
  by side.
- Keep node text short and place details in prose/tables below the diagram; the
  diagram should show ownership and flow, not every implementation detail.
- Quote Mermaid labels that contain punctuation, routes, operators, or code-ish
  tokens. Prefer `A["login/google or login/apple"]`, `B{"X-Token anonymous?"}`,
  and edge labels like `-- "yes" -->` over raw labels containing `/`, `::`,
  `->`, `=`, `+`, or underscores. If the HTML renders but Mermaid shows an
  error, simplify labels first, re-render, and only then present the plan.
- For SRP/refactor plans, model each independently scheduled unit explicitly:
  one service/class per sink or responsibility, one rake task/CronJob per cadence,
  and a shared provider/cache/facade for expensive cross-cutting dependencies.

  ambiguous graph syntax.
- For SRP/refactor plans, model each independently scheduled unit explicitly:
  one service/class per sink or responsibility, one rake task/CronJob per cadence,
  and a shared provider/cache/facade for expensive cross-cutting dependencies.

## Code preview sections

For implementation plans that the user will approve before coding, include a
short "Preview do código" section when useful. Keep it explicitly non-binding:
show controller/service/hook/spec skeletons with real file paths and realistic
method names, but label it as approximate so future implementation can adapt to
legacy helpers, serializers, and test factories discovered during coding.

See `references/decision-driven-plan-updates.md` for a compact example of updating
an infra plan from live evidence, external PR details, and user decisions.
See `references/srp-sync-visual-plans.md` for patterns when visualizing SRP sync
refactors with separate services, rake tasks/CronJobs, cadences, and shared
expensive dependencies such as embedding providers.

## First-run setup

The renderer needs its dependencies once:

```bash
npm install --prefix ~/.hermes/skills/software-development/visual-plan/renderer
```

Deps: `@mdx-js/mdx`, `react`, `react-dom`, `remark-gfm`, `remark-frontmatter`,
`remark-mdx-frontmatter`. No hosted service, no account.

## Customizing

Edit `renderer/components.mjs` to restyle blocks (CSS in `PAGE_CSS`) or add new
block components, then expose them in the `components` map. New blocks are just
React components returning HTML — keep them pure (no client JS) except mermaid,
which is rendered by the runtime injected in `page()`.
