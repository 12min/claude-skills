---
name: apm
description: >
  Use when querying 12min observability: Elastic APM/ELK for api-production or api-staging service health, endpoint latency, slowest routes, throughput, error rates, span breakdowns, N+1 detection, or Sentry self-hosted issues/events/errors.
version: 1.1.0
author: the user Filho / Claude Code skill, adapted for Hermes
license: Proprietary
metadata:
  hermes:
    tags: [apm, elasticsearch, kibana, observability, performance, 12min]
    related_skills: [systematic-debugging]
---

# APM — Query 12min Elastic APM Observability

## Overview

Extract observability data from the self-hosted Elastic APM/ELK stack used by the 12min Rails `web` app. Use this for latency, throughput, errors, span breakdowns, N+1 detection, endpoint health, and service health for `api-production` / `api-staging`.

Kibana UI: https://apm.12min.com
APM → Services shows `api-production` and `api-staging`.

## When to Use

- User asks for APM data.
- User asks “qual endpoint está lento?”, “latência”, “p95”, “throughput”, “erro no APM”, “N+1”, “onde está gastando tempo”.
- User wants production/staging service health for API.
- User asks for Sentry issues/events/errors, mobile crash/error investigation, or whether Sentry has signal for a flow.
- You need evidence before performance/debugging work.

For Sentry self-hosted access, see `references/sentry-selfhosted.md`.

## Infra

- APM/ELK 7.17.25 runs on Compute Engine VM `production-apm-elk-stack-0`.
- GCP project: `min-b302a`.
- Zone: `us-central1-c`.
- It is NOT in GKE.
- Native systemd services:
  - Elasticsearch: `localhost:9200`
  - Kibana: `:5601`
  - apm-server: `:8200`
- Agents: `elastic-apm-ruby/4.7.3` from Rails `web` app.
- Rails config is ENV-driven via `config/elastic_apm.yml`.
- APM server URL in app env: `APM_SERVER_URL=http://10.128.15.207:8200`.

## Known Data Gap

Ingestion was dead from 2025-09-09 to 2026-06-02 due to span-index/alias collision, since fixed.

- History before 2025-09-09 exists.
- The gap window is empty.
- Default live queries should use `now-30m` unless the user asks for another window.

## Access Pattern

Run commands via IAP SSH to the APM VM:

```bash
gcloud compute ssh production-apm-elk-stack-0 --zone=us-central1-c --tunnel-through-iap --command='<remote cmd>'
```

Important:

- Elasticsearch on `localhost:9200` has no auth on the VM.
- Do not use local `curl` / `wget`; prefer remote `python3 urllib`.
- Python on the VM is older than 3.12: avoid backslashes inside f-strings.
- Use heredoc with `<<"PY"` to avoid shell expansion.
- Keep SSH `--command` in single quotes and use escaped quotes for JSON strings.
- Filter SSH noise:

```bash
... 2>&1 | grep -v "NumPy\|cloud.google.com/iap\|increasing\|WARNING\|^$"
```

## Key Field Names — APM 7.17 / ECS

Transactions (`apm-*-transaction*`):

- `service.name`
- `service.environment`
- `transaction.name`
- `transaction.type`
- `transaction.duration.us` — microseconds
- `transaction.result`
- `event.outcome` — `success` / `failure`
- `http.response.status_code`

Elasticsearch 7 caps exact hit counts at 10,000 unless `track_total_hits: true` is set. For rollout reports where transaction count is user-facing evidence, include `"track_total_hits": true` in the search body; otherwise `hits.total.value=10000` can be only a lower-bound while aggregations still include the full matching set.

Spans (`apm-*-span*`):

- `trace.id`
- `transaction.id`
- `span.name`
- `span.type` — `db` / `external` / `cache` / `app`
- `span.subtype` — `postgresql` / `elasticsearch` / `http`
- `span.duration.us`
- `span.destination.service.resource`

Errors (`apm-*-error*`):

- `error.grouping_name`
- `error.exception.message`
- `error.culprit`

## Recipe 1 — Service Health

Throughput, latency and failures over the last 30 minutes. For a weekend/incident sweep, replace `now-30m` with an explicit UTC lower bound such as the last Saturday 00:00 BRT converted to UTC, and include both `track_total_hits: true` and status-code buckets so failures are not hidden behind Elasticsearch's 10k hit cap.

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

## Recipe 2 — Slowest and Highest-Volume Endpoints

Aggregate `transaction.name` over `now-30m` with:

- `avg(transaction.duration.us)`
- bucket filter `doc_count >= 15`
- sort by average latency for slowest endpoints
- sort by count for highest volume

Background jobs, Sidekiq and DelayedJob can appear as transactions too; do not assume every transaction is an HTTP route.

## Recipe 3 — Errors

Aggregate `apm-*-error*` over `now-30m` on `error.grouping_name`, size 8.

Empty buckets means no errors in the selected window.

## Recipe 3.5 — Post-Ramp Endpoint Monitoring

For a newly migrated endpoint ramped behind an app-level `NATIVE_*_PCT` flag:

1. Query `apm-*-transaction*` for the live service name over the observation window (`now-10m` / `now-15m`). For production `api-books-v2`, the APM `service.name` is usually `api-books-v2-production`; preview deploys use names like `api-books-v2-preview-98`, while a generic `api-books-v2` bucket may contain only health-check traffic and is not sufficient for production rollout health.
2. Report transaction count, avg, p95, `event.outcome=failure` count, and HTTP 5xx count. If failures are present, aggregate failed `transaction.name`, `url.path`, status buckets, and APM error buckets so unrelated proxy timeouts are not confused with the migrated endpoint.
3. Query endpoint-specific transactions if naming is known, but do not require a match for low-traffic endpoints. Transaction names may be controller/action names rather than URL fragments, and at low PCT there may be no native samples yet.
4. Query `apm-*-error*` for the same `service.name` over the same window. Empty buckets are useful evidence.
4. If endpoint-specific samples are absent, combine APM service-level health with Kubernetes log checks and a controlled authenticated request. Say explicitly that endpoint-specific APM samples were not observed.
   - For authenticated app-level cohort endpoints, the controlled request should deliberately choose a user that lands in the native bucket. Compute the bucket with the same algorithm as `NativeCohort`: `Zlib.crc32("<endpoint_key>:<user_id>") % 100`, then pick a user where bucket `< NATIVE_*_PCT`. Never print the user's token.
   - After the request, query APM for the exact `transaction.name` and `url.path` over `now-5m`/`now-10m` and verify `labels.cohort`, `labels.native_pct`, status, outcome, and duration. This turns “no real traffic observed” into a concrete native sample.
5. When service-level failures exist during a ramp, aggregate failed transactions by `transaction.name`, `url.path`, and status before attributing them to the migrated endpoint. In this codebase, unrelated proxy failures (for example `ProxyController#forward` on `/api/v1/personalized_plans/learning_plans/create_sync`) can appear in the same service-level window and should not block a migrated endpoint unless the endpoint-specific query also shows failures.
6. Do not report rollout monitoring as complete unless APM was checked; pod readiness and Kubernetes logs alone are insufficient.

## Recipe 4 — Pre/Post Migration Endpoint Performance Comparison

Use this when comparing a migrated endpoint before/after a strangler cutover.

1. Identify the endpoint by `url.path` first, not only `transaction.name`:
   - legacy service often uses `service.name=api-production`;
   - migrated Books endpoints often use `service.name=api-books-v2-production`;
   - both may share the same controller transaction name, e.g. `Api::V1::BooksController#search`.
2. Anchor the cutover timestamp from rollout/deploy history, then compare explicit UTC windows:
   - `legacy_pre_24h`: `api-production`, `url.path=<endpoint>`, `@timestamp < cutover`;
   - `native_post_24h`: new service, same `url.path`, `@timestamp >= cutover`.
3. Report sample-size and response mix before interpreting latency. A pre/post comparison is weak if status distributions differ (for example legacy mostly `422` while native is `200/304`). State that caveat prominently.
4. Metrics to include:
   - count, avg, p50, p75, p90, p95, p99;
   - failures (`event.outcome=failure`);
   - HTTP status buckets;
   - slow buckets (`transaction.duration.us >= 1_000_000`, `2_000_000`, `5_000_000`).
5. Include an hourly breakdown around the cutover when traffic is sparse; this helps distinguish a real regression from a small burst of slow autocomplete/prefix searches.
6. If the native median improves but the tail worsens, inspect slow samples and then spans by `trace.id` before proposing a fix. For search endpoints, short/prefix queries (`P`, `Pr`, `Pro`, etc.) are common tail-latency suspects.
7. Do not claim “faster” or “slower” from avg alone. Summarize as median vs tail, and mention status-code/request-shape caveats.

## Recipe 5 — Span Breakdown / N+1 Detection

This is often the most valuable performance recipe.

1. Find slowest sample:
   - Query `apm-*-transaction*`.
   - Use `bool.filter` with `term transaction.name` plus time range.
   - Sort `transaction.duration.us` descending.
   - Size 1.
   - `_source`: `trace.id`, `transaction.duration.us`.

2. Pull spans:
   - Query `apm-*-span*` with `term trace.id`.
   - Sort `span.duration.us` descending.
   - `_source`: `span.name`, `span.type`, `span.subtype`, `span.duration.us`, `span.destination.service.resource`.
   - This shows where time went: PostgreSQL, Elasticsearch, external HTTP, cache, app code.

3. N+1 signature:
   - For a single trace, filter `span.type=db`.
   - Aggregate by `span.name`.
   - Include `sum span.duration.us` and `value_count`.
   - If the same table query repeats many times, it is likely N+1.
   - Fix Rails N+1 with eager loading: `includes` / `preload`.

Real example previously found: `RecommendationsController#index` had 137 queries / 4.5s, with authors/books/librarians/playlists repeated around 30x each.

## Common Pitfalls

1. Looking in GKE for APM/ELK. It runs on a Compute Engine VM, not in GKE.
2. Querying the known ingestion gap and assuming zero traffic means no issue.
3. Using seconds instead of microseconds. `transaction.duration.us` and `span.duration.us` are microseconds; divide by 1000 for ms.
4. Treating Sidekiq/DelayedJob transactions as HTTP endpoints.
5. Using local curl/wget. Prefer remote Python urllib from the VM.
6. For strangler production ramps, do not rely on Kubernetes logs alone. Query APM service health/errors explicitly, then separately report whether endpoint-specific transaction samples were present.
7. Low-traffic or low-cohort endpoints may have no endpoint-specific APM transaction samples in a short window. This is not proof of no traffic or no issue; report it as “service-level healthy, no endpoint-specific sample observed” and keep monitoring or generate a safe probe if appropriate. Before concluding the new endpoint is or is not receiving real user traffic, verify the live `NATIVE_*_PCT` flag and routing path: at `PCT=0`, authenticated users should proxy to legacy even though direct/smoke requests can still appear under the native service.
8. For app-level cohort routes, do not stop at “the manifest in `origin/main` contains the path.” Compare the **live** Ingress paths in Kubernetes against the source-of-truth manifest. A cluster can still be running an older Ingress object after a deploy; the symptom is `NATIVE_*_PCT>0`, code/image deployed, but APM shows all transactions on legacy pods. Reapply the current anchor+canary manifests with explicit production context, then verify native host samples appear in APM.
8. **Do not trust `service.name` / `service.environment` alone when deciding whether an APM error is production.** Staging or preview pods can be mislabeled by bad APM env vars in shared secrets. Before escalating “production” errors, inspect `host.name`, `cloud.instance.name`, and pod prefixes: real production nodes/pods differ from `gke-api-staging-*`, `api-staging-*`, and `api-preview-*`. See `references/apm-staging-mislabeling.md`.
8. **Do not trust `service.name` / `service.environment` alone for prod-vs-staging attribution.** Staging/previews can inherit or override APM labels incorrectly (for example `12min-credentials-staging` once labeled staging pods as `api-books-v2-production` / `production`). Before telling the user an error is production-impacting, inspect raw APM `_source` fields such as `cloud.instance.name`, `cloud.availability_zone`, `host.name`, `host.hostname`, `service.node.name`, and request host/IP. `gke-api-staging-0-*`, `api-staging-*`, and `api-preview-*` hosts indicate staging/preview even if `service.name` says production.

### Prod-vs-staging attribution check

When an error bucket references staging infrastructure (for example `pgbouncer-staging.default.svc.cluster.local`) but appears under a production service label, run a raw sample query before escalating as prod:

```bash
gcloud compute ssh production-apm-elk-stack-0 --zone=us-central1-c --tunnel-through-iap --command='python3 - <<"PY"
import urllib.request as u, json
B="http://localhost:9200"
PHRASE="pgbouncer-staging.default.svc.cluster.local"
body={"size":5,"sort":[{"@timestamp":{"order":"desc"}}],"query":{"bool":{"filter":[{"range":{"@timestamp":{"gte":"now-2h","lte":"now"}}}],"must":[{"match_phrase":{"error.exception.message":PHRASE}}]}},"_source":["@timestamp","service.name","service.environment","service.node.name","cloud.instance.name","cloud.availability_zone","host.name","host.hostname","url.path","transaction.name"]}
req=u.Request(B+"/apm-*-error*/_search",data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
for h in json.loads(u.urlopen(req,timeout=30).read().decode())["hits"]["hits"]:
    s=h["_source"]
    print(s.get("@timestamp"), s.get("service",{}), s.get("cloud",{}).get("instance",{}).get("name"), s.get("host",{}).get("name"), s.get("url",{}).get("path"))
PY'
```

If the samples are staging/preview mislabeled as production, verify the relevant Kubernetes secret/deployment labels in staging before changing production. For the legacy/new-api staging stack, `12min-credentials-staging` may supply APM labels via `envFrom`; check selected values without printing secrets:

```bash
kubectl --context gke_min-b302a_us-central1-c_api-staging-0 -n default get secret 12min-credentials-staging -o json \
  | python3 -c 'import sys,json,base64; d=json.load(sys.stdin)["data"]; keys=["APM_SERVICE_NAME","APM_ENVIRONMENT","PGBOUNCER_HOST","PGBOUNCER_PORT","RDS_HOSTNAME","RDS_PORT","RDS_DB_NAME"]; print("\\n".join(f"{k}="+(base64.b64decode(d.get(k,"")).decode(errors="replace") if k in d else "<missing>") for k in keys))'
```

8. **Unexpected dependency hosts in production errors.** When APM errors mention an impossible host (for example production traffic trying `pgbouncer-staging.default.svc.cluster.local`), do not stop at the deployment spec. Verify the live pod environment with `kubectl exec ... env`, inspect `envFrom` secrets/configmaps, and compare APM paths/trace samples against pod logs for the same window. If pod env is correct but APM still shows the unexpected host, report it as a likely code/path/runtime config leak rather than “the deployment env is wrong”.

## Rollout Monitoring Note

When monitoring a production rollout/ramp, do not claim the rollout is healthy from Kubernetes logs alone. Check APM in the same monitoring pass, or explicitly say APM has not been checked yet. A minimal ramp gate should include:

- Kubernetes rollout/ready replicas and restart counts.
- Application logs for 5xx/exceptions in the ramp window.
- APM service health for the affected service (`api-books-v2` / `api-production`): transaction count, avg, p95, failures.
- APM error aggregation for the same window.
- Endpoint-specific transaction search when the route name is expected to appear; if no endpoint transactions appear, report that absence separately rather than treating it as success.
- For app-level `NATIVE_*_PCT` ramps, verify the endpoint path is actually routed to the native service. Raising the env var alone is not enough if nginx still sends that path only to legacy. See `references/app-level-cohort-ingress-routing.md` for the anchor/canary ingress pattern and verification checklist.

For automated watchdogs, distinguish monitor failure from app failure. If APM cannot be queried because SSH/IAP/quoting/parsing fails, report monitor degradation but do not roll back production solely on that basis. Rollback should require concrete endpoint-specific evidence such as APM failure/5xx counts, endpoint logs with errors/5xx, or unstable Kubernetes rollout state.

For Slack/cron watchdogs after an endpoint ramp, keep alert conditions endpoint-specific. Query transactions by the endpoint `url.path` wildcard(s) for failures/5xx, and query `apm-*-error*` with `should` clauses tied to the endpoint path, controller/transaction name, or endpoint-specific error-message phrase. Do not alert on all `api-books-v2-production` service errors for an endpoint-specific ramp: unrelated bot scans, proxy timeouts, or other routes can create false Slack alerts even while the ramped endpoint is healthy. A good no-agent watchdog should emit empty stdout when healthy, and only print a concise Slack-ready alert when endpoint-specific K8s/log/APM evidence is bad.

### Executing an app-level ramp after an APM gate

When the user asks to watch APM for a fixed window and then ramp if clean, actually wait the requested window, query the same APM window, and only then mutate the flag. For `api-books-v2` production app-level percentage flags, the live ramp can be done with Kubernetes env overrides, for example:

```bash
kubectl -n default set env deployment/api-books-v2-production NATIVE_LIBRARY_FAVORITES_PCT=100
kubectl -n default rollout status deployment/api-books-v2-production --timeout=180s
kubectl -n default get deploy api-books-v2-production -o jsonpath='{range .spec.template.spec.containers[0].env[?(@.name=="NATIVE_LIBRARY_FAVORITES_PCT")]}{.name}={.value}{"\n"}{end}{.metadata.name}{" ready="}{.status.readyReplicas}{"/"}{.status.replicas}{" updated="}{.status.updatedReplicas}{"\n"}'
```

Post-ramp verification should include ready/updated replicas, pod restart counts, a short log scan for 5xx/exceptions, and a fresh APM service/error query. Also run an endpoint-specific APM query by `url.path` against both native and legacy services; if native has zero samples while legacy has traffic, the endpoint probably lacks the required ingress anchor/canary route and the env ramp is not actually live. If the repository manifest still has the flag or manually applied ingress at an older/missing value, tell the user the live cluster was changed and ask whether to update the source-of-truth YAML to avoid drift on the next apply.

For longer post-ramp watches, use the bundled helper instead of hand-typing a loop: `scripts/monitor_app_level_endpoint_ramp.sh`. Set at least `KUBE_CONTEXT`, `DEPLOYMENT`, `URL_PATH`, and optionally `PCT_ENV_NAME`, `TICKS`, and `INTERVAL_SECONDS`. It polls Kubernetes readiness/restarts, filtered native logs, endpoint-specific APM for native vs legacy, and APM error buckets.

## Verification Checklist

- [ ] Used the APM VM `production-apm-elk-stack-0` via IAP SSH.
- [ ] Queried a valid time window outside the known ingestion gap, unless intentionally inspecting historical data.
- [ ] Converted microseconds to milliseconds in user-facing output.
- [ ] Reported service/window/index assumptions.
- [ ] Included counts/sample sizes next to latency claims.
- [ ] For rollout monitoring, checked APM errors/service health in addition to Kubernetes logs before saying the ramp is healthy.
- [ ] For N+1 claims, inspected spans from a concrete trace.
