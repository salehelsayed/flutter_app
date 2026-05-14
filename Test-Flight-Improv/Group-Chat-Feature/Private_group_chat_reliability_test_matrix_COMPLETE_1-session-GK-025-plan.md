# GK-025 Session Plan: Envelope Type Tamper Harmlessness

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-025`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 18:48:00 CEST | Evidence Collector started | Source matrix GK-025 row; breakdown row 76; `go-mknoon/internal/group_envelope.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/crypto/group.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/pubsub_test.go`; Dart reaction payload/handler files | GK-025 source row is `Open` and the referenced plan file was missing. Current Go signature data is `groupId|epoch|ciphertext`, so changing only the outer `type` from `group_message` to `group_reaction` can still pass validator. Current live subscription routes `group_reaction` before parsing the inner payload, which can emit a fake reaction event containing a decrypted message payload. | Create the missing doc-scoped plan, then execute a narrow Go reaction-dispatch guard plus exact row-owned regression. |
| 2026-05-12 18:49:00 CEST | Reviewer completed | Same files plus existing tamper tests and reaction payload schema | Prefer harmless rejection at dispatch instead of changing signature format because signing-format migration is larger than this row and valid old/new clients currently share `BuildGroupSignatureData`. The row explicitly allows either signature-policy rejection or safe ignore. | Require decrypted `group_reaction` payloads to match the app reaction schema before emitting `group_reaction:received`; malformed/mismatched inner payloads must emit `group:payload_parse_failed` and no message/reaction event. |
| 2026-05-12 18:49:00 CEST | Arbiter completed | Source row GK-025, breakdown row 76, current Go envelope and dispatch seams | No external fixture blocker. This session owns only GK-025; GK-026 sender tamper and GK-027 device/transport binding remain separate rows. | Execute code/tests in Go node owner files, then close only GK-025. |

## Real Scope

GK-025 owns the live Go group envelope type-tamper behavior. It may change `go-mknoon/node/pubsub.go` and add exact tests in `go-mknoon/node/pubsub_decryption_failure_test.go` or adjacent Go node tests. It must not change sender-id, device-binding, key-epoch, relay inbox, Flutter offline replay, or signature-format migration behavior beyond what is necessary to make a tampered outer `group_reaction` harmless.

## Required Implementation

1. Add a small Go reaction-payload schema check before `handleGroupSubscription` emits `group_reaction:received`.
2. Treat a `group_reaction` envelope whose decrypted plaintext is not a valid reaction payload as `group:payload_parse_failed` with `groupId`, `senderId`, and `envelopeType`, then continue without emitting `group_reaction:received` or `group_message:received`.
3. Preserve valid reaction delivery and existing validator semantics unless the implementation deliberately chooses signature-policy rejection with evidence.
4. Add exact `GK-025` regression evidence for a valid signed message envelope whose outer `type` is mutated to `group_reaction` without re-signing.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-025 regression | `(cd go-mknoon && go test ./node -run 'TestGK025')` |
| Adjacent tamper/security coverage | `(cd go-mknoon && go test ./node -run 'GK00(6|7|8|12|15|25)|GroupReaction|PayloadParse|DecryptionFailed')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupReaction|DecryptionFailed|GK025')` |
| Race check if production Go dispatch changes | `(cd go-mknoon && go test -race ./node -run 'TestGK025|GroupReaction')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-025 can move to `Covered` only after concrete code/test/gate evidence is recorded.
- No fake reaction event may be emitted from a tampered message payload.
- No valid reaction path may regress.
- Residual work, if any, must be outside GK-025 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command/result | Decision/blocker | Next action |
|---|---|---|---|---|---|
| 2026-05-12 19:00:28 CEST | Contract extracted | This plan; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `lib/features/groups/domain/models/group_reaction_payload.dart`; `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart` | N/A | Scope remains GK-025 only: validate decrypted `group_reaction` payload schema before emitting a reaction event; keep validator signature semantics unchanged. | Implement narrow dispatch guard and exact regression. |
| 2026-05-12 19:02:00 CEST | Local Executor completed | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go` passed | Added `group_reaction` inner-payload schema validation and shared `group:payload_parse_failed` emitter. Added GK-025 valid-reaction and type-tamper tests. | Run focused and wider evidence. |
| 2026-05-12 19:03:00 CEST | Focused evidence | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Initial `cd go-mknoon && go test ./node -run 'TestGK025'` failed because the sandbox blocked the default Go build cache under `~/Library/Caches/go-build`; final rerun as `cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK025'` passed: `ok github.com/mknoon/go-mknoon/node 4.023s` | Writable cache workaround is required for this sandbox only; test evidence is valid. | Run adjacent tamper/security selector. |
| 2026-05-12 19:04:00 CEST | Adjacent evidence | Go node tamper/security tests | `cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK00(6|7|8|12|15|25)|GroupReaction|PayloadParse|DecryptionFailed'` passed: `ok github.com/mknoon/go-mknoon/node 13.564s` | Adjacent validator, decryption, payload parse, and reaction coverage remains green. | Run broader Go selector. |
| 2026-05-12 19:05:00 CEST | Broader evidence | `go-mknoon/node`; `go-mknoon/internal`; `go-mknoon/crypto` | `cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupReaction|DecryptionFailed|GK025'` passed: `ok node 8.967s`; `ok internal (cached)`; `ok crypto (cached)` | Broader selected Go seams remain green. | Run race check because production dispatch changed. |
| 2026-05-12 19:06:00 CEST | Race evidence | Go node GK-025/reaction dispatch | `cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK025|GroupReaction'` passed: `ok github.com/mknoon/go-mknoon/node 5.312s` | No race regression found in focused changed dispatch path. | Run formatting and whitespace checks. |
| 2026-05-12 19:10:00 CEST | Compatibility evidence | `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` | `cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestLP003|TestGL008'` initially exposed that a full-schema-only reaction guard rejected existing minimal valid reaction fixtures. | Full-schema-only validation would narrow the repo-owned Go reaction contract. | Preserve both minimal and full-schema valid reaction payloads, then rerun required evidence. |
| 2026-05-12 19:13:16 CEST | Local QA and final evidence | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`; this plan | `gofmt -w go-mknoon/node/pubsub.go go-mknoon/node/pubsub_decryption_failure_test.go go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` passed; `git diff --check` passed | Local QA found no GK-025 blocker. Source matrix and session breakdown closure rows intentionally not updated per instruction. | Close GK-025 plan verdict. |
| 2026-05-12 19:19:08 CEST | Main QA correction and final evidence | `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`; this plan | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK025'` passed: `ok .../node 4.205s`; `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestLP003|TestGL008'` passed: `ok .../node 11.718s`; `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK00(6|7|8|12|15|25)|GroupReaction|PayloadParse|DecryptionFailed'` passed: `ok .../node 13.392s`; `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|GroupReaction|DecryptionFailed|GK025'` passed: `ok node 8.917s`, `ok internal (cached)`, `ok crypto (cached)`; `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK025|GroupReaction'` passed: `ok .../node 5.243s`; `git diff --check` passed | Final implementation rejects tampered message plaintext under a `group_reaction` envelope while preserving existing minimal and app full-schema reaction payloads. | Update source matrix and breakdown closure rows. |

## Final Verdict

GK-025 is closed as implemented and covered.

- `group_reaction` live dispatch now validates the decrypted inner reaction payload before `group_reaction:received`.
- A valid signed `group_message` envelope whose outer `type` is mutated to `group_reaction` without re-signing still preserves existing validator semantics (`accept`), but the live receiver treats the decrypted message payload as a reaction schema mismatch, emits `group:payload_parse_failed` with `groupId`, `senderId`, and `envelopeType`, and emits no fake reaction or message event.
- Valid full-schema group reaction delivery remains covered by `TestGK025ValidGroupReactionDeliveryStillEmitsReaction`; existing minimal live reaction fixtures remain valid via the LP003/GL008 compatibility check.
- No GK-025 residual blocker remains. Source matrix and session breakdown closure rows are updated to `Covered`/`covered/accepted`.

## Closure Note

Closure accepted at 2026-05-12 19:21 CEST.

- Source matrix GK-025 is `Covered`.
- Breakdown GK-025 inventory, row-disposition, session-ledger, ordered-session, closure-progress, and Session Closure Ledger rows are `covered/accepted`.
- Final evidence is code-plus-tests Go node proof in `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_decryption_failure_test.go`, plus LP003/GL008 compatibility proof for minimal reaction payloads.
- Commands passed: focused GK-025, LP003/GL008 compatibility, adjacent tamper/security, broader node/internal/crypto, race, gofmt, and `git diff --check`.
- Residual-only: none for GK-025. GK-026 remains the next unresolved P0 row.
