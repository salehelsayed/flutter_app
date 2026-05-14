Status: accepted/closed

# GK-018 Implementation Plan

## Execution Progress
- 2026-05-12 14:35:03 CEST | Closure Reviewer completed | Files inspected or touched: source matrix GK-018/GK-019 rows, breakdown GK-018 closure rows, this plan status/Closure Note, stale-state searches, final-program-verdict heading search, `git diff --check`, and untracked-plan whitespace check. | Decision/blocker: no overclaiming found; GK-018 is `Covered`/`covered/accepted`, this plan is `accepted/closed`, no stale unresolved GK-018 row state remains, no final program verdict heading exists, and GK-019 remains next/open. | Next action: report closure result.
- 2026-05-12 14:29:00 CEST | Closure Writer completed | Files inspected or touched: source matrix row GK-018; breakdown Gap-Closure Reconciliation, Closure Progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 69, Ordered Session Breakdown row 69; this plan. | Decision/blocker: GK-018 is now `Covered`/`covered/accepted` with concrete test/gate evidence and no final program verdict. | Next action: run scoped closure review, then continue from GK-019.
- 2026-05-12 14:27:44 CEST | Completion Auditor completed | Files inspected or touched: this plan, source matrix GK-018/GK-019 rows, breakdown GK-018/GK-019 rows, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, focused audit rerun, `git diff --check`, and final-program-verdict heading search. | Command/result: `(cd go-mknoon && go test ./node -run 'TestGK018' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 2.077s`; `git diff --check` passed with no output. | Decision/blocker: `closed`/`accepted`; three GK-018 row-owned tests are landed, no GK-018 production code changed, no final program verdict exists, and GK-019 remains next/open. | Next action: closure writer updates source matrix, breakdown rows, and this plan closure note.
- 2026-05-12 14:23:54 CEST | Final diff hygiene finished | Files inspected or touched: this GK-018 plan only. | Command/result: `git diff --check` passed with no output after the final execution verdict entry. | Decision/blocker: no blockers. | Next action: return final execution result to the user.
- 2026-05-12 14:23:09 CEST | Final execution verdict written | Files inspected or touched: this GK-018 plan only. | Decision/blocker: final execution verdict is `accepted`; no blockers and no non-blocking GK-018 follow-ups remain; no source matrix, breakdown closure rows, or final program verdict written. | Next action: run final `git diff --check` after verdict entry.
- 2026-05-12 14:21:38 CEST | QA scope guard checked | Files inspected or touched: source matrix and session breakdown diffs read only; this plan updated only. | Decision/blocker: source matrix GK-018 row remains `Open`, breakdown GK-018 row remains `implementation-ready`, and no final program verdict was written. | Next action: report accepted GK-018 QA result.
- 2026-05-12 14:19:36 CEST | QA Reviewer completed | Files inspected or touched: this GK-018 plan and `go-mknoon/node/pubsub_key_rotation_grace_test.go`; scoped diff checked for GK-018 strings. | Command/results: `(cd go-mknoon && go test ./node -run 'TestGK018' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 2.025s`; `(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires)' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 6.087s`; `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 11.088s`, `ok github.com/mknoon/go-mknoon/internal 0.577s`, `ok github.com/mknoon/go-mknoon/crypto 0.894s`; `git diff --check` passed with no output. | Decision/blocker: accepted for GK-018 execution sufficiency; required row-owned tests prove current E2 validation, direct decrypt, and live raw-publish receive after expired Prev E1 grace with no validation/decryption failure; no production GK-018 diff found and race/Flutter/device gates are not required for this tests-only pass. | Next action: none for GK-018 QA; no source matrix, breakdown closure, or final program verdict written.
- 2026-05-12 14:02:16 CEST | Contract extracted | Files inspected or touched: this GK-018 plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, scoped git status/diff. | Decision/blocker: scope is tests-only unless GK-018 tests expose a real failure; required tests/gates and source/breakdown non-edit guard confirmed; working tree is dirty and existing unrelated edits will be preserved. | Next action: spawn isolated Executor with model `gpt-5.5` and `model_reasoning_effort=xhigh` for GK-018 only.
- 2026-05-12 14:03:31 CEST | Executor spawn retry | Files inspected or touched: this plan file only. | Decision/blocker: first `codex exec` spawn attempt failed before child work because the CLI rejected `-a` in subcommand position; no child code/test/doc work materialized. | Next action: retry spawned Executor with the same model/reasoning request using global CLI options.
- 2026-05-12 14:07:11 CEST | Executor child stopped / local fallback started | Files inspected or touched: child read this plan, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, selected helper files, and production seams but produced no GK-018 edits, no gate evidence, and no plan progress update before the bounded wait expired. | Decision/blocker: classify nested Executor attempt as `spawn_or_tool_failure` with no partial assigned code/test/doc work; use local sequential fallback under the skill's bounded rule. | Next action: add the three GK-018 tests locally, then run the exact required gates.
- 2026-05-12 14:08:57 CEST | Local Executor editing | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`. | Decision/blocker: existing production order checks current epoch before previous-key grace; add tests only unless gates expose a concrete GK-018 failure. | Next action: patch the three GK-018 tests into the target Go test file.
- 2026-05-12 14:11:02 CEST | Local Executor focused gate starting | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go` patched and gofmt-formatted. | Command: `(cd go-mknoon && go test ./node -run 'TestGK018' -count=1)`. | Decision/blocker: three GK-018 tests are present; no production edit made. | Next action: run focused GK-018 selector.
- 2026-05-12 14:11:51 CEST | Local Executor focused gate finished / adjacent gate starting | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. | Command/result: `(cd go-mknoon && go test ./node -run 'TestGK018' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 2.142s`. Next command: `(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires)' -count=1)`. | Decision/blocker: no GK-018 production failure exposed. | Next action: run adjacent selector.
- 2026-05-12 14:12:40 CEST | Local Executor adjacent gate finished / broader gate starting | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. | Command/result: `(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires)' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 6.129s`. Next command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018' -count=1)`. | Decision/blocker: adjacent GK-016/GK-017/GK-018 behavior remains green. | Next action: run broader selector.
- 2026-05-12 14:13:36 CEST | Local Executor broader gate finished / diff hygiene starting | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`. | Command/result: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 11.175s`; `ok github.com/mknoon/go-mknoon/internal 0.894s`; `ok github.com/mknoon/go-mknoon/crypto 0.690s`. Next command: `git diff --check`. | Decision/blocker: broader Go group envelope/decrypt/key-rotation selector is green. | Next action: run diff hygiene.
- 2026-05-12 14:14:32 CEST | Local Executor completed / QA Reviewer spawning | Files inspected or touched: `go-mknoon/node/pubsub_key_rotation_grace_test.go`, this GK-018 plan. | Command/result: `git diff --check` passed with no output. | Decision/blocker: required Executor gates passed; no production code edit made by GK-018; race gate not required because no production Go concurrency behavior changed. | Next action: spawn isolated QA Reviewer with model `gpt-5.5` and `model_reasoning_effort=xhigh`.

## Closure Note

Closure status: accepted/closed at 2026-05-12 14:29:00 CEST.

GK-018 closed as tests-only. No GK-018 production, Dart, Flutter, crypto, wire-format, membership, authorization, relay, or transport behavior changes were required; existing Go node validator/decrypt/live subscription behavior already accepts current E2 traffic after the previous-key grace deadline expires once row-owned proof is present.

Concrete evidence:

- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline` proves a valid E2 envelope signed/encrypted with the current key validates as `accept` when `PrevKeyEpoch == 1` and the grace deadline has expired.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline` proves direct decrypt still returns current E2 plaintext after the expired previous-key grace window.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go::TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline` proves live raw-publish delivery emits `group_message:received` with `keyEpoch == 2` and no post-baseline `group:validation_rejected` or `group:decryption_failed`.

Gate evidence: executor passed focused GK-018 (`ok node 2.142s`), adjacent grace/expiry/GK-016/GK-017/GK-018 (`ok node 6.129s`), broader node/internal/crypto (`ok node 11.175s`, `ok internal 0.894s`, `ok crypto 0.690s`), and `git diff --check`. QA reran focused (`ok node 2.025s`), adjacent (`ok node 6.087s`), broader (`ok node 11.088s`, `ok internal 0.577s`, `ok crypto 0.894s`), and `git diff --check`. Completion Auditor reran focused GK-018 with `ok github.com/mknoon/go-mknoon/node 2.077s`; `git diff --check` passed.

Accepted differences: race was skipped because no GK-018 production Go concurrency behavior changed. Flutter/offline/groups and real-device/relay gates were not required because no Dart/Flutter/transport files changed and those surfaces are Recommended-only for this row. Residual-only: none for GK-018. Source matrix row GK-018 and breakdown row 69 are now `Covered`/`covered/accepted`; GK-019 remains the next unresolved P0 row. No final program verdict was written.

## Planning Progress
- 2026-05-12 13:57:49 CEST | Arbiter completed | Files inspected since last update: reviewer sufficiency notes and full GK-018 plan draft. | Decision/blocker: no structural blockers remain; incremental details are implementation-time choices; accepted differences are documented. Plan is execution-ready. | Next action: implement GK-018 in a later execution pass using the three tests-first proof seams and required gates.
- 2026-05-12 13:57:14 CEST | Arbiter started | Files inspected since last update: reviewer sufficiency notes and full GK-018 plan draft. | Decision/blocker: no reviewer-identified structural blocker; classify remaining details before final status. | Next action: record arbiter decision and set execution readiness if no structural blocker remains.
- 2026-05-12 13:56:13 CEST | Reviewer completed | Files inspected since last update: this GK-018 plan draft; mandatory-section scan; scoped git diff output for named source/breakdown/plan paths. | Decision/blocker: sufficient as-is; no structural blocker found. The plan keeps GK-018 implementation-ready/tests-first, includes the three required proof seams, exact required gates, conditional race rule, recommended-only Flutter/device gates, and source/breakdown non-edit guard. | Next action: run arbiter classification and final readiness decision.
- 2026-05-12 13:55:37 CEST | Reviewer started | Files inspected since last update: this GK-018 plan draft; current git diff for the named source matrix/breakdown/plan paths; mandatory-section scan. | Decision/blocker: draft has all mandatory sections; review will check whether live raw-publish proof, gates, known-failure handling, and source/breakdown non-edit guard are sufficient. | Next action: record sufficiency findings and any required adjustments.
- 2026-05-12 13:52:36 CEST | Planner completed | Files inspected since last update: none. | Decision/blocker: drafted a narrow tests-first plan with no production edits unless row-owned GK-018 tests expose a concrete current-epoch expired-grace failure. | Next action: run reviewer sufficiency pass against scope, tests, gates, and stop rule.

## real scope
Own exactly source row `GK-018 | Current epoch remains accepted after grace deadline`.

In scope:
- Add row-owned Go node tests proving that a valid current E2 envelope is accepted after the E2/Prev E1 grace deadline has expired.
- Cover the same behavior through the pure validator helper, direct decrypt helper, and live raw-publish receive path.
- Make the smallest production change only if those tests fail against current code.

Out of scope:
- Do not change the source matrix or session breakdown during planning.
- Do not change Flutter, Dart offline replay, relay/device orchestration, membership, authorization, envelope wire format, or key-rotation policy unless a GK-018 test exposes a concrete failure in that surface.
- Do not reopen GK-016 or GK-017 except as adjacent regression guards.

## closure bar
GK-018 is good enough when row-owned tests prove that expired previous-key grace does not disable current epoch traffic:
- A valid E2 envelope signed/encrypted with the current E2 key validates as `accept` while `PrevKeyEpoch == 1` and `GraceDeadline` is already expired.
- Direct decrypt of the same E2 envelope returns plaintext via the current key after the expired grace deadline.
- A live raw-publish path delivers `group_message:received` with `keyEpoch == 2` and emits no validation rejection or decryption failure for that E2 envelope.
- Adjacent GK-016/GK-017 grace/expiry tests still pass.

## source of truth
- Current code and tests are authoritative over stale prose.
- Source matrix row `GK-018` is authoritative for the expected behavior: current E2 with expired Prev E1 must be accepted and received.
- Session breakdown ordered row 69 is authoritative for this session classification: `needs_tests_only` / `implementation-ready` / tests only.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gates; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Closed GK-016/GK-017 rows are accepted context and should be used only as regression guards.

## session classification
`implementation-ready`

This is tests-only unless the required GK-018 tests expose a real current-epoch expired-grace failure. It must not be downgraded to docs-only/evidence-only because existing tests do not close the exact row.

## exact problem statement
The repo does not yet have exact row-owned proof that current epoch group traffic remains accepted after the previous-epoch grace deadline expires. That missing proof is risky because grace expiry must reject stale E1 traffic without accidentally rejecting valid current E2 traffic.

User-visible behavior to protect: after key rotation to E2 and expiration of the Prev E1 grace window, valid E2 group messages continue to validate, decrypt, and reach receivers.

Behavior that must stay unchanged: expired previous E1 envelopes still reject; live previous-epoch grace still works; first-rotation epoch-0 grace stays accepted only under explicit previous-key/live-deadline conditions; membership, authorization, signature binding, and malformed-envelope rejection semantics do not change.

## files and repos to inspect next
Primary production seams:
- `go-mknoon/node/pubsub.go`
  - `hasKeyRotationGrace`
  - `verifyGroupEnvelopeSignature`
  - `decryptGroupEnvelopePayload`
  - `groupTopicValidator`
  - `handleGroupSubscription`

Primary test file:
- `go-mknoon/node/pubsub_key_rotation_grace_test.go`

Shared test helpers:
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Inspect only if tests expose a lower-level failure:
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/node/group.go`

## existing tests covering this area
Existing adjacent coverage:
- `TestGroupTopicValidator_AcceptsCurrentEpochDuringGrace` proves current E2 validator acceptance while grace is still live, but not after the deadline.
- `TestGK017GroupTopicValidatorRejectsPreviousEpochAfterGraceDeadline` proves previous E1 validator rejection after expired grace.
- `TestGK017DecryptGroupEnvelopePayloadRejectsPreviousEpochAfterGraceDeadline` proves previous E1 direct decrypt failure after expired grace.
- `TestGK017GroupTopicValidatorEmitsBadSignatureOrEpochAfterGraceDeadline` proves previous E1 live raw-publish rejection with no receive/decrypt-failure side effects.
- `TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires` proves stale previous E1 live delivery is dropped after expiry.
- `TestGL014UpdateGroupKeyIgnoresOlderEpochAndKeepsCurrentEpochDelivery` and `TestGL015UpdateGroupKeyIgnoresSameEpochDifferentMaterialAndKeepsEpoch3Delivery` protect related current-epoch delivery after stale update inputs, but they are not exact GK-018 expired Prev E1 proof.

Missing row-owned coverage:
- No `GK018` / `GK-018` test exists in `go-mknoon`, `test/features/groups`, or `lib/features/groups` for current E2 acceptance after expired Prev E1 grace.

Current production evidence:
- `verifyGroupEnvelopeSignature` checks `env.KeyEpoch == keyInfo.KeyEpoch` before the previous-epoch grace branch.
- `decryptGroupEnvelopePayload` decrypts `env.KeyEpoch == keyInfo.KeyEpoch` before considering the previous-epoch grace branch.

## regression/tests to add first
Add these tests before any production edit:

1. `TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline`
   - Place near existing GK-017 pure validator tests in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
   - Build an E2 envelope signed/encrypted with `currentKey`, configure `GroupKeyInfo{Key: currentKey, KeyEpoch: 2, PrevKey: prevKey, PrevKeyEpoch: 1, GraceDeadline: now.Add(-time.Second)}`, and assert `validateGroupEnvelope(...) == "accept"`.

2. `TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline`
   - Parse the E2 envelope and call `decryptGroupEnvelopePayload(env, expiredGrace, now)`.
   - Assert no error and plaintext contains the expected message text.

3. `TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline`
   - Use the local two-node raw-publish pattern from nearby GK-016/GK-017 tests.
   - Join both nodes on E1, rotate both to E2, force node B's `GraceDeadline` to `time.Now().Add(-time.Second)`, connect, wait for topic peer count, publish a raw E2 envelope, and assert node B receives `group_message:received` with `keyEpoch == 2`.
   - Assert no post-baseline `group:validation_rejected` and no `group:decryption_failed` for the E2 message.

These tests prove the row's validator/decrypt/live receive seams directly and should pass without production changes if current code behaves as inspected.

## step-by-step implementation plan
1. Add `TestGK018GroupTopicValidatorAcceptsCurrentEpochAfterGraceDeadline`.
2. Run the focused GK-018 selector. If it passes, continue. If it fails, inspect only `verifyGroupEnvelopeSignature` and its immediate key-info inputs.
3. Add `TestGK018DecryptGroupEnvelopePayloadAcceptsCurrentEpochAfterGraceDeadline`.
4. Run the focused GK-018 selector. If it fails, inspect only `decryptGroupEnvelopePayload` and current-key material flow.
5. Add `TestGK018HandleGroupSubscriptionReceivesCurrentEpochAfterGraceDeadline`.
6. Run the focused GK-018 selector. If it fails, inspect only live validator/decrypt timing, local group key state, and the test harness ordering around collector setup, joins, connect, and peer count.
7. Make production changes only if a GK-018 test demonstrates that current E2 traffic is rejected/decryption-failed after expired Prev E1 grace. Keep any production edit limited to `go-mknoon/node/pubsub.go` unless direct evidence points elsewhere.
8. Run adjacent and broader gates listed below.
9. If all required gates pass, implementation may later update the source matrix and breakdown in a closure step, but this planning session must not write a final program verdict.

## risks and edge cases
- Accidentally testing previous E1 instead of current E2 would duplicate GK-017 instead of closing GK-018.
- A live raw-publish test can become flaky if it publishes before topic peer discovery; use the nearby `waitForGroupTopicPeerCount` pattern.
- Current and previous keys must be distinct so the test proves epoch/key selection rather than accidental decrypt with shared material.
- The post-baseline event assertions must not treat pre-existing join/connection events as GK-018 failures.
- A production fix must not relax signature, membership, authorization, group mismatch, future epoch, or stale previous-epoch rejection behavior.

## exact tests and gates to run
Required focused GK-018 selector:

```bash
(cd go-mknoon && go test ./node -run 'TestGK018' -count=1)
```

Required adjacent GK-016/GK-017/GK-018 grace/expiry selector:

```bash
(cd go-mknoon && go test ./node -run 'Test(GK016|GK017|GK018|GroupTopicValidator_AcceptsCurrentEpochDuringGrace|GroupTopicValidator_RejectsPreviousEpochAfterGraceExpires|HandleGroupSubscription_DecryptsPreviousEpochDuringGrace|HandleGroupSubscription_DropsPreviousEpochAfterGraceExpires)' -count=1)
```

Required broader Go node/internal/crypto selector scoped to group envelope, key rotation, and decryption:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|Decrypt|DecryptionFailed|KeyRotation|GK016|GK017|GK018' -count=1)
```

Required diff hygiene:

```bash
git diff --check
```

Conditional race gate, only if production Go concurrency behavior changes:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGK018|Test(GK016|GK017).*Grace|Test.*GroupTopicValidator|Test.*HandleGroupSubscription' -count=1)
```

Recommended-only unless Dart/Flutter/transport files change:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh group-real-network-nightly
```

## known-failure interpretation
- Treat any new failure in the focused GK-018 tests as a GK-018 blocker until explained or fixed.
- Treat failures in adjacent GK-016/GK-017 grace/expiry tests as blockers because they protect behavior this session can accidentally regress.
- For broader Go selectors, compare failures against the current working tree before edits if needed. Do not classify unrelated pre-existing failures as GK-018 regressions unless the failure touches group envelope validation, current/previous epoch key selection, or decryption.
- Recommended-only Flutter/device/relay failures are not GK-018 blockers unless this session changes Dart, Flutter, transport, or relay/device orchestration files.

## done criteria
- Three row-owned GK-018 tests exist in `go-mknoon/node/pubsub_key_rotation_grace_test.go`.
- Focused GK-018 selector passes.
- Adjacent GK-016/GK-017/GK-018 grace/expiry selector passes.
- Broader Go node/internal/crypto selector passes or any unrelated known failure is documented with proof.
- `git diff --check` passes.
- No production code changes are present unless a failing GK-018 test required them.
- No source matrix, breakdown, final program verdict, Dart/Flutter, device/relay, or unrelated product files are changed by this plan session.

## scope guard
Do not broaden this session into key-distribution architecture, offline replay, relay reliability, membership roles, envelope schema changes, notification routing, or product UX.

Overengineering would include adding generic key-epoch abstractions, rewriting validation order, adding new gate definitions, adding device/simulator orchestration, or changing the source matrix/breakdown before implementation proof exists.

Keep GK-018 limited to current epoch E2 acceptance after expired Prev E1 grace.

## accepted differences / intentionally out of scope
- Device/relay proof remains Recommended-only for GK-018 unless transport/device files change.
- Flutter offline replay remains Recommended-only unless Dart/Flutter group replay files change.
- Race proof is conditional because tests-only Go additions do not alter production concurrency behavior.
- This plan intentionally relies on direct Go node validator/decrypt/live raw-publish proof rather than full end-to-end mobile network proof.

## dependency impact
- GK-018 closure will unblock later matrix rows that assume expired previous-key grace does not affect current epoch delivery.
- If GK-018 requires a production change, rerun and possibly expand adjacent current/previous epoch tests before any later GK row is closed.
- If row-owned tests pass without production changes, later work should treat GK-018 as tests-only proof and avoid reopening key-rotation policy unless a real regression appears.

## reviewer sufficiency notes
Reviewer verdict: sufficient as-is.

Required questions:
- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None. The plan names the production seams, the test file, shared helpers, three GK-018 row-owned tests, focused/adjacent/broader Go selectors, diff hygiene, and the conditional race rule.
- What assumptions are stale or incorrect? None found. Existing tests do not cover exact GK-018, and the source row remains Open while breakdown row 69 remains implementation-ready / needs_tests_only.
- What is overengineered? Nothing structural. The plan avoids new abstractions, gate edits, Flutter/device proof, and source/breakdown edits during planning.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It adds pure validator, direct decrypt, then live raw-publish proof, with a stop point after each failure.
- What is the minimum needed to make the plan sufficient? Already present: tests-first seam coverage, closure bar, scope guard, exact gates, known-failure interpretation, and stop rule.

## arbiter decision
Structural blockers: none.

Incremental details intentionally deferred:
- The executor may choose exact assertion helper placement for the live raw-publish no-rejection checks, using existing helpers where possible.
- If a focused GK-018 test fails, the executor should narrow the production investigation to the failing seam before expanding file scope.

Accepted differences intentionally left unchanged:
- Direct Go node proof is sufficient for GK-018; full device/relay and Flutter/offline proof remains Recommended-only unless those files change.
- Race proof stays conditional because the expected implementation is tests-only and should not alter production concurrency behavior.
- Source matrix and breakdown closure updates are intentionally outside this planning pass.

Final arbiter verdict: execution-ready.

## Final Execution Verdict
Verdict: accepted.

GK-018 is execution-sufficient because row-owned tests now prove current E2 acceptance after expired Prev E1 grace through pure validation, direct decrypt, and live raw-publish receive with `keyEpoch == 2` and no validation/decryption failure. Required focused, adjacent, broader Go selectors and diff hygiene passed. No GK-018 production code change was required, and no source matrix, breakdown closure rows, or final program verdict were written.
