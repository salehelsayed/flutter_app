## 1. Title and Type

- Title: Group chat invited users receive empty message notifications
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/106-group-chat-invited-vs-accepted-message-notifications.md`

## 2. Problem Statement

Group creators need to invite people to a group while preserving a clear difference between someone who has been invited and someone who has actually accepted and joined.

Today, an invited user can appear in the creator's group member list before accepting. If that user has not accepted, does not have the group locally, and has no visible pending group invite in Orbit > Intro, they can still receive group-message notifications. Tapping the notification does not reveal any messages, because the recipient app has no joined group to open and no pending invite to redirect to.

One important way to reach this state is time-based invite freshness: a pending invite can only become visible if the incoming invite passes validation before storage. Before session `01-invite-lifecycle`, the hidden membership freshness proof could expire before the visible invite lifecycle, so the invite could be rejected before it was stored. Sessions `01` through `04` now close the accepted-vs-invited notification journey: normal invite freshness matches the visible invite lifecycle, ordinary group-message fanout is limited to accepted/current recipients, receiver-side fallback/tap routing fails closed for non-current invite states, and final mixed-recipient simulator/matrix evidence is recorded below.

From the user's perspective, this looks like a broken or misleading notification: the app says there is a group message, but the group is absent and there is no actionable invitation.

## 3. Impact Analysis

- Affected users: group invite recipients who have not accepted, group creators/admins who see invitees in the group member list, and accepted members in mixed accepted/unaccepted groups.
- Trigger moments: group creation with multiple invitees, some invitees accepting immediately while others do not, delayed invite delivery beyond membership freshness, later group messages, background push, foreground push, local notification tap, and Orbit Intro review.
- Severity: high for trust in group chat notifications. The notification implies a readable message, but the user lands in a dead end.
- Frequency: repo evidence supports the state combination: invited contacts are added to the creator's local group config before invite acceptance, group message fanout starts from configured/local members and explicit recipient ids rather than invite-delivery status, and remote push fallback can display a group notification from payload data alone.
- Confusion cost: recipients cannot tell whether they missed an invite, joined a group incorrectly, or lost messages. Creators can mistake "listed as member" for "accepted and reachable."

## 4. Current State

- Group invite lifecycle:
  - `lib/features/groups/domain/models/pending_group_invite.dart` stores each pending invite with `expiresAt`.
  - `PendingGroupInvite.fromPayload` uses the earlier of local TTL and invite-policy expiry.
  - `lib/features/groups/application/send_group_invite_use_case.dart` derives invite policy expiry from `now + pendingGroupInviteTtl`.
  - `lib/features/orbit/presentation/screens/orbit_wired.dart` loads pending group invites directly from `pendingInviteRepo.getPendingInvites()`.
  - `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` labels a stored expired invite as expired and disables acceptance, so a stored expired invite would still be visible rather than silently disappearing from the read path.
  - `lib/core/database/helpers/pending_group_invites_db_helpers.dart` and `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` include an expired-pending-invite delete path, and repository tests cover it when explicitly invoked.
  - Repo evidence found no production caller in `lib/` for `deleteExpiredPendingInvites`; the method is wired through repository construction but is not invoked by startup, resume, or a scheduled sweep today. Under current production behavior, a missing Orbit Intro invite is therefore better explained by receive-time non-storage or an explicit terminal delete than by automatic 7-day cleanup.
- Membership freshness gate:
  - Session `01-invite-lifecycle` changed `lib/features/groups/domain/models/group_invite_payload.dart` so `groupInviteMembershipFreshnessTtl` is 7 days, aligned with the visible pending invite lifecycle; `groupInviteMembershipFreshnessClockSkew` remains 5 minutes.
  - `lib/features/groups/application/group_invite_auth.dart` builds `GroupInviteMembershipFreshnessProof` with `expiresAt = issuedAt + groupInviteMembershipFreshnessTtl`.
  - `lib/features/groups/application/send_group_invite_use_case.dart` attaches the membership freshness proof to outgoing group invite payloads.
  - `GroupInvitePayload.currentTimeValidationFailure` still returns `staleMembershipFreshness` when the proof is no longer fresh at validation time, including explicitly shortened or tampered proof expiry.
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` validates the invite before saving `PendingGroupInvite`; invalid or explicitly stale payloads return without storing a pending invite or local group.
  - The receive path can also return without storing for unknown sender, decryption failure, invalid policy, active revocation, already-used single-use material, stale replacement, or duplicate local group. Those outcomes are materially different from a stored invite reaching visible expiry because no pending row is created for Orbit to render.
  - `lib/features/groups/application/group_invite_listener.dart` only emits to `pendingInviteStream` when `StorePendingGroupInviteResult.storedPending` is returned, so explicitly stale freshness leaves no user-visible Intro card.
  - Existing tests cover stale freshness not storing the invite, not creating the group, and not joining the group. Session `01` added delayed-but-policy-valid parse, receive/store, listener, and accept coverage after the old 24-hour window.
- Creator-side group creation and invite status:
  - `lib/features/groups/application/create_group_with_members_use_case.dart` adds each selected contact as a `GroupMember` before sending individual P2P group invites.
  - The same flow builds the group config from all local members and then sends invites.
  - This means the creator's roster/config can include users whose recipient app has not accepted or materialized the group.
  - `lib/features/groups/domain/models/group_invite_delivery_attempt.dart` already models creator-side invite delivery status as `sent`, `queued`, `needsResend`, `cannotSend`, `joined`, or `unknown`.
  - `lib/features/groups/application/group_message_listener.dart` marks an invite delivery attempt as `joined` when durable `member_joined` evidence is processed.
  - `lib/features/groups/presentation/screens/group_info_wired.dart` overlays invite delivery attempts and durable join evidence into Group Info statuses, so the creator-side UI is not a blank slate. Sessions `02` and `04` close the message-eligibility risk by proving roster presence without joined evidence is not enough for ordinary group-message recipient selection.
- Group message delivery/fanout:
  - `lib/features/groups/application/send_group_message_use_case.dart` builds recipient peer ids from `groupRepo.getMembers(groupId)`, excluding the sender, non-deliverable identities, and members whose `joinedAt` is after the message timestamp.
  - Because group creation writes invitees as members with `joinedAt` at add/invite time, the send-time cutoff protects removal/re-add timing but does not by itself prove invite acceptance.
  - Session `02-recipient-eligibility` adds the accepted-recipient guard for ordinary group messages: persisted non-joined invite attempts are excluded while accepted `joined` members and legacy/current members remain eligible.
  - The same send path includes computed `recipientPeerIds` in the offline replay envelope and then calls reliable group send.
  - `go-mknoon/node/pubsub.go` derives reliable group send recipients from the current group config and stores group inbox messages for those recipients.
  - `go-mknoon/node/group_inbox.go` derives active group inbox recipients by walking normalized group config members and active devices.
  - `go-relay-server/inbox.go` requires explicit `recipientPeerIds` for `group_store` and fans out group push notifications by iterating those ids, so relay push behavior depends on the upstream recipient set it is given. Session `04` accepts this boundary with targeted Go/relay evidence and simulator proof that terminal invitees are excluded before relay fanout.
- Incoming live group message handling:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` materializes a local group, members, key, and topic join only when a pending invite is accepted.
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart` rejects unknown local groups and rejects non-system messages when local membership is missing.
  - `lib/features/groups/application/group_message_listener.dart` only emits a local notification after `handleIncomingGroupMessage` returns a persisted message.
  - This means the ordinary live listener is guarded against notifying for messages that cannot be saved locally, and an unaccepted invitee should not be receiving live GossipSub group-message notifications.
- Push notification display and tap routing:
  - Session `03-notification-suppression-routing` added a local display-eligibility decision for ordinary group-message fallback display. Background and foreground local fallback now require local current-membership proof for parsed group-message routes, including legacy payload-only `group:<id>|message:<id>` routes.
  - `lib/features/push/application/background_push_notification_fallback.dart` preserves non-group and `group_invite` fallback behavior, keeps background provider-visible notification skipping, and uses foreground-specific eligibility so accepted/current members still get foreground local fallback when OS foreground presentation is disabled and the group drain requests a notification.
  - `lib/features/push/application/background_message_handler.dart` now checks local encrypted DB state through a fail-closed resolver before showing background group-message fallback or marking a recent remote announcement; denied paths emit leak-safe suppression flow evidence.
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart` still drains the targeted group inbox for foreground `group_message` pushes; if that group drain throws and the display eligibility resolver proves current membership, `showForegroundPushFallbackNotificationIfNeeded` can display a local fallback notification from the same remote payload.
  - `lib/core/notifications/notification_route_target.dart` maps `type: group_invite` to the shared Intros route and excludes `group_invite` from group-message-like remote data.
  - Existing tests assert that `group_invite` remote fallback routes to `intros`; the group invite listener itself does not show a local notification when an invite message is processed.
  - `lib/main.dart` routes group notification taps through `resolveGroupNotificationRouteTarget`.
  - `lib/features/push/application/resolve_group_notification_route_target_use_case.dart` opens a group only when local group and current local membership are resolved, redirects to pending invite when one exists, and otherwise returns missing.
  - When the tap resolver returns missing with no pending invite, `lib/main.dart` emits a missing-route flow event and returns without opening a route, leaving the user with no visible group or invite destination.
  - Existing route tests cover current group, pending invite redirect, missing group/invite, stale group without local member, and stale group with pending invite redirect.
- Adjacent docs:
  - `Test-Flight-Improv/91-group-invitation-status-visibility.md` covers creator-side invite status visibility, including the risk that local member presence does not prove acceptance.
  - `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md` covers foreground group push drain behavior for accepted group members.
  - Neither adjacent doc covers the reported product failure where an unaccepted invitee receives an ordinary group-message notification that cannot open a group or invite.

## 5. Scope Clarification

- In scope:
  - User-visible distinction between invited/not-yet-accepted people and accepted/current group participants in group chat behavior.
  - Group creator/admin clarity that an invited person listed in the group is not necessarily accepted or reachable for ordinary group messages.
  - Alignment between creator-side invite status or join evidence and ordinary group-message fanout/notification eligibility, so a roster row alone is not treated as acceptance.
  - Recipient behavior before invite acceptance, after invite expiry, after invite decline, and when no pending invite is locally visible.
  - An internal invite freshness gate whose effective user-visible lifetime is aligned with invite policy and pending-invite lifecycle, instead of undercutting them with a shorter hidden window.
  - Visible invite expiry as the user-facing lifecycle shown from Orbit > Intro and group invitation surfaces.
  - A non-contradiction rule: invite policy expiry, pending-invite expiry, and membership freshness proof must not present different effective lifetimes to the user.
  - A clear distinction between a pending invite that was stored and later became expired or terminal, versus an invite that was never stored because receive-time validation rejected it.
  - Expired or stale invite handling that gives recipients and creators/admins an understandable outcome, such as "Invite expired, ask an admin to resend" or creator-side "needs resend."
  - Receive-time non-storage outcomes, including stale freshness, invalid payload, unknown sender, decryption failure, revoked invite, already-used invite, and duplicate local group, when those outcomes can otherwise combine with later group-message pushes into empty notification taps.
  - Recipient behavior when invite delivery is delayed and no pending invite is stored.
  - Ordinary group-message delivery, group-message push notifications, foreground fallback notifications, background fallback notifications, local notification tap behavior, and Orbit Intro visibility for the affected recipient state.
  - The difference between an invite notification/Intros route and an ordinary group-message notification route.
  - Mixed groups where some invitees accepted and some did not.
- Explicit non-goals:
  - No broad redesign of group creation, Group Info, Orbit, or the notification center.
  - No change to the user's ability to receive and act on a valid group invite.
  - No claim about exact UI wording, iconography, storage shape, wire format, or protocol ownership.
  - No requirement that a sent or queued invite implies acceptance.
  - No change to accepted-member group message delivery, notification mute behavior, active-conversation suppression, duplicate-notification suppression, or group-message tap routing for valid current members.
  - No retroactive claim about historical messages sent before this bug is addressed.
- Accepted implementation choices:
  - The closure did not require final product-label or iconography changes for invitee, pending invite, accepted member, declined invite, expired invite, and missing invite states.
  - Existing `GroupInviteDeliveryAttempt` status plus durable `member_joined` evidence remain the creator/admin distinction; message eligibility now treats non-joined invite attempts as non-accepted.
  - The client-node-relay path is accepted at the repo-owned boundary because the upstream explicit `recipientPeerIds` set excludes non-accepted invitees before relay `group_store` fanout.
  - Provider APNs/FCM delivery guarantees remain outside this report; repo evidence proves local recipient selection, relay custody input, fallback display suppression, and tap-routing behavior.
- Acceptance bar:
  - This spec is not satisfied by unit tests alone.
  - This spec is not satisfied by proving only the invite UI, only message fanout, or only notification tap routing in isolation.
  - The accepted closure evidence provides integration, smoke, and simulator coverage across invite creation, invite acceptance or non-acceptance, group message send, recipient eligibility, push display or suppression, notification tap routing, and accepted-member preservation.

## 6. Test Cases

### Happy Path

- Given User A creates a group and invites User B, when User B has not accepted yet, then User A can still understand that User B is invited/not yet accepted rather than confirmed as an active participant.
- Given User A's Group Info status for User B is `sent`, `queued`, `needsResend`, `cannotSend`, or `unknown` rather than `joined`, when User A sends an ordinary group message, then User B is not treated as an accepted message recipient.
- Given User B has a valid pending group invite, when User B opens Orbit > Intro, then the invite is available for an explicit decision until it reaches a terminal state.
- Given User B's device receives a group invite within the visible invite lifecycle, when User B opens Orbit > Intro, then the invite can appear as a pending decision.
- Given User B sees an invite as still valid in the user-facing lifecycle, when User B accepts it, then a shorter hidden freshness gate does not reject it before the visible expiry.
- Given User B's invite reaches its user-facing expiry, when User B reviews the invitation state, then the app explains that the invite expired and that a resend is needed instead of silently omitting context.
- Given User B has not accepted the group, when User A sends an ordinary group message, then User B does not receive that ordinary group message as a readable chat message.
- Given User B has not accepted the group, when User A sends an ordinary group message, then User B does not receive a group-message notification that claims there is a readable message.
- Given User B accepts the invite, when User A sends a later ordinary group message, then User B receives the message and notification behavior expected for a current group participant.
- Given User A invited multiple users and only some accepted, when User A sends a group message, then accepted participants receive the normal group chat experience while unaccepted invitees do not receive empty group-message notifications.

### Edge Cases

- Given User B has no local group and no visible pending group invite, when a remote payload for an ordinary group message references that group, then User B does not see a notification that opens to no messages.
- Given a group-message notification tap resolves to no local group and no pending invite, when the app handles the tap, then it does not silently no-op without an understandable user-visible outcome.
- Given User B has a pending group invite but has not accepted, when a notification related to the invite itself is opened, then the app routes to the invite decision surface rather than pretending the group conversation exists.
- Given User B's device first processes a relayed invite after the aligned invite freshness proof is stale, when User B opens Orbit > Intro, then the app does not create a local group and gives an understandable stale-or-expired invite outcome.
- Given User B's pending invite was stored locally and only the visible invite expiry has passed, when User B opens Orbit > Intro, then the app presents an expired or terminal invite state rather than making it indistinguishable from a never-received invite.
- Given User B's incoming invite is rejected before storage because of stale freshness, unknown sender, decryption failure, invalid payload or policy, active revocation, already-used material, or duplicate local group, when later group-message payloads reference that group, then User B does not receive a dead-end ordinary group-message notification.
- Given User B's pending invite expired, when User A sends a group message later, then User B does not receive a group-message notification for that group.
- Given User B declined the invite, when User A sends a group message later, then User B does not receive a group-message notification for that group.
- Given User B's invite was revoked or rejected as invalid, when User A sends a group message later, then User B does not receive a group-message notification for that group.
- Given the app is foregrounded and User B has not accepted, when a group-message push arrives for that group, then the foreground experience does not produce a local notification that opens to no group or invite.
- Given the app is backgrounded and User B has not accepted, when a group-message push arrives for that group, then the background experience does not produce a dead-end group-message notification.
- Given User B receives a remote `group_invite` notification, when User B taps it, then the app routes to the Intros decision surface and does not treat the notification as an ordinary group message.
- Given User A sees User B in a group member-related surface before acceptance, when User A inspects the group, then that surface does not present User B as a confirmed message recipient.
- Given User B accepts after some earlier group messages were sent while unaccepted, when User B opens the group, then the app does not imply that pre-acceptance empty notifications represented readable local messages.

### Regressions To Preserve

- Accepted group members continue to receive ordinary group messages and eligible group-message notifications.
- Active group conversation notification suppression continues to work for accepted members.
- Duplicate notification suppression continues to work for accepted members.
- Group notification taps continue to open the group for current local members.
- Group notification taps continue to redirect to Orbit > Intro when a pending invite is the current local state.
- Valid pending group invites remain visible in Orbit > Intro until they are accepted, declined, revoked, rejected, or otherwise terminal.
- Invite expiry remains a clear terminal or non-joinable state from the recipient's perspective.
- Stored-expired invite behavior remains distinguishable from receive-time non-storage, so debugging and user-visible states do not collapse into the same missing-invite outcome.
- Invite freshness validation continues to reject stale or tampered invite payloads before local group creation, while staying aligned with the visible invite lifecycle.
- The app never presents an invite as valid for one duration while enforcing a shorter hidden membership freshness duration.
- Remote `group_invite` payloads continue to route to Intros rather than group conversation.
- Existing invite delivery status labels such as `Invite sent`, `In their inbox`, `Resend needed`, `Cannot send`, `Joined`, and `Invite unknown` remain observable where they already exist.
- Existing `member_joined` processing continues to mark invite delivery status as joined when valid join evidence arrives.
- Existing group invite authenticity, sender validation, duplicate-group rejection, membership-boundary checks, and local message persistence protections remain observable.
- Existing group creation and add-member flows do not lose the ability to show creator-side invite status or local group setup progress.

### Bug Regression

- Given User B is only invited, has not accepted, does not have the group locally, and has no visible pending invite, when User A sends a group message, then User B must not receive a group-message notification that opens to no group, no invite, and no messages.

### Acceptance Evidence

- TDD evidence is accepted through the four-session rollout: direct regressions, host smoke, targeted Go/relay tests, named gates, and simulator commands now define the maintenance safety set for this bug shape.
- Integration evidence must cover a mixed-recipient group journey where User A creates a group, at least one invited user accepts, at least one invited user remains unaccepted, User A sends an ordinary group message, accepted users receive the normal message experience, and unaccepted users are excluded from readable message delivery and dead-end group-message notification display.
- Integration evidence must cover the client-node-relay boundary: the ordinary group-message recipient set must not include a rostered-but-unaccepted invitee, and relay group push fanout must not produce a `group_message` push for that invitee from that send.
- Integration evidence must cover the tap resolver states for current group member, pending invite, and missing group/missing invite, proving that the missing state cannot become a silent dead-end after a group-message notification.
- Smoke evidence must cover the broad group chat journey with multiple invitees where some accept immediately and some do not, preserving normal accepted-member messaging while keeping the unaccepted invitee out of empty notification outcomes.
- Smoke evidence must cover creator/admin visibility in the same mixed group: invited/not-accepted users are understandable as not yet joined or not confirmed, while accepted users remain understandable as current participants.
- Simulator evidence must cover foreground group-message push behavior for an unaccepted recipient, proving the app does not surface a local fallback notification that opens to no group or invite.
- Simulator evidence must cover background group-message push behavior and notification tap handling for accepted member, pending invitee, and unaccepted or missing-invite recipient states.
- Simulator evidence must cover delayed invite processing relative to the aligned invite freshness lifecycle, proving the user sees an understandable stale-or-expired invite outcome instead of silently losing the invite and later receiving empty group-message notifications.
- Acceptance evidence must distinguish at least two missing-invite causes: a locally stored invite that reached visible expiry, and an invite that never stored because receive-time validation rejected it.
- The final acceptance evidence must explicitly include the negative matrix for pending, expired, declined, revoked or invalid, and missing-invite recipient states; none of those states may produce an ordinary group-message notification that opens to no messages.

### Existing Coverage And Closure Evidence

- Existing tests partially cover current route safety:
  - `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` covers group route success, pending invite redirect, missing route, and stale group without local membership.
  - `test/integration/notification_deeplink_integration_test.dart` covers group notification route behavior once local membership is resolved.
- Existing tests partially cover stale invite freshness:
  - `test/features/groups/application/group_invite_listener_test.dart` covers stale membership freshness not storing a pending invite or local group.
  - `test/features/groups/domain/models/group_invite_payload_test.dart` covers detailed parse failure for `staleMembershipFreshness`.
  - `test/features/groups/application/store_pending_group_invite_use_case_test.dart` covers invalid or stale payloads not storing pending invite state.
- Existing tests partially cover pending-invite expiry mechanics:
  - `test/features/groups/domain/repositories/pending_group_invite_repository_impl_test.dart` covers explicit expired-row deletion when `deleteExpiredPendingInvites` is invoked.
  - No current production caller in `lib/` invokes that expired pending-invite delete method, so existing tests do not prove any automatic 7-day cleanup journey.
- Session `03` closed the former permissive fallback behavior:
  - `test/features/push/application/background_push_notification_fallback_test.dart` now covers ordinary group-message fallback denial for non-current/missing local membership, payload-only legacy group routes, foreground visible-FCM current-member fallback preservation, and `group_invite` routing to `intros`.
  - `test/features/push/application/background_message_handler_test.dart` covers denied background group-message fallback without showing a local notification or marking a recent remote announcement.
  - `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` covers display eligibility for current-member, pending-invite, missing-group, missing-local-member, and unknown-local-identity states.
- Existing tests partially cover creator-side invite status:
  - `test/features/groups/presentation/group_info_wired_test.dart` covers `member_joined` evidence overlaying invite status and only accepted invited members rendering as joined.
  - `test/features/groups/presentation/group_info_screen_test.dart` covers invite status copy and resend visibility for status states.
  - `test/features/groups/application/group_message_listener_test.dart` covers `member_joined` marking an invite delivery attempt as joined.
  - `test/features/groups/application/create_group_with_members_use_case_test.dart` covers invite delivery attempts being recorded as sent or needs-resend during group creation.
- Existing tests partially cover send-time recipient filtering:
  - `test/features/groups/application/send_group_message_use_case_test.dart` covers explicit active recipient ids at send time, including exclusion of removed or absent peers.
  - `test/features/groups/integration/group_messaging_smoke_test.dart` covers active-recipient inbox storage for declined, expired, or never-joined fixture peers.
  - Session `02-recipient-eligibility` added direct and smoke evidence that
    persisted non-joined invite attempts are excluded from ordinary
    group-message replay, `group:inboxStore`, native `group:sendReliable`, and
    Go relay custody while accepted and legacy/current members remain eligible.
- Existing code guards live in-app notifications after message persistence, and
  session `03` now proves foreground/background remote push fallback is
  suppressed for stale, legacy, malformed, or incorrectly targeted ordinary
  group-message payloads unless local state proves current membership.
- Closed by session `04`: final mixed accepted/unaccepted journey evidence now
  combines the closed sender-fanout proof with foreground/background
  notification suppression, tap routing, and simulator states.
- Closed by session `02`: invite delivery status and durable join evidence are
  now used to keep rostered-but-unaccepted invitees out of ordinary
  group-message recipient sets.
- Closed by session `02` for upstream custody: relay custody now receives the
  explicit accepted `recipientPeerIds` list.
- Closed by session `03` for receiver-side defense-in-depth: foreground and
  background group-message fallback display now fail closed for non-current
  local membership, pending invite, missing group, unknown local identity, and
  legacy payload-only group routes; notification-open simulator evidence covers
  current-member open, pending-invite Intros redirect, and missing-group
  suppression.
- Closed by session `04`: final matrix closure now maps pending, expired,
  declined, revoked, invalid, terminal, and missing-invite recipient states to
  accepted-recipient exclusion and receiver-side suppression evidence.
- Accepted evidence layers:
  - unit: deterministic user-visible distinctions between pending invite, accepted member, terminal invite, missing invite, and current local member states.
  - integration: the mixed accepted/unaccepted group journey, ordinary message recipient eligibility, relay push fanout eligibility, pending invite lookup, and notification tap outcomes across multiple app layers.
  - smoke: multi-user group chat journey with mixed accepted and unaccepted invitees remains understandable, prevents empty notification outcomes, and does not break accepted-member messaging.
  - simulator: foreground/background notification behavior and notification tap behavior for accepted members, pending invitees, terminal invite states, and unaccepted/missing-invite recipients.

## 7. Session Closure Progress

Updated: 2026-06-04 22:31 CEST

### Report 106 Acceptance Ledger

Closure verdict: `closed` for the accepted-vs-invited ordinary group-message
notification journey. Future work should reopen this report only on a real
regression in the accepted-recipient selection, relay custody input,
receiver-side suppression, notification tap routing, or accepted-member
preservation evidence below.

What is now considered closed:

- Mixed accepted/unaccepted group journeys are covered by the `INV-106` host
  smoke and the `private_invite_terminal_states` reliability simulator Report
  106 fields. Accepted Bob receives the post-terminal group message, while
  terminal/non-accepted Charlie has no local group/key, no plaintext, no local
  fallback notification, and no sent-recipient entry.
- Ordinary group-message recipient eligibility is closed across Flutter send
  and retry paths, Dart replay, `group:inboxStore`, native
  `group:sendReliable`, and relay custody input. Relay-server behavior is
  accepted at the repo-owned boundary because it fans out from the supplied
  accepted `recipientPeerIds` set.
- Receiver-side suppression and tap routing are closed for current member,
  pending invite, missing group/missing invite, unknown local identity,
  non-current local member, legacy payload-only group route, and
  foreground/background fallback cases.
- Pending, expired, declined, revoked, invalid, terminal, and missing-invite
  states no longer remain open matrix items for this bug shape; they are covered
  by accepted-recipient exclusion and/or receiver-side fail-closed suppression.

Residual-only items:

- Provider APNs/FCM background or terminated delivery proof remains outside this
  report until a provider-backed device harness exists. This closure does not
  claim provider-side delivery SLA or TestFlight APNs behavior.
- The session `02` full Go sweep failure
  `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree` remains an explicit
  out-of-scope native topic join/leave/update lifecycle follow-up, not a Report
  106 blocker.

Accepted differences:

- Session `04` added Report 106 fields to the existing
  `private_invite_terminal_states` simulator criteria instead of creating a new
  scenario.
- Session `04` did not change production behavior; sessions `01`, `02`, and
  `03` already supplied the implementation behavior, and session `04` supplied
  final acceptance evidence and stable documentation closure.
- No `91-group-invitation-status-visibility.md` update was required because
  session `04` did not add or change creator/status UI evidence.

Maintenance-time safety gates:

- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
- `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/resolve_group_notification_route_target_use_case_test.dart test/features/push/application/prepare_notification_open_use_case_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/integration/notification_deeplink_integration_test.dart test/integration/group_notification_dedupe_integration_test.dart`
- `flutter test --no-pub -d macos integration_test/notification_open_ui_smoke_test.dart`
- `cd go-mknoon && go test ./bridge -run TestGroupSendReliable`
- `cd go-mknoon && go test ./node -run 'TestSendGroupMessageReliable|TestGroupInboxStore'`
- `cd go-relay-server && go test ./...`
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh runtime-telemetry`
- `./scripts/run_test_gates.sh completeness-check`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 'integration_test/scripts/run_group_multi_party_device_real.dart:private_invite_terminal_states'`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_notification_open_ui_smoke.dart`

### Session `01-invite-lifecycle`

Closure verdict: `closed` for the invite lifecycle/freshness slice only.

What is now considered closed:

- The normal group invite membership freshness proof now aligns with the visible
  pending invite lifecycle instead of expiring after 24 hours.
- A delayed invite that remains inside the visible pending invite/policy window
  can parse, store as pending, notify the pending-invite stream, and accept
  without creating local group state before acceptance.
- Explicit shortened, stale, or tampered freshness proof rejection remains a
  security guard; stale proof rejection did not get removed.

Residual-only items:

- No residual remains inside session `01-invite-lifecycle`.
- This session did not close the full product report by itself. The final
  product report is now closed by the later sessions: session
  `02-recipient-eligibility` closed accepted-recipient fanout, session
  `03-notification-suppression-routing` closed receiver-side dead-end
  notification suppression, and session `04-acceptance-closure` closed final
  mixed-recipient acceptance evidence plus matrix/closure-reference updates.

Accepted differences:

- Session `01` aligned the normal generated freshness proof lifetime to 7 days
  in `group_invite_payload.dart`; it did not add a new cross-model duration
  abstraction.
- Session `01` did not change creator/admin status copy, Orbit rendering,
  notification routing, Flutter-to-Go recipient selection, Go relay fanout, or
  stable notification/group matrices.

Reopen rule:

- Reopen session `01` only on a real invite-lifecycle regression: a
  delayed-but-policy-valid invite again fails after the old 24-hour hidden
  freshness window, a stored valid pending invite cannot be accepted before
  visible expiry, or an explicitly shortened/tampered proof starts validating.

Maintenance-time safety gates:

- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart`
- `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `flutter test --no-pub test/features/groups/domain/models/pending_group_invite_test.dart`
- `./scripts/run_test_gates.sh groups`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 5`

### Session `02-recipient-eligibility`

Closure verdict: `accepted_with_explicit_follow_up` for the recipient
eligibility slice only.

What is now considered closed:

- Ordinary group-message sender fanout excludes persisted non-joined invite
  attempts while preserving accepted `joined` members and legacy/current members
  with no invite-attempt row.
- Dart offline replay, `group:inboxStore`, native `group:sendReliable`, and Go
  relay custody now preserve the same explicit accepted recipient list,
  including explicit empty recipient lists.
- Production send and retry paths that have access to invite delivery attempt
  state are wired through that repository, including the manual retry screen
  path verified by the focused `group_conversation_wired` regression.
- Creator/admin direct evidence keeps `sent`, `queued`, `needsResend`,
  `cannotSend`, and `unknown` invite delivery states distinct from accepted
  membership.

Residual-only items:

- The only residual follow-up is the previously triaged full Go sweep failure
  `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`. It is classified as
  an out-of-scope native topic join/leave/update lifecycle issue, not a session
  `02` recipient eligibility blocker.
- This session did not close the full product report by itself. Sessions
  `03-notification-suppression-routing` later closed foreground/background
  notification suppression, tap-routing, and simulator evidence for stale or
  wrongly targeted payloads, and session `04-acceptance-closure` later closed
  final mixed-recipient acceptance plus matrix/closure doc updates.

Accepted differences:

- No relay-server changes were needed for this session because the landed
  Flutter and Go evidence preserves explicit upstream `recipientPeerIds` into
  relay custody.
- No simulator, push fallback, notification tap-routing, or final matrix update
  was performed in session `02`; session `03` later closed the push/tap
  portion, and session `04` later closed final matrix closure.

Reopen rule:

- Reopen session `02` only on a real recipient-eligibility regression: a
  persisted non-joined invite attempt reappears in ordinary group-message
  replay, `group:inboxStore`, native reliable-send custody, or manual retry
  fanout, or an accepted/current member is incorrectly dropped from those paths.

Maintenance-time safety gates:

- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `go test ./bridge -run TestGroupSendReliable`
- `go test ./node -run 'TestSendGroupMessageReliable|TestGroupInboxStore'`
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

### Session `03-notification-suppression-routing`

Closure verdict: `closed` for the receiver-side notification suppression and
tap-routing slice only.

What is now considered closed:

- Ordinary group-message local fallback notifications are suppressed unless
  local state proves the recipient is a current local group member.
- Background fallback suppression opens local encrypted state read-only,
  fails closed on unavailable local identity/state, and does not mark recent
  remote announcements when display is denied.
- Foreground fallback preserves accepted/current-member display when drain
  requests a notification, including visible FCM payloads, while suppressing
  non-current, missing, pending-invite, and payload-only legacy group routes.
- Notification-open evidence covers current-member group open, pending-invite
  redirect to Intros, and missing-group suppression without empty navigation.
- `group_invite` payloads remain routed to Intros and are not reclassified as
  ordinary group messages.

Residual-only items:

- No residual remains inside session `03-notification-suppression-routing`.
- This session did not close the full product report by itself. Session
  `04-acceptance-closure` later closed final mixed accepted/unaccepted journey
  proof and final matrix updates.

Accepted differences:

- Session `03` extended existing simulator/test files instead of adding new
  gate definitions, so `completeness-check` was not required for that slice.
- Session `03` did not change sender recipient selection, native/relay fanout,
  creator/admin copy, or final matrix docs; those boundaries are covered by
  session `02` and session `04`.

Reopen rule:

- Reopen session `03` only on a real notification-suppression regression: a
  non-current, pending, missing, unknown-identity, or legacy payload-only
  ordinary group-message route displays a local fallback notification; an
  accepted/current member loses eligible foreground/background fallback; or
  `group_invite` stops routing to Intros.

Maintenance-time safety gates:

- `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart`
- `flutter test --no-pub test/features/push/application/background_message_handler_test.dart`
- `flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
- `flutter test --no-pub test/features/push/application/prepare_notification_open_use_case_test.dart`
- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`
- `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`
- `./scripts/run_test_gates.sh groups`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh runtime-telemetry`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_notification_open_ui_smoke.dart`

### Session `04-acceptance-closure`

Closure verdict: `closed` for final mixed-recipient acceptance and stable
matrix/closure documentation.

What is now considered closed:

- The existing `INV-106` host smoke passed as part of
  `group_messaging_smoke_test.dart`, preserving accepted-recipient delivery and
  excluding non-joined invitees from ordinary message persistence.
- `private_invite_terminal_states` now emits and validates
  `report106MixedInviteNotificationProof` for sender accepted-only recipients,
  Bob's accepted-member receipt, and Charlie's terminal-invitee no-message,
  no-key, no-local-fallback-notification proof.
- Foreground group push and notification-open reliability smokes were rerun
  after session `04`, preserving current-member display/open, pending-invite
  Intros redirect, and missing/non-current suppression.
- Targeted native/relay commands, named gates, and completeness classification
  all passed with the session `04` acceptance harness changes.

Residual-only items:

- Provider APNs/FCM background and terminated delivery proof remains outside
  Report 106.
- The out-of-scope `TestGL019ConcurrentJoinLeaveUpdateSameGroupIsRaceFree`
  full Go sweep failure remains preserved from session `02` and is not a Report
  106 closure blocker.

Accepted differences:

- No production code change was needed in session `04`.
- The final simulator proof extends the existing multi-party
  `private_invite_terminal_states` scenario instead of adding a new Report 106
  scenario.

Reopen rule:

- Reopen session `04` only if the `INV-106` host smoke, Report 106 simulator
  fields, foreground/open simulator rows, targeted Go/relay gates, or stable
  matrix closure evidence regresses for the accepted-vs-invited notification
  journey.
