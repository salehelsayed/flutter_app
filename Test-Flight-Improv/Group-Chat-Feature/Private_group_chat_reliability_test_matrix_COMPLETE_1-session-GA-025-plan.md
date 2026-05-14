# GA-025 Session Plan: Expected Peer Count Uses Active Devices

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GA-025`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-12 23:55:32 CEST | Controller | Source matrix GA-025 row; breakdown row 104; production `go-mknoon/node/pubsub.go::ensureGroupTopicPeersBeforePublish`, `countRemoteGroupMembers`, `activeGroupMemberDialTargets`, and `expectedConnectedGroupMembers`; adjacent GA-023 and GA-024 proofs | Planning-time gap: GA-025 lacked exact row-owned proof. Current production appeared to derive expected peer count from active device transport targets, but the row still needed proof that publish preflight ignores logical member peers, revoked devices, and stale removed-member transports. | Add exact Go node regression evidence. No production code change is expected unless the row-owned test exposes a gap. |

## Scope

GA-025 owns expected peer count construction for publish preflight. It must not change authorization, validator binding, live payload delivery, durable inbox selection, UI role handling, or Flutter repository code unless the row-owned regression proves the Go target count is wrong.

## Execution Contract

1. Add a row-owned Go node regression named `TestGA025ExpectedPeerCountUsesActiveDevicesCurrentRecipients`.
2. Build a group with an admin sender, one logical multi-device current member with two active device transports plus a revoked device, and a stale removed-member entry with only a revoked transport.
3. Prove `activeGroupMemberDialTargets`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers` count only the two active device transports.
4. Seed peerstore addresses for active, logical, and revoked/stale peers, then send through `PublishGroupMessage`.
5. Assert publish preflight `expectedPeers` and direct-dial `totalMembers` are exactly two, and that logical/stale/revoked peers are not selected or connected.

## Required Gates

| Gate | Command |
|---|---|
| Focused GA-025 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA025')` |
| Adjacent peer-count selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA025|GA024|ExpectedPeer|PublishPeer|KnownMemberDial|ActiveDevice')` |
| Broader publish/discovery selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage|GroupDiscovery|KnownMemberDial|Device|Transport|GA025')` |
| Race selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA025|ExpectedPeer|PublishPeer|KnownMemberDial')` |
| Hygiene | `gofmt` on changed Go files and `git diff --check` |

## Closure Bar

- Source row GA-025 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 104, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GA-025 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:06:38 CEST | Implementation completed | Added `go-mknoon/node/pubsub_test.go::TestGA025ExpectedPeerCountUsesActiveDevicesCurrentRecipients`. The test proves publish preflight expected-peer counts use the two active device transport targets and exclude logical, revoked-device, and stale removed-member transports even when all have peerstore addresses. |
| 2026-05-13 00:06:38 CEST | Closure completed | Source matrix GA-025 and breakdown row 104 were updated to `Covered`/`covered/accepted` with exact row-owned evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GA-025 regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGA025'` passed (`ok github.com/mknoon/go-mknoon/node 0.674s`). |
| Adjacent peer-count selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GA025\|GA024\|ExpectedPeer\|PublishPeer\|KnownMemberDial\|ActiveDevice'` passed (`ok github.com/mknoon/go-mknoon/node 2.933s`). |
| Broader publish/discovery selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'PublishGroupMessage\|GroupDiscovery\|KnownMemberDial\|Device\|Transport\|GA025'` passed (`ok node 52.248s`, `ok internal 0.591s`, `ok crypto 1.178s`). |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGA025\|ExpectedPeer\|PublishPeer\|KnownMemberDial'` passed (`ok github.com/mknoon/go-mknoon/node 2.235s`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_test.go` and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GA-025 is covered by exact row-owned Go node proof. No production code changed because existing publish preflight already derives expected peer count from active device dial targets. The proof verifies only active device transports contribute to expected peer count and direct-dial totals, while logical member peers, revoked devices, and stale removed-member transports are excluded even when peerstore addresses exist. Residual-only: none for GA-025. GP-005 remains the next unresolved P0 row; no final program verdict is written.
