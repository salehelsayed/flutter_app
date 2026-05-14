# GK-016 Implementation Plan: First Key Rotation Preserves Epoch 0 During Grace

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 12:30:28 CEST | Evidence Collector completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/group.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/group_security_harness_test.go`; `Test-Flight-Improv/test-gate-definitions.md`; dirty diff for `go-mknoon/node/pubsub.go` | Evidence confirms `UpdateGroupKey` preserves previous key epoch 0, but `hasKeyRotationGrace` rejects `PrevKeyEpoch == 0`; validator and decrypt fallback both depend on that helper. Existing tests cover 1 -> 2 grace, expiry, current epoch, initial no-grace state, and live decrypt, but not 0 -> 1. | Write the smallest `needs_code_and_tests` plan. |
| 2026-05-12 12:30:28 CEST | Planner started | Evidence summary above | Scope will stay in Go node grace semantics unless execution touches Dart/Flutter or exact evidence proves replay ownership. | Draft mandatory plan sections and regression contract. |
| 2026-05-12 12:30:28 CEST | Planner completed | This plan draft | Draft pins the epoch-0 previous-key contract, tests-first regressions, one-line production fix, gates, closure docs, scope guard, and known dirty-worktree handling. | Run Reviewer role for sufficiency. |
| 2026-05-12 12:33:53 CEST | Reviewer started | Full GK-016 draft plan; source row/breakdown evidence; direct Go code/test evidence summarized in this file | Reviewing for missing mandatory sections, stale assumptions, regression-first proof, gate gaps, overbroad scope, and dirty-worktree safety. | Complete sufficiency review and patch only structural gaps. |
| 2026-05-12 12:33:53 CEST | Reviewer completed | Full GK-016 draft plan | Reviewer verdict: sufficient as-is. The plan includes exact production target, two row-owned failing regressions, initial no-grace preservation, conditional Flutter rule, race requirement, closure docs, and no final program verdict. | Move to Arbiter role. |
| 2026-05-12 12:36:00 CEST | Arbiter completed | Reviewer findings and final plan | No structural blockers. The production target is narrow, row-owned tests are explicit, race/diff gates are required, and accepted differences are bounded to Go validator/decrypt proof. | Plan is execution-ready; implement tests first, then patch `hasKeyRotationGrace` only if the exact GK-016 RED appears. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 12:40:43 CEST | RED focused selector completed | `go-mknoon/node/pubsub_key_rotation_grace_test.go` | Added row-owned tests first. Focused pre-fix command `(cd go-mknoon && go test ./node -run '^TestGK016(GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace\|HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace)$' -count=1)` failed as expected: pure validation returned `reject:bad_signature`, and live delivery timed out after node B emitted `bad_signature_or_epoch` for keyEpoch 0. | Patch the narrow production guard in `hasKeyRotationGrace`. |
| 2026-05-12 12:41:40 CEST | GREEN focused selector completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go` | Removed the `PrevKeyEpoch > 0` exclusion while keeping non-empty `PrevKey`, non-zero `GraceDeadline`, and live deadline guards. `gofmt` ran. Focused GK-016 selector passed: `ok github.com/mknoon/go-mknoon/node 1.073s`. | Run adjacent grace and broader selectors. |
| 2026-05-12 12:42:10 CEST | Adjacent and broader selectors completed | `go-mknoon/node`; `go-mknoon/internal`; `go-mknoon/crypto` | Adjacent key-rotation grace selector passed: `ok github.com/mknoon/go-mknoon/node 3.572s`. Broader selector passed: `ok node 5.389s`, `ok internal 0.279s`, `ok crypto 0.561s`. | Run race selector because production Go changed. |
| 2026-05-12 12:42:27 CEST | Race selector first run classified | `go-mknoon/node/pubsub_key_rotation_grace_test.go`; `go-mknoon/node/node.go`; `go-mknoon/node/pubsub.go` | Initial race selector exposed adjacent test harness races in existing `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace` and `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires`: those tests assigned `nodeB.eventCallback` after `JoinGroupTopic`, while discovery goroutines could emit concurrently. The race was repo-owned adjacent test setup, not the epoch-0 predicate. | Fix adjacent tests by using `startLocalNodeForMultiRelayTestWithCollector` before joining. |
| 2026-05-12 12:43:15 CEST | Race selector passed after harness cleanup | `go-mknoon/node/pubsub_key_rotation_grace_test.go` | Updated the adjacent live grace/expiry tests to install node B's collector at node start, preserving behavior and eliminating the race. Focused race selector passed: `ok github.com/mknoon/go-mknoon/node 3.887s`. | Rerun non-race selectors after the harness cleanup. |
| 2026-05-12 12:44:00 CEST | Final implementation gates completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go`; this plan | Final focused selector passed `ok node 0.992s`; final adjacent selector passed `ok node 3.607s`; final broader selector passed `ok node 4.870s`, `ok internal 0.459s`, `ok crypto 0.641s`; final `git diff --check` passed with no output. Flutter/offline replay gates were not run because no Dart/Flutter files changed and exact evidence stayed in Go validator/decrypt behavior. Final execution verdict: accepted. | Run QA review, then closure audit. |
| 2026-05-12 12:50:00 CEST | Independent QA reviewer completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go`; this plan | QA verdict accepted. Reviewer verified the production change only removes `PrevKeyEpoch > 0` while retaining previous-key/deadline guards; signature/decrypt still require `env.KeyEpoch == keyInfo.PrevKeyEpoch`; row-owned tests cover validator acceptance plus missing previous key, zero deadline, expired deadline negatives, and live epoch-0 decrypt/delivery; adjacent harness cleanup installs collectors before node startup/join and keeps receive/drop assertions. QA reruns passed focused GK-016 selector `ok node 0.969s`, race selector `ok node 3.689s`, adjacent selector `ok node 3.673s`, and `git diff --check`. | Closure audit can proceed. |
| 2026-05-12 12:53:20 CEST | Completion Auditor completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go`; source matrix GK-016/GK-017 rows; breakdown GK-016 rows | Auditor verdict `closed`/`accepted`. Fresh focused rerun passed `ok github.com/mknoon/go-mknoon/node 1.159s`; `git diff --check` passed. Source matrix and breakdown GK-016 rows were still closure-writer pending at audit time. | Update source matrix, breakdown rows, and this plan closure note. |
| 2026-05-12 12:59:12 CEST | Closure Writer completed | Source matrix row GK-016; breakdown Gap-Closure Reconciliation, closure progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 67, Ordered Session Breakdown row 67; this plan | Closure docs now record GK-016 as `Covered`/`covered/accepted` with concrete production/test/gate evidence. No final program verdict was written because later rows remain unresolved. | Run scoped closure review, then continue from GK-017. |

## Closure Note

Closure status: accepted/closed at 2026-05-12 12:59:12 CEST.

GK-016 closed with a narrow code change plus row-owned Go node proof. `go-mknoon/node/pubsub.go::hasKeyRotationGrace` no longer excludes `PrevKeyEpoch == 0`; it still requires a non-empty previous key, a non-zero grace deadline, and a live deadline. Signature and decrypt paths still require `env.KeyEpoch == keyInfo.PrevKeyEpoch`, so initial join does not gain implicit grace.

Concrete evidence:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace` proves pure validator acceptance for an epoch-0 envelope during 0->1 grace and rejects missing previous key, zero deadline, and expired deadline.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace` proves live raw-publish delivery/decrypt of an epoch-0 message after node B rotates to epoch 1, observes `keyEpoch == 0`, and emits no `group:decryption_failed`.
- Existing live grace/expiry tests in the same file now install node B collectors before join, removing event-callback races while preserving receive/drop assertions.

Gate evidence: pre-fix focused RED failed with `reject:bad_signature` and `bad_signature_or_epoch`; executor passed final focused, adjacent, broader node/internal/crypto, race, and `git diff --check`; independent QA passed focused, race, adjacent, and `git diff --check`; Completion Auditor reran focused GK-016 with `ok github.com/mknoon/go-mknoon/node 1.159s` and `git diff --check`.

Accepted differences: full real-network proof is Recommended-only. Flutter/offline replay gates were not required because no Dart/Flutter files changed and the exact row evidence stayed in Go validator/decrypt behavior. Residual-only: none for GK-016. Source matrix row GK-016 and breakdown row 67 are now `Covered`/`covered/accepted`; GK-017 remains the next unresolved P0 row. No final program verdict was written.

## Final Plan

Add row-owned Go regressions first, then make the smallest production change in `go-mknoon/node/pubsub.go::hasKeyRotationGrace`: remove the `PrevKeyEpoch > 0` exclusion and rely on the existing `PrevKey != ""`, non-zero `GraceDeadline`, and live-deadline checks. Do not change the envelope format, signature data, crypto primitives, key update ordering, Dart replay, Flutter UI, or group membership policy.

## real scope

GK-016 owns exactly the first group-key rotation from epoch 0 to epoch 1 when an in-flight epoch-0 envelope arrives during the grace window.

In scope:

- Add row-named Go tests proving epoch 0 is accepted as an explicit previous epoch during grace.
- Patch only `hasKeyRotationGrace` if those tests fail because it excludes `PrevKeyEpoch == 0`.
- Preserve the existing initial-join contract: `PrevKeyEpoch == 0` alone is not grace state when `PrevKey == ""` or `GraceDeadline` is zero.
- Preserve existing previous-epoch grace behavior for 1 -> 2, grace expiry rejection, current-epoch acceptance, removed-sender rejection, same/older epoch update no-ops, and nil-key behavior.

Out of scope unless exact GK-016 evidence requires it:

- Key distribution or generation policy.
- Signature payload format.
- Group envelope wire shape.
- Dart offline replay, Flutter receive UI, database state, simulator/device harnesses, and final matrix verdicts.

## closure bar

GK-016 can close only when:

- A focused GK-016 pure validator/signature regression fails before the production fix and passes after it.
- A focused GK-016 decrypt proof, preferably live raw-publish delivery or at minimum `decryptGroupEnvelopePayload`, fails before the production fix and passes after it.
- Initial join with `PrevKeyEpoch == 0`, empty `PrevKey`, and zero `GraceDeadline` still has no grace state.
- Adjacent key-rotation grace tests still pass, including 1 -> 2 acceptance/decrypt, expiry rejection, current epoch during grace, update preservation, and join initial no-grace.
- Broader `go-mknoon/node`, `go-mknoon/internal`, and `go-mknoon/crypto` selectors pass.
- `go test -race` is run for the focused Go node selector because production code changes.
- `git diff --check` passes.
- Source matrix GK-016, breakdown row 67/session ledgers, and this plan closure note are updated after execution. No final program verdict is written.

## source of truth

Authoritative sources, in order:

- Current code and tests in `go-mknoon/node`, `go-mknoon/internal`, and `go-mknoon/crypto`.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate behavior.
- Source matrix row GK-016 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown row 67 / GK-016 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- This plan after it reaches `Status: execution-ready`.

If prose disagrees with code, code wins. If gate docs disagree with ad hoc gate descriptions, gate docs win. Existing dirty work outside this plan is presumed user/other-agent work and must not be reverted.

## session classification

`needs_code_and_tests`; closed as accepted with a code change plus row-owned Go node proof.

This was not docs-only. The source row named a production guard that blocked the required behavior at planning intake, and evidence confirmed both signature validation and decrypt fallback depended on that guard.

## exact problem statement

`UpdateGroupKey` correctly preserves the previous key and previous epoch on rotation. During the first rotation, that means current epoch 0 becomes `PrevKeyEpoch == 0` with a non-empty `PrevKey` and live `GraceDeadline`.

At planning intake, `hasKeyRotationGrace` required:

- `keyInfo != nil`
- `keyInfo.PrevKey != ""`
- `keyInfo.PrevKeyEpoch > 0`
- `!keyInfo.GraceDeadline.IsZero()`
- `now.Before(keyInfo.GraceDeadline)`

The `PrevKeyEpoch > 0` guard made epoch 0 impossible to accept as a previous epoch. Because `verifyGroupEnvelopeSignature` and `decryptGroupEnvelopePayload` only use the previous key when `env.KeyEpoch == keyInfo.PrevKeyEpoch && hasKeyRotationGrace(...)`, a valid epoch-0 envelope after a 0 -> 1 rotation was rejected before grace could work and could not decrypt if it reached the handler.

Required behavior:

- Epoch 0 is a valid explicit previous epoch only when `PrevKey` is non-empty and `GraceDeadline` is live.
- Initial join must still not create grace state when `PrevKeyEpoch == 0` but `PrevKey` is empty and `GraceDeadline` is zero.
- Expired grace and missing previous-key material remain rejected.

## files and repos to inspect next

Primary production:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/config.go`

Primary tests:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`

Supporting only if failures point there:

- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

Existing Go coverage:

- `TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace` covers validator acceptance for previous epoch 1 while current epoch is 2.
- `TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires` covers expiry rejection.
- `TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace` covers current epoch while grace exists.
- `TestGroupTopicValidator_RejectsRemovedSenderPreviousEpochDuringGrace` covers member policy before grace acceptance.
- `TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline` covers 1 -> 2 previous-key preservation and deadline stamping.
- `TestJoinGroupTopic_InitialKeyHasNoGraceState` covers initial join with empty `PrevKey`, `PrevKeyEpoch == 0`, and zero `GraceDeadline`.
- `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace` covers live decrypt/delivery for 1 -> 2.
- `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires` covers post-expiry no-delivery.

Missing:

- No GK-016 test proves 0 -> 1 rotation preserves and accepts epoch 0.
- No test proves `hasKeyRotationGrace` treats epoch 0 as valid only when previous key material and a live deadline exist.
- No row-owned decrypt/delivery proof exists for epoch 0 during grace.

## regression/tests to add first

Add tests before production edits:

1. `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace`

   - Generate an epoch-0 group key and an epoch-1 current key.
   - Build a valid epoch-0 envelope signed over `BuildGroupSignatureData(groupId, 0, ciphertext)`.
   - Use `GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1, PrevKey: epoch0Key, PrevKeyEpoch: 0, GraceDeadline: time.Now().Add(KeyRotationGracePeriod)}`.
   - Assert `validateGroupEnvelope(...) == "accept"`.
   - Add subcases or companion assertions that the same epoch-0 envelope rejects when `PrevKey` is empty, `GraceDeadline` is zero, or deadline is expired.
   - Expected RED before fix: reject as `reject:bad_signature`.

2. `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace`

   - Prefer the existing two-node raw-publish harness from `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace`.
   - Join node A and B with `GroupKeyInfo{Key: epoch0Key, KeyEpoch: 0}`.
   - Rotate only node B to `GroupKeyInfo{Key: epoch1Key, KeyEpoch: 1}` so B stores epoch 0 as previous.
   - Publish a raw epoch-0 envelope from node A.
   - Assert node B emits `group_message:received` with the plaintext and no `group:decryption_failed`.
   - Expected RED before fix: no receive event because the validator rejects as bad signature/epoch, or decrypt helper fails if the test exercises helper directly.

3. Keep or extend `TestJoinGroupTopic_InitialKeyHasNoGraceState` only if needed to make the no-grace contract explicit for epoch 0 initial join. Do not weaken this test.

If the live delivery test is unstable in the current dirty worktree, add a helper-level proof named `TestGK016DecryptGroupEnvelopePayloadAcceptsEpoch0PreviousKeyDuringFirstRotationGrace` and keep the live test as the preferred closure proof once the harness is stable.

## step-by-step implementation plan

1. Re-read the dirty diff for `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_key_rotation_grace_test.go`; preserve unrelated edits.
2. Add the pure validator/signature GK-016 test first.
3. Run only the focused GK-016 selector and record the expected RED.
4. Add the live decrypt/delivery GK-016 test, or the decrypt helper proof if the live harness is blocked by unrelated dirty worktree failures.
5. Run the focused GK-016 selector again and record expected RED for decrypt/delivery.
6. Patch only `hasKeyRotationGrace` by removing `keyInfo.PrevKeyEpoch > 0`. Do not add a new sentinel epoch or extra state flag.
7. Run `gofmt` on touched Go files.
8. Re-run the focused GK-016 selector until it passes.
9. Run the adjacent key-rotation grace selector.
10. Run the broader node/internal/crypto selector.
11. Run focused `go test -race` because production code changed.
12. Run `git diff --check`.
13. Update closure docs after passing evidence: source matrix GK-016, breakdown row 67/session ledgers, and this plan closure note/status. Do not write a final program verdict.

Stop early if the focused tests unexpectedly pass before production changes; in that case, inspect whether another dirty worktree edit already fixed `hasKeyRotationGrace`, then convert execution to evidence-and-doc closure without overwriting that edit.

## risks and edge cases

- Epoch zero can be confused with the zero value for "unset"; this plan permits it only when previous key material and a live deadline prove an explicit rotation state.
- A fix broader than `hasKeyRotationGrace` could accidentally create grace on initial join or accept stale unsigned/mismatched epochs.
- Validator acceptance without decrypt fallback would still lose messages, so GK-016 needs decrypt/delivery proof, not only signature proof.
- Grace expiry must remain strict; `now.Before(deadline)` should remain unchanged.
- Dirty worktree changes already exist in `go-mknoon/node/pubsub.go` and many group files; execution must preserve unrelated changes and avoid formatting unrelated files.

## exact tests and gates to run

Focused GK-016 selector:

```bash
(cd go-mknoon && go test ./node -run '^TestGK016(GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace|HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace|DecryptGroupEnvelopePayloadAcceptsEpoch0PreviousKeyDuringFirstRotationGrace)$' -count=1)
```

Adjacent key-rotation grace selector:

```bash
(cd go-mknoon && go test ./node -run 'TestGK016|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace|RejectsRemovedSenderPreviousEpochDuringGrace)|TestUpdateGroupKey_(PreservesPreviousKeyAndGraceDeadline|IgnoresSameEpochDifferentMaterial|IgnoresOlderEpochAfterCurrent)|TestJoinGroupTopic_InitialKeyHasNoGraceState|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)|TestGL014|TestGL015' -count=1)
```

Broader Go selector:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptGroupMessage|EncryptGroupMessage|DecryptionFailed|TestGK016' -count=1)
```

Race gate because production changed:

```bash
(cd go-mknoon && go test -race ./node -run '^TestGK016|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)
```

Diff hygiene:

```bash
git diff --check
```

Flutter/offline replay gates are required only if Dart/Flutter files are touched or exact execution evidence proves a row-owned Dart replay gap. Default GK-016 execution should not run Flutter gates.

## known-failure interpretation

- The focused GK-016 tests are expected to fail before the production fix because current `hasKeyRotationGrace` excludes `PrevKeyEpoch == 0`.
- A failure in existing 1 -> 2 grace tests after the fix is a GK-016 regression unless it reproduces on the pre-GK-016 baseline and is unrelated to touched code.
- A race-detector finding in touched Go node grace code is a GK-016 blocker.
- Failures in unrelated dirty Flutter, membership, relay, or docs files are not GK-016 blockers unless the executor touches those files or the failing test proves epoch-0 grace behavior is broken.
- `git diff --check` failures in files modified by this session are blockers; pre-existing whitespace failures outside touched files should be documented and left untouched unless the user asks otherwise.

## done criteria

- Row-owned GK-016 tests exist and show expected RED before the production fix or documented already-fixed evidence from an existing dirty edit.
- `hasKeyRotationGrace` no longer excludes epoch 0 when previous key material and live grace deadline exist.
- Initial join remains no-grace with empty `PrevKey`, `PrevKeyEpoch == 0`, and zero `GraceDeadline`.
- Focused, adjacent, broader Go, race, and diff hygiene gates pass or have documented unrelated pre-existing failures.
- Closure docs are updated after execution: source matrix GK-016, breakdown row 67/session ledgers, and this plan closure note/status.

## scope guard

Do not:

- Introduce a new epoch sentinel, grace-state enum, migration, protocol version, or wire-field change.
- Change `UpdateGroupKey` ordering except if focused evidence proves it no longer preserves epoch 0 as previous.
- Change signature data, encryption/decryption primitives, group config membership policy, sender-device binding, publish routing, offline inbox replay, Flutter listeners, or UI.
- Broaden into later GK/GM rows or write a final program verdict.
- Reformat or revert unrelated dirty files.

## accepted differences / intentionally out of scope

- Epoch 0 is accepted as a previous epoch only through explicit grace state; the unset zero value remains harmless when `PrevKey` is empty or `GraceDeadline` is zero.
- Full real-network, simulator, packet-capture, and Flutter app proof are out of scope unless execution touches those layers.
- Offline replay epoch handling is out of scope by default because GK-016 evidence points to Go validator/decrypt grace only.
- This plan does not decide whether all products should allow in-flight epoch-0 messages forever; it implements only the existing finite grace-window model.

## dependency impact

GK-016 is a P0 blocker for first-rotation reliability. Later key-epoch, delivery, and group-message rows can rely on the first rotation behaving like later rotations only after this row closes with Go validator and decrypt proof. If GK-016 changes beyond `hasKeyRotationGrace`, later sessions must re-read the updated grace contract before planning.

## Reviewer Findings

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none blocking. The plan names the direct production file, existing helper/test files, two row-owned GK-016 regressions, adjacent grace selectors, broader Go selectors, focused race, and `git diff --check`.

Stale or incorrect assumptions at planning review: none found. At review time before execution, the code still had `PrevKeyEpoch > 0` inside `hasKeyRotationGrace`, while `UpdateGroupKey` stored the previous epoch without excluding zero.

Overengineering: none found. The production change is constrained to removing one invalid guard and explicitly rejects new sentinels, migrations, state enums, wire changes, and Flutter work.

Decomposition: sufficient. Tests are ordered before production change, and closure docs are separated from implementation evidence.

Minimum needed to proceed: run Arbiter; if no structural blocker is found, mark execution-ready.

## Arbiter Decision

Structural blockers: none.

Accepted differences:

- Direct Go validator/decrypt proof is sufficient for closure because the source matrix marks full real-network proof as Recommended.
- Flutter/offline replay gates are conditional and not required unless execution touches Dart/Flutter files or exact evidence proves a row-owned replay gap.
- The production fix may be one predicate change if the focused RED proves `PrevKeyEpoch == 0` is the only blocker.

Final arbiter verdict: execution-ready. Implement row-owned tests first, preserve unrelated dirty work, and do not write a final program verdict while later rows remain unresolved.
