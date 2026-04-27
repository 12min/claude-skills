# 12min Platform

Skills and commands for engineers working on the 12min platform — Rails backend, Kubernetes deploys, Metabase analytics, and book content workflows.

## Skills

| Skill | Trigger | What it does |
|---|---|---|
| `merge-pr` | "merge PR", "ship PR" | Squash-merge PR with auto branch cleanup, development sync, and CI/CD deploy monitoring |
| `metabase` | "create Metabase question", "build dashboard" | Programmatic CRUD on `data.12min.com` Metabase via direct MySQL access |
| `upload-book-covers` | "upload book covers", "run cover experiment" | Bulk upload book covers for `new_cover_experiment` to prod via K8s pods (S3 + Paperclip + Thumbor) |

## Install

```
/plugin marketplace add 12min/claude-skills
/plugin install 12min-platform@12min
```

## Requirements

- Access to 12min GitHub org (private repo)
- `gh` CLI authenticated
- `kubectl` configured for `production` cluster (for `upload-book-covers`)
- MySQL access to Metabase internal DB (for `metabase`)

## Contributing

PR-based. See [CONTRIBUTING.md](../../docs/CONTRIBUTING.md) at repo root (TBD).
