# GK-002 Session Plan: Encrypt/decrypt round-trip for text payload

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 02:34:50 CEST | Planner completed | Same evidence set; no new production files required for the draft | Draft plan written as tests-only, regression-first work with explicit no-GK-003 drift and no Flutter/offline-replay expansion. | Run strict sufficiency review. |
| 2026-05-12 02:36:00 CEST | Reviewer started | Draft plan, mandatory section checklist, direct evidence from source matrix/breakdown/code/tests/gates | Review targets: missing closure bar, missing regression-first rule, weak stop rule, stale gate assumptions, or GK-003 scope drift. | Decide whether adjustments are structural or incremental. |
| 2026-05-12 02:36:00 CEST | Reviewer completed | Same draft and evidence set | Plan is sufficient as-is for tests-only execution. No structural blockers found; only incremental implementation details remain. | Send to Arbiter for final classification. |
| 2026-05-12 02:36:32 CEST | Arbiter started | Reviewer pass, draft plan, scope guard, regression contract, gate list | Review findings are being classified as structural blockers, incremental details, or accepted differences. | Finalize execution readiness if no structural blocker exists. |
| 2026-05-12 02:36:49 CEST | Arbiter completed | Reviewer pass, final mandatory sections, scope guard, known-failure interpretation, exact gate contract | No structural blockers remain. Incremental detail is documented; accepted differences are explicit. Stop rule reached. | Plan is reusable for GK-002 execution. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 02:38:25 CEST | Executor contract extracted | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-002-plan.md`, `go-mknoon/crypto/group_test.go`, worktree status | Scope is tests-only unless the focused GK-002 regression proves a crypto production defect; worktree has unrelated dirty files and existing GK-001 changes to preserve. | Add exact GK-002 row-named unit test and run required evidence. |
| 2026-05-12 02:39:35 CEST | Executor implementation completed | `go-mknoon/crypto/group_test.go`, this plan | Added `TestGK002EncryptDecryptRoundTripForTextPayload`; preserved existing GK-001 coverage; no production files inspected or changed. | Record required command evidence and hand off for QA review. |
| 2026-05-12 02:39:35 CEST | Focused Go selector finished | `go-mknoon/crypto/group_test.go` | `(cd go-mknoon && go test ./crypto -run 'TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` passed: `ok github.com/mknoon/go-mknoon/crypto 0.443s`. | Run broader Go sweep. |
| 2026-05-12 02:39:35 CEST | Broader Go sweep finished | `go-mknoon/crypto/group_test.go` | `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` passed for `node` 4.569s, `internal` 0.835s, and `crypto` 0.198s. | Run diff hygiene. |
| 2026-05-12 02:39:35 CEST | Diff hygiene finished | `go-mknoon/crypto/group_test.go`, this plan | `git diff --check` passed with no output. | Write executor verdict. |

## real scope

GK-002 owns only the row "Encrypt/decrypt round-trip for text payload." The implementation session should add an exact row-named Go crypto unit test proving that a valid generated group key can encrypt a JSON/text payload, decrypt it, and recover the exact original string bytes.

Expected code surface:

- Primary test file: `go-mknoon/crypto/group_test.go`, placed near `TestGroupEncryptDecrypt_RoundTrip`.
- Production file to inspect only if the regression fails: `go-mknoon/crypto/group.go`.

This session does not own key generation invariants already closed by GK-001, nonce uniqueness/ciphertext uniqueness owned by GK-003, invalid-key handling owned by GK-004, node/pubsub delivery, Flutter replay envelopes, bridge code, or simulator evidence.

## closure bar

GK-002 is good enough when there is a deterministic, exact row-named unit test such as `TestGK002EncryptDecryptRoundTripForTextPayload` that:

- calls `GenerateGroupKey()` to obtain a valid group key;
- encrypts a JSON/text payload through `EncryptGroupMessage(groupKeyB64, payload)`;
- asserts ciphertext and nonce strings are non-empty;
- strict-decodes ciphertext and nonce with `base64.StdEncoding.Strict()` and asserts decoded ciphertext is non-empty;
- asserts the decoded nonce length is exactly 12 bytes as basic validity for the round trip;
- decrypts through `DecryptGroupMessage(groupKeyB64, ctB64, nonceB64)`;
- compares exact string bytes, preferably with `bytes.Equal([]byte(decrypted), []byte(payload))` plus a clear failure message.

No production change is required if this test passes against current `group.go`.

## source of truth

- Source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GK-002 is authoritative for scenario, priority, expected result, and required unit coverage.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` row GK-002 is authoritative for session classification and expected plan path.
- Current code and tests win over stale prose for actual behavior and available seams.
- `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/test-gates-reference.md`, and `scripts/run_test_gates.sh` are authoritative only for named Flutter gates; GK-002 should prefer direct Go commands unless implementation evidence expands the scope.

## session classification

`implementation-ready`.

The breakdown classifies GK-002 as `needs_tests_only` / `implementation-ready`. Evidence supports that classification: `go-mknoon/crypto/group.go` already has direct encrypt/decrypt APIs, and `go-mknoon/crypto/group_test.go` has adjacent generic coverage but no exact row-named GK-002 proof.

## exact problem statement

The missing coverage is not a known production defect yet. GK-002 is open because the matrix requires row-owned proof that group message encryption and decryption preserve a JSON/text payload exactly with a valid group key.

User-visible behavior protected by this row: group chat text payloads must not be corrupted, truncated, re-encoded, or changed during AES-GCM encryption and decryption.

Must stay unchanged unless RED proves otherwise:

- the public signatures of `EncryptGroupMessage` and `DecryptGroupMessage`;
- AES-256-GCM behavior and standard base64 encoding in `go-mknoon/crypto/group.go`;
- GK-001 key generation behavior and GK-003 nonce uniqueness behavior;
- Flutter/offline replay behavior and Go node/pubsub delivery behavior.

## files and repos to inspect next

- `go-mknoon/crypto/group_test.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/go.mod`
- If the broader breakdown-suggested Go sweep fails: inspect only the failing package/test files named by `go test`, likely under `go-mknoon/node` or `go-mknoon/internal`.
- Do not inspect or edit Flutter files unless a concrete failure proves GK-002 cannot be validated at the crypto unit seam.

## existing tests covering this area

Existing adjacent tests in `go-mknoon/crypto/group_test.go`:

- `TestGroupEncryptDecrypt_RoundTrip` covers generic text encrypt/decrypt and non-empty ciphertext/nonce.
- `TestGroupEncryptDecrypt_WrongKey`, `TestGroupEncryptDecrypt_TamperedCiphertext`, and `TestGroupEncryptDecrypt_TamperedNonce` cover authentication failure behavior.
- `TestGroupEncryptDecrypt_UniqueNonces` and `TestSP003GroupKeysAndNoncesUseFreshRandomness` cover nonce freshness; keep GK-002 out of uniqueness assertions.
- `TestGroupEncryptDecrypt_EmptyString` and `TestGroupEncryptDecrypt_LargeMessage` cover other payload sizes.
- `TestGK001GenerateGroupKeyReturns32ByteBase64AESKey` was just added for GK-001 and proves valid generated key shape; do not modify or revert it.

Missing coverage:

- no exact row-named `GK-002` test was found.
- existing round-trip coverage uses a generic sentence, not the matrix's JSON/text payload row ownership.

## regression/tests to add first

Add the regression first in `go-mknoon/crypto/group_test.go`, near `TestGroupEncryptDecrypt_RoundTrip`:

- name it `TestGK002EncryptDecryptRoundTripForTextPayload`;
- use a stable ASCII JSON payload, for example `{"type":"text","body":"GK-002 exact round trip","meta":{"line":1,"urgent":false}}`;
- generate the key with `GenerateGroupKey()`;
- call `EncryptGroupMessage`;
- fail if ciphertext or nonce is empty;
- strict-decode ciphertext and nonce with `base64.StdEncoding.Strict()`;
- assert decoded ciphertext length is greater than zero;
- assert decoded nonce length is exactly 12 bytes;
- call `DecryptGroupMessage`;
- compare exact string bytes with `bytes.Equal([]byte(decrypted), []byte(payload))`.

If this test is RED because of current product behavior, stop and inspect `go-mknoon/crypto/group.go` before changing anything else. If it is GREEN, keep the session tests-only and do not touch production code.

## step-by-step implementation plan

1. Confirm the worktree still has existing GK-001/user edits and do not revert them.
2. Edit only `go-mknoon/crypto/group_test.go` to add `TestGK002EncryptDecryptRoundTripForTextPayload` near the existing round-trip test.
3. Add only the minimal imports required by that test, expected to be `bytes` if exact byte comparison is used; keep existing imports and GK-001 changes intact.
4. Run the focused crypto selector:
   `(cd go-mknoon && go test ./crypto -run 'TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)`
5. If the focused selector fails only at the new GK-002 regression, inspect `go-mknoon/crypto/group.go` and make the smallest production fix required to preserve exact plaintext. Rerun the focused selector.
6. If the focused selector passes, do not change production code.
7. Run the broader Go sweep from the breakdown if feasible:
   `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)`
8. Run `git diff --check`.
9. Stop after proof and report GK-002 evidence. Do not update source matrix or breakdown in this execution session unless a separate closure-writing task explicitly asks for it.

## risks and edge cases

- JSON payload exactness: the test must pass the string through the crypto API without parsing or reserializing JSON, so whitespace, quotes, and byte order stay identical.
- Base64 validity: ciphertext and nonce should be strict-decodable because `group.go` uses `base64.StdEncoding.EncodeToString`.
- Nonce length: asserting 12 decoded bytes is basic AES-GCM validity for this round trip.
- Nonce uniqueness: repeated encryption uniqueness belongs to GK-003 and should not be added here.
- Existing dirty GK-001 test changes: preserve them; do not reorder or rewrite adjacent tests beyond the minimal insert/import change.

## exact tests and gates to run

Required focused gate:

```sh
(cd go-mknoon && go test ./crypto -run 'TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)
```

Broader Go sweep, if feasible:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Optional only if implementation evidence unexpectedly reaches Flutter/offline replay surfaces:

```sh
flutter test test/features/groups/application/group_offline_replay_envelope_test.dart
```

Do not run simulator/device gates for GK-002 unless a concrete non-unit failure proves the direct crypto unit seam is insufficient.

## known-failure interpretation

- Treat failures in the new `TestGK002EncryptDecryptRoundTripForTextPayload` as GK-002 blocking evidence.
- Treat failures in existing `TestGroupEncryptDecrypt*`, `TestGK001*`, or `TestSP003*` as adjacent crypto regressions that must be understood before claiming GK-002 closure.
- Treat failures in `go-mknoon/node`, `go-mknoon/internal`, or Flutter optional tests as scope-expansion evidence only if they directly involve group encrypt/decrypt round-trip behavior. Otherwise record them as pre-existing or unrelated and do not patch them under GK-002.
- If `git diff --check` reports whitespace in files not touched by the GK-002 executor, record it as unrelated dirty-worktree evidence and do not rewrite those files without explicit scope.

## done criteria

- Exact row-named GK-002 unit test exists in `go-mknoon/crypto/group_test.go`.
- The test generates a valid key, encrypts JSON/text, validates non-empty strict-base64 ciphertext and 12-byte nonce, decrypts, and compares exact plaintext bytes.
- Required focused Go command passes.
- Broader Go sweep is run and passes, or a concrete reason is recorded if not feasible.
- `git diff --check` passes for GK-002 changes, or unrelated existing whitespace failures are documented without being rewritten.
- No production code changed unless the new RED test proved a real round-trip defect.

## scope guard

Do not:

- modify the source matrix, breakdown, closure ledger, or unrelated plan files during GK-002 execution;
- rewrite GK-001 tests or revert existing dirty work;
- add nonce uniqueness sampling, duplicate detection, or multi-encryption randomness assertions; that is GK-003;
- add invalid-key/error-path tests; that is GK-004 and later GK rows;
- change Flutter offline replay, Go pubsub, group membership, simulator harnesses, or notification behavior;
- replace AES-GCM, change API signatures, or introduce new crypto abstractions without a failing GK-002 regression proving current behavior cannot satisfy the row.

Overengineering for GK-002 includes integration harness work, device proof, JSON parsing/reformatting, generalized crypto helpers, or broad module rewrites when the row asks for an exact round-trip proof.

## accepted differences / intentionally out of scope

- The matrix marks integration as Recommended, not Required. GK-002 can close through row-owned crypto unit evidence if the focused and feasible broader Go checks pass.
- Existing generic `TestGroupEncryptDecrypt_RoundTrip` remains valuable but is not row-named; GK-002 intentionally adds row-owned coverage rather than renaming or replacing the generic test.
- Basic nonce base64 and 12-byte length validation is in scope because it is needed to verify the round-trip artifacts are valid. Nonce uniqueness and ciphertext uniqueness are intentionally out of scope for GK-003.
- Flutter offline replay envelope tests are optional fallback evidence only; the direct source row points to `group.go` and the core behavior is in Go crypto.

## dependency impact

- GK-003 should build on this by proving fresh nonce/ciphertext behavior for repeated encryption without reopening exact plaintext round-trip semantics.
- GK-004 and later invalid-input rows should build on the same crypto seam without altering the GK-002 happy-path proof.
- If GK-002 unexpectedly requires production changes, rerun GK-001/GK-003-adjacent crypto selectors and revisit later GK rows for assumptions about encoding and nonce behavior.

## reviewer pass

Sufficiency: sufficient as-is.

Missing files, tests, regressions, or gates: none structural. The plan names the direct crypto test file, the production file to inspect only on RED, the focused Go selector, the broader Go sweep, optional Flutter fallback evidence, and diff hygiene.

Stale or incorrect assumptions: none found. The plan treats current code/tests as authoritative and keeps source matrix/breakdown as scope authority.

Overengineering: none found. The plan explicitly rejects simulator work, Flutter replay changes, generalized crypto abstractions, nonce uniqueness sampling, and unrelated invalid-input rows.

Decomposition quality: sufficient. The executor can add one row-named unit test first and stop if it passes; production changes are gated by a failing GK-002 regression.

Minimum needed to make the plan sufficient: no structural patch required. Incremental detail only: when implementing, keep the JSON payload stable and ASCII so exact-byte comparison is unambiguous in the Go test source.

## arbiter decision

Structural blockers: none.

Incremental details: keep the payload stable and ASCII during implementation, and place the test near `TestGroupEncryptDecrypt_RoundTrip` to preserve local readability.

Accepted differences: integration evidence remains Recommended, not Required; exact row-owned Go crypto unit proof is sufficient unless a concrete failure proves the need for broader product evidence. Basic nonce strict-base64 and 12-byte length checks remain in GK-002; nonce uniqueness remains deferred to GK-003.

Stop rule: reviewer found no structural blocker, so no fix loop is needed. This plan is execution-ready.

## Execution Verdict

Executor verdict: complete and ready for separate QA Reviewer.

Evidence:

- Added exact row-named unit test `TestGK002EncryptDecryptRoundTripForTextPayload` in `go-mknoon/crypto/group_test.go` near `TestGroupEncryptDecrypt_RoundTrip`.
- The test uses a stable ASCII JSON/text payload, generates a valid key, encrypts with `EncryptGroupMessage`, asserts non-empty ciphertext and nonce, strict-base64 decodes both artifacts, asserts decoded ciphertext is non-empty, asserts decoded nonce length is exactly 12 bytes, decrypts with `DecryptGroupMessage`, and compares exact plaintext bytes with `bytes.Equal`.
- Preserved existing GK-001 test coverage in the same file.
- Production code changed: no.
- Required focused command passed: `(cd go-mknoon && go test ./crypto -run 'TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` -> `ok github.com/mknoon/go-mknoon/crypto 0.443s`.
- Required broader Go sweep passed: `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 4.569s`; `ok github.com/mknoon/go-mknoon/internal 0.835s`; `ok github.com/mknoon/go-mknoon/crypto 0.198s`.
- Diff hygiene passed: `git diff --check`.
- Blockers: none found by Executor.
- QA Reviewer role: not performed in this Executor-only pass.

## QA Result

| Timestamp | Role | Files inspected | Decision/blocker | Final verdict |
| --- | --- | --- | --- | --- |
| 2026-05-12 02:42:30 CEST | QA Reviewer | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-002-plan.md`, `go-mknoon/crypto/group_test.go`, scoped `git diff`, GK-002 source matrix and breakdown references | No blockers. `TestGK002EncryptDecryptRoundTripForTextPayload` is exact row-named and proves valid generated key -> JSON/text encrypt -> non-empty strict-base64 ciphertext/nonce -> 12-byte nonce -> decrypt -> exact plaintext bytes. It does not add repeated-encryption uniqueness or ciphertext uniqueness sampling. Scoped GK-002 changes are tests-only plus this plan; unrelated dirty source matrix/breakdown and production files remain outside GK-002 execution scope. Required reruns passed: `(cd go-mknoon && go test ./crypto -run 'TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` -> `ok github.com/mknoon/go-mknoon/crypto 0.291s`; `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|UpdateGroupKey|GroupEnvelope|GroupMessage|DecryptionFailed|TestGK002|TestGroupEncryptDecrypt|TestGK001' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 4.463s`, `ok github.com/mknoon/go-mknoon/internal 0.631s`, `ok github.com/mknoon/go-mknoon/crypto 0.201s`; `git diff --check` passed with no output. | tests-only accepted |
