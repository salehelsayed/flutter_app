# Posts Nearby Privacy Contract

Status: Proposed v1 implementation baseline  
Baseline date: 2026-03-15  
Approval record: `UI-21-POST/Phase-0-Approval.md`  
Companion docs:
- `UI-21-POST/Posts-Envelope-Schemas.md`
- `UI-21-POST/Plan-Phases.md`
- `../kitchen/landing-screen-claude/neighbourhood_spec.md`

This document reconciles the nearby/privacy promises in the product spec with the concrete behavior the app must implement in v1.

## Scope

Nearby affects:
- sender-side qualification for `People Nearby`
- coarse presence sharing between direct friends
- distance labels on nearby-scoped cards
- compose-time nearby availability state

Nearby does not introduce:
- stranger discovery
- background location tracking
- always-on presence
- map sharing

## Approved v1 Interpretation

### Approximate location promise

Product copy says location is rounded to a "~200m area".

V1 implementation contract:
- transport and storage use `lat_e3` and `lng_e3`, meaning latitude and longitude rounded to 3 decimal places
- this gives neighborhood-scale blur, not precise coordinates
- effective granularity varies by latitude and direction, typically around 100m to 200m for user-facing expectations in this product
- the product promise is therefore interpreted as "roughly neighborhood-block precision", not a literal fixed 200m geofence cell

### "Sharing stops when app is closed"

V1 implementation contract:
- the app does not capture or broadcast fresh nearby presence while closed
- app close does not emit an automatic `inactive` presence envelope
- the last persisted local snapshot may remain stored locally and may remain usable by receivers until freshness expires
- once the stored snapshot becomes stale, it is ineligible for new nearby qualification

This preserves the product promise that nearby is not live tracking, while avoiding a synthetic close-time network event in v1.

## Nearby Participation Model

- Nearby is opt-in through Settings-backed sharing state.
- Nearby uses direct friends only.
- Blocked contacts never qualify.
- Archived contacts do not qualify in v1.
- Nearby recipient qualification is computed by the sender at send time and then persisted.
- Inbox replay never recomputes nearby eligibility later.

## Presence Data Model

### Local sharing state

Persist locally:
- `sharing_enabled`
- `permission_state`
- `last_local_lat_e3`
- `last_local_lng_e3`
- `last_local_captured_at`
- `last_local_accuracy_m`
- `last_refresh_attempt_at`

### Friend snapshot state

Persist per direct friend:
- `peer_id`
- `lat_e3`
- `lng_e3`
- `captured_at`
- `accuracy_m`
- `updated_at`
- `status`

## `post_presence_update` Payload Assumptions

This contract approves the v1 payload assumptions used by `Posts-Envelope-Schemas.md`:

- `status: "active"` means the sender is currently sharing a fresh coarse snapshot
- `status: "inactive"` means nearby should be treated as unavailable for that sender until a later active snapshot arrives
- `active` payloads include:
  - `lat_e3`
  - `lng_e3`
  - `captured_at`
  - `accuracy_m`
- `inactive` payloads include:
  - `captured_at`
  - `reason`

Allowed inactive reasons:
- `sharing_disabled`
- `permission_revoked`
- `services_disabled`

## Freshness and Eligibility

- Freshness TTL: 30 minutes from `captured_at`
- A stale snapshot is not eligible for new nearby recipient qualification
- A stale snapshot may still support rendering of an already delivered nearby card because the sender-side qualification result is already persisted on that post

## Refresh Rules

### Silent refreshes

Allowed when permission is already granted and device location services are on:
- app startup
- app resume
- Posts screen open when the local snapshot is stale

Silent refreshes must not trigger a permission dialog.

### Interactive refreshes

Allowed from:
- enabling nearby sharing in Settings
- selecting `People Nearby` in compose when the snapshot is stale
- explicit `Refresh nearby` action in compose

Interactive refresh may request permission.

## Invalidation Rules

The local app must immediately mark nearby unavailable when any of these happen while the app is active:
- nearby sharing toggled off
- OS location permission revoked
- device location services turned off
- local snapshot explicitly cleared

When invalidation happens while the app is active and the app can send:
- emit `post_presence_update` with `status: "inactive"`

When the app is closed:
- do not emit `inactive`
- rely on freshness expiry instead

## App-Close and Persistence Rules

- Local nearby state is stored in the DB across app restarts.
- Remote friend snapshots are stored in the DB across app restarts.
- Persisting the snapshot locally does not mean the app is actively sharing while closed.
- Active sharing in v1 requires:
  - `sharing_enabled == true`
  - permission granted
  - services on
  - fresh local snapshot
  - app running when a refresh or send action occurs

## Sender Qualification Rule

For a `People Nearby` post:

1. load the sender's fresh local coarse snapshot
2. load each direct friend's freshest known active coarse snapshot
3. compute distance using rounded coordinates
4. include the friend if `distance <= selected radius`
5. persist the qualified recipient set on the post
6. persist the sender snapshot used for that post

## Pass-Along Rule for Nearby Posts

- Nearby-scoped pass-along keeps the original sender anchor and original radius.
- The passing friend's current location is not used as the anchor.
- A pass recipient qualifies only if their stored coarse snapshot is within the original radius of the original sender snapshot attached to the post.

## Distance Label Rules

Distance labels are computed from the same coarse snapshot model used for qualification.

Display format:
- under 1000m: meters, rounded to nearest 50m
- 1000m and above: kilometers with one decimal place

Examples:
- `350m away`
- `1.2km away`

## Compose-Time Nearby States

When `People Nearby` is selected in compose, the UI may show:
- permission missing
- location services off
- nearby sharing off in Settings
- stale snapshot needing refresh
- refreshing
- ready with selected radius

The stale blocked copy is:
- title: `Refresh nearby before posting`
- primary action: `Refresh nearby`

## Explicit Non-Goals in v1

- no background location jobs
- no geofence callbacks
- no app-close revoke broadcast
- no map UI
- no stranger or friend-of-friend presence sharing

## Acceptance Summary

This nearby/privacy contract is correct only if:
- direct-friend nearby qualification is sender-side and replay-safe
- coarse location is approximate and persisted
- app close stops fresh sharing activity without requiring a synthetic revoke event
- startup and resume refresh remain silent
