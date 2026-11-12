# Web and Mobile Acceptance Testing

Prepared: 29 October 2026. PC: `192.168.1.8`. Backend repository:
`/home/ebenezeri-maleko/Desktop/WORK/databenki_group/tarefgps_web`.
Mobile repository: the repository containing this guide.

## 1. Protect your data first

- Use an isolated test database and test accounts. Never connect this test setup
  to production. Back up any database containing valuable data before migrations.
- Use separate test upload/storage directories too. A cloned database pointing
  at production files is NOT isolated. Do not test deletion on real customer files.
- Keep the existing APP_KEY; do not regenerate it on an existing database.
- Do not run migrate:fresh, migrate:refresh, resets, automatic seeding or rollback.
- This guide was prepared without running migrations or changing live records.
- Recent database/concurrency/browser workflows have not all been verified.
  Passing unit/widget tests does not certify this release for production.

## 2. Backend .env: first test pass

Edit the WEB repository's `.env`, not a mobile file. Keep real secrets private.
Replace database placeholders with a separately created test database/user.

```dotenv
APP_ENV=local
APP_DEBUG=true
APP_URL=http://192.168.1.8:8000
VITE_API_URL=http://192.168.1.8:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=tarefgps_acceptance
DB_USERNAME=YOUR_TEST_DATABASE_USER
DB_PASSWORD=YOUR_TEST_DATABASE_PASSWORD

MAIL_MAILER=log
SESSION_SECURE_COOKIE=false
QUEUE_CONNECTION=sync

COMPANY_ORGANIZATION_ENABLED=true
FIELD_JOBS_ENABLED=true
JOB_REVIEWS_ENABLED=true
COMPANY_ADVANCED_ROLES_ENABLED=true
RECORD_COPY_ENABLED=true
RECORD_MOVE_ENABLED=true
CUSTOM_FIELDS_ENABLED=true
SHARED_LINKS_ENABLED=true

DEVICE_LIMITS_ENABLED=false
USAGE_ALERTS_ENABLED=false
RECOVERABLE_CLEANUP_ENABLED=false
RECOVERABLE_CLEANUP_PROCESSING_ENABLED=false

DXF_ENABLED=false
SHAPEFILE_ENABLED=false
PARCEL_REPORTS_ENABLED=false
```

These flags enable server runtimes, not subscription access. Administrators must
also configure plans, features, limits and company subscriptions.
Advanced roles need the enum expansion migration before the flag is used.
Mail goes to Laravel logs, NOT actual email recipients. Use test verification
links from `storage/logs/laravel.log`; check that their host matches APP_URL.
Do not publish logs, tokens, verification URLs or passwords in bug reports.

### Prepare schema and assets

After independently checking the DB settings and backup:

```bash
cd /home/ebenezeri-maleko/Desktop/WORK/databenki_group/tarefgps_web
php artisan config:clear
php artisan migrate:status
php artisan migrate --pretend
```

Inspect the pending SQL before applying anything. On the confirmed TEST database:

```bash
php artisan migrate
php artisan migrate:status
php artisan storage:link
npm run types:check
npm run build
php artisan serve --host=0.0.0.0 --port=8000
```

Do not continue past a migration failure. The new work includes 22 migrations
dated 26-29 October, in addition to older application migrations. In particular,
the latest must include organization, record assignments, jobs, job links,
reviews and `2026_10_29_000007_expand_company_roles.php`.

Production build is the simplest LAN test: open `http://192.168.1.8:8000`.
For hot reload instead, use a separate terminal:

```bash
npm run dev -- --host 0.0.0.0
```

Vite's advertised asset/HMR host must be reachable from the browsing device.
If assets point at localhost, stop Vite and use the production-build route.
Do not open your router to the internet; allow only trusted LAN access.

## 3. Mobile connection

The current `lib/core/network/api_client.dart` is configured as:

```dart
static const String baseUrl = 'http://192.168.1.8:8000/api/v1';
```

Use the same Wi-Fi, disable VPN/client isolation if applicable, and first open
the web address in the phone browser. Never enter 0.0.0.0 as a client address.
Use `10.0.2.2` instead of the LAN IP for the standard Android emulator if needed.

```bash
cd /home/ebenezeri-maleko/Desktop/WORK/databenki_group/geo_coordinates
flutter devices
flutter run -d YOUR_DEVICE_ID
```

Use a dedicated debug installation/test device with no valuable unsynced records.
Do not uninstall or clear application storage to troubleshoot a device holding
real drafts. Accounts/tokens from production are not valid test credentials.

### Local HTTP blockers

The current manifests/plist do not explicitly provide LAN HTTP exceptions.
If Android reports cleartext blocked, add `android:usesCleartextTraffic="true"`
to an application element in a DEBUG-only manifest, then rebuild. Do not relax
production networking. On iOS, local transport and Local Network access may need
a development-only Info.plist configuration; report the exact device error before
adding broad ATS exceptions. A working phone browser does not prove app transport
permissions are configured.

## 4. Prepare test identities and plans

Use unique test emails. Verify each account.

| Account | Purpose |
| --- | --- |
| Platform admin | Web plan configuration, approvals and platform checks |
| Personal A | Personal records and fallback-plan behavior |
| Company owner A | Company Alpha, plans, memberships and jobs |
| Manager A | Independent admin/reviewer for Alpha |
| Operator A | Assigned field work in Alpha |
| Viewer A | Read-only Alpha access |
| Owner B | Company Beta; cross-company isolation checks |

Use the web admin to create or select TEST plans; never apply presets to a real
customer plan accidentally. Suggested fixtures: personal fallback with 10 records,
company plan with 3 paid seats, 1 free viewer, 2 projects and 1 team. Configure
features for shared workspace, employee management, projects, teams, field jobs
and review. Set `company_roles` explicitly to offer advanced roles. Owner is
assigned through creation/ownership transfer, not a member dropdown.

For a role test company, temporarily use enough seats to add all test identities;
use a separate limited-seat company for boundary tests. Otherwise full seats can
obscure unrelated permission tests. Reviewer is the proposed fifth fixed role;
custom roles and two-step approval are not implemented.

## 5. Test in this order

Mark each row PASS/FAIL/BLOCKED and keep the account/workspace noted.

### A. Platform admin, web first

- [ ] Open subscriptions: create/edit personal and company plans, save, reopen.
- [ ] Confirm prices, intervals, availability, limits and included features persist.
- [ ] Configure fallback personal plan, company role list and role export access.
- [ ] Check feature catalog: mobile-only differs from server-not-ready. Runtime
      readiness does not automatically assign a feature to any plan.
- [ ] On WEB, submit a plan request as a user; approve as admin. Pending requests must
      not immediately change access. No payment should be taken.

### B. Personal A: web, then mobile

- [ ] Sign in; Settings shows Plans & Access and workspace selection.
- [ ] Signed-out/unverified users do not see account workspace tools.
- [ ] Personal mode shows personal identity, navy accent and My library.
- [ ] Plans & Access shows correct fallback/active plan, records, storage MB,
      exports, request state and feature access. Refresh after a plan change.
- [ ] Create, view, rename, edit, navigate to and share test coordinates.
- [ ] Reach a small record limit. New cloud creation is rejected; an offline
      mobile draft stays saved and shows Waiting for space after quota rejection.
- [ ] Free space/raise allowance: retry sync; ensure one cloud record, not duplicates.
- [ ] At an unchanged full limit, existing eligible records remain editable.
- [ ] On WEB/API, individual existing-record CSV stays available; bulk/non-CSV
      obey plan rules. Mobile file export is approved future work; existing text
      sharing is a separate workflow, not a passing file-export test.

### C. Company owner A: web, then mobile

- [ ] Create Alpha, invite a test member, accept/decline as recipient; pending
      invitations appear for sender and recipient. Log-mail delivery is not email.
- [ ] Switch personal -> Alpha -> personal. Names, role, accent and tools change;
      each Library contains only its workspace's records.
- [ ] Mobile company strip shows Alpha and role; company tools open correctly.
      Personal settings do not show the company-only tools section.
- [ ] Create/edit/archive/reactivate projects and teams; exercise quota boundaries.
- [ ] Search/paginate members, add to a team and remove. Company membership,
      paid seat and records must remain unchanged by team-roster removal.
- [ ] Assign records to projects/teams on web and mobile. Library filters and View records
      links show the right records; archived assignment names remain visible.
- [ ] Create a job, assign an active Alpha member, edit description/reassign.
      Link a project and record on both platforms. Closed jobs must not be editable.

### D. Operator, reviewer and viewer

- [ ] Operator can start/complete their assigned job, not unrelated jobs; cannot
      manage company members or approve work via direct requests.
- [ ] Submit completed job, review as another authorized manager/reviewer.
      Self-approval is blocked, including through direct API requests.
- [ ] Request changes with a note -> reopen -> correct -> complete -> resubmit
      -> approve. Web and mobile review history retain earlier decisions and notes.
- [ ] Viewer reads company content but cannot create/edit/delete/import/upload
      or progress jobs. Check menus AND direct API requests.
- [ ] On WEB/API, export roles: unset uses defaults; explicit list restricts bulk/non-CSV/PDF;
      individual CSV remains accessible. A role denial must not suggest upgrading.
- [ ] Remove a role from plan configuration after sending an invitation: it cannot
      be newly activated. Existing active roles are not silently rewritten.
- [ ] Test invitations, activation, reactivation and role changes at seat capacity;
      pending invitations reserve seats, free viewers share the configured slots.

### E. Isolation and recovery

- [ ] Alpha cannot view/change Beta records, jobs, projects, teams or membership IDs.
- [ ] Switch workspace while searches/pages/sync are loading: no stale company data.
- [ ] Open a field-job form, then change account/workspace before saving: it must
      refuse stale submission. Repeat with an in-flight save: its late response
      must not navigate or refresh the new scope. Same-workspace refresh should
      preserve the draft form rather than discard its values.
- [ ] Edit locally during upload: newest edit remains pending; confirmed cloud ID
      is retained. Switch away during a batch: unsent records keep original workspace.
- [ ] Disconnect network: viewing local drafts works, forms retain values, retry
      states do not pretend that a failed access check is a subscription lock.
- [ ] Downgrade a TEST account with >10 records to a 10-record fallback. Newest
      eligible 10 remain manageable, excess are read-only. Check three-dot menus,
      details, bulk actions and direct API. Keep cleanup OFF; expect no deletion.
- [ ] Company expiry: existing data remains readable; new paid work is blocked.
- [ ] Test ownership transfer only on a disposable company. Former owner becomes
      company admin; an ordinary non-owner cannot transfer ownership. Platform
      administrators have the backend-authorized override.

### F. Mobile layout/accessibility

- [ ] Small phone and tablet; 150%/200% text, long company/member/project names.
- [ ] Keyboard open on create/edit/member search/review; Save and errors reachable.
- [ ] Personal/company strip, nav, map controls and bottom sheets do not overlap.
- [ ] Rotate, background/resume, refresh, logout/login using test-only local data.
- [ ] Deny GPS permission: continue browsing. GPS actions explain access without
      trapping the user. Check service-off and permanently-denied states separately.
- [ ] Saved map layer rechecks plan access after login/workspace changes. A confirmed
      denial falls back without overwriting the preference; network errors stay distinct.

## 6. Optional feature test passes

Enable ONE runtime at a time, clear config, restart PHP and test its fixtures.

| Flag | Prerequisite/expected test |
| --- | --- |
| DXF_ENABLED=true | Node + installed runtime dependencies; known survey control-point DXF |
| SHAPEFILE_ENABLED=true | Installed PHP/Node format dependencies; bounded ZIP with SHP sidecars |
| PARCEL_REPORTS_ENABLED=true | Report dependencies/process runtime; open generated PDF and inspect units/logo |
| DEVICE_LIMITS_ENABLED=true | Disposable sessions; exceed limit, revoke a device, retry |
| USAGE_ALERTS_ENABLED=true | Admin Defaults alert switch enabled; log mail, synthetic usage thresholds |

On WEB/API, import/export CSV/KML/GeoJSON/GPX and opt-in formats with known reference coordinates;
compare geometry, units, ellipsoid, labels, counts and file contents. Test malformed
archives and disallowed/oversized formats. Do not equate a downloaded file with
a correct survey result. Do not start the scheduler against production: reconciliation,
notice delivery, import pruning and account cleanup can mutate data or files.
Cleanup/erasure tests require a separate disposable fixture and are not part of
this normal pass. Keep both recoverable cleanup flags false.

## 7. Repeatable automated checks

Web (database-free focused suite):

```bash
npm run types:check
php vendor/bin/phpunit --do-not-cache-result tests/Unit/CompanyRolePermissionsTest.php tests/Unit/CompanyRecordWriteRoutesTest.php tests/Unit/PlanLimitConfigurationTest.php tests/Unit/FieldJobReviewPolicyTest.php tests/Unit/FieldJobTransitionsTest.php tests/Unit/WebFeatureReadinessTest.php
```

Mobile (one worker to reduce memory/swap pressure):

```bash
flutter analyze --no-pub lib/features/workspaces lib/features/subscriptions
flutter test --no-pub --concurrency=1 \
  test/workspace_refresh_safety_test.dart test/workspace_identity_bar_test.dart test/workspace_permissions_test.dart test/workspace_sync_safety_test.dart \
  test/library_organization_test.dart test/organization_page_test.dart test/field_job_form_test.dart test/field_job_link_picker_test.dart \
  test/job_progress_actions_test.dart test/job_review_page_test.dart test/job_review_history_test.dart \
  test/company_create_page_test.dart test/company_invitations_page_test.dart test/company_invite_form_test.dart test/company_members_page_test.dart \
  test/company_member_editor_test.dart test/company_ownership_page_test.dart test/auth_device_identity_test.dart test/device_sessions_page_test.dart \
  test/record_recovery_test.dart test/plans_access_page_test.dart test/feature_access_status_test.dart test/record_access_parsing_test.dart test/land_cloud_exception_test.dart
```

PHP database integration needs PDO SQLite for in-memory tests. The previous
temporary driver path disappeared; do not copy old commands assuming it exists.
MySQL races require the isolated Docker verification harness and remain deferred;
do not point that harness or unreviewed test suites at your application database.

## 8. Known incomplete scope / expected blocks

See [PHASE_TWO_STATUS.md](PHASE_TWO_STATUS.md) for the dated document-to-code
coverage matrix and delivery order. Earlier web readiness notes contain historical
pending items and must not be treated as the current mobile completion checklist.

[APPROVED_PLATFORM_SCOPE.md](APPROVED_PLATFORM_SCOPE.md), approved 2026-11-02,
defines which workflows belong on mobile. Imports, bulk/project exports, billing
requests, copy/move and advanced administration are web only initially. Their
absence on mobile is not a failed test. Individual CSV/KML/GeoJSON export,
existing PDF download, basic public links and existing custom-field value editing
are approved future mobile work, not currently passing scenarios.

- Custom roles, two-step approval and advanced reports/scheduling are incomplete.
- Mobile job project/record links and review history are implemented; verify them
  against the backend rather than treating them as pending development.
- Automatic trials, scheduled/pro-rated transitions and remaining mapping/document
  features must not be assumed shipped; consult the web readiness checklist.
- Some newly added UI text is not localized yet.
- Failed tests should block release. Log PASS/FAIL/BLOCKED separately; disabled or
  unsupported functionality is not a successful test.

## 9. Report issues and restore release configuration

### Mobile record history and recycle bin

- From Library > menu > Recycle bin, page/search deleted cloud records in personal
  and company workspaces. Confirm restore deadlines and blocked/expired reasons.
- Cancel a restore first. Confirm a second time; verify the record returns to web
  and mobile Library, not to another workspace. No permanent-delete control exists.
- Fill the record allowance before restoring: the server must reject restoration
  without removing the deleted row. Confirm viewer/read-only access has no restore
  control and expired restore windows remain blocked.
- Open a synced record's details > Record history. Preview a retained version and
  compare saved names, geometry type and coordinates before restoring.
- Modify the cloud record from web after loading history. The old revision must
  be rejected. Use Reload history and re-review rather than bypassing that check.
- Pending local edits for the same cloud record must block restore. A successful
  cloud restore refreshes cached details but must never overwrite a newer draft.
- Simulate cache-refresh failure after a successful restore: report cloud success
  plus refresh guidance, not a failed restore or an automatic repeat POST.
- Test workspace/account changes during confirmation/network requests; no late
  response may populate another workspace or account. Use synthetic records only.

### Mobile company creation

- From Settings > Create company, submit a name with optional email/phone. Verify
  on web that the company exists and the creator is owner. The current workspace,
  personal records and subscriptions must remain unchanged.
- Open the Workspace selector afterward: the new company should be available but
  not automatically selected. Select it explicitly before adding members.
- Empty names must fail locally; server validation must keep entered fields.
- On a timeout/ambiguous server response, check workspaces before another create
  attempt. The form must not immediately offer an identical repeat submission.
- Test account logout/switch during submission; a late response must not refresh
  or select a company for a different account. Use test companies only.

### Mobile device session checks

- Open Settings > Signed-in devices from an authenticated account. Confirm the
  current session is labeled and has no revoke button. Review every page.
- Cancel signing out another test session: it must remain active. Confirm on the
  next attempt: verify the remote test session loses API access while both phones'
  local drafts remain intact. Never revoke customer sessions for testing.
- Login/registration now send a random installation UUID and platform label. Sign
  out/sign in on the same installation and verify the ID is reused. Reinstalling
  or clearing app data creates a new installation; no hardware ID is collected.
- With device enforcement enabled only in an isolated test environment, fill the
  allowance and attempt login on another installation. It must show the backend
  error plus guidance to use Signed-in devices on an existing session.
- There is no pre-login device-replacement endpoint. If no existing session is
  accessible, recovery still requires support/backend work; do not claim a complete
  self-service replacement flow. Existing legacy sessions may need explicit sign
  out before rollout; old tokens are not silently adopted or deleted by the client.
- Workspace-specific admission may reject access even after login. Use the
  account-wide device manager, free a test session and retry the workspace action.
- Login/password-update request and response bodies must be redacted from HTTP
  debug logs. Do not include tokens or passwords in bug reports.

### Mobile ownership transfer

- Use a disposable test company with at least two active test members. As its
  owner, open Company members > Company actions > Transfer ownership.
- Current owner and inactive memberships must not appear as candidates. Search
  by name/email, choose another member and cancel the confirmation first.
- Confirm on a second attempt: verify on web and mobile that the chosen member
  is now owner and the former owner is admin. Company records must be unchanged.
- Ordinary company admins must not see the transfer action. Platform admins may
  use their backend-authorized override within a selected company workspace.
- Test a recipient deactivated after selection; API rejection must leave the
  screen intact with the explanation, not claim a successful transfer.
- Switch workspace/sign out before confirmation: no stale transfer should send.

### Mobile membership editing

- As owner/admin, open a non-owner member's access editor from Company members.
  Change only the role and confirm; status must remain unchanged.
- Deactivate and reactivate a test member. Reactivation must enforce seat limits;
  rejected requests retain the form and display the server explanation.
- Remove a test membership only after confirmation. Cancelling must not mutate
  membership. Saved company records and the user's account must remain intact.
- When paid management access is unavailable, role changes/reactivation are
  disabled while deactivation/removal remain available, subject to API checks.
- Owner memberships have no edit/remove controls; ownership transfer is separate.
- Change a test admin's own role/access, then verify the workspace selector and
  available tools refresh correctly. Do not use the only owner for this check.

### Mobile invitation creation and acceptance

From Company members, authorized managers can use the invite icon. Search an
existing account using at least two characters, select it, choose a server-enabled
role and send. Check the Pending invitations tab afterward. The person must not
become an active member until acceptance. Verify duplicate/seat-limit rejection
keeps the selection and shows an error. If mail delivery fails after creation,
the message must say the invitation exists and can still be accepted in-app.
Changing the search must clear the previous selected account. Empty configured
roles and unavailable employee-management access must disable sending.

Company managers can open Company members from company Settings or the company
tools menu. Check the Members and Pending invitations tabs independently; pending
users must not appear as active members. Search by name/email and page through
more than 20 accounts. The current API returns complete lists; the mobile page
shows 20 entries at a time locally. Viewer/operator accounts must not see this
manager-only directory. Switch company or sign out with the directory open and
confirm the previous company's accounts are no longer displayed.

- Invite an existing verified account from web. Sign in as that user on mobile
  and open Settings > Company invitations. Confirm the company, role and expiry.
- Cancel acceptance/decline first: the invitation must remain pending.
- Accept: the invitation disappears and the company becomes available in the
  workspace selector. The app must not switch workspaces automatically.
- Decline a separate invitation: it disappears without adding company access.
- Test an expired invitation, changed role eligibility, full seats and a failed
  connection. A rejected response must not show success or fabricate membership.
- Invitations are account-wide and must work from personal and company workspaces.

### Mobile Library assignment checks

- In a company Library, select a project and a team. Search, scroll to the next
  page, refresh, and manually sync; every cloud request should keep both filters.
- Clear the filters to see all records, including pending local drafts. Filtering
  must never delete or reassign a local draft.
- Switch to personal or another company: previous project/team filters must reset.
- Open a synced record as an authorized company manager. Assign, replace, and clear
  its project/team independently; the other assignment must remain unchanged.
- Reopen that record on web and mobile to confirm persisted assignments.
- Archive an assigned project/team: its name must remain visible with an archived
  label, and it must remain selectable as a Library filter, not as a new assignment.
- Viewer/operator accounts and downgrade read-only records must not expose editing
  controls. A failed assignment request must leave the existing assignment intact.

For every failure record: web/mobile, account role, company, action steps, expected
vs actual result, screenshot, relevant HTTP status/message and whether local data
remained intact. Never include credentials or customer coordinates.

Before any release restore the mobile HTTPS production API URL, production network
restrictions, mail/queue settings and reviewed rollout flags. Do not publish local
APP_DEBUG=true, test database credentials or the LAN API URL. Device acceptance
alone does not replace database/concurrency and release-build verification.
# Individual mobile file exports (2026-11-02)

- Deploy the accompanying backend serializer correction; no migration or data
  reset is needed. Use isolated test records, not customer data.
- Open a saved cloud record in Library, then Export file. Verify CSV remains
  available without paid export access, including a read-only existing record.
- Test KML and GeoJSON with permitted and forbidden formats/roles in both personal
  and company workspaces. The API must enforce access independently of the UI.
- Export a point, route and polygon. Inspect longitude/latitude order, route not
  closed as an area, polygon closure, accented names, commas, quotes and ampersands.
- Pending local edits must block cloud file export. Unsynced drafts retain text
  sharing, not the new cloud file action. Existing plain-text sharing is unchanged.
- Cancel native sharing, then Share file again: no second download/quota charge
  should occur while the downloaded file remains on this screen.
- Check Android and iOS/iPad sharing, including the iPad popover anchor, at narrow
  widths and enlarged text. Mocked tests do not establish native plugin behavior.
- Change account/workspace while downloading: do not share the previous scope's
  file. Test offline, forbidden, malformed response and oversized downloads (over
  16 MiB); show an error without sharing an error response as an attachment.

# Saved parcel PDF download (2026-11-02)

## Deployment

- Deploy backend `StoredParcelReport`, report controller/service, route/read-policy,
  private disk configuration and account-erasure cleanup changes together before
  releasing mobile. Refresh Laravel configuration/route caches through the normal
  deployment process. No migration, seed, reset or data cleanup is required.
- The PHP process must be able to write `storage/app/private/parcel-reports`.
  Keep it persistent across deployments and include it in private backups. Never
  symlink it into public storage. Local-filesystem atomic rename is required; this
  disk is not an S3 adapter. Multiple web instances need a shared private filesystem.
- The existing `PARCEL_REPORTS_ENABLED=true` plus GD/Dompdf/PHP-worker requirements
  apply to generating a new report on web, not downloading a previously saved PDF.
  No new environment switch is required. Only reports generated after deployment
  have saved copies. One latest PDF per record is retained; bundles include base64
  content and are bounded to a 12 MiB source PDF.

## Acceptance

- Use isolated personal/company accounts. Before generating a report, Library ->
  record details -> Parcel PDF should show no saved PDF, not a generation action.
- Generate a report on web, then refresh mobile Parcel PDF. Check generation date,
  open/share the file on Android and iOS/iPad, and compare its bytes with the web PDF.
- Check the generation allowance before and after repeated mobile downloads: it
  must not increase. Cancel native sharing and retry: reuse the downloaded bytes.
- Change name, geometry or custom values on web. Refresh mobile: show an older-data
  warning. Regenerate on web and refresh: show the new copy and clear the warning.
- If web regenerates after mobile metadata loads, downloading the old revision
  must return a refresh error, not silently deliver another PDF. A newly stale
  report detected during download requires a separate share action after warning.
- Pending local edits must block download/share. Switching account/workspace while
  downloading must discard the late result. Verify viewer/read-only access,
  removed membership, another user's record, moved records and trashed records.
- Test offline/retry, missing files, corrupted bundles, private-storage write
  failure, and narrow screens/enlarged text. Failed PDF storage must not consume
  generation quota through the normal transaction-failure path.
- On isolated fixtures only, verify personal-account erasure removes its saved PDFs
  after commit and preserves company files. This cleanup is not run by these unit
  tests. Do not test erasure against production accounts.

