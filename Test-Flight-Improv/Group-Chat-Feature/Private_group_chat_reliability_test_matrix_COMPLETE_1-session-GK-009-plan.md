# GK-009 Plan: Signature Data Is Deterministic and Epoch-Bound

Status: accepted/closed

## Planning Progress

- 2026-05-12 06:26:05 CEST - Planner completed. Files inspected since last update: full draft plan sections, exact test shape, exact commands, scope guard, and known-failure interpretation. Decision/blocker: draft is implementation-ready and tests-only unless the new row-named regression proves a production bug. Next action: run reviewer pass for sufficiency and scope drift.
- 2026-05-12 06:27:00 CEST - Reviewer started. Files inspected since last update: full draft plan, mandatory section checklist, source row semantics, breakdown row classification, PubSub usage evidence, and exact gate list. Decision/blocker: review focus is whether direct crypto proof is enough despite recommended integration, whether race omission is justified, and whether GK-010+/GK-008 scope is excluded. Next action: classify sufficiency and required adjustments.
- 2026-05-12 06:27:00 CEST - Reviewer completed. Files inspected since last update: full draft plan and evidence notes. Decision/blocker: sufficient as-is; no structural blockers. The plan requires a row-named regression, exact changed-field signature invalidation, focused crypto selector, broader Go sweep, and diff hygiene while preserving dirty files. Next action: run arbiter classification and stop-rule decision.
- 2026-05-12 06:28:00 CEST - Arbiter started. Files inspected since last update: reviewer verdict, closure bar, scope guard, exact tests/gates, known-failure interpretation, and accepted differences. Decision/blocker: classify findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution-ready status if no structural blocker remains.
- 2026-05-12 06:28:00 CEST - Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; no patch loop required. Incremental details are limited to implementation-time fixture/placement choices, and accepted differences are documented. Next action: plan is execution-ready for GK-009 only.

## Execution Progress

- 2026-05-12 06:30:32 CEST - Executor started. Files inspected or touched: plan file, `git status --short`, `go-mknoon/crypto/group_test.go`, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/sign.go`, `go-mknoon/crypto/sign_test.go`, `go-mknoon/crypto/signature_test.go`. Decision/blocker: contract extracted; worktree already dirty with unrelated files, including existing `group_test.go` edits from earlier rows. Next action: add only the GK-009 row-named regression in `go-mknoon/crypto/group_test.go`.
- 2026-05-12 06:30:32 CEST - Executor implementation pass. Files touched: `go-mknoon/crypto/group_test.go`. Decision/blocker: added `TestGK009SignatureDataIsDeterministicAndEpochBound` near the existing `TestBuildGroupSignatureData_*` tests; no production code touched. Next action: run required gofmt and gates.
- 2026-05-12 06:35:19 CEST - Required gofmt completed. Command: `(cd go-mknoon && gofmt -w crypto/group_test.go)`. Result: exit 0, no output. Next action: run focused crypto selector.
- 2026-05-12 06:35:19 CEST - Focused crypto selector completed. Command: `(cd go-mknoon && go test ./crypto -run '^(TestGK009SignatureDataIsDeterministicAndEpochBound|TestBuildGroupSignatureData_Format|TestBuildGroupSignatureData_Deterministic|TestSignAndVerify|TestSignVerify_RoundTrip|TestVerifyWrongData|TestVerify_TamperedData)$' -count=1)`. Result: exit 0; output: `ok  	github.com/mknoon/go-mknoon/crypto	0.390s`. Next action: run broader Go sweep.
- 2026-05-12 06:35:19 CEST - Broader Go sweep completed. Command: `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)`. Result: exit 0; output: `ok  	github.com/mknoon/go-mknoon/node	213.685s`; `ok  	github.com/mknoon/go-mknoon/internal	0.694s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.928s`. Next action: run diff hygiene.
- 2026-05-12 06:35:19 CEST - Diff hygiene completed. Command: `git diff --check`. Result: exit 0, no output. Decision/blocker: no blockers or pre-existing failures observed in required gates. Next action: record final executor verdict.
- 2026-05-12 06:36:17 CEST - Final doc diff hygiene rerun completed after executor verdict write. Command: `git diff --check`. Result: exit 0, no output. Decision/blocker: final owned diff remains clean.

## Evidence Collector Notes

- Source matrix row `GK-009` is still `P0` / `Open`: "Signature data is deterministic and epoch-bound." Preconditions are known `groupId`, `epoch`, and `ciphertext`; steps are build signature data twice, change epoch/group/ciphertext, and verify signatures; expected result is same inputs produce same data and any changed signed field invalidates the signature. Unit is `Required`, Integration is `Recommended`, Fake Network/3-Party E2E/Race/Perf are `N/A`; the existing note points at `group.go:107-111`.
- Session breakdown row `GK-009` is `needs_tests_only` / `implementation-ready` and says this session owns exactly GK-009. It lists broader group/PubSub/offline-replay surfaces from the matrix, but also marks the row as tests-only.
- `go-mknoon/crypto/group.go:107-110` currently constructs signature data as `fmt.Sprintf("%s|%d|%s", groupId, keyEpoch, ctB64)`.
- `go-mknoon/crypto/group_test.go:480-496` already has `TestBuildGroupSignatureData_Format` and `TestBuildGroupSignatureData_Deterministic`, plus row tests through GK-005 in the same dirty file. Those tests do not sign data or prove mutated group/epoch/ciphertext fail verification under the original signature.
- `go-mknoon/crypto/sign.go:13-48` signs and verifies Ed25519 over the exact data string passed to `SignPayload` / `VerifyPayload`.
- `go-mknoon/crypto/sign_test.go:11-18` provides `generateTestKeyPair(t)` in package `crypto`, which a new `group_test.go` test can reuse without new helpers. Existing sign tests prove generic same-data success and changed-data failure.
- `go-mknoon/node/pubsub.go:216-217` signs live group messages with `BuildGroupSignatureData(groupId, keyInfo.KeyEpoch, ctB64)`, and `go-mknoon/node/pubsub.go:587-595` verifies envelopes with `BuildGroupSignatureData(groupId, current-or-previous epoch, env.Encrypted.Ciphertext)`. This confirms production uses the same group/epoch/ciphertext signature-data seam for live PubSub.
- The worktree is already dirty with many unrelated files, including `go-mknoon/crypto/group_test.go` from earlier rows. Execution must preserve those edits and touch only the GK-009 plan plus the minimal test file unless the regression exposes a production defect.

## real scope

Own exactly source matrix row GK-009: prove the group signature-data string is deterministic for identical `groupId`, `epoch`, and `ciphertext`, and prove signatures over that string are invalid when any one of those signed fields changes.

In scope:

- Add one exact row-named crypto regression, preferably `TestGK009SignatureDataIsDeterministicAndEpochBound`, in `go-mknoon/crypto/group_test.go` near the existing signature-data tests.
- Build identical inputs twice and assert the exact stable string.
- Sign the base signature data with Ed25519 via existing `SignPayload`.
- Verify the base signature succeeds against the same data and public key.
- Build changed signature data for changed epoch, changed group id, and changed ciphertext.
- Assert each changed data string differs from the base string.
- Assert the same original signature/public key fails verification for each changed data string.

Out of scope:

- Do not update source matrix or breakdown closure rows in this planning task.
- Do not implement GK-010+ malformed-envelope/parser rows.
- Do not reopen GK-008 live PubSub wrong-key behavior.
- Do not add Flutter, fake-network, simulator, bridge, offline replay, or PubSub integration tests for this row unless the direct crypto proof exposes a production defect outside `crypto`.
- Do not change the signature algorithm, delimiter format, envelope schema, key rotation behavior, nonce handling, or validator diagnostics unless the row-named regression proves current production is wrong.

## closure bar

GK-009 is good enough when the repo has row-owned evidence that:

- `BuildGroupSignatureData` returns the same exact string for repeated identical inputs.
- The exact base string includes group id, decimal epoch, and ciphertext in the current format `groupId|epoch|ciphertext`.
- `SignPayload` over the base string verifies successfully with `VerifyPayload` using the matching public key.
- Rebuilding signature data with only the epoch changed produces a different string and fails verification with the base signature/public key.
- Rebuilding signature data with only the group id changed produces a different string and fails verification with the base signature/public key.
- Rebuilding signature data with only the ciphertext changed produces a different string and fails verification with the base signature/public key.
- The focused crypto selector, broader Go sweep over `./node ./internal ./crypto`, and `git diff --check` pass, or any unrelated pre-existing failures are isolated with exact command output.

## source of truth

- Current code and tests win over stale docs.
- Source row `GK-009` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is the row contract.
- Breakdown row/session `GK-009` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is the session contract.
- `go-mknoon/crypto/group.go` is authoritative for `BuildGroupSignatureData`.
- `go-mknoon/crypto/sign.go` is authoritative for Ed25519 signing and verification behavior.
- `go-mknoon/crypto/group_test.go`, `go-mknoon/crypto/sign_test.go`, and `go-mknoon/crypto/signature_test.go` are authoritative for current direct crypto coverage.
- `go-mknoon/node/pubsub.go` is evidence-only for production usage of group id, epoch, and ciphertext in live group signatures. It is not an expected write surface for GK-009.

## session classification

implementation-ready.

This is implementation-committed gap closure. Production already appears to build and consume the expected signature data, so the expected execution is tests-only. It is not acceptance-only because the source row remains `Open` and lacks exact row-owned signature invalidation proof.

## exact problem statement

GK-009 remains open because existing crypto tests prove string format and same-input determinism, while existing signature tests prove generic changed-data failure, but no exact row-owned test connects the two: group signature data must be deterministic and must bind the signature to group id, epoch, and ciphertext together.

User-visible behavior protected by this row: a valid group signature for one encrypted envelope must not remain valid if the envelope is replayed or rewritten under a different group, key epoch, or ciphertext. The behavior that must stay unchanged is the current `groupId|epoch|ciphertext` signed-data contract used by PubSub.

## files and repos to inspect next

Before editing:

- `git status --short`
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `go-mknoon/crypto/sign.go`
- `go-mknoon/crypto/sign_test.go`
- `go-mknoon/crypto/signature_test.go`
- `go-mknoon/node/pubsub.go`

Expected write surface:

- `go-mknoon/crypto/group_test.go`

Fallback-only if the new regression fails due to production behavior rather than test construction:

- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/sign.go`

Do not inspect or edit Flutter/Dart files for the expected GK-009 tests-only proof.

## existing tests covering this area

- `go-mknoon/crypto/group_test.go::TestBuildGroupSignatureData_Format` pins the current string format as `group-abc-123|5|c2VjcmV0`.
- `go-mknoon/crypto/group_test.go::TestBuildGroupSignatureData_Deterministic` proves two identical input triples produce the same string.
- `go-mknoon/crypto/sign_test.go::TestSignAndVerify` and `go-mknoon/crypto/signature_test.go::TestSignVerify_RoundTrip` prove direct Ed25519 sign/verify success for unchanged data.
- `go-mknoon/crypto/sign_test.go::TestVerifyWrongData` and `go-mknoon/crypto/signature_test.go::TestVerify_TamperedData` prove generic changed-data verification failure.
- Adjacent `go-mknoon/crypto/group_test.go` row tests GK-001 through GK-005 pin key generation/encrypt/decrypt/key validation behavior and must remain intact.

Missing:

- No exact `GK-009` row-named regression proves the deterministic group signature-data string and Ed25519 signature invalidation for changed epoch, changed group id, and changed ciphertext in one row-owned test.

## regression/tests to add first

Add `TestGK009SignatureDataIsDeterministicAndEpochBound` in `go-mknoon/crypto/group_test.go`, next to `TestBuildGroupSignatureData_Format` and `TestBuildGroupSignatureData_Deterministic`.

Preferred test shape:

- Set stable base inputs such as `groupID := "group-gk-009"`, `epoch := 7`, and `ciphertext := "Y2lwaGVydGV4dC1nazAwOQ=="`.
- Call `BuildGroupSignatureData(groupID, epoch, ciphertext)` twice.
- Assert both values equal each other and equal the exact string `group-gk-009|7|Y2lwaGVydGV4dC1nazAwOQ==`.
- Reuse `generateTestKeyPair(t)` from `sign_test.go` to get Ed25519 public/private keys.
- Sign the base data with `SignPayload(privateKeyB64, baseData)`.
- Verify the base data succeeds with `VerifyPayload(publicKeyB64, baseData, signature)`.
- For each changed field, build a candidate data string:
  - changed epoch: `BuildGroupSignatureData(groupID, epoch+1, ciphertext)`
  - changed group id: `BuildGroupSignatureData(groupID+"-other", epoch, ciphertext)`
  - changed ciphertext: `BuildGroupSignatureData(groupID, epoch, "Y2lwaGVydGV4dC1nazAwOS10YW1wZXJlZA==")`
- For each candidate, assert the candidate data differs from the base data.
- For each candidate, verify the original base signature against the candidate data with the original public key and assert `valid == false` with no verification error.

Do not encrypt inside this test. GK-009 is about signature data and signature binding, not AES-GCM randomness or nonce/ciphertext generation.

## step-by-step implementation plan

1. Reconfirm `git status --short` and preserve unrelated dirty files.
2. Reopen `go-mknoon/crypto/group_test.go`, `go-mknoon/crypto/group.go`, `go-mknoon/crypto/sign.go`, and direct signature tests to verify local context has not shifted.
3. Add `TestGK009SignatureDataIsDeterministicAndEpochBound` near the existing `TestBuildGroupSignatureData_*` tests in `go-mknoon/crypto/group_test.go`.
4. Use fixed group id, epoch, and ciphertext values; assert the exact base string before signing.
5. Reuse `generateTestKeyPair(t)` and existing `SignPayload` / `VerifyPayload` helpers.
6. Add a small table for the changed epoch, changed group id, and changed ciphertext cases.
7. For each changed case, assert the changed data string is not equal to the base data and that verifying the base signature against the changed data returns false.
8. Run `gofmt` on `go-mknoon/crypto/group_test.go`.
9. Run the focused crypto selector with GK-009 plus adjacent signature-data/signature tests.
10. Run the broader Go sweep over `./node ./internal ./crypto`.
11. Run `git diff --check`.
12. If the focused test fails because changed epoch/group/ciphertext still verifies, inspect whether the test accidentally re-signed changed data. If the test is correct, make the smallest production fix in `BuildGroupSignatureData` or sign/verify code and rerun the same gates.
13. Leave source matrix and session breakdown closure updates to a later closure/audit task after executor and QA evidence exist.

## risks and edge cases

- A test that signs each mutated data string would not prove GK-009; it must reuse the original base signature for all changed-field verification attempts.
- A test that only compares strings would duplicate existing coverage and miss the row's signature invalidation requirement.
- A test that only checks changed ciphertext would leave epoch-bound behavior unproved.
- Adding encryption to create ciphertext would add randomness and distract from deterministic signature-data proof.
- Because `go-mknoon/crypto/group_test.go` is already dirty from earlier rows, implementation must patch around existing edits and avoid formatting unrelated files.
- If `VerifyPayload` returns an error for changed data with the same valid public key/signature, that indicates a malformed test fixture, not expected Ed25519 changed-data behavior.
- If the broader Go sweep fails in unrelated dirty node/Flutter-adjacent changes, document exact failing packages and rerun the focused crypto selector; do not misclassify unrelated failures as GK-009 defects.

## exact tests and gates to run

Run from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

If the Go test file is edited:

```sh
(cd go-mknoon && gofmt -w crypto/group_test.go)
```

Focused GK-009 and adjacent signature-data/signature selector:

```sh
(cd go-mknoon && go test ./crypto -run '^(TestGK009SignatureDataIsDeterministicAndEpochBound|TestBuildGroupSignatureData_Format|TestBuildGroupSignatureData_Deterministic|TestSignAndVerify|TestSignVerify_RoundTrip|TestVerifyWrongData|TestVerify_TamperedData)$' -count=1)
```

Broader Go sweep:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Race is not required for the expected GK-009 implementation because the direct proof is pure deterministic string construction plus Ed25519 sign/verify with no shared state or goroutines. If execution unexpectedly touches PubSub, node validation, or concurrent state, add a focused Go race command for the touched package before closure.

Do not run Flutter gates for the expected tests-only Go crypto implementation.

## known-failure interpretation

- Any failure in `TestGK009SignatureDataIsDeterministicAndEpochBound` is row-owned and blocks GK-009 closure.
- If the base data strings differ, treat it as a deterministic string-construction defect or test input mutation bug.
- If the exact string assertion fails, confirm whether `BuildGroupSignatureData` format intentionally changed. If not, fix production or adjust only with explicit source-row justification.
- If base signature verification fails, investigate `SignPayload`, `VerifyPayload`, and key fixture setup before touching group signature data.
- If a changed epoch/group/ciphertext verifies successfully with the original base signature, treat it as a GK-009 blocker after confirming the test did not re-sign changed data.
- If the focused adjacent signature tests fail, treat failures in `crypto` sign/verify as blockers unless they are clearly unrelated pre-existing failures.
- If the broader Go sweep fails outside `./crypto`, document the exact failure and decide whether it is pre-existing from the dirty worktree; it should not broaden GK-009 into PubSub or Flutter work without a direct connection to signature data.
- `git diff --check` failures in the new GK-009 test or plan file are row-owned; unrelated pre-existing whitespace failures must be named and isolated before closure.

## done criteria

- `go-mknoon/crypto/group_test.go` contains exact row-named `TestGK009SignatureDataIsDeterministicAndEpochBound`.
- The test builds identical signature data twice and asserts the exact stable string.
- The test signs the base data once with `SignPayload`.
- The test verifies the base data succeeds with `VerifyPayload`.
- The test proves changed epoch, changed group id, and changed ciphertext each produce a different signature-data string.
- The test proves the original signature/public key fails verification for each changed signature-data string.
- No production files are changed unless the new test proves a real defect.
- Focused crypto selector, broader Go sweep over `./node ./internal ./crypto`, and `git diff --check` pass or any unrelated pre-existing failures are documented with exact commands and outputs.
- Source matrix and session breakdown closure rows remain untouched until a later closure writer records executor and QA evidence.

## scope guard

Non-goals:

- No GK-010+ malformed envelope parser work.
- No GK-008 wrong-public-key PubSub work.
- No GK-006/GK-007 ciphertext or nonce tamper work.
- No key-rotation grace semantics.
- No envelope schema changes.
- No Dart/Flutter bridge or offline replay changes.
- No simulator, fake-network, or UI tests.
- No broad refactor of crypto helpers or test utilities.

Overengineering signals:

- Adding a new signature-data abstraction when the row only needs proof of the existing builder.
- Generating encrypted payloads instead of using fixed ciphertext fixtures.
- Creating PubSub envelopes or starting nodes for a pure crypto row.
- Changing validator diagnostics or events for a direct string/signature proof.

## accepted differences / intentionally out of scope

- The session breakdown lists broad PubSub, internal envelope, and Flutter offline-replay files as possible surfaces, but current evidence narrows GK-009 to direct Go crypto proof plus PubSub usage confirmation. That difference is accepted because the row's expected result is signature-data determinism and changed-field signature invalidation, not live delivery behavior.
- Integration is `Recommended` in the source row, but direct crypto coverage is sufficient for closure if production usage is confirmed in `pubsub.go` and the broader Go sweep passes. Live PubSub signature rejection was covered by GK-008 and should not be duplicated here.
- Race testing is intentionally omitted for the expected tests-only crypto proof because no concurrent code path is touched.

## dependency impact

- GK-009 closure gives later group envelope/security rows a stable proof that signatures bind group id, epoch, and ciphertext.
- GK-010+ malformed envelope/parser rows should continue independently after GK-009 and must not inherit this plan's scope.
- If GK-009 unexpectedly requires a production change to `BuildGroupSignatureData`, re-run affected PubSub/node crypto sweeps before closing later rows because live validators depend on the same string format.

## Reviewer Notes

Reviewer verdict: sufficient as-is.

- Missing files, tests, or gates: none. The direct write surface is `go-mknoon/crypto/group_test.go`; `go-mknoon/crypto/group.go`, `go-mknoon/crypto/sign.go`, and `go-mknoon/node/pubsub.go` are correctly evidence/fallback files. The focused selector, broader Go sweep, and `git diff --check` are sufficient for the expected tests-only crypto change.
- Stale assumptions: none found. Current code still formats `groupId|epoch|ciphertext`, and PubSub signs/verifies with the same builder.
- Overengineering: none. The plan avoids encryption, PubSub nodes, Flutter gates, and new abstractions for a pure deterministic/signature-binding row.
- Decomposition: sufficient. One row, one row-named test, one expected test file, and a clear stop condition if production already passes.
- Minimum needed: implement the GK-009 test exactly, run the listed commands, and leave source matrix/breakdown closure updates to a later closure task.

## Arbiter Decision

Final verdict: execution-ready for GK-009 only.

Structural blockers:

- None.

Incremental details intentionally deferred:

- The executor may choose equivalent fixed ciphertext fixture strings if the exact assertions remain stable and readable.
- The executor may place the test immediately before or after the existing `TestBuildGroupSignatureData_*` tests as long as it stays in `go-mknoon/crypto/group_test.go`.
- Focused race is intentionally omitted unless execution unexpectedly touches concurrent PubSub/node code.

Accepted differences intentionally left unchanged:

- Direct crypto proof is accepted instead of live PubSub integration because PubSub usage has been confirmed and the source row asks for signature-data determinism plus changed-field signature invalidation.
- No Flutter/offline-replay work is planned despite broad breakdown surfaces because this row's behavior lives in Go crypto.
- No source matrix or breakdown closure rows are updated by this planner.

Stop rule:

- The reviewer found no structural blocker, so the arbiter stops after this pass. No re-review loop is required.

## Executor Verdict

Verdict: pass.

Files changed by this executor:

- `go-mknoon/crypto/group_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-009-plan.md`

Implementation summary:

- Added exact row-named `TestGK009SignatureDataIsDeterministicAndEpochBound` near the existing `TestBuildGroupSignatureData_*` tests.
- The test builds identical group signature data twice, asserts the exact `group-gk-009|7|Y2lwaGVydGV4dC1nazAwOQ==` string, signs the base data once, verifies the base data succeeds, and proves changed epoch, changed group id, and changed ciphertext each differ from base data and fail verification with the original signature/public key.
- No production files were changed. Existing dirty worktree edits, including earlier GK-001 through GK-005 changes in `go-mknoon/crypto/group_test.go`, were preserved.

Exact command results:

- `(cd go-mknoon && gofmt -w crypto/group_test.go)` -> exit 0, no output.
- `(cd go-mknoon && go test ./crypto -run '^(TestGK009SignatureDataIsDeterministicAndEpochBound|TestBuildGroupSignatureData_Format|TestBuildGroupSignatureData_Deterministic|TestSignAndVerify|TestSignVerify_RoundTrip|TestVerifyWrongData|TestVerify_TamperedData)$' -count=1)` -> exit 0; `ok  	github.com/mknoon/go-mknoon/crypto	0.390s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` -> exit 0; `ok  	github.com/mknoon/go-mknoon/node	213.685s`; `ok  	github.com/mknoon/go-mknoon/internal	0.694s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.928s`.
- `git diff --check` -> exit 0, no output. Rerun after final executor-verdict doc edit also exited 0 with no output.

Blockers/pre-existing failures:

- None observed in the required commands.

## QA Reviewer Pass

QA verdict: passed.

Inspected files:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-009-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `go-mknoon/crypto/group_test.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/sign.go`

Scope and behavior review:

- `go-mknoon/crypto/group_test.go::TestGK009SignatureDataIsDeterministicAndEpochBound` matches GK-009 row semantics. It builds `BuildGroupSignatureData(groupID, epoch, ciphertext)` twice, asserts exact stable data `group-gk-009|7|Y2lwaGVydGV4dC1nazAwOQ==`, signs that base data once, verifies the base data, then checks changed epoch, changed group id, and changed ciphertext each produce different data and fail verification with the original signature/public key.
- Relevant helpers still implement the expected production contract: `go-mknoon/crypto/group.go::BuildGroupSignatureData` returns `fmt.Sprintf("%s|%d|%s", groupId, keyEpoch, ctB64)`, and `go-mknoon/crypto/sign.go::SignPayload` / `VerifyPayload` sign and verify the exact data string.
- GK-009 production code was not changed. The GK-009-owned crypto diff is limited to `go-mknoon/crypto/group_test.go`; `go-mknoon/crypto/group.go` and `go-mknoon/crypto/sign.go` have no diff.
- No GK-010+, GK-008, PubSub live integration, Flutter, source-matrix closure, breakdown closure, or final program verdict scope was absorbed. Source matrix row `GK-009` remains `Open`; breakdown row `GK-009` remains `implementation-ready`.

Exact command results:

- `(cd go-mknoon && go test ./crypto -run '^(TestGK009SignatureDataIsDeterministicAndEpochBound|TestBuildGroupSignatureData_Format|TestBuildGroupSignatureData_Deterministic|TestSignAndVerify|TestSignVerify_RoundTrip|TestVerifyWrongData|TestVerify_TamperedData)$' -count=1)` -> exit 0; output: `ok  	github.com/mknoon/go-mknoon/crypto	0.428s`.
- `(cd go-mknoon && go test ./node ./internal ./crypto -count=1)` -> exit 0; output: `ok  	github.com/mknoon/go-mknoon/node	214.969s`; `ok  	github.com/mknoon/go-mknoon/internal	0.447s`; `ok  	github.com/mknoon/go-mknoon/crypto	0.258s`.
- `git diff --check` -> exit 0, no output.

Blocking findings:

- None.

Non-blocking findings:

- The worktree remains dirty with unrelated group-chat files and earlier closure docs. They were not modified by this QA pass and are not GK-009 blockers.

## Closure Note

2026-05-12 06:48 CEST - Closure Writer accepted and closed GK-009. `go-mknoon/crypto/group_test.go::TestGK009SignatureDataIsDeterministicAndEpochBound` builds identical `BuildGroupSignatureData(groupID, epoch, ciphertext)` twice, asserts exact stable data `group-gk-009|7|Y2lwaGVydGV4dC1nazAwOQ==`, signs the base data once, verifies the base data, and proves changed epoch, changed group id, and changed ciphertext each produce different data and fail `VerifyPayload` with the original signature/public key. Executor evidence: focused crypto selector `ok github.com/mknoon/go-mknoon/crypto 0.390s`, broader Go sweep `ok node 213.685s`, `ok internal 0.694s`, `ok crypto 0.928s`, and `git diff --check` passed. Independent QA evidence: focused crypto selector `ok github.com/mknoon/go-mknoon/crypto 0.428s`, broader Go sweep `ok node 214.969s`, `ok internal 0.447s`, `ok crypto 0.258s`, and `git diff --check` passed. Production code unchanged for GK-009; scoped crypto diff is tests-only in `go-mknoon/crypto/group_test.go`; residual-only none. Source matrix and breakdown closure rows now record GK-009 as covered/accepted, with GK-010 left as the next runnable unresolved P0 row.
