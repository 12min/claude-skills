# App-level cohort ramps require ingress routing

When ramping a newly migrated endpoint behind a `NATIVE_*_PCT` env var, first confirm that production traffic for that exact path actually reaches the native service. The env var only affects requests handled by the native app. If nginx still routes the path exclusively to the legacy `api` service, raising `NATIVE_*_PCT` changes a deployment env var but produces zero native endpoint samples.

## Detection pattern

After setting the env var, query APM by `url.path` for both services:

- native service, e.g. `api-books-v2-production`
- legacy service, e.g. `api-production`

If all endpoint transactions remain under legacy and native has zero samples, check ingress routing before treating the ramp as live.

## Production ingress pattern

For routes not already covered by an `api-books-v2-*` ingress pair, create/apply a scoped anchor + canary pair:

1. Anchor Service pointing to legacy pods with a distinct upstream name, e.g. `api-legacy-<endpoint>-anchor` selecting `app: api`.
2. Non-canary anchor Ingress for the exact regex path, backend = the anchor service.
3. Canary Ingress for the same regex path, backend = `api-books-v2-production-service`, with:
   - `nginx.ingress.kubernetes.io/canary: "true"`
   - `nginx.ingress.kubernetes.io/canary-weight: "100"`
   - `nginx.ingress.kubernetes.io/canary-by-header: "X-Canary"`
   - `nginx.ingress.kubernetes.io/use-regex: "true"`

Use the app-level `NATIVE_*_PCT` as the gradual ramp knob. The nginx canary weight is effectively the routing cutover to the native app/proxy layer, not the user rollout percentage.

## Verification checklist

- `kubectl get ingress` shows both anchor and canary for the target path.
- Compare the live ingress paths, not only the repository manifest. A previous production drift had the manifest containing both `/progress` and `/content/:language`, while the live cluster only had `/progress`; the flag was at 50% but content traffic stayed 100% legacy.
- If the source-of-truth manifest already has the missing path, reapply that exact manifest from `origin/main` with explicit production context, then re-read live ingress paths before checking APM.
- A safe probe produces endpoint samples in `api-books-v2-production` APM. For unauthenticated endpoints, a `401 {"message":"authentication error"}` can still be a valid routing probe when it lands on the expected native controller/action.
- The same endpoint may still appear in `api-production` for proxied cohorts; this is expected below 100%.
- APM errors and 5xx are checked for both services.
- Record any manually applied ingress as source-of-truth work; otherwise future manifest applies may lose the route.
