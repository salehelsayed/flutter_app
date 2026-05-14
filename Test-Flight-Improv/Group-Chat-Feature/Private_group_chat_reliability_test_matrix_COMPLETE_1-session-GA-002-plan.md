# GA-002 Session Plan: Non-Member Publish Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-002`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 21:34:10 CEST | Controller | Source matrix GA-002 row; breakdown row 83; existing authorization tests in `go-mknoon/node/pubsub_authorization_forward_test.go`; pure validator coverage in `go-mknoon/node/pubsub_test.go`; live delivery helpers in `go-mknoon/node/pubsub_delivery_test.go`; production validator in `go-mknoon/node/pubsub.go` | Source row GA-002 is still `Open` and evidence-gated. Existing LP-002/RP-017 tests prove removed or stale peers are rejected before forwarding, and pure validator tests prove non-member rejection, but there is no exact `GA-002` row-owned live test proving a non-member not in the current config publishes a valid envelope and current members reject with no decrypt/render. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing validator behavior. |

## Scope

GA-002 owns only non-member publish rejection for private chat group messages. It may add Go node authorization tests. It must not change role update semantics, device binding policy, key epoch handling, forwarding policy beyond the row, Flutter UI, relay behavior, or offline replay.

## Execution Contract

1. Add a row-owned test named for GA-002 in `go-mknoon/node/pubsub_authorization_forward_test.go`.
2. Build a private `GroupTypeChat` group where current members A/B do not include X, while X can publish on the topic using a stale local config and a valid signature/key.
3. Assert pure validation against the current config returns `reject:non_member`.
4. Publish X's raw envelope and assert both A and B emit `group:validation_rejected` with `reason == non_member` and the expected key epoch.
5. Assert no `group_message:received`, `group_reaction:received`, `group:decryption_failed`, `group:payload_parse_failed`, or plaintext marker appears after the reject baseline.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-002 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA002')` |
| Adjacent authorization selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA002|LP002|RP017|Authorization|ValidationReject|NonMember')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Authorization|NonMember|GA002')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA002|Authorization|ValidationReject')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-002 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 83, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-002 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 21:39:50 CEST | Executor completed | `go-mknoon/node/pubsub_authorization_forward_test.go` | Added `TestGA002NonMemberCannotPublishValidEnvelope`, proving a non-member X can publish a validly signed envelope from a stale local topic view while current A/B configs exclude X, pure validation rejects as `reject:non_member`, and both A/B emit only `group:validation_rejected` reason `non_member` with no message/reaction/decrypt/payload-parse/plaintext side effects. No production code changed. | Record gate evidence and close GA-002. |
| 2026-05-12 21:39:50 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go` validator path | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production validator behavior satisfies the row. | Close GA-002 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-002 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA002')` -> `ok node 7.152s` |
| Adjacent authorization selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA002\|LP002\|RP017\|Authorization\|ValidationReject\|NonMember')` -> `ok node 13.496s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Authorization\|NonMember\|GA002')` -> `ok node 10.692s`, `ok internal 0.607s`, `ok crypto 0.911s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA002\|Authorization\|ValidationReject')` -> `ok node 8.314s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_authorization_forward_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-002 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_authorization_forward_test.go`; this GA-002 plan. No production code changed, no blockers remain, and GA-003 is covered separately and GP-005 remains the next unresolved P0 row. No final program verdict was written.
