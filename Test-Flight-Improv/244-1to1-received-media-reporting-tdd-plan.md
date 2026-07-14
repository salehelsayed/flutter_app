# 244 - 1:1 Received Media Reporting

Status: accepted / intentionally not applicable
Type: Product disposition and preservation closure
Spec: direct received-media Report is intentionally absent; preserve direct actions and contact-level user controls
Classification: product non-goal
Closure tier: repository preservation

## Final Product Decision

Mknoon intentionally has no received-media reporting organization, backend,
gateway, queue, receipt, or UI. Direct-media reporting is not waiting for an
external authority. Plan 244 is closed as accepted/not-applicable.

The supported direct-lane user-control model is QR/contact based:

- scanning a valid signed QR payload adds the peer to the user's contact Circle
  and sends the recipient-bound contact request;
- a new verified recipient-bound request can complete the mutual contact flow;
- a previously declined or blocked peer cannot be silently resurrected; and
- Block and Unblock are explicit local user choices enforced by the direct chat
  and reaction receive paths and other contact-scoped features.

Block, Delete for me, Save, Share, Reply, and Info are independent user actions.
None is a content report or a promise of review by Mknoon.

## Current Source Truth

- `lib/features/qr_code/application/handle_scanned_qr_use_case.dart:26-32,68-138`
  validates the QR, adds the contact, and sends the request.
- `lib/features/contact_request/application/handle_incoming_message_use_case.dart:449-475`
  restricts one-scan auto-add to new verified v2 requests and guards blocked or
  declined peers.
- `lib/features/conversation/application/chat_message_listener.dart:445-456`
  and
  `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:763`
  enforce direct blocked-sender denial.
- `lib/features/contacts/application/block_contact_use_case.dart` and
  `unblock_contact_use_case.dart` persist the user's explicit choice through the
  contact repository.
- `lib/features/conversation/application/received_media_action_controller.dart:15-25`
  explicitly owns current-row Save/Share egress and has no reporting dependency.
- The direct media overlay preservation test explicitly asserts that no Report
  key or Report copy exists.

## Scope Contract

Must preserve:

- direct received-media Save, Share, Reply, Info, and Delete for me under their
  existing eligibility and private-media rules;
- exact attachment identity reload before irreversible egress;
- explicit QR admission and Block/Unblock behavior; and
- zero reporting side effects on messages, media, contacts, exports, or
  transport.

Must remain absent:

- Report action/copy, reason/consent/status UI, moderation notification, or
  dashboard;
- reporting gateway/service/endpoint, request/evidence schema, upload, queue,
  retry, idempotency, receipt, retention policy, or audit fixture; and
- any analytics, Block, Delete, Share, email, or direct message relabeled as a
  report.

No production, schema, native, localization, Go, relay, device, or
reporting-specific test implementation is required or authorized.

## Causal Test Contract

| Case | Preserved behavior | Existing proof |
|---|---|---|
| TC-244-01 | Direct attachment long-press exposes the ordinary actions and no Report key/copy | `conversation_received_media_actions_test.dart::attachment long press exposes direct media actions without replacing row context` |
| TC-244-02 | QR admission completes one mutual contact relationship without a reciprocal loop | `contact_request_one_scan_mutual_test.dart::B fresh auto-adds A and reciprocates; A no loop; one row each` |
| TC-244-03 | A blocked peer is not auto-added and direct incoming messages/reactions remain denied | `handle_incoming_message_use_case_test.dart::blocked peer is NOT auto-added`, `chat_message_listener_test.dart::returns blockedSender for blocked contacts before persistence`, and `reaction_listener_test.dart::rejects blocked senders` |
| TC-244-04 | Block/Unblock remain explicit repository-backed user choices | `block_contact_use_case_test.dart`, `unblock_contact_use_case_test.dart`, repository projection tests, and Orbit/Conversation controls |
| TC-244-05 | No reporting production path or gateway/config/result contract exists | shared structural absence commands |

Existing tests are sufficient. Adding a fake gateway, report model, or Report UI
test would contradict the accepted product decision.

## Acceptance Commands

```bash
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'attachment long press exposes direct media actions without replacing row context'
flutter test test/features/contact_request/integration/contact_request_one_scan_mutual_test.dart \
  --plain-name 'B fresh auto-adds A and reciprocates; A no loop; one row each'
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart \
  --plain-name 'blocked peer is NOT auto-added'
flutter test test/features/conversation/application/chat_message_listener_test.dart \
  --plain-name 'returns blockedSender for blocked contacts before persistence'
flutter test test/features/conversation/application/reaction_listener_test.dart \
  --plain-name 'rejects blocked senders'
flutter test test/features/contacts/application/block_contact_use_case_test.dart
flutter test test/features/contacts/application/unblock_contact_use_case_test.dart

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
- [x] Direct ordinary media actions and private-media policy remain unchanged.
- [x] QR admission and direct/contact Block semantics are source-verified.
- [x] No reporting backend, gateway, outbox, receipt, migration, or UI exists.
- [x] Existing causal tests cover the accepted absence; no report fake was
  authored.
- [x] Track-2/Wave-2 full host census passed `1151/1151` commands: `1143`
  Flutter files (`11502` tests passed, `1` skipped) and `8/8` Go legs.
- [x] Focused exact sentinels passed in the serialized slot: `7/7` Flutter
  invocations and `9/9` cases.
- [x] Scoped documentation diff/hygiene checks are clean.

## Device/Relay Proof Profile

N/A. Reporting has no native, relay, credential, or external-service boundary
by product decision.

## Reopen Rule

Reopen Plan 244 only after an explicit product decision authorizes a reporting
organization and user-visible reporting capability. External service
availability alone is not authorization.
