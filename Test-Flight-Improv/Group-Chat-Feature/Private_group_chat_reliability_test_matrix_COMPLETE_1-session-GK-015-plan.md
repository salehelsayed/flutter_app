# GK-015 Execution Plan: Envelope groupId mismatch is rejected

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 11:42:54 CEST | Planner completed | This plan draft | Draft written with three row-owned GK-015 tests, production-change fallback, conditional race/Flutter gates, and closure docs requirements. | Run Reviewer role for sufficiency. |
| 2026-05-12 11:46:14 CEST | Reviewer started | Full GK-015 draft plan; source matrix/breakdown evidence; validator/test evidence summarized in this file | Reviewing for missing mandatory sections, gate gaps, stale assumptions, over-broad scope, and unclear tests-first stop rule. | Complete sufficiency review and patch only structural issues. |
| 2026-05-12 11:46:14 CEST | Reviewer completed | Full GK-015 draft plan | Reviewer verdict: sufficient as-is. No structural blockers found. Direct pure/live/raw-publish tests, closure bar, source-of-truth rule, conditional race/Flutter gates, known-failure handling, and scope guard are explicit. | Move to Arbiter role. |
| 2026-05-12 11:46:14 CEST | Arbiter started | Reviewer findings and draft plan | Classifying reviewer findings into structural blockers, incremental details, and accepted differences. | Finalize arbiter decision and execution-ready status. |
| 2026-05-12 11:46:14 CEST | Arbiter completed | Reviewer findings and final plan | No structural blockers. Incremental details are intentionally deferred to execution naming/placement if equivalent proof is preserved. Accepted differences remain documented. | Plan is execution-ready; implement GK-015 tests first and patch production only if exact proof fails. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 11:50:07 CEST | Contract extracted | This plan; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `git status --short` | Nested Executor/QA child spawning is unavailable in this isolated tool context, so execution is using the skill's local sequential fallback. Scope remains GK-015 tests first; production changes only if exact GK-015 tests expose a mismatch. Dirty worktree is pre-existing and will be preserved. | Executor local fallback: add the three row-owned GK-015 tests before production edits. |
| 2026-05-12 11:51:34 CEST | Executor local fallback running | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; shared raw-publish helpers | Current validator/helper order already checks `group_mismatch` before peer/config/key/signature. No production edit justified before adding RED/row-owned tests. | Add GK-015 tests in `pubsub_test.go` and `pubsub_decryption_failure_test.go`; run focused selector. |
| 2026-05-12 11:54:41 CEST | Focused row tests finished | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Added and formatted the three row-owned GK-015 tests. `(cd go-mknoon && go test ./node -run '^TestGK015(ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature|GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason|GroupIDMismatchRejectedByValidatorAndEmitsNoPayloadEvent)$' -count=1)` passed. No production mismatch exposed; classify as tests-only unless later required gates prove otherwise. | Run adjacent GK-011 through GK-015 selector. |
| 2026-05-12 11:55:30 CEST | Adjacent selector finished | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | `(cd go-mknoon && go test ./node -run 'TestGK015|TestGK014|TestGK013|TestGK012|TestGK011' -count=1)` passed. | Run broader row-relevant Go sweep. |
| 2026-05-12 11:56:23 CEST | Broader Go sweep finished | `go-mknoon/node`; `go-mknoon/internal`; `go-mknoon/crypto` | `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK015|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)` passed. Conditional race skipped because no production validator code changed. Conditional Flutter and `groups` gates skipped because no Dart/Flutter group code changed for GK-015. | Run `git diff --check`, then local QA review. |
| 2026-05-12 11:58:38 CEST | Local QA reviewer completed | GK-015 additions in `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this execution progress section | `git diff --check` passed before QA. QA found no blocking issues: exact tests exist and pass, no GK-015 production code was edited, conditionals are not applicable, and source matrix/breakdown closure rows were intentionally left unchanged for closure audit. Final execution verdict: accepted. | Final `git diff --check` rerun after this progress edit; closure audit can proceed. |

## Closure Note

Closure status: accepted/closed at 2026-05-12 12:16:09 CEST.

GK-015 closed as tests-only. No GK-015 production, Dart, Flutter, crypto, wire-format, membership, authorization, or transport behavior changes were required. Existing `go-mknoon/node/pubsub.go` rejects `env.GroupId != groupId` as `group_mismatch` before transport peer, config, key, signature, decrypt, or receive paths.

Concrete evidence:

- `go-mknoon/node/pubsub_test.go::TestGK015ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature` proves pure validation returns `reject:group_mismatch` for topic group G / envelope group H before peer/config/key/signature branches.
- `go-mknoon/node/pubsub_test.go::TestGK015GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason` proves the live validator returns `pubsub.ValidationReject` and emits `group:validation_rejected` with reason `group_mismatch`, `envelopeType`, and `keyEpoch`.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK015GroupIDMismatchRejectedByValidatorAndEmitsNoPayloadEvent` proves the raw-publish path emits no `group_message:received`, no `group_reaction:received`, no `group:decryption_failed`, and no plaintext marker after mismatch rejection.

Gate evidence: executor/QA passed the focused GK-015 selector, adjacent GK-011..GK-015 selector, broader node/internal/crypto selector, and `git diff --check`. Completion Auditor reran the focused GK-015 selector with `ok github.com/mknoon/go-mknoon/node 3.124s`; `git diff --check` passed.

Accepted differences: full real-network proof is Recommended-only. Race, Flutter, and groups gates were not required because GK-015 did not change production validator, Dart replay, or Flutter group code. Residual-only: none for GK-015. Source matrix row GK-015 and breakdown row 66 are now `Covered`/`covered/accepted`; GK-016 remains the next unresolved P0 row. No final program verdict was written.

## real scope

GK-015 owns exactly the validator behavior for a message published or validated on topic group `G` while the v3 group envelope claims `groupId = H`.

In scope:

- Add row-owned Go node tests proving `group_mismatch` for `env.GroupId != topic groupId`.
- Prove the pure validator helper returns `reject:group_mismatch` before transport peer, config, key, signature, or decrypt paths can change the reason.
- Prove the live `groupTopicValidator` returns `pubsub.ValidationReject` and emits `group:validation_rejected` with reason `group_mismatch`.
- Prove the raw-pubsub/live validator path emits no `group_message:received`, `group_reaction:received`, or `group:decryption_failed` after the mismatch reject.
- Keep matching-group acceptance pinned by adjacent tests and one new matching-control assertion.

Out of scope unless the exact GK-015 regression fails:

- Production validator changes.
- Wire format, crypto/signature format, membership/authorization semantics, key rotation, Dart replay, Flutter UI, database, or real-network harness expansion.

## closure bar

GK-015 can close only when source row GK-015 is updated from `Open` to `Covered` with concrete evidence and the session/breakdown rows are updated to `covered/accepted` or the exact accepted closure wording used by adjacent rows.

Required proof:

- A row-named pure validator test passes and shows `reject:group_mismatch` when envelope group `H` is validated for topic group `G`.
- A row-named live `groupTopicValidator` test passes and shows `pubsub.ValidationReject` plus a `group:validation_rejected` event with reason `group_mismatch`.
- A row-named live/raw publish test passes and shows no payload/decrypt side effects after the mismatch reject.
- Adjacent GK-011 through GK-014 validator/envelope tests remain green.
- Broader row-relevant Go sweep and `git diff --check` pass.
- Race proof is included if production validator code changes.
- Flutter proof is included only if Dart replay or Flutter group code is touched or exact evidence proves it is row-owned.

Do not write a final program verdict for the full matrix while later rows remain unresolved.

## source of truth

Authoritative sources, in order:

- Current code and tests in `go-mknoon/node`, `go-mknoon/internal`, and `go-mknoon/crypto`.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate meanings.
- Source matrix row GK-015 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown row 66 / GK-015 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- This plan after it reaches `Status: execution-ready`.

If prose disagrees with code, code wins. If gate docs disagree with ad hoc commands, gate docs win. If the exact GK-015 RED exposes a production gap, the executor must patch the narrow validator branch and keep the test names/gates from this plan.

## session classification

`implementation-ready`.

Historical planning disposition: tests-first with likely tests-only closure. At planning time the breakdown said `needs_code_and_tests`; planning evidence showed the production branch already existed, but row-owned proof was missing. Do not downgrade the source/breakdown rows during planning. In execution, add the exact GK-015 tests first. The executed tests passed without production changes, and closure corrected the disposition to tests-only/covered.

## exact problem statement

At planning intake, GK-015 was open because the matrix required explicit proof that an envelope for group `H` cannot be accepted or delivered on topic group `G`.

Current risk:

- Before execution, `go-mknoon/node/pubsub.go` appeared to reject mismatched group IDs correctly, but no row-owned `GK-015` test proved it.
- Without exact tests, future edits could move group mismatch behind transport peer, membership, signature, or decrypt paths and either return the wrong reject reason or emit side effects.

Required behavior:

- Mismatched envelope group ID rejects as `group_mismatch`.
- The reject happens before transport-peer binding, group config/member lookup, key lookup, signature verification, decrypt, or receive-event emission.
- Supported matching group IDs continue to accept under valid config/key/signature inputs.

## files and repos to inspect next

Primary files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Supporting files:

- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- Source matrix and session breakdown paths named above.

Conditional only:

- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

Existing coverage:

- `go-mknoon/node/pubsub_test.go::validateGroupEnvelopeForTransportPeer` already returns `reject:group_mismatch` for `env.GroupId != groupId`.
- `go-mknoon/node/pubsub_test.go::TestGK014ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction` pins matching supported v3 `group_message` and `group_reaction` acceptance.
- `go-mknoon/node/pubsub_test.go::TestGK014GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope` pins the first validator gate before parse/config/key/signature paths.
- `go-mknoon/node/pubsub_test.go::TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic` pins live validator rejection event assertions.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage` and `TestGK013MissingEncryptedFieldsRejectedByValidatorAndEmitsNoPayloadEvent` show the raw-publish harness pattern for validator reject plus no received/reaction/decrypt side effects.

Missing:

- No `TestGK015...` exists.
- No row-owned live validator event proof for `group_mismatch`.
- No row-owned no-side-effect proof for group-id mismatch.

## regression/tests to add first

Add these tests before any production edit:

1. `go-mknoon/node/pubsub_test.go::TestGK015ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature`

   - Build a valid v3 `group_message` envelope for envelope group `group-gk-015-H`.
   - Validate it against topic group `group-gk-015-G`.
   - Pass an intentionally wrong transport peer and nil config/key to prove the result is `reject:group_mismatch` before peer/config/key/signature paths.
   - Add a matching control envelope for `group-gk-015-G` with valid config/key/transport and assert `accept`.

2. `go-mknoon/node/pubsub_test.go::TestGK015GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason`

   - Construct `n := New(collector)` and call `n.groupTopicValidator("group-gk-015-G")` directly.
   - Use a valid v3 envelope whose `GroupId` is `group-gk-015-H`.
   - Do not rely on group config/key maps for the mismatch assertion; the test should fail if the branch moves behind those paths.
   - Assert return value `pubsub.ValidationReject`.
   - Decode the emitted event and assert `event == "group:validation_rejected"`, `data.reason == "group_mismatch"`, `data.envelopeType == "group_message"`, and the expected `keyEpoch`.
   - Assert no emitted event string contains `group_message:received`, `group_reaction:received`, or `group:decryption_failed`.

3. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK015GroupIDMismatchRejectedByValidatorAndEmitsNoPayloadEvent`

   - Reuse the two-node raw publish pattern from GK-006/GK-012/GK-013.
   - Join both nodes to topic group `G` with valid config/key.
   - Build or mutate a valid envelope to claim group `H`.
   - Disable only node A's local topic validator before raw publish so node B's validator remains under test.
   - Publish on topic `G`.
   - Wait for node B `group:validation_rejected` reason `group_mismatch`.
   - Assert no post-baseline `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext marker.

If all three pass without production changes, stop production work and treat GK-015 as tests-only for closure. If an exact failure shows a production gap, patch only the validator/helper ordering needed to make these tests pass.

## step-by-step implementation plan

1. Re-read current `go-mknoon/node/pubsub.go` and test helpers to avoid conflicting with dirty worktree changes.
2. Add the pure helper test in `go-mknoon/node/pubsub_test.go`.
3. Run the focused pure test. If it passes without production edits, continue; if it fails, patch only the pure helper or shared validator-order logic required by the failure.
4. Add the direct live `groupTopicValidator` event test in `go-mknoon/node/pubsub_test.go`.
5. Run the focused direct live test. If it fails because production emits a wrong reason or checks a later branch first, patch only `groupTopicValidator` ordering/reason.
6. Add the raw-publish/no-side-effect test in `go-mknoon/node/pubsub_decryption_failure_test.go`.
7. Run the focused GK-015 selector for all row-owned tests.
8. Run `gofmt` on touched Go test/production files.
9. Run adjacent GK-011 through GK-014 selectors and the broader row-relevant Go sweep.
10. Run conditional race only if production validator code changed.
11. Run conditional Flutter only if Dart replay or Flutter group code changed.
12. Run `git diff --check`.
13. Update closure docs only after tests pass: source matrix GK-015, breakdown row 66/session ledgers, and this plan closure note/status. Do not write final program verdict.

## risks and edge cases

- Branch-order regression: a mismatch could be rejected as `peer_mismatch`, `unknown_group`, `missing_key`, or `bad_signature_or_epoch` if the guard moves later.
- Side-effect regression: if mismatched traffic reaches subscription handling, it could emit decrypt failure or payload events.
- Local raw publish: node A's own validator can reject before fanout, so the raw-publish test must unregister only node A's local validator and leave node B's validator active.
- Signature binding: an envelope signed for group `H` should not rely on signature failure for topic `G`; GK-015 must close on `group_mismatch`, not bad signature.
- Dirty worktree: many files are modified or untracked before GK-015 planning; executor must avoid reverting unrelated changes.

## exact tests and gates to run

Focused row tests:

```bash
(cd go-mknoon && go test ./node -run '^TestGK015(ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature|GroupTopicValidatorRejectsGroupIDMismatchAndEmitsReason|GroupIDMismatchRejectedByValidatorAndEmitsNoPayloadEvent)$' -count=1)
```

Adjacent GK validator/envelope selectors:

```bash
(cd go-mknoon && go test ./node -run 'TestGK015|TestGK014|TestGK013|TestGK012|TestGK011' -count=1)
```

Broader row-relevant Go sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK015|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)
```

Conditional race, required only if production validator code changes:

```bash
(cd go-mknoon && go test -race ./node -run 'TestGK015|GroupTopicValidator' -count=1)
```

Conditional Flutter/Dart replay proof, required only if Dart replay or Flutter group code is touched or exact GK-015 evidence proves it row-owned:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

Named Flutter gate, required only if implementation expands into Dart group send/receive/retry/resume behavior:

```bash
./scripts/run_test_gates.sh groups
```

Diff hygiene:

```bash
git diff --check
```

Recommended real-network proof remains optional for GK-015 and must not be introduced as a new required harness unless exact evidence shows direct host proof cannot cover the row.

## known-failure interpretation

- Any failure in the focused GK-015 selector is blocking and must be fixed or explicitly classified before closure.
- Any adjacent GK-011 through GK-014 failure caused by GK-015 edits is blocking.
- A broader Go sweep failure outside the touched files may be pre-existing because the worktree is already dirty; record the exact failing test and rerun the focused GK-015 plus adjacent selectors to separate old red from new regression.
- Do not fix unrelated dirty-worktree failures unless they block GK-015 proof directly.
- If a conditional Flutter or named gate is not applicable, record why it was skipped.

## done criteria

- Exact GK-015 tests exist with row-owned names and pass.
- No production code changed if the tests pass against current validator behavior.
- If production code changes, it is limited to the group mismatch validator/helper ordering or reason and the race selector passes.
- Adjacent GK-011 through GK-014 selectors pass.
- Broader row-relevant Go sweep passes or non-GK-015 failures are classified with focused green evidence.
- `git diff --check` passes.
- Source matrix GK-015 is marked `Covered` only with concrete evidence.
- Breakdown/session rows and this plan closure state are updated.
- No final program verdict is written while later rows remain unresolved.

## scope guard

Do not change:

- Group envelope schema or serialization.
- `BuildGroupSignatureData`, signature formats, crypto verification, encryption, nonce, or key epoch semantics.
- Membership lookup, authorization roles, device binding, transport peer binding, key rotation, retry/replay, relay inbox, Dart, Flutter, database, or UI behavior.
- Real-network or simulator harnesses.
- Named gate definitions.

Overengineering for this session includes adding new validator abstractions, creating a cross-language mismatch model, broadening parser validation, or rewriting shared test harnesses when a small row-owned test can prove the branch.

## accepted differences / intentionally out of scope

- GK-015 closes with direct host/pure/live validator proof; full real-network proof is Recommended-only, not required.
- It is acceptable for matching-group acceptance to be pinned by adjacent tests plus one new control assertion rather than a new end-to-end matching delivery test.
- It is acceptable for closure to correct the disposition from `needs_code_and_tests` to tests-only if the exact GK-015 tests pass without production edits.
- Dart offline replay is intentionally out of scope unless touched or proven row-owned by an exact failure.

## dependency impact

Later GK rows depend on a stable validator ordering contract: structural envelope gates first, then group mismatch, then peer/config/member/key/signature, then subscription decrypt/receive only after validation acceptance.

If GK-015 reveals a production gap, later rows that assume `group_mismatch` happens before signature/decrypt should wait for the narrow fix and updated evidence. If GK-015 closes as tests-only, later rows can rely on the existing guard with row-owned proof.

## Reviewer Pass

Verdict: sufficient as-is.

Sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None structurally. The plan names the relevant production file, pure helper test file, raw-publish harness file, helper files, source docs, focused tests, adjacent selectors, broader Go sweep, conditional race, conditional Flutter, named group gate condition, and `git diff --check`.
- What assumptions are stale or incorrect? None found. The plan treats current code as authoritative, keeps source/breakdown rows unchanged during planning, and allows tests-only closure only after exact GK-015 proof passes.
- What is overengineered? Nothing blocking. The plan stays in Go node validator tests and avoids wire-format, crypto, membership, Dart, Flutter, and real-network expansion unless exact evidence requires it.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It gives three concrete tests with exact behavior and a clear stop rule after tests pass without production changes.
- What is the minimum needed to make the plan sufficient? Already present: row-owned tests first, narrow code fallback, closure bar, regression gates, known-failure handling, and scope guard.

Reviewer notes:

- The test names are intentionally explicit and row-owned.
- The direct validator test's use of no config/key maps is important because it proves `group_mismatch` happens before downstream validator branches.
- The raw-publish test is required because direct `groupTopicValidator` proof alone does not exercise the no-payload-event side-effect surface.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- The executor may place the live no-side-effect test in another existing node test file only if it still uses the live/raw-publish validator path, keeps the `TestGK015...` row-owned name, and proves the same no-event assertions.
- The executor may add small local test helpers only if they reduce duplication without changing shared harness behavior.

Accepted differences intentionally left unchanged:

- GK-015 can close with direct host/pure/live validator proof; real-network proof remains Recommended-only.
- At planning time, the breakdown `needs_code_and_tests` classification was not rewritten. Closure has now classified the result as tests-only because exact GK-015 tests passed without production changes.
- Dart replay and Flutter gates remain conditional, not required, unless implementation touches those files or exact GK-015 evidence proves them row-owned.

Final arbiter verdict: execution-ready. Implement tests first; touch production only if the exact GK-015 proof fails.
