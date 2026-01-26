Show the Git Worktree Docker Compose Isolation guide from CLAUDE.md

**What this command does:**
Displays the complete "Git Worktree Testing" section from the web project's CLAUDE.md file, which explains how to:
- Create and manage Git worktrees
- Run tests simultaneously in multiple worktrees
- Achieve database isolation per worktree
- Troubleshoot common issues

**Quick Start:**
```bash
# Create a worktree
git worktree add ../web-feature-name feature/branch-name
cd ../web-feature-name

# Start services (auto-configures!)
bin/worktree-compose up -d

# Run tests
bin/worktree-compose exec app bundle exec rspec
```

**Key Features:**
- Automatic port allocation (hash-based, deterministic)
- Unique container names per worktree
- Isolated PostgreSQL databases
- Zero manual configuration
- Backward compatible

**For detailed information, see:**
- `/Users/renatofilho/Projects/web/CLAUDE.md` - "Git Worktree Testing" section
- `/Users/renatofilho/Projects/web/docs/README-WORKTREE.md` - Comprehensive guide (500+ lines)

**Available Scripts:**
- `bin/worktree-compose` - Main wrapper script (use instead of `docker compose`)
- `bin/cleanup-worktree <name>` - Remove single worktree
- `bin/cleanup-all-worktrees` - Remove all non-main worktrees

**Related Pull Request:**
https://github.com/12min/web/pull/1072

**Usage Examples:**

1. **Create worktree and run tests simultaneously:**
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

2. **Check port assignments:**
   ```bash
   cat docker-compose.override.yml
   ```

3. **Database isolation verification:**
   ```bash
   # Worktree A
   bin/worktree-compose exec app bundle exec rails console
   > User.create!(email: 'test@a.com', password: '123')

   # Worktree B (different database)
   bin/worktree-compose exec app bundle exec rails console
   > User.count
   => 0  # Empty - complete isolation!
   ```

4. **Cleanup:**
   ```bash
   # Single worktree
   bin/cleanup-worktree web-feature-a

   # All worktrees
   bin/cleanup-all-worktrees
   ```

**Port Mapping Algorithm:**
- Hash: `echo -n "worktree-name" | sum | awk '{print $1 % 100}'`
- Offset: 0-99 (deterministic)
- Each worktree gets unique ports: base_port + offset
- Supports 100+ simultaneous worktrees

**Troubleshooting:**

Port conflict?
```bash
lsof -i :5447  # Check what's using the port
```

Database not initialized?
```bash
bin/worktree-compose exec app bundle exec rake db:create db:migrate
```

Container naming conflict?
```bash
docker ps -a | grep web-feature-name
docker rm -f web-feature-name-db web-feature-name-redis
```

**For complete documentation, read:**
- Quick reference: `CLAUDE.md` → "Git Worktree Testing"
- Full guide: `docs/README-WORKTREE.md`
