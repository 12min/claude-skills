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
| **[12min-platform](./plugins/12min-platform/)** | Skills for the 12min platform — PR merge workflow, Metabase, book covers upload |

More plugins (`dev-tools`, `design-system`, etc.) coming soon.

## Repo structure

```
.
├── .claude-plugin/
│   └── marketplace.json          ← marketplace registry (lists plugins below)
├── plugins/
│   └── 12min-platform/           ← first plugin
│       ├── .claude-plugin/plugin.json
│       ├── README.md
│       ├── skills/
│       │   ├── merge-pr/SKILL.md
│       │   ├── metabase/SKILL.md
│       │   └── upload-book-covers/SKILL.md
│       └── commands/
└── README.md                     ← you are here
```

## Loose files (not yet packaged)

These commands live in the repo root pending categorization into a future `dev-tools` plugin:

- `timer.md` — countdown timer command
- `news.md` — news fetcher
- `worktree.md` — git worktree helper
- `create-traefik-worktree.md` — worktree + Traefik isolation

## Contributing

PR-based. Each plugin lives under `plugins/<name>/` with its own `plugin.json` + `README.md`. Skills follow the standard `SKILL.md` format with YAML frontmatter (`name`, `description`).

## Access

Repo is private — only members of the `12min` GitHub org can clone. Adding/removing engineers from the org automatically grants/revokes plugin access.
