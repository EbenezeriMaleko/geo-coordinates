# Phase Two: implementation audit

Reviewed: 2026-10-31. Source: TaREF Subscription Plans, draft 1.0 dated
2026-10-24, plus the subsequent decisions in this project conversation.

Scope revised: 2026-11-02. [APPROVED_PLATFORM_SCOPE.md](APPROVED_PLATFORM_SCOPE.md)
is authoritative for feature placement. This matrix records implementation, not
a requirement to reproduce every web workflow on mobile. Earlier mobile-parity
recommendations are superseded by the approved split.

This is a source-code audit, not deployment certification. A feature being in
code does not mean its migrations, runtime flag, plan configuration or production
dependencies are enabled. No database, mail, scheduler or cleanup commands were
run for this audit. No application behavior or customer data was changed.

## Agreed interpretation

- Plan names, prices, feature policies, roles and supported allowances remain
  administrator-controlled. The eight presets are drafts, not live entitlements.
- Personal values in section 2.1 take precedence over conflicting section 6
  values: Free 10 records/20 points/10 MB, Basic 100/200/100 MB,
  Professional 500/500/1 GB and Expert unlimited/5,000/2 GB.
- Billing remains manual approval. No payment provider has been approved.
- On downgrade, only the newest records within the new allowance remain
  manageable. Excess records are read-only, including no delete/manage actions.
- The requested grace period is 14 days, overriding the document's conflicting
  wording. Recoverable cleanup exists separately and must stay disabled until
  explicitly validated and approved. Permanent purge is not implemented.
- The document does not name its fifth fixed company role. Reviewer exists in
  the current implementation; confirm that product terminology before launch.

## Status key

- **Present**: a corresponding application workflow and server implementation
  were found. This is not a claim that every edge case is acceptance-tested.
- **Partial**: some implementation exists, but important requirements remain.
- **Missing**: no matching end-to-end implementation found in the inspected scope.
- **Operational**: requires a business/service delivery process, not just code.
- **Web only**: no mobile UI is required in the approved initial scope; any
  incomplete web/backend implementation still remains work.
- **Deferred scope**: the detailed mobile boundary is not approved yet. Do not
  count it as a committed mobile feature or silently add screens for it.

Rows below group related requirements. They are not a count of every individual
feature in the document. An existing generic API or configuration key alone is
not treated as completion of a promised product feature.

## Coverage matrix

| Requirement group | Web/backend | Mobile | Remaining work |
| --- | --- | --- | --- |
| Admin-defined personal/company plans and feature policies | Present | Read-only access | Configuration and plan requests are web only. Mobile consumes policies and displays access. |
| Eight plan presets and proposed prices | Partial | Web only | Presets exist; live catalog/policies require admin configuration. Mobile does not administer plans. |
| Personal/company workspace isolation and switching | Present | Present | Real account-switch, offline and concurrency acceptance remains required. |
| Company creation | Present | Present | Mobile creation refreshes company choices without selecting the company or activating a plan. Ambiguous outcomes require checking workspaces before retry. |
| Invitations, acceptance/decline, member directory | Present | Present | Confirm production email failures and expired/duplicate invitations with test accounts. |
| Role/status changes, removal and ownership transfer | Present | Present | Re-test self-demotion/removal, ownership and access changes across devices. |
| Fixed roles, viewer-seat allowance, export-by-role policy | Present | Partial | Mobile lacks the server-backed format export workflow; validate seat accounting under concurrent invitations. |
| Custom roles and two-step review | Missing | Deferred scope | Custom-role configuration belongs on web; any advanced mobile review/auth behavior needs scoped acceptance criteria. |
| Record, point, media-storage and export quotas | Present | Partial | Mobile queues rejected drafts and shows usage; approved individual export integration remains planned. Import/bulk-export UI is web only. |
| Downgrade newest-N management / excess read-only | Present | Present | Verify every mutation surface with real downgrade fixtures, including assignments and bulk actions. |
| Grace notices and cleanup | Partial | Partial | Backend notices/recoverable cleanup exist. Mobile lacks full notice/recovery UI. Permanent deletion is not shipped. |
| Device limits and choosing a device to sign out | Partial | Partial | Signed-in session listing/revocation, installation ID and login guidance now exist. No pre-login replacement endpoint exists; inaccessible-device recovery remains backend work. |
| Record history and restoring versions | Present | Present | Mobile lists/previews retained versions and restores with the loaded cloud revision; pending local edits block restoration. |
| Recycle bin and restoration | Present | Present | Mobile lists/searches deleted records, displays restore deadlines and uses quota/role-checked restores. No permanent delete control. |
| Capture/drawing, standard and satellite map tools | Present | Partial | Basemap feature grouping exists, not complete document-specific layer/plan controls. |
| Coordinate entry/formats, datum and shape-edit plan controls | Partial | Partial | Tools exist, but approved per-plan restrictions are not comprehensively represented/enforced. |
| Per-point GPS accuracy and averaging | Partial | Partial | Displaying current GPS accuracy is not retained per-point accuracy plus an averaging workflow. |
| Personal/company plot overlap checks | Missing | Deferred scope | Needs a scoped geometry workflow, platform placement and plan policy before mobile commitment. |
| Offline map areas and area-count allowances | Missing | Partial | Mobile tile caching exists; it is not downloadable/manageable areas with enforced area counts. |
| Custom WMS/XYZ/boundary map layers | Missing | Deferred scope | Configuration is advanced web work; any mobile rendering commitment needs explicit scope. |
| Individual CSV/KML/GeoJSON export | Present | Missing (approved) | Add after mobile regression/polish. Existing text sharing is retained but is not equivalent to a file export. |
| File imports and DXF/GPX/Shapefile export | Present | Web only | Keep advanced file processing on web initially. |
| Bulk and project exports | Partial | Web only | Web bulk export exists; the dedicated project-export gap remains web/backend work. |
| Parcel PDFs, watermark/logo/side-measurement options | Present | Implemented (saved-PDF download/share only) | Web generation saves the latest PDF privately. Mobile uses read-only endpoints and warns on changed record data. Native acceptance remains pending. |
| Public read-only sharing, password links, company switch | Present | Missing (basic links) | Mobile basic link creation/revocation is approved. Advanced administration is not a mobile requirement. Text sharing is separate. |
| Custom and required record fields | Present | Missing (values only) | Mobile fills/edits existing values. Definition/required-field configuration is web only; do not infer that a full definition catalog exists from per-record field support. |
| Personal-to-company record copy/move | Present | Web only | No mobile transfer workflow in the initial approved scope. |
| Projects/teams, archives, rosters and record assignments | Present | Present | Assignments organize records; they do not create project/team visibility boundaries. |
| Field jobs, project/record links and progress | Present | Present | Existing UI is a status-based list, not necessarily a dedicated drag/drop jobs board. |
| Review/corrections/history | Present | Present | This reviews completed jobs, not independent approval/version locking of each linked land record. |
| Record/job comments and naming rules | Missing | Deferred scope | Review notes are not general comments. Naming-rule configuration is web administration; mobile behavior needs scoped criteria. |
| Project reports, team analytics, templates and scheduling | Missing | Web only | Parcel report generation does not satisfy these web/backend requirements. |
| Usage alerts and complete usage presentation | Present | Partial | Mobile shows records/storage/exports, not every seat/link/report/device limit and notice. Verify live delivery separately. |
| Manual subscription requests/approval | Present | Web only | Mobile keeps current/pending access visibility; requests and billing stay on web initially. |
| Automatic trials, proration, scheduled downgrade and expiry lifecycle | Partial | Server policy consumption | Full lifecycle remains backend/web work. Mobile must reflect resulting access, not provide billing administration. |
| Extra-seat purchasing and per-workspace negotiated overrides | Missing | Web only | Configurable plan seats are not add-on purchases or workspace-specific allowances. Mobile must obey the resulting limits. |
| Audit log retention and downloadable Enterprise audit product | Partial | Web only | Events exist; configuring audit_log_days does not implement the web/backend retention/export product. |
| Mandatory organization 2FA, SSO, customer API/webhooks | Missing | Deferred auth compatibility | Configure on web; mobile authentication must be reviewed before enabling new security requirements. App endpoints are not a customer API product. |
| Section 7 pricing presentation | Partial | Not applicable | Audience switch/comparison exist; monthly/yearly and currency controls, featured plans and full allowance comparison are incomplete. |
| Support SLAs, training, uptime and negotiated discounts | Operational | Operational | Need approved service delivery, owners and agreements, not unsupported marketing claims. |

## Source evidence

Web paths below are relative to the sibling `tarefgps_web` repository.

- `app/Services/PlanLimitConfiguration.php`: accepted configurable count/format/
  role keys. Coordinate-format/datum rules and custom roles are not present there.
- `app/Services/SubscriptionPlanPresets.php`: eight draft presets and section 2.1
  personal values. Draft price metadata does not create billing periods/products.
- `app/Services/FeatureRegistry.php`: current registered feature keys; not every
  document tool has its own implemented policy or workflow.
- `app/Services/CompanyRolePermissions.php`, `CompanySeatService.php`: fixed roles,
  viewer accounting and export policy foundation, not custom-role definitions.
- `app/Http/Controllers/Api/V1/CompanyController.php`: company creation,
  invitations, membership changes and locked ownership transfer.
- `CompanyOrganizationController.php`, `FieldJobController.php`,
  `FieldJobReviewController.php` in that directory: organization, jobs and review.
- `app/Services/RecordRetentionService.php`, `RecoverableCleanupService.php`:
  downgrade restrictions and recovery-first soft deletion, not permanent purge.
- `RecordHistoryService.php`, `RecycleBinService.php`, `RecordSharingService.php`,
  `ParcelReportService.php`, `CustomFieldService.php`, `RecordCopyService.php`,
  `RecordMoveService.php`, `DeviceSessionService.php`: server implementations that
  must not be mistaken for mobile integration.
- `resources/js/components/public-pricing.tsx`: audience switch and feature
  comparison. Compact mode displays up to three plans, not section 7's four-card
  presentation; it lacks the requested period/currency selectors and featured
  Professional/Team treatment.
- `config/services.php`: runtime gates. This audit did not read or change live
  `.env` values, so enabled deployment state is deliberately unknown.

Mobile evidence:

- `lib/features/workspaces/`: organization, job/review, invitation, membership,
  ownership, assignment and workspace switching implementations.
- `lib/features/subscriptions/plans_access_page.dart`: read-only access/usage;
  no plan purchase or request submission UI.
- `lib/features/land_map/services/land_sync_service.dart`: pending records and
  quota-failure preservation; sync safety tests use synthetic Hive data.
- `lib/features/land_map/ui/saved_locations_page.dart`: organization filters,
  manual sync and plain-text sharing. No server-format export/download integration
  was found here.
- `lib/features/auth/services/auth_device_identity.dart` and
  `lib/features/auth/ui/device_sessions_page.dart`: installation-scoped ID and
  signed-in device management. `auth_service.dart` recognizes the current login
  allowance error; it does not offer an unauthenticated replacement API.
- `lib/core/network/api_client.dart`: still uses the LAN development URL. Restore
  reviewed production configuration before release.

## Delivery order

1. **Regress and polish existing mobile workflows.** Follow the approved scope's
   regression gate and test guide before adding more mobile features.
2. **Approved mobile additions only:** individual CSV/KML/GeoJSON export, existing
   PDF download, basic sharing links and editing existing custom-field values.
   Confirm each API contract and keep changes separately tested.
3. **Web/backend backlog:** imports, bulk/project exports, transfers, billing,
   advanced reports, administration and unimplemented document requirements.
   Web-only placement does not make missing backend behavior complete.
4. **Safety/release track:** pre-login device recovery, isolated MySQL/concurrency
   tests, always-readable/CSV behavior, platform testing, localization and reviewed
   production configuration. Do not enable an unverified recovery path or cleanup.

Do not add mobile imports, subscription requests, copy/move, report generation or
advanced administration under this scope. See APPROVED_PLATFORM_SCOPE.md for the
full split and dependencies, including the download-only PDF contract check.

## Verification boundary

Saved parcel PDF download/share is implemented in mobile record details. The
backend now retains the latest web-generated report on the private `parcel_reports`
local disk, outside public storage. GET `/lands/{id}/report/saved` reads metadata;
GET `/lands/{id}/report/download?revision=...` downloads only an existing artifact.
These paths authorize current record/workspace access and do not call report
generation or usage counters. They remain readable under existing-record policy.
Record-content changes trigger stale warnings; a replaced PDF requires refreshing
the artifact revision. Pending local edits block mobile sharing. Personal-account
erasure queues saved report removal through the existing post-commit cleanup.
No database migration is required. Persistent private storage and deploying the
backend/config/routes before the mobile update are required. Previously generated
PDFs cannot be recovered automatically. Native sharing, full middleware/database
integration, storage-failure transaction behavior and erasure integration still
require isolated acceptance testing. File replacement is atomic on the local
filesystem, not a distributed transaction with MySQL.

Individual mobile CSV/KML/GeoJSON export is implemented for saved cloud records
via the record details actions. It preserves plain-text sharing and blocks pending
local edits. CSV remains selectable without paid export access; other formats use
the current workspace access snapshot, with server authorization authoritative.
Canceled sharing reuses the downloaded file rather than consuming another export.
Downloads are bounded to 16 MiB. Larger, bulk and advanced exports remain web-only.
Deploy the accompanying backend RecordTextExport serializer changes before the
mobile release: they correct geometry types, CSV quoting, XML escaping and safe
attachment names. No database migration is involved. Native sharing acceptance
and isolated API integration remain outstanding.

Recent focused Flutter tests cover workspace refresh races, sync preservation,
organization filters, job links/review history, invitations, membership controls
and ownership selection/confirmation/error behavior. They do not replace API
integration, real email, simultaneous-user, Android/iOS release or database tests.
The separate [2026-11-02 mobile regression](MOBILE_REGRESSION_2026-11-02.md)
passed 86 tests across 24 selected files with one worker. This was a focused mobile
run, not the full repository suite or a live backend/device acceptance test.

Earlier web readiness notes are historical and contain superseded pending items,
especially fixed roles, job review and the mobile workspace workflows. Use this
dated matrix with `WEB_MOBILE_TESTING.md` to plan work, and update it after each
completed stage. Do not advertise the entire PDF as implemented.
