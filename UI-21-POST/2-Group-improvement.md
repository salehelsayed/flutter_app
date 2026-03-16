# Group Messages Improvement

Prepared on: 2026-03-15  
Prepared by: Codex  
Scope: group-message prioritization separate from Posts

## Why This File Exists

This file is the group-message companion to `UI-21-POST/3-Post-improvement.md`.

The goal is to keep prioritization clear:
- `Group Messages` should focus on explicit-member conversations, reliability, and larger-group evolution.
- `Posts` should focus on feed-style publishing, ad hoc audiences, and fanout cost.

At the moment, group messaging is not the main latency bottleneck in the app. It already has a better send shape than Posts. Group work should therefore be prioritized behind Posts performance work unless a specific reliability or scale issue appears.

## Current State In This Codebase

### What we have today

Group messages are already using a dedicated group transport path, not the `1:1` send path:
- group send entry point: `lib/features/groups/application/send_group_message_use_case.dart`
- optimistic UI insert: `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- bridge group publish helpers: `lib/core/bridge/bridge_group_helpers.dart`
- group recovery and inbox replay: `lib/features/groups/application/group_invite_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/rejoin_group_topics_use_case.dart`

### Current send behavior

The current group send path is materially better than the current Post send path:
- the UI creates and persists an optimistic local message immediately with `status: 'sending'`
- the send use case performs one `group:publish` call to the group topic
- offline inbox persistence runs in parallel through `group:inboxStore`
- the sender does not loop over every group member when sending a normal group message

Relevant code:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`

### Why it feels faster than Posts

Group messaging is effectively `O(1)` for foreground send from Flutter:
- one topic publish
- one concurrent inbox-store side path
- one optimistic local insert

Posts is currently `O(N)` from Flutter for send, because it loops recipient-by-recipient.

## What Is Already Good

### 1. Explicit group semantics already exist

Groups already have:
- membership
- roles
- keys and key rotation
- topic join and rejoin logic
- offline recovery primitives

That makes groups the correct primitive for durable, explicit-member conversations.

### 2. Normal group send does not do sender-side fanout

This is the most important architectural property to preserve.

The sender publishes once to the group topic. That is the right shape for group messaging and one of the main reasons group messages feel responsive.

### 3. The current design is already closer to group-first systems

Compared with external systems, the current group model is closer to Berty/Wesh than to a pairwise `1:1` expansion model:
- explicit group identity
- explicit group membership
- group-scoped keys
- publish-once group transport

## Current Gaps

These are the main things that still look weaker than the chat stack or than a future large-group architecture.

### 1. Delivery visibility is coarse

The sender treats a successful publish as success, but there is no rich per-message delivery surface comparable to `1:1` chat transport states.

Practical implication:
- the app knows that local publish succeeded
- it does not expose richer recipient-level outcome states for group messages

### 2. Retry behavior is not as developed as `1:1`

`1:1` chat has stronger retry machinery through:
- `lib/core/services/pending_message_retrier.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`

Group messaging does not currently have the same style of sender-side retry orchestration for failed outgoing group messages.

### 3. Media sending still pays upload cost before the message is complete

The group send UI is optimistic, but media still needs to be prepared and uploaded before the final publish path completes.

This is not the main bottleneck today, but it is still a place where perceived send cost can grow.

### 4. Large-group scaling features are still limited

The current implementation is solid for explicit groups, but it does not yet show large-scale channel/community features such as:
- partitioned topics
- long-lived history service
- community-style shards or channels
- more advanced backlog or server-assisted catch-up

## Improvements We Can Do With What We Already Have

These improvements stay within the current group model and reuse existing codebase patterns.

### Priority 1: keep the current send model, add stronger reliability

Recommended work:
- add a group-message retry queue for outgoing messages that fail publish or inbox-store
- persist richer transient send state for failed and retrying outgoing group messages
- align group retry orchestration with the existing chat retrier pattern

Why:
- this strengthens reliability without changing group semantics
- it is lower-risk than changing transport shape

### Priority 2: improve observability and recovery

Recommended work:
- add clearer instrumentation around `group:publish`, `group:inboxStore`, replay, and rejoin paths
- explicitly surface whether failures came from publish, offline-store, recovery, or key issues
- add focused tests around app resume, topic rejoin, and delayed inbox replay

Why:
- group systems usually fail at recovery edges, not the happy-path send

### Priority 3: optimize media path where needed

Recommended work:
- review whether attachment preparation can be parallelized per selected item
- ensure group media upload path stays shared with existing app media primitives instead of forking logic

Why:
- media cost matters, but it is secondary to reliability and recovery

### Priority 4: parallelize the places where group code already does member-specific work

This is already partly present in the repo:
- group invites already use parallel sending in `lib/features/groups/application/send_group_invite_use_case.dart`

We should keep applying that pattern where the work is truly per-member and independent:
- invites
- key updates
- other membership-control envelopes

We should not add member-by-member fanout to normal group messages.

## What We Should Avoid

### Do not regress group messages into `1:1` pairwise fanout

That would make normal group send behave more like Posts:
- more sender-side work
- more encryption and network calls per message
- worse latency as member count grows

This is the wrong direction for this codebase.

### Do not use Posts as the model for group evolution

Posts today is an app-owned per-recipient fanout system. Group messages should remain publish-once and membership-owned.

## Comparison With Status And Berty

External comparison verified on 2026-03-15 using official docs.

### Status

Status separates small private groups from larger community-scale spaces:
- smaller private group chat is closer to pairwise secure-channel logic
- larger shared spaces move toward community/channel infrastructure over Waku topics and shards

What that means for us:
- our current group implementation is already past the naive pairwise model
- if we need very large-group or community behavior later, the likely destination is a channel/community layer, not more pairwise fanout

### Berty / Wesh

Berty/Wesh is group-first:
- a group is the core primitive
- messaging and metadata are group-scoped
- the architecture is oriented around shared group context and shared logs/stores

What that means for us:
- our current group direction is philosophically closer to Berty than to per-recipient message copying
- that is a good sign for group chat

## How We Differ Today

Compared with Status and Berty, this codebase currently differs in a few important ways:
- group messaging is implemented as an app + bridge feature, but not yet as a broader community or channel platform
- recovery exists, but the sender-side reliability and observability story is thinner than the `1:1` chat path
- there is no separate large-scale community architecture yet

## Better Long-Term Architecture For Group Messages

### Short to medium term

The right direction is:
- keep current group-topic send semantics
- strengthen retry and recovery
- improve media and instrumentation where useful

### Long term

If the product needs very large shared spaces, add a separate `community/channel` layer on top of the current app architecture.

That future layer should look more like:
- explicit channels inside a larger space
- publish-once semantics
- stronger history and catch-up support
- clearer moderation and role controls
- optional partitioning/sharding for scale

This should be treated as a distinct evolution of `Groups`, not as an extension of `Posts`.

## Priority Conclusion

For prioritization across features:
- `Group Messages` already has the correct core send shape
- `Posts` is the feature that currently pays the largest sender-side performance penalty

Recommendation:
- prioritize `Posts` performance and architecture work first
- prioritize `Group Messages` for reliability, recovery, and future channel/community scale second

## External References

- Status 1-to-1 / private group direction: `https://status.app/specs/status-1to1-chat`
- Status scaling direction: `https://status.app/specs/status-simple-scaling`
- Status communities: `https://status.app/specs/status-communities`
- Berty protocol overview: `https://berty.tech/ar/docs/protocol`
- Weshnet API surface: `https://pkg.go.dev/berty.tech/weshnet/v2`
