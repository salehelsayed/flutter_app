# Session EK-004 Plan - All-Event Offline Replay Signature Equivalence

Status: closed

## Planning Progress

- 2026-05-02T08:40:00Z - Controller closure completed. Files inspected since last update: EK-004 product/test delta, source matrix row, test inventory row, breakdown ledger/final verdict, and this plan. Commands passed: focused EK004 Flutter bundle (`+16`), direct key/audit/remote-family selector (`+12`), create/event-log (`+19`), invite wildcard (`+149`), key wildcard (`+49`), fake-network replay bundle (`+80`), Go live invalid-signature selector, targeted format, scoped analyzer, `groups` (`+103`), `completeness-check` (`712/712`), and `git diff --check`. Decision/blocker: no EK-004 blocker remains; source matrix, inventory, breakdown, and this plan are updated to `Covered`/closed. Next action: none for this rollout unless a new regression is found.
- 2026-05-02T07:04:10Z - Arbiter completed. Files inspected since last update: reviewer findings and adjusted plan. Decision/blocker: no structural blockers remain; the plan is safe to execute as EK-004 row-owned implementation work. Next action: execute with RED-first tests and keep EK-004 `Partial` until all-family offline/history replay signature-equivalence passes.
- 2026-05-02T07:03:28Z - Reviewer completed; Arbiter started. Files inspected since last update: draft plan only. Decision/blocker: sufficient with adjustments; no structural blocker. Adjustments needed before final status: use regex `--name` for multi-selector commands, add explicit local create/event-log proof, and name dissolve/broadcast sender tests in the exact test contract. Next action: classify findings and finalize if no structural blocker remains.
- 2026-05-02T07:03:10Z - Planner completed; Reviewer started. Files inspected since last update: no new files beyond the evidence pass. Decision/blocker: draft plan is implementation-ready, row-owned, and requires new signed offline/history replay-envelope proof for group payload families while rerunning direct invite/key-update evidence. Next action: review for missing families, gates, scope drift, and device/relay proof requirements.
- 2026-05-02T06:59:44Z - Evidence Collector completed; Planner started. Files inspected since last update: EK-004 source row and remaining-partial table, session breakdown final verdict/ledger, gate definitions, `signed_group_transition_audit.dart`, `group_offline_replay_envelope.dart`, `drain_group_offline_inbox_use_case.dart`, `group_message_listener.dart`, `group_key_update_listener.dart`, `main.dart`, Go PubSub invalid-signature test, PREREQ signed-audit/remote-family/inviter-freshness plans, and focused group tests. Decision/blocker: current repo evidence is not enough; group offline/history replay envelopes lack an explicit signature-equivalence proof for all shipped group message/reaction/system payloads. Next action: draft an execution-ready EK-004 plan with all event families, owner files, RED-first tests, gates, and host/device proof profile.
- 2026-05-02T06:55:48Z - Evidence Collector started. Files inspected since last update: existing EK-004 plan. Decision/blocker: confirmed the current artifact is stale because it closes direct key-update signatures but leaves complete offline replay signature-equivalence unplanned. Next action: inspect the EK-004 source row, breakdown ledger, current event-family code/tests, and gate definitions.

## Run Mode

- Active mode: implementation-committed gap-closure.
- Current session: EK-004 only.
- Source row: `EK-004` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Source status at intake: `Partial`.
- Row-owned closure rule: EK-004 moves to `Covered` only after concrete current proof that every shipped security-relevant group event family rejects invalid signatures before local mutation on live receipt, offline/pending replay, and history repair replay where that path exists.
- Current plan posture: implementation-ready, not evidence-only. Current evidence narrows many adjacent blockers, but current unsigned `group_offline_replay` envelopes are not enough for complete offline/history replay signature-equivalence.

## real scope

Implement the smallest EK-004-owned proof for all-event-family signature equivalence.

What this session owns:

- Add current signed offline/history replay proof for group replay payloads that travel through `group_offline_replay`.
- Prove live PubSub, offline/pending inbox replay, and history repair replay enforce equivalent sender signature/authentication before group message, reaction, system transition, key, membership, metadata, tombstone, timeline, cursor-transaction, notification, or event-log side effects.
- Preserve and rerun already-landed direct event signatures for group invites, invite revocations, welcome/key-package material embedded in invites, direct `group_key_update`, signed transition audits, and metadata actor events.
- Keep EK-004 row-owned. Do not move any other source row or rewrite product/test code during this planning pass.

What this session does not own:

- No new MLS protocol, server consensus service, public moderation model, account-wide identity registry, packet capture, admin UI, relay rewrite, or broad transport rewrite.
- No reopening EC-007 invite freshness, EK-012 replay protection, DB-012 idempotency, DB-002 event-log hash chain, EK-003 device identity, or EK-005 future-key repair unless an EK-004 regression directly exposes a signature-equivalence gap in their current owner paths.
- No product/test code edits in this planning session.

## closure bar

EK-004 is good enough only when all of the following are true in current code and tests:

- Every shipped security-relevant family listed below has a valid-signature acceptance path and invalid/missing/mismatched-signature rejection path before local mutation.
- Live receipt remains covered by the Go v3 PubSub envelope signature for `group_message`, `group_reaction`, and group system payloads, plus app-layer signed transition/audit checks where those payloads mutate state.
- Offline/pending replay uses a signed replay envelope for current `group_offline_replay` payloads and verifies the sender, sender device/transport binding, payload type, group id, key epoch, ciphertext/nonce binding, plaintext hash or equivalent payload binding, message/source event id, and signature before decoded payloads can mutate state.
- History repair replay uses the same signed replay verification as normal offline inbox drain before applying repaired messages. A repair range with an invalid replay signature is rejected without message/reaction/system mutation and is recorded as a failed or rejected repair attempt with privacy-safe diagnostics.
- Existing direct `group_invite`, `group_invite_revocation`, and direct `group_key_update` signature tests remain green and prove rejection before pending/group/key/join/revocation/key-save/event-log side effects.
- Legacy unsigned replay envelopes are not silently accepted as current proof. They must either be fail-closed/quarantined before mutation or be handled by an explicitly tested compatibility path that cannot mark EK-004 `Covered` unless current generated replay envelopes are signed and enforced.
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, focused direct tests, Go invalid-signature proof, targeted analyzer/format where relevant, and `git diff --check` pass or record exact unrelated pre-existing caveats.

## source of truth

- Active plan artifact: this file once it says `Status: execution-ready`.
- Source row: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row EK-004 and the remaining-partial prerequisite table.
- Breakdown ledger: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, final verdict and EK-004-only remaining blocker.
- Evidence inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, especially EK-004, EK-012, DB-002, DB-012, EC-006, EC-007, IJ-002, IJ-003, and EK-003 entries.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; the script wins on disagreement.
- Current production code and focused tests beat stale prose. If docs claim coverage but code/tests do not prove it, implementation must leave EK-004 `Partial`.

## session classification

`implementation-ready`

Reason: current repo evidence proves the remaining gap is repo-owned. The current group replay envelope is encrypted but not signed, and both normal offline drain and history repair replay decode it before applying message/reaction/system handlers. That is enough to plan concrete tests and code changes without requiring a device or relay fixture first.

## exact problem statement

EK-004 asks: "Signature verification covers every security-relevant event type." Its expected behavior is that tampered messages, invites, membership, roles, settings, key updates, and audit events are rejected before local state mutation with privacy-safe diagnostics.

Current evidence already covers adjacent pieces:

- Go PubSub validator rejects invalid live signatures for `group_message`, `group_reaction`, `member_added`, `members_added`, `member_removed`, `member_banned`, `member_unbanned`, `member_role_updated`, `group_message_deleted`, `group_metadata_updated`, `group_dissolved`, and `key_rotated`.
- Signed transition audit and event-log evidence covers shipped system transitions and direct `group_key_update` append-wired audit verification.
- Invite and invite-revocation payloads are signed and rejected before pending/group/key/join/revocation side effects.
- Future/missing-key replay now queues and retries through the verified replay path after key arrival.
- Remote tombstone families and inviter freshness are now covered in their own rows.

The remaining blocker is specific: `group_offline_replay` currently contains `kind`, `version`, `payloadType`, `keyEpoch`, optional `messageId`, `ciphertext`, and `nonce`, but no replay signature. `drain_group_offline_inbox_use_case.dart` and history repair decode that envelope, decrypt it, and route the payload to message, reaction, or system handlers. That proves encryption and apply behavior, but not signature equivalence with live PubSub for every current offline/history replay family.

User-visible behavior that must improve: stale, forged, or tampered replay payloads cannot create or alter group messages, reactions, membership, roles, metadata, tombstones, key state, timeline rows, unread/read state, notifications, or history repair state unless they carry a valid current signature bound to the same sender and payload that live receipt would require.

Behavior that must stay unchanged: valid group send/reaction/system replay, invite acceptance and backlog drain, key rotation, direct key updates, signed metadata, tombstone idempotency, future-key repair, and group resume recovery remain green.

## shipped event families to cover

Coverage must explicitly account for these shipped families and paths:

| Family | Live path | Offline/pending replay path | History repair replay path | Required EK-004 proof |
| --- | --- | --- | --- | --- |
| `group_message` normal text/media | Go PubSub envelope signature before `group_message:received`; Flutter `GroupMessageListener`/`handleIncomingGroupMessage` membership and replay guards | `send_group_message_use_case.dart` builds `group_offline_replay`; `drain_group_offline_inbox_use_case.dart` decodes and applies | `_applyRepairedHistoryMessages` decodes and applies repaired group messages | Add signed replay-envelope generation and verification; invalid replay signature or payload binding rejects before message/media/receipt/notification/cursor mutation |
| `group_reaction` add/remove | Go PubSub envelope signature before `group_reaction:received`; Flutter `handleIncomingGroupReaction` sender/member guards | `send_group_reaction_use_case.dart`, `remove_group_reaction_use_case.dart`, reaction replay outbox and retry build `group_offline_replay` | History repair currently rejects reaction repair ranges; keep or prove no reaction mutation | Add signed replay-envelope generation/verification for add/remove reaction replay; invalid signature rejects before reaction repository mutation |
| Membership transitions: `member_added`, `members_added`, `member_removed` | Go PubSub envelope signature plus signed transition audit and app authorization/device binding in `GroupMessageListener` | `group_info_wired.dart`, `broadcast_voluntary_leave_use_case.dart`, `accept_pending_group_invite_use_case.dart` and related senders can store system payloads through `group_offline_replay` | Same drain/history listener path if repaired ranges contain system payloads | Signed replay envelope plus existing signed transition audit. Invalid outer replay signature rejects before listener; invalid inner audit rejects before member/config/timeline/event-log mutation |
| Moderation/tombstones: `member_banned`, `member_unbanned`, `group_message_deleted` | Go PubSub envelope signature plus signed transition audit, authorization, deterministic tombstone handling | `drain_group_offline_inbox_use_case_test.dart` already replays these through listener, but current replay envelope signature is missing | Same as system payload history repair when present | Add signed replay-envelope proof and retain signed audit/tombstone idempotency; invalid signature rejects before member/message/tombstone mutation |
| Role/settings/dissolve/key-system: `member_role_updated`, `group_metadata_updated`, `group_dissolved`, `key_rotated` | Go PubSub envelope signature plus signed transition audit; metadata also has actor-event signature | `group_info_wired.dart`, `dissolve_group_use_case.dart`, key-rotation/system senders store or publish system payloads; replay currently shares listener path | Same as system payload history repair when present | Signed replay envelope plus existing inner audit/actor checks; invalid outer or inner signature rejects before role/config/dissolve/key/timeline/event-log mutation |
| `member_joined` join announcement | Group PubSub envelope and `_isAuthorizedJoinEventSender`; membership/key admission is owned by signed invite accept | `accept_pending_group_invite_use_case.dart` stores a join system payload through `group_offline_replay` | Same system replay path if present | Cover replay-envelope signature before timeline insertion. Signed transition audit is not required if implementation confirms `member_joined` stays timeline-only and cannot admit membership/key state |
| Direct `group_invite` | Direct P2P route through `IncomingMessageRouter` and `GroupInviteListener`; signed invite attestation and freshness proof | Direct/mailbox/pending invite handling, not `group_offline_replay` | No group history repair path | Existing tests must be rerun; add only if current proof no longer rejects invalid signatures before pending/group/key/join/notification side effects |
| Direct `group_invite_revocation` | Direct P2P route through `GroupInviteListener`; signed revocation payload | Delayed direct/mailbox revocation handling, not `group_offline_replay` | No group history repair path | Existing tests must be rerun; invalid revocation signature rejects before tombstone/pending deletion side effects |
| Direct `group_key_update` | Direct P2P `GroupKeyUpdateListener`; canonical key-update signature plus signed transition audit | Pending key-repair retry after key arrival reuses the verified key/update and replay paths | No group history repair path for the direct key update itself | Existing EK004 and PREREQ signed-audit tests must stay green; invalid key-update signature rejects before `group:updateKey`, event-log append, key save, or repair retry |
| `group_created` local audit | Local create signed event-log append | No remote offline/history replay path | No remote offline/history replay path | Rerun create/event-log evidence or document as local-only accepted difference; invalid create signing must still roll back local create state |
| Welcome/key-package material | Embedded in signed `group_invite`; no separate shipped event route | Pending invite storage/accept path | No group history repair path | Covered through invite signature/freshness/key-package tests; do not invent a separate event family unless code exposes one |

## files and repos to inspect next

Primary production owners:

- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
- `lib/features/groups/application/signed_group_transition_audit.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/group_invite_auth.dart`
- `lib/features/groups/domain/models/group_invite_payload.dart`
- `lib/features/groups/domain/models/group_invite_revocation_payload.dart`
- `lib/core/database/helpers/group_event_log_db_helpers.dart`
- `lib/main.dart` only if wiring or dependency injection changes are required

Replay envelope sender call sites:

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/remove_group_reaction_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` for preservation of direct key-update and `key_rotated` evidence

Go guard files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`

Likely direct tests:

- `test/features/groups/application/group_offline_replay_envelope_test.dart` if added
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/application/remove_group_reaction_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/broadcast_voluntary_leave_use_case_test.dart` if present or a nearest existing leave/remove owner test if not
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/core/database/helpers/group_event_log_db_helpers_test.dart`
- `test/features/groups/application/group_invite_listener_test.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/domain/models/group_invite_payload_test.dart`
- `test/features/groups/domain/models/group_invite_revocation_payload_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `go-mknoon/node/pubsub_test.go`

Docs to update only after execution and QA:

- This plan with execution result.
- EK-004 row in the source matrix.
- EK-004 entry in `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- EK-004 session/breakdown ledger and final program verdict.

## existing tests covering this area

Already useful evidence:

- `go-mknoon/node/pubsub_test.go` contains `TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies`, currently covering live invalid signatures for group messages, reactions, membership adds/removals, ban/unban, remote delete, metadata, dissolve, and key rotation at the Go envelope layer.
- `group_message_listener_test.dart` covers signed transition audit rejection/idempotency for some system paths, metadata actor signature rejection, tombstone idempotency, role replay, stale membership/metadata, dissolve behavior, and unauthorized mutation rejection.
- `drain_group_offline_inbox_use_case_test.dart` proves offline replay routes system payloads through the listener and transaction path, but does not currently prove a replay signature envelope.
- `group_key_update_listener_test.dart` has EK004 tests for unsigned, mismatched, and invalid direct key-update signatures before bridge update/log/key save, plus signed transition-audit direct key-update proof.
- Invite payload/listener/accept tests prove signed invite and signed revocation rejection before pending/group/key/join/revocation side effects.
- `group_event_log_db_helpers_test.dart` and DB-002 evidence cover tamper-evident event-log append and conflicting replay detection after a payload is accepted for append.

Missing today:

- No current signed replay-envelope contract for `group_offline_replay`.
- No all-family test that invalid offline replay signatures reject before mutation for normal messages, reactions, system transitions, `member_joined`, and history repair.
- No sender-side proof that every current `storeGroupOfflineReplayEnvelope` or retry-payload call site signs the replay envelope before `group:inboxStore` or pending retry storage.
- No history repair proof that repaired payloads require the same signed replay validation as normal offline drain.

## regression/tests to add first

Add RED tests before production edits:

- `group_offline_replay_envelope_test.dart` or focused tests in `drain_group_offline_inbox_use_case_test.dart` proving current replay envelopes must include `signatureAlgorithm`, `signedPayload`, `signature`, `senderPeerId`, and sender device/transport binding. Missing, malformed, mismatched, or invalid signatures must fail before returning a decoded payload to apply code.
- `send_group_message_use_case_test.dart`: `EK004 stores signed offline replay envelope for group_message and aborts or fails closed when replay signing fails`.
- `send_group_reaction_use_case_test.dart` and `remove_group_reaction_use_case_test.dart`: `EK004 stores signed offline replay envelope for group_reaction add/remove and retry rows`.
- `group_info_wired_test.dart`, `dissolve_group_use_case_test.dart`, `broadcast_voluntary_leave_use_case` owner tests, and `accept_pending_group_invite_use_case_test.dart` as needed: signed offline replay envelopes are emitted for `member_removed`, `member_role_updated`, `group_metadata_updated`, `group_dissolved`, and `member_joined` system payloads.
- `drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004'`: table-driven valid/invalid replay for `group_message`, `group_reaction`, `member_added` or `members_added`, `member_removed`, `member_banned`, `member_unbanned`, `member_role_updated`, `group_message_deleted`, `group_metadata_updated`, `group_dissolved`, `key_rotated`, and `member_joined`. Invalid signatures produce no message/reaction/member/group/key/timeline/event-log/read-receipt mutation.
- History repair coverage in `drain_group_offline_inbox_use_case_test.dart`: a repaired range with valid signed replay applies; the same range with tampered replay signature is not marked repaired and produces no local mutation.
- Preservation reruns for direct paths: `group_key_update_listener_test.dart --plain-name 'EK004'`, invite signature/revocation selectors, and Go invalid-signature selectors.

Expected RED result: current code should fail these tests because `group_offline_replay` has no replay signature fields and `decodeInboxMessage` cannot reject invalid replay signatures before decoding/applying payloads.

## step-by-step implementation plan

1. Start execution with `git status --short` and inspect current diffs in every owner file before editing. Do not revert unrelated dirty-tree work.

2. Add RED tests from the section above. If tests unexpectedly pass with concrete all-family proof, stop and classify as already-covered with exact evidence. Otherwise continue with implementation.

3. Add a compact signed replay-envelope helper, preferably in `group_offline_replay_envelope.dart` or a nearby `group_offline_replay_signature.dart`. The signed canonical payload should bind:
   - schema/version and `kind: group_offline_replay`
   - `groupId`
   - `payloadType`
   - `messageId` or source event/reaction id where present
   - `senderPeerId`
   - `senderDeviceId` and `senderTransportPeerId` when present
   - `keyEpoch`
   - ciphertext and nonce hash or exact canonical ciphertext/nonce fields
   - plaintext hash or equivalent decrypted-payload binding
   - recipient set hash when a call site has explicit recipients
   - `signatureAlgorithm`, `signedPayload`, and signer signature

4. Update `buildGroupOfflineReplayEnvelope`, `storeGroupOfflineReplayEnvelope`, `buildGroupOfflineReplayInboxRetryPayload`, and `storeGroupOfflineReplayFromRetryPayload` to support the signed envelope. Current generated envelopes must be signed. Preserve call-site ergonomics with a small signer object or parameters rather than ad hoc JSON at each sender.

5. Update all current replay sender call sites so they pass the signing material they already use for live publish or direct send:
   - message send
   - reaction add/remove and retry
   - member removal/leave
   - role update
   - metadata update
   - dissolve
   - member joined invite-accept announcement
   - any `key_rotated` offline replay if a sender stores it through the replay envelope

6. Enforce replay signature verification in `decodeInboxMessage` before it returns a decoded payload to callers. Resolve the signer public key from current group member/device identity. Verify relay `from`, signed sender/transport, and payload sender fields agree. Reject invalid/missing/mismatched signatures with privacy-safe diagnostics and no decoded payload.

7. After decrypting a signed replay envelope, verify the plaintext hash or payload binding before routing to:
   - `handleIncomingGroupMessage`
   - `handleIncomingGroupReaction`
   - `GroupMessageListener.handleReplayEnvelope`
   - history repair `_applyRepairedHistoryMessages`

8. Preserve existing inner validations:
   - Signed transition audit remains mandatory for append-wired system transitions.
   - Metadata actor-event signature remains mandatory for metadata.
   - Direct invite, revocation, and key-update signatures remain unchanged and still reject before side effects.
   - `member_joined` can remain signed-replay-only if implementation confirms it is timeline-only and never creates membership/key admission state.

9. Decide and test legacy unsigned replay behavior. EK-004 closure allows only fail-closed/quarantine behavior for current unsigned replay envelopes unless a compatibility path is narrowly justified and cannot mutate security-relevant state. Do not let a legacy compatibility branch become the proof for current replay.

10. Run focused tests, then named gates. Fix only EK-004-owned failures. If a test exposes a non-replay product gap, record it as out of scope unless it blocks signature-equivalence closure.

11. After implementation and QA pass, update EK-004 source matrix, test inventory, this plan, and breakdown/final verdict to `Covered` only with concrete files, commands, and any accepted caveats.

## risks and edge cases

- Replay signature verification must run before message, reaction, system transition, receipt/read-state, event-log, key-save, timeline, notification, or cursor-transaction side effects.
- A signed replay envelope must not let a relay `from` spoof a different signed sender or transport peer.
- Current group members without first-class device records may still need a legacy member public-key fallback consistent with existing live/direct validation. That fallback must be documented and tested.
- Recipient-specific replay signatures must not leak member lists, keys, plaintext, raw signatures, or private identity material into logs.
- History repair ranges should not be marked repaired when any member of the range fails signature validation.
- Future/missing-key replay must still queue for key repair without applying plaintext, then re-enter the same signature verification path after key arrival.
- Duplicate signed replay should be idempotent; conflicting signed replay with the same source id should be rejected.
- Existing valid metadata, membership, remote-delete, ban/unban, key rotation, reactions, invite accept, and direct key-update flows must remain green.

## exact tests and gates to run

Focused RED/green selectors:

- `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'` if a new helper test is added
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/remove_group_reaction_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart --plain-name 'EK004'` if dissolve replay-signature tests are added there
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'EK004'`
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name 'EK004'` if local `group_created` proof is refreshed under this selector
- `flutter test --no-pub test/core/database/helpers/group_event_log_db_helpers_test.dart --plain-name 'EK004'` if event-log signature-equivalence helpers are added there
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'EK004'` if `group_info_wired.dart` replay sender hooks are touched

Preservation and adjacent direct-signature commands:

- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart`
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS|EK004'`
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`
- `flutter test --no-pub test/features/groups/application/*key*_test.dart`
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`

Go and named gates:

- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- targeted `dart analyze` over touched Dart production/test files
- `dart format --output=none --set-exit-if-changed <touched Dart files>`
- `git diff --check`

## known-failure interpretation

- A focused EK004 replay-envelope test that still fails because unsigned `group_offline_replay` is accepted is a valid RED failure.
- Broad Flutter folder sweeps are not the source of truth; use the focused selectors and the named `groups` gate.
- If targeted analyzer includes pre-existing warning-only debt in `group_message_listener.dart`, document exact diagnostics and ensure EK-004 introduces no analyzer errors or new touched-line warnings.
- Broad Go owner regexes may still hit unrelated peer-count/peer-mismatch tests documented by prior sessions. The direct invalid-signature Go selector is the EK-004 Go source of truth unless Go production code changes.
- `group-real-network-nightly` requires external device/relay fixtures. Missing or flaky external fixture evidence must not be used to mark EK-004 `Covered` or `Partial`; the host/fake-network proof is primary for this row.

## done criteria

- Current generated `group_offline_replay` envelopes are signed for every current sender call site that stores group messages, reactions, or system payloads for offline/pending delivery.
- Offline inbox drain rejects missing, malformed, mismatched, or invalid replay signatures before any local mutation.
- History repair replay uses the same verification and fails repair safely when replay signatures are invalid.
- Live Go invalid-signature proof remains green for all listed live event families.
- Existing direct invite, revocation, key-update, metadata actor, and signed transition-audit proofs remain green.
- Focused EK004 tests, preservation tests, named gates, analyzer/format as applicable, and diff hygiene pass or have exact unrelated caveats.
- EK-004 source matrix row, inventory entry, plan execution result, and breakdown final verdict are updated only after implementation plus QA acceptance.

## scope guard

- Do not introduce a new transport protocol, relay authorization model, MLS commit layer, server-side consensus, public moderation product, or account-wide device registry.
- Do not move any non-EK-004 row to `Covered` from this session.
- Do not treat encryption-only replay envelopes as signature-equivalence proof.
- Do not accept unsigned legacy replay envelopes as current EK-004 coverage. They must fail closed or be explicitly quarantined before mutation.
- Do not weaken existing invite, revocation, key-update, metadata, signed-audit, or event-log checks to make replay tests pass.
- Do not add a database migration unless current persisted retry rows need an explicit fail-closed/quarantine marker that cannot be represented with existing status fields.

## accepted differences / intentionally out of scope

- `member_joined` can remain outside signed transition-audit requirements if implementation proves it is timeline-only and cannot create membership, key, or admission state. It still needs signed replay-envelope coverage before timeline insertion when delivered through offline/history replay.
- `group_created` is a local signed audit event, not a remote live/offline/history replay family. Rerun local create/event-log evidence, but do not invent remote replay semantics for create.
- Welcome/key-package material is embedded in signed invite payloads and pending invite/tombstone handling; there is no separate shipped replay event family to sign under EK-004 unless current code exposes one.
- Host/fake-network proof is primary. Real device/relay proof is supporting only unless implementation touches real transport/bridge behavior in a way host tests cannot exercise.

## Device/Relay Proof Profile

Device/relay proof is not required as a primary closure gate for EK-004.

Justification: the remaining blocker is deterministic signature verification at repo-owned Go validator and Dart application replay seams. The required evidence can be produced with:

- Go unit tests for live PubSub envelope invalid signatures.
- Dart host tests for signed replay-envelope generation, drain rejection, history repair rejection, and direct listener side-effect absence.
- Existing fake-network group integration tests for resume, invite, membership, and replay preservation.

Run `group-real-network-nightly` only as supporting evidence after host/fake-network proof is green or if implementation unexpectedly changes real transport, bridge callback semantics, relay protocol, or device-only identity wiring. Missing device/relay fixtures must not block execution-ready planning.

## dependency impact

- EK-004 is the only remaining `Partial` row in the source breakdown. If this plan executes and QA accepts, the rollout can move toward final `closed`/`Covered` reconciliation.
- If implementation finds a shipped family with no safe current signature source, EK-004 must remain `Partial` with that exact family and path named.
- If the replay-envelope design requires a migration or compatibility quarantine, DB docs may need evidence notes, but DB rows must not move from this EK-004 session unless separately requested.

## Reviewer Pass

Reviewer status: sufficient with adjustments, now applied.

Findings:

- Sufficient: the plan enumerates shipped families, including `member_joined`, direct invites/revocations, direct key updates, local `group_created`, and embedded welcome/key-package material.
- Sufficient: the plan requires implementation and RED-first tests because current `group_offline_replay` lacks replay signature fields.
- Sufficient: invalid-signature rejection before mutation is explicit for live, offline/pending, and history repair paths.
- Adjustment applied: multi-test-name preservation commands use `--name` regex rather than `--plain-name`.
- Adjustment applied: local `group_created`/event-log proof and dissolve/broadcast sender tests are explicit in the file/test contract.
- Not overengineered: device/relay proof remains supporting only with a host/fake-network primary profile.

## Arbiter Decision

`execution-ready`

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper/file naming for replay signatures can be chosen by the executor after RED tests land.
- The executor can choose whether to add a dedicated `group_offline_replay_envelope_test.dart` or keep helper coverage inside existing drain/send tests, as long as the focused EK004 commands and completeness gate prove the same contract.

Accepted differences intentionally left unchanged:

- `member_joined` is signed-replay-envelope covered but does not need signed transition-audit coverage unless implementation finds it mutates membership/key admission.
- `group_created` remains local signed audit evidence, not a remote replay family.
- Welcome/key-package material remains covered as part of signed invite payloads, not as a standalone event.
- Device/relay proof is supporting only because this row can close through deterministic host/fake-network and Go validator evidence.

Why safe to implement now:

- Current code evidence identifies a concrete missing seam: unsigned `group_offline_replay` for offline/history replay.
- The plan names the exact event-family matrix, owner files, RED-first tests, named gates, done criteria, known-failure policy, and scope guard.
- EK-004 stays `Partial` until implementation and QA prove the all-family contract with current code and commands.

## Execution Progress

- 2026-05-02T07:07:03Z - Controller started under `$implementation-execution-qa-orchestrator`. Files inspected: skill instructions, this EK-004 plan, gate definition/script references. Command run: `git status --short`. Decision/blocker: dirty tree is intentionally broad from prior rollout sessions; do not revert or reset unrelated edits. Exact initial status output captured in execution notes at `/tmp/ek004_initial_git_status_20260502T070703Z.txt` with SHA-256 `0a73ceb7bf4b89b983c9fe518da2045eb7eeb06a591bee800a4e1c3185b124e5`. Next action: extract contract and spawn the Executor child agent.
- 2026-05-02T07:07:03Z - Contract extracted. Scope: EK-004 only; add signed `group_offline_replay` generation/verification and all-event-family offline/history replay signature-equivalence proof while preserving direct invite/revocation/key-update/audit evidence. Owner entry files: replay envelope helper, drain/history replay, message/reaction/system sender call sites, listener/direct-signature preservation tests, Go invalid-signature selector, and named `groups`/`completeness-check` gates. Required RED-first tests: signed replay envelope missing/malformed/mismatched/invalid rejection before decoded payload/apply, sender-side signed envelope generation for message/reaction/system families, drain/history all-family rejection, and preservation selectors. Non-goals: no transport/relay/MLS/device-registry rewrite and no moving EK-004 source docs to Covered. Next action: spawn Executor with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-05-02T07:08:00Z - Executor spawned/running. Files handed off: this plan, gate definitions/script references, and EK-004 owner file/test list named by the plan. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"` as isolated Executor. Decision/blocker: none yet. Next action: wait for Executor handoff summary and repo evidence.
- 2026-05-02T07:08:20Z - Executor spawn retry. Files touched: none beyond this progress entry. Command result: first `codex exec` invocation exited before materializing a child because the CLI rejected short option `-a`. Decision/blocker: tool invocation issue only, no partial child edits. Next action: relaunch Executor with long-form `--ask-for-approval never`.
- 2026-05-02T07:08:50Z - Executor spawn retry. Files touched: none beyond this progress entry. Command result: second `codex exec` invocation exited before materializing a child because this CLI build also rejected `--ask-for-approval` after the subcommand. Decision/blocker: tool invocation ordering issue only, no partial child edits. Next action: relaunch Executor with sandbox/approval as top-level `codex` options before `exec`.
- 2026-05-02T07:10:01Z - Executor child started from user handoff. Files inspected: this EK-004 plan, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `git status --short`, current diffs for EK-004 owner files/tests, and `lib/features/groups/application/group_offline_replay_envelope.dart`. Decision/blocker: current helper is encryption-only and has no replay signature fields, so RED-first signed replay tests are required. Next action: add focused EK004 tests before production edits.
- 2026-05-02T07:18:52Z - RED-first tests added. Files touched: `test/features/groups/application/group_offline_replay_envelope_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/application/send_group_reaction_use_case_test.dart`, `test/features/groups/application/remove_group_reaction_use_case_test.dart`. Command run: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'`. Result: failed as expected because `buildGroupOfflineReplayEnvelope` has no signer parameters/signature constants and `GroupOfflineReplaySignatureException` does not exist yet; fixed one test-fixture-only `GroupModel.myRole` omission before implementation. Next action: implement signed replay-envelope generation and verification.
- 2026-05-02T07:21:27Z - Signed replay-envelope implementation landed. Files touched: `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, message/reaction/system replay sender call sites. Command run: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'`. Result: PASS. Decision/blocker: helper signs current envelopes and rejects missing/malformed/mismatched/invalid signatures before decrypt in the direct helper suite. Next action: run drain and sender EK004 focused selectors and fix scoped failures.
- 2026-05-02T07:26:31Z - Focused EK004 replay sender/drain selectors passed. Files touched: message, reaction, retry, drain/history repair, invite-accept, dissolve, voluntary-leave, and group-info replay sender tests. Commands passed: `send_group_message_use_case_test.dart --plain-name 'EK004'`, `send_group_reaction_use_case_test.dart --plain-name 'EK004'`, `remove_group_reaction_use_case_test.dart --plain-name 'EK004'`, `retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'EK004'`, `drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004'`, `accept_pending_group_invite_use_case_test.dart --plain-name 'EK004'`, `dissolve_group_use_case_test.dart --plain-name 'EK004'`, `member_removal_integration_test.dart --plain-name 'EK004'`, and `group_info_wired_test.dart --plain-name 'EK004'`. Decision/blocker: current generated message/reaction/system replay sender paths now produce signed envelopes; normal drain and history repair reject invalid signatures before side effects. Next action: run required adjacent preservation selectors and analyzer/format.
- 2026-05-02T07:29:23Z - Preservation/gate sweep started. Files touched since last entry: this progress log only. Commands queued: adjacent invite/key preservation selectors, Go live invalid-signature selector, targeted format/analyzer for EK-004 Dart files, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Decision/blocker: none yet. Next action: run preservation selectors and record exact pass/fail output.
- 2026-05-02T07:35:11Z - Adjacent preservation selectors passed. Files touched since last entry: `test/features/groups/integration/group_resume_recovery_test.dart` fixture only, adding default `payload.sign`/`payload.verify` handling to `_Section10MirroringBridge` so the real wired sender path can build signed replay envelopes. Commands passed: `group_invite_listener_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`, `handle_incoming_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`, `accept_pending_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS|EK004'`, `flutter test --no-pub test/features/groups/application/*invite*_test.dart`, `flutter test --no-pub test/features/groups/application/*key*_test.dart`, `invite_round_trip_test.dart`, `group_resume_recovery_test.dart`, `group_membership_smoke_test.dart`, and `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`. Caveat: the first `group_resume_recovery_test.dart` run failed/hung before this fixture fix because `payload.sign` returned no signature; rerun passed. Next action: run targeted format/analyzer, named gates, and `git diff --check`.
- 2026-05-02T07:39:32Z - Executor verification sweep completed. Commands passed: `dart format --output=none --set-exit-if-changed` after formatting, scoped `dart analyze` excluding the known `group_info_wired.dart` warning cluster, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Caveat: full targeted analyzer including `lib/features/groups/presentation/screens/group_info_wired.dart` still exits nonzero on existing presentation nullability/dead-code warnings; no analyzer errors were reported. Decision/blocker: no EK-004 implementation blocker remains from Executor perspective. Next action: QA Reviewer should inspect the code/test delta and independently decide acceptance.
- 2026-05-02T07:44:20Z - QA Reviewer started. Files inspected: this EK-004 plan, executor handoff, initial dirty-tree capture, focused replay-envelope/drain/sender diffs, and EK-004 helper/drain tests. Decision/blocker: candidate QA blocker under review because invalid replay signatures are skipped before payload mutation but normal inbox drain still appears to commit the page cursor. Next action: inspect remaining sender/direct-preservation evidence and rerun required focused gates before final QA verdict.
- 2026-05-02T07:48:44Z - QA Reviewer completed. Files inspected: replay envelope helper, normal drain/history repair/pending key repair paths, sender call sites, EK004 helper/drain/sender tests, direct invite/key/audit preservation tests, Go validator selector, source matrix EK-004 row, gate definitions by script execution, and focused line-level cursor/legacy decode evidence. Commands passed: focused EK004 Flutter selectors, invite/key/audit/create/event-log preservation selectors, invite/key wildcards, `invite_round_trip_test.dart`, `group_resume_recovery_test.dart`, `group_membership_smoke_test.dart`, Go live invalid-signature selector, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, targeted format, scoped analyzer excluding `group_info_wired.dart`, and `git diff --check`. Decision/blocker: QA verdict rejected due replay-drain signature side-effect gaps; fix pass required. Caveats: analyzer including `group_info_wired.dart` still exits nonzero on the existing warning cluster with no analyzer errors; host/fake-network/Go proof was used as primary evidence and no device/relay proof was run.
- 2026-05-02T07:53:09Z - Fix-pass Executor started. Files inspected: QA result, executor result, this plan `## QA Verdict`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and cursor transaction fakes/helpers. Decision/blocker: fix scope is limited to the two QA blockers: abort page transactions on replay signature rejection before cursor/receipt/read-state side effects, and fail closed on unsigned decoded/fallback relay replay forms before mutation. Next action: add RED-first EK004 drain/decode regressions, run them to confirm failure, then patch the drain/decode behavior.
- 2026-05-02T07:55:33Z - RED-first fix-pass regressions added and confirmed. Files touched: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Commands failed as expected: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004 invalid or missing replay signatures abort before cursor side effects'` failed because invalid signature replay committed cursor `''`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004 unsigned non envelope replay forms fail closed before mutation'` failed because decoded unsigned relay replay saved `ek004-unsigned-decoded`. Decision/blocker: both QA blockers are reproduced. Next action: update drain transaction error handling and unsigned decode fallback behavior only.
- 2026-05-02T07:56:23Z - Fix implementation completed. Files touched: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`. Code delta: replay signature exceptions now rethrow out of `runInboxPageTransaction` after privacy-safe flow logging so cursor/receipt/read-state changes roll back; `decodeInboxMessage` now returns only verified `group_offline_replay` payloads and fails closed on decoded relay maps, already-decoded sender maps, and fallback relay strings. Commands passed: both new EK004 fix-pass regressions. Boundary documented in code comment: unsigned replay forms are rejected before mutation; signed missing-key repair remains separate. Next action: run full EK004/focused preservation verification, format/analyze, diff check, and required gates.
- 2026-05-02T08:03:31Z - Post-fix verification still in progress. Commands passed after the fix: both new EK004 replay-drain regressions, focused EK004 Flutter selectors after formatting, adjacent drain cursor/listener/system/receipt/history-repair selectors with signed replay fixtures, targeted `dart format --output=none --set-exit-if-changed`, scoped `dart analyze` for the fix-pass Dart files, and `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`. Current gate status: `./scripts/run_test_gates.sh groups` exposed additional valid offline backlog fixtures in `test/features/groups/integration/group_resume_recovery_test.dart` that still used unsigned decoded relay maps; fix-pass is converting those fixtures to current signed `group_offline_replay` envelopes and rerunning targeted resume-recovery selectors before retrying the gate. Decision/blocker: no final QA verdict yet; if signed-fixture conversion does not stabilize `groups`, final verdict must remain blocked with exact gate/failure evidence.
- 2026-05-02T08:09:50Z - Verification status heartbeat after second user status request. Active fix-pass Executor session is still running and has surfaced fixture conversion work in `test/features/groups/integration/group_resume_recovery_test.dart`, but it has not yet written a final handoff or final QA verdict. No long-running named gate completion is visible from the child output yet. Next action: continue bounded polling; if the child does not produce trustworthy final verification, perform controller-side sequential fallback with exact post-fix focused tests/gates and write either a final accepted or blocked verdict here.
- 2026-05-02T08:09:57Z - Fix-pass final verification started after signed replay fixture conversion. Files touched since last entry: `test/features/groups/integration/group_resume_recovery_test.dart` and this progress log. Commands passed before final gate retry: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline remaining member drains remove-vs-send backlog'`, `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline member reconnects after repeated metadata edits'`, and `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'Section 11'`. Decision/boundary: integration fixtures now use signed `group_offline_replay` envelopes for relay inbox replay; the remaining-member fixture keeps only the valid pre-removal Bob replay plus signed removal system replay because post-removal Bob replay cannot be verified from current membership state and production must not reintroduce unsigned compatibility mutation. Next action: rerun targeted format/analyze, focused selectors, `git diff --check`, `groups`, and `completeness-check`.
- 2026-05-02T08:19:34Z - Same-session EK-004 recovery/fix pass started from controller blocker. Scope guard: write only `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` plus this plan evidence; do not edit source matrix, breakdown, inventory, or production code. Files inspected: this plan, target invite-accept test, `group_offline_replay_envelope.dart`, `drain_group_offline_inbox_use_case.dart`, `fake_bridge.dart`, and invite materialization/member/key helpers. Decision/blocker: two invite-accept fixtures still used unsigned legacy relay maps while current drain fail-closes with `GroupOfflineReplaySignatureException(unsigned_relay_payload)`. Next action: replace only those stale fixtures with signed replay-envelope test helpers.
- 2026-05-02T08:20:59Z - Same-session EK-004 recovery/fix pass completed. Files touched: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` and this plan. Code/test delta: added a small `signedReplayInboxMessage` helper using `buildGroupOfflineReplayEnvelope`, `FakeBridge` signing/encryption defaults, and the invite's `GroupKeyInfo`; converted the plain offline message fixture and message-plus-`group_reaction` backlog fixture to signed `group_offline_replay` envelopes while preserving existing message/reaction assertions. Commands passed: `dart format test/features/groups/application/accept_pending_group_invite_use_case_test.dart`; `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/*invite*_test.dart`; `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'EK004'`; `dart format --output=none --set-exit-if-changed test/features/groups/application/accept_pending_group_invite_use_case_test.dart`. Decision/blocker: controller-reported stale unsigned fixture blocker is resolved; no residual blocker found in the required verification set.
- 2026-05-02T08:28:49Z - Same-session EK-004 recovery pass 2 started for integration fixture fallout only. Scope guard: write only `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and this plan progress/evidence; do not edit product code, source matrix, breakdown, or test inventory. Files inspected: this plan, both target integration tests, `group_offline_replay_envelope.dart`, `drain_group_offline_inbox_use_case.dart`, `fake_bridge.dart`, and `bridge_group_helpers.dart`. Decision/blocker: the broad fake-network integration bundle exposed stale unsigned replay fixtures and helper calls using repos without replay keys. Next action: convert only the named fixtures to signed `group_offline_replay` envelopes, rerun the six focused selectors, rerun the three-file bundle, and run the requested format check.
- 2026-05-02T08:32:21Z - Same-session EK-004 recovery pass 2 completed. Files touched: `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and this plan. Fixture delta: converted the invite bridge-error drain row to a signed `group_offline_replay` envelope; converted the history-gap repair response list and expected range hash to the signed relay messages actually returned by the bridge; changed resume/watchdog replay signing to use the receiver repo that has the replay key; changed the two removed-offline-member `group:inboxStore` fixtures to `storeGroupOfflineReplayEnvelope` with admin signer material and an explicit decryptable key. Commands passed: `dart format test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart`; `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'bridgeError accept later rejoin and drain converge without the pending invite row'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'member backgrounded during send receives missed group messages after resume'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'removed offline member drains replayed removal'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'removed offline member does not retry queued failed sends after replayed removal'`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'`; `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_membership_smoke_test.dart`; `dart format --output=none --set-exit-if-changed test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart`. Decision/blocker: all requested recovery-pass verification passed; no residual integration-fixture blocker found. EK-004 source/matrix/breakdown/inventory status was intentionally not changed to `Covered`.

## Executor Handoff

Executor scope completed for EK-004 only. I did not move EK-004 source docs to `Covered` and did not perform the QA Reviewer role.

Code/test/doc delta:

- `lib/features/groups/application/group_offline_replay_envelope.dart`: current `group_offline_replay` generation now signs canonical replay metadata and verifies missing/malformed/mismatched/invalid signatures before decrypt/apply.
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`: normal inbox drain and history repair now use signed replay verification and reject invalid replay envelopes before message/reaction/system side effects.
- `lib/features/groups/application/group_pending_key_repair_service.dart`: pending key repair replay decrypt now preserves the same expected relay/sender verification.
- Replay sender call sites updated to pass signer identity/material: `send_group_message_use_case.dart`, `send_group_reaction_use_case.dart`, `remove_group_reaction_use_case.dart`, `accept_pending_group_invite_use_case.dart`, `broadcast_voluntary_leave_use_case.dart`, `dissolve_group_use_case.dart`, and `group_info_wired.dart`.
- New/updated tests: `group_offline_replay_envelope_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, `send_group_message_use_case_test.dart`, `send_group_reaction_use_case_test.dart`, `remove_group_reaction_use_case_test.dart`, `retry_failed_group_inbox_stores_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `dissolve_group_use_case_test.dart`, `member_removal_integration_test.dart`, `group_info_wired_test.dart`, and `group_resume_recovery_test.dart`.
- `group_resume_recovery_test.dart` fixture fix: `_Section10MirroringBridge` now mirrors base fake `payload.sign`/`payload.verify` defaults so real wired sender-path replay signing works in Section 10 tests.
- This EK-004 plan was updated with execution progress and this handoff only.

Focused EK-004 test results:

- RED-first `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'`: failed as expected before implementation because replay signer parameters/constants/exception did not exist.
- `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/send_group_reaction_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/remove_group_reaction_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/dissolve_group_use_case_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'EK004'`: PASS.

Preservation and gate results:

- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --name 'PREREQ-SIGNED-COMMIT-AUDIT|EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'PREREQ-SIGNED-COMMIT-AUDIT|PREREQ-REMOTE-EVENT-FAMILIES|EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`: PASS.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS'`: PASS.
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --name 'IJ002|IJ003|PREREQ-INVITER-FRESHNESS|EK004'`: PASS.
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/application/*key*_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`: PASS.
- First `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`: FAIL/hung after `GROUP_SEND_MSG_REPLAY_ENVELOPE_FAILED` because `_Section10MirroringBridge` returned no `signature` for `payload.sign`; fixed the fixture and reran.
- Rerun `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`: PASS.
- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`: PASS.
- `./scripts/run_test_gates.sh groups`: PASS.
- `./scripts/run_test_gates.sh completeness-check`: PASS.
- `dart format --output=none --set-exit-if-changed <EK-004 touched Dart files>`: initial FAIL with 4 files needing formatting; `dart format <EK-004 touched Dart files>` applied formatting; rerun PASS with 0 changed.
- `dart analyze <EK-004 touched Dart files excluding group_info_wired.dart>`: PASS with infos only.
- `dart analyze <EK-004 touched Dart files including group_info_wired.dart>`: FAIL/nonzero due existing `group_info_wired.dart` warnings (`unnecessary_null_comparison`, `dead_code`, `dead_null_aware_expression`) plus infos; no errors.
- `git diff --check`: PASS.

Blockers/caveats for QA:

- No EK-004 implementation blocker remains from the Executor perspective.
- Full targeted analyzer remains blocked by the existing `group_info_wired.dart` presentation warning cluster. I did not normalize that broad file because it is outside the replay-signature change and the worktree is intentionally dirty.
- Host/fake-network and Go proof are primary for this session. I did not run real device/relay proof because EK-004 did not touch real transport/device-only behavior.

## QA Verdict

QA verdict: rejected.

Blocking findings:

- `cursor_side_effect_after_invalid_replay_signature`: normal offline inbox drain catches replay signature decode failures inside the inbox page transaction and continues, then commits the page cursor. Evidence: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` lines 256-309 call `runInboxPageTransaction`, catch `decodeInboxMessage` failures, emit `GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED`, and continue; lines 534-536 advance local cursor state after the transaction. The production transaction helper commits `nextCursor` in `lib/core/database/helpers/group_sync_receipts_db_helpers.dart` lines 118-138, and the in-memory fake mirrors that at `test/shared/fakes/in_memory_group_message_repository.dart` lines 317-334. The EK004 invalid-family test at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` lines 498-610 proves no decrypt/message/reaction/group/member mutation, but it does not prove cursor non-mutation. This does not satisfy the QA contract requiring invalid replay signatures to reject before cursor side effects.
- `unsigned_non_envelope_replay_still_applies`: `decodeInboxMessage` still accepts decoded relay `message` maps that are not `group_offline_replay` envelopes, and also accepts already-decoded maps with `senderId`, without requiring a replay signature. Evidence: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` lines 965-994 return a non-envelope decoded message directly; lines 997-1001 return an already-decoded `senderId` payload directly; lines 1003-1011 synthesize a fallback payload from relay fields. That leaves a missing-signature replay path that can reach message/reaction/system handlers, so missing replay signatures are not fail-closed or explicitly quarantined before mutation.

Accepted evidence:

- Current generated replay envelopes are signed for inspected sender call sites: message, reaction add/remove and retry, member join, member removal/leave, metadata, role update, and dissolve.
- Signed replay verification runs before decrypt for recognized `group_offline_replay` envelopes, and plaintext binding is checked before decoded payload return.
- History repair invalid replay signatures are rejected without marking repaired in the focused EK004 test.
- Direct invite, invite revocation, direct key update, metadata actor, signed transition-audit, future-key repair, replay/idempotency, and Go live invalid-signature evidence remained green in QA reruns.

QA evidence rerun:

- Passed: `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart --plain-name 'EK004'`.
- Passed: grouped focused EK004 Flutter selectors for send message, reaction add/remove, retry, drain/history, invite accept, dissolve, member removal, and group info.
- Passed: direct preservation selectors for `group_key_update_listener_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, `group_message_listener_test.dart`, create/event-log tests, invite payload/revocation tests, invite listener/handler/accept selectors, invite/key wildcards, and the three fake-network integration suites.
- Passed: `go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`.
- Passed: `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, targeted `dart format --output=none --set-exit-if-changed`, scoped `dart analyze` excluding `group_info_wired.dart`, and `git diff --check`.
- Caveat: `dart analyze lib/features/groups/presentation/screens/group_info_wired.dart` exits nonzero with 26 existing warnings (`unnecessary_null_comparison`, `dead_code`, `dead_null_aware_expression`) and no analyzer errors.

Fix pass required: yes.

## Recovery Pass 2 QA Verdict

QA verdict: accepted for the integration-fixture fallout scope only. EK-004 source, matrix, breakdown, and inventory status remain unchanged; this pass does not mark EK-004 `Covered`.

Scope review:

- Files changed in this pass: `test/features/groups/integration/invite_round_trip_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and this plan evidence.
- Product code, source matrix, breakdown, and test inventory were not edited by this recovery pass.
- The existing dirty tree outside this scope was left untouched.

Evidence:

- Passed: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'bridgeError accept later rejoin and drain converge without the pending invite row'`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR fake-network repair rejects bad source then restores range before live delivery'`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'member backgrounded during send receives missed group messages after resume'`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'removed offline member drains replayed removal'`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'removed offline member does not retry queued failed sends after replayed removal'`.
- Passed: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'`.
- Passed: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_membership_smoke_test.dart`.
- Passed: `dart format --output=none --set-exit-if-changed test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart`.

Blocking issues remaining for this recovery pass: none.

Non-blocking follow-ups deferred: controller still owns broader EK-004 closure documentation and any full-gate reconciliation.

## Final Closure Verdict

QA verdict: accepted for EK-004 overall.

Closed source state:

- EK-004 source matrix row: `Covered`.
- EK-004 inventory row: `Covered`.
- Breakdown final verdict: `closed`, `49 Covered / 0 Open / 0 Partial`, unresolved row ids `None`.

Closure evidence:

- `flutter test --no-pub test/features/groups/application/group_offline_replay_envelope_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/remove_group_reaction_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/dissolve_group_use_case_test.dart test/features/groups/application/member_removal_integration_test.dart test/features/groups/presentation/group_info_wired_test.dart --plain-name 'EK004'`: PASS (`+16`).
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/group_message_listener_test.dart --name 'PREREQ-SIGNED-COMMIT-AUDIT|PREREQ-REMOTE-EVENT-FAMILIES|EK004'`: PASS (`+12`).
- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart test/core/database/helpers/group_event_log_db_helpers_test.dart`: PASS (`+19`).
- `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/domain/models/group_invite_revocation_payload_test.dart test/features/groups/application/*invite*_test.dart`: PASS (`+149`).
- `flutter test --no-pub test/features/groups/application/*key*_test.dart`: PASS (`+49`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/integration/group_membership_smoke_test.dart`: PASS (`+80`).
- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsInvalidSignatureForSecurityEventFamilies' -count=1 -v`: PASS.
- `dart format --output=none --set-exit-if-changed <EK-004 touched Dart files>`: PASS (`0 changed`).
- `dart analyze <EK-004 touched Dart files excluding group_info_wired.dart>`: PASS with info-only diagnostics.
- `dart analyze lib/features/groups/presentation/screens/group_info_wired.dart`: nonzero with the documented pre-existing warning-only cluster (`unnecessary_null_comparison`, `dead_code`, `dead_null_aware_expression`); no analyzer errors.
- `./scripts/run_test_gates.sh groups`: PASS (`+103`).
- `./scripts/run_test_gates.sh completeness-check`: PASS (`712/712`).
- `git diff --check`: PASS.

Accepted caveats:

- Host/fake-network/Go proof is the primary EK-004 closure profile. Real device/relay proof remains supporting-only because this row did not change device-only transport behavior.
- `group_created` is local event-log-only, not a remote replay family.
- Welcome/key-package material is embedded in signed invite payloads and already covered by the invite path, not a separate EK-004 replay family.
- Full MLS semantics and a separate account/device registry remain outside this retained source-row contract.
