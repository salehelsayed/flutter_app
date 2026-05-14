# GK-006 Ciphertext Tamper Plan

Status: accepted/closed

## Planning Progress

- 2026-05-12 04:29:49 CEST - Planner completed. Files inspected since last update: complete draft sections and exact test/gate contract. Decision/blocker: plan is implementation-ready with likely tests-only code change; production changes are fallback-only if the new regression fails. Next action: run strict reviewer pass.
- 2026-05-12 04:32:12 CEST - Reviewer started. Files inspected since last update: full draft plan, mandatory section checklist, source row Required host/integration evidence, no-closure-before-QA rule. Decision/blocker: review for missing closure bar, stale assumptions, overbroad Flutter/device requirements, and weak RED proof. Next action: classify sufficiency.
- 2026-05-12 04:32:12 CEST - Reviewer completed. Files inspected since last update: full draft plan and evidence notes. Decision/blocker: sufficient as-is; no structural blockers. The plan supplies required unit evidence through pure validator assertion and required integration evidence through two-node Go PubSub validator proof, and correctly keeps Flutter offline replay out of scope unless touched. Next action: run arbiter stop-rule classification.
- 2026-05-12 04:32:39 CEST - Arbiter started. Files inspected since last update: reviewer pass, closure bar, scope guard, exact tests/gates, accepted differences. Decision/blocker: classify reviewer findings and decide whether a patch loop is required. Next action: finalize or patch once if structural blockers exist.
- 2026-05-12 04:32:39 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; no patch loop required. Next action: plan is execution-ready for GK-006 only.

## Execution Progress

- 2026-05-12 04:36:26 CEST - Executor started. Files inspected since last update: plan contract, dirty worktree, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/crypto/group.go`, `go-mknoon/internal/group_envelope.go`, libp2p repo map. Decision/blocker: scope is tests-only unless the new GK-006 regression proves a production defect; preserve unrelated dirty files. Next action: add the row-named Go regression near existing tamper tests.
- 2026-05-12 04:38:15 CEST - Executor implementation pass. Files touched since last update: `go-mknoon/node/pubsub_decryption_failure_test.go`. Command finished: `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)`. Decision/blocker: added `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` with pure validator rejection and two-node PubSub validator proof; no production file edits. Next action: run focused GK-006 and adjacent tamper selector.
- 2026-05-12 04:39:08 CEST - Executor validation. Command finished: `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce)$' -count=1)`. Result: pass, `ok github.com/mknoon/go-mknoon/node 3.644s`. Decision/blocker: focused row and adjacent tamper tests pass. Next action: run focused race proof.
- 2026-05-12 04:41:19 CEST - Local recovery worker started. Files inspected since last update: plan contract, dirty worktree, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/node_test.go`. Decision/blocker: nested Executor/QA spawning is unavailable in this isolated invocation; proceed with local sequential fallback. Existing target-file diff already contains the exact GK-006 test shape, so preserve it and run the required commands plus self-review. Next action: run `gofmt` and required Go selectors.
- 2026-05-12 04:41:53 CEST - Local executor validation. Files touched since last update: `go-mknoon/node/pubsub_decryption_failure_test.go` by gofmt only, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-006-plan.md`. Commands finished: `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)` and `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce)$' -count=1)`. Result: pass, `ok github.com/mknoon/go-mknoon/node 3.552s`. Decision/blocker: focused row and adjacent tamper tests pass in this recovery pass. Next action: run focused race proof.
- 2026-05-12 04:42:35 CEST - Local executor validation. Commands finished: `(cd go-mknoon && go test -race ./node -run '^TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage$' -count=1)` and `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TamperedCiphertext|TamperedNonce|TestGK006|TestGroupEncryptDecrypt_TamperedCiphertext|TestGroupEncryptDecrypt_TamperedNonce' -count=1)`. Results: pass, `ok github.com/mknoon/go-mknoon/node 3.587s` for race; broader sweep passed with `ok github.com/mknoon/go-mknoon/node 5.552s`, `ok github.com/mknoon/go-mknoon/internal 0.334s`, `ok github.com/mknoon/go-mknoon/crypto 0.206s`. Decision/blocker: all required Go gates passed. Next action: run `git diff --check` and self-QA review.
- 2026-05-12 04:43:12 CEST - Local QA completed. Files inspected since last update: target test diff, numbered GK-006 test body, plan progress. Command finished: `git diff --check`. Result: pass, no output. Decision/blocker: no blocking QA findings; the test mutates exactly one decoded ciphertext byte after signing without re-signing, asserts pure validator `reject:bad_signature`, unregisters only node A's local validator, waits for node B `group:validation_rejected` reason `bad_signature_or_epoch`, and asserts no received/reaction/decryption-failed events after baseline. Next action: write final execution verdict.
- 2026-05-12 04:44:02 CEST - Final verdict written. Files touched since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-006-plan.md`. Decision/blocker: `accepted_candidate`; no production changes required. Next action: none for this isolated GK-006 worker.

## QA Reviewer Pass

- 2026-05-12 04:47:28 CEST - Independent QA reviewer pass. Files inspected: GK-006 plan, `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/crypto/group.go`. Result: passed; no blocking findings. Confirmed `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` mutates exactly one decoded ciphertext byte after signing via `mutateGroupEnvelope`, does not re-sign, asserts pure `reject:bad_signature`, unregisters only node A's local validator so node B's real validator emits `group:validation_rejected` reason `bad_signature_or_epoch`, and asserts no `group_message:received`, `group_reaction:received`, or `group:decryption_failed` after baseline. Reruns: `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce)$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 3.694s`; `(cd go-mknoon && go test -race ./node -run '^TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage$' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 3.675s`; `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TamperedCiphertext|TamperedNonce|TestGK006|TestGroupEncryptDecrypt_TamperedCiphertext|TestGroupEncryptDecrypt_TamperedNonce' -count=1)` passed, `ok github.com/mknoon/go-mknoon/node 5.279s`, `ok github.com/mknoon/go-mknoon/internal 0.841s`, `ok github.com/mknoon/go-mknoon/crypto 0.606s`; `git diff --check` passed with no output.

## Evidence Collector Notes

- Source matrix row `GK-006` is `P0` and still `Open`: "Ciphertext tamper fails decrypt and emits no message." Preconditions are "Valid envelope then one ciphertext byte changed"; steps are deliver tampered envelope, validator/decrypt, inspect events; expected result is "Signature or AES-GCM fails; no `group_message:received` event." Unit and Integration are `Required`; Fake Network is `Recommended`; 3-Party E2E is `N/A`.
- Neighboring rows show the intended split: `GK-007` owns nonce tamper and expects AES-GCM `group:decryption_failed`; `GK-009` owns deterministic signature data; `GK-012` and `GK-013` own missing signature/encrypted-field malformed envelope behavior. GK-006 must not absorb those rows.
- Breakdown row 57 classifies `GK-006` as `needs_code_and_tests` / `implementation-ready`, points at this plan path, and lists `go-mknoon/node/pubsub.go`, `go-mknoon/node/group.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/crypto/group.go`, and offline replay as candidate seams. The row says the missing proof is an exact GK-006 regression.
- Accepted GK-001..GK-005 style is exact row-owned Go evidence with focused selectors, broader Go selectors, QA reruns, `git diff --check`, no source/breakdown closure until execution and QA evidence, and no broad Flutter/device proof when the row is Go-local or direct crypto-local.
- `go-mknoon/crypto/group.go` uses AES-256-GCM; ciphertext includes the GCM auth tag, decrypt returns `aes-gcm decrypt` on auth failure, and `BuildGroupSignatureData` signs exactly `groupId|epoch|ciphertext`.
- `go-mknoon/node/pubsub.go` signs `BuildGroupSignatureData(groupId, keyEpoch, ctB64)` during publish, verifies `env.Encrypted.Ciphertext` in `verifyGroupEnvelopeSignature`, rejects invalid signatures in `groupTopicValidator` with `group:validation_rejected` reason `bad_signature_or_epoch`, and only decrypts inside `handleGroupSubscription` after validator acceptance.
- Therefore, in the current architecture, changing one ciphertext byte after signing must be rejected by signature validation before decrypt. The GK-006 expected branch is validator rejection, not AES-GCM failure.
- Existing `go-mknoon/crypto/group_test.go::TestGroupEncryptDecrypt_TamperedCiphertext` proves the direct AES-GCM baseline for a tampered ciphertext string, but it does not deliver a signed group envelope through node validation.
- Existing `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext` flips a ciphertext byte and then re-signs the mutated envelope. That intentionally bypasses signature rejection and proves the adjacent AES-GCM/decryption-failed path, but it is not GK-006's "valid envelope then one ciphertext byte changed" prerequisite.
- Existing `TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce` mutates without re-signing because nonce is not signed; that is GK-007-adjacent and should remain unchanged.
- `go-mknoon/node/group_security_harness_test.go` already provides `mutateGroupEnvelope`, `mutateAndResignGroupEnvelope`, `publishRawGroupEnvelope`, and event helpers. `pubsub_delivery_test.go` provides `waitForCollectedValidationReject`, and `node_test.go` provides `testEventCollector`.
- `test/features/groups/application/group_offline_replay_envelope_test.dart` covers a separate Dart offline replay envelope (`kind`, `signedPayload`, signature validation, `ciphertextHash`, `nonceHash`, and `plaintextHash`) and does not exercise the Go v3 PubSub `group_message:received` event path. It is not required for GK-006 unless implementation touches offline replay.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define the Flutter `groups` gate for Dart group send/receive/retry/resume/invite/announcement tests. The exact GK-006 proof should be Go host/integration evidence first; the Flutter gate is fallback-only if Dart/Flutter group code changes.

## real scope

Own exactly source row GK-006: ciphertext tamper fails validation/decrypt and emits no message.

In scope:

- Add or verify one exact row-owned Go node regression for "valid signed group envelope, then one ciphertext byte changed without re-signing."
- Exercise both the pure validator seam and the real two-node PubSub validator path so the row has required unit and integration evidence.
- Assert current architecture rejects at signature validation with `bad_signature_or_epoch` / `reject:bad_signature`, emits no `group_message:received`, and emits no `group:decryption_failed` for this exact post-signing ciphertext mutation.
- Preserve the existing re-signed tampered-ciphertext AES-GCM test as adjacent coverage.

Out of scope:

- Do not change source matrix or breakdown closure rows during planning or implementation. Closure rows update only after execution plus QA evidence.
- Do not implement nonce tamper, missing signature, malformed encrypted fields, signature determinism, sender-public-key tamper, offline replay, membership, key rotation, or Flutter UI behavior.
- Do not change signature data format unless the new RED proves the current code does not reject post-signing ciphertext mutation.

## closure bar

GK-006 is good enough when the repo has row-owned Go evidence that:

- A valid v3 group message envelope is signed over its original ciphertext.
- One decoded ciphertext byte is flipped and re-encoded after signing, without updating the signature.
- The pure validator rejects the mutated envelope as `reject:bad_signature`.
- The real receiver validator emits `group:validation_rejected` with reason `bad_signature_or_epoch` for the tampered envelope.
- No `group_message:received`, `group_reaction:received`, or `group:decryption_failed` event is emitted for that tampered delivery.
- Focused and broader Go selectors pass, plus `git diff --check`.

Because the source row and breakdown are implementation-committed, GK-006 cannot be accepted while the row remains `Open`. A later closure writer must update only GK-006 source matrix and breakdown entries after execution and QA evidence. Do not use `accepted_with_explicit_follow_up` for unresolved row-owned gaps.

## source of truth

- Current code and tests win over stale docs.
- Source row GK-006 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is the row contract.
- Breakdown row/session GK-006 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is the session contract.
- `go-mknoon/node/pubsub.go` is authoritative for publish, validator, decrypt, and event behavior.
- `go-mknoon/crypto/group.go` is authoritative for AES-GCM and signature-data construction.
- `go-mknoon/internal/group_envelope.go` is authoritative for the v3 envelope shape.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are authoritative only for named gate membership; exact Go commands are the primary GK-006 gates unless Flutter/Dart files change.

## session classification

implementation-ready.

This is repo-owned gap closure. Current evidence suggests a tests-only implementation, but not evidence-only or docs-only: the source row lacks exact row-owned proof and must receive a concrete regression before closure.

## exact problem statement

GK-006 is open because no exact row-owned test proves that a valid signed group envelope becomes non-renderable when its ciphertext is changed after signing. The risk is a regression where tampered encrypted content reaches the receive path and emits `group_message:received`, or where validation/decrypt diagnostics become ambiguous enough that source-row closure overclaims the architecture.

Current code appears to reject this tamper at signature validation because the signed data includes ciphertext. Existing tests cover nearby behavior but not the exact prerequisite: direct crypto AES-GCM tamper, nonce tamper, wrong-key decrypt, and a re-signed tampered-ciphertext node delivery. User-visible behavior must remain that no plaintext message is emitted for tampered ciphertext.

## files and repos to inspect next

Before editing:

- `git status --short`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/internal/group_envelope.go`

Fallback-only if tests fail in a way that proves a production defect:

- `go-mknoon/node/group.go`
- `go-mknoon/crypto/group_test.go`
- `go-mknoon/internal/group_envelope_test.go`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`

## existing tests covering this area

- `go-mknoon/crypto/group_test.go::TestGroupEncryptDecrypt_TamperedCiphertext` proves AES-GCM rejects a tampered ciphertext string in direct crypto.
- `go-mknoon/crypto/group_test.go::TestGroupEncryptDecrypt_TamperedNonce` proves AES-GCM rejects nonce tamper in direct crypto.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEvent` proves a wrong local key emits `group:decryption_failed` and no `group_message:received`.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce` proves nonce tamper reaches decrypt and emits `group:decryption_failed`; that belongs to GK-007 because nonce is not signed.
- `go-mknoon/node/pubsub_decryption_failure_test.go::TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext` proves AES-GCM failure for a ciphertext changed and re-signed after mutation; it is adjacent coverage and should not be removed.
- `go-mknoon/node/pubsub_test.go::validateGroupEnvelope` and validator tests cover pure signature and membership behavior, but there is no row-named `GK-006` exact test.
- `go-mknoon/internal/group_envelope_test.go` covers parsing and envelope shape, not post-signing ciphertext tamper policy.
- `test/features/groups/application/group_offline_replay_envelope_test.dart` covers Dart replay-envelope signature rejection before decrypt, not Go PubSub `group_message:received`.

Missing:

- No exact `GK-006` / `TestGK006...` test that mutates ciphertext after signing without re-signing, proves signature rejection, and proves no receive/decrypt event escapes.

## regression/tests to add first

Add `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` in `go-mknoon/node/pubsub_decryption_failure_test.go` before any production change.

The test should:

- Generate sender signing keys and a real group key.
- Start local node A and node B, preferably using `startLocalNodeForMultiRelayTestWithCollector` for node B so validation events are captured from startup.
- Join both nodes to the same group with the same `GroupConfig` and `GroupKeyInfo`.
- Build a valid signed v3 message envelope with `buildTestEnvelope`.
- Mutate the existing envelope with `mutateGroupEnvelope`, decode `env.Encrypted.Ciphertext`, flip one byte, re-encode it, and do not call `mutateAndResignGroupEnvelope`.
- Assert `validateGroupEnvelope(tamperedEnvelope, groupId, config, keyInfo)` returns `reject:bad_signature`.
- Connect nodes, unregister only node A's local validator if necessary so node A can publish malformed raw data while node B's validator remains active, then publish via `publishRawGroupEnvelope`.
- Capture baseline node B events before publish and wait for `group:validation_rejected` reason `bad_signature_or_epoch` at the expected key epoch.
- Inspect events after the baseline and fail if any contain `group_message:received`, `group_reaction:received`, or `group:decryption_failed`.

This is RED/regression proof because current closure lacks an exact GK-006 test. If it passes immediately against current production code, stop without production edits.

## step-by-step implementation plan

1. Reconfirm the dirty worktree and do not overwrite unrelated edits.
2. Reopen `go-mknoon/node/pubsub_decryption_failure_test.go`, `go-mknoon/node/group_security_harness_test.go`, and `go-mknoon/node/pubsub_delivery_test.go` to reuse existing helpers instead of inventing a harness.
3. Add `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` near the existing tampered nonce/ciphertext tests.
4. Use `mutateGroupEnvelope` rather than `mutateAndResignGroupEnvelope`. This is the key GK-006 distinction.
5. Add pure validator assertion first. If it returns anything other than `reject:bad_signature`, inspect `verifyGroupEnvelopeSignature` and `BuildGroupSignatureData` before changing production.
6. Add real two-node PubSub delivery proof. If node A's local validator blocks raw publish before node B can validate, unregister node A's topic validator only; keep node B's validator registered and captured.
7. Assert no `group_message:received`, no `group_reaction:received`, and no `group:decryption_failed` after the baseline. In current architecture, `group:decryption_failed` would mean the tampered ciphertext bypassed signature validation, which is not GK-006's expected branch.
8. Run `gofmt` on changed Go test files.
9. Run the focused Go selector. If it passes, do not edit production.
10. If the new test fails because ciphertext is not signed, make the smallest production fix in `go-mknoon/crypto/group.go` / `go-mknoon/node/pubsub.go` so signature data covers ciphertext consistently at publish and verify, then rerun focused and broader Go tests.
11. Run the broader Go selector and `git diff --check`.
12. After execution and QA evidence, closure writer updates only GK-006 source matrix and GK-006 breakdown entries with concrete test results; do not write an overall final program verdict while later rows remain open.

## risks and edge cases

- Accidentally re-signing the mutated ciphertext would convert GK-006 into the existing AES-GCM proof and leave the row gap open.
- If node A's local validator rejects the raw tampered publish, node B may never emit the required validation event. Unregister only node A's validator for the publish leg, preserving node B as the validator under test.
- A bounded quiet-window assertion is needed after validation rejection so a late receive/decrypt event cannot slip through unobserved.
- Validation diagnostics are rate-limited by reason/group/sender/transport key. Use a unique group ID per test and record the event baseline before publish.
- Do not infer Flutter offline replay closure from the Go test. It is a separate envelope format and should stay out of GK-006 unless touched.

## exact tests and gates to run

Run from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

If `go-mknoon/node/pubsub_decryption_failure_test.go` is edited:

```sh
(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)
```

Focused row-owned Go proof:

```sh
(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce)$' -count=1)
```

Focused race proof for the new validator/subscription path:

```sh
(cd go-mknoon && go test -race ./node -run '^TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage$' -count=1)
```

Broader row-relevant Go sweep:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TamperedCiphertext|TamperedNonce|TestGK006|TestGroupEncryptDecrypt_TamperedCiphertext|TestGroupEncryptDecrypt_TamperedNonce' -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Do not run Flutter offline replay or `./scripts/run_test_gates.sh groups` for the expected Go-test-only implementation. Run Flutter/group gates only if execution changes Dart/Flutter group files, bridge contracts used by Flutter, or `lib/features/groups/application/group_offline_replay_envelope.dart`.

## known-failure interpretation

- Any failure in `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage` is row-owned and blocks closure.
- If the pure validator assertion fails, treat it as a likely signature-data regression and fix before accepting.
- If the real PubSub leg fails to observe `group:validation_rejected`, first check whether node A's local validator blocked raw fanout; do not weaken the expected node B validator rejection.
- Any `group_message:received`, `group_reaction:received`, or `group:decryption_failed` after baseline for the tampered post-signing ciphertext is a GK-006 blocker.
- Existing failures in unrelated dirty-worktree Flutter tests do not block GK-006 if the required Go selectors and diff check pass and no Flutter files were changed.
- Broader Go selector failures outside group envelope/signature/decryption selectors must be separated from this row before closure; do not mark GK-006 covered while the focused row proof fails.

## done criteria

- `go-mknoon/node/pubsub_decryption_failure_test.go` contains the exact row-named GK-006 regression.
- The regression mutates one ciphertext byte after signing without re-signing.
- Pure validator proof rejects the tampered envelope as bad signature.
- Real two-node PubSub proof emits `group:validation_rejected` reason `bad_signature_or_epoch`.
- No receive, reaction, or decryption-failed event is emitted for the tampered delivery.
- Existing tampered nonce and re-signed tampered ciphertext tests remain intact.
- Focused Go, focused race, broader Go, and `git diff --check` pass or have clearly separated non-row pre-existing failures.
- Source matrix and breakdown are updated only after execution plus QA evidence, not during this plan or initial implementation.

## scope guard

Non-goals:

- Do not close or edit GK-007, GK-008, GK-009, GK-012, GK-013, GK-025, GK-028, GK-029, or offline replay rows.
- Do not redesign the signature scheme, envelope schema, event names, encryption mode, key epoch policy, membership validation, or Flutter replay format.
- Do not replace current helper APIs with a new harness.
- Do not turn this into a property/fuzzer row; `GE-018` owns broad random envelope tampering.
- Do not update source matrix or breakdown closure rows until executor and QA evidence exists.

## accepted differences / intentionally out of scope

- GK-006 uses signature rejection rather than AES-GCM failure because current signature data covers ciphertext. The AES-GCM tampered-ciphertext branch remains covered by the existing re-signed test and direct crypto test, but it is not the expected branch for "one ciphertext byte changed after signing."
- Flutter offline replay is intentionally out of scope because it uses a Dart replay envelope with signed hashes and does not emit the Go `group_message:received` event named by GK-006.
- Device/3-party E2E is intentionally out of scope because the source row marks 3-Party E2E `N/A` and a two-node Go PubSub host test supplies the required integration evidence for the repo-owned receive path.

## dependency impact

Closing GK-006 unblocks GK-007 in the ordered P0 flow. GK-007 should still independently prove nonce tamper reaches AES-GCM and emits `group:decryption_failed`, because nonce is not covered by current signature data.

If GK-006 execution reveals ciphertext is not consistently signed, GK-009 signature-data determinism and related malformed-envelope rows may need fresh review after the narrow fix, but they must not be absorbed into GK-006 closure.

## reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none. The plan names the source matrix row, breakdown row, Go publish/signature/validator/decrypt production seams, helper files, existing adjacent tests, the row-named RED/regression test, focused normal and race Go commands, broader Go sweep, and `git diff --check`.

Stale or incorrect assumptions: none found. Current code evidence shows ciphertext is in the signed data, so post-signing ciphertext mutation should be validator-rejected before decrypt. The plan still includes a production-fix fallback if execution disproves that evidence.

Overengineering: none found. The plan uses one exact row-owned test with existing helpers. It avoids Flutter, simulator, property fuzzing, and unrelated malformed-envelope rows.

Decomposition: sufficient. The work is scoped to GK-006 only and explicitly preserves GK-007 nonce tamper, GK-009 signature determinism, and offline replay rows.

Minimum needed to make sufficient: no structural change required. Implementation can proceed by adding the row-named Go test first.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred: none required for execution safety. If implementation discovers node A raw publish cannot fan out even after unregistering only node A's validator, the executor may use the existing helper pattern from adjacent validator tests or direct node B validator invocation, but must still preserve the real PubSub validator proof if feasible.

Accepted differences intentionally left unchanged:

- The row closes through signature rejection because ciphertext is signed in the current architecture; AES-GCM failure for re-signed ciphertext remains adjacent evidence, not the GK-006 expected branch.
- Flutter offline replay is not required for this row because the required event contract is Go PubSub `group_message:received` and the two-node Go host test supplies integration evidence.
- 3-party device proof remains out of scope because the source row marks it `N/A`.

Execution-ready verdict: ready to implement GK-006 only.

## Final Execution Verdict

accepted/closed

Evidence:

- `go-mknoon/node/pubsub_decryption_failure_test.go` now contains `TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage`.
- The GK-006 regression builds a valid signed v3 group envelope, mutates exactly one decoded ciphertext byte with `mutateGroupEnvelope`, and does not re-sign.
- Pure validator proof rejects the tampered envelope as `reject:bad_signature`.
- Two-node PubSub proof leaves node B's validator active, unregisters only node A's local validator for raw publish fanout, and observes `group:validation_rejected` reason `bad_signature_or_epoch` for epoch 6.
- The post-baseline assertions fail on any `group_message:received`, `group_reaction:received`, or `group:decryption_failed` event.
- Existing re-signed tampered-ciphertext and tampered-nonce tests remain intact.

Required command results:

- `(cd go-mknoon && gofmt -w node/pubsub_decryption_failure_test.go)` passed with no output.
- `(cd go-mknoon && go test ./node -run '^(TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce)$' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 3.552s`.
- `(cd go-mknoon && go test -race ./node -run '^TestGK006TamperedCiphertextAfterSigningRejectedByValidatorAndEmitsNoMessage$' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 3.587s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|DecryptionFailed|TamperedCiphertext|TamperedNonce|TestGK006|TestGroupEncryptDecrypt_TamperedCiphertext|TestGroupEncryptDecrypt_TamperedNonce' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 5.552s`; `ok github.com/mknoon/go-mknoon/internal 0.334s`; `ok github.com/mknoon/go-mknoon/crypto 0.206s`.
- `git diff --check` passed with no output.

QA findings:

- No blocking findings.
- The implementation is tests-only; no production files were changed for GK-006.
- Source matrix and session breakdown were intentionally left untouched for later closure.

## Closure Note

2026-05-12 04:52 CEST - Closure Writer accepted/closed GK-006. The source matrix row and breakdown GK-006 entries now record `Covered`/accepted tests-only closure; production already signs ciphertext and rejects post-signing ciphertext mutation at signature validation. Residual-only: none. GK-007 nonce/AES-GCM branch remains open; no final program verdict was written.
