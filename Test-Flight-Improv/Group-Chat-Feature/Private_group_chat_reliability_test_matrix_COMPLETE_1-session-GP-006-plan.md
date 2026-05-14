# GP-006 Session Plan: Partial Peers Refresh Before Send

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-006`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:41:13 CEST | Controller | Source matrix GP-006 row; breakdown row 109; production `go-mknoon/node/pubsub.go::ensureGroupTopicPeersBeforePublish`; production `lib/features/groups/application/send_group_message_use_case.dart`; existing Go warm-retry tests; existing Flutter `partial delivery with inbox drain completion` integration proof | Implementation-ready row remains Open because existing partial-peer coverage is adjacent/generic and does not explicitly own GP-006. Current production appears to dial known members during publish preflight and to store durable inbox fallback even when `topicPeers > 0`. | Add exact GP-006 Go and Flutter application regressions, then rerun the existing focused integration proof. No production code change is expected unless the row-owned tests expose a gap. |

## Scope

GP-006 owns publish behavior when at least one recipient is already live in the topic but another known recipient is missing. It must prove that Go publish preflight dials known missing members before publishing, that returned `topicPeers` can increase, and that the app send path still stores durable inbox fallback for recipients that may not have received live fanout.

Out of scope: relay-fallback diagnostics when host connection succeeds but topic subscription stays missing, discovery filtering policy, retry of failed inbox stores after a failed durable store, UI status labels, and broader offline replay cursor behavior beyond the focused fallback proof.

## Execution Contract

1. Add row-owned Go node regression `TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend`.
2. Build a three-member private chat group where A initially sees only B as a live topic peer, then learns C's direct addresses immediately before publish.
3. Publish from A and assert the publish preflight emits `publish_peer_refresh_begin` with `topicPeers == 1`, dials/refreshes known members, emits `publish_peer_refresh_done` with promoted peer count, returns `peerCount >= 2`, and both B and C receive the message once.
4. Add row-owned Flutter application regression named with `GP-006` in `send_group_message_use_case_test.dart`.
5. Force bridge `group:publish` to return `topicPeers: 1` with two recipients in membership and assert the send succeeds as normal `success`, persists `sent` with `inboxStored == true`, and stores `group:inboxStore` recipient ids for both recipients.
6. Rerun the existing focused integration proof `partial delivery with inbox drain completion` to cover one live recipient plus offline recipients draining from inbox fallback.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-006 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP006')` |
| Adjacent Go publish refresh selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP006|PublishGroupMessage|GroupPeerDiscoveryLoop|KnownGroupMemberDial|publish_peer_refresh')` |
| Focused GP-006 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-006'` |
| Focused partial-delivery integration proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'` |
| Hygiene | `gofmt` on changed Go files, `dart format --set-exit-if-changed` on changed Dart tests, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-005 closure artifacts. GP-006 scope is limited to row-owned tests, this plan, and closure documentation updates unless a regression exposes a production gap.

## Closure Bar

- Source row GP-006 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 109, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-006 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:43:54 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP006PublishWithPartialPeersRefreshesKnownMembersBeforeSend` and `test/features/groups/application/send_group_message_use_case_test.dart` test `GP-006 partial peers keep durable fallback for recipients`. No production code changed because existing Go publish preflight and Flutter durable inbox behavior already satisfied the row. |
| 2026-05-13 00:43:54 CEST | Closure completed | Source matrix GP-006 and breakdown row 109 were updated to `Covered`/`covered/accepted` with exact row-owned Go, Flutter app, and focused integration evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-006 Go regression | Initial assertion version failed on a delayed already-live peer dial-success event; the test was tightened to wait for the missing peer's specific dial-success event. Rerun `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP006'` passed (`ok github.com/mknoon/go-mknoon/node 0.626s`). |
| Adjacent Go publish refresh selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP006\|PublishGroupMessage\|GroupPeerDiscoveryLoop\|KnownGroupMemberDial\|publish_peer_refresh'` passed (`ok github.com/mknoon/go-mknoon/node 11.227s`). |
| Focused GP-006 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-006'` passed (`+1`). |
| Focused partial-delivery integration proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'partial delivery with inbox drain completion'` passed (`+1`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go`, `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart`, and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-006 is covered by exact row-owned Go and Flutter proof. The Go regression proves publish preflight starts from one live topic peer, dials the missing known member before publish, promotes topic peers to at least two, and delivers the same message to both recipients. The Flutter application regression proves a partial live fanout result (`topicPeers: 1`) still records successful sender state and durable inbox custody for all recipient peer ids. Existing focused integration proof confirms one online recipient receives before drain and offline recipients receive once after inbox drain. Residual-only: none for GP-006. GI-031 remains the next unresolved P0 row; no final program verdict is written.
