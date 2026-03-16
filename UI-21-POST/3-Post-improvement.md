# Posts Improvement

Prepared on: 2026-03-15  
Prepared by: Codex  
Scope: Posts prioritization separate from Group Messages

## Why This File Exists

This file captures the current Posts send architecture, the concrete improvements available with the existing codebase, and the longer-term architecture choices.

This file should be used as the main prioritization artifact for performance work between:
- `Group Messages`
- `Posts`

Current conclusion:
- `Posts` should be prioritized first
- the current Posts architecture is the main sender-side latency bottleneck

## Current State In This Codebase

### What we have today

Posts is currently implemented as app-owned per-recipient delivery over the existing single-peer send APIs:
- send entry point: `lib/features/posts/application/send_post_use_case.dart`
- media preparation and upload: `lib/features/posts/application/attach_post_media_use_case.dart`
- incoming ingest: `lib/features/posts/application/handle_incoming_post_use_case.dart`
- composer UI: `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
- Posts screen orchestration: `lib/features/posts/presentation/screens/posts_wired.dart`

This is explicitly aligned with the current Posts plan:
- `UI-21-POST/Plan-Phases.md` says Posts should be built over existing direct send and inbox paths and should not be treated as a bulk-broadcast primitive

### Current send flow

The send path today is:
1. validate sender and audience
2. resolve eligible recipients
3. create the local `PostModel` with `deliveryStatus: 'sending'`
4. create per-recipient delivery rows
5. if media exists, prepare and upload media before send completes
6. build a per-recipient wire envelope
7. for each recipient, try direct send, then inbox fallback
8. aggregate result into `sent`, `partial`, or `failed`

Relevant code:
- recipient resolution: `lib/features/posts/application/send_post_use_case.dart`
- media attach/upload: `lib/features/posts/application/attach_post_media_use_case.dart`
- recipient delivery loop: `lib/features/posts/application/send_post_use_case.dart`

### Current audience model

Posts currently supports dynamic ad hoc audiences:
- `allFriends`
- `peopleNearby`
- `pickPeople`

Relevant code:
- `lib/features/posts/domain/models/post_audience.dart`

This matters because Posts is not modeled as a long-lived shared channel. It is modeled as a snapshot delivered to a computed audience for one post.

### Current UI behavior

Posts does some optimistic local persistence, but not full optimistic UX:
- the post is saved locally as `sending`
- the compose sheet still stays open with `Posting...`
- the user must wait for the whole send pipeline to finish before the sheet closes

That is why Posts feels slow even when local persistence has already happened.

Relevant code:
- `lib/features/posts/presentation/widgets/compose_post_sheet.dart`
- `lib/features/posts/presentation/screens/posts_wired.dart`

## Why Posts Feels Slower Than 1:1 And Group Chat

### 1. Posts is still effectively serial

The current implementation delivers recipient-by-recipient in a loop.

That means the sender pays per-recipient cost for:
- envelope construction
- optional per-recipient encryption
- direct send attempt
- inbox fallback if direct send fails

### 2. Posts does more critical-path work before completion

The current send path includes:
- audience resolution
- optional nearby eligibility logic
- local DB writes for post and recipient deliveries
- media preparation and upload
- per-recipient network delivery

### 3. Posts does not use the full chat transport fast path

`1:1` chat currently has a stronger delivery strategy:
- reuse existing connection if present
- race local WiFi and direct relay send
- probe relay when discoverability is stale
- use inbox fallback
- retry failed or unacked sends later

Posts currently skips most of that and calls `sendMessageWithReply(...)` directly for each recipient, then falls back to inbox.

Relevant code:
- chat fast path: `lib/features/conversation/application/send_chat_message_use_case.dart`
- Posts direct send: `lib/features/posts/application/send_post_use_case.dart`

### 4. Follow-on Post events inherit the same fanout model

The same per-recipient pattern appears in:
- post reactions
- comments
- comment reactions
- pass-along
- pin updates
- presence updates

Relevant code:
- `lib/features/posts/application/send_post_reaction_use_case.dart`
- `lib/features/posts/application/send_post_comment_use_case.dart`
- `lib/features/posts/application/send_post_comment_reaction_use_case.dart`
- `lib/features/posts/application/pass_post_along_use_case.dart`
- `lib/features/posts/application/post_pin_delivery_support.dart`
- `lib/features/posts/application/publish_post_presence_update_use_case.dart`

## What We Can Improve With The Current Codebase

These improvements are intentionally based on code that already exists in the repo.

## Priority 1: Make Posts fully optimistic from the user perspective

Recommended change:
- save the local post and recipient-delivery records
- dismiss the composer immediately
- show the post in-feed with a sending or partial-send state
- continue delivery in the background

Why:
- this removes the biggest perceived delay without changing the wire model
- the codebase already has local persistence and feed reload primitives

This should be the first improvement.

## Priority 2: Replace serial fanout with bounded parallel fanout

Recommended change:
- do not keep strict one-recipient-at-a-time delivery
- do not use unbounded `Future.wait(...)` either
- use a small concurrency pool, for example `4-8` recipients at a time

Why bounded concurrency:
- each recipient may require per-recipient encryption
- each recipient causes bridge and DB work
- the bridge does not expose an explicit batching or backpressure contract

There is already repo precedent for safe parallel independent sends:
- group invites use parallel send in `lib/features/groups/application/send_group_invite_use_case.dart`

This should be the second improvement.

## Priority 3: Reuse the `1:1` transport engine, not the full `1:1` chat use case

Recommended change:
- extract a lower-level helper such as `deliverEnvelopeToPeer(...)`
- reuse the mature `1:1` transport behavior:
  - connection reuse
  - local WiFi fast path
  - direct discover/dial race
  - relay probe
  - inbox fallback

Why:
- `1:1` chat already has the most mature single-peer delivery logic in the app
- Posts should reuse that transport strategy for each recipient

What to avoid:
- do not call `sendChatMessage(...)` directly from Posts
- `sendChatMessage(...)` is conversation-specific and persists `ConversationMessage`

This should be the third improvement.

### Why reuse the transport engine and not the full `1:1` chat use case

The distinction matters.

What is reusable from `1:1` chat:
- how to deliver one opaque envelope to one peer efficiently
- how to choose between local WiFi, direct send, relay probe, and inbox fallback
- how to later retry unfinished delivery states

What is not reusable as-is:
- chat payload construction
- chat repository writes
- chat message status semantics
- chat attachment semantics
- chat-specific UI and persistence model

The current `sendChatMessage(...)` use case does chat-specific work:
- it builds `MessagePayload`
- it persists `ConversationMessage`
- it writes to chat repositories
- it assumes one conversation target, not one Post with many recipients

Posts needs different business objects:
- `PostModel`
- `PostRecipientDelivery`
- `PostCreateEnvelope`
- post-specific engagement and recipient-set semantics

So the right move is not to call the full chat use case from Posts. The right move is to extract the lower-level delivery engine from the chat path and reuse that engine inside Posts fanout.

## Priority 4: Add a Posts delivery retrier

Recommended change:
- introduce a Posts-owned retry service similar in spirit to `PendingMessageRetrier`
- retry failed or unfinished recipient deliveries when the node comes back online
- allow direct-to-inbox fallback on delayed recovery

Why:
- chat already has retry infrastructure
- Posts currently has very little sender-side recovery after the first attempt

This improvement becomes more valuable after background delivery is added.

## Priority 5: Reduce media cost in the critical path

Recommended change:
- where safe, parallelize attachment preparation and upload for multi-image Posts
- keep using shared media helpers instead of creating a Posts-only media stack
- move as much media work as possible out of the blocked composer path

Why:
- media is not the only problem, but it amplifies the send delay significantly

## Priority 6: Update follow-on Post event fanout to match the new delivery engine

After the base post-send improvement lands, the same transport helper and bounded concurrency model should also be used by:
- reactions
- comments
- comment reactions
- pin updates
- pass-along

That keeps the whole Posts feature internally consistent.

## What We Should Avoid

### Do not use unbounded parallel fanout

This would likely create avoidable pressure in:
- bridge calls
- encryption work
- SQLite writes
- device/network resource usage

### Do not directly swap Posts onto the current group-chat transport

That would be a product-model change, not just a transport optimization.

The current group system assumes:
- explicit membership
- group keys
- topic join and rejoin
- group inbox recovery
- stable group identity

Posts currently assumes:
- one post can target a dynamically computed audience
- the audience can differ per post
- recipient sets are stored as part of post semantics

This mismatch is especially strong for:
- `peopleNearby`
- `pickPeople`

### Do not call the current conversation send use cases from Posts

Reuse lower-level delivery behavior, not higher-level conversation models.

If Posts directly called the current `1:1` chat send use case, it would either:
- persist fake chat messages for every Post recipient, which is wrong
- or force the chat use case to absorb Post-specific branching until it stops being a clean chat use case

Both outcomes are worse than extracting a shared peer-delivery helper.

## Comparison With Status And Berty

External comparison verified on 2026-03-15 using official docs.

### Status

Status separates two different problems:
- smaller private group messaging is close to pairwise `1:1` secure-channel behavior
- larger shared spaces use community and channel infrastructure over Waku topics and shards

What that means for this codebase:
- current Posts is still closer to app-owned targeted delivery than to a real shared feed channel
- current Posts therefore resembles a pairwise fanout strategy more than a true community/channel publish system

### Berty / Wesh

Berty/Wesh is group-first and log-oriented:
- shared group context
- group-scoped messaging and metadata
- durable shared-space mindset

What that means for this codebase:
- Berty-like architecture is a better fit for durable shared channels than for one-off dynamic audiences
- it is not a drop-in match for the current Posts semantics

## How We Differ Today

Compared with Status communities or Berty/Wesh group-style systems:
- Posts has no long-lived audience primitive
- Posts has no publish-once shared feed/channel primitive
- Posts is still sender-owned recipient fanout
- engagement routing depends on the stored recipient set from the original post

That last point is important. Receivers persist `recipientPeerIds`, and later Post engagements rely on that stored audience state.

Relevant code:
- `lib/features/posts/domain/models/post_create_envelope.dart`
- `lib/features/posts/application/handle_incoming_post_use_case.dart`

## Better Long-Term Architecture

### Near-term architecture

The right near-term architecture is:
- keep current Post semantics
- make delivery optimistic and backgrounded
- use bounded parallel fanout
- use the chat transport engine per recipient
- add sender-side retry and better delivery state

This gives the highest ROI with the least product risk.

### Long-term architecture

Long term, Posts should likely split into two different publish models.

### Model A: targeted ad hoc Posts

Use this for:
- `pickPeople`
- some `peopleNearby` cases
- other one-off recipient-specific sharing

Delivery model:
- bounded per-recipient delivery
- recipient-aware semantics
- stored recipient set remains part of the contract

### Model B: durable feed channels or circles

Use this for:
- `allFriends` if it becomes a real shared feed
- future circles, communities, or channels
- larger shared audiences with repeated posting

Delivery model:
- explicit channel identity
- membership and key management
- publish-once semantics
- channel-scoped history and replay
- channel-scoped engagement instead of per-post recipient copying

This is the model that is closer to what Status communities and Berty-like shared spaces suggest.

### Important long-term note

If we build this future model, it should not be implemented as "Posts now uses the current group chat feature directly."

Instead, it should be a distinct `post channel` or `community feed` primitive that may reuse some of the same lower-level group or pubsub infrastructure, but with post-specific semantics, moderation, history, and audience rules.

## Priority Conclusion

For feature prioritization:
- `Posts` is the current sender-side performance problem
- `Group Messages` already has the correct high-level send shape

Recommended order:
1. improve Posts UX with optimistic dismiss and background delivery
2. add bounded parallel Posts fanout
3. reuse the `1:1` peer-delivery engine inside Posts, not the full chat use case
4. add Posts retry and richer delivery states
5. only after that, evaluate whether the product needs a new long-lived post-channel architecture

## External References

- Status 1-to-1 / private group direction: `https://status.app/specs/status-1to1-chat`
- Status scaling direction: `https://status.app/specs/status-simple-scaling`
- Status communities: `https://status.app/specs/status-communities`
- Berty protocol overview: `https://berty.tech/ar/docs/protocol`
- Weshnet API surface: `https://pkg.go.dev/berty.tech/weshnet/v2`
