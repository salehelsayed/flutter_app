# Move Account Aborted With TimeoutException "Before Final Handoff" — Root-Cause Triage

**Date:** 2026-06-10
**Scenario:** Move Account from Pixel (Android, old phone / SENDER) → iPhone 13 (iOS, new phone / RECEIVER)
**Symptom (as reported):** The account move stopped unexpectedly before final handoff.
**Logs analysed:** `./pixel.log` (sender), `./iphone-13.log` (receiver) — run Jun 10 2026, 07:22–07:23 UTC.
**Method:** 13-agent triage workflow — 6 dimensions traced against working-tree source, each adversarially verified, then synthesized. Report only — **no code was changed.**

> **One line:** The bundle built fine (34 segments, all media present); the move died **during the encrypted database/segment upload** — the first large segment HTTP POST stalled, a 10s `.timeout()` guard threw an **uncaught `TimeoutException`**, which escaped to the UI catch and was **mislabeled `bundleSourceFailed`**. The transport emits **zero telemetry**, so exactly *why* the segment upload stalled cannot be pinned from these logs.

---

## Executive Summary

The account move failed because the SENDER's (Pixel/Android) segment-upload HTTP POST stalled and never completed, tripping a 10s `.timeout()` guard inside `_postJson` and throwing an uncaught `TimeoutException`. This is PROVEN: the sender advanced cleanly through `preparing → connecting → encrypting → transferringDatabase` (07:23:04.619Z) — which is only reachable after the transcript and manifest POSTs both returned HTTP 2xx — then went completely silent on the migration transport for 38.855s before throwing at 07:23:43.474Z. The bundle itself built fine (`BUNDLE_SOURCE_BUILT segmentCount:34, totalBytes:8717746`, media all present, `missingRequiredMediaCount:0`), so the failure is unambiguously in the segment/database transfer phase, NOT bundle assembly. The most probable underlying cause is a large-body upload stall on the first ~349KB base64-ciphertext segment POST over a cold Android `dart:io` `HttpClient` (no connection reuse across 34 segments) — but whether the body stalled on the sender's write/flush or was received-and-hung in the receiver's un-instrumented `_handleSegment` cannot be disambiguated from logs (this remains a HYPOTHESIS). Three CERTAIN diagnosability defects compound the failure: the transport timeout is mislabeled `reason:"bundleSourceFailed"` by a string-match classifier even though the bundle source already succeeded; the entire transport path emits zero FLOW telemetry (the 38.855s blackout); and the user sees only a generic "stopped unexpectedly before final handoff" message. The libp2p `netlinkrib: permission denied` noise and the 07:23:37 relay peer flap are RULED OUT as causes — they are environmental Android Go-libp2p noise on a transport disjoint from the Dart LAN HTTP path.

## What The Logs Prove

All timestamps UTC. Sender = `pixel.log` (Pixel/Android, OLD phone). Receiver = `iphone-13.log` (iPhone 13/iOS, NEW phone). `[DIRECT]` = literally in the logs; `[INFERRED]` = via control-flow gating.

### Sender (pixel.log) — cross-cited timeline

- `pixel.log:6928` @07:22:48.553 — `LOCAL_MDNS_PEER_FOUND host 192.168.0.9 port 53954`. `[DIRECT]` The migration receiver was discovered at the correct IP:port (matches the iPhone's advertised `53954`). The host string is a numeric IP literal, not a `.local.` name (verified: pixel.log contains zero `.local.` strings; Android `bonsoir` yields `InetAddress.getHostAddress()`).
- `pixel.log:6959` @07:22:56.152 — `TRANSFER_START`; `:6960/:6961` @07:22:56.155/.156 — `STAGE preparing` then `STAGE connecting`. `[DIRECT]`
- `pixel.log:6964/6965` @07:22:56.876 — `STAGE encrypting` + `BUNDLE_SOURCE_START`. `[INFERRED]` This stage is gated in `runOldPhoneTransfer` behind the transcript `_postJson` (`runtime:287`) passing the `_isOk` check (`runtime:293`). Reaching it proves `resolvePeer` + the small transcript POST both succeeded within ~0.72s.
- `pixel.log:6967` @07:22:57.118 — `ROWS_LOADED`; `:6972` @07:22:58.817 — `RELAY_FREE_MEDIA_AUDIT {fileEntryCount:10, missingRequiredMediaCount:0, relayDependencyRisk:false}`. `[DIRECT]` Media all present; this is not the prior group-media bug.
- `pixel.log:6982` @07:23:00.287 — `SNAPSHOT_EXPORTED`; `:7126` @07:23:04.367 — `BUNDLE_SOURCE_BUILT {segmentCount:34, totalBytes:8717746}`. `[DIRECT]` Bundle built fine; ~256KiB plaintext/segment.
- `pixel.log:7127` @07:23:04.619 — `STAGE transferringDatabase`. `[INFERRED]` This stage (`runtime:358`) is gated behind the manifest `_postJson` (`runtime:338`) passing `_isOk` (`runtime:351`). Reaching it proves the small manifest POST also succeeded. There is NO explicit "transcript ok" / "manifest ok" log line — both successes are inferred from this code-level stage gating, which is airtight.
- `pixel.log:7128–7287` @07:23:04.619 → 07:23:43.474 — `[DIRECT]` 38.855s of total migration-transport SILENCE. The window contains ONLY background `group:discovery`, `P2P_HEALTH_CHECK`, `BRIDGE_CALL_TIMING`, `mDNS PEER_FOUND` re-resolve noise, and the peer flap. ZERO `_postJson` / segment / HTTP / connect FLOW events.
- `pixel.log:7276/7279` @07:23:37.237/.616 — `P2P_PUSH_EVENT peer:disconnected` then `peer:connected`. `[DIRECT]` A libp2p relay-circuit peer flap (the events carry no peerId in their details; attributing it specifically to a particular peer is NOT proven — three distinct relay peers appear in disconnect/connect events).
- `pixel.log:7288` @07:23:43.474 — `ACCOUNT_MIGRATION_TRANSFER_ERROR {errorType:"TimeoutException", reason:"bundleSourceFailed"}`. `[DIRECT]` Delta from `transferringDatabase` = 38.855s exactly (07:23:04.619198 → 07:23:43.474642).
- Throughout: 84× `E/GoLog ... basic/basic_host.go:396 "failed to resolve local interface addresses {netlinkrib: permission denied}"` on a fixed ~5s cadence (first at `pixel.log:501` @07:17:13.880, i.e. 5+ min before the move; seven inside the stall window at :08/:13/:18/:23/:28/:33/:38). `[DIRECT]` iPhone has zero such errors.

### Receiver (iphone-13.log) — cross-cited timeline

- `iphone-13.log:761` @07:22:43.682 — `LOCAL_WS_SERVER_STARTED {port:53954}`; `:764` @07:22:47.442 — `LOCAL_RECEIVER_STARTED {sessionId:7e907b7a..., port:53954}`; `:765` — `NEW_PHONE_QR_READY`. `[DIRECT]` Session ID matches the sender's.
- 07:22:47–07:23:48 — `[DIRECT]` Only `LOCAL_MDNS_PEER_FOUND` migration-related lines. NO transcript/manifest/segment/complete receiver-command telemetry, NO `RECEIVER_REQUEST_FAILED`, NO `segment_rejected`. The receiver WAS otherwise busy (24× `MLKEM_FL_BRIDGE_DECRYPT`, `GO_BRIDGE_SEND`, 4× `PUSH_REGISTER_TOKEN_FAILED`), with its last decrypt at 07:23:42.738 — ~0.74s before the sender error. `[DIRECT]` The Dart event loop was alive and not frozen throughout the window.
- `iphone-13.log:971` @07:23:49.358 — `LOCAL_RECEIVER_STOPPED`, 5.88s after the sender error (teardown). `[DIRECT]`

`[INFERRED, well-supported]` Because the transcript + manifest POSTs must have returned HTTP 2xx for the sender to reach `transferringDatabase`, the receiver DID execute `_handleTranscript` and `_handleManifest` and wrote responses — so the receiver received and answered the small JSON commands. The failure is therefore localized to the segment phase. The receiver handlers emit NO happy-path telemetry, so the receiver's silence on segments is fully explained by missing instrumentation and does NOT prove segments never arrived.

`[INFERRED, decisive localization]` The migration stage `checking` (`runtime:382`, emitted immediately before the `complete` POST) was NEVER logged (grep count 0). Combined with `BUNDLE_SOURCE_FAILED` count 0 and `TRANSFER_FAILED` count 0 (vs `TRANSFER_ERROR` count 1), this pins the throw strictly between `transferringDatabase` (`runtime:358`) and `checking` (`runtime:382`) — i.e. inside `_sendPreparedBundleSegments` — and rules out the `complete` POST and cutover as the hang site. The presence of `TRANSFER_ERROR` (catch path) rather than `TRANSFER_FAILED` (graceful `result.failure` path) is hard proof an exception was THROWN, not returned.

## Root Causes (Ranked)

### (i) Proximate failure

**1. Uncaught `TimeoutException` from a stalled segment-phase `_postJson`, never converted to a graceful failure**
- **Severity:** Critical
- **Category:** Primary cause
- **Mechanism:** After `transferringDatabase`, the runtime takes the prepared-segment path `_sendPreparedBundleSegments` (`account_migration_local_transfer_runtime.dart:366`, selected because `encryptedSegments != null`). That method (`runtime:525-562`) loops `manifest.orderedSegments` and calls `_postJson` (`runtime:553`) for segment index 0 first. `_postJson` (`runtime:807-840`) has NO retry: it does `httpClient.post(...).timeout(httpTimeout)` (818), then synchronous `request.write(jsonEncode(body))` (820, buffers the full ~349KB base64 body — NOT `addStream`), then `await request.close().timeout(httpTimeout)` (821, where the buffered body is actually pushed and response headers awaited), then drains the response with `.timeout(httpTimeout)` (825). `httpTimeout` = 10s (`runtime:118`). The segment POST hangs; one `.timeout()` guard throws `TimeoutException`. Neither `_postJson`, nor the `for`-loop in `_sendPreparedBundleSegments`, nor the `transferringDatabase` block in `runOldPhoneTransfer` (`runtime:358-380`, which only handles `!transferResult.isSuccess` and assumes the send RETURNS) wraps this in try/catch — in contrast, the bundle-SOURCE build IS wrapped (`runtime:317-333`). The throw escapes the runner (wired directly at `main.dart:2392`, no wrapper) to the only catch, `account_migration_journey_wired.dart:481-499`.
- **Evidence:** `pixel.log:7288` (the throw); `pixel.log:7127→7288` (38.855s silence); code as cited.
- **Confidence:** PROVEN. Every verifier confirmed this exactly; high confidence, no dissent.

**On the ~38.85s arithmetic (CORRECTED — do NOT believe any "stacked / 4× timeout" framing):** There are ZERO retries anywhere in the path (grep confirmed: only the segment-index for-loops at `runtime:536/538`; no `while`/`retry`/`attempt`/`onTimeout`). Dart's `.timeout()` on three SEQUENTIAL awaits does NOT sum: if `request.close()` (821) hangs, its 10s timer throws and aborts the function — lines 822-825 never run, so their timers never arm. A single un-retried `_postJson` therefore times out at ~10s on whichever await blocks. **Conclusion the evidence actually supports:** the 38.855s is NOT cleanly explained by the timeout structure of one POST. The most defensible reading is that several earlier segments POSTed successfully (each consuming wall time) before one segment's POST hung for ~one 10s window, OR a single long stall — but the exact decomposition is unrecoverable because the transport emits zero telemetry. State this as unresolved, not as "stacked timeouts." (An attempt to attribute the residual time to in-window ML-KEM encryption was specifically falsified: all 34 encryptions completed in the prior `encrypting → BUNDLE_SOURCE_BUILT` window, 07:22:56.876 → 07:23:04.367 = 7.49s; the 38.855s window is encryption-free.)

### (ii) Most probable underlying cause (why small POSTs succeeded but the segment upload stalled) — HYPOTHESIS, ranked

The small transcript/manifest bodies are <1KB single-shot JSON; the first segment body is ~349KB (256KiB plaintext × ~1.33 base64). The asymmetry is body-size/streaming-driven, NOT a routing difference (same `_postJson`, same host:port). Leading hypotheses, ranked:

- **H1 — Large-body upload stall on a cold Android `HttpClient` (sender-side write/flush backpressure).** Every `_postJson` builds a fresh `HttpClient` and force-closes it in `finally` (`runtime:813/837-838`), so segment[0] is a cold connect + large synchronous-buffered write with zero keep-alive reuse across 34 segments. The full body is buffered by `request.write` (820, NOT timeout-wrapped) and pushed during `request.close()` (821). A large first write that backpressures would hang at `close()`'s 10s guard. *Confirming evidence:* per-segment sender telemetry (byte counts, which `.timeout` fired) on a re-run, or a packet capture showing bytes leaving the sender but the upload not completing.
- **H2 — Receiver `_handleSegment` reads the full body before responding, so a slow drain/decrypt/disk-write hangs the response.** `_handleSegment` (`runtime:649-686`) awaits `_readJsonMap` → `utf8.decoder.bind(request).join()` (`runtime:902`, also NOT timeout-wrapped) to fully drain the body, THEN awaits `receiver.acceptSegment` (which does `crypto.decryptSegment` over the Go bridge at `account_migration_bundle_transfer.dart:999` and a flushed `writeAsBytes(..., flush:true)` disk write at 1015-1017), and only then `_writeJson` the 200. Any of these on the critical path delays the response, tripping the sender's `close()`/read timeout. *Compounding hazard:* `local_ws_server.dart:120` invokes the migration handler fire-and-forget (not awaited) with no per-request server-side timeout, so a never-completing handler leaves the connection open indefinitely. *Confirming evidence:* receiver-side `_handleSegment` entry/decrypt/write telemetry on a re-run showing the request arrived and where it blocked. *Weak prior against H2:* the receiver event loop stayed alive (decrypts continued to 07:23:42.738), which slightly favors a sender/transport stall (H1) over a receiver compute-freeze — but this is not conclusive.
- **H3 — Environmental WiFi / interface instability mid-upload.** An IP captured at resolve-time could go unroutable if the Android active interface flapped during the window. *Against:* small POSTs succeeded at connect time and mDNS kept re-resolving 192.168.0.9 throughout the stall (07:23:02/:22/:42). Weakest hypothesis; needs a re-run with packet capture and WiFi RSSI/roaming logs to assess.

These cannot be ranked decisively against one another from the current logs — both `_postJson` and `_handleSegment` are un-instrumented, and the 38.855s is a total blackout.

### (iii) Certain diagnosability defects — all PROVEN

**2. Transport `TimeoutException` is MISLABELED `reason:"bundleSourceFailed"`**
- **Severity:** High · **Category:** Diagnosability defect
- **Mechanism:** The wired catch (`account_migration_journey_wired.dart:492`) passes the raw error to `accountMigrationBundleSourceFailureReason(error)`. That classifier (`account_migration_transfer_flow.dart:83-106`) lowercases the message and string-matches 5 branches (missing-secure-value, file-manifest, file-changed, database/sqlcipher/integrity, encrypt/segmentcrypto). A `TimeoutException` message ("TimeoutException after 0:00:10.000000: Future not completed") matches none, so it falls through to the DEFAULT `return 'bundleSourceFailed';` (line 105). This is provably wrong: `BUNDLE_SOURCE_BUILT {segmentCount:34}` already succeeded and there is NO `BUNDLE_SOURCE_FAILED` event. It steers an on-call reader toward debugging snapshot/SQLCipher/encryption assembly — the one subsystem the logs prove worked.
- **Evidence:** `transfer_flow.dart:105`; `pixel.log:7288 {reason:"bundleSourceFailed"}`. **Confidence:** PROVEN.

**3. Zero transport telemetry — the 38.855s blackout**
- **Severity:** High · **Category:** Diagnosability defect
- **Mechanism:** Of the runtime's `emitFlowEvent` calls, none are inside `_postJson` (`runtime:807-840`) or `_sendPreparedBundleSegments` (`runtime:525-562`) — no segment index, command, host:port, byte count, attempt, or which `.timeout` fired. Symmetrically the receiver handlers (`_handleTranscript:566`, `_handleManifest:603`, `_handleSegment:649`, `_handleComplete:688`) and `acceptSegment` (`bundle_transfer.dart:980-1020`) emit nothing on the happy path — only `RECEIVER_REQUEST_FAILED` (`runtime:246`) on a thrown exception. This is the direct cause of the 38.855s of dead air on the sender and the receiver-side silence, and it is precisely what makes H1 vs H2 undecidable.
- **Evidence:** code as cited; `pixel.log:7128-7287` empty; `iphone-13.log` no command telemetry. **Confidence:** PROVEN.

**4. Generic error identity and user message**
- **Severity:** Medium · **Category:** Diagnosability defect
- **Mechanism:** `accountMigrationTransferErrorType` (`transfer_flow.dart:78-81`) returns only `error.runtimeType.toString()` → `"TimeoutException"`, with no phase/operation/segment context. The wired catch hardcodes `_progressErrorText = 'The account move stopped unexpectedly before final handoff.'` (`journey_wired.dart:497-498`) regardless of cause. Combined with defect 2 (overwriting the one structured `reason` field with a false value) and defect 3 (no in-flight evidence), the failure is undiagnosable from logs alone.
- **Evidence:** code as cited. **Confidence:** PROVEN.

### (iv) Ruled-out / environmental

**5. libp2p `netlinkrib: permission denied` + 07:23:37 relay peer flap — NOISE, not cause**
- **Severity:** Low · **Category:** Environmental (ruled out)
- **Mechanism:** The move transport is pure Dart `dart:io` `HttpClient` over LAN to a numeric IP:port resolved via Dart `bonsoir` mDNS (`local_ws_server.dart:96` receiver = `HttpServer.bind(InternetAddress.anyIPv4, 0)`; `_postJson:816-818` raw `HttpClient().post(peer.host, peer.port, ...)`). The `netlinkrib` error originates in vendored Go-libp2p `basichost` (`basic_host.go:396`), the known Android `wlynxg/anet` interface-enumeration issue (`go-mknoon/Makefile` `-checklinkname=0`, `go.mod` anet v0.0.5) — a separate process subsystem. Three independent facts prove non-causation: (a) the error is a constant ~5s background condition firing 5+ min before the move and continuing after, anti-correlated with the stall; (b) Dart mDNS kept resolving 192.168.0.9 throughout the stall, so multicast/LAN reachability was unimpaired; (c) the flapped peer(s) are group/relay-circuit peers, never the migration receiver (GoLog references neither `53954` nor `migration`). Plainly: **noise, not cause.** It does confirm Android interface enumeration is degraded for the Go stack, which is at most a weak indirect signal worth a separate ticket (it affects only relay/gossipsub group delivery).
- **Confidence:** PROVEN ruled-out (high; minor citation note: the cited "first occurrence pixel.log:5787" conflated the PID with a line number — the actual first line is 501; the peer-flap peer-identity attribution is unproven).

## Why This Is Hard To Diagnose

Two classes of gaps make this failure opaque:

- **Instrumentation gap (defect 3):** The entire transport layer — both the sender's `_postJson`/`_sendPreparedBundleSegments` and the receiver's `_handleSegment`/`acceptSegment` — emits zero FLOW telemetry. The 38.855s between `transferringDatabase` and the error is a complete blackout: no per-segment start/end, no byte counts, no which-await-fired, no receiver-arrival signal. This single gap is why H1 (sender write stall) and H2 (receiver handler hang) cannot be separated; both produce identical sender-silence + receiver-silence. The body-drain (`runtime:902`) and synchronous `request.write` (`runtime:820`) are not even timeout-wrapped, so some hang modes are unbounded by `httpTimeout` entirely.
- **Classification gap (defects 2 + 4):** The one structured field that survives to the log (`reason`) is actively overwritten with an affirmatively-wrong value (`bundleSourceFailed`) by a classifier designed for bundle-SOURCE errors but reused for transport exceptions. The error identity is flattened to a bare runtime type, and the user message is a single hardcoded sentence. Together these don't just fail to help — they point triage at the wrong subsystem (snapshot/SQLCipher/encryption), the exact area the logs prove already succeeded.

## What We Cannot Yet Conclude

- **Whether segment[0] reached the receiver.** The receiver's silence is un-instrumented, NOT proof that no segment arrived. We cannot distinguish "POST never completed on the wire (sender stall)" from "POST arrived and `_handleSegment`/`acceptSegment` hung" from these logs. This requires a re-run with sender + receiver transport telemetry or a packet/HTTP-access-log capture.
- **Which `.timeout()` guard fired** (connect 818 / close 821 / read 825), and therefore whether the body even started uploading. Most plausibly `close()` (821), but unconfirmed.
- **The exact composition of the 38.855s.** It is NOT explained by the timeout structure of one POST (a single un-retried `_postJson` caps at ~10s on the blocking await, and there are zero retries). It implies multiple sequential POSTs (some succeeding) or one long stall; the split is unrecoverable without per-segment timing logs.
- **Whether environmental WiFi/interface instability contributed (H3).** Connect-time reachability was fine (small POSTs succeeded, mDNS kept resolving), but sustained large-body throughput under degraded Go-layer interface enumeration was not measured. Unproven; needs a controlled repro with WiFi/roaming capture.

## Recommended Next Steps

(All RECOMMENDATIONS — none applied; this is a report-only analysis.)

Diagnostic, in order:
1. **Instrument the transport on both sides first.** Add `emitFlowEvent` at: `_postJson` request-start (command, segment index, byte count) and at each outcome (status code, which `.timeout` fired, elapsed); each iteration of `_sendPreparedBundleSegments`; and the receiver's `handleMigrationTransferRequest` entry + `_handleSegment`/`acceptSegment` (received / decrypted / written, with index). This single change eliminates the 38s blackout and disambiguates H1 vs H2 on the very next run.
2. **Re-run the Pixel→iPhone13 move with that telemetry plus a packet capture** (e.g. `tcpdump`/Wireshark on both ends, or an HTTP access log on the Dart `HttpServer`) to observe whether segment[0] bytes leave the sender and whether they arrive at the receiver, and exactly where the wall time goes.
3. **Confirm the segment-stall hypothesis by reading:** `_handleSegment` (`runtime:649-686`) and `acceptSegment` (`bundle_transfer.dart:980-1020`) for read-then-respond ordering and the Go-bridge `decryptSegment` cost; `local_ws_server.dart:109-122` for the fire-and-forget, no-timeout, no-concurrency-cap handler dispatch; and the Android `dart:io` `HttpClient` large-body write/keep-alive behavior (the cold-client-per-segment pattern at `runtime:813/837-838`).
4. **Capture WiFi/roaming + interface state** during the re-run to assess H3.

## Recommended Fixes

(RECOMMENDATIONS only — clearly separated by concern; none applied.)

Transport timeout / retry / ergonomics:
- Wrap the segment-send phase (or `_postJson` itself) in try/catch so `TimeoutException`/`SocketException` becomes a graceful `AccountMigrationTransferResult.failure(transferTimedOut)` with a transport-specific message, instead of escaping uncaught to the wired catch.
- Replace the three independent 10s `.timeout()` windows with one bounded overall deadline per POST (and timeout-wrap `request.write` at 820 and the receiver's body-drain at 902, which are currently unbounded).
- Reuse a single keep-alive `HttpClient`/connection across the 34 segments instead of a cold connect + force-close per segment; consider streaming the body with explicit content-length / bounded backpressure.
- Add bounded retry with backoff for segment POSTs.
- On the receiver, await/track the migration handler future in `local_ws_server.dart` and add a per-request server-side timeout so a stalled handler cannot hold the connection open.

Error classification / telemetry (separate from transport):
- Stop routing transport exceptions through `accountMigrationBundleSourceFailureReason`; add a distinct `transferTimeout`/transport reason and remove the catch-all `bundleSourceFailed` default (return `unknown` for truly unclassified errors) so a transport timeout is never mislabeled after `BUNDLE_SOURCE_BUILT` succeeded.
- Enrich `accountMigrationTransferErrorType` to carry the failing phase/operation/segment.
- Branch the user message on failure code (timeout vs assembly vs receiver-rejected) instead of the single hardcoded "stopped unexpectedly" sentence.

Environmental (separate ticket, not blocking):
- Downgrade/suppress the benign `basichost` `netlinkrib` ERROR on Android (or upgrade/patch `wlynxg/anet`) so it stops polluting incident triage; it affects only the relay/gossipsub group path, not the move.

## Confidence (per root cause)

- **RC1 — Proximate: uncaught transport `TimeoutException` in segment-phase `_postJson` after transcript+manifest succeeded:** PROVEN, high. All findings + verdicts concur on the causal chain, file:line, and log:line. The only downgraded sub-claim is the 38.855s arithmetic, explicitly corrected to "single ~10s window per hung POST; total NOT explained by the timeout structure; exact composition unrecoverable."
- **RC2-H1 — sender large-body write stall:** HYPOTHESIS, moderate (leading). Best-supported by the cold-client/no-keep-alive structure and the live receiver event loop, but unconfirmed without telemetry.
- **RC2-H2 — receiver `_handleSegment` read-then-respond / decrypt / disk-write hang:** HYPOTHESIS, moderate. Structurally plausible (read-full-body-before-respond + fire-and-forget no-timeout dispatch), not ruled in or out by logs.
- **RC2-H3 — environmental WiFi/interface:** HYPOTHESIS, low. Connect-time reachability was demonstrably fine; weakest.
- **RC2 (mislabel `bundleSourceFailed`):** PROVEN, high. Verified in source (default fallback `transfer_flow.dart:105`) and in `pixel.log:7288`.
- **RC3 (zero transport telemetry):** PROVEN, high. Confirmed absent on both sender and receiver paths.
- **RC4 (generic errorType + message):** PROVEN, high.
- **RC5 (libp2p netlink/peer-flap ruled out as cause):** PROVEN ruled-out, high (three independent anti-correlation facts).

---

### Appendix — Key identifiers for reproduction

- **Session id:** `7e907b7a-336e-4467-93af-08b7786ff24f`
- **Receiver endpoint:** `192.168.0.9:53954` (iPhone Dart WS server, mDNS `_mknoon._tcp`)
- **Bundle:** `segmentCount:34`, `totalBytes:8717746` (~256 KiB plaintext/segment → ~349 KB base64 JSON body/segment); media `fileEntryCount:10`, `missingRequiredMediaCount:0`, `relayDependencyRisk:false`.
- **Failure:** `transferringDatabase` @07:23:04.619 → `TRANSFER_ERROR {TimeoutException / bundleSourceFailed}` @07:23:43.474 (Δ 38.855s of transport silence).
- **httpTimeout:** 10s; **peerResolveTimeout:** 12s (`account_migration_local_transfer_runtime.dart:117-118`).

*Generated by the `move-transfer-timeout-triage` workflow (13 agents: 6 trace dimensions, 6 adversarial verifiers, 1 synthesis). Report only — no code changes made.*
