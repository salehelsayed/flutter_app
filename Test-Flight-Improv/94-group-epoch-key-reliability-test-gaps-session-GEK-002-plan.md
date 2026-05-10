# GEK-002 - Decrypt-failure Placeholder to Durable Replay Repair Journey

Status: execution-ready

## Planning Progress

- 2026-05-09 22:08:00 CEST - Role: Arbiter completed. Files inspected since last update: reviewer-pass plan and patched test/gate section. Decision/blocker: no structural blockers remain; plan is reusable and execution-ready. Next action: stop planning and hand off for GEK-002 implementation.
- 2026-05-09 22:06:00 CEST - Role: Arbiter started. Files inspected since last update: exact plan path existence check, first 34 lines of the plan, reviewer findings. Decision/blocker: exact path exists; user progress request acknowledged; classify reviewer findings and final readiness. Next action: write final arbiter verdict and final planning output.
- 2026-05-09 22:04:00 CEST - Role: Reviewer completed. Files inspected since last update: full GEK-002 draft, bridge diagnostic test selector, direct gate list. Decision/blocker: sufficient with adjustments; no structural blocker, but the bridge selector needed exact wording and the direct suite needed full owner-file reruns after focused checks. Next action: patch incremental details and run Arbiter pass.
- 2026-05-09 22:01:00 CEST - Role: Reviewer started. Files inspected since last update: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`, `test/core/bridge/go_bridge_client_test.dart`, `go-mknoon/node/pubsub_decryption_failure_test.go`. Decision/blocker: no blocker; checking section completeness, selector exactness, scope drift, and proof profile. Next action: record sufficiency findings.
- 2026-05-09 21:58:00 CEST - Role: Planner completed. Files inspected since last update: code/test evidence from Evidence Collector plus this draft plan. Decision/blocker: reusable draft written with host-only proof profile, regression-first rule, and GEK-003/GEK-004 exclusions. Next action: run Reviewer pass for sufficiency, stale assumptions, missing tests/gates, and overreach.

## real scope

GEK-002 changes only the app-layer repair journey for one missing group message after a live decrypt failure:

- consume a live `group:decryption_failed` diagnostic without creating a fake delivered plaintext row
- create or preserve a pending key-repair placeholder for the affected group/sender/epoch
- accept a later durable group inbox replay for the same missing message while the key is still absent
- after the missing key arrives, replay/decrypt the durable envelope and make the final plaintext message visible exactly once
- leave a clear pending or undecryptable state if the durable replay cannot be repaired

This session does not plan GEK-003 partial-recipient rotation races, GEK-004 delayed membership/config propagation, GEK-005 final simulator/relay acceptance, group invite eligibility, receipt semantics, protocol redesign, or broad UI redesign.

## closure bar

GEK-002 is good enough when a regression test proves the whole journey in one run:

1. a live decrypt-failure diagnostic creates a safe pending state and no normal delivered message for the real replay `messageId`
2. duplicate durable replay for that same missing message does not add a second visible placeholder
3. later key arrival plus pending-repair retry replaces or resolves the pending state into the real plaintext message
4. the timeline/repository has exactly one visible row for the repaired message after recovery
5. repeating replay or retry does not duplicate the row or reintroduce an orphan live placeholder

The implementation may choose the smallest safe correlation mechanism, but it must not leave a synthetic live placeholder visible beside the repaired durable message.

## source of truth

Authoritative order on disagreement:

1. current code and focused tests in this worktree
2. `Test-Flight-Improv/test-gate-definitions.md` for named gate membership and gate commands
3. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md` for GEK-002 session scope
4. `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md` for the reported reliability problem and acceptance gap
5. GEK-001 plan/closure evidence only for current key-acceptance behavior; do not replan or alter GEK-001
6. stable inventory/closure docs for historical coverage labels and known caveats

## session classification

`implementation-ready`

The source row is not stale or already covered. Existing tests prove live diagnostic placeholder handling and offline future-epoch repair separately, but not the combined user-visible journey.

## exact problem statement

Today, repo evidence shows these pieces independently:

- Go emits `group:decryption_failed` and suppresses normal `group_message:received`.
- Flutter routes that diagnostic to `GroupMessageListener`.
- `GroupMessageListener` can save a live pending repair placeholder.
- offline durable replay can queue a pending repair and later repair it after key arrival.
- GEK-001 prevents stale/older or conflicting same-generation key updates from rolling back active key material.

The missing proof is that one live decrypt failure and the later durable replay for the same message converge into one final visible plaintext message. The risk is a silent disappearance, a fake delivered row, or a double-row outcome where a synthetic live placeholder remains visible after the durable replay repairs the real message.

User-visible behavior must improve from "isolated diagnostics and isolated repair are covered" to "the actual degraded-to-repaired journey is covered and durable." Existing no-backfill, removed-member denial, duplicate suppression, diagnostic privacy, and GEK-001 key conflict semantics must stay unchanged.

## files and repos to inspect next

Production files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/models/group_pending_key_repair.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart`

Tests:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `go-mknoon/node/pubsub_decryption_failure_test.go`

Docs to update only during implementation closure, not in this planning session:

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_decryption_failure_test.go` proves wrong-key/tampered live group envelopes emit `group:decryption_failed` and do not emit `group_message:received`.
- `test/core/bridge/go_bridge_client_test.dart` proves `group:decryption_failed` enters Flutter's diagnostic stream and does not invoke the normal group-message callback; ER-005 variants keep sensitive diagnostic payloads redacted.
- `test/features/groups/application/group_message_listener_test.dart` includes `PREREQ-FUTURE-EPOCH-KEY-REPAIR live decryption failure creates repair placeholder and trigger without normal delivery`.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` includes `PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival`, mixed-epoch replay, and future-epoch placeholder coverage.
- `test/features/groups/application/group_key_update_listener_test.dart` includes `PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save` and rejected-key no-retry coverage.
- `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart` covers durable pending-repair upsert, lookup, attempt, and finalization basics.
- `test/features/groups/presentation/group_conversation_screen_test.dart` proves pending/finalized repair placeholders render safe text.
- GEK-001 focused tests prove delayed older and conflicting same-generation key updates cannot promote or replace accepted key material.

Missing: one combined test that starts with live `group:decryption_failed`, then drains durable replay for the same message while the key is missing, then repairs after key arrival, and asserts exactly one final visible message.

## regression/tests to add first

Add the red regression first in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`:

`GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival`

Minimum assertions:

- set up an existing group, sender member, local epoch 1 key, diagnostic stream, `GroupMessageListener`, pending-repair repository, fake inbox bridge, and repair request capture
- emit `group:decryption_failed` for group `group-1`, sender `peer-sender`, key epoch 2, local epoch 1
- assert a safe pending placeholder exists and no real replay `messageId` is delivered yet
- drain a signed durable replay envelope for the same group/sender/key epoch/message id while epoch 2 key is absent; include a duplicate replay envelope in the page to pin exactly-once behavior
- assert the visible pending state is still one row for this missing message journey, not a live synthetic row plus an offline replay row
- save the epoch 2 key and run `GroupPendingKeyRepairRunner.retryPendingRepairsForKey`, preferably with `replayGroupEnvelope: listener.handleReplayEnvelope`
- assert the final message text, sender, key generation, and delivered status are correct
- assert the group timeline/repository contains exactly one visible row for the repaired journey and no orphan pending live placeholder
- assert a second retry or duplicate replay does not add another row

If this test unexpectedly passes without production changes, stop implementation and reclassify GEK-002 as evidence-only with the exact command output. Otherwise, implement only enough to make this regression and existing owner tests pass.

If the implementation adds or changes repository operations for superseding/correlating pending repairs, add a focused test to `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart` before the production repository change.

## step-by-step implementation plan

1. Write the GEK-002 regression in `drain_group_offline_inbox_use_case_test.dart` using existing signed replay helpers and in-memory fakes.
2. Run the focused new test and confirm it fails for the expected reason: duplicate visible pending rows, an orphan live placeholder, a missing replay envelope finalizing the live repair as undecryptable, or no final exactly-once repaired message.
3. Inspect the failure and choose the smallest repair-correlation change in `group_pending_key_repair_service.dart`.
4. Preferred implementation direction: when durable replay queues a missing-key repair, correlate it with any pending live diagnostic repair for the same group id, sender/transport peer, and key epoch that has no replay envelope. Supersede or merge the live synthetic placeholder so the durable replay's real `messageId` becomes the canonical visible row.
5. Keep current diagnostic privacy and do not require Go to include plaintext, ciphertext, nonce, or message body. Do not add a native diagnostic `messageId` dependency unless repo evidence proves Dart-side durable replay correlation cannot satisfy the regression.
6. Ensure pending-repair retry ignores or safely finalizes superseded live no-envelope repairs so later key arrival cannot turn the old synthetic row into an undecryptable visible artifact.
7. Preserve `handleIncomingGroupMessage` duplicate behavior: repaired real messages can replace pending placeholders, while non-placeholder duplicates remain idempotent.
8. If a repository method is required, add the narrowest method and focused repository/helper tests. Avoid a migration unless a schema constraint actually blocks the minimal status or finalization update; current evidence shows status is ordinary text.
9. Wire only the affected app-layer path. Do not alter group membership validation, key rotation distribution, invite acceptance, Go pubsub behavior, relay APIs, or broad conversation UI.
10. Re-run the direct tests and gates below. If any failure shows the new regression expectation was wrong because current architecture intentionally keeps a separate live diagnostic row, stop and escalate that accepted-difference decision instead of hiding duplicate rows.

## risks and edge cases

- Live diagnostics do not currently carry the eventual durable replay `messageId`; correlation must rely on group id, sender/transport peer, key epoch, and pending/no-envelope state until durable replay arrives.
- Multiple messages from the same sender and epoch could fail live decrypt before durable replay arrives. The plan must avoid merging distinct durable messages into the wrong row. If ambiguity appears, prefer one durable canonical row per replay `messageId` and remove only safe no-envelope synthetic placeholders that cannot be message-specific.
- Duplicate replay envelopes should not increment visible row count or repair request count in a user-visible way.
- Missing replay envelope on a live-only diagnostic can still become explicit undecryptable if no durable replay ever arrives; GEK-002 must not remove that fallback for truly unrecoverable live failures.
- App restart durability matters through the existing pending-repair repository and message table. The regression may use in-memory fakes for behavior, but any repository change needs DB-backed proof.
- Later key arrival must happen only after accepted key save. GEK-001's conflict/monotonic contract must remain intact.
- Foreground/background recovery is represented by durable inbox drain plus retry runner; device lifecycle proof is not part of this session.

## exact tests and gates to run

Direct red/green command:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'
```

Owner regression commands:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR live decryption failure creates repair placeholder and trigger without normal delivery'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save'
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR rejected key updates do not trigger pending repair'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group decryption failure push event reaches diagnostics stream without invoking group message callback'
```

Full owner-file reruns after focused checks are green:

```bash
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
```

If pending-repair repository/helper APIs change:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart
flutter test --no-pub test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart
flutter test --no-pub test/core/database/migrations/063_group_pending_key_repairs_test.dart
```

If group message persistence or replacement semantics change:

```bash
flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test --no-pub test/core/database/helpers/group_messages_db_helpers_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Go command only if native `group:decryption_failed` diagnostics or Go key update behavior changes:

```bash
cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_Emits(DecryptionFailed|PayloadParseFailed)|TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)' -count=1
```

Always run:

```bash
git diff --check
```

## Device/Relay Proof Profile

Host-only for GEK-002.

Reason: this session's missing proof is the app-layer state machine that combines a diagnostic stream event, durable replay row, pending-repair repository state, key-arrival retry, and final message replacement. The breakdown assigns final simulator/relay reconciliation to GEK-005, and `test-gate-definitions.md` classifies real-stack group recovery and real-crypto onboarding suites as heavier optional/nightly evidence. GEK-002 should not require simulator or relay proof unless implementation changes native transport, relay APIs, or device-only lifecycle wiring.

## known-failure interpretation

- The new GEK-002 regression is expected to fail before implementation; after implementation it must pass.
- A failure in the existing live diagnostic, offline repair, key-arrival retry, pending-repair repository, or group gate coverage is blocking if it involves files touched by GEK-002 or the new combined behavior.
- Broad unrelated failures already documented in inventory, such as older MD-011 future-media replay caveats or Go peer-mismatch owner-slice failures, must not be counted as GEK-002 regressions unless the GEK-002 diff touches those paths or changes their failure signature.
- Dirty worktree changes outside this plan are not to be reverted or normalized during GEK-002 implementation.

## done criteria

- The GEK-002 combined regression was red before production changes and green after.
- Final repaired timeline/repository state contains exactly one visible row for the missing message journey.
- No fake delivered plaintext row appears on the live decrypt-failure path.
- Durable replay plus later key arrival repairs the real message or leaves one explicit unrecoverable state.
- Existing focused live diagnostic, offline repair, and key-arrival retry tests remain green.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass, or any unrelated known failure is documented with evidence.
- No GEK-003, GEK-004, or GEK-005 behavior is implemented or claimed.

## scope guard

Do not implement:

- GEK-003 rotation-race or partial-recipient multi-party transport proof
- GEK-004 membership/config propagation, invite eligibility, or accepted-recipient rules
- GEK-005 final simulator, relay, or release verdict work
- new delivery receipts, read receipts, MLS-style commit protocols, or per-recipient delivery truth
- native Go/relay protocol changes unless the direct regression proves Dart-side correlation is impossible
- UI redesign beyond preserving/removing the existing safe pending/undecryptable rows needed for exactly-once visibility
- broad repository rewrites, migration churn, or test-gate expansion

Overengineering for this session includes adding a new repair orchestration subsystem, new user-facing copy variants, new background services, or a device-lab harness to solve what current evidence shows is a host-testable state correlation gap.

## accepted differences / intentionally out of scope

- Group `sent` remains sender-pipeline durability, not proof that every member read the message.
- A live diagnostic can be less message-specific than durable replay because the Go diagnostic intentionally avoids sensitive payload details.
- If no durable replay ever arrives, one pending or undecryptable placeholder can remain for the live failure; GEK-002 only requires convergence when durable replay and later key arrival do arrive.
- Newly added members still do not receive pre-join history.
- Removed or left members still must not regain post-removal content.
- Final real-device/relay confidence is deferred to GEK-005 by the breakdown.

## dependency impact

GEK-003 and GEK-005 may rely on GEK-002's repair contract when a stale recipient later receives the missing key and durable replay. If GEK-002 changes the pending-repair identity or finalization semantics, GEK-003's rotation-race plan must inspect that behavior before asserting partial-recipient repair. GEK-004 should remain skipped unless the combined GEK-002 regression shows the root issue is membership/config rejection rather than key repair. GEK-005 should not write a final program verdict until GEK-002 through GEK-004 are closed or explicitly reclassified.

## Reviewer Pass

Sufficiency: sufficient with adjustments.

- Missing files/tests/gates: no structural gaps after adding the exact bridge selector and full owner-file reruns for `drain_group_offline_inbox_use_case_test.dart` and `group_message_listener_test.dart`.
- Stale or incorrect assumptions: the first draft used a non-exact bridge test selector; patched to the current test name. The host-only proof profile matches the GEK-002 breakdown because final simulator/relay reconciliation is GEK-005.
- Overengineering: the plan correctly avoids Go/relay/device changes unless the direct regression proves Dart-side correlation impossible.
- Decomposition: narrow enough for implementation; one combined regression owns the behavior, while GEK-003/GEK-004/GEK-005 are explicitly guarded out.
- Minimum needed for sufficiency: keep the regression-first command, exact selectors, full owner reruns, group gate, `git diff --check`, and the stop rule for unexpected already-covered evidence.

## Arbiter Pass

Structural blockers: none.

Incremental details:

- The reviewer-found bridge selector and full owner-suite rerun details were patched before this arbiter pass.
- A full `group_key_update_listener_test.dart` file rerun is optional unless GEK-002 implementation touches key-update listener behavior beyond relying on the existing retry callback.
- Device/relay proof remains intentionally deferred to GEK-005 unless implementation changes native transport, relay APIs, or device-only lifecycle wiring.

Accepted differences:

- Live diagnostics remain less message-specific than durable replay because they avoid sensitive payload details.
- A live-only diagnostic with no later durable replay may remain pending or become undecryptable; GEK-002 closes only the durable replay plus later key arrival journey.
- Host-side proof is sufficient for this session's state-machine gap; final real-stack confidence belongs to GEK-005.

Decision: no structural blocker remains after the reviewer adjustments. Stop planning here per the stop rule.

## Final Planning Output

Final verdict: execution-ready.

Final plan: add one red GEK-002 regression that combines live `group:decryption_failed`, pending placeholder creation, duplicate durable replay while the key is missing, later key arrival, pending repair retry, and exactly one final visible plaintext message. Implement only the smallest app-layer correlation/finalization change needed to make that regression and existing owner tests pass.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- no simulator/relay proof in GEK-002
- no Go diagnostic change unless Dart-side durable replay correlation proves impossible
- no full key-update listener suite unless implementation touches that listener

Accepted differences intentionally left unchanged:

- group `sent` is not all-recipient read proof
- live diagnostics can lack durable replay `messageId`
- live-only unrepaired diagnostics can remain explicit pending/undecryptable states
- GEK-003 rotation races, GEK-004 membership/config work, and GEK-005 final acceptance remain separate

Exact docs/files used as evidence:

- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`
- `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/domain/models/group_pending_key_repair.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/main.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`
- `go-mknoon/node/pubsub_decryption_failure_test.go`

Why the plan is safe to implement now: it is narrowly scoped to one GEK-002 state-machine gap, starts with a direct red regression, preserves GEK-001's accepted key semantics, names exact owner tests and gates, excludes GEK-003/GEK-004/GEK-005, and documents when to stop if evidence shows the behavior is already covered or requires product-level accepted-difference escalation.

## Execution Progress

- 2026-05-09 21:51:50 CEST - Phase: Orchestrator started before contract extraction. Files inspected or targeted: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`, `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, and current dirty worktree status. Command running: none. Decision/blocker: GEK-002 is the only execution scope; unrelated dirty files are present and must not be reverted. Next action: extract the execution contract and spawn the Executor.
- 2026-05-09 21:52:30 CEST - Phase: Contract extracted. Files inspected or targeted: GEK-002 plan direct-test/gate sections and breakdown GEK-002 row. Command running: none. Decision/blocker: required red regression is `GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival`; required owner commands are the focused regression, listed focused prerequisite tests, full `drain_group_offline_inbox_use_case_test.dart` and `group_message_listener_test.dart` reruns, `./scripts/run_test_gates.sh groups`, and `git diff --check`; conditional repository/message/Go tests run only if those paths change. Next action: spawn the Executor with the extracted contract.
- 2026-05-09 21:52:33 CEST - Phase: Executor spawned/running. Files inspected or targeted: GEK-002 plan and primary owner files/tests named in the plan. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app ...`. Decision/blocker: no blocker yet; child agent must add the regression first, run the red check, implement only the smallest GEK-002 change, and run required tests/gates. Next action: wait for Executor result and inspect landed evidence.
- 2026-05-09 21:53:13 CEST - Phase: Executor spawn command corrected. Files inspected or targeted: no code files; CLI help output and failed launch stderr only. Command running: none. Decision/blocker: first `codex exec` attempt failed before child materialization because `-a never` was passed in the wrong option position; no child code/test/doc work occurred. Next action: relaunch Executor with global CLI options before the `exec` subcommand.
- 2026-05-09 21:54:29 CEST - Phase: Progress request while Executor running. Files inspected or targeted: plan tail, scoped worktree status for GEK-002 owner files, and live Executor output. Command running: `codex -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never -C /Users/I560101/Project-Sat/mknoon-2/flutter_app exec ...` in tool session `23642`. Decision/blocker: no blocker yet; Executor has materialized and inspected the plan/worktree plus owner file references, with no GEK-002 owner code/test file touched at this heartbeat. Next action: continue bounded wait for Executor to add the regression, run the focused red check, implement if needed, and report exact test/gate evidence.
- 2026-05-09 21:54:19 CEST - Phase: Executor local pass started before owner-file inspection. Files inspected or targeted: GEK-002 plan, current dirty worktree status, and owner-file search hits only. Command running: none. Decision/blocker: unrelated dirty worktree entries are present and will not be reverted or normalized; implementation scope remains the GEK-002 regression plus smallest app-layer repair-correlation change. Next action: inspect owner files before adding the regression.
- 2026-05-09 21:55:43 CEST - Phase: Executor owner-file inspection completed before regression edit. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, pending repair model/repository interfaces, and in-memory message/pending-repair fakes. Command running: none. Decision/blocker: live diagnostics currently persist a no-envelope `live:` placeholder while durable missing-key replay persists an `offline:` placeholder keyed by real `messageId`; the regression should fail on duplicate visible rows before production edits. Next action: add the GEK-002 regression first.
- 2026-05-09 21:57:38 CEST - Phase: Executor red test starting after regression-only edit. Files inspected or targeted: added `GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival` in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; no production files changed yet. Command running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'`. Decision/blocker: expected red result should demonstrate duplicate live/offline visible pending rows or equivalent missing convergence. Next action: run the focused red command and stop if it unexpectedly passes.
- 2026-05-09 21:58:03 CEST - Phase: Executor red test completed. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command result: failed as expected, exit 1. Notable snippet: expected `null` for `msgRepo.getMessage(live:group-1:peer-sender:2:1)` after durable replay queue, actual was a live pending `GroupMessage`; flow also showed one offline `GROUP_PENDING_KEY_REPAIR_QUEUED` for `msg-gek002-replay`. Decision/blocker: not evidence-only; proceed to smallest app-layer correlation change. Next action: implement live no-envelope placeholder supersession when durable replay creates the canonical offline repair.
- 2026-05-09 21:58:39 CEST - Phase: Executor implementation starting. Files inspected or targeted: `lib/features/groups/application/group_pending_key_repair_service.dart`. Command running: none. Decision/blocker: no repository/schema change required; existing `getPendingRepairsForGroupEpoch`, `finalizeRepaired`, and `GroupMessageRepository.deleteMessage` can remove matching pending no-envelope `live:` placeholders from the visible timeline while leaving the durable `offline:` repair canonical. Next action: patch the app-layer queue path only.
- 2026-05-09 21:59:26 CEST - Phase: Executor implementation completed. Files touched: `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and this plan. Command running: none. Decision/blocker: production change stayed app-layer only; durable replay queue now supersedes matching pending no-envelope live diagnostic repairs by deleting the synthetic live message and finalizing that live repair, while the real `offline:` message repair remains pending. Next action: rerun the focused GEK-002 command as the fastest structural validation.
- 2026-05-09 21:59:54 CEST - Phase: Executor focused GEK-002 green/structural validation completed. Files inspected or targeted: `lib/features/groups/application/group_pending_key_repair_service.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command result: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK002 live decrypt failure plus durable replay repairs one visible message after key arrival'` passed, exit 0. Notable evidence: flow emitted `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED` before `GROUP_PENDING_KEY_REPAIR_QUEUED`, then repaired `msg-gek002-replay`; test ended `+1: All tests passed!`. Decision/blocker: changed seam compiles and focused regression is green. Next action: run required focused owner regression commands in order.
- 2026-05-09 22:00:09 CEST - Phase: Executor required direct test 2 starting. Files inspected or targeted: `test/features/groups/application/group_message_listener_test.dart`. Command running: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR live decryption failure creates repair placeholder and trigger without normal delivery'`. Decision/blocker: verify existing live diagnostic placeholder behavior remains intact before durable replay correlation. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:00:27 CEST - Phase: Executor required direct test 2 completed. Files inspected or targeted: `test/features/groups/application/group_message_listener_test.dart`. Command result: passed, exit 0; output ended `+1: All tests passed!`. Decision/blocker: live diagnostic-only placeholder behavior remains intact. Next action: run required direct test 3.
- 2026-05-09 22:00:36 CEST - Phase: Executor required direct test 3 starting. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'`. Decision/blocker: verify existing durable future-epoch repair path still queues and repairs. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:00:51 CEST - Phase: Executor required direct test 3 completed. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command result: passed, exit 0; output ended `+1: All tests passed!`. Decision/blocker: durable future-epoch repair path remains green. Next action: run required direct test 4.
- 2026-05-09 22:01:01 CEST - Phase: Executor required direct test 4 starting. Files inspected or targeted: `test/features/groups/application/group_key_update_listener_test.dart` and pre-existing dirty key-update listener files. Command running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save'`. Decision/blocker: verify key arrival still triggers pending replay retry after save; note key-update files had pre-existing unrelated dirt before this session. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:01:16 CEST - Phase: Executor required direct test 4 completed. Files inspected or targeted: `test/features/groups/application/group_key_update_listener_test.dart`. Command result: passed, exit 0; output ended `+1: All tests passed!`. Decision/blocker: key-arrival retry trigger remains green despite pre-existing key-update worktree dirt. Next action: run required direct test 5.
- 2026-05-09 22:01:26 CEST - Phase: Executor required direct test 5 starting. Files inspected or targeted: `test/features/groups/application/group_key_update_listener_test.dart`. Command running: `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR rejected key updates do not trigger pending repair'`. Decision/blocker: verify rejected key updates still do not trigger pending repair. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:01:41 CEST - Phase: Executor required direct test 5 completed. Files inspected or targeted: `test/features/groups/application/group_key_update_listener_test.dart`. Command result: passed, exit 0; output ended `+1: All tests passed!`. Decision/blocker: rejected key updates still do not trigger pending repair. Next action: run required direct test 6.
- 2026-05-09 22:01:51 CEST - Phase: Executor required direct test 6 starting. Files inspected or targeted: `test/core/bridge/go_bridge_client_test.dart`. Command running: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group decryption failure push event reaches diagnostics stream without invoking group message callback'`. Decision/blocker: verify bridge diagnostic routing remains unchanged; GEK-002 did not touch bridge code. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:02:15 CEST - Phase: Executor required direct test 6 completed. Files inspected or targeted: `test/core/bridge/go_bridge_client_test.dart`. Command result: passed, exit 0; output ended `+1: All tests passed!`. Decision/blocker: bridge diagnostic routing remains green and no normal callback regression was observed. Next action: run full owner-file rerun 7.
- 2026-05-09 22:02:26 CEST - Phase: Executor required full owner-file test 7 starting. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command running: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Decision/blocker: full drain owner suite should cover the new regression plus surrounding offline replay behaviors. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:02:56 CEST - Phase: Executor required full owner-file test 7 completed with failure under triage. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command result: failed, exit 1. Notable snippets: `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply` expected saved `sync-cursor-msg` but got null at line 1119; `listener replay failure does not commit cursor or receipts` expected cursor null but got empty string at line 1211; `duplicate receipt replay is idempotent` expected one receipt but got zero at line 1319. Decision/blocker: failures occur before the new GEK-002 test and do not exercise `group_pending_key_repair_service.dart`; triage needed before any fix attempt. Next action: run the failing selectors individually to classify.
- 2026-05-09 22:03:47 CEST - Phase: Executor full owner-file test 7 triage. Files inspected or targeted: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/domain/models/group_backlog_retention_policy.dart`, and retention handling in `drain_group_offline_inbox_use_case.dart`. Triage command result: focused `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply` also failed alone, exit 1, with `sync-cursor-msg` null after decrypt. Classification: environment/date-sensitive unrelated-but-required failure; the test fixture uses `2026-05-01T12:00:00Z`, and on current date `2026-05-09` the seven-day backlog cutoff is after that timestamp, so the message is skipped before persistence. Decision/blocker: not caused by GEK-002 production changes; do not broaden scope by rewriting older receipt fixtures in Executor pass. Next action: continue required owner/gate commands and document this blocker.
- 2026-05-09 22:04:01 CEST - Phase: Executor required full owner-file test 8 starting. Files inspected or targeted: `test/features/groups/application/group_message_listener_test.dart`. Command running: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: verify full group message listener owner suite after app-layer repair-service change. Next action: record pass/fail and triage if needed.
- 2026-05-09 22:04:35 CEST - Phase: Executor required full owner-file test 8 completed. Files inspected or targeted: `test/features/groups/application/group_message_listener_test.dart`. Command result: passed, exit 0; output ended `+95: All tests passed!`. Decision/blocker: full listener owner suite remains green. Next action: no conditional repository/helper/message/Go tests required because no repository/helper/message persistence/Go production paths changed; run named group gate.
- 2026-05-09 22:04:46 CEST - Phase: Executor required named gate starting. Files inspected or targeted: group gate membership via `./scripts/run_test_gates.sh groups`. Command running: `./scripts/run_test_gates.sh groups`. Decision/blocker: required gate may include the date-sensitive drain owner suite failure already classified; run it anyway for exact gate evidence. Next action: record pass/fail and triage any new failure signature.
- 2026-05-09 22:05:20 CEST - Phase: Executor required named gate completed. Files inspected or targeted: group gate membership via `./scripts/run_test_gates.sh groups`. Command result: passed, exit 0. Notable evidence: gate printed `Running Group Messaging Gate` and ended `+103: All tests passed!`; dependency resolver reported package updates available but no gate failure. Decision/blocker: named group gate is green. Next action: run `git diff --check`.
- 2026-05-09 22:05:30 CEST - Phase: Executor required whitespace check starting. Files inspected or targeted: current diff. Command running: `git diff --check`. Decision/blocker: verify no whitespace errors in landed changes. Next action: record pass/fail.
- 2026-05-09 22:05:45 CEST - Phase: Executor required whitespace check completed. Files inspected or targeted: current diff. Command result: `git diff --check` passed, exit 0 with no output. Decision/blocker: no whitespace errors. Next action: inspect final diff and worktree before Executor handoff.
- 2026-05-09 22:06:11 CEST - Phase: Executor completion/handoff. Files touched by this pass: `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and this GEK-002 plan. Command running: none. Decision/blocker: implementation completed but one required owner-file rerun remains failed due an unrelated/date-sensitive receipt fixture issue in older `PREREQ-GROUP-SYNC-RECEIPTS` tests; focused GEK-002, focused prerequisites, full listener owner file, named `groups` gate, and `git diff --check` are green. Next action: hand off to controller/QA for independent review; Executor does not close session as accepted.
- 2026-05-09 22:07:37 CEST - Phase: Controller post-Executor checkpoint before QA. Files inspected or targeted: plan tail, scoped status for GEK-002 owner files, final Executor output, `lib/features/groups/application/group_pending_key_repair_service.dart`, and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Command running: none. Decision/blocker: Executor completed the GEK-002 implementation and required focused/gate checks, but full `drain_group_offline_inbox_use_case_test.dart` still has a documented date-sensitive required-suite failure in older receipt tests; QA must independently decide whether that is blocking. Next action: spawn the fresh QA Reviewer with the landed diff and exact test evidence.
- 2026-05-09 22:08:36 CEST - Phase: QA Reviewer started. Files inspected or targeted: GEK-002 plan execution evidence, current worktree status, landed diff for `lib/features/groups/application/group_pending_key_repair_service.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, plus relevant owner-file context. Command running: none. Decision/blocker: no QA verdict yet; must independently validate GEK-002 scope, behavior, required evidence, and whether the full drain owner-file failure is acceptable under the plan's known-failure rules. Next action: inspect diff and run small confirmatory checks only as needed.
- 2026-05-09 22:09:35 CEST - Phase: QA confirmatory commands starting. Files inspected or targeted: landed GEK-002 production/test diff, drain retention cutoff owner code, and older receipt tests with hardcoded 2026-05-01 payload timestamps. Command running: focused GEK-002 regression, focused `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply`, and `git diff --check`. Decision/blocker: no verdict yet; commands are to confirm the implemented path and the date-sensitive unrelated failure classification without rerunning broad gates. Next action: record results and finalize QA verdict.
- 2026-05-09 22:11:18 CEST - Phase: QA Reviewer completed. Files inspected or targeted: GEK-002 plan, breakdown GEK-002 scope row, `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/domain/models/group_backlog_retention_policy.dart`, group gate definitions, and `/tmp/gek002-qa-review.md`. Command results: focused GEK-002 regression passed, exit 0; focused `PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply` failed, exit 1, with `sync-cursor-msg` null at line 1119; `git diff --check` passed, exit 0. Decision/blocker: accepted_with_explicit_follow_up; no GEK-002 blocking findings. The full drain owner-file failure is non-blocking for this execution because it is a pre-existing/date-sensitive receipt fixture using `2026-05-01T12:00:00Z`, now outside the seven-day retention cutoff on 2026-05-09, and GEK-002 did not alter receipt or retention semantics. Next action: no GEK-002 fix loop; track fixture-maintenance separately.
- 2026-05-09 22:12:39 CEST - Phase: Final verdict written. Files touched by this execution: `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and this GEK-002 plan. Command running: none. Decision/blocker: final execution verdict is `accepted_with_explicit_follow_up`; blocking issues remaining: none. Non-blocking follow-up: older `PREREQ-GROUP-SYNC-RECEIPTS` receipt fixtures should be refreshed or clock-controlled outside GEK-002 because their fixed `2026-05-01T12:00:00Z` timestamps are now outside the seven-day retention cutoff. Next action: return final response.
