# Mobile API environments

The default endpoint is `https://dev.ardhi.co.tz/api/v1` (staging).
Override it at build time; changing it requires rebuilding, not hot reload.

```bash
# Staging
flutter run --dart-define=API_BASE_URL=https://dev.ardhi.co.tz/api/v1

# Production
flutter build appbundle --release --dart-define=API_BASE_URL=https://ardhi.co.tz/api/v1

# Local backend, debug only
flutter run --dart-define=API_BASE_URL=http://192.168.1.8:8000/api/v1
```

Release/profile builds require HTTPS. URLs must include `/api/v1` and cannot
contain credentials, query parameters or fragments. Never put keys or passwords
in this URL. Use separate installations/test devices when switching environments;
log out first to avoid carrying cached records or credentials between servers.

The native Google Maps key is separate from the Laravel API endpoint. Android
reads `GOOGLE_MAPS_ANDROID_API_KEY` from ignored `android/local.properties` (or
the build environment). See `GOOGLE_MAPS_MOBILE.md` for platform setup.

## Google Maps tile diagnosis

The Google logo and map-created callback do not prove imagery has loaded.
Connect the phone, reproduce the failure, then inspect native SDK diagnostics:

```bash
adb logcat -v time 'Google Maps Android API:*' 'Google Maps SDK:*' '*:S'
```

Do not publish logs containing API keys. Check authorization errors against the
installed build's application ID and signing certificate, and check connectivity
before attributing slow tiles to application rendering. Keep Standard available
as a manual fallback. A failed tile load must not be treated as successful map
acceptance; verify capture, overlays and camera movement on the device as well.
