# Group 3 Critical/High Findings Session Breakdown

## Run Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: `false`
- Source review matrix: `Test-Flight-Improv/Group-Chat-Feature/group3-critical-high-findings-2026-05-24-matrix.md`
- Source status vocabulary: `Open`, `Covered`, `Skipped`, `Closed`
- Overall closure bar: every `Open` row must be either implemented with focused test evidence and moved to `Closed`, or truthfully reclassified with concrete blocker evidence.
- Final verdict policy: `closed` only if all `Open` rows in this breakdown are `Closed`; `accepted_with_explicit_follow_up` only for non-blocking residuals; `still_open` if any accepted row lacks code/test evidence.

## Recommended Plan Count

4

## Downstream Execution Path

For each runnable session: create/reuse the session plan, execute with `$implementation-execution-qa-orchestrator`, close with `$implementation-closure-audit-orchestrator`, then update this ledger and the source matrix. Final program acceptance writes a final verdict here.

## Session Ledger

| Session | Source rows | Status | Plan path | Execution verdict | Closure docs touched | Blocker class | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G3-MEM-001 | G3-001, G3-004, G3-005, G3-006, G3-007, G3-009, G3-010 | closed | `Test-Flight-Improv/Group-Chat-Feature/group3-critical-high-findings-2026-05-24-session-G3-MEM-001-plan.md` | accepted | source matrix updated | none | Membership mutation authorization, event ordering, locking, snapshot, dissolved guards implemented and verified. |
| G3-INV-001 | G3-003 | closed | `Test-Flight-Improv/Group-Chat-Feature/group3-critical-high-findings-2026-05-24-session-G3-INV-001-plan.md` | accepted | source matrix updated | none | Current-time invite validation implemented at parse/acceptance boundaries and verified. |
| G3-REACT-001 | G3-011, G3-012, G3-013, G3-014 | closed | `Test-Flight-Improv/Group-Chat-Feature/group3-critical-high-findings-2026-05-24-session-G3-REACT-001-plan.md` | accepted | source matrix updated | none | Reaction target scoping, sender key binding, payload validation, deterministic add IDs implemented and verified. |
| G3-DEVICE-001 | G3-019 | closed | `Test-Flight-Improv/Group-Chat-Feature/group3-critical-high-findings-2026-05-24-session-G3-DEVICE-001-plan.md` | accepted | source matrix updated | none | Strict device identity validation for member config material implemented and verified. |

## Ordered Session Breakdown

### G3-MEM-001

- Classification: `implementation-ready`
- Exact scope: `add_group_member_use_case.dart`, `remove_group_member_use_case.dart`, `group_member.dart` only as needed for config `joinedAt`, and focused tests.
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_membership_event_watermark.dart`
  - `lib/features/groups/domain/models/group_member.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/domain/models/group_member_test.dart`
- Likely tests:
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/domain/models/group_member_test.dart`
- Named gates: none beyond focused tests.
- Dependencies: none.
- Matrix docs to update: this breakdown and the source matrix.
- Scope guard: do not implement durable pending group-config sync state for G3-008.

### G3-INV-001

- Classification: `implementation-ready`
- Exact scope: strict current-time invite validation without making pure model parse depend on async bridge signing.
- Likely code-entry files:
  - `lib/features/groups/domain/models/group_invite_payload.dart`
  - `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
  - `test/features/groups/domain/models/group_invite_payload_test.dart`
  - `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- Likely tests:
  - `flutter test --no-pub test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- Named gates: none beyond focused tests.
- Dependencies: none.
- Matrix docs to update: this breakdown and the source matrix.
- Scope guard: do not replace bridge-backed Ed25519 verification with fake Dart crypto.

### G3-REACT-001

- Classification: `implementation-ready`
- Exact scope: group reaction send/receive validation and deterministic add IDs.
- Likely code-entry files:
  - `lib/features/groups/application/send_group_reaction_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_pending_key_repair_service.dart`
  - `lib/features/groups/domain/models/group_reaction_payload.dart`
  - `test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  - `test/features/groups/domain/models/group_reaction_payload_test.dart`
- Likely tests:
  - `flutter test --no-pub test/features/groups/domain/models/group_reaction_payload_test.dart test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
- Named gates: none beyond focused tests.
- Dependencies: none.
- Matrix docs to update: this breakdown and the source matrix.
- Scope guard: do not add pending reaction state schema for G3-015.

### G3-DEVICE-001

- Classification: `implementation-ready`
- Exact scope: reject invalid device identity config before member config parsing can silently drop bad devices.
- Likely code-entry files:
  - `lib/features/groups/domain/models/group_member.dart`
  - `test/features/groups/domain/models/group_member_test.dart`
- Likely tests:
  - `flutter test --no-pub test/features/groups/domain/models/group_member_test.dart`
- Named gates: none beyond focused tests.
- Dependencies: none.
- Matrix docs to update: this breakdown and the source matrix.
- Scope guard: preserve legacy alias parsing for historical rows.

## Controller Progress

- 2026-05-23T22:41:40Z: Created source matrix and runnable breakdown from user findings after local code audit and parallel explorer input. Next action: plan/execute runnable sessions.
- 2026-05-23T22:58:22Z: Executed G3-MEM-001, G3-INV-001, G3-REACT-001, and G3-DEVICE-001 with parallel worker agents plus controller review. Focused analyzer passed for the touched Dart files. Focused gate passed: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/domain/models/group_member_test.dart test/features/groups/domain/models/group_invite_payload_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/domain/models/group_reaction_payload_test.dart test/features/groups/application/send_group_reaction_use_case_test.dart test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart` (`+169: All tests passed!`).

## Final Program Verdict

`closed`

All rows accepted for this rollout are closed in the source matrix with focused test evidence. Rows marked `Covered` or `Skipped` remain intentionally out of implementation scope for the reasons recorded in the matrix.
