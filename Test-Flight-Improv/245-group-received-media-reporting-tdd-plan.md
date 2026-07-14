# 245 - Group Received Media Reporting

Status: accepted / intentionally not applicable
Type: Product disposition and preservation closure
Spec: group received-media Report is intentionally absent; preserve group actions and explicit membership controls
Classification: product non-goal
Closure tier: repository preservation

## Final Product Decision

Mknoon intentionally has no received-media reporting organization, backend,
gateway, queue, receipt, or UI. Discussion-group reporting is not waiting for
an external authority. Plan 245 is closed as accepted/not-applicable.

Group participation is not a centralized moderation system. The source-proven user
controls are:

- group invitations are explicitly accepted or declined;
- blocked contacts cannot authorize or deliver a new group invitation through
  the normal contact-backed invite path;
- Mute is an installation-local notification preference and does not discard
  or suppress group messages; and
- Leave exits the group/topic and removes local group membership state, subject
  to the last-admin invariant.

Contact Block is not sender-level group moderation. The current group message
receive path does not consult contact block state, so blocking an existing group
member does not suppress that member's already-authorized messages/media. This
limit is explicit in the closure and is not changed by Plan 245.

## Current Source Truth

- `lib/features/groups/application/group_received_media_action_policy.dart:11`
  defines only Save, Share, Delete for me, Info, and Reply.
- Discussion eligibility is current-state and fail-closed for direction,
  media type, owner lane, integrity/private-media state, and write authority.
- `lib/features/groups/application/group_invite_listener.dart:177-192` and
  `group_invite_auth.dart:12-31` reject blocked-contact invite paths.
- `lib/features/groups/application/group_message_listener.dart:118-230` has no
  `ContactRepository` dependency, and
  `handle_incoming_group_message_use_case.dart` has no contact/block input or
  sender-block gate. `ML-016` persists a non-contact roster member delivery;
  membership/key authorization remains the group-message boundary.
- `lib/features/groups/application/set_group_muted_use_case.dart:6-45` records a
  device-local notification preference.
- `lib/features/groups/application/leave_group_use_case.dart:8-68` owns explicit
  group exit and its last-admin guard.

## Scope Contract

Must preserve:

- discussion received-media Save, Share, Delete for me, Info, and Reply when
  currently authorized;
- current-row integrity/private-media checks and source transport silence for
  local actions;
- invite Accept/Decline, notification-only Mute, and Leave behavior; and
- existing group membership, key, and writer authorization.

Must remain absent:

- Report action/copy, reason/consent/status UI, moderation notification, or
  dashboard;
- reporting gateway/service/endpoint/relay/Go command, request/evidence schema,
  upload, queue, retry, idempotency, receipt, retention policy, audit fixture,
  or database migration; and
- any relabeling of Block, Delete, Mute, Leave, Share, group publication, or
  telemetry as reporting.

No production or test semantics are changed by this closure.

## Causal Test Contract

| Case | Preserved behavior | Existing proof |
|---|---|---|
| TC-245-01 | Discussion media action capabilities remain exact and fail closed by state | `group_received_media_action_policy_test.dart::GMA-01 discussion incoming media capabilities vary safely by action and state` |
| TC-245-02 | Wired local media actions reach only their injected coordinators and remain transport-silent | `group_conversation_wired_test.dart::GMA-11 wired media actions reach only injected coordinators` |
| TC-245-03 | Group invitation is user-controlled and blocked-contact invite authorization fails closed | `group_list_wired_test.dart::accepting a pending invite joins the group and removes the row`, `::declining optimistically hides the row but keeps the invite until the undo window elapses`, plus `group_invite_listener_test.dart::does not process invite from blocked contact` |
| TC-245-04 | Mute remains notification-only while messages persist | `group_message_listener_test.dart::suppresses local notification for muted groups but still persists the message` |
| TC-245-05 | Leave exits explicitly and the sole-admin invariant is preserved | `leave_group_use_case_test.dart::leaves group successfully` and `blocks sole admin from leaving` |
| TC-245-06 | No reporting production path or gateway/config/result contract exists | shared structural absence commands |

No new reporting test is needed. Existing action, invitation, mute, leave, and
authorization tests provide the causal preservation evidence.

## Acceptance Commands

```bash
flutter test test/features/groups/application/group_received_media_action_policy_test.dart \
  --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'GMA-11 wired media actions reach only injected coordinators'
flutter test test/features/groups/application/group_invite_listener_test.dart \
  --plain-name 'does not process invite from blocked contact'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'accepting a pending invite joins the group and removes the row'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'declining optimistically hides the row but keeps the invite until the undo window elapses'
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  --plain-name 'ML-016 incoming member message falls back to group member label when sender username is empty'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'suppresses local notification for muted groups but still persists the message'
flutter test test/features/groups/application/leave_group_use_case_test.dart \
  --plain-name 'blocks sole admin from leaving'

if rg --files lib android ios go-mknoon go-relay-server | \
  rg -i '(^|/)(received_media_report|group_media_report|announcement_media_report|reporting_authority|reporting_gateway|safety_gateway)'; \
then exit 1; else echo PASS; fi

if rg -n -i 'class[[:space:]]+[A-Za-z0-9_]*(ReportingAuthority|ReportingGateway|MediaReportGateway)|REPORTING_FIXTURE_URL|consentedMediaV1|metadataOnlyV1|Report received by|reporting is unavailable right now' \
  lib android ios go-mknoon go-relay-server; then exit 1; else echo PASS; fi

git diff --check
```

Focused Flutter commands run only in the root-owned serialized slot. No full
`host-all` and no Graphify refresh are required for this documentation-only
closure.

## Acceptance Evidence And Done Criteria

- [x] Report is intentionally absent, not external-provisioning-pending.
- [x] Group ordinary media actions remain unchanged and independent.
- [x] Invite Accept/Decline, notification-only Mute, and Leave are recorded as
  the actual user controls.
- [x] Contact Block is not overstated as filtering existing group members.
- [x] No reporting backend, gateway, outbox, receipt, migration, or UI exists.
- [x] Existing causal tests cover the accepted absence; no report fake was
  authored.
- [x] Track-2/Wave-2 full host census passed `1151/1151` commands: `1143`
  Flutter files (`11502` tests passed, `1` skipped) and `8/8` Go legs.
- [x] Focused exact sentinels passed in the serialized slot: `8/8` Flutter
  invocations and `8/8` cases.
- [x] Scoped documentation diff/hygiene checks are clean.

## Device/Relay Proof Profile

N/A. Reporting has no native, relay, credential, or external-service boundary
by product decision.

## Reopen Rule

Reopen Plan 245 only after an explicit product decision authorizes a reporting
organization and user-visible reporting capability. External service
availability alone is not authorization.
