# 12min Platform Plugin

Skills for engineers working on the 12min platform — observability, log analysis, sprint management, deploy monitoring, PR workflow, and more.

## Install

Open any Claude Code session and run:

```
/plugin marketplace add 12min/claude-skills
/plugin install 12min-platform@12min
```

To update later:

```
/plugin update 12min-platform
```

> **Requirement:** must be a member of the `12min` GitHub org (repo is private).

## Skills

| Skill | Trigger phrases | What it does |
|---|---|---|
| `apm` | APM data, endpoint latency, slowest routes, N+1 | Queries Elastic APM via SSH — latency, throughput, errors, N+1 detection |
| `deploy-monitor` | monitor deploy, me avisa se der erro | Generates a post-deploy monitoring script with Slack DM alerts |
| `logcli-ingress` | nginx logs, 5xx errors, ingress logs | Searches nginx/ingress logs via Loki (5xx, 4xx, tail, custom LogQL) |
| `logcli-google-callbacks` | Google callbacks, IAP logs | Fetches and decodes Google Play subscription callbacks from Loki |
| `merge-pr` | merge PR, ship PR | Squash-merge PR with branch cleanup and CI/CD monitoring |
| `metabase` | create Metabase question, build dashboard | CRUD on `data.12min.com` Metabase via direct MySQL |
| `qa-plan` | QA plan, test this PR | Generates a QA checklist for a PR or feature |
| `roadmap-quarter` | roadmap Q2, quarterly roadmap slide | Generates the weekly roadmap slide |
| `sprint` | sprint atual, tasks da sprint, sprint do Ricardo | Lists current ClickUp sprint tasks with team member filtering |
| `sync-development` | sync development, reset development branch | Recreates `development` branch from `master` |
| `upload-book-covers` | upload book covers | Bulk-uploads book covers to prod via K8s + S3 |
| `worktree` | worktree guide, parallel testing | Git worktree Docker Compose isolation guide for the web repo |
| `youtube-content` | YouTube summary, transcript, video notes | Fetches/transcribes YouTube content and formats it as summaries, chapters, threads, blogs, or Obsidian notes |

## First-time setup: sprint skill

The `sprint` skill depends on a Python script. Copy it once after installing:

```bash
# Find where Claude Code installed the plugin (usually ~/.claude/plugins/)
cp ~/.claude/plugins/12min-platform/scripts/clickup_sprint.py ~/.claude/scripts/
```

Set your ClickUp API key in `~/.zprofile`:

```bash
export CLICKUP_API_KEY="your_api_key_here"
```

Get your key at: **ClickUp → Settings → Apps → API Token**.

## Requirements

| Tool | Required by |
|---|---|
| `gh` CLI authenticated | `merge-pr` |
| `kubectl` → production cluster | `upload-book-covers`, `logcli-*`, `deploy-monitor` |
| `logcli` in PATH | `logcli-ingress`, `logcli-google-callbacks` |
| `gcloud` + IAP access | `apm`, `deploy-monitor` |
| `CLICKUP_API_KEY` env var | `sprint` |
| `uv`, `yt-dlp`, `ffmpeg` optional | `youtube-content` transcript/audio fallback |

## Contributing

PR-based against `main`. Each skill lives in `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`). See root [README.md](../../README.md) for repo structure.
