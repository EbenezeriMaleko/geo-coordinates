# Map performance and cost acceptance

## Implementation

- Standard remains the default and switching provider requires a user action.
- Native Google Maps uses `google_maps_flutter`; no Google Routes, Places or
  Street View integration is added by the map surface.
- Routing currently uses the OSRM public demo endpoint. This is not a production
  availability guarantee or an unlimited free routing service; review hosting
  and usage terms before rollout.
- Camera zoom updates store the latest position without rebuilding the complete
  Flutter map page. Identical Google camera commands are skipped.
- Do not cache or bulk-download Google imagery outside supported SDK behavior.

## Cloud controls required before rollout

Google's pricing list currently lists native Maps SDK usage with an unlimited
free cap. This does not make all Google Maps products free: web Dynamic Maps,
Routes, Places, Street View and tile/report services have separate SKUs.
Check actual usage by SKU in the billing console rather than estimating charges
from Flutter rebuild counts or the number of survey points.

- Use separate Android, iOS and browser keys. Restrict each to the appropriate
  application/signing certificate or website and only the APIs it needs.
- Separate staging and production projects where practical.
- Set budget notifications and available quotas on paid services. Budget alerts
  alone do not automatically stop spending. Quota availability varies by API.
- Review real billing before expanding access. Never rely on a mobile-only
  counter as a billing cap.

Sources checked 2026-11-15:
- https://developers.google.com/maps/billing-and-pricing/pricing
- https://developers.google.com/maps/billing-and-pricing/manage-costs
- https://developers.google.com/maps/documentation/android-sdk/usage-and-billing

## Device acceptance

Use a profile build, the same device, record, map type, network and gesture
sequence for before/after comparisons. Debug builds and historical app-wide
Android frame statistics do not certify map performance.

1. Pan and pinch-zoom repeatedly with a representative large survey loaded.
2. Check that geometry, point labels, distances and navigation remain aligned.
3. Switch providers, open/close Settings, and return from the background.
4. Verify GPS follow does not fight manual gestures.
5. Record Flutter frame timing and native-map logs; distinguish authorization,
   networking and tile loading failures from Flutter layout work.
6. Check map/API usage in Cloud separately from frame timing.

The connected Android app showed 251 janky frames out of 1,055 historical frames
during inspection. This is an app-wide installed-build baseline, not a controlled
map benchmark or evidence that a subsequent code change improved performance.
