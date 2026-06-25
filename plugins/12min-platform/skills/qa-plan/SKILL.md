name: qa-plan
description: >
  Analisa um GitHub PR ou task do ClickUp e gera um plano de QA completo com:
  setup de ambiente, criação de dados no banco (via SQL), casos de teste
  (positivos e negativos), testes manuais no browser e cleanup.
  Use when: user asks to "montar QA", "criar plano de teste", "testar PR",
  "fazer QA da task", "qa do PR", ou similar.

---

# QA Plan Generator

## Input

Aceita um destes formatos como argumento:
- GitHub PR URL: `https://github.com/12min/web/pull/1234`
- GitHub PR número: `1234` ou `#1234` (assume repo `12min/web`)
- ClickUp task URL: `https://app.clickup.com/t/...`
- ClickUp task ID: `abc123xyz`

Se nenhum argumento fornecido, perguntar ao usuário qual PR/task antes de continuar.

---

## Fase A — Coletar informações

### GitHub PR

```bash
# Obter detalhes completos do PR
gh pr view <PR_NUMBER> --repo 12min/web \
  --json title,body,files,commits,baseRefName,headRefName,additions,deletions

# Obter URL do preview environment (gerado pelo GitHub Actions)
gh api repos/12min/web/issues/<PR_NUMBER>/comments \
  --jq '.[].body' | grep -A2 "Preview environment"
```

Depois ler os arquivos alterados usando `ctx_batch_execute` — não usar `cat` direto (flood context).

### ClickUp task

```bash
# Usar REST API (NÃO usar MCP tools — causam erro 502)
curl -s -H "Authorization: $CLICKUP_API_KEY" \
  "https://api.clickup.com/api/v2/task/<TASK_ID>" | \
  jq '{name, description, status, subtasks: [.subtasks[]?.name]}'
```

---

## Fase B — Analisar mudanças

Com base nas informações coletadas, identificar:

1. **O que mudou**: model methods, admin actions, controllers, jobs, CSS
2. **Casos felizes** (happy path): fluxo principal que deve funcionar
3. **Guards / predicates**: condições que bloqueiam ação — cada uma é um caso negativo
4. **Rate limits / locks**: checar se há limites de frequência ou pessimistic locks
5. **Jobs assíncronos**: verificar se algum job é enfileirado após ação
6. **Side effects visuais**: CSS, columns, labels que mudaram
7. **Dados necessários no banco**: quais estados de registros cobrem cada caso

---

## Fase C — Gerar o plano

Salvar o plano em `/Users/renatofilho/.claude/plans/qa-<slug>.md`
onde `<slug>` = PR number ou task ID.

### Estrutura obrigatória do plano

```markdown
# QA Plan — <título>

## Context
[O que muda e por quê. Link para PR/task.]
Ambiente: local Docker (http://localhost:3000) ou preview (URL do GA se disponível)

## Fase 0 — Environment Setup
[checkout branch + docker up OU verificar preview URL]

## Fase 1 — Data Setup
[SQL via `docker compose exec db psql` para local, ou `/database-staging` skill para staging]
[Um INSERT multi-row para todos os TCs de uma vez]
[RETURNING id para capturar IDs]
[Audit logs / registros auxiliares para edge cases]

## Fase 2 — Testes Automatizados
[rspec paths relevantes — apenas specs dos arquivos alterados]

## Fase 3 — Testes Manuais
### 3.x — Visibilidade / Guards
[Tabela: TC | URL | Esperado]

### 3.x — Happy Path
[Passo a passo detalhado: o que clicar, o que conferir, o que checar no banco]

### 3.x — Edge Cases
[Rate limit, lock, job assíncrono, etc.]

### 3.x — Regressão Visual
[CSS, colunas removidas, labels]

## Fase 4 — Cleanup
[DELETE SQL com WHERE guest_email LIKE 'qa-<slug>-%' ou marcador equivalente]
[Confirmar COUNT = 0]

## Checklist Final
[ ] item por TC + cleanup
```

---

## Regras de geração

### Naming convention de dados de teste
- `guest_email` / `email` / campos identificadores: sempre `qa-<slug>-tc<N>@example.com`
- Facilita cleanup com `LIKE 'qa-<slug>-%'`

### SQL preferido a Rails console
- Rails console tem boot lento (~30s)
- Usar `docker compose exec db psql -U postgres -d twelve_min_development` para local
- Usar skill `/database-staging` para staging
- JSON em SQL: usar `'{}'::jsonb` (evitar backslash escape em shells aninhados)
- `generate_series` para criar múltiplos registros auxiliares (ex: audit logs de rate limit)

### Ambiente
- **Local**: `http://localhost:3000/admin` — branch checked out + `docker compose up -d`
- **Preview**: URL do comentário do GitHub Actions no PR (formato `https://api-preview-<PR>.12min.com`)
  - ⚠️ Preview usa staging database — dados de teste devem ser limpos no cleanup
  - ⚠️ Preview pode ter instabilidade de recursos — preferir local

### Casos de teste mínimos
Sempre cobrir:
- Pelo menos 1 happy path (com verificação de todos os campos alterados)
- Todos os guards/predicates como casos negativos separados
- Rate limit / lock se existir
- Jobs assíncronos (verificar Sidekiq)
- Regressão de CSS / colunas se houver mudanças visuais

### Cleanup
- Sempre incluir Fase 4 com DELETE e confirmação (`SELECT COUNT(*) = 0`)
- Remover registros na ordem correta: dependentes primeiro (audit_logs → gift_invites)
- Para admin users de QA: incluir no cleanup se criados

---

## Fase D — Perguntar antes de executar

Depois de salvar o plano, perguntar:

> "Plano salvo em `<path>`. Quer que eu execute agora (setup de dados + testes no browser) ou prefere revisar primeiro?"

Se usuário pedir execução:
1. Fase 1: rodar SQL de setup
2. Fase 2: rodar rspec via `ctx_execute`
3. Fase 3: usar `mcp__Claude_in_Chrome__*` para testes no browser
4. Fase 4: rodar SQL de cleanup

---

## Contexto da plataforma 12min

- **Rails app (web)**: `http://localhost:3000`, Docker via `docker compose exec app`
- **DB local**: `docker compose exec db psql -U postgres -d twelve_min_development`
- **DB staging**: usar skill `/database-staging` (kubectl exec no pod api-staging)
- **Admin**: `/admin/login` (não `/admin/sign_in`)
- **ClickUp API**: REST direto com `$CLICKUP_API_KEY` (não MCP tools — 502 errors)
- **kubectl**: sempre usar `--context` flag, nunca aliases `kubectl-production/staging`
- **Sidekiq Web UI**: `http://localhost:3000/admin/sidekiq`
