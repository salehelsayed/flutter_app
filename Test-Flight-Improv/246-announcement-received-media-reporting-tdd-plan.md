# 246 - Announcement Received-Media Reporting

Status: accepted / intentionally not applicable
Type: Product disposition and preservation closure
Spec: received-media Report is intentionally absent; preserve announcement actions and user-controlled trust/membership boundaries
Classification: product non-goal
Closure tier: repository preservation
Owning wave: Track-3 / Wave-3

## Final Product Decision

Mknoon intentionally has no received-media reporting body, backend, gateway,
queue, receipt, or UI. Announcement reporting is not waiting for external
provisioning. It is not part of the product model, so Plan 246 is closed as
accepted/not-applicable.

The supported user-control model is:

- QR scanning admits a peer to the user's direct contact Circle after signed
  payload validation and sends the recipient-bound contact request. It does
  not join, approve, or confine announcement content.
- Direct/contact Block and Unblock remain explicit local choices. They do not
  constitute moderation and do not suppress messages/media from an existing
  member of a shared group or announcement.
- Group and announcement membership is separately user-controlled through
  explicit invite Accept/Decline. Once joined, Mute suppresses local
  notifications but still persists messages; Leave exits the group/topic,
  subject to the last-admin invariant.

This decision supersedes the earlier proposal for a future Trust & Safety
authority and durable report outbox. There is no external-provisioning blocker
and no future implementation step implied by this plan.

## Source And Counterexample Audit

Graphify review anchored the announcement action policy, QR/contact flow,
Block/Unblock controls, group invite path, and group message listener. Current
source establishes:

- `GroupReceivedMediaAction` contains only `save`, `share`, `deleteForMe`,
  `info`, and `reply` at
  `lib/features/groups/application/group_received_media_action_policy.dart:11`.
- Announcement policy exposes exactly Save, Share, Delete for me, and Info for
  both members and admins; Reply remains absent even when an admin can write.
- Message overlays and typed viewers derive actions from that policy at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5532-5567`
  and
  `lib/features/groups/presentation/screens/group_conversation_screen.dart:1160-1205`.
- QR contact admission is implemented at
  `lib/features/qr_code/application/handle_scanned_qr_use_case.dart:26-32,68-138`.
- Blocked peers cannot be auto-added by a later contact request at
  `lib/features/contact_request/application/handle_incoming_message_use_case.dart:449-475`.
- Contact Block is enforced by direct/contact paths and group-invite
  authorization, but `GroupMessageListener` has no `ContactRepository` and
  `handleIncomingGroupMessage` has no contact/block input or `isBlocked` gate.
  `ML-016` proves a non-contact roster member's message persists, while
  announcement delivery is separately roster/admin-authorized at
  `handle_incoming_group_message_use_case.dart:455-474`. Block must not be
  described as sender-level announcement filtering.
- Pending group invitations expose Accept/Decline at
  `lib/features/groups/presentation/widgets/pending_group_invite_card.dart:158-201`.
- Mute is installation-local at
  `lib/features/groups/application/set_group_muted_use_case.dart:6-45`; tests
  prove muted announcements persist while notification-silent.
- Leave exits the group topic and removes local membership/key/group state at
  `lib/features/groups/application/leave_group_use_case.dart:8-68`, while the
  sole-admin guard prevents an invalid last-admin exit.

Product-policy correction: QR/contact trust and Block are not a reporting or
moderation authority. They cannot be cited as protection from content sent by
an already-authorized announcement member. The applicable announcement controls
are Accept/Decline, notification-only Mute, and Leave.

## Scope Contract And Guard

Must preserve:

- ordinary incoming announcement image/video actions: Save, Share, Delete for
  me, and Info;
- identical announcement media capabilities for members and admins;
- no Reply leak from admin write authority;
- Plan 242 protected/private-media egress denial and redaction;
- source announcement reader no-publish authorization; and
- QR/contact, invite Accept/Decline, Block/Unblock, Mute, and Leave behavior as
  independently owned controls.

Must remain absent:

- Report action/copy, reason or consent flow, reporting status, moderation
  notification, or dashboard;
- reporting gateway/service/endpoint/Go command/relay route;
- report request/evidence model, upload, queue, retry, idempotency, receipt,
  retention policy, audit fixture, or database migration; and
- any relabeling of Block, Delete, Mute, Leave, Share, telemetry, messaging, or
  announcement publication as reporting.

No production, schema, platform, localization, Go, relay, or device change is
authorized by this closure.

## Causal Test Contract

| Case | Preserved behavior | Existing causal proof |
|---|---|---|
| TC-246-01 | Announcement member/admin media exposes exactly Save/Share/Delete for me/Info, no Reply or Report capability | `group_received_media_action_policy_test.dart::GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty` |
| TC-246-02 | Wired announcement message and viewer surfaces preserve the same exact four actions and emit no source transport command | `group_conversation_wired_test.dart::GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded` |
| TC-246-03 | QR-originated contact admission converges once; a blocked peer is not auto-added again | `contact_request_one_scan_mutual_test.dart::B fresh auto-adds A and reciprocates; A no loop; one row each` plus `handle_incoming_message_use_case_test.dart::blocked peer is NOT auto-added` |
| TC-246-04 | Announcement controls remain explicit and accurately scoped: invitation Accept/Decline, notification-only Mute, and Leave with last-admin guard | `group_list_wired_test.dart::accepting a pending invite joins the group and removes the row`, `::declining optimistically hides the row but keeps the invite until the undo window elapses`, `group_message_listener_test.dart::muted and actively viewed announcements stay notification-silent`, and `leave_group_use_case_test.dart::blocks sole admin from leaving` |
| TC-246-05 | Announcement readers still cannot publish | `group_conversation_wired_test.dart::non-admin in announcement group cannot write` and Go `TestIsAllowedWriter_AnnouncementMemberBlocked` |
| TC-246-06 | No reporting production path or gateway/config/result contract exists | structural production-root absence commands below |

No new test is needed: the relevant absence, exact-action, trust-admission,
blocked-peer, invitation, mute, leave, and authorization behaviors already have
causal coverage. A test-authored report gateway would contradict the product
decision.

## Acceptance Commands

```bash
# Intentional production absence.
if rg --files lib android ios go-mknoon go-relay-server | \
  rg -i '(^|/)(received_media_report|group_media_report|announcement_media_report|reporting_authority|reporting_gateway|safety_gateway)'; \
then exit 1; else echo PASS; fi

if rg -n -i 'class[[:space:]]+[A-Za-z0-9_]*(ReportingAuthority|ReportingGateway|MediaReportGateway)|REPORTING_FIXTURE_URL|consentedMediaV1|metadataOnlyV1|Report received by|reporting is unavailable right now' \
  lib android ios go-mknoon go-relay-server; then exit 1; else echo PASS; fi

# Exact announcement action and trust/control sentinels.
flutter test test/features/groups/application/group_received_media_action_policy_test.dart \
  --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'
flutter test test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart \
  --plain-name 'B fresh auto-adds A and reciprocates; A no loop; one row each'
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart \
  --plain-name 'blocked peer is NOT auto-added'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'accepting a pending invite joins the group and removes the row'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'declining optimistically hides the row but keeps the invite until the undo window elapses'
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  --plain-name 'ML-016 incoming member message falls back to group member label when sender username is empty'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'muted and actively viewed announcements stay notification-silent'
flutter test test/features/groups/application/leave_group_use_case_test.dart \
  --plain-name 'blocks sole admin from leaving'

# Announcement publication preservation.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'non-admin in announcement group cannot write'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Documentation/analyzer hygiene for the docs-only closure.
git diff --check
```

Per the root coordination contract, focused Flutter/Go commands run only in the
serialized test slot. No full `host-all` and no Graphify refresh are required
for this documentation-only product disposition.

## Acceptance Evidence And Done Criteria

- [x] Product decision is explicit: Report is intentionally absent, not pending
  external provisioning.
- [x] No reporting backend, gateway, queue, receipt, migration, or UI exists.
- [x] Ordinary announcement received-media actions remain independently
  available under their existing policy.
- [x] QR/contact Block semantics are bounded to source truth and are not
  mislabeled as announcement moderation.
- [x] Accept/Decline, notification-only Mute, and Leave are recorded as the
  actual group/announcement user controls.
- [x] Existing causal tests cover the closure; no fake reporting surface was
  added.
- [x] The latest repository-wide host census (run during Track-2/Wave-2)
  passed `1151/1151` commands: `1143` Flutter files (`11502` tests passed, `1`
  skipped) and `8/8` Go legs. This is regression evidence, not Track-2 ownership
  of Plan 246.
- [x] Focused exact sentinels passed in the serialized slot: `10/10` Flutter
  invocations/cases and `2/2` named Go cases. Both reporting-absence scans and
  global diff hygiene also passed.
- [x] Scoped documentation diff/hygiene checks are clean.

## Device/Relay Proof Profile

N/A. There is no reporting native, relay, credential, or external-service
boundary by product decision. Existing Android private-media proof and
announcement authorization coverage retain their own plan closures; neither is
reporting evidence.

## Reopen Rule

Reopen Plan 246 only after an explicit product decision changes the non-goal and
authorizes a real reporting organization plus user-visible reporting semantics.
A newly available endpoint, vendor, fixture, or credential is not sufficient.
