export const meta = {
  name: 'move-transfer-timeout-triage',
  description: 'Triage why Move Account aborted with TimeoutException before final handoff (Pixel->iPhone13, Jun 10)',
  phases: [
    { title: 'Trace', detail: 'Trace each failure dimension against real source + logs' },
    { title: 'Verify', detail: 'Adversarially verify each finding against code/logs' },
    { title: 'Synthesize', detail: 'Reconcile into ranked root causes (report only)' },
  ],
}

const EVIDENCE = `
ESTABLISHED FACTS (cwd = flutter_app; logs ./pixel.log [old phone, Android, SENDER] and ./iphone-13.log [new phone, iOS, RECEIVER], run Jun 10 2026 07:22-07:23 UTC). The move FAILED; user saw "The account move stopped unexpectedly before final handoff." This task is REPORT ONLY — do NOT modify code.

USER-FACING FAILURE:
- account_migration_journey_wired.dart:481-499 catch block sets _progressErrorText = 'The account move stopped unexpectedly before final handoff.' and emits ACCOUNT_MIGRATION_TRANSFER_ERROR.
- pixel.log:7288 ACCOUNT_MIGRATION_TRANSFER_ERROR details {"errorType":"TimeoutException","reason":"bundleSourceFailed"} at 07:23:43.474Z. So an exception (TimeoutException) was THROWN out of the transfer runner (not a graceful result.failure).

PIXEL (SENDER) TIMELINE (all confirmed in pixel.log):
- 07:22:49.612 ACCOUNT_MIGRATION_OLD_PHONE_SCAN_START (scans the new phone's QR)
- 07:22:53.855 OLD_PHONE_QR_AUTHORIZE_START ; 07:22:54.002 OLD_PHONE_CONFIRMATION_READY
- 07:22:56.152 ACCOUNT_MIGRATION_TRANSFER_START
- 07:22:56.155 STAGE preparing ; 07:22:56.156 STAGE connecting  (resolvePeer + transcript POST happen here)
- 07:22:56.876 STAGE encrypting => ACCOUNT_MIGRATION_BUNDLE_SOURCE_START (so resolvePeer + the transcript POST at runtime line ~287 BOTH succeeded inside ~0.72s => receiver was reachable for small JSON)
- 07:22:57.118 ROWS_LOADED ; 07:22:58.817 RELAY_FREE_MEDIA_AUDIT {fileEntryCount:10, sourceTransport:"move_bundle_direct_wifi", relayDependencyRisk:false, missingRequiredMediaCount:0}  (media all present this run — NOT the prior group-media bug)
- 07:23:00.287 SNAPSHOT_EXPORTED ; 07:23:04.367 BUNDLE_SOURCE_BUILT {segmentCount:34}
- 07:23:04.619 STAGE transferringDatabase  (runtime line 358 — reached ONLY AFTER the manifest POST at runtime line 338 returned OK, i.e. manifest also succeeded)
- 07:23:04.6 .. 07:23:43.4 = ~38.85 s of SILENCE on the migration transport: NO _postJson / segment / HTTP / connect FLOW events at all. Only background group-sync, health checks, mDNS PEER_FOUND noise.
- 07:23:43.474 ACCOUNT_MIGRATION_TRANSFER_ERROR (TimeoutException / bundleSourceFailed).
- THROUGHOUT: GoLog every ~5s: ERROR basichost basic/basic_host.go:396 "failed to resolve local interface addresses" {"error":"route ip+net: netlinkrib: permission denied"} (libp2p, Android). At 07:23:37 a libp2p relay peer flap: P2P_PUSH_EVENT peer:disconnected then peer:connected (12D3KooWEqHd...).

IPHONE (RECEIVER) TIMELINE (all confirmed in iphone-13.log):
- 07:22:42.339 NEW_PHONE_QR_LOAD_START
- 07:22:43.682 LOCAL_WS_SERVER_STARTED {port:53954}
- 07:22:47.428 LOCAL_MDNS_ADVERTISE_START {port:53954} ; 07:22:47.441 LOCAL_MDNS_DISCOVERY_START
- 07:22:47.442 ACCOUNT_MIGRATION_LOCAL_RECEIVER_STARTED {sessionId:7e907b7a..., migrationPeerId, port:53954}
- 07:22:47.444 NEW_PHONE_QR_READY
- 07:22:47.8.. mDNS LOCAL_MDNS_PEER_FOUND repeatedly: hosts "J3L23D1Q5D.local." (ports 61013/61241) and "Android_89F036PP.local." (the Pixel). The receiver advertises/discovers via mDNS _mknoon._tcp.
- BETWEEN 07:22:47 and 07:23:49 the iPhone logs NO account-migration receiver-side command events (no manifest/transcript/segment/complete telemetry) — only mDNS PEER_FOUND. (NOTE: the receiver HTTP handlers appear UN-instrumented, so this silence does NOT by itself prove nothing arrived.)
- 07:23:49.358 ACCOUNT_MIGRATION_LOCAL_RECEIVER_STOPPED (6s after the sender's error).

KEY CODE (lib/features/account_migration/application/):
- account_migration_local_transfer_runtime.dart — the local transfer runtime (SENDER + RECEIVER). httpTimeout = const Duration(seconds: 10) (line 118); peerResolveTimeout = const Duration(seconds: 12) (line 117). Sender flow _run(): onProgress(connecting) -> discovery.resolvePeer(...) (line 272) -> transcript _postJson (287) -> manifest _postJson (338) -> onProgress(transferringDatabase) (358) -> _sendPreparedBundleSegments(...) (366) / _exportPlaintextBundleSegments (360) -> complete _postJson (383) -> cutover. _sendPreparedBundleSegments at 525-560 loops segments calling _postJson (553). _postJson at 807-830 builds an HttpClient request and does request.addStream(...).timeout(httpTimeout) / request.close().timeout(httpTimeout) (lines 818-825). NONE of _postJson / _sendPreparedBundleSegments emit emitFlowEvent (transport is un-instrumented).
- account_migration_transfer_flow.dart:83-106 accountMigrationBundleSourceFailureReason(error): a string-match classifier whose DEFAULT FALLBACK (line 105) is 'bundleSourceFailed'. A TimeoutException message matches none of the branches, so it falls through to 'bundleSourceFailed' — MISLABELING a transport timeout as a bundle-source failure even though BUNDLE_SOURCE_BUILT already succeeded.
- lib/core/local_discovery/bonsoir_discovery_service.dart — mDNS _mknoon._tcp advertise/discover. local_discovery_service.dart (resolvePeer / LocalPeer host:port). local_ws_server.dart (the Dart WS/HTTP server, 18.5KB). local_media_sender.dart / local_media_server.dart.

ARITHMETIC CLUE: transferringDatabase 07:23:04.619 -> error 07:23:43.474 = 38.85 s ≈ ~4 x httpTimeout(10s). The transcript POST and manifest POST clearly succeeded fast (sub-second) because their stages advanced. So the stall is in the SEGMENT phase (or whatever _postJson runs first after transferringDatabase). Determine the exact retry/timeout structure that yields ~38.85s, and WHICH request hung.

PIVOTAL QUESTIONS TO RESOLVE FROM SOURCE:
  Q1. Small JSON POSTs (transcript @287, manifest @338) succeeded but the large segment POSTs stalled. WHY would small succeed and large hang? (receiver segment handler bug/await; large-body upload over Android HttpClient; chunked addStream stalls; connection reuse/keep-alive; backpressure).
  Q2. What is the exact retry/timeout path producing ~38.85s with httpTimeout=10s (e.g., ~4 attempts)? Where is TimeoutException thrown and why is it not caught into a graceful result.failure?
  Q3. Is the receiver-side silence because handlers are un-instrumented, OR because the segment requests never reached it? Trace the receiver command handlers (segment/upload) in account_migration_local_transfer_runtime.dart + local_ws_server.dart; does the segment endpoint hang or never respond?
  Q4. Is the libp2p "netlinkrib: permission denied" / peer flap relevant to this Dart-HTTP-over-LAN transport, or unrelated noise? (Known Android issue: wlynxg/anet interface-address resolution; Go libp2p, NOT the move's Dart WS/HTTP path — but assess any indirect impact on mDNS/multicast/LAN reachability.)
  Q5. Diagnosability defects: (a) transport emits no FLOW telemetry; (b) bundleSourceFailed mislabel; (c) generic user message. Confirm each from source.
`

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'rootCauseConfirmed', 'summary', 'mechanism', 'evidence', 'severity', 'category', 'fixDirection'],
  properties: {
    dimension: { type: 'string' },
    rootCauseConfirmed: { type: 'boolean' },
    summary: { type: 'string' },
    mechanism: { type: 'string', description: 'Precise causal chain with file:line and log:line refs inline' },
    category: { type: 'string', enum: ['primary-cause', 'contributing-cause', 'environmental', 'diagnosability-defect', 'ruled-out'] },
    evidence: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['kind', 'ref', 'detail'],
        properties: { kind: { type: 'string', enum: ['code', 'log', 'doc'] }, ref: { type: 'string' }, detail: { type: 'string' } },
      },
    },
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    fixDirection: { type: 'string' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['holdsUp', 'confidence', 'assessment'],
  properties: {
    holdsUp: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    assessment: { type: 'string' },
    corrections: { type: 'array', items: { type: 'string' } },
    missedEvidence: { type: 'array', items: { type: 'string' } },
  },
}

const DIMENSIONS = [
  {
    key: 'sender-segment-timeout',
    prompt: `Trace the SENDER side of account_migration_local_transfer_runtime.dart _run() from onProgress(transferringDatabase) (line 358) through _sendPreparedBundleSegments (525-560) and _postJson (807-830). Establish EXACTLY: how the 34 segments are posted; the retry structure (count, backoff); how httpTimeout(10s) applies per request (addStream vs close); where TimeoutException originates and why it propagates as an uncaught throw (caught only by the wired catch at journey_wired.dart:481) instead of a graceful AccountMigrationTransferResult.failure. Reconcile the 38.85s wall time with httpTimeout=10s (≈4 attempts?). Confirm transcript(287)+manifest(338) succeeded (stages advanced) so the stall is in the segment phase. Answer Q1/Q2.`,
  },
  {
    key: 'receiver-segment-handler',
    prompt: `Trace the RECEIVER side: the HTTP/WS command handlers in account_migration_local_transfer_runtime.dart (search for the command constants accountMigrationLocalTransferCommandManifest/Transcript/Segment/Complete and the request router) plus lib/core/local_discovery/local_ws_server.dart and the import staging (migration_database_import_staging.dart / migration_database_active_importer.dart). Determine: does the receiver emit ANY FLOW telemetry per command (explaining the iPhone log silence)? Could the segment/upload endpoint hang, block, or never send an HTTP response (so the sender's _postJson hits its 10s timeout)? Is there any await (disk write, decrypt, db import, lock) on the receiver segment path that could stall? Answer Q3. Decide whether the receiver got the manifest/transcript but stalled on segments, vs never received segments.`,
  },
  {
    key: 'peer-resolution-discovery',
    prompt: `Trace how the SENDER resolves the receiver address: discovery.resolvePeer (account_migration_local_transfer_runtime.dart:272) -> LocalDiscoveryService / bonsoir_discovery_service.dart (_mknoon._tcp) -> LocalPeer host:port used by _postJson. Does it yield an IP or a ".local." mDNS hostname? On Android, does Dart HttpClient resolve ".local." hosts (mDNS) reliably? Note the iPhone advertises port 53954 but the Pixel's small POSTs (transcript/manifest) SUCCEEDED — so the address resolved and connected at least initially. Assess whether a ".local."/hostname-based or interface-flapping address could work for small requests then stall for large uploads. Answer the discovery portion of Q1. Cross-check: how does the OLD phone learn the receiver endpoint — from the scanned QR (migration_qr_payload) or from mDNS discovery? Read migration_qr_payload model.`,
  },
  {
    key: 'android-netlink-libp2p',
    prompt: `Assess the recurring pixel GoLog error every ~5s: 'failed to resolve local interface addresses' {"error":"route ip+net: netlinkrib: permission denied"} (basic_host.go:396, libp2p) and the 07:23:37 libp2p relay peer flap (peer:disconnected/peer:connected). Determine whether this is RELEVANT to the move transport (which is Dart HttpClient/WebSocket over the LAN to the iPhone's Dart WS server on 53954) or UNRELATED libp2p/relay noise. Reference the known Android issue (wlynxg/anet interface-address resolution; the project notes 'Android build requires Go < 1.25 or patched wlynxg/anet'). Could Android multicast-lock / NetworkInterface.list restrictions affect Dart mDNS (bonsoir) or large LAN uploads mid-session? Be explicit about what is causation vs correlation vs noise. Answer Q4. Default to 'ruled-out/environmental' unless you find a concrete code link.`,
  },
  {
    key: 'error-classification-diagnosability',
    prompt: `Confirm the diagnosability defects from source: (a) account_migration_transfer_flow.dart:83-106 accountMigrationBundleSourceFailureReason returns 'bundleSourceFailed' as the DEFAULT fallback (line 105), so a transport TimeoutException is mislabeled as a bundle-source failure even though BUNDLE_SOURCE_BUILT succeeded — and the wired layer (journey_wired.dart:487-499) uses this reason and the generic message. (b) The transport (_postJson, _sendPreparedBundleSegments) emits no emitFlowEvent, so neither log shows which request/segment/connect hung. (c) accountMigrationTransferErrorType just returns runtimeType. Explain how these THREE defects make this failure undiagnosable from logs and how they should be split (transport-timeout vs bundle-source vs receiver-rejected). Answer Q5. Category: diagnosability-defect.`,
  },
  {
    key: 'log-timeline-authoritative',
    prompt: `Re-derive the AUTHORITATIVE cross-device timeline from ./pixel.log and ./iphone-13.log with exact line numbers (grep; do not trust the summary). Confirm: (a) the sender stage progression and the EXACT timestamps for transferringDatabase and the TRANSFER_ERROR, and the 38.85s delta; (b) that transcript+manifest POSTs must have succeeded (stages advanced past them) — note there is no explicit success log so this is an inference from control flow; (c) the total absence of migration-transport FLOW events in the stall window on the Pixel; (d) the iPhone receiver inbound-silence and the 07:23:49 STOP; (e) the libp2p netlink errors and the 07:23:37 peer flap timestamps; (f) anything that CONTRADICTS the 'segment-upload stalled' story (e.g., evidence the manifest actually failed, or an explicit receiver-side error). Return the timeline as mechanism with log:line refs in evidence.`,
  },
]

phase('Trace')
const results = await pipeline(
  DIMENSIONS,
  (d) => agent(`${d.prompt}\n\n---\n${EVIDENCE}`, { label: `trace:${d.key}`, phase: 'Trace', schema: FINDINGS_SCHEMA })
    .then((f) => ({ ...f, _key: d.key })),
  (finding, d) => agent(
    `Adversarial verifier. REFUTE this finding against ACTUAL source + logs (cwd flutter_app; ./pixel.log ./iphone-13.log). Verify every file:line and log:line says what is claimed; check the causal mechanism is what the code does; surface contradicting evidence. Be skeptical; default holdsUp:false if thin. Pay special attention to: is the "manifest/transcript succeeded" inference sound? is the 38.85s≈4×10s retry claim actually supported by the code? is the libp2p/netlink angle correctly scoped as noise vs cause?\n\nFINDING (dimension ${d.key}):\n${JSON.stringify(finding, null, 2)}\n\n---\n${EVIDENCE}`,
    { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT_SCHEMA },
  ).then((v) => ({ finding, verdict: v, key: d.key })),
)

const verified = results.filter(Boolean)

phase('Synthesize')
const synthInput = verified.map((r) => `### ${r.key}\nFINDING:\n${JSON.stringify(r.finding, null, 2)}\nVERDICT:\n${JSON.stringify(r.verdict, null, 2)}`).join('\n\n')

const report = await agent(
  `You are the lead debugger. Synthesize the verified findings into a single REPORT-ONLY root-cause analysis (no code changes) for this failure:
"Move Account Pixel->iPhone13 aborted with TimeoutException ('stopped unexpectedly before final handoff'); bundle built fine (34 segments, all media present) but the database/segment transfer stalled ~38.85s then timed out."

Write a thorough Markdown report body (no surrounding code fence), sections:
1. ## Executive Summary (4-6 sentences: what failed, the most probable root cause, and the certain secondary defects)
2. ## What The Logs Prove (line-cited cross-device timeline, sender then receiver; flag inferences vs direct evidence)
3. ## Root Causes (Ranked) — each: bolded title, severity, category (primary/contributing/environmental/diagnosability), precise mechanism with file:line + log:line, and confidence reflecting the adversarial verdict. CLEARLY separate (i) the proximate failure (segment/database transfer stalled -> 10s httpTimeout x retries -> TimeoutException), (ii) the most probable underlying cause (state the leading hypotheses for why small POSTs succeeded but segment upload stalled, ranked, with what evidence would confirm each), (iii) the CERTAIN diagnosability defects (bundleSourceFailed mislabel; zero transport telemetry; generic message), and (iv) ruled-out/environmental (libp2p netlink noise — say plainly whether it's cause or noise).
4. ## Why This Is Hard To Diagnose (the instrumentation + classification gaps)
5. ## What We Cannot Yet Conclude (honest gaps: receiver silence is un-instrumented not proof; need a re-run with transport logging / packet capture; whether environmental WiFi)
6. ## Recommended Next Steps (diagnostic, ordered: what to instrument/log, what to capture on re-run, code reading to confirm the segment-stall hypothesis) and ## Recommended Fixes (separate transport timeout/retry/telemetry from error classification) — clearly labeled as recommendations, not applied.
7. ## Confidence (per root cause)

Only assert what verified findings support; where a verifier downgraded a finding, reflect it. Prefer precise citations. Distinguish PROVEN (timeout fired, bundle built, stages advanced, mislabel, no telemetry) from INFERRED (segment-phase stall) from HYPOTHESIS (why segments stalled). Be exhaustive but precise.\n\n---\nVERIFIED FINDINGS:\n${synthInput}\n\n---\n${EVIDENCE}`,
  { label: 'synthesize:report', phase: 'Synthesize' },
)

return { report, verified }
