# GK-004 Invalid Key Base64 Plan

Status: accepted/closed

Closure note: GK-004 is accepted as tests-only. `go-mknoon/crypto/group_test.go::TestGK004InvalidKeyBase64IsRejected` provides the row-owned malformed-key proof, executor and QA focused/broader commands passed, `git diff --check` passed, and `go-mknoon/crypto/group.go` has no production diff.

## Planning Progress

- 2026-05-12 03:23:44 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: drafted tests-only implementation plan for exact GK-004 row ownership; no blocker. Next action: run reviewer sufficiency pass against scope, regression contract, gates, closure bar, and stop rule.
- 2026-05-12 03:25:20 CEST - Reviewer started. Files inspected since last update: drafted GK-004 plan artifact. Decision/blocker: no blocker. Next action: answer sufficiency questions and identify any missing files, tests, gates, stale assumptions, overengineering, or decomposition gaps.
- 2026-05-12 03:25:34 CEST - Reviewer completed. Files inspected since last update: drafted GK-004 plan artifact. Decision/blocker: sufficient as-is; no structural blocker found. Next action: run Arbiter classification and finalize execution-ready status if no structural blocker appears.
- 2026-05-12 03:26:03 CEST - Arbiter started. Files inspected since last update: reviewer-pass GK-004 plan artifact. Decision/blocker: no blocker. Next action: classify reviewer outcome into structural blockers, incremental details, and accepted differences.
- 2026-05-12 03:26:21 CEST - Arbiter completed. Files inspected since last update: reviewer-pass GK-004 plan artifact. Decision/blocker: no structural blockers; plan is execution-ready. Next action: execute only through the listed GK-004 tests-only path unless the exact proof exposes a production gap.

## Execution Progress

- 2026-05-12 03:28:00 CEST - Executor contract extracted/started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-004-plan.md`, `go-mknoon/crypto/group_test.go`, `go-mknoon/crypto/group.go`, scoped `git status`. Decision/blocker: exact scope is GK-004 test-only proof in `go-mknoon/crypto/group_test.go`; `go-mknoon/crypto/group.go` may change only if exact proof exposes a malformed-key production defect; source matrix and breakdown are out of scope for this execution pass; no blocker. Scoped dirty state: `??` GK-004 plan, `M` `go-mknoon/crypto/group_test.go`, clean `go-mknoon/crypto/group.go`, `M` source matrix, `M` session breakdown. Next action: run pre-add discovery selector.
- 2026-05-12 03:28:32 CEST - Pre-add discovery completed. Files inspected or touched since last update: none. Command: `(cd go-mknoon && go test ./crypto -list '^TestGK004InvalidKeyBase64IsRejected$')`. Result: pass, no `TestGK004InvalidKeyBase64IsRejected` listed; output `ok github.com/mknoon/go-mknoon/crypto 0.385s`. Decision/blocker: expected missing row-owned test confirmed; no blocker. Next action: add the GK-004 regression in `go-mknoon/crypto/group_test.go`.
- 2026-05-12 03:29:13 CEST - GK-004 test added and focused proof completed. Files inspected or touched since last update: `go-mknoon/crypto/group_test.go`. Commands: `(cd go-mknoon && gofmt -w crypto/group_test.go)` then `(cd go-mknoon && go test ./crypto -run '^(TestGK004InvalidKeyBase64IsRejected|TestEncryptGroupMessage_InvalidKey|TestDecryptGroupMessage_InvalidBase64|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext)$' -count=1)`. Result: gofmt completed with exit 0; focused proof passed with output `ok github.com/mknoon/go-mknoon/crypto 0.353s`. Decision/blocker: production change not needed; no blocker. Next action: run broader node/internal/crypto row-relevant sweep.
- 2026-05-12 03:29:55 CEST - Broader sweep and whitespace gate completed. Files inspected or touched since last update: `go-mknoon/crypto/group_test.go`, GK-004 plan. Commands: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK004|TestGK003|TestGK002|TestGK001|InvalidBase64|InvalidKey' -count=1)` then `git diff --check`. Result: broader sweep passed with output `ok github.com/mknoon/go-mknoon/node 4.819s`, `ok github.com/mknoon/go-mknoon/internal 0.293s`, `ok github.com/mknoon/go-mknoon/crypto 0.459s`; `git diff --check` passed with exit 0 and no output. Decision/blocker: no blocker. Next action: write final Executor verdict and hand off to QA.

## final execution verdict

Executor verdict: implemented; ready for QA.

Changed files in this Executor pass:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-004-plan.md`: recorded execution progress, command evidence, and this verdict.
- `go-mknoon/crypto/group_test.go`: added exactly one row-owned `TestGK004InvalidKeyBase64IsRejected`.

Production changed: no. `go-mknoon/crypto/group.go` remained untouched because the focused GK-004 proof passed against existing decode-first behavior.

Source matrix and breakdown changed by this Executor pass: no. They were already dirty on entry and remain out of scope for this execution pass.

Exact tests and gates run:

- `(cd go-mknoon && go test ./crypto -list '^TestGK004InvalidKeyBase64IsRejected$')` passed; no matching GK-004 test was listed before the add; output `ok github.com/mknoon/go-mknoon/crypto 0.385s`.
- `(cd go-mknoon && gofmt -w crypto/group_test.go)` completed with exit 0.
- `(cd go-mknoon && go test ./crypto -run '^(TestGK004InvalidKeyBase64IsRejected|TestEncryptGroupMessage_InvalidKey|TestDecryptGroupMessage_InvalidBase64|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext)$' -count=1)` passed with output `ok github.com/mknoon/go-mknoon/crypto 0.353s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK004|TestGK003|TestGK002|TestGK001|InvalidBase64|InvalidKey' -count=1)` passed with output `ok github.com/mknoon/go-mknoon/node 4.819s`, `ok github.com/mknoon/go-mknoon/internal 0.293s`, `ok github.com/mknoon/go-mknoon/crypto 0.459s`.
- `git diff --check` passed with exit 0 and no output.

Residuals and QA handoff:

- No Executor blocker remains for GK-004.
- QA should verify scope adherence, the new row-owned test assertions, unchanged production code, and the required command evidence.
- Later closure still needs to update the source matrix and breakdown with concrete GK-004 evidence; this Executor pass intentionally did not edit them.

## QA Result

2026-05-12 03:33:30 CEST - QA Reviewer verdict: blocked.

Findings:

- `go-mknoon/crypto/group_test.go` contains exactly one `TestGK004InvalidKeyBase64IsRejected`. The test uses malformed key base64, asserts encrypt returns a non-nil error containing `decode group key`, asserts empty ciphertext and nonce, then decrypts with the same malformed key and valid-looking base64 ciphertext/nonce placeholders, asserts a non-nil `decode group key` error, and asserts empty plaintext. Normal test completion provides the direct no-panic proof.
- Existing GK-001, GK-002, and GK-003 row-owned tests are still present and were included in the focused QA proof.
- `git diff -- go-mknoon/crypto/group.go` is empty, so there is no GK-004 production diff.
- Historical initial-QA blocker: at the time of this QA pass, the plan closure bar and done criteria said GK-004 could not be accepted while the source row had status `Open`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` had not yet been updated, and the session breakdown had not yet moved GK-004 from `implementation-ready`. This QA pass was explicitly limited to editing this plan file only. The later closure writer moved GK-004 to `Covered`/accepted with concrete evidence, superseding this closure-doc blocker.

Exact QA command outcomes:

- `(cd go-mknoon && go test ./crypto -run '^(TestGK004InvalidKeyBase64IsRejected|TestEncryptGroupMessage_InvalidKey|TestDecryptGroupMessage_InvalidBase64|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext)$' -count=1)` passed: `ok github.com/mknoon/go-mknoon/crypto 0.301s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK004|TestGK003|TestGK002|TestGK001|InvalidBase64|InvalidKey' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 4.425s`; `ok github.com/mknoon/go-mknoon/internal 0.170s`; `ok github.com/mknoon/go-mknoon/crypto 0.631s`.
- `git diff --check` passed with exit 0 and no output.

Residual-only notes: no code/test residual remains for the row-owned GK-004 regression. Next retry focus is the closure-only source matrix and breakdown update with the passing evidence above.

## QA Fix-Pass Note

2026-05-12 03:36:22 CEST - Executor fix-pass inspected the QA result and execution evidence. Blocker signature: `GK-004 qa_blocking_issue / closure-docs-not-yet-updated / source matrix + breakdown`. Classification: closure-phase handoff, not execution blocker. No code/test change required; the QA evidence already records the row-owned GK-004 test passing, adjacent GK-001/GK-002/GK-003 preservation, and no `go-mknoon/crypto/group.go` diff. At this execution-fix-pass point, the source matrix and session breakdown were intentionally out of execution QA scope and were assigned to the closure writer after QA acceptance.

## evidence inventory

- Source matrix row at planning time: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-004 was `Open`, P0, Required host evidence, Recommended integration evidence, and pointed at `group.go:27-34 and 66-73`; closure later updated the row to `Covered` with exact file/test/gate evidence.
- Breakdown row at planning time: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` classified GK-004 as `needs_tests_only` / `implementation-ready`, expected plan path `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-004-plan.md`, implementation scope `tests only`; closure later updated the GK-004 ledger rows to `covered/accepted`.
- Current code: `go-mknoon/crypto/group.go::EncryptGroupMessage` decodes `groupKeyB64` before any AES/GCM work and returns empty ciphertext, empty nonce, and `fmt.Errorf("decode group key: %w", err)` on malformed base64.
- Current code: `go-mknoon/crypto/group.go::DecryptGroupMessage` decodes `groupKeyB64` before ciphertext and nonce decode and returns empty plaintext plus `fmt.Errorf("decode group key: %w", err)` on malformed base64.
- Current tests: `go-mknoon/crypto/group_test.go` already contains GK-001, GK-002, and GK-003 row-owned tests, plus generic `TestEncryptGroupMessage_InvalidKey` and `TestDecryptGroupMessage_InvalidBase64`. It does not contain `TestGK004InvalidKeyBase64IsRejected`.
- Current imports: `go-mknoon/crypto/group_test.go` already imports `encoding/base64` and `strings`, so the planned test should not need new imports.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md` defines the Group Messaging Gate for group send/receive/retry/resume/invite/announcement behavior changes and records Go module tests and `git diff --check` as part of broad release-style evidence. This GK-004 path is direct Go crypto tests-only unless the proof exposes a production behavior gap.
- Worktree caution: scoped status showed existing modifications in the source matrix, breakdown, and `go-mknoon/crypto/group_test.go`. Implementers must preserve those edits and avoid reverting adjacent GK-001/GK-002/GK-003 work.

## real scope

Own exactly source row GK-004: malformed group key base64 is rejected for both encrypt and decrypt with a clear key decode error and no panic.

The expected implementation is a row-owned Go crypto regression test in `go-mknoon/crypto/group_test.go`. Production code is not in scope unless the exact GK-004 regression proves that malformed group keys no longer return a clear `decode group key` error, return non-empty encrypt artifacts on failure, panic, or are masked by ciphertext/nonce decode errors.

Do not change Flutter group replay code, Go node/internal envelope behavior, key generation, encryption algorithms, nonce generation, source matrix rows, breakdown rows, or adjacent GK-001/GK-002/GK-003 tests during the implementation step except for the later closure update that records concrete passing evidence after the code/test work is accepted.

## closure bar

GK-004 is good enough when a row-named test `TestGK004InvalidKeyBase64IsRejected` proves all of the following:

- `EncryptGroupMessage` with a malformed group key returns a non-nil error containing `decode group key`.
- The failed encrypt call returns empty ciphertext and empty nonce.
- `DecryptGroupMessage` with the same malformed group key and valid-looking ciphertext/nonce placeholders returns a non-nil error containing `decode group key`.
- The decrypt path returns empty plaintext.
- The test completes normally, which is the no-panic proof for this direct unit seam.
- Focused crypto and broader row-relevant Go sweeps pass, `gofmt` has been applied if the test file is edited, and `git diff --check` passes.
- Later gap-closure updates the source row from `Open` with concrete file/test/gate evidence; this closure prerequisite has been satisfied for GK-004 by the closure writer, so the plan is accepted/closed.

## source of truth

Current code and direct tests are authoritative for behavior. The source matrix row GK-004 is authoritative for the row requirement, status, and closure expectation. The session breakdown is authoritative for this row's implementation classification and plan path. `Test-Flight-Improv/test-gate-definitions.md` is authoritative for named gate meaning when behavior changes.

If prose conflicts with current code, inspect and trust the code/test seam first. If the breakdown conflicts with the source matrix status, do not accept closure until the source row is updated with evidence. If gate prose conflicts with direct command evidence, keep the direct failing command as unresolved until reviewed.

## session classification

`implementation-ready`

Rationale: the row is `needs_tests_only`, the behavior appears already implemented in `go-mknoon/crypto/group.go`, and the missing artifact is an exact row-owned regression/proof. At planning time this was not docs-only, evidence-only, or acceptance-only because source row GK-004 remained `Open`; after closure, GK-004 is `Covered` with exact row-owned evidence.

## exact problem statement

GK-004 lacks exact row-owned proof that malformed group key base64 is rejected on both group encrypt and group decrypt. Generic invalid-key/base64 tests exist, but they do not own the GK-004 matrix row, do not assert the error text contains `decode group key` on both paths, and do not assert empty encrypt artifacts.

User-visible behavior to protect: malformed stored, received, or replayed group key material must fail cleanly at key decode time instead of panicking, producing ciphertext/nonce output, or surfacing a misleading ciphertext/nonce error.

What must stay unchanged: valid group key generation, valid encrypt/decrypt round-trip behavior, nonce uniqueness, ciphertext/authentication semantics, signature data formatting, and adjacent GK-001/GK-002/GK-003 tests.

## files and repos to inspect next

- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `go-mknoon/go.mod`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-004, only during later closure
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row GK-004, only during later closure
- `Test-Flight-Improv/test-gate-definitions.md`, only if implementation unexpectedly changes behavior beyond Go crypto tests

## existing tests covering this area

- `TestEncryptGroupMessage_InvalidKey` checks encrypt rejects a non-base64 key, but only asserts `err != nil`.
- `TestDecryptGroupMessage_InvalidBase64` checks invalid ciphertext, invalid nonce, and invalid key base64, but only asserts `err != nil`.
- `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` owns key generation length/base64/uniqueness.
- `TestGK002EncryptDecryptRoundTripForTextPayload` owns exact valid encrypt/decrypt round trip and artifact base64 shape.
- `TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext` owns nonce/ciphertext uniqueness for same plaintext.

Missing: an exact GK-004 test that covers both encrypt and decrypt with malformed group key base64, asserts the key-specific decode error prefix, asserts empty failure outputs, and documents no panic through normal test completion.

## regression/tests to add first

Add `TestGK004InvalidKeyBase64IsRejected` to `go-mknoon/crypto/group_test.go` before considering production changes.

Planned proof shape:

```go
func TestGK004InvalidKeyBase64IsRejected(t *testing.T) {
	malformedKeyB64 := "not-valid-base64!!!"

	ctB64, nonceB64, err := EncryptGroupMessage(malformedKeyB64, "GK-004 plaintext")
	if err == nil {
		t.Fatal("EncryptGroupMessage with malformed group key should fail")
	}
	if !strings.Contains(err.Error(), "decode group key") {
		t.Fatalf("EncryptGroupMessage error = %q, want decode group key", err.Error())
	}
	if ctB64 != "" || nonceB64 != "" {
		t.Fatalf("EncryptGroupMessage returned ciphertext=%q nonce=%q, want empty outputs", ctB64, nonceB64)
	}

	validLookingCiphertextB64 := base64.StdEncoding.EncodeToString([]byte("GK-004 ciphertext placeholder"))
	validLookingNonceB64 := base64.StdEncoding.EncodeToString(make([]byte, 12))
	plaintext, err := DecryptGroupMessage(malformedKeyB64, validLookingCiphertextB64, validLookingNonceB64)
	if err == nil {
		t.Fatal("DecryptGroupMessage with malformed group key should fail")
	}
	if !strings.Contains(err.Error(), "decode group key") {
		t.Fatalf("DecryptGroupMessage error = %q, want decode group key", err.Error())
	}
	if plaintext != "" {
		t.Fatalf("DecryptGroupMessage plaintext = %q, want empty", plaintext)
	}
}
```

The ciphertext and nonce placeholders should be valid standard-base64 strings so the decrypt assertion isolates the key decode path and avoids accidentally proving only ciphertext/nonce decode behavior.

## step-by-step implementation plan

1. Confirm the GK-004 test selector is not already present. If it is already present, inspect whether it fully satisfies the closure bar instead of adding a duplicate.
2. Add `TestGK004InvalidKeyBase64IsRejected` to `go-mknoon/crypto/group_test.go` near the adjacent invalid key/base64 tests, preserving GK-001/GK-002/GK-003 tests and existing imports.
3. Run `gofmt` on `go-mknoon/crypto/group_test.go`.
4. Run the focused crypto command for GK-004 plus adjacent invalid-base64 and GK-001/GK-002/GK-003 tests.
5. If the focused test passes without production changes, stop implementation there and do not edit `go-mknoon/crypto/group.go`.
6. If the exact GK-004 proof fails because malformed keys do not return `decode group key`, because encrypt returns non-empty artifacts on failure, or because a panic occurs, inspect `go-mknoon/crypto/group.go` only and make the smallest code change needed to restore decode-first malformed-key rejection.
7. Run the broader node/internal/crypto row-relevant sweep.
8. Run `git diff --check`.
9. During later gap closure, update only the source matrix and breakdown GK-004 closure entries with concrete evidence from the passed commands. Do not accept the row while the source matrix still says `Open`.

## risks and edge cases

- The existing generic tests may create a false sense of coverage; the row still needs an exact GK-004 test with error-text and empty-output assertions.
- Decrypt must prove key decode rejection, not ciphertext or nonce decode rejection. Use valid-looking ciphertext and nonce placeholders.
- Go's `-run` selector exits successfully when no test matches. Treat the pre-add selector as a discovery step, not closure evidence.
- Existing uncommitted edits in the source matrix, breakdown, and crypto test file must be preserved.
- A production change would be higher risk than expected for this row. Only make one if the row-owned proof exposes a real behavior gap.

## exact tests and gates to run

Pre-add discovery selector:

```bash
(cd go-mknoon && go test ./crypto -list '^TestGK004InvalidKeyBase64IsRejected$')
```

Expected pre-add result: no matching test is listed. If the test already exists, inspect it against the closure bar before editing.

Format after editing the Go test file:

```bash
(cd go-mknoon && gofmt -w crypto/group_test.go)
```

Focused crypto proof:

```bash
(cd go-mknoon && go test ./crypto -run '^(TestGK004InvalidKeyBase64IsRejected|TestEncryptGroupMessage_InvalidKey|TestDecryptGroupMessage_InvalidBase64|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext)$' -count=1)
```

Broader row-relevant Go sweep:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK004|TestGK003|TestGK002|TestGK001|InvalidBase64|InvalidKey' -count=1)
```

Whitespace/check gate:

```bash
git diff --check
```

Named Flutter gate requirement: none on the expected tests-only Go crypto path, because no group send/receive/retry/resume/invite/announcement behavior should change. If implementation unexpectedly touches Flutter group behavior, offline replay envelope code, or production group messaging behavior, also run:

```bash
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

## known-failure interpretation

Any failure in the focused crypto proof is relevant and blocks GK-004 closure. Any compile failure in `go-mknoon/crypto`, `go-mknoon/node`, or `go-mknoon/internal` blocks closure because the row-relevant sweep cannot validate.

If the broader sweep fails in a test selected by the regex, inspect whether it is caused by the GK-004 change or a pre-existing adjacent failure. Do not claim GK-004 closure unless the focused GK-004 proof and broader row-relevant sweep both pass or the failure is explicitly classified by the reviewer as unrelated with concrete evidence.

Known Flutter gate history in `test-gate-definitions.md` is not a waiver for Go crypto failures. Optional Flutter gate/device issues are only relevant if implementation unexpectedly touches Flutter or production group behavior.

## done criteria

- `go-mknoon/crypto/group_test.go` contains exactly one row-owned `TestGK004InvalidKeyBase64IsRejected`.
- The test covers encrypt and decrypt with a malformed group key.
- Both paths assert non-nil errors containing `decode group key`.
- Encrypt failure asserts empty ciphertext and nonce; decrypt failure asserts empty plaintext.
- No production code is changed unless required by a failing GK-004 proof.
- `gofmt`, the focused crypto command, the broader node/internal/crypto sweep, and `git diff --check` pass.
- Later closure records the concrete file/test/gate evidence in the source matrix and breakdown so GK-004 no longer remains `Open`.

## scope guard

Non-goals:

- Do not redesign key validation or switch base64 encoders.
- Do not change AES-GCM parameters, nonce length, random source, ciphertext format, or signature data.
- Do not broaden into key rotation, group envelope validation, offline replay, relay delivery, node pubsub, Flutter bridge, or simulator proofs.
- Do not rewrite existing generic invalid-base64 tests unless the new row-owned test would otherwise duplicate fragile code.
- Do not close GK-005 or any later row.

Overengineering for this session would include adding helper abstractions, table-driving unrelated crypto cases, changing public error types, normalizing every crypto error, or adding integration tests for a direct `go-mknoon/crypto` malformed-input unit seam.

## accepted differences / intentionally out of scope

- Generic invalid-key/base64 tests may remain as broader smoke coverage; GK-004 adds row-owned specificity instead of replacing them.
- Integration evidence is Recommended in the source row but not required for the expected direct crypto tests-only path.
- Node/internal/Flutter files named by the breakdown are relevant blast-radius references, not planned edit targets, unless the Go crypto proof exposes behavior drift outside `crypto/group.go`.
- Source matrix and breakdown closure edits are intentionally deferred until after implementation and verification produce concrete evidence.

## dependency impact

GK-004 is the next unresolved P0 row after GK-003 in the breakdown continuation. Later GK rows should not treat invalid-key base64 rejection as covered until this row has exact row-owned test evidence and source row closure.

If the plan changes from tests-only to production-fix-required, later rows that depend on stable group-key decode errors should be revisited for assumptions about error text and empty outputs. If the pre-add discovery finds an already sufficient GK-004 test, skip duplicate test work and move directly to verification and closure evidence.

## reviewer notes

Reviewer verdict: sufficient as-is.

- Missing files, tests, regressions, or gates: none for the expected tests-only path. The direct GK-004 regression, adjacent crypto tests, broader node/internal/crypto sweep, `gofmt`, and `git diff --check` are explicit. Optional Flutter/group gate escalation is correctly conditional on unexpected production or Flutter behavior changes.
- Stale or incorrect assumptions: none found. Current code evidence supports decode-first malformed-key rejection, and the plan preserves the source row as `Open` until later closure evidence exists.
- Overengineering: none. The plan avoids helper abstractions, error-type redesign, integration expansion, and unrelated key/envelope/replay work.
- Decomposition sufficiency: sufficient. Implementation starts with one row-owned Go test, stops if it passes, and only permits a narrow `go-mknoon/crypto/group.go` production change if the exact proof fails.
- Minimum needed to implement safely: add `TestGK004InvalidKeyBase64IsRejected`, run the listed commands, and later update row closure evidence only after the commands pass.

## arbiter notes

Structural blockers: none.

Incremental details: none that must be patched before execution. The pre-add `-list` command is intentionally a discovery selector because Go `-run` can pass with zero matching tests.

Accepted differences:

- No named Flutter gate is required for the expected tests-only Go crypto path.
- Recommended integration evidence remains intentionally out of scope unless implementation touches production group behavior.
- Source matrix and breakdown closure edits are deferred until after concrete implementation evidence exists; this plan alone does not close GK-004.

Stop rule: no new structural blocker was found, so planning stops here.

## final planning verdict

Final verdict: execution-ready.

Final plan: add one row-owned Go crypto test, `TestGK004InvalidKeyBase64IsRejected`, then run the exact focused and broader Go commands plus `git diff --check`. Do not edit production code unless the exact GK-004 proof fails.

Structural blockers remaining: none.

Incremental details intentionally deferred: none.

Accepted differences intentionally left unchanged: no Flutter/group named gate on the expected direct crypto tests-only path; source row closure waits for implementation evidence.

Exact docs/files used as evidence: source matrix GK-004 row, session breakdown GK-004 rows, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/group_test.go`, `go-mknoon/go.mod`, and `Test-Flight-Improv/test-gate-definitions.md`.

Why the plan is safe to implement now: the current code already exposes the desired decode-first behavior, the missing work is a narrow row-owned proof, the commands validate direct and adjacent behavior, and the scope guard prevents production or closure drift.

## Final QA Result

2026-05-12 03:38:47 CEST - QA Reviewer verdict: accepted.

Findings:

- `go-mknoon/crypto/group_test.go::TestGK004InvalidKeyBase64IsRejected` satisfies the GK-004 closure bar: malformed key, encrypt returns a non-nil error containing `decode group key`, ciphertext and nonce remain empty, decrypt uses the same malformed key with valid-looking base64 ciphertext/nonce placeholders, decrypt returns a non-nil error containing `decode group key`, plaintext remains empty, and normal test completion provides the no-panic proof.
- GK-001, GK-002, and GK-003 row-owned tests remain present and were included in the focused QA proof.
- `git diff -- go-mknoon/crypto/group.go` is empty; no production crypto code changed.
- The `QA Fix-Pass Note` correctly reclassifies the prior source matrix/breakdown blocker as closure-phase handoff, not an execution blocker. Source matrix and breakdown edits remain intentionally reserved for the closure writer and are not a blocker for this execution QA acceptance.

Exact QA command outcomes:

- `(cd go-mknoon && go test ./crypto -run '^(TestGK004InvalidKeyBase64IsRejected|TestEncryptGroupMessage_InvalidKey|TestDecryptGroupMessage_InvalidBase64|TestGK001GenerateGroupKeyReturns32ByteBase64AESKey|TestGK002EncryptDecryptRoundTripForTextPayload|TestGK003EncryptionProducesUniqueNoncesAndCiphertextsForSamePlaintext)$' -count=1)` passed: `ok github.com/mknoon/go-mknoon/crypto 0.491s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK004|TestGK003|TestGK002|TestGK001|InvalidBase64|InvalidKey' -count=1)` passed: `ok github.com/mknoon/go-mknoon/node 4.397s`; `ok github.com/mknoon/go-mknoon/internal 0.679s`; `ok github.com/mknoon/go-mknoon/crypto 0.845s`.
- `git diff --check` passed with exit 0 and no output.

Residual-only note: source matrix and session breakdown closure remains for the closure writer before row acceptance. No execution QA blocker remains.
