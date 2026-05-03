# EC-007 Session Plan - Stale role and invite actions after demotion/removal

Status: prerequisite-blocked

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:58:00+02:00 | Local planner completed | EC-007 source matrix row; ordered-session EC-007 row; local stale role/invite tests; receive-side stale mutation tests; signed invite auth tests; `group_invite_auth.dart` and invite accept/handle paths | Current evidence covers local stale role/invite rechecks and receive-side stale mutation rejection. The remaining row-owned gap is stale removed/demoted inviter replay with an old self-consistent signed invite snapshot; the repo lacks an authoritative current-membership/freshness source for new invitees to reject that case. | Run focused positive evidence, then persist EC-007 as `Partial`/prerequisite-blocked without changing production code. |

## real scope

EC-007 asks for queued role changes and invites after demotion or removal, including offline replay after B reconnects. Current shipped coverage includes local stale permission rechecks, receive-side stale membership/role/metadata rejection, and invite rejection when the signed snapshot itself shows the inviter is non-admin, invite-disabled, or removed. It does not prove rejection of a removed or demoted inviter replaying an old but internally valid signed invite snapshot to a new invitee.

## closure bar

EC-007 can move to `Covered` only when:

- queued role changes after demotion fail locally and remotely without role/audit side effects
- queued invite/add-member actions after invite permission loss fail locally without pending/group/key side effects
- receive-side stale membership/role mutations after demotion/removal fail before state, timeline, and bridge side effects
- stale removed/demoted inviter replay with an old self-consistent signed invite snapshot is rejected before pending/group/key/join state, including offline replay
- the required authoritative current-membership/freshness source for new invitees either exists with direct proof or the source matrix explicitly scopes that case out

## session classification

`prerequisite-blocked`. This is not just missing assertions around existing code: rejecting a stale self-consistent invite from a removed inviter requires a freshness or authoritative membership proof that the current invite model does not provide to new invitees.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter application evidence.
- Real-network proof is supplemental; the blocker is missing invite freshness/current-membership primitives.

## files touched

- closure docs only

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/update_group_member_role_use_case_test.dart --plain-name 'rechecks revoked manage-roles permission before applying queued role update'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name 'rechecks revoked invite permission before adding a queued member'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RP005 demoted creator receive-side mutations are rejected before side effects'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'IJ002 rejects signed non-admin or removed inviters before state or join'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart --plain-name 'IJ002 does not store pending invite from unauthorized or removed inviter'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'IJ002 persisted signed snapshot must still authorize inviter at accept time'` passed (`+1`).
- Code inspection confirmed `group_invite_auth.dart` authorizes the inviter against the signed invite snapshot and trusted contact key; it has no current authoritative membership/freshness check for a new invitee receiving an old but internally valid signed snapshot.
- `git diff --check` must pass after closure docs.

## positive evidence

- Local queued role update rechecks current manage-role permission and leaves target role plus bridge state unchanged after permission loss.
- Local queued add/invite path rechecks current invite permission and creates no target member or bridge update after permission loss.
- Receive-side stale creator mutation events for `member_added`, `member_removed`, `member_role_updated`, and signed `group_metadata_updated` are rejected before state, timeline, signature verification, or bridge update side effects.
- Direct invite handling, invite listener, and pending accept reject signed snapshots whose inviter is non-admin, invite-disabled, or missing from the snapshot.

## blocker class

- `missing_authoritative_inviter_membership_freshness_proof`
- `missing_stale_self_consistent_invite_replay_rejection`
- `missing_offline_stale_invite_after_removal_fake_network_proof`

## done criteria for this blocked session

- Source matrix EC-007 remains `Partial` with positive shipped evidence and blockers named directly.
- `test-inventory.md` gets an EC-007 crosswalk row with the fresh evidence.
- Breakdown current-session state, shared prerequisites, session ledger, ordered row, and classification counts record EC-007 as `prerequisite-blocked`.
- No `Covered` or accepted EC-007 claim is made.

## scope guard

Do not invent an authoritative group-membership freshness protocol inside this closure. Future closure needs a product-level way for new invitees to verify that an inviter is still authorized at invite use time, or an explicit source-matrix decision that self-consistent stale signed invite snapshots are out of scope.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:59:00+02:00 | Local evidence auditor completed | Focused local stale role/invite tests, receive-side stale mutation tests, invite signed-snapshot tests, and invite auth code inspection | Blocked. Shipped stale role and invalid-snapshot invite paths are covered, but not stale self-consistent invite replay after removal/demotion. | Persist EC-007 as `Partial`/prerequisite-blocked without changing product code. |

## Final Execution Verdict

Blocked on 2026-05-01. EC-007 remains `Partial`: queued stale role changes and invite/add-member actions have strong local and receive-side evidence, but stale invite replay after inviter removal/demotion cannot fully close until the repo has authoritative inviter membership freshness proof for old self-consistent signed invite snapshots or an explicit source-matrix scope decision.
