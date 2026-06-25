#!/usr/bin/env python3
"""
Pull current sprint tasks from ClickUp (folder Sprints) for any team member.

Usage:
    python3 clickup_sprint.py                    # current sprint, my open tasks
    python3 clickup_sprint.py --all              # current sprint, ALL assignees, all statuses
    python3 clickup_sprint.py --include-done     # include completed tasks
    python3 clickup_sprint.py --sprint 2026-05-04  # explicit sprint by name
    python3 clickup_sprint.py --user ricardo     # filter by team member name (case-insensitive partial match)
    python3 clickup_sprint.py --user-id 88097761 # filter by raw user id

Why this script exists:
    GET /list/{id}/task only returns tasks WHOSE HOME is that list. Sprint lists are
    populated via "Add to multiple lists" — tasks live in Bugs/SideQuests/Project lists
    and are multi-listed into the weekly sprint. The correct endpoint is the default
    list view: GET /list/{id}/view → required_views.list.id → GET /view/{view_id}/task.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.parse
import urllib.request

API = "https://api.clickup.com/api/v2"
TEAM_ID = "9013887712"
SPACE_ID = "901312520244"
SPRINTS_FOLDER_ID = "901316000371"
DEFAULT_USER_ID = 88097761  # Renato Filho

# Quick lookup table for common names → user IDs (avoids API call on most invocations).
# Match is case-insensitive substring; the first match wins (order matters here).
TEAM_MEMBERS: list[tuple[int, str, str]] = [
    (88097761, "renato", "renato.filho@12min.com"),
    (88097770, "ricardo", "ricardo@12min.com"),  # Luis Ricardo
    (88112551, "emir", "emir@12min.com"),
    (88112772, "gui", "gui@12min.com"),
    (88112560, "abras", "abras@12min.com"),
    (88097767, "andrew", "andrew@12min.com"),
    (112080215, "cadu", "carlos.farias@12min.com"),
    (112080218, "marcio", "marcio.vieira@12min.com"),
    (463196, "rafa", "rafa@12min.com"),
]

CLOSED_STATUSES = {"complete", "closed", "done", "canceled", "cancelled"}


def resolve_user(name: str) -> int:
    """Resolve a name (case-insensitive partial match) to a user id.

    Tries the local TEAM_MEMBERS table first; falls back to the team API if no match.
    """
    needle = name.lower().strip()
    for uid, nname, email in TEAM_MEMBERS:
        if needle in nname or needle in email:
            return uid
    # Fallback: query the team API
    try:
        d = fetch(f"{API}/team")
        for t in d.get("teams", []):
            if t.get("id") != TEAM_ID:
                continue
            for m in t.get("members", []):
                u = m.get("user", {}) or {}
                username = (u.get("username") or "").lower()
                email = (u.get("email") or "").lower()
                if needle in username or needle in email:
                    return int(u.get("id"))
    except Exception:
        pass
    sys.exit(f"ERROR: no team member found matching '{name}'. Known: {', '.join(n for _, n, _ in TEAM_MEMBERS)}")


def api_key() -> str:
    k = os.environ.get("CLICKUP_API_KEY")
    if not k:
        sys.exit("ERROR: CLICKUP_API_KEY not set")
    return k


def fetch(url: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": api_key()})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def current_sprint_list(today: dt.date | None = None) -> dict:
    today = today or dt.date.today()
    monday = today - dt.timedelta(days=today.weekday())
    name = monday.isoformat()
    folder = fetch(f"{API}/space/{SPACE_ID}/folder?archived=false")
    sprints_folder = next(
        (f for f in folder.get("folders", []) if f.get("id") == SPRINTS_FOLDER_ID),
        None,
    )
    if not sprints_folder:
        sys.exit("ERROR: Sprints folder not found")
    for lst in sprints_folder.get("lists", []):
        if lst.get("name") == name:
            return lst
    raise SystemExit(f"ERROR: no sprint list for week starting {name}")


def sprint_list_by_name(name: str) -> dict:
    folder = fetch(f"{API}/space/{SPACE_ID}/folder?archived=false")
    sprints_folder = next(
        (f for f in folder.get("folders", []) if f.get("id") == SPRINTS_FOLDER_ID),
        None,
    )
    if not sprints_folder:
        sys.exit("ERROR: Sprints folder not found")
    for lst in sprints_folder.get("lists", []):
        if lst.get("name") == name:
            return lst
    raise SystemExit(f"ERROR: sprint list '{name}' not found")


def sprint_tasks(sprint_id: str, space_id: str = SPACE_ID) -> list[dict]:
    """Return every task in the sprint list — home tasks AND multi-listed ones.

    The old approach (GET /list/{id}/view -> /view/{view_id}/task) broke: ClickUp
    now returns null required_views for these lists, so there is no view id to query.
    GET /team/{id}/task?list_ids[]= only returns tasks whose HOME is the list, so it
    silently drops the multi-listed ones (the whole point of a sprint list).

    Robust fix: scan the space once and keep any task whose home list OR its
    `locations` array references the sprint list id. `locations` is how ClickUp
    exposes "Add to multiple lists" membership. Heavier (scans the space) but correct.

    Limitation: a task multi-listed into the sprint from a DIFFERENT space is not
    caught. All current sprint sources live in SPACE_ID, so this holds in practice.
    """
    out = []
    page = 0
    while page < 60:  # safety cap; a space rarely exceeds a few thousand tasks
        url = (
            f"{API}/team/{TEAM_ID}/task"
            f"?space_ids[]={space_id}&subtasks=true&include_closed=true&page={page}"
        )
        d = fetch(url)
        ts = d.get("tasks", [])
        if not ts:
            break
        out.extend(ts)
        if d.get("last_page", True):
            break
        page += 1

    def in_sprint(t: dict) -> bool:
        if (t.get("list") or {}).get("id") == sprint_id:
            return True
        return any((loc or {}).get("id") == sprint_id for loc in (t.get("locations") or []))

    return [t for t in out if in_sprint(t)]


def filter_tasks(
    tasks: list[dict],
    user_id: int | None,
    include_done: bool,
) -> list[dict]:
    out = []
    for t in tasks:
        if user_id is not None:
            if not any(a.get("id") == user_id for a in t.get("assignees", [])):
                continue
        status = (t.get("status", {}) or {}).get("status", "").lower()
        if not include_done and status in CLOSED_STATUSES:
            continue
        out.append(t)
    return out


PRIORITY_RANK = {"urgent": 0, "high": 1, "normal": 2, "low": 3, "-": 4, None: 4}


def render_table(tasks: list[dict]) -> str:
    by_prio: dict[str, list[dict]] = {"urgent": [], "high": [], "normal": [], "low": [], "-": []}
    for t in tasks:
        pr = (t.get("priority") or {}).get("priority") or "-"
        by_prio.setdefault(pr, []).append(t)

    icons = {"urgent": "🔴", "high": "🟠", "normal": "🔵", "low": "⚪", "-": "⚫"}
    lines = []
    for pr in ["urgent", "high", "normal", "low", "-"]:
        bucket = by_prio.get(pr, [])
        if not bucket:
            continue
        lines.append(f"\n### {icons[pr]} {pr.title() if pr != '-' else 'Sem prioridade'} ({len(bucket)})")
        lines.append("| ID | Status | Criada | Assignees | Título |")
        lines.append("|---|---|---|---|---|")
        bucket.sort(key=lambda x: int(x.get("date_created", "0")))
        for t in bucket:
            created = dt.datetime.fromtimestamp(int(t["date_created"]) / 1000).strftime("%d-%b")
            st = (t.get("status", {}) or {}).get("status", "-")
            assignees = ", ".join(a.get("username", "?") for a in t.get("assignees", []))
            name = t.get("name", "")[:90].replace("|", "\\|")
            lines.append(f"| `{t.get('id')}` | {st} | {created} | {assignees} | {name} |")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sprint", help="Sprint list name (YYYY-MM-DD). Default: current week")
    p.add_argument("--user", help="Filter by team member name (case-insensitive partial match: ricardo, emir, gui, abras, andrew, cadu, marcio, rafa, renato)")
    p.add_argument("--user-id", type=int, help="Filter assignee user id (overrides --user). Default Renato 88097761")
    p.add_argument("--all", action="store_true", help="No assignee filter")
    p.add_argument("--include-done", action="store_true", help="Include completed tasks")
    p.add_argument("--json", action="store_true", help="Raw JSON output")
    args = p.parse_args()

    if args.all:
        user_id = None
        who_label = "todos"
    elif args.user_id is not None:
        user_id = args.user_id
        who_label = f"user_id={user_id}"
    elif args.user:
        user_id = resolve_user(args.user)
        who_label = f"{args.user} (user_id={user_id})"
    else:
        user_id = DEFAULT_USER_ID
        who_label = f"user_id={user_id}"

    sprint = sprint_list_by_name(args.sprint) if args.sprint else current_sprint_list()
    sprint_id = sprint["id"]
    sprint_name = sprint["name"]
    raw = sprint_tasks(sprint_id)
    tasks = filter_tasks(raw, user_id=user_id, include_done=args.include_done)

    if args.json:
        print(json.dumps(tasks, indent=2, ensure_ascii=False))
        return

    header = f"## Sprint {sprint_name} (id `{sprint_id}`)"
    status_scope = "todas" if args.include_done else "não completadas"
    print(f"{header} — {who_label}, {status_scope}: **{len(tasks)}** / {len(raw)} na sprint")
    print(render_table(tasks))


if __name__ == "__main__":
    main()
