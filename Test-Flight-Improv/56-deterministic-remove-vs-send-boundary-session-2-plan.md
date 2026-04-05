# 56 Session 2 Plan: Prove Replay and Reconnect Convergence for the Same Cutoff

## Final verdict

`implementation-ready`

## Real scope

- Prove that replayed or inbox-drained removed-sender traffic uses the same
  sender-specific cutoff from Session `1`: accept only when
  `message.timestamp < persisted member_removed.removedAt`.
- Add the smallest direct recovery regressions needed to show that a remaining
  peer who missed the live removal still converges on the same before-cutoff
  versus at-or-after-cutoff result after inbox drain and resume.
- Update the architecture note and the two group matrices so `MR-015` and
  `SC-012` reflect the landed cutoff rule and the new recovery evidence.
- Keep this session scoped to replay/reconnect proof and doc truth. Do not
  redesign relay storage or group transport policy.

## Closure bar

Session `2` is good enough only when all of the following are true:

- inbox-drained membership replays persist the same sender-specific removal
  cutoff that the live path now uses
- a replayed removed-sender message from before the cutoff still lands for a
  remaining peer who missed the live removal
- a replayed removed-sender message at or after the cutoff is rejected for
  that same remaining peer, including across cursor/page boundaries when
  applicable
- the direct recovery evidence is strong enough to say replay/reconnect no
  longer reopens the remove-vs-send race by arrival timing
- `Test-Flight-Improv/09-network-group-messaging.md`,
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, and
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` all tell the
  same truthful story about the landed cutoff rule and evidence

## Source of truth

- Active task docs:
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
  - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
- Governing architecture and matrices:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Regression and gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Landed Session `1` code that now defines the cutoff:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/group_membership_timeline_message.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`

On disagreement, landed code and passing recovery tests beat stale prose.

## Exact problem statement

Session `1` defined the cutoff and proved it in the live path. What is still
missing is direct replay/reconnect evidence for a remaining peer that missed the
live removal. The repo needs proof that inbox drain replays the same removal
cutoff marker and that later queued removed-sender traffic is accepted or
rejected by the same timestamp rule rather than by whichever envelope happens to
arrive first after resume.

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Direct tests:
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Closure docs:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`

## Existing tests covering this area

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  already proves replayed self-removal stops later queued traffic for the
  removed peer, but it does not yet prove the remaining-peer before/after
  cutoff split for removed-sender chat rows.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  already proves offline self-removal cleanup and broader membership churn
  convergence, but it does not yet pin the exact removed-sender cutoff for an
  offline remaining peer after resume.
- `test/features/groups/integration/group_membership_smoke_test.dart`
  already proves the live path boundary and can remain as the live reference
  while this session adds the replay proof.

## Regression/tests to add first

- Add one drain-level regression in
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  where a remaining peer drains:
  - a replayed `member_removed` envelope carrying `removedAt`
  - one removed-sender message from before the cutoff
  - one removed-sender message at or after the cutoff
  - at least one case crossing a cursor/page boundary so the persisted cutoff
    survives later-page processing
- Add one integration regression in
  `test/features/groups/integration/group_resume_recovery_test.dart` where a
  remaining peer misses the live removal, rejoins, drains replayed backlog, and
  converges on the same before-cutoff accept / at-or-after-cutoff reject result
  as the live path

## Step-by-step implementation plan

1. Reuse the Session `1` `removedAt` cutoff rule exactly as landed. Do not
   invent a second replay-only ordering rule.
2. Add the drain-level regression first so the inbox-drain seam is pinned at
   the smallest unit/integration boundary.
3. Add the remaining-peer resume integration proof using the cursor bridge and
   fake network helpers already in the repo.
4. Only if one of those regressions fails, patch the replay path so the
   persisted removal marker is available before later removed-sender traffic is
   processed.
5. Update the architecture note and both matrices to replace the stale
   best-effort/open wording with the landed cutoff rule and concrete evidence.
6. Re-run the direct recovery tests plus the required named gates.
7. Write the finished doc verdict back into the breakdown once code, tests, and
   docs agree.

## Risks and edge cases

- If a replay envelope omits `removedAt`, the repo still falls back to the
  envelope timestamp; the new tests should keep using explicit `removedAt` so
  the deterministic rule is what is being proved.
- Replay pages may deliver an older accepted message after the removal envelope;
  that message must still land when its own timestamp is strictly before the
  cutoff.
- Later cursor pages must not reopen the race once the cutoff is persisted from
  an earlier page.

## Exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`

## Known-failure interpretation

- Treat failures in the new drain/resume regressions as session blockers.
- Treat unrelated dirty-worktree failures as blockers only if they intersect the
  replay/remove boundary seam touched here.
- If a named gate fails in an unrelated pre-existing area, record the command
  and failing seam truthfully instead of claiming the gate passed.

## Done criteria

- replay/drain evidence proves the same `removedAt` cutoff used by the live path
- the new direct tests pass
- `groups` and `baseline` are rerun and either pass or are recorded truthfully
  as unrelated blockers
- the three closure docs and the breakdown all tell the same final story

## Scope guard

- Do not widen into new relay fan-out behavior for offline remaining peers
  unless the new replay proofs show the current path cannot be validated
  honestly without it.
- Do not redesign key rotation, transport retries, or sender receipts.
- Do not reopen Session `1` live-path semantics unless the new recovery tests
  demonstrate a real contradiction.
