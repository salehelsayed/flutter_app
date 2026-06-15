# 114 LAN Ack After Commit - Session S2 Plan

Status: execution-ready

## Planning Progress

- 2026-06-13T05:21:05Z - Arbiter completed. Files inspected since last update: revised S2 plan. Decision/blocker: no structural blockers remain; simulator/device proof is accepted as doc-level residual for S4/S5, not S2 host closure. Next action: S2 may proceed to execution under this plan.
- 2026-06-13T05:20:46Z - Reviewer completed; Arbiter started. Files inspected since last update: full S2 draft plan and S2 source/test evidence. Decision/blocker: sufficient with one structural tightening around replay callback shape; patched by making `stagedEntryId` explicit in callback signatures. Next action: arbiter classification and final execution-ready verdict.
- 2026-06-13T05:20:31Z - Planner completed; Reviewer started. Files inspected since last update: full draft plan. Decision/blocker: draft includes mandatory sections, owner files, S2 checklist mapping, tests/gates, non-goals, rollback/blocker rules, and dirty-worktree handling. Next action: reviewer sufficiency pass.
- 2026-06-13T05:16:58Z - Planner started. Files inspected since last update: graphify-arch query for `P2PServiceImpl _shouldDurablyStageDeferredDirectChat inbox_staging _applyRecoveredInboxOutcome LocalP2PService LAN staged chat`, source doc Phase 2, S1 plan, S1 closure ledger in breakdown, `local_p2p_service.dart`, `p2p_service_impl.dart`, `main.dart`, `fake_local_p2p_service.dart`, direct tests, staging repository/fakes, receipt origin helper, gate docs/scripts. Decision/blocker: S2 is implementable against current S1 surface; no S3-S5 planning allowed. Next action: draft execution-ready S2 plan sections.
- 2026-06-13T05:14:59Z - Evidence Collector started. Files inspected since last update: `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`, `.agents/skills/graphify/SKILL.md`, `.agents/skills/graphify/references/query.md`, `git status --short`, existing S2 plan path check. Decision/blocker: S2 artifact did not exist; broad pre-existing worktree dirt confirmed, including S1/source/breakdown docs. Next action: collect graph, doc, code, and direct-test evidence for S2 only.

## Real Scope

S2 wires the S1 LAN commit-handler seam into the receiver-side P2P service path only:

- Add `LocalP2PService.configureInboundChatCommitHandler(...)` as a passthrough to `LocalWsServer.configureInboundChatCommitHandler(...)`.
- Configure that handler from `P2PServiceImpl` when a `LocalP2PService` is present.
- Implement `P2PServiceImpl._commitInboundLanChatMessage(...)` so a LAN chat commit runs the account-migration gate before staging, stages chat envelopes into `inbox_staging` as `lan:<nonce>`, returns committed only after staging succeeds, replays through the existing recovered-inbox disposition machinery, and emits LAN-specific flow events.
- Preserve inbound LAN transport telemetry (`TransportMetrics.recordTransport('wifi')` and `MSG_RECEIVED_TRANSPORT`) even though handled LAN messages no longer flow through `localMessageStream`.
- Add a live LAN replay callback so live LAN replay uses unsuppressed notification behavior while recovered replay can keep recovery suppression.
- Thread the staged entry id into recovered/live replay so existing delivery-receipt origin discrimination can see `direct:` and `lan:` prefixes.
- Update the single `LocalP2PService` implements fake and direct tests needed for the receiver path.

S2 does not change sender status/backstop policy, does not add `DurableLanSender`, does not add `sendMessageDetailed`, does not change sticky transport training or Go transport labels, does not add the S4 host loopback integration file, and does not update docs 115/116, final gate arrays, source closure logs, or S3-S5 plans.

## Closure Bar

S2 is closed when the receiver-side LAN commit path has host-test proof for every listed S2 requirement:

| S2 requirement | Planned proof |
|---|---|
| Wire S1 commit handler through `LocalP2PService` into `P2PServiceImpl` | `local_p2p_service_test.dart` proves the passthrough reaches `LocalWsServer`; `p2p_service_impl_test.dart` proves `FakeLocalP2PService` captures a handler when `P2PServiceImpl` is constructed. |
| Migration gate before staging | `p2p_service_impl_test.dart` invokes the captured handler with a LAN chat and a gate closure returning false; expects `LanInboundDecision.rejected('account_migration_blocked')`, no staged row, no `messageStream` emission, and `ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED`. |
| Stage chat envelopes as `lan:<nonce>` before committed decision | `p2p_service_impl_test.dart` invokes the handler with nonce `n1`; the repo contains `lan:n1` before the handler returns committed, then committed replay deletes it. |
| Replay through recovered-inbox disposition machinery | LAN tests cover committed delete, retryable mark, rejected mark, and quarantined mark using `_applyRecoveredInboxOutcome` LAN event names. |
| Live LAN notifications unsuppressed | `p2p_service_impl_test.dart` proves live handler replay uses `replayLiveLanChatMessage` when provided and falls back to recovered replay only when absent; `main.dart` wires the live callback with `suppressNotification:false`. |
| Reject or fall back truthfully on staging errors | `p2p_service_fault_injection_test.dart` uses a stage-throwing repo; expects `LanInboundDecision.rejected('staging_error')`, `P2P_SERVICE_LAN_STAGE_ERROR`, and receiver in-memory emission for loss-free fallback. |
| Preserve inbound transport telemetry | `p2p_service_inbound_transport_test.dart` or the LAN handler tests assert `wifi` metrics and `MSG_RECEIVED_TRANSPORT` still fire for handled LAN commits. |
| Preserve receipt-origin contract | Existing `shouldMintDeliveryReceipt` skips `direct:` and `lan:`; S2 tests prove `stagedEntryId` is passed through replay callbacks so main/listener wiring can actually apply that contract. |

S2 closure is session-level host closure only. Final doc 114 closure still requires later S4/S5 real loopback, mixed-version, device, and evidence capture. Do not claim final LAN end-to-end closure from S2 host tests alone.

## Source Of Truth

- Active session scope: `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md`, S2 only. The breakdown records S1 as accepted/closed for S1 only; S2 remains pending.
- Detailed S2 design/test contract: `Test-Flight-Improv/114-lan-ack-after-commit.md`, Phase 2.
- S1 evidence: `Test-Flight-Improv/114-lan-ack-after-commit-session-S1-plan.md`, plus current S1 code surface (`lan_ack.dart`, `LocalWsServer.configureInboundChatCommitHandler`, `sendMessageWithAck`).
- Current implementation wins over stale prose: `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/main.dart`, `lib/features/conversation/application/chat_message_listener.dart`, and tests under `test/core/services/` and `test/core/local_discovery/`.
- Gate source of truth: `scripts/run_test_gates.sh` wins over gate prose if they differ; `test-gate-definitions.md` supplies classification policy.
- Existing doc-115 receipt-origin code is evidence only, not S2 doc scope: `send_delivery_receipt_use_case.dart` already treats `direct:` and `lan:` as non-receipt origins; S2 must not edit or decompose docs 115/116.
- Worktree hygiene: S1 files and the source/breakdown docs are untracked/dirty, and there is broad pre-existing worktree dirt across Flutter, Go, relay, platform, and docs files. S2 implementers must preserve all non-S2 changes and limit intentional edits to the owner files below.
- Graph maintenance: use `graphify-arch` only for exact-symbol queries. Do not run `graphify update` or extraction from inside `graphify-arch`. After S2 code changes, rebuild the architecture graph from the repo root with `./graphify-arch/refresh_arch_graph.sh`; if `uv tool upgrade graphifyy` occurs, remove `graphify-out/cache/ast` before any rebuild.

## Session Classification

`implementation-ready`.

The S1 protocol surface required by S2 is present in the current tree. The only session-level evidence gap is implementation/test work, not missing design input. Simulator/device evidence remains a later doc-level requirement owned by S4/S5 and must not be treated as closed by this session.

## Exact Problem Statement

Today `P2PServiceImpl` still merges LAN text through `_localP2P.localMessageStream`. With S1's configured handler path, handled chat messages are deliberately not broadcast by `LocalWsServer`, so no receiver-side durable LAN commit will happen unless `P2PServiceImpl` configures the handler directly. The current LAN `ChatMessage` path also has no nonce-derived staging id, so `_shouldDurablyStageDeferredDirectChat` remains false and no `inbox_staging` row is created for LAN.

S2 must make the receiver commit decision truthful: a LAN sender gets a committed ack only after the receiver has passed the migration gate and durably staged `lan:<nonce>`. Replay outcomes must reuse the existing recovered-inbox disposition machinery so decrypt deferral stays retryable, decrypt failure is quarantined, committed replay deletes the row, and errors do not silently drop the only copy. Live LAN replay must keep notification behavior equivalent to the old in-memory LAN path.

## Files And Repos To Inspect Next

Production owner files:

- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `lib/features/conversation/application/chat_message_listener.dart`

Support files to inspect, but edit only if the tests require it:

- `lib/core/local_discovery/lan_ack.dart`
- `lib/core/inbox/inbox_staging_entry.dart`
- `lib/core/inbox/inbox_staging_repository.dart`
- `lib/features/conversation/application/send_delivery_receipt_use_case.dart`

Test owner files:

- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- Existing receipt-origin proof in `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` should be run, not rewritten unless S2 changes the listener signature and requires call-site updates.

Do not edit `lib/core/services/p2p_service.dart`, `send_chat_message_use_case.dart`, retry use cases, integration tests, gate arrays, docs 115/116, or S3-S5 plan files in S2.

## Existing Tests Covering This Area

- `test/core/local_discovery/local_ws_server_test.dart` now covers S1 commit-handler behavior, committed/legacy/nack classification, legacy unconfigured behavior, and prompt nack handling.
- `test/core/local_discovery/local_p2p_service_test.dart` covers current local P2P facade send/media/stream behavior but does not yet cover handler passthrough.
- `test/core/services/p2p_service_impl_test.dart` has a `durable inbox staging` group covering direct confirmNonce staging, direct replay callback behavior, retryable/quarantined/rejected dispositions, startup replay of staged rows, relay drain staging, and ack-boundary migration gate behavior.
- `test/core/services/p2p_service_inbound_transport_test.dart` covers inbound transport telemetry, including current local WiFi message surfacing as `wifi`.
- `test/shared/fakes/in_memory_inbox_staging_repository.dart` supports staging, retryable, rejected, quarantined, recoverable lookup, and delete for host tests.
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` already pins the doc-115 origin-marker contract: `direct:` and `lan:` skip receipts, relay entries mint receipts, and decrypt failures do not mint receipts.

Missing today:

- No `LocalP2PService` commit-handler passthrough.
- No `P2PServiceImpl` captured handler for LAN commits.
- No `lan:<nonce>` staging entry builder.
- No LAN-specific replay events through `_applyRecoveredInboxOutcome`.
- No live LAN replay callback.
- No `stagedEntryId` propagation from recovered/live replay into `ChatMessageListener.processIncomingMessage`.
- No staging-error LAN nack/fallback test.
- No handled-LAN telemetry test.

## Regression/Tests To Add First

Add these RED tests before production edits:

1. In `test/core/local_discovery/local_p2p_service_test.dart`, add `configureInboundChatCommitHandler delegates to LocalWsServer` using a real `LocalWsServer` or recording test server pattern already in the file. The handler should receive the same `LocalChatMessage` and nonce when the underlying server invokes it.
2. In `test/core/services/p2p_service_impl_test.dart`, extend `FakeLocalP2PService` usage so construction of `P2PServiceImpl(localP2PService: fake, ...)` captures a `LanInboundChatCommitHandler`.
3. In the `durable inbox staging` group, add `stages LAN chat into inbox_staging before the commit decision and deletes the row on committed replay`: invoke the captured handler with nonce `n1` and a chat envelope; assert `lan:n1` exists before the handler future completes committed, the replay callback sees transport `wifi` and staged id `lan:n1`, and the row is deleted after committed outcome.
4. Add `rejects LAN commit when the account-migration gate blocks inbound`: gate returns false; expect rejected decision, no staged row, no `messageStream` emission, and migration blocked telemetry.
5. Add `marks LAN staged row retryable on decryptionDeferred replay outcome`: replay returns retryable with `decryption_deferred`; expect `lan:<nonce>` row remains retryable with reason metadata.
6. Add `quarantines LAN staged row on decryptionFailed replay outcome`: replay returns quarantined; expect row status `quarantined` and reason metadata while the commit decision remains committed because custody was taken.
7. Add `LAN staged row left by a killed process is recovered by startup replay sweep`: stage via the handler but hold live replay; construct a second `P2PServiceImpl` over the same repo, drive `drainOfflineInbox`, and assert the `lan:` row replays once and deletes.
8. Add `live LAN replay routes through live replay callback so notifications are not suppressed`: with both callbacks present, captured handler must call `replayLiveLanChatMessage`; with only recovered callback present, it must fall back.
9. Add `staged entry id is passed to chat listener for direct and LAN replay`: in `chat_message_listener_test.dart`, prove `processIncomingMessage(stagedEntryId: 'lan:n1')` forwards that id to `handleIncomingChatMessage` behavior by using a receipt hook that would fire for `transport:'inbox'` without the `lan:` staged id but does not fire with it.
10. In `test/core/services/p2p_service_fault_injection_test.dart`, add `LAN staging write failure produces rejected commit and falls back to in-memory emit` with a stage-throwing `InboxStagingRepository`.
11. In `test/core/services/p2p_service_inbound_transport_test.dart` or the LAN handler tests, assert handled LAN commits still increment `wifi` metrics and emit/record transport as before.

Do not add a new integration test file in S2. S4 owns `local_ws_durable_ack_integration_test.dart`.

## Step-By-Step Implementation Plan

1. Add the `lan_ack.dart` import to `LocalP2PService` and implement `configureInboundChatCommitHandler(LanInboundChatCommitHandler handler)` by delegating to `_wsServer`.
2. Update `FakeLocalP2PService` with a nullable captured handler field and an override of `configureInboundChatCommitHandler`. Do not add S3 `sendMessageDetailed` behavior here.
3. In `P2PServiceImpl`, add an optional constructor callback for live LAN replay, using the same outcome type as recovered replay. Keep it optional and default null.
4. Make the replay callback shape explicit and origin-aware:

   ```dart
   typedef ReplayRecoveredInboxChatMessage =
       Future<RecoveredInboxReplayOutcome> Function(
         ChatMessage message, {
         String? stagedEntryId,
       });
   ```

   Apply the same signature to the new live LAN replay callback. Update every current `P2PServiceImpl` construction that supplies `replayRecoveredInboxChatMessage` so test and main callbacks accept `{String? stagedEntryId}` explicitly. Do not use dynamic maps, globals, or a second parallel callback API for origin.
5. Add `stagedEntryId` as an optional named parameter to `ChatMessageListener.processIncomingMessage` and pass it to `handleIncomingChatMessage`. Existing callers remain source-compatible.
6. In the `P2PServiceImpl` constructor, when `_localP2P` is not null, call `_localP2P.configureInboundChatCommitHandler(_commitInboundLanChatMessage)` near the existing local stream subscription.
7. Keep `_localMessageSub` in place for legacy/unconfigured local messages and non-handler paths; S2 must not remove the existing stream merge.
8. Implement `_stagingEntryFromLanMessage(LocalChatMessage message, {required String nonce, String? messageType})` to build `InboxStagingEntry(entryId: 'lan:$nonce', ownerPeerId: message.to, senderPeerId: message.from, messageType, relayTimestamp from message timestamp, envelope: message.content, stagedAt now)`.
9. Implement `_commitInboundLanChatMessage(LocalChatMessage localMsg, {required String? nonce})`:
   - record `wifi` telemetry and emit `MSG_RECEIVED_TRANSPORT` at handler entry;
   - run `_allowsAccountNetworkSideEffects('p2p_inbound_message', peerId: localMsg.to)` before staging;
   - parse `envelopeType` from `localMsg.content`;
   - if the gate blocks, return `LanInboundDecision.rejected('account_migration_blocked')`;
   - if the envelope is not `chat_message`, replay callback is unavailable, nonce is missing/empty, or required fields are missing, emit the existing in-memory message and return `LanInboundDecision.accepted()` to preserve legacy behavior;
   - stage `lan:<nonce>` and return `LanInboundDecision.committed()` only after `stageEntries` succeeds;
   - start replay with `unawaited` after staging, using `replayLiveLanChatMessage ?? replayRecoveredInboxChatMessage` and `_applyRecoveredInboxOutcome` with LAN event names;
   - on replay exception, mark the row retryable with `processing_error` and emit `P2P_SERVICE_LAN_STAGED_CHAT_EXCEPTION`;
   - on staging exception, emit `P2P_SERVICE_LAN_STAGE_ERROR`, emit the message in memory as a fallback, and return `LanInboundDecision.rejected('staging_error')`.
10. Reuse `_applyRecoveredInboxOutcome` for committed, retryable, rejected, and quarantined LAN dispositions. Do not create a separate disposition state machine.
11. In `_replayStagedInboxEntries` and `_processDurablyStagedDirectChat`, pass `entry.entryId` into the replay callback so `direct:` and `lan:` origins are visible downstream.
12. In `main.dart`, wire `replayLiveLanChatMessage` with the same unknown-sender intro recovery pre-step as the recovered callback, but call `chatMessageListener.processIncomingMessage(..., suppressNotification:false, stagedEntryId: entryId)` for live LAN. Keep recovered inbox replay using `suppressNotification:true`.
13. Update test constructor lambdas affected by the replay callback signature and keep existing direct/relay tests green.
14. Stop and refresh this plan if implementation requires changing `P2PService`, sender local-send policy, sticky transport, integration-test harnesses, DB schema/migrations, Go/relay code, or docs 115/116.

## Risks And Edge Cases

- Handler-broadcast split: configured `LocalWsServer` handlers do not emit on `messageStream`, so telemetry and routing must be performed by the handler path.
- Missing nonce: committed LAN ack cannot be truthful without a nonce-derived `lan:<nonce>` id. S2 should fall back to accepted legacy/in-memory behavior for missing nonce, not invent a sender-visible committed ack.
- Staging duplicate: `stageEntries` may already contain `lan:<nonce>` after a retry; the handler should treat idempotent staging as committed and let replay dedup/delete handle the row.
- Staging succeeds but replay fails: keep the staged row retryable; do not emit a committed ack and then delete or drop the row on processing exception.
- Staging fails: return nack/rejected so the sender can later use S3 backstop behavior, while still emitting in memory for receiver-side best effort and idempotent duplicate absorption.
- Account migration can block at two levels: S2 must gate before staging; later listener-level gate may still return retryable if state changes after staging.
- Receipt origin: without `stagedEntryId`, staged `direct:`/`lan:` rows look like `transport:'inbox'` and can mint receipts incorrectly.
- Notification parity: live LAN replay must not inherit recovered replay `suppressNotification:true`.
- Broad dirty worktree: unrelated modified/untracked files must not be reverted, cleaned, or folded into S2.

## Exact Tests And Gates To Run

Focused S2 tests:

```bash
flutter test test/core/local_discovery/local_p2p_service_test.dart
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/services/p2p_service_fault_injection_test.dart
flutter test test/core/services/p2p_service_inbound_transport_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
```

S2 direct suites:

```bash
flutter test test/core/services test/core/local_discovery
```

Named host gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh completeness-check
```

Graph maintenance after code changes:

```bash
./graphify-arch/refresh_arch_graph.sh
```

Simulator/device evidence:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_relay_fallback_smoke_test.dart
```

Do not require the simulator/device command for S2 implementation acceptance unless the executor touches integration-test/device behavior. It is the narrow doc-level reliability-sim placeholder for the end-to-end LAN/notification journey and must remain a S4/S5 residual if not runnable here. S2 can be accepted only as receiver host closure, not final doc closure.

## Known-Failure Interpretation

- The new S2 RED tests should fail before implementation because no handler passthrough, LAN staging handler, live LAN replay callback, staged-entry-id propagation, or staging-error decision path exists yet.
- Existing S1 local-discovery tests may be dirty/untracked but are accepted as S1 evidence; do not rewrite them unless S2's `LocalP2PService` passthrough requires a compile adjustment.
- Failures in `./scripts/run_test_gates.sh 1to1` or `completeness-check` caused by unrelated broad worktree dirt must be recorded with exact file/test names and not fixed under S2.
- If `handle_incoming_chat_message_use_case_test.dart` origin-marker tests are already green, treat them as pins; S2 still must prove P2P replay passes `stagedEntryId` into that existing machinery.
- If simulator devices are unavailable, record the simulator command as doc-level residual evidence for S4/S5 rather than blocking S2 host implementation.

## Done Criteria

S2 is done when:

- `LocalP2PService` exposes and delegates `configureInboundChatCommitHandler`.
- `P2PServiceImpl` configures the LAN commit handler at construction when local P2P is present.
- The handler runs the migration gate before staging.
- Chat envelopes with non-empty nonce stage as `lan:<nonce>` before returning committed.
- LAN committed, retryable, rejected, and quarantined replay outcomes use `_applyRecoveredInboxOutcome` and LAN-specific flow events.
- Live LAN replay uses the live callback and main wiring calls `processIncomingMessage` with `suppressNotification:false`.
- Recovered/direct/LAN replay passes `stagedEntryId` so `direct:` and `lan:` origins do not mint delivery receipts.
- Staging errors return rejected/nack, emit `P2P_SERVICE_LAN_STAGE_ERROR`, and fall back to in-memory receiver emit.
- Handled LAN commits still record `wifi` inbound telemetry.
- The exact focused tests and host gates above have been run, or unrelated/pre-existing failures are recorded precisely.
- `./graphify-arch/refresh_arch_graph.sh` has been run from the repo root after S2 code changes, or an exact blocker is recorded.
- No S3-S5, docs 115/116, sender policy, sticky transport, Go/relay, DB migration, or final closure docs are modified.

## Scope Guard

Non-goals:

- Do not start, plan, or execute S3-S5.
- Do not create or edit docs 115/116.
- Do not modify `send_chat_message_use_case.dart`, retry use cases, sticky learned transport, `DurableLanSender`, or sender status/backstop policy.
- Do not change `P2PService` abstract interface or broad P2P fakes.
- Do not add `sendMessageDetailed` to `LocalP2PService`; that is S3.
- Do not add `local_ws_durable_ack_integration_test.dart`; that is S4.
- Do not edit `scripts/run_test_gates.sh` or `test-gate-definitions.md`; S5 owns gate capture unless S2 unexpectedly creates a new test file, which this plan forbids.
- Do not add DB migrations; `inbox_staging_entries` is reused.
- Do not change Go, relay, gomobile, platform manifests, or notification channel configuration.

Overengineering signals:

- adding LAN protocol negotiation or version handshakes;
- adding a separate LAN replay state machine instead of `_applyRecoveredInboxOutcome`;
- hiding origin in maps/dynamic payloads instead of explicit callback parameters;
- treating S2 host evidence as final device or mixed-version proof.

Rollback/blocker rules:

- Block and refresh the plan if the S1 handler API is absent or materially different from current `lan_ack.dart`.
- Block if `stagedEntryId` cannot be propagated without broad listener/router rewrites.
- Block if a required S2 test demands sender policy or sticky-transport changes.
- Roll back only S2 edits if the handler causes legacy/unconfigured local messages to stop using `localMessageStream`.

## Accepted Differences / Intentionally Out Of Scope

- S2 does not make senders truthful for legacy/bool LAN acks; S3 owns sender status/backstop/sticky behavior.
- S2 does not prove real socket, mixed-version, mDNS, or device notification behavior; S4/S5 own final integration and device evidence.
- S2 may update the callback signature for recovered replay to carry `stagedEntryId`; this is accepted because it is required to preserve the already-landed receipt-origin contract.
- The doc-115 origin-marker implementation is treated as existing code evidence only. S2 must not alter docs 115/116.
- Missing-nonce LAN chat falls back to legacy accepted/in-memory behavior rather than committed durable ack.

## Dependency Impact

- S3 depends on S2 ensuring committed LAN acks mean receiver durable staging happened.
- S4 depends on S2's `lan:<nonce>` rows, live replay callback, and staging-error behavior for real loopback loss-window tests.
- S5 depends on S2 test names/results for final gate capture and source-doc closure logs.
- If S2 changes the replay callback signature, every existing `P2PServiceImpl` test construction with `replayRecoveredInboxChatMessage` must be updated in the same session so later sessions do not inherit a partially migrated type surface.

## Reviewer Notes

Reviewer verdict: sufficient with one adjustment, now patched.

- Missing files/tests/gates: none after adding `chat_message_listener_test.dart`, `handle_incoming_chat_message_use_case_test.dart`, the focused core/local-discovery tests, `1to1`, `completeness-check`, and a doc-level simulator residual command.
- Stale assumptions: the draft originally left callback shape as "extend or wrap"; current code shows `ReplayRecoveredInboxChatMessage` lacks `stagedEntryId`, while doc-115 receipt-origin code already needs that id. The plan now mandates one explicit optional named parameter and updates all callback constructors.
- Overengineering: no separate LAN replay state machine, no sender policy, no DB migration, no S3/S4/S5 work.
- Decomposition: narrow enough for implementation; all user-listed S2 requirements map to a proof in the closure bar.
- Minimum sufficiency: preserve S1 surface, implement handler wiring, add LAN staging/replay tests first, run direct suites plus named host gates, and record simulator/device evidence as later doc-level residual rather than S2 closure.

## Arbiter Decision

Final verdict: execution-ready for S2 implementation.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper names inside `P2PServiceImpl` may vary, but the handler, staging entry, live replay callback, and staged-entry-id propagation must remain explicit.
- The simulator/device command is retained as doc-level reliability evidence for the later end-to-end closure path; S2 host closure must not overclaim that proof.

Accepted differences intentionally left unchanged:

- S2 remains host-focused and does not close real mDNS/WS, mixed-version, or device notification evidence.
- S2 does not implement sender durable-ack policy, sticky transport truthfulness, or final gate/doc closure.
- S2 may touch `ChatMessageListener` narrowly to carry `stagedEntryId`; this is required to preserve the already-landed receipt-origin contract and is not a product-scope expansion.

Why safe to implement now: the plan maps every user-listed S2 requirement to an owner file, a first regression, and a closure proof; it preserves S1 and broad dirty worktree changes; it blocks S3-S5 scope; and it names exact direct tests and host gates before any acceptance claim.

## Execution Progress

- 2026-06-13T05:23:42Z - Controller pre-execution snapshot recorded before any Executor/code edit. Phase: contract extraction and dirty-worktree baseline. Files inspected: S2 plan, doc 114 source, S2 breakdown entry, `git status --short`. Dirty state: broad pre-existing modified/untracked worktree across Flutter, Go, relay, platform, docs, graphify, and tests; S2 owner files already dirty/untracked include `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/main.dart`, `lib/features/conversation/application/chat_message_listener.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_fault_injection_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, and `test/features/conversation/application/chat_message_listener_test.dart`. Decision/blocker: no execution blocker; work must preserve unrelated dirty changes and stay inside S2 owner files/tests. Next action: spawn fresh Executor agent with `model:gpt-5.5` and `reasoning_effort:xhigh`.
- 2026-06-13T05:23:58Z - Controller extracted S2 execution contract and is spawning Executor. Phase: Executor running. Files inspected: S2 plan sections `Real Scope`, `Closure Bar`, `Regression/Tests To Add First`, `Exact Tests And Gates To Run`, `Done Criteria`, and `Scope Guard`; S2 breakdown entry; doc 114 Phase 2. Command currently running: spawned Executor agent. Decision/blocker: none; S2 scope only, no S3-S5/docs 115/116. Next action: wait for Executor result and inspect its code/test/doc evidence.
- 2026-06-13T05:34:29Z - Controller first bounded wait for Executor timed out. Phase: Executor running, progress inspection. Files inspected/touched: S2 plan progress only so far. Command/result: `wait_agent` for Executor `019ebf70-289e-7490-b562-26d71ddb8a5b` timed out after 600000ms without final status. Decision/blocker: pending progress inspection, not yet classified. Next action: inspect assigned-file diffs and plan progress to decide whether one additional bounded wait is allowed.
- 2026-06-13T05:34:55Z - Controller progress inspection found real Executor progress. Phase: Executor running, second bounded wait allowed. Files inspected: S2 plan progress tail; S2 owner-file diff stat/name list. Evidence: Executor added RED-test progress entries, confirmed expected RED failures, and touched S2 owner production/test files including local P2P passthrough, P2P service, main wiring, listener, fakes, and focused tests. Command currently running: additional `wait_agent` for Executor `019ebf70-289e-7490-b562-26d71ddb8a5b`. Decision/blocker: not a no-progress spawn failure; one additional bounded wait is allowed. Next action: wait for final Executor result, then inspect evidence and spawn QA if trustworthy.
- 2026-06-13T05:47:12Z - Controller received completed Executor result. Phase: QA Reviewer spawning. Files inspected/touched: S2 plan progress and Executor final summary. Executor evidence: expected RED focused command failed before production edits; focused S2 tests passed; `flutter test test/core/services test/core/local_discovery` passed; `./scripts/run_test_gates.sh 1to1` passed; `./scripts/run_test_gates.sh completeness-check` passed with `840/840`; targeted analyzer fixes passed; `./graphify-arch/refresh_arch_graph.sh` passed; no `uv tool upgrade graphifyy`. Decision/blocker: Executor produced trustworthy completion evidence; separate QA Reviewer required. Next action: spawn fresh QA Reviewer with `model:gpt-5.5` and `reasoning_effort:xhigh`.
- 2026-06-13T05:24:57Z - Executor contract extraction completed. Phase: S2 implementation pass starting. Files inspected: full S2 plan, S2 breakdown entry only, doc 114 Phase 2 only, implementation-execution skill contract. Command currently running: none. Decision/blocker: no blocker; will add required RED tests before production edits and keep intentional edits to S2 owner files/tests plus this progress section. Next action: inspect owner files and current dirty S2 surfaces.
- 2026-06-13T05:26:46Z - Executor owner-file inspection completed and RED test edit phase starting. Phase: RED tests before production edits. Files inspected: `local_p2p_service.dart`, `local_ws_server.dart`, `lan_ack.dart`, `fake_local_p2p_service.dart`, `p2p_service_impl.dart`, `chat_message_listener.dart`, S2 direct tests, `in_memory_inbox_staging_repository.dart`. Command currently running: none. Decision/blocker: S1 handler API exists; no blocker. Next action: add S2 RED tests in owner test files only.
- 2026-06-13T05:31:25Z - RED tests added and formatted before production edits. Phase: expected RED confirmation. Files touched: `local_p2p_service_test.dart`, `fake_local_p2p_service.dart`, `p2p_service_impl_test.dart`, `p2p_service_fault_injection_test.dart`, `p2p_service_inbound_transport_test.dart`, `chat_message_listener_test.dart`. Command currently running: `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_fault_injection_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/conversation/application/chat_message_listener_test.dart`. Decision/blocker: expected RED from missing S2 production seam; no blocker yet. Next action: run focused RED confirmation, then implement production S2 seam.
- 2026-06-13T05:32:09Z - Focused RED confirmation completed. Phase: production implementation starting. Failing command: `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_fault_injection_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/conversation/application/chat_message_listener_test.dart`. Failing files/tests: compile failures in `local_p2p_service_test.dart` (`configureInboundChatCommitHandler` missing), `p2p_service_impl_test.dart` (`replayLiveLanChatMessage` missing), `chat_message_listener_test.dart` (`stagedEntryId` missing), plus null captured handler failures in LAN telemetry/fault tests. Classification: expected_red_before_production. Next action: implement S2 production seams and rerun focused tests.
- 2026-06-13T05:35:39Z - Production S2 seam implemented and formatted. Phase: focused S2 validation. Files touched: `local_p2p_service.dart`, `p2p_service_impl.dart`, `main.dart`, `chat_message_listener.dart`, S2 direct test files/fake. Command currently running: `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_fault_injection_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`. Decision/blocker: no blocker before rerun. Next action: run focused S2 tests and triage any failures.
- 2026-06-13T05:36:26Z - Focused S2 tests passed. Phase: required direct suite. Last completed command/result: `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_fault_injection_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` passed. Command currently running: `flutter test test/core/services test/core/local_discovery`. Decision/blocker: none. Next action: run required direct suite.
- 2026-06-13T05:37:32Z - Required direct suite passed. Phase: named gates. Last completed command/result: `flutter test test/core/services test/core/local_discovery` passed. Command currently running: `./scripts/run_test_gates.sh 1to1`. Decision/blocker: none. Next action: run required `1to1` gate.
- 2026-06-13T05:38:24Z - Required `1to1` gate passed. Phase: named gates. Last completed command/result: `./scripts/run_test_gates.sh 1to1` passed. Command currently running: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: none. Next action: run required completeness-check gate.
- 2026-06-13T05:38:53Z - Required completeness-check gate passed. Phase: graph maintenance. Last completed command/result: `./scripts/run_test_gates.sh completeness-check` passed with `840/840 test files classified`. Command currently running: `./graphify-arch/refresh_arch_graph.sh`. Decision/blocker: none; no `uv tool upgrade graphifyy` occurred. Next action: refresh architecture graph from repo root.
- 2026-06-13T05:41:13Z - Graph refresh passed, then a callback seam compile-shape check found non-required benchmark call sites still using the old replay callback shape. Phase: seam cleanup. Last completed command/result: `./graphify-arch/refresh_arch_graph.sh` passed; `dart analyze test/performance/benchmark_inbox_delivery_timing_test.dart` failed with five `argument_type_not_assignable` errors for `replayRecoveredInboxChatMessage` lambdas. Classification: session_caused_compile_shape. Next action: mechanically update those callback lambdas to the explicit `{String? stagedEntryId}` signature and rerun the focused analyze.
- 2026-06-13T05:41:39Z - Callback seam cleanup completed. Phase: graph maintenance rerun. Last completed command/result: `dart format test/performance/benchmark_inbox_delivery_timing_test.dart && dart analyze test/performance/benchmark_inbox_delivery_timing_test.dart` passed. Command currently running: `./graphify-arch/refresh_arch_graph.sh`. Decision/blocker: none; rerunning graph refresh because a test file changed after the first refresh. Next action: refresh architecture graph again from repo root.
- 2026-06-13T05:43:02Z - Final graph refresh passed. Phase: executor handoff. Last completed command/result: `./graphify-arch/refresh_arch_graph.sh` passed and refreshed `graphify-arch/graphify-out/graph.json`, `GRAPH_REPORT.md`, aggregated `graph.html`, `GRAPH_SELECTION.md`, and `comparison.json`; no `uv tool upgrade graphifyy` occurred. Command currently running: none. Decision/blocker: no executor blocker. Next action: final scoped diff/status check and handoff to QA reviewer/controller.
- 2026-06-13T05:44:39Z - Production compile-shape analyze found one missing import and fix was applied. Phase: final validation. Failing command: `dart analyze lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/chat_message_listener.dart lib/main.dart`. Failing file/test: `lib/main.dart` undefined `ChatMessage` in replay helper. Classification: session_caused_compile_shape; fixed by adding the existing P2P `ChatMessage` model import. Command currently running: `dart format lib/main.dart && dart analyze lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/chat_message_listener.dart lib/main.dart`. Next action: rerun production analyze and refresh graph again if it passes.
- 2026-06-13T05:45:05Z - Production compile-shape analyze passed. Phase: final graph maintenance. Last completed command/result: `dart format lib/main.dart && dart analyze lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/chat_message_listener.dart lib/main.dart` passed. Command currently running: `./graphify-arch/refresh_arch_graph.sh`. Decision/blocker: none; rerunning graph refresh because `main.dart` changed after the prior refresh. Next action: final graph refresh and scoped status handoff.
- 2026-06-13T05:46:27Z - Final graph refresh passed after all S2 code/test edits. Phase: executor handoff. Last completed command/result: `./graphify-arch/refresh_arch_graph.sh` passed and refreshed `graphify-arch/graphify-out/graph.json`, `GRAPH_REPORT.md`, aggregated `graph.html`, `GRAPH_SELECTION.md`, and `comparison.json`; no `uv tool upgrade graphifyy` occurred. Command currently running: none. Decision/blocker: no executor blocker. Next action: final scoped status and chat handoff; QA reviewer/controller own acceptance.
- 2026-06-13T05:48:15Z - QA Reviewer started. Phase: S2 QA sufficiency review. Files inspected so far: S2 plan, S2 breakdown entry, worktree status, Executor progress evidence. Command currently running: none. Decision/blocker: pending QA review. Next action: inspect S2 owner-file diffs, implementation/test files touched by Executor, scope adherence, callback seam coherence, and recorded test/gate evidence.
- 2026-06-13T05:50:08Z - QA Reviewer code/diff inspection completed; validation starting. Phase: focused QA validation. Files inspected: `local_p2p_service.dart`, `local_ws_server.dart`, `lan_ack.dart`, `p2p_service_impl.dart`, `main.dart`, `chat_message_listener.dart`, `send_delivery_receipt_use_case.dart`, S2 direct tests, `benchmark_inbox_delivery_timing_test.dart`, staging repository/helper code. Command currently running: focused S2 test rerun and targeted analyzer reruns. Decision/blocker: no blocking code issue found yet; benchmark touch appears limited to callback signature migration plus formatting. Next action: verify focused tests/analyzers and final scope evidence.
- 2026-06-13T05:50:48Z - QA Reviewer completed. Phase: S2 QA sufficiency review complete. Last completed command/result: focused S2 test rerun passed; targeted analyzer rerun passed; scoped `git diff --check` passed. Evidence reviewed: Executor-recorded RED failure, direct suite pass, `1to1` gate pass, completeness-check `840/840`, production/benchmark analyzer fixes, and final `./graphify-arch/refresh_arch_graph.sh` pass. Decision/blocker: no blocking issues found; remaining broad dirty files/docs outside S2 appear pre-existing from the controller baseline and were not evaluated as S2 changes. Next action: controller owns final execution verdict.
- 2026-06-13T05:51:35Z - Controller writing final execution verdict. Phase: final verdict. Files inspected/touched: S2 plan progress/verdict, S2 owner-file diff list, Executor result, QA result. Command currently running: none. Decision/blocker: no S2 blocking issue remains; S2 execution accepted. Next action: stop without updating the breakdown ledger because parent closure owns accepted-session bookkeeping.

## Execution Verdict

Verdict: accepted.

Blocker class: none.

Spawned-agent isolation used: yes. Executor agent `019ebf70-289e-7490-b562-26d71ddb8a5b` and QA Reviewer agent `019ebf85-7ce6-7732-b6a5-10cde50b15a5` were spawned in separate fresh contexts with `model:gpt-5.5` and `reasoning_effort:xhigh`.

Local sequential fallback used: no.

Files changed for S2:

- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/performance/benchmark_inbox_delivery_timing_test.dart` only for the mechanical replay callback signature compile seam
- `graphify-arch/graphify-out/*` refreshed by `./graphify-arch/refresh_arch_graph.sh`

Tests added or updated: S2 LAN commit-handler passthrough, LAN durable staging/replay disposition, migration-gate rejection, live LAN replay, staging-error fallback, handled-LAN telemetry, `stagedEntryId` receipt-origin propagation, and callback signature compile-seam coverage in the files listed above.

Evidence captured:

- Expected RED focused S2 command failed before production edits with missing `configureInboundChatCommitHandler`, `replayLiveLanChatMessage`, and `stagedEntryId` seams.
- Executor verified final graph maintenance with `./graphify-arch/refresh_arch_graph.sh`; no `uv tool upgrade graphifyy` occurred.
- QA Reviewer inspected scope, callback seam coherence, LAN staging path, receipt-origin propagation, and the benchmark callback fix; no blocking issues found.

Exact tests and gates run:

- `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_fault_injection_test.dart test/core/services/p2p_service_inbound_transport_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` - passed in Executor and rerun by QA.
- `flutter test test/core/services test/core/local_discovery` - passed.
- `./scripts/run_test_gates.sh 1to1` - passed.
- `./scripts/run_test_gates.sh completeness-check` - passed with `840/840 test files classified`.
- `dart analyze lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/chat_message_listener.dart lib/main.dart` - passed after session-caused import fix.
- `dart analyze test/performance/benchmark_inbox_delivery_timing_test.dart` - passed after mechanical callback signature update.
- `dart analyze lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/chat_message_listener.dart lib/main.dart test/performance/benchmark_inbox_delivery_timing_test.dart` - passed in QA.
- Scoped `git diff --check` - passed in QA.
- `./graphify-arch/refresh_arch_graph.sh` - passed after final code/test changes.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none inside S2. S4/S5 still own real loopback, device, mixed-version, gate-capture, and final doc closure evidence, but those are outside S2 and are not blockers for S2 host acceptance.

Why S2 is safe to consider complete: the receiver-side LAN commit path now wires through `LocalP2PService` into `P2PServiceImpl`, gates before staging, stages `lan:<nonce>` rows before returning committed, reuses recovered-inbox disposition handling for LAN replay outcomes, preserves live LAN notification behavior through the live callback, passes `stagedEntryId` through replay/listener seams for receipt-origin discrimination, rejects staging failures with fallback emission, preserves handled-LAN telemetry, and has the required focused tests, direct suites, named gates, analyzer checks, QA review, and graph refresh evidence recorded above.
