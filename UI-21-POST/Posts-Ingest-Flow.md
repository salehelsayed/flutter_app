# Posts Ingest Flow

Status: Proposed v1 implementation baseline  
Baseline date: 2026-03-15  
Approval record: `UI-21-POST/Phase-0-Approval.md`  
Companion docs:
- `UI-21-POST/Posts-Envelope-Schemas.md`
- `UI-21-POST/Posts-Feed-Rules.md`
- `UI-21-POST/Posts-Nearby-Privacy-Contract.md`

This document defines how Posts events move from transport to repository, how notification-open targeting works, and how duplicates or missing parents are handled.

## Canonical Rule

Live delivery, offline replay, and push-triggered wake-up must all converge into the same typed ingest use case path. No Posts event may bypass repository ingest just because it arrived through a notification flow.

## Route Targets

All notification-open paths normalize into one of these route-target payloads:

- `post:<post_id>`
- `post_comment:<post_id>:<comment_id>`

These route targets are stored in one pending-target handoff state before UI routing.

## Canonical Ingest Stages

1. Router parses the raw message into a typed Posts stream.
2. Typed listener validates sender and payload shape.
3. Listener calls the feature ingest use case.
4. Use case dedupes by `event_id` and logical entity rules.
5. If parent post is missing for a child event, stage it.
6. Persist accepted state to the Posts repository.
7. Reconcile staged child events immediately after a parent post becomes available.
8. Emit repository updates for UI consumers.
9. Evaluate notification side effects only after persistence.

## Flow 1: Live `post_create`

```text
transport receive
-> IncomingMessageRouter
-> postCreateStream
-> PostListener
-> HandleIncomingPostUseCase
-> dedupe by post_id / event_id
-> save post
-> reconcile staged child events
-> emit feed update
```

Rules:
- A duplicate live `post_create` for the same `post_id` does not create a second card.
- Attachment hydration may continue after the post row is persisted, but the post must exist locally before hydration begins.

## Flow 2: Offline Replay

```text
startup / resume / push wake
-> drainOfflineInbox()
-> router emits typed streams
-> same typed listeners
-> same ingest use cases
-> same repository writes
```

Rules:
- Replay may arrive interleaved with live traffic.
- Replay uses the same dedupe rules as live delivery.
- `drainOfflineInbox()` completion is not a replay-complete signal for UI focus because the current service only waits for the first page before continuing in background.

## Flow 3: Notification-Open Target Handoff

### Sources

- local notification tap
- `FirebaseMessaging.onMessageOpenedApp`
- `getInitialMessage`
- Android local fallback notification cold start

### Canonical behavior

1. Parse or normalize the route target.
2. Store it in pending-target state.
3. Trigger inbox drain.
4. Wait for the repository to observe the target post.
5. When observed:
   - select the Posts tab
   - scroll or focus the target card
   - open the comments sheet if the route target is `post_comment:*`
6. If the target is not observed before timeout:
   - still open the Posts tab
   - show a transient "Finishing catch-up..." fallback state
   - keep listening for the target until the pending state expires

### Timeout rule

- Pending target wait budget: 5 seconds from the time drain is triggered
- Pending target expiry: 30 seconds from the original open event

The user must never be routed straight to a post detail before local persistence exists.

## Flow 4: Orphan Child Events

Child events:
- `post_comment`
- `post_reaction`
- `post_comment_reaction`
- `post_pin_update`
- `post_pin_remove`

Canonical behavior:

```text
child event arrives
-> parent post missing
-> persist staged row keyed by (post_id, event_type, event_id)
-> no user-visible mutation yet
-> parent post later ingested
-> reconcile staged rows in created_at/event_id order
-> mark staged rows consumed
```

Rules:
- Orphan child events are never dropped just because the parent post is missing at first arrival.
- Parent-dependent validation still applies after staging. For `post_pin_update` and `post_pin_remove`, reconciliation must reject the event if `sender_peer_id` does not match the original post author for `post_id`.
- Reconciliation must be idempotent.

## Flow 5: Duplicate and Conflict Handling

### `post_create`

- Dedupe by `post_id`
- First valid create wins as the base row
- Later duplicate creates may refresh equivalent metadata only if the snapshot matches the accepted row

### Comments

- Dedupe by `comment_id`
- Exact duplicates are ignored

### Reactions

- Dedupe by `event_id`
- Current logical state keyed by `reaction_id`
- Latest `created_at`, then lexicographically larger `event_id`, wins

### Pass along

- Dedupe by `pass_id`
- Feed merge behavior is governed by `Posts-Feed-Rules.md`

### Pins

- Current logical state keyed by `post_id`
- Accept only author-originated pin events. `post_pin_update` and `post_pin_remove` are valid only when `sender_peer_id` matches the original post author for `post_id`.
- Latest valid pin event wins
- `post_pin_remove.reason` is the single v1 value `removed`
- `post_pin_remove` tombstones active pin state only

### Presence

- Current logical state keyed by `sender_peer_id`
- Latest presence event wins

## Flow 6: Reconciliation After `post_create`

When a parent post is saved:

1. Load staged child events for `post_id`
2. Sort by `created_at`, then `event_id`
3. Apply each staged event through the same typed ingest logic used for normal arrivals
4. Mark staged rows consumed or delete them
5. Emit one consolidated repository update after reconciliation completes

## Flow 7: Pass-Along Ingest

```text
transport receive
-> router emits post_pass
-> pass listener validates sender is direct contact
-> verify sender matches passer_peer_id
-> verify original snapshot is renderable
-> merge against local post/pass state
-> emit one feed item per original post identity
```

Rules:
- A pass envelope never triggers network reconstruction of the original post.
- If the receiver already has the original post directly, no second visible card is created.

## Flow 8: Notification Side Effects

Notification decisions happen after persistence.

- direct post create: eligible for post notification
- new comment or heart: eligible for author-side notification
- archived sender: persist but suppress visible notification
- blocked sender: reject before persistence and before notification logic

## Failure Handling

- Invalid payload: reject and log
- Sender validation failure: reject and log
- Repository failure: do not mark the event consumed; allow replay to retry later
- Hydration failure: keep the post row and attachment metadata, then retry through media restore logic

## Acceptance Summary

This ingest flow is correct only if:
- live, replay, and wake-up reuse the same ingest path
- notification-open waits for repository observation, not transport completion
- orphan child events are staged, not dropped
- duplicate deliveries never create duplicate cards
