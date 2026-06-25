---
name: deploy-monitor
description: >
  Post-deploy anomaly monitor for 12min platform services. Use this skill whenever the user has just merged a PR, deployed a service, or pushed a change and wants to watch for regressions or side effects. Triggers on phrases like "monitor deploy", "me avisa se der erro", "watch for errors after this deploy", "monitorar o deploy", "quero saber se quebrou alguma coisa", "set up post-deploy monitoring", "acompanhar o deploy", "verificar se o deploy causou algum problema". Also trigger proactively right after helping the user merge or deploy something.
argument-hint: "[PR number or description of what was deployed]"
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
  - mcp__plugin_context-mode_context-mode__ctx_execute
  - mcp__bigquery__execute_sql
---

# Deploy Monitor

Generates a continuous monitoring script after a deploy, with Slack DM notification when anomalies are detected.

## Platform context

- **K8s context produção:** `gke_min-b302a_southamerica-east1-a_api-production`
- **K8s context staging:** `gke_min-b302a_us-central1-c_api-staging-0`
- **Slack bot token:** extract from `~/.claude/mcp.json` server "slack" → env `SLACK_BOT_TOKEN`
- **Billing DB:** `postgres://billing:<password>@10.103.112.29/billing` (extract from `BILLING_DATABASE_URL_RW` env in any `api-*` pod in production)

## Process

### 1. Collect deploy context

Ask (one at a time, only what's necessary):

1. **What was deployed?** PR number + repo + brief description (e.g., "PR #1620 in web — Rails, added status to Hotmart sync")
2. **When was the merge?** UTC timestamp (e.g., "2026-05-19 17:40 UTC")
3. **What could break?** Which behavior does the deploy affect? (e.g., "Hotmart approvals should create subscriptions with plan_id=3 and status=active")

If context is already in the conversation (PR just merged, deploy just done), extract this info without asking.

### 2. Define checks

Based on what changed, decide which checks are relevant:

#### BigQuery volume check
Use when the deploy affects events in `rudderstack.order_completed` or other BigQuery tables.
```sql
-- Example: Hotmart approvals post-deploy
SELECT COUNT(*) as count
FROM `rudderstack.order_completed`
WHERE affiliation = 'hotmart'
  AND timestamp >= TIMESTAMP('<DEPLOY_TIME>')
  AND order_id NOT LIKE 'REPLAY-%'
```

#### Billing DB state check
Use when the deploy affects data written to `v2_subscriptions` or `v2_invoices`.
```sql
-- Example: Hotmart subscriptions with wrong plan
SELECT COUNT(DISTINCT vs.user_id) as misses
FROM v2_subscriptions vs
JOIN v2_invoices vi USING(user_id)
WHERE vi.platform = 'hotmart'
  AND vi.created_at >= NOW() - INTERVAL '30 minutes'
  AND vs.plan_id NOT IN (3, 27)
```

#### Sentry error check
Use when the deploy could introduce new exceptions. Search via `mcp__sentry__list_issues` with date filter.

#### Business metrics check
Use when the deploy affects conversion or revenue. Query BigQuery comparing pre vs post-deploy window.

#### K8s rollout + APM + smoke test (new-api-app / strangler-fig)
Use whenever the deploy is to `new-api-app`. Covers three dimensions:

**1. K8s rollout** — new pod started without CrashLoop:
```bash
kubectl --context=gke_min-b302a_southamerica-east1-a_api-production \
  rollout status deployment/api-books-v2 -n default --timeout=120s
```

**2. APM — post-deploy error count** — via SSH to ELK VM (`production-apm-elk-stack-0`):
```bash
gcloud compute ssh production-apm-elk-stack-0 --project=min-b302a --zone=us-central1-c \
  --command "curl -s 'http://localhost:9200/apm-7.17.25-error-*/_count' \
    -H 'Content-Type: application/json' -d '{
      \"query\": {\"bool\": {\"filter\": [
        {\"term\": {\"service.name\": \"api-books-v2-production\"}},
        {\"range\": {\"@timestamp\": {\"gte\": \"<DEPLOY_TIME_ISO>\"}}}
      ]}}}'" 2>&1
```

**3. Smoke test HTTP** — migrated endpoint responds with correct shape:
```bash
RESPONSE=$(curl -s -X PUT "https://api.12min.com/api/v1/books/<BOOK_ID>/read" \
  -H "X-Token: <SERVICE_TOKEN>")
SUCCESS=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success','MISSING'))")
if [[ "$SUCCESS" != "True" ]]; then
  ((ISSUES++))
  echo "FAIL smoke test: success=$SUCCESS body=$RESPONSE"
fi
```

### 3. Generate monitoring script

Create the script at `.planning/scripts/deploy-monitor-<PR_NUMBER>.sh`.

Script structure:

```bash
#!/usr/bin/env bash
# Deploy Monitor — <SERVICE> PR #<NUMBER>
# Deployed: <TIMESTAMP UTC>
# Monitors: <WHAT IS BEING MONITORED>
# Interval: every 30min via cron

set -euo pipefail

DEPLOY_TIME="<TIMESTAMP_UTC>"
K8S_CONTEXT="gke_min-b302a_southamerica-east1-a_api-production"
SLACK_TOKEN="<TOKEN>"
SLACK_USER="<YOUR_SLACK_USER_ID>"  # get from Slack profile
LOG_FILE="$(dirname "$0")/deploy-monitor-<PR>.log"

# Slack notification function
slack_dm() {
  local msg="$1"
  curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"channel\":\"$SLACK_USER\",\"text\":\"$msg\"}" > /dev/null
}

echo "=== Deploy Monitor $(date -u '+%Y-%m-%d %H:%M UTC') ==="

ISSUES=0

# ── CHECK 1: <check name> ──────────────────────────────────────────────────
# ... check logic ...

if [[ $ISSUES -eq 0 ]]; then
  echo "✅ All clear."
else
  slack_dm ":rotating_light: *Deploy Monitor PR #<N>* — $ISSUES anomaly(ies) detected. Log: $LOG_FILE"
fi
```

**Script rules:**
- Only notify Slack on issues (don't flood DM with ✅)
- Always filter by `timestamp >= DEPLOY_TIME`
- Exclude test/replay data (`order_id NOT LIKE 'REPLAY-%'`, etc.)
- Full log to file for diagnostics

### 4. Extract Slack bot token

```bash
python3 -c "
import json
with open('$HOME/.claude/mcp.json') as f:
    d = json.load(f)
for k, v in d.get('mcpServers', {}).items():
    if 'slack' in k.lower():
        print(v.get('env', {}).get('SLACK_BOT_TOKEN', ''))
"
```

### 5. Configure cron

```bash
# Make executable
chmod +x <path-to-script>

# Add to crontab (every 30min)
(crontab -l 2>/dev/null; echo "*/30 * * * * <path-to-script> >> <log-path> 2>&1") | crontab -

# Verify
crontab -l | grep deploy-monitor
```

### 6. Test before leaving it running

Always run the script once manually to confirm:
1. Connects to BigQuery without error
2. Connects to billing DB without error (if applicable)
3. Returns a result (even if "no events yet")
4. Does not notify Slack unnecessarily on first run

If `gke-gcloud-auth-plugin not found`:
```bash
# Re-authenticate to cluster
gcloud container clusters get-credentials <cluster-name> --region <region> --project min-b302a
```

### 7. When to remove monitoring

```bash
# Remove specific cron entry
crontab -l | grep -v deploy-monitor-<PR> | crontab -
```

Remove when smoke test criteria are met (e.g., 20 organic approvals verified without anomaly).
