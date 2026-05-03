# EC-004 Session Plan - Old valid events cannot roll back finalized newer state

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:50:00+02:00 | Local planner completed | EC-004 source matrix row; ordered-session EC-004 row; `group_message_listener_test.dart`; `handle_incoming_group_message_use_case_test.dart`; `handle_incoming_group_reaction_use_case_test.dart`; `group_membership_smoke_test.dart`; `group_resume_recovery_test.dart` | Current repo evidence covers the row-owned old-event matrix for shipped metadata, membership, role, removed-sender message, dissolve, key-rotation, and local tombstone surfaces. No production behavior gap was found. | Run focused evidence gates and close EC-004 as evidence-only if they pass. |

## Execution Progress

| timestamp | role | files inspected or updated | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:51:00+02:00 | Local verifier completed | Application old-event, dissolve-cutoff, reaction-cutoff, membership-smoke, and resume-recovery evidence | All focused EC-004 gates passed. Evidence proves older valid events are accepted only before policy cutoffs and cannot roll back newer metadata, membership, role, key, dissolve, or local-delete tombstone state. | Persist EC-004 as `Covered` with no production-code changes for this row. |

## real scope

EC-004 covers the shipped old-event conflict policy:

- older metadata events cannot roll back a newer metadata state, including after restart and offline replay
- older membership/role events cannot revive a member removed by newer state or roll back a newer role
- removed-sender messages are accepted only before the persisted removal cutoff and rejected at or after the cutoff
- messages and reactions are accepted only before the dissolve cutoff and rejected at or after the cutoff
- old system events after dissolve cannot mutate metadata, members, keys, or visible messages
- old system events for a locally deleted group cannot recreate the group, members, keys, or visible rows

## closure bar

EC-004 can close when direct application and fake-network evidence proves old but otherwise valid events either apply within policy cutoffs or are ignored without rolling back finalized newer state.

## session classification

`needs_repo_evidence`; no production behavior gap was found for shipped metadata, membership, role, key, message, reaction, dissolve, and local tombstone surfaces.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter application and fake-network integration proof.
- Real-device/relay proof is supporting only for this row because the conflict/cutoff behavior is deterministic in the local listener, message/reaction handlers, offline replay drain, and fake-network membership/recovery fixtures.

## files changed

- EC-004 closure docs only.

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'older group_metadata_updated cannot roll back a newer metadata state after restart|older member_added cannot revive state after a newer removal across restart|older member_role_updated cannot roll back a newer role change across restart|older member_role_updated cannot resurrect a member removed by a newer event across restart|old system events after group_dissolved do not mutate metadata, members, keys, or visible messages|old system events for a locally deleted group do not recreate group row or visible message'` passed (`+6`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name 'accepts a message that predates the persisted dissolve cutoff|rejects a message at or after the persisted dissolve cutoff|replayed message after dissolve cutoff does not overwrite the accepted pre-dissolve row'` passed (`+3`).
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --name 'ignores add reactions at or after the dissolve cutoff|ignores remove reactions at or after the dissolve cutoff|accepts late replayed reactions when the payload predates dissolve'` passed (`+3`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'conflicting remove and promote of the same member converge to removal'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline remaining member drains remove-vs-send backlog and keeps the same before-cutoff outcome after resume'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'offline member reconnects after repeated metadata edits and converges to the final metadata state'` passed (`+1`).
- `git diff --check` passed after closure docs.

## Recovery Input

None.

## scope guard

EC-004 does not claim first-class ban, unban, remote message delete, receipt, signed commit-transition, key-package transition, or real-device packet-capture proof. Those remain separate row scope until the product surfaces exist.

## Final Execution Verdict

`accepted`: EC-004 is covered for shipped old-event conflict handling. Older valid events apply only before policy cutoffs and do not roll back finalized newer metadata, membership, role, key, dissolve, local-delete tombstone, message, or reaction state.
