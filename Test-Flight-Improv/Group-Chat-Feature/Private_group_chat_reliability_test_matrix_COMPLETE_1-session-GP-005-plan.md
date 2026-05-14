# GP-005 Session Plan: Zero Topic Peers Still Succeeds

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-005`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 00:33:04 CEST | Controller | Source matrix GP-005 row; breakdown row 108; production `go-mknoon/node/pubsub.go::PublishGroupMessage`; production `lib/features/groups/application/send_group_message_use_case.dart`; existing Go `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers`; existing Flutter WU-3 zero-peer fallback tests | Evidence-gated row remains Open because existing tests are adjacent/generic and the row lacks exact `GP-005` proof tying Go zero-peer publish success to app-layer durable inbox fallback and honest sender status. Production already appears to implement the required behavior. | Add row-named Go and Flutter regressions. No production code change is expected unless row-owned tests expose a gap. |

## Scope

GP-005 owns the zero live-topic peer publish path. It must prove that Go publish succeeds and reports peer count zero when PubSub publish succeeds, and that the app send use case treats that result as an honest durable fallback send by storing relay inbox custody and not marking the row failed.

Out of scope: UI presentation wording for not-live/fallback states, retry policy beyond the first durable store, multi-device relay fixture proof, and later GO/GE rows that own broader offline recovery/status semantics.

## Execution Contract

1. Add a row-owned Go node regression named `TestGP005PublishWithZeroTopicPeersStillSucceedsAndReportsZero`.
2. Add a row-owned Flutter application regression named with `GP-005` in `send_group_message_use_case_test.dart`.
3. Go proof must join a single-node group, publish with no other topic peers, and assert no error, non-empty message id, and `peerCount == 0`.
4. Flutter proof must force `group:publish` to return `ok: true` and `topicPeers: 0`, assert `SendGroupMessageResult.successNoPeers`, persisted status `sent`, `inboxStored == true`, cleared retry payload, and `group:inboxStore` custody for the message.
5. Capture flow/timing evidence for `success_no_peers` with `topicPeers: 0`.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-005 Go regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP005')` |
| Adjacent Go publish selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP005|ReturnsPeerCountZero|PublishGroupMessage|GroupPeerDiscoveryLoop|KnownGroupMemberDial')` |
| Focused GP-005 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-005'` |
| App zero-peer fallback selector | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name '0-peer'` |
| Hygiene | `gofmt` on changed Go files, `dart format --set-exit-if-changed` on changed Dart tests, and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: existing rollout worktree is dirty with prior matrix, Go, Flutter, integration, and plan-file changes; GP-005 will only add row-owned test deltas plus this plan and closure doc updates.

## Closure Bar

- Source row GP-005 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 108, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is explicitly outside GP-005 ownership and does not mask a repo-owned blocker.

## Execution Progress

| Time | Phase | Result |
|---|---|---|
| 2026-05-13 00:36:33 CEST | Implementation completed | Added `go-mknoon/node/pubsub_delivery_test.go::TestGP005PublishWithZeroTopicPeersStillSucceedsAndReportsZero` and `test/features/groups/application/send_group_message_use_case_test.dart` test `GP-005 zero topic peers records durable fallback custody`. No production code changed because existing Go publish and Flutter send-result matrix already satisfied the row. |
| 2026-05-13 00:36:33 CEST | Closure completed | Source matrix GP-005 and breakdown row 108 were updated to `Covered`/`covered/accepted` with exact row-owned Go, Flutter app, and focused integration evidence. |

## Gate Evidence

| Gate | Result |
|---|---|
| Focused GP-005 Go regression | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGP005'` passed (`ok github.com/mknoon/go-mknoon/node 0.580s`). |
| Adjacent Go publish selector | `GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GP005\|ReturnsPeerCountZero\|PublishGroupMessage\|GroupPeerDiscoveryLoop\|KnownGroupMemberDial'` passed (`ok github.com/mknoon/go-mknoon/node 12.517s`). |
| Focused GP-005 Flutter regression | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-005'` passed (`+1`). |
| App zero-peer fallback selector | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name '0-peer'` passed (`+14`). |
| Focused integration fallback proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'publish with zero peers falls back to inbox'` passed (`+1`). |
| Hygiene | `gofmt` on `go-mknoon/node/pubsub_delivery_test.go`, `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart`, and `git diff --check` passed. |

## Final Verdict

`accepted` / `closed`. GP-005 is covered by exact row-owned Go and Flutter proof. The Go regression proves a zero-live-peer topic publish succeeds and reports `peerCount == 0`; the Flutter application regression proves `topicPeers: 0` returns `successNoPeers`, persists sender status `sent`, records `inboxStored == true`, clears the retry payload, and stores a durable `group:inboxStore` payload for the recipient. Existing focused integration proof confirms the recipient later drains the inbox fallback. Residual-only: none for GP-005. GI-031 remains the next unresolved P0 row; no final program verdict is written.
