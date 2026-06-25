# SRP sync visual plans — lessons

Use this reference when a plan is about splitting a shared sync/orchestrator into independent services, rake tasks, or CronJobs.

## Visual layout

- Prefer vertical Mermaid (`flowchart TD`) for long pipelines. Horizontal diagrams become unreadable in the HTML renderer when two pipelines sit side-by-side.
- Put shared dependencies in a top/central subgraph, then each responsibility/cadence in its own subgraph below it.
- Name each lane by responsibility, not implementation detail: e.g. `Qdrant sync`, `pgvector content sync`, `pgvector reads refresh`.

## Modeling SRP correctly

- If two workflows have different cadences, model them as separate rake tasks/CronJobs even if they write to the same store.
- Do not merge a frequently-changing signal into a slow content sync for convenience. Example: book content/embeddings can sync nightly, while `reads`/popularity may need hourly or every few hours.
- For separated syncs, identify the watermark for each sink. A shared watermark can hide updates from the second sink after the first marks the source record as synced.

## Shared expensive dependencies

- If both syncs need an expensive generated artifact (e.g. Gemini embeddings), add a shared provider/facade block.
- A Ruby `Singleton` only deduplicates inside one process. Separate CronJobs/processes need a persistent cache such as `Rails.cache` keyed by model + content hash.
- Prefer a key derived from the exact semantic content (`sha256(content)`) over `updated_at` alone, because records can change for non-semantic reasons.

## Example structure

- `AI::QdrantCatalogSyncService` + `rake qdrant_books_sync` + Qdrant CronJob.
- `AI::PgvectorCatalogSyncService` + `rake pgvector_books_sync` + pgvector content CronJob.
- `AI::PgvectorReadsRefreshService` + `rake pgvector_refresh_reads` + more frequent reads CronJob.
- `AI::BookEmbeddingProvider.instance` as shared Gemini facade/cache.
