# Approved platform scope

Approved by the user: 2026-11-02.

Mobile is focused on fieldwork. Web is focused on management and advanced
processing. Backend availability does not imply a requirement for mobile UI.
This decision supersedes earlier suggestions to mirror all web features on mobile.
It changes delivery scope, not subscription permissions or server enforcement.

## Placement

| Feature | Approved placement | Mobile boundary |
| --- | --- | --- |
| GPS capture, navigation, offline fieldwork and media capture | Mobile-focused | Keep the field workflow usable, including denied location permission and offline drafts. Exact advanced mapping tools still need scoped acceptance criteria. |
| Record viewing/editing, cloud sync and workspace switching | Both | Keep personal/company isolation and preserve pending local records. |
| Basic company management | Both | Retain company creation, invitations, member access and ownership transfer already implemented. |
| Projects/teams, field jobs and review actions | Both | Retain current mobile workflows; do not infer a requirement for every advanced web view. |
| History and recycle bin | Both; retain existing mobile functionality | Keep viewing and authorized restoration. Do not introduce permanent deletion. |
| Current plan, usage and locked-feature explanations | Both | Visibility only on mobile initially; no purchase or subscription-request flow. |
| Individual CSV/KML/GeoJSON export | Both | Implemented for saved cloud records. Pending edits block export; existing text-sharing controls remain. Native device acceptance is still required. |
| Download an existing parcel PDF | Both | Implemented download/share of the latest privately saved web-generated PDF. Shows stale-record warnings; no mobile generation, report design or branding configuration. Native device acceptance remains required. |
| Create/revoke basic public record links | Both | Planned after regression/polish. Backend sharing permissions, link limits and expiry rules remain authoritative. Advanced sharing administration is not part of this mobile addition. |
| Fill/edit existing custom-field values | Both | Planned after regression/polish. Read server definitions/requirements; do not add schema/required-field administration to mobile. |
| Configure custom-field definitions and requirements | Web only | Absence of a mobile definition editor is not a gap. |
| Personal-to-company copy/move | Web only initially | No mobile transfer workflow in the current scope. |
| File imports | Web only initially | No mobile import workflow in the current scope. |
| Bulk/project exports and advanced export formats | Web only initially | Mobile export scope is individual CSV/KML/GeoJSON only. Existing multi-record plain-text sharing is retained, not reclassified as a file-export product. |
| Advanced reports, analytics, templates and scheduling | Web only | No mobile reporting administration or advanced report builder. |
| Plan requests, billing and plan configuration | Web only initially | Mobile displays existing plan/access/approval status; it does not submit requests or collect payments. |
| Advanced administration and Enterprise configuration | Web only | Configure on web. Mobile must still obey applicable server policies and remain compatible with any subsequently enabled authentication requirements. |

## Existing code and remaining requirements

This approval does not remove working mobile company management, ownership
transfer, record history, recycle-bin restoration or sharing controls.

Web-only features that are incomplete on web/backend remain web/backend work.
They are not considered complete merely because they are excluded from mobile.
Examples include advanced reporting, custom roles, audit retention, extra-seat
purchasing and the full subscription lifecycle.

Do not automatically assign every remaining PDF requirement to a platform.
Features such as overlap checks, advanced GPS averaging, custom map layers,
two-step approval and managed offline-area downloads need explicit implementation
boundaries and acceptance criteria before adding new mobile screens or tools.

Server-side record/point/storage limits, roles, read-only downgrade behavior,
device checks and workspace scoping remain applicable to mobile. A web-only
configuration interface is not permission to bypass its resulting policy in-app.

## Next delivery order

1. **Regress and polish the mobile workflows already implemented.** Use the
   checklist below and the detailed `WEB_MOBILE_TESTING.md` scenarios. Fix observed
   defects in focused changes before expanding mobile functionality.
2. **Individual CSV/KML/GeoJSON export.** Confirm the API contract, role/plan gates,
   free CSV guarantees, file naming and sharing behavior. Keep existing text share.
3. **Parcel PDF download.** Implemented with separate saved-report metadata and
   download GET endpoints, private storage, workspace checks and stale warnings.
   Deploy the backend first; reports generated before this change are not saved.
   No mobile report generation or generation-quota charge on downloads.
4. **Basic public sharing links.** Implement only approved creation/revocation and
   clear public-data disclosure, with current server permissions/limits.
5. **Existing custom-field values.** Add appropriate inputs and server validation
   without introducing mobile schema configuration.
6. **Track web/backend and release work separately.** Resolve pre-login recovery
   when no existing device session is accessible, web-only document gaps, isolated
   database/concurrency verification and production configuration.

Items 2-3 are implemented with focused automated coverage; items 4-5 remain planned. Do not start
mobile imports, billing requests, bulk exports or copy/move under this roadmap.

## Mobile regression and polish gate

- Personal/company identity is clear across navigation, forms and record actions.
- Owner/admin/operator/reviewer/viewer controls match server authorization. Include
  current-role changes, self-demotion/removal and ownership transfer.
- Logout/account/workspace changes cannot apply delayed responses to a new scope.
- Capture, pending edits, manual/background sync and quota rejection preserve local
  drafts. Restores cannot overwrite newer pending work.
- Job assignment/progress, project/team links, review/corrections and history work
  end-to-end against isolated backend fixtures, not only mocked HTTP.
- Location denial/GPS-off states permit non-GPS use and do not stack prompts.
- Small screens, enlarged text, keyboard opening, long names, scrolling, dialog
  cancellation, empty/error/loading states and offline recovery remain usable.
- Validate Android/iOS release behavior and device-session limits with test
  accounts; do not enforce an unverified recovery path for production users.

Record PASS, FAIL or BLOCKED with role, workspace and steps. Web-only UI absence
is not a mobile failure. Missing approved mobile features remain planned, not
passing tests. This document does not certify release readiness.

Automated baseline: [2026-11-02 regression report](MOBILE_REGRESSION_2026-11-02.md).
