# Google Maps mobile setup

The Google Maps SDK is configured for Android and iOS. The existing map remains
the default. The Google provider is experimental and must not be used for
production surveying until its interactions have been validated on devices.

Enable billing and the Maps SDK for Android and/or iOS in Google Cloud. Use
separate application-restricted keys for each platform; do not commit keys or
paste them into support conversations.

For local Android builds, add `GOOGLE_MAPS_ANDROID_API_KEY=<key>` to the ignored
`android/local.properties`. CI may instead provide the environment variable or
Gradle property `GOOGLE_MAPS_ANDROID_API_KEY`. Restrict the key to the Android
application ID and the appropriate signing certificate fingerprints.

For local iOS builds, create the ignored `ios/Flutter/GoogleMaps.local.xcconfig`
containing `GOOGLE_MAPS_IOS_API_KEY = <key>`. CI can provide the same Xcode
build setting. Restrict this key to the application's iOS bundle identifier.

No keys are required for the existing map provider. Native Google Maps support
also requires Android/iOS device testing and the `map.google_maps` entitlement.

To expose the experimental provider selector in the map type sheet, run a
mobile debug build with `flutter run --dart-define=GOOGLE_MAPS_EXPERIMENTAL=true`.
Without this flag, Google Maps is not offered. Switching back to Standard is
manual; an invalid key or failed tile loading does not trigger automatic
fallback. The native SDK does not report successful imagery loading through the
map-created callback.

The experimental provider renders boundaries, routes, numbered points,
segment-distance labels and a navigation arrow, and uses the native compass.
Verify map alignment, gestures, capture, camera follow, marker legibility and
attribution on both platforms before considering it for release. The SDK does
not guarantee offline imagery availability; use Standard for the existing
cached tile behavior.
