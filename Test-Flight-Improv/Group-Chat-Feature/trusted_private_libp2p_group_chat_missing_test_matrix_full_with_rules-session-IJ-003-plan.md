# IJ-003 Invite Revocation And Revoked-Accept Failure Plan

Status: execution-ready

Session classification: `implementation-ready / needs_code_and_tests`

Planning verdict: IJ-003 is a row-owned implementation-committed gap. It must not close as doc-only, evidence-only, or acceptance-only while sender-side signed revocation delivery, receiver-side revocation handling, and 3-party direct plus mailbox proof are missing.

## Evidence Used

- Source row: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` marks IJ-003 Open: revoked invites must be removed from pending surfaces and cannot be accepted even if replayed later.
- Inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` marks IJ-003 Partial. Existing coverage is migration 055, local revocation tombstones, delayed invite rejection when a tombstone already exists, and revoked pending accept failure.
- Breakdown ledger: IJ-003 is `needs_code_and_tests`, `implementation-ready`, with this plan path.
- Current code evidence:
  - `revoke_pending_group_invite_use_case.dart` only revokes a locally pending row and writes a local `GroupInviteRevocation`; it does not send revocation to the invitee.
  - `send_group_invite_use_case.dart` has signed encrypted invite send with direct/inbox fallback; there is no equivalent revocation sender API.
  - `handle_incoming_group_invite_use_case.dart` and `accept_pending_group_invite_use_case.dart` already check active revocation tombstones before pending store or accept side effects.
  - `group_invite_listener.dart` only stores incoming invites; it has no revocation branch.
  - `incoming_message_router.dart` routes `group_invite`, not a revocation type.
  - `group_invite_auth.dart` and IJ-002 invite signing provide the local pattern for trusted-contact signature verification and self-contained authorization.
- Prior accepted sessions to preserve: GL-005, LP-002, LP-003, LP-013, IJ-001, IJ-002.

## Real Scope

Implement only trusted-private invite revocation delivery and revoked-accept failure:

- Add a signed encrypted invite-revocation payload for a known `inviteId`, `groupId`, and recipient.
- Add sender-side revocation delivery with direct `sendMessage` and `storeInInbox` fallback.
- Add receiver-side revocation handling that verifies the signer, stores an active tombstone, removes the matching pending invite, and refreshes pending surfaces.
- Prove delayed direct and mailbox copies of the original invite cannot recreate pending state or materialize group/key/join state after revocation.

## Closure Bar

IJ-003 is complete only when:

- Authorized revoker sends a signed encrypted revocation to the intended invitee via direct and inbox fallback.
- Receiver verifies revocation signature with the trusted contact public key and checks a self-contained revoker authorization snapshot before any tombstone or pending-row mutation.
- Cleartext revocation envelope does not expose group keys, member lists, peer addresses, invite policy, or message/history content. Cleartext may contain only routing metadata needed for dispatch, such as type/version, sender peer id, invite id, and encrypted block metadata.
- Invalid, unsigned, tampered, wrong-recipient, unknown/blocked sender, unauthorized, or removed-revoker revocations fail closed without deleting pending invites or storing tombstones.
- Valid revocation stores/updates `GroupInviteRevocation`, removes the matching pending invite, and creates no group row, member rows, key row, `group:join`, consumed marker, inbox drain, or join timeline.
- Delayed original invite copies through direct and mailbox paths are ignored after revocation and cannot be accepted.
- IJ-001 encrypted-only policy behavior and IJ-002 signed invite attestation remain green.
- Before acceptance, the IJ-003 source matrix row and `test-inventory.md` IJ-003 row are updated to Covered/Closed with concrete production files, test names, command evidence, and any real-network nightly caveat. This plan file is the only doc edited during planning.

## Implementation Steps

1. Add `GroupInviteRevocationPayload`, preferably at `lib/features/groups/domain/models/group_invite_revocation_payload.dart`.
   - Use top-level type `group_invite_revocation`, versioned encrypted envelope, and encrypted plaintext for revocation-critical fields only.
   - Include schema version, invite id, group id, recipient peer id, revoked-by peer id, revoked-at, expires-at, minimal revoker authorization snapshot, and signature envelope.
   - Reuse `canonicalizeGroupEventLogPayload` for signed payload canonicalization.

2. Add revocation auth helper next to `group_invite_auth.dart`.
   - Verify with `callVerifyPayload` using the trusted contact public key for `revokedByPeerId`.
   - Require the signed authorization snapshot to bind revoker peer id to the same trusted key and allow `GroupMemberPermission.inviteMembers`.
   - Fail closed for malformed timestamps, expired revocation, wrong recipient, missing/unsupported signature, canonical mismatch, unknown/blocked contact, empty trusted key, unauthorized role, or removed/missing revoker.

3. Add `sendGroupInviteRevocation` in `revoke_pending_group_invite_use_case.dart`.
   - Inputs: `p2pService`, `bridge`, invite id, group id, recipient peer/key, sender peer/public/private key, sender username, group config or minimal auth snapshot, and optional `now`.
   - Validate node/key/id/signing/auth before encryption or delivery.
   - Sign before encryption; if signing/encryption fails, return an invalid/send-failed result before direct or inbox delivery.
   - Use direct send first and inbox fallback, mirroring `sendGroupInvite`.

4. Add receiver handler, likely near `handle_incoming_group_invite_use_case.dart`.
   - Parse/decrypt only revocation envelopes.
   - Validate transport sender, recipient binding, signature, and authorization.
   - Save `GroupInviteRevocation(inviteId, groupId, revokedAt, expiresAt, revokedBy)`.
   - Delete the pending invite only when the current pending row for `groupId` has the same `inviteId`.
   - If no pending row exists, still save the tombstone so later original invite copies are blocked.

5. Wire routing and surface refresh narrowly.
   - Route `group_invite_revocation` through `IncomingMessageRouter` to invite handling, or add a separate stream only if implementation evidence requires it.
   - In `GroupInviteListener`, detect revocation before normal invite storage, call the revocation handler, and emit the existing pending-invite reload signal when pending state changed.
   - Do not redesign pending-invite UI; `GroupListWired` and `OrbitWired` already reload from repositories on pending invite stream events.

6. After code/test acceptance, update closure docs.
   - Update only the IJ-003 source matrix row, `test-inventory.md` IJ-003 row, and breakdown ledger closure evidence as required by the pipeline.

## RED Tests First

Add tests first, then run this before production implementation:

```bash
flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart
```

Expected RED: fails because revocation payload, sender API, router/listener handling, and 3-party direct plus mailbox proof do not exist.

Required tests:

- Payload test: signed/canonical/encrypted revocation parsing, tamper rejection, recipient binding, expiry, and privacy-safe cleartext envelope.
- Sender test: sign-before-encrypt, direct success, inbox fallback, node/key/sign/encrypt failure, and no cleartext sensitive fields.
- Listener/receiver test: valid revocation removes pending and stores tombstone; invalid revocation leaves pending unchanged.
- Store/accept tests: delayed direct/mailbox invite copies after revocation do not recreate pending/group state; revoked accept creates no consumed marker or join timeline.
- Router test: `group_invite_revocation` dispatches to the chosen revocation path.
- Integration test: A/B/C fake-network flow proving C pending invite is revoked, delayed direct and mailbox invite copies are ignored, and accept cannot join.

## Green Gates

Run after implementation:

```bash
dart format --output=none --set-exit-if-changed lib/features/groups/application/revoke_pending_group_invite_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/group_invite_listener.dart lib/features/groups/application/group_invite_auth.dart lib/features/groups/domain/models/group_invite_revocation_payload.dart lib/features/groups/domain/models/group_invite_revocation.dart lib/core/services/incoming_message_router.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart
flutter test --no-pub test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
flutter test --no-pub test/features/groups/application/*invite*_test.dart
flutter test --no-pub test/core/services/incoming_message_router_test.dart
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
./scripts/run_test_gates.sh groups
flutter test --no-pub test/features/groups/integration
git diff --check
```

Supporting only when env is configured:

```bash
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

If env is unset, record real-network nightly as unconfigured supporting evidence, not as blocking failure or green proof.

## Scope Guard

Do not implement:

- IJ-005 replay/reuse semantics beyond revocation tombstones.
- IJ-009 auto-join.
- IJ-010 concurrent join/revoke arbitration beyond deterministic tombstone rejection.
- IJ-013 account/device registry or richer device eligibility.
- EK-004 broad event-family signature parity.
- Sent-invite persistence, revoke/list UI, group invite management API, or a generic invite-management system.
- New durable membership-history/index infrastructure unless implementation proves IJ-003 is prerequisite-blocked without it.

Do not expose group keys, member lists, peer addresses, invite policy, revocation signatures, or history/message content in cleartext revocation envelopes.

## Known-Failure Interpretation

- RED failures from missing revocation model/API/router/listener/proof are expected IJ-003 evidence.
- Post-implementation, direct IJ-003 tests, invite wildcard, router test, `invite_round_trip_test.dart`, `group_new_member_onboarding_test.dart`, `./scripts/run_test_gates.sh groups`, and `git diff --check` must pass before closure.
- If full groups integration has unrelated pre-existing dirty-worktree failures, rerun focused failed files and classify explicitly. IJ-003 cannot close unless row-specific tests and the named groups gate are green or the controller explicitly accepts the unrelated gate failure.

## Residual Non-Goals

- Durable sent-invite discovery/listing remains future API work.
- Cross-device revocation propagation beyond the addressed recipient remains IJ-013/device-scope work.
- Invite replay/reuse policy remains IJ-005.
- User-facing distinct error taxonomy remains EC-001.
- TP-SMOKE-01 may depend on IJ-003 later, but IJ-003 alone does not close the smoke scenario.

## Execution Progress

- 2026-05-01 02:55:34 CEST - Controller: extracted IJ-003 contract from this plan and `Test-Flight-Improv/test-gate-definitions.md`; scope is signed encrypted invite revocation delivery, receiver tombstone handling, router/listener dispatch, and revoked delayed direct/mailbox invite rejection. Next: spawn Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-05-01 02:56:53 CEST - Executor: contract extracted before coding. Exact scope is signed-before-encrypted `group_invite_revocation` payload/auth, sender direct delivery with inbox fallback, receiver tombstone plus pending-row deletion, router/listener dispatch with pending-surface refresh, and delayed direct/mailbox invite rejection after revocation. Closure requires fail-closed validation for invalid signer/recipient/auth/tamper/expiry cases, privacy-safe cleartext envelopes preserving IJ-001/IJ-002, no group/member/key/join/consumed side effects from revocation, RED-first tests and the named green gates in this plan. Scope guard excludes IJ-005/IJ-009/IJ-010/IJ-013/EK-004, sent-invite persistence/UI/API, and generic invite-management redesign. Next: inspect current invite seams and add missing RED tests.
- 2026-05-01 03:03:16 CEST - Executor RED: added IJ-003 regression coverage in `test/features/groups/domain/models/group_invite_revocation_payload_test.dart`, `test/features/groups/application/revoke_pending_group_invite_use_case_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/application/store_pending_group_invite_use_case_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/core/services/incoming_message_router_test.dart`, and `test/features/groups/integration/invite_round_trip_test.dart`. Ran `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart`; outcome RED as expected: missing `lib/features/groups/domain/models/group_invite_revocation_payload.dart`, missing `sendGroupInviteRevocation` / `SendGroupInviteRevocationResult`, and `group_invite_revocation` still routed to unknown instead of the invite listener path. Next: implement payload/auth/sender/receiver/listener/router.
- 2026-05-01 03:10:53 CEST - Executor implementation: added `GroupInviteRevocationPayload` and revocation signature parsing/encryption helpers, revocation authorization helpers in `group_invite_auth.dart`, sender-side `sendGroupInviteRevocation` direct delivery with inbox fallback, receiver-side `handleIncomingGroupInviteRevocation` tombstone handling and pending-row deletion, listener revocation dispatch with pending refresh, and `group_invite_revocation` router dispatch through the group invite stream. The receiver path verifies trusted signer/auth snapshot, recipient binding, expiry, and transport sender before mutating state; valid revocation stores only a tombstone and removes a matching pending invite without group/member/key/join/consumed side effects.
- 2026-05-01 03:10:53 CEST - Executor fast structural validation: `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/core/services/incoming_message_router_test.dart` passed.
- 2026-05-01 03:10:53 CEST - Executor green evidence: `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart` passed.
- 2026-05-01 03:10:53 CEST - Executor green evidence: `dart format --output=none --set-exit-if-changed lib/features/groups/application/revoke_pending_group_invite_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/group_invite_listener.dart lib/features/groups/application/group_invite_auth.dart lib/features/groups/domain/models/group_invite_revocation_payload.dart lib/features/groups/domain/models/group_invite_revocation.dart lib/core/services/incoming_message_router.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart` passed after formatting the touched files.
- 2026-05-01 03:10:53 CEST - Executor green evidence: `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart` passed; `flutter test --no-pub test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` passed; `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed.
- 2026-05-01 03:10:53 CEST - Executor green evidence: `flutter test --no-pub test/core/services/incoming_message_router_test.dart` passed; `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed; `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed; `./scripts/run_test_gates.sh groups` passed; `flutter test --no-pub test/features/groups/integration` passed; `git diff --check` passed.
- 2026-05-01 03:10:53 CEST - Executor supporting gate note: `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` were unset, so `group-real-network-nightly` was not run and is recorded as supporting-only/unconfigured, not blocking.
- 2026-05-01 03:10:53 CEST - Executor summary: IJ-003 implementation and focused proof are complete for the Executor role. Tests added/updated cover signed canonical encrypted revocation payload privacy/tamper/binding/expiry, sender sign-before-encrypt direct and inbox fallback plus failure cases, listener receiver tombstone and invalid-signature fail-closed handling, delayed direct/mailbox invite rejection after revocation, revoked accept no-side-effect behavior, router dispatch, and integration-level revoked invite replay rejection.
- 2026-05-01 03:15:57 CEST - QA Reviewer completed: verdict `accepted`, blocking issues `none`. QA inspected the IJ-003 diff and plan evidence, confirmed RED-first evidence and recorded green gates, verified the forbidden source matrix/inventory/breakdown docs remain dirty only from prior IJ-001/IJ-002 closure work with IJ-003 still open there, and reran focused smoke gates: `flutter test --no-pub test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/revoke_pending_group_invite_use_case_test.dart test/features/groups/application/group_invite_listener_test.dart test/core/services/incoming_message_router_test.dart test/features/groups/integration/invite_round_trip_test.dart` passed with 50 tests; `flutter test --no-pub test/features/groups/application/store_pending_group_invite_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/domain/models/group_invite_payload_test.dart` passed with 40 tests; `git diff --check` passed.
- 2026-05-01 03:15:57 CEST - Final execution verdict: `accepted`. IJ-003 code/tests prove signed encrypted invite revocation delivery, trusted receiver tombstone handling, router/listener dispatch, delayed direct/mailbox invite rejection after revocation, and revoked accept failure without pending/group/key/join/consumed side effects. Residual closure caveats: `group-real-network-nightly` remains supporting-only/unconfigured while `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset; closure must update the source matrix, inventory, and session breakdown later.

## Final Execution Verdict

Verdict: `accepted`

Blocking issues: none

Residual caveats for closure: `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset, and the source matrix/inventory/session-breakdown docs still need the dedicated closure-writer update.

## Reviewer And Arbiter

Reviewer sufficiency: sufficient as-is for implementation. The plan has repo evidence, RED-first tests, narrow implementation steps, exact gates, closure-doc requirements, and explicit non-goals.

Arbiter decision: no structural blockers remain. Incremental implementation details such as exact helper names and whether routing uses the existing invite stream or a new revocation stream can be decided during execution as long as the tests prove the same behavior.
