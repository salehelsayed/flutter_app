# LAN-002 Real Same-WiFi mDNS Acceptance Proof Plan

Status: arbiter-pass - prerequisite-blocked

## Planning Progress

- 2026-05-30T00:17:42+02:00 - Planner completed. Files inspected since last update: live device availability supplied by controller and the evidence set above. Decision/blocker: draft classifies LAN-002 as `prerequisite-blocked` until same-WiFi, paired-account, Local Network permission, and physical-device artifact capture prerequisites are satisfied or a non-interactive LAN harness exists. Next action: strict reviewer pass for missing gates, stale assumptions, and simulator overclaim.
- 2026-05-30T00:17:42+02:00 - Reviewer started. Files inspected since last update: this draft plan. Decision/blocker: checking whether every required proof has a command, artifact, or explicit blocker and whether reliability-sim is correctly treated as companion evidence only. Next action: record sufficiency review.
- 2026-05-30T00:24:12+02:00 - Reviewer completed. Files inspected since last update: this draft plan and exact user checklist. Decision/blocker: sufficient as a prerequisite-blocked plan after tightening sender-side proof so aggregate diagnostics cannot substitute for stored `local` evidence. Next action: arbiter classification of the execution blocker versus structural plan blockers.
- 2026-05-30T00:26:04+02:00 - Arbiter started. Files inspected since last update: reviewer result and tightened proof ledger. Decision/blocker: classifying missing same-WiFi fixture/harness as an execution prerequisite, not a structural planning defect. Next action: write final plan verdict.
- 2026-05-30T00:26:04+02:00 - Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural plan blockers remain; LAN-002 itself is prerequisite-blocked until manual same-WiFi setup or a non-interactive physical-device harness can produce the required artifacts. Next action: hand the plan back without executing tests, builds, or production-code edits.

## real scope

LAN-002 is an acceptance-proof session for real same-WiFi local discovery and transport selection. It does not own product behavior changes.

In scope:

- Prove, with two physical devices on the same WiFi and local discovery enabled, that a currently visible 1:1 peer can win the send race through the local path.
- Prove the sender-side stored transport is `local` for at least one real same-WiFi text send.
- Prove the receiver-side diagnostics or stored receive path records the WiFi/local bucket for the same exchange.
- Prove the positive result is not a hard-coded label by running a negative control where LAN is unavailable and `wifi`/`local` does not increment.
- Capture durable evidence artifacts in a repo-local evidence directory or append them to this plan.

Out of scope:

- No production code edits.
- No new local-discovery architecture.
- No group, intro, contact-request, share, delete/tombstone, NAT traversal, DCUtR, relay springboard, or cross-network direct-delivery work.
- No final matrix or closure-doc updates; LAN-003 owns durable closure docs after LAN-002 evidence is accepted or explicitly blocked.
- No claim that loopback, fake discovery, standard simulators, disabled-local-discovery runs, or single-device transport gates prove mDNS.

## closure bar

LAN-002 is closable only when this coverage ledger is complete:

| Required proof | Accepted evidence | Current planning state |
| --- | --- | --- |
| Two real physical devices are attached and selected. | Device inventory naming exact IDs and roles. | Physical devices are visible from controller context, but roles are not yet bound to a runnable proof. |
| Both devices are on the same WiFi/subnet with AP client isolation off. | Fixture note with SSID/subnet/AP-isolation confirmation, or harness preflight output. | Blocked: not proven by `flutter devices`. |
| Local discovery is enabled. | Build command or harness log proving `DISABLE_LOCAL_DISCOVERY=false` or omitted, plus `LOCAL_MDNS_ADVERTISE_START` and `LOCAL_MDNS_DISCOVERY_START` logs. | Blocked until a run is performed. |
| iOS Local Network permission is accepted on every iOS participant. | Manual fixture note plus diagnostics card showing discovery active and not `suspected-denied`, or harness-preflight permission record. | Blocked: cannot be accepted non-interactively by current repo harness. |
| App identities/accounts are created and paired as contacts. | Fixture note, harness identity exchange output, or screenshots/logs proving both contacts can open a 1:1 conversation. | Blocked: no paired-account fixture supplied. |
| Positive same-WiFi send uses local. | Sender DB row, harness JSON, or app log tied to a message id showing sender-side stored transport `local`; diagnostics are corroboration only. Relay must stay unchanged for that exchange. | Blocked until manual or harness proof. |
| Receiver records WiFi/local. | Receiver DB row `wifi` or diagnostics report with WiFi bucket increment for the same exchange. | Blocked until manual or harness proof. |
| Negative control rejects false local. | Repeat with LAN impossible, permission denied, or devices on different networks; WiFi/local stays zero/unchanged and direct/relay/inbox carries delivery. | Blocked until manual or harness proof. |
| Companion transport confidence is classified correctly. | Single-device transport gate and/or reliability-sim evidence explicitly labeled as companion only. | Planned; cannot close LAN-002 without physical mDNS proof. |

If any required proof remains unavailable, LAN-002 must finish as `still_open` or `prerequisite-blocked`; it must not be marked accepted on loopback, fake discovery, simulator `wifi=0`, disabled local discovery, or single-device transport evidence.

## source of truth

- Active session contract: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, LAN-002 block and LAN-001 closure ledger.
- Product/source contract: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`.
- Transport tracking facts: `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`, `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`, and `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`.
- Gate source of truth: `scripts/run_test_gates.sh`; if prose in `Test-Flight-Improv/test-gate-definitions.md` disagrees, the script wins.
- Current code and tests beat stale prose. Current evidence shows host/loopback local/fallback/media/diagnostics coverage from LAN-001, but no current repo command proves true physical-device mDNS selection.

## session classification

`prerequisite-blocked`

LAN-002 remains an evidence-gated objective in the breakdown, but current execution is prerequisite-blocked. The controller has visible physical devices, but that does not prove same-WiFi reachability, accepted Local Network permission, paired accounts, local-discovery-enabled app builds, or a non-interactive artifact capture harness. The repo currently documents a manual two-phone procedure; it does not provide a runnable same-WiFi mDNS acceptance command.

## exact problem statement

The repo can prove local transport mechanics with fake discovery and loopback WebSocket tests, but that does not prove the user-visible claim that two real nearby devices on the same WiFi discover each other over Bonjour/mDNS and prefer the local path over relay/direct/inbox. The missing proof risks overclaiming LAN reliability based on fallback success or simulator runs where local discovery is disabled. LAN-002 must produce or block on real physical-device mDNS evidence while preserving all LAN-001 boundaries.

## Device/Relay Proof Profile

Required primary physical device pair:

- Device A: iOS physical device `00008030-001A6D2801BB802E` (`Saleh's iPhone` from controller inventory).
- Device B: iOS physical device `00008110-00184D622289801E` (`iOS iPhone` from controller inventory).

Allowed alternate pair only after documenting why the primary iOS pair cannot be used:

- Device A: iOS physical device `00008110-00184D622289801E`.
- Device B: Android Pixel 6 `21071FDF600CSC`.
- Android alternate requires resolving the shell-level `adb` gap first, or proving Flutter can install/run and artifacts can still be collected without direct `adb`.

Required app/build mode:

- Debug build on both devices, because the transport diagnostics card is debug-gated.
- Local discovery enabled. Do not use `reset_simulators.sh`; do not set `DISABLE_LOCAL_DISCOVERY=true`.
- Relay must remain reachable during the positive run so the proof shows local winning against a real fallback option, not only success in a relay-disabled environment.

Required environment and dart defines:

```bash
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"
export LAN002_EVIDENCE_DIR="Test-Flight-Improv/evidence/LAN-002/<run-id>"
mkdir -p "$LAN002_EVIDENCE_DIR"
```

Required install/run commands for the primary pair, in two terminals:

```bash
flutter run -d 00008030-001A6D2801BB802E \
  --debug \
  --dart-define=DISABLE_LOCAL_DISCOVERY=false \
  --dart-define=MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" \
  2>&1 | tee "$LAN002_EVIDENCE_DIR/device-a-flutter-run.log"
```

```bash
flutter run -d 00008110-00184D622289801E \
  --debug \
  --dart-define=DISABLE_LOCAL_DISCOVERY=false \
  --dart-define=MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" \
  2>&1 | tee "$LAN002_EVIDENCE_DIR/device-b-flutter-run.log"
```

Required manual setup during the run:

- Put both devices on the same SSID/subnet and confirm AP client isolation is off.
- Accept the iOS Local Network permission prompt on both devices, or verify Settings > Privacy & Security > Local Network > app is ON.
- Create or reuse two app identities and pair them as contacts through the normal app flow.
- Keep both apps foregrounded for at least 15-30 seconds after launch or foreground resume.
- On both devices, open Settings > Transport Diagnostics and confirm discovery active and peers `>= 1` on at least one side before the positive send.

Required positive evidence artifacts:

- `$LAN002_EVIDENCE_DIR/device-inventory.txt`: copied controller inventory including the selected physical IDs and the `adb` availability note.
- `$LAN002_EVIDENCE_DIR/fixture-profile.md`: SSID/subnet/AP-isolation confirmation, device roles, build mode, dart defines, account/pairing steps, Local Network permission state, and who performed the manual actions.
- `$LAN002_EVIDENCE_DIR/device-a-flutter-run.log` and `device-b-flutter-run.log`: logs containing `LOCAL_MDNS_ADVERTISE_START`, `LOCAL_MDNS_DISCOVERY_START`, at least one `LOCAL_MDNS_PEER_FOUND`, and local send/receive evidence if emitted.
- `$LAN002_EVIDENCE_DIR/device-a-diagnostics-before.txt` and `device-b-diagnostics-before.txt`: copied debug-card baseline report before the message exchange.
- `$LAN002_EVIDENCE_DIR/device-a-diagnostics-after.txt` and `device-b-diagnostics-after.txt`: copied debug-card baseline report after the message exchange.
- `$LAN002_EVIDENCE_DIR/sender-stored-transport-proof.txt` or `$LAN002_EVIDENCE_DIR/harness-result.json`: message-id-tied sender-side proof that the stored transport is `local`. Aggregate diagnostics alone are insufficient for this row.
- `$LAN002_EVIDENCE_DIR/message-proof.md`: exact message count, direction, timestamp window, sender-side `local` evidence, receiver-side WiFi/local evidence, and relay/direct/inbox counters before and after.

Required negative-control evidence artifacts:

- `$LAN002_EVIDENCE_DIR/negative-control-profile.md`: how LAN was made impossible or local discovery was denied without disabling relay/inbox fallback.
- `$LAN002_EVIDENCE_DIR/negative-control-diagnostics-before.txt` and `negative-control-diagnostics-after.txt`: WiFi/local unchanged and fallback path incremented.
- `$LAN002_EVIDENCE_DIR/negative-control-result.md`: interpretation proving the positive WiFi/local result was not hard-coded or defaulted.

Missing non-interactive proof command:

```bash
dart run integration_test/scripts/run_lan_wifi_local_acceptance.dart \
  --devices 00008030-001A6D2801BB802E,00008110-00184D622289801E \
  --artifacts "$LAN002_EVIDENCE_DIR" \
  --require-local \
  --require-negative-control
```

This command is intentionally listed as missing, not runnable. A future executor may add a test-only harness with this behavior, but LAN-002 is currently blocked if the controller requires non-interactive execution.

Companion commands that are not mDNS proof:

```bash
FLUTTER_DEVICE_ID=00008110-00184D622289801E ./scripts/run_test_gates.sh transport
```

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
```

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_transport_test.dart
```

The companion commands can provide regression confidence, but they do not satisfy LAN-002 because `wifi_transport_test.dart` is loopback-only and standard reliability-sim/simulator runs do not prove real Bonjour/mDNS discovery.

## files and repos to inspect next

- `lib/core/debug/e2e_test_mode.dart`
- `lib/main.dart`
- `lib/core/local_discovery/bonsoir_discovery_service.dart`
- `lib/core/local_discovery/disabled_local_discovery_service.dart`
- `lib/core/local_discovery/local_discovery_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- `reset_simulators.sh`
- `integration_test/wifi_transport_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/scripts/run_wifi_relay_fallback_smoke.dart`
- `scripts/run_test_gates.sh`
- `scripts/run_reliability_simulations.sh`
- `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`

If a non-interactive harness is approved, inspect these harness patterns before writing it:

- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`

## existing tests covering this area

- `test/features/conversation/application/send_chat_message_use_case_test.dart` covers fake local success, discover-on-send, stale/absent/non-LAN fallback, and sender-side `local` persistence under controlled fake discovery.
- `test/core/local_discovery/local_peer_ttl_test.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, and `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` cover host/loopback TTL, local P2P facade, WebSocket ack/timeout, local media, and stale host behavior.
- `test/core/services/p2p_service_inbound_transport_test.dart` covers incoming local WebSocket messages being surfaced as the WiFi/local bucket.
- `test/core/services/p2p_service_lan_availability_test.dart`, `test/core/debug/transport_metrics_test.dart`, `test/core/debug/transport_metrics_privacy_test.dart`, and `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart` cover aggregate diagnostics and privacy-safe rendering.
- `integration_test/wifi_transport_test.dart` tests two `LocalWsServer` instances over localhost and explicitly does not test mDNS.
- `integration_test/transport_e2e_test.dart` documents that the CLI Go test peer does not run mDNS, so WiFi fallback is only implicit there.
- `scripts/run_test_gates.sh transport` includes transport integration suites, but no member proves true same-WiFi mDNS.
- `scripts/run_reliability_simulations.sh 1to1 --dry-run` lists 1:1 reliability commands, including `wifi_transport_test.dart` and `run_wifi_relay_fallback_smoke.dart`, but the listed entries do not pin real physical mDNS local delivery.

Missing coverage:

- No current test instantiates `BonsoirDiscoveryService` across two real physical app instances and asserts that a real send persisted `local`/WiFi while relay stayed unchanged.
- No current non-interactive harness can grant or verify iOS Local Network permission, pair two physical accounts, confirm same-WiFi/AP isolation, drive a real 1:1 send, and collect both devices' diagnostics.

## regression/tests to add first

Do not add production regressions in LAN-002 unless execution is explicitly converted from manual proof to harness work.

If non-interactive closure is required before manual execution is allowed, add a test-only acceptance harness first:

- New runner: `integration_test/scripts/run_lan_wifi_local_acceptance.dart`.
- Optional app-side harness: `integration_test/lan_wifi_local_acceptance_test.dart`.
- Required runner features: two physical-device IDs, local-discovery-enabled debug build, relay address injection, identity/account pairing or fixture import, foreground keepalive, diagnostics extraction, positive local send, negative control, and JSON/text artifacts under `Test-Flight-Improv/evidence/LAN-002/<run-id>/`.
- Gate classification: classify the runner as nightly/manual or a dedicated physical-device acceptance command, not a PR gate, and run `./scripts/run_test_gates.sh completeness-check` only if gate docs or test classification are edited.

If manual proof is accepted, no new test is required before execution; the manual fixture profile and copied diagnostics artifacts are the proof.

## step-by-step implementation plan

1. Stop immediately if the executor cannot use either the manual two-phone procedure or a newly approved non-interactive harness. Record `prerequisite-blocked`.
2. Bind the physical pair. Prefer `00008030-001A6D2801BB802E` plus `00008110-00184D622289801E`; use Pixel 6 only after the Android artifact path is resolved.
3. Create `$LAN002_EVIDENCE_DIR` and write `device-inventory.txt` and `fixture-profile.md`.
4. Install/run debug builds on both devices with `DISABLE_LOCAL_DISCOVERY=false` and relay addresses configured.
5. Accept iOS Local Network permission, pair the two app identities as contacts, keep both foregrounded, and wait for diagnostics to show discovery active and peer count `>= 1` on at least one device.
6. Capture before diagnostics reports from both devices.
7. Send 5-10 text messages from A to B and 5-10 replies from B to A.
8. Capture after diagnostics reports and Flutter logs. The positive run passes only if WiFi/local increments for the exchange and relay does not increment for those same messages.
9. Run the negative control by making LAN impossible while relay/inbox remains available. Capture before/after diagnostics. The control passes only if WiFi/local remains unchanged and fallback carries the send.
10. Optionally run companion transport/reliability commands listed in the Device/Relay Proof Profile. Interpret them as regression confidence only.
11. Append an `Execution Evidence` section to this plan with artifact paths and verdict: `accepted`, `still_open`, or `prerequisite-blocked`.
12. Do not update final closure docs or matrix rows in LAN-002. Hand accepted or blocked evidence to LAN-003.

## risks and edge cases

- Same SSID is insufficient if AP client isolation blocks peer reachability.
- iOS Local Network permission denial can look like a normal zero-peer LAN.
- A single successful direct/relay/inbox send can mask the absence of local discovery.
- Diagnostics are session-scoped; before/after reports must be captured in the same app sessions as the proof.
- Debug-card evidence is not available in TestFlight/release; release/profile runs need a separate artifact extraction path.
- `adb` is not on this shell PATH, so Android physical proof may fail at artifact collection even though Flutter lists the Pixel.
- Foreground/background transitions can restart advertising; keep both devices foregrounded unless a lifecycle probe is explicitly being run.
- Peer IDs or logs may contain sensitive identifiers; evidence summaries added to durable docs should use aggregate counts and artifact paths rather than raw IDs.

## exact tests and gates to run

Required physical proof commands, after prerequisites are satisfied:

```bash
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"
export LAN002_EVIDENCE_DIR="Test-Flight-Improv/evidence/LAN-002/<run-id>"
mkdir -p "$LAN002_EVIDENCE_DIR"
```

```bash
flutter run -d 00008030-001A6D2801BB802E --debug \
  --dart-define=DISABLE_LOCAL_DISCOVERY=false \
  --dart-define=MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" \
  2>&1 | tee "$LAN002_EVIDENCE_DIR/device-a-flutter-run.log"
```

```bash
flutter run -d 00008110-00184D622289801E --debug \
  --dart-define=DISABLE_LOCAL_DISCOVERY=false \
  --dart-define=MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" \
  2>&1 | tee "$LAN002_EVIDENCE_DIR/device-b-flutter-run.log"
```

Required manual actions inside those sessions:

- Pair the two accounts as contacts.
- Capture before/after transport diagnostics reports on both devices.
- Run the positive same-WiFi exchange.
- Run the negative control.

Required companion regression commands, not accepted as mDNS proof:

```bash
FLUTTER_DEVICE_ID=00008110-00184D622289801E ./scripts/run_test_gates.sh transport
```

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
```

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_transport_test.dart
```

If a new acceptance harness is added, run its exact command after implementation:

```bash
dart run integration_test/scripts/run_lan_wifi_local_acceptance.dart \
  --devices 00008030-001A6D2801BB802E,00008110-00184D622289801E \
  --artifacts "$LAN002_EVIDENCE_DIR" \
  --require-local \
  --require-negative-control
```

This harness command is currently a required missing capability, not an existing gate.

## known-failure interpretation

- `wifi_transport_test.dart` passing proves loopback WebSocket/media mechanics only.
- Simulator `wifi=0` is neutral because standard simulator setup disables local discovery.
- `transport_e2e_test.dart` and `run_wifi_relay_fallback_smoke.dart` can prove direct/relay/inbox liveness, but the CLI peer does not run mDNS and cannot be the local peer.
- A green `./scripts/run_test_gates.sh transport` on one device is companion confidence only.
- A visible physical device from `flutter devices --machine` is not enough to prove same-WiFi, permission, pairing, or local discovery.
- Android proof is blocked if artifact capture depends on `adb` and the shell still reports `adb: command not found`.
- If relay counters increment during the positive run, the run is not a local-path success unless separate sender-side DB/log evidence pins the tested messages to `local`.

## done criteria

LAN-002 is done only when one of these verdicts is recorded in this plan:

- `accepted`: all closure ledger rows are covered by artifact paths, including positive real physical same-WiFi `local`/WiFi proof and negative control.
- `prerequisite-blocked`: exact missing fixture or harness prerequisite is recorded, with the next safe action.
- `still_open`: a run was possible but failed to produce real mDNS/local evidence, with logs and failure interpretation.

Minimum accepted artifacts:

- Device pair and build/profile evidence.
- Same-WiFi and permission evidence.
- Pairing/account evidence.
- Message-id-tied sender-side stored transport `local` evidence.
- Positive before/after diagnostics and logs.
- Negative-control before/after diagnostics and logs.
- Explicit statement that loopback, fake discovery, simulator disabled-local-discovery, and single-device transport gates were not used as mDNS proof.

## scope guard

- Do not edit production code in LAN-002.
- Do not change local discovery semantics, TTL, media receive wiring, or diagnostics behavior unless execution is explicitly re-scoped.
- Do not weaken gates by accepting `direct || relay || inbox` for the positive same-WiFi proof.
- Do not broaden into group, posts, intro, notification, or NAT traversal flows.
- Do not record peer IDs, hostnames, raw addresses, or message content in durable closure docs; keep raw artifacts local and summarize aggregate proof.
- Do not mark LAN-003 or the whole source doc closed from LAN-002 planning.

## accepted differences / intentionally out of scope

- Manual debug-card evidence is acceptable only because the repo lacks a non-interactive physical mDNS harness; it remains weaker than a future automated runner.
- The Android Pixel 6 is visible but not the primary proof target while shell-level `adb` is unavailable.
- Reliability-sim and transport gates remain companion evidence, not closure proof, because they do not exercise real physical mDNS.
- Media and fallback probes may be skipped in LAN-002 if they would broaden beyond the text-send mDNS acceptance proof already isolated from LAN-001.
- Local Network permission handling remains heuristic in current production code; LAN-002 proves allowed-vs-blocked behavior, not an authoritative iOS permission API.

## dependency impact

- LAN-003 remains blocked until LAN-002 records either accepted artifacts or an explicit unresolved fixture/harness blocker.
- If LAN-002 is accepted, LAN-003 can update stable closure docs and matrices without reopening LAN-001.
- If LAN-002 is prerequisite-blocked, LAN-003 must not close same-WiFi reliability; it may only document the residual external fixture blocker.
- If the positive run fails because production behavior regressed despite LAN-001 host evidence, reopen a new implementation session scoped to the failing seam rather than expanding LAN-002 into an unbounded repair.

## reviewer result

Sufficient as a prerequisite-blocked plan.

Review answers:

- Sufficiency: sufficient with the recorded blocker. The plan is not execution-ready because no current command can complete the real same-WiFi proof non-interactively.
- Missing files, tests, or gates: no existing frozen gate proves physical mDNS. The missing capability is `integration_test/scripts/run_lan_wifi_local_acceptance.dart` or equivalent manual artifact capture.
- Stale assumptions: none found after explicitly treating LAN-001 as host/loopback-only and treating simulator `DISABLE_LOCAL_DISCOVERY=true` as neutral.
- Overengineering: no production repair or new architecture is included; the optional harness is test-only and only needed if manual proof is not acceptable.
- Decomposition: narrow enough. LAN-002 owns evidence, LAN-003 owns closure docs, and LAN-001 remains closed for host/loopback only.
- Minimum needed to execute: two paired physical devices on the same WiFi, accepted iOS Local Network permission, discovery-enabled debug builds, and artifact capture proving sender-side `local`, receiver-side WiFi/local, and a negative control.
- Checklist coverage: every user-listed proof requirement maps to a command, artifact, accepted difference, or explicit blocker. Aggregate diagnostics cannot substitute for message-id-tied sender-side `local` proof.

## arbiter decision

No structural plan blocker remains.

Classification:

- Structural blockers: none for the plan artifact. The closure bar, scope guard, proof profile, regression contract, stop rule, and checklist coverage are explicit.
- Execution prerequisite blocker: LAN-002 cannot safely execute in this controller run because same-WiFi/AP-isolation state, app account pairing, iOS Local Network permission acceptance, and message-id-tied sender-side `local` artifact capture are not available non-interactively. The current repo also lacks the proposed `run_lan_wifi_local_acceptance.dart` harness.
- Incremental details: exact UI screenshots or DB extraction mechanics can be selected by the executor after the fixture exists, as long as the required artifact names and proof fields are preserved.
- Accepted differences: simulator/reliability-sim/transport-gate runs remain companion confidence only; manual proof is weaker than an automated harness but acceptable only if it captures all required artifacts.

Stop rule: stop now. The plan was patched once for sender-side proof strictness; no final structural blocker remains to justify another planning loop.

## final planning output

Final verdict: `prerequisite-blocked`.

Final plan: use this plan as the LAN-002 contract only after either the manual two-phone fixture is ready or a test-only two-physical-device LAN acceptance harness exists. The exact proof profile requires iOS physical devices `00008030-001A6D2801BB802E` and `00008110-00184D622289801E`, debug builds with `DISABLE_LOCAL_DISCOVERY=false`, relay addresses configured, same-WiFi/AP-isolation confirmation, accepted Local Network permission, paired contacts, sender-side stored `local` proof, receiver-side WiFi/local proof, and a negative control.

Structural blockers remaining: none in the plan. The remaining blocker is an execution prerequisite: no current non-interactive same-WiFi mDNS harness or completed manual fixture/artifact package.

Incremental details intentionally deferred: screenshot format, exact DB extraction mechanism, and whether the Android Pixel 6 alternate is used after the `adb` path issue is resolved.

Accepted differences intentionally left unchanged: loopback, fake discovery, disabled-local-discovery simulators, and single-device transport gates are not mDNS proof; they remain companion confidence only.

Exact docs/files used as evidence:

- `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`
- `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `scripts/run_reliability_simulations.sh`
- `/Users/I560101/.codex/skills/run-flutter-reliability-sims/SKILL.md`
- `reset_simulators.sh`
- `lib/main.dart`
- `lib/core/debug/e2e_test_mode.dart`
- `lib/core/local_discovery/bonsoir_discovery_service.dart`
- `lib/core/local_discovery/local_discovery_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/disabled_local_discovery_service.dart`
- `lib/core/debug/transport_metrics.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/scripts/run_wifi_relay_fallback_smoke.dart`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`
- `Network-Arch/Transport-Reliability/06-test-and-simulation-strategy.md`
- `Test-Flight-Improv/99-transport-observability-and-metrics-HARVEST-DECISION.md`

Why the plan is unsafe to implement now: visible physical devices are not enough. Execution still needs manual same-WiFi setup, paired app accounts, Local Network permission acceptance, and an artifact path for sender-side `local` plus receiver-side WiFi/local proof. Without those, any run would overclaim LAN-002.
