# 12min Claude Code Marketplace

Internal Claude Code plugins for the 12min engineering team. Skills, commands, and tooling shared across the org.

## Install

In any Claude Code session:

```
/plugin marketplace add 12min/claude-skills
/plugin install 12min-platform@12min
```

Update later:

```
/plugin update 12min-platform
```

## Available plugins

| Plugin | Description |
|---|---|
| **[12min-platform](./plugins/12min-platform/)** | Skills for the 12min platform — PR merge, Metabase, APM, Loki logs, ClickUp sprint, deploy monitor, worktree |

## Repo structure

```
.
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   └── 12min-platform/
│       ├── .claude-plugin/plugin.json
│       ├── README.md
│       ├── scripts/
│       │   └── clickup_sprint.py       ← ClickUp sprint script (copy to ~/.claude/scripts/ on first use)
│       ├── skills/
│       │   ├── apm/                    ← Elastic APM observability queries
│       │   ├── deploy-monitor/         ← post-deploy anomaly monitoring
│       │   ├── logcli-google-callbacks/ ← Google Play callback log analyzer
│       │   ├── logcli-ingress/         ← nginx/ingress log search via Loki
│       │   ├── merge-pr/               ← smart PR merge + CI/CD monitoring
│       │   ├── metabase/               ← Metabase analytics queries
│       │   ├── qa-plan/                ← QA plan generation
│       │   ├── roadmap-quarter/        ← quarterly roadmap slide
│       │   ├── sprint/                 ← ClickUp current sprint viewer
│       │   ├── sync-development/       ← recreate development branch from master
│       │   ├── upload-book-covers/     ← book cover upload workflow
│       │   └── worktree/               ← git worktree Docker Compose guide
│       └── commands/
└── README.md                           ← you are here
```

## Skills reference

| Skill | Trigger phrases |
|---|---|
| `apm` | APM data, endpoint latency, slowest routes, N+1 detection |
| `deploy-monitor` | monitor deploy, me avisa se der erro, watch for errors after deploy |
| `logcli-ingress` | nginx logs, 5xx errors, ingress logs, Loki ingress |
| `logcli-google-callbacks` | Google Play callbacks, IAP logs, subscription callbacks |
| `merge-pr` | merge PR, ship PR, close feature branch |
| `metabase` | Metabase, analytics query |
| `sprint` | sprint atual, tasks da sprint, sprint do Ricardo |
| `sync-development` | sync development, reset development branch |
| `worktree` | worktree guide, parallel testing, Docker Compose isolation |

## First-time setup for sprint skill

The `sprint` skill requires `clickup_sprint.py` in your `~/.claude/scripts/` directory:

```bash
cp plugins/12min-platform/scripts/clickup_sprint.py ~/.claude/scripts/
```

Also set `CLICKUP_API_KEY` in your `~/.zprofile`:
```bash
export CLICKUP_API_KEY="your_api_key_here"
```

## Contributing

PR-based. Each plugin lives under `plugins/<name>/` with its own `plugin.json` + `README.md`. Skills follow the standard `SKILL.md` format with YAML frontmatter (`name`, `description`).

## Access

Repo is private — only members of the `12min` GitHub org can clone. Adding/removing engineers from the org automatically grants/revokes plugin access.
