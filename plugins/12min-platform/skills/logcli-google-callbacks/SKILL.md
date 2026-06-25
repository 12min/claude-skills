---
name: logcli-google-callbacks
description: Fetch and analyze Google Play subscription callbacks from Loki ingress logs. Decodes base64 Pub/Sub payloads and enriches with Google Play API data (order_id, subscription_state, expiry_time, region_code). Use when investigating Google Play IAP issues, callback failures, or subscription state problems.
---

# logcli-google-callbacks — Google Play Callback Log Analyzer

Fetches all `POST /api/v2/callbacks/google` requests from the billing service ingress logs in Loki (production), decodes the base64 Pub/Sub payload, enriches each entry with live data from the Google Play API (order_id, subscription_state, expiry_time, region_code, auto_renew), and exports a CSV.

## Usage

```
/logcli-google-callbacks [options]
```

**Examples:**
```
/logcli-google-callbacks
/logcli-google-callbacks --since=6h
/logcli-google-callbacks --since=24h --limit=500
/logcli-google-callbacks --since=1h --output=/tmp/google_callbacks_2026-03-11.csv
```

**Parameters:**
- `--since=<duration>` — how far back to search (default: `1h`). Accepts: `15m`, `1h`, `6h`, `24h`, `48h`, `7d`
- `--limit=<n>` — max log lines to fetch from Loki (default: `200`)
- `--output=<path>` — output CSV file path (default: `/tmp/google_callbacks_<YYYYMMDD_HHMM>.csv`)

---

## Instructions

### Step 1 — Parse arguments

Extract:
- `SINCE` — duration string (default `1h`)
- `LIMIT` — integer (default `200`)
- `OUTPUT` — file path (default `/tmp/google_callbacks_<YYYYMMDD_HHMM>.csv` using current time)

### Step 2 — Ensure Loki is reachable

Check if logcli is installed:
```bash
which logcli
```

Check if Loki is reachable:
```bash
curl -s http://localhost:3100/ready
```

If not ready, switch to production context and start port-forward:
```bash
kubectl --context=gke_min-b302a_southamerica-east1-a_api-production \
  port-forward service/loki-12 3100:3100 -n default >/tmp/loki-pf.log 2>&1 &
echo $! > /tmp/loki-pf.pid
sleep 4
curl -s http://localhost:3100/ready
```

Retry once after 3s if still not ready. Stop with error if Loki is unreachable after retries.

### Step 3 — Fetch logs from Loki

```bash
logcli query '{app="ingress-nginx"} |= "callbacks/google"' \
  --addr=http://localhost:3100 \
  --since=SINCE \
  --limit=LIMIT \
  --output=jsonl 2>/dev/null
```

### Step 4 — Parse, decode and export to CSV

Save this Python script to `/tmp/parse_google_callbacks.py` and pipe the logcli output into it:

```python
import sys, json, csv, re, base64
from datetime import datetime

OUTPUT_PATH = sys.argv[1] if len(sys.argv) > 1 else "/tmp/google_callbacks.csv"

NOTIFICATION_TYPES = {
    1: 'RECOVERED', 2: 'RENEWED', 3: 'CANCELED', 4: 'PURCHASED',
    5: 'ON_HOLD', 6: 'GRACE_PERIOD', 7: 'RESTARTED', 8: 'PRICE_CHANGE',
    9: 'DEFERRED', 10: 'PAUSED', 11: 'PAUSE_SCHEDULE_CHANGED',
    12: 'REVOKED', 13: 'EXPIRED'
}

entries = []
raw_count = 0
parse_errors = 0

for l in sys.stdin:
    try:
        obj = json.loads(l)
        ts = obj.get('timestamp', '')
        line = obj.get('line', '')
        raw_count += 1

        end_m = re.search(r'(\d{3}) ([a-f0-9]{32})\s*$', line)
        status = end_m.group(1) if end_m else '?'
        req_id = end_m.group(2) if end_m else ''

        data_m = re.search(r'\\x22data\\x22:\\x22([A-Za-z0-9+/=]+)\\x22', line)
        if not data_m:
            parse_errors += 1
            continue

        b64 = data_m.group(1)
        try:
            decoded = json.loads(base64.b64decode(b64 + '==').decode('utf-8'))
        except Exception:
            parse_errors += 1
            continue

        pubsub_subscription = decoded.get('subscription', '')
        notification = decoded.get('subscriptionNotification', {})
        is_test = False
        if not notification and 'testNotification' in decoded:
            notification = decoded.get('testNotification', {})
            is_test = True

        notif_type_num = notification.get('notificationType', 0)
        notif_type = 'TEST' if is_test else NOTIFICATION_TYPES.get(notif_type_num, f'TYPE_{notif_type_num}')
        purchase_token = notification.get('purchaseToken', '')
        subscription_id = notification.get('subscriptionId', '')
        package_name = decoded.get('packageName', '')

        event_time_ms = decoded.get('eventTimeMillis', '')
        event_time_iso = ''
        if event_time_ms:
            try:
                event_time_iso = datetime.utcfromtimestamp(int(event_time_ms) / 1000).strftime('%Y-%m-%dT%H:%M:%SZ')
            except Exception:
                event_time_iso = event_time_ms

        entries.append({
            'loki_timestamp':    ts,
            'event_time':        event_time_iso,
            'status':            status,
            'notification_type': notif_type,
            'subscription_id':   subscription_id,
            'package_name':      package_name,
            'purchase_token':    purchase_token,
            'request_id':        req_id,
            'order_id':           '',
            'subscription_state': '',
            'expiry_time':        '',
            'region_code':        '',
            'auto_renew':         '',
        })
    except Exception:
        parse_errors += 1

if not entries:
    print(f"No Google callback requests found. (raw={raw_count}, errors={parse_errors})")
    sys.exit(0)

cols = ['loki_timestamp', 'event_time', 'status', 'notification_type',
        'subscription_id', 'package_name', 'purchase_token', 'request_id',
        'order_id', 'subscription_state', 'expiry_time', 'region_code', 'auto_renew']

with open(OUTPUT_PATH, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(entries)

print(f"PARSED:{len(entries)}:{raw_count}:{parse_errors}:{OUTPUT_PATH}")
```

Run with:
```bash
logcli query '{app="ingress-nginx"} |= "callbacks/google"' \
  --addr=http://localhost:3100 \
  --since=SINCE \
  --limit=LIMIT \
  --output=jsonl 2>/dev/null \
  | python3 /tmp/parse_google_callbacks.py OUTPUT
```

### Step 5 — Get Google credentials from API pod

**IMPORTANT:** Access token expires quickly. Steps 5, 6, and 7 MUST run in the same shell session.

```bash
API_POD=$(kubectl --context=gke_min-b302a_southamerica-east1-a_api-production \
  get pods -n default | grep "^api-" | grep Running | grep -v busybox | awk '{print $1}' | head -1)

CREDS=$(kubectl --context=gke_min-b302a_southamerica-east1-a_api-production \
  exec $API_POD -- sh -c 'env | grep -E "GOOGLE_CLIENT_KEY|GOOGLE_CLIENT_SECRET|GOOGLE_REFRESH_TOKEN"')
GOOGLE_CLIENT_KEY=$(echo "$CREDS" | grep GOOGLE_CLIENT_KEY | cut -d= -f2)
GOOGLE_CLIENT_SECRET=$(echo "$CREDS" | grep GOOGLE_CLIENT_SECRET | cut -d= -f2)
GOOGLE_REFRESH_TOKEN=$(echo "$CREDS" | grep GOOGLE_REFRESH_TOKEN | cut -d= -f2)

ACCESS_TOKEN=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "client_id=$GOOGLE_CLIENT_KEY" \
  -d "client_secret=$GOOGLE_CLIENT_SECRET" \
  -d "refresh_token=$GOOGLE_REFRESH_TOKEN" \
  -d "grant_type=refresh_token" | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
```

### Step 6 — Enrich CSV with Google Play API data

Save this script to `/tmp/enrich_google_callbacks.py`:

```python
import sys, json, csv, urllib.request, urllib.error, time

INPUT_CSV    = sys.argv[1]
ACCESS_TOKEN = sys.argv[2]
PACKAGE      = "com.br.twelvemin"

def fetch_google(token, access_token):
    url = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/purchases/subscriptionsv2/tokens/{token}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"error": {"code": e.code, "message": str(e)}}
    except Exception as e:
        return {"error": {"message": str(e)}}

with open(INPUT_CSV, newline='') as f:
    rows = list(csv.DictReader(f))

fieldnames = list(rows[0].keys()) if rows else []
total = len(rows)

for i, row in enumerate(rows):
    token = row.get('purchase_token', '')
    if not token:
        continue

    print(f"  [{i+1}/{total}] {row.get('notification_type','?'):12s} {row.get('subscription_id','')[:40]} ...", flush=True)
    data = fetch_google(token, ACCESS_TOKEN)

    if 'error' in data:
        row['order_id'] = f"ERROR: {data['error'].get('message', '')}"
    else:
        line_items = data.get('lineItems', [])
        item       = line_items[0] if line_items else {}
        auto_renew_plan = item.get('autoRenewingPlan', {})

        row['order_id']           = data.get('latestOrderId', '')
        row['subscription_state'] = data.get('subscriptionState', '')
        row['expiry_time']        = item.get('expiryTime', '')
        row['region_code']        = data.get('regionCode', '')
        row['auto_renew']         = str(auto_renew_plan.get('autoRenewEnabled', ''))

    time.sleep(0.2)

with open(INPUT_CSV, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(rows)

print(f"\nEnriched {total} entries -> {INPUT_CSV}")
```

Run with:
```bash
python3 /tmp/enrich_google_callbacks.py OUTPUT "$ACCESS_TOKEN"
```

### Step 7 — Present results

Display:

1. **Summary header:** total requests | time window | output file | parse errors
2. **Notification type breakdown** (count per type)
3. **Status code breakdown** (⚠️ on non-200)
4. **Full results table:** `event_time | status | notification_type | subscription_id | order_id | subscription_state | expiry_time | region_code`
5. **Highlights:**
   - ⚠️ `status != 200` — HTTP failures
   - ⚠️ CANCELED, EXPIRED, REVOKED, ON_HOLD, GRACE_PERIOD notifications
   - ⚠️ `subscription_state` other than `SUBSCRIPTION_STATE_ACTIVE`
   - ⚠️ Any Google API errors in `order_id`
   - ℹ️ TEST notifications

---

## Notification Type Reference

| Type | Name | Meaning |
|------|------|---------|
| 1 | RECOVERED | Subscription recovered from account hold |
| 2 | RENEWED | Active subscription renewed |
| 3 | CANCELED | Subscription canceled voluntarily |
| 4 | PURCHASED | New subscription purchased |
| 5 | ON_HOLD | Subscription put on hold (billing issue) |
| 6 | GRACE_PERIOD | In grace period (billing issue, still active) |
| 7 | RESTARTED | Subscription restarted after cancel |
| 8 | PRICE_CHANGE | User confirmed price change |
| 9 | DEFERRED | Subscription renewal deferred |
| 10 | PAUSED | Subscription paused |
| 12 | REVOKED | Subscription revoked (refund) |
| 13 | EXPIRED | Subscription expired |

## Requirements

- `logcli` installed and in PATH
- `kubectl` configured with access to production cluster
- `python3` available
- Port 3100 available locally for Loki port-forward
