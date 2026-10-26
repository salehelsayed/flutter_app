# Priority end-to-end MCP execution

Prepared from `ad970f81d3eba2be6f178bfc73eb4003bb4a6f8d`. Only `flutter_app`
executes device actions, after build 127's lanes and its device ownership end.
Use the actual Appium MCP tools and the shared
[camera/permission operations](priority-e2e-camera-permission-mcp.md).
This packet changes no app behavior and launches no device CLI or UI server.

## Preparation and receipt commands

1. Resolve the currently available matrix through the executor's existing setup
   checks. Pin targets privately and acquire the existing campaign leases.
   Prefer Pixel plus an available Android emulator for shared Android behavior;
   use an available iPhone for the explicitly requested Android/iOS parity legs.
   iPhone 11/13 are usable when available; neither model is a mandatory gate.
   Missing targets are `N/A (target unavailable by project policy)`.
2. Bind each role to its exact installed source, artifact SHA-256, version and
   configuration. Record current native trees, permissions and owned state.
   Different/older candidates cannot supply the receipt's candidate claim.
   Preserve the owner apps, identities, history, contacts and photo libraries.
   Use an already available disposable package/emulator for a fresh installation;
   do not erase an owner's phone or create hardware to satisfy a case.
3. Create a private attempt directory. For each missing case, generate a receipt:

   ```sh
   python3 scripts/priority_e2e_verdict.py template --case RG-002 --source FULL_CANDIDATE_REVISION > PRIVATE_ATTEMPT/receipt.json
   ```

   Set its unique `run_id`, real artifact bindings and private evidence paths.
   Execute the named steps below with MCP, retaining timestamps, native trees,
   screenshots and the first failure at the original deadline. Fill a check
   only from its actual observation; placeholders remain `NOT_RUN`.
4. Run the host-only recorded-evidence verdict:

   ```sh
   python3 scripts/priority_e2e_verdict.py check --source FULL_CANDIDATE_REVISION --receipt PRIVATE_ATTEMPT/receipt.json
   ```

   References must be nonempty files inside the attempt directory. The checker
   hashes them, checks completeness, source/platform binding and recorded call
   start times. `PASS_RECORDED` means complete executor observations, **not**
   independent screenshot/audio interpretation or signed-release certification.
   `INCOMPLETE` exits 1. A live unavailable-target record with evidence yields
   `N/A_TARGET_UNAVAILABLE`, not PASS. Never relabel a setup failure as missing
   hardware. Keep device identities, messages, codes and logs out of mail.

## RG-002 — fresh onboarding and first conversations

Planning estimate: 10–20 minutes. Targets: disposable Android installation plus
Pixel/available Android peer. This is the shared Android journey; it does not
certify iOS onboarding.

1. Prove the disposable installation has no identity/contact/group. Launch its
   supported onboarding and finish real UI identity creation. Do not use
   `auto_setup.json` or a seeded database: `ProductionAndroidJourney.prepare`
   writes that file before launch and therefore is not this onboarding proof.
2. Through real QR/contact UI, request/explicitly accept, observe reciprocal
   linking/keys, then send one unique exact first text in each direction. Use
   the existing CR-001 acceptance oracle; no `prepare_contact` command.
3. The new user creates or joins a real group through the supported UI. Every
   entitled member receives the first unique group message once. Record the
   actual roster and receiver observations, not just the sender's send tick.
4. Fill all RG-002 checks. Reopen without clearing data and retain the identity,
   accepted relationship and both conversations. Restore only owned state.

## CR-009, DC-011 and GX-002 — cross-platform basics

Planning estimate: 30–50 minutes, separately recorded subcases. Use Pixel and an
available iPhone; GX-002 also needs a third available peer (Android emulator is
sufficient). Use real candidate builds and read current UI; the old Group C
runbook's “waiting for UI-Update” and “do not use iPhone 11” constraints are
historical session restrictions, not current gates.

- **CR-009:** use fresh owned Android test identities, preserving existing owner
  pairings. First iPhone scans/adds the fresh Pixel test identity, which explicitly
  accepts; exchange first texts both ways. Repeat with another fresh isolated
  Android identity as scanner/initiator and iPhone as explicit acceptor. Record
  real scanning versus supported manual entry separately: payload import does
  not prove the camera scanner. Reopen and require one linked relationship and
  one copy of each first text. If using the existing production preparation
  helper for this case, set `prepareContactMesh: false`; its contact seeding
  cannot satisfy the handshake. No UI/identity bypass belongs in RG-002.
- **DC-011:** reuse Group C's [text/media steps](astra-group-c-device-runbook.md#dc-011-text-and-representative-media-in-both-directions).
  Exchange ordered exact text and actual image, short video and voice note in
  both directions. Image must open fully with exact caption; video/voice content
  needs a real human/acoustic observer, not a progress timer. Restart both owned
  processes without clearing data, then check content, order and uniqueness
  again. Existing structural playback evidence does not fill missing content.
- **GX-002:** reuse the production group create and GM-006 remove/re-add action
  sequence, applied through MCP to this mixed-platform roster. Create/accept a
  three-member group; send from each platform and inspect every entitled
  receiver. Remove C, send a unique removed-window marker: remaining receivers
  get it once and C never gets it, including after re-add/reopen. Re-add/accept C
  through current authority, send a distinct post-readd marker from C and from
  another member, and inspect every now-entitled receiver. The existing
  `production_group_gm006_criteria.dart` defines the entitlement/epoch oracle;
  Android-only/fake-policy results cannot certify this mixed-platform run.

## MEDIA-002/003 — existing coverage, reuse rather than duplicate

The 2026-10-22 owner run already captured both camera directions, Original and
Compressed, full recipient viewers, exact captions and reopened uniqueness:
`journey-coverage-matrix.yaml:3987,4056`, backed by
`build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:14,18,41`.
The Android full file was exported; iPhone full viewer/Info was observed without
writing into the owner's photo library. This covers the requested historical
camera/full-open/caption behavior, not original sensor resolution, an iPhone
exported hash, or a newly installed signed candidate. Skip a duplicate runner.
If a candidate rerun is needed, use shared `camera_capture` and
`camera_send_and_open` in both directions, about 10–15 minutes.

## DC-002 — existing runnable production campaign

Reuse `integration_test/scripts/run_production_direct_ordered_replay.dart` and
`tool/sims/production_direct_ordered_replay_criteria.dart`, capability
`production.direct_catalog.ordered_offline_replay`, wrapper check
`production-catalog-direct-ordered`. Use the existing SIMS preparation/build
cache and that check's setup preview, then the ordinary wrapper run pinned to
the available disposable emulator pair. Do not invoke it on preserved phones.

Planning estimate: 20–40 minutes; registered timeout is 7,200 seconds, not a new
deadline. It sends 100 numbered online texts, ten recipient-offline texts,
requires actual inbox custody, verifies owned recipient death and both-peer
restarts, and runs the existing exact-ID/order/uniqueness oracle at each phase.
Retain its original `observations.json`, `oracle.json`, SIMS result and cleanup.
Do not substitute routing S13's partial receipt threshold. This existing runner
needs execution by flutter_app; host/source coverage is not a device PASS.

## VC-015/014 — answered audio and supported OS states

Planning estimate: 35–55 minutes with idle-state waits. Use Pixel plus an
available iPhone. **Before every call, check local Europe/Berlin time: no calls
before 08:30 (CET on 2026-10-26).** Do not ring an owner's iPhone at night.

1. VC-015: iPhone initiates, Android answers; reverse roles. Reuse Group C's
   [call actions](astra-group-c-device-runbook.md#vc-015-each-platform-initiates-and-answers).
   Require matching live call, 20 seconds of intelligible synthetic audio in
   both directions, answerer hangup and once-only terminal cleanup/history on
   both sides. Capture real human/acoustic content evidence. Connected text,
   mic indicators, RTP flags or today's unanswered timing calls are insufficient.
2. VC-014: for each platform, put the callee in supported background and locked
   states with MCP. For iOS idle suspension, reuse the existing signed-audio
   six-minute no-VoIP-push precondition. The system incoming call surface must
   arrive within 30 seconds; answer and check audio/cleanup as above. Record
   the state, native incoming surface and exact call, including first failures.
3. Add supported OS process-termination delivery separately. User force-stop or
   force-quit is not equivalent to OS termination/suspension. If a state is
   unsupported, record `supported_process_termination` as N/A with explicit
   product/OS evidence; do not waive the supported background/locked legs.
4. Restore owned lock/lifecycle/audio state and leave no active call. Missing
   audibility observation remains incomplete; do not introduce an app audio hook.
   Record each call check's timezone-aware actual start in the receipt.

Today's timing evidence at `.codex-test-logs/call-timing-20261026T0731Z/SUMMARY.md:7`
is explicitly unanswered/no audio. TRANSFER-011's retained 2026-10-23 summary
proves migrated simulator media reopen, with the physical receiver leg unrun;
it is neither fresh-user onboarding nor a new physical cross-platform audio run.
