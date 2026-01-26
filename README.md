# Claude Code Custom Commands

This directory contains custom slash commands for 12min project workflows.

## Available Commands

### `/timer`

**Purpose**: Countdown timer with sound alert and notifications.

**Documentation**: `.claude/commands/timer.md`

**What it does**:
- Starts a countdown timer with MM:SS display format
- Updates display every second
- Plays sound alert when finished
- Shows system notification
- Supports various time formats (seconds, minutes, hours, combinations)

**Quick Usage**:
```bash
/timer 5m           # 5 minutes
/timer 30s          # 30 seconds
/timer 1h30m        # 1 hour 30 minutes
/timer 45           # 45 seconds (no unit defaults to seconds)
```

**Display Format**:
```
⏱️  Timer iniciado: 5:00

5:00
4:59
4:58
...
0:01

╔════════════════════════════════╗
║     ⏰ TEMPO FINALIZADO! ⏰      ║
╚════════════════════════════════╝
```

---

### `/create-traefik-worktree`

**Purpose**: Automatically create a new Git worktree with full Traefik multi-instance configuration.

**Documentation**: `.claude/commands/create-traefik-worktree.md`

**What it does**:
- Creates a new Git worktree
- Copies updated docker-compose.yml (with Traefik labels and networks)
- Generates docker-compose.override.yml with unique ports
- Configures environment variables
- Optionally starts containers

**Quick Usage**:
```bash
/create-traefik-worktree web-feature-auth
/create-traefik-worktree web-bugfix-123 --start
```

**Under the Hood**:
This command invokes the bash script at `/web/bin/create-traefik-worktree.sh` which automates:
1. `git worktree add`
2. Docker compose file copying
3. Override generation with unique port allocation
4. Container startup (optional)

---

## Setup for New Developers

1. **First time setup** (one-time):
   ```bash
   # Create Traefik network
   docker network create proxy-net

   # Start Traefik
   cd /Users/renatofilho/Projects/traefik
   docker-compose up -d
   ```

2. **Create your worktree**:
   ```bash
   /create-traefik-worktree web-my-feature
   ```

3. **Start developing**:
   ```bash
   cd /Users/renatofilho/Projects/web-my-feature
   docker-compose up -d

   # Access at http://my-feature.localhost
   ```

---

## Related Documentation

- **Quick Start Guide**: `/web/docs/TRAEFIK_WORKTREE_QUICKSTART.md`
- **Full Test Results**: `/web/docs/TRAEFIK_MULTI_WORKTREE_TEST_RESULTS.md`
- **Implementation Details**: `/web/docs/TRAEFIK_MULTI_WORKTREE_TEST_RESULTS.md`
- **Bash Script**: `/web/bin/create-traefik-worktree.sh`
- **Port Generation**: `/web/bin/generate-override.sh`

---

## Technical Overview

### Architecture

```
┌─ Traefik (Port 80) ─┐
│                    │
├─ master.localhost ──→ web-app:3000
├─ feature.localhost ─→ web-feature-app:3000
├─ test.localhost ────→ web-test-app:3000
└─ ...
```

### Port Allocation Strategy

Each worktree gets unique ports using hash-based offset:
```bash
PORT_OFFSET = $(echo -n "worktree-name" | cksum | awk '{print ($1 % 100)}')
```

**Benefits**:
- ✅ No port conflicts
- ✅ Deterministic (same result every time)
- ✅ Automatic (no manual management)
- ✅ Collision-free (modulo 100)

### Service Isolation

Each worktree has:
- ✅ Separate PostgreSQL container + volume
- ✅ Separate Redis container
- ✅ Separate Elasticsearch cluster
- ✅ Dedicated Traefik router
- ✅ Isolated internal network

---

## Troubleshooting

### Q: How do I create a new worktree?
A: Use `/create-traefik-worktree <name>` or `./bin/create-traefik-worktree.sh <name>`

### Q: What ports are used?
A: See port reference in `/web/docs/TRAEFIK_WORKTREE_QUICKSTART.md`

### Q: How do I access my app?
A: http://{subdomain}.localhost (subdomain = worktree name without "web-" prefix)

### Q: I'm getting 502 Bad Gateway
A: Rails is still booting. Wait 30-60 seconds and check: `docker logs -f web-{name}-app`

### Q: Port already allocated error
A: Regenerate override: `cd /web-{name} && ./bin/generate-override.sh && docker-compose down && docker-compose up -d`

### Q: Can't resolve hostname
A: Add to /etc/hosts: `127.0.0.1 {subdomain}.localhost`

---

## Advanced Usage

### Create multiple worktrees
```bash
for feature in auth payment dashboard; do
  /create-traefik-worktree web-feature-$feature &
done
wait
```

### Monitor all containers
```bash
watch 'docker ps --format "{{.Names}} | {{.State}}" | grep "^web"'
```

### Access any database
```bash
# Example: Connect to web-feature-auth database
psql -h localhost -p 5516 -U 12min -d postgres

# Find port: docker ps | grep "web-feature-auth-db"
```

### Clean up worktree
```bash
# Remove git worktree
git worktree remove web-old-branch

# Remove data volume
rm -rf pg-data-web-old-branch/

# Remove containers
docker ps -a | grep "web-old-branch" | awk '{print $1}' | xargs docker rm
```

---

## Performance Notes

- **Container Startup**: 30-60 seconds per worktree (Rails preloading)
- **Memory Usage**: ~800MB per worktree (Rails + PostgreSQL + Redis + Elasticsearch)
- **Disk Usage**: ~2GB per worktree
- **Network Overhead**: Minimal (internal Docker network)

### Recommendations

- **Recommended Max Concurrent Worktrees**: 3-4 on developer machine
- **Production Load**: Traefik can handle 100+ routers
- **Database**: PostgreSQL containers don't share connection pool (isolated)

---

## Files Modified

| File | Purpose |
|------|---------|
| `/web/docker-compose.yml` | Traefik labels + networks |
| `/web/bin/create-traefik-worktree.sh` | Worktree creation automation |
| `/web/bin/generate-override.sh` | Port offset calculation |
| `/traefik/docker-compose.yml` | Reverse proxy service |
| `/web/docs/TRAEFIK_WORKTREE_QUICKSTART.md` | User guide |
| `/web/docs/TRAEFIK_MULTI_WORKTREE_TEST_RESULTS.md` | Test results & architecture |

---

## Contributing

To improve these commands:

1. Update `/web/bin/create-traefik-worktree.sh` for script changes
2. Update `/web/docs/TRAEFIK_WORKTREE_QUICKSTART.md` for user-facing docs
3. Update this file for meta-documentation

---

**Last Updated**: 2025-12-18
**Status**: ✅ Production Ready
**Tested With**: 2 simultaneous worktrees, 0 port conflicts
