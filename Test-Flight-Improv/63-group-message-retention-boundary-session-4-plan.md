# 63 Session 4 Plan: Close UX-008 in Maintained Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- update the maintained network and matrix docs so they describe the landed
  repo-owned 7-day group-backlog retention boundary instead of leaving
  `UX-008` contract-undefined
- close `UX-008` with concrete proof references spanning replay filtering,
  mixed-window recovery, and the shipped expired-backlog UI
- remove `UX-008` from the policy-needed and not-fully-implemented trackers
- record the final doc-63 closure verdict after same-day verification is
  attached

Out of scope for this session:

- changing the retention duration or replay rule chosen in sessions `1` to `3`
- relay-server pruning work or new protocol parameters
- max-group-size or same-user multi-device scope, which remain separate open
  rows

### Closure bar

Session `4` is done only when:

- `09-network-group-messaging.md` describes the shipped 7-day replay boundary,
  expired-versus-retained persistence, and truthful mixed-window UX
- the full matrix marks `UX-008` closed with exact repo-local proof references
- the policy-needed and not-fully-implemented trackers no longer list `UX-008`
- the doc-63 breakdown records a final `closed` verdict with same-day
  verification evidence

### Source of truth

- active session contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/63-group-message-retention-boundary.md`
- session `2` replay contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-2-plan.md`
- session `3` UX contract:
  `Test-Flight-Improv/63-group-message-retention-boundary-session-3-plan.md`
- maintained architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- maintained matrix docs:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
  `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`
- retention-policy seam:
  `lib/features/groups/domain/models/group_backlog_retention_policy.dart`

### Exact problem statement

The repo now owns the retention contract in code, tests, and shipped UI, but
the long-lived maintenance docs still describe `UX-008` as contract-undefined.
Session `4` must bring those docs back into sync so future work does not reopen
the row unless the behavior truly regresses.

### Files and repos to inspect next

Docs:

- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`
- `Test-Flight-Improv/63-group-message-retention-boundary-session-breakdown.md`

Verification artifacts:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

### Step-by-step implementation plan

1. Refresh the maintained network architecture note so it states the explicit
   7-day retention boundary, the replay-filtering rule, the persisted expired
   and retained timestamps, and the visible expired-backlog UX.
2. Update the full matrix row for `UX-008` from `Contract-undefined` to
   `Closed`, using the direct replay, resume-recovery, and presentation suites
   as proof.
3. Remove `UX-008` from the policy-needed and not-fully-implemented trackers,
   updating the tracker counts to match.
4. Re-run the targeted replay and presentation suites plus the required named
   gates, then write the final doc-63 breakdown verdict with same-day evidence.

### Risks and edge cases

- do not overclaim server-side pruning; the landed contract is app-owned replay
  filtering plus truthful UX, not guaranteed relay deletion
- keep the docs clear that system envelopes stay exempt from the message
  retention cutoff so membership/removal convergence still works
- avoid implying that all conversation history expires; only older missed relay
  backlog outside the 7-day window does

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_list_screen_test.dart test/features/groups/presentation/group_list_wired_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`

### Done criteria

- maintained docs all agree that `UX-008` is landed repo behavior
- the trackers and full matrix no longer disagree about retention support
- doc `63` records a final closed verdict with same-day verification evidence

### Scope guard

- do not start doc `64` until the doc-63 breakdown records a final close
- do not widen this pass into new retention-product work or adjacent matrix-row
  cleanup beyond `UX-008`
