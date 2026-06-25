#!/usr/bin/env bash
set -euo pipefail

# Monitor an app-level NATIVE_*_PCT endpoint ramp across Kubernetes + Elastic APM.
# Required env vars:
#   KUBE_CONTEXT, DEPLOYMENT, URL_PATH
# Optional env vars:
#   NAMESPACE=default
#   NATIVE_SERVICE=api-books-v2-production
#   LEGACY_SERVICE=api-production
#   PCT_ENV_NAME=<name of NATIVE_*_PCT env var>
#   INTERVAL_SECONDS=300
#   TICKS=6
#   APM_VM=production-apm-elk-stack-0
#   APM_ZONE=us-central1-c

: "${KUBE_CONTEXT:?set KUBE_CONTEXT}"
: "${DEPLOYMENT:?set DEPLOYMENT}"
: "${URL_PATH:?set URL_PATH, e.g. /api/v1/search}"

NAMESPACE="${NAMESPACE:-default}"
NATIVE_SERVICE="${NATIVE_SERVICE:-api-books-v2-production}"
LEGACY_SERVICE="${LEGACY_SERVICE:-api-production}"
PCT_ENV_NAME="${PCT_ENV_NAME:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-300}"
TICKS="${TICKS:-6}"
APM_VM="${APM_VM:-production-apm-elk-stack-0}"
APM_ZONE="${APM_ZONE:-us-central1-c}"

for i in $(seq 1 "$TICKS"); do
  echo "=== monitor tick $i/$TICKS $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

  echo "--- kubernetes deployment ---"
  if [ -n "$PCT_ENV_NAME" ]; then
    kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get deploy "$DEPLOYMENT" \
      -o jsonpath="{range .spec.template.spec.containers[0].env[?(@.name==\"$PCT_ENV_NAME\")]}{.name}={.value}{\"\\n\"}{end}{.metadata.name}{\" ready=\"}{.status.readyReplicas}{\"/\"}{.status.replicas}{\" updated=\"}{.status.updatedReplicas}{\"\\n\"}" || true
  else
    kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get deploy "$DEPLOYMENT" \
      -o jsonpath='{.metadata.name}{" ready="}{.status.readyReplicas}{"/"}{.status.replicas}{" updated="}{.status.updatedReplicas}{"\n"}' || true
  fi

  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get pods -l "app=$DEPLOYMENT" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" status="}{.status.phase}{" restarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}' || true

  echo "--- recent native logs (errors / endpoint only) ---"
  kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" logs "deploy/$DEPLOYMENT" --since=5m 2>/dev/null \
    | grep -Ei "error|exception|fatal| 500 |Completed 5|${URL_PATH#/}" \
    | tail -80 || true

  echo "--- APM last 10m for endpoint ---"
  gcloud compute ssh "$APM_VM" --zone="$APM_ZONE" --tunnel-through-iap --command="python3 - <<'PY'
import urllib.request as u, json, os
B='http://localhost:9200'
def s(idx, body):
    r=u.Request(B+'/'+idx+'/_search', data=json.dumps(body).encode(), headers={'Content-Type':'application/json'})
    return json.loads(u.urlopen(r, timeout=30).read().decode())
services=[os.environ.get('NATIVE_SERVICE', '$NATIVE_SERVICE'), os.environ.get('LEGACY_SERVICE', '$LEGACY_SERVICE')]
url_path=os.environ.get('URL_PATH', '$URL_PATH')
for svc in services:
    q={'size':0,'track_total_hits':True,'query':{'bool':{'filter':[{'term':{'service.name':svc}},{'term':{'url.path':url_path}},{'range':{'@timestamp':{'gte':'now-10m'}}}]}},'aggs':{'lat':{'avg':{'field':'transaction.duration.us'}},'p95':{'percentiles':{'field':'transaction.duration.us','percents':[95]}},'fail':{'filter':{'term':{'event.outcome':'failure'}}},'status':{'terms':{'field':'http.response.status_code','size':10}}}}
    r=s('apm-*-transaction*', q)
    total=r.get('hits',{}).get('total',{}).get('value',0)
    avg=r['aggregations']['lat']['value']
    p95=list(r['aggregations']['p95']['values'].values())[0]
    print('endpoint service=%s txns=%s avg_ms=%s p95_ms=%s failures=%s status=%s' % (svc,total,None if avg is None else round(avg/1000,1),None if p95 is None else round(p95/1000,1),r['aggregations']['fail']['doc_count'],[(b['key'],b['doc_count']) for b in r['aggregations']['status']['buckets']]))
qe={'size':0,'query':{'bool':{'filter':[{'terms':{'service.name':services}},{'range':{'@timestamp':{'gte':'now-10m'}}}]}},'aggs':{'svc':{'terms':{'field':'service.name','size':5},'aggs':{'err':{'terms':{'field':'error.grouping_name','size':10}}}}}}
re=s('apm-*-error*', qe)
print('errors_by_service=', [(b['key'], [(e['key'],e['doc_count']) for e in b['err']['buckets']]) for b in re['aggregations']['svc']['buckets']])
PY" 2>&1 | grep -v "NumPy\|cloud.google.com/iap\|increasing\|WARNING\|^$" || true

  if [ "$i" != "$TICKS" ]; then sleep "$INTERVAL_SECONDS"; fi
done
