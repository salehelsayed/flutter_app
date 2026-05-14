# GK-010 Envelope Parser Missing GroupId Plan

Status: accepted/closed

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-12 07:01:26 CEST | Planner completed | Full draft plan sections, exact test shape, exact Go commands, named-gate decision, scope guard, and known-failure interpretation | Draft is implementation-ready for committed gap closure. Expected executor diff is tests-only in `go-mknoon/internal/group_envelope_test.go`; production code is conditional on the row-named regression proving the existing guard insufficient. | Run reviewer pass for sufficiency, stale assumptions, missing gates, and scope drift. |
| 2026-05-12 07:03:19 CEST | Reviewer started | Full draft plan, mandatory section checklist, source row semantics, breakdown classification, and current parser/validator evidence | Review focus: direct proof sufficiency, conditional production scope, named-gate decision, known-failure interpretation, and exclusion of GK-011/GK-015. | Write reviewer findings and determine whether structural changes are required. |
| 2026-05-12 07:03:47 CEST | Reviewer completed | Full draft plan and mandatory sections | Sufficient as-is. No structural blockers: direct row-named parser regression is enough, production scope is conditional, exact Go commands are present, named Flutter gate omission is justified for internal-test-only work, and GK-011/GK-015 are explicitly excluded. | Run arbiter classification and stop-rule decision. |
| 2026-05-12 07:04:17 CEST | Arbiter started | Reviewer notes, full plan, closure bar, scope guard, exact commands, accepted differences, and dependency impact | Arbiter focus: classify findings into structural blockers, incremental details, and accepted differences; apply stop rule. | Finalize status if no structural blocker remains. |
| 2026-05-12 07:04:41 CEST | Arbiter completed | Reviewer findings and final plan sections | No structural blockers remain; no patch loop required. Incremental details are implementation-time only, and accepted differences are documented. | Plan is execution-ready for GK-010 only. |

## Execution Progress

| Timestamp | Role | Files inspected or touched | Command/evidence | Decision/blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-12 07:06:24 CEST | Executor contract extracted | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-010-plan.md`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go` | `git status --short`; parser and validator references inspected | Scope is GK-010 test-only unless the regression exposes a parser defect; unrelated dirty work is present and preserved. | Add row-owned regression near missing-fields parser tests. |
| 2026-05-12 07:06:24 CEST | Executor implementation | `go-mknoon/internal/group_envelope_test.go`, GK-010 plan file | Added `TestGK010ParseGroupEnvelopeRejectsMissingGroupID` and `strings` import. | Production parser already has the required missing-`groupId` guard; `go-mknoon/internal/group_envelope.go` not touched. | Run required gofmt, focused selector, broader Go sweep, and diff hygiene. |
| 2026-05-12 07:08:12 CEST | Executor validation | `go-mknoon/internal/group_envelope_test.go` | `(cd go-mknoon && gofmt -w internal/group_envelope_test.go)` exited 0. | Formatting completed without output. | Run focused selector. |
| 2026-05-12 07:08:12 CEST | Executor validation | `go-mknoon/internal/group_envelope_test.go` | `(cd go-mknoon && go test ./internal -run '^(TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestParseGroupEnvelope_InvalidJSON|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)` -> `ok github.com/mknoon/go-mknoon/internal 0.404s`. | Focused GK-010 and adjacent parser selector passed. | Run broader Go parser/validator sweep. |
| 2026-05-12 07:08:12 CEST | Executor validation | `go-mknoon/node`, `go-mknoon/internal`, `go-mknoon/crypto` | `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupEnvelope|GroupTopicValidator|GroupMessage|DecryptionFailed|UpdateGroupKey|BuildGroupSignatureData|Sign' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 9.606s`; `ok github.com/mknoon/go-mknoon/internal 0.441s`; `ok github.com/mknoon/go-mknoon/crypto 0.308s`. | Broader Go parser/validator sweep passed. | Run diff hygiene. |
| 2026-05-12 07:08:12 CEST | Executor validation | Worktree diff | `git diff --check` exited 0. | Diff hygiene passed. | Write final execution verdict. |
| 2026-05-12 07:08:12 CEST | Executor completed | `go-mknoon/internal/group_envelope_test.go`, GK-010 plan file | Final diff reviewed; `git status --short` shows this execution touched only the row-owned test and untracked GK-010 plan. | GK-010 done criteria met; no blocker. | Stop. |
| 2026-05-12 07:11:29 CEST | QA Reviewer started | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-010-plan.md`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/internal/group_envelope.go`, source matrix GK-010 row, breakdown GK-010 rows | Scoped diff and current/HEAD row state inspected. `go-mknoon/internal/group_envelope.go` has no diff; source matrix and breakdown closure rows had not yet been advanced by the closure writer. | Landed test matches scope: v3-looking JSON has `version`/`type` and omits `groupId`; assertions require `env == nil`, `err != nil`, and error text containing both `parse group envelope` and `missing groupId`. | Rerun required commands independently. |
| 2026-05-12 07:11:29 CEST | QA Reviewer validation | `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/internal/group_envelope.go`, worktree diff | `(cd go-mknoon && go test ./internal -run '^(TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestParseGroupEnvelope_InvalidJSON|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)` -> `ok github.com/mknoon/go-mknoon/internal 0.302s`; `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupEnvelope|GroupTopicValidator|GroupMessage|DecryptionFailed|UpdateGroupKey|BuildGroupSignatureData|Sign' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 9.055s`; `ok github.com/mknoon/go-mknoon/internal 0.171s`; `ok github.com/mknoon/go-mknoon/crypto 0.634s`; `git diff --check` exited 0. | Required QA commands passed. No blocking or non-blocking findings. | Write final QA verdict. |
| 2026-05-12 07:11:29 CEST | Final QA verdict | GK-010 scoped test diff and plan file | `accepted` | Sufficiency rule met: required regression exists, required commands passed, production parser unchanged, and source matrix/breakdown closure rows for GK-010 were not advanced. | Stop. |

## Evidence Collector Notes

- Source matrix row `GK-010` is now `Covered`: "Envelope parser rejects missing groupId." Preconditions are JSON with `version` and `type` but no `groupId`; steps are parse and validate; expected result is `ParseGroupEnvelope` returns a missing `groupId` error. Unit is `Required`, Integration is `Recommended`, Fake Network/3-Party E2E/Perf are `N/A`, Race is `Recommended`, and the closure evidence is the row-named internal parser regression plus executor, QA, fresh-audit, and diff-hygiene proof.
- Session breakdown row `GK-010` is now `covered/accepted` and still owns exactly source row GK-010. The accepted proof is the missing-`groupId` parser contract, not GK-011 missing-`senderId` or other malformed-envelope rows.
- `go-mknoon/internal/group_envelope.go::ParseGroupEnvelope` unmarshals JSON into `GroupEnvelope`, wraps JSON errors with `parse group envelope`, and currently returns `nil, fmt.Errorf("parse group envelope: missing groupId")` when `env.GroupId == ""`.
- `go-mknoon/internal/group_envelope_test.go::TestParseGroupEnvelope_MissingFields` already passes for a missing-`groupId` envelope, but it only checks `err != nil`; it is not row-named and does not assert no envelope is returned or that the error contains both `parse group envelope` and `missing groupId`.
- Existing focused evidence passed: `(cd go-mknoon && go test ./internal -run '^TestParseGroupEnvelope_MissingFields$' -count=1)` returned `ok github.com/mknoon/go-mknoon/internal 0.386s`.
- `go-mknoon/internal/group_envelope.go::IsGroupEnvelope` intentionally peeks only `version` and `type`. JSON with `version:"3"` and `type:"group_message"` but no `groupId` can still be recognized as a group envelope, after which `ParseGroupEnvelope` must reject it.
- `go-mknoon/node/pubsub.go::groupTopicValidator` calls `IsGroupEnvelope`, then `ParseGroupEnvelope`, then rejects parser errors as `invalid_envelope`; `go-mknoon/node/pubsub_test.go` mirrors that behavior in the pure `validateGroupEnvelope` helper.
- The worktree was already dirty before this planning task. Execution must preserve unrelated edits and should touch only the GK-010 plan and the minimal row-owned test file unless the regression exposes a real production defect.

## real scope

Own exactly source matrix row GK-010: prove the Go group envelope parser rejects JSON that has the v3 envelope discriminator fields (`version` and `type`) but omits `groupId`.

In scope for execution:

- Add one row-named internal Go regression, `TestGK010ParseGroupEnvelopeRejectsMissingGroupID`, in `go-mknoon/internal/group_envelope_test.go`.
- Build a JSON string with `version:"3"` and `type:"group_message"` and otherwise plausible fields, but no `groupId`.
- Call `ParseGroupEnvelope`.
- Assert the returned envelope is `nil`.
- Assert an error is returned.
- Assert `err.Error()` contains both `parse group envelope` and `missing groupId`.
- Preserve existing parser behavior for valid round trips, invalid JSON, and `IsGroupEnvelope`.
- Change `go-mknoon/internal/group_envelope.go` only if the new row-named regression proves the current guard is insufficient.

Out of scope:

- Do not update source matrix or session breakdown closure rows in this planning task.
- Do not implement GK-011 missing-`senderId`, GK-015 group mismatch, or other malformed-envelope rows.
- Do not change `IsGroupEnvelope` to require `groupId`; GK-010 is about `ParseGroupEnvelope`.
- Do not add Flutter, bridge, offline replay, simulator, fake-network, or UI tests for the expected internal parser proof.
- Do not change PubSub validator reason strings unless the parser regression proves that the parser cannot surface the missing-`groupId` error.

## closure bar

GK-010 is good enough when the repo has row-owned evidence that:

- `ParseGroupEnvelope` rejects v3 group envelope JSON with no `groupId`.
- The parser returns no envelope on that failure.
- The parser error includes the parser context `parse group envelope`.
- The parser error includes the field-specific text `missing groupId`.
- Existing parser tests for valid envelopes, invalid JSON, and envelope discrimination still pass.
- Focused `./internal` Go tests, broader Go parser/validator sweep, and `git diff --check` pass, or any unrelated pre-existing failures are isolated with exact command output.
- No production code changes are made unless the row-named regression fails against the current parser guard for a real implementation reason.

## source of truth

- Current code and tests win over stale docs.
- Source row `GK-010` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` is the row contract.
- Breakdown row/session `GK-010` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is the session contract and now records this row as `covered/accepted`.
- `go-mknoon/internal/group_envelope.go` is authoritative for `ParseGroupEnvelope`, `IsGroupEnvelope`, `GroupEnvelope`, and parser error text.
- `go-mknoon/internal/group_envelope_test.go` is authoritative for direct parser coverage.
- `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go` are adjacent evidence for how parser failures flow into live and pure validator rejection, but they are not expected write surfaces for GK-010.
- `Test-Flight-Improv/test-gate-definitions.md` documents named gates; `scripts/run_test_gates.sh` wins if gate docs and script disagree.

## session classification

accepted/closed.

This is closed as implementation-committed gap closure because the row-named regression was added and the source matrix plus breakdown now carry concrete `Covered` / `covered/accepted` evidence. Current production code already satisfied the parser guard, so the accepted execution is tests-only row-owned proof with no `go-mknoon/internal/group_envelope.go` diff.

## exact problem statement

GK-010 is closed because the repository now has an exact row-named regression proving the parser returns no envelope and emits the expected field-specific parser error when the JSON still looks like a v3 group envelope by `version` and `type`.

User-visible behavior protected by this row: malformed group messages without a group id must fail closed before validator membership, key, or decrypt paths can treat them as valid group content. Behavior that must stay unchanged: valid group envelopes still parse, invalid JSON still fails as a parse error, and `IsGroupEnvelope` remains a lightweight discriminator over `version` and `type`.

## files and repos to inspect next

Before editing:

- `git status --short`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`

Expected write surface:

- `go-mknoon/internal/group_envelope_test.go`

Fallback-only if the new regression fails due to real parser behavior:

- `go-mknoon/internal/group_envelope.go`

Do not inspect or edit Flutter/Dart files for the expected GK-010 parser proof.

## existing tests covering this area

- `go-mknoon/internal/group_envelope_test.go::TestMarshalParseGroupEnvelope_RoundTrip` proves valid envelopes marshal and parse with all current fields.
- `go-mknoon/internal/group_envelope_test.go::TestParseGroupEnvelope_InvalidJSON` proves invalid JSON returns an error.
- `go-mknoon/internal/group_envelope_test.go::TestParseGroupEnvelope_MissingFields` uses a missing-`groupId` envelope and passes, but only checks that an error exists.
- `go-mknoon/internal/group_envelope_test.go::TestIsGroupEnvelope_V3GroupMessage` proves version/type detection for valid v3 group messages.
- `go-mknoon/internal/group_envelope_test.go::TestIsGroupEnvelope_V1Message`, `TestIsGroupEnvelope_V2Message`, and `TestIsGroupEnvelope_InvalidJSON` pin discriminator false cases.
- `go-mknoon/node/pubsub_test.go::validateGroupEnvelope` rejects `ParseGroupEnvelope` errors as `reject:invalid_envelope`, and `TestGroupTopicValidator_InvalidJSON` covers a non-v3 invalid-JSON rejection.

Missing:

- No exact `GK-010` row-named test asserts `ParseGroupEnvelope` returns nil and an error containing both `parse group envelope` and `missing groupId` for a v3-looking envelope with no `groupId`.

## regression/tests to add first

Add `TestGK010ParseGroupEnvelopeRejectsMissingGroupID` in `go-mknoon/internal/group_envelope_test.go`, near `TestParseGroupEnvelope_MissingFields`.

Preferred test shape:

- Use input JSON like:

```json
{"version":"3","type":"group_message","senderId":"peer1","senderPublicKey":"abc","signature":"sig","keyEpoch":1,"encrypted":{"ciphertext":"ct","nonce":"n"}}
```

- Call `env, err := ParseGroupEnvelope(data)`.
- If `err == nil`, fail with a message saying missing `groupId` must be rejected.
- If `env != nil`, fail with a message saying no envelope should be returned on missing `groupId`.
- Use `strings.Contains` to require `parse group envelope`.
- Use `strings.Contains` to require `missing groupId`.

This test should pass with the current production guard. If it does not, fix the parser before touching validator, PubSub, or Flutter surfaces.

## step-by-step implementation plan

1. Reconfirm `git status --short` and preserve unrelated dirty files.
2. Reopen `go-mknoon/internal/group_envelope.go` and `go-mknoon/internal/group_envelope_test.go` to confirm the parser guard and test placement have not shifted.
3. Add the `strings` import to `go-mknoon/internal/group_envelope_test.go` if it is not already present.
4. Add `TestGK010ParseGroupEnvelopeRejectsMissingGroupID` near `TestParseGroupEnvelope_MissingFields`.
5. Use a v3-looking group envelope JSON with `version` and `type` present and `groupId` omitted.
6. Assert `ParseGroupEnvelope` returns a non-nil error.
7. Assert the returned envelope is nil.
8. Assert the error contains both `parse group envelope` and `missing groupId`.
9. Run `gofmt` on `go-mknoon/internal/group_envelope_test.go`.
10. Run the focused internal selector.
11. Run the broader Go parser/validator sweep.
12. Run `git diff --check`.
13. If the row-named test fails because `ParseGroupEnvelope` returns an envelope, no error, or an error without the required missing-`groupId` context, make the smallest production fix in `go-mknoon/internal/group_envelope.go` and rerun the same commands.
14. Stop there. Leave source matrix and session breakdown closure updates to a later closure/audit task after executor and QA evidence exist.

## risks and edge cases

- A test that omits `version` or `type` would not prove GK-010 because it would not exercise the v3-looking envelope path from the row.
- A test that only checks `err != nil` duplicates existing `TestParseGroupEnvelope_MissingFields` and does not provide row-owned proof.
- Changing `IsGroupEnvelope` to require `groupId` would alter the discriminator contract and may change validator rejection reasons from `invalid_envelope` to `not_v3_envelope`; that is out of scope.
- Adding a node/PubSub delivery test would overreach unless the internal parser test reveals a real validator-flow gap.
- Because many unrelated files are already dirty, implementation must patch only the planned test file and must not format unrelated Go/Dart files.
- If the broader Go sweep fails in `./node` due to unrelated dirty worktree changes, record the exact package/test failure and keep GK-010 focused on the direct internal selector.

## exact tests and gates to run

Run from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`.

If the Go test file is edited:

```sh
(cd go-mknoon && gofmt -w internal/group_envelope_test.go)
```

Focused GK-010 and adjacent parser selector:

```sh
(cd go-mknoon && go test ./internal -run '^(TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestParseGroupEnvelope_InvalidJSON|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)
```

Broader Go parser/validator sweep:

```sh
(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupEnvelope|GroupTopicValidator|GroupMessage|DecryptionFailed|UpdateGroupKey|BuildGroupSignatureData|Sign' -count=1)
```

Diff hygiene:

```sh
git diff --check
```

Named Flutter gates:

- No named Flutter gate is required for the expected `go-mknoon/internal/group_envelope_test.go`-only change.
- If execution unexpectedly touches Dart/Flutter group code, bridge code, or app-level group send/receive behavior, run:

```sh
./scripts/run_test_gates.sh groups
```

Race:

- A Go race run is not required for the expected parser unit-test-only proof because no shared state or goroutines are touched.
- If production parser or node validation code changes and the executor has time budget for the source row's recommended race coverage, add:

```sh
(cd go-mknoon && go test -race ./internal -run '^TestGK010ParseGroupEnvelopeRejectsMissingGroupID$' -count=1)
```

## known-failure interpretation

- Any failure in `TestGK010ParseGroupEnvelopeRejectsMissingGroupID` is row-owned and blocks GK-010 closure.
- If the new test receives `err == nil`, treat current parser behavior as insufficient and fix `ParseGroupEnvelope`.
- If the new test receives a non-nil envelope on error, treat it as a parser API contract blocker for GK-010 unless current parser design is intentionally changed and documented.
- If the error does not contain `parse group envelope`, the parser is missing the required contextual wrapper for this row's expected diagnostic.
- If the error does not contain `missing groupId`, the parser is missing the field-specific diagnostic required by the row.
- If adjacent internal parser tests fail, treat them as blockers unless exact evidence shows a pre-existing failure unrelated to the GK-010 edit.
- If the broader Go sweep fails in `./node` or `./crypto` while the focused internal selector passes, document the exact failing tests and inspect only enough to decide whether the failure is pre-existing or parser-related; do not broaden GK-010 into node, crypto, or Flutter work without direct evidence.
- `git diff --check` failures in the new GK-010 test or plan file are row-owned; unrelated pre-existing whitespace failures must be named and isolated.

## done criteria

- `go-mknoon/internal/group_envelope_test.go` contains exact row-named `TestGK010ParseGroupEnvelopeRejectsMissingGroupID`.
- The test input has `version` and `type` but no `groupId`.
- The test proves `ParseGroupEnvelope` returns no envelope.
- The test proves `ParseGroupEnvelope` returns an error.
- The test proves the error contains both `parse group envelope` and `missing groupId`.
- Existing parser tests still pass.
- No production code changes are made unless the new regression proves a real parser defect.
- Focused internal selector, broader Go parser/validator sweep, and `git diff --check` pass, or unrelated pre-existing failures are documented with exact commands and outputs.
- Source matrix and session breakdown closure rows remain untouched until a later closure writer records executor and QA evidence.

## scope guard

Non-goals:

- No GK-011 missing-`senderId` work.
- No GK-015 group-id mismatch validator work.
- No GK-006/GK-007 ciphertext or nonce tamper work.
- No GK-008 wrong-public-key signature work.
- No key-epoch, decryption, signature, replay, offline inbox, or device-binding behavior changes.
- No Dart/Flutter bridge, offline replay, simulator, fake-network, UI, or matrix-closure edits.
- No broad parser-schema refactor.

Overengineering signals:

- Requiring every `GroupEnvelope` field in `ParseGroupEnvelope` when GK-010 only owns missing `groupId`.
- Starting libp2p nodes for a parser-unit row.
- Changing validator reason strings or event payloads without a failing parser regression requiring it.
- Adding helper abstractions for one direct JSON fixture.

## accepted differences / intentionally out of scope

- The source row says "Parse and validate"; current evidence shows parser rejection is the authoritative expected result, and validators already route parser errors to `invalid_envelope`. This plan therefore requires direct parser proof and treats node validation as adjacent sweep coverage, not a new node regression.
- `IsGroupEnvelope` returning true for v3-looking JSON with no `groupId` is accepted. It is a discriminator, not a complete validator.
- Integration is `Recommended`, not `Required`; for the expected tests-only internal parser proof, a live PubSub or Flutter integration test is intentionally out of scope.
- Race is `Recommended`, but the expected change adds only a deterministic parser unit test and no shared state. A race command is conditional on production code changes.

## dependency impact

- GK-010 closure gives later malformed-envelope rows a stable parser baseline: missing `groupId` fails at parse time with a field-specific error.
- GK-011 should still own missing `senderId` validator/parser behavior independently; do not inherit GK-010's missing-`groupId` proof.
- GK-015 should still own envelope/topic group mismatch independently; do not alter `ParseGroupEnvelope` group-id mismatch semantics here.
- If GK-010 unexpectedly requires production parser changes, later parser/validator rows should recheck their expected rejection reason because validator flow depends on parse outcomes.

## Reviewer Notes

- Sufficiency: sufficient as-is.
- Missing files, tests, regressions, or gates: none structurally missing. The exact row-named regression belongs in `go-mknoon/internal/group_envelope_test.go`; `go-mknoon/internal/group_envelope.go` is fallback-only. No named Flutter gate is required for the expected internal-test-only change; the conditional `groups` gate is stated for unexpected Dart/Flutter group-surface edits.
- Stale or incorrect assumptions: none found. Current code already has the missing-`groupId` guard, but the source row and breakdown still require committed gap closure because there is no row-named nil-envelope/error-text proof.
- Overengineering: none. The plan avoids node startup, `IsGroupEnvelope` contract changes, Flutter/offline replay, and schema-wide parser validation.
- Decomposition: narrow enough for implementation. The executor has a single direct test to add first and a clear stop point if it passes.
- Minimum needed to make the plan sufficient: already present; no patch loop required before arbiter.

## Arbiter Decision

- Structural blockers: none.
- Incremental details: implementation may choose exact fixture variable names and test placement near the existing missing-fields test, as long as the row-named test assertions stay intact.
- Accepted differences: no new node/PubSub integration test is required for the expected parser-unit closure; `IsGroupEnvelope` stays a version/type discriminator; Flutter `groups` gate and Go race are conditional rather than mandatory for the expected test-only edit.
- Stop-rule decision: no structural blocker was found, so the plan stops here with no patch loop.

## Final Planning Output

- Final verdict: execution-ready for GK-010.
- Final plan: add `TestGK010ParseGroupEnvelopeRejectsMissingGroupID` in `go-mknoon/internal/group_envelope_test.go`; prove a v3-looking JSON envelope with no `groupId` returns nil envelope plus an error containing `parse group envelope` and `missing groupId`; touch `go-mknoon/internal/group_envelope.go` only if that regression fails for a real parser defect.
- Structural blockers remaining: none.
- Incremental details intentionally deferred: exact fixture variable naming and local test placement are left to the executor.
- Accepted differences intentionally left unchanged: `IsGroupEnvelope` remains version/type-only; no Flutter gate, node integration test, or race run is required for the expected internal-test-only change.
- Exact docs/files used as evidence: source matrix row GK-010, session breakdown row/session GK-010, `go-mknoon/internal/group_envelope.go`, `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_security_harness_test.go`, `Test-Flight-Improv/test-gate-definitions.md`, and `scripts/run_test_gates.sh`.
- Why the plan is safe to implement now: current parser code already contains the required guard, the missing closure artifact is a precise row-owned regression, production scope is conditional and minimal, and the plan has exact commands plus known-failure interpretation.

## Final Execution Verdict

- Final verdict: accepted.
- Blocker class: none.
- Files changed: `go-mknoon/internal/group_envelope_test.go`; `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-010-plan.md`.
- Tests added or updated: added `TestGK010ParseGroupEnvelopeRejectsMissingGroupID`.
- Production code changes: none; `go-mknoon/internal/group_envelope.go` stayed fallback-only.
- Exact commands/results:
  - `(cd go-mknoon && gofmt -w internal/group_envelope_test.go)` exited 0.
  - `(cd go-mknoon && go test ./internal -run '^(TestGK010ParseGroupEnvelopeRejectsMissingGroupID|TestParseGroupEnvelope_MissingFields|TestParseGroupEnvelope_InvalidJSON|TestMarshalParseGroupEnvelope_RoundTrip|TestIsGroupEnvelope_V3GroupMessage|TestIsGroupEnvelope_InvalidJSON)$' -count=1)` -> `ok github.com/mknoon/go-mknoon/internal 0.404s`.
  - `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupEnvelope|GroupTopicValidator|GroupMessage|DecryptionFailed|UpdateGroupKey|BuildGroupSignatureData|Sign' -count=1)` -> `ok github.com/mknoon/go-mknoon/node 9.606s`; `ok github.com/mknoon/go-mknoon/internal 0.441s`; `ok github.com/mknoon/go-mknoon/crypto 0.308s`.
  - `git diff --check` exited 0.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: none.
- Scope guard result: source matrix and session breakdown closure rows were not touched by this execution; pre-existing dirty work remains preserved.
- Why complete: the row-owned regression uses v3-looking JSON with `version` and `type` present and `groupId` omitted, asserts `env == nil`, asserts `err != nil`, and checks the error contains both `parse group envelope` and `missing groupId`; required Go validation and diff hygiene passed.

## Closure Note

- Closure status: accepted/closed.
- Closure evidence: source matrix GK-010 is `Covered`; breakdown GK-010 inventory, disposition, session ledger row 61, ordered session row 61, and session closure ledger now record `covered/accepted`.
- Landed proof: `go-mknoon/internal/group_envelope_test.go::TestGK010ParseGroupEnvelopeRejectsMissingGroupID`.
- Validation: executor, QA, and fresh audit reruns passed the focused internal selector, broader Go parser/validator sweep, and `git diff --check`.
- Accepted differences: no production parser change was required; `go-mknoon/internal/group_envelope.go` has no diff. Integration and race evidence remain non-required for this tests-only internal parser closure.
- Residual-only: none for GK-010. GK-011 owns missing `senderId` independently.
