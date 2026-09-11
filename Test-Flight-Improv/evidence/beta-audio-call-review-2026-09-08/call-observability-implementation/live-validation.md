# Live validation and limits — 8 September 2026

All times below are UTC. These checks used the USB-connected Pixel 6 and iPhone 11 lab accounts. They did not call external beta testers. Production diagnostics were enabled through Settings on both lab devices; sharing remains off by default for other installations.

## Observed results

| Check | Evidence and result |
| --- | --- |
| Consent and real bridge upload | Both platforms configured sharing and received relay upload acknowledgements. The initial live failure exposed an incorrect bridge envelope, which was corrected and covered by a test through the real `GoBridgeClient` and native method channel. |
| Failed attempt recorded while offline | At 15:24:10, a call tap and `preflight_failed / graph_unavailable` terminal event were durably recorded under diagnostic trace `eec02a59-40f7-44c5-9568-34cf7f191518`. Wi-Fi was disabled; mobile data was already disabled. The failure reason came from the native-disabled lab build, so this is not evidence that networking caused the preflight failure. |
| Automatic retry after reconnect | Wi-Fi was restored at 15:25:04. The relay received the offline attempt at 15:29:53 and the app recorded acknowledgement at 15:29:55, without a restart or manual flush. The bounded exponential retry accounts for the delay. |
| Android → background iPhone media | The call started at 15:33:54, was answered at 15:34:18, and ended around 15:34:45. Both local endpoint reports recorded verified inbound and outbound RTP progress using TURN/UDP. This proves packet progress; no acoustic listening assessment was made. Shared trace: `9e891762-4b44-4e1a-99a1-9419d5ff748d`. |
| Relay quota correction | The successful call exposed a shared relay cap smaller than the two permitted endpoint archives together. The cap and reserved first-media/terminal slots were corrected; permanent rejections now advance the client queue once. After deployment, the relay recovered the callee media and terminal records. At 16:16, the caller's media and terminal records were still queued locally. Do not describe this trace as complete on both endpoints at the relay. |
| Reverse call diagnosis | Some earlier iPhone → Android attempts recorded native presentation but were not answered by the harness. The final 15:59 attempt stayed at the background admission placeholder for all 62 observations and never reached ringing. WorkManager returned success in 853 ms; that alone did not reveal the admission disposition. Exact native admission outcome logging was added to close this gap. |
| Final build diagnostic probe | At 16:49, both phones ran source `f1899f0d63e1724b`. Android recorded `admission / deferred / bridge_unavailable` in 949 ms, followed by `finish / pending` in 981 ms, with native build `1.0.1+111`. The caller recorded `no_answer` after 30 seconds. Its native iOS terminal record used `unknown` for the unavailable native cause rather than falsely claiming a local user action. See [the final probe](final-native-cause-probe.json). |

## Corrections discovered during validation

- Late presentation events could retain a provisional diagnostic ID after the shared trace was resolved. The runtime now persists bounded aliases and canonicalizes later Dart and native events, including after restart.
- The Android lab build initially omitted the native Gradle enable flag. Later artifacts explicitly enable and verify the native gate. This packaging error is not attributed to the original beta releases.
- Local sharing consent originally looked ready before relay acknowledgement. The Settings screen now exposes pending configuration, queue size, last upload, storage health, and discarded-event counts.
- Old relay quota counters counted rejection attempts, including retries. They are now labeled legacy rejection attempts with unknown unique loss; new permanent-discard counts are deduplicated.
- A preflight-only failure was incorrectly included in the post-preflight technical failure denominator. The operator report now separates these categories.

## Limits

The Pixel is on its secure lock screen. The harness does not know or bypass its passcode. Android full-screen call permission is allowed, but the final observed attempt did not reach the ringing stage; that observation does not prove a full-screen permission or activity-display defect.

The successful physical media call predates the final trace-alias and quota changes. Focused regressions and the curated call suite validate those corrections; a completed two-way physical call using the final artifacts is a separate proof leg. The [first native admission probe](native-admission-first-probe.json) recorded a deferred completion in 895 ms, with the database-closed and lease-released flags true. The caller timed out as no-answer after 30 seconds. Its native records remained queued locally, so the operator correctly reported admission evidence as missing. That probe also exposed a diagnostic reason-label correction; the upstream deferral cause was not recorded by that artifact.

The final probe narrows the failure to the single `mknoon/canonical_runtime_lease → acquire` call, including reply decoding. It threw before database opening, P2P initialization, or mailbox retrieval. The instrumentation does not distinguish an unavailable channel, a native error, or an invalid reply. The cleanup flags mean no Dart-owned database or acknowledged lease remained; they do not prove that a native lease was acquired or released if the native request succeeded but its reply failed. The underlying bridge failure is not fixed by this logging change.

At final capture, Android retained 209 unacknowledged diagnostic events and reported zero local drops; iOS had no queued events or local drops. The Android records were available in the protected local archive, but a shared Android trace at the relay was not proven. Uploads still depend on the app's networking runtime becoming available. No live call remained active after the final probe.

Historical calls from older builds cannot acquire missing app/native events retroactively. Unreported endpoints, unuploaded queues, interrupted attempts, and legacy records must remain explicit in incident conclusions.

No TestFlight or Play release was published during this implementation. Beta testers need a build containing this instrumentation and must enable sharing for relay-side endpoint diagnostics.
