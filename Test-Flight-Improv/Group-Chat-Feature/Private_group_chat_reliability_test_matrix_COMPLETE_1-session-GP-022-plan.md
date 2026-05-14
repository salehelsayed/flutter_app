# GP-022 Session Plan: Decryption Failure Diagnostics

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-022`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:52:00 CEST | Controller | Source matrix GP-022 row; breakdown row 117; production `go-mknoon/node/pubsub.go::emitGroupDecryptionFailed` and `decryptGroupEnvelopePayload`; existing `TestHandleGroupSubscription_EmitsDecryptionFailedEvent`, GL013 key-removal proof, and tampered-nonce diagnostics tests | Existing tests cover most decryption diagnostics, but the row remains open because no exact row-owned wrong-local-key proof asserts the complete field set `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, `error`, and `decryptMs` in one test. | Add exact Go node regression `TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey`. No production code change is expected unless the test exposes a missing diagnostic. |
| 2026-05-13 01:57:00 CEST | Controller | New GP-022 Go regression; focused and adjacent Go gates; source matrix row GP-022; breakdown row 117 | Row-owned proof now exists. The test exercises the live receive path with a valid envelope encrypted under the sender key while the receiver has the wrong local key, and proves complete decryption-failure diagnostics plus no receive/plaintext side effects. | Close GP-022 as `Covered`/accepted with tests-only evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-022 owns the Go node receive-path diagnostics when an otherwise valid group envelope cannot decrypt because the local receiver key is wrong or stale.

Out of scope: missing-key behavior after key removal, malformed payload parse failures, handler continuation after malformed traffic, UI notification behavior, and app-layer dedupe.

## Execution Contract

1. Add row-owned Go regression `TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey`.
2. Build a valid signed/encrypted envelope under the sender's group key while the receiver has a different local key at the same epoch.
3. Publish over a live local PubSub path.
4. Assert `group:decryption_failed` includes `groupId`, `senderId`, envelope `keyEpoch`, receiver `localKeyEpoch`, non-empty AES-GCM error, and non-negative `decryptMs`.
5. Assert no message/reaction receive event or plaintext leak is emitted after the decryption failure.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-022 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP022')` |
| Adjacent decryption diagnostics selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP022|DecryptionFailed|TamperedNonce|KeyRemoval|decryptGroupEnvelopePayload')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-021 closure artifacts. GP-022 scope is limited to row-owned Go tests, this plan, and closure documentation updates unless the focused regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:57:00 CEST | Executor/QA completed | `go-mknoon/node/pubsub_decryption_failure_test.go` | Added `TestGP022ReceivePathEmitsDecryptionFailedDiagnosticsForWrongLocalKey`. The test publishes a valid signed/encrypted envelope while the receiver has a wrong local key at the same epoch, then verifies `group:decryption_failed` includes `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, AES-GCM `error`, and non-negative numeric `decryptMs`, with no message/reaction receive event or plaintext marker after baseline. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-022 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP022'` passed (`ok github.com/mknoon/go-mknoon/node 2.638s`). |
| Adjacent decryption diagnostics selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP022\|DecryptionFailed\|TamperedNonce\|KeyRemoval\|decryptGroupEnvelopePayload'` passed (`ok github.com/mknoon/go-mknoon/node 4.601s`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-022 is `Covered` by tests-only Go node evidence: wrong-local-key receive failure emits the required decryption diagnostics (`groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`, `error`, and `decryptMs`) and does not emit message/reaction receive events or plaintext. Residual-only none for GP-022; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-022 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 117, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-022 ownership and does not mask a repo-owned blocker.
