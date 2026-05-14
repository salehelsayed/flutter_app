# GK-017 Session Plan: Previous Epoch Rejected After Grace Deadline

Status: accepted/closed

## Execution Progress

- 2026-05-12T11:21:22Z - Role: Execution controller started via local sequential fallback because nested Executor/QA spawning is unavailable in this environment. Files inspected/touched: skill contract, this plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go`, `git status --short`. Decision/blocker: proceed GK-017-only; existing dirty worktree includes unrelated edits and pre-existing target-file edits, so preserve them and avoid production changes unless GK-017 tests prove the row-owned bug. Next action: extract contract, then add row-owned tests before any production edit.
- 2026-05-12T11:21:22Z - Role: Contract extracted. Files inspected/touched: this plan only. Decision/blocker: scope is row 68/GK-017 only; required first edits are three GK-017 Go tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`; `go-mknoon/node/pubsub.go` is conditional only if those tests fail for stale previous-epoch acceptance/decrypt/emission; required gates are focused GK-017, adjacent selector, broader Go selector, `git diff --check`; race selector is required only if production changes in this execution; Flutter/offline/groups gates are out of scope unless Dart/Flutter/group-send/transport files are touched. Next action: Executor local fallback will inspect helper placement and add only GK-017 tests.
- 2026-05-12T11:24:10Z - Role: Executor local fallback started. Files inspected/touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/group.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`. Decision/blocker: existing helpers cover GK-017 proof shape; add row-owned tests only. Next action: patch `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- 2026-05-12T11:26:02Z - Role: Executor local fallback completed test edit. Files inspected/touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this plan. Decision/blocker: added the three required GK-017 row-owned tests and ran `gofmt`; no production file was edited in this execution. Next action: start focused GK-017 gate `(cd go-mknoon && go test ./node -run 'TestGK017' -count=1)`.
- 2026-05-12T11:27:00Z - Role: Focused GK-017 gate finished. Files inspected/touched: no new file edits. Command: `(cd go-mknoon && go test ./node -run 'TestGK017' -count=1)`. Result: passed with `ok github.com/mknoon/go-mknoon/node 2.555s`. Decision/blocker: row-owned tests pass; production patch is not needed. Next action: start adjacent selector.
- 2026-05-12T11:27:38Z - Role: Adjacent selector finished. Files inspected/touched: no new file edits. Command: `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)|TestGK016|TestGK017' -count=1)`. Result: passed with `ok github.com/mknoon/go-mknoon/node 4.623s`. Decision/blocker: GK-016 live grace and adjacent expiry/current-epoch guards remain green. Next action: start broader Go selector.
- 2026-05-12T11:28:27Z - Role: Broader Go selector finished. Files inspected/touched: no new file edits. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|GK016|GK017' -count=1)`. Result: passed with `ok github.com/mknoon/go-mknoon/node 7.024s`, `ok github.com/mknoon/go-mknoon/internal 0.677s`, `ok github.com/mknoon/go-mknoon/crypto 0.951s`. Decision/blocker: broader host proof is green. Race selector skipped because this execution was tests-only and made no production edit. Next action: run `git diff --check`.
- 2026-05-12T11:29:00Z - Role: Diff hygiene gate finished. Files inspected/touched: no new file edits. Command: `git diff --check`. Result: passed with no output. Decision/blocker: required gates are complete; no Flutter/offline/groups gates required because no Dart/Flutter/group-send/transport files were touched by this execution. Next action: QA Reviewer local fallback will inspect diff, scope, and evidence.
- 2026-05-12T11:30:13Z - Role: QA Reviewer local fallback started. Files inspected/touched: this plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `git diff --name-only`, `git diff --stat`. Decision/blocker: checking exact test names, scope adherence, required gate evidence, race skip condition, and source matrix/breakdown non-touch policy. Next action: classify blocking issues, if any.
- 2026-05-12T11:30:13Z - Role: QA Reviewer local fallback completed. Files inspected/touched: this plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`. Decision/blocker: no blocking issues; the three exact GK-017 tests exist, required Go selectors and diff hygiene passed, production was not edited by this execution, race selector was correctly skipped, and no closure/source matrix/breakdown doc was edited by this execution. Next action: write final verdict as `accepted`.
- 2026-05-12T11:30:13Z - Role: Final verdict written. Files inspected/touched: this plan. Decision/blocker: accepted; GK-017 row-owned execution is tests-only complete. Next action: return final execution output.
- 2026-05-12T13:35:20+02:00 - Role: Completion Auditor completed. Files inspected/touched: this plan, source matrix GK-017/GK-018 rows, breakdown row 68 and adjacent rows, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, focused audit rerun, and `git diff --check`. Decision/blocker: `closed`/`accepted`; focused audit rerun passed `ok github.com/mknoon/go-mknoon/node 2.667s`, `git diff --check` passed, and no GK-017 production code changed. Next action: closure writer updates source matrix, breakdown rows, and this plan closure note.
- 2026-05-12T13:42:33+02:00 - Role: Closure Writer completed. Files inspected/touched: source matrix row GK-017; breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 68, Ordered Session Breakdown row 68; this plan. Decision/blocker: GK-017 is now `Covered`/`covered/accepted` with concrete test/gate evidence and no final program verdict. Next action: run scoped closure review, then continue from GK-018.

## Closure Note

Closure status: accepted/closed at 2026-05-12 13:42:33 CEST.

GK-017 closed as tests-only. No GK-017 production, Dart, Flutter, crypto, wire-format, membership, authorization, relay, or transport behavior changes were required; existing `go-mknoon/node/pubsub.go` validator/decrypt grace logic already rejected expired previous-epoch traffic once row-owned proof was added.

Concrete evidence:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline` proves a valid previous E1 envelope accepts during live grace, then rejects as pure `reject:bad_signature` after the E2/Prev E1 deadline, and also rejects when previous-key material or the grace deadline is absent.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline` proves direct decrypt succeeds during live grace and returns `no group key available for epoch 1` after the expired deadline.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline` proves live raw-publish validation emits `group:validation_rejected` reason `bad_signature_or_epoch` with `keyEpoch == 1`, and emits no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed`.

Gate evidence: executor/QA passed focused GK-017 (`ok node 2.555s`), adjacent grace/expiry/GK-016/GK-017 (`ok node 4.623s`), broader node/internal/crypto (`ok node 7.024s`, `ok internal 0.677s`, `ok crypto 0.951s`), and `git diff --check`. Completion Auditor reran focused GK-017 with `ok github.com/mknoon/go-mknoon/node 2.667s`; `git diff --check` passed.

Accepted differences: the original code-and-test disposition closed as tests-only because existing production behavior satisfied the expired-grace contract. Race was skipped because no GK-017 production code changed. Flutter/offline/groups and real-device/relay gates were not required because no Dart/Flutter/transport code changed and device/relay evidence is Recommended-only. Residual-only: none for GK-017. Source matrix row GK-017 and breakdown row 68 are now `Covered`/`covered/accepted`; GK-018 remains the next unresolved P0 row. No final program verdict was written.

## Planning Progress

- 2026-05-12T11:17:52Z - Role: Arbiter completed. Files inspected since last update: reviewed plan only. Decision/blocker: no structural blockers remain; plan is execution-ready for GK-017 only. Next action: implementation agent may execute the row-owned tests-first plan without broadening scope.
- 2026-05-12T11:17:52Z - Role: Arbiter started. Files inspected since last update: reviewer findings only. Decision/blocker: classifying reviewer adjustment; no blocker. Next action: decide whether another review loop is required.
- 2026-05-12T11:16:26Z - Role: Reviewer completed. Files inspected since last update: draft plan only. Decision/blocker: sufficient with one adjustment; add explicit direct decrypt-helper/no-key proof because the source row names validator/decrypt, while keeping live PubSub validator-first. Next action: Arbiter will classify this as incremental detail or structural blocker.
- 2026-05-12T11:16:26Z - Role: Reviewer started. Files inspected since last update: draft plan only. Decision/blocker: checking scope, closure bar, gate contract, stale assumptions, and overengineering risk; no blocker. Next action: answer sufficiency questions.
- 2026-05-12T11:13:17Z - Role: Planner completed. Files inspected since last update: no new files beyond Evidence Collector set. Decision/blocker: draft plan is implementation-ready and GK-017-only; start with row-owned tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`, patch production only if those tests fail for row-owned reasons. Next action: Reviewer will check sufficiency, scope guard, device/relay classification, and exact gate contract.

## Evidence Collector Findings

- At planning intake, source row GK-017 was still `Open`: current E2 with Prev E1 and expired grace had to reject a valid E1 envelope as `bad_signature_or_epoch` or with no key available. Adjacent GK-016 was `Covered` for accepting previous epoch during live first-rotation grace; GK-018 remained open for accepting the current epoch after grace expiry.
- At planning intake, breakdown row 68 still marked GK-017 `needs_code_and_tests | implementation-ready | code changes + tests`, but the row-owned note only said to add or verify the exact GK-017 regression. The prior GK-016 closure records that `hasKeyRotationGrace` now permits epoch 0 only when previous key material and a live deadline exist, with no Dart/Flutter changes.
- `go-mknoon/node/pubsub.go` uses `hasKeyRotationGrace` for both signature verification and decrypt. The predicate requires non-empty `PrevKey`, non-zero `GraceDeadline`, and `now.Before(GraceDeadline)`. Expired grace therefore makes `verifyGroupEnvelopeSignature` return false for `env.KeyEpoch == PrevKeyEpoch`, so `groupTopicValidator` emits `bad_signature_or_epoch`; `decryptGroupEnvelopePayload` separately returns `no group key available for epoch <n>` outside current/live-previous epochs.
- Existing tests already cover the shape but not as GK-017 row-owned closure proof: `TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires` proves the pure validator returns `reject:bad_signature`; `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires` proves raw-published previous epoch after expired grace emits no received payload and no decryption failure. The live test does not assert the `group:validation_rejected` reason/keyEpoch and is not GK-017 named.
- Relevant helpers exist for a precise row-owned test: `buildGroupKeyInfoWithGrace`, `publishRawGroupEnvelope`, `waitForCollectedValidationReject`, and `assertNoCollectedEventContainingAfter`.
- `go-mknoon/node/group.go`, `go-mknoon/internal/group_envelope.go`, and `go-mknoon/crypto/group.go` define data shape, envelope epoch field, and crypto operations but do not appear to need changes for GK-017 unless the row-owned Go tests fail.
- Gate definitions classify device/real-stack group tests as heavier nightly or optional/manual. The GK-017 matrix marks device/relay-style proof as Recommended, not Required.

## real scope

GK-017 owns only the source row: "Previous epoch is rejected after grace deadline." The executor should prove current E2 with previous E1 and an expired grace deadline rejects a valid E1 envelope before payload delivery.

Allowed changes:

- Add GK-017-named Go tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- Patch `go-mknoon/node/pubsub.go` only if the exact GK-017 tests fail because expired previous-epoch traffic is accepted, decrypted, or emitted.
- Update closure docs after execution only if the row-owned proof passes.

Not in scope:

- GK-018 current-epoch acceptance after expired grace.
- Changing key rotation policy, grace duration, wire format, crypto primitives, membership authorization, Dart offline replay, Flutter UI, relay behavior, or final program verdicts.

## closure bar

GK-017 is closed only when row-owned proof shows:

- A valid E1 envelope signed/encrypted with the previous E1 key rejects after local state is current E2 with `PrevKeyEpoch == 1` and an expired `GraceDeadline`.
- The pure validator rejects that envelope as `reject:bad_signature`, matching the live validator's emitted `group:validation_rejected` reason `bad_signature_or_epoch`.
- Direct decrypt-helper proof for the same expired previous epoch returns `no group key available for epoch 1`, or the plan records why the live validator-first path makes helper coverage redundant.
- Raw-publish/live node proof emits no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed` for the stale envelope.
- Existing GK-016 live-grace acceptance still passes, so the fix/proof does not collapse the allowed grace window.

## source of truth

- Source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-017; adjacent GK-016/GK-018 guard scope.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row 68 and recent GK-016 closure context.
- Code beats stale planning prose. If docs imply production changes but row-owned tests pass against existing code, keep production unchanged and close as tests-only.
- `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named Flutter gates and device/real-stack classification.

## session classification

`needs_code_and_tests`; closed as accepted tests-only after exact row-owned proof.

Evidence narrowed the likely work from "code changes + tests" to tests-first. Production changes were conditional and were not needed after the exact row-owned tests passed.

## exact problem statement

At planning intake, the open row lacked row-owned proof that previous-epoch traffic is rejected after grace expiry. Without this proof, a regression could accidentally continue accepting removed/stale E1 traffic after current local state has moved to E2.

User-visible behavior to preserve: in-flight previous-epoch messages are accepted only during the explicit grace window; after the deadline, stale previous-epoch traffic does not surface to users as messages or reactions.

Must stay unchanged: GK-016 acceptance during live grace and GK-018's separate current-epoch-after-expiry behavior.

## Device/Relay Proof Profile

GK-017 closure is host-only direct Go proof.

- Required proof is Go node validator/decrypt behavior because the matrix fields are `Required` for host/code proof and only `Recommended` for device/relay-style proof.
- Device, simulator, relay, and real-network commands are Recommended-only for this row and should not block GK-017 closure unless production changes touch Flutter/Dart replay or transport surfaces.
- If Dart offline replay is touched unexpectedly, run the conditional Flutter/offline command below and record why the scope expanded.

## files and repos to inspect next

Executor should inspect before editing:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/group.go`
- Conditional only if Dart replay is touched: `lib/features/groups/application/group_offline_replay_envelope.dart` and `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

- `TestGroupTopicValidator_AcceptsPreviousEpochDuringGrace` proves previous epoch acceptance while grace is live.
- `TestGroupTopicValidator_RejectsPreviousEpochAfterGraceExpires` proves pure validator rejection after expired grace but is not GK-017 named and does not exercise the live event reason.
- `TestHandleGroupSubscription_DecryptsPreviousEpochDuringGrace` proves live raw-publish previous epoch decrypts during grace.
- `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires` proves no payload/decrypt-failure events after expiry but does not assert `group:validation_rejected` reason/keyEpoch.
- `TestGK016GroupTopicValidatorAcceptsEpoch0PreviousKeyDuringFirstRotationGrace` and `TestGK016HandleGroupSubscriptionDecryptsEpoch0PreviousKeyDuringFirstRotationGrace` pin GK-016 and must remain green.

## regression/tests to add first

Add GK-017 row-owned tests before any production edit:

1. `TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline`
   - Build a valid E1 envelope signed/encrypted with the E1 key.
   - Validate against key info with current E2, `PrevKey == E1`, `PrevKeyEpoch == 1`, and expired `GraceDeadline`.
   - Assert pure validator returns `reject:bad_signature`.
   - Add negative controls only if compact: live grace accepts the same shape, expired grace rejects, and missing previous key/zero deadline reject. Do not duplicate all GK-016 cases.

2. `TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline`
   - Use a real `groupTopicValidator` or raw publish path with collectors installed before join.
   - Publish/deliver the valid E1 envelope after B has current E2 with expired E1 grace.
   - Assert `group:validation_rejected` reason `bad_signature_or_epoch` and `keyEpoch == 1`.
   - Assert no received message/reaction and no `group:decryption_failed` after the baseline.

3. `TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline`
   - Parse the same valid E1 envelope and call `decryptGroupEnvelopePayload` with current E2, previous E1, and expired `GraceDeadline`.
   - Assert the error contains `no group key available for epoch 1`.
   - Also assert the same helper decrypts during live grace only if this can reuse the existing setup without duplicating GK-016.

If these tests pass without production edits, stop implementation and record tests-only closure.

## step-by-step implementation plan

1. Re-read `pubsub_key_rotation_grace_test.go` and place GK-017 tests next to the existing previous-epoch grace/expiry tests.
2. Add the pure validator GK-017 regression using existing `buildTestEnvelope` and `buildGroupKeyInfoWithGrace` helpers.
3. Add the direct decrypt-helper GK-017 regression if it can stay compact in the same file.
4. Add the live validator/raw-publish GK-017 regression using existing local-node, collector, `publishRawGroupEnvelope`, `waitForCollectedValidationReject`, and `assertNoCollectedEventContainingAfter` helpers. Prefer collector setup before join, matching the GK-016 race cleanup pattern.
5. Run the focused GK-017 selector. If it passes, do not touch production.
6. If focused tests fail because expired previous epoch is accepted or decrypted, patch only `hasKeyRotationGrace`, `verifyGroupEnvelopeSignature`, or `decryptGroupEnvelopePayload` in `go-mknoon/node/pubsub.go` as needed. Do not edit crypto, internal envelope parsing, group config structures, or Dart replay unless the failing assertion proves that exact file owns the defect.
7. Run focused, adjacent, broader, race-if-production-changed, and diff-hygiene commands.
8. Closure writer should update only GK-017 source row, breakdown row 68/current-next-row references, this plan's status/closure note, and ledger evidence. Do not write a final program verdict.

## risks and edge cases

- Time-bound flake: use expired deadlines safely in the past and live deadlines with enough margin.
- Validator-vs-decrypt distinction: after expiry, the normal path should reject in validator and should not reach decrypt; direct decrypt helper can return `no group key available` but live PubSub should close via `bad_signature_or_epoch`.
- GK-016 regression risk: over-tightening the grace predicate could break valid in-flight previous-epoch delivery during live grace.
- Event-race risk: collectors must be installed before join/publish for live tests.
- Scope risk: GK-018 current-epoch acceptance after expiry is adjacent but not part of GK-017.

## exact tests and gates to run

Focused GK-017:

```bash
(cd go-mknoon && go test ./node -run 'TestGK017' -count=1)
```

Adjacent grace/expiry/GK-016/GK-018 guard selector:

```bash
(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace)|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)|TestGK016|TestGK017' -count=1)
```

Broader Go node/internal/crypto selector:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|GK016|GK017' -count=1)
```

Race if production changed:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGK016|TestGK017|TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires)|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)' -count=1)
```

Diff hygiene:

```bash
git diff --check
```

Conditional Flutter/offline command only if Dart replay/offline files change:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

Conditional named group gate only if Flutter group send/receive/retry/resume behavior changes:

```bash
./scripts/run_test_gates.sh groups
```

## known-failure interpretation

- A failure outside `TestGK017`, existing grace/expiry selectors, or files touched by this session is not automatically a GK-017 regression; record it separately with command output.
- If existing non-GK-017 tests are red before GK-017 edits, capture baseline and avoid attributing old failures to this row.
- If `TestGK017` fails because the live validator emits a different accepted rejection reason that still matches the source row only as `no key available`, verify whether the test accidentally bypassed validator registration before changing production.

## done criteria

- GK-017 row-owned tests exist and pass.
- No production code is changed unless the row-owned tests first fail for the exact stale-previous-epoch-after-deadline behavior.
- GK-016 live-grace tests still pass.
- `git diff --check` passes.
- Closure docs describe GK-017 only and leave GK-018 as next unresolved row.

## scope guard

Do not:

- Change grace period duration or key update semantics beyond the exact expired-deadline bug if one is proven.
- Add new cross-platform offline replay semantics.
- Change signature data format, encryption format, membership/device authorization, relay discovery, or libp2p transport setup.
- Bundle GK-018 or later GK rows.
- Write a final program verdict.

Overengineering would include adding a new key-epoch state machine, generic epoch policy abstraction, simulator harness, or Flutter replay changes for a Go validator/decrypt proof that passes host-side.

## accepted differences / intentionally out of scope

- Full device/relay/real-network proof is Recommended-only and intentionally out of GK-017 closure unless production changes unexpectedly cross into Flutter or transport code.
- Direct decrypt returning `no group key available` is an acceptable lower-level behavior, but the normal live PubSub validator proof should prefer `bad_signature_or_epoch`.
- Existing non-GK-017 expiry tests are useful evidence but not enough as closure documentation; the session should add GK-017-named proof or explicitly record exact evidence if no new test is needed.

## dependency impact

GK-017 closure unblocks the next row, GK-018, which must separately prove current E2 remains accepted after previous E1 grace expires. If GK-017 uncovers a production bug in the shared grace predicate, rerun GK-016 and do not begin GK-018 until GK-017's fix and closure docs are stable.

## Planner Decision

The plan is safe to implement as GK-017-only. The likely implementation is tests-only, with production patching gated by exact row-owned test failure.

## Reviewer Findings

- Sufficiency: sufficient with adjustment. The plan has a clear closure bar, source of truth, scope guard, test-first rule, exact commands, and no final program verdict.
- Missing files/tests/gates: add explicit direct decrypt-helper coverage or record why live validator-first coverage supersedes it. No additional production files are required up front.
- Stale assumptions: breakdown row 68's "code changes + tests" appears broader than current code evidence; the plan correctly makes production changes conditional.
- Overengineering: no overengineering detected; simulator/relay proof remains Recommended-only.
- Decomposition: narrow enough for implementation; GK-018 is clearly excluded.
- Minimum adjustment made: direct decrypt-helper/no-key proof added to closure bar and regression list.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: the reviewer-requested direct decrypt-helper proof was useful and has been incorporated; no extra review loop is required.
- Accepted differences: direct Go host proof is sufficient for GK-017; device/relay proof remains Recommended-only; production changes remain conditional; GK-018 stays out of scope.
- Stop rule: no structural blocker remains, so planning stops here.
