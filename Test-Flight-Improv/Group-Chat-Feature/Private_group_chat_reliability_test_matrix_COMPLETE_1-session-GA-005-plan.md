# GA-005 Session Plan: Role Update Without Topic Rejoin

## Status

Status: accepted

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-005`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 21:57:15 CEST | Controller | Source matrix GA-005 row; breakdown row 85; existing pure writer-role tests in `go-mknoon/node/pubsub_test.go`; live delivery/update tests in `go-mknoon/node/pubsub_delivery_test.go`; production publish, update, and validator paths in `go-mknoon/node/pubsub.go` | Source row GA-005 is still `Open` and evidence-gated. Existing pure tests prove announcement groups are admin-only and config mutation changes validation results, but there is no exact row-owned live proof that `UpdateGroupConfig` changes write permission immediately on an already joined topic without rejoining. Chat/QA groups allow any member to write, so the role-sensitive repo-owned path is announcement-group authorization. | Add exact live Go node proof for local publish gating and receiver validation before promotion, after promotion, and after demotion with unchanged topic subscriptions. No production code change is expected unless the exact test exposes missing update/authorization behavior. |

## Scope

GA-005 owns only role-based write authorization after `UpdateGroupConfig` on an already joined group topic. It may add Go node tests around announcement-group authorization because chat/QA role changes do not affect write permission in the current product semantics. It must not change group membership, key rotation, device binding, Flutter UI, relay behavior, or offline replay.

## Execution Contract

1. Add a row-owned test named for GA-005 in `go-mknoon/node/pubsub_delivery_test.go`.
2. Build a two-node `GroupTypeAnnouncement` group with A as admin and B initially writer.
3. Prove B cannot publish locally as writer, and pure validation rejects B's writer-role envelope as `reject:unauthorized`.
4. Call `UpdateGroupConfig` to promote B to admin on the existing joined topic; assert the topic subscription pointer remains present/unchanged.
5. Prove B can publish through `PublishGroupMessage` without rejoining and A receives the message.
6. Call `UpdateGroupConfig` on A to demote B back to writer on the existing joined topic while B still has stale local admin state; assert the topic subscription pointer remains present/unchanged.
7. Prove stale-local-admin B can still publish from its local state, but A's current receiver-side validator rejects the demoted sender as `unauthorized_writer` with no render/decrypt side effects.
8. Call `UpdateGroupConfig` on B to apply the demotion locally; assert the topic subscription pointer remains present/unchanged and `PublishGroupMessage` immediately rejects B as not allowed to write.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-005 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA005')` |
| Adjacent role/update selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA005|Announcement|Role|UpdateGroupConfig|Authorization|ValidationReject|Unauthorized')` |
| Broader validator selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupMessage|Authorization|Role|GA005')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA005|UpdateGroupConfig|ValidationReject')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-005 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 85, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-005 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Files/Evidence | Result | Next Action |
|---|---|---|---|---|
| 2026-05-12 22:00:00 CEST | Executor completed | `go-mknoon/node/pubsub_delivery_test.go` | Added `TestGA005RoleUpdateTakesEffectWithoutTopicRejoin`. The test proves the role-sensitive announcement-group path: B writer is blocked locally and by pure validation, promotion through `UpdateGroupConfig` keeps existing topic subscriptions and allows B to publish without rejoin, A receives the promoted message, receiver-side demotion makes A reject stale-local-admin traffic as `unauthorized_writer` with no message/reaction/decrypt/payload-parse/plaintext side effects, and B's later local demotion blocks `PublishGroupMessage` without rejoin. No production code changed. | Record gate evidence and close GA-005. |
| 2026-05-12 22:00:00 CEST | QA completed | Same test plus `go-mknoon/node/pubsub.go` publish, update, and validator paths | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. Existing production behavior satisfies the row once exact row-owned proof is present. | Close GA-005 as Covered in source matrix and breakdown. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-005 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA005')` -> `ok node 4.706s` |
| Adjacent role/update selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA005\|Announcement\|Role\|UpdateGroupConfig\|Authorization\|ValidationReject\|Unauthorized')` -> `ok node 12.148s` |
| Broader validator selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupMessage\|Authorization\|Role\|GA005')` -> `ok node 7.329s`, `ok internal 0.714s`, `ok crypto 1.039s` |
| Race selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA005\|UpdateGroupConfig\|ValidationReject')` -> `ok node 10.055s` |
| Hygiene | Pass: `gofmt -w go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Final Verdict

Accepted and closed. GA-005 is `Covered` by tests-only Go node proof. Files changed: `go-mknoon/node/pubsub_delivery_test.go`; this GA-005 plan. No production code changed, no blockers remain, and GP-005 remains the next unresolved P0 row. No final program verdict was written.
