---
name: sync-development
description: Sync development branch — deletes and recreates the development branch from current master. Use when the user asks to sync development, reset the development branch, or recreate development from master.
---

# sync-development

Deletes and recreates the `development` branch of the web repo from the current `master` (local + remote).

## Usage

```
/sync-development
```

## Instructions

Execute the steps below **without asking for confirmation**:

1. Locate the web repo (defaults to `~/Projects/web`, override via `WEB_DIR` env):
   ```bash
   WEB_DIR="${WEB_DIR:-$HOME/Projects/web}"
   cd "$WEB_DIR"
   ```

2. Update local master:
   ```bash
   git checkout master && git pull origin master
   ```

3. Delete remote branch:
   ```bash
   git push origin --delete development
   ```

4. Delete local branch (if it exists):
   ```bash
   git branch -D development 2>/dev/null || true
   ```

5. Create new branch from master:
   ```bash
   git checkout -b development
   ```

6. Push new branch:
   ```bash
   git push origin development
   ```

7. Confirm result by showing the last commit of `development`:
   ```bash
   git log development -1 --format="✅ development recreated: %H %s"
   ```
