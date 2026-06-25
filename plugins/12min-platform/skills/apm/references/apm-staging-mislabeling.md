# APM staging/preview mislabeled as production

## Symptom

An APM query may show errors under:

- `service.name = api-books-v2-production`
- `service.environment = production`

but the actual source can still be staging/preview if APM env vars are wrong in a shared staging secret.

## Verification pattern

When an apparent production error mentions staging infrastructure such as `pgbouncer-staging.default.svc.cluster.local`, inspect these fields in `apm-*-error*` before concluding production is affected:

- `host.name`
- `cloud.instance.name`
- `service.node.name`
- `url.path`
- `http.request.headers.Host`

Useful query shape from the APM VM:

```python
q = {
  "size": 0,
  "query": {
    "bool": {
      "filter": [{"range": {"@timestamp": {"gte": "now-3h", "lte": "now"}}}],
      "must": [{"match_phrase": {"error.exception.message": "pgbouncer-staging.default.svc.cluster.local"}}]
    }
  },
  "aggs": {
    "host": {
      "terms": {"field": "host.name", "size": 20},
      "aggs": {
        "cloud": {"terms": {"field": "cloud.instance.name", "size": 10}},
        "svc": {"terms": {"field": "service.name", "size": 10}},
        "env": {"terms": {"field": "service.environment", "size": 10}},
        "path": {"terms": {"field": "url.path", "size": 8}}
      }
    }
  }
}
```

Interpretation:

- `cloud.instance.name` starting with `gke-api-staging-0-*` means the event came from staging GKE nodes.
- `host.name` starting with `api-staging-*` or `api-preview-*` means the event came from staging/preview pods.
- In that case, report it as staging/preview mislabeled as production, not a real production app error.

## Known root-cause class

A shared staging secret can override APM labels, for example:

- `APM_SERVICE_NAME=api-books-v2-production`
- `APM_ENVIRONMENT=production`

on `12min-credentials-staging` or similar. Confirm with Kubernetes by checking the pod's effective env and the secret keys, without printing unrelated secrets.

## Related staging failure mode

If errors mention `pgbouncer-staging.default.svc.cluster.local` and show `Connection refused`, check whether the `pgbouncer-staging` Service has endpoints. A common cause is the pgbouncer deployment stuck in `CreateContainerConfigError` because its expected DB keys are missing from the staging secret, e.g. `RDS_HOSTNAME`, `RDS_HOSTNAME_SLAVE1`, `RDS_DB_NAME`, `RDS_USERNAME`, `RDS_PASSWORD`.

Do not store secret values in reports or skills; only report key names and non-secret labels.
