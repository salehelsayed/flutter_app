# GK-019 Implementation Plan

Status: accepted/closed

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Session: `GK-019 | Jump from epoch 0 to 2 preserves only allowed prior epoch`

## Planning Progress

- `2026-05-12 14:51:00 CEST` - Planner completed. Files inspected since last update: evidence collector findings and adjacent GK-016/GK-017/GK-018 closure patterns. Decision/blocker: drafted a narrow tests-first plan; no production edit is planned unless row-owned GK-019 tests fail. Next action: run reviewer sufficiency pass.
- `2026-05-12 14:51:00 CEST` - Reviewer started. Files inspected since last update: full GK-019 planning draft. Decision/blocker: draft has the mandatory sections; review will check scope, exact tests, gates, known-failure handling, and stop rule. Next action: record sufficiency findings.
- `2026-05-12 14:55:00 CEST` - Reviewer completed. Files inspected since last update: full GK-019 planning draft, mandatory-section scan, and exact gate commands. Decision/blocker: sufficient as-is; no structural blocker found. Next action: run arbiter classification.
- `2026-05-12 14:55:00 CEST` - Arbiter started. Files inspected since last update: reviewer sufficiency notes and full GK-019 planning draft. Decision/blocker: no reviewer-identified structural blocker; classify incremental details and accepted differences. Next action: record arbiter decision and final readiness.
- `2026-05-12 14:57:00 CEST` - Arbiter completed. Files inspected since last update: reviewer sufficiency notes and full GK-019 planning draft. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: execute GK-019 later using the row-owned tests-first contract and required gates.

## Execution Progress

- `2026-05-12 14:51:15 CEST` - Phase: contract extracted / local fallback selected. Files inspected or touched: this GK-019 plan, `implementation-execution-qa-orchestrator` skill, source/breakdown GK-019 search results. Command currently running: none. Decision/blocker: no spawned sub-agent tool is available in this session; running the bounded local sequential fallback under the GK-019-only contract. Next action: inspect owner tests and add row-owned GK-019 regressions before any production edit.
- `2026-05-12 14:51:15 CEST` - Phase: Executor started. Files inspected or touched: dirty worktree status and owner-helper search across `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `pubsub_test.go`, `pubsub_delivery_test.go`, `group_security_harness_test.go`, and `pubsub_decryption_failure_test.go`. Command currently running: none. Decision/blocker: worktree is already dirty with unrelated source matrix, breakdown, Go, Flutter, and untracked plan files; preserve existing changes and scope edits to GK-019 test/progress files. Next action: patch `pubsub_key_rotation_grace_test.go` with the four required tests.
- `2026-05-12 14:58:05 CEST` - Phase: Executor test patch completed. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go` and this plan. Command finished: `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go`. Decision/blocker: four row-owned `TestGK019...` regressions were added; no production edit was made. Next action: run focused GK-019 selector.
- `2026-05-12 14:58:23 CEST` - Phase: focused gate finished. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Command finished: `(cd go-mknoon && go test ./node -run 'TestGK019' -count=1)`. Result: passed, `ok github.com/mknoon/go-mknoon/node 3.724s`. Decision/blocker: no focused GK-019 failure; no production edit needed from this gate. Next action: run required adjacent GK-016/GK-017/GK-018/GK-019 grace selector.
- `2026-05-12 14:58:39 CEST` - Phase: adjacent gate finished. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Command finished: `(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GK019|GroupTopicValidator_AcceptsPreviousEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires|UpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|JoinGroupTopic_InitialKeyHasNoGraceState)' -count=1)`. Result: passed, `ok github.com/mknoon/go-mknoon/node 9.374s`. Decision/blocker: adjacent grace/expiry guards remain green. Next action: run required broader Go selector.
- `2026-05-12 14:59:00 CEST` - Phase: broader Go gate finished. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Command finished: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018|GK019' -count=1)`. Result: passed, `ok github.com/mknoon/go-mknoon/node 14.561s`, `ok github.com/mknoon/go-mknoon/internal 0.283s`, `ok github.com/mknoon/go-mknoon/crypto 0.894s`. Decision/blocker: required broader selector is green. Next action: run `git diff --check`.
- `2026-05-12 14:59:05 CEST` - Phase: diff hygiene finished / local QA started. Files inspected or touched: full dirty worktree diff hygiene. Command finished: `git diff --check`. Result: passed with no output. Decision/blocker: no whitespace blocker. Next action: local QA review of GK-019 diff, scope adherence, and required evidence.
- `2026-05-12 15:03:21 CEST` - Phase: local QA Reviewer completed. Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this plan, targeted GK-019 test-name search, and target-file status. Command currently running: none. Decision/blocker: no blocking issues; all four required GK-019 proof seams exist and passed, production edits were not required by GK-019, race remains conditional/skipped, and Flutter/offline/device gates remain Recommended-only because this session did not change Dart/Flutter/transport files. Next action: write final execution verdict and run final diff-hygiene recheck.
- `2026-05-12 15:03:21 CEST` - Phase: final execution verdict written. Files inspected or touched: this GK-019 plan. Command currently running: none. Decision/blocker: `accepted`; no blockers and no non-blocking GK-019 follow-ups remain. Next action: run final `git diff --check` after the verdict edit.
- `2026-05-12 15:03:34 CEST` - Phase: final diff hygiene recheck finished. Files inspected or touched: full dirty worktree diff hygiene after final verdict edit. Command finished: `git diff --check`. Result: passed with no output. Decision/blocker: no whitespace blocker; GK-019 execution is complete. Next action: stop and report final execution result.

## real scope

Own exactly source row `GK-019 | Jump from epoch 0 to 2 preserves only allowed prior epoch`.

In scope:
- Add exact row-owned Go node tests for a direct current E0 to E2 key update.
- Prove the app's current rotation contract explicitly: E2 is current, E0 is the one previous epoch allowed only during live grace, and skipped E1 is unsupported because no E1 key was ever installed.
- Use direct `UpdateGroupKey` state inspection, pure validator and/or direct decrypt matrix proof, and live raw-publish receive/reject proof.
- Make production changes only if the exact GK-019 tests expose a real repo-owned failure in the current validator/decrypt/key-state behavior.

Out of scope:
- Do not edit the source matrix or breakdown closure rows during planning.
- Do not write a final program verdict.
- Do not change Flutter, Dart offline replay, relay/device orchestration, membership, authorization, envelope schema, or key-distribution architecture unless exact GK-019 tests prove that surface is the failing owner.
- Do not reopen GK-016, GK-017, or GK-018 except as adjacent regression guards.

## closure bar

GK-019 is good enough when row-owned proof shows that a direct 0->2 key update has a single explicit allowed prior epoch:

- `UpdateGroupKey` from E0 to E2 stores E2 as current and E0 as `PrevKey` / `PrevKeyEpoch` with a live `GraceDeadline`.
- No E1 key is implicitly synthesized, stored, or accepted.
- A valid E0 envelope is accepted/decrypted only during the live grace window and rejects after the deadline.
- A valid E1 envelope rejects through validator/decrypt paths because epoch 1 is neither current nor the stored previous epoch.
- A valid E2 envelope is accepted/decrypted as current.
- The live raw-publish path receives E0 during live grace, rejects E1 with no payload/decryption side effects, and receives E2.
- Required focused, adjacent, broader Go selectors and diff hygiene pass.

## source of truth

- Current code and tests win over stale prose.
- Source matrix row `GK-019` is authoritative for the row goal: update key to E2, deliver E0/E1/E2 envelopes, and make the allowed-epoch contract explicit.
- Breakdown ordered row 70 is now `covered/accepted` by exact row-owned GK-019 Go node evidence.
- Closed GK-016/GK-017/GK-018 context is accepted: epoch 0 can be previous during first-rotation live grace; expired previous E1 rejects; current E2 remains accepted after expired previous grace.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gates; if it conflicts with `scripts/run_test_gates.sh`, the script wins.

## session classification

`covered/accepted`

This closed tests-only because the exact GK-019 tests passed against existing production behavior. No GK-019 production edit was required.

## exact problem statement

The repo lacks row-owned proof for the skipped-epoch case where a node moves directly from epoch 0 to epoch 2. That gap matters because the app must not accidentally accept every lower epoch during grace, and it must not reject the current E2 traffic after a direct jump.

User-visible behavior to protect: after a participant receives a direct E2 key update while previously on E0, in-flight E0 messages are accepted only under the live grace contract, E1 messages are rejected because the app never received an E1 key, and E2 messages continue to validate, decrypt, and render.

Behavior that must stay unchanged: first-rotation E0 grace remains guarded by explicit previous-key material and live deadline; expired previous epochs reject; current epoch accepts; membership, writer authorization, signature binding, group mismatch, malformed envelope, and device binding checks are not relaxed.

## files and repos to inspect next

Primary production seams:
- `go-mknoon/node/pubsub.go`
  - `UpdateGroupKey`
  - `joinedGroupKeyInfo`
  - `hasKeyRotationGrace`
  - `verifyGroupEnvelopeSignature`
  - `decryptGroupEnvelopePayload`
  - `groupTopicValidator`
  - `handleGroupSubscription`
- `go-mknoon/node/group.go`
  - `GroupKeyInfo`

Primary tests:
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

Shared Go test helpers:
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`

Inspect only if tests expose lower-level failure:
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/group.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

Adjacent coverage already accepted:
- `TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace` proves epoch 0 can be accepted as a previous epoch during live 0->1 grace.
- `TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace` proves live raw-publish delivery for epoch 0 during first-rotation grace.
- `TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline`, `TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline`, and `TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline` prove expired previous E1 rejects and has no payload/decryption side effects.
- `TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline`, `TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline`, and `TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline` prove current E2 accepts after expired previous-key grace.
- `TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline` proves ordinary higher-epoch updates preserve the immediately previous key.
- `TestJoinGroupTopic_InitialKeyHasNoGraceState` proves initial join does not create an active grace state.

Current production evidence:
- `UpdateGroupKey` accepts any higher epoch and stores only the immediately previous local current key as `PrevKey` / `PrevKeyEpoch` with a new grace deadline.
- `verifyGroupEnvelopeSignature` accepts only `keyInfo.KeyEpoch` or `keyInfo.PrevKeyEpoch` under live grace.
- `decryptGroupEnvelopePayload` decrypts only with the current key or the stored previous key under live grace.
- `GroupKeyInfo` has one previous-key slot, not a historical key ring.

Missing row-owned coverage:
- No `GK019`, `GK-019`, or `TestGK019` test exists in `go-mknoon`, `lib`, or `test` outside this newly created plan file.

## regression/tests to add first

Add tests before any production edit.

1. `TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious`
   - Place in `go-mknoon/node/pubsub_key_rotation_grace_test.go` near the existing `UpdateGroupKey` and GK-016/GK-018 tests.
   - Start a local node, join a group at E0, call `UpdateGroupKey(groupId, &GroupKeyInfo{Key: epoch2Key, KeyEpoch: 2})`, and inspect `GetGroupKeyInfo`.
   - Assert current key/epoch is E2, previous key/epoch is E0, `GraceDeadline` is live and bounded, and no E1 material is stored.

2. `TestGK019GroupTopicValidatorAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`
   - Build distinct E0, E1, and E2 keys and envelopes for the same valid sender.
   - Use the key state produced by an actual E0 join plus direct E2 update, or an equivalent `GroupKeyInfo` that exactly matches that state.
   - Assert live grace results: E0 `accept`, E1 `reject:bad_signature`, E2 `accept`.
   - Assert expired grace results: E0 `reject:bad_signature`, E1 `reject:bad_signature`, E2 `accept`.

3. `TestGK019DecryptGroupEnvelopePayloadAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`
   - Parse E0, E1, and E2 envelopes.
   - Assert live grace decrypt results: E0 plaintext succeeds, E1 returns `no group key available for epoch 1`, E2 plaintext succeeds.
   - Assert expired grace results: E0 returns `no group key available for epoch 0`, E1 still returns `no group key available for epoch 1`, E2 plaintext succeeds.

4. `TestGK019HandleGroupSubscriptionDirectJumpReceivesAllowedEpochsOnly`
   - Use the existing two-node raw-publish harness.
   - Join node A and node B at E0, direct-update both to E2, and verify node B's key state is current E2 / previous E0 with live grace.
   - Publish an E0 raw envelope and assert node B receives `group_message:received` with `keyEpoch == 0`.
   - Publish an E1 raw envelope and assert node B emits `group:validation_rejected` reason `bad_signature_or_epoch` with `keyEpoch == 1`, and emits no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed` after that baseline.
   - Publish an E2 raw envelope and assert node B receives `group_message:received` with `keyEpoch == 2` and no validation/decryption failure after that baseline.

## step-by-step implementation plan

1. Add the `UpdateGroupKey` direct 0->2 state test.
2. Run the focused GK-019 selector. If it fails, inspect only `UpdateGroupKey`, `joinedGroupKeyInfo`, and `GroupKeyInfo` state cloning.
3. Add the pure validator matrix test for E0/E1/E2 live and expired direct-jump states.
4. Run the focused GK-019 selector. If it fails, inspect only `verifyGroupEnvelopeSignature`, `hasKeyRotationGrace`, and the constructed key state.
5. Add the direct decrypt matrix test for E0/E1/E2 live and expired direct-jump states.
6. Run the focused GK-019 selector. If it fails, inspect only `decryptGroupEnvelopePayload` and current/previous key selection.
7. Add the live raw-publish test proving received E0, rejected E1, and received E2 after node B jumps 0->2.
8. Run the focused GK-019 selector again.
9. Make production changes only if an exact GK-019 test fails against current behavior. Keep any production edit scoped to `go-mknoon/node/pubsub.go` unless the failing assertion proves another owner.
10. Run the required adjacent selector, broader Go selector, and `git diff --check`.
11. Do not update the source matrix, breakdown closure rows, or final program verdict in this planning session.

## risks and edge cases

- A test that manually constructs the wrong key state could prove a scenario the app never creates; prefer actual `JoinGroupTopic` plus `UpdateGroupKey` state for at least the state proof and live raw-publish proof.
- E0 acceptance must be tied to non-empty previous-key material and a live `GraceDeadline`; initial join must not gain grace.
- E1 must reject even if the test has generated an E1 key locally, because that key was never installed into node B's `GroupKeyInfo`.
- Live raw-publish ordering can be flaky if publishing starts before topic peer discovery; use the existing `connectLocalGroupNodes` and `waitForGroupTopicPeerCount` pattern.
- Post-baseline assertions must isolate E1 side effects from the earlier accepted E0 and later accepted E2 messages.
- Any production fix must not turn the single previous-key slot into an unbounded historical key ring as part of GK-019.

## exact tests and gates to run

Required focused GK-019 Go node selector:

```bash
(cd go-mknoon && go test ./node -run 'TestGK019' -count=1)
```

Required adjacent GK-016/GK-017/GK-018/GK-019 grace/expiry selector:

```bash
(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GK019|GroupTopicValidator_AcceptsPreviousEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires|UpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|JoinGroupTopic_InitialKeyHasNoGraceState)' -count=1)
```

Required broader Go node/internal/crypto selector scoped to group envelope, key rotation, and decryption:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018|GK019' -count=1)
```

Required diff hygiene:

```bash
git diff --check
```

Conditional race gate, only if production Go concurrency behavior changes:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGK019|Test(GK016|GK017|GK018).*Grace|Test.*GroupTopicValidator|Test.*HandleGroupSubscription|Test.*UpdateGroupKey' -count=1)
```

Recommended-only unless Dart/Flutter/transport files change:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh group-real-network-nightly
```

## known-failure interpretation

- Treat any focused `TestGK019` failure as a GK-019 blocker until explained or fixed.
- Treat adjacent GK-016/GK-017/GK-018 failures as blockers if they touch epoch 0 grace, expired previous-epoch rejection, current epoch acceptance, key-state preservation, or live raw-publish side effects.
- The working tree is already dirty with many unrelated modified and untracked files. Preserve those changes. If a broader selector fails outside the GK-019 touched files or named epoch/key/decrypt paths, classify it as pre-existing or unrelated only with exact test names and failure text.
- Do not classify Recommended-only Flutter/device/relay failures as GK-019 blockers unless this session changes Dart, Flutter, transport, relay, or device orchestration files.
- If production code changes are required, race becomes required only for the affected Go concurrency path; otherwise race remains not required for tests-only GK-019 closure.

## done criteria

- Row-owned `TestGK019...` tests exist in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- Tests prove direct 0->2 state, validator acceptance/rejection matrix, direct decrypt matrix, and live raw-publish received/rejected behavior for E0/E1/E2.
- Focused GK-019 selector passes.
- Adjacent GK-016/GK-017/GK-018/GK-019 grace/expiry selector passes.
- Broader Go node/internal/crypto selector passes, or unrelated pre-existing failures are documented with exact proof.
- `git diff --check` passes.
- No production code changed unless an exact GK-019 test required it.
- No source matrix, breakdown closure rows, final program verdict, Dart/Flutter, device/relay, or unrelated product files are changed by this planning pass.

## scope guard

Do not broaden GK-019 into multi-rotation policy, historical key retention, key distribution recovery, relay inbox migration, Flutter offline replay entitlement, membership removal/re-add semantics, notification routing, or device orchestration.

Overengineering would include adding a key history store, changing the wire envelope schema, rewriting signature data, changing gate definitions, adding simulator-only proof, or treating skipped E1 as recoverable in this session.

The only contract to make explicit is current repo behavior for a direct E0 to E2 update: current E2 plus one stored previous E0 under live grace, with E1 unsupported.

## accepted differences / intentionally out of scope

- Direct Go node host proof is sufficient for GK-019 because the row's Required seams are local validator/decrypt and local raw-publish behavior; full device/relay evidence is Recommended-only unless transport/device files change.
- Flutter offline replay is intentionally not required unless Dart/Flutter replay files change; the Go live PubSub path is the owner for this row.
- The plan accepts `reject:bad_signature` / `bad_signature_or_epoch` for unsupported E1 at validator level and `no group key available for epoch 1` at direct decrypt level as the explicit skipped-epoch outcome.
- The plan does not require inventing an E1 recovery/backfill mechanism.
- Race proof remains conditional because tests-only Go additions should not alter production concurrency behavior.

## dependency impact

- GK-019 closure will give GK-020 a clear baseline: the current architecture has exactly one previous-key grace slot after a direct higher-epoch update.
- If GK-019 unexpectedly requires production key-state changes, GK-020 and later membership/removal rows must revisit assumptions about previous-key retention and skipped epoch behavior.
- If GK-019 closes as tests-only, later rows should not reopen skipped E1 acceptance unless a product requirement changes the rotation contract.

## reviewer sufficiency notes

Reviewer verdict: sufficient as-is.

Required questions:
- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None. The plan names the production seams, primary test file, shared helpers, four row-owned GK-019 tests, focused/adjacent/broader Go selectors, diff hygiene, conditional race rule, and Recommended-only Flutter/device gates.
- What assumptions are stale or incorrect? The planning-time open-row assumption is now superseded by closure: source row GK-019 is `Covered`, breakdown ordered row 70 is `covered/accepted`, and exact `TestGK019...` coverage exists.
- What is overengineered? Nothing structural. The four tests are the smallest coherent proof set for state, validator, decrypt, and live raw-publish seams; the plan does not add key history, schema changes, gate edits, or product UX.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. Each test has a single seam and a stop point before any production inspection expands.
- What is the minimum needed to make the plan sufficient? Already present: closure bar, scope guard, tests-first contract, exact gates, known-failure policy for the dirty worktree, and no source-matrix/breakdown closure edits during planning.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred:
- The executor may choose exact helper placement and assertion helper names inside `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- The executor may choose whether the validator matrix reuses the exact `GetGroupKeyInfo` state object from the state test setup or constructs an equivalent `GroupKeyInfo`, as long as at least one test proves actual `UpdateGroupKey` state for 0->2.
- If a focused GK-019 test fails, the executor should narrow investigation to the failing seam before expanding file scope.

Accepted differences intentionally left unchanged:
- Direct Go node proof is sufficient for GK-019; Flutter/offline and device/relay evidence remains Recommended-only unless those files change.
- Unsupported E1 is documented through validator/decrypt rejection, not through a new recovery mechanism.
- Race proof remains conditional because the expected implementation is tests-only and should not alter production concurrency behavior.

Final arbiter verdict: execution-ready.

## Final Execution Verdict

Final verdict: accepted.

Spawned-agent isolation used: no. No spawned sub-agent tool was available in this session, so execution used the bounded local sequential fallback recorded above.

Local sequential fallback used: yes.

Files changed by this GK-019 execution:
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-019-plan.md`

Tests added or updated:
- `TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious`
- `TestGK019GroupTopicValidatorAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`
- `TestGK019DecryptGroupEnvelopePayloadAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`
- `TestGK019HandleGroupSubscriptionDirectJumpReceivesAllowedEpochsOnly`

Exact tests and gates run:
- `(cd go-mknoon && go test ./node -run 'TestGK019' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 3.724s`
- `(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GK019|GroupTopicValidator_AcceptsPreviousEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires|UpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|JoinGroupTopic_InitialKeyHasNoGraceState)' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 9.374s`
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018|GK019' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 14.561s`; `ok github.com/mknoon/go-mknoon/internal 0.283s`; `ok github.com/mknoon/go-mknoon/crypto 0.894s`
- `git diff --check` passed with no output

QA status: accepted. Required tests exist, required gates passed, GK-019 scope remained tests-only, and no production change was required by the exact GK-019 proof.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Conditional gates skipped: race was skipped because this GK-019 execution did not change production Go concurrency behavior. Flutter/offline/device/relay gates were skipped because they are Recommended-only unless Dart/Flutter/transport files change, and this GK-019 execution did not change those files.

Why this session is safe to consider complete: direct 0->2 key update behavior is now row-owned by tests proving current E2, single stored previous E0 under live grace, unsupported/rejected E1, E0 expiry after grace, current E2 acceptance, and live raw-publish receive/reject behavior.

## Closure Note

Closure status: accepted/closed.

Closure docs updated: source matrix row GK-019; breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 70, and Ordered Session Breakdown row 70.

Maintenance evidence: `(cd go-mknoon && go test ./node -run 'TestGK019' -count=1)` passed in execution with `ok github.com/mknoon/go-mknoon/node 3.724s` and in Completion Auditor rerun with `ok github.com/mknoon/go-mknoon/node 3.771s`; adjacent and broader Go selectors passed in execution; `git diff --check` passed in execution and closure audit.

Residual-only items: none.

Accepted differences: GK-019 required no production code edit; race was not required because there was no production Go concurrency change; Flutter/offline/device/relay gates remained Recommended-only because no Dart/Flutter/transport files changed. Skipped E1 is explicitly unsupported, not recovered or backfilled.

Next row: GK-020 remains the next unresolved P0 row. No final program verdict was written.
