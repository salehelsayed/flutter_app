# GP-015 Session Plan: Host Connection Is Not A Live Topic Peer

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-015`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 01:18:00 CEST | Controller | Source matrix GP-015 row; breakdown row 114; production `go-mknoon/node/pubsub.go::ensureGroupTopicPeersBeforePublish`, `liveGroupTopicPeerSet`, and `PublishGroupMessage`; existing GP-005/GP-014 proofs; Flutter `send_group_message_use_case.dart` durable fallback behavior | Pre-closure row state lacked exact row-owned proof combining a libp2p-connected host peer that is not subscribed with publish peer count `0` and durable fallback. Current production appeared to satisfy the row. | Add exact GP-015 Go publish regression and Flutter app fallback regression. No production code change was expected unless the row-owned tests exposed a gap. |
| 2026-05-13 01:23:40 CEST | Controller | New GP-015 Go and Flutter regressions; focused/adjacent gates; source matrix row GP-015; breakdown row 114 | Row-owned proof now exists. Go proves host connectedness stays separate from live topic peer count during publish, and Flutter proves zero live-topic peer sends still store durable fallback while reporting `successNoPeers`/`sent`. | Close GP-015 as `Covered`/accepted with concrete tests-only evidence and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-015 owns the distinction between host connectedness and live PubSub topic membership. A peer connected at the libp2p host/network layer must not count toward `topicPeers` unless it appears in `topic.ListPeers`, and the app must still use durable fallback when the bridge reports zero live topic peers.

Out of scope: relay fallback diagnostics already covered by GP-014, zero-peer publish without a connected host already covered by GP-005, direct-address filtering, simulator E2E, and UI rendering.

## Execution Contract

1. Add row-owned Go regression `TestGP015ConnectedHostPeerDoesNotCountAsLiveTopicPeer`.
2. Connect B at the libp2p host layer without B joining the group topic.
3. Publish from A and prove host connectedness is `Connected`, `topic.ListPeers` remains empty, `PublishGroupMessage` returns `peerCount == 0`, and B receives no group event.
4. Add row-owned Flutter regression named with `GP-015`.
5. Force bridge `topicPeers: 0` and prove the send use case stores durable inbox fallback while marking sender state honestly as `successNoPeers`/`sent`.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-015 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP015')` |
| Adjacent Go topic-peer selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP015|GP014|GP005|PublishGroupMessage|liveGroupTopicPeerSet|waitForLiveGroupTopicPeer')` |
| Focused GP-015 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-015'` |
| Hygiene | `gofmt` on changed Go files, `dart format --set-exit-if-changed` on changed Dart tests, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-014 closure artifacts. GP-015 scope is limited to row-owned Go/Flutter tests, this plan, and closure documentation updates unless a regression exposes a production gap.

## Execution Progress

| Time | Phase | Files touched | Evidence |
|---|---|---|---|
| 2026-05-13 01:23:40 CEST | Executor/QA completed | `go-mknoon/node/pubsub_delivery_test.go`; `test/features/groups/application/send_group_message_use_case_test.dart` | Added `TestGP015ConnectedHostPeerDoesNotCountAsLiveTopicPeer` and Flutter test `GP-015 zero live topic peers keep durable fallback`. The Go test proves B is host-connected but absent from `topic.ListPeers`, publish returns `peerCount == 0`, sender diagnostics report `topicPeers == 0`, and B receives no group event. The Flutter test proves bridge `topicPeers: 0` stores `group:inboxStore`, persists `sent`/`inboxStored`, clears retry/wire payloads, and returns `successNoPeers`. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-015 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP015'` passed (`ok github.com/mknoon/go-mknoon/node 2.745s`). |
| Adjacent Go topic-peer selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP015\|GP014\|GP005\|PublishGroupMessage\|liveGroupTopicPeerSet\|waitForLiveGroupTopicPeer'` passed (`ok github.com/mknoon/go-mknoon/node 3.323s`). |
| Focused GP-015 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-015'` passed (`+1`). |
| Hygiene | `gofmt` passed on `go-mknoon/node/pubsub_delivery_test.go`; `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` passed (`0 changed`); `git diff --check` passed. |

## Final Verdict

Accepted/closed. GP-015 is `Covered` by tests-only Go and Flutter evidence: a libp2p host connection does not count as a live group topic peer, publish peer count is based on `topic.ListPeers`, and the app still stores durable inbox fallback with honest `successNoPeers`/`sent` state when live topic peers are zero. Residual-only none for GP-015; no `accepted_with_explicit_follow_up` is used.

## Closure Bar

- Source row GP-015 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 114, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-015 ownership and does not mask a repo-owned blocker.
