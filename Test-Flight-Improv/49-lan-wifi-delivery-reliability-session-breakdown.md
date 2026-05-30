# Reliable Same-WiFi 1:1 Delivery Session Breakdown

Status: reusable-breakdown

Final program verdict: `still_open`

## Decomposition Artifact Updated

- Artifact path: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- Downstream workflow rule: detailed planning happens one session at a time, and later sessions must be refreshed against landed code before execution.

## Recommended Plan Count

Recommended plan count: 3

This is a three-session decomposition:

1. `LAN-001` - host-side local delivery, fallback, media, and diagnostics contract.
2. `LAN-002` - real same-WiFi device evidence for mDNS/local selection.
3. `LAN-003` - closure, matrix, and gate-documentation update.

## Overall Closure Bar

Same-WiFi 1:1 delivery can be called reliable only when all of these are true:

- A currently visible same-WiFi peer can win the 1:1 send race through the local path and persist the sender-side transport as `local`.
- A peer that is not visible, stale, denied, too slow, or not on the LAN falls back through direct, relay probe, or inbox without falsely reporting `local`.
- Incoming local WebSocket messages surface as the receiver-side WiFi/local transport bucket.
- Local image and voice bytes can transfer through the production local media receive path, pass token and SHA-256 checks, persist outside temporary storage, and leave relay fallback intact.
- LAN diagnostics remain aggregate and privacy-safe: active/inactive discovery, peer count, and suspected permission-denied state only.
- Standard simulator runs with `DISABLE_LOCAL_DISCOVERY=true` are never treated as proof that real mDNS same-LAN delivery works or fails.
- A real-device debug same-WiFi proof records that the app used the local path when local discovery is enabled.
- Stable 1:1 reliability, transport, and test-gate docs reflect the final evidence without inventing a new matrix.

## Source Of Truth

- Product intent: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- NET-REL tracking context: `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md` and `Network-Arch/Transport-Reliability/00-INDEX.md`
- Regression policy: `Test-Flight-Improv/14-regression-test-strategy.md`
- Named gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`
- 1:1 closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- 1:1 architecture reference: `Test-Flight-Improv/08-network-1to1-messaging.md`
- Stable matrix to extend when needed: `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
- Current code and tests govern stale prose. Current evidence shows LAN text, TTL, discover-on-send, local media receive, metrics, and diagnostics seams already exist in the working tree, but the real mDNS device proof remains evidence-gated.

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- Source row/status vocabulary: source doc uses narrative feature-spec coverage language (`Existing partial coverage`, `Current gap`, `In scope`, `Non-goals`) rather than row status values.
- Overall closure bar: same-WiFi 1:1 delivery requires host-verifiable local/fallback/media/diagnostics contracts, plus a real-device debug same-WiFi proof for mDNS/local path selection, plus stable reliability and gate documentation.
- Final verdict policy for this run: use `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; if physical-device same-WiFi mDNS evidence is unavailable, persist `still_open` with the exact external fixture blocker and next safe action instead of overclaiming closure.

## Controller Progress

- 2026-05-30T00:14:12+02:00 - Final program acceptance pass only: verified `LAN-001` accepted for host/loopback scope, `LAN-002` prerequisite-blocked on missing same-WiFi physical-device fixture or harness, and `LAN-003` skipped due to the unresolved `LAN-002` dependency. Persisted final program verdict `still_open`; no session planning, execution, source-doc, matrix, gate, production, or test-code updates were performed.

## Closure Progress

- 2026-05-29T22:01:44Z - `LAN-001` closure audit started. Phase: Completion Auditor. Docs inspected/updated: inspected `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, and `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`; updated this closure-progress entry only. Tentative verdict: `accepted_with_explicit_follow_up` for host/loopback LAN-001 proof only. Next action: verify execution evidence from the plan and classify residual LAN-002/LAN-003 boundaries before ledger updates.
- 2026-05-29T22:02:15Z - `LAN-001` closure audit classified. Phase: Closure Writer. Docs inspected/updated: inspected `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`, `/tmp/lan001-executor-result.txt`, `/tmp/lan001-qa-result.txt`, `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`, and `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`; updated closure-progress entries only. Tentative verdict: `accepted_with_explicit_follow_up` because LAN-001 direct host/loopback evidence is accepted and physical-device Bonjour/mDNS remains `LAN-002`. Next action: write the LAN-001 closure ledger without claiming whole-doc closure or executing `LAN-002`/`LAN-003`.
- 2026-05-29T22:02:50Z - `LAN-001` closure ledger written. Phase: Closure Reviewer. Docs inspected/updated: updated `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md`; no source, matrix, gate, production, or test-code files updated. Tentative verdict: `accepted_with_explicit_follow_up` for `LAN-001`; `LAN-002` and `LAN-003` remain not executed. Next action: review the breakdown diff for accuracy, residual boundaries, and overclaiming before finalizing closure.
- 2026-05-29T22:03:14Z - `LAN-001` closure review completed. Phase: Closure Reviewer. Docs inspected/updated: inspected the updated `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-breakdown.md` and ran `git diff --check`; updated this final closure-progress entry. Tentative verdict: final `accepted_with_explicit_follow_up` for `LAN-001` host/loopback proof only. Next action: report closure result; do not execute `LAN-002` or `LAN-003`.

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
|---|---|---|---|---|---|
| `LAN-001` | Host local-delivery and fallback contract | `implementation-ready` | `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md` | None | `accepted_with_explicit_follow_up` |
| `LAN-002` | Real same-WiFi mDNS acceptance proof | `evidence-gated` | `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-002-plan.md` | `LAN-001` | `prerequisite-blocked` |
| `LAN-003` | Closure and matrix update | `closure-only` | `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-003-plan.md` | `LAN-001`, `LAN-002` | `skipped_due_to_dependency` |

## Current Session Closure Ledger

| Session id | Closure outcome | Evidence accepted | Residual boundaries | Next action |
|---|---|---|---|---|
| `LAN-001` | `accepted_with_explicit_follow_up` for host/loopback scope only | Final execution verdict in `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md` is `accepted`; Executor and QA artifacts accepted no blocking issues; no Executor production or test-code edits were made; required direct suites passed after the initial non-reproducible `send_chat_message_use_case_test.dart` load failure reran green; `git diff --check` passed | Does not prove physical-device Bonjour/mDNS selection, iOS Local Network prompt behavior, or whole-doc same-WiFi closure; final matrix and durable closure docs remain deferred | Use this as the green LAN-001 prerequisite for planning `LAN-002` when a physical same-WiFi fixture is available; keep `LAN-003` deferred until `LAN-002` evidence is resolved |
| `LAN-002` | `prerequisite-blocked` | Plan verdict in `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-002-plan.md` is `prerequisite-blocked`; visible physical devices alone were not accepted as proof | Missing completed manual same-WiFi fixture or non-interactive physical-device LAN acceptance harness; no accepted evidence yet for same-WiFi/AP isolation, paired accounts, accepted Local Network permission, local-discovery-enabled debug builds, sender-side message-id-tied `local`, receiver-side WiFi/local proof, or negative control | Complete the manual two-phone same-WiFi fixture or add an approved non-interactive physical-device LAN acceptance harness, then execute LAN-002 proof without reopening LAN-001 |
| `LAN-003` | `skipped_due_to_dependency`; not executed | None; no closure, source, matrix, gate, production, or test-code files were updated for LAN-003 | Blocked by unresolved LAN-002 prerequisite; stable final docs must not close same-WiFi reliability while physical-device Bonjour/mDNS proof is absent | Revisit LAN-003 only after LAN-002 records accepted physical-device same-WiFi Bonjour/mDNS evidence |

## Final Program Acceptance Verdict

Final program acceptance verdict: `still_open`

The overall closure bar is not met because real physical-device same-WiFi Bonjour/mDNS proof is still missing. `LAN-001` remains accepted only for host/loopback local-delivery, fallback, media, and aggregate diagnostics proof; it should not be reopened for the external LAN-002 fixture blocker. `LAN-002` is unresolved as `prerequisite-blocked`. `LAN-003` is unresolved as `skipped_due_to_dependency` and was not executed.

- Unresolved session IDs: `LAN-002`, `LAN-003`.
- Blocker class: external fixture / execution prerequisite blocker.
- Exact missing evidence or prerequisite: a completed manual same-WiFi two-device fixture or a non-interactive physical-device LAN acceptance harness that proves same-WiFi/AP isolation, paired accounts, accepted Local Network permission, local-discovery-enabled debug builds, sender-side message-id-tied stored transport `local`, receiver-side WiFi/local proof, and a negative control.
- Next safe action: satisfy the LAN-002 physical-device fixture prerequisite, execute the LAN-002 proof, and only then run LAN-003 closure or matrix documentation work.
- Docs updated in this final acceptance step: this breakdown artifact only.

### LAN-001 Maintenance-Time Closure Notes

- What is now closed: host-verifiable same-WiFi 1:1 local text delivery and sender-side `local` persistence, bounded discover-on-send, stale/absent/disabled/too-slow/non-LAN fallback without false `local`, inbound local WebSocket classification into the WiFi/local bucket, local media receive/persistence/linking mechanics, relay upload fallback preservation, and aggregate privacy-safe LAN diagnostics.
- Tests and gates defining safety: the required direct Flutter suites recorded in the LAN-001 plan passed with `+72`, `+8`, `+53`, `+27`, `+35`, and `+3`; `git diff --check` passed.
- Accepted conditional skips: `flutter test -d macos integration_test/wifi_transport_test.dart`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh baseline`, `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`, and `./scripts/run_test_gates.sh completeness-check` were not run because LAN-001 execution made no production/test-code edits and no gate-classification edits.
- Residual-only for LAN-001: no host/loopback LAN-001 residual remains. The remaining proof is external to LAN-001: `LAN-002` must provide real physical-device Bonjour/mDNS same-WiFi evidence with local discovery enabled.
- Accepted differences: loopback and fake-discovery tests are accepted as LAN-001 transport-mechanics proof, not as mDNS discovery proof; standard simulator runs with `DISABLE_LOCAL_DISCOVERY=true` remain neutral; Local Network permission denial remains a heuristic diagnostic, not an authoritative permission API.
- Reopen rule: reopen `LAN-001` only on a real regression in the accepted host/loopback contracts or their direct test evidence. Do not reopen it merely because `LAN-002` still needs physical-device mDNS proof or `LAN-003` still owns final matrix/closure docs.

## Ordered Session Breakdown

### LAN-001 - Host local-delivery and fallback contract

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-001-plan.md`
- Exact scope: Refresh the current host-side implementation and regressions for same-WiFi 1:1 text, TTL freshness, discover-on-send, non-LAN negative control, local WebSocket receive labeling, local media receive wiring, relay/direct/inbox fallback, and aggregate LAN diagnostics. If the current working-tree implementation is already present, this session should become validation and small repair only, not duplicate feature work.
- Why it is its own session: These seams can be validated deterministically with host and loopback tests. They do not prove real mDNS, and they should not wait for physical-device availability.
- Likely code-entry files:
  - `lib/core/local_discovery/local_discovery_service.dart`
  - `lib/core/local_discovery/bonsoir_discovery_service.dart`
  - `lib/core/local_discovery/local_p2p_service.dart`
  - `lib/core/local_discovery/local_ws_server.dart`
  - `lib/core/local_discovery/local_media_server.dart`
  - `lib/core/services/p2p_service.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/debug/transport_metrics.dart`
  - `lib/main.dart`
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- Likely direct tests/regressions:
  - `test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `test/core/resilience/f1_wifi_relay_fallback_test.dart`
  - `test/core/resilience/f2_transport_switch_recovery_test.dart`
  - `test/core/local_discovery/local_peer_ttl_test.dart`
  - `test/core/local_discovery/local_p2p_service_test.dart`
  - `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`
  - `test/core/local_discovery/local_media_server_test.dart`
  - `test/core/local_discovery/local_media_integration_test.dart`
  - `test/core/services/p2p_service_inbound_transport_test.dart`
  - `test/core/services/p2p_service_local_media_wiring_test.dart`
  - `test/core/services/p2p_service_lan_availability_test.dart`
  - `test/core/services/p2p_service_transport_census_test.dart`
  - `test/core/services/p2p_service_transport_latency_test.dart`
  - `test/core/debug/transport_metrics_test.dart`
  - `test/core/debug/transport_metrics_privacy_test.dart`
  - `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
  - `integration_test/wifi_transport_test.dart` as loopback/device-bound local WS evidence, not real mDNS proof.
- Likely named gates: direct host suites above; `./scripts/run_test_gates.sh 1to1` for shared 1:1 send/media changes; `./scripts/run_test_gates.sh baseline` for Flutter production changes; `./scripts/run_test_gates.sh transport` only if bootstrap, app resume, reconnect, or transport fallback wiring changes; `./scripts/run_test_gates.sh completeness-check` only if gate docs change.
- Matrix/closure docs to update when done: Defer final doc closure to `LAN-003`; only touch `Test-Flight-Improv/test-gate-definitions.md` in this session if a new direct test classification is added.
- Dependency on earlier sessions: None.

### LAN-002 - Real same-WiFi mDNS acceptance proof

- Session classification: `evidence-gated`
- Intended plan file: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-002-plan.md`
- Exact scope: Define and execute the real same-WiFi acceptance proof that host tests cannot provide. Use two physical devices on the same WiFi, debug build, local discovery enabled, and prove that at least one 1:1 text send records sender-side `transport == 'local'` while receiver/diagnostics record the WiFi/local bucket. Include media and fallback probes only if the host contracts from `LAN-001` are green and the device fixture can support them without broadening scope.
- Why it is its own session: Real mDNS discovery is not proven by loopback tests, simulator tests, or TestFlight/release diagnostics. It has a different prerequisite, different evidence bar, and different failure interpretation.
- Likely code-entry files:
  - `lib/core/debug/transport_metrics.dart`
  - `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
  - `integration_test/wifi_transport_test.dart`
  - `integration_test/scripts/run_wifi_relay_fallback_smoke.dart`
  - `reset_simulators.sh`
  - Any narrowly scoped acceptance runbook or debug harness added during planning.
- Likely direct tests/regressions:
  - Re-run the relevant `LAN-001` host suites as a precondition.
  - Physical-device debug same-WiFi acceptance run with local discovery enabled.
  - `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` as companion transport confidence, while documenting that it is not the real mDNS proof.
  - `integration_test/wifi_transport_test.dart` may remain loopback WS/media confidence, not discovery proof.
- Likely named gates: no frozen named gate currently proves true mDNS. Use direct acceptance evidence plus transport gate as companion confidence only.
- Matrix/closure docs to update when done: Record evidence in `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`, `Network-Arch/Transport-Reliability/00-INDEX.md`, and the source doc if the acceptance result changes the rollout state.
- Dependency on earlier sessions: Depends on `LAN-001` host contracts being green or explicitly classified.

### LAN-003 - Closure and matrix update

- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-LAN-003-plan.md`
- Exact scope: Convert landed host evidence and real-device acceptance evidence into stable maintenance documentation. Update existing docs only; do not invent a new matrix.
- Why it is its own session: Closure should happen after implementation and real-device evidence, otherwise the docs can overclaim same-WiFi reliability based on loopback or disabled-discovery simulator runs.
- Likely code-entry files:
  - `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`
  - `Network-Arch/Transport-Reliability/00-INDEX.md`
- Likely direct tests/regressions:
  - Documentation consistency checks by inspection.
  - `./scripts/run_test_gates.sh completeness-check` if `test-gate-definitions.md` is edited.
  - No behavior tests are required for docs-only closure unless this session discovers a stale code claim that reopens `LAN-001` or `LAN-002`.
- Likely named gates: completeness-check only if gate definitions change.
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` for the durable closure claim and residual boundaries.
  - `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md` for 1:1 same-WiFi/mixed-path coverage notes if needed.
  - `Test-Flight-Improv/test-gate-definitions.md` for direct-suite classification only if new files or gate language are introduced.
  - `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md` and `00-INDEX.md` for NET-REL-01 state.
- Dependency on earlier sessions: Depends on `LAN-001` and `LAN-002`.

## Why This Is Not Fewer Sessions

Two sessions would mix host-verifiable behavior with physical-device evidence or would let closure happen before the real mDNS claim is proven. That is unsafe because loopback/local fake discovery can prove transport and media mechanics, but cannot prove Bonjour/mDNS peer selection on an actual same-WiFi network. Closure is also separate because it must preserve the distinction between real mDNS evidence and disabled-discovery simulator runs.

## Why This Is Not More Sessions

The source doc lists many test cases, but the current repo evidence groups them into three meaningful verification seams: host contracts, real-device discovery proof, and closure. Splitting text, TTL, discover-on-send, media, diagnostics, and settings rendering into separate implementation sessions would mostly create bookkeeping because they share the same local-discovery and 1:1 transport contract and can be validated by the same direct host suite family.

## Regression And Gate Contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies the change-based model: direct tests for the edited seam, then named subsystem gates when shared pipelines change.
- `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates.
- `LAN-001` should run direct host tests for local discovery, local WS, local media, P2P service wiring, diagnostics, and 1:1 send/fallback. If production Flutter code changes, run baseline. If shared 1:1 send/media paths change, run `./scripts/run_test_gates.sh 1to1`. If bootstrap, resume, reconnect, or transport fallback wiring changes, run `./scripts/run_test_gates.sh transport`.
- `LAN-002` must not treat simulator `wifi=0` as failure evidence because `reset_simulators.sh` sets `DISABLE_LOCAL_DISCOVERY=true`. Real mDNS proof requires local discovery enabled on physical devices.
- `LAN-003` should run `./scripts/run_test_gates.sh completeness-check` only when gate definitions are edited.

## Matrix Update Contract

Use existing stable docs:

- Primary closure doc: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- Primary matrix doc: `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
- Gate classification doc: `Test-Flight-Improv/test-gate-definitions.md`
- NET-REL tracking docs: `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md` and `Network-Arch/Transport-Reliability/00-INDEX.md`

`LAN-003` owns the final doc updates. `LAN-001` may make only narrow gate-classification edits if it adds or reclassifies tests. `LAN-002` records acceptance evidence in NET-REL docs, then `LAN-003` converts that evidence into closure language.

## Downstream Execution Path

For each session:

- `LAN-001` is resolved as `accepted_with_explicit_follow_up` for host/loopback proof only; do not reopen it for the `LAN-002` external fixture blocker.
- `LAN-002` remains `prerequisite-blocked`; the next safe action is to satisfy the manual same-WiFi physical-device fixture or provide an approved non-interactive physical-device LAN acceptance harness before execution.
- `LAN-003` is `skipped_due_to_dependency` and must not run closure, source, matrix, or gate-document updates while `LAN-002` lacks accepted physical-device same-WiFi Bonjour/mDNS evidence.

## Reviewer Result

- Recommended session count: sufficient.
- Proposed sessions to merge: none.
- Proposed sessions that must split: none.
- Missing tests or named gates: no frozen named gate proves real mDNS; that is intentionally assigned to `LAN-002` as direct acceptance evidence.
- Meaningful verified state: yes. `LAN-001` ends with host green local/fallback/media/diagnostics contracts, `LAN-002` ends with device acceptance evidence or an explicit prerequisite block, and `LAN-003` ends with stable closure docs.
- Matrix-update responsibility: clearly assigned to `LAN-003`.
- Minimum safe session set: 3.

## Structural Blockers Remaining

None for decomposition.

`LAN-002` has an execution prerequisite: two physical devices on the same WiFi, debug build, and local discovery enabled. That is not a decomposition blocker; it is the reason the session is evidence-gated and initially prerequisite-blocked.

## Accepted Differences Intentionally Left Unchanged

- No group messaging, NAT traversal, DCUtR, relay springboard, or cross-network direct-delivery policy is included.
- No decision is made here about encrypting LAN WebSocket metadata or adding a local routing-layer identity challenge.
- No promise is made that standard simulator runs prove mDNS behavior.
- No TestFlight/release diagnostics claim is made for the debug-only transport diagnostics card.
- Local Network permission handling remains a suspected-denial heuristic, not an authoritative iOS permission API.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/49-lan-wifi-delivery-reliability.md`
- `Network-Arch/Transport-Reliability/01-lan-wifi-reliability.md`
- `Network-Arch/Transport-Reliability/00-INDEX.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
- `lib/main.dart`
- `lib/core/debug/e2e_test_mode.dart`
- `lib/core/debug/transport_metrics.dart`
- `lib/core/local_discovery/local_discovery_service.dart`
- `lib/core/local_discovery/bonsoir_discovery_service.dart`
- `lib/core/local_discovery/disabled_local_discovery_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/settings/presentation/widgets/settings_transport_diagnostics_card.dart`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- `reset_simulators.sh`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `test/core/resilience/f1_wifi_relay_fallback_test.dart`
- `test/core/resilience/f2_transport_switch_recovery_test.dart`
- `test/core/local_discovery/local_peer_ttl_test.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`
- `test/core/local_discovery/local_media_server_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_local_media_wiring_test.dart`
- `test/core/services/p2p_service_lan_availability_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_transport_latency_test.dart`
- `test/core/debug/transport_metrics_test.dart`
- `test/core/debug/transport_metrics_privacy_test.dart`
- `test/features/settings/presentation/widgets/settings_transport_diagnostics_card_test.dart`
- `integration_test/wifi_transport_test.dart`
- `git status --short`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

The split follows actual seams in the current repo instead of mirroring every test case in the source doc. Host-verifiable behavior is isolated from real-device mDNS proof, and closure is held until both evidence classes are resolved. All intended plan paths are doc-scoped under `Test-Flight-Improv/49-lan-wifi-delivery-reliability-session-<session-id>-plan.md`, so downstream planning cannot collide with generic shared `session-<id>-plan.md` files.
