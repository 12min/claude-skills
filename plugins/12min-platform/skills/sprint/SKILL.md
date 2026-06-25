---
name: sprint
description: "List tasks from the current ClickUp sprint, optionally filtered by team member (Ricardo, Emir, Gui, Abras, Andrew, Cadu, Marcio, Rafa, Renato). Use whenever the user asks for current sprint tasks, their own tasks, someone else's tasks, sprint of <name>, what's in the sprint, or variations like 'sprint do Ricardo', 'tasks do Emir this week', 'what's in the sprint', 'team sprint'. Do NOT use for tasks outside the sprint (Side Quests, Bugs folder, Q2 projects) — use clickup-tasks skill instead."
---

# sprint

Lists tasks from the **current sprint** (folder `Sprints` in ClickUp). Defaults to filtering by the current user's tasks; accepts filter for any team member via `--user <name>`.

## Why this skill exists

`GET /list/{id}/task` **does not return multi-listed tasks** — only returns tasks whose "home" is that list. Sprint lists are populated via "Add to multiple lists": tasks live in Bugs/SideQuests/Project lists and are added to the sprint. The same applies to `GET /team/{id}/task?list_ids[]=` (home only).

**Current approach (2026-06):** scan the space (`GET /team/{id}/task?space_ids[]=`, paginated) and keep every task whose `list.id` **or** any entry in `locations[]` points to the sprint id. `locations[]` is how ClickUp exposes multi-list membership.

⚠️ The old route `GET /list/{id}/view` → `required_views.list.id` → `GET /view/{view_id}/task` **broke**: ClickUp now returns `required_views` as all `null` for these lists. Do not use.

## Script

The script is at `scripts/clickup_sprint.py` in this repo. On first use, copy it to `~/.claude/scripts/`:

```bash
cp <plugin-root>/scripts/clickup_sprint.py ~/.claude/scripts/clickup_sprint.py
```

```bash
# Current sprint, my open tasks (default)
python3 ~/.claude/scripts/clickup_sprint.py

# Current sprint, another team member's tasks (case-insensitive partial match)
python3 ~/.claude/scripts/clickup_sprint.py --user ricardo
python3 ~/.claude/scripts/clickup_sprint.py --user emir
python3 ~/.claude/scripts/clickup_sprint.py --user gui

# Current sprint, all assignees
python3 ~/.claude/scripts/clickup_sprint.py --all

# Include completed tasks
python3 ~/.claude/scripts/clickup_sprint.py --include-done

# Specific sprint
python3 ~/.claude/scripts/clickup_sprint.py --sprint 2026-05-04

# Filter by raw user id (overrides --user)
python3 ~/.claude/scripts/clickup_sprint.py --user-id 88097770

# Raw JSON output
python3 ~/.claude/scripts/clickup_sprint.py --json
```

Recognized names for `--user` (case-insensitive substring match against username + email):
| Name | User ID | Email |
|---|---|---|
| `renato` | 88097761 | renato.filho@12min.com |
| `ricardo` | 88097770 | ricardo@12min.com |
| `emir` | 88112551 | emir@12min.com |
| `gui` | 88112772 | gui@12min.com |
| `abras` | 88112560 | abras@12min.com |
| `andrew` | 88097767 | andrew@12min.com |
| `cadu` | 112080215 | carlos.farias@12min.com |
| `marcio` | 112080218 | marcio.vieira@12min.com |
| `rafa` | 463196 | rafa@12min.com |

If the name doesn't match the local table, the script queries the ClickUp team API.

## How to use

1. Run the script with appropriate flags based on the user's request.
2. Output comes pre-formatted in Markdown grouped by priority (🔴 Urgent / 🟠 High / 🔵 Normal / ⚪ Low / ⚫ No priority).
3. Display the output directly to the user (verbatim or lightly trimmed).

> ⚠️ **REQUIRED: use the `Bash` tool to run the script — never `ctx_execute` or sandbox.**
> The sandbox does not inherit shell variables (`~/.zprofile`), so `CLICKUP_API_KEY` is undefined and the script fails with `ERROR: CLICKUP_API_KEY not set`.

## Constants

- Space ID: `901312520244`
- Sprints folder ID: `901316000371`
- Sprint current = list whose name is the Monday of the current week (format `YYYY-MM-DD`).

## Environment variables

- `CLICKUP_API_KEY` — required (configure in `~/.zprofile` or shell profile)

## When NOT to use

- For tasks outside the sprint (Side Quests, Bugs folder, Q2 projects) → use `clickup-tasks` skill.
- To create/edit/move tasks → use the ClickUp API directly.
