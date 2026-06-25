---
name: sdd
description: Use when the user asks for /sdd, spec-driven development, or a test-first implementation plan from an approved visual plan. Converts a plan into RED/GREEN/REFACTOR specs, worktree setup, parallel subagent lanes, verification commands, and done criteria before coding.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [sdd, spec-driven-development, tdd, worktrees, subagents, planning]
    related_skills: [test-driven-development, visual-plan, github-pr-workflow]
---

# SDD — Spec-Driven Development

## Overview

Use SDD to turn an approved plan into an executable, test-first implementation script. The output is a markdown artifact that names the target contract, RED specs, expected failures, minimal GREEN implementation notes, worktree isolation, subagent lanes, verification commands, and done criteria.

SDD is stricter than a regular implementation plan: it must define the failing specs before production code, and it must identify what can be parallelized safely without splitting unresolved contracts across agents.

## When to Use

Use when the user says:

- `/sdd`
- `crie um sdd`
- `spec driven development`
- `faça um plano de specs`
- `implementar com specs primeiro`
- asks to parallelize implementation via subagents after a visual plan

Do not use for trivial one-line fixes unless the user explicitly requests SDD.

## Required Inputs

Before writing SDD, gather:

1. Approved or near-approved plan path, usually from `visual-plan`.
2. Repos involved and likely default branches.
3. Existing test frameworks and test file conventions.
4. Existing implementation patterns relevant to the fix.
5. Decisions already closed vs. still open.

If any of these are missing but discoverable, inspect files/repos directly. Ask only when the ambiguity changes the contract.

## Output Location

Prefer writing the SDD next to the visual plan:

```text
/tmp/visual-plan/<slug>/sdd.md
```

If the plan lives in a repo and should be versioned, write:

```text
plans/<slug>/sdd.md
```

Return only the path and short summary unless the user asks for inline content.

## SDD Structure

Use this structure:

```md
# SDD — <title>

Origem: `<plan path>`

Objetivo: <bug/feature in one paragraph>

Regra de execução: RED -> GREEN -> REFACTOR. Nenhum código de produção antes de uma spec falhando pelo motivo correto.

## Contrato alvo
...

## Sequência recomendada

### Fase 0 — preparar worktrees obrigatórias
...

### Fase 0.1 — baseline read-only dentro das worktrees
...

## Fase 1 — <first spec area>
...

## Paralelização via subagentes
...

## Comandos de verificação alvo
...

## Done criteria
...
```

## Worktree Discipline

Implementation SDDs should use worktrees by default when touching application repos, especially multi-repo or subagent work.

Rules:

- Do not implement in the checkout principal.
- Create dedicated worktrees before any RED spec.
- Subagents receive the worktree path, not the main repo path.
- Each lane edits only its assigned worktree/repo.
- Do not remove worktrees or broad paths without checking `git status`.
- If edits accidentally happened in the main checkout, save a patch, restore main, apply in the worktree, then rerun RED.

Template:

```bash
# Repo A
cd /path/to/repo-a
git fetch origin
DEFAULT_BRANCH=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')
mkdir -p ../worktrees
git worktree add -b fix/<slug> ../worktrees/<repo-a>-<slug> origin/$DEFAULT_BRANCH
cd ../worktrees/<repo-a>-<slug>
git status --short
```

Recovery:

```bash
cd /path/to/repo
git diff > /tmp/<slug>-<repo>.patch
git restore --source=HEAD --worktree --staged .
git worktree add -b fix/<slug> ../worktrees/<repo>-<slug> origin/<default-branch>
cd ../worktrees/<repo>-<slug>
git apply /tmp/<slug>-<repo>.patch
```

## RED/GREEN Spec Blocks

For each behavior, include:

- target file path;
- short purpose;
- spec sketch or precise assertions;
- expected RED failure;
- minimal GREEN implementation;
- verification command.

Example:

```md
### RED 1.1 — merge anonymous user into existing social account

Arquivo: `spec/services/anonymous_users/social_auth_spec.rb`

Spec:
- anon with active profile;
- existing permanent target by provider identity;
- Billing merge returns applied;
- profile stamped with `merged_into_user_id`;
- anon token rotated;
- result returns target.

RED esperado: `uninitialized constant AnonymousUsers::SocialAuth`.

GREEN mínimo:
- add service class;
- lookup identity owner;
- call Billing;
- stamp profile in transaction.
```

## Parallelization Rules

Split lanes by independent contract surfaces, not by random files.

Good lanes:

- backend service specs + implementation;
- backend controller/serializer specs;
- mobile hook specs;
- docs/plan updates;
- read-only investigation lane.

Do not parallelize:

- final response/API contract decisions;
- migrations/data writes/smoke with shared state;
- two agents editing the same file unless one is read-only or clearly sequenced;
- staging/prod validation that depends on a single deployed artifact.

Each lane must include:

```md
### Lane A — <name>

Responsável: subagente <n>

Escopo:
- Worktree: `<absolute path>`
- Files/behaviors owned by this lane
- Explicit exclusions

Dependências:
- What must be decided first

Entrega:
- RED/GREEN specs and passing commands
```

## Subagent Dispatch Guidance

When dispatching implementation subagents, pass:

- PT-BR output preference if the user is in PT-BR.
- Worktree path.
- Exact files/behaviors owned.
- TDD rule: write failing spec first, run it, then implement.
- Required commands.
- No writes outside assigned worktree.

Example:

```text
Implement Lane A using strict RED/GREEN/REFACTOR in /path/to/worktree. Write the failing spec first and run it to verify the expected failure before production code. Do not edit controllers or mobile files. Return changed files, RED output, GREEN output, and remaining risks.
```

## Verification Commands

Always include focused commands and a broader pre-PR command set.

Example:

```bash
cd /path/to/worktree
bundle exec rspec spec/services/path_spec.rb
bundle exec rspec spec/controllers/path_spec.rb

cd /path/to/mobile-worktree
npm test -- --runInBand useSocialAuthMutation
```

## Done Criteria

Every SDD must end with checkboxes or bullets for:

- every new behavior had a RED spec first;
- RED failure was expected, not a typo/setup error;
- GREEN verified with focused tests;
- broader suite or local equivalent run;
- legacy/no-op path preserved;
- multi-repo integration reconciled;
- staging/prod smoke executed or blocker documented;
- PR/ClickUp/report updated if applicable.

## Common Pitfalls

1. Writing production code preview as if it were implementation. In SDD, preview is allowed only as desired shape; actual code starts after RED.
2. Creating worktrees after editing. Worktrees come before RED specs.
3. Parallelizing an unresolved contract. Decide response shape and ownership first.
4. Letting subagents edit the same files concurrently. Split by service/controller/mobile or serialize.
5. Skipping RED because the test file is hard to set up. Hard setup indicates unclear design; sharpen the interface.
6. Reporting “plan done” without a file. SDD deliverable is a real `sdd.md` artifact.

## Verification Checklist

- [ ] SDD file written to disk.
- [ ] Source plan path referenced.
- [ ] Target contract explicit.
- [ ] Worktree commands included before RED specs.
- [ ] Each RED block has expected failure and minimal GREEN note.
- [ ] Parallel lanes have worktree paths and exclusions.
- [ ] Focused and broad verification commands included.
- [ ] Done criteria include RED/GREEN evidence and integration smoke.
