# Call observability implementation — 8 September 2026

The app, Android/iOS native call paths, Go bridge, and relay now emit bounded structured diagnostic events. Relay deployment is complete. The [live validation record](live-validation.md) distinguishes observed device results from remaining proof limits. Store distribution is not part of this change.

## What is recorded

- A random diagnostic attempt ID starts at the call tap, including failures before a call session exists. It is independent of contact, device, and protocol call identifiers.
- Events identify caller/callee, source, app build, sequence and timing, stage, fixed outcome and reason, and related request/authority operations.
- The timeline covers endpoint checks, authority publication/withdrawal, signaling/mailbox delivery, push-provider response, native presentation and answer/refusal, audio activation, connection setup, RTP packet progress, terminal intent, and cleanup.
- Android background admission records its exact disposition, timeout or exception category, persistence/custody checks, and final presentation decision. WorkManager completion alone is not interpreted as a presented call.
- Provider acceptance, native ringing, answering, and packet progress are separate facts. An answered call without observed media is visible. Declines and cancellations remain separate from technical failures.
- Restarted unfinished attempts are marked `interrupted_unknown`. Missing endpoint reports, legacy peers, truncation, and dropped telemetry remain explicit; silence is not converted into a successful call.

## App operation

On each participating phone, open **Settings → Call diagnostics → Share call diagnostics**. Sharing is off by default. The screen shows pending setup, readiness, upload queue, last upload, storage problems, and dropped events. **Preview support report** exposes the bounded report and diagnostic trace IDs for support.

Reports persist locally and retry after connectivity returns or the app restarts. Upload acknowledgements prevent duplicates. Diagnostic errors do not change call admission decisions; uploads run separately from call setup. Turning sharing off and clearing reports persists pending server updates so they can finish after an offline period.

Local reports are retained for up to seven days, relay reports for up to fourteen days. Collection and export use a closed schema: no audio, message content, raw contact/device identifiers, protocol handles, tokens, SDP, ICE candidates, or network addresses. Native private binding state is separate and protected; the operator export excludes private authorization maps.

## Relay operation

The deployed relay binary SHA-256 is `d19ec7efeccf0a3624ec07b8312c737895fc2d5b79763328d8df20a89c5f73b3`, with source/build digest `7c70c5616c335ee1a3435730a153946466b73b636a138a1fef3ae78732900865`. The deployment backup is `/var/backups/mknoon-relay/diagnostics-20260908T161909Z`. Matching operator SHA-256: `e9fb9371ec2d8c0dabc25de8484b9ecf0d5c026aa4e3895d287844a46cd636cc`. Signaling and TURN configuration were preserved.

On the relay, use:

```sh
sudo python3 /usr/local/bin/call_diagnostics.py --dir /var/lib/mknoon/call-diagnostics --hours 24
sudo python3 /usr/local/bin/call_diagnostics.py --dir /var/lib/mknoon/call-diagnostics --trace <diagnostic-UUID>
sudo cat /var/lib/mknoon/call-diagnostics-report/latest.json
sudo journalctl -u call-diagnostics-monitor.service --since today
```

`call-diagnostics-monitor.timer` runs every minute and maintains a protected one-hour aggregate report. It records changes to fixed alert categories in the server journal; no external notification service or recipient was configured. The report includes counts and denominators, with a minimum sample requirement before rate alerts. Public metrics contain aggregate outcomes and storage readiness, with no attempt identifiers.

Read the joined timeline before attributing a cause. A failed direct signaling send can recover through successful mailbox storage; push-provider acceptance does not prove native ringing. An early failed event is a navigation hint, not a root-cause verdict. Missing endpoint reports and still-queued native events remain visible as incomplete evidence.

## Validation boundaries

The live check exposed and fixed a real integration bug: the diagnostics runtime initially used the wrong `GoBridgeClient.send` envelope. The regression now goes through the real bridge and native method channel and asserts configure, acknowledged upload, shared-trace resolution, disable, and clear. A strict fake also rejects the original invalid shape.

See the app and native validation records here, plus the Go validation record in the parent directory, for exact commands and counts. Test invocation counts overlap and must not be added together as distinct tests.

The final call regression gate passed **3,544 tests with 4 skips and no failures** on source `f1899f0d63e1724b`; all 58 source inputs matched before and after the run. Focused validation also passed 101 Android tests, 15 Swift host tests, and the Dart admission/schema checks. The deployed admission-schema relay passed its full Go test suite and the operator's nine tests. See [the final gate result](final-curated-result.json) and [the independent cause review](headless-diagnostic-cause-independent-review.md).

Matching Android and iOS builds were installed on the lab devices. The [final device probe](final-native-cause-probe.json) recorded an Android canonical-runtime lease acquisition exception before database/P2P/mailbox setup, with a bounded reason and the installed native build. This is a confirmed diagnostic result, not a fix for the underlying bridge failure. Its Android records remained queued locally; iOS uploaded its no-answer terminal report. Final artifact and installation provenance are in [the installation record](final-mobile-installation.json).

A shared trace is established through authenticated successful mailbox storage. A direct signaling call can succeed while mailbox storage fails; its caller report remains useful, but the callee report can remain separate or partial. This is an explicit diagnostic limitation.

The relay suppresses native push trace sidecars after a successful legacy token registration and requires fresh capability configuration after a relay restart. A binary rollback before any new registration is not observable by the server: acknowledge diagnostic opt-out before installing an older native app.

This instrumentation cannot reconstruct events that older beta builds never recorded. Earlier historical calls retain the uncertainty documented in the original investigation.
