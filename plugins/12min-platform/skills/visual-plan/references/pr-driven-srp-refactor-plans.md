# PR-driven SRP/refactor visual plans

Use this when the user asks for a visual "before/after" before refactoring code that already exists in an open PR.

Workflow:

1. Treat the PR branch as the source of truth. Fetch/check out a dedicated worktree for the PR head rather than planning from a different repo/branch.
2. Research read-only before writing the plan:
   - read the current orchestrating service/class;
   - read low-level clients it calls;
   - read rake tasks/cronjobs or other entrypoints;
   - inspect specs that lock current behavior.
3. In the plan, separate:
   - **Antes**: actual current flow and responsibilities observed in files;
   - **Depois**: proposed class boundaries and entrypoints;
   - **Decisão crítica**: any data model or watermark/ownership issue that makes the refactor real rather than cosmetic.
4. For SRP sync refactors, explicitly name the state/watermark owned by each sink. If two independent sync tasks share one watermark, call out the hidden coupling and recommend a separate watermark or another correctness mechanism.
5. Include a FileTree with expected touched files and mark new service/spec/task files explicitly.
6. Render locally and validate the HTML contains the proposed new class/task names before asking for implementation approval.

Example lesson: splitting a Qdrant catalog sync and pgvector sync is not just class extraction. If Qdrant marks `books.last_indexed_at`, a later pgvector-only sync can miss changes unless pgvector has its own watermark such as `books.pgvector_indexed_at` or another independent freshness source.