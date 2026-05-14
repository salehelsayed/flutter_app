# GK-003 Implementation Plan

Status: accepted/closed

## Closure Note

Closure Writer status update: GK-003 is accepted/closed after source matrix and breakdown updates. Tests-only closure is based on `go-mknoon/crypto/group_test.go::TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext`; `go-mknoon/crypto/group.go` has no diff; integration evidence is Recommended, not Required.

## Execution Progress

- 2026-05-12T00:56:31Z - Executor started in user-requested Executor-only mode. Files inspected/touched: this plan, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`. Decision/blocker: contract extracted; scope is GK-003 only, with production `group.go` edits allowed only if the row-owned proof exposes a real nonce-generation defect. Next action: run pre-add selector and record gap evidence.
- 2026-05-12T00:56:31Z - Scoped dirty state confirmed. Files inspected/touched: this plan, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, source matrix, breakdown. Decision/blocker: `git status --short -- ...` shows `??` this plan, ` M go-mknoon/crypto/group_test.go`, clean `go-mknoon/crypto/group.go`, ` M` source matrix, and ` M` breakdown; preserve unowned GK-001/GK-002, matrix, and breakdown edits. Next action: run `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext' -count=1)`.
- 2026-05-12T00:56:50Z - Pre-add selector completed. Files inspected/touched: no code edits. Command: `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext' -count=1)`. Result: pass with expected gap evidence, `ok github.com/mknoon/go-mknoon/crypto 0.404s [no tests to run]`. Next action: add exact GK-003 regression to `go-mknoon/crypto/group_test.go`.
- 2026-05-12T00:57:27Z - GK-003 regression added and formatted. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command: `gofmt -w go-mknoon/crypto/group_test.go`. Result: command passed. Decision/blocker: production `go-mknoon/crypto/group.go` not changed. Next action: run focused GK-003 plus adjacent crypto command.
- 2026-05-12T00:57:50Z - Focused crypto command completed. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command: `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext|TestSP003GroupKeysAndNoncesUseFreshRandomness|TestGroupEncryptDecrypt_UniqueNonces|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey' -count=1)`. Result: pass, `ok github.com/mknoon/go-mknoon/crypto 0.466s`. Decision/blocker: exact GK-003 proof passes against current production, so no `go-mknoon/crypto/group.go` change is needed. Next action: run broader row-relevant Go sweep.
- 2026-05-12T00:58:20Z - Broader row-relevant Go sweep completed. Files inspected/touched: this plan. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK003|TestGK002|TestGK001|TestSP003|TestGroupEncryptDecrypt' -count=1)`. Result: pass, `ok github.com/mknoon/go-mknoon/node 4.411s`; `ok github.com/mknoon/go-mknoon/internal 0.863s`; `ok github.com/mknoon/go-mknoon/crypto 0.622s`. Next action: run `git diff --check`.
- 2026-05-12T00:59:00Z - Diff hygiene and final scoped status completed. Files inspected/touched: this plan. Command: `git diff --check`; scoped `git status --short -- ...`; `git diff -- go-mknoon/crypto/group.go`. Result: `git diff --check` passed with no output; scoped status still shows `??` this plan, ` M go-mknoon/crypto/group_test.go`, clean `go-mknoon/crypto/group.go`, and pre-existing ` M` source matrix/breakdown; `group.go` diff is empty. Next action: hand off to QA.

## Final Execution Verdict

Executor verdict: ready for QA.

Changed in this Executor pass:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-003-plan.md`: added execution progress, command evidence, and this verdict.
- `go-mknoon/crypto/group_test.go`: added `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext`.

Production changed: no. `go-mknoon/crypto/group.go` remains unchanged because the exact GK-003 proof passed against current nonce generation.

Exact tests/gates run:

- `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext' -count=1)` -> pass with expected pre-add gap, `ok github.com/mknoon/go-mknoon/crypto 0.404s [no tests to run]`.
- `gofmt -w go-mknoon/crypto/group_test.go` -> pass.
- `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext|TestSP003GroupKeysAndNoncesUseFreshRandomness|TestGroupEncryptDecrypt_UniqueNonces|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey' -count=1)` -> pass, `ok github.com/mknoon/go-mknoon/crypto 0.466s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK003|TestGK002|TestGK001|TestSP003|TestGroupEncryptDecrypt' -count=1)` -> pass, `ok github.com/mknoon/go-mknoon/node 4.411s`; `ok github.com/mknoon/go-mknoon/internal 0.863s`; `ok github.com/mknoon/go-mknoon/crypto 0.622s`.
- `git diff --check` -> pass with no output.

Residuals and QA handoff:

- Source matrix and breakdown were intentionally not edited in this Executor pass and remain modified from pre-existing work.
- GK-003 source-row closure was completed after QA by updating the source matrix and breakdown with accepted evidence.
- No Executor blockers remain.

## QA Result

QA Reviewer verdict: accepted.

Findings:

- `go-mknoon/crypto/group_test.go` contains `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` and meets the closure bar: one generated key, fixed plaintext payload, `samples = 128`, strict standard-base64 decode for ciphertext and nonce, non-empty ciphertext/nonce artifacts, non-empty decoded ciphertext, decoded nonce length exactly 12 bytes, no duplicate nonce strings, and no duplicate ciphertext strings.
- Existing adjacent coverage remains present: `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey`, `TestGK002EncryptDecryptRoundTripForTextPayload`, `TestSP003GroupKeysAndNoncesUseFreshRandomness`, and `TestGroupEncryptDecrypt_UniqueNonces`.
- `git diff -- go-mknoon/crypto/group.go` is empty; no GK-003 production diff was found.

QA command outcomes:

- `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext|TestSP003GroupKeysAndNoncesUseFreshRandomness|TestGroupEncryptDecrypt_UniqueNonces|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey' -count=1)` -> pass, `ok github.com/mknoon/go-mknoon/crypto 0.262s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK003|TestGK002|TestGK001|TestSP003|TestGroupEncryptDecrypt' -count=1)` -> pass, `ok github.com/mknoon/go-mknoon/node 4.287s`; `ok github.com/mknoon/go-mknoon/internal 0.455s`; `ok github.com/mknoon/go-mknoon/crypto 0.628s`.
- `git diff --check` -> pass with no output.

Blocking issues: none.

Residual-only note: source matrix and breakdown closure evidence remains outside this QA-only ownership scope.

## Planning Progress

- 2026-05-12T00:54:34Z - Arbiter completed. Files inspected since last update: reviewer notes and complete draft plan. Decision/blocker: no structural blockers remain; incremental details are documented and accepted differences are explicit. Next action: plan is execution-ready for a future executor.
- 2026-05-12T00:54:11Z - Reviewer completed; Arbiter started. Files inspected since last update: full draft plan heading inventory and draft plan body. Decision/blocker: reviewer found the plan sufficient as-is; no missing mandatory sections, tests, or gates, and no structural blocker. Next action: classify reviewer result through arbiter and finalize execution-ready status if no blocker remains.
- 2026-05-12T00:52:03Z - Planner completed; Reviewer started. Files inspected since last update: numbered snippets for the source matrix row, breakdown GK-003 rows, `go-mknoon/crypto/group.go`, and adjacent tests. Decision/blocker: drafted a regression-first implementation plan; no production change is planned unless the exact GK-003 proof fails against current code. Next action: run sufficiency review for missing files, stale assumptions, test gaps, and scope drift.
- 2026-05-12T00:51:35Z - Evidence Collector completed; Planner started. Files inspected since last update: source matrix GK-003 row, session breakdown GK-003 ledger and ordered row, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, `Test-Flight-Improv/test-gate-definitions.md`, and scoped git status. Decision/blocker: no planning blocker; current implementation appears to use a 12-byte `crypto/rand` AES-GCM nonce, but at planning time GK-003 lacked an exact row-owned proof and the source row was Open. Next action: draft a regression-first, implementation-ready plan that permits tests-only closure only after the exact GK-003 proof passes against current code.
- 2026-05-12T00:50:35Z - Evidence Collector started. Files inspected since last update: none beyond target plan existence check. Decision/blocker: source row GK-003 and required plan path confirmed by prompt; no blocker. Next action: inspect source matrix row, session breakdown, nearby group crypto implementation/tests, and relevant gate docs.

## real scope

Own exactly source row GK-003: `Encryption produces unique nonces/ciphertexts for same plaintext`.

In scope for the later executor:

- Add an exact row-owned Go crypto proof named `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` in `go-mknoon/crypto/group_test.go`.
- Prove that encrypting one fixed plaintext many times with one valid generated group key returns strict standard-base64 nonce/ciphertext artifacts, decoded nonce length is exactly 12 bytes, and the sample contains no duplicate nonce strings or ciphertext strings.
- Touch `go-mknoon/crypto/group.go` only if the exact GK-003 proof fails because nonce generation is not random, not 12 bytes, not GCM-compatible, or otherwise produces duplicates/non-base64 artifacts.
- Preserve landed GK-001 and GK-002 tests in `go-mknoon/crypto/group_test.go`.
- Require source-row closure with concrete file/test/gate evidence. This closure is now complete: `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-003 is `Covered`.

Out of scope for this plan artifact: editing production code, tests, source matrix, or breakdown during planning. The only file updated by this planning task is this plan file.

## closure bar

GK-003 is good enough when:

- `go-mknoon/crypto/group_test.go` contains the exact row-owned test `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext`.
- The test uses one valid generated key, one fixed plaintext payload, and a meaningful sample count of 128 encryptions unless repo evidence justifies changing that count.
- Every sample strict-decodes nonce and ciphertext with `base64.StdEncoding.Strict()`.
- Every decoded nonce is exactly 12 bytes.
- No duplicate nonce string and no duplicate ciphertext string occurs in the sample.
- Focused and broader row-relevant Go commands pass, formatting/hygiene passes, and `git diff --check` passes.
- If the exact proof passes against current code, the session may close as tests-only implementation-ready work with no production change. That is not evidence-only closure because the row-owned regression/proof was added and run.
- If the exact proof fails, production must be fixed narrowly at the nonce-generation seam before closure, and the same proof must pass after the fix.
- The closure writer updated the source row from `Open` to `Covered` with concrete evidence before acceptance.

## source of truth

- Active source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-003 is now `Covered`, P0, Unit Required, Integration Recommended, note: nonce reuse would be catastrophic.
- Active breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` now records GK-003 as `covered/accepted`; its original planning classification was `needs_code_and_tests` / `implementation-ready`.
- Current code beats stale prose. If code and docs disagree, trust `go-mknoon/crypto/group.go` and direct test results for behavior; closure docs now reflect the accepted GK-003 evidence.
- `scripts/run_test_gates.sh` is the execution source of truth for named Flutter gates if a named gate becomes relevant. For this crypto-only row-owned plan, direct Go commands are the required gates; no frozen named Flutter gate is required unless implementation expands into Dart or Flutter files.
- Worktree status matters: source matrix, breakdown, and `go-mknoon/crypto/group_test.go` already have modifications not made by this planner. The executor must preserve those edits and avoid reverting unrelated work.

## session classification

`implementation-ready`

The breakdown currently says `needs_code_and_tests`, but current code evidence suggests the implementation may already satisfy GK-003. The executor should add the exact row-owned regression/proof first. If that proof passes against current code, close as tests-only after RED/GREEN-style gap verification and concrete command evidence. If it fails, continue into the narrow production fix.

## exact problem statement

GK-003 was open because there was no exact row-owned proof that repeated encryption of the same plaintext under a valid group key produces fresh 12-byte nonces and unique ciphertexts across a meaningful sample. The added GK-003 proof now covers that risk. AES-GCM nonce reuse under the same key would compromise confidentiality and integrity, so the row keeps direct regression coverage even though adjacent tests already exercise similar behavior.

Current behavior must stay unchanged for valid callers: `EncryptGroupMessage` returns base64 ciphertext and nonce, and `DecryptGroupMessage` remains compatible with those artifacts. Existing GK-001, GK-002, `TestSP003GroupKeysAndNoncesUseFreshRandomness`, and `TestGroupEncryptDecrypt_UniqueNonces` coverage must continue to pass.

## files and repos to inspect next

- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if named gate classification becomes relevant
- `scripts/run_test_gates.sh` only if named Flutter gate execution becomes relevant

Conditional only if the exact proof shows a non-crypto serialization/envelope issue:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group.go`
- `go-mknoon/internal/group_envelope.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`

## existing tests covering this area

- `TestSP003GroupKeysAndNoncesUseFreshRandomness` in `go-mknoon/crypto/group_test.go` samples 64 generated keys and 64 encryptions of a stable plaintext, rejects duplicate nonce/ciphertext strings, and asserts decoded nonce length 12. It is adjacent but not an exact GK-003 row-owned proof, uses non-strict base64 decode, and also owns SP-003 key randomness scope.
- `TestGroupEncryptDecrypt_UniqueNonces` compares only two nonce strings for the same plaintext. It is useful adjacent coverage but too small for GK-003 closure and does not check ciphertext uniqueness or decoded nonce length.
- `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` proves generated group keys strict-decode to 32 bytes and are unique across 128 samples. Preserve it.
- `TestGK002EncryptDecryptRoundTripForTextPayload` proves valid-key encryption/decryption round trip, non-empty strict-base64 artifacts, and 12-byte nonce for one JSON/text payload. Preserve it; do not claim it covers GK-003 uniqueness.

## regression/tests to add first

Add `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` to `go-mknoon/crypto/group_test.go`.

The test should:

- Generate one valid key with `GenerateGroupKey`.
- Use a fixed plaintext payload, for example `{"type":"text","body":"GK-003 stable plaintext","meta":{"sample":true}}`.
- Set `const samples = 128`.
- Allocate `seenNonces := make(map[string]struct{}, samples)` and `seenCiphertexts := make(map[string]struct{}, samples)`.
- For each sample, call `EncryptGroupMessage(keyB64, payload)`.
- Assert ciphertext and nonce strings are non-empty.
- Strict-decode both artifacts with `base64.StdEncoding.Strict()`.
- Assert decoded ciphertext is non-empty.
- Assert decoded nonce length is exactly 12.
- Reject duplicate nonce strings with a failure message naming the sample number.
- Reject duplicate ciphertext strings with a failure message naming the sample number.

Do not require decrypting every sample for GK-003 closure. GK-002 owns exact encrypt/decrypt round-trip behavior. If the executor chooses to decrypt one representative sample while keeping the primary assertions focused on uniqueness, that is acceptable but not part of the closure bar.

Before adding the test, run the GK-003 selector to document the row-owned coverage gap. A "no tests to run" result before the test exists is expected gap evidence, not product correctness evidence.

## step-by-step implementation plan

1. Confirm scoped dirty state with `git status --short -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-003-plan.md go-mknoon/crypto/group.go go-mknoon/crypto/group_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`. Preserve existing unowned edits.
2. Run the pre-add GK-003 selector: `(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext' -count=1)`. Expected before implementation: no matching test, unless another worker has already added it.
3. If another worker already added an exact GK-003 test, inspect it instead of duplicating. If it satisfies the closure bar, run the exact tests/gates and proceed to closure evidence. If it is incomplete, update only the test as needed.
4. Add `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` to `go-mknoon/crypto/group_test.go`, near the existing group-key and encrypt/decrypt tests, without removing or weakening GK-001, GK-002, SP-003, or generic encrypt/decrypt tests.
5. Run `gofmt -w go-mknoon/crypto/group_test.go`.
6. Run the focused crypto command. If it passes, do not change production code.
7. If the focused command fails because the new GK-003 assertions expose nonce length, duplicate nonce, duplicate ciphertext, invalid base64, or missing randomness, inspect `go-mknoon/crypto/group.go::EncryptGroupMessage` and make the smallest production fix. The expected narrow fix, if needed, is confined to AES-GCM nonce allocation/fill/return behavior: generate a fresh nonce per call using `crypto/rand`, keep the nonce size at 12 bytes for standard GCM, and keep the existing base64 API.
8. If production Go code is edited, run `gofmt -w go-mknoon/crypto/group.go go-mknoon/crypto/group_test.go`, then rerun the focused crypto command.
9. Run the broader node/internal/crypto sweep.
10. Run conditional Dart/Flutter companion coverage only if the implementation touched `lib/features/groups/application/group_offline_replay_envelope.dart` or changed serialized envelope behavior. Otherwise, document that the Flutter companion was intentionally not run because GK-003 closed at the Go crypto primitive seam.
11. Run `git diff --check`.
12. During the closure-writing step owned by the rollout pipeline, update the source matrix row GK-003 and breakdown ledger with the exact test name, changed files, command evidence, and whether no production code changed. This has been completed for GK-003; no final program verdict was written because GK-004 and later rows remain open.

## risks and edge cases

- AES-GCM nonce reuse under the same key is catastrophic; any duplicate nonce or ciphertext in the 128-sample test must be treated as a real blocker unless proven to be test corruption.
- A true random collision over 128 samples with 96-bit nonces is effectively impossible for this regression; a duplicate should trigger investigation of nonce generation or test setup.
- Strict base64 decoding prevents accidentally accepting malformed artifacts that non-strict decoding might tolerate.
- Large sample counts can make tests slower without meaningfully improving confidence. Keep the sample count at 128 unless there is concrete evidence to change it.
- Do not introduce deterministic or injectable nonce behavior in production for this row.
- Dirty worktree changes in matrix, breakdown, and `go-mknoon/crypto/group_test.go` may belong to other workers. Preserve them and coordinate by inspecting before editing.

## exact tests and gates to run

Pre-add gap selector:

```bash
(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext' -count=1)
```

Formatting after adding only the test:

```bash
gofmt -w go-mknoon/crypto/group_test.go
```

Formatting if production Go code is also edited:

```bash
gofmt -w go-mknoon/crypto/group.go go-mknoon/crypto/group_test.go
```

Focused GK-003 plus adjacent crypto coverage:

```bash
(cd go-mknoon && go test ./crypto -run 'TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext|TestSP003GroupKeysAndNoncesUseFreshRandomness|TestGroupEncryptDecrypt_UniqueNonces|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey' -count=1)
```

Broader row-relevant Go sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK003|TestGK002|TestGK001|TestSP003|TestGroupEncryptDecrypt' -count=1)
```

Conditional companion only if Dart envelope behavior changes:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

Diff hygiene:

```bash
git diff --check
```

No frozen named Flutter gate is required for a crypto-only GK-003 test addition. If the implementation expands into Flutter group behavior, stop and re-scope before running broader gates.

## known-failure interpretation

- Before adding the GK-003 test, a selector result with no matching tests is expected coverage-gap evidence.
- After adding the GK-003 test, "no tests to run" is a failure of implementation because the exact test is missing or misnamed.
- Any GK-003 duplicate nonce, duplicate ciphertext, invalid strict base64 artifact, empty ciphertext, or decoded nonce length other than 12 is a P0 blocker for this row.
- Failures in pre-existing dirty files are not automatically caused by this session. Re-run the exact command after the GK-003 edit; only classify failures as GK-003 regressions when they are in the touched test, the `EncryptGroupMessage` seam, or the row-relevant command surface.
- If the broader node/internal/crypto sweep fails in a test unrelated to the regex or touched files, record the failure with command output and current git status, then decide whether it is pre-existing. Do not mark GK-003 covered without a passing focused crypto proof.

## done criteria

- This plan file says `Status: accepted/closed`.
- The later executor adds or verifies `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` in `go-mknoon/crypto/group_test.go`.
- The exact GK-003 test enforces strict base64 decode, 12-byte nonce length, and no duplicate nonce/ciphertext across 128 same-plaintext encryptions.
- Focused crypto command, broader row-relevant Go sweep, required formatting command, and `git diff --check` pass.
- Production code remains unchanged if the exact proof passes against current `EncryptGroupMessage`.
- If production code changes, the change is confined to nonce generation/encoding behavior and the same commands pass after the fix.
- Closure updated the source matrix GK-003 row from `Open` to `Covered` with concrete file/test/command evidence before GK-003 was accepted.

## scope guard

- Do not change AES mode, key size, ciphertext format, nonce base64 API, decrypt API, group signature data, key rotation, PubSub delivery, relay inbox behavior, or Flutter offline replay behavior unless the exact GK-003 proof proves the crypto primitive is wrong and the fix requires it.
- Do not edit source matrix, breakdown, production code, or tests during this planning-only task.
- Do not remove or weaken GK-001, GK-002, SP-003, or generic encrypt/decrypt tests.
- Do not expand this row into GK-004 invalid-base64 handling, GK-005 wrong key length, GK-006 tamper behavior, or later group envelope rows.
- Do not add deterministic nonce test hooks or randomness abstractions for this row.
- Do not use a huge sample count that turns the direct crypto test into a slow or flaky suite.

## accepted differences / intentionally out of scope

- GK-003 can close without Flutter or simulator evidence because Integration is Recommended, not Required, and the invariant is owned by the Go crypto primitive.
- Decrypting every sample is intentionally out of scope. GK-002 already owns exact round-trip behavior; GK-003 owns uniqueness and 12-byte nonce proof for repeated same-plaintext encryption.
- Existing SP-003 and generic nonce tests remain valuable adjacent coverage but are not accepted as GK-003 closure because the source row requires exact row-owned evidence.
- No bridge, node, internal, Flutter, relay, or simulator behavior should change if current `EncryptGroupMessage` passes the exact proof.

## dependency impact

- At planning time GK-003 was the next unresolved P0 after GK-002 in the breakdown. GK-003 now has row-owned evidence and source-row coverage, so GK-004 is the next unresolved P0.
- GK-004/GK-005/GK-006 and later envelope/decryption rows depend on the encryption primitive remaining stable, so this plan avoids broad API or serialization changes.
- If GK-003 exposes a production nonce bug, pause later GK closure and fix this primitive first because downstream confidentiality and decrypt/auth failure tests depend on fresh nonces.
- If GK-003 closes tests-only, later work can proceed without revisiting nonce generation unless a real regression lands.

## reviewer notes

Sufficiency verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none. The plan names the exact source row, breakdown, production seam, row-owned Go test, focused crypto command, broader node/internal/crypto sweep, conditional Dart companion, formatting commands, and `git diff --check`.
- Stale or incorrect assumptions: none found. The plan correctly treats current code and direct test results as stronger than stale docs, and treated source-row `Open` as preventing acceptance until closure docs were updated.
- Overengineering: none found. The plan avoids nonce abstractions, deterministic hooks, broad crypto redesign, Flutter scope, and simulator scope unless the proof fails in a way that requires more investigation.
- Decomposition: sufficient. The implementation starts with the exact GK-003 proof, stops without production changes if it passes, and only then permits a narrow nonce-generation fix if the proof fails.
- Minimum needed to make sufficient: no required adjustment.

## arbiter notes

Structural blockers: none.

Incremental details:

- The executor may choose whether to decrypt one representative sample, but this remains outside the GK-003 closure bar because GK-002 owns round-trip correctness.
- The Dart offline replay companion remains conditional. It should not be promoted to required evidence unless implementation actually changes Dart envelope behavior.
- Source matrix and breakdown closure were intentionally deferred during planning and were completed by the later closure-writing step.

Accepted differences:

- Although the breakdown says `needs_code_and_tests`, the plan permits a tests-only close if the exact row-owned proof passes against current code. This is accepted because current `EncryptGroupMessage` already appears to allocate and fill a fresh 12-byte nonce with `crypto/rand`; the missing artifact is the GK-003-named proof and closure evidence.
- Integration evidence is Recommended, not Required. A direct Go crypto proof is sufficient for the row-owned primitive invariant unless code changes expand beyond that seam.

## final planning verdict

Final planning verdict: execution-ready. Final closure verdict: accepted/closed.

Final plan: add or verify `go-mknoon/crypto/group_test.go::TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` first. The test must encrypt one fixed plaintext 128 times with one valid generated key, strict-decode ciphertext and nonce artifacts, require 12-byte decoded nonces, and reject duplicate nonce or ciphertext strings. If that proof passes, do not change production code. If it fails, make the smallest `go-mknoon/crypto/group.go::EncryptGroupMessage` nonce-generation fix and rerun the exact commands.

Structural blockers remaining: none.

Incremental details intentionally deferred: optional representative decrypt and conditional Dart companion only if Dart envelope behavior changes. Source-matrix/breakdown closure evidence has now been completed.

Accepted differences intentionally left unchanged: no simulator or Flutter named gate for crypto-only closure; no broad crypto/API redesign; no acceptance occurred before the source row was moved to `Covered`.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-003
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GK-003 row inventory, session ledger, and ordered-session row
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`
- scoped `git status --short` for the relevant docs and crypto files

Why the plan was safe to implement: the source row and breakdown agreed that GK-003 was unresolved and implementation-ready at planning time; current code evidence pointed to the correct primitive seam; the plan added the missing exact proof before any production change; production edits were allowed only if the proof failed; and closure required concrete command evidence plus a source-row update from `Open` to `Covered`, which has now been completed.
