---
name: create-traefik-worktree
description: Create a new Git worktree with Traefik multi-instance configuration pre-configured. Use when the user wants to create an isolated development environment for a new feature branch with unique ports and subdomain access.
argument-hint: "<worktree-name>"
---

# Create Traefik-Ready Worktree

Automates the creation of a new Git worktree with full Traefik multi-instance configuration pre-configured.

**Usage**: `/create-traefik-worktree <worktree-name>`

**Example**: `/create-traefik-worktree web-feature-auth`

## What it does

1. Creates a new Git worktree from the current HEAD
2. Copies the updated docker-compose.yml (with no hardcoded ports)
3. Generates docker-compose.override.yml with unique ports
4. Sets up environment variables
5. Optionally starts containers

## Arguments

- `<worktree-name>` (required): Name for the new worktree (e.g., `web-feature-auth`, `web-bugfix-123`)

## Result

After execution:
- New directory created: `$WEB_DIR/../{worktree-name}` (default: `~/Projects/{worktree-name}`)
- Accessible via subdomain: `http://{clean-name}.localhost`
- Unique ports for all services (no conflicts)
- Ready to run: `docker-compose up -d`

## Directory Structure Created

```
~/Projects/web-{name}/
├── docker-compose.yml           (updated - no hardcoded ports)
├── docker-compose.override.yml  (auto-generated with unique ports)
├── .env                         (updated with WORKTREE_NAME & WORKTREE_SUBDOMAIN)
├── bin/
│   ├── generate-override.sh     (copied from main repo)
│   └── ... (other scripts)
└── ... (all other repo files)
```

## Port Mapping Examples

For `web-feature-auth` (offset: XX):
- PostgreSQL: 5432+XX → unique port
- Redis: 6379+XX → unique port
- Elasticsearch: 9200+XX → unique port

## After Creation — Next Steps

```bash
# 1. Navigate to new worktree
cd ~/Projects/web-{name}

# 2. Start containers
docker-compose up -d

# 3. Access via browser
open http://{subdomain}.localhost

# 4. View logs
docker logs -f web-{name}-app
```

## Troubleshooting

- **"Port already allocated"**: Run `./bin/generate-override.sh` to regenerate.
- **"Permission denied"**: `chmod +x bin/generate-override.sh`
- **"502 Bad Gateway"**: Rails still booting. Wait 30-60s: `docker logs web-{name}-app | grep "Worker.*booted"`

## Related Documentation

- Full test results: `web/docs/TRAEFIK_MULTI_WORKTREE_TEST_RESULTS.md`
- Docker compose configuration: `web/docker-compose.yml`
- Override generation script: `web/bin/generate-override.sh`
