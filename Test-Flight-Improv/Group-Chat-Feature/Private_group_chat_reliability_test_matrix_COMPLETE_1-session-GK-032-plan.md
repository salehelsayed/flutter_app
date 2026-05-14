# Private Group Chat Reliability Matrix - Session GK-032 Plan

Status: accepted/closed

## Planning Progress

- 2026-05-13 23:52 CEST - Local gap-closure pass reached GK-032 after GK-031 closure. Source matrix row GK-032 is `Open`; session ledger row 192 is `implementation-ready` / `needs_tests_only`; no adjacent GK-032 plan existed. Inspected the source row, session ledger, `go-mknoon/node/pubsub.go` receive-path `publishedAtNano` parsing, existing GK-030/GK-031 extra-field live delivery tests, and raw encrypted envelope helpers in `go-mknoon/node/pubsub_delivery_test.go`.
- 2026-05-13 23:56 CEST - Implemented and validated the exact row-owned live encrypted receive proof. Source matrix row GK-032 is now `Covered`; session ledger row 192 is now `covered/accepted`.

## Source Row

| Row | Title | Source Status | Ledger Status |
| --- | --- | --- | --- |
| GK-032 | publishedAtNano is parse-safe and cannot crash receive | Covered | covered/accepted |

## Gap Classification

`needs_tests_only`.

Current receive-path behavior already type-checks `payload.Extra["publishedAtNano"]`, calls `strconv.ParseInt`, and only emits `deliveryMs` when parsing succeeds. Missing, malformed, overflow-sized, and non-string values should still emit the message event and omit `deliveryMs`. The row-owned gap is missing exact GK-032 proof on the live encrypted receive path.

## Scope

Owned files:

- `go-mknoon/node/pubsub_delivery_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Out of scope:

- Production runtime changes unless the exact invalid-`publishedAtNano` proof exposes a behavior gap.
- Dart/Flutter replay changes; the source row is owned by the Go encrypted receive path.
- Device-lab or relay-backed harness changes; the row is host-only and has Smoke/Fake Network/3-Party E2E marked N/A.

## Implementation Plan

1. Add an exact live Go regression that publishes raw valid encrypted group-message envelopes with missing, malformed, overflow-sized, and non-string `publishedAtNano` extras.
2. Assert every variant emits `group_message:received` with the expected message id/text and without `deliveryMs`.
3. Run focused GK-032 tests, adjacent Go receive/publish selectors, selected race proof, gofmt, named groups gate, and diff hygiene.
4. Update the source matrix, breakdown ledger, plan verdict, and test inventory with concrete evidence before accepting the row.

## Acceptance Bar

- Source matrix row GK-032 is `Covered`.
- Session ledger row 192 is `covered/accepted`.
- Tests include an exact `GK-032` selector for live encrypted receive behavior.
- Evidence records focused selector, adjacent Go gates, selected race proof, named groups gate, and `git diff --check`.
- Residual-only entry is `none`; no unresolved row-owned blocker remains.

## Execution Evidence

Implemented `go-mknoon/node/pubsub_delivery_test.go::TestGK032PublishedAtNanoInvalidValuesStillEmitMessageWithoutDeliveryMs`. The test publishes raw valid encrypted `group_message` envelopes with four invalid/missing `publishedAtNano` variants: absent value, malformed string, overflow-sized string, and non-string numeric value. Each variant emits `group_message:received` with the expected message id and plaintext, and each omits `deliveryMs` rather than crashing or surfacing an invalid metric.

Validation passed:

- `gofmt -w go-mknoon/node/pubsub_delivery_test.go`
- `cd go-mknoon && go test ./node -run 'TestGK032' -count=1` (`ok node 0.619s`)
- `cd go-mknoon && go test ./node -run 'TestGK030|TestGK031|TestGK032|GroupMessage|PublishedAtNano|PublishGroupMessage' -count=1` (`ok node 1.349s`)
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGK030|TestGK031|TestGK032|GroupMessage|GroupEnvelope|PublishGroupMessage' -count=1` (`ok node 1.705s`, `ok internal 0.289s`, `ok crypto 0.922s`)
- `cd go-mknoon && go test -race ./node -run 'TestGK032|TestGK030|TestGK031|PublishGroupMessage' -count=1` (`ok node 3.056s`)
- `./scripts/run_test_gates.sh groups` (`+159`)
- `git diff --check -- go-mknoon/node/pubsub_delivery_test.go Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-032-plan.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

## Final Verdict

Accepted/closed. GK-032 is `Covered` with exact live encrypted receive-path evidence, no production runtime change was required, and no row-owned residual remains. Continue from GA-018, the next unresolved session in ordered ledger order; do not write a final program verdict while later rows remain unresolved.
