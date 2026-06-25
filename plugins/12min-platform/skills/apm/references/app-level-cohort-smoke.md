# App-level cohort smoke for low-traffic strangler endpoints

Use when a production ramp at `NATIVE_*_PCT` has healthy service-level APM but zero endpoint-specific samples in the observation window.

## Pattern

1. Identify the controller transaction name from code or historical APM. For `GET /api/v1/books/:id/recommendations`, the APM transaction is `Api::V1::BooksController#recommendations` and path is `/api/v1/books/:id/recommendations`.
2. Query both the legacy and native services over a longer window (`now-24h`) to discover whether samples exist and whether they are legacy/proxy/native:
   - `service.name=api-production`
   - `service.name=api-books-v2-production`
   - filter `url.path` or `transaction.name` with the endpoint.
3. If recent endpoint samples are absent, generate one controlled authenticated request using a real production user whose deterministic cohort bucket falls inside the current PCT.
4. To choose a user without printing secrets, query production API DB for candidate `id, authentication_token`, compute `Zlib.crc32("<endpoint_key>:<user_id>") % 100`, pick one below the rollout PCT, and only print `user_id` + bucket — never the token.
5. Send one request with `X-Token` and a clear `User-Agent` such as `Hermes rollout smoke <endpoint>/1.0`.
6. Wait ~20-30s, then query APM over `now-5m`/`now-10m` for the endpoint transaction and report:
   - status/outcome
   - duration
   - `labels.cohort`
   - `labels.native_pct`
   - trace id
7. Also query failures for the same service/window and aggregate by transaction/path. If failures are on unrelated proxied endpoints, say that explicitly rather than blocking the ramp on unrelated noise.

## Pitfalls

- A zero endpoint-specific count in a short window often means no traffic, not no instrumentation.
- Service-level `Net::ReadTimeout` errors can come from unrelated `ProxyController#forward` paths; always group failures by `transaction.name` and `url.path` before attributing them to the ramped endpoint.
- Python on macOS may fail HTTPS certificate verification for direct smoke calls. Ruby `Net::HTTP` can be a simpler local smoke client if Python lacks certs.
- Do not save or display production tokens. Use temp files and clean them up.
