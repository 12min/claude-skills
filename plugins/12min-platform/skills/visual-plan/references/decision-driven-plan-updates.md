# Decision-driven plan updates

Use this pattern when a local visual plan is being refined through user decisions and live evidence.

## Pattern

1. Keep the plan artifact as the source of truth. When the user decides a previously open question, update the plan immediately rather than only answering in chat.
2. Replace recommendations/open questions with explicit decisions. Do not leave stale alternatives in command snippets, tables, diagrams, or validation text.
3. If a decision depends on live infrastructure, gather read-only evidence first and record the evidence compactly in the plan:
   - provider/project/region/VPC;
   - availability mode such as Cloud SQL `ZONAL` vs `REGIONAL`;
   - names of existing resources used as precedent;
   - whether legacy env var names are historical aliases rather than proof of provider.
4. If the plan depends on code in another repo/PR, inspect the PR before updating:
   - `gh pr view <N> --repo owner/repo --json title,url,state,headRefName,body,files,commits,statusCheckRollup`
   - `gh pr diff <N> --repo owner/repo --name-only`
   - for specific files on the PR branch: `gh api repos/owner/repo/contents/<path>?ref=<headRefName> --jq '.content' | base64 --decode`
5. Update operational commands to match the decisions. Example: if the user chooses Single-AZ for Cloud SQL, ensure every command uses `--availability-type=ZONAL` and verify no stale `--availability-type=REGIONAL` remains.
6. Re-render with the local renderer and run a small validation command against the generated HTML for the critical terms. Example validations:
   - HTML contains the chosen resource names;
   - HTML contains the chosen provider/availability mode;
   - HTML no longer contains the old candidate name or command flag.

## Pitfalls

- Do not infer RDS from historical `RDS_*` env var names. In 12min infrastructure those vars may point to GCP Cloud SQL private IPs.
- A Cloud SQL read replica in the same zone is not equivalent to `REGIONAL` / Multi-AZ HA. Check `settings.availabilityType`, `gceZone`, and replica zone before recommending parity.
- For Kubernetes Secrets consumed through `envFrom`, adding keys to the existing external Secret can be enough; avoid suggesting deployment YAML changes unless a workload uses explicit per-key `env` entries or needs a new CronJob.
- Never apply a minimal Secret manifest over a shared secret. Use a patch/update flow that preserves existing keys.
