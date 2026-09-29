# Survey delivery handoff

The Flutter app saves survey responses locally under the Hive key
`pending_user_surveys_v1` and retries `POST /api/v1/surveys` on submission and
in the existing background sync loop. A response leaves the queue only after
the server confirms the matching UUID. The mobile UI says the answer is saved
and will sync automatically; it does not claim immediate delivery.

Each queued response contains only `id` (UUID for idempotency), `schema_version`
(currently 1), `role`, `difficulty`, `satisfaction` (1–5), `comment` (up to 1000
characters), and `created_at` (UTC ISO 8601). It contains no coordinates, land
records, email address, or account ID.

The sibling `tarefgps_web` backend implements the public, rate-limited POST
endpoint and an admin-only `GET /api/v1/admin/surveys` endpoint. The UUID makes
retries idempotent. No free-text comment is written to mobile debug logs.
Review the privacy policy and deploy the backend migration before releasing
the mobile update.
