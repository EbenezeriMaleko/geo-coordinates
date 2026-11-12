# Mobile regression: 2026-11-02

Scope: [APPROVED_PLATFORM_SCOPE.md](APPROVED_PLATFORM_SCOPE.md).

## Result

**PASS: 86 tests across 24 selected test files.** The final Flutter test process
exited successfully, using `--no-pub --concurrency=1`. The repeatable command is
in section 7 of [WEB_MOBILE_TESTING.md](WEB_MOBILE_TESTING.md).

An initial parallel run was cancelled because the host was under heavy memory
and swap pressure. Cancellation produced test-runner shutdown errors; the final
single-worker run above is the completed result, not the interrupted run.

## Automated coverage

- Workspace/session refresh races, switching and identity-bar layout.
- Explicit workspace permissions and read-only record parsing.
- Pending draft preservation, sync failure and upload/edit/delete races.
- Company Library filters, pagination and workspace reset.
- Project/team organization screens and project dialog cancellation.
- Field-job editing, link selection and progress permissions.
- Review permissions, self-approval controls and paginated review history.
- Company creation, unchanged workspace selection and uncertain-create outcomes.
- Invitation creation, delivery-result wording, acceptance/decline and errors.
- Member directory, role/status changes, removal and owner protection.
- Ownership selection, confirmation, failed transfer and access restrictions.
- Installation identity, auth-body redaction and signed-in device management.
- Recycle/history restore, stale revisions, local draft protection and cache errors.
- Plans/access usage layout, feature-status wording and quota error classification.

Tests use synthetic fixtures, temporary local storage and mocked services/HTTP.
URLs printed in mocked HTTP logs are not evidence of live backend requests.
The selected run is not every test in the repository. No full analyzer run was
performed in this documentation/scope pass.

## Not verified in this pass

- Actual Android/iOS release builds, GPS permission dialogs, background/resume,
  keyboard behavior on physical devices, rotation and 200% text throughout the app.
- Live backend authorization, simultaneous-user changes, isolated MySQL locks,
  real email delivery and end-to-end device revocation.
- The pre-login replacement path for users unable to access any existing session;
  this remains a backend recovery gap, not a completed mobile feature.
- Approved future mobile individual exports, existing-PDF downloads, basic public
  links and existing custom-field value editing; these are not implemented/tested
  by this scope update.
- Web-only features: their absence from mobile is intentional, not a mobile defect.

## Baseline change boundary

Only documentation was changed in the baseline pass above. Existing application code, user data,
database schemas, environment flags, subscriptions and permissions were not changed.
No migrations, cleanup, scheduler, production email or real membership actions ran.

Next gate: perform the remaining device/backend acceptance scenarios and fix
observed defects. Then add only the approved mobile features in the scope document.
This report is a test baseline, not production certification.

## Follow-up polish: field-job form scope safety

A subsequent pass on 2026-11-02 changed `field_job_form.dart` and its tests:

- Forms retain the opening account token/company and refuse submission after
  an account/workspace change. Searches and the stale form are no longer exposed.
- Late save responses cannot pop the form or refresh a different account/company.
- Same-workspace refreshes retain the form, and interrupted saves release the
  busy/back-navigation state when the request finishes.
- Existing string job IDs still update the original job; untouched project/record
  links remain omitted from update payloads rather than being silently cleared.
- A small injectable save service permits testing these races without live API
  requests; backend payloads/endpoints are unchanged.

Final focused follow-up run: **14 tests passed** across `field_job_form_test.dart`,
`field_job_link_picker_test.dart`, `job_progress_actions_test.dart` and
`workspace_refresh_safety_test.dart`, with `--no-pub --concurrency=1`.
This is a new focused result, not a rerun of the entire 86-test baseline.

Only Linux/Chrome targets were detected. No Android/iOS device or confirmed
isolated test API was supplied for this pass. Real-device/backend acceptance is
still not verified; no customer records, migrations, mail or environment flags
were used/changed for this follow-up.
