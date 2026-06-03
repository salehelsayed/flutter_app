# 1. Title and Type

- Title: Current admins must keep stale pending group invites recoverable
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/105-current-admin-stale-invite-refresh-and-accept-catchup.md`

# 2. Problem Statement

A user can receive a group invite while the inviter is still an admin, wait to
accept it, and then accept after group administration has changed. During that
waiting window, the original inviter may lose admin rights and another admin may
change the group name, description, avatar, roles, members, or key material.

The user still expects one clear result when tapping Accept: either they join the
current group with the current details, or the app gives a clear non-joined
state. The app must not depend on the original inviter's device being the only
place that knows the invite is still pending.

The current Scenario 7 stale-invite regression now passes in the simulator after
recent replay-envelope and accept-catch-up fixes, and the latest Alice/Bob log
review did not show the previous `payload_message_mismatch`,
`Failed to accept invite`, or `Invite accepted, but recovery is still catching
up` failure. The remaining backlog risk is narrower: pending invite freshness
and accept-time recovery are not yet proven when the original inviter is no
longer an admin before the invitee accepts.

From the user's perspective, this matters because the invite card is the only
visible entry point. If the app cannot refresh or verify the latest group state
after admin changes, the invitee can see stale group identity, a confusing
failure, or a retryable invite that looks like Accept did nothing.

# 3. Impact Analysis

- Affected users: late invitees, admins who change group ownership or roles, and
  existing members who expect all participants to converge on the same group
  identity.
- Trigger moments: a group invite is sent, the invitee stays offline or waits,
  the inviter loses admin rights, and a different admin changes group metadata,
  membership, roles, config, or key material before the invitee taps Accept.
- Severity: high for group trust. A stale invite can bootstrap a real group
  join, but the user-visible group identity can be wrong or the accept result can
  be unclear.
- Frequency: not measurable from repo evidence. The current tests cover
  Scenario 7 stale metadata recovery, but do not prove the original-inviter
  admin-loss case.
- Confusion cost: the invitee can repeatedly tap Accept, see old metadata, or
  fail to understand whether the group is joined, still pending, or waiting for
  recovery.
- Regression risk: stale invite acceptance spans encrypted invite payloads,
  pending invite persistence, admin authorization, group inbox recovery, direct
  invite refresh, role/member convergence, avatar bytes, and the four-device
  simulator harness.

# 4. Current State

## Status

- Report 103 documents the original Scenario 7 user bug: User D accepted a stale
  invite and saw `test 2` / `222` / old image instead of `test 3` / `333` /
  latest image, while the invite stayed visible.
- Report 104 documents the earlier root-cause analysis. The strongest reusable
  fact remains that a group invite carries a send-time `groupConfig` snapshot;
  it is not automatically the latest group truth at accept time.
- A later manual Bob log showed a different concrete failure point:
  `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED` with
  `payload_message_mismatch`.
- The replay mismatch was traced to metadata replay envelopes using a different
  `messageId` from the signed plaintext. The local fix aligned the envelope and
  signed payload IDs in `lib/features/groups/presentation/screens/group_info_wired.dart`.
- The targeted Scenario 7 simulator then passed. Dana's verdict showed
  `pendingInviteStaleAtAccept == true`,
  `pendingInviteRefreshedBeforeAccept == false`,
  `pendingInviteCountAfterAccept == 0`,
  `acceptedGroupName == test 3`, and
  `acceptedGroupDescription == 333`.
- Alice and Bob logs from that successful run ended with `All tests passed` and
  did not contain the old accept failure strings. They still showed repeated
  group inbox cursor EOF/retry noise, which is separate reliability evidence to
  keep in mind.

## Current Behavior and Evidence

- `lib/features/groups/application/send_group_invite_use_case.dart` sends an
  encrypted invite with a point-in-time `GroupInvitePayload.groupConfig`.
- `lib/features/groups/application/group_config_payload.dart` includes group
  name, description, avatar blob/mime, members, roles, config, and metadata
  watermarks in that snapshot.
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  materializes the accepted group from the invite `groupConfig` before the
  accepted-inbox catch-up can apply newer signed group updates.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  now tries to drain accepted group inbox state and avoids committing a stale
  materialized group when it cannot prove metadata advanced beyond the invite.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  is the durable catch-up path that can replay signed metadata, membership,
  role, reaction, and message state after the invitee joins.
- `lib/features/groups/application/group_message_listener.dart` applies signed
  group metadata and membership events, including `group_metadata_updated`,
  `member_role_updated`, `members_added`, `member_removed`, and `member_joined`
  system events.
- `lib/features/groups/application/refresh_pending_group_invites_for_metadata_change_use_case.dart`
  refreshes pending invite snapshots after metadata changes by reading
  `GroupInviteDeliveryAttempt` rows for the current local admin device.
- `lib/features/groups/application/resend_group_invite_use_case.dart` can resend
  a current invite snapshot for a known group member when the current local app
  has the group, member, key, and invite-delivery attempt context.
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart` stores
  local invite attempt status such as `sent`, `queued`, `needsResend`,
  `cannotSend`, and `joined`.
- `lib/features/groups/presentation/screens/contact_picker_wired.dart` records
  invite delivery attempts when an admin adds members.
- `lib/features/groups/application/group_message_listener.dart` marks invite
  attempts as `joined` when it observes a `member_joined` event.
- The weak point is ownership of the "this invite is still pending" knowledge:
  the current refresh loop reads local delivery attempts. It does not yet prove
  that a different current admin, who did not originally send the invite, will
  automatically know to refresh the stale invitee.

## Files That Need Review

- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/refresh_pending_group_invites_for_metadata_change_use_case.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `test/core/services/fake_p2p_service.dart`

## Existing Sim and Test Assets to Reuse or Update

- `integration_test/scripts/run_group_multi_party_device_real.dart` already
  registers `scenario7_group_invite_stale_metadata_recovery`.
- `integration_test/group_multi_party_device_real_harness.dart` contains the
  four-role Scenario 7 flow, including stale invite capture, Dana accepting the
  stale invite, final metadata/avatar proof, role proof, and four-way message
  matrix proof.
- `integration_test/scripts/group_multi_party_device_criteria.dart` validates
  Scenario 7 verdict fields such as `pendingInviteStaleAtAccept`,
  `pendingInviteRefreshedBeforeAccept`, `acceptedGroupName`,
  `acceptedGroupDescription`, `pendingInviteCountAfterAccept`,
  `finalRolesConverged`, and `fullMessageMatrixProofPassed`.
- `test/integration/group_multi_party_device_criteria_test.dart` already has
  positive and negative verdict fixtures for Scenario 7 stale invite recovery.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  contains GCA-103 accept/catch-up tests for stale invite metadata recovery,
  failed first drain rollback, duplicate retry, equal-timestamp replay, and
  buffered direct metadata.
- `test/features/groups/presentation/group_info_wired_test.dart` includes
  metadata refresh behavior for pending invite payloads and the replay-envelope
  ID regression that blocked manual accept.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` covers stale
  pending invite accept behavior from the Orbit/Intros surface.
- `test/features/groups/presentation/group_list_wired_test.dart` covers the
  group-list pending invite accept UI, including recovery copy behavior.

## Challenges From the Previous Bug

- The simulator once passed while manual testing still failed. Future evidence
  for this backlog item must include a negative reproduction that fails for the
  intended reason before claiming closure.
- The manual failure was not simply stale metadata. It failed during accepted
  group inbox replay signature validation with `payload_message_mismatch`.
- The app had multiple delivery paths for group updates: GossipSub/live publish,
  group inbox replay, and best-effort direct messages. A test can accidentally
  pass through one path while the path the user needs remains broken.
- Pending invite freshness and accepted group catch-up are related but not the
  same problem. A refreshed invite card can hide a broken accept-time catch-up,
  while a working accept-time catch-up can hide missing current-admin refresh.
- Avatar metadata is not enough. The test must prove latest avatar bytes or a
  stable byte/hash proof, not only latest `avatarBlobId`.
- Relay noise can obscure the real failure. The last passing sim still had
  repeated `GROUP_INBOX_ERROR` EOF retries in Alice and Bob logs.
- Repeated Accept behavior must stay in scope because a lingering invite turns a
  single accept failure into multiple local join events and user confusion.

# 5. Scope Clarification

## In Scope

- A stale pending invite remains safe and understandable when the original
  inviter loses admin rights before the invitee accepts.
- A current admin can change group metadata, avatar, roles, members, or config
  after the invite was sent without causing the late invitee to settle on the
  stale invite snapshot.
- The late invitee either accepts into the latest verified group state or stays
  in a clear non-joined/pending state.
- The final group shown under All has the latest group name, description,
  avatar bytes, member list, roles, and config that current admins see.
- The pending invite is not left visible as an actionable card after a
  successful accepted join.
- The result does not depend on the original inviter's local
  `GroupInviteDeliveryAttempt` row being available on another admin's device.
- The acceptance evidence must distinguish "invite was refreshed before accept"
  from "invite stayed stale but accept-time recovery applied the latest state."

## Improvement Target

- Treat the invite snapshot as bootstrap material, not final group truth.
- Treat current signed group state as the authority the invitee must converge
  to before the group is shown as joined.
- Ensure current admins and late invitees have an observable path to the latest
  state even when the original inviter/admin is no longer the right actor.
- Preserve fail-closed behavior: if the latest state cannot be verified, the app
  must not show the stale group as successfully joined.

## Non-Goals

- No broad redesign of group roles, admin policy, group key cryptography, or
  GossipSub itself.
- No requirement that GossipSub replay historical messages to late subscribers.
- No requirement that every old invite card always updates visually before the
  user taps Accept.
- No requirement to introduce centralized server authority for group state.
- No product copy redesign outside the stale invite accept and pending invite
  clarity needed for this flow.
- No claim that Status, Session, or another app's exact protocol should be
  copied. The relevant principle is only that durable signed state should win
  over a stale invite snapshot.

## Accepted Ambiguities for Later Work

- The later implementation pass can decide whether current-admin freshness is
  proven by refreshed invite fanout, accept-time authoritative replay, explicit
  state request, or a combination.
- The later implementation pass can decide how to represent pending invitees
  across admin devices, as long as user-visible acceptance does not depend on
  the original inviter.
- The later implementation pass can decide how to handle key-changing updates
  separately from metadata-only updates, as long as stale successful joins are
  not allowed.

# 6. Test Cases

## Happy Path

- Given Alice invites Bob while Alice is an admin, and Bob waits to accept, when
  Alice remains an admin and another admin changes the group name, description,
  and avatar before Bob accepts, then Bob accepts into the latest verified group
  state and the invite disappears.
- Given Alice invites Bob, Alice later loses admin rights, and Charlie as a
  current admin changes the group name, description, and avatar before Bob
  accepts, when Bob taps Accept, then Bob sees the latest group details and not
  Alice's stale invite snapshot.
- Given the pending invite card still displays stale send-time metadata before
  Bob taps Accept, when Bob accepts and recovery succeeds, then the final group
  under All displays the latest current-admin metadata and avatar bytes.
- Given the old invite is stale and is not refreshed before accept, when the app
  can verify latest signed group state during accept, then the final accepted
  result is success, the pending invite count becomes zero, and retrying Accept
  returns a non-actionable not-found result.
- Given all four members are active after Bob/Dana accepts, when each member
  sends a message, then every other active member receives exactly one copy.

## Edge Cases

- Given the original inviter loses admin rights before the invitee accepts, when
  a current admin changes group roles but not metadata, then the late invitee
  converges to the current role map and does not restore the original inviter's
  old admin state from the invite.
- Given the original inviter loses admin rights before accept and the current
  admin changes the avatar, when the invitee accepts, then the invitee has the
  latest avatar bytes, not only the latest avatar blob id.
- Given the latest group update changes key material or membership in a way the
  stale invite cannot decrypt, when the invitee taps Accept, then the app does
  not show a stale joined group as successful.
- Given current-admin freshness cannot be verified because group inbox catch-up
  is unavailable, when the invitee taps Accept, then the app leaves a clear
  pending or retryable state without materializing stale group details under
  All.
- Given the invitee taps Accept more than once during a degraded recovery
  window, then the app does not create duplicate local `member_joined` timeline
  rows or duplicate join fanout to existing members.
- Given the current admin did not originally send the invite, when that admin
  edits group details, then the late invitee is still eligible for fresh state
  delivery or accept-time recovery.
- Given the invitee was offline when the current admin changed metadata, when
  the invitee later accepts within the durable replay window, then the app
  applies the latest current-admin state before showing the group.

## Bug Regression

- Reproduce the current drawback with a four-role simulator journey:
  - Alice, Bob, Charlie, and Dana start with the Scenario 7 contact graph.
  - Alice or Charlie sends a group invite to the late invitee while the group
    still has older metadata.
  - The simulator captures the invite as stale before accept.
  - The original inviter loses admin rights before the late invitee accepts.
  - A different current admin changes the group name, description, avatar, and
    role/member state after the original inviter loses admin rights.
  - The late invitee accepts without the pending invite being refreshed before
    accept.
  - The current app should reveal the drawback by failing to prove both
    original-inviter independence and latest final state, or by leaving the
    invitee pending/failed when no current-admin freshness path exists.
  - After the future update, the same journey must pass with latest final
    metadata/avatar/roles, pending invite count zero after accept, and full
    message matrix success.
- The simulator verdict must include fields that distinguish:
  - stale invite captured before the latest metadata;
  - original inviter admin role lost before accept;
  - pending invite not refreshed before accept, when that path is being tested;
  - current admin latest metadata published before accept;
  - accepted group name and description equal the latest current-admin values;
  - accepted avatar bytes differ from the stale invite avatar;
  - final role map matches the current admin state;
  - pending invite count after accept is zero;
  - retry Accept is non-actionable after success;
  - all active members can exchange messages after accept.

## Reuse or Update Existing Simulator Coverage

- Reuse the existing Scenario 7 four-role structure in
  `integration_test/group_multi_party_device_real_harness.dart`.
- Reuse the existing Scenario 7 criteria shape in
  `integration_test/scripts/group_multi_party_device_criteria.dart`.
- Reuse the existing command registration in
  `integration_test/scripts/run_group_multi_party_device_real.dart`.
- Add or update criteria-side negative fixtures in
  `test/integration/group_multi_party_device_criteria_test.dart` so stale final
  metadata, missing original-inviter-admin-loss proof, stale avatar bytes,
  lingering invite, and incomplete message matrix all fail for specific reasons.
- Keep the existing Scenario 7 stale invite recovery test as a preservation
  baseline; the new coverage should extend it rather than weaken its current
  `test 3` / `333` / pending-count-zero guarantees.

## Regressions to Preserve

- Existing Scenario 7 stale invite recovery still passes when the original
  inviter remains a valid admin and accepted-inbox catch-up succeeds.
- Existing group invite authenticity, recipient binding, expiry, revocation,
  and single-use checks remain observable.
- Existing group metadata edits by an authorized admin still converge for
  already-joined members.
- Existing admin promotion/demotion enforcement remains observable.
- Existing Bob-demoted-cannot-edit-details behavior remains observable.
- Existing add-member flow still sends encrypted invites only to selected
  contacts.
- Existing group avatar upload and download behavior still proves latest bytes
  for all active recipients.
- Existing group text fanout still works after admin role changes and late
  member acceptance.
- Existing retry/rollback behavior still prevents stale groups from appearing
  under All when latest state cannot be verified.
- Existing pending invite UI from Orbit and Group List remains consistent after
  accept.

## Other Group Tests to Run as Safety Coverage

- Focused accept use-case coverage for stale invite metadata recovery.
- Focused Group Info metadata refresh and replay-envelope coverage.
- Focused Orbit and Group List pending invite accept UI coverage.
- Scenario 7 criteria unit coverage.
- Existing Scenario 7 four-simulator reliability run.
- The promoted-admin permissions and four-user message reliability simulator
  profile.
- Group admin metadata convergence tests.
- Group invite terminal-state tests.
- Group stale invite re-add tests.
- Group stale/lower key update and partial key distribution tests.
- Group epoch key reliability tests where key material changes are involved.
- Group media all-recipient coverage when avatar/media permissions are touched.
