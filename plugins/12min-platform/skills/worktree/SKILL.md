---
name: worktree
description: Git Worktree Docker Compose isolation guide for the web repo. Use when the user wants to create a parallel worktree, run tests in isolation, manage multiple feature branches simultaneously, or learn about the worktree setup.
---

# Git Worktree — Docker Compose Isolation

Shows the Git Worktree Docker Compose Isolation guide for the 12min web repo, which explains how to create and manage isolated worktrees for parallel testing.

## Quick Start

```bash
# Create a worktree
git worktree add ../web-feature-name feature/branch-name
cd ../web-feature-name

# Start services (auto-configures!)
bin/worktree-compose up -d

# Run tests
bin/worktree-compose exec app bundle exec rspec
```

## Key Features

- Automatic port allocation (hash-based, deterministic)
- Unique container names per worktree
- Isolated PostgreSQL databases
- Zero manual configuration
- Backward compatible

## Usage Examples

**Create worktree and run tests simultaneously:**
```bash
# Terminal 1 - Feature A
git worktree add ../web-feature-a feature/auth
cd ../web-feature-a
bin/worktree-compose up -d
bin/worktree-compose exec app bundle exec rspec spec/models/

# Terminal 2 - Feature B (at same time)
git worktree add ../web-feature-b feature/api
cd ../web-feature-b
bin/worktree-compose up -d
bin/worktree-compose exec app bundle exec rspec spec/requests/
```

**Check port assignments:**
```bash
cat docker-compose.override.yml
```

**Cleanup:**
```bash
# Single worktree
bin/cleanup-worktree web-feature-a

# All worktrees
bin/cleanup-all-worktrees
```

## Port Mapping Algorithm

- Hash: `echo -n "worktree-name" | sum | awk '{print $1 % 100}'`
- Offset: 0-99 (deterministic)
- Each worktree gets unique ports: base_port + offset
- Supports 100+ simultaneous worktrees

## Available Scripts

- `bin/worktree-compose` - Main wrapper script (use instead of `docker compose`)
- `bin/cleanup-worktree <name>` - Remove single worktree
- `bin/cleanup-all-worktrees` - Remove all non-main worktrees

## Troubleshooting

**Port conflict?**
```bash
lsof -i :5447  # Check what's using the port
```

**Database not initialized?**
```bash
bin/worktree-compose exec app bundle exec rake db:create db:migrate
```

**Container naming conflict?**
```bash
docker ps -a | grep web-feature-name
docker rm -f web-feature-name-db web-feature-name-redis
```

## Documentation

- Quick reference: `web/CLAUDE.md` → "Git Worktree Testing" section
- Full guide: `web/docs/README-WORKTREE.md`
- Related PR: https://github.com/12min/web/pull/1072
