# Release build defines

`voice_call_release_defines.json` is the single source of the compile-time
gates that turn 1:1 voice calling on. Every gate in
`lib/features/call/application/voice_call_feature_flags.dart` reads a
`--dart-define` with no default, so a build that does not pass this file has
no call button, no incoming-call presentation, and publishes no call endpoint.

Consumers pass it with `--dart-define-from-file=tool/build/voice_call_release_defines.json`:

- `scripts/build_ios_appstore_ipa.sh` (App Store IPA)
- `docker-ws/build_store_release.sh` (Play app bundle + App Store IPA)
- `docker-ws/deploy_all_phones.sh`, `docker-ws/run_fresh_all_phones.sh`,
  `docker-ws/run_fresh_three_phones.sh`, `docker-ws/build_pixel_production.sh`,
  `docker-ws/build_ios_only.sh` (device builds)

Android additionally needs the Gradle gate
`--android-project-arg=enableAndroidNativeCalls=true`, which compiles the
Telecom lifecycle in (`android/app/build.gradle.kts`,
`BuildConfig.ENABLE_ANDROID_NATIVE_CALLS`). The Android scripts above pass it
next to the defines file.

The set matches the `android.e2e.production_call_local` Sims profile in
`tool/sims/critical_features.json` minus the test-only defines. Always-relay
is on: media goes through TURN only, which hides peer IP addresses (VC2-03
section 6, VC2-06 section 5).

The relay must be deployed with the call-control handlers and TURN credential
minting enabled (`TURN_CREDENTIALS_ENABLED`, `TURN_CREDENTIAL_URLS`,
`TURN_CREDENTIAL_PRIMARY_SECRET_B64`) before a build with these defines can
place a call; otherwise the client fails closed at endpoint publish.
