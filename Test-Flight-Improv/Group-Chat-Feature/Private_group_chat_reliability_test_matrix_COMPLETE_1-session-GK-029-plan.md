# GK-029 Session Plan: Malformed Payload Parse Failure Only

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-029`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 20:30:12 CEST | Evidence Collector started | Source matrix GK-029 row; breakdown row 79; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/internal/group_envelope.go`; `go-mknoon/internal/group_envelope_test.go`; adjacent payload parse tests | Source row GK-029 is `Open` and the adjacent plan file was missing. Existing live coverage proves non-JSON plaintext emits `group:payload_parse_failed`, but `ParseGroupPayload` currently accepts JSON objects that omit required payload fields into zero-value `GroupMessagePayload`, so wrong-schema plaintext can still emit `group_message:received`. | Add schema validation for decrypted `group_message` payloads and exact row-owned non-JSON plus wrong-schema live tests. |
| 2026-05-12 20:30:12 CEST | Reviewer completed | Same files plus `buildGroupMessageReceivedEvent`, `emitGroupPayloadParseFailed`, and payload round-trip tests | GK-029 is a repo-owned parser/handler gap. The safe production change is limited to `internal.ParseGroupPayload` requiring a JSON object with a present string `text` field and a present non-empty string `timestamp` field, preserving valid payload round trips and extras. | Implement parser validation, focused internal tests, live raw-publish no-message tests, then run required Go gates. |

## Real Scope

GK-029 owns only malformed decrypted `group_message` payload handling after an envelope has passed validation and decryption. It may update `go-mknoon/internal/group_envelope.go` parser validation, internal parser tests, and Go node live payload-parse tests. It must not change envelope validation, signature data, key epochs, reaction schema behavior beyond existing GK-025 handling, device binding, replay entitlement, Flutter UI, or relay behavior.

## Required Implementation

1. Preserve valid `GroupMessagePayload` round trips, including `extra`, media, quoted message, and empty text when the `text` key is present.
2. Reject non-object JSON, missing `text`, non-string `text`, missing `timestamp`, non-string `timestamp`, and blank `timestamp` from `ParseGroupPayload`.
3. Prove a decrypted non-JSON payload emits only `group:payload_parse_failed` with group, sender, and envelope type.
4. Prove a decrypted wrong-schema JSON payload emits only `group:payload_parse_failed` with group, sender, and envelope type.
5. Prove neither malformed payload path emits `group_message:received`, `group_reaction:received`, `group:decryption_failed`, or the malformed plaintext marker.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-029 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./internal ./node -run 'TestGK029')` |
| Adjacent parser/payload parse coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./internal ./node -run 'ParseGroupPayload|PayloadParse|MalformedPayload|GK029|GK025')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|PayloadParse|DecryptionFailed|GK029')` |
| Race check for live PubSub evidence | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK029|PayloadParse')` |
| Formatting and whitespace | `gofmt -w go-mknoon/internal/group_envelope.go go-mknoon/internal/group_envelope_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-029 can move to `Covered` only after concrete file/test/gate evidence is recorded.
- Non-JSON decrypted plaintext must emit `group:payload_parse_failed` and no message/reaction/decrypt event.
- Wrong-schema decrypted JSON must emit `group:payload_parse_failed` and no message/reaction/decrypt event.
- Valid message payloads, extras, media, quotes, and existing reaction behavior must remain accepted.
- Residual work, if any, must be outside GK-029 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 20:30:12 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-029-plan.md`; `go-mknoon/internal/group_envelope.go`; `go-mknoon/internal/group_envelope_test.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Execute GK-029 locally in the controller. The row needs a small production parser guard because JSON with missing message fields was accepted into zero-value payloads. | Patch parser validation and row-owned tests, then run required Go gates with `GOCACHE=/private/tmp/codex-go-build-cache`. |
| 2026-05-12 20:38:08 CEST | Executor completed | `go-mknoon/internal/group_envelope.go`; `go-mknoon/internal/group_envelope_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Added parser validation requiring a JSON object with present string `text` and present non-empty string `timestamp`; empty `text` remains valid for attachment-only payloads. Added internal wrong-schema parser tests and live raw-publish GK-029 proof for non-JSON plus wrong-schema plaintext. Updated existing payload/decrypt tests in the same file to construct collector-backed nodes before goroutines start, closing a race surfaced by the required race gate. | Record gate evidence and close GK-029. |
| 2026-05-12 20:38:08 CEST | QA completed | Same files plus `go-mknoon/node/pubsub.go` handler path | Required evidence passed after the test-harness race fix: focused GK-029, adjacent parser/payload selector, broader node/internal/crypto selector, race-scoped payload parse selector, gofmt, and `git diff --check`. Scope stayed inside decrypted group-message payload parsing and test harness setup; reaction handling remained covered by GK-025. | Close GK-029 as Covered in source matrix and breakdown. |

## Evidence Captured

| Evidence | Result |
|---|---|
| Focused GK-029 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./internal ./node -run 'TestGK029')` -> `ok internal (cached)`, `ok node 5.755s` after harness fix |
| Adjacent parser/payload parse coverage | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./internal ./node -run 'ParseGroupPayload\|PayloadParse\|MalformedPayload\|GK029\|GK025')` -> `ok internal (cached)`, `ok node 9.835s` |
| Broader Go node/internal/crypto selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|PayloadParse\|DecryptionFailed\|GK029')` -> `ok node 13.741s`, `ok internal (cached)`, `ok crypto (cached)` |
| Race check for live PubSub evidence | Initial run exposed an existing test-harness race from post-start `eventCallback` assignment in payload/decrypt tests. After switching those tests to `startLocalNodeForMultiRelayTestWithCollector`, pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK029\|PayloadParse')` -> `ok node 10.148s` |
| Formatting and whitespace | Pass: `gofmt -w go-mknoon/internal/group_envelope.go go-mknoon/internal/group_envelope_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Final Verdict

Final verdict: accepted

Spawned-agent isolation used: no.

Local sequential fallback used: yes.

Files changed: `go-mknoon/internal/group_envelope.go`; `go-mknoon/internal/group_envelope_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this GK-029 plan.

Tests added or updated: `TestGK029ParseGroupPayloadRejectsWrongSchema`; `TestGK029ParseGroupPayloadAcceptsPresentEmptyTextWithTimestamp`; `TestGK029MalformedPayloadJSONEmitsPayloadParseFailedOnly`; existing payload/decrypt tests in `pubsub_decryption_failure_test.go` now use collector-backed node construction instead of mutating `eventCallback` after start.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: malformed decrypted message payloads now fail before `group_message:received`, both row-owned non-JSON and wrong-schema live paths emit only `group:payload_parse_failed`, valid payloads with extras and empty present text remain accepted, and all required Go evidence passed.

## Closure Note

Controller closure recorded at 2026-05-12 20:38 CEST. The source matrix GK-029 row and breakdown GK-029 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with the concrete code, tests, and gate evidence from this plan. No blockers or follow-ups remain. GK-030 is covered separately and GK-033 is covered separately and GA-001 is covered separately and GA-002 is covered separately and GA-003 is covered separately and GP-005 remains the next unresolved P0 row, and no final program verdict was written.
