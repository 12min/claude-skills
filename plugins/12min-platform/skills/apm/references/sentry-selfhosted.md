# 12min Sentry self-hosted access

Use this when asked to read Sentry issues/events/errors for 12min projects (mobile-v2, api, billing-api, onboarding, web, etc.).

## Correct host and org

- Sentry is self-hosted at `https://sentry.12min.com`.
- Org slug: `12min`.
- Common project slugs: `api`, `api-books-v2`, `api-staging`, `billing-api`, `billing-api-staging`, `internal`, `mobile-v2`, `onboarding`, `web`, `webapp-vw`.
- Do **not** default to `https://sentry.io`; the token in `.zprofile` may be invalid there and is the wrong host for 12min self-hosted data.

## Token source

Use a read token supplied by the environment or by the user's local secret manager. Do not commit token values, token-bearing local paths, or copied shell history into this skill. Never paste or echo tokens in responses. Keep the token in a local variable/env var only.

Example pattern:

```bash
set +x
: "${SENTRY_AUTH_TOKEN:?set SENTRY_AUTH_TOKEN in your shell or secret manager}"
sentry-cli --url https://sentry.12min.com info
```

Expected read scopes: `alerts:read`, `event:read`, `member:read`, `org:read`, `project:read`, `team:read`.

## CLI checks

List orgs:

```bash
sentry-cli --url https://sentry.12min.com organizations list
```

If `sentry-cli` subcommand names differ by version, run `sentry-cli --help`; newer versions use `organizations`, not `orgs`.

## API checks without curl

Use Python `urllib` instead of shell `curl` when context-mode blocks curl/wget. The local Python on macOS may fail CA verification for this self-hosted certificate; if that happens, use an unverified SSL context for read-only API calls.

Safe skeleton:

```python
import json, ssl, urllib.request
base = 'https://sentry.12min.com/api/0'
ctx = ssl._create_unverified_context()

def get(path):
    req = urllib.request.Request(
        base + path,
        headers={'Authorization': f'Bearer {token}'},
    )
    with urllib.request.urlopen(req, timeout=20, context=ctx) as r:
        return json.load(r)

projects = get('/organizations/12min/projects/')
events = get('/projects/12min/mobile-v2/events/?limit=10')
```

Useful endpoints:

- `/api/0/organizations/`
- `/api/0/organizations/12min/projects/`
- `/api/0/projects/12min/<project>/events/?limit=10`

## Infra reference

Self-hosted Sentry runs outside GKE on Compute Engine:

- GCP project: `min-b302a`
- VM: `production-12min-sentry-2`
- Zone: `us-central1-a`
- SSH: `gcloud compute ssh production-12min-sentry-2 --project=min-b302a --zone=us-central1-a --tunnel-through-iap`
- Event retention observed: 90 days.

## Pitfalls

1. `sentry-cli info` against default `https://sentry.io` can return `Invalid token (401)` even though a valid self-hosted token exists. Always pass `--url https://sentry.12min.com`.
2. DSNs from app deployments are for sending events, not querying issues/events.
3. Secret Manager/GKE may expose SENTRY_DSN or stale auth tokens; prefer the known self-hosted token source above unless the user provides a new token.
4. Do not claim “no Sentry access” until checking Claude local Sentry scripts/memory and the self-hosted URL/token source.
