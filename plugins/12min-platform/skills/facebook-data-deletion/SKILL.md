---
name: facebook-data-deletion
description: >
  Resolve Meta/Facebook user data deletion requests for the 12min platform. Use this skill whenever the user mentions Facebook data deletion, Meta "Download User Identifiers", app-scoped Facebook UID, `facebook_data_deletions`, deletion CSV exported from the Meta dashboard, or asks to process/verify/remove users requested by Facebook. The skill supports dry runs, UID-to-user mapping, deletion planning, execution across internal systems and external services, audit registration, and post-delete verification. Trigger proactively when a user shows the Meta deletion email or asks how to process Facebook removal requests.
argument-hint: "[facebook uid, CSV path, or task description]"
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
---

# Facebook Data Deletion

Process Facebook/Meta deletion requests for 12min using the production mapping in `web.identities`, the audit table `facebook_data_deletions`, and the same deletion discipline used for LGPD account removals.

This skill is for the recurring operational workflow behind Meta's "User Data Deletion Request" email and the "Download User Identifiers" CSV.

## Platform facts

- Meta app name: `12min`
- Facebook identities are mapped through `web.identities` with:
  - `provider = 'facebook'`
  - `uid = <app-scoped facebook uid>`
- Audit table: `web.facebook_data_deletions`
- Current callback behavior in `web` is not a full deletion flow. It creates audit context and anonymizes email, but does not remove all user data by itself.
- `facebook_data_deletions.user_id` references `users.id`, so the usual safe completion pattern is:
  1. delete dependent data
  2. keep `users` as a tombstone row
  3. insert/register `facebook_data_deletions`
  4. anonymize personal fields on `users`

## When to use dry run vs execution

- Default to **dry run** unless the user explicitly asks to execute the deletion.
- If the user gives a CSV from Meta, first produce:
  - matched users
  - unmatched Facebook UIDs
  - already processed rows in `facebook_data_deletions`
  - pending users still requiring deletion
- If the user asks to test with one user, narrow the scope to a single pending Facebook UID and show all deletable data before deleting anything.

## Required inputs

Accept any of these inputs:

- one Facebook app-scoped UID
- a CSV exported from Meta's "Download User Identifiers"
- a list of Facebook UIDs
- a support/task link plus the UID list in conversation

If the request is ambiguous, normalize it into one of:

- `dry-run single uid`
- `dry-run csv batch`
- `execute single uid`
- `execute csv batch`

## Step 1. Normalize the request

Extract:

- Facebook UID(s)
- whether this is dry run or execution
- whether the user wants one-user test mode or full batch mode
- any ticket/task that should receive documentation

If the user only says "resolve this" after showing the Meta email, assume:

- source of truth is the Meta CSV or UID list
- first action is dry run

## Step 2. Map Facebook UID to 12min user

Use production data as the source of truth.

Match on:

```sql
SELECT i.uid, i.user_id, u.email, u.name, u.created_at
FROM identities i
JOIN users u ON u.id = i.user_id
WHERE i.provider = 'facebook'
  AND i.uid IN (<facebook_uids>);
```

Classify each UID into:

- `matched_pending`: found in `identities`, not yet in `facebook_data_deletions`
- `matched_completed`: found in `identities` or historical audit, already present in `facebook_data_deletions`
- `unmatched`: not found in `identities`

For dry runs, always present this classification before proposing deletion.

## Step 3. Show the deletion inventory before executing

For each candidate user, inspect and summarize the data that would be removed or anonymized.

Minimum internal checks:

- `users`
- `identities` with `provider='facebook'`
- `libraries`
- `librarians`
- `pins`
- `app_installations`
- `subscriptions`
- `facebook_data_deletions`

Minimum billing checks:

- `v2_subscriptions`
- `v2_invoices`
- `v2_receipts`

Also inspect any obviously user-bound rows discovered during the run. If the local LGPD flow or repo documentation exposes additional 12min-owned tables for this environment, include them instead of silently ignoring them.

The dry run output should make the deletion target obvious:

- Facebook UID
- internal `user_id`
- current email
- whether user is already tombstoned/anonymized
- row counts by table/service

## Step 4. Confirm before irreversible work

Before execution, state clearly:

- the exact Facebook UID(s)
- the mapped internal `user_id`
- the current email
- which systems will be touched
- that the operation is irreversible

If the user did not explicitly ask to execute, stop after the dry run.

## Step 5. Execute external-service deletion first

Run external deletions before internal cleanup when possible so you still have the identifiers needed by vendors.

Primary services for 12min:

1. ActiveCampaign
2. OneSignal
3. SendGrid suppression or contact removal
4. Amplitude GDPR deletion request
5. Adjust GDPR device forget, when device identifiers exist

Execution guidance:

- `ActiveCampaign`: delete by email if the contact exists.
- `OneSignal`: delete by `external_id = web.users.id`.
- `SendGrid`: suppress or remove the email so future sends stop.
- `Amplitude`: submit the GDPR deletion request using the identifiers available for the app. This may fail for numeric-only IDs if the app did not track them that way; log the HTTP response and keep going.
- `Adjust`: only if you can still find device identifiers associated with the user.

Rules:

- `not found` is not fatal; record and continue.
- vendor API failure is not a blocker for internal deletion; record it for follow-up.
- save enough response detail for the final report or task comment.

## Step 6. Execute internal deletion with tombstone preservation

Use the Facebook UID mapping result to delete internal records, but do not hard-delete the `users` row if you need to preserve `facebook_data_deletions`.

Preferred sequence:

1. delete dependent rows in `web`
2. delete dependent rows in `billing`
3. remove the Facebook identity row
4. insert `facebook_data_deletions` if missing
5. anonymize the `users` row into a tombstone

Typical `web` cleanup includes:

- `pins`
- `librarians`
- `libraries`
- `app_installations`
- `subscriptions`
- `identities` for provider `facebook`

Typical `billing` cleanup includes:

- `v2_receipts`
- `v2_invoices`
- `v2_subscriptions`

Tombstone expectations for `users`:

- replace email with `deleted-<confirmation_code>@facebook.com`
- null personal fields such as name, phone, username, bio, profile images, auth tokens, and other directly identifying attributes

If the environment has model callbacks or scripts that already implement this safely, prefer those over ad hoc SQL.

## Step 7. Register completion in `facebook_data_deletions`

Ensure there is an audit row for the processed user.

Minimum fields:

- `user_id`
- `confirmation_code`
- timestamps

If a row already exists, do not create a duplicate. Reuse the existing audit context and verify the user is already cleaned up.

## Step 8. Verify post-delete state

After execution, verify and report:

- `facebook identity = 0`
- dependent `web` tables are empty for that user
- dependent `billing` tables are empty for that user
- `facebook_data_deletions = 1`
- `users = 1` only if intentionally retained as tombstone

Call out any expected leftovers explicitly. A retained `users` row is acceptable only when it is anonymized and required by the audit relation.

## Step 9. Document the run

When a task or support thread exists, leave a concise operational note with:

- batch size or single UID scope
- matched, unmatched, completed, and pending counts
- for executed users: Facebook UID, internal `user_id`, anonymized email, systems touched
- any vendor-specific failures or manual follow-up required

## Output format

Use this structure:

### Dry run

- Scope
- Matched pending users
- Already completed users
- Unmatched Facebook UIDs
- Data inventory by user
- Recommended next action

### Execution

- Scope executed
- External services results
- Internal deletion results
- `facebook_data_deletions` audit status
- Post-delete verification
- Follow-up items

## Guardrails

- Never delete based only on email when the request came from Meta. The source identifier is the Facebook app-scoped UID.
- Never assume "not found in `identities`" means the deletion is complete. Distinguish between unmatched and already audited.
- Never hard-delete `users` if that would orphan or violate `facebook_data_deletions`.
- Do not execute a batch delete immediately after a CSV import unless the user explicitly approved execution.
- If one UID is enough to validate the flow, test with a single pending user first.

## Example prompts

- `Processa esse CSV do Meta e me mostra quem está pendente antes de apagar`
- `Faz um dry run do facebook uid 9892407167497238`
- `Pode executar a exclusão desse usuário do Facebook e registrar em facebook_data_deletions`
- `Recebi um User Data Deletion Request da Meta para o app 12min; confere os identificadores`
