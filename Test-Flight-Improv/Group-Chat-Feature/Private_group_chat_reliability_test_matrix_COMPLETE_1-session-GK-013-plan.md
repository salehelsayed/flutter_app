# GK-013 Plan - Envelope parser/validator rejects missing encrypted fields

Status: accepted/closed

## Planning Progress

- 2026-05-12 09:14:00 CEST - Planner completed. Files inspected since last update: `/opt/homebrew/Cellar/go/1.25.0/libexec/src/crypto/cipher/gcm.go`. Decision/blocker: draft plan written; no blocker. Next action: reviewer pass for sufficiency, missing gates, stale assumptions, and over-scope.
- 2026-05-12 09:17:00 CEST - Reviewer started. Files inspected since last update: this plan file; mandatory-section scan. Decision/blocker: all mandatory sections are present; no blocker. Next action: classify sufficiency and missing details.
- 2026-05-12 09:18:00 CEST - Reviewer completed. Files inspected since last update: this plan file. Decision/blocker: sufficient as-is with one non-structural optional detail; no blocker. Next action: arbiter classification and final status.
- 2026-05-12 09:20:00 CEST - Arbiter started. Files inspected since last update: reviewer pass in this plan. Decision/blocker: no structural blockers to patch; stop rule applies after classification. Next action: write final arbiter decision.
- 2026-05-12 09:21:00 CEST - Arbiter completed. Files inspected since last update: this plan file. Decision/blocker: execution-ready; no structural blockers remain. Next action: hand off plan for GK-013 execution.

## Execution Progress

- 2026-05-12 09:13:44 CEST - Executor running; contract extraction started. Files inspected or touched: this plan file and skill instructions. Command: none. Decision/blocker: dirty worktree noted; no blocker because GK-013 owner files are explicit. Next action: extract exact scope, tests, gates, known-failure interpretation, done criteria, and scope guard.
- 2026-05-12 09:13:44 CEST - Contract extracted. Files inspected or touched: this plan file. Command: none. Decision/blocker: scope is host-only Go proof in `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, and `go-mknoon/node/pubsub_decryption_failure_test.go`; source matrix and breakdown closure rows remain out of scope until QA. Required red tests and exact validation commands are present. Next action: inspect owner files and add regression-first tests.
- 2026-05-12 09:16:19 CEST - Regression-first tests started. Files inspected or touched: `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`. Command: none. Decision/blocker: existing dirty owner-file changes observed; no unrelated edits will be reverted. Next action: add GK-013 tests without production changes.
- 2026-05-12 09:18:45 CEST - Regression-first tests added. Files inspected or touched: `go-mknoon/crypto/group_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`. Command: `gofmt -w go-mknoon/crypto/group_test.go go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go`. Decision/blocker: row-owned tests added before production changes. Next action: run expected-red focused commands and record failure modes.
- 2026-05-12 09:20:03 CEST - Regression-first expected-red completed. Files inspected or touched: GK-013 test files only. Commands: `(cd go-mknoon && go test ./crypto -run '^TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic$' -count=1)` failed as expected with missing ciphertext returning `aes-gcm decrypt` instead of `missing ciphertext` and missing/short nonce panicking; `(cd go-mknoon && go test ./node -run 'TestGK013' -count=1)` failed as expected with pure/live missing ciphertext returning `bad_signature` and missing nonce returning `accept`. Decision/blocker: failures are GK-013-caused expected gaps, not pre-existing or environment failures. Next action: implement narrow production helper/decrypt guards.
- 2026-05-12 09:20:49 CEST - Implementation started. Files inspected or touched: `go-mknoon/crypto/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Command: none. Decision/blocker: applying only the planned decrypt input guards and shared encrypted-field validator helper. Next action: patch production and pure-helper paths, then gofmt.
- 2026-05-12 09:22:20 CEST - Implementation completed. Files inspected or touched: `go-mknoon/crypto/group.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`. Command: `gofmt -w go-mknoon/crypto/group.go go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go`. Decision/blocker: added decrypt guards for missing ciphertext, missing nonce, empty decoded ciphertext, and wrong nonce length; added shared encrypted-field helper used by live and pure validators. Next action: run required validation commands.
- 2026-05-12 09:22:57 CEST - Validation started. Files inspected or touched: owner files only. Command: required GK-013 focused and broader Go selectors plus `git diff --check`. Decision/blocker: no validation blocker yet. Next action: run each command in the exact plan order and classify any failure before fixing.
- 2026-05-12 09:23:44 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./crypto -run '^TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic$' -count=1)`. Decision/blocker: passed. Next action: run focused node GK-013 selector.
- 2026-05-12 09:24:42 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./node -run 'TestGK013' -count=1)`. Decision/blocker: passed. Next action: run focused crypto regression selector.
- 2026-05-12 09:25:26 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./crypto -run 'TestGK013|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt' -count=1)`. Decision/blocker: passed. Next action: run focused adjacent node selector.
- 2026-05-12 09:26:18 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -count=1)`. Decision/blocker: passed. Next action: run broader row-relevant Go sweep.
- 2026-05-12 09:27:16 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK013|TestGK012|TestGK011|TestGK010|TestGK007|TestGK006|DecryptGroupMessage' -count=1)`. Decision/blocker: passed for `./node`, `./internal`, and `./crypto`. Next action: run required node race selector.
- 2026-05-12 09:28:27 CEST - Validation command finished. Files inspected or touched: none. Command: `(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -race -count=1)`. Decision/blocker: passed. Next action: run `git diff --check`.
- 2026-05-12 09:29:04 CEST - Validation command finished. Files inspected or touched: none. Command: `git diff --check`. Decision/blocker: passed. Next action: inspect final diff, record executor verdict, and hand off for QA.
- 2026-05-12 09:31:01 CEST - Executor final verdict written. Files inspected or touched: this plan file and GK-013 owner files. Command: none. Decision/blocker: accepted for QA; no blocking issue remains in the executor pass. Source matrix and session breakdown closure rows intentionally not updated. Next action: QA reviewer can verify scope, diffs, and recorded gate evidence.
- 2026-05-12 09:49:28 CEST - QA Reviewer running. Files inspected or touched: this plan file, source matrix GK-013 row, breakdown GK-013 row, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, and `go-mknoon/internal/group_envelope.go`. Commands finished: GK-013 crypto focused passed (`ok crypto 0.424s`), GK-013 node focused passed (`ok node 5.701s`), crypto regression selector passed (`ok crypto 0.203s`), adjacent node selector passed (`ok node 11.955s`), broader node/internal/crypto selector passed (`ok node 16.370s`, `ok internal 0.368s`, `ok crypto 0.545s`), node race selector passed (`ok node 13.338s`). Decision/blocker: no QA blocking issue found so far; `git diff --check` still pending. Next action: run `git diff --check` and write final QA verdict.
- 2026-05-12 09:51:43 CEST - QA Reviewer validation completed. Files inspected or touched: diff hygiene only. Command: `git diff --check`. Decision/blocker: passed with no output; no failed QA command to classify. Next action: write final QA verdict.
- 2026-05-12 09:51:43 CEST - QA Reviewer finalization completed. Files touched since last update: this GK-013 plan only. Command: none. Decision/blocker: final QA verdict written as accepted; no blocking issues remain. Next action: closure may update the source matrix and breakdown outside this QA-only scope.
- 2026-05-12 10:08:25 CEST - Closure Writer completed. Files inspected since last update: source matrix GK-013/GK-014 rows, breakdown current update and GK-013 ledger rows, accepted GK-013 plan evidence, provided Completion Auditor verdict, and final-program-verdict search. Files touched since last update: source matrix, session breakdown, and this plan. Command: none. Decision/blocker: closure docs accepted for the completed row; row-owned evidence now lives in the source matrix, breakdown, and Closure Note. Next action: run stale-state and diff-hygiene verification.

## Final QA verdict

Verdict: accepted.

Blocking issues remaining: none.

Scope adherence: accepted. QA reviewed only GK-013 Go behavior for missing `encrypted.ciphertext` and missing `encrypted.nonce`, plus the adjacent GK-006/GK-007/GK-011/GK-012 preservation tests. No Flutter, wire-format, signature-format, membership, retry, inbox, matrix, or breakdown closure edits were made by QA.

Behavior correctness: accepted. `DecryptGroupMessage` now returns diagnostic errors for missing ciphertext, missing nonce, and wrong decoded nonce length before AES-GCM can panic. The live `groupTopicValidator` and pure test helper both reject missing encrypted fields as `invalid_envelope` before signature verification or subscription decrypt. GK-007 present-but-tampered nonce still remains a decrypt-failure path, and GK-012 missing signature still remains a bad-signature path.

Regression-first classification: accepted. The executor recorded the required regression-first failures before production changes: missing ciphertext returned the old decrypt/bad-signature behavior, missing/short nonce could panic or accept, and those failures were classified as expected GK-013-caused gaps before the fix.

Required command results:

- `(cd go-mknoon && go test ./crypto -run '^TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic$' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/crypto 0.424s`
- `(cd go-mknoon && go test ./node -run 'TestGK013' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 5.701s`
- `(cd go-mknoon && go test ./crypto -run 'TestGK013|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/crypto 0.203s`
- `(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 11.955s`
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK013|TestGK012|TestGK011|TestGK010|TestGK007|TestGK006|DecryptGroupMessage' -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 16.370s`; `ok github.com/mknoon/go-mknoon/internal 0.368s`; `ok github.com/mknoon/go-mknoon/crypto 0.545s`
- `(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -race -count=1)` -> passed: `ok github.com/mknoon/go-mknoon/node 13.338s`
- `git diff --check` -> passed with no output.

Done criteria: accepted for QA. Row-owned Go crypto, pure validator, and live two-node PubSub tests exist and pass; adjacent GK-010/GK-011/GK-012/GK-006/GK-007 selectors still pass; all required Go commands and diff hygiene pass. Source matrix and session-breakdown closure rows remain intentionally untouched per QA-only scope and are ready for a later closure writer.

Non-blocking follow-ups deferred: source matrix and breakdown closure evidence should be written by the closure step, not by this QA pass.

## Closure Note

- Closure status: accepted/closed.
- Closure evidence: source matrix GK-013 is `Covered`; breakdown GK-013 inventory, disposition, session ledger row 64, ordered session row 64, and session closure ledger record `covered/accepted`.
- Landed proof: `go-mknoon/node/pubsub.go` rejects missing or blank `encrypted.ciphertext` or `encrypted.nonce` as `invalid_envelope` before group mismatch, signature verification, or decrypt, and the pure validator helper in `go-mknoon/node/pubsub_test.go` mirrors the same encrypted-field helper. `go-mknoon/crypto/group.go::DecryptGroupMessage` returns diagnostic errors for missing ciphertext, missing nonce, empty decoded ciphertext, and wrong decoded nonce length instead of panicking.
- Tests: `go-mknoon/crypto/group_test.go::TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic`, `go-mknoon/node/pubsub_test.go::TestGK013ValidateGroupEnvelopeRejectsMissingEncryptedFieldsAsInvalidEnvelope`, and `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK013MissingEncryptedFieldsRejectedByValidatorAndEmitsNoPayloadEvent`.
- Validation: regression-first evidence recorded crypto missing ciphertext returning `aes-gcm decrypt`, crypto missing/short nonce panicking, node missing ciphertext returning `bad_signature`, and node missing nonce returning `accept`; executor and QA reruns passed the focused, adjacent, broader, race, and `git diff --check` commands recorded above.
- Accepted differences: missing encrypted fields close as `invalid_envelope` before signature/decrypt; real-network proof is Recommended-only; Flutter/Dart replay was not required because landed scope stayed in Go validator/decrypt paths.
- Residual-only: none for GK-013. GK-014 remains the next unresolved P0 row.

## real scope

Own exactly GK-013: v3 group envelopes that omit `encrypted.ciphertext` or `encrypted.nonce` must not produce `group_message:received` or `group_reaction:received`.

Implement the smallest Go-side fix if the regression-first tests expose the current gap:

- In `go-mknoon/node/pubsub.go`, reject missing/blank encrypted fields as `invalid_envelope` in the live `groupTopicValidator` before signature verification and before subscription decrypt.
- Mirror that validation in the pure test helper path in `go-mknoon/node/pubsub_test.go` by calling the same production helper where possible, so the helper does not drift from the live validator.
- In `go-mknoon/crypto/group.go`, make `DecryptGroupMessage` return explicit errors for missing ciphertext, missing nonce, empty decoded ciphertext, and wrong decoded nonce length instead of allowing AES-GCM to panic on a zero-length or short nonce.
- Add row-owned Go tests proving the pure validator, live two-node PubSub path, and decrypt helper behavior.

Do not change the group wire format, signature format, key epoch rules, member authorization rules, delivery retry logic, durable inbox behavior, Flutter UI, or source matrix/breakdown closure state during planning.

## closure bar

GK-013 is good enough when a missing `encrypted.ciphertext` or `encrypted.nonce` envelope is rejected with a diagnostic before payload emission, the subscription loop does not panic or blackhole on missing nonce, adjacent GK-010/GK-011/GK-012/GK-006/GK-007 behavior still passes, and the exact Go commands below pass.

Host-only Go proof is sufficient for this row unless implementation touches Dart replay code. The source row marks device-lab as `N/A` and real network as `Recommended`, not required; the row behavior is owned by the Go v3 envelope validator/decrypt path.

## source of truth

- Primary task contract: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-013.
- Active session disposition: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row 64.
- Current implementation truth: `go-mknoon/node/pubsub.go`, `go-mknoon/crypto/group.go`, `go-mknoon/internal/group_envelope.go`, and their current tests.
- Named-gate truth, if any named gate is invoked: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- On disagreement, current code and focused row-owned tests beat stale prose. Adjacent covered rows GK-010, GK-011, and GK-012 constrain this session.

## session classification

`accepted/closed`

This is implementation-committed closure. The repo now has explicit encrypted-field guards in `groupTopicValidator` and `DecryptGroupMessage`; row-owned Go tests prove missing encrypted fields reject as `invalid_envelope`, decrypt diagnostics return without panic, adjacent GK-006/GK-007/GK-011/GK-012 behavior still passes, and the source matrix plus breakdown now carry `Covered` / `covered/accepted` evidence.

## exact problem statement

GK-013 is closed. A malformed v3 group envelope that omits `encrypted.ciphertext` or `encrypted.nonce` now produces diagnostic rejection or decrypt-input failure behavior and never emits plaintext message or reaction events.

What improved:

- Missing ciphertext and missing nonce are row-owned by explicit tests.
- Missing nonce cannot reach AES-GCM as a zero-length nonce.
- The live validator path produces a `group:validation_rejected` diagnostic for these structurally malformed encrypted fields.

What must stay unchanged:

- GK-010 missing `groupId` remains parser-owned through `ParseGroupEnvelope`.
- GK-011 missing `senderId` remains validator-owned as `invalid_envelope`.
- GK-012 missing `signature` remains `bad_signature_or_epoch` / pure `reject:bad_signature`, not parser-level invalid envelope.
- GK-007 nonce tamper with a present but changed nonce remains accepted by signature validation and fails during decrypt with `group:decryption_failed`.

## files and repos to inspect next

Production:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/node/group.go` only to confirm no group config/key side effects are needed
- `lib/features/groups/application/group_offline_replay_envelope.dart` only if implementation touches Dart offline replay

Tests:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/crypto/group_test.go`
- `test/features/groups/application/group_offline_replay_envelope_test.dart` only if Dart replay changes

Gate docs:

- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `go-mknoon/internal/group_envelope_test.go::TestGK010ParseGroupEnvelopeRejectsMissingGroupID` proves only missing `groupId` is parser-owned today.
- `go-mknoon/node/pubsub_test.go::TestGK011ValidateGroupEnvelopeRejectsMissingSenderIDAsInvalidEnvelope` and `TestGK011GroupTopicValidatorRejectsMissingSenderIDAsInvalidEnvelopeNoPanic` prove missing sender is validator-owned and no-panic.
- `go-mknoon/node/pubsub_test.go::TestGK012ValidateGroupEnvelopeRejectsMissingSignatureAsBadSignature` plus `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK012MissingSignatureRejectedByValidatorAndEmitsNoMessage` prove missing signature stays bad-signature validation, not parser-owned.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` covers post-signing ciphertext mutation.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK007NonceByteTamperFailsDecryptAndEmitsNoMessage` covers present-but-tampered nonce and must remain a decrypt failure, not a structural missing-field rejection.
- `go-mknoon/crypto/group_test.go::TestDecryptGroupMessage_InvalidBase64` covers invalid base64, but not empty ciphertext, empty nonce, or wrong decoded nonce length.
- `lib/features/groups/application/group_offline_replay_envelope.dart` already throws `missing_ciphertext` and `missing_nonce` before Dart offline replay decrypt; the current test file exercises signature rejection generally but does not need to close the live Go PubSub row unless Dart code changes.

## regression/tests to add first

Add these tests before production changes and record the expected red result:

1. `go-mknoon/crypto/group_test.go::TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic`
   - Generate a valid group key.
   - Call `DecryptGroupMessage` with empty ciphertext plus a valid 12-byte nonce.
   - Call `DecryptGroupMessage` with valid-looking ciphertext plus empty nonce.
   - Call `DecryptGroupMessage` with valid-looking ciphertext plus a valid-base64 nonce that decodes to a non-12-byte value.
   - Wrap each case with a panic guard and assert a non-nil diagnostic error and empty plaintext.
   - Current expected failure: at least the empty/short nonce case can panic because AES-GCM panics on wrong nonce length.

2. `go-mknoon/node/pubsub_test.go::TestGK013ValidateGroupEnvelopeRejectsMissingEncryptedFieldsAsInvalidEnvelope`
   - Build a valid signed envelope.
   - Use structured JSON mutation to remove nested `encrypted.ciphertext` and then nested `encrypted.nonce` in separate subtests.
   - Assert the mutated JSON still satisfies `internal.IsGroupEnvelope` and parses with the missing nested field as an empty string.
   - Assert `validateGroupEnvelope(...) == "reject:invalid_envelope"` for both missing fields.
   - Assert GK-012 missing signature remains `reject:bad_signature` in its existing test.
   - Current expected failure: missing nonce likely returns `accept`; missing ciphertext may return `reject:bad_signature` instead of `reject:invalid_envelope`.

3. `go-mknoon/node/pubsub_decryption_failure_test.go::TestGK013MissingEncryptedFieldsRejectedByValidatorAndEmitsNoPayloadEvent`
   - Use the same two-node local PubSub pattern as GK-006/GK-012.
   - For missing ciphertext and missing nonce subtests, disable only node A's local validator before raw publish so node B's validator remains under test.
   - Publish the malformed envelope.
   - Wait for `group:validation_rejected` with reason `invalid_envelope`.
   - Assert no `group_message:received`, no `group_reaction:received`, no `group:decryption_failed`, and no plaintext marker after the baseline.
   - Include a panic guard around direct validator invocation where useful; the live publish assertion is the integration proof.

## step-by-step implementation plan

1. Add the three GK-013 tests above first. Run the focused regression commands and capture the expected failure mode.
2. In `go-mknoon/node/pubsub.go`, add a small unexported helper such as `groupEnvelopeHasEncryptedFields(env *internal.GroupEnvelope) bool` that returns false when `env` is nil or `strings.TrimSpace(env.Encrypted.Ciphertext)` or `strings.TrimSpace(env.Encrypted.Nonce)` is empty.
3. In `groupTopicValidator`, call that helper immediately after the existing missing `SenderId` check and before group mismatch, membership, key lookup, or signature verification. Reject with `invalid_envelope` and `logPubSubValidationReject("invalid_envelope", ...)`.
4. In `go-mknoon/node/pubsub_test.go`, update `validateGroupEnvelopeForTransportPeer` to use the same helper after the missing sender guard so pure tests match the live validator.
5. In `go-mknoon/crypto/group.go`, add decrypt input guards:
   - reject blank ciphertext as `missing ciphertext`;
   - reject blank nonce as `missing nonce`;
   - after base64 decode, reject zero-length ciphertext as `missing ciphertext`;
   - after GCM creation, reject decoded nonce length not equal to `gcm.NonceSize()` as `invalid nonce length: got X, want 12`;
   - keep existing invalid base64 and key length errors intact.
6. Re-run the focused GK-013 commands. If the new tests pass without a production change, stop and document tests-only closure instead of forcing code churn. Static evidence makes this unlikely.
7. Re-run adjacent GK-010/GK-011/GK-012/GK-006/GK-007 selectors and the broader row-relevant Go sweep.
8. Only if Dart replay code was edited, run the direct Flutter replay test and add/adjust a Dart missing-field test. Otherwise leave Dart unchanged.
9. After implementation and verification, update the source matrix row and session-breakdown row with row-owned evidence. This planning session must not perform those closure edits.

## risks and edge cases

- Empty string base64 decodes successfully; without explicit guards, a missing nonce can become a zero-length nonce and panic inside AES-GCM.
- Signature data covers `groupId|epoch|ciphertext`, not nonce. A missing nonce can retain a valid signature unless the validator has a structural encrypted-field guard.
- Missing ciphertext with an unchanged signature may already reject as bad signature, but a re-signed empty-ciphertext envelope still needs a safe decrypt diagnostic. The planned crypto guard covers that.
- The new structural guard must not convert GK-007 present-but-tampered nonce into `invalid_envelope`; it should only reject missing/blank encrypted fields.
- The guard must not change GK-012 missing-signature behavior.
- Two-node PubSub tests can be timing-sensitive; use existing collector helpers and baseline indexes from adjacent tests.

## exact tests and gates to run

Regression-first expected red:

```bash
(cd go-mknoon && go test ./crypto -run '^TestGK013DecryptGroupMessageRejectsMissingCiphertextOrNonceWithoutPanic$' -count=1)
(cd go-mknoon && go test ./node -run 'TestGK013' -count=1)
```

Focused proof after implementation:

```bash
(cd go-mknoon && go test ./crypto -run 'TestGK013|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt' -count=1)
(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -count=1)
```

Broader row-relevant sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK013|TestGK012|TestGK011|TestGK010|TestGK007|TestGK006|DecryptGroupMessage' -count=1)
(cd go-mknoon && go test ./node -run 'TestGK013|TestGK012|TestGK011|TestGK007|TestGK006' -race -count=1)
git diff --check
```

Conditional only if Dart replay code or tests are touched:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

No simulator, device-lab, relay, or real-network gate is required for closure. The row marks device-lab `N/A` and real network `Recommended`; the row-owned live integration proof is the local two-node Go PubSub test.

## known-failure interpretation

- A regression-first failure where missing nonce is accepted by the validator, times out waiting for validation rejection, emits a decrypt failure, or panics is the expected GK-013 gap.
- A regression-first failure where missing ciphertext rejects as `bad_signature` rather than `invalid_envelope` is also an expected GK-013 gap because the row asks for missing encrypted fields to be diagnosed structurally or during decrypt.
- Existing dirty worktree changes are not evidence of GK-013 closure unless the new row-owned tests pass in the current working tree.
- Failures in GK-011 or GK-012 after implementation are regressions, not known failures.
- Infrastructure failures in two-node PubSub setup should be checked by rerunning an adjacent known-passing selector such as GK-012 before changing the plan.

## done criteria

- Row-owned GK-013 tests exist in Go crypto, pure node validator, and live two-node PubSub validation/decryption path.
- Regression-first failure is recorded, or current coverage is proven by the new tests without production changes.
- Missing ciphertext and missing nonce both reject with `invalid_envelope` in the live validator path and emit no payload event.
- `DecryptGroupMessage` returns diagnostic errors for missing ciphertext, missing nonce, and wrong decoded nonce length without panic.
- GK-010, GK-011, GK-012, GK-006, and GK-007 selectors still pass.
- Required exact Go commands and `git diff --check` pass.
- Execution phase updates source matrix and breakdown closure evidence after code/tests land.

## scope guard

Do not:

- Add nonce, sender, type, or device fields to the group signature payload.
- Redesign `ParseGroupEnvelope` into a full schema validator.
- Change group envelope JSON field names or v3 wire compatibility.
- Change authorization, membership, key rotation grace, offline inbox, retry, or Flutter delivery behavior.
- Add simulator/device/relay proof unless new evidence shows the host Go path cannot prove the row.
- Edit source matrix or breakdown closure state during this planning task.

Overengineering for this row would include a new schema validation framework, a protocol migration, a signature-format migration, or broad Flutter replay refactors.

## accepted differences / intentionally out of scope

- Missing encrypted fields may close as `invalid_envelope` before signature/decrypt rather than as `bad_signature_or_epoch` or `group:decryption_failed`; this is within the source row's "before or during decrypt with diagnostic" expectation.
- Missing signature remains a bad-signature path. GK-013 must not reopen GK-012.
- Present but tampered nonce remains a decrypt-failure path. GK-013 must not reopen GK-007.
- Dart offline replay already has missing `ciphertext`/`nonce` signature checks; no Flutter gate is required unless that code changes.
- Real-network proof remains recommended-only and is deferred.

## dependency impact

Closing GK-013 removes a malformed-envelope validator/decrypt safety gap before later rows such as GK-014, GK-017, and GK-025 build on envelope validation behavior. If this plan changes to parser-level schema validation or signature-format migration, later GK rows must be reviewed for changed rejection reasons and compatibility assumptions.

## reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: no structural misses. The focused Go crypto/node tests and row-relevant Go sweep are enough for the row; Flutter replay and real-network gates are correctly conditional or deferred.

Stale or incorrect assumptions: none found. The plan correctly treats source row GK-013 and breakdown row 64 as active, while using current code and adjacent covered tests as the implementation truth.

Overengineering check: no structural overengineering. The crypto guard is justified by the current AES-GCM panic behavior for wrong nonce length; it is not a protocol redesign.

Decomposition check: sufficient. Tests are added first, the live validator and pure helper are kept aligned, and adjacent rows constrain rejection reasons.

Minimum needed to make the plan sufficient: no structural change. Incremental detail only: if implementation makes it trivial, include a pure-validator table case for the entire missing `encrypted` object as another way of producing missing ciphertext and nonce, but do not make that a closure requirement.

## arbiter pass

Final decision: execution-ready.

Structural blockers: none.

Incremental details: optional pure-validator coverage for a missing top-level `encrypted` object may be added if it falls out naturally from the helper/test table, but closure does not depend on it because GK-013 is specifically missing `ciphertext` or `nonce`.

Accepted differences:

- Host-only Go proof is accepted; simulator/device/relay proof remains out of scope for this row.
- `invalid_envelope` is an accepted live-validator diagnostic for missing encrypted fields.
- Missing signature stays on the GK-012 bad-signature path.
- Present-but-tampered nonce stays on the GK-007 decrypt-failure path.
- Dart offline replay changes and Flutter gates remain conditional only.

Stop rule: no structural blocker was found, so no second planning loop is required.
