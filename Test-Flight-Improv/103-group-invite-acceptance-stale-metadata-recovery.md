# 1. Title and Type

- Title: Group invite acceptance must not leave stale group details
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`

# 2. Problem Statement

Group members are trying to continue a group administration journey where admin
roles change, group name/description/photo changes, and a promoted admin invites
a fourth member, then changes the group details again before that invitee
accepts.

In the reported Scenario 7, User C added/invited User D while the group still
had older details, then User C changed the group to `test 3`, description `333`,
and a new group image before User D tapped Accept. User D instead saw a warning
like `Joined test 2, but recovery is still catching up`, the invitation still
appeared as actionable after Accept, and the group listed under All showed the
older `test 2` name, `222` description, and old image.

This is a user-facing bug because User D is told the join happened but still
sees the invitation and stale group identity. The user cannot tell whether to
press Accept again, wait, or trust the group they entered. The group can still
deliver messages, which makes the stale details more confusing because the
membership appears active while the visible identity is wrong.

# 3. Impact Analysis

- Affected users: newly invited group members, existing group admins, and
  existing group participants who rely on consistent group identity after admin
  handoffs.
- Affected flows: Orbit/Intros pending group invite acceptance, All group list,
  group details/header metadata, group photo display, group admin role changes,
  add-member flow, and group text fan-out after a new member joins.
- Trigger pattern: the issue appears after multiple metadata and role changes,
  especially when a promoted admin invites another friend, then updates the
  group name, description, and photo before that friend accepts while join or
  accepted-inbox catch-up is degraded.
- Severity: high for trust. The app shows a successful join signal and working
  message delivery while keeping the invite visible and the group identity stale
  for the new member.
- Frequency: not measurable from repo evidence alone. Existing code and tests
  show this flow crosses invite payload metadata, pending invite storage, group
  materialization, catch-up/recovery, role convergence, and simulator UI.
- Confusion cost: User D can keep pressing Accept because the invitation still
  exists, and can enter the wrong-looking group even though messages fan out to
  all members.

# 4. Current State

- User-provided Scenario 7 reports a four-user journey:
  - User A and User B are friends.
  - User A creates `test` and adds User B.
  - User A promotes User B to admin.
  - User B updates the group name, description, and photo; User A receives the
    update.
  - User B adds User C; User C accepts and sees the updated details and photo.
  - User A, User B, and User C can all send messages to each other in the group.
  - User A changes the group photo, demotes User B, and promotes User C.
  - User C and User D are friends.
  - User C adds/invites User D while the group has older `test 2` details.
  - User C then updates the group to `test 3`, description `333`, and a new
    image before User D accepts.
  - User D accepts after that newer update but sees stale `test 2` details,
    stale image, a recovery warning, and a still-visible invitation.
- `Test-Flight-Improv/104-scenario7-group-invite-stale-metadata-recovery-root-cause-analysis.md`
  is a companion root-cause memo for this scenario. Its strongest reusable
  facts are:
  - the invite carries a send-time metadata snapshot, so D's card and first
    materialized local group can legitimately start from `test 2`;
  - accept can persist the group and publish a joined timeline before returning
    `bridgeError`;
  - the pending invite is deleted only after the accepted invite is committed,
    so the current `bridgeError` path leaves a materialized group and an
    actionable invite in the same UI;
  - the stale metadata should not be framed as a proven permanent Dart-side
    suppression bug, because current relay group-inbox reads are non-destructive
    and a later successful accepted-inbox drain should be able to re-serve
    `test 3` inside the normal TTL/cap window.
- `lib/features/groups/application/send_group_invite_use_case.dart` builds the
  invite payload from a point-in-time group config loaded from the inviter's
  current local group state, and embeds that `groupConfig` into the
  `GroupInvitePayload`.
- `lib/features/groups/application/group_invite_auth.dart` loads the inviter's
  current group and member list to build the invite freshness state, and
  `lib/features/groups/application/group_config_payload.dart` copies group name,
  description, avatar blob/mime, and `metadataUpdatedAt` into that config.
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  materializes an accepted invite by reading `name`, `description`,
  `avatarBlobId`, `avatarMime`, and `metadataUpdatedAt` from the invite
  `groupConfig`, then saving the local `GroupModel`, members, key, and optional
  downloaded avatar path.
- Group avatar replacement has a separate entitlement and byte-convergence
  surface. `lib/features/groups/presentation/screens/group_info_wired.dart`
  builds avatar-upload `allowedPeers` from the current group members via
  `groupMediaAllowedPeersForMembers`, and `uploadGroupAvatar` passes that ACL to
  the relay media upload. In Scenario 7, because User C adds User D before the
  `test 3` image upload, D must be included in the new avatar blob's allowed
  peers. If D is missing from that ACL, D can receive `test 3` metadata but still
  fail to download the actual image bytes after accepting.
- The current stale-invite guard is not enough for first join: when User D has
  no local group yet, the accept path has no later local metadata watermark to
  compare against, so the send-time `test 2` snapshot can be treated as the
  initial materialized group state.
- `lib/features/groups/domain/models/pending_group_invite.dart` stores
  `groupName`, `groupDescription`, `avatarBlobId`, `avatarMime`, and
  `metadataUpdatedAt` from the invite payload.
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart`
  renders the pending invite's stored group name and description and keeps the
  Accept button actionable while the invite is not expired and is not currently
  processing.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  deletes the pending invite only after the successful accept path commits the
  accepted invite. If inbox catch-up or bridge join returns `bridgeError`, it can
  return a joined `GroupModel` while leaving the pending invite uncommitted.
- There are two important `bridgeError` origins to keep separate during the
  implementation pass: `callGroupJoinWithConfig` can fail or time out after the
  group has already been saved and before accepted-inbox drain runs, and the
  accepted-inbox drain can fail after materialization. Both origins currently
  produce the same user-visible stale joined-with-recovery state.
- Accepted-inbox failure reproduction needs enough failure pressure to get past
  built-in cursor self-healing. `callGroupInboxRetrieveWithCursor` retries only
  recognized transient cursor failures (`GROUP_INBOX_ERROR` messages containing
  read-response EOF/reset/timeout/deadline): it reconnects the relay, halves the
  page limit while possible, and then makes same-limit retry attempts. A single
  transient blip can therefore recover before `acceptPendingGroupInvite` sees a
  drain failure. Existing GCA-004 uses a persistent non-transient
  `RELAY_UNAVAILABLE` response, which reaches `bridgeError` immediately because
  that code is not classified as a transient cursor error.
- The accepted-inbox drain is the accept-time channel that can replay User C's
  post-invite `test 3` metadata update to User D. The root-cause memo's review
  says a strictly newer metadata event should pass the Dart metadata watermark;
  the risk is delivery/catch-up failure, not the watermark rejecting `test 3`.
- User C's metadata update currently fans out over three channels in
  `lib/features/groups/presentation/screens/group_info_wired.dart`: live group
  publish via `callGroupPublish`, durable group-inbox replay via
  `callGroupInboxStore` addressed to `recipientPeerIds`, and opportunistic
  direct P2P delivery via `sendGroupMembershipUpdateDirect` to
  `groupMembershipUpdateDirectTargets`. For Scenario 7, live publish can miss
  User D because D has not accepted/joined/subscribed to the group topic yet,
  and the direct P2P path is best-effort only in the metadata flow: it retries
  `p2pService.sendMessage` but has no `storeP2PMessageInInbox` fallback there.
  The durable group-inbox replay is therefore the only designed reliable path
  for a late or offline invitee to receive User C's post-invite `test 3`
  metadata update after accepting.
- A failed drain does not prove the update is lost: the Dart cursor advances
  only after a page is processed, and later resume/startup/periodic or
  notification-triggered drains may retry. Current Go relay group-inbox storage
  is also non-destructive on read: `go-relay-server/group_inbox_store.go`
  documents `RetrieveSince` as "NOT deleted on retrieve", and both in-memory and
  Redis group-inbox cursor/since retrieval read and filter records without an
  ack/delete path. The default group-inbox retention is seven days
  (`groupMessageTTL`) with a default 500-message-per-group FIFO cap
  (`maxMessagesPerGroup`, configurable through server limits), so relay
  retention/redelivery is not the primary suspected loss point for Scenario 7
  inside a normal TTL/cap window when User D is an authorized recipient and the
  relay backend is reachable.
- A successful accepted-inbox page can still be risky if an authoritative replay
  is delivered but treated as unapplied. `drain_group_offline_inbox_use_case.dart`
  skips some replay items and continues the page, including pre-join replay
  classification, recipient-not-entitled decode errors, deferred/unknown sender
  replay skips, revoked-device skips, stale replay epochs, and transport
  mismatch returns. `group_message_listener.dart` is called with
  `rethrowOnError:true`, but some metadata-specific rejects are normal returns
  rather than thrown errors, including stale metadata watermarks, metadata
  signature/actor verification failure, and metadata state-hash mismatch. Once
  the page finishes, the drain commits receipts and the next cursor. If User C's
  `test 3` authoritative metadata event lands in one of these
  delivered-but-unapplied paths, later ordinary cursor drains may not see that
  exact replay again even though the relay retained it.
- Timestamp ordering is another boundary risk. The pre-join replay skip does
  not directly compare User C's metadata `changedAt` to User D's `joinedAt`; it
  compares the relay replay timestamp to D's locally materialized member
  `joinedAt`. That local `joinedAt` comes from the invite groupConfig member
  snapshot, with fallbacks to the invite membership watermark or materialization
  time. Separately, metadata application compares the metadata event/config time
  against D's `lastMetadataEventAt`, which was seeded from the send-time invite
  snapshot. Scenario 7 therefore needs coverage for close or skewed add-D vs
  edit timestamps so a valid post-invite `test 3` update is not misclassified as
  pre-join or stale.
- Avatar bytes are stickier than avatar metadata. When
  `group_message_listener.dart` applies an authoritative group config, it updates
  the group row and then downloads the avatar only when the blob changed or no
  local avatar path exists. Scenario 7 therefore needs D-specific byte evidence:
  matching `avatarBlobId`/`avatarMime` or a visible image widget alone is not
  enough to prove D replaced the old `test 2` image with the new `test 3` bytes.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` maps
  `AcceptPendingGroupInviteResult.bridgeError` to user-visible copy:
  `Joined <group name>, but recovery is still catching up` when a group exists.
- The "recovery is still catching up" copy should not be treated as evidence
  that an accept-path recovery gate is actively protecting User D. The companion
  root-cause memo rules out `GroupRecoveryGate` as the mechanism behind this
  accept flow, so the implementation must either back the copy with a real
  idempotent background state or avoid implying that stale visible details are
  safely being handled.
- `test/features/groups/presentation/group_list_wired_test.dart` currently
  asserts that the `bridgeError` accept path keeps the pending invite visible,
  keeps a joined group, and shows `Joined Book Club, but recovery is still
  catching up`.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  has `GCA-004 inbox bridgeError keeps pending invite retryable until drain
  succeeds`, which asserts that a relay/inbox error returns `bridgeError`, keeps
  a materialized group, and leaves the pending invite present until a later
  retry succeeds.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  has a retry path for already-materialized groups. While the invite remains
  visible, repeated Accept attempts can re-enter the accept flow instead of
  becoming a settled joined/non-actionable state from the user's perspective.
- The root-cause memo identifies a repeated-Accept amplification risk: because
  the joined timeline publish happens before the `bridgeError` early return,
  every re-tap can save another local `member_joined` timeline row, publish
  another live join signal, and store another signed `member_joined` offline
  replay envelope via group inbox unless the accept path becomes idempotent
  after the group is durably materialized. Those stored replay envelopes can
  later re-fan the duplicate join event to User A/User B/User C when they drain
  their group inboxes.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` covers happy
  path pending invite acceptance from Intros: the pending invite is removed, the
  group exists, and the group appears under All.
- `integration_test/group_invite_accept_spinner_simulator_test.dart` is a
  simulator proof that tapping Accept on a pending group invite clears the
  spinner, removes the invite card, and joins the group within a bounded
  deadline. It does not cover a fourth member accepting after later group
  metadata/photo changes.
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart`
  covers A/B/C metadata convergence, admin promotion, promoted-admin member add,
  three-way text fan-out, avatar convergence, admin demotion enforcement, and a
  promoted-admin recovery-save convergence path.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` wraps
  those A/B/C admin metadata convergence journeys as simulator tests. It does
  not extend the same flow to User D accepting after User C changes the group to
  newer details.
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`
  contains a registered four-role simulator regression for promoted-admin
  permissions, metadata/avatar convergence, and message reliability. It is
  useful companion evidence because it already exposes late-member
  metadata/avatar convergence risk, but it does not by itself cover Scenario 7's
  pending-invite card, joined-with-recovery copy, or repeated-Accept behavior.
- Group List and Orbit map the same joined-with-recovery outcome differently:
  `lib/features/groups/presentation/screens/group_list_wired.dart` uses
  localized group-invite recovery copy, while
  `lib/features/orbit/presentation/screens/orbit_wired.dart` currently hardcodes
  the English string `Joined <group name>, but recovery is still catching up`.
  This is not the root cause of stale metadata, but it is part of the same
  user-visible failure surface.
- `Test-Flight-Improv/97-group-details-recovery-save-feedback.md` is closed for
  group details editing during recovery. It does not cover a later invitee
  accepting stale group details after another admin's successful metadata/photo
  update.
- `Test-Flight-Improv/98-group-membership-recovery-action-feedback.md` covers
  user-visible recovery feedback for add/remove/promote/demote membership
  actions. It does not cover stale group identity after a successful invite
  acceptance.
- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md` records existing
  four-user text fan-out coverage, including the expectation that every active
  member receives text messages from every other active member. That protects
  message delivery but not the stale group identity and lingering invite bug.

# 5. Scope Clarification

In scope:

- Scenario 7 as a group invite acceptance and stale metadata regression.
- User D accepting after User C, as an admin, has changed group name,
  description, and photo.
- The exact reported ordering: User C adds/invites User D, User C then changes
  group details/photo, and only then User D accepts.
- User D's visible pending invite card, Accept action state, snackbar/status
  copy, All group row, group details/header, group photo, and post-join message
  participation.
- Repeated Accept behavior after a joined/catch-up warning, including duplicate
  or contradictory join/status signals.
- Both the immediate post-Accept state and the settled state after normal
  catch-up, app resume, and conversation/list reopen.
- Preservation of User A/User B/User C admin promotion, demotion, metadata
  convergence, and message fan-out behavior before User D joins.
- Simulator acceptance evidence for the reported user-visible journey.
- Integration acceptance evidence for group state convergence across invite
  payload, pending invite storage, group membership, metadata/photo state, and
  post-join message delivery.

Non-goals:

- No change to who can invite whom.
- No change to group admin permission policy.
- No change to group key design, transport selection, or broad recovery
  architecture.
- No relay/backend behavior change for the normal Scenario 7 window unless
  implementation evidence shows a concrete relay-side failure despite the
  current non-destructive group-inbox reads, seven-day TTL, and default 500
  message FIFO cap. Relay-adjacent investigation can still rule out configured
  cap overflow, TTL expiry, recipient authorization filtering, backend
  availability, or history-gap behavior if the app fails to recover after a
  later accepted-inbox drain.
- No new product requirement to backfill pre-join messages or media to User D.
- No redesign of Orbit, Intros, All, or Group Info beyond the stale invite and
  stale details behavior described here.
- No requirement to reopen Reports `90`, `97`, or `98` unless this bug proves
  one of their accepted behaviors has regressed.
- No claim that the stale state is always permanent. This spec is concerned with
  the user-visible failure window and the settled visible state after ordinary
  catch-up opportunities.

Accepted ambiguities for later implementation:

- The user report contains intermediate names `test 2`, `test me`, and final
  `test 3`. This spec treats the final required post-User-C state for User D as
  `test 3`, description `333`, and a new image, while preserving the earlier
  A/B/C convergence steps as observed setup.
- The stale baseline source is no longer fully open: the companion root-cause
  memo shows that the pending invite payload and first local group
  materialization are seeded from the send-time `test 2` snapshot. The later
  implementation pass should focus on why the newer `test 3` update is not
  delivered/applied quickly enough, and why the accepted invite remains
  actionable after the group is already materialized.
- The dominant catch-up failure trigger remains open: group join, accepted-inbox
  drain, relay/backend availability, recipient authorization filtering, group
  inbox TTL/cap edge cases, delivered-but-unapplied replay handling, timestamp
  boundary handling around add-D/edit/accept, live group-subscription timing,
  direct P2P reachability, or a combination can all be investigated later. Plain
  relay message loss on read is lower priority because current group-inbox
  retrieval is non-destructive.
- The metadata watermark should not be treated as the primary suspect unless new
  evidence contradicts the companion root-cause memo; a strictly newer `test 3`
  metadata replay is expected to apply if delivered.
- Given the current Go relay defaults, a later successful drain should be able
  to re-serve User C's stored `test 3` update within the seven-day TTL and
  default group FIFO cap. This spec does not require proving indefinite
  permanence; it requires the app not to leave User D with a confusing
  repeatable Accept loop or a settled stale group identity in the normal
  recovery window.
- The exact temporary copy during a real catch-up window can be decided later,
  as long as it does not leave a joined user with a repeatedly actionable stale
  invitation.
- The representative group image used in acceptance evidence can be synthetic or
  fixture-based as long as the visible image changes are distinguishable.

# 6. Test Cases

## Happy Path

- User A and User B are friends. User A creates group `test`, invites User B,
  and User B accepts. Both users can send and receive group messages.
- User A promotes User B to admin. User B sees the admin role and can change the
  group name, description, and photo.
- After User B changes the group details, User A sees the same updated name,
  description, and photo.
- User B and User C are friends. User B invites User C after the metadata/photo
  update, User C accepts, and User C sees the current group name, description,
  and photo rather than the original `test` values.
- User A, User B, and User C each send a group message. Every other active
  member receives the message exactly once.
- User A changes the group photo, and User A and User C see the new photo.
- User A demotes User B from admin. The group timeline/status reports that User
  A removed User B as an admin, and User B cannot change group name or
  description afterward.
- User A promotes User C to admin. User C sees the admin role.
- User C and User D are friends. User C adds/invites User D while the group
  still has older details, then User C updates the group to `test 3`,
  description `333`, and a new group image before User D accepts.
- User D accepts after User C's latest metadata/photo change. Even if the invite
  card initially reflects the older send-time snapshot, User D's final visible
  group under All, group details/header, and group photo match `test 3`, `333`,
  and the latest image.
- User D's latest-image proof includes both metadata and bytes: D is entitled to
  download the `test 3` avatar blob, D's local avatar file exists with supported
  non-empty image bytes, and D's byte hash matches the uploaded `test 3` image
  rather than the earlier invite snapshot image.
- User D does not have to press Accept again to make metadata recovery happen:
  once the group is durably materialized, any catch-up or current-config resync
  proceeds through an idempotent background path.
- After User D joins, the pending invitation is no longer presented as an
  actionable Accept card for the same group.
- Any joined/catch-up status shown to User D is truthful across Orbit and Group
  List and does not name the stale group identity as the settled joined group.
- User A, User B, User C, and User D each send a post-join group message. Every
  other active member receives the message exactly once.
- Required acceptance evidence layer: integration, because the observable
  outcome spans invite storage, accept state, group metadata/photo persistence,
  role state, membership state, and message fan-out.
- Required acceptance evidence layer: simulator, because the reported failure is
  visible through the pending invite card, snackbar/status copy, All group list,
  and mobile group surfaces.

## Edge Cases

- If User D's accept enters a catch-up state, the UI remains truthful: User D is
  not left with an actionable stale invite after becoming a joined member, and
  the final visible group details converge to User C's latest values.
- If User D's group has already been durably materialized but group join or
  accepted-inbox drain returns `bridgeError`, the accepted invite is consumed,
  tombstoned, or filtered out of pending-invite surfaces so it cannot reappear as
  a fresh Accept action.
- If the first accepted-inbox drain fails before applying User C's `test 3`
  metadata update, a later automatic catch-up path re-attempts delivery without
  requiring a repeated Accept tap, and acceptance evidence records whether the
  retry came from Dart catch-up, relay re-serving, or an edge case such as
  configured cap overflow, TTL expiry, recipient authorization filtering, or
  backend availability.
- If Scenario 7 regression evidence injects an accepted-inbox failure, the
  injected failure is strong enough to survive cursor self-healing: either a
  persistent non-transient relay/inbox error or a sustained recognized transient
  cursor failure that exhausts adaptive limit-halving, reconnect, and retry
  behavior. A one-off transient cursor blip must not be used as the sole proof
  of the joined-with-recovery failure path.
- If User D is offline, not yet subscribed to the group topic, or otherwise
  unreachable for direct P2P when User C publishes `test 3`, User D still
  converges after accepting through the durable group-inbox replay path. The
  Scenario 7 proof must not rely on User D catching live GossipSub or a
  best-effort direct membership update before Accept.
- If User C uploads a new `test 3` group image after adding User D but before D
  accepts, the upload entitlement includes D as an allowed peer, and D can
  download the blob after accepting. A metadata-only match on `avatarBlobId` or
  `avatarMime` is not enough if D's local bytes are missing, unreadable, or still
  equal to the old `test 2` image.
- If User C's `test 3` authoritative metadata replay is delivered during an
  otherwise successful accepted-inbox drain but is not applied because it is
  classified as pre-join, recipient-ineligible, unknown-sender, stale, invalid,
  mismatched, or otherwise soft-skipped, User D still converges to `test 3`,
  `333`, and the latest image through a later catch-up path without pressing
  Accept again.
- If User C adds/invites User D and then updates to `test 3` within the same
  second, same millisecond, or across skewed device/relay clocks, User D's valid
  post-invite metadata update still converges to `test 3`, `333`, and the latest
  image. The app must not strand User D on `test 2` merely because the replay
  timestamp, D's materialized `joinedAt`, the invite metadata watermark, and the
  metadata event/config timestamp are close, equal, or slightly out of expected
  order.
- If User D taps Accept repeatedly while the first accept is processing, the app
  does not create duplicate membership, duplicate timeline entries, or multiple
  contradictory visible states for the same invite.
- If User D taps Accept again after a joined/catch-up warning, the app still
  does not create duplicate join timeline/status entries, does not publish or
  store duplicate `member_joined` replay envelopes for other members, and does
  not re-present the same invite as a fresh action.
- If an older invite payload and a newer metadata/photo update are observed in
  close succession, User D's final joined group view reflects the latest
  accepted group identity, not the older invitation display values.
- If User D opens All immediately after accepting and again after catch-up,
  stale `test 2` details do not remain as the settled state for a joined group.
- If app resume, startup catch-up, notification-open catch-up, or periodic
  catch-up is needed to finish recovery, the group identity and pending invite
  state still converge without requiring User D to keep pressing Accept.
- If User D accepts while messages are being sent by User A, User B, or User C,
  post-join messages still fan out to the correct active members and no
  pre-join history requirement is added.
- If the invite is expired, revoked, already used, for the wrong identity, or
  missing required key material, the app does not show User D as a joined member
  with stale group details.

## Regressions To Preserve

- Bug regression: after User C updates the group to `test 3`, description
  `333`, and a new image, User D must not settle into a joined group that still
  shows `test 2`, `222`, or the old image.
- Bug regression: after User D successfully joins, the invitation for that group
  must not remain as a confusing actionable Accept card.
- Bug regression: User D must not see a joined/catch-up warning that names the
  stale group identity as the joined group while the final All row stays stale.
- Bug regression: current bridge-error behavior that materializes a group while
  keeping the pending invite retryable must not reappear as a user-visible
  repeated-Accept loop.
- Bug regression: repeated Accept attempts after a joined/catch-up warning must
  not create duplicate joined timeline/status notifications for User A, User B,
  User C, or User D, and must not store duplicate `member_joined` replay
  envelopes that later re-fan the same join event through accepted-inbox drains.
- Bug regression: both bridge-error branches are covered: join-with-config
  timeout/failure after group materialization, and accepted-inbox drain failure
  after group materialization.
- Bug regression: a delivered-but-unapplied authoritative metadata replay must
  not be silently consumed as a settled success; User D must still converge to
  `test 3` on a later automatic catch-up opportunity.
- Bug regression: close or skewed add-D-vs-edit timestamps must not cause the
  accepted-inbox drain or metadata watermark logic to permanently classify User
  C's `test 3` update as pre-join/stale for User D.
- Bug regression: User D's convergence to `test 3` must still pass when D misses
  live group publish and direct P2P delivery before Accept; accepted-inbox replay
  must carry the post-invite metadata update for a late/offline invitee.
- Bug regression: User D must have D-specific byte/SHA proof for the new `test 3`
  avatar. The regression must fail if D only has matching avatar metadata, lacks
  blob entitlement, cannot download the file, or keeps the old `test 2` image
  bytes.
- Bug regression: existing tests that currently assert a materialized
  `bridgeError` keeps the pending invite retryable must be updated so they no
  longer lock in the Scenario 7 failure.
- Bug regression: the same simulator journey must fail if the screenshot state
  returns: `Joined test 2, but recovery is still catching up`, visible old group
  details, and an invitation that can still be accepted again after the first
  accept.
- Existing A/B/C promoted-admin metadata convergence still works.
- Existing admin demotion enforcement still works: demoted User B cannot edit
  group name or description.
- Existing User C admin promotion still works before User C invites User D.
- Existing four-user text fan-out remains intact after User D joins.
- Existing invalid, expired, revoked, wrong-identity, already-used, and
  repair-pending invite outcomes remain clear and do not fake a successful join.

## Final Acceptance Evidence

- Add focused Scenario 7 regression evidence that either reuses the four-role
  simulator infrastructure from Report `95` or explicitly explains why a
  separate scenario is needed for the pending-invite UI and `bridgeError` copy.
  Required proof: D accepts after C's post-invite `test 3` update, D does not
  retain an actionable stale invite, D converges to `test 3`/`333`/latest image,
  D has byte/SHA proof for the latest avatar, and repeated Accept cannot
  duplicate joined timeline/status output or stored `member_joined` replay
  envelopes. Report `95` already uses an
  `assertGroupImageVisible`-style proof that waits for avatar metadata, verifies
  supported non-empty file bytes, and compares SHA-256 against the upload; the
  Scenario 7 proof should provide the same level of D-specific avatar evidence.
- When the focused proof exercises the accepted-inbox `bridgeError` branch, the
  failure injection must be sustained or non-transient enough to outlast
  `callGroupInboxRetrieveWithCursor` retry/reconnect/adaptive-limit behavior, so
  the result is not a flaky artifact of an under-powered transient blip.
- At the end of the implementation pass, run `$run-flutter-reliability-sims` in
  fix-as-you-go mode for the `group` scope. Required evidence: group simulator
  reliability coverage is planned first, run fail-fast, any failing command is
  debugged and fixed at the correct layer without weakening real assertions, the
  failed command is rerun by itself, the run resumes after that command, and the
  full `group` scope finishes green.
- At the end of the implementation pass, run `$run-flutter-host-gates` in
  fix-as-you-go mode for the existing named host gate `groups`. Required
  evidence: the group host gate is run fail-fast, any failure is debugged and
  fixed at the correct layer without weakening real assertions, the failed
  command or gate slice is rerun by itself where the runner supports it, and the
  full `groups` host gate finishes green.
- These final gates are required acceptance evidence in addition to the focused
  Scenario 7 regression; they do not replace the user-visible simulator proof
  for stale metadata, lingering invite, and repeated Accept behavior.

## Rollout Verdict - 2026-06-02

Status: `still_open`

The host-side implementation and regression evidence for Report 103 is green,
and the required Scenario 7-specific multi-party simulator path is now wired and
discoverable. Final closure remains open on the required four-simulator passing
proof and the visible UI-state acceptance evidence.

Evidence recorded during the rollout:

- Session 01 accepted the materialized accepted-invite settlement path, with
  later GCA-004 alignment proving that a settled materialized `bridgeError`
  drains recovered inbox state without leaving the same invite actionable.
- Session 02 accepted late name/description catch-up for User D after a stale
  invite snapshot and later authoritative metadata replay.
- Session 03 accepted D-specific latest-avatar byte/SHA convergence and the
  upload-call allowed-peer proof, with companion four-user simulator evidence
  for the older reliability scenario.
- Session 04 added a focused host Scenario 7 proof in
  `test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
  That proof covers the stale `test 2` invite snapshot, User C's post-invite
  `test 3` / `333` / latest-avatar replay, pending invite consumption, repeated
  Accept returning `notFound`, D-specific latest-avatar byte/SHA convergence,
  all four active member rows, and exactly-once post-join text fan-out.
- Session 04 follow-up added `scenario7_group_invite_stale_metadata_recovery`
  to `integration_test/group_multi_party_device_real_harness.dart`,
  `integration_test/scripts/run_group_multi_party_device_real.dart`, and
  `integration_test/scripts/group_multi_party_device_criteria.dart`, with
  criteria tests in `test/integration/group_multi_party_device_criteria_test.dart`.
  The criteria require stale invite capture, pending consumption, retry
  `notFound`, final `test 3` / `333` metadata, latest avatar bytes/hash, all
  four active members, final role convergence, and the four-user message matrix.
- The direct Session 04 checks passed:
  - `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "scenario7_late_invitee_acceptance_closes_stale_metadata_invite_and_four_user_fanout"`
  - `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "scenario7_late_invitee_acceptance_combined_host_direct_replay"`
  - `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "late_invitee_catches_up_name_description_after_stale_invite_snapshot"`
  - `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name "late_invitee_catches_up_avatar_bytes_after_post_invite_photo_update"`
  - `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"`
  - `flutter test test/features/groups/presentation/group_list_wired_test.dart --plain-name "bridgeError accept keeps joined group without stale pending invite action"`
- The full owner file passed:
  `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`
  (`00:03 +16: All tests passed!`).
- The named host gate passed:
  `./scripts/run_test_gates.sh groups` (`00:55 +317: All tests passed!`).
- Scoped `git diff --check` passed over the 103-owned tracked production and
  test files.
- Simulator discovery checks passed:
  - `dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario scenario7_group_invite_stale_metadata_recovery --list-scenarios`
  - `./scripts/run_reliability_simulations.sh group --list`
  - `./scripts/check_reliability_simulation_discovery.sh --checks-tsv`

No production edits were made in Session 04. The gate-definition row for the
multi-party simulator orchestrator now names the Report 103 Scenario 7 entry as
an optional/manual reliability simulator proof.

The remaining acceptance gap is mobile simulator execution and visible UI
evidence. The dedicated `scenario7_group_invite_stale_metadata_recovery` entry
exists and is discoverable, but no Scenario 7-specific four-simulator proof has
passed yet. The harness criteria validate repository/result state and message
fan-out, not the reported pending invite card, All row, group details/header,
snackbar/status copy, or repeated Accept UI behavior directly.

Required next action: run and pass the dedicated
`scenario7_group_invite_stale_metadata_recovery` simulator proof, then add a
narrow UI companion proof or explicitly revise this report's visible UI
acceptance requirement before changing the final verdict to `closed` or
`accepted_with_explicit_follow_up`.
