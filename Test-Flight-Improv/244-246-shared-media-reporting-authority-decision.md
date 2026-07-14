# 244-246 - Shared Media Reporting Product Decision

Date: 2026-07-13
Status: accepted / intentionally not applicable
Scope: Plans 244, 245, and 246
Production behavior: no reporting body, backend, gateway, queue, receipt, or Report UI exists or is planned

## Decision

Received-media reporting is intentionally not a Mknoon product capability.
People enter a user's contact Circle through the QR contact flow. The user then
controls that direct/contact relationship through QR/contact admission plus
explicit Block and Unblock. Group and announcement participation has its own
explicit invite Accept/Decline, notification Mute, and Leave controls. Mknoon
does not operate a moderation body, human-review queue, automated content
moderation service, centralized ban list, or third-party Trust & Safety
integration.

This product decision supersedes the earlier conditional design for a future
signed reporting authority. The missing authority is not a provisioning
blocker: it is intentional absence. Plans 244-246 are therefore closed as
accepted/not-applicable, not deferred for a backend to appear.

## User-Control Model

The supported user-control boundary is deliberately local and
relationship-based; it is not a content-safety guarantee:

- Scanning a valid signed QR payload adds the scanned peer to the user's direct
  contact Circle and sends a recipient-bound contact request. The one-scan
  mutual flow converges to one contact row per peer. A QR scan does not join,
  approve, or confine content in a group or announcement.
- A recipient-bound request may auto-add only when it is new, verified, and not
  previously declined or blocked. A blocked contact cannot be resurrected by a
  later contact request.
- Block and Unblock are explicit user actions. Block persists on the contact
  record and is enforced by direct chat/reaction receive paths, contact-request
  admission, group-invite authorization, and other contact-scoped features;
  Unblock is separately user-controlled.
- Contact Block is not group or announcement moderation. The current group
  message receive path does not consult contact block state, so blocking an
  existing member does not suppress that member's already-authorized group or
  announcement messages/media.
- Group and announcement invitations expose explicit Accept and Decline
  controls. Once joined, Mute is an installation-local notification preference:
  messages still persist. Leave exits the group/topic and removes local group
  membership data, subject to the existing last-admin invariant.
- Delete for me, Save, Share, Info, Reply where authorized, Forward where
  authorized, and private-media lifecycle actions remain independent local
  capabilities. None of them is a substitute for reporting.

Source anchors:

- `lib/features/qr_code/application/handle_scanned_qr_use_case.dart:26-32,68-138`
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart:449-475`
- `lib/features/contacts/domain/models/contact_model.dart:1-47,97-138`
- `lib/features/contacts/application/block_contact_use_case.dart:4-30`
- `lib/features/contacts/application/unblock_contact_use_case.dart:4-30`
- `lib/features/orbit/presentation/screens/orbit_wired.dart:2274-2315`
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart:13-22,42-58,158-201`
- `lib/features/groups/application/set_group_muted_use_case.dart:6-45`
- `lib/features/groups/application/leave_group_use_case.dart:8-68`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart:25-55`
- `lib/features/groups/application/group_message_listener.dart:118-230` (its
  state and constructor contain no `ContactRepository`/block dependency)
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart:179-216`
  (`ML-016` persists a non-contact member delivery)
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart:455-474`
  (announcement delivery is roster/admin-authorized)

## Reporting Non-Goal

The repository must not add any of the following under Plans 244-246:

- a reporting authority, moderation service, safety gateway, HTTP/relay/Go
  reporting command, or third-party reporting destination;
- a report request or evidence schema, media upload, durable outbox, retry job,
  idempotency key, receipt, retention promise, or audit fixture;
- a Report action, reason/consent sheet, queued/accepted/rejected reporting
  state, success copy, reporting notification, or moderation dashboard;
- an automatic Block, Delete, Mute, membership change, or source-message
  publication disguised as reporting; or
- analytics, diagnostic telemetry, email, OS sharing, peer messaging, group
  publication, or local deletion relabeled as a report.

There is no reporting-specific database migration, native capability, device
proof, external credential, or rollout gate. Device testing is N/A because no
reporting boundary exists by design.

## Received-Media Preservation Contract

The intentional absence of Report must not remove or weaken ordinary actions:

- direct received media retains Save, Share, Reply, Info, and Delete for me
  under the existing current-row and private-media policy;
- discussion received media retains Save, Share, Delete for me, Info, and Reply
  when currently authorized;
- announcement received media retains exactly Save, Share, Delete for me, and
  Info for both members and admins, with no Reply capability leaked by admin
  write authority;
- protected, expired, missing, corrupt, wrong-lane, outgoing, and non-visual
  media continue to fail closed under their existing policies; and
- announcement readers remain unable to publish to the source announcement.

The current production action boundary is explicit:

- `lib/features/conversation/application/received_media_action_controller.dart`
  has no reporting dependency.
- `lib/features/groups/application/group_received_media_action_policy.dart:11`
  defines only `save`, `share`, `deleteForMe`, `info`, and `reply`.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart:5532-5567`
  derives viewer actions only from that typed capability set.

## Repository And Privacy Consistency

Targeted production-root inventory on 2026-07-13 found no reporting
implementation path and no reporting gateway/configuration/result contract.
The privacy inventory independently states:

- no automated or human content moderation;
- no user-report mechanism;
- no third-party Trust & Safety vendor; and
- no server-side banning, while local contact blocking remains available for
  the direct/contact-scoped paths that consult it.

See `Privacy-Policy/Questions.md:1006-1012`.

## Acceptance Evidence

Existing causal coverage is sufficient; no reporting-specific test or fake is
needed:

- `conversation_received_media_actions_test.dart` explicitly asserts that the
  direct media overlay exposes its ordinary actions and no Report key or copy.
- `group_received_media_action_policy_test.dart` pins exact discussion and
  announcement capability sets.
- `group_conversation_wired_test.dart` pins announcement member/admin message
  and viewer action parity plus source-transport silence.
- `contact_request_one_scan_mutual_test.dart` pins QR-originated one-scan mutual
  contact convergence.
- `handle_incoming_message_use_case_test.dart` pins that a blocked peer is not
  auto-added.
- Block/Unblock application, repository, and Orbit swipe-control tests pin the
  explicit local user controls.

The Track-2/Wave-2 full host census passed `1151/1151` commands: all `1143`
Flutter test-file commands (`11502` tests passed, `1` skipped) and all `8` Go
legs, with zero failures. Focused exact sentinels are recorded in the canonical
lane plans and the reporting closure artifact.

## Closure And Reopen Rule

- Shared product decision: accepted.
- Track-2 Plans 244 and 245: accepted / intentionally not applicable.
- Plan 246: the same accepted/intentionally-not-applicable product disposition,
  recorded for its owning Track-3/Wave-3 closure rather than counted in Track-2.
- Production, schema, Go, relay, platform, localization, and test changes for
  reporting: none.
- External provisioning blocker: none.
- Report capability: intentionally absent.

Reopen this decision only if the user explicitly changes the product model to
add a reporting organization and user-visible reporting capability. The mere
availability of a service, vendor, endpoint, or test fixture is not a reopen
condition and does not authorize implementation.
