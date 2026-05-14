# GK-027 Session Plan: Sender Device and Transport Binding Tamper Rejection

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-027`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 19:58:00 CEST | Evidence Collector started | Source matrix GK-027 row; breakdown row 78; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/internal/group_envelope.go`; adjacent GK-021/GK-026 and device-binding tests | Source row GK-027 is `Open` and the adjacent plan file was missing. Current validator already checks transport peer binding before device lookup and then active device binding before signature verification, so expected closure path is tests-only unless exact row-owned tests expose a gap. | Add focused pure-validator and live raw-publish GK-027 regression tests for senderDeviceId and senderTransportPeerId tampering. |
| 2026-05-12 19:58:00 CEST | Reviewer completed | Same files plus `buildTestDeviceEnvelope`, `validateGroupEnvelopeForTransportPeer`, `activeMemberDeviceForEnvelope`, `groupEnvelopeMatchesTransportPeer`, and validation-reject collector helpers | The row needs proof for both failure classes named by the expected result: `senderTransportPeerId` tamper should reject as `peer_mismatch`; `senderDeviceId` tamper to a revoked/other device on the same transport should reject as `unbound_device`. Live proof should show no payload, decrypt, plaintext, or attribution side effects. | Execute row-owned Go node tests, adjacent device/transport selectors, broader node/internal/crypto selector, race for live PubSub evidence, gofmt, and diff hygiene. |

## Real Scope

GK-027 owns only tampering of sender device identity and transport binding on v3 group envelopes. It may add row-owned Go node tests and may change `go-mknoon/node/pubsub.go` only if existing validation accepts a valid envelope after `senderDeviceId` or `senderTransportPeerId` is modified to a revoked/other device. It must not change senderId key lookup, public-key spoofing, key epochs, reaction schema validation, membership replay entitlement, durable inbox, or Flutter UI behavior.

## Required Implementation

1. Build a valid device-bound group envelope from an active member device and prove it validates before tamper.
2. Mutate only `senderDeviceId` to a revoked/other device while preserving signature, ciphertext, nonce, group, type, epoch, transport peer, sender public key, device public key, and key package fields.
3. Prove that senderDeviceId tamper rejects as `unbound_device` in pure validation and in live raw-publish validation, with no receive/reaction/decrypt/plaintext side effects.
4. Mutate only `senderTransportPeerId` to a revoked/other transport while preserving all other envelope fields.
5. Prove that senderTransportPeerId tamper rejects as `peer_mismatch` in pure validation and in live raw-publish validation, with no receive/reaction/decrypt/plaintext side effects.
6. Change production only if a focused regression shows accepted or misclassified row-owned tamper behavior.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-027 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK027')` |
| Adjacent device/transport tamper coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK02(1|6|7)|Device|TransportPeer|Unbound|PeerMismatch|ValidationReject')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|BadSignature|Unbound|PeerMismatch|GK027')` |
| Race check for live PubSub evidence | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK027|Unbound|PeerMismatch|ValidationReject')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-027 can move to `Covered` only after concrete file/test/gate evidence is recorded.
- A valid envelope modified to a revoked/other `senderDeviceId` must not be accepted and must reject as `unbound_device`.
- A valid envelope modified to a mismatched `senderTransportPeerId` must not be accepted and must reject as `peer_mismatch`.
- Live raw-publish evidence must show no `group_message:received`, `group_reaction:received`, `group:decryption_failed`, plaintext marker, or tampered-device attribution side effect.
- Residual work, if any, must be outside GK-027 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 20:08:45 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-027-plan.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Execute GK-027 locally per user instruction; repo is already dirty, including expected files, so existing unrelated work is preserved. Scope remains tests-first with production change only if focused evidence shows acceptance or misclassification. | Add pure and live GK-027 regressions, then run required Go gates with `GOCACHE=/private/tmp/codex-go-build-cache`. |
| 2026-05-12 20:08:45 CEST | Executor running | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Existing validation order already appears to reject transport tamper as `peer_mismatch` and active-device tamper as `unbound_device`; production edit is not justified before RED evidence. | Patch row-owned tests only. |
| 2026-05-12 20:18:54 CEST | Executor completed | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Added tests-only GK-027 coverage: `TestGK027ValidateGroupEnvelopeRejectsDeviceAndTransportBindingTamper` proves valid active device envelopes accept, `senderDeviceId` tamper to a revoked device preserves signature/ciphertext and rejects `unbound_device`, and `senderTransportPeerId` tamper preserves signature/ciphertext and rejects `peer_mismatch`; `TestGK027DeviceAndTransportBindingTamperLiveRawPublishRejectsWithoutPayload` proves live raw publishes emit validation rejects and no payload/decrypt/plaintext/tampered-attribution side effects. No production change was needed. | Run and record required gates. |
| 2026-05-12 20:18:54 CEST | QA completed | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/pubsub.go` | Required evidence passed: focused GK-027, adjacent device/transport selector, broader node/internal/crypto selector, race-scoped PubSub selector, `gofmt`, and `git diff --check`. Scope stayed inside row-owned test coverage and confirmed existing production validator behavior. | Close GK-027 as Covered in source matrix and breakdown. |

## Evidence Captured

| Evidence | Result |
|---|---|
| Focused GK-027 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK027')` -> `ok github.com/mknoon/go-mknoon/node 6.335s` |
| Adjacent device/transport tamper coverage | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK02(1\|6\|7)\|Device\|TransportPeer\|Unbound\|PeerMismatch\|ValidationReject')` -> `ok github.com/mknoon/go-mknoon/node 12.538s` |
| Broader Go node/internal/crypto selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|BadSignature\|Unbound\|PeerMismatch\|GK027')` -> `ok` for `node`, `internal`, and `crypto` |
| Race check for live PubSub evidence | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK027\|Unbound\|PeerMismatch\|ValidationReject')` -> `ok github.com/mknoon/go-mknoon/node 7.355s` |
| Formatting and whitespace | Pass: `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Final Verdict

Final verdict: accepted

Spawned-agent isolation used: partial isolated executor attempt was started for GK-027 but produced only the plan heartbeat and was stopped after a bounded no-progress wait.

Local sequential fallback used: yes; the controller completed the tests, gates, and QA locally within the GK-027 write scope.

Files changed: `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this GK-027 plan.

Tests added or updated: `TestGK027ValidateGroupEnvelopeRejectsDeviceAndTransportBindingTamper`; `TestGK027DeviceAndTransportBindingTamperLiveRawPublishRejectsWithoutPayload`; `assertGK027BindingOnlyMutationPreservesEnvelope`.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: both row-owned tamper classes are now proven in pure validation and live raw-publish paths with concrete negative side-effect assertions, and all required Go evidence passed without production code changes.

## Closure Note

Controller closure recorded at 2026-05-12 20:18 CEST. The source matrix GK-027 row and breakdown GK-027 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with the concrete tests and gate evidence from this plan. No production code changed for GK-027; no blockers or follow-ups remain. GK-029 is covered separately and GK-030 is covered separately and GK-033 is covered separately and GA-001 is covered separately and GA-002 is covered separately and GA-003 is covered separately and GP-005 remains the next unresolved P0 row, and no final program verdict was written.
