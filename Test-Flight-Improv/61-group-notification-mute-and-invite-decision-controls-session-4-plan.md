# 61 Session 4 Plan: Close Matrix Rows and Refresh Maintained Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- tighten any last direct proof needed to close `UX-004` and `UX-012`
  honestly, especially around visible expired-invite state
- update the maintained audit, network, and matrix docs so they stop calling
  per-group mute and explicit invite decision flows unsupported
- persist the final doc-61 closure verdict once the maintained docs match the
  landed code and test truth

Out of scope for this session:

- new feature expansion beyond the already landed mute and invite-decision
  contract
- doc `62` group-dissolve work, which stays blocked until this doc is closed

### Closure bar

Session `4` is done only when:

- `UX-004` and `UX-012` can be marked closed with repo-local proof references
  instead of unsupported notes
- the audit summary no longer lists mute or invite expiry as missing features
- the unsupported-features tracker removes `UX-004` and `UX-012`
- the doc-61 breakdown records a final closed verdict with same-day evidence

### Source of truth

- active session contract:
  `Test-Flight-Improv/61-group-notification-mute-and-invite-decision-controls-session-breakdown.md`
- maintained audit:
  `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- network architecture notes:
  `Test-Flight-Improv/09-network-group-messaging.md`
- full matrix:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- unsupported tracker:
  `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`

### Exact problem statement

The code and tests now own per-group mute and explicit invite decisions, but
the maintained docs still describe those rows as unsupported. Session `4` must
bring the long-lived docs back into sync and record the final closure verdict
for doc `61`.

### Files and repos to inspect next

Production and proof files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/decline_pending_group_invite_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`

Direct tests:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
- `test/features/groups/presentation/group_list_screen_test.dart`
- `test/features/groups/presentation/group_list_wired_test.dart`

### Step-by-step implementation plan

1. Add any missing row-closing regression needed to show expired invite state
   is both invalid and visible in the shipped review surface.
2. Refresh the maintained audit and network docs so mute and explicit invite
   decisions are described as landed behavior with concrete proof references.
3. Update the full matrix rows for `UX-004` and `UX-012` from unsupported to
   closed, and remove those rows from the unsupported-only tracker.
4. Re-run the direct tests touched in this session and persist the final
   breakdown verdict for doc `61`.

### Risks and edge cases

- do not overclaim unsupported scenarios such as admin-initiated dissolve or
  same-user multi-device convergence
- keep the matrix notes specific about what is actually covered: mute delivery
  suppression, explicit pending storage, accept, decline, and expiry cleanup
- avoid drifting the audit summary into a generic changelog; only fix the rows
  that changed truth

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `flutter test test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
- `flutter test test/features/groups/presentation/group_list_screen_test.dart`
- `flutter test test/features/groups/presentation/group_list_wired_test.dart`

Required named gates:

- reuse the same-day passing `./scripts/run_test_gates.sh groups` evidence if
  only docs or row-closing tests change

### Done criteria

- the maintained docs all agree that `UX-004` and `UX-012` are landed
- doc `61` can record a final `closed` verdict with explicit proof references

### Scope guard

- do not start doc `62` until the doc-61 breakdown records a final close
- do not widen this pass into unrelated matrix cleanup
