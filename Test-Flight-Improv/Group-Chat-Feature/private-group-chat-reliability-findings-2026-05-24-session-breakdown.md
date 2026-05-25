# Private Group Chat Reliability Findings - 2026-05-24 Session Breakdown

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/private-group-chat-reliability-findings-2026-05-24-matrix.md`

## Run Mode Snapshot

- Active mode: standard session pipeline with row-owned closure.
- Degraded local continuation: not enabled.
- Recommended plan count: 5 sessions plus skipped/covered resolution.
- Source status vocabulary: `Open`, `Closed`, `Covered`, `Skipped`, `Blocked`.
- Closure bar: each `Open` row must be closed with code/test evidence or recorded as a truthful blocker. Covered/skipped rows require concrete evidence in the matrix.
- Final verdict policy: `accepted` only if all open rows are closed and no blockers remain; `accepted_with_explicit_follow_up` only if remaining blockers are explicitly scoped and non-deceptive; `still_open` if runnable implementation work remains.

## Session Ledger

| Session | Rows | Status | Owner Scope | Evidence |
|---|---|---:|---|---|
| S0 | PGC2-001, PGC2-010, PGC2-011, PGC2-013, PGC2-COMPAT | closed | Matrix-only evidence reconciliation | Rows classified stale/covered/skipped with concrete repo evidence. |
| S1 | PGC2-006, PGC2-017, PGC2-018 | accepted | Go EventDispatcher safety | Worker `019e56fe-f927-7d32-9ee0-01a90bbfa559`; `go test ./node -run 'TestEventDispatcher|TestDE010|TestDE011|TestDE012|TestDE020|TestST005|TestPL008' -count=1` passed. |
| S2 | PGC2-002, PGC2-003, PGC2-004, PGC2-007, PGC2-019 | accepted | Rotation distribution safety | Worker `019e56ff-6522-71d0-af2f-fd6c0c73649b`; focused rotation tests passed in bundle. |
| S3 | PGC2-008, PGC2-009, PGC2-012, PGC2-020 | accepted | Invite listener/send safety | Worker `019e56ff-2731-72d0-96c9-2faf744840b0`; focused invite tests passed in bundle. |
| S4 | PGC2-014, PGC2-015, PGC2-016 | accepted | Key repair, key conflict, key DB helper safety | Worker `019e56ff-def3-77e2-bab0-4e3e08dfbaff`; focused key repair/listener/DB tests passed in bundle. |
| S5 | PGC2-005 | blocked_protocol_contract | Two-phase direct key receipt vs signed rotation activation | Blocked pending explicit pending-key activation schema and `key_rotated` promotion contract. |

## Ordered Session Breakdown

### S0 - Covered And Skipped Rows

Resolution without execution. Verify and retain matrix evidence:
- `node.EventCallback` exists in `go-mknoon/node/node.go`; bridge callback is adapted in `go-mknoon/bridge/bridge.go`.
- Invite revocation/consumption/welcome tombstone migrations and helpers exist (`055`, `056`, `064`) and are wired in `main.dart`.
- Accept-pending invite commit records consumption/tombstone only after successful materialization; bridge errors keep the pending invite retryable.
- Dart SDK constraint is `^3.9.0`.

### S1 - Go EventDispatcher Safety

Classification: implementation-ready.

Scope:
- `go-mknoon/node/event_dispatcher.go`
- `go-mknoon/node/node_test.go`

Contract:
- Clone event data on enqueue.
- Make `Stop()` idempotent and make `Emit()` after stop a no-op.
- Preserve critical message-bearing events beyond nominal queue cap while emitting overflow diagnostics.
- Ensure pressure/overflow diagnostics have sane `queueWaitMs`.

Focused gates:
- `go test ./node -run 'TestEventDispatcher|TestDE010|TestDE011|TestDE012|TestDE020|TestST005|TestPL008' -count=1`

### S2 - Rotation Distribution Safety

Classification: implementation-ready with one explicit protocol non-goal.

Scope:
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- focused rotation tests

Contract:
- Null direct transport cannot count as successful distribution.
- No outer batch timeout can return while started key sends are still running.
- Rotation fails closed for active non-self members with no active ML-KEM device.
- Direct send failure may use optional inbox fallback before failing the device.
- Retry reuses the pending draft timestamp for direct key update `eventAt`.

Focused gates:
- `flutter test test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`

### S3 - Invite Listener And Send Safety

Classification: implementation-ready.

Scope:
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- focused invite tests

Contract:
- Invite listener processing is serialized.
- Revocation expiry uses local receive time.
- Invite send rejects stale caller key/epoch.
- Batch invite sends one envelope per active recipient device, falling back to legacy peer only when no devices exist.

Focused gates:
- focused `group_invite_listener_test.dart`
- focused `send_group_invite_use_case_test.dart`

### S4 - Key Repair And Key DB Safety

Classification: implementation-ready.

Scope:
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- focused key repair/listener/DB tests

Contract:
- Live repair rows without replay envelope remain pending instead of becoming undecryptable.
- Same group key epoch insertion is idempotent only for identical material and fails on conflict.
- Same-epoch key update conflicts request repair.

Focused gates:
- focused `group_pending_key_repair_service_test.dart`
- focused `group_key_update_listener_test.dart`
- focused `group_keys_db_helpers_test.dart`

### S5 - Two-Phase Key Activation Protocol

Classification: blocked_protocol_contract.

The finding is meaningful, but current code intentionally uses direct `group_key_update` as the activation path and treats `key_rotated` as signed audit/timeline. Closing this safely requires:
- durable pending key-update material separate from committed `group_keys`
- direct key update listener stores pending material without promoting Go/Dart epoch
- `key_rotated` system event validates signed commit and promotes matching pending material
- rollback/retry behavior for missing commit, duplicate commit, restart, and offline replay

This is not safe as an incidental patch inside the distribution session.

## Controller Progress

- 2026-05-24: Source matrix and session breakdown created. S1-S4 worker sessions spawned with disjoint ownership. S5 recorded as a protocol blocker pending a dedicated two-phase activation plan.
- 2026-05-24: S1-S4 implementation sessions completed and parent verification passed. QA reviewer agent timed out without returning findings; parent-run focused gates, analyzer, and diff check were used as acceptance evidence.

## Final Program Verdict

Verdict: `accepted_with_explicit_follow_up`.

All runnable row-local findings in this batch are closed, covered, or skipped. PGC2-005 remains a deliberate blocker because safe closure requires a protocol-level two-phase key activation design:
- store direct key updates as pending material
- promote only after a signed `key_rotated` commit
- define restart, missing-commit, duplicate-commit, rollback, and offline replay semantics

Verification completed:
- `go test ./node -run 'TestEventDispatcher|TestDE010|TestDE011|TestDE012|TestDE020|TestST005|TestPL008' -count=1`
- `flutter test test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_pending_key_repair_service_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- targeted `flutter analyze` on the touched Dart sources/tests
- `git diff --check -- <batch touched files>`
