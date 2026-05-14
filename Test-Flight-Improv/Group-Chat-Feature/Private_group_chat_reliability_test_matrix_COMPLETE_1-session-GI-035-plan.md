# GI-035 Session Plan: Inbox Relay Plaintext Privacy

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-035`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:13:00 CEST | Controller | Source matrix GI-035 row; breakdown row 151; existing GI-003 Go request proof; existing EK-002 Flutter retry privacy proof; `go-mknoon/node/group_inbox.go::GroupInboxStore`; `go-relay-server/inbox.go::GroupInboxStore`; `send_group_message_use_case.dart` replay-envelope construction | The source row is `Open` and the breakdown marks GI-035 `needs_repo_evidence` / `evidence-gated`. Existing adjacent proof covers omitted push previews and app retry privacy, but no row-owned `GI-035` proof ties the fake relay-captured group-store request, relay persistence, and Flutter send path to plaintext absence. Production sends only the encrypted/offline replay envelope to group inbox store and relay storage persists the opaque `message` string. | Add exact row-owned GI-035 proof across Go node fake-relay capture, Go relay storage, and Flutter app send command/retry payload inspection; close as tests-only if no production gap appears. |

## Scope

GI-035 owns relay-visible and relay-persisted group inbox privacy for normal private group message durable delivery.

Out of scope: live PubSub encryption/decryption validation, push notification rendering policy beyond absence of plaintext payload, inbox dedupe, history repair integrity, and unsupported malicious clients that deliberately send plaintext to the relay API.

## Execution Contract

1. Add a Go node test that builds a valid encrypted group envelope from known plaintext, sends it through `GroupInboxStore` to a fake relay, captures the raw request frame, and searches for plaintext/media fragments.
2. Add a Go relay test that stores/retrieves an opaque group replay envelope and searches stored relay-visible JSON for plaintext fragments.
3. Update the existing Flutter app privacy test to include `GI-035` in the test name and assert the replay envelope lacks plaintext fields while the `group:inboxStore` command and retry payload contain only the opaque replay envelope.
4. Run focused GI-035 Go/Flutter gates, adjacent inbox privacy gates, gofmt/dart format, and `git diff --check`.
5. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused Go node frame proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI035'` from `go-mknoon` |
| Focused relay storage proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./... -run 'TestGI035'` from `go-relay-server` |
| Focused Flutter app proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-035'` |
| Adjacent inbox privacy proof | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GI003|GI035|GroupInboxStore'` from `go-mknoon`; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'EK-002'` |
| Hygiene | `gofmt -w go-mknoon/node/group_inbox_test.go go-relay-server/group_inbox_test.go`; `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout code, tests, and accepted plan artifacts. GI-035 scope is limited to row-owned tests, this plan, source matrix row GI-035, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added Go node fake-relay proof in `go-mknoon/node/group_inbox_test.go`: `TestGI035GroupInboxStoreSendsEncryptedEnvelopeWithoutPlaintextToRelay`.
- Added Go relay persistence proof in `go-relay-server/group_inbox_test.go`: `TestGI035GroupInboxStorePersistsEncryptedEnvelopeWithoutPlaintext`.
- Updated the existing Flutter app privacy proof in `test/features/groups/application/send_group_message_use_case_test.dart` so it is row-selectable as `EK-002 GI-035 pending inbox retry stores encrypted replay without protected plaintext`, and added assertions that the replay envelope lacks plaintext fields such as `text`, `media`, and `senderUsername`.
- No production code changed for GI-035. Existing production sends only the encrypted/offline replay envelope to `group:inboxStore`, `GroupInboxStore` forwards that opaque message string to the relay, and relay storage persists/retrieves the same opaque envelope.

## Verification

- Initial `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGI035'` failed before tests with local temp-volume error `no space left on device` under `/var/folders`; cleared generated `/private/tmp/codex-go-build-cache` and reran with `GOTMPDIR=/private/tmp/codex-go-tmp`.
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGI035'` passed (`ok node 0.509s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./... -run 'TestGI035'` from `go-relay-server` passed (`ok relay-server 0.558s`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-035'` passed (`+1`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'GI003|GI035|GroupInboxStore'` passed (`ok node 0.883s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./... -run 'GI035|GroupInbox|InboxDedup'` from `go-relay-server` passed (`ok relay-server 0.688s`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'EK-002'` passed (`+1`).
- `gofmt -l go-mknoon/node/group_inbox_test.go go-relay-server/group_inbox_test.go` passed with no output.
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` passed (`0 changed`).
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GI-035 is `Covered` by row-owned Go node, Go relay, and Flutter app evidence proving relay-visible and relay-persisted group inbox data contains only encrypted/opaque replay envelopes and no protected plaintext fragments or plaintext fields. Residual-only: none for GI-035. GR-004 is the next unresolved P0 row in session order; no final program verdict was written.
