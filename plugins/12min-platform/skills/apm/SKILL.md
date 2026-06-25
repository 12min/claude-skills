---
name: apm
description: Query 12min Elastic APM observability — latency, throughput, errors, N+1 detection. Use whenever the user wants APM data, endpoint latency, slowest routes, error rates, service health for api-production or api-staging, or N+1 query detection.
---

# APM — Query 12min Elastic APM observability

Extract observability data (latency, throughput, errors, span breakdown / N+1 detection) from the self-hosted Elastic APM/ELK stack used by the 12min Rails `web` app. Use whenever the user wants APM data, endpoint latency, slowest routes, error rate, where request time is spent, N+1 detection, or service health for `api-production` / `api-staging`.

**Kibana UI:** https://apm.12min.com (nginx + Certbot → Kibana `:5601`). APM → Services shows `api-production` + `api-staging`.

## Infra (read before querying)

- APM/ELK **7.17.25** runs on Compute Engine VM `production-apm-elk-stack-0` (project `min-b302a`, zone `us-central1-c`), NOT in GKE. Native systemd services: elasticsearch `:9200`, kibana `:5601`, apm-server `:8200`.
- Agents: `elastic-apm-ruby/4.7.3` from the Rails `web` app. Config is ENV-driven (`APM_SERVER_URL=http://10.128.15.207:8200`) via `config/elastic_apm.yml`.
- **Data gap:** ingestion was dead 2025-09-09 → 2026-06-02 (span-index/alias collision, since fixed). History before 2025-09-09 exists; the gap window is empty. Default queries to `now-30m` for live data.

## Access pattern (IMPORTANT)

```bash
gcloud compute ssh production-apm-elk-stack-0 --zone=us-central1-c --tunnel-through-iap --command='<remote cmd>'
```

- ES on `localhost:9200` has **no auth**.
- **`curl`/`wget` are blocked** by context-mode in local Bash. Inside the remote command use **`python3 urllib`**, NOT curl.
- Python on the VM is <3.12: **no backslash inside f-strings**. Access dict keys in plain statements, then `%`-format for output.
- Heredoc with `<<"PY"` avoids shell expansion; keep the SSH `--command` in single quotes and use `\"` for JSON strings.
- Filter SSH noise: `... 2>&1 | grep -v "NumPy\|cloud.google.com/iap\|increasing\|WARNING\|^$"`

## Key field names (APM 7.17, ECS)

- Transactions (`apm-*-transaction*`): `service.name`, `service.environment`, `transaction.name`, `transaction.type`, `transaction.duration.us` (microseconds), `transaction.result`, `event.outcome` (`success`/`failure`), `http.response.status_code`.
- Spans (`apm-*-span*`): `trace.id`, `transaction.id`, `span.name`, `span.type` (`db`/`external`/`cache`/`app`), `span.subtype` (`postgresql`/`elasticsearch`/`http`), `span.duration.us`, `span.destination.service.resource`.
- Errors (`apm-*-error*`): `error.grouping_name`, `error.exception.message`, `error.culprit`.

## Recipe 1 — service health (throughput + latency + failures)

```bash
gcloud compute ssh production-apm-elk-stack-0 --zone=us-central1-c --tunnel-through-iap --command='python3 - <<"PY"
import urllib.request as u, json
B="http://localhost:9200"
def s(idx,body):
    r=u.Request(B+"/"+idx+"/_search",data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.loads(u.urlopen(r,timeout=30).read().decode())
R={"range":{"@timestamp":{"gte":"now-30m"}}}
q={"size":0,"query":R,"aggs":{"svc":{"terms":{"field":"service.name","size":10},"aggs":{"lat":{"avg":{"field":"transaction.duration.us"}},"p95":{"percentiles":{"field":"transaction.duration.us","percents":[95]}},"fail":{"filter":{"term":{"event.outcome":"failure"}}}}}}}
for b in s("apm-*-transaction*",q)["aggregations"]["svc"]["buckets"]:
    n=b["key"];c=b["doc_count"];a=b["lat"]["value"]/1000.0;p=(list(b["p95"]["values"].values())[0] or 0)/1000.0;f=b["fail"]["doc_count"]
    print("%-16s txns=%7d avg=%6.1fms p95=%7.1fms fail=%d"%(n,c,a,p,f))
PY' 2>&1 | grep -v "NumPy\|cloud.google.com/iap\|increasing\|WARNING\|^$"
```

## Recipe 2 — slowest + highest-volume endpoints

Aggregate `transaction.name` over `now-30m` with `avg(transaction.duration.us)`, filter buckets with `doc_count >= 15`, sort by avg (slowest) and by count (volume). Background jobs (Sidekiq/DelayedJob) appear as transactions too.

## Recipe 3 — errors

Aggregate `apm-*-error*` over `now-30m` on `error.grouping_name` (size 8). Empty buckets = no errors in window.

## Recipe 4 — span breakdown / N+1 detection (most valuable)

1. Find slowest sample: query `apm-*-transaction*` with `bool.filter` `term transaction.name` + range, sort `transaction.duration.us` desc, size 1, `_source: [trace.id, transaction.duration.us]`.
2. Pull spans: query `apm-*-span*` with `term trace.id`, sort `span.duration.us` desc, `_source: [span.name, span.type, span.subtype, span.duration.us, span.destination.service.resource]`. Shows where time went (postgresql / elasticsearch / http external).
3. **N+1 signature:** aggregate that trace's spans with `term span.type=db` + `terms span.name` + `sum span.duration.us` + `value_count`. If the same table query repeats N times (e.g. `SELECT FROM librarians` 30x), it's N+1 → fix with Rails eager loading (`includes`/`preload`). Real example found: `RecommendationsController#index` = 137 queries / 4.5s, authors/books/librarians/playlists each 30x.
