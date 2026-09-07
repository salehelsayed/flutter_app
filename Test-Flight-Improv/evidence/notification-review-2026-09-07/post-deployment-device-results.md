# Post-deployment device smoke — 2026-09-07

The deployed relay was reported healthy by the root agent at 10:12:25 UTC, with durable wake storage enabled. This device leg used preserved test accounts and the previously installed final clients; no rebuild, reset, or private-phone control occurred. All times below are UTC; raw device logs display UTC+02:00.

## Targets and installed builds

- Pixel 6 `21071FDF600CSC`, Android 16/API 36, account `picel`: versionCode111, `1.0.0-807874437-notification260907-final`.
- `emulator-5554`, existing Codex_API35 AVD, Android 15/API35, account `TC256-B`: same Android build111.
- USB iPhone11 `00008030-001A6D2801BB802E`, iOS26.5, account `iphone-11`: release `1.0.0807874437`, bundle260907113535. Prior verified install/provenance is unchanged: `../devices/ios-cleanup-installed-app.json` and `../ios-cleanup-provenance.json`.

## Registration before sends

- Pixel resumed10:13:51.070; wake registration count2, response `ok=true`, `unsupported=false` at10:13:54.275.
- Emulator resumed10:13:51.235; wake registration count2, response `ok=true`, `unsupported=false` at10:13:56.378.
- iPhone initially remained foreground, so an ordinary Preferences→app transition was performed. Push relay registration succeeded10:14:22.063, registration_success10:14:22.183, healthy resume10:14:22.327. Private release FLOW fields do not independently expose the wake-grant contents; relay durability/registration proof is owned by the root deployment audit.

## Android reaction delivery: PASS, expanded wording discrepancy

Emulator backgrounded10:14:45.619 and was never reopened during the delivery observation. Pixel changed its reaction to 😂 on incoming message `Notification-review-260907-stopped-process`, target prefix `b4feae46`. Tap10:15:14.587; sender FLOW start10:15:15.366 and success10:15:27.480, reaction event prefix `060c0649`.

Recipient FCM ingress10:15:15.127, background notification shown with `silent=false`10:15:17.790, followed by silent durable reconciliation10:15:19.951 and OS_POSTED settlement10:15:19.973. Active OS NotificationRecord1968162080 has `android.text=Reacted 😂 to your message` before any receiver reopen. FCM ingress occurs within approximately0.54s of the UI tap; device clocks can differ slightly from sender FLOW timestamps.

The settled screenshot **does not prove reaction wording**: `android-reaction-shade.png` visibly shows older unread `Notification-review-final-build111-text`. Both initial and settled OS payloads have InboxStyle `android.textLines=[Notification-review-final-build111-text]`, despite the reaction `android.text`. This is a reproducible expanded-card wording mismatch, distinct from missing background delivery. Root was notified for source triage. Initial/settled payloads and the screenshot are retained.

## iPhone reaction delivery and catch-up: PASS

Preferences background command10:14:55.503 succeeded. Exactly one Pixel reaction was sent to iPhone: replaced🙏 with😂 on incoming `k`, target prefix `d70a77ad`, reaction event `ce639f2b`. Tap10:16:24.552; sender start10:16:25.349; inbox stored10:16:25.518; sender success10:16:29.141.

NSE received10:16:44.833, staged/decrypted successfully, authorized active handoff10:16:44.865. OS request **A449-34FC** was added10:16:44.935 with shouldPresentAlert1/shouldPlaySound1. Explicit Sound-can-be-played1 and Play-sound records occur10:16:45.699/45.707. The app stayed backgrounded throughout this delivery. Store→NSE delay was approximately19.3s; root owns the exact provider-acceptance correlation.

Controlled reopen10:17:22.263; inbox drain started10:17:24.568; registration_success10:17:25.310; healthy resume10:17:25.452 (`bridgeWasHealthy=true`). No new com.mknoon.app local/remote notification request or notification sound occurred through10:18:08.128, over42s after healthy resume. Unrelated Apple accessory-notification removal logs were excluded from this app assertion.

This one shorter delivery does **not** resolve or erase the earlier117.7s provider→iPhone ingress delay preserved in `../devices/final-installed-build-results.md`. Both cases arrived before receiver reopen. No device clock was changed.

## Evidence and capture closure

- `actions.jsonl`: exact device actions and target markers.
- `pixel-logcat-proof.log`, `emulator-logcat-proof.log`, `iphone11-syslog-proof.log`: bounded event extracts; full raw logs retained alongside them.
- `android-reaction-notifications.txt`, `android-reaction-settled-notifications.txt`, `android-reaction-shade.png`: Android OS record and actual rendered wording.
- `pixel-installed-version.txt`, `emulator-installed-version.txt`: current Android build verification.
- `captures.json`, `capture-shutdown.json`: three owned captures started10:13:26 UTC and stopped by SIGTERM10:18:32.165 UTC. Prior captures and accounts were preserved. Emulator remains available; no account data was cleared.

This is the bounded post-deploy smoke only. Prior full-matrix successes and limitations (accepted iPhone group UI, direct mute UI, generic file UI, earlier ANR with three clean retests) remain in the prior device reports and are not widened by this result.
