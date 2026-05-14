# GK-020 Implementation Plan

Status: accepted/closed

## Planning Progress

- 2026-05-12 15:36:00 CEST | Role: Planner completed | Files inspected since last update: none | Decision/blocker: Draft plan written as tests-first, implementation-ready, and scoped to GK-020; production edits are conditional only. | Next action: Reviewer will check sufficiency, gates, stale assumptions, and scope boundaries.
- 2026-05-12 15:37:00 CEST | Role: Reviewer started | Files inspected since last update: draft plan artifact | Decision/blocker: Reviewing for mandatory-section completeness, exact test/gate coverage, stale assumptions, and over-broad scope. | Next action: Record sufficiency findings and required adjustments.
- 2026-05-12 15:41:00 CEST | Role: Reviewer completed | Files inspected since last update: plan draft reread and section inventory | Decision/blocker: Sufficient with small clarifications; no structural blocker. Clarified actual sequential state reuse and raw-publish local validator handling. | Next action: Arbiter will classify findings and finalize execution readiness if no structural blocker remains.
- 2026-05-12 15:42:00 CEST | Role: Arbiter started | Files inspected since last update: reviewer findings and adjusted plan | Decision/blocker: Classifying reviewer findings as structural blockers, incremental details, or accepted differences. | Next action: Stop if no structural blocker remains; otherwise patch once and rerun review.
- 2026-05-12 15:43:00 CEST | Role: Arbiter completed | Files inspected since last update: reviewer findings and final adjusted plan | Decision/blocker: No structural blockers remain; reviewer clarifications are incorporated and remaining differences are accepted out of scope. | Next action: Plan is execution-ready for GK-020 only.

## real scope

Own exactly source row `GK-020`: multiple quick rotations `E0 -> E1 -> E2` must keep exactly the current key `E2` plus the immediately previous key `E1` during the live grace window. A too-old `E0` envelope must not validate, decrypt, or emit payload side effects after the second rotation, even if the first rotation's original grace window would still have been live.

Expected edit scope is tests-only in `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Production files are inspect-only unless the exact GK-020 tests expose a real repo-owned mismatch.

Do not edit the source matrix or session breakdown closure rows during planning. During execution/closure, the source matrix row must still become `Covered` with proof after the row-owned tests and gates pass.

## closure bar

GK-020 is good enough when row-owned automated proof shows all three key epochs after sequential quick rotations:

- state: after join at `E0`, update to `E1`, then update to `E2`, stored key state is current `E2`, previous `E1`, live grace deadline from the second rotation, and no stored/synthesized `E0` previous key remains;
- pure validator: `E0` rejects, `E1` accepts only during live current grace and rejects after grace expiry, and `E2` accepts both during and after previous-key grace expiry;
- direct decrypt: the same epoch matrix holds at the decrypt helper, including `E0` returning no key available/no plaintext;
- live raw-publish: node B rejects too-old `E0` with `bad_signature_or_epoch` and no payload/decrypt side effects, then receives `E1` during live grace and `E2` as current.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-020`.
- Active breakdown contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` ordered row 71.
- Current implementation truth: `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, and the current Go tests.
- Named-gate truth: `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md`; the script wins if prose is stale.
- On disagreement, current code and exact tests beat stale prose; this plan beats older broad matrix suggestions only for GK-020 execution scope.

## session classification

`implementation-ready`.

This is planned as `needs_tests_only` / tests-only. Production edits are allowed only if the row-owned GK-020 tests fail for a repo-owned behavior gap.

## exact problem statement

GK-020 is open because the repo lacks exact row-owned proof for the sequential rotation case `E0 -> E1 -> E2 quickly`. GK-016 through GK-019 prove adjacent first-rotation, grace-expiry, current-after-expiry, and direct `0 -> 2` jump behavior, but none proves that the second normal rotation overwrites the prior previous key so `E0` becomes too old immediately after `E2` becomes current.

The user-visible risk is accidental acceptance or decryption of too-old group messages after multiple fast rotations, which could widen replay/grace beyond the documented one-previous-key policy. Current and immediate previous epoch behavior must stay unchanged.

## files and repos to inspect next

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/group.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Before editing, re-read current hunks for any dirty files that execution touches, especially `go-mknoon/node/pubsub_key_rotation_grace_test.go` and any production Go file if a failure forces production work.

## existing tests covering this area

- `TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace` and `TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace` prove first `0 -> 1` grace behavior.
- `TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline`, `TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline`, and `TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline` prove previous epoch rejection after grace expiry.
- `TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline`, `TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline`, and `TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline` prove current `E2` remains accepted after previous grace expiry.
- `TestGK019UpdateGroupKeyJumpFromEpoch0To2PreservesOnlyEpoch0AsPrevious`, `TestGK019GroupTopicValidatorAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`, `TestGK019DecryptGroupEnvelopePayloadAcceptsOnlyEpoch0GraceAndCurrentEpoch2ForDirectJump`, and `TestGK019HandleGroupSubscriptionDirectJumpReceivesAllowedEpochsOnly` prove direct `0 -> 2` jump behavior.
- `TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline` proves one normal higher-epoch update preserves the immediately prior current key.

Missing: exact `TestGK020...` coverage for two normal rotations `E0 -> E1 -> E2`.

## regression/tests to add first

Add these tests first in `go-mknoon/node/pubsub_key_rotation_grace_test.go`:

1. `TestGK020UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious`
   - Join with `E0`, call `UpdateGroupKey(E1)`, then `UpdateGroupKey(E2)` quickly.
   - Assert current key/epoch is `E2`, previous key/epoch is `E1`, `E0` is not present as current or previous, and the live grace deadline is bounded by the second update.

2. `TestGK020GroupTopicValidatorAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations`
   - Build valid envelopes for `E0`, `E1`, and `E2`.
   - Use key state produced by the actual sequential `UpdateGroupKey(E1)` then `UpdateGroupKey(E2)` path, not a manually synthesized key window, except for the explicit expired-deadline copy.
   - With live `E2`/Prev `E1` grace: `E0` rejects as `reject:bad_signature`, `E1` accepts, `E2` accepts.
   - With expired previous-key grace: `E0` rejects, `E1` rejects, `E2` accepts.

3. `TestGK020DecryptGroupEnvelopePayloadAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations`
   - Use parsed envelopes and direct `decryptGroupEnvelopePayload`.
   - Use key state produced by the actual sequential `UpdateGroupKey(E1)` then `UpdateGroupKey(E2)` path, not a manually synthesized key window, except for the explicit expired-deadline copy.
   - With live grace: `E0` fails with `no group key available for epoch 0`, `E1` decrypts, `E2` decrypts.
   - With expired grace: `E0` fails, `E1` fails with `no group key available for epoch 1`, `E2` decrypts.

4. `TestGK020HandleGroupSubscriptionSequentialRotationsReceivesAllowedEpochsOnly`
   - Two local nodes join at `E0`, both rotate to `E1`, then both rotate to `E2`.
   - Assert node B state is current `E2` plus previous `E1`.
   - Connect topics, wait for peer counts, and unregister node A's local validator before raw publishes using the existing GK-019 pattern so the test observes node B's validator/decrypt behavior.
   - Publish `E0`, `E1`, `E2` raw envelopes in row order.
   - Assert node B emits `group:validation_rejected` reason `bad_signature_or_epoch` for `E0` keyEpoch `0` with no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed` after baseline.
   - Assert node B receives `E1` during live grace with `keyEpoch == 1`, then receives `E2` current with `keyEpoch == 2`, and neither acceptance emits validation/decryption failure side effects.

## step-by-step implementation plan

1. Inspect the current dirty hunks in `go-mknoon/node/pubsub_key_rotation_grace_test.go` so new tests fit the existing GK-016..GK-019 helper style without overwriting user changes.
2. Add a small GK-020 helper only if it removes duplication from the four planned tests. Keep it local to the test file and do not generalize key-window policy.
3. Add `TestGK020UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious`.
4. Add the pure validator matrix test.
5. Add the direct decrypt matrix test.
6. Add the live raw-publish test using existing collector, peer-count, validation-reject, and no-event helpers.
7. Run the focused GK-020 selector. If all tests pass, stop production work.
8. If a GK-020 test fails for a real product mismatch, patch only the minimum relevant Go seam:
   - `UpdateGroupKey` if stored previous-key state is wrong;
   - `verifyGroupEnvelopeSignature` only if validation accepts an epoch other than current or the immediately previous live-grace epoch;
   - `decryptGroupEnvelopePayload` only if decrypt accepts an epoch other than current or the immediately previous live-grace epoch.
9. Re-run focused, adjacent, broader, and hygiene gates.
10. During execution/closure, update the source matrix row to `Covered` and the breakdown GK-020 rows with exact proof only after tests and gates pass. Do not write a final program verdict.

## risks and edge cases

- Sequential rotation must overwrite the first previous key; it must not keep a hidden two-key grace window.
- `PrevKeyEpoch == 0` is valid for first rotation GK-016 but must not make `E0` acceptable after a later `E1 -> E2` rotation.
- Local raw publish can be blocked by the publisher's own validator; follow the GK-019 pattern and unregister node A's local validator only for raw-publish test mechanics before publishing `E0`, `E1`, and `E2`.
- Live tests must baseline collector events before each publish to avoid confusing earlier accepts/rejects with the target epoch.
- The worktree is already broadly dirty; execution must not revert or normalize unrelated edits.

## exact tests and gates to run

Focused GK-020 selector:

```bash
(cd go-mknoon && go test ./node -run '^TestGK020(UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious|GroupTopicValidatorAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|DecryptGroupEnvelopePayloadAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|HandleGroupSubscriptionSequentialRotationsReceivesAllowedEpochsOnly)$' -count=1)
```

Adjacent grace/rotation selector:

```bash
(cd go-mknoon && go test ./node -run 'TestGK01[6-9]|TestGK020|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|TestJoinGroupTopic_InitialKeyHasNoGraceState|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)
```

Broader Go node/internal/crypto selector scoped to group envelope, key rotation, and decryption:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GK020|GK019|GK018|GK017|GK016|GroupTopicValidator|UpdateGroupKey|GetGroupKeyInfo|JoinGroupTopic_InitialKeyHasNoGraceState|GroupEnvelope|GroupMessage|DecryptionFailed|EncryptGroupMessage|DecryptGroupMessage' -count=1)
```

Diff hygiene:

```bash
git diff --check
```

Conditional only if production Go concurrency behavior changes:

```bash
(cd go-mknoon && go test ./node -run 'GK020|UpdateGroupKey|GroupTopicValidator|DecryptGroupEnvelopePayload' -race -count=1)
```

Recommended-only unless Dart/Flutter/offline replay, transport, or device-facing group files change:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

## known-failure interpretation

- Focused GK-020 failures are actionable unless they are clearly harness-only; do not close the row on failing focused proof.
- Failures in adjacent/broader Go selectors that are in touched files or key-rotation/decrypt seams are blockers until fixed or explicitly proven pre-existing and unrelated.
- If `git diff --check` reports pre-existing whitespace in unrelated dirty files, record it separately and also run a scoped diff check for GK-020 touched files; GK-020 touched files must be clean.
- Flutter/offline/device/relay failures are not release-blocking for tests-only Go closure unless execution touches Dart/Flutter/transport files or changes a Flutter-visible group replay contract.

## done criteria

- Exact `TestGK020...` state, pure validator, direct decrypt, and live raw-publish tests exist and pass.
- Focused GK-020, adjacent GK-016..GK-020 grace/rotation, broader Go node/internal/crypto, and `git diff --check` evidence are recorded.
- Any production change, if needed, is minimal and covered by the same tests.
- No Dart/Flutter/offline/device/relay gates are required unless execution changes those files/contracts.
- Source matrix GK-020 is ready to be marked `Covered` with proof during the closure step; the planning pass itself does not edit it.
- No final program verdict is written.

## scope guard

Do not redesign group key distribution, add a multi-epoch key ring, add configurable replay windows, change wire format, alter encryption/signature data, change membership/removal rules, modify Flutter replay behavior, or widen into GK-021/GK-022 removal/re-add privacy scenarios.

Overengineering for this session includes adding generic key-window abstractions, simulator harnesses, new named gates, relay/device orchestration, or broad Go/Flutter refactors for a row that can be closed with direct Go node proof.

## accepted differences / intentionally out of scope

- The intended policy is exactly one previous key under live grace, not a documented multi-previous-key replay window.
- Direct Go node state/validator/decrypt/raw-publish host proof is sufficient for required GK-020 coverage; full real-network/device/relay proof remains Recommended-only.
- Flutter offline replay evidence is intentionally out of scope unless execution touches Dart/Flutter/offline replay files.
- GK-021 and GK-022 remove/re-add/decrypt-after-removal privacy cases remain separate rows.

## dependency impact

GK-020 closure supports later GK rows by pinning the one-previous-key rotation contract before remove/re-add and removed-member decryptability work. If GK-020 exposes a production policy mismatch, later rows that assume only current plus immediately previous key must pause until the corrected policy and tests are landed.

## Reviewer Findings

Sufficiency: sufficient with adjustments. The plan has all mandatory sections, direct row-owned tests, exact focused/adjacent/broader Go selectors, diff hygiene, conditional race criteria, known-failure rules, done criteria, scope guard, and closure rules.

Missing files, tests, regressions, or gates: none structurally missing after clarifying that validator/decrypt tests should use actual sequential `UpdateGroupKey` state and the raw-publish proof should explicitly unregister node A's local validator as in GK-019.

Stale or incorrect assumptions: none found. Current `UpdateGroupKey`, `verifyGroupEnvelopeSignature`, and `decryptGroupEnvelopePayload` support the intended one-previous-key policy, but no exact `TestGK020` exists yet.

Overengineering: none. The plan does not introduce a key ring, configurable window, simulator harness, or Flutter work unless execution touches those surfaces.

Decomposition: sufficient. Four row-owned tests separately cover stored state, pure validator, direct decrypt, and live raw-publish side effects.

Minimum needed for sufficiency: keep execution tests-first, add the four exact `TestGK020...` tests, stop production work if they pass, and record the named gates before closure.

## Arbiter Decision

Structural blockers: none.

Incremental details: the reviewer clarifications were incorporated directly: use actual sequential `UpdateGroupKey` state in validator/decrypt tests, and explicitly unregister node A's local validator for the raw-publish proof.

Accepted differences: direct Go node host proof is sufficient; full real-network/device/relay proof and Flutter offline replay proof remain Recommended-only unless execution touches those files or contracts. GK-021/GK-022 removal and post-removal decryptability stay out of scope.

Final classification: `implementation-ready`, tests-first, expected tests-only. The plan is safe to execute now for GK-020 only.

## Execution Progress

- 2026-05-12 15:37:21 CEST | Phase: contract extracted | Files inspected or touched: plan file, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go` | Command: none | Decision/blocker: GK-020 scope is tests-only unless exact tests expose a repo-owned production mismatch; required four `TestGK020...` seams and named Go gates extracted. Spawned-agent tool is unavailable in this environment, so execution proceeds under the skill's local sequential fallback with that limitation recorded. | Next action: local Executor pass will add only row-owned GK-020 tests in `pubsub_key_rotation_grace_test.go`.
- 2026-05-12 15:43:16 CEST | Phase: local Executor completed test additions | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, plan file | Command: `gofmt -w go-mknoon/node/pubsub_key_rotation_grace_test.go` | Decision/blocker: Added the four required `TestGK020...` seams and GK-020-only sequential key-state helpers; no production files edited. | Next action: run focused GK-020 selector.
- 2026-05-12 15:44:44 CEST | Phase: focused GK-020 gate completed | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, plan file | Command: `(cd go-mknoon && go test ./node -run '^TestGK020(UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious|GroupTopicValidatorAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|DecryptGroupEnvelopePayloadAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|HandleGroupSubscriptionSequentialRotationsReceivesAllowedEpochsOnly)$' -count=1)` | Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 4.731s`; no production mismatch exposed. | Next action: run adjacent grace/rotation selector.
- 2026-05-12 15:45:59 CEST | Phase: adjacent grace/rotation gate completed | Files inspected or touched: plan file | Command: `(cd go-mknoon && go test ./node -run 'TestGK01[6-9]|TestGK020|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|TestJoinGroupTopic_InitialKeyHasNoGraceState|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)` | Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 13.438s`. | Next action: run broader Go node/internal/crypto selector.
- 2026-05-12 15:46:20 CEST | Phase: broader Go selector completed | Files inspected or touched: plan file | Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GK020|GK019|GK018|GK017|GK016|GroupTopicValidator|UpdateGroupKey|GetGroupKeyInfo|JoinGroupTopic_InitialKeyHasNoGraceState|GroupEnvelope|GroupMessage|DecryptionFailed|EncryptGroupMessage|DecryptGroupMessage' -count=1)` | Decision/blocker: PASS, `ok github.com/mknoon/go-mknoon/node 17.121s`, `ok github.com/mknoon/go-mknoon/internal 0.725s`, `ok github.com/mknoon/go-mknoon/crypto 0.446s`. | Next action: run `git diff --check`.
- 2026-05-12 15:46:32 CEST | Phase: diff hygiene completed | Files inspected or touched: plan file | Command: `git diff --check` | Decision/blocker: PASS with no output. | Next action: local QA Reviewer pass will inspect scope adherence, required proof seams, and gate sufficiency.
- 2026-05-12 15:47:10 CEST | Phase: local QA Reviewer completed | Files inspected or touched: plan file, `go-mknoon/node/pubsub_key_rotation_grace_test.go` | Command: `rg -n "TestGK020(UpdateGroupKeySequentialRotationsKeepsOnlyEpoch1AsPrevious|GroupTopicValidatorAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|DecryptGroupEnvelopePayloadAcceptsOnlyEpoch1GraceAndCurrentEpoch2AfterSequentialRotations|HandleGroupSubscriptionSequentialRotationsReceivesAllowedEpochsOnly)|gk020SequentialRotationKeyInfo|assertGK020SequentialRotationKeyInfo" go-mknoon/node/pubsub_key_rotation_grace_test.go` | Decision/blocker: No blocking issues. Exact required GK-020 tests exist; required gates passed; no production file was edited by this pass; source matrix and breakdown closure rows were not updated by this pass. | Next action: write final execution verdict.
- 2026-05-12 15:47:20 CEST | Phase: final execution verdict written | Files inspected or touched: plan file | Command: none | Decision/blocker: `accepted`; sufficiency rule met with no blocking issues or required follow-ups. | Next action: stop GK-020 execution.

## Final Execution Verdict

`accepted`

QA status: no blocking issues. The four required GK-020 proof seams were added and all required GK-020, adjacent, broader Go, and diff hygiene gates passed. No production changes were made by this pass, so the conditional race, Flutter/offline, and device/relay gates were not required. Source matrix and breakdown closure rows remain for the separate closure step; no final program verdict was written here.

## Closure Note

Closure status: accepted/closed.

Closure docs updated: source matrix row GK-020; breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 71, and Ordered Session Breakdown row 71.

Maintenance evidence: focused GK-020 selector passed in execution with `ok github.com/mknoon/go-mknoon/node 4.731s` and in Completion Auditor rerun with `ok github.com/mknoon/go-mknoon/node 4.735s`; adjacent GK-016..GK-020 grace selector and broader Go node/internal/crypto selector passed in execution; `git diff --check` passed in execution and closure audit.

Residual-only items: none.

Accepted differences: GK-020 required no production code edit; race was not required because there was no production Go concurrency change; Flutter/offline/device/relay gates remained Recommended-only because no Dart/Flutter/transport files changed.

Next row: GK-021 remains the next unresolved P0 row. No final program verdict was written.
