Status: qa_passed

# PREREQ-INVITER-FRESHNESS Plan

## Planning Progress

- 2026-05-01 23:02:28 CEST - Current role: Planner completed. Files inspected since last update: no new files beyond Evidence Collector pass. Decision/blocker: draft plan adds first-class invite membership freshness proof at send/parse/auth/storage/accept seams, with stale offline replay proof; no structural blocker identified in planner pass. Next action: run Reviewer pass.
- 2026-05-01 23:04:04 CEST - Current role: Reviewer started. Files inspected since last update: draft plan. Decision/blocker: reviewing sufficiency, scope width, stale assumptions, required tests/gates, and whether the plan overclaims current-membership authority. Next action: record reviewer findings and required adjustments.
- 2026-05-01 23:04:31 CEST - Current role: Reviewer completed. Files inspected since last update: draft plan only. Decision/blocker: sufficient with adjustments; add call-site tests for contact picker/create-group fanout, keep proof expiry out of raw parse-time validation, and frame the proof as stale/offline freshness rather than a global consensus oracle. Next action: run Arbiter pass.
- 2026-05-01 23:05:31 CEST - Current role: Arbiter started. Files inspected since last update: reviewer-adjusted plan. Decision/blocker: classifying reviewer findings as structural blockers, incremental details, or accepted differences. Next action: issue final arbiter decision and status.
- 2026-05-01 23:06:26 CEST - Current role: Arbiter completed. Files inspected since last update: reviewer-adjusted plan and final TTL clarification. Decision/blocker: `execution-ready`; no structural blocker remains. Next action: hand off to implementation/QA execution when requested.

## Run Mode

- Active mode: implementation-committed gap-closure.
- Reopened prerequisite: `PREREQ-INVITER-FRESHNESS`.
- Owned source row: EC-007 only.
- Current pipeline state: 47 Covered / 0 Open / 2 Partial after `PREREQ-REMOTE-EVENT-FAMILIES`.
- Non-owned remaining row: EK-004 stays separate signature-equivalence scope and must not move because of this session.
- Device/relay profile: host/fake-network proof is primary. The supplied iOS device and relay defaults can support `group-real-network-nightly` later, but this plan does not require external fixtures for primary closure.

## real scope

Implement the missing EC-007 invite freshness slice:

- Add a first-class invite membership freshness proof to signed group invites. The proof must bind the invite id, group id, recipient identity/device binding, inviter identity/device binding, key epoch, current group config state hash, current inviter member snapshot, local membership watermark/version, proof issue time, and proof expiry.
- Define a dedicated proof freshness TTL, initially `const groupInviteMembershipFreshnessTtl = Duration(hours: 24)`, next to the invite credential model. This must not replace or shorten the existing 7-day `pendingGroupInviteTtl`; it only governs whether the membership proof is still fresh enough to store or accept.
- Build that proof only after rechecking the inviter against current local group repository state, not only against the caller-supplied `groupConfig`.
- Include the proof inside `GroupInvitePayload.canonicalInviteSignedPayload()` so tampering with the proof invalidates the existing invite signature.
- Verify the proof in `verifyGroupInviteAttestation` after the trusted contact signature check and before any pending invite, group, key, join, tombstone, mailbox drain, notification, or acceptance side effect.
- Revalidate the same proof at accept time using the current clock, so a pending invite that was fresh when stored cannot be accepted after the proof becomes stale.
- Add direct and fake-network tests proving old self-consistent invites from an inviter who was later removed or demoted are rejected before durable state.

This session does not rework queued role updates, local `addGroupMember` permission rechecks, receive-side stale system mutation rejection, invite revocation, key-package replay, or complete event-family signature equivalence. Those are already covered or separately owned.

## closure bar

EC-007 can move to `Covered` only when:

- a valid current invite still stores and accepts through the listener/direct/accept paths
- `sendGroupInvite` cannot mint or deliver a proof from stale caller-supplied config when the inviter is no longer authorized in current `GroupRepository` state
- signed invite parsing rejects missing, malformed, tampered, mismatched, or expired freshness proof fields before side effects
- direct handle, listener pending-store, and pending accept all reject an old but internally self-consistent invite snapshot once its freshness proof is stale
- fake-network/offline replay proves B can queue or store an invite, then after A removes or demotes B and the invite becomes stale, C rejects the replay without pending/group/key/join/audit confusion
- valid remove-rotate-reinvite flows remain green with a fresh proof and rotated key epoch
- focused direct tests, `groups`, `completeness-check`, targeted analyzer over touched Dart files, and `git diff --check` pass or have exact unrelated caveats
- source matrix EC-007, `test-inventory.md`, this plan, and the breakdown ledger are updated only after implementation plus QA acceptance

## source of truth

- Primary source row: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, EC-007.
- Current prerequisite ledger: row 58 in `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Current evidence map: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, EC-007.
- Prior blocked row plan: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-EC-007-plan.md`.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; the script wins if they disagree.
- Current production code and focused tests beat stale prose.

## session classification

`implementation-ready`.

The remaining blocker is repo-owned missing production invite credential behavior plus tests. No external relay/device fixture is required for the primary proof.

## exact problem statement

EC-007 remains Partial because current invite auth proves only that the inviter was authorized inside the signed invite snapshot. A removed or demoted inviter can replay an old but internally valid signed invite snapshot to a new recipient, and the current receive/accept paths have no first-class freshness proof that the snapshot was minted from current local membership state or is still fresh enough to use.

User-visible behavior must improve by rejecting stale offline/replayed invites before they create pending invites, local group state, group keys, topic joins, join publications, mailbox drains, notifications, or audit confusion. Existing valid signed invite round trips, explicit revocation behavior, welcome/key-package validation, and rotated re-invite flows must stay unchanged except for carrying and verifying the new proof.

## files and repos to inspect next

Production/model files:

- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/signed_group_transition_audit.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`

Direct tests:

- `test/features/groups/domain/models/group_invite_payload_test.dart`
- `test/features/groups/application/send_group_invite_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- update `Test-Flight-Improv/test-gate-definitions.md` only if a new integration test file is added; prefer extending existing files to avoid widening gates

## existing tests covering this area

- `update_group_member_role_use_case_test.dart` proves queued role updates recheck current manage-role permission.
- `add_group_member_use_case_test.dart` proves queued add/invite-member actions recheck current invite permission.
- `group_message_listener_test.dart` proves demoted creators cannot apply receive-side member add/remove/role/metadata mutations.
- `handle_incoming_group_invite_use_case_test.dart` proves invalid signatures, tampered fields, non-admin snapshots, invite-disabled snapshots, and missing-inviter snapshots reject before group/key/join state.
- `group_invite_listener_test.dart` proves signature failures and unauthorized/removed signed snapshots are not stored as pending.
- `accept_pending_group_invite_use_case_test.dart` proves tampered persisted invites and non-admin/removed snapshots delete pending state and do not materialize groups.
- `invite_round_trip_test.dart` keeps valid signed invite round trips, revoked invite rejection, rotated re-invite, offline inbox fallback re-invite, multi-use duplicate safety, and concurrent accepts green.

Missing today: a stale old invite whose snapshot still says the inviter is authorized, whose signature is valid, and whose recipient/device binding is valid.

## regression/tests to add first

Add failing tests before production changes:

- `group_invite_payload_test.dart`: `PREREQ-INVITER-FRESHNESS requires signed membership freshness proof and rejects proof tampering`, covering missing proof, mismatched invite id/group id/recipient/key epoch, malformed proof, and group config state-hash mismatch. Expiry belongs in auth/receive/accept tests where a validation time is available.
- `send_group_invite_use_case_test.dart`: `PREREQ-INVITER-FRESHNESS refuses to sign invite from stale caller config after inviter removal or invite permission revocation`, proving the send path reads current `GroupRepository` state before proof/sign/encrypt/deliver.
- `create_group_with_members_use_case_test.dart` and `contact_picker_wired_test.dart`: focused `PREREQ-INVITER-FRESHNESS` preservation tests proving create/add-member invite fanout still emits signed `members_added` and sends per-recipient invites with proof fields.
- `handle_incoming_group_invite_use_case_test.dart`: `PREREQ-INVITER-FRESHNESS rejects stale self-consistent invite before group state or join`, proving direct handling returns `invalidPayload` with no group, member, key, or `group:join`.
- `group_invite_listener_test.dart`: `PREREQ-INVITER-FRESHNESS does not store stale self-consistent invite from removed inviter`, proving no pending row, pending stream event, notification, group, key, or join.
- `accept_pending_group_invite_use_case_test.dart`: `PREREQ-INVITER-FRESHNESS accept deletes stale self-consistent invite without state`, proving accept-time revalidation deletes pending and creates no consumed tombstone, group, member, key, join, mailbox drain, or join event.
- `invite_round_trip_test.dart`: `PREREQ-INVITER-FRESHNESS offline invite after inviter removal is rejected`, using existing fake P2P/bridge/repository patterns to deliver an old stored invite after removal/demotion and proof staleness.
- Positive preservation in `invite_round_trip_test.dart` or focused app tests: valid fresh invite and remove-rotate-reinvite still pass with proof fields present.

## step-by-step implementation plan

1. Add a compact `GroupInviteMembershipFreshnessProof` value object in or next to `group_invite_payload.dart`. Keep it JSON/canonicalization-only; do not add a database table. Add `groupInviteMembershipFreshnessTtl = Duration(hours: 24)` as the proof window unless implementation evidence shows a tighter local constant is already established.
2. Add fields to `GroupInvitePayload` for the proof, include it in `_toPayloadMap()`, `_toInviteSignedPayloadMap()`, parsing, `withInviteSignature`, and structural validation. Missing/malformed/mismatched proof should become a security/invalid payload failure for signed trusted-private invites; time-based staleness should be checked by auth/receive/accept code with an explicit validation time.
3. Add proof-building helpers that derive the current inviter member from `GroupRepository.getMember(groupId, senderPeerId)`, derive the current full group config/state hash from `buildGroupConfigPayload`, add/normalize the group config state hash when caller-supplied test configs omit it, use `GroupModel.lastMembershipEventAt` or the current config state hash as the membership watermark, bind recipient/device/key epoch/invite id, and set a short freshness expiry. Use existing canonical JSON/signature helpers rather than ad hoc string formats.
4. Update `sendGroupInvite` and `sendGroupInvitesInParallel` to require the current `GroupRepository` or a narrow proof-building dependency. The send path must reject if current repo state says the inviter is missing, invite-disabled, public-key mismatched, or no longer authorized, even if the passed `groupConfig` is stale.
5. Update `contact_picker_wired.dart` and `create_group_with_members_use_case.dart` call sites to pass the current repository/proof dependency after `addGroupMember`, config sync, and signed `members_added` publish. Preserve existing degraded invite result semantics.
6. Extend `verifyGroupInviteAttestation` to validate, after contact signature verification:
   - proof signature and canonical payload
   - proof binds to invite id, group id, sender, recipient/device, key epoch, group config state hash, and trusted inviter public key
   - proof issue time is compatible with the invite timestamp
   - proof expiry is after the supplied validation time
   - proof inviter member snapshot still grants `inviteMembers`
7. Pass explicit validation time through `_resolveIncomingGroupInvite`, `storeIncomingPendingGroupInvite`, `handleIncomingGroupInvite`, and `acceptPendingGroupInvite` so listener/direct receive uses message/received time and accept uses current `now`.
8. Ensure stale proof rejection happens before durable side effects. If a pending invite fails at accept time, delete the pending row but do not create consumed/package tombstones, group, members, keys, join events, inbox drain, or notifications.
9. Keep direct revocation, welcome/key-package tombstone, recipient identity binding, and existing signed-snapshot authorization behavior intact.
10. If proof fields require test fakes to decode/sign consistently, update `FakeBridge`, `PassthroughCryptoBridge`, or focused helper builders only to support the same payload-sign/verify command contracts already used by invite signatures.
11. Run focused tests and gates. After QA accepts, update EC-007 in the source matrix and inventory to `Covered`; update breakdown row 58 to accepted/qa_passed. Keep EK-004 `Partial`.

Stop if tests show that a truly authoritative current-membership source cannot be represented without a live external consensus/control-plane service. In that case, record the structural blocker instead of weakening the closure claim.

## risks and edge cases

- Old pending invite accepted after proof expiry must delete pending state but not record consumption or welcome-package tombstones.
- Fresh valid invite must not be rejected because listener `receivedAt` differs slightly from payload timestamp; use proof expiry and sane clock-skew tolerance rather than exact timestamp equality.
- Remove-rotate-reinvite must carry the rotated key epoch and a fresh proof so rejoined members can send on the new epoch.
- Device-bound invites must bind proof to recipient device, transport peer, ML-KEM public key, and key-package id/material where present.
- Proof validation must not trust raw `groupConfig` alone; it must compare canonical state hash and trusted contact public key.
- Sender-side stale caller config must fail before encryption or P2P/inbox delivery.
- Existing blocked-contact and unknown-sender behavior must remain distinct from invalid stale proof behavior where current result enums allow it.
- Broad analyzer on `group_message_listener.dart` has known warning debt from prior work; this session should not introduce analyzer errors or new touched-file warnings.

## exact tests and gates to run

Focused red/green commands:

- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'`

Preservation commands:

- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- targeted `dart analyze` over touched Dart production/test files
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Optional supporting real-network command only after host/fake-network proof is green:

- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly`

## known-failure interpretation

- A focused `PREREQ-INVITER-FRESHNESS` test must fail before implementation for the exact missing freshness behavior; unrelated setup failures are not valid RED evidence.
- The named `groups` gate is the canonical group regression gate. Broad folder sweeps can include unrelated dirty-tree or warning debt and should not replace the named gate.
- If targeted analyzer reports pre-existing warnings in untouched code, document them with exact file/diagnostic counts. Do not claim broad analyzer cleanliness unless rerun and verified.
- `group-real-network-nightly` requires device/relay configuration and is supporting only; missing device/relay or fixture flake must not block host/fake-network EC-007 closure.

## done criteria

- First-class invite freshness proof is modeled, signed, parsed, serialized, and included in canonical invite signing.
- Sender-side invite creation rechecks current local inviter membership/permission before proof/sign/encrypt/delivery.
- Direct receive, listener pending-store, and pending accept reject stale self-consistent invites before durable side effects.
- Offline fake-network replay after inviter removal/demotion is covered.
- Valid fresh invite, explicit revoke, welcome/key-package, rotated re-invite, and existing duplicate/identity behavior remain green.
- Required focused tests, preservation tests, `groups`, `completeness-check`, targeted analyzer, and `git diff --check` pass or have exact unrelated caveats.
- EC-007 source matrix row, inventory, plan, and breakdown ledger are updated only after QA acceptance.
- EK-004 remains `Partial`.

## scope guard

- Do not replan or rewrite queued role-update permission checks, `addGroupMember` local rechecks, receive-side stale mutation rejection, or invalid signed-snapshot rejection as the primary work.
- Do not build public/link invite flows, server-side invite directories, social graph features, admin UI, packet capture, or a new relay consensus service.
- Do not change `pendingGroupInviteTtl` globally to force closure; proof freshness must be explicit and local to trusted-private signed invites.
- Do not close EK-004 or claim complete all-event-family offline replay signature equivalence.
- Do not add a database migration unless implementation discovers that proof replay state cannot be represented inside the signed invite credential and existing pending invite repository.

## accepted differences / intentionally out of scope

- The proof is a trusted-private invite credential freshness proof, not a globally consistent membership ledger or external consensus oracle.
- Near-concurrent races where an invite is freshly minted and accepted before any later removal event is observable remain outside this stale/offline replay session. This plan targets queued/stale replay after the proof is no longer fresh and sender-side stale local state after membership change.
- Explicit invite revocation remains IJ-003 scope and should continue to coexist with proof expiry.
- Complete signature-equivalence for every offline replay family remains EK-004 scope.
- Real-device and real-relay proof is supporting after host/fake-network proof; it is not required to make the repo-owned code path executable.

## dependency impact

- EC-007 depends directly on this session. If this plan executes and QA accepts, EC-007 can move from `Partial` to `Covered`.
- EK-004 must remain `Partial` because this work does not prove complete all-event-family offline replay signature equivalence.
- Future invite/link/public-room work must preserve the freshness proof contract or explicitly define a separate current-membership proof.
- If implementation proves the stale replay case requires a live external state oracle, this plan must be downgraded and the breakdown/source matrix should keep EC-007 `Partial` with that structural blocker named.

## Reviewer Findings

Reviewer verdict: sufficient with adjustments, now applied.

- Missing files/tests: add direct coverage for `create_group_with_members_use_case.dart` and `contact_picker_wired.dart` because changing `sendGroupInvite` or `sendGroupInvitesInParallel` will touch their invite fanout call sites.
- Stale assumption corrected: proof expiry should not be validated by raw payload parsing unless parsing receives an explicit validation time; structural proof mismatches can fail parse, while staleness belongs in receive/store/accept auth paths.
- Scope width acceptable: the plan adds a credential-level stale/offline replay proof and sender-side current-state recheck without inventing a new relay consensus service.
- Overengineering check: no database migration, UI, public invite, or real-device-only proof is planned unless implementation evidence forces it.
- Minimum sufficient plan: keep the new proof canonical, signed, current-repo-derived, validation-time-aware, and covered by direct plus fake-network replay tests.

## Arbiter Decision

`execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact proof UX copy is not part of this session; stale proof failures can use existing invalid invite/error surfaces unless implementation exposes a row-owned classification gap.
- Real-device/relay proof is supporting after host/fake-network proof. It is not required to begin implementation.

Accepted differences intentionally left unchanged:

- This plan does not add a globally consistent membership ledger or external consensus oracle. It closes the repo-owned stale/offline invite replay gap with sender-side current-state proof generation, signed freshness binding, and receive/accept-time expiry checks.
- EK-004 remains separate and must stay `Partial` unless complete all-event-family offline replay signature-equivalence is proven by a later session.

Why this is safe to implement now:

- The plan is anchored to the existing signed invite, group config hash, group repository, and contact trust seams.
- Tests are regression-first and directly target the missing stale self-consistent invite path.
- Scope guard prevents reopening already-covered queued role/add, invalid signed snapshot, revocation, key-package replay, UI, and global relay-state work.

## Execution Progress

- 2026-05-01 23:10:42 CEST - Phase: Executor contract extracted. Files inspected or touched: plan, breakdown, current git status, invite payload/auth/send/receive/listener/accept/config/repository/member/model entry points and initial send/model test helpers. Decision/blocker: execution can proceed locally in the already-requested Executor role; dirty tree is broad and pre-existing, so changes will be layered without reverting unrelated edits. Next action: add focused PREREQ-INVITER-FRESHNESS RED tests for missing/tampered proof and stale sender config, then patch production seams.
- 2026-05-01 23:13:00 CEST - Phase: RED tests added and run. Files touched: `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`. Commands: `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'` failed because `GroupInviteMembershipFreshnessProof`, `membershipFreshnessProof`, and `groupInviteMembershipFreshnessProofField` do not exist; `flutter test --no-pub test/features/groups/application/send_group_invite_use_case_test.dart --plain-name 'PREREQ-INVITER-FRESHNESS'` failed because `sendGroupInvite` has no `groupRepo` parameter. Decision/blocker: RED evidence matches the planned missing seam. Next action: implement proof model, sender current-repo proof generation, and receive/accept validation.
- 2026-05-01 23:45:29 CEST - Phase: Executor implementation and validation complete. Production files touched for this session: `lib/features/groups/domain/models/group_invite_payload.dart`, `lib/features/groups/application/group_invite_auth.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`. Test files touched for this session: `test/features/groups/domain/models/group_invite_payload_test.dart`, `test/features/groups/application/send_group_invite_use_case_test.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`, `test/features/groups/application/store_pending_group_invite_use_case_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`. Implementation evidence: signed invite payloads now carry a first-class `GroupInviteMembershipFreshnessProof` bound into the canonical invite signature; sender invite creation reloads current local group membership/permission/config state through `GroupRepository` before proof/sign/encrypt/delivery; receive/listener/accept auth validates proof structure, binding, freshness, inviter snapshot permission, trusted inviter key, and group config state hash before durable side effects; stale accept-time proof deletes the pending invite without consumed/package tombstones, group/member/key state, join events, mailbox drain, or notification effects. Validation: all focused `PREREQ-INVITER-FRESHNESS` selectors passed for invite payload, send invite, create-with-members, contact picker, direct handle, listener, accept pending, and invite round trip; `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed; `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed; targeted `dart analyze` over touched Dart production/test files passed with no issues; `./scripts/run_test_gates.sh groups` passed; `./scripts/run_test_gates.sh completeness-check` passed; `git diff --check` passed. Caveats: an early parallel test attempt hit native asset temporary-file races in `lipo`/`install_name_tool`, but sequential focused reruns passed; earlier groups-gate failures were isolated to existing/follow-on test fixture coverage and were resolved before the final green gate. Source matrix, inventory, and breakdown closure rows were intentionally not updated by this executor pass. Executor verdict: ready for QA; EC-007 closure remains for controller/QA after review, and EK-004 remains separate.
- 2026-05-01 23:52:10 CEST - Phase: QA Reviewer completed. Files inspected: plan, current diff, invite payload/auth/send/create/contact-picker/handle/listener/accept implementation, focused PREREQ tests, invite round-trip preservation tests. Blocking finding: listener/store freshness validation uses `ChatMessage.timestamp` as `receivedAt`, so replaying an old signed invite with its original timestamp can pass proof freshness and create a pending invite side effect; this misses the closure bar that listener pending-store reject stale self-consistent replays before durable state. Commands rerun and passing despite blocker: focused PREREQ payload/send/create/contact-picker/handle/listener/accept/invite-round-trip tests, fresh round-trip preservation test, rotated re-invite preservation test, targeted `dart analyze` over touched Dart production/test files, and `git diff --check`. QA verdict: BLOCKED; EC-007 is not yet eligible for controller closure, EK-004 remains separate.
- 2026-05-01 23:57:20 CEST - Phase: Executor fix-pass completed. Files touched: `lib/features/groups/application/group_invite_listener.dart`, `test/features/groups/application/group_invite_listener_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`. Decision/blocker: listener pending-store freshness now uses an injectable local receive clock instead of `ChatMessage.timestamp`; listener and fake-network replay tests keep the original queued message timestamp while advancing local receipt beyond `groupInviteMembershipFreshnessTtl`. Verification: requested listener and integration `PREREQ-INVITER-FRESHNESS` selectors passed; full listener test file passed; targeted analyzer and `git diff --check` passed; payload/handle/accept PREREQ selectors passed. Next action: QA can re-review this blocker.
- 2026-05-02 00:04:15 CEST - Phase: Final QA Reviewer completed after bounded fix pass. Files inspected: listener/store receive-time seam, invite auth/proof model, sender proof generation, direct handle, pending accept, and focused PREREQ plus preservation tests. Commands rerun: listener PREREQ selector, invite round-trip PREREQ selector, payload/send/handle/accept PREREQ selectors, valid fresh round-trip selector, remove-rotate-reinvite selector, targeted `dart analyze` over invite freshness files, and `git diff --check`; all passed. Decision/blocker: previous listener `ChatMessage.timestamp` replay blocker is resolved; no blocking findings remain. Verdict: ACCEPTED for EC-007 controller closure eligibility; EK-004 remains separate.

## Final QA Verdict

Accepted after one bounded fix pass. EC-007 is eligible for controller closure because the signed membership freshness proof is canonical and bound into invite signatures, sender-side invite creation rechecks current repository membership before proof/sign/encrypt/delivery, direct/listener/accept paths reject stale self-consistent invites before durable side effects, listener pending-store validation now uses local receipt time rather than replayed `ChatMessage.timestamp`, and fresh plus remove-rotate-reinvite flows remain green. EK-004 remains separate and is not closed by this session.
