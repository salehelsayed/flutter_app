# GK-014 Execution Plan

Status: accepted/closed

## Planning Progress

- 2026-05-12T08:42:40Z - Arbiter completed. Files inspected since last update: Reviewer Pass and full plan. Decision/blocker: execution-ready; no structural blockers remain. Next action: hand off GK-014 plan for tests-first execution.
- 2026-05-12T08:42:39Z - Arbiter started. Files inspected since last update: Reviewer Pass. Decision/blocker: classify reviewer findings under stop rule. Next action: decide structural blockers, incremental details, and accepted differences.
- 2026-05-12T08:42:38Z - Reviewer completed. Files inspected since last update: this full plan, exact tests/gates, closure bar, scope guard, known-failure interpretation, and dependency impact. Decision/blocker: sufficient as-is; no structural blocker. Next action: arbiter pass.
- 2026-05-12T08:42:37Z - Reviewer started. Files inspected since last update: this full plan draft. Decision/blocker: review mandatory sections, missing tests/gates, stale assumptions, and over-scope. Next action: write reviewer sufficiency result.
- 2026-05-12T08:39:21Z - Planner completed. Files inspected since last update: this plan draft and Evidence Collector Notes. Decision/blocker: draft plan is tests-first, implementation-ready, and `needs_tests_only` unless exact RED proof exposes a production mismatch. Next action: reviewer pass for sufficiency, missing gates, stale assumptions, and scope creep.

## Execution Progress

- 2026-05-12T08:46:58Z - Contract extracted. Files inspected since last update: this plan, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/internal/group_envelope.go`, and `go-mknoon/node/pubsub.go` dirty diffs. Decision/blocker: scope is tests-first GK-014 only; production remains read-only unless exact row tests expose a mismatch. Next action: add row-owned tests.
- 2026-05-12T08:46:58Z - Executor spawn/running. Files inspected or touched: none beyond contract and owner diffs. Decision/blocker: nested Executor child could not materialize because this environment exposes no callable nested-agent spawn tool; using the skill's local sequential fallback inside this isolated execution agent. Next action: perform Executor responsibilities locally and run exact required commands.
- 2026-05-12T08:51:38Z - Executor tests added. Files inspected or touched: `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`; `gofmt` run on both. Decision/blocker: added the three row-owned GK-014 tests before any production edit; production remains unchanged by this session. Next action: run focused GK-014 proof commands.
- 2026-05-12T08:51:38Z - Required direct test started. Files inspected or touched: GK-014 test files. Command running: `(cd go-mknoon && go test ./internal -run '^TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction$' -count=1)`. Decision/blocker: none yet. Next action: record result and continue exact command list.
- 2026-05-12T08:52:39Z - Required direct test finished. Files inspected or touched: GK-014 test files. Command: `(cd go-mknoon && go test ./internal -run '^TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction$' -count=1)`. Decision/blocker: PASS. Next action: run focused node GK-014 proof.
- 2026-05-12T08:52:39Z - Required direct test started. Files inspected or touched: GK-014 test files. Command running: `(cd go-mknoon && go test ./node -run '^TestGK014(ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction|GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope)$' -count=1)`. Decision/blocker: none yet. Next action: record result and continue exact command list.
- 2026-05-12T08:53:19Z - Required direct test finished. Files inspected or touched: GK-014 test files. Command: `(cd go-mknoon && go test ./node -run '^TestGK014(ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction|GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope)$' -count=1)`. Decision/blocker: PASS; no production mismatch exposed. Next action: run adjacent parser/validator proof.
- 2026-05-12T08:53:19Z - Required direct test started. Files inspected or touched: GK-014 test files. Command running: `(cd go-mknoon && go test ./internal -run 'TestGK014|TestIsGroupEnvelope|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestMarshalParseGroupEnvelope|TestParseGroupEnvelope' -count=1)`. Decision/blocker: none yet. Next action: record result and continue exact command list.
- 2026-05-12T08:53:50Z - Required direct test finished. Files inspected or touched: GK-014 test files. Command: `(cd go-mknoon && go test ./internal -run 'TestGK014|TestIsGroupEnvelope|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestMarshalParseGroupEnvelope|TestParseGroupEnvelope' -count=1)`. Decision/blocker: PASS. Next action: run adjacent node validator proof.
- 2026-05-12T08:53:50Z - Required direct test started. Files inspected or touched: GK-014 test files. Command running: `(cd go-mknoon && go test ./node -run 'TestGK014|TestGroupTopicValidator_NotV3Envelope|TestGK013|TestGK012|TestGK011' -count=1)`. Decision/blocker: none yet. Next action: record result and continue exact command list.
- 2026-05-12T08:54:39Z - Required direct test finished. Files inspected or touched: GK-014 test files. Command: `(cd go-mknoon && go test ./node -run 'TestGK014|TestGroupTopicValidator_NotV3Envelope|TestGK013|TestGK012|TestGK011' -count=1)`. Decision/blocker: PASS. Next action: run broader row-relevant Go sweep.
- 2026-05-12T08:54:39Z - Required direct test started. Files inspected or touched: GK-014 test files. Command running: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)`. Decision/blocker: none yet. Next action: record result and run `git diff --check`.
- 2026-05-12T08:55:26Z - Required direct test finished. Files inspected or touched: GK-014 test files. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)`. Decision/blocker: PASS for `./node`, `./internal`, and `./crypto`. Next action: run `git diff --check`.
- 2026-05-12T08:55:26Z - Required gate started. Files inspected or touched: GK-014 test files and plan. Command running: `git diff --check`. Decision/blocker: none yet. Next action: record result, then run QA review.
- 2026-05-12T08:55:58Z - Required gate finished. Files inspected or touched: GK-014 test files and plan. Command: `git diff --check`. Decision/blocker: PASS. Next action: complete Executor handoff and run QA review.
- 2026-05-12T08:55:58Z - Executor completed. Files inspected or touched: `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`, this plan. Decision/blocker: tests-only implementation; no production changes made by GK-014 because focused tests passed. Next action: QA Reviewer local fallback pass.
- 2026-05-12T08:55:58Z - QA Reviewer spawn/running. Files inspected or touched: pending QA diff/test review. Decision/blocker: nested QA child could not materialize because this environment exposes no callable nested-agent spawn tool; continuing the skill's local sequential fallback. Next action: verify scope adherence, row-owned tests, exact command evidence, and residual items.
- 2026-05-12T08:57:26Z - QA Reviewer completed. Files inspected or touched: `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`, this plan, relevant status/diff evidence. Decision/blocker: no blocking issues; scope adhered, required row-owned tests exist, all required commands passed, no production/Dart changes from GK-014 so conditional race/Flutter commands were not required. Next action: write final execution verdict.
- 2026-05-12T08:57:26Z - Final verdict written. Files inspected or touched: this plan. Decision/blocker: `accepted` for GK-014 execution/QA; no fix pass needed. Next action: leave source matrix and breakdown closure rows unchanged for later closure audit.
- 2026-05-12T09:00:17Z - Controller verification recovery completed. Files inspected or touched: this plan, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`. Decision/blocker: execution child wrote row-owned tests and progress but did not return a chat final before shutdown; controller reran the exact required commands and all passed. Next action: fresh closure audit can use this plan plus on-disk tests as execution evidence.
- 2026-05-12 11:16 CEST - Closure Writer completed via bounded local fallback after a stalled writer child. Files inspected or touched: source matrix GK-014/GK-015 rows, breakdown Gap-Closure Reconciliation, closure progress, Session Closure Ledger, Matrix Row Inventory, Row Disposition Map, Session Ledger row 65, Ordered Session Breakdown row 65, and this plan. Decision/blocker: source GK-014 is now `Covered`, breakdown GK-014 rows are `covered/accepted`, this plan is `accepted/closed`, and no final program verdict was written. Next action: run closure review and continue from GK-015 if accepted.

## Evidence Collector Notes

- At planning intake, source matrix row GK-014 was `Open`, P0, Required host proof, Recommended real-network proof, expected `Only version 3 group_message and group_reaction are accepted`, with source note `group_envelope.go:71-82`. Closure later updated the source row to `Covered` with the row-owned evidence recorded in the Closure Note.
- At planning intake, breakdown row 65 classified GK-014 as `needs_tests_only` / `implementation-ready` with this plan path and no closure evidence yet. Closure later updated row 65 to `covered/accepted` with the row-owned evidence recorded in the Closure Note.
- `go-mknoon/internal/group_envelope.go:71-82` currently returns true only when parsed JSON has `version == "3"` and `type` is `group_message` or `group_reaction`; invalid JSON returns false.
- `go-mknoon/node/pubsub.go:783-786` calls `internal.IsGroupEnvelope(data)` before parse, sender/encrypted-field validation, group ID, transport peer binding, membership, key, signature, or decrypt behavior. Failure emits `group:validation_rejected` reason `not_v3_envelope` and rejects.
- `go-mknoon/node/pubsub_test.go:726-729` mirrors the same first gate in `validateGroupEnvelopeForTransportPeer`, returning `reject:not_v3`.
- Existing adjacent tests cover v3 `group_message`, v1/v2 non-group envelopes, invalid JSON, and one pure helper `TestGroupTopicValidator_NotV3Envelope`, but they are not exact GK-014 row-named coverage and do not table-drive accepted/rejected version/type combinations plus live validator rejection reason.
- `Test-Flight-Improv/test-gates-reference.md` says `scripts/run_test_gates.sh` wins for named gate membership. Group Messaging Gate is for Flutter group send/receive/retry/resume/invite/announcement behavior changes; GK-014 should not require Flutter unless Dart replay behavior is actually touched. Known baseline/posts/transport failures are unrelated to the planned focused Go proof.
- The worktree is already broadly dirty. GK-014 execution must work with existing owner-file changes and avoid reverting unrelated edits.

## real scope

Own exactly GK-014: prove that only JSON envelopes with `version == "3"` and `type` equal to `group_message` or `group_reaction` are accepted by the group-envelope classifier and allowed past the first group-topic validator gate.

Expected execution scope:

- Add row-named Go tests in `go-mknoon/internal/group_envelope_test.go` for accepted and rejected version/type combinations.
- Add row-named Go tests in `go-mknoon/node/pubsub_test.go` proving the pure validator returns `reject:not_v3` and the live `groupTopicValidator` emits `group:validation_rejected` reason `not_v3_envelope` for unsupported versions/types.
- Make no production changes if the exact tests pass against current behavior.
- Change production only if an exact GK-014 regression-first test proves current code accepts an unsupported version/type or rejects a supported v3 `group_message` / `group_reaction`.

Out of immediate scope: Flutter replay, real-network proof, durable inbox, crypto, key epochs, signatures, membership, transport peer binding, announcement authorization, and group wire-format changes.

## closure bar

GK-014 is good enough when:

- `IsGroupEnvelope` has a row-owned table proving true only for v3 `group_message` and v3 `group_reaction`, and false for unsupported versions, unsupported types, missing version/type, numeric/non-string version where relevant, and malformed JSON.
- The pure validator path rejects unsupported version/type payloads as `reject:not_v3` before parse, config, key, signature, or decrypt requirements can affect the result.
- The live `groupTopicValidator` direct path rejects unsupported version/type payloads with `pubsub.ValidationReject` and emits `group:validation_rejected` reason `not_v3_envelope`, using env-nil diagnostic evidence such as `envelopeType == "unknown"` and `keyEpoch == 0` where practical.
- Supported v3 `group_message` and v3 `group_reaction` still validate when the rest of the envelope is valid.
- Required focused and adjacent Go commands plus `git diff --check` pass.
- Source matrix GK-014 is not considered accepted until a later closure step records `Covered` or `Closed` with concrete file, test, and gate evidence. This session must not write a final program verdict while later rows remain unresolved.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-014.
- Active breakdown contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row 65 and related GK-014 ledger rows.
- Current implementation truth: `go-mknoon/internal/group_envelope.go`, `go-mknoon/node/pubsub.go`, and their direct tests.
- Named-gate truth if named Flutter gates are invoked: `scripts/run_test_gates.sh` wins over `Test-Flight-Improv/test-gates-reference.md` and `Test-Flight-Improv/test-gate-definitions.md`.
- On disagreement, current code and focused row-owned tests beat stale prose. Existing closed GK-010 through GK-013 evidence constrains adjacent parser/validator behavior.

## session classification

Historical planning classification: tests-only row proof needed before closure.

Closure classification: `accepted/closed`. The source matrix now records GK-014 as `Covered`, and breakdown row 65 records `covered/accepted` with row-owned test evidence.

## exact problem statement

At planning intake, GK-014 was open because the repo lacked exact row-owned proof that the group-envelope classifier and validator accept only v3 `group_message` / `group_reaction` and reject all other version/type combinations at the first validator gate. That proof is now recorded in the Closure Note.

The user-visible risk is schema drift: an unsupported version or type could be allowed deeper into group-message validation, leading to misleading diagnostics, later signature/decrypt work, or accidental acceptance of a non-v3 group payload.

What must stay unchanged:

- Accepted wire schema remains exactly version string `"3"` plus `group_message` or `group_reaction`.
- Unsupported versions/types continue to reject before parse/signature/decrypt behavior.
- Pure helper reason remains `reject:not_v3`; live validator event reason remains `not_v3_envelope`.
- GK-010 missing `groupId`, GK-011 missing `senderId`, GK-012 missing signature, and GK-013 missing encrypted-field behavior stay unchanged.

## files and repos to inspect next

Production, only if exact tests fail:

- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/node/pubsub.go`

Tests to edit:

- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/node/pubsub_test.go`

Tests to inspect only if direct validator proof is insufficient or timing/diagnostic helpers need reuse:

- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`

Docs for closure after execution, not during initial implementation:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`

## existing tests covering this area

- `go-mknoon/internal/group_envelope_test.go::TestIsGroupEnvelope_V3GroupMessage` proves one supported message case.
- `go-mknoon/internal/group_envelope_test.go::TestIsGroupEnvelope_V1Message`, `TestIsGroupEnvelope_V2Message`, and `TestIsGroupEnvelope_InvalidJSON` prove some unsupported cases.
- `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_NotV3Envelope` proves one pure helper v1 rejection as `reject:not_v3`.
- GK-010 through GK-013 tests pin adjacent parser/validator behavior for missing group ID, sender ID, signature, and encrypted fields.

Missing coverage:

- No exact `TestGK014...` row-named table covers both supported types and multiple unsupported version/type combinations.
- No row-owned test proves v3 `group_reaction` is accepted by `IsGroupEnvelope`.
- No row-owned pure validator table proves unsupported versions/types return `reject:not_v3` before later validation concerns.
- No row-owned live validator test proves event reason `not_v3_envelope`.

## regression/tests to add first

Add these tests before any production change:

1. `go-mknoon/internal/group_envelope_test.go::TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction`
   - Table-drive at least these cases: v3 `group_message` true, v3 `group_reaction` true, v2 `group_message` false, v4 `group_message` false, v3 unsupported type false, missing version false, missing type false, numeric `version: 3` false, and malformed JSON false.
   - Keep payloads minimal except when a full valid envelope improves clarity.

2. `go-mknoon/node/pubsub_test.go::TestGK014ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction`
   - Build a valid signed `group_message` envelope with existing helpers and assert pure validation returns `accept`.
   - Mutate only `Type` to `group_reaction` without changing signature data and assert pure validation returns `accept`.
   - For unsupported version/type payloads, pass nil config/key or otherwise later-invalid data and assert the result is exactly `reject:not_v3`; this proves the initial guard owns rejection before later paths.

3. `go-mknoon/node/pubsub_test.go::TestGK014GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope`
   - Directly instantiate `New(&testEventCollector{})`, call `groupTopicValidator(groupId)`, and pass unsupported payloads through `pubsub.Message`.
   - Use unique group IDs or peer IDs per subtest to avoid validation-diagnostic dedupe.
   - Assert `pubsub.ValidationReject`.
   - Assert the collected `group:validation_rejected` event has reason `not_v3_envelope`; where practical, assert env-nil diagnostics such as `envelopeType == "unknown"` and `keyEpoch == 0`.
   - Do not require a running topic, real libp2p fanout, decryption, or Flutter.

If all three tests pass against current code, stop and classify execution as tests-only. If any test fails because the accepted set or rejection reason is wrong, only then patch the smallest production seam.

## step-by-step implementation plan

1. Re-inspect the current dirty diff for `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/internal/group_envelope.go`, and `go-mknoon/node/pubsub.go` before editing so user changes are preserved.
2. Add the GK-014 tests listed above before production changes.
3. Run the focused internal and node GK-014 commands. Record whether the result is expected green proof or RED production mismatch.
4. If the focused tests pass, do not edit production. Proceed to adjacent and broader Go commands.
5. If a test exposes a production mismatch, patch only the smallest needed seam:
   - `go-mknoon/internal/group_envelope.go::IsGroupEnvelope` for classifier mismatch.
   - `go-mknoon/node/pubsub.go::groupTopicValidator` only if live validator no longer rejects the classifier failure as `not_v3_envelope`.
   - `go-mknoon/node/pubsub_test.go::validateGroupEnvelopeForTransportPeer` only to keep the pure helper aligned with production.
6. Run `gofmt` on changed Go files.
7. Run focused, adjacent, broader Go commands and `git diff --check`.
8. Do not run Flutter unless execution actually edits Dart replay or a source-of-truth mismatch proves GK-014 requires Dart behavior. Current evidence does not.
9. After tests pass, update GK-014 source matrix and breakdown closure rows only in the closure phase, recording concrete tests/gates. Do not write a final program verdict because later rows remain unresolved.

## risks and edge cases

- JSON unmarshalling into string fields treats numeric `version` as invalid for the peek struct; the test should expect false rather than accepting numeric `3`.
- Unsupported payloads can be structurally incomplete by design; the expected `reject:not_v3` / `not_v3_envelope` proves they did not reach later parse, config, key, signature, or decrypt paths.
- Validation diagnostics are deduped by reason, group, sender, and transport peer. Live validator subtests must use unique group IDs or peer IDs, or a fresh node, so events are not suppressed.
- `group_reaction` should be accepted by the first envelope gate and pure validator when the rest of the envelope is valid; changing that would regress reaction delivery.
- `group_message` announcement authorization and writer checks are later-path behavior and must not be conflated with GK-014.
- The repo has a dirty worktree; execution must not revert unrelated edits or classify unrelated existing test failures as GK-014 regressions.

## exact tests and gates to run

Focused GK-014 proof after adding tests:

```bash
(cd go-mknoon && go test ./internal -run '^TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction$' -count=1)
(cd go-mknoon && go test ./node -run '^TestGK014(ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction|GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope)$' -count=1)
```

Adjacent parser/validator proof:

```bash
(cd go-mknoon && go test ./internal -run 'TestGK014|TestIsGroupEnvelope|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestMarshalParseGroupEnvelope|TestParseGroupEnvelope' -count=1)
(cd go-mknoon && go test ./node -run 'TestGK014|TestGroupTopicValidator_NotV3Envelope|TestGK013|TestGK012|TestGK011' -count=1)
```

Broader row-relevant Go sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)
git diff --check
```

Conditional only if production validator code changes:

```bash
(cd go-mknoon && go test ./node -run 'TestGK014|TestGroupTopicValidator_NotV3Envelope|TestGK013|TestGK012|TestGK011' -race -count=1)
```

Conditional only if Dart replay code changes:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

No required Flutter named gate, simulator, or real-network command is part of GK-014 closure unless execution widens beyond the current Go classifier/validator seam. The source matrix marks real-network proof as Recommended, not Required.

## known-failure interpretation

- Existing focused commands reported by the controller already passed before planning:
  - `(cd go-mknoon && go test ./internal -run 'TestIsGroupEnvelope' -count=1)`
  - `(cd go-mknoon && go test ./node -run '^TestGroupTopicValidator_NotV3Envelope$' -count=1)`
- If a newly added GK-014 focused test fails on the accepted version/type set or rejection reason, treat it as a GK-014 production or helper mismatch.
- If an adjacent or broader Go command fails outside GK-014 tests, rerun the narrow failing selector without GK-014 changes where practical before classifying. Pre-existing unrelated failures must be recorded and not counted as GK-014 regressions.
- Known Flutter baseline/posts/transport failures in `Test-Flight-Improv/test-gates-reference.md` are irrelevant because this plan does not require those gates.
- `git diff --check` failures in files touched by GK-014 must be fixed. Whitespace failures in unrelated dirty files should be reported separately and not silently fixed unless they block committing GK-014 evidence.

## done criteria

- Row-owned GK-014 tests exist in `go-mknoon/internal/group_envelope_test.go` and `go-mknoon/node/pubsub_test.go`.
- Focused GK-014 internal and node commands pass.
- Adjacent parser/validator commands pass.
- Broader row-relevant Go sweep passes.
- `git diff --check` passes or any unrelated pre-existing whitespace issue is explicitly documented with scoped evidence.
- No production files changed unless a RED GK-014 proof required it.
- Source matrix GK-014 and breakdown row 65 are updated during closure with concrete file/test/gate evidence before the row is marked `Covered` or `Closed`.
- No final program verdict is written while later rows remain unresolved.

## scope guard

Do not change:

- The accepted version string.
- The accepted envelope types.
- Group wire format or JSON field names.
- Signature data, key epoch handling, encryption/decryption, or crypto helpers.
- Group membership, writer authorization, transport peer binding, diagnostics rate limits, or event schema beyond adding tests.
- Flutter replay or durable inbox behavior unless exact evidence proves GK-014 is owned there.
- Source matrix/breakdown closure state before execution evidence exists.

Overengineering for this session includes adding a version-negotiation layer, enum abstraction, parser rewrite, compatibility shim, new named gate, simulator harness, real-network harness, or broad group validator refactor.

## accepted differences / intentionally out of scope

- Pure helper rejection text is `reject:not_v3`; live validator event reason is `not_v3_envelope`. Both are intentional and should be asserted in their respective layers.
- Direct `groupTopicValidator` invocation is sufficient for required host proof; full libp2p publish/fanout proof is not required for GK-014.
- Real-network proof is Recommended-only and intentionally deferred unless a later closure policy chooses to add supporting evidence.
- Flutter/Dart offline replay is intentionally out of scope unless Dart files are touched or an exact GK-014 Dart mismatch is found.
- Closure docs are part of post-execution closure, not part of the initial test implementation.

## dependency impact

- Closing GK-014 lets later GK rows rely on a pinned v3/type admission guard when testing deeper key, signature, decrypt, or delivery behaviors.
- If execution changes accepted versions or types, downstream group replay, interop vectors, Dart replay, and any later rows that assume v3-only semantics must be revisited. This plan is designed to avoid that.
- After closure, rollout controllers should treat GK-014 as covered/accepted and continue from GK-015. The overall rollout still must not advance to a final program verdict while later source rows remain unresolved.

## Reviewer Pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none structurally missing. The plan includes exact focused GK-014 internal/node tests, adjacent parser/validator selectors, a broader Go selector, `git diff --check`, conditional race/Dart commands only when scope widens, and explicit source-matrix/breakdown closure requirements.

Stale or incorrect assumptions: none found. Current code evidence supports tests-only classification; production edits are guarded by exact RED proof.

Overengineering: none. The plan rejects version negotiation, parser rewrites, real-network harness work, Flutter gates, and broad validator refactors unless exact row evidence requires them.

Decomposition: sufficient. Implementation is constrained to two test files first, with only two production seams allowed if the row-owned tests fail.

Minimum needed to implement safely: add the three GK-014 tests before production changes, run the exact commands, and stop at tests-only closure if they pass.

## Arbiter Decision

Structural blockers: none.

Incremental details intentionally deferred:

- A full libp2p publish/fanout proof can be added later as supporting evidence, but direct `groupTopicValidator` event proof is enough for required host proof.
- A node race selector is conditional on production validator edits, not mandatory for tests-only closure.

Accepted differences intentionally left unchanged:

- Pure helper reason `reject:not_v3` and live event reason `not_v3_envelope` intentionally differ by layer.
- Real-network proof remains Recommended-only.
- Flutter/Dart replay remains out of scope unless execution touches Dart or finds a row-owned Dart mismatch.

Historical final planning verdict before execution: execution-ready. This was superseded by the accepted/closed Closure Note after GK-014 landed as tests-only `covered/accepted`.

## Final QA verdict

Verdict: accepted.

Blocking issues remaining: none.

Scope adherence: accepted. GK-014 landed tests only in `go-mknoon/internal/group_envelope_test.go` and `go-mknoon/node/pubsub_test.go`. No GK-014 production, Dart, Flutter, crypto, wire-format, signature, membership, authorization, transport, matrix, or breakdown closure changes were made during execution.

Behavior correctness: accepted. The row-owned tests prove `IsGroupEnvelope` returns true only for v3 `group_message` and v3 `group_reaction`, rejects unsupported versions/types, missing fields, numeric version, and malformed JSON, and that the pure and live validator gates reject unsupported versions/types before later parse/config/key/signature/decrypt paths.

Required command results:

- `(cd go-mknoon && go test ./internal -run '^TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/internal 0.171s`
- `(cd go-mknoon && go test ./node -run '^TestGK014(ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction|GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope)$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 0.362s`
- `(cd go-mknoon && go test ./internal -run 'TestGK014|TestIsGroupEnvelope|TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestMarshalParseGroupEnvelope|TestParseGroupEnvelope' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/internal 0.234s`
- `(cd go-mknoon && go test ./node -run 'TestGK014|TestGroupTopicValidator_NotV3Envelope|TestGK013|TestGK012|TestGK011' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 7.688s`
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK014|TestGK013|TestGK012|TestGK011|TestGK010|EncryptGroupMessage|DecryptGroupMessage' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 10.801s`; `ok github.com/mknoon/go-mknoon/internal 0.258s`; `ok github.com/mknoon/go-mknoon/crypto 0.727s`
- `git diff --check` -> passed with no output.

Conditional commands not run: node race was not required because GK-014 did not change production validator code; Flutter replay was not required because GK-014 did not touch Dart.

Done criteria: accepted for QA. Row-owned GK-014 internal and node tests exist and pass; adjacent GK-010 through GK-013 parser/validator selectors pass; broader row-relevant Go sweep and diff hygiene pass. Source matrix and session-breakdown closure rows were intentionally untouched during QA and were updated later by the closure step.

## Closure Note

- Closure status: accepted/closed.
- Closure evidence: source matrix GK-014 is `Covered`; breakdown GK-014 Matrix Row Inventory, Row Disposition Map, Session Ledger row 65, Ordered Session Breakdown row 65, and Session Closure Ledger record `covered/accepted`.
- Landed proof: `go-mknoon/internal/group_envelope_test.go::TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction`, `go-mknoon/node/pubsub_test.go::TestGK014ValidateGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction`, and `go-mknoon/node/pubsub_test.go::TestGK014GroupTopicValidatorRejectsUnsupportedVersionsAndTypesAsNotV3Envelope`.
- Behavior proven: only v3 `group_message` and v3 `group_reaction` pass `IsGroupEnvelope` and the first validator gate; unsupported versions/types, missing version/type, numeric version, and malformed JSON reject as pure `reject:not_v3` or live `not_v3_envelope` before parse/config/key/signature/decrypt paths.
- Validation: controller verification passed focused internal `ok internal 0.171s`, focused node `ok node 0.362s`, adjacent internal `ok internal 0.234s`, adjacent node `ok node 7.688s`, broader `ok node 10.801s` / `ok internal 0.258s` / `ok crypto 0.727s`, and `git diff --check`; fresh QA reruns passed focused internal `ok internal 0.384s`, focused node `ok node 0.455s`, adjacent internal `ok internal 0.178s`, adjacent node `ok node 7.680s`, broader `ok node 11.047s` / `ok internal 0.183s` / `ok crypto 0.477s`, and `git diff --check`; Completion Auditor reruns passed focused internal `ok internal 0.366s`, focused node `ok node 0.490s`, and `git diff --check`.
- Accepted differences: this is tests-only closure; direct pure validator and direct `groupTopicValidator` host proof are sufficient, full libp2p fanout/real-network proof remains Recommended-only, and race/Flutter commands were not required because GK-014 did not change production validator or Dart replay code.
- Residual-only: none for GK-014. GK-015 remains the next unresolved P0 row; no final program verdict was written.
