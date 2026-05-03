# Session PREREQ-REMOTE-EVENT-FAMILIES Plan - Remote Event Families, Tombstones, And Replay Idempotency

Status: qa_passed

## Planning Progress

| timestamp | role | files inspected since last update | decision/blocker | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T22:19:00+02:00 | Evidence Collector completed | Source rows EK-012, DB-012, EC-006; breakdown reopened prerequisite row 57; `test-inventory.md`; `group_message_listener.dart`; `handle_incoming_group_message_use_case.dart`; `handle_incoming_group_reaction_use_case.dart`; `group_message.dart`; `group_message_repository.dart`; `group_message_repository_impl.dart`; `in_memory_group_message_repository.dart`; `signed_group_transition_audit.dart`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; focused listener/drain/repository tests | Repo-owned prerequisite. Receipts, welcome/key-package replay, signed shipped transitions, message/reaction idempotency, removal, dissolve, metadata, roles, and key rotation are partly or fully covered. Missing first-class surfaces are remote message delete, ban, unban, complete tombstone replay matrix, and signature/replay proof for those newly modeled families. Device availability was verified; iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is present, but this plan is host/fake-network first. | Draft narrow implementation plan. |
| 2026-05-01T22:21:00+02:00 | Planner completed | Same files plus current listener system-event switch and repository delete/read APIs | Plan uses encrypted group system payloads plus deterministic synthetic tombstone/timeline rows, not a new transport or UI feature. Add first-class parsed event helpers for `member_banned`, `member_unbanned`, and `group_message_deleted`; wire receive/replay handling through the existing listener, signed transition audit, event log, and transaction-scoped replay path. | Run sufficiency review. |
| 2026-05-01T22:22:00+02:00 | Reviewer completed | Draft scope, closure bar, tests/gates, and known-failure policy | Sufficient with guardrails: old ban/delete tombstones must not affect current rejoined members or newer messages; duplicate replay must be idempotent; unsupported public-room moderation semantics must stay out of scope; new event families must be added to Go invalid-signature proof and Flutter replay/idempotency proof. | Fold guardrails into arbiter decision. |
| 2026-05-01T22:23:12+02:00 | Arbiter completed | Final plan and source row closure rules | `execution-ready`: no structural blocker remains. DB-012, EC-006, and EK-012 can move to `Covered` only if the implementation proves all newly modeled event families apply idempotently, replay safely, and reject invalid signatures before local mutation. EK-004 may only move if complete all-family offline replay signature-equivalence is also proven; otherwise keep EK-004 `Partial`. | Run Execution+QA. |

## Run Mode

- Active mode: implementation-committed gap-closure.
- Reopened prerequisite: `PREREQ-REMOTE-EVENT-FAMILIES`.
- Owned source rows: DB-012 and EC-006, plus EK-012 replay-family blockers.
- Dependent row to revisit cautiously: EK-004 only if this work proves complete all-event-family offline replay signature-equivalence, not merely the new families.
- Device/relay defaults verified on 2026-05-01T22:19+02:00: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is visible, and the supplied relay addresses remain the configured defaults. This prerequisite is host/fake-network first; real relay/device proof is supporting only unless direct tests reveal a transport-only gap.

## Real Scope

Implement the missing repo-owned remote event family slice:

- Add first-class local parsing/normalization for group system payloads representing:
  - `member_banned`
  - `member_unbanned`
  - `group_message_deleted`
- Wire those families through `GroupMessageListener` using the existing encrypted group-message envelope path.
- Require the same sender device binding, membership authorization, signed transition audit, append-only event-log behavior, and transaction-scoped replay behavior used by shipped security-relevant system transitions.
- Persist deterministic synthetic tombstone/timeline rows for ban, unban, and remote-delete events so duplicate replay is idempotent and old tombstones can be compared against current member/message timestamps.
- For remote message delete, delete or hide only the exact target message id after validating the target belongs to the same group and predates the tombstone; save a deterministic delete tombstone so replay does not create duplicate visible timeline spam.
- For ban/unban, treat this as trusted-private moderation/tombstone semantics only: ban removes a current member and records a ban tombstone; unban records a later tombstone that makes older ban replay stale. Do not add public-room, server-authoritative, discoverable-ban-list, or account-wide moderation features.
- Add direct Flutter tests for live listener and offline replay idempotency/staleness, and Go tests proving the new event families participate in invalid-signature rejection diagnostics.

This session does not build a full public moderation product, admin UI, server-side ban registry, push UI for deletes, packet capture, or a new libp2p protocol.

## Closure Bar

DB-012, EC-006, and EK-012 may move to `Covered` only when:

- duplicate live and offline replay of `member_banned`, `member_unbanned`, and `group_message_deleted` converges to one stable local state with no duplicate timeline spam
- stale `member_banned` replay after unban/rejoin does not remove current valid membership
- stale or out-of-scope `group_message_deleted` replay does not delete newer/current unrelated messages and does not delete messages from another group
- authorization failures for ban, unban, and remote delete produce no group/member/message/tombstone side effects
- signed transition audit and event-log behavior cover the new system families where the listener has append/audit wiring
- Go invalid-signature diagnostics include the new event families and remain privacy-safe
- focused Flutter listener/replay tests, focused repository/fake tests if touched, focused Go tests, `groups`, `completeness-check`, targeted analyzer, and `git diff --check` pass or have documented pre-existing unrelated caveats
- source matrix DB-012, EC-006, EK-012, `test-inventory.md`, this plan, and the breakdown ledger are updated to `Covered` only after final QA accepts

EK-004 can move to `Covered` only if the execution also proves complete offline replay signature-equivalence for every shipped security event family. If the implementation only adds/validates the new remote families, EK-004 must remain `Partial`.

## Source Of Truth

- Primary source rows: `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, EK-012, DB-012, EC-006.
- Current prerequisite ledger: row 57 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Current evidence map: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Current code and focused tests beat stale prose if they disagree.

## Session Classification

`implementation-ready`.

The blocker is repo-owned missing production event-family behavior and tests. No external fixture is required to implement or prove the primary contract.

## Exact Problem Statement

The remaining source rows still name bans, unbans, remote message deletes, and complete event-family idempotency/replay behavior. The repo currently has durable proof for messages, reactions, membership add/remove, role, metadata, dissolve, key rotation, key updates, welcome/key-package tombstones, and receipts, but it has no first-class ban/unban/remote-delete system family. As a result, DB-012, EC-006, and EK-012 cannot close without either production models/tests for those families or a source-scope decision. In this implementation-committed run, the missing behavior is small enough to implement locally.

## Files And Repos To Inspect Next

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/signed_group_transition_audit.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_message.dart`
- likely new helper/model under `lib/features/groups/domain/models/` or `lib/features/groups/application/` for remote tombstone payload parsing
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub.go`

## Existing Tests Covering This Area

- `group_message_listener_test.dart` already covers shipped duplicate/idempotent membership, metadata, role, removal, dissolve, key-rotation, unknown-system, stale-after-dissolve, and unauthorized mutation behavior.
- `drain_group_offline_inbox_use_case_test.dart` already proves replay goes through transaction-scoped listener paths and durable cursor/receipt application.
- `group_message_repository_impl_test.dart` and `in_memory_group_message_repository.dart` already cover durable receipts and message delete basics.
- `go-mknoon/node/pubsub_test.go` already proves invalid signatures are rejected for messages, reactions, member add/remove, role update, metadata, dissolve, and key rotation.
- Current evidence explicitly says ban, unban, remote delete, and all-tombstone replay matrix are missing.

## Regression/Tests To Add First

- Add `PREREQ-REMOTE-EVENT-FAMILIES` Flutter listener tests for:
  - duplicate `group_message_deleted` applies once, removes only the target message, and saves one deterministic tombstone row
  - stale `group_message_deleted` for a message with a newer timestamp, wrong group, missing target, or unauthorized actor produces no destructive side effects
  - duplicate `member_banned` removes the target once and saves one deterministic tombstone row
  - old `member_banned` replay after the target has rejoined or after a later unban tombstone is ignored
  - duplicate `member_unbanned` is idempotent and does not recreate membership or delete current state
- Add offline replay coverage through `drain_group_offline_inbox_use_case_test.dart` or existing listener replay harness to prove replayed tombstones use the same apply path and transaction semantics.
- Add Go invalid-signature cases for `member_banned`, `member_unbanned`, and `group_message_deleted`.

## Step-By-Step Implementation Plan

1. Add a small typed parser/normalizer for the new system event payloads. It should accept the canonical fields needed for deterministic ids:
   - target peer id for ban/unban
   - target message id for remote delete
   - event timestamp
   - optional reason fields only if they are already sanitized and not needed for closure
2. Extend `requiresSignedGroupTransitionAudit` and `buildGroupSystemTransitionSubject` coverage for the three new families.
3. Extend `GroupMessageListener` system dispatch:
   - include new families in authorization routing
   - require active bound actor device
   - require admin/removeMembers for ban/unban and admin/deleteMessages or message owner policy for remote delete
   - append event log before local mutation when append wiring is installed
4. Implement `_handleMemberBanned`, `_handleMemberUnbanned`, and `_handleGroupMessageDeleted` with deterministic tombstone ids:
   - do not duplicate tombstone rows on exact replay
   - ignore stale ban when target joined after event time or a newer unban tombstone exists
   - ignore stale delete when the target message is absent, belongs to another group, or has a timestamp after the delete event time
   - delete/hide only the exact target message id for remote delete
5. Keep the implementation inside existing group message/listener repositories unless tests prove a dedicated migration/table is required. If a table is required, add the next migration/helper/repository tests with the Flutter SQLite migration skill pattern.
6. Update fakes only where required for focused tests to observe current tombstone/message state.
7. Run focused tests, analyzer, Go invalid-signature test, named gates, and diff hygiene.
8. After final QA accepts, update source matrix, test inventory, and breakdown rows:
   - DB-012 to `Covered` if the all-family idempotency matrix is complete for shipped and newly modeled families
   - EC-006 to `Covered` if tombstone replay matrix is complete
   - EK-012 to `Covered` if replay diagnostics/remaining unmodeled replay families are closed by the new event family coverage and explicit trusted-private scope
   - EK-004 only if complete offline replay signature-equivalence is proven; otherwise leave `Partial`

## Risks And Edge Cases

- A replayed old ban after a rejoin must not remove the current valid member.
- A replayed old delete must not delete a newer message or a message outside the target group.
- Exact duplicate tombstones must not create duplicate timeline rows or duplicate event-log entries.
- Signed audit duplicate handling must still distinguish exact replay from conflicting replay.
- Unban should not recreate membership or grant permissions; it is a tombstone/freshness event, not a join event.
- Remote delete should not delete local upload artifacts or media files unless existing user-owned delete code already handles that safely; this prerequisite is about remote event state, not file cleanup UX.

## Exact Tests And Gates To Run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'`
- any focused repository/fake tests added by implementation
- `dart analyze` over touched Dart files
- `cd go-mknoon && go test ./node -run 'InvalidSignatureForSecurityEventFamilies|ER001|PREREQ_REMOTE_EVENT_FAMILIES' -count=1`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Known-Failure Interpretation

- Broad ad hoc Flutter folder sweeps may include pre-existing unrelated failures from earlier matrix work. Use the named `groups` gate as the canonical group regression gate.
- Existing listener analyzer debt outside touched lines should be documented if targeted analyzer reports unrelated warnings; do not claim broad analyzer cleanliness unless rerun and verified.
- Real relay/device proof is supporting only for this prerequisite. If a real-device gate is run, use inline defaults when unset:
  - `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
  - `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`

## Done Criteria

- The new remote event families have production parsing, authorization, signed audit/event-log integration, and listener apply behavior.
- Duplicate and stale replay tests prove idempotency and no current-state corruption for ban, unban, and remote delete.
- Go invalid-signature tests cover the new families.
- Required focused tests, targeted analyzer, `groups`, `completeness-check`, and `git diff --check` pass or document exact unrelated pre-existing caveats.
- Source matrix, inventory, plan, and breakdown are updated only after QA accepts.

## Scope Guard

- Do not build public-room moderation, server-authoritative ban lists, link-invite moderation, admin UI, push copy, packet capture, or a new transport protocol.
- Do not close EK-004 unless complete all-family offline replay signature-equivalence is actually proven.
- Do not close EC-007; inviter freshness belongs to `PREREQ-INVITER-FRESHNESS`.
- Do not reinterpret ban/unban as public-room policy. In trusted-private groups, this session only needs durable remote event tombstone behavior and replay safety.
- Do not delete unrelated user/local media files as part of remote message delete unless an existing safe owner already does it.

## Accepted Differences / Intentionally Out Of Scope

- Ban/unban can be represented as trusted-private encrypted group system events rather than a server-side moderation registry.
- Unban can be a freshness/tombstone event and does not have to re-add the member or restore keys.
- Remote message delete can remove/hide only local message state for the exact target id; global media retention, file erasure, and UI affordances remain separate product surfaces.

## Dependency Impact

- If this plan closes, DB-012, EC-006, and EK-012 should be revisited for `Covered`.
- EK-004 remains `Partial` unless execution proves complete all-event-family offline replay signature-equivalence.
- EC-007 remains owned by `PREREQ-INVITER-FRESHNESS`.

## Arbiter Decision

`execution-ready`.

The plan is narrow enough to execute safely. It adds the missing event-family behavior directly named by the source rows, uses existing encrypted system events, event-log, signed-audit, and listener replay seams, and keeps public moderation/product UI out of scope.

## Execution Progress

| timestamp | role | files inspected or touched | command/result | decision/blocker | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T22:24:00+02:00 | Controller | Plan file, source rows, device snapshot, dirty worktree status | `flutter devices --machine` confirmed requested iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` is visible; plan status is `execution-ready`; `git diff --check` passed after DB-006 closure docs. | Contract extracted. Scope is PREREQ-REMOTE-EVENT-FAMILIES only: add trusted-private remote event families for ban, unban, and remote message delete with idempotency/replay/signature tests, then update source rows only after QA. | Spawn Executor with bounded owner files and tests. |
| 2026-05-01T22:28:38+02:00 | Executor | Plan file; `group_message_listener.dart`; `signed_group_transition_audit.dart`; group message/member/model repositories and fakes; focused listener/drain tests; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go` | Inspection only. | Existing path already has sender-device binding, optional signed transition audit, event-log append, deterministic system timeline rows, and replay through `handleReplayEnvelope`. The smallest slice is to add a typed trusted-private parser, tombstone timestamp lookup helpers, listener handlers, focused Flutter replay tests, and Go invalid-signature cases. | Patch scoped production and tests. |
| 2026-05-01T22:36:32+02:00 | Executor | `group_message_listener.dart`; `trusted_private_group_system_event.dart`; `signed_group_transition_audit.dart`; `group_message_repository.dart`; `group_message_repository_impl.dart`; `in_memory_group_message_repository.dart`; focused listener/drain tests; `go-mknoon/node/pubsub_test.go` | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` passed; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` passed; `cd go-mknoon && go test ./node -run 'InvalidSignatureForSecurityEventFamilies|ER001|PREREQ_REMOTE_EVENT_FAMILIES' -count=1` passed. | Production slice and direct focused replay/signature tests are green. | Run targeted analyzer, named gates, and diff hygiene. |
| 2026-05-01T22:39:16+02:00 | Executor | Same touched files plus plan Execution Progress | Focused Flutter listener and drain slices rerun and passed; Go invalid-signature focused test passed; `./scripts/run_test_gates.sh groups` passed; `./scripts/run_test_gates.sh completeness-check` passed; `git diff --check` passed. `dart analyze` over touched Dart files still exited 2 with 19 pre-existing warnings in `group_message_listener.dart` (`unnecessary_non_null_assertion`, `invalid_null_aware_operator`, `unused_element`, `use_null_aware_elements`); warnings introduced by this slice were removed before rerun. | Implementation handoff ready with analyzer caveat. Source matrix, test inventory, and breakdown closure rows intentionally not updated per controller instruction. | Hand off to QA/controller. |
| 2026-05-01T22:47:40+02:00 | Final QA | Lander diff for trusted-private system event parser, listener handlers, signed audit, repository/fake tombstone helpers, Flutter PREREQ tests, and Go invalid-signature proof | Final QA verdict: `ACCEPTED`, no blocking findings. QA reran `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+3`), `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-REMOTE-EVENT-FAMILIES'` (`+1`), Go invalid-signature regex, and `git diff --check`; all passed. Targeted analyzer still exits 2 with the same warning-only pre-existing `group_message_listener.dart` caveat and no analyzer errors. | `qa_passed`: DB-012, EC-006, and EK-012 may move to `Covered`. EK-004 must remain `Partial` because complete offline replay signature-equivalence for every shipped security event family was not proven. | Update source matrix, test inventory, and breakdown ledger for DB-012, EC-006, and EK-012 only; continue to PREREQ-INVITER-FRESHNESS. |

## Final QA Verdict

`accepted / qa_passed`.

The implementation adds trusted-private encrypted system-event support for `member_banned`, `member_unbanned`, and `group_message_deleted` through the production `GroupMessageListener` path, with typed parsing, existing sender device binding, authorization, signed transition audit/event-log integration, deterministic tombstone/timeline rows, duplicate replay idempotency, stale ban-after-unban/rejoin protection, and stale/wrong-group/newer-message remote-delete protection.

DB-012, EC-006, and EK-012 can move to `Covered` from this prerequisite. EK-004 remains `Partial` because this prerequisite added and proved the missing event families but did not prove complete offline replay signature-equivalence for every shipped security event family.
