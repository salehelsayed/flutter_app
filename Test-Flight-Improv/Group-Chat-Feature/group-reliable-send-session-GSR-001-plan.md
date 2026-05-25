# Reliable Group Send GSR-001 Plan

Status: accepted

## Real Scope

Add a native `SendGroupMessageReliable` path for ordinary group messages. Keep reaction/system durable replay behavior out of scope. Preserve existing `group:publish` and `group:inboxStore` commands for compatibility and retry flows.

## Closure Bar

The normal group send path can use one bridge command that returns `messageId`, `topicPeerCount`, `expectedRecipientCount`, `inboxStored`, `publishSucceeded`, and `deliveryMode`. Flutter persists `sent` only when inbox storage succeeded or live fanout count covers every expected active recipient.

## Source Of Truth

Current code wins over stale docs. Main owner files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

## Session Classification

implementation-ready

## Exact Problem Statement

`PublishGroupMessage` builds a live PubSub envelope while `GroupInboxStore` accepts an unrelated opaque message and caller-supplied recipients. The app can therefore diverge live and durable payloads or compute the durable recipient set outside native group config. The fix must build one native live envelope once, store that exact envelope for the native active recipient set, publish it, and report enough evidence for UI status.

## Existing Tests Covering This Area

Go tests cover publish validation, group inbox request shape, and bridge publish/inbox commands separately. Flutter tests cover the existing fanout/inbox matrix, including zero-peer durable success and partial fanout diagnostics.

## Regression/Tests To Add First

1. Go node test: reliable send stores the exact v3 envelope it publishes, computes active device transport recipients, and returns `live_and_inbox`.
2. Go node test: no relay/inbox failure plus no topic peers returns `live_only` with `inboxStored=false` and `expectedRecipientCount`.
3. Bridge helper test: `callGroupSendReliable` sends one `group:sendReliable` command and parses returned delivery fields.
4. Flutter use-case test: partial live fanout without inbox success stays `pending`; full live fanout without inbox success may be `sent`.

## Step-By-Step Implementation Plan

1. Extract group message envelope building from `PublishGroupMessage` into a small helper.
2. Add `activeGroupInboxRecipientPeerIds` using active device `transportPeerId`s and legacy member `peerId`s, excluding the sender account.
3. Add `SendGroupMessageReliable` and `GroupReliableSendResult`.
4. Add bridge command `GroupSendReliable` and Dart helper `callGroupSendReliable`.
5. Make `sendGroupMessage` prefer the reliable command, falling back to the legacy split path only when the command is unavailable.
6. Teach offline inbox drain to decode stored v3 group envelopes so exact live envelopes stored by native reliable send remain replayable.

## Risks And Edge Cases

Deviceful inbox recipients must be transport peer IDs, not logical account IDs. Existing mobile native frameworks may not expose the new method until rebuilt, so Dart must tolerate missing native method by falling back to the old path. Storing v3 live envelopes requires offline drain compatibility.

## Exact Tests And Gates To Run

Focused first:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestSendGroupMessageReliable|TestGroupInbox'
flutter test test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/send_group_message_use_case_test.dart
```

Then targeted bridge if changed:

```bash
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupSendReliable|TestGroupPublish'
```

## Known-Failure Interpretation

Existing full `go test ./node` failures in unrelated `GI012`-`GI016`, `GA019`, `GA021`, and `GM028` are pre-existing from the previous session and should not block focused acceptance unless touched tests regress.

## Done Criteria

All new focused tests pass, existing focused publish/inbox tests still pass, docs record accepted status, and the final response names any broader gates that remain red for pre-existing reasons.

## Scope Guard

Do not redesign GossipSub, relay storage, group reactions, system event replay, push notification content, or generated native binaries in this session.

## Accepted Differences / Intentionally Out Of Scope

The legacy split commands remain supported for retry/backward compatibility. Reactions and system-event durable replay remain out of scope. The local gomobile artifacts were refreshed through the repository scripts/Makefile so the new platform wrapper route is verifiable, but the artifact paths are ignored/untracked in this checkout.

## Dependency Impact

This closes the normal message send reliability contract. Future sessions can migrate reactions/system durable replay to the same style if product scope requires it.

## Execution Summary

Implemented `SendGroupMessageReliable` in Go, with shared envelope construction for `PublishGroupMessage`, native active-recipient computation, exact-envelope inbox storage, live publish, and delivery-mode evidence. Added `GroupSendReliable` to the Go bridge, Dart helper/client mapping, iOS/macOS/Android platform routes, and Flutter send-use-case gating so "sent" requires durable inbox success or full live fanout. Added v3 group envelope decode to offline inbox drain so native-stored live envelopes replay correctly.

## Verification

- `cd go-mknoon && go test ./node -count=1 -run 'TestSendGroupMessageReliable|TestGroupTopicValidator_UsesPubSubAuthorForForwardedMessages'` passed.
- `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupSendReliable|TestGroupPublish_ResponseIncludesTopicPeers|TestGroupPublish_InvalidJSON|TestGroupPublish_MissingFields'` passed.
- `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name callGroupSendReliable` passed.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GSR-001 reliable send uses single native command and treats full live fanout as sent'` passed.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-006 partial topicPeers with inbox failure stays publish-only and retryable'` passed.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'DE-006 topicPeers matrix reports fanout without recipient receipt claim'` passed.
- `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name callGroupPublish` passed.
- `scripts/verify_gomobile_bindings.sh all` passed after local iOS/macOS/Android gomobile artifact refresh.
- `git diff --check` on touched source/doc files passed.
