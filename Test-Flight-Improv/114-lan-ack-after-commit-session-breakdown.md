# 114 LAN Ack After Commit Session Breakdown

## recommended plan count

Recommended plan count: 5.

## decomposition artifact

- Artifact path: `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md`
- Proposal/source doc path: `Test-Flight-Improv/114-lan-ack-after-commit.md`
- Downstream workflow rule: detailed planning happens one session at a time; later sessions must be refreshed against landed code before execution.
- Active run assumption: standard rollout mode. This doc is not a row-owned matrix gap closure, but its closure session must update the source doc review/closure logs and existing gate inventory docs with concrete evidence.

## Run Mode Snapshot

- Active mode: `standard`.
- Degraded local continuation explicitly allowed: no.
- Source proposal, matrix, or closure doc path: `Test-Flight-Improv/114-lan-ack-after-commit.md`.
- Source row/status vocabulary: doc-scoped phase/session status with `pending`, `accepted`, `accepted_with_explicit_follow_up`, `stale/already-covered`, `skipped_due_to_dependency`, `blocked`, and final program verdicts `closed`, `accepted_with_explicit_follow_up`, `residual_only`, `still_open`.
- Overall closure bar: LAN WebSocket 1:1 text ack is committed only after durable receiver staging; rejected or legacy LAN acks never mint `delivered/local`; retry, quarantine, sticky transport, host coverage, and residual device evidence are recorded truthfully.
- Final verdict policy: persist exactly one final program verdict in this breakdown after all runnable sessions are resolved; use `still_open` if any required session remains blocked, any required closure result is missing, or the closure bar is unmet.
- Graph maintenance rule for remaining sessions: use `graphify-arch` only for exact-symbol queries. Do not run `graphify update` or extraction from inside `graphify-arch`. After code changes, rebuild the architecture graph from the repo root with `./graphify-arch/refresh_arch_graph.sh`; if `uv tool upgrade graphifyy` occurs, remove `graphify-out/cache/ast` before any rebuild.

## Closure Progress

- 2026-06-13T06:32:35Z - S3 closure audit started. Scope is doc 114 S3 only; do not plan, execute, close, or edit S4/S5 or docs 115/116. Files inspected so far: closure skill, `Test-Flight-Improv/114-lan-ack-after-commit-session-S3-plan.md`, `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md`, and `Test-Flight-Improv/114-lan-ack-after-commit.md`. Next action: reconcile the S3 ledger against the final S3 plan verdict and residual evidence.
- 2026-06-13T06:33:34Z - S3 closure audit completed. Reconciled the S3 ledger, preserved host implementation acceptance and passed host gates, recorded the then-current simulator residual for command `16`, and preserved the doc 115 P3 retry-unacked focused failures as outside S3. Reviewer outcome: no overclaiming found; S4/S5 remain pending and parent pipeline may advance to S4. This simulator residual was superseded by the final command-16 pass below.
- 2026-06-13T06:35:46Z - S4 closure audit completed. Reconciled the S4 plan verdict and host evidence: new real-loopback durable ack integration test, local-discovery sweep, `1to1`, completeness, diff hygiene, and architecture graph refresh all passed. Preserved simulator/device-only proof as S5 residual because the available wrapper found no runnable `wifi_relay_fallback_smoke_test.dart` command for the requested selector.
- 2026-06-13T06:38:30Z - S5 closure audit completed. Updated source doc status, review-resolution log, closure log, amendment log, and gate inventory notes. The then-current doc 114 verdict preserved host implementation/gate acceptance while leaving shared gate-array promotion, device/mDNS/mixed-version proof, and simulator smoke proof for later re-audit.
- 2026-06-13T14:33:00Z - Whole-doc closure re-audit completed before the final command-16 fix. Doc 116 had completed the coordinated 114/115/116 gate-array edit and doc 115 P3 was accepted/closed; physical Evidence bar items 2-9 were still unclaimed. The final re-audit below supersedes the simulator-smoke portion of this note.
- 2026-06-13T15:07:40Z - Final closure re-audit completed. The command-16 simulator residual is resolved: the Wi-Fi relay fallback smoke harness now applies migrations 075/077, uses DB version 77, accepts truthful `inboxed` fallback statuses, and `./scripts/run_reliability_simulations.sh 1to1 --only 16` passed S1-S4 at 4/4. The final verdict is normalized to `residual_only`: implementation, host gates, and simulator proof are closed; physical device/mDNS/mixed-version evidence is archived as unclaimed external lab residual evidence, not an implementation follow-up.

## overall closure bar

Doc 114 is closed only when the LAN WebSocket 1:1 text path has stage-before-ack parity with the direct deferred-ack path: a committed LAN ack is written only after receiver-side durable staging, legacy or rejected LAN acks never mint `delivered/local`, retry and quarantine dispositions survive process failure through `inbox_staging`, sticky local transport is trained only by committed LAN acks, and the new host and gate coverage proves the loss windows and version-skew cells named in the source doc. Any device-only evidence that cannot be collected in this host rollout must be recorded as an explicit residual or fixture blocker, not implied closed.

## source of truth

- `Test-Flight-Improv/114-lan-ack-after-commit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/111-one-to-one-p0-silent-message-loss-test-inventory.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `Test-Flight-Improv/115-relay-inbox-custody.md` for the `inboxed` status prerequisite
- `Test-Flight-Improv/116-edit-retry-fidelity.md` for the edit retry/idempotency prerequisite
- Current repo evidence found during decomposition: `lib/core/database/migrations/077_message_relay_custody.dart`, `lib/features/conversation/application/handle_delivery_receipt_use_case.dart`, `lib/features/conversation/application/retry_failed_messages_use_case.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, and related 115/116 tests already contain `inboxed`, `deriveRetryAction`, downgrade-block, single-flight, and receipt machinery.
- Likely doc 114 implementation entry files: `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/lan_ack.dart`, `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/main.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`.
- Likely direct tests: `test/core/local_discovery/local_ws_server_test.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_fault_injection_test.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`, `test/features/conversation/application/pending_message_retrier_test.dart`, and the new `test/core/local_discovery/local_ws_durable_ack_integration_test.dart`.

## session ledger

| session id | title | classification | intended plan file | depends on | initial status |
|---|---|---|---|---|---|
| S1 | Local WebSocket committed-ack protocol seam | implementation-ready | `Test-Flight-Improv/114-lan-ack-after-commit-session-S1-plan.md` | none | accepted / closed for S1 |
| S2 | P2PService durable LAN intake and replay dispositions | implementation-ready | `Test-Flight-Improv/114-lan-ack-after-commit-session-S2-plan.md` | S1 | accepted / closed for S2 |
| S3 | Sender durable LAN ack policy and sticky transport truthfulness | implementation-ready | `Test-Flight-Improv/114-lan-ack-after-commit-session-S3-plan.md` | S1, S2, verified 115 P1 and 116 P1-P2 repo evidence | accepted / closed for S3 host implementation |
| S4 | Host loopback integration, version skew, and loss-window pins | implementation-ready | `Test-Flight-Improv/114-lan-ack-after-commit-session-S4-plan.md` | S1, S2, S3 | accepted / closed for S4 host integration |
| S5 | Gate capture, integration assertion sweep, and doc closure | closure-only | `Test-Flight-Improv/114-lan-ack-after-commit-session-S5-plan.md` | S4 | residual_only / closed for doc 114 implementation |

## ordered session breakdown

### S1 - Local WebSocket committed-ack protocol seam

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/114-lan-ack-after-commit-session-S1-plan.md`
- Exact scope: add the LAN ack contract types and the `LocalWsServer` receive/send protocol seam. A configured inbound chat commit handler must withhold ack until the handler returns committed, write explicit nacks for rejection/timeout, avoid broadcast emission for handled chat, preserve byte-compatible legacy parse-time ack behavior when no handler is configured, and classify outbound acks as committed, legacy, or failed.
- Why it is its own session: this is the wire/protocol foundation for every later receiver and sender change and is fully testable in `local_discovery` without touching the broader P2P service or conversation send policy.
- Likely code-entry files: `lib/core/local_discovery/lan_ack.dart`, `lib/core/local_discovery/local_ws_server.dart`, possibly `lib/core/local_discovery/local_p2p_service.dart` only for compile-facing imports if needed.
- Likely direct tests/regressions: `test/core/local_discovery/local_ws_server_test.dart`, plus any local-discovery fake adjustments needed for compile.
- Likely named gates: `flutter test test/core/local_discovery`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: source doc review-resolution log if behavior differs from the plan; final closure log is owned by S5.
- Dependency on earlier sessions: none.
- Closure status: `accepted` / `closed for S1 only`; do not treat this as final doc 114 closure.
- Closure evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S1-plan.md` contains `## Execution Verdict` with `Verdict: accepted.`
- Passed verification recorded in the S1 plan: `flutter test test/core/local_discovery/local_ws_server_test.dart`; `flutter test test/core/local_discovery`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check`; `graphify update .`.
- S1 closed scope: `lan_ack.dart`, `LocalWsServer`, and local-discovery test updates only. S2-S5 remain pending for durable receiver staging/replay, sender ack policy, host integration/version-skew, gate capture, and final source-doc closure.
- Controller graph note: S1's recorded `graphify update .` evidence happened before the controller rule was corrected. Future doc 114 sessions must use `./graphify-arch/refresh_arch_graph.sh` from repo root after code changes.

### S2 - P2PService durable LAN intake and replay dispositions

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/114-lan-ack-after-commit-session-S2-plan.md`
- Exact scope: wire the S1 commit handler through `LocalP2PService` into `P2PServiceImpl`; implement receiver-side migration gate before staging; stage chat envelopes into `inbox_staging` with `lan:<nonce>` entry ids; replay through the existing recovered-inbox disposition machinery; keep live LAN notifications unsuppressed through a live replay callback; reject or fall back truthfully on staging errors; preserve inbound transport telemetry.
- Why it is its own session: this owns durable receiver custody and loss windows W1/W2/W3/W5, using different files and tests than S1. It can land while sender status/backstop policy is still unchanged.
- Likely code-entry files: `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/main.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`.
- Likely direct tests/regressions: `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_fault_injection_test.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, and targeted local-discovery tests from S1 if compile surfaces overlap.
- Likely named gates: `flutter test test/core/services test/core/local_discovery`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: source doc review-resolution log if the origin-marker contract is already covered by 115; final gate/docs classification is S5.
- Dependency on earlier sessions: S1.
- Closure status: `accepted` / `closed for S2 only`; do not treat this as final doc 114 closure.
- Closure evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S2-plan.md` contains `## Execution Verdict` with `Verdict: accepted.`
- S2 closed scope: `LocalP2PService.configureInboundChatCommitHandler`, receiver-side `P2PServiceImpl` LAN commit staging/replay, live LAN replay callback wiring, `ChatMessageListener` `stagedEntryId` forwarding, S2 direct tests, and mechanical replay-callback signature updates in `test/performance/benchmark_inbox_delivery_timing_test.dart` only.
- Passed verification recorded in the S2 plan: focused S2 test command covering local P2P, P2P service, fault injection, inbound transport, chat listener, and incoming chat use-case tests; `flutter test test/core/services test/core/local_discovery`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check` (`840/840`); targeted production and benchmark `dart analyze`; scoped `git diff --check`; `./graphify-arch/refresh_arch_graph.sh`.
- S2 accepted differences: host receiver-side closure only; real loopback, device, mixed-version, gate capture, and final source-doc closure remain S4/S5 work. Sender durable ack policy, sticky transport truthfulness, and `DurableLanSender` remain S3 work.
- Controller closure note: spawned S2 closure attempt produced no trustworthy ledger update under bounded waits, so the controller used the single allowed current-session local closure fallback to persist this S2 ledger/section update.
- Future-session graph note: continue using `graphify-arch` only for exact-symbol queries. After code changes, use `./graphify-arch/refresh_arch_graph.sh` from repo root; do not run `graphify update` or extraction inside `graphify-arch`. If `uv tool upgrade graphifyy` occurs, remove `graphify-out/cache/ast` before rebuild.

### S3 - Sender durable LAN ack policy and sticky transport truthfulness

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/114-lan-ack-after-commit-session-S3-plan.md`
- Exact scope: add the opt-in `DurableLanSender` capability and detailed local send path; map only `LanSendAck.committed` to acknowledged local success; treat legacy/bool local acks as non-durable so the existing backstop persists `inboxed` or truthful `sent` with `wireEnvelope`; prevent legacy acks from training sticky `local`; remove the Go-channel reuse mislabel that preserves `local` over actual direct/relay transport.
- Why it is its own session: this changes sender truthfulness, retry visibility, sticky routing, and conversation application tests. It depends on S1's ack classification and S2's committed receiver custody, and it must refresh against the already-landed 115/116 code in this worktree before planning.
- Likely code-entry files: `lib/core/services/p2p_service.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, shared or in-file P2P fakes.
- Likely direct tests/regressions: `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`, `test/features/conversation/application/pending_message_retrier_test.dart`, plus LAN availability/census/inbound transport tests if assertions pin old bool-ack or reuse-label semantics.
- Likely named gates: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`; retry trio above; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: source doc review-resolution log if any mixed-version tradeoff or census behavior differs from the plan; S5 owns final docs.
- Dependency on earlier sessions: S1 and S2; planner must verify 115 P1 `inboxed` foundation and 116 P1-P2 retry-fidelity floor remain present in current code/tests before execution.
- Closure status: `accepted` / `closed for S3 host implementation only`; do not treat this as final doc 114 closure.
- Closure evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S3-plan.md` now contains `## Execution Verdict` with `Verdict: accepted.`
- S3 closed scope: opt-in `DurableLanSender`, detailed LAN send ack path, committed-only local delivered/sticky behavior, legacy/bool local ack inbox/retry backstop, truthful Go reuse transport labeling, S3 sender/local/core tests, and the S3-owned stale `WIFI-INTERRUPTED-VOICE` integration expectation update.
- Passed verification recorded in the S3 plan: focused sender/P2P/local-discovery/core tests; focused `WIFI-INTERRUPTED-VOICE` integration slice; `./scripts/run_test_gates.sh 1to1` (`+593`); `./scripts/run_test_gates.sh completeness-check` (`840/840`); targeted `dart analyze` with only info-level notes; scoped `git diff --check`; `./graphify-arch/refresh_arch_graph.sh`.
- S3 simulator residual resolution: the original command-discovery/schema issue is closed by the final 2026-06-13 pass. Command `./scripts/run_reliability_simulations.sh 1to1 --only 16` now reaches LAN/fallback behavior and passes S1-S4 after the harness applies migrations 075/077 and uses DB version 77.
- S3 outside-scope failures preserved: the retry-focused trio still has pre-existing doc 115 P3 retry-unacked failures outside S3 scope; do not fix or reopen them under doc 114 S3.
- S3 accepted differences: host implementation closure is accepted while physical device and mixed-version lab evidence remains archived as unclaimed residual evidence.
- Controller closure note: spawned S3 execution stalled after partial progress, so the controller used the single bounded current-session local fallback to finish validation, apply the narrow stale expectation fix, persist the S3 execution verdict, and close this ledger entry.

### S4 - Host loopback integration, version skew, and loss-window pins

- Session classification: `implementation-ready`
- Intended plan file: `Test-Flight-Improv/114-lan-ack-after-commit-session-S4-plan.md`
- Exact scope: add the host-runnable real loopback WebSocket integration file over a real staging DB; prove post-ack receiver-kill recovery, decrypt-failure quarantine, old-sender committed ack compatibility, new-sender legacy ack classification, rejecting receiver nack behavior, old matcher skip-nack timeout behavior, and the media-bearing LAN replay non-silent-loss contract where host-testable.
- Why it is its own session: these tests compose the prior three implementation seams and may expose integration-only wiring gaps. They also require a device/relay proof profile because the source doc carries device-only evidence requirements that host tests cannot fully close.
- Likely code-entry files: `test/core/local_discovery/local_ws_durable_ack_integration_test.dart`, test helpers around staging DB setup, and only the production files from S1-S3 if integration exposes a real bug.
- Likely direct tests/regressions: `flutter test test/core/local_discovery`; focused new integration file; possibly `test/core/database/helpers/inbox_staging_db_helpers_test.dart` if an entry-id assumption is discovered.
- Likely named gates: `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check`; device evidence profile for `integration_test/wifi_transport_test.dart`, `integration_test/wifi_relay_fallback_smoke_test.dart`, and `dart run integration_test/scripts/run_transport_e2e.dart -d <simulator-id>` as required closure evidence or explicit residual/blocker.
- Matrix/closure docs to update when done: source doc evidence bar and closure log via S5; gate docs via S5.
- Dependency on earlier sessions: S1, S2, S3.
- Closure status: `accepted` / `closed for S4 host integration only`; do not treat this as final doc 114 closure.
- Closure evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S4-plan.md` contains `## Execution Verdict` with `Verdict: accepted.`
- S4 closed scope: `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` host-runnable loopback coverage over real `LocalWsServer` frames and a real `sqflite_common_ffi` staging DB. No production code changes were needed in S4.
- Passed verification recorded in the S4 plan: focused new integration test plus targeted analyzer; `flutter test test/core/local_discovery` (`+118`); `./scripts/run_test_gates.sh 1to1` (`+593`); `./scripts/run_test_gates.sh completeness-check` (`841/841`); `git diff --check`; `./graphify-arch/refresh_arch_graph.sh`.
- S4 accepted residuals: the earlier simulator command-discovery issue is closed by the final command-16 pass. Device-only/mDNS/mixed-version proof remains external lab residual evidence.

### S5 - Gate capture, integration assertion sweep, and doc closure

- Session classification: `closure-only`
- Intended plan file: `Test-Flight-Improv/114-lan-ack-after-commit-session-S5-plan.md`
- Exact scope: classify new/extended tests in `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` if this doc is the final owner of the coordinated 1:1 gate edit; sweep `integration_test/` for delivered-on-parse-ack or bool-LAN-ack assertions and record changed expectations; run final host gates and regression sanity available in this environment; update doc 114 review-resolution and closure logs with exact evidence, residual device blockers, and final verdict.
- Why it is its own session: this is process and closure work spanning docs, gate arrays, and evidence logs after code has landed. It should not be mixed into implementation sessions where code/test fixes still churn.
- Likely code-entry files: `Test-Flight-Improv/114-lan-ack-after-commit.md`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, relevant `integration_test/` files if assertions are updated.
- Likely direct tests/regressions: final sweep named in the source doc: `flutter test test/core/local_discovery`, `flutter test test/core/services`, `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`, `flutter test test/features/conversation/integration/`, `./scripts/run_test_gates.sh 1to1`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, `./scripts/run_test_gates.sh completeness-check`, `(cd go-mknoon && make test)`, `(cd go-relay-server && go test ./...)`, with unavailable device-only evidence recorded honestly.
- Likely named gates: final 1:1, baseline, completeness, Go regression sanity.
- Matrix/closure docs to update when done: source doc review-resolution log, closure log, test gate definitions, and script gate arrays where this doc owns the coordinated edit.
- Dependency on earlier sessions: S4.
- Closure status: `residual_only` / `closed for doc 114 implementation`; do not claim physical device-lab proof.
- Closure evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S5-plan.md` now contains `Verdict: residual_only.`
- S5 closed scope: updated `Test-Flight-Improv/114-lan-ack-after-commit.md` status, review-resolution log, closure log, amendment log, and graphify guidance; added `Test-Flight-Improv/test-gate-definitions.md` 114 gate-capture notes. A later closure re-audit verified that doc 116 completed the shared frozen `1to1` gate-array edit, so this is no longer a doc-114 residual.
- S5 residual archive: device/mDNS/mixed-version evidence was not collected in this shell and remains unclaimed. The simulator residual is closed: command `16` is selectable and passed after the DB-version/migration and `inboxed` expectation fixes.

## why this is not fewer sessions

The work spans five different closure bars: WS protocol semantics, receiver durable staging and replay, sender status/backstop/sticky behavior, real-socket integration/version skew, and gate/documentation closure. Collapsing these would make failures hard to localize and would mix independent test families (`local_discovery`, `core/services`, conversation application, host integration, and process gates). S3 also has explicit cross-doc prerequisites that should be checked at planning time rather than bundled into S1/S2.

## why this is not more sessions

The source doc has many RED tests, but most cluster around five coherent seams. Splitting every loss window, skew cell, or test file into its own session would create bookkeeping overhead and increase the chance of partial, misleading states. S1 and S2 already isolate the risky receiver split; S3 owns all sender policy because the same fake and `_tryLocalSend`/`_persistOutgoingSendResult` regions must be updated together; S4 owns composed integration evidence; S5 owns closure.

## regression and gate contract

`Test-Flight-Improv/14-regression-test-strategy.md` and `Test-Flight-Improv/test-gate-definitions.md` require the 1:1 Reliability Gate for shared 1:1 send, retry, listener, inbox, decrypt, and transport changes. Each implementation session must run the focused host tests it directly changes before widening to `./scripts/run_test_gates.sh 1to1`. `completeness-check` must stay green whenever new test files are introduced or gate classifications change. Device-only LAN/mDNS, notification, and mixed-version evidence must be represented in the S4/S5 device proof profile and recorded as residual or blocker when unavailable.

## matrix update contract

Do not create a new matrix doc. Reuse and update:

- `Test-Flight-Improv/114-lan-ack-after-commit.md` review-resolution and closure logs for this rollout's exact evidence and residuals.
- `Test-Flight-Improv/test-gate-definitions.md` for the 114 gate capture section and 1:1 Reliability Gate file list if this rollout owns the coordinated edit.
- `scripts/run_test_gates.sh` for the same 1:1 gate array only when S5 verifies that this doc is the correct coordinated owner.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` only if S5 needs to update the stable 1:1 closure reference with the new LAN ack-after-commit invariant.

## downstream execution path

For each session, run the downstream sequence in this order:

1. `$implementation-plan-orchestrator`
2. `$implementation-execution-qa-orchestrator`
3. `$implementation-closure-audit-orchestrator`

After S5, run one final whole-doc acceptance/closure pass and persist one of the allowed final program verdicts in this breakdown artifact: `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`.

## final program verdict

Verdict: `residual_only`.

Doc 114 implementation is closed. The LAN ack-after-commit protocol, receiver staging/replay, sender truthfulness, sticky transport policy, and host loopback loss-window/version-skew pins are implemented and covered by focused host tests plus `1to1` and completeness gates.

The final expanded three-doc `./scripts/run_test_gates.sh 1to1` rerun passed
with `+793` on 2026-06-13 after the bridge timeout test was made deterministic
and the send-then-lock 7c expectation was aligned with Doc 115 receipt-gated
custody semantics.

The simulator smoke proof is closed by `./scripts/run_reliability_simulations.sh
1to1 --only 16`, which passed S1-S4 at 4/4 on 2026-06-13 after the integration
harness was aligned with DB version 77 and truthful `inboxed` fallback statuses.
Physical device/mDNS/mixed-version evidence is archived as unclaimed residual
lab evidence, not an open implementation item. The previous doc 115 P3
retry-unacked note and coordinated frozen `1to1` script-array handoff are
stale/resolved: doc 115 records P3 accepted/closed, and doc 116 completed the
public gate doc plus `scripts/run_test_gates.sh` array edit.

## structural blockers remaining

No decomposition structural blocker remains. S3 must verify 115 Phase 1 and 116 Phases 1-2 from current code/tests before execution. S4/S5 device-only evidence may become an external-fixture blocker if the required devices, mixed-version builds, notification permissions, or router blackhole setup are unavailable.

## accepted differences intentionally left unchanged

- The doc order requested by the user starts with 114 even though the source program text says 115 is the program foundation. Current repo evidence already contains the 115 `inboxed` foundation and 116 retry-fidelity machinery, so this decomposition keeps 114 runnable while making S3 verify those prerequisites before sender execution.
- No Go or relay implementation session is created for doc 114 because the source doc explicitly says the fix is Dart-side and Go/relay paths are parity models, not owners.
- Device-only evidence remains represented as proof-profile work in S4/S5 rather than split into a separate device-lab implementation session.

## exact docs/files used as evidence

- `Test-Flight-Improv/114-lan-ack-after-commit.md`
- `Test-Flight-Improv/115-relay-inbox-custody.md`
- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/111-one-to-one-p0-silent-message-loss-test-inventory.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `scripts/run_test_gates.sh`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `test/core/local_discovery/local_ws_server_test.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`

## why the decomposition is safe to send into downstream planning/execution

Each session has a doc-scoped plan path, an exact implementation or closure seam, concrete likely owner files, focused direct tests, named gate expectations, and explicit dependencies. The split preserves the source doc's cross-plan prerequisites without forcing docs 115/116 into the same controller context, and it leaves device-only proof as a later profile/blocker decision instead of overclaiming host coverage.
