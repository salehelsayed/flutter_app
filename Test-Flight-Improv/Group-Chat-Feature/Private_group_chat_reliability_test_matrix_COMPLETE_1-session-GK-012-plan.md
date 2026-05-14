Status: accepted/closed

# GK-012 Missing Group Envelope Signature Plan

## Planning Progress

- 2026-05-12T08:09:55+02:00 - Role: Planner completed. Files inspected since last update: full draft plan content. Decision/blocker: draft was ready for execution, test-first, and expected tests-only closure unless the row proof failed; no blocker. Next action: run reviewer sufficiency pass.
- 2026-05-12T08:11:41+02:00 - Role: Reviewer started. Files inspected since last update: draft plan sections and mandatory-section checklist. Decision/blocker: reviewing for missing no-decrypt proof, stale gate assumptions, overbroad Flutter scope, and whether the no-production-change branch is still implementation-owned. Next action: classify sufficiency and required adjustments.
- 2026-05-12T08:12:20+02:00 - Role: Reviewer completed. Files inspected since last update: full draft plan, mandatory sections, test list, command list, source-of-truth hierarchy, and scope guard. Decision/blocker: sufficient as-is; no structural blocker. Next action: Arbiter will classify reviewer findings and either pass or request one patch.
- 2026-05-12T08:13:12+02:00 - Role: Arbiter started. Files inspected since last update: reviewer findings, draft scope guard, closure bar, tests, and gates. Decision/blocker: classifying findings into structural blockers, incremental details, and accepted differences. Next action: finalize or request one patch only if a structural blocker exists.
- 2026-05-12T08:13:52+02:00 - Role: Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers; plan is execution-ready. Next action: implement GK-012 exactly as scoped in a later execution pass, starting with the two row-owned tests.

## Execution Progress

- 2026-05-12T08:18:11+02:00 - Role: Executor started. Files inspected since last update: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/sign.go`, and `git status --short`. Decision/blocker: GK-012 contract extracted; worktree is already dirty with unrelated Go/Flutter/doc edits, including the row-owned Go test files, so execution will make only additive GK-012 test changes and avoid production unless tests disprove current behavior. Next action: add the two row-owned GK-012 tests.
- 2026-05-12T08:20:03+02:00 - Role: Executor implementation completed. Files touched since last update: `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`. Decision/blocker: added the pure missing-signature validator proof and the two-node raw-publish/no-event validator proof; no production file edited for GK-012. Next action: run `gofmt` on touched Go files, then execute the required Go selectors and diff hygiene.
- 2026-05-12T08:23:02+02:00 - Role: Executor validation. Files touched since last update: formatted `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_decryption_failure_test.go`. Command started/finished: `(cd go-mknoon && go test ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)`. Decision/blocker: first attempt hit Go build-cache disk exhaustion (`no space left on device`); after `go clean -cache -testcache`, rerun passed: `ok github.com/mknoon/go-mknoon/node 2.680s`. Next action: run adjacent closed-row preservation selector.
- 2026-05-12T08:23:55+02:00 - Role: Executor validation. Files inspected/touched since last update: none. Command started/finished: `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic|TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)`. Decision/blocker: passed: `ok github.com/mknoon/go-mknoon/node 7.235s`. Next action: run broader Go parser/signature/envelope sweep.
- 2026-05-12T08:24:50+02:00 - Role: Executor validation. Files inspected/touched since last update: none. Command started/finished: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK010|TestGK011|TestGK012|TestGK008|TestGK006|SignatureData|VerifyPayload' -count=1)`. Decision/blocker: passed: `ok github.com/mknoon/go-mknoon/node 10.105s`; `ok github.com/mknoon/go-mknoon/internal 0.945s`; `ok github.com/mknoon/go-mknoon/crypto 0.662s`. Next action: run focused race selector.
- 2026-05-12T08:26:21+02:00 - Role: Executor validation. Files inspected/touched since last update: none. Command started/finished: `(cd go-mknoon && go test -race ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)`. Decision/blocker: passed: `ok github.com/mknoon/go-mknoon/node 3.729s`. Next action: run `git diff --check`.
- 2026-05-12T08:27:46+02:00 - Role: Executor validation completed. Files inspected/touched since last update: diff hygiene only. Command started/finished: `git diff --check`. Decision/blocker: passed with no output. Next action: write final execution verdict.
- 2026-05-12T08:28:36+02:00 - Role: Executor finalization completed. Files touched since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-012-plan.md`. Command started/finished: final `git diff --check`. Decision/blocker: final execution verdict written as accepted; diff hygiene still passes with no output. Next action: stop.
- 2026-05-12T08:34:06+02:00 - Role: QA Reviewer started. Files inspected since last update: this plan, landed GK-012 hunks in `go-mknoon/node/pubsub_test.go` and `go-mknoon/node/pubsub_decryption_failure_test.go`, plus validator/parser/signature code in `go-mknoon/node/pubsub.go`, `go-mknoon/internal/group_envelope.go`, and `go-mknoon/crypto/sign.go`. Decision/blocker: tests are row-owned and additive; no GK-012 production-code change found. Next action: rerun required GK-012 commands.
- 2026-05-12T08:34:06+02:00 - Role: QA Reviewer validation completed. Commands started/finished: all required GK-012 focused, adjacent, broader Go, race, and `git diff --check` commands. Decision/blocker: all passed; no failed command to classify. Next action: write final QA verdict.
- 2026-05-12T08:34:06+02:00 - Role: QA Reviewer finalization completed. Files touched since last update: this GK-012 plan only. Decision/blocker: final QA verdict written as accepted; no blocking issues. Next action: closure may update the source matrix and breakdown.
- 2026-05-12 08:44:35 CEST - Closure Writer completed. Files inspected since last update: source matrix GK-012/GK-013 rows, breakdown current update and GK-012 ledger rows, accepted GK-012 plan evidence, and final-program-verdict search. Files touched since last update: source matrix, session breakdown, and this plan. Decision/blocker: closure docs accepted for the completed row; row-owned evidence now lives in the source matrix, breakdown, and Closure Note. Next action: run stale-state and diff-hygiene verification.

## Final execution verdict

Verdict: accepted.

Files changed by GK-012 execution:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-012-plan.md`

Production code changed: no GK-012 production code was changed. `go-mknoon/node/pubsub.go` remains dirty from pre-existing unrelated work and was not edited in this execution pass.

Evidence: both GK-012 row-owned tests were added, `gofmt` was run on touched Go test files, all required focused/adjacent/broader/race Go selectors passed, and `git diff --check` passed. The first focused selector attempt failed before test execution due to Go build-cache disk exhaustion (`no space left on device`); `go clean -cache -testcache` freed space and the exact selector passed on rerun.

Blocking issues remaining: none.

## Final QA verdict

Verdict: accepted.

Blocking issues remaining: none.

Scope adherence: accepted. QA reviewed only GK-012 scope: missing top-level `signature` on an otherwise valid v3 group envelope. The row-owned tests are additive and named for GK-012. The validator behavior remains the existing parser -> sender validation -> signature verification path, with missing signature rejected as `bad_signature_or_epoch` before decrypt/event emission.

Production code changed for GK-012: no. The worktree contains unrelated dirty production files, including `go-mknoon/node/pubsub.go`, but QA found no GK-012 production edit to parser policy, signature verification, decrypt handling, or rejection taxonomy.

Required command results:

- `(cd go-mknoon && go test ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 2.604s`
- `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic|TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 7.167s`
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK010|TestGK011|TestGK012|TestGK008|TestGK006|SignatureData|VerifyPayload' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 10.293s`; `ok github.com/mknoon/go-mknoon/internal 0.290s`; `ok github.com/mknoon/go-mknoon/crypto 0.885s`
- `(cd go-mknoon && go test -race ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 3.673s`
- `git diff --check` -> passed with no output.

Non-blocking follow-ups deferred: none.

## Closure Note

- Closure status: accepted/closed.
- Closure evidence: source matrix GK-012 is `Covered`; breakdown GK-012 inventory, disposition, session ledger row 63, ordered session row 63, and session closure ledger record `covered/accepted`.
- Landed proof: no GK-012 production code changed; missing signature closes through existing `VerifyPayload` / bad-signature behavior rather than parser-level structural validation.
- Tests: `go-mknoon/node/pubsub_test.go::TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature` deletes the top-level JSON `signature` key, confirms the envelope remains v3/parseable with `Signature == ""`, and asserts pure validation returns `reject:bad_signature`. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage` publishes the missing-signature envelope through the real two-node PubSub validator path, observes `group:validation_rejected` reason `bad_signature_or_epoch`, and proves no post-baseline receive, reaction, or decrypt-failed events.
- Validation: executor and QA reruns passed the focused, adjacent, broader, race, and `git diff --check` commands recorded above.
- Accepted differences: `ParseGroupEnvelope` remains groupId-only for GK-012; the row closes through bad-signature validation rather than parser-required `signature`.
- Residual-only: none for GK-012. GK-013 remains the next unresolved P0 row.

## real scope

Own exactly source row GK-012: a v3 group envelope has the required structural fields but omits the top-level JSON `signature` key. The validator must reject it as `bad_signature_or_epoch` on the production `groupTopicValidator` path, and the rejected envelope must not reach decrypt, `group_message:received`, or `group_reaction:received`.

Repo-owned closure is code/test proof in `go-mknoon`, not a docs-only downgrade. Current code evidence indicates no production edit is expected: missing JSON `signature` unmarshals to `env.Signature == ""`; `verifyGroupEnvelopeSignature` calls `mcrypto.VerifyPayload`; `VerifyPayload` decodes an empty signature to zero bytes, returns an invalid signature length error, and the validator logs `bad_signature_or_epoch`.

Minimal production code is allowed only if the row-owned tests disprove that path. If needed, add a narrow empty-signature guard that still returns through the existing bad-signature branch, preferably inside `verifyGroupEnvelopeSignature` before `VerifyPayload`:

```go
if strings.TrimSpace(env.Signature) == "" {
    return false
}
```

Do not change `ParseGroupEnvelope` to make missing signature `invalid_envelope` in this session, because the row expectation is `bad_signature_or_epoch` and GK-010/GK-011 already define the current parser/validator split.

## closure bar

GK-012 is good enough when a missing-signature envelope built from a valid signed envelope:

- remains recognizable as a v3 group envelope and parseable with `Signature == ""`
- returns `reject:bad_signature` from `validateGroupEnvelope`
- is rejected by the real `groupTopicValidator` with `group:validation_rejected` reason `bad_signature_or_epoch`
- produces no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed` after the validator rejection baseline
- passes the focused, adjacent, broader Go, race, and diff-hygiene commands below
- leaves GK-010 and GK-011 closed and does not claim GK-013 or later rows

## source of truth

Authoritative task sources:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-012: status `Covered`, expected `bad_signature_or_epoch`, no decrypt/event, with concrete row-owned test evidence.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row GK-012: `needs_code_and_tests` / `covered/accepted`, with this plan as the closure record.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`: named gate source of truth. The script wins if they disagree.
- Current code and focused tests win over stale prose.

Behavior sources:

- `go-mknoon/internal/group_envelope.go`: `ParseGroupEnvelope` requires only `groupId`; omitted `signature` becomes an empty string.
- `go-mknoon/node/pubsub.go`: `groupTopicValidator` rejects bad signatures as `bad_signature_or_epoch` before subscription decrypt.
- `go-mknoon/crypto/sign.go`: `VerifyPayload` rejects empty signatures through invalid signature length.
- `go-mknoon/node/pubsub_test.go`: pure validator helper, `buildTestEnvelope`, and GK-011's `deleteGroupEnvelopeJSONField`.
- `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, and `go-mknoon/node/pubsub_delivery_test.go`: existing raw-publish and no-event proof pattern.

## session classification

accepted/closed.

Reason: GK-012 is closed as tests-only implementation-committed gap closure because the row-owned pure validator and real PubSub validator/no-event proofs were added, all required executor/QA commands passed, and the source matrix plus breakdown now carry concrete `Covered` / `covered/accepted` evidence.

## exact problem statement

GK-012 is closed because the repo now has row-owned proof that a v3 group envelope with all normal fields except `signature` is rejected as `bad_signature_or_epoch` and never reaches decrypt or event emission.

The user-visible security behavior is that unsigned group traffic cannot create or decrypt a group message, reaction, or diagnostic that implies decrypt was attempted. Existing valid signed message/reaction behavior, group key epoch logic, parser behavior for `groupId`, GK-011 sender validation, and adjacent signature-tamper rows must stay unchanged.

## files and repos to inspect next

Production:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/sign.go`

Tests/helpers:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/crypto/sign_test.go`

Docs/gates:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

No Flutter file is expected to be touched for GK-012. Only inspect `test/features/groups/application/group_offline_replay_envelope_test.dart` if execution unexpectedly discovers that source docs require Dart offline replay parity for this row; do not include it by default.

## existing tests covering this area

- GK-006 proves post-signing ciphertext mutation rejects through signature validation and emits no receive/reaction/decrypt event.
- GK-007 proves nonce mutation passes signature validation, fails AES-GCM decrypt, and emits no receive/reaction/plaintext event.
- GK-008 proves wrong public key signature rejection emits `bad_signature_or_epoch` and no receive/reaction/decrypt event.
- GK-009 proves signature data is deterministic and epoch-bound.
- GK-010 proves missing `groupId` is parser-owned and rejected by `ParseGroupEnvelope`.
- GK-011 proves omitted `senderId` is validator-owned `invalid_envelope` with no panic and keeps parser behavior unchanged.
- Existing generic bad-signature tests in `go-mknoon/node/pubsub_test.go` cover wrong keys and forged events, but not an omitted `signature` JSON field.

Closed coverage: row-named GK-012 tests now delete the `signature` field from an otherwise valid envelope, check the pure helper result, and exercise the real PubSub validator with no decrypt/event proof.

## regression/tests to add first

Add tests before any production edit:

1. `go-mknoon/node/pubsub_test.go::TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature`
   - Generate a valid group key and Ed25519 member key.
   - Build a valid v3 envelope with `buildTestEnvelope`.
   - Remove the top-level `signature` key with `deleteGroupEnvelopeJSONField`.
   - Assert raw JSON has no `signature` key.
   - Assert `internal.IsGroupEnvelope(missingSignatureEnvelope)` is true.
   - Assert `internal.ParseGroupEnvelope` succeeds and `env.Signature == ""`.
   - Assert `validateGroupEnvelope(missingSignatureEnvelope, groupId, config, keyInfo) == "reject:bad_signature"`.
   - This proves current code routes omission through `VerifyPayload` / bad signature instead of parse, member, key, or decrypt paths.

2. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage`
   - Start two local nodes using the same group security harness style as GK-006 and GK-008.
   - Join both to the same group with a valid config and current `GroupKeyInfo`.
   - Build a valid envelope, delete `signature`, and assert the pure helper returns `reject:bad_signature`.
   - Record node B event baseline.
   - Unregister only node A's local validator before raw publish so node B's validator is under test.
   - Publish the missing-signature envelope.
   - Wait for node B `group:validation_rejected` with reason `bad_signature_or_epoch` and the expected key epoch.
   - Assert no post-baseline `group_message:received`, `group_reaction:received`, or `group:decryption_failed`.

If both tests pass against current production, stop without production code. If either test fails because the missing signature is accepted, panics, emits decrypt/receive events, or reports an unexpected rejection reason, add the minimal production guard described in `real scope`, then rerun the same tests.

## step-by-step implementation plan

1. Re-check `git status --short` and note unrelated dirty worktree files. Do not revert or overwrite edits by others.
2. Add `TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature` in `go-mknoon/node/pubsub_test.go` near the GK-011 missing-field tests so it reuses `buildTestEnvelope` and `deleteGroupEnvelopeJSONField`.
3. Run the focused pure-helper selector for GK-012. Expected result from current evidence: pass without production code.
4. Add `TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage` in `go-mknoon/node/pubsub_decryption_failure_test.go` near the GK-006/GK-008 signature rejection tests.
5. Run the focused two-test selector. Expected result from current evidence: pass without production code.
6. If the focused tests fail for a real GK-012 behavior gap, patch only `go-mknoon/node/pubsub.go` so missing or whitespace-only signatures return false from signature verification and continue to log `bad_signature_or_epoch`. Do not modify parser required fields or decrypt handling.
7. Run adjacent and broader Go selectors, then the focused race selector and `git diff --check`.
8. Only after implementation/QA acceptance, update source matrix and session breakdown closure entries for GK-012. Do not update GK-013+ or write a final program verdict in this execution session.

## risks and edge cases

- Missing `signature` is not a parser error today. Changing parser policy would alter row semantics and risk reopening GK-010/GK-011 accepted differences.
- `VerifyPayload("")` returns an error because the decoded signature length is zero. The plan relies on the validator treating that as bad signature, which current code does.
- Raw PubSub publish can be stopped by node A's local validator before node B observes the malformed envelope. The live test must unregister only node A's local topic validator while leaving node B's validator active.
- Event assertions must use a post-setup baseline to avoid failing on unrelated startup/join events.
- The worktree is already dirty in many files. Execution must touch only the row-owned test file(s) and `go-mknoon/node/pubsub.go` if genuinely needed.

## exact tests and gates to run

Focused GK-012:

```bash
cd go-mknoon && go test ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1
```

Adjacent closed-row preservation:

```bash
cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestGK008SignatureRejectsWrongPublicKeyAndEmitsNoMessage|TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope|TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic|TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1
```

Broader Go parser/signature/envelope sweep:

```bash
cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK010|TestGK011|TestGK012|TestGK008|TestGK006|SignatureData|VerifyPayload' -count=1
```

Focused race check:

```bash
cd go-mknoon && go test -race ./node -run '^(TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature|TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage)$' -count=1
```

Diff hygiene:

```bash
git diff --check
```

Named gates:

- No Flutter named gate is required if execution only adds Go node tests or the narrow Go validator guard.
- Run `./scripts/run_test_gates.sh groups` only if execution unexpectedly touches Flutter group send, receive, retry, resume, invite, or announcement behavior.
- Run `./scripts/run_test_gates.sh completeness-check` only if a new Dart/integration test or gate classification change is added. This is not expected for GK-012.

## known-failure interpretation

- A focused GK-012 failure before production edits is useful RED evidence only if it shows acceptance, panic, decrypt/receive event emission, or a wrong validator reason for the missing-signature envelope.
- If the pure-helper test passes immediately, that is acceptable row-owned proof that current production already routes missing signature through `VerifyPayload`; do not invent a production edit just to make the session look larger.
- If the live test times out waiting for node B validation rejection, first check whether node A's local validator rejected before fanout or whether the event baseline was taken too early. Do not patch decrypt code to compensate for a harness mistake.
- Failures in unrelated dirty-worktree Flutter tests or broad package tests should be isolated and reported as pre-existing unless the focused GK-012 tests or touched Go files are implicated.
- Any race failure in the focused GK-012 selector is blocking for this row. A race failure outside the focused selector needs separate attribution before it is counted against GK-012.

## done criteria

- The two GK-012 row-owned tests exist and are named exactly enough to be grep-findable by `GK012`.
- Missing top-level `signature` is generated by structured JSON field deletion, not by string replacement.
- Pure helper rejects missing signature as `reject:bad_signature`.
- Real `groupTopicValidator` rejects missing signature as `bad_signature_or_epoch`.
- No post-baseline `group_message:received`, `group_reaction:received`, or `group:decryption_failed` event appears for the missing-signature envelope.
- Production code is unchanged if the tests pass against current behavior; if production code changes, the diff is limited to the narrow bad-signature guard in `go-mknoon/node/pubsub.go`.
- Focused, adjacent, broader Go, race, and `git diff --check` commands pass or have clearly attributed pre-existing non-GK-012 failures.
- GK-010 and GK-011 remain covered/accepted. GK-013 and later rows remain open and untouched.

## scope guard

Do not implement or close:

- GK-013 missing encrypted fields
- GK-014 version/type matrix
- GK-015 group mismatch
- GK-016+ key-rotation and epoch-window rows
- nonce signing, signature-data redesign, or all-field canonical signature expansion
- parser-wide schema validation beyond what GK-010/GK-011 already established
- Dart offline replay, Flutter UI, notification, simulator, or bridge work
- broad security-event family parity or device identity binding

Overengineering for this session includes changing envelope JSON struct tags, adding a schema validator framework, changing rejection reason taxonomy, or expanding tests to every missing field.

## accepted differences / intentionally out of scope

- Missing signature may close as `bad_signature_or_epoch` through `VerifyPayload` rather than an explicit parser-level structural error. That is acceptable because it matches the row expected reason and still rejects before decrypt/event.
- `ParseGroupEnvelope` remains intentionally narrow and groupId-owned for this session.
- GK-011's missing sender behavior remains `invalid_envelope`; GK-012's missing signature behavior remains `bad_signature_or_epoch`.
- Dart offline replay signature/hash behavior is a separate architecture path and does not need to be proven for this Go PubSub row unless future source docs explicitly re-scope GK-012.

## dependency impact

Closing GK-012 gives later malformed-envelope rows a stable proof that missing signature fails before decrypt/event. GK-013 can then focus on encrypted ciphertext/nonce absence without also proving missing signature. If execution changes the parser/validator split or rejection reason, GK-013+ plans must re-check their assumptions before implementation.

## Reviewer Sufficiency Questions

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? No files, tests, regressions, or gates remain missing for GK-012. The two row-owned tests cover the pure validator and real PubSub validator/no-event path. The command list included focused, adjacent, broader Go, race, and diff hygiene; named Flutter gates stayed correctly conditional.
- What assumptions are stale or incorrect? No stale or incorrect assumptions remain for GK-012. The main assumption, that missing `signature` reaches `VerifyPayload` as an empty string, was grounded in `ParseGroupEnvelope`, `verifyGroupEnvelopeSignature`, and `VerifyPayload`, and the row-owned tests proved it before any production edit.
- What is overengineered? Nothing material. The plan avoids parser redesign, signature-data redesign, GK-013+, Flutter, simulator, and broad security-family parity.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. It specifies exact test names, helper usage, event assertions, and the only allowed fallback production guard.
- What is the minimum needed to make the plan sufficient? Already present: two GK-012 tests plus the optional narrow guard only if those tests fail.

## Arbiter Decision

Structural blockers: none.

Incremental details: none required before execution. The conditional named-gate guidance is intentionally narrow because the planned changes are Go-only.

Accepted differences: missing signature is allowed to close through the existing bad-signature verification path rather than a parser-level schema error. Parser required-field behavior and GK-011 invalid-envelope behavior stay unchanged.

Stop rule: no structural blocker remains, so stop planning. Do not loop on optional refinements or reopen accepted differences.

## Final verdict

Accepted/closed. Session classification is `covered/accepted`.

## Final plan

Implement GK-012 with two row-owned Go node tests first: one pure-validator proof in `go-mknoon/node/pubsub_test.go`, and one real PubSub validator/no-event proof in `go-mknoon/node/pubsub_decryption_failure_test.go`. Production code should remain unchanged if those tests pass against current behavior. If the tests reveal a real gap, add only a narrow empty-signature guard that still rejects through the existing `bad_signature_or_epoch` branch.

## Structural blockers remaining

No structural blockers remain.

## Incremental details intentionally deferred

- Closure-doc updates belong after execution/QA acceptance, not this planning-only pass.
- `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh completeness-check` remain conditional because no Dart or gate-classification change is planned.

## Accepted differences intentionally left unchanged

- Missing signature can be rejected through `VerifyPayload` as bad signature rather than parser structural validation.
- `ParseGroupEnvelope` remains groupId-only for GK-012.
- GK-010/GK-011 remain closed; GK-013+ remain out of scope.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/crypto/sign.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/group_security_harness_test.go`

## Why the plan is safe or unsafe to implement now

Closed after implementation and QA. The source row is covered, the current code path is proven by narrow row-owned tests, no fallback production guard was needed, and the scope guard prevented reopening GK-010/GK-011 or absorbing GK-013+.
