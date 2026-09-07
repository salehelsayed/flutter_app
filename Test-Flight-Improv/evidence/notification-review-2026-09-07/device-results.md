# Final installed builds: device verification

The final source builds are installed on the test devices, with accounts and chat history preserved. No private/wireless phone was controlled. The Android emulator remains running; owned log captures were stopped at **2026-09-07 09:48:54 UTC**.

| Target | Final installed build | Evidence |
| --- | --- | --- |
| USB Pixel 6 `21071FDF600CSC`, Android16/API36 | `com.mknoon.app`, versionCode111, versionName`1.0.0-807874437-notification260907-final` | `android-final-package-pixel.txt` |
| Emulator `emulator-5554`, existing `Codex_API35`, Android15/API35 | Same APK/build111 | `android-final-package-emulator.txt` |
| USB iPhone11 `00008030-001A6D2801BB802E`, iOS26.5 | `com.mknoon.app`, version`1.0.0807874437`, build`260907113535` | `ios-cleanup-installed-app.json` |

APK SHA256: `3f8ec7e119c46a69f5c71fbe0a18b1d89c1c6e430a15e2ba3009e8c5d4e35e21`. Root provenance: `../android-final-provenance.json` and `../ios-cleanup-provenance.json`; both record no pending source changes at build. iPhone uses development APNs signing.

## Android final-build smoke

Both apps were launched after in-place installation. Existing contacts/groups remained visible; emulator identity prefix`12D3KooWSxW3` matches the earlier installed build. Both reported send/inbox readiness. Recipient emulator then stayed backgrounded for the sends below.

- Text `Notification-review-final-build111-text`: physical Android send09:37:41 UTC; emulator FCM receiver09:37:44.676; durable OS_POSTED09:37:49.370. Active OS record1968162080 shows title`picel` and exact text.
- New❤️ reaction on the emulator's earlier stopped-process test message: send09:38:22.504; FCM receiver09:38:22.887; durable OS_POSTED09:38:29.168. Active record shows `Reacted ❤️ to your message` before recipient reopen.

Evidence: `android-final-smoke-proof.log`, `android-final-smoke-text-settled-notifications.txt`, `android-final-smoke-reaction-settled-notifications.txt`, and exact `actions.jsonl`.

## iPhone final-build reaction and replay check

Final build launched09:41:50.881 UTC; bridge startup and push registration succeeded, with registration_success09:41:56.199. Existing peer keys authorized/decrypted the subsequent reaction, supporting preserved identity state.

| Event | UTC timestamp |
| --- | --- |
| Background into Preferences | 09:42:40.411 |
| Android tap replacing❤️ with🙏 on iPhone's `k` message | 09:42:53.639 |
| Sender REACTION_SEND_START, target prefix`d70a77ad` | 09:42:54.364 |
| Protected inbox store success | 09:42:54.541 |
| Sender success, reaction prefix`d2033819` | 09:42:57.524 |
| Relay push provider success, attempt1 | 09:42:54 (relay timestamp resolution) |
| iPhone receives remote`0AFB-A3E7` while still backgrounded | 09:44:51.690 |
| NSE decrypts/authorizes and hands off active content | 09:44:51.862 |
| OS active notification, sound enabled | 09:44:51.917 |
| Explicit OS sound playback | 09:44:52.827 |
| OS banner appears | 09:44:54.279 |
| Controlled app reopen | 09:47:25.004 |
| Inbox drain begins | 09:47:25.899 |
| Healthy resume completes | 09:47:26.779 |
| Independent no-duplicate observation endpoint | 09:48:25.938 |

**Presentation and replay suppression pass:** the reaction appeared and sounded before reopening. After a healthy resume, no second local/remote/OS notification request or alert callback appeared for over59 seconds. The earlier installed build had reproduced a second audible local reaction alert roughly two seconds after reopening.

**Delivery latency remains a finding:** the final reaction took about117.7 seconds from provider acceptance to iPhone ingress. Relay custody/push acceptance matched the test iPhone and Pixel peer prefixes, and the unauthorized-reaction counter remained3, unchanged from the earlier baseline. No additional test send or recipient reopen occurred during that delay. This observation does not establish an app-side cause or prove immediate push delivery.

Evidence: `ios-cleanup-final-proof.log`, full `iphone11-retention-final-syslog.log`, `ios-cleanup-reaction-sender-window.log`, root relay correlation files, and independent reviewer extracts `ios-final-cleanup-reaction-wait-113535-events.log` / `ios-final-cleanup-reopen-113535-events.log`.

## Earlier focused device coverage and limits

- `results.md`: original Android physical/emulator direct text, reaction, voice, photo; group text/reaction/voice/photo; visible-chat suppression, group mute suppression, notification tap routing, and process-stopped delivery. The original and updated builds were distinguished. It also records the initial iPhone direct text/reaction/voice/photo/video OS proofs.
- `final-targeted-results.md` and `retention-targeted-results.md`: iPhone background direct reaction, text and voice control coverage, rejected-group neutral/passive fallback, and repeated no-duplicate reopen checks. Accepted iPhone group membership was not safely controllable; that separate live parity leg was not claimed.
- `android-additional-results.md`: direct/group video OS notifications and three successful group-video→foreground repetitions following one preserved renderer ANR. No ANR recurred during those three repetitions; the original trace does not establish a root cause.
- Generic document/file notification sending and direct chat mute were not reachable through the tested composer/overflow/identity UI. No pass was invented for these navigation limits. Group mute was tested and restored.
- The13-hour boundary was verified through controlled-clock host tests, with no phone clock changes.

Capture ownership/endpoints are recorded in `capture-shutdown.json`. All raw logs and evidence are retained locally. No iOS test harness was rebuilt; unavailable WDA/screenshot services were handled with bounded attempts and devicectl/syslog controls.
