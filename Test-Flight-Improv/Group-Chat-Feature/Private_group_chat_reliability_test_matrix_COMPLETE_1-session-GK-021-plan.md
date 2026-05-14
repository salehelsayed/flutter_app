Status: accepted/closed

# GK-021 Re-add Key Epoch Differs From Removal Epoch Plan

## Planning Progress

- 2026-05-12 16:20 CEST - Role: Arbiter completed - Files inspected since last update: source row GK-021, breakdown row 72, `go-mknoon/node/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/handle_incoming_group_message_use_case.dart`. - Decision/blocker: execution-ready tests-only plan; no production change is planned unless the row-owned RED proof shows stale E1 removed-package traffic is accepted. - Next action: run execution/QA against this plan.
- 2026-05-12 16:17 CEST - Role: Reviewer completed - Files inspected since last update: local fallback evidence after child planner no-progress. - Decision/blocker: plan must not overclaim GM-021 key-package proof as GK-021 epoch proof; add GK-021-named Go validator and live raw-publish coverage with E1 stale removed package versus E2 fresh re-add package. - Next action: finalize mandatory sections.
- 2026-05-12 16:15 CEST - Role: Planner completed - Files inspected since last update: Go group member schema and Dart config payload. - Decision/blocker: Go `GroupMember` has device/key-package identity but no membership joinedAt/removal window; the exact repo-owned closure is proof that the stale E1 removed package cannot pass the current re-add config while fresh E2 can. - Next action: reviewer pass.
- 2026-05-12 16:12 CEST - Role: Evidence Collector completed - Files inspected since last update: GK-016 through GK-020 grace tests, GM-021 key-package tests, Flutter re-add smoke and real harness. - Decision/blocker: existing GM-021 proves stale package rejection and fresh package metadata, but GK-021 lacks a row-named proof tying that rejection to old E1 versus fresh E2 group-key epochs. - Next action: draft a tests-only execution plan.
- 2026-05-12 16:10 CEST - Role: Controller fallback started - Files inspected since last update: child planner output. - Decision/blocker: spawned planner persisted only intake after bounded waits and was closed as no-progress; continue planning locally from collected repo evidence. - Next action: write execution-safe plan.

## real scope

Own source row GK-021 only: "Re-add key epoch differs from removal epoch." Add row-owned automated proof that, after C is removed under epoch E1 and represented in the re-add config only by a fresh device/key-package at epoch E2, A/B reject C's stale E1 removed-package traffic and accept C's fresh E2 traffic.

The expected implementation is tests-only in `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Production code changes are allowed only if the new row-owned proof shows the stale E1 removed package is accepted.

This session does not redesign group membership windows, add a multi-epoch key ring, change `GroupConfig` wire format, or alter GK-016 through GK-020 current/previous grace semantics for ordinary in-flight current-member traffic.

## closure bar

GK-021 closes because the source matrix row is now `Covered` with concrete evidence naming:

- a pure Go validator test where stale E1 removed-package traffic rejects under the re-add E2 config while fresh E2 accepts
- a live two-node raw-publish test where node B rejects the stale E1 removed package with no payload/decrypt side effects and receives the fresh E2 message
- focused, adjacent, broader Go gates and `git diff --check`

## source of truth

Current code and tests win over stale prose. Source row GK-021 defines the acceptance contract. Breakdown row 72 defines the row-owned session and now records `covered/accepted` tests-only evidence. Existing GM-021 closure is supporting evidence for key-package re-add identity, but it is not sufficient by itself because GK-021 must name the old E1 versus fresh E2 epoch proof.

## session classification

`implementation-ready` as tests-only first. If the new GK-021 tests fail because stale E1 removed-package traffic is accepted, reclassify the same session to code-and-tests and patch only the smallest Go validator seam needed to reject the stale removed package without weakening current E2 acceptance or prior grace rows.

## exact problem statement

The repo currently has general key-rotation grace coverage and separate GM-021 fresh key-package coverage. It does not have a GK-021-named proof that the re-add security boundary works when the removed member has old E1 material and later receives fresh E2 material. The user-visible risk is a removed/re-added member using stale removed credentials so Alice/Bob accept a message outside the fresh re-add epoch/package.

The behavior that must stay unchanged:

- current epoch E2 traffic from the re-added member's active device/key package is accepted
- stale removed device/key-package traffic is rejected before payload emission
- GK-016 through GK-020 previous-epoch grace remains valid for ordinary current-member in-flight messages
- malformed envelope, sender/device binding, key package, and signature checks keep their existing ordering unless the focused proof requires a narrow fix

## files and repos to inspect next

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/group.go`
- Supporting only, do not edit unless a failure proves it: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_delivery_test.go`
- Supporting app evidence only: `test/features/groups/integration/group_membership_smoke_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `lib/features/groups/application/send_group_message_use_case.dart`

## existing tests covering this area

- `TestGK016...` through `TestGK020...` in `go-mknoon/node/pubsub_key_rotation_grace_test.go` cover first-rotation grace, expired previous epoch, current epoch after grace, direct epoch jump, and sequential one-previous-key behavior.
- `TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage` in `go-mknoon/node/pubsub_test.go` proves a stale removed key package rejects and a fresh re-add package accepts, but it uses one group epoch and is GM-021-owned.
- `GM-006` and `GM-021` Flutter/harness coverage prove current app send paths use the fresh current key/package after re-add. They do not replace a GK-021 row-owned Go epoch validation proof.

## regression/tests to add first

Add focused GK-021 tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`:

1. `TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch`
   - Build old C device/signing key/key package and fresh C device/signing key/key package.
   - Build receiver config after re-add containing only fresh C and B.
   - Build receiver key info as current E2 with previous E1 and a live grace deadline, so the test proves stale C fails because of the removed package/device binding, not because previous-epoch grace is absent.
   - Assert old C E1 envelope rejects as `reject:unbound_device`.
   - Assert fresh C E2 envelope accepts.

2. `TestGK021HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch`
   - Join node A and node B with the post-re-add config and E2 key info.
   - Disable only node A's local validator for raw fanout.
   - Publish old C E1 removed-package envelope and assert node B emits `group:validation_rejected` with reason `unbound_device`, keyEpoch `1`, and no `group_message:received`, `group_reaction:received`, or `group:decryption_failed`.
   - Publish fresh C E2 envelope and assert node B receives exactly the fresh message at keyEpoch `2` without validation/decrypt failure.

## step-by-step implementation plan

1. Add small local helper functions only if needed for GK-021 readability, keeping them in `pubsub_key_rotation_grace_test.go`.
2. Add the pure validator GK-021 test using `buildTestDeviceEnvelope`.
3. Add the live raw-publish GK-021 test using `startLocalNodeForMultiRelayTestWithCollector`, `connectLocalGroupNodes`, `publishRawGroupEnvelope`, `waitForCollectedValidationReject`, and existing no-event assertions.
4. Run the focused GK-021 tests. If they fail because stale E1 removed-package traffic is accepted, patch only `activeMemberDeviceForEnvelope`, validator reject mapping, or adjacent Go validator code as the failure indicates.
5. Run adjacent key-rotation and GM-021 device/key-package selectors to prove the new proof did not regress earlier grace or re-add package behavior.
6. Run the broader Go selector and `git diff --check`.

## risks and edge cases

- A test that omits fresh/stale key package data would not prove re-add security; stale C must carry the old removed package and fresh C must carry the re-add package.
- A test with no previous E1 grace would be too weak; the stale E1 rejection must hold even while the receiver still has E1 as a live previous key.
- A production patch that disables all previous-epoch traffic would regress GK-016 through GK-020 and is out of scope.
- Flutter group config currently omits `joinedAt` from `toConfigJson`; do not pretend Go can enforce joinedAt/removal windows in this row without a separate protocol change.

## exact tests and gates to run

Focused:

```bash
(cd go-mknoon && go test ./node -run '^TestGK021(GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch|HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch)$' -count=1)
```

Adjacent:

```bash
(cd go-mknoon && go test ./node -run 'TestGK01[6-9]|TestGK020|TestGK021|TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|TestJoinGroupTopic_InitialKeyHasNoGraceState|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)
```

Broader:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GK021|GK020|GK019|GK018|GK017|GK016|GroupTopicValidator|UpdateGroupKey|GetGroupKeyInfo|JoinGroupTopic_InitialKeyHasNoGraceState|GroupEnvelope|GroupMessage|DecryptionFailed|EncryptGroupMessage|DecryptGroupMessage' -count=1)
```

Hygiene:

```bash
git diff --check
```

## known-failure interpretation

Any failure in the focused GK-021 tests is a current-row blocker. Adjacent or broader failures are GK-021 blockers only when they touch Go group envelope validation, group key selection, sender device/key-package binding, decrypt handling, or helper compile shape. Unrelated dirty-worktree failures must be recorded and not "fixed" by reverting unrelated user or previous-session changes.

## done criteria

- New row-named GK-021 tests are committed to the working tree.
- Focused, adjacent, broader, and diff-check commands pass.
- The source matrix GK-021 row is updated to `Covered` with exact test/gate evidence.
- The breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 72, and Ordered Session Breakdown row 72 are updated by closure.
- No final program verdict is written while GK-022 and later rows remain unresolved.

## scope guard

Do not add joinedAt to Go group config, change signature data, alter encrypted envelope format, introduce a multi-key sender policy, change Flutter send/replay code, or run device/simulator gates unless the focused Go proof shows a production or app seam actually changed. Do not close GK-022 or GK-023 inbox/decrypt/backlog rows from this work.

## accepted differences / intentionally out of scope

GK-021 closure can rely on Go validator/live raw-publish proof plus existing GM-006/GM-021 app evidence as support. The exact stale removed-window inbox decrypt/backlog behavior remains GK-022/GK-023. Physical device or relay proof is not required for this tests-only Go row unless execution touches Flutter, bridge request shape, or transport orchestration.

## dependency impact

GK-022 and GK-023 depend on this row not weakening the stale-credential rejection boundary. If GK-021 discovers that stale E1 removed-package traffic is accepted, keep GK-022/GK-023 open and complete the current-row Go validator fix before advancing.

## Execution Progress

- 2026-05-12 16:48 CEST - Phase: final execution verdict written - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this plan. - Decision/blocker: GK-021 implementation is accepted locally after child no-progress recovery; no production code changed and no current-row blocker remains. - Next action: run closure audit for source matrix and breakdown updates.
- 2026-05-12 16:45 CEST - Phase: controller-side QA rerun completed - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. - Command finished: `git diff --check` passed with no output. - Decision/blocker: diff hygiene is green. - Next action: write final execution verdict.
- 2026-05-12 16:44 CEST - Phase: controller-side QA rerun completed - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. - Command finished: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GK021|GK020|GK019|GK018|GK017|GK016|GroupTopicValidator|UpdateGroupKey|GetGroupKeyInfo|JoinGroupTopic_InitialKeyHasNoGraceState|GroupEnvelope|GroupMessage|DecryptionFailed|EncryptGroupMessage|DecryptGroupMessage' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 19.283s`, `ok github.com/mknoon/go-mknoon/internal 0.175s`, `ok github.com/mknoon/go-mknoon/crypto 0.211s`. - Decision/blocker: broader Go selector is green. - Next action: run diff hygiene.
- 2026-05-12 16:43 CEST - Phase: controller-side QA rerun completed - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. - Command finished: `(cd go-mknoon && go test ./node -run 'TestGK01[6-9]|TestGK020|TestGK021|TestGroupTopicValidator_ReaddFreshKeyPackageRejectsRemovedPackage|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestUpdateGroupKey_PreservesPreviousKeyAndGraceDeadline|TestJoinGroupTopic_InitialKeyHasNoGraceState|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 16.728s`. - Decision/blocker: adjacent grace/key-package selector is green. - Next action: run broader selector.
- 2026-05-12 16:41 CEST - Phase: controller-side recovery implementation completed - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. - Command finished: `gofmt -w node/pubsub_key_rotation_grace_test.go && go test ./node -run '^TestGK021(GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch|HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch)$' -count=1` passed: `ok github.com/mknoon/go-mknoon/node 3.758s`. - Decision/blocker: focused proof is green after strengthening stale E1 to use the current re-add device/transport/signing key with the removed E1 key package under live previous-epoch grace. - Next action: run adjacent selector.
- 2026-05-12 16:36 CEST - Phase: child no-progress recovery - Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this plan. - Decision/blocker: spawned execution child landed initial GK-021 tests but never returned a final verdict and was closed; controller strengthened the stale E1 case and ran required gates locally. - Next action: finish controller-side verification.
- 2026-05-12 16:25 CEST - Phase: Executor running - Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-021-plan.md`, git status output. - Decision/blocker: extracted GK-021 scope, done criteria, non-goals, and exact focused/adjacent/broader/hygiene commands; first pass remains tests-only in `go-mknoon/node/pubsub_key_rotation_grace_test.go`. - Next action: inspect row-owned Go tests and adjacent validator helpers without touching source matrix or breakdown closure rows.
- 2026-05-12 16:22 CEST - Phase: contract extracted - Files inspected or touched: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-021-plan.md`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`; git status reviewed. - Decision/blocker: execute GK-021 tests-only first; scoped write targets are this plan and `go-mknoon/node/pubsub_key_rotation_grace_test.go` unless focused GK-021 tests prove stale E1 removed-package traffic is accepted. - Next action: spawn isolated Executor.
- 2026-05-12 16:22 CEST - Phase: Executor spawned/running - Files inspected or touched: plan heartbeat updated. - Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -s danger-full-access -a never`. - Decision/blocker: isolated Executor is responsible for adding GK-021 tests and running focused/adjacent/broader Go selectors plus `git diff --check`, without source matrix or breakdown closure edits. - Next action: wait for Executor result.
- 2026-05-12 16:23 CEST - Phase: Executor spawn retry - Files inspected or touched: `~/.codex/config.toml` checked for approval config. - Decision/blocker: first spawn command failed before child materialization because `codex exec` does not accept `-a`; retrying with `approval_policy="never"` from config and explicit `model_reasoning_effort="xhigh"`. - Next action: spawn isolated Executor with corrected CLI flags.

## Final Execution Verdict

Verdict: `accepted`.

Files changed:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-021-plan.md`

What landed:

- `TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch` proves the post-re-add config contains only C's fresh E2 device/key package, rejects stale E1 removed-package traffic as `reject:unbound_device` even with live previous-epoch grace, rejects stale E1 traffic that uses the current re-add device/transport/signing key but the removed E1 key package, and accepts fresh E2 traffic.
- `TestGK021HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch` proves the live two-node raw-publish path rejects C's stale E1 removed package on the current re-add transport/signing key as `group:validation_rejected` reason `unbound_device` with `keyEpoch == 1`, emits no message/reaction/decrypt-failure side effects, then receives C's fresh E2 message with `keyEpoch == 2`.

Tests and gates:

- Focused GK-021 selector: `ok github.com/mknoon/go-mknoon/node 3.758s`.
- Adjacent grace/key-package selector: `ok github.com/mknoon/go-mknoon/node 16.728s`.
- Broader Go selector: `ok github.com/mknoon/go-mknoon/node 19.283s`, `ok github.com/mknoon/go-mknoon/internal 0.175s`, `ok github.com/mknoon/go-mknoon/crypto 0.211s`.
- `git diff --check` passed with no output.

Production code changed: none.

Blockers: none for GK-021 execution.

## Closure Note

Verdict: `accepted/closed`.

Source matrix row GK-021 is now `Covered`, and breakdown row 72 plus the Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, and Session Ledger all record `covered/accepted` evidence. No production, Dart/Flutter, or transport code changed.

Closure evidence:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK021GroupTopicValidatorRejectsRemovalEpochPackageAndAcceptsReaddEpoch`
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK021HandleGroupSubscriptionRejectsRemovalEpochPackageAndReceivesReaddEpoch`
- Focused GK-021 selector: `ok github.com/mknoon/go-mknoon/node 3.758s`
- Adjacent grace/key-package selector: `ok github.com/mknoon/go-mknoon/node 16.728s`
- Broader Go selector: `ok github.com/mknoon/go-mknoon/node 19.283s`, `ok github.com/mknoon/go-mknoon/internal 0.175s`, `ok github.com/mknoon/go-mknoon/crypto 0.211s`
- Completion Auditor focused rerun: `ok github.com/mknoon/go-mknoon/node 3.717s`
- `git diff --check` passed for execution and closure checks

Accepted differences: direct Go validator/live raw-publish host proof is sufficient for this row. Race, Flutter/offline, device/relay, and removed-window inbox backlog gates were not required because GK-021 landed tests-only and GK-022/GK-023 own the remaining inbox/backlog contracts. Residual-only: none for GK-021. GK-022 remains the next unresolved P0 row. No final program verdict was written.
