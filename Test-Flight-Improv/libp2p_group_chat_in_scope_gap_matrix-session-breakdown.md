# Libp2p Group Chat In-Scope Gap Matrix Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- Supporting docs:
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
  - `Test-Flight-Improv/57-authenticated-group-membership-events.md`
  - `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Decomposition date:
  `2026-04-04`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must refresh against landed code before execution
  - implementation-committed gap-closure mode applies because the source matrix explicitly exists to make the current repo match the remaining in-scope user journeys

## Downstream execution path

- Row-owned sessions should run, in breakdown order, through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Execute rows in this default order:
  1. `P0` rows in source order
  2. `P1` rows in source order
  3. `P2` rows in source order
- Run `CLOSURE-001` only after the row-owned sessions that remain runnable are resolved.
- Sessions classified `prerequisite-blocked` stay in the ledger but should not advance past planning until their blocker is resolved or the source matrix is truthfully split.

## Recommended plan count

- `31`
- The smallest safe split is:
  - `30` row-owned sessions keyed directly to source matrix row ids
  - `1` closure-only session for final matrix truth, gate classification, and final verdict emission
- Row disposition counts:
  - `covered_in_repo`: `1`
  - `needs_tests_only`: `16`
  - `needs_code_and_tests`: `13`
  - `blocked_by_prerequisite`: `0`
- No shared prerequisite session was added during decomposition. The former blocker rows were later resolved through follow-on doc-scoped rollouts `56-deterministic-remove-vs-send-boundary.md`, `57-authenticated-group-membership-events.md`, and `58-offline-group-membership-sync-scope-split.md` without weakening row ownership or traceability.

## Overall closure bar

`Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` stays `still_open` until all of the following are true at the same time:

- every source row in this filtered matrix is updated from an unresolved state to `Closed` or `Covered` with concrete repo evidence
- a row-owned session is not considered done until the source matrix row itself changes state, not merely because related code or tests improved elsewhere
- `accepted_with_explicit_follow_up` is not an acceptable final outcome for any row that remains unresolved in the source matrix
- rows currently marked `prerequisite-blocked` do not count as closed while the blocker remains; the prerequisite must be resolved or the source row must be truthfully split or retired by contract
- the source matrix, this breakdown, and any touched architecture or closure docs tell the same truthful story about repo support, remaining work, and exact row-level evidence

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
- `Test-Flight-Improv/57-authenticated-group-membership-events.md`
- `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that materially affected row classification:

- `MR-014` is already recorded as closed in the filtered source matrix with exact direct proof, so it is carried forward here as `covered_in_repo` instead of being reopened.
- `GM-011`, `MR-003`, `MR-004`, `MR-008`, `MR-020`, `RJ-007`, `SC-007`, and `SC-018` now read as genuine repo-owned behavior gaps rather than missing-evidence-only rows, so they stay `needs_code_and_tests`.
- Follow-on rollout `56-deterministic-remove-vs-send-boundary.md` resolved the former ordering prerequisite for `MR-015` and `SC-012`, so both rows now close with the same repo-owned `message.timestamp < member_removed.removedAt` rule across live, replay, and reconnect paths.
- Follow-on rollout `57-authenticated-group-membership-events.md` resolved the former membership-event authorization prerequisite for `SC-001` and `SC-015`, so raw non-admin add/remove bypass traffic is now rejected at the Flutter listener seam using durable local creator/admin facts.
- Follow-on rollout `58-offline-group-membership-sync-scope-split.md` split unsupported admin-transfer propagation out of `MR-024` and closed the repo-owned offline-bystander reconnect contract with direct convergence proof.
- Rows that only needed direct proof, including `UX-007`, stayed in `needs_tests_only` and now close with row-owned evidence rather than broader evidence-only cleanup.
- This filtered matrix already removed unsupported and contract-undefined rows, so no source row in this artifact is silently reclassified as `unsupported_product_scope` or `repo_external_proof`.

## Matrix row inventory

| Row ID | Scenario | Priority | Source section | Provisional row disposition | Intended session id |
| --- | --- | --- | --- | --- | --- |
| `GM-002` | Create/add with offline member bootstrap | `P1` | Core Group Messaging | `needs_tests_only` | `GM-002` |
| `GM-006` | Sequential same-sender ordering | `P1` | Core Group Messaging | `needs_tests_only` | `GM-006` |
| `GM-011` | Notification deep link | `P1` | Core Group Messaging | `needs_code_and_tests` | `GM-011` |
| `GM-016` | Network partition and reconnect | `P1` | Core Group Messaging | `needs_tests_only` | `GM-016` |
| `MR-003` | New member cannot send before bootstrap completes | `P1` | Membership and Role Control | `needs_code_and_tests` | `MR-003` |
| `MR-004` | Add existing member handled cleanly | `P1` | Membership and Role Control | `needs_code_and_tests` | `MR-004` |
| `MR-008` | Remove non-member handled cleanly | `P1` | Membership and Role Control | `needs_code_and_tests` | `MR-008` |
| `MR-013` | Remaining members see removal system event | `P1` | Membership and Role Control | `needs_code_and_tests` | `MR-013` |
| `MR-014` | Removed while offline | `P0` | Membership and Role Control | `covered_in_repo` | `MR-014` |
| `MR-015` | Removed while typing/sending | `P0` | Membership and Role Control | `needs_code_and_tests` | `MR-015` |
| `MR-020` | At least one admin remains | `P0` | Membership and Role Control | `needs_code_and_tests` | `MR-020` |
| `MR-024` | Offline bystander syncs supported membership changes on reconnect | `P1` | Membership and Role Control | `needs_tests_only` | `MR-024` |
| `RJ-005` | Notifications resume after rejoin | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-005` |
| `RJ-007` | System event for re-add | `P1` | Re-invite and Rejoin | `needs_code_and_tests` | `RJ-007` |
| `RJ-010` | Re-invite while removed member is offline | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-010` |
| `SC-001` | UI restrictions are not the only restrictions | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-001` |
| `SC-004` | Group key/epoch rotates on removal | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-004` |
| `SC-005` | Group key/epoch updates correctly on re-invite | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-005` |
| `SC-007` | Stale client resync | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-007` |
| `SC-010` | Replay protection | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-010` |
| `SC-011` | Post-removal store-and-forward cut-off | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-011` |
| `SC-012` | Membership change ordering vs in-flight messages | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-012` |
| `SC-015` | Membership and role events are authenticated | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-015` |
| `SC-017` | Duplicate membership or role event is idempotent | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-017` |
| `SC-018` | Older membership or role event cannot roll back newer state | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-018` |
| `UX-001` | New member history policy | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-001` |
| `UX-005` | Unread count correctness | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-005` |
| `UX-006` | Long text / emoji / RTL / special characters | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-006` |
| `UX-007` | Large message or attachment | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-007` |
| `UX-010` | Member list consistency after reconnect | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-010` |

## Row traceability rule

- Every source row maps to exactly one session id, and every session id preserves the source row id verbatim.
- No row in this artifact was merged into a seam bucket, and no row was dropped or hidden behind a broader prerequisite session.
- Later closure work must report final truth per source row, not only per broad subsystem or family-level seam.

## Session ledger

| Session ID | Source row | Priority | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- | --- |
| `MR-014` | `MR-014` | `P0` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-014-plan.md` | none | `stale/already-covered` |
| `MR-015` | `MR-015` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-015-plan.md` | none | `accepted` |
| `MR-020` | `MR-020` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-020-plan.md` | none | `accepted` |
| `SC-001` | `SC-001` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-001-plan.md` | none | `accepted` |
| `SC-004` | `SC-004` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-004-plan.md` | none | `accepted` |
| `SC-005` | `SC-005` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-005-plan.md` | none | `accepted` |
| `SC-007` | `SC-007` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-007-plan.md` | none | `accepted` |
| `SC-010` | `SC-010` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-010-plan.md` | none | `accepted` |
| `SC-011` | `SC-011` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-011-plan.md` | none | `accepted` |
| `SC-012` | `SC-012` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-012-plan.md` | none | `accepted` |
| `SC-015` | `SC-015` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-015-plan.md` | none | `accepted` |
| `SC-017` | `SC-017` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-017-plan.md` | none | `accepted` |
| `SC-018` | `SC-018` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-018-plan.md` | none | `accepted` |
| `GM-002` | `GM-002` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-002-plan.md` | none | `accepted` |
| `GM-006` | `GM-006` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-006-plan.md` | none | `accepted` |
| `GM-011` | `GM-011` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-011-plan.md` | none | `accepted` |
| `GM-016` | `GM-016` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-016-plan.md` | none | `accepted` |
| `MR-003` | `MR-003` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-003-plan.md` | none | `accepted` |
| `MR-004` | `MR-004` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-004-plan.md` | none | `accepted` |
| `MR-008` | `MR-008` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-008-plan.md` | none | `accepted` |
| `MR-013` | `MR-013` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-013-plan.md` | none | `accepted` |
| `MR-024` | `MR-024` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-024-plan.md` | none | `accepted` |
| `RJ-005` | `RJ-005` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-005-plan.md` | none | `accepted` |
| `RJ-007` | `RJ-007` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-007-plan.md` | none | `accepted` |
| `RJ-010` | `RJ-010` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-010-plan.md` | none | `accepted` |
| `UX-001` | `UX-001` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-001-plan.md` | none | `accepted` |
| `UX-005` | `UX-005` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-005-plan.md` | none | `accepted` |
| `UX-006` | `UX-006` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-006-plan.md` | none | `accepted` |
| `UX-010` | `UX-010` | `P1` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-010-plan.md` | none | `accepted` |
| `UX-007` | `UX-007` | `P2` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-007-plan.md` | none | `accepted` |
| `CLOSURE-001` | n/a | n/a | `closure-only` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-CLOSURE-001-plan.md` | all row-owned sessions that remain runnable | `accepted` |

## Ordered session breakdown

### Session MR-014

- Title:
  `Source row MR-014: Removed while offline`
- Session id:
  `MR-014`
- Source row id:
  `MR-014`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `covered_in_repo`
- Session classification:
  `stale/already-covered`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-014-plan.md`
- Exact scope:
  - preserve the direct proof already listed for source row MR-014 (Removed while offline), keep the row classified as covered, and only reopen it if contradictory evidence appears
- Ownership:
  - `no execution because already covered`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Notes:
  - current matrix note: Closed on 2026-04-04: removal now stores a targeted replay payload for the removed peer, and `drainGroupOfflineInbox()` routes replayed `member_removed` envelopes through `GroupMessageListener`, so reconnecting removed peers hit the same leave-group plus `groupRemovedStream` cleanup path as live self-removal. Direct proof was recorded in `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and `./scripts/run_test_gates.sh groups`.
  - the filtered source matrix already records exact direct proof for this row, so this session should stay closed unless contradictory evidence appears

### Session MR-015

- Title:
  `Source row MR-015: Removed while typing/sending`
- Session id:
  `MR-015`
- Source row id:
  `MR-015`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-015-plan.md`
- Exact scope:
  - define and enforce one repo-owned remove-vs-send cutoff for source row MR-015 (Removed while typing/sending), prove the same sender-specific rule holds for live peers, and update the row to `Closed` only after direct code-and-test evidence lands
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when group removal UI or message delivery wiring changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: the repo now defines one sender-specific cutoff rule, `message.timestamp < persisted member_removed.removedAt`, for the remove-vs-send boundary. The live path persists that cutoff for both remaining peers and the admin/remover, and direct evidence landed in `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`. The row was revalidated with those direct suites plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
  - accepted on `2026-04-05` after follow-on rollout `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md` converted the former ordering prerequisite into one repo-owned cutoff contract and landed the direct row-owned proof listed in the source matrix.

### Session MR-020

- Title:
  `Source row MR-020: At least one admin remains`
- Session id:
  `MR-020`
- Source row id:
  `MR-020`
- Priority:
  `P0`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-020-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row MR-020 (At least one admin remains), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/leave_group_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when group settings or member-action UI changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Open on 2026-04-04: `11-group-discussion-use-case-audit.md` still records that groups can become leaderless if the original admin leaves, and `leave_group_use_case.dart` still leaves unconditionally, so last-admin protection is not currently enforced in the repo-owned product contract.
  - accepted on `2026-04-05` after the bounded local planning, execution, and closure fallbacks landed a sole-admin guard in `lib/features/groups/application/leave_group_use_case.dart`, surfaced the blocked path in `lib/features/groups/presentation/screens/group_info_wired.dart`, and added direct regressions in `test/features/groups/application/leave_group_use_case_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` passed and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.
  - gate classification on `2026-04-05`: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` remains red outside the MR-020 write scope because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen`; neither `integration_test/loading_states_smoke_test.dart` nor `lib/features/share/presentation/screens/share_target_picker_screen.dart` changed in this session.

### Session SC-001

- Title:
  `Source row SC-001: UI restrictions are not the only restrictions`
- Session id:
  `SC-001`
- Source row id:
  `SC-001`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-001-plan.md`
- Exact scope:
  - authenticate the repo-owned inbound add/remove membership-event seam for source row SC-001 (UI restrictions are not the only restrictions), reject raw non-admin bypass traffic, and update the row to `Closed` only after direct code-and-test proof lands
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when group listener authorization rules change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `lib/features/groups/application/group_message_listener.dart` now rejects unauthorized repo-owned membership system events (`member_added`, `members_added`, `member_removed`) unless the sender matches durable local creator/admin facts, so raw non-admin add/remove bypass traffic no longer mutates Flutter-side member state. Direct proof landed in `test/features/groups/application/group_message_listener_test.dart` and the peer-visible raw-bypass regression in `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart` plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. Promotion flows remain outside current repo-owned scope.
  - accepted on `2026-04-05` after follow-on rollout `Test-Flight-Improv/57-authenticated-group-membership-events.md` resolved the former listener-authorization prerequisite and returned the row to direct row-owned closure.

### Session SC-004

- Title:
  `Source row SC-004: Group key/epoch rotates on removal`
- Session id:
  `SC-004`
- Source row id:
  `SC-004`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-004-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row SC-004 (Group key/epoch rotates on removal), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/member_removal_integration_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when removal-boundary ordering or key rotation timing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: `test/features/groups/application/member_removal_integration_test.dart` and `test/features/groups/presentation/group_info_wired_test.dart` prove the remove flow rotates and distributes a new key to the remaining members, but there is still no deterministic removal-boundary test proving the first real post-removal send already uses the rotated epoch.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added a deterministic removal-boundary regression to `test/features/groups/application/member_removal_integration_test.dart` proving that once removal and rotation complete, the first subsequent real send persists and inbox-stores the rotated epoch.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart test/features/groups/application/send_group_message_use_case_test.dart` passed and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.

### Session SC-005

- Title:
  `Source row SC-005: Group key/epoch updates correctly on re-invite`
- Session id:
  `SC-005`
- Source row id:
  `SC-005`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-005-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row SC-005 (Group key/epoch updates correctly on re-invite), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when rejoin bootstrap or key replay changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: the new rejoin smoke proves the rejoined member resumes on key epoch `2`, but that proof still injects the fresh key through the test helper. Invite handling separately proves it persists a supplied key/epoch, so the repo still lacks one deterministic remove->reinvite flow that proves fresh key issuance and no stale credential reuse end to end.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added a deterministic remove -> rotate -> re-invite regression to `test/features/groups/integration/invite_round_trip_test.dart` proving that the invite carries rotated epoch `2`, the rejoined member persists key epoch `2`, and the member's first post-rejoin send also uses epoch `2`.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.

### Session SC-007

- Title:
  `Source row SC-007: Stale client resync`
- Session id:
  `SC-007`
- Source row id:
  `SC-007`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-007-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row SC-007 (Stale client resync), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when startup or resume replay ordering changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: startup/watchdog rejoin and message catch-up are covered, but rejoin rebuilds from locally cached membership state and the repo still lacks a proof that offline membership/admin changes are replayed before a privileged operation.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added a shared runtime recovery fence around resume/startup rejoin + inbox drain, then made admin-only group actions fail fast while that fence is active so stale cached membership/admin state cannot drive privileged behavior before replay settles.
  - direct proof on `2026-04-05`: `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` now proves a stale admin cannot execute `removeGroupMember(...)` while resume recovery is waiting on a replayed `member_removed` envelope, and that the same recovery finishes by deleting the stale local group state.
  - supporting guard coverage on `2026-04-05`: `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/application/remove_group_member_use_case_test.dart`, and `test/features/groups/application/send_group_message_use_case_test.dart` now cover the admin-only blocked paths while the recovery fence is active.
  - verification on `2026-04-05`: `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`, `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart`, `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` all passed.

### Session SC-010

- Title:
  `Source row SC-010: Replay protection`
- Session id:
  `SC-010`
- Source row id:
  `SC-010`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-010-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row SC-010 (Replay protection), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/core/notifications/app_root_notification_open.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when notification dedupe behavior changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: replay deliveries are deduped and may only enrich sparse metadata on the existing row, but the “no duplicate notification” half is still an inference from listener control flow rather than a dedicated replay-through-notification regression.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added a replay-through-listener notification regression in `test/features/groups/application/group_message_listener_test.dart` instead of widening the seam into route-open or remote-push policy changes.
  - direct proof on `2026-04-05`: replaying the exact same group envelope through `GroupMessageListener.handleReplayEnvelope(...)` leaves both the persisted message count and the shown notification count at `1`.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session SC-011

- Title:
  `Source row SC-011: Post-removal store-and-forward cut-off`
- Session id:
  `SC-011`
- Source row id:
  `SC-011`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-011-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row SC-011 (Post-removal store-and-forward cut-off), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when inbox replay cut-off changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: `MR-014` now closes offline removed-state convergence for the removed peer, but the repo still lacks a direct queued-after-removal inbox-drain regression proving deferred traffic never reaches that removed peer.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added one narrow inbox-drain regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` instead of widening the row into live publish ordering or transport changes.
  - direct proof on `2026-04-05`: replayed self-removal now proves the removed peer's inbox drain stops before later queued messages on the same page or any later cursor page can be persisted locally.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session SC-012

- Title:
  `Source row SC-012: Membership change ordering vs in-flight messages`
- Session id:
  `SC-012`
- Source row id:
  `SC-012`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-012-plan.md`
- Exact scope:
  - extend the same deterministic remove-vs-send cutoff to replay and reconnect for source row SC-012 (Membership change ordering vs in-flight messages), prove convergence across live and resumed peers, and update the row to `Closed` only after direct code-and-test evidence lands
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when replay ordering or listener delivery rules change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: replay and reconnect now honor the same `member_removed.removedAt` cutoff used by the live path instead of reopening the race by arrival timing. Direct evidence landed in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`, which together prove before-cutoff removed-sender traffic still lands while at-or-after-cutoff replay is rejected for both live and resumed remaining peers. The row was revalidated with those direct suites plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
  - accepted on `2026-04-05` after follow-on rollout `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md` replaced the former best-effort prerequisite with one deterministic repo-owned cutoff rule and matching replay proof.

### Session SC-015

- Title:
  `Source row SC-015: Membership and role events are authenticated`
- Session id:
  `SC-015`
- Source row id:
  `SC-015`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-015-plan.md`
- Exact scope:
  - authenticate the current repo-owned membership-event seam for source row SC-015 (Membership and role events are authenticated), accept only authorized add/remove events, and update the row to `Closed` only after direct code-and-test proof lands
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when membership-event authorization rules change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `lib/features/groups/application/group_message_listener.dart` now authenticates the current repo-owned membership-event seam by requiring durable local creator/admin authorization before applying inbound `member_added`, `members_added`, or `member_removed` system messages on both live and replay paths. Direct proof landed in `test/features/groups/application/group_message_listener_test.dart` and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart` plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. Promotion/demotion role-event flows remain outside current repo-owned scope, so this closure is intentionally limited to the landed add/remove membership seam.
  - accepted on `2026-04-05` after follow-on rollout `Test-Flight-Improv/57-authenticated-group-membership-events.md` resolved the former validator/auth prerequisite for the current repo-owned add/remove event seam.

### Session SC-017

- Title:
  `Source row SC-017: Duplicate membership or role event is idempotent`
- Session id:
  `SC-017`
- Source row id:
  `SC-017`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-017-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row SC-017 (Duplicate membership or role event is idempotent), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when badge or list projections change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: member persistence is upsert-like and membership events are not surfaced on `groupMessageStream`, but the repo still lacks a row-owned duplicate membership/role event regression proving one canonical state change and one UI effect.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added duplicate `member_added` and duplicate self-removal regressions in `test/features/groups/application/group_message_listener_test.dart`, which exposed one real repeated self-removal UI effect and closed it with a narrow guard in `lib/features/groups/application/group_message_listener.dart`.
  - direct proof on `2026-04-05`: duplicate `member_added` now leaves one canonical member/admin-role state and no regular UI-stream event, while duplicate self-removal now emits one `groupRemovedStream` signal and one `group:leave` call.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session SC-018

- Title:
  `Source row SC-018: Older membership or role event cannot roll back newer state`
- Session id:
  `SC-018`
- Source row id:
  `SC-018`
- Priority:
  `P0`
- Source section:
  Security, Correctness, and Convergence
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-018-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row SC-018 (Older membership or role event cannot roll back newer state), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when event ordering metadata changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: membership system messages carry no explicit sequence/version metadata, and `group_message_listener.dart` applies them in arrival order, so stale-event rollback prevention is not currently proven and may require new ordering metadata or validator rules.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added a durable `lastMembershipEventAt` watermark on groups, threaded it through `GroupMessageListener`, and used current persisted group/member/key timestamps as the fallback baseline when upgraded rows still have a null watermark.
  - direct proof on `2026-04-05`: `test/features/groups/application/group_message_listener_test.dart` now proves across listener restart that an older `member_removed` cannot roll back a newer added admin state and an older `member_added` cannot revive state after a newer removal.
  - persistence proof on `2026-04-05`: `test/features/groups/domain/repositories/group_repository_impl_test.dart`, `test/core/database/migrations/048_groups_last_membership_event_at_test.dart`, and `test/core/database/integration/full_migration_chain_test.dart` now cover the new groups watermark column and upgrade path.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart test/core/database/migrations/048_groups_last_membership_event_at_test.dart`, `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` all passed.

### Session GM-002

- Title:
  `Source row GM-002: Create/add with offline member bootstrap`
- Session id:
  `GM-002`
- Source row id:
  `GM-002`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-002-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row GM-002 (Create/add with offline member bootstrap), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when reconnect, replay, or ordering logic changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: the repo proves offline invite fallback, invite bootstrap persistence, inbox drain after join, and post-bootstrap participation, but there is still no single offline-add-then-reconnect end-to-end regression that closes this exact row.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added one combined reconnect-bootstrap regression in `test/features/groups/application/group_invite_listener_test.dart` instead of widening the row into runtime bootstrap changes.
  - direct proof on `2026-04-05`: the new row-owned regression now proves invite acceptance on reconnect bootstraps the group, drains missed inbox traffic, and allows the newly joined member to send immediately with invite epoch `1`.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/application/group_invite_listener_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session GM-006

- Title:
  `Source row GM-006: Sequential same-sender ordering`
- Session id:
  `GM-006`
- Source row id:
  `GM-006`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-006-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row GM-006 (Sequential same-sender ordering), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when reconnect, replay, or ordering logic changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: storage and UI ordering are chronological by timestamp and existing smoke coverage observes ordered incoming texts, but `09-network-group-messaging.md` still records ordering as best-effort and the repo lacks one exact same-sender M1->M2 proof for both recipients.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added one narrow three-user ordering regression in `test/features/groups/integration/group_messaging_smoke_test.dart` instead of widening the row into new runtime ordering logic.
  - direct proof on `2026-04-05`: the new row-owned regression now proves that when A sends `M1` and then `M2`, both B and C read the incoming texts in chronological order as `['M1', 'M2']` under the repo's timestamp-based ordering rule.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session GM-011

- Title:
  `Source row GM-011: Notification deep link`
- Session id:
  `GM-011`
- Source row id:
  `GM-011`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-011-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row GM-011 (Notification deep link), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/core/notifications/app_root_notification_open.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/core/notifications/app_root_notification_open_test.dart`
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when notification routing or deep-link anchor state changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: current push-open coverage proves the app routes to the correct group only after targeted group catch-up, but the route model has no message anchor and the repo does not currently prove landing on the relevant message context.
  - accepted on `2026-04-05` after the bounded local plan/execution/closure sequence extended the group notification route contract with an optional message anchor in `lib/core/notifications/notification_route_target.dart`, threaded explicit anchored payloads through `lib/core/notifications/notification_service.dart`, `lib/core/notifications/flutter_notification_service.dart`, `lib/features/push/application/show_notification_use_case.dart`, and `lib/features/groups/application/group_message_listener.dart`, and surfaced highlighted message context via `lib/main.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, and `lib/features/groups/presentation/screens/group_conversation_screen.dart`.
  - direct proof on `2026-04-05`: route-target parsing and payload round-trips, remote and local notification-open routing, fallback notification payload generation, and anchored group-screen highlighting are now directly covered in `test/core/notifications/notification_route_target_test.dart`, `test/core/notifications/notification_route_dispatch_test.dart`, `test/core/notifications/app_root_notification_open_test.dart`, `test/core/notifications/flutter_notification_service_test.dart`, `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/features/push/application/show_notification_use_case_test.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`, and `test/features/groups/presentation/group_conversation_wired_test.dart`.
  - verification on `2026-04-05`: `flutter test --no-pub test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_route_dispatch_test.dart test/core/notifications/app_root_notification_open_test.dart test/core/notifications/flutter_notification_service_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart test/features/groups/presentation/group_conversation_wired_test.dart` passed and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed.
  - gate classification on `2026-04-05`: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` remains red outside the GM-011 write scope because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen`; neither `integration_test/loading_states_smoke_test.dart` nor `lib/features/share/presentation/screens/share_target_picker_screen.dart` changed in this session.

### Session GM-016

- Title:
  `Source row GM-016: Network partition and reconnect`
- Session id:
  `GM-016`
- Source row id:
  `GM-016`
- Priority:
  `P1`
- Source section:
  Core Group Messaging
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-GM-016-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row GM-016 (Network partition and reconnect), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when partition timing, delayed delivery, or replay order changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: the repo proves a temporarily disconnected member drains missed messages and resumes live delivery after rejoin, but there is still no explicit fake-network partition/heal regression with controlled split timing and release order.
  - accepted on `2026-04-05` after the local plan/execution/closure sequence added one narrow fake-network partition-heal regression in `test/features/groups/integration/group_resume_recovery_test.dart` instead of widening the row into new reconnect or replay logic.
  - direct proof on `2026-04-05`: the new row-owned regression unsubscribes one peer during the partition, drives two split-window sends through the bridge-backed group send path, replays the missed backlog through deterministic cursor pages in order, and then proves post-heal live delivery resumes once that peer rejoins.
  - verification on `2026-04-05`: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.
  - gate classification on `2026-04-05`: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` was not required because this session landed test-only proof and did not change production timing, replay, or reconnect code.

### Session MR-003

- Title:
  `Source row MR-003: New member cannot send before bootstrap completes`
- Session id:
  `MR-003`
- Source row id:
  `MR-003`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-003-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row MR-003 (New member cannot send before bootstrap completes), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when membership UI or notification routing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `send_group_message_use_case.dart` now rejects member-role sends while the local group key is still missing instead of falling back to key epoch `0`, and `test/features/groups/integration/group_membership_smoke_test.dart` now proves a newly added member cannot publish before bootstrap key persistence but succeeds immediately after the key arrives. Direct proof landed in `test/features/groups/application/send_group_message_use_case_test.dart` and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added the member-side missing-key guard in `lib/features/groups/application/send_group_message_use_case.dart` instead of widening scope into queued-send or invite transport redesign.
  - direct proof on 2026-04-05: `test/features/groups/application/send_group_message_use_case_test.dart` now proves a member-role send with no local key is rejected before any bridge publish or inbox-store side effect starts, and `test/features/groups/integration/group_membership_smoke_test.dart` proves a newly added member is blocked before bootstrap key persistence but succeeds immediately after the key is saved.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed.

### Session MR-004

- Title:
  `Source row MR-004: Add existing member handled cleanly`
- Session id:
  `MR-004`
- Source row id:
  `MR-004`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-004-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row MR-004 (Add existing member handled cleanly), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when membership UI or notification routing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `add_group_member_use_case.dart` now rejects duplicate peerIds before any repo overwrite or `group:updateConfig` bridge sync starts, and `test/features/groups/presentation/contact_picker_wired_test.dart` now proves a stale selection that becomes duplicate before confirm fails without `group:updateConfig` or `group:publish` (`members_added`) side effects. Direct proof landed in `test/features/groups/application/add_group_member_use_case_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added a duplicate-member guard in `lib/features/groups/application/add_group_member_use_case.dart` instead of widening into invite-flow redesign or new system-message types.
  - direct proof on 2026-04-05: `test/features/groups/application/add_group_member_use_case_test.dart` now proves duplicate adds are rejected before bridge sync and preserve the original member row, `test/features/groups/presentation/contact_picker_wired_test.dart` proves a stale selection that becomes duplicate before confirm shows the failure path without `group:updateConfig` or `group:publish`, and `test/features/groups/integration/group_membership_smoke_test.dart` proves a duplicate re-add leaves the shared member lists unchanged.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` both passed. No baseline gate was required because the session changed the add-member use case plus tests only.

### Session MR-008

- Title:
  `Source row MR-008: Remove non-member handled cleanly`
- Session id:
  `MR-008`
- Source row id:
  `MR-008`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-008-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row MR-008 (Remove non-member handled cleanly), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when membership UI or notification routing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `remove_group_member_use_case.dart` now rejects already absent peerIds before any `group:updateConfig` bridge sync starts, and `group_info_wired.dart` now surfaces the error while refreshing the member list instead of silently swallowing the failure. Direct proof landed in `test/features/groups/application/remove_group_member_use_case_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. A same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` rerun remained red in unrelated share-loading drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside the MR-008 write scope.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added an absent-member guard in `lib/features/groups/application/remove_group_member_use_case.dart` and surfaced the remove failure in `lib/features/groups/presentation/screens/group_info_wired.dart` instead of widening into removal-message redesign.
  - direct proof on 2026-04-05: `test/features/groups/application/remove_group_member_use_case_test.dart` now proves a non-member removal is rejected before bridge sync and preserves the existing members, `test/features/groups/presentation/group_info_wired_test.dart` proves a stale remove action shows the error without `group:updateConfig`, `group:publish`, or `group:inboxStore` side effects, and `test/features/groups/integration/group_membership_smoke_test.dart` proves the absent-member path leaves shared member lists unchanged.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` remained red in unrelated share-loading compile drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside this row's write scope.

### Session MR-013

- Title:
  `Source row MR-013: Remaining members see removal system event`
- Session id:
  `MR-013`
- Source row id:
  `MR-013`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-013-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row MR-013 (Remaining members see removal system event), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when timeline or member-list presentation changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `group_message_listener.dart` now emits a readable synthetic removal entry on the live `groupMessageStream` for remaining members after `member_removed` config convergence, so the existing conversation timeline path can show `Admin removed Charlie` without widening into durable system-message history redesign. Direct proof landed in `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. A same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` rerun remained red in unrelated share-loading compile drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside the MR-013 write scope.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass extended `lib/features/groups/application/group_message_listener.dart` so non-self `member_removed` events emit a readable live timeline message for remaining members instead of staying invisible to the conversation stream.
  - direct proof on 2026-04-05: `test/features/groups/application/group_message_listener_test.dart` now proves the listener emits `Admin removed Sender` on `groupMessageStream`, `test/features/groups/presentation/group_conversation_wired_test.dart` proves the conversation UI renders the live removal timeline event, and `test/features/groups/integration/group_membership_smoke_test.dart` proves a real bystander receives `Admin removed Charlie` while the member list converges to the post-removal state.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`, `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "live removal timeline event from listener appears in UI"`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "remaining member receives readable removal timeline event while member list updates"`, `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` remained red in unrelated share-loading compile drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside this row's write scope.

### Session MR-024

- Title:
  `Source row MR-024: Offline bystander syncs supported membership changes on reconnect`
- Session id:
  `MR-024`
- Source row id:
  `MR-024`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-024-plan.md`
- Exact scope:
  - split unsupported admin-transfer propagation out of source row MR-024 and land the direct offline-bystander reconnect proof for the supported add/remove membership contract before updating the row to `Closed`
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/group_resume_recovery_test.dart` now contains `offline member reconnects after membership churn and converges to the final member list`, which forces Bob offline while Charlie is removed and Diana is added, then proves rejoin plus inbox drain converge the reconnecting bystander onto the exact same final member/admin map and metadata seen by live peers. The row was revalidated with `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` and same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Unsupported promotion/admin-transfer propagation remains outside current repo-owned scope and stays covered by the existing unsupported role-management rows.
  - accepted on `2026-04-05` after follow-on rollout `Test-Flight-Improv/58-offline-group-membership-sync-scope-split.md` separated unsupported admin-transfer propagation from the repo-owned reconnect contract and landed the direct bystander-sync proof.

### Session RJ-005

- Title:
  `Source row RJ-005: Notifications resume after rejoin`
- Session id:
  `RJ-005`
- Source row id:
  `RJ-005`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-005-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row RJ-005 (Notifications resume after rejoin), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when notification routing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/group_membership_smoke_test.dart` now contains a row-owned remove -> message while removed -> re-add -> message after rejoin regression proving the removed member receives no local notification while unsubscribed and starts receiving group notifications again only after rejoin becomes effective. Existing listener notification coverage remains in `test/features/groups/application/group_message_listener_test.dart`, and the row was revalidated with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass widened the `test/shared/fakes/group_test_user.dart` harness only enough to inject the existing notification dependencies, then added one row-owned rejoin notification regression in `test/features/groups/integration/group_membership_smoke_test.dart` instead of changing production notification code.
  - direct proof on 2026-04-05: the new regression proves a removed member gets no notification for `While removed`, is restored to active group state through the current re-add flow, and then gets the expected local group notification for `After rejoin`.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "removed member notifications stay off until rejoin becomes effective"`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` was not rerun because this session changed only test coverage and test helper wiring, not production notification routing or share-loading code.

### Session RJ-007

- Title:
  `Source row RJ-007: System event for re-add`
- Session id:
  `RJ-007`
- Source row id:
  `RJ-007`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-007-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row RJ-007 (System event for re-add), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when visible system-event presentation changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `group_message_listener.dart` now emits a readable synthetic add entry on the live `groupMessageStream` for remaining members after `member_added` config convergence, so the existing conversation timeline path can show `Admin added Charlie` without widening into durable system-message history redesign. Direct proof landed in `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`, revalidated with `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. A same-day `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` rerun remained red in unrelated share-loading compile drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside the RJ-007 write scope.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass extended `lib/features/groups/application/group_message_listener.dart` so non-self `member_added` events emit a readable live timeline message for remaining members instead of staying invisible to the conversation stream.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "duplicate member_added keeps one canonical member state and one UI stream event"`, `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "member_added emits readable timeline event on groupMessageStream"`, `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "live re-add timeline event from listener appears in UI"`, `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "remaining member receives readable re-add timeline event while member list updates"`, `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`, and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` remained red in unrelated share-loading compile drift because `integration_test/loading_states_smoke_test.dart` still passes removed `onContactSelected` arguments to `ShareTargetPickerScreen` outside this row's write scope.

### Session RJ-010

- Title:
  `Source row RJ-010: Re-invite while removed member is offline`
- Session id:
  `RJ-010`
- Source row id:
  `RJ-010`
- Priority:
  `P1`
- Source section:
  Re-invite and Rejoin
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-RJ-010-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row RJ-010 (Re-invite while removed member is offline), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when invite bootstrap or rejoin replay behavior changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/invite_round_trip_test.dart` now contains an exact remove -> rotate -> offline re-invite regression that forces `sendGroupInvite(...)` onto inbox fallback, then later routes that stored invite through `handleIncomingGroupInvite(...)` so the rejoined member restores the current group/member state and resumes `sendGroupMessage(...)` on rotated epoch `2`. The row was revalidated with `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added one exact offline reinvite regression in `test/features/groups/integration/invite_round_trip_test.dart` instead of widening into production invite, replay, or recovery code.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` was not rerun because this session changed only integration test coverage.

### Session UX-001

- Title:
  `Source row UX-001: New member history policy`
- Session id:
  `UX-001`
- Source row id:
  `UX-001`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-001-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row UX-001 (New member history policy), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/invite_round_trip_test.dart` now contains a policy-locking regression that creates a concrete pre-join group message, proves `handleIncomingGroupInvite(...)` bootstraps the new member's group/member/key state without backfilling that earlier history, and then proves a post-join replay envelope persists normally. The row was revalidated with `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added one direct invite/bootstrap history-policy regression in `test/features/groups/integration/invite_round_trip_test.dart` instead of widening into production history-sync changes.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` was not rerun because this session changed only integration test coverage and regression-strategy prose.

### Session UX-005

- Title:
  `Source row UX-005: Unread count correctness`
- Session id:
  `UX-005`
- Source row id:
  `UX-005`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-005-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row UX-005 (Unread count correctness), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when unread or badge projections change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/group_resume_recovery_test.dart` now contains one combined recovery regression proving unread increments to `1` on the first live delivery, stays at `1` when the same message is replayed through inbox drain, rises to `2` only after a failed publish is retried successfully, and clears back to `0` when the group is marked read. The row was revalidated with `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added one combined unread-accounting regression in `test/features/groups/integration/group_resume_recovery_test.dart` instead of widening into badge UI or notification code.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` was not rerun because this session changed only integration test coverage and regression-strategy prose.

### Session UX-006

- Title:
  `Source row UX-006: Long text / emoji / RTL / special characters`
- Session id:
  `UX-006`
- Source row id:
  `UX-006`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-006-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row UX-006 (Long text / emoji / RTL / special characters), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when preview rendering or notification text formatting changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/integration/group_membership_smoke_test.dart` now contains one mixed-content regression that sends a deliberately long payload combining emoji, Arabic/RTL text, and special characters, then proves the receiver stores the exact text unchanged and the paused-app notification preview carries the same body without corruption. The row was revalidated with `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`.
  - accepted on 2026-04-05 after a bounded local plan/execution/closure pass added one mixed-content delivery regression in `test/features/groups/integration/group_membership_smoke_test.dart` instead of widening into new sanitizer or notification code.
  - verification on 2026-04-05: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed. `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` was not rerun because this session changed only integration test coverage and regression-strategy prose.

### Session UX-010

- Title:
  `Source row UX-010: Member list consistency after reconnect`
- Session id:
  `UX-010`
- Source row id:
  `UX-010`
- Priority:
  `P1`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-010-plan.md`
- Exact scope:
  - tighten or add the narrowest direct regression for source row UX-010 (Member list consistency after reconnect), using the current repo behavior already described in the gap matrix, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when multi-peer reconnect ordering changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Notes:
  - current matrix note: Partial on 2026-04-04: member-list convergence after add, remove, and restart exists, but the exact reconnect-after-membership-churn comparison across all peers is still only partially covered.

### Session UX-007

- Title:
  `Source row UX-007: Large message or attachment`
- Session id:
  `UX-007`
- Source row id:
  `UX-007`
- Priority:
  `P2`
- Source section:
  Metadata, Notifications, and Optional Feature Coverage
- Row disposition:
  `needs_tests_only`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-007-plan.md`
- Exact scope:
  - tighten the row-owned proof for source row UX-007 (Large message or attachment), using the current repo behavior already recorded in the settled media-size contract, and update the row to `Closed` or `Covered` only after the exact proof lands
- Ownership:
  - `tests only`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - the media size-limit coverage from `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md` when payload-limit behavior changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- Notes:
  - current matrix note: Closed on 2026-04-05: `test/features/groups/presentation/group_conversation_wired_test.dart` now proves the live group composer overflow dialog, successful compress-under-budget staging, and explicit reject-after-compression cleanup for oversized attachments.

### Session CLOSURE-001

- Title:
  `Final matrix closure refresh and gate classification`
- Session id:
  `CLOSURE-001`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-CLOSURE-001-plan.md`
- Exact scope:
  - refresh the filtered source matrix and this breakdown with final per-row truth after the row-owned sessions finish
  - update gate definitions only when landed work actually changes a frozen gate or direct-suite classification
  - emit the final doc verdict as `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` based on row-owned outcomes
- Ownership:
  - `closure docs only`
- Likely code-entry files:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely direct tests/regressions:
  - rerun the accepted proof batches for the row-owned sessions that changed code or tests
  - rerun `./scripts/run_test_gates.sh groups` when group production code changed
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` when Flutter production code changed
  - `./scripts/run_test_gates.sh completeness-check` only if `Test-Flight-Improv/test-gate-definitions.md` changed
- Dependency on earlier sessions:
  - all row-owned sessions that remain runnable
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - any touched stable closure docs
- Notes:
  - this is the only non-row session in the artifact
  - final closure on `2026-04-05` reconciled the formerly blocked rows `MR-015`, `MR-024`, `SC-001`, `SC-012`, and `SC-015` against the now-closed source matrix and follow-on rollout docs `56`, `57`, and `58`, so the truthful final program verdict is `closed`

## Why this is not fewer sessions

- The user asked for row-by-row ownership, so broad seam buckets would lose traceability and recreate the earlier matrix-to-rollout mismatch.
- This filtered matrix already contains only in-scope unresolved rows; collapsing them would blur which items need proof, which need new code, and which are honestly blocked.
- `CLOSURE-001` is the only non-row session because final matrix truth and gate classification necessarily span the whole rollout.

## Ledger sanity correction

- review date: `2026-04-05`
- correction:
  promoted stale row-owned sessions `MR-015`, `MR-024`, `SC-001`, `SC-012`,
  and `SC-015` from `blocked` to `accepted`, then refreshed `CLOSURE-001` to
  the final truthful doc verdict
- why the correction was required:
  the governing source matrix at
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` and the
  supporting rollout docs `56`, `57`, and `58` now close every remaining
  formerly blocked source row with concrete file-and-test evidence, so the
  earlier `still_open` ledger state was no longer truthful
- additional stale-ledger evidence:
  the original row-plan paths for `MR-015`, `MR-024`, `SC-001`, `SC-012`, and
  `SC-015` were never materialized because those blockers resolved through the
  bounded follow-on rollout artifacts `56-deterministic-remove-vs-send-
  boundary.md`, `57-authenticated-group-membership-events.md`, and
  `58-offline-group-membership-sync-scope-split.md`; those docs plus the
  landed matrix notes are the trustworthy execution contracts for the final row
  closures
- unaffected sessions:
  `MR-014` remains `stale/already-covered`, and every previously accepted
  row-owned session remains truthfully `accepted`

## Current pipeline state

- sessions currently runnable: `0`
- sessions currently blocked: `0`
- sessions currently resolved as `accepted`: `30`
- sessions currently resolved as `stale/already-covered`: `1`
- sessions currently skipped_due_to_dependency: `0`
- next runnable session in order: `none`
- current doc state: `closed`
- trustworthy final program verdict currently persisted: `closed`
- safe-to-continue rationale:
  every source row in the filtered matrix now reads `Closed` or `Covered` with
  concrete evidence, the formerly blocked rows were resolved by follow-on
  rollouts `56`, `57`, and `58`, and no additional gate-definition churn was
  needed for honest whole-doc closure
