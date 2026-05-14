# GA-003 Session Plan: Removed Member Old Config/Key Rejection

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-003`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 21:45:45 CEST | Controller | Source matrix GA-003 row; breakdown row 84; existing GL-011/GM-017/GM-018 delivery tests in `go-mknoon/node/pubsub_delivery_test.go`; authorization forwarding tests in `go-mknoon/node/pubsub_authorization_forward_test.go`; pure validator coverage in `go-mknoon/node/pubsub_test.go`; production validator in `go-mknoon/node/pubsub.go` | Source row GA-003 is still `Open` and evidence-gated. Existing adjacent tests prove removed/stale publishers reject in broader membership scenarios, but there is no exact `GA-003` row-owned test proving C remains locally joined with stale config/key after A/B remove C and rotate key, then A/B validators reject C's publish with diagnostics and no render/decrypt side effects. | Add exact live Go node proof. No production code change is expected unless the exact test exposes a missing validator or update behavior. |

## Scope

GA-003 owns only removed-member publish rejection when the removed member still has old local config/key material. It may add Go node delivery/authorization tests. It must not change member-removal semantics, re-add behavior, role update behavior, device binding policy, Flutter UI, relay behavior, or offline replay.

## Execution Contract

1. Add a row-owned test named for GA-003 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a three-node private `GroupTypeChat` group with A/B/C initially active.
3. Update A and B to a config without C and a newer group key; leave C locally joined with its stale config and old key.
4. Assert pure validation against the current A/B config rejects C's old-envelope publish as `reject:non_member`.
5. Publish from C through `PublishGroupMessage` using C's stale local config/key and assert both A and B emit `group:validation_rejected` with an allowed row result (`non_member` or `bad_signature_or_epoch`) and no message/reaction/decrypt/payload-parse/plaintext side effects.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-003 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA003')` |
| Adjacent authorization selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA003|GA002|GL011|GM017|GM018|Authorization|ValidationReject|NonMember|BadSignature')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Authorization|NonMember|BadSignature|GA003')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA003|UpdateGroupConfig|UpdateGroupKey|ValidationReject')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-003 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 84, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-003 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 21:49:22 CEST | Executor completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGA003RemovedMemberCannotPublishWithOldConfigKey`, proving C remains locally joined with stale config/key after A/B remove C and rotate key, pure validation rejects against the current A/B config as `reject:non_member`, C's stale publish emits validation rejects on both A/B, and no message/reaction/decrypt/payload-parse/plaintext side effects occur. No production code changed. | Record gate evidence and close GA-003. |
| 2026-05-12 21:49:22 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go` update/validator paths | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production validator behavior satisfies the row. | Close GA-003 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-003 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA003')` -> `ok node 7.578s` |
| Adjacent authorization selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA003\|GA002\|GL011\|GM017\|GM018\|Authorization\|ValidationReject\|NonMember\|BadSignature')` -> `ok node 25.471s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Authorization\|NonMember\|BadSignature\|GA003')` -> `ok node 16.729s`, `ok internal 0.282s`, `ok crypto 0.882s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA003\|UpdateGroupConfig\|UpdateGroupKey\|ValidationReject')` -> `ok node 13.776s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-003 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_delivery_test.go`; this GA-003 plan. No production code changed, no blockers remain, and GP-005 remains the next unresolved P0 row. No final program verdict was written.
