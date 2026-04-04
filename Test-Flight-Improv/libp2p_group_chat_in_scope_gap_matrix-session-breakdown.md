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
  - `needs_tests_only`: `14`
  - `needs_code_and_tests`: `10`
  - `blocked_by_prerequisite`: `5`
- No shared prerequisite session was added. The blockers in this filtered matrix are real, but they are not uniform enough to justify a seam-level prerequisite bucket without weakening row ownership and traceability.

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
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that materially affected row classification:

- `MR-014` is already recorded as closed in the filtered source matrix with exact direct proof, so it is carried forward here as `covered_in_repo` instead of being reopened.
- `GM-011`, `MR-003`, `MR-004`, `MR-008`, `MR-013`, `MR-020`, `RJ-007`, `SC-007`, `SC-018`, and `UX-007` now read as genuine repo-owned behavior gaps rather than missing-evidence-only rows, so they stay `needs_code_and_tests`.
- `MR-015`, `MR-024`, `SC-001`, `SC-012`, and `SC-015` remain row-owned but `blocked_by_prerequisite` because the current notes still describe missing ordering, authentication, or feature-scope prerequisites that prevent honest row closure today.
- The remaining partial rows are phrased as direct proof gaps with substantial existing behavior already cited, so they stay `needs_tests_only` instead of being downgraded to evidence-only cleanup.
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
| `MR-015` | Removed while typing/sending | `P0` | Membership and Role Control | `blocked_by_prerequisite` | `MR-015` |
| `MR-020` | At least one admin remains | `P0` | Membership and Role Control | `needs_code_and_tests` | `MR-020` |
| `MR-024` | Admin change propagates to offline members | `P1` | Membership and Role Control | `blocked_by_prerequisite` | `MR-024` |
| `RJ-005` | Notifications resume after rejoin | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-005` |
| `RJ-007` | System event for re-add | `P1` | Re-invite and Rejoin | `needs_code_and_tests` | `RJ-007` |
| `RJ-010` | Re-invite while removed member is offline | `P1` | Re-invite and Rejoin | `needs_tests_only` | `RJ-010` |
| `SC-001` | UI restrictions are not the only restrictions | `P0` | Security, Correctness, and Convergence | `blocked_by_prerequisite` | `SC-001` |
| `SC-004` | Group key/epoch rotates on removal | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-004` |
| `SC-005` | Group key/epoch updates correctly on re-invite | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-005` |
| `SC-007` | Stale client resync | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-007` |
| `SC-010` | Replay protection | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-010` |
| `SC-011` | Post-removal store-and-forward cut-off | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-011` |
| `SC-012` | Membership change ordering vs in-flight messages | `P0` | Security, Correctness, and Convergence | `blocked_by_prerequisite` | `SC-012` |
| `SC-015` | Membership and role events are authenticated | `P0` | Security, Correctness, and Convergence | `blocked_by_prerequisite` | `SC-015` |
| `SC-017` | Duplicate membership or role event is idempotent | `P0` | Security, Correctness, and Convergence | `needs_tests_only` | `SC-017` |
| `SC-018` | Older membership or role event cannot roll back newer state | `P0` | Security, Correctness, and Convergence | `needs_code_and_tests` | `SC-018` |
| `UX-001` | New member history policy | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-001` |
| `UX-005` | Unread count correctness | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-005` |
| `UX-006` | Long text / emoji / RTL / special characters | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-006` |
| `UX-007` | Large message or attachment | `P2` | Metadata, Notifications, and Optional Feature Coverage | `needs_code_and_tests` | `UX-007` |
| `UX-010` | Member list consistency after reconnect | `P1` | Metadata, Notifications, and Optional Feature Coverage | `needs_tests_only` | `UX-010` |

## Row traceability rule

- Every source row maps to exactly one session id, and every session id preserves the source row id verbatim.
- No row in this artifact was merged into a seam bucket, and no row was dropped or hidden behind a broader prerequisite session.
- Later closure work must report final truth per source row, not only per broad subsystem or family-level seam.

## Session ledger

| Session ID | Source row | Priority | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- | --- |
| `MR-014` | `MR-014` | `P0` | `stale/already-covered` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-014-plan.md` | none | `stale/already-covered` |
| `MR-015` | `MR-015` | `P0` | `prerequisite-blocked` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-015-plan.md` | none | `blocked` |
| `MR-020` | `MR-020` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-020-plan.md` | none | `accepted` |
| `SC-001` | `SC-001` | `P0` | `prerequisite-blocked` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-001-plan.md` | none | `blocked` |
| `SC-004` | `SC-004` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-004-plan.md` | none | `accepted` |
| `SC-005` | `SC-005` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-005-plan.md` | none | `accepted` |
| `SC-007` | `SC-007` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-007-plan.md` | none | `accepted` |
| `SC-010` | `SC-010` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-010-plan.md` | none | `accepted` |
| `SC-011` | `SC-011` | `P0` | `implementation-ready` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-011-plan.md` | none | `accepted` |
| `SC-012` | `SC-012` | `P0` | `prerequisite-blocked` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-012-plan.md` | none | `blocked` |
| `SC-015` | `SC-015` | `P0` | `prerequisite-blocked` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-015-plan.md` | none | `blocked` |
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
| `MR-024` | `MR-024` | `P1` | `prerequisite-blocked` | `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-024-plan.md` | none | `blocked` |
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
  `blocked_by_prerequisite`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-015-plan.md`
- Exact scope:
  - do not claim closure for source row MR-015 (Removed while typing/sending) until the missing prerequisite is resolved; either land the prerequisite within repo scope or split the row truthfully before opening row-owned proof
- Ownership:
  - `code changes and tests after prerequisite closure`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when removal ordering or replay timing changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Open on 2026-04-04: the repo now proves post-removal send rejection after cleanup and separately proves sends are pre-persisted before publish completes, and that direct evidence was revalidated in `test/features/groups/integration/group_membership_smoke_test.dart` plus the pre-persist contract case in `test/features/groups/application/send_group_message_use_case_test.dart`, but `09-network-group-messaging.md` still records ordering as best-effort, so the remove-vs-send boundary remains an explicit open ordering gap rather than covered behavior.
  - blocking prerequisite: the current note still treats the remove-vs-send boundary as a best-effort ordering problem rather than a closed rule with direct proof

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
  `blocked_by_prerequisite`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-001-plan.md`
- Exact scope:
  - do not claim closure for source row SC-001 (UI restrictions are not the only restrictions) until the missing prerequisite is resolved; either land the prerequisite within repo scope or split the row truthfully before opening row-owned proof
- Ownership:
  - `code changes and tests after prerequisite closure`
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
  - direct injected-event or fake-network proof once validator or auth logic exists
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: local Flutter tests cover UI/use-case admin gating for add/remove, but inbound membership system messages are still applied without sender-role authentication in `group_message_listener.dart`, so raw bypass resistance is not closed at the repo-owned layer. Promotion flows are also not current repo-owned scope.
  - blocking prerequisite: the repo still accepts inbound membership changes without sender-role validation, and the row also names promote flows that are not currently repo-owned

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
  `blocked_by_prerequisite`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-012-plan.md`
- Exact scope:
  - do not claim closure for source row SC-012 (Membership change ordering vs in-flight messages) until the missing prerequisite is resolved; either land the prerequisite within repo scope or split the row truthfully before opening row-owned proof
- Ownership:
  - `code changes and tests after prerequisite closure`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when boundary ordering rules change
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: `Test-Flight-Improv/09-network-group-messaging.md` still records ordering as best-effort, and `MR-015` remains an explicit remove-vs-send ordering gap, so in-flight membership/message boundary behavior is not currently closed.
  - blocking prerequisite: the expected result depends on a defined ordering or epoch rule, but the current architecture note still records this boundary as best-effort

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
  `blocked_by_prerequisite`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-SC-015-plan.md`
- Exact scope:
  - do not claim closure for source row SC-015 (Membership and role events are authenticated) until the missing prerequisite is resolved; either land the prerequisite within repo scope or split the row truthfully before opening row-owned proof
- Ownership:
  - `code changes and tests after prerequisite closure`
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
  - direct signed-event or validator proof once authenticated event support exists
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Notes:
  - current matrix note: Open on 2026-04-04: `lib/features/groups/application/group_message_listener.dart` applies `member_added` and `member_removed` system messages without verifying sender admin authority, so this row still depends on future signed-event or validator enforcement and is not closed by current local tests.
  - blocking prerequisite: authenticated membership event validation still depends on signed-event or validator enforcement that is not yet present in this repo

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
  - current matrix note: Open on 2026-04-04: the repo proves sends work after bootstrap and fail when the group is absent, but there is still no explicit bootstrap-complete gate and `sendGroupMessage` falls back to key epoch `0` when no key is present.

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
  - current matrix note: Partial on 2026-04-04: `ContactPickerWired` excludes existing members from the add flow and the direct add-member use case upserts duplicate peerIds into one member row, but the repo does not yet prove a clear no-op/error outcome or duplicate system-event suppression for this row.

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
  - current matrix note: Partial on 2026-04-04: the remove-member use case appears tolerant of an already absent member because it snapshots the target and rebuilds config from remaining members, but there is still no direct non-member-remove regression and no asserted user-facing no-op/error contract.

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
  - current matrix note: Partial on 2026-04-04: the repo broadcasts and processes `member_removed` config events so remaining members converge on the updated membership state, but system messages are explicitly not surfaced on the UI message stream, so a visible `A removed C` timeline event is not proven.

### Session MR-024

- Title:
  `Source row MR-024: Admin change propagates to offline members`
- Session id:
  `MR-024`
- Source row id:
  `MR-024`
- Priority:
  `P1`
- Source section:
  Membership and Role Control
- Row disposition:
  `blocked_by_prerequisite`
- Session classification:
  `prerequisite-blocked`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-MR-024-plan.md`
- Exact scope:
  - do not claim closure for source row MR-024 (Admin change propagates to offline members) until the missing prerequisite is resolved; either land the prerequisite within repo scope or split the row truthfully before opening row-owned proof
- Ownership:
  - `code changes and tests after prerequisite closure`
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` when offline catch-up or replay ordering changes
- Dependency on earlier sessions:
  - none
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- Notes:
  - current matrix note: Open on 2026-04-04: `MR-014` now closes offline self-removal catch-up for the removed peer, but this row still lacks repo proof that an offline bystander reconnects with the latest member/admin list, and the promotion/admin-change half remains out of current scope.
  - blocking prerequisite: the source row still bundles offline bystander sync with promotion or admin-change propagation, and the current note says that promotion or admin-change half remains out of current repo-owned scope

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
  - current matrix note: Partial on 2026-04-04: the repo proves rejoin restores current state and send/receive behavior, and it separately proves incoming group messages can raise notifications, but there is still no exact regression showing notifications stay off while removed and resume only after rejoin becomes effective.

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
  - current matrix note: Partial on 2026-04-04: the repo broadcasts and consumes re-add config events so membership state converges, but those events are not emitted as user-visible chat or timeline messages, so a visible `A added C` system event is not proven.

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
  - current matrix note: Partial on 2026-04-04: the repo proves re-invites can fall back to inbox, invite bootstrap restores group and key state, and rejoined members regain only allowed post-rejoin access, but there is still no exact offline-during-re-add then reconnect-later end-to-end regression.

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
  - current matrix note: Partial on 2026-04-04: current behavior implies future-from-membership plus post-join inbox replay, but the repo still lacks one direct row-owned policy test that pins new-member history semantics explicitly.

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
  - current matrix note: Partial on 2026-04-04: unread counting and message deduplication are both covered, but the repo still lacks one row-owned regression proving unread counters stay correct across duplicate, retry, and reconnect flows end to end.

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
  - current matrix note: Partial on 2026-04-04: bidi sanitization and mixed RTL/LTR preview rendering are covered, but the repo still lacks one direct end-to-end row proof for long text, emoji, and special-character behavior together.

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
  `needs_code_and_tests`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-UX-007-plan.md`
- Exact scope:
  - implement the missing repo-owned behavior for source row UX-007 (Large message or attachment), land the narrowest direct regression that proves it, and update the row to `Closed` or `Covered` only after both code and tests land
- Ownership:
  - `code changes and tests`
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
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
  - current matrix note: Partial on 2026-04-04: attachments and durable failed-media recovery are real and tested, but the repo does not yet prove a large-payload or explicit size-limit contract for this row.

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
  - rows that remain `prerequisite-blocked` keep the final verdict at `still_open` unless the source matrix itself is truthfully updated

## Why this is not fewer sessions

- The user asked for row-by-row ownership, so broad seam buckets would lose traceability and recreate the earlier matrix-to-rollout mismatch.
- This filtered matrix already contains only in-scope unresolved rows; collapsing them would blur which items need proof, which need new code, and which are honestly blocked.
- `CLOSURE-001` is the only non-row session because final matrix truth and gate classification necessarily span the whole rollout.
