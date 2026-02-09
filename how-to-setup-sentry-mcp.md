# How to Setup Sentry MCP

Este guia explica como configurar o Sentry MCP (Model Context Protocol) para integrar o Sentry com Claude Code.

## O que é Sentry MCP?

O Sentry MCP é um servidor de protocolo que permite ao Claude Code interagir diretamente com sua instância do Sentry para:
- Buscar e analisar issues/erros
- Consultar traces e eventos
- Obter detalhes de releases
- Criar e atualizar projetos
- Gerenciar times e organizações
- Analisar issues com Seer (AI do Sentry)
- Consultar documentação do Sentry

## Pré-requisitos

- Node.js instalado (para executar `npx`)
- Acesso a uma instância do Sentry (cloud ou self-hosted)
- Permissões para criar tokens de autenticação no Sentry

## Passo 1: Obter as Credenciais do Sentry

### 1.1. Auth Token

Você precisa de um token de autenticação com as permissões necessárias:

1. Acesse sua instância do Sentry
2. Vá em **Settings** → **Account** → **API** → **Auth Tokens**
3. Clique em **Create New Token**
4. Configure as permissões necessárias:
   - `project:read` - Ler projetos
   - `project:write` - Criar/atualizar projetos
   - `team:read` - Ler times
   - `team:write` - Criar times
   - `org:read` - Ler organizações
   - `event:read` - Ler eventos e issues
   - `event:write` - Atualizar issues
5. Copie o token gerado (começa com `sntryu_...`)

**⚠️ IMPORTANTE**: Guarde este token em local seguro. Ele dá acesso à sua organização no Sentry.

### 1.2. Organization Slug

O slug da sua organização pode ser encontrado:
- Na URL do Sentry: `https://sentry.io/organizations/[SLUG]/`
- Ou em **Settings** → **Organization Settings** → **General Settings**

Exemplo: `12min`, `my-company`, etc.

### 1.3. Sentry URL

- **Sentry Cloud**: `https://sentry.io`
- **Self-hosted**: URL da sua instância (ex: `https://sentry.12min.com`)

## Passo 2: Configurar o MCP

### 2.1. Localizar o arquivo de configuração

O arquivo de configuração do MCP fica em:
```
~/.claude/mcp.json
```

Se o arquivo não existir, crie-o:
```bash
mkdir -p ~/.claude
touch ~/.claude/mcp.json
```

### 2.2. Adicionar a configuração do Sentry

Edite o arquivo `~/.claude/mcp.json` e adicione a seguinte configuração:

```json
{
  "mcpServers": {
    "sentry": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-sentry"
      ],
      "env": {
        "SENTRY_AUTH_TOKEN": "SEU_TOKEN_AQUI",
        "SENTRY_ORG_SLUG": "sua-org",
        "SENTRY_URL": "https://sentry.io"
      }
    }
  }
}
```

**Exemplo completo (com self-hosted Sentry):**
```json
{
  "mcpServers": {
    "sentry": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-sentry"
      ],
      "env": {
        "SENTRY_AUTH_TOKEN": "sntryu_your_actual_token_here",
        "SENTRY_ORG_SLUG": "your-org-name",
        "SENTRY_URL": "https://sentry.yourcompany.com"
      }
    }
  }
}
```

### 2.3. Se já existirem outros MCPs

Se o arquivo já tiver outros servidores MCP configurados, adicione o Sentry dentro do objeto `mcpServers`:

```json
{
  "mcpServers": {
    "existing-server": {
      "command": "...",
      "args": [...]
    },
    "sentry": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-sentry"
      ],
      "env": {
        "SENTRY_AUTH_TOKEN": "SEU_TOKEN_AQUI",
        "SENTRY_ORG_SLUG": "sua-org",
        "SENTRY_URL": "https://sentry.io"
      }
    }
  }
}
```

## Passo 3: Testar a Configuração

### 3.1. Reiniciar Claude Code

Após salvar o arquivo, reinicie o Claude Code para carregar as novas configurações.

### 3.2. Verificar ferramentas disponíveis

No Claude Code, as seguintes ferramentas do Sentry devem estar disponíveis (use `ToolSearch` para carregá-las):

- `mcp__sentry__whoami` - Verificar autenticação
- `mcp__sentry__find_organizations` - Listar organizações
- `mcp__sentry__find_teams` - Listar times
- `mcp__sentry__find_projects` - Listar projetos
- `mcp__sentry__list_issues` - Listar issues
- `mcp__sentry__get_issue_details` - Detalhes de uma issue
- `mcp__sentry__update_issue` - Atualizar issue
- `mcp__sentry__analyze_issue_with_seer` - Análise com IA
- `mcp__sentry__search_docs` - Buscar documentação
- `mcp__sentry__get_trace_details` - Detalhes de trace
- E muitas outras...

### 3.3. Teste básico

Peça ao Claude Code para verificar a autenticação:

```
Verifique se a conexão com o Sentry está funcionando usando o whoami
```

O Claude deve usar a ferramenta `mcp__sentry__whoami` e retornar informações sobre o usuário autenticado.

## Recursos Disponíveis

### Issues e Eventos
- Listar issues por projeto/organização
- Obter detalhes completos de uma issue (stack trace, breadcrumbs, tags)
- Listar eventos de uma issue
- Atualizar status de issues (resolve, ignore, assign)
- Obter valores de tags

### Projetos e Times
- Listar projetos da organização
- Criar novos projetos
- Atualizar configurações de projeto
- Listar times
- Criar times

### Releases e Deploys
- Listar releases de um projeto
- Obter detalhes de release

### DSNs (Data Source Names)
- Criar novos DSNs para ingestão de dados
- Listar DSNs de um projeto

### Traces e Performance
- Obter detalhes de traces
- Analisar performance

### Análise com IA (Seer)
- Análise automática de issues usando Seer do Sentry
- Sugestões de causa raiz e soluções

### Documentação
- Buscar na documentação do Sentry
- Obter documentos específicos

## Exemplos de Uso

### Listar issues recentes
```
Liste as 10 issues mais recentes do projeto web
```

### Analisar uma issue específica
```
Analise a issue SENTRY-123 e sugira possíveis causas
```

### Buscar erros por tag
```
Busque todas as issues com a tag environment:production nas últimas 24 horas
```

### Criar um novo projeto
```
Crie um novo projeto chamado "mobile-app" no time "engineering"
```

## Segurança

### Boas Práticas

1. **Nunca commite tokens**: Adicione `.claude/mcp.json` ao `.gitignore` se estiver versionando configurações
2. **Use tokens com escopo limitado**: Crie tokens com apenas as permissões necessárias
3. **Rotacione tokens regularmente**: Revogue e recrie tokens periodicamente
4. **Não compartilhe tokens**: Cada desenvolvedor deve ter seu próprio token

### Protegendo o Token

Se você precisar versionar a configuração (ex: em repositório privado), considere usar variáveis de ambiente:

```json
{
  "mcpServers": {
    "sentry": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sentry"],
      "env": {
        "SENTRY_AUTH_TOKEN": "${SENTRY_AUTH_TOKEN}",
        "SENTRY_ORG_SLUG": "${SENTRY_ORG_SLUG}",
        "SENTRY_URL": "${SENTRY_URL}"
      }
    }
  }
}
```

E exporte as variáveis no seu shell:
```bash
export SENTRY_AUTH_TOKEN="sntryu_..."
export SENTRY_ORG_SLUG="12min"
export SENTRY_URL="https://sentry.12min.com"
```

## Troubleshooting

### Erro: "Authentication failed"
- Verifique se o token está correto e não expirou
- Confirme que o token tem as permissões necessárias
- Teste o token diretamente via API: `curl -H "Authorization: Bearer TOKEN" https://sentry.io/api/0/`

### Erro: "Organization not found"
- Verifique se o `SENTRY_ORG_SLUG` está correto
- Confirme que o token tem acesso à organização

### Ferramentas não aparecem
- Reinicie o Claude Code após editar `mcp.json`
- Verifique se o arquivo JSON está válido (sem erros de sintaxe)
- Use `ToolSearch` para carregar as ferramentas do Sentry

### Erro: "npx not found"
- Instale Node.js: `brew install node` (macOS) ou `apt install nodejs` (Linux)
- Verifique a instalação: `npx --version`

## Referências

- [Sentry MCP Server](https://github.com/modelcontextprotocol/servers/tree/main/src/sentry)
- [Sentry API Documentation](https://docs.sentry.io/api/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Claude Code Documentation](https://claude.ai/code)

## Contribuindo

Se você encontrar problemas ou tiver sugestões de melhorias para este guia, abra uma issue ou PR no repositório do projeto.

---

**Última atualização**: 2026-02-09
**Mantido por**: Time de Engenharia 12min
