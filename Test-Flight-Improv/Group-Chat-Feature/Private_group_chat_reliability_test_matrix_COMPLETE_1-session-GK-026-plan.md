# GK-026 Session Plan: SenderId Tamper Rejection

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-026`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 19:25:00 CEST | Evidence Collector started | Source matrix GK-026 row; breakdown row 77; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/internal/group_envelope.go`; `go-mknoon/crypto/group.go` | Source row GK-026 is `Open` and the adjacent plan file was missing. Current signature data still does not cover `senderId`, but validation looks up the claimed sender's configured signing key before signature verification, which should reject B-signed traffic relabeled as C unless C somehow has the same signing key. | Add exact row-owned Go node proof for pure validator and live PubSub rejection; only change production if RED evidence exposes a real gap. |
| 2026-05-12 19:25:00 CEST | Reviewer completed | Same files plus existing GK-008/GK-012/GK-025 tamper tests | Expected closure path is tests-only: mutate only `senderId` after signing, preserve signature/ciphertext/nonce, verify pure validation rejects as `bad_signature`, and prove live raw-publish emits validation rejection with no attribution or payload side effects. | Execute focused GK-026 tests, adjacent signature/tamper selectors, broader Go selector, race if test path touches live PubSub, gofmt, and diff hygiene. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 19:36:23 CEST | Contract extracted | Source matrix GK-026 row; breakdown row 77; this plan; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/group_security_harness_test.go`; `go-mknoon/node/pubsub_delivery_test.go`; `go-mknoon/internal/group_envelope.go`; `go-mknoon/crypto/group.go` | Scope is GK-026 only. Existing validator looks up the claimed `senderId` member and verifies with that member's configured key, so expected path is tests-only unless row-owned tests expose a gap. Local sequential execution is being used because this turn did not authorize sub-agents. | Add focused pure-validator and live raw-publish GK-026 regression tests. |
| 2026-05-12 19:42:48 CEST | Executor completed focused regression | Touched `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this plan | Added tests-only GK-026 evidence. `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK026'` passed (`ok github.com/mknoon/go-mknoon/node 3.677s`). `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go go-mknoon/node/pubsub_test.go` completed. No production change required. | Run adjacent sender/signature tamper selector, broader node/internal/crypto selector, race selector, and `git diff --check`. |
| 2026-05-12 19:45:31 CEST | Gates and local QA completed | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this plan | Adjacent selector passed (`ok node 10.380s`); broader node/internal/crypto selector passed (`ok node 7.885s`, `ok internal 0.281s`, `ok crypto 0.572s`); race selector passed (`ok node 6.870s`); post-format focused rerun passed from cache; `git diff --check` passed. Local QA found no scope, regression, or missing-gate blocker. | Write final verdict. |

## Real Scope

GK-026 owns only sender identity tampering for v3 group envelopes. It may add row-owned Go node tests and may change `go-mknoon/node/pubsub.go` only if the existing validator fails to reject B-signed traffic whose outer `senderId` is changed to C. It must not change sender-device/transport binding, public-key spoofing, key epochs, reaction schema validation, relay inbox, Flutter offline replay, or signature-format migration behavior beyond what is necessary to close GK-026.

## Required Implementation

1. Build a valid B-signed group envelope, then mutate only top-level `senderId` to C without re-signing.
2. Prove the mutation preserves signature, ciphertext, nonce, group, type, and epoch.
3. Prove pure validation rejects under C's configured member key unless C has the same signing key.
4. Prove live raw-publish validation emits a rejection and no `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or plaintext/attribution corruption.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-026 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK026')` |
| Adjacent sender/signature tamper coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK00(8|11|12|25|26)|Sender|Signature|BadSignature|ValidationReject')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupReaction|BadSignature|GK026')` |
| Race check if live PubSub evidence is added | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK026|BadSignature|ValidationReject')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go go-mknoon/node/pubsub_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-026 can move to `Covered` only after concrete code/test/gate evidence is recorded.
- B-signed traffic relabeled as C must not be accepted or emitted as a C-authored message.
- No valid sender/signature path may regress.
- Residual work, if any, must be outside GK-026 row ownership and must not hide an unresolved repo-owned blocker.

## Final Verdict

`accepted`

Spawned-agent isolation used: no. Local sequential fallback used because this turn did not authorize sub-agents.

Files changed:

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-026-plan.md`

Tests added:

- `TestGK026ValidateGroupEnvelopeRejectsSenderIDTamperUnderClaimedMemberKey`
- `TestGK026SenderIDTamperLiveRawPublishRejectsWithoutAttributionCorruption`

Evidence captured:

- A valid B-signed v3 `group_message` envelope is mutated only at top-level `senderId` to claim C.
- The mutation preserves `signature`, `encrypted.ciphertext`, `encrypted.nonce`, encrypted payload, group, type, epoch, sender public key, and optional sender device/transport fields.
- The signature still verifies with B's signing key, does not verify with C's configured member key, and pure validation under C's transport/member identity rejects as `reject:bad_signature`.
- Live raw publish from C's transport emits `group:validation_rejected` reason `bad_signature_or_epoch` and emits no `group_message:received`, `group_reaction:received`, `group:decryption_failed`, plaintext marker, or raw C `senderId` attribution event after the rejection baseline.

Exact tests and gates run:

- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK026')` passed (`ok node 3.677s`; post-format rerun cached).
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK00(8|11|12|25|26)|Sender|Signature|BadSignature|ValidationReject')` passed (`ok node 10.380s`).
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupReaction|BadSignature|GK026')` passed (`ok node 7.885s`, `ok internal 0.281s`, `ok crypto 0.572s`).
- `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK026|BadSignature|ValidationReject')` passed (`ok node 6.870s`).
- `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go go-mknoon/node/pubsub_test.go` completed.
- `git diff --check` passed.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why this session is safe to consider complete: GK-026 closes through row-owned Go node evidence only; production validator behavior already rejects B-signed/C-claimed traffic under C's configured key, and the live PubSub path proves rejection without payload or attribution side effects. The source matrix and session breakdown closure rows were intentionally left for the controller.

## Closure Note

Controller closure recorded at 2026-05-12 19:49 CEST. The source matrix GK-026 row and breakdown GK-026 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with the concrete tests and gate evidence from this plan. No production code changed for GK-026; no blockers or follow-ups remain. GK-027 is the next unresolved P0 row, and no final program verdict was written.
