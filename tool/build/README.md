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

`VOICE_CALL_ALWAYS_RELAY_ENABLED` makes the **Always relay calls** privacy
setting available. It does not choose the transport. The existing secure store
persists an explicit choice independently of the build, and the setting is
honored even if a later build hides its UI. An absent choice uses normal mode;
an unreadable, timed-out or unrecognized choice uses relay-only mode without
overwriting the saved value.

`VOICE_CALL_FORCE_RELAY_ENABLED` is a separate rollout restriction. This file
sets it **false**, enabling the PRD's normal/direct-first default after the
mixed-policy fix and its UDP/TCP device matrices passed. Setting it **true**
restores the previous release's TURN-only restriction without overwriting user
choice. The local production-audio Sims profile explicitly keeps it true
because its oracle requires TURN. Neither flag seeds or migrates the preference.
Custom build invocations that previously used the availability flag to force
relay must now also set `VOICE_CALL_FORCE_RELAY_ENABLED=true` to preserve that
restriction. There was no persisted call preference to migrate in that wiring.

With that restriction disabled, normal calls use `iceTransportPolicy=all`:
native ICE can prefer a direct candidate and retain TURN fallback. The approved
STUN endpoint in `VOICE_CALL_STUN_URLS` is the same Mknoon-operated endpoint
configured in `docker-ws/deploy_relay_v1100.sh`; no third-party STUN service is
added. TURN credentials still come from the authenticated existing provider.
An enabled privacy preference uses `iceTransportPolicy=relay`. Policy is
captured at call admission, before media creation, and stays fixed through
ringing, native adoption, media setup and ICE restarts. Changes apply to the
next call.

Direct media can reveal an address to the other participant. Relay-only media
protects that media path; direct libp2p signaling can independently reveal an
address. This setting does not hide all application addresses.

Do not disable the rollout restriction by changing the availability flag.
The direct-first policy change was checked with the combined call host
regressions and current device evidence for direct media, TURN fallback under
blocked direct connectivity, mixed all/relay calls and selected local TURN in
privacy mode (see `docs/testing/TESTING.md`). This is not a publication approval:
native-wrapper proofs using a local broker do not certify the
production signaling/settings/wake path or a signed distribution artifact.

The relay must be deployed with the call-control handlers and TURN credential
minting enabled (`TURN_CREDENTIALS_ENABLED`, `TURN_CREDENTIAL_URLS`,
`TURN_CREDENTIAL_PRIMARY_SECRET_B64`) before a build with these defines can
place a call; otherwise the client fails closed at endpoint publish.
