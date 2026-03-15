# Posts Feed Rules

Status: Proposed v1 implementation baseline  
Baseline date: 2026-03-15  
Approval record: `UI-21-POST/Phase-0-Approval.md`  
Companion docs:
- `UI-21-POST/Posts-Envelope-Schemas.md`
- `../kitchen/landing-screen-claude/neighbourhood_spec.md`

This document is normative for feed ordering, pinned ordering, overflow behavior, and reorder triggers.

## Definitions

- `post_created_at`: time the original `post_create` happened
- `visible_at`: time used to place a card in the normal feed
- `pass_created_at`: time the accepted `post_pass` happened
- `pin_activated_at`: time the latest active `post_pin_update` took effect
- `last_engagement_at`: latest accepted comment time on the logical post

## Approved Ordering Keys and Tie-Breakers

### Normal feed ordering

1. Pinned section always renders above the normal chronological feed.
2. Normal feed items sort by `visible_at DESC`.
3. Tie-breaker 1: `post_created_at DESC`
4. Tie-breaker 2: `post_id DESC`

### `visible_at` by item type

- Direct post: `visible_at = post_created_at`
- Passed-along post: `visible_at = pass_created_at`

Rationale:
- a fresh pass-along is a new human endorsement and should surface when it is passed, not when the original post was first authored

### Pinned ordering

1. Active pins sort by `pin_activated_at DESC`
2. Tie-breaker 1: `post_created_at DESC`
3. Tie-breaker 2: `post_id DESC`

### Collapsed-header overflow

- Collapsed header avatars show unique authors, not raw pin count.
- Unique authors are ordered by the most recent visible active pin they own.
- Show at most 6 avatars.
- Overflow badge counts remaining unique authors after the first 6.

### Expanded pinned section overflow

- Expanded view shows the first 5 active pins by pinned ordering.
- If more than 5 active pins remain, show `See all N pinned posts`.

## Chronological Sections

Sectioning uses `visible_at` in the local device timezone:

- `Right now`: within the last 4 hours
- `Earlier today`: same local calendar day, older than 4 hours
- `Yesterday`: previous local calendar day
- Older: date header formatted as `EEE, MMM d`

## Reorder Triggers

### Does reorder the normal feed

- new direct post create
- new accepted pass-along event

### Does not reorder the normal feed

- comments
- hearts on posts or comments
- expiry reset after comment
- pin activation
- pin removal
- sender edit propagated through `post_pin_update`
- media hydration finishing after the card already exists

### Does reorder the pinned section

- new active `post_pin_update`
- `post_pin_remove`
- local receiver dismissal of a pin

### Does not reorder the pinned section

- comments
- hearts
- sender edit of text or media in an already active pin

## Duplicate-Merge Rules

### Duplicate creates

- Never render two cards for the same `post_id`.
- Later duplicate `post_create` deliveries merge into the accepted post row if they are equivalent.

### Direct post plus pass-along for the same original post

- If the receiver already has the original post directly, keep the direct post card only.
- The pass event may update sender-side share analytics or local pass metadata, but it does not create a second visible card.

### Duplicate pass envelopes

- Merge by original `post_id`, not by transport message id alone.
- Keep one visible card only.
- Preserve the first accepted visible attribution line in v1 instead of flipping attribution on later duplicates.

## Pinned-Specific Visibility Rules

- A post may appear both in the pinned section and in the normal feed during its first 24 hours after creation.
- After 24 hours, if still pinned, it leaves the normal chronological feed and remains pinned only.
- Shared pin-state changes are author-only. Only the original post author may send `post_pin_update` or `post_pin_remove`.
- Sender-side pin removal is one visible `Remove` action in v1. If the post is still within 24 hours, it remains in the normal feed; if older, it disappears entirely from receiver-visible surfaces.
- Removing the pin later does not resurrect an aged-out normal-feed card.
- Local dismiss removes the pin from the receiver's pinned section only and does not affect other receivers.

## Collapsed Header Rules

- Header count uses visible active pins after local dismissals.
- Names in the collapsed summary come from the same author order as the avatar stack.
- If no active visible pins remain, the pinned section is hidden completely.

## Card Update Rules

- Sender edits propagated through `post_pin_update` update the existing card content in place.
- Those edits do not change normal feed position.
- Expiry footer updates in place as `expires_at` changes.
- Comment counts and heart counts update in place.

## Feed End Message

- `You're all caught up` appears after the last visible normal-feed item.
- It still appears when the pinned section is present.
- If there are no normal-feed items and no pins, show the caught-up or empty reference state from `Posts-UI-State-Inventory.md`.

## Acceptance Summary

This feed contract is correct only if:
- passed-along posts rise by pass time
- pins are ordered independently from the chronological feed
- comments and hearts never bubble cards upward
- duplicate passes do not create duplicate cards
