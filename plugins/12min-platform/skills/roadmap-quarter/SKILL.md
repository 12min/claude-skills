---
name: roadmap-quarter
description: "Gera/atualiza o roadmap timeline HTML de um trimestre. Mostra 13 semanas com tasks por sprint multi-listadas, gap-fill de semanas sem sprint, células coloridas por % done, backlog destacado. Use quando o usuário pedir roadmap, timeline trimestral, plano de trimestre, status dos projetos, atualizar roadmap, gerar roadmap dos projetos, ou variações."
---

# roadmap-quarter

Gera arquivo HTML de roadmap trimestral em `${ROADMAP_OUTPUT_DIR}/roadmap-YYYY-QN-timeline.html`. Layout: linha por projeto, coluna por semana ISO (13 colunas para um trimestre), célula colorida por % done, coluna de backlog separada.

## Usage

```
/roadmap-quarter
```

Argumento opcional: trimestre no formato `YYYY-QN` (ex: `2026-Q2`). Default: trimestre atual.

## Configuração

| Var | Valor |
|-----|-------|
| `CLICKUP_API_KEY` | env var (obrigatório) |
| `ROADMAP_OUTPUT_DIR` | env var. Default: `~/Projects/self-management/roadmaps/` |
| Team ID | `9013887712` |
| Sprint folder ID | `901316000371` |

Resolução do output dir (em ordem):

1. `$ROADMAP_OUTPUT_DIR` se definido
2. `~/Projects/self-management/roadmaps/` se o repo `self-management` existir nesse path
3. `./roadmaps/` (relativo ao cwd) como último fallback — cria se não existir

O HTML final usa o path absoluto resolvido. Logue o destino escolhido no chat.

## Projetos default (Q2 2026)

Editar a constante `projects` no script para o conjunto desejado. Default Q2:

| List ID | Nome | Categoria |
|---------|------|-----------|
| `901327088461` | Conta Simples MVP | Side Project |
| `901327054893` | Hub UI (Renato/Ricardo) | Side Project |
| `901327113292` | Gift Link 12min | Side Project |
| `901326443330` | Anonymous User Individualization | Q2 Personal |
| `901326444253` | Billing DB Simplification | Q2 Personal |
| `901326482056` | Lean Up / Refactoring | Q2 Personal |

Plus a **synthetic** `__SIDE__` row (Ad-hoc / Side Tasks) — see section below.

## Side Tasks (linha sintética)

Tasks atribuídas ao usuário que tocaram alguma sprint Q2 mas **não** estão em nenhum dos 6 projetos principais. Cobre support tickets, SEO ad-hoc, side quests, bugs avulsos, CRs, demandas pontuais.

### Como derivar

```python
SPRINT_LISTS = set(sprint_to_date.keys())  # all Q2 sprint list ids
PROJECT_LISTS = {6 project list ids}

# Pull team-wide Renato tasks within Q2 update window (date_updated_gt/lt)
all_tasks = team_task_filter(assignees=[me], date_updated in [Q2_start, Q2_end+30d])

side = []
for t in all_tasks:
    locs = {t['list']['id']} | {l['id'] for l in t.get('locations',[])}
    if (locs & SPRINT_LISTS) and not (locs & PROJECT_LISTS):
        side.append(t)
```

### Render

Adiciona como projeto sintético `__SIDE__` no `data` dict, com cor vermelha (`#dc2626/#fecaca/#fff7f7`). Renderiza em sua própria seção: **"Ad-hoc / Side Tasks (support, SEO, etc.)"**.

### Header badge

Separar contagem: `{project_done}/{project_total} project tasks · {side_done}/{side_total} side · {pts}p`. Side tasks **não** entram no agregado de pontos do trimestre (na maioria não têm pts atribuídos).

## Algoritmo (importante para futuras atualizações)

### 1. Computa intervalo do trimestre

13 semanas (Mondays). Para Q2 2026: `2026-04-06` até `2026-06-29`.

### 2. Mapeia sprint lists existentes

`GET /folder/{sprint_folder}/list` → mapeia `list_id → sprint_date` para listas cujo nome bate em `YYYY-MM-DD` dentro do trimestre.

### 3. Coverage com gap-fill

Quando uma semana não tem sprint criada (ex: 12min pulou `2026-04-20`), a sprint **seguinte** absorve aquela semana. Para cada sprint date `S`:

```
prev_sprint_date = sprint anterior na ordem (ou None)
covers = todas as Mondays entre (prev+7d) e S, inclusive
```

Exemplo Q2 2026:
- `2026-04-06` cobre `[2026-04-06]`
- `2026-04-13` cobre `[2026-04-13]`
- `2026-04-27` cobre **`[2026-04-20, 2026-04-27]`** ← gap fill!
- `2026-05-04` cobre `[2026-05-04]`

### 4. Bin de tasks em semanas (multi-week)

Para cada task de cada projeto:

```python
weeks = set()

# (a) Sprint membership: home + locations[]
for list_id in [home_list, *location_list_ids]:
    if list_id ∈ sprint_to_date:
        weeks.update(sprint_coverage[sprint_to_date[list_id]])

# (b) date_done fallback (para tasks sem sprint membership)
if is_done and date_done:
    monday = Monday(date_done)
    if no_sprint_membership and monday ∈ week_to_sprint:
        # Spread done task across the full sprint span containing the done week
        weeks.update(sprint_coverage[week_to_sprint[monday]])
    else:
        weeks.add(monday)

# (c) Sem nada → backlog
if not weeks: weeks = {"backlog"}
```

**Por que multi-week:** uma task carregada via `Add to multiple lists` ao longo de 3 sprints (ex: W15+W16+W17) aparece nas 3 colunas — visualiza carry-over real.

### 5. Render HTML

- Header: top-bar + page badge com totais agregados (`done/total tasks · done/total pts`).
- 1 timeline div por categoria (Side Projects, Q2 Personal Lists).
- 1 row por projeto: label esquerda + 13 cells weekly + backlog à direita.
- Cell de semana passada/atual: gradient horizontal mostra `% done`.
- Cell de semana futura: striped diagonal (planejada, não executada).
- Cell vazia: dashed border.
- Backlog cell: amarelo, mostra count + pts.

## Pitfalls conhecidos (do que aprendi)

1. **`team/{id}/task?list_ids[]=` NÃO retorna multi-listed tasks** — só home list. Para sprint atual usa `clickup_sprint.py` com view endpoint, mas funciona só se a list tem default view configurada.

2. **`include_markdown_description=true` é OBRIGATÓRIO** quando se quer ler markdown formatado — default só retorna `description` (texto cru sem formatação). Usado nas leituras de tasks individuais.

3. **`task['list']['id']` vs `task['locations']`:**
   - `list` = home list (1 só)
   - `locations` = lists adicionais via "Add to multiple lists"
   - Sprint membership precisa olhar **ambos**.

4. **Home list não pode ser removida via REST API** (`TASK_035 "Task home list cannot be altered"`). Tasks na sprint errada precisam ser movidas via UI ClickUp (botão Move).

5. **`/list/{id}/task` cache:** após `POST /list/{id}/task/{tid}` (multi-list add), o endpoint pode demorar segundos pra refletir. Use `task['locations']` na task individual para verificar.

6. **Semanas sem sprint criada:** time pula semanas (ex: 04-20). Sprint seguinte absorve via `sprint_coverage` gap-fill.

7. **Tasks sem sprint membership mas com `date_done`** dentro de uma semana coberta por sprint: spread across full sprint span (Hub UI ex: closed Apr 30 → aparece em W17 e W18).

8. **Quando regenerar HTML, NÃO use `re.sub` para patchear** — fácil quebrar e duplicar seções. Reescreva o arquivo todo a partir dos dados.

9. **SEMPRE `subtasks=true&include_closed=true`** em `/list/{id}/task` E `team/{id}/task`. Default omite subtasks — tasks broken into POC subtasks (ex: Hub UI tech[10] n8n, 10 subtasks Wed 13/05) ficam invisíveis no roadmap E em totals. Após fetch, dedup por `id` (API pode retornar mesma id em páginas diferentes quando subtasks=true). Subtasks normalmente sem `locations` — herdam só `list_id` do pai → bin via `date_done` fallback funciona.

## Como atualizar

### Cenário 1: Re-pull data + regenerate

```bash
# Apenas roda o skill — re-fetcha do ClickUp e regenera HTML
/roadmap-quarter 2026-Q2
```

### Cenário 2: Override manual em uma célula

Editar `/tmp/roadmap_timeline.json` flipando `is_done` ou `weeks` de tasks específicas, depois rodar só a parte de render.

Exemplo: marcar todas as tasks de Conta Simples na W19 como done (porque só falta review):

```python
import json
data=json.load(open('/tmp/roadmap_timeline.json'))
W='2026-05-04'
for t in data['901327088461']['tasks']:
    if W in t['weeks']: t['is_done']=True
json.dump(data, open('/tmp/roadmap_timeline.json','w'))
```

Em seguida rodar só o render block do skill.

### Cenário 3: Adicionar/remover projetos

Editar a const `projects` no top do script — chave = list_id, valor = nome. Adicionar entrada correspondente em `PROJ_COLOR` (cor primária + border + bg).

### Cenário 4: Trimestre diferente

Mudar `start = datetime(YYYY, 4 ou 7 ou 10 ou 1, 6)` (primeira segunda do trimestre) e ajustar `Q2_START`/`Q2_END` no fetch.

## Output

```
file://${ROADMAP_OUTPUT_DIR}/roadmap-YYYY-QN-timeline.html
```

Mostrar resumo no chat:

- Path absoluto do arquivo gerado (resolvido conforme regra acima)
- Totais agregados (done/total tasks, pts)
- Quais projetos têm progresso vs estão em backlog
- Sinais (deadlines apertados, projetos parados)

## Script

Implementação completa em Python embutida no skill — não vive em arquivo separado. Reusa:

- ClickUp REST: `/folder/{f}/list`, `/list/{l}/task` (paginado, `include_closed=true&subtasks=true`)
- Render: HTML/CSS inline, sem JS, fontes do Google (Inter)
- Layout: CSS grid 13 cols + label/backlog edges
