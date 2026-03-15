# Posts Envelope Schemas

Status: Proposed v1 implementation baseline  
Baseline date: 2026-03-15  
Approval record: `UI-21-POST/Phase-0-Approval.md`  
Source inputs:
- `UI-21-POST/Plan-Phases.md`
- `../kitchen/landing-screen-claude/neighbourhood_spec.md`
- `UI-21-POST/screenshots/*`

This document is normative for v1 payload shape, sender validation, idempotency, and event conflict behavior.

## Common Envelope

Every Posts envelope uses this outer JSON shape:

```json
{
  "type": "post_create",
  "version": "1",
  "event_id": "evt_01JQ4V86MZ2W7S4TQ0G3C2SY8K",
  "created_at": "2026-03-15T10:15:30.000Z",
  "sender_peer_id": "12D3KooWAbCdEf...",
  "payload": {}
}
```

Required top-level fields:
- `type`: one of `post_create`, `post_comment`, `post_reaction`, `post_comment_reaction`, `post_presence_update`, `post_pass`, `post_pin_update`, `post_pin_remove`
- `version`: string, v1 is `"1"`
- `event_id`: globally unique opaque string for this state transition
- `created_at`: RFC3339 UTC timestamp with milliseconds
- `sender_peer_id`: peer id of the actor who sent this envelope
- `payload`: object matching the schema for `type`

Parsing rules:
- Unknown top-level fields are ignored.
- Missing required fields reject the envelope.
- `sender_peer_id` must match the transport sender when a transport sender is available.
- `created_at` later than `now + 5 minutes` is rejected as invalid clock skew.

## Delivery Model

- `post_create` is fanned out one envelope per recipient.
- All per-recipient copies of the same logical post reuse the same `post_id` and `event_id`.
- Send-side per-recipient delivery bookkeeping is keyed by `(post_id, recipient_peer_id)`.
- Receiver-side dedupe of `post_create` is keyed by `post_id`.
- Child events use one `event_id` per state transition and may be delivered live, by inbox replay, or both.
- Live delivery, replay, and wake-up drain all feed the same typed ingest path.

## Idempotency and Conflict Rules

### Base rules

- Envelope replay dedupe key: `event_id`
- Missing-parent child events are staged by `(post_id, event_type, event_id)` until the parent post is available.
- If two envelopes conflict on the same logical entity, the winner is:
  1. newer `created_at`
  2. lexicographically larger `event_id` when timestamps tie

### Logical entity keys

| Entity | Stable key | Conflict rule |
|---|---|---|
| Post create | `post_id` | first valid create wins, later duplicate creates merge metadata only if identical |
| Comment | `comment_id` | exact duplicate ignored |
| Post reaction | `reaction_id` | latest state event wins |
| Comment reaction | `reaction_id` | latest state event wins |
| Pass along | `pass_id` | exact duplicate ignored |
| Pin state | `post_id` | latest pin event wins |
| Presence snapshot | `sender_peer_id` | latest presence event wins |

## Sender and Trust Validation

### Direct posts and engagement

- `post_create`, `post_comment`, `post_reaction`, `post_comment_reaction`, `post_pin_update`, and `post_pin_remove` must come from:
  - the local user, or
  - a known direct contact
- Blocked direct contacts are rejected before persistence.
- Archived direct contacts may persist, but notification display is suppressed.

### Pass along

- `post_pass` must come from a known direct contact.
- `sender_peer_id` must equal the passing friend recorded in the payload.
- The embedded original author does not need to be a direct contact.
- `Pick People` posts cannot be passed along.
- V1 pass-along depth is exactly one explicit extra hop.

### Presence

- `post_presence_update` must come from a known direct contact or the local user.
- Presence is never relayed to friends-of-friends.

## Approved V1 Semantics

These are the explicit v1 defaults that the product spec did not define at wire level.

### `post_reaction`

- Heart-only reaction model.
- A post heart is an upsert state event, not a delta count event.
- Stable logical key: one heart state per `(post_id, actor_peer_id)`.
- `reaction_id` format: `post_heart:<post_id>:<actor_peer_id>`
- `is_active: true` means the heart is currently on.
- `is_active: false` means the heart was removed.
- Receivers do not increment or decrement blindly; they store the latest state for `reaction_id`.

### `post_comment_reaction`

- Same model as post heart, but target is a comment.
- Stable logical key: one heart state per `(comment_id, actor_peer_id)`.
- `reaction_id` format: `comment_heart:<comment_id>:<actor_peer_id>`
- `is_active` carries the full current state.

### `post_pin_update`

- `post_pin_update` is authoritative replace semantics for the pinned projection of a post.
- It carries the latest sender-approved renderable post snapshot for the pinned card and any mirrored normal-feed update.
- Receivers replace pinned-renderable fields with the snapshot in the latest valid `post_pin_update`.
- It is not a field patch.

### `post_pin_remove`

- `post_pin_remove` is an authoritative tombstone for pin state on one `post_id`.
- It removes the post from the pinned section.
- It does not delete the underlying post row. If the post is still within normal feed lifetime, it remains in the feed.

### Notification-open payloads

- Local notification tap payload strings use compact route targets:
  - `post:<post_id>`
  - `post_comment:<post_id>:<comment_id>`
- Remote push payloads may remain structured, but all open-paths normalize into one of those route targets before UI routing.
- Posts notification taps never open a 1:1 conversation route directly.

### Pass-along engagement

- Pass recipients can comment and heart on the passed-along post.
- Hearts and comments from pass recipients fan out to the post's effective recipient set.
- The effective recipient set becomes:
  - original author
  - original canonical recipients
  - passing friend
  - pass recipients of that one-hop delivery
- Any new comment, including one from a pass recipient, resets the original post expiry.
- Hearts never reset expiry.

## Shared Payload Fragments

### `PostAudience`

```json
{
  "kind": "all_friends",
  "radius_m": null,
  "scope_label": null
}
```

Rules:
- `kind`: `all_friends`, `people_nearby`, or `pick_people`
- `radius_m`: required only for `people_nearby`
- `scope_label`:
  - `null` for `all_friends`
  - `"Shared nearby"` for `people_nearby`
  - `"Shared with you"` for `pick_people`

### `RenderableMedia`

```json
{
  "media_id": "media_01JQ4V8M9KS4KSKWR7K8S4Q9M1",
  "blob_id": "blob_01JQ4V8M9KS4KSKWR7K8S4Q9M1",
  "kind": "image",
  "mime": "image/jpeg",
  "size_bytes": 248120,
  "width": 1440,
  "height": 1080,
  "duration_ms": null,
  "waveform": null,
  "thumbnail_blob_id": null
}
```

Rules:
- `kind`: `image`, `video`, or `voice`
- One post may contain:
  - one image
  - multiple images for a carousel
  - one video
  - one voice clip
- Mixed media kinds in one post are not allowed.

### `RenderablePostSnapshot`

```json
{
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "author_peer_id": "12D3KooWOriginal...",
  "author_username": "Sarah",
  "post_created_at": "2026-03-15T10:15:30.000Z",
  "audience": {
    "kind": "people_nearby",
    "radius_m": 2000,
    "scope_label": "Shared nearby"
  },
  "text": "Lost dog near Neckar bridge.",
  "media_kind": "image",
  "media": [],
  "keep_available": false,
  "expires_at": "2026-03-18T10:15:30.000Z"
}
```

This snapshot is the canonical renderable subset used by:
- `post_create`
- `post_pass`
- `post_pin_update`

## Envelope Schemas

### `post_create`

Payload:

```json
{
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "snapshot": {
    "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
    "author_peer_id": "12D3KooWOriginal...",
    "author_username": "Sarah",
    "post_created_at": "2026-03-15T10:15:30.000Z",
    "audience": {
      "kind": "all_friends",
      "radius_m": null,
      "scope_label": null
    },
    "text": "Anyone need a ladder this weekend?",
    "media_kind": "none",
    "media": [],
    "keep_available": false,
    "expires_at": "2026-03-18T10:15:30.000Z"
  }
}
```

Required payload fields:
- `post_id`
- `snapshot`

Rules:
- `snapshot.author_peer_id` must equal top-level `sender_peer_id`.
- `snapshot.post_id` must equal payload `post_id`.
- `snapshot.media_kind` is one of `none`, `image`, `image_carousel`, `video`, `voice`.

### `post_comment`

Payload:

```json
{
  "comment_id": "cmt_01JQ4V9W1F31V7M2X1P4X4PGCH",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "body": "I can lend one.",
  "commented_at": "2026-03-15T11:00:00.000Z"
}
```

Required payload fields:
- `comment_id`
- `post_id`
- `body`
- `commented_at`

Rules:
- `body` must be non-empty after trim.
- `commented_at` should equal top-level `created_at` unless the sender is replaying a previously persisted comment.

### `post_reaction`

Payload:

```json
{
  "reaction_id": "post_heart:post_01JQ4V7Y7B1E1S4J4N8J6R0HAB:12D3KooWActor...",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "kind": "heart",
  "is_active": true,
  "reacted_at": "2026-03-15T11:05:00.000Z"
}
```

Required payload fields:
- `reaction_id`
- `post_id`
- `kind`
- `is_active`
- `reacted_at`

Rules:
- `kind` must be `"heart"`.
- `reaction_id` must match the logical target and actor.

### `post_comment_reaction`

Payload:

```json
{
  "reaction_id": "comment_heart:cmt_01JQ4V9W1F31V7M2X1P4X4PGCH:12D3KooWActor...",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "comment_id": "cmt_01JQ4V9W1F31V7M2X1P4X4PGCH",
  "kind": "heart",
  "is_active": true,
  "reacted_at": "2026-03-15T11:07:00.000Z"
}
```

Required payload fields:
- `reaction_id`
- `post_id`
- `comment_id`
- `kind`
- `is_active`
- `reacted_at`

### `post_presence_update`

Payload:

```json
{
  "status": "active",
  "lat_e3": 49008,
  "lng_e3": 8670,
  "captured_at": "2026-03-15T11:10:00.000Z",
  "accuracy_m": 42,
  "reason": null
}
```

Required payload fields:
- `status`: `active` or `inactive`
- `captured_at`

Conditionally required fields:
- `lat_e3`, `lng_e3`, and `accuracy_m` are required when `status == "active"`
- `reason` is required when `status == "inactive"`

Rules:
- `inactive` reasons are one of `sharing_disabled`, `permission_revoked`, or `services_disabled`.
- App close does not send an automatic `inactive` event in v1.

### `post_pass`

Payload:

```json
{
  "pass_id": "pass_01JQ4VB0C59S3H4P7MV0N2EQ9Q",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "passed_at": "2026-03-15T11:15:00.000Z",
  "passer_peer_id": "12D3KooWPasser...",
  "passer_username": "James",
  "original_snapshot": {
    "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
    "author_peer_id": "12D3KooWOriginal...",
    "author_username": "Sarah",
    "post_created_at": "2026-03-15T10:15:30.000Z",
    "audience": {
      "kind": "people_nearby",
      "radius_m": 2000,
      "scope_label": "Shared nearby"
    },
    "text": "Lost dog near Neckar bridge.",
    "media_kind": "image",
    "media": [],
    "keep_available": false,
    "expires_at": "2026-03-18T10:15:30.000Z"
  }
}
```

Required payload fields:
- `pass_id`
- `post_id`
- `passed_at`
- `passer_peer_id`
- `passer_username`
- `original_snapshot`

Rules:
- `passer_peer_id` must equal top-level `sender_peer_id`.
- `original_snapshot.post_id` must equal payload `post_id`.
- `original_snapshot.audience.kind` must not be `pick_people`.

### `post_pin_update`

Payload:

```json
{
  "pin_event_id": "pin_evt_01JQ4VCCP5RG2P0Q4Y6CZQDKQ6",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "state": "active",
  "pinned_at": "2026-03-15T11:20:00.000Z",
  "snapshot": {
    "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
    "author_peer_id": "12D3KooWOriginal...",
    "author_username": "Sarah",
    "post_created_at": "2026-03-15T10:15:30.000Z",
    "audience": {
      "kind": "all_friends",
      "radius_m": null,
      "scope_label": null
    },
    "text": "Updated offer text.",
    "media_kind": "none",
    "media": [],
    "keep_available": true,
    "expires_at": "2026-03-18T10:15:30.000Z"
  }
}
```

Required payload fields:
- `pin_event_id`
- `post_id`
- `state`
- `pinned_at`
- `snapshot`

Rules:
- `state` must be `"active"` in v1.
- `snapshot.keep_available` must be `true`.
- V1 sender edits for active pinned posts reuse `post_pin_update`.
- `post_pin_update` is the only transport contract for pinned-post content edits in v1.
- The latest accepted snapshot updates both:
  - the pinned projection
  - the normal-feed projection, if that post is still visible in the normal feed

### `post_pin_remove`

Payload:

```json
{
  "pin_event_id": "pin_evt_01JQ4VDTJSJ1Q8P5M8SPDT3E0N",
  "post_id": "post_01JQ4V7Y7B1E1S4J4N8J6R0HAB",
  "removed_at": "2026-03-15T11:25:00.000Z",
  "reason": "sender_removed"
}
```

Required payload fields:
- `pin_event_id`
- `post_id`
- `removed_at`
- `reason`

Rules:
- `reason` is one of `sender_removed` or `sender_unpinned`.
- `post_pin_remove` beats any earlier active pin state for the same `post_id`.

## Receiver Acceptance Summary

- Reject envelopes with missing required fields.
- Reject envelopes whose sender fails trust validation.
- Stage orphan child events instead of dropping them.
- Apply latest valid state for reactions, presence, and pin state.
- Never render duplicate cards for the same `post_id`.
