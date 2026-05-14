# GK-005 Wrong Key Length Rejection Plan

Status: accepted/closed

## Planning Progress

- 2026-05-12 04:00:49 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: tests-only plan is sufficient if execution confirms current `go-mknoon/crypto/group.go` guards remain present; no blocker. Next action: run reviewer sufficiency pass.
- 2026-05-12 04:00:49 CEST - Reviewer started. Files inspected since last update: none. Decision/blocker: review the draft for missing closure bar, regression-first rule, gates, and scope guard. Next action: classify findings before arbiter.
- 2026-05-12 04:02:58 CEST - Reviewer completed. Files inspected since last update: full draft plan, mandatory section list, exact GK-005 contract, test/gate contract. Decision/blocker: plan is sufficient as-is; no missing files, tests, gates, stale assumptions, overengineering, or decomposition blockers found. Next action: run arbiter stop-rule classification.
- 2026-05-12 04:02:58 CEST - Arbiter started. Files inspected since last update: reviewer finding summary and draft plan. Decision/blocker: classify findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution-ready status if no structural blockers exist.
- 2026-05-12 04:03:29 CEST - Arbiter completed. Files inspected since last update: reviewer pass and final plan sections. Decision/blocker: no structural blockers remain; no patch loop required. Next action: plan is execution-ready for GK-005 only.

## Execution Progress

- 2026-05-12 04:05:15 CEST - Executor started. Files inspected/touched: `git status --short`, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, this plan. Decision/blocker: contract extracted; unrelated dirty worktree changes observed and left untouched; production guards already reject decoded non-32-byte keys. Next action: add row-owned GK-005 regression in `go-mknoon/crypto/group_test.go`.
- 2026-05-12 04:05:15 CEST - Executor edit. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Decision/blocker: adding `TestGK005WrongKeyLengthIsRejected` near GK-004 and the existing wrong-length test; no production edit planned unless required tests fail. Next action: run gofmt and required Go selectors.
- 2026-05-12 04:06:26 CEST - Executor validation. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command/result: `(cd go-mknoon && gofmt -w crypto/group_test.go)` exited 0 with no output. Next action: run focused crypto selector.
- 2026-05-12 04:06:26 CEST - Executor validation. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command/result: `(cd go-mknoon && go test ./crypto -run '^(TestGK005WrongKeyLengthIsRejected|TestEncryptGroupMessage_WrongKeyLength|TestGK004InvalidKeyBase64IsRejected|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt_WrongKey)$' -count=1)` passed with `ok github.com/mknoon/go-mknoon/crypto 0.370s`. Next action: run broader row-relevant Go selector.
- 2026-05-12 04:06:26 CEST - Executor validation. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command/result: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK005|TestGK004|TestGK003|TestGK002|TestGK001|TestGenerateGroupKey|TestGroupEncryptDecrypt|WrongKey|WrongKeyLength|InvalidBase64|InvalidKey' -count=1)` passed with `ok github.com/mknoon/go-mknoon/node 4.802s`, `ok github.com/mknoon/go-mknoon/internal 0.439s`, and `ok github.com/mknoon/go-mknoon/crypto 0.212s`. Next action: run diff whitespace check.
- 2026-05-12 04:06:26 CEST - Executor validation. Files inspected/touched: `go-mknoon/crypto/group_test.go`, this plan. Command/result: `git diff --check` exited 0 with no output. Decision/blocker: all required executor commands passed; no production code change needed. Next action: write final execution verdict.

## real scope

Own exactly source row GK-005: "Wrong key length is rejected." The implementation target is the decoded group-key length guard used by `EncryptGroupMessage` and `DecryptGroupMessage` in `go-mknoon/crypto/group.go`, with the likely code change limited to `go-mknoon/crypto/group_test.go`.

The row-owned proof must show that a base64 string which decodes successfully but is not 32 bytes is rejected by both encrypt and decrypt paths with a clear `invalid group key length` error. Encrypt must return empty ciphertext and nonce on failure, and decrypt must return empty plaintext on failure.

Do not touch Flutter, bridge, node delivery, internal envelope, offline replay, membership, or key-rotation behavior for this row unless execution disproves the current crypto guard evidence. Preserve existing GK-001 through GK-004 tests, the existing `TestEncryptGroupMessage_WrongKeyLength` test, and all unrelated dirty worktree changes.

## closure bar

GK-005 is good enough when a row-owned Go test proves both crypto entry points reject a decoded non-32-byte key with `invalid group key length` and empty failure outputs, the focused and broader Go selectors pass, and `git diff --check` passes.

Because this is implementation-committed gap-closure mode, GK-005 cannot be accepted while the source matrix row has unresolved status. After execution and QA, the closure writer must update the source matrix GK-005 row and the breakdown GK-005 session/closure evidence with concrete command output and file/test evidence. This closure prerequisite has since been satisfied for GK-005, and no final program verdict should be written for the overall rollout.

## source of truth

- Current code and tests are authoritative if they conflict with older prose.
- The active row contract is source matrix row GK-005 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- The active gap-closure and session contract is breakdown row GK-005 plus the run-mode snapshot in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- `go-mknoon/crypto/group.go` is the production behavior owner for group-key decode and length checks.
- `go-mknoon/crypto/group_test.go` is the direct regression-test owner for GK-005.
- `Test-Flight-Improv/test-gate-definitions.md` is not needed for this plan because no named Flutter or repository gate semantics are used; exact local Go commands are sufficient.

## session classification

implementation-ready.

This is implementation-committed gap-closure work, not docs-only, evidence-only, acceptance-only, or stale/already-covered. Current evidence suggests tests-only closure, but execution must still add the missing GK-005 row-owned proof and close the source row with concrete evidence.

## exact problem statement

At planning time, GK-005 was still `Open` in the source matrix. Production appeared to reject decoded keys whose length is not 32 bytes in both `EncryptGroupMessage` and `DecryptGroupMessage`, but the existing tests did not close the row:

- `TestEncryptGroupMessage_WrongKeyLength` only checks that encrypting with a 16-byte decoded key returns a non-nil error.
- There is no row-owned `GK-005` test name.
- Decrypt is not covered for wrong decoded key length.
- The clear `invalid group key length` error text and empty failure outputs are not asserted.

The required improvement is a durable regression proving clear key-length rejection at the crypto boundary. Existing valid-key, invalid-base64, round-trip, nonce uniqueness, wrong-key, tamper, and GK-001 through GK-004 behavior must stay unchanged.

## files and repos to inspect next

- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `git status --short` before editing, to avoid overwriting unrelated dirty changes.

No Flutter files should be inspected or changed unless a direct execution finding proves GK-005 cannot close at the crypto layer.

## existing tests covering this area

- `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` proves generated group keys decode to exactly 32 bytes and are unique across samples.
- `TestGK002EncryptDecryptRoundTripForTextPayload` proves valid-key text payload encrypt/decrypt round trip.
- `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` proves valid-key repeated encryption emits fresh nonce/ciphertext artifacts.
- `TestGK004InvalidKeyBase64IsRejected` proves malformed key base64 is rejected by encrypt and decrypt with `decode group key` and empty failure outputs.
- `TestEncryptGroupMessage_WrongKeyLength` proves only that encrypt fails for a 16-byte decoded key, without row ID, decrypt coverage, specific error assertion, or output assertions.
- `TestGroupEncryptDecrypt_WrongKey` proves decrypt fails when ciphertext was encrypted with a different valid 32-byte key; this is not a key-length proof.
- `TestDecryptGroupMessage_InvalidBase64` covers malformed ciphertext, nonce, and key base64 paths; it does not cover decoded key length.

## regression/tests to add first

Add `TestGK005WrongKeyLengthIsRejected` in `go-mknoon/crypto/group_test.go` before any production change. Use a single base64-encoded 16-byte key as the smallest sufficient row-owned proof: it decodes successfully, is not 32 bytes, and exercises the exact `len(key) != 32` guard. Do not add a long-key case unless execution finds a separate long-key path or reviewer evidence proves the guard is asymmetric.

The test should:

- Build `wrongLengthKeyB64 := base64.StdEncoding.EncodeToString(make([]byte, 16))`.
- Call `EncryptGroupMessage(wrongLengthKeyB64, "GK-005 plaintext")`.
- Assert encrypt returns a non-nil error containing `invalid group key length`, preferably including `got 16, want 32`.
- Assert encrypt returns `ctB64 == ""` and `nonceB64 == ""`.
- Build valid-looking base64 ciphertext and 12-byte nonce placeholders so decrypt cannot fail because of malformed ciphertext or nonce input.
- Call `DecryptGroupMessage(wrongLengthKeyB64, validLookingCiphertextB64, validLookingNonceB64)`.
- Assert decrypt returns a non-nil error containing `invalid group key length`, preferably including `got 16, want 32`.
- Assert decrypt returns empty plaintext.

This regression is intentionally row-owned and should coexist with the older `TestEncryptGroupMessage_WrongKeyLength` test instead of deleting or weakening it.

## step-by-step implementation plan

1. Reconfirm `go-mknoon/crypto/group.go` still rejects decoded keys with `len(key) != 32` before AES setup in both encrypt and decrypt.
2. Reconfirm `go-mknoon/crypto/group_test.go` still contains GK-001 through GK-004 tests and the existing `TestEncryptGroupMessage_WrongKeyLength`; preserve them.
3. Add `TestGK005WrongKeyLengthIsRejected` to `go-mknoon/crypto/group_test.go`, near GK-004 and the existing wrong-length test.
4. Run `gofmt` on `go-mknoon/crypto/group_test.go` if the file is changed.
5. Run the focused crypto selector. If it passes, do not change production code.
6. If and only if the focused test proves one of the production guards is absent or not returning the required empty outputs/error, make the smallest possible fix in `go-mknoon/crypto/group.go` to restore the decoded key-length check before AES/ciphertext/nonce processing, then rerun the focused selector.
7. Run the broader Go selector that includes node/internal/crypto group behavior plus GK-001 through GK-004 and wrong-key/wrong-length coverage.
8. Run `git diff --check`.
9. After executor and QA evidence is complete, have the closure writer update only the GK-005 source matrix row and GK-005 breakdown closure/session entries with concrete test evidence. Do not write a final program verdict.

## risks and edge cases

- Decrypt proof can be accidentally weakened if ciphertext or nonce inputs are malformed; use valid-looking base64 placeholders so the wrong key length fails first.
- The existing production guard returns before ciphertext and nonce decode. The test should pin that behavior without adding a wider decrypt-envelope contract.
- Error text becomes part of the row closure evidence. Require `invalid group key length` and avoid accepting a generic AES error.
- The worktree already has unrelated dirty changes, including group docs/tests from earlier rows. The executor must not revert or rewrite unrelated changes.
- A long decoded key is the same guard class as a short decoded key in current code. Adding both would broaden the row proof without adding meaningful coverage unless evidence shows divergent behavior.

## exact tests and gates to run

Run these commands from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`:

1. If `go-mknoon/crypto/group_test.go` is edited:

   ```sh
   (cd go-mknoon && gofmt -w crypto/group_test.go)
   ```

2. Focused crypto selector:

   ```sh
   (cd go-mknoon && go test ./crypto -run '^(TestGK005WrongKeyLengthIsRejected|TestEncryptGroupMessage_WrongKeyLength|TestGK004InvalidKeyBase64IsRejected|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt_WrongKey)$' -count=1)
   ```

3. Broader row-relevant Go selector preserving GK-001 through GK-004 and wrong-key behavior:

   ```sh
   (cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK005|TestGK004|TestGK003|TestGK002|TestGK001|TestGenerateGroupKey|TestGroupEncryptDecrypt|WrongKey|WrongKeyLength|InvalidBase64|InvalidKey' -count=1)
   ```

4. Diff whitespace check:

   ```sh
   git diff --check
   ```

Do not require Flutter tests for this session unless a Flutter file is changed because of a newly discovered, direct GK-005 production touch.

## known-failure interpretation

Any failure in `TestGK005WrongKeyLengthIsRejected` is row-owned and must be fixed before closure. Any failure in GK-001 through GK-004, `WrongKey`, `WrongKeyLength`, `InvalidBase64`, or `InvalidKey` selectors is a regression unless current baseline evidence proves it pre-existing and unrelated.

If the broader selector fails in node/internal tests outside the regex-owned crypto/key paths because of unrelated dirty worktree changes, record the exact failing package/test and rerun the focused crypto selector to separate row-owned status from pre-existing red. Do not mark GK-005 covered while the row-owned focused selector fails.

## done criteria

- `go-mknoon/crypto/group_test.go` contains `TestGK005WrongKeyLengthIsRejected`.
- The new test proves encrypt and decrypt both reject a base64-decoded 16-byte key with `invalid group key length` and empty failure outputs.
- Existing GK-001 through GK-004 tests and existing wrong-key/wrong-length tests remain present.
- Production code is unchanged unless the new regression proves the current guard is missing or incorrect.
- The focused crypto selector, broader Go selector, and `git diff --check` pass or have clearly separated non-row pre-existing failures.
- After execution and QA, the closure writer updates source matrix GK-005 and breakdown GK-005 with concrete evidence and leaves the overall program verdict unset.

## scope guard

Non-goals for GK-005:

- Do not implement ciphertext tamper, nonce tamper, signature, delivery, replay, or decryption-failure event behavior; those belong to later GK rows.
- Do not modify Flutter offline replay, group listeners, Go node pubsub, internal envelope, bridge code, membership, or key rotation unless crypto evidence makes that unavoidable for this exact row.
- Do not replace AES-GCM, change generated key format, change nonce length, or redesign group-key handling.
- Do not remove, rename, or weaken GK-001 through GK-004 tests or existing legacy crypto tests.
- Do not update source matrix or breakdown closure rows during planning; closure updates belong after execution and QA evidence.

## accepted differences / intentionally out of scope

- Integration evidence is `Recommended`, not `Required`, for GK-005; the direct crypto unit proof is the closure path unless execution finds production behavior outside crypto.
- The plan uses one short decoded key as the minimal non-32-byte representative. A long-key case is intentionally out of scope unless later evidence shows it exercises a different branch.
- Node/internal/Flutter files listed in the generic breakdown row are not implementation targets for this exact row because current evidence localizes the invariant to `go-mknoon/crypto/group.go`.

## dependency impact

Closing GK-005 unblocks continuation to GK-006 in the breakdown's ordered P0 flow. GK-006 and later tamper/decryption-failure rows should not be started from this plan and should not inherit GK-005 closure unless the source row and breakdown are updated with concrete GK-005 execution plus QA evidence.

If execution finds production crypto behavior missing or changes the error contract, rerun adjacent GK-001 through GK-004 selectors and preserve their source-row closure evidence before allowing GK-005 closure.

## reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none. The plan names the source matrix, breakdown, production crypto file, crypto test file, focused crypto selector, broader node/internal/crypto selector, `gofmt` command, and `git diff --check`.

Stale or incorrect assumptions: none found. Current production code evidence shows both encrypt and decrypt already reject decoded non-32-byte keys; the plan still includes a stop condition if execution disproves that.

Overengineering: none found. The plan intentionally uses one short decoded key as the smallest representative and avoids node, internal, Flutter, and long-key expansion unless evidence requires it.

Decomposition: sufficient. The row-owned proof is isolated to one test and one optional production guard fallback.

Minimum needed to make sufficient: no structural changes required.

## arbiter decision

Structural blockers: none.

Incremental details intentionally deferred: none required for execution safety. A long decoded-key case remains optional only if execution evidence reveals a distinct branch.

Accepted differences intentionally left unchanged: integration/Flutter proof is not required for this direct crypto invariant; node/internal/Flutter files listed by the generic breakdown row are not implementation targets unless new evidence contradicts the current crypto-local behavior.

Execution-ready verdict: ready to implement GK-005 only.

## Final Execution Verdict

Verdict: accepted.

Files changed by this GK-005 executor pass:

- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-005-plan.md`

Tests added or updated:

- Added `TestGK005WrongKeyLengthIsRejected`.

Evidence:

- `TestGK005WrongKeyLengthIsRejected` uses a base64-encoded 16-byte key, asserts `EncryptGroupMessage` returns a non-nil `invalid group key length` error containing `got 16, want 32`, and asserts empty ciphertext and nonce.
- `TestGK005WrongKeyLengthIsRejected` uses valid-looking base64 ciphertext and 12-byte nonce placeholders, asserts `DecryptGroupMessage` returns a non-nil `invalid group key length` error containing `got 16, want 32`, and asserts empty plaintext.
- Existing GK-001 through GK-004 tests and `TestEncryptGroupMessage_WrongKeyLength` remain present.
- `go-mknoon/crypto/group.go` was inspected but not changed because existing production guards satisfied the new regression.

Required commands/results:

- `(cd go-mknoon && gofmt -w crypto/group_test.go)` - passed, no output.
- `(cd go-mknoon && go test ./crypto -run '^(TestGK005WrongKeyLengthIsRejected|TestEncryptGroupMessage_WrongKeyLength|TestGK004InvalidKeyBase64IsRejected|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt_WrongKey)$' -count=1)` - passed: `ok github.com/mknoon/go-mknoon/crypto 0.370s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK005|TestGK004|TestGK003|TestGK002|TestGK001|TestGenerateGroupKey|TestGroupEncryptDecrypt|WrongKey|WrongKeyLength|InvalidBase64|InvalidKey' -count=1)` - passed: `ok github.com/mknoon/go-mknoon/node 4.802s`; `ok github.com/mknoon/go-mknoon/internal 0.439s`; `ok github.com/mknoon/go-mknoon/crypto 0.212s`.
- `git diff --check` - passed, no output.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none by this executor pass. Source matrix and breakdown closure-row updates are intentionally left for the closure phase after QA, per scope.

## QA Result

Verdict: accepted.

QA Reviewer scope:

- Inspected the final execution verdict above and confirmed it is `accepted`.
- Inspected `go-mknoon/crypto/group_test.go::TestGK005WrongKeyLengthIsRejected`.
- Confirmed the test uses a base64-encoded 16-byte decoded key, asserts both encrypt and decrypt reject with `invalid group key length` and `got 16, want 32`, asserts empty ciphertext and nonce for encrypt, asserts empty plaintext for decrypt, and uses valid-looking base64 ciphertext plus a 12-byte nonce placeholder for decrypt.
- Confirmed existing GK-001 through GK-004 tests and `TestEncryptGroupMessage_WrongKeyLength` remain present.
- Confirmed `git diff -- go-mknoon/crypto/group.go` has no output; there is no production diff in `go-mknoon/crypto/group.go`.
- Left source matrix and breakdown rows untouched because they are intentionally closure-phase handoff items and do not block execution QA when code/test evidence passes.

Required QA command results:

- `(cd go-mknoon && go test ./crypto -run '^(TestGK005WrongKeyLengthIsRejected|TestEncryptGroupMessage_WrongKeyLength|TestGK004InvalidKeyBase64IsRejected|TestDecryptGroupMessage_InvalidBase64|TestGroupEncryptDecrypt_WrongKey)$' -count=1)` - passed: `ok github.com/mknoon/go-mknoon/crypto 0.263s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK005|TestGK004|TestGK003|TestGK002|TestGK001|TestGenerateGroupKey|TestGroupEncryptDecrypt|WrongKey|WrongKeyLength|InvalidBase64|InvalidKey' -count=1)` - passed: `ok github.com/mknoon/go-mknoon/node 4.456s`; `ok github.com/mknoon/go-mknoon/internal 0.637s`; `ok github.com/mknoon/go-mknoon/crypto 0.216s`.
- `git diff --check` - passed, no output.

Blocking issues: none.

Non-blocking follow-ups: none for execution QA.
