# GK-001 Session Plan - GenerateGroupKey returns 32-byte base64 AES key

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 02:17:50 CEST | Planner completed | Evidence Collector notes above plus mandatory section draft. | Draft is tests-only and implementation-ready: add one exact row-named `go-mknoon/crypto` unit test and stop if it passes against current code. | Run strict sufficiency review. |
| 2026-05-12 02:19:12 CEST | Reviewer started | This plan draft; Evidence Collector notes; gate docs summarized above. | Review target: sufficiency, missing tests/gates, stale assumptions, scope drift, and decomposition clarity. | Classify findings and patch only if structural gaps exist. |
| 2026-05-12 02:19:31 CEST | Reviewer completed | This plan draft and mandatory section checklist. | Sufficient as-is. No structural blocker: scope is narrow, regression-first rule is explicit, source-of-truth order is clear, tests/gates are exact, and stop rule prevents production/codebase drift. | Run Arbiter classification and final status decision. |
| 2026-05-12 02:20:02 CEST | Arbiter started | Reviewer Findings; full mandatory plan sections. | Classifying reviewer findings into structural blockers, incremental details, and accepted differences. | Promote only if no structural blocker remains. |
| 2026-05-12 02:20:19 CEST | Arbiter completed | Reviewer Findings; scope guard; exact tests/gates; accepted differences. | No structural blockers. Incremental details are optional only. Accepted differences are documented. Plan is promoted through arbiter-pass to `execution-ready`. | Hand off for GK-001 implementation later; do not implement in this planning session. |

## Evidence Collector Notes

- Source row `GK-001` in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` says "GenerateGroupKey returns 32-byte base64 AES key"; expected behavior is that every generated key decodes to 32 bytes and repeated calls are unique; status is `Open`, priority `P0`, unit test `Required`, integration `Recommended`.
- Breakdown entries classify `GK-001` as `needs_tests_only` / `implementation-ready`, point at this plan path, and state the missing row-owned proof is an exact `GK-001` regression for `GenerateGroupKey`.
- `go-mknoon/crypto/group.go` implements `GenerateGroupKey()` by allocating `make([]byte, 32)`, filling it with `crypto/rand.Read`, and returning `base64.StdEncoding.EncodeToString(key)`.
- `go-mknoon/crypto/group_test.go` already has `TestGenerateGroupKey_Length`, `TestGenerateGroupKey_Unique`, and `TestSP003GroupKeysAndNoncesUseFreshRandomness`; together they prove nearby behavior, but they are not row-named for GK-001.
- `rg` found no existing `GK-001`, `GK001`, or `TestGK001` test outside this new plan file.
- `go-mknoon/bridge/bridge.go` exposes bridge `GenerateGroupKey()` by delegating to `mcrypto.GenerateGroupKey()`. `go-mknoon/bridge/bridge_test.go::TestGenerateGroupKey_ReturnsKey` only verifies a non-empty returned key; `TestSP003GroupCreateGeneratesFreshV4GroupIdsAndKeys` verifies group-created keys decode to 32 bytes and are unique across eight groups.
- `go-mknoon/node/group.go` documents `GroupKeyInfo.Key` as a base64 AES-256 key, and `go-mknoon/node/pubsub.go` consumes stored keys through `EncryptGroupMessage` / `DecryptGroupMessage`; these files are downstream consumers, not the key-generation seam.
- `go-mknoon/internal/group_envelope.go` and `lib/features/groups/application/group_offline_replay_envelope.dart` carry encrypted payloads and persisted key material, but they do not generate group keys. Their current tests are supporting context only for GK-001.
- Gate docs say `scripts/run_test_gates.sh` is canonical for named gates. The `groups` named gate applies when group send, receive, retry, resume, invite, or announcement behavior changes; GK-001 should not require that gate if implementation remains crypto-test-only.

## real scope

In scope:

- Add an exact row-named GK-001 unit test for `GenerateGroupKey()` in `go-mknoon/crypto/group_test.go`.
- The test must generate many keys, decode each with standard base64, assert each decoded key is exactly 32 bytes, and assert no duplicate key string appears across the sample.
- If the new test passes against current code, stop with tests-only evidence and do not change production code.

Out of scope:

- Do not edit Flutter application code, offline replay code, source matrix, breakdown, bridge APIs, node PubSub behavior, envelope formats, or group-key rotation behavior.
- Do not change `go-mknoon/crypto/group.go` unless the exact GK-001 regression fails and the failure proves `GenerateGroupKey()` no longer returns valid unique 32-byte base64 keys.
- Do not add broad randomness/statistical testing beyond deterministic validity, length, and duplicate checks.

## closure bar

GK-001 is good enough when a row-named unit regression proves that repeated `GenerateGroupKey()` calls return valid standard-base64 strings whose decoded byte length is 32 and whose generated values are unique across a bounded sample, and the focused crypto package command plus row-relevant broader Go sweep pass or any unrelated pre-existing failure is clearly classified.

## source of truth

- Primary source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-001`.
- Session decomposition source: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row `GK-001`.
- Current code and tests win over stale prose if they disagree.
- `scripts/run_test_gates.sh` wins for named gate membership if it disagrees with gate docs.
- This plan controls only the execution contract for GK-001; it must not update source matrix or breakdown state during implementation.

## session classification

`implementation-ready`

The session is tests-only. Current implementation appears correct, but exact row-named proof is missing.

## exact problem statement

The product behavior required by GK-001 is that group symmetric encryption keys generated by the Go crypto package are valid base64-encoded AES-256 material: every generated value decodes to exactly 32 bytes, and repeated generation does not reuse the same key. Current code appears to satisfy this, but the source row remains open because there is no exact GK-001 row-named regression. User-visible group encryption behavior must stay unchanged unless the new regression proves a real generator defect.

## files and repos to inspect next

Required before editing:

- `go-mknoon/crypto/group.go`
- `go-mknoon/crypto/group_test.go`
- `git status --short`

Supporting inspection only if the focused crypto regression fails or the reviewer asks for package-boundary proof:

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `test/features/groups/application/group_offline_replay_envelope_test.dart`

## existing tests covering this area

- `go-mknoon/crypto/group_test.go::TestGenerateGroupKey_Length` decodes one generated key and asserts 32 decoded bytes.
- `go-mknoon/crypto/group_test.go::TestGenerateGroupKey_Unique` asserts two generated key strings differ.
- `go-mknoon/crypto/group_test.go::TestSP003GroupKeysAndNoncesUseFreshRandomness` samples 64 generated keys, validates base64 decoding and 32 decoded bytes, and rejects duplicate key strings while also checking nonce/ciphertext freshness.
- `go-mknoon/bridge/bridge_test.go::TestGenerateGroupKey_ReturnsKey` verifies the bridge returns a non-empty `groupKey`, but it does not decode or length-check it.
- `go-mknoon/bridge/bridge_test.go::TestSP003GroupCreateGeneratesFreshV4GroupIdsAndKeys` verifies group-created keys decode to 32 bytes and are unique across eight groups.

Missing:

- No exact `GK-001` / `TestGK001...` test currently pins the source row.

## regression/tests to add first

Add one focused unit test in `go-mknoon/crypto/group_test.go`, near the existing `TestGenerateGroupKey_*` tests:

```go
func TestGK001GenerateGroupKeyReturns32ByteBase64AESKey(t *testing.T) {
    const samples = 128
    seen := make(map[string]struct{}, samples)

    for i := 0; i < samples; i++ {
        keyB64, err := GenerateGroupKey()
        if err != nil {
            t.Fatalf("GenerateGroupKey() #%d error: %v", i+1, err)
        }
        keyBytes, err := base64.StdEncoding.Strict().DecodeString(keyB64)
        if err != nil {
            t.Fatalf("GK-001 key #%d is not valid standard base64: %v", i+1, err)
        }
        if len(keyBytes) != 32 {
            t.Fatalf("GK-001 key #%d decoded length = %d, want 32", i+1, len(keyBytes))
        }
        if _, exists := seen[keyB64]; exists {
            t.Fatalf("GK-001 duplicate generated key at sample %d", i+1)
        }
        seen[keyB64] = struct{}{}
    }
}
```

This is the regression-first proof for the row. Run it before any production edit. If it passes, there is no product gap to fix.

## step-by-step implementation plan

1. Reconfirm `git status --short` and inspect `go-mknoon/crypto/group_test.go` for any concurrent edits. Do not overwrite unrelated changes.
2. Add `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` in `go-mknoon/crypto/group_test.go` next to existing `GenerateGroupKey` tests. Reuse the existing `encoding/base64` import.
3. Run the exact focused test command. If it passes, do not touch production code.
4. If and only if the focused test fails, inspect `go-mknoon/crypto/group.go` and fix only `GenerateGroupKey()` to restore the current intended behavior: 32 bytes from `crypto/rand` encoded with standard base64.
5. If the failure appears only at the bridge boundary, add optional bridge proof in `go-mknoon/bridge/bridge_test.go`; otherwise keep bridge untouched.
6. Run the broader row-relevant Go sweep and diff hygiene commands listed below.
7. Record results in the implementation handoff, but do not close or edit the source matrix or breakdown in this session.

## risks and edge cases

- Random duplicate false positives are cryptographically negligible at 128 samples, but the test must not attempt to statistically prove entropy quality.
- `base64.StdEncoding.Strict()` rejects malformed standard-base64 encodings while accepting the current generator output.
- A failure in `go-mknoon/bridge` or downstream group packages should not be treated as a key-generation failure unless the focused crypto regression also fails or package-boundary proof identifies a bridge serialization defect.
- The dirty worktree contains many unrelated edits; implementation must avoid formatting or sweeping files outside `go-mknoon/crypto/group_test.go` unless a proven RED requires a minimal production fix.

## exact tests and gates to run

Required focused command:

```bash
(cd go-mknoon && go test ./crypto -run 'TestGK001|TestGenerateGroupKey|TestSP003' -count=1)
```

Required broader row-relevant Go sweep if feasible:

```bash
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK001|TestGenerateGroupKey|TestSP003' -count=1)
```

Optional bridge boundary proof only if reviewer requests it or focused crypto evidence is not considered enough:

```bash
(cd go-mknoon && go test ./bridge -run 'TestGenerateGroupKey|TestSP003GroupCreateGeneratesFreshV4GroupIdsAndKeys' -count=1)
```

Diff hygiene:

```bash
git diff --check
```

Named Flutter `groups` gate is not required for a crypto-test-only implementation. Run `./scripts/run_test_gates.sh groups` only if execution changes group send, receive, retry, resume, invite, or announcement behavior, which this plan explicitly forbids unless a focused RED proves broader product impact.

## known-failure interpretation

- Any failure in `go-mknoon/crypto` for `TestGK001...`, `TestGenerateGroupKey_*`, or `TestSP003GroupKeysAndNoncesUseFreshRandomness` is a GK-001 blocker.
- Any failure in the broader Go sweep outside the row-focused selectors must be triaged against current dirty worktree state and existing package behavior before being attributed to GK-001.
- Pre-existing or unrelated Flutter gate failures do not block GK-001 if this session only changes `go-mknoon/crypto/group_test.go` and all required Go commands plus `git diff --check` pass.

## done criteria

- `go-mknoon/crypto/group_test.go` contains an exact row-named GK-001 test.
- The test proves valid standard base64, 32 decoded bytes, and uniqueness across repeated calls.
- No production code changed unless the focused GK-001 regression failed first and the fix is limited to `GenerateGroupKey()`.
- Required focused Go command passes.
- Required broader row-relevant Go sweep passes or any unrelated failure is documented with evidence.
- `git diff --check` passes or any failure is clearly unrelated to GK-001 and pre-existing.
- Source matrix and breakdown remain untouched by this session.

## scope guard

Do not use GK-001 to refactor crypto helpers, replace randomness primitives, redesign key epochs, alter group envelope schema, alter Flutter offline replay, update Go bridge JSON shape, or add simulator/device tests. Do not close GK-001 in the source matrix or breakdown during implementation. The only planned file edit is `go-mknoon/crypto/group_test.go`, with `go-mknoon/crypto/group.go` allowed only after a focused RED proves it necessary.

## accepted differences / intentionally out of scope

- Bridge-level proof is optional because the source row names `GenerateGroupKey` behavior and the direct generation seam lives in `go-mknoon/crypto`.
- Flutter offline replay and Go internal envelope tests are intentionally out of scope because they consume already-stored key material or encrypted payloads rather than generating keys.
- Integration evidence is recommended by the matrix, not required; for this tests-only row, the broader Go package sweep is sufficient unless reviewer demands bridge-boundary proof.

## dependency impact

Later GK and encryption-envelope rows can rely on GK-001 only for the invariant that generated group keys are standard-base64 AES-256 material and are not reused across a bounded sample. If the exact GK-001 test fails and forces a production fix, downstream group encryption, PubSub validation, bridge group creation, and offline replay rows should rerun their own direct checks before claiming dependent closure.

## Reviewer Findings

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none structurally missing. The direct row-owned test is specified in `go-mknoon/crypto/group_test.go`; focused, broader Go, optional bridge, and diff-hygiene commands are exact.

Stale or incorrect assumptions: none found. The plan treats current implementation as evidence, not as closure, because exact row-named proof is missing.

Overengineering: none. Optional bridge proof is correctly conditional; Flutter/offline replay and simulator evidence are out of scope unless a focused RED proves broader product impact.

Decomposition clarity: sufficient. The implementer can add one test, run exact commands, and stop if green.

Minimum needed to make sufficient: already met; no patch required beyond this reviewer record.

## Arbiter Decision

Structural blockers: none.

Incremental details:

- Optional bridge-level proof can be run if a later reviewer wants package-boundary confidence, but it is not required for the direct GK-001 source row.
- The broader Go sweep may expose unrelated node/internal failures in the current dirty worktree; those should be classified rather than silently ignored.

Accepted differences:

- This session intentionally does not update source matrix or breakdown status.
- This session intentionally does not add Flutter, simulator, offline replay, or envelope tests.
- Integration evidence is treated as recommended, not required, unless a focused RED proves broader product impact.

Final arbiter verdict: `arbiter-pass`; the plan is execution-safe and promoted to `Status: execution-ready`.

## Execution Progress

| Timestamp | Role | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 02:22:02 CEST | Executor started | This plan; `go-mknoon/crypto/group.go`; `go-mknoon/crypto/group_test.go`; `git status --short`. | Contract extracted: tests-only GK-001 row proof; dirty worktree has unrelated changes outside owner files; no production edit justified before focused RED. | Add exact row-named regression in `go-mknoon/crypto/group_test.go`. |
| 2026-05-12 02:22:02 CEST | Executor edited | `go-mknoon/crypto/group_test.go`; this plan. | Added `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` using strict standard base64 decode, 32-byte decoded-length assertion, and 128-sample uniqueness map. | Run required focused Go command. |
| 2026-05-12 02:23:11 CEST | Executor verified | `go-mknoon/crypto/group_test.go`. | `gofmt -w go-mknoon/crypto/group_test.go` completed; focused command passed: `ok github.com/mknoon/go-mknoon/crypto 0.410s`. | Run required broader Go sweep. |
| 2026-05-12 02:23:11 CEST | Executor verified | `go-mknoon/node`; `go-mknoon/internal`; `go-mknoon/crypto`. | Broader command passed: `ok github.com/mknoon/go-mknoon/node 4.821s`; `ok github.com/mknoon/go-mknoon/internal 0.278s`; `ok github.com/mknoon/go-mknoon/crypto 0.452s`. | Run diff hygiene. |
| 2026-05-12 02:23:11 CEST | Executor completed | `go-mknoon/crypto/group_test.go`; this plan. | `git diff --check` passed. No source matrix, session breakdown, production code, bridge, node, internal, Flutter, or unrelated files were edited by this Executor pass. | Hand off to separate QA Reviewer. |
| 2026-05-12 02:25:43 CEST | QA Reviewer completed | This plan; `go-mknoon/crypto/group.go`; `go-mknoon/crypto/group_test.go`; scoped diffs; required Go and diff-hygiene commands. | QA pass: exact GK-001 test is row-named and proves strict standard-base64 decode, 32 decoded bytes, and 128-sample uniqueness; required commands passed; no GK-001 production/source-matrix/breakdown edit found. | Final verdict: `tests-only accepted`. |

## Execution Verdict

Executor verdict: `completed_for_qa`.

Evidence:

- Added exact row-named test `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` in `go-mknoon/crypto/group_test.go`.
- The test generates 128 keys, decodes each with `base64.StdEncoding.Strict()`, asserts each decoded key is 32 bytes, and rejects duplicate key strings across the sample.
- Required focused command passed: `(cd go-mknoon && go test ./crypto -run 'TestGK001|TestGenerateGroupKey|TestSP003' -count=1)`.
- Required broader command passed: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK001|TestGenerateGroupKey|TestSP003' -count=1)`.
- Diff hygiene passed: `git diff --check`.
- Production code changed: no.
- Blockers: none from the Executor pass.

## QA Result

Final QA verdict: `tests-only accepted`.

Evidence:

- Verified `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` is exact row-named and checks `base64.StdEncoding.Strict().DecodeString`, decoded length `32`, and no duplicate key string across 128 generated samples.
- Reran required focused command: `(cd go-mknoon && go test ./crypto -run 'TestGK001|TestGenerateGroupKey|TestSP003' -count=1)` -> `ok github.com/mknoon/go-mknoon/crypto 0.397s`.
- Reran required broader command: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK001|TestGenerateGroupKey|TestSP003' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 4.602s`; `ok github.com/mknoon/go-mknoon/internal 0.173s`; `ok github.com/mknoon/go-mknoon/crypto 0.349s`.
- Reran `git diff --check` -> passed with no output.
- GK-001 scoped diff is tests-only in `go-mknoon/crypto/group_test.go` plus this plan note. Current source matrix and breakdown dirty diffs were inspected for GK-001 and do not close or mutate the GK-001 source row for this execution.
- Blocking issues: none.
- Fix pass required: no.
