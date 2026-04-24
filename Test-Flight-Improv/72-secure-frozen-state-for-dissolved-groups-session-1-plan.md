# Session 1 Plan - Tighten dissolve authority to current-admin-only across local, live, and replay paths

## Final verdict

- `implementation-ready`

## Real scope

- Tighten `group_dissolved` authorization so live and replayed system events
  require a current admin sender instead of accepting the stored creator
  identity by itself.
- Tighten replay handling so system-event sender trust comes from the outer
  transport sender when the decrypted payload also contains a `senderId`.
- Add direct regressions for:
  - former creator / former admin cannot dissolve
  - live listener ignores creator-only dissolve authority after demotion
  - replay drain ignores spoofed system-event payload sender identity
- Keep the already-landed dissolve state, timeline row, send blocking, and
  rejoin skipping unchanged.

## Closure bar

- A local caller can dissolve only when the current repo-owned role state says
  that caller is an admin.
- A live or replayed `group_dissolved` event is applied only when the sender is
  a current admin according to current member state, not because the sender is
  merely the stored creator.
- Replay does not accept a spoofed payload `senderId` when the outer transport
  sender disagrees.
- Existing authorized dissolve flows, idempotent replay, and unauthorized
  non-admin rejection remain intact.

## Source of truth

- Active session contract:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- Governing product/problem docs:
  - `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
  - `Test-Flight-Improv/62-admin-initiated-group-dissolve-session-breakdown.md`
- Regression and gate docs:
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
- Primary code/tests:
  - `lib/features/groups/application/dissolve_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `test/features/groups/application/dissolve_group_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

On disagreement:

- current code and tests beat older prose
- `test-gate-definitions.md` is the source of truth for named gates
- if the local dissolve use case already proves the current-admin rule, do not
  invent extra code there just for symmetry

## Session classification

- `implementation-ready`

## Exact problem statement

- Report `72` identified that dissolve authority is still too broad on the
  listener/replay side: `_isAuthorizedMembershipEventSender(...)` accepts the
  stored creator as inherently authorized, and replay drain forwards
  `payload['senderId']` into system-message handling when present.
- That means a former creator who is no longer an admin can still be treated as
  authorized for `group_dissolved`, and replayed system events can trust a
  decrypted payload sender field more than the outer authenticated sender.
- The local dissolve use case already checks `group.myRole`, so the first step
  is to prove whether that local path already satisfies the current-admin rule
  with a direct regression before changing it.
- The session must improve trust in dissolve authority without reopening the
  broader membership-event model or Report `62`'s already-landed baseline
  dissolve behavior.

## Files and repos to inspect next

- Production:
  - `lib/features/groups/application/dissolve_group_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- Tests:
  - `test/features/groups/application/dissolve_group_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`

## Existing tests covering this area

- `dissolve_group_use_case_test.dart`
  proves happy-path dissolve, non-admin rejection by `group.myRole`, already
  dissolved short-circuit, and inbox-fallback degradation handling.
- `group_message_listener_test.dart`
  proves authorized live/replayed `group_dissolved`, idempotent replay, and
  unauthorized non-admin rejection, but it does not prove creator-demotion
  rejection.
- `drain_group_offline_inbox_use_case_test.dart`
  already proves replay sender mismatch handling for `group_reaction` items,
  but it does not prove that replayed system events ignore spoofed payload
  sender identity.
- `group_membership_smoke_test.dart`
  already proves offline dissolve convergence, but not the former-creator /
  no-longer-admin rejection case.

## Regression/tests to add first

- Add a local use-case regression for "former creator who is no longer admin
  cannot dissolve". If it already passes, leave the use-case code unchanged.
- Add a listener regression that demotes the creator from admin to writer and
  proves live `group_dissolved` is ignored afterward.
- Add a replay-drain regression where the outer `from` sender is unauthorized
  but the decrypted system payload claims an admin `senderId`, and prove the
  dissolve is ignored.

These tests prove the exact trust seam before any implementation change.

## Step-by-step implementation plan

1. Add the three direct regressions above and run them first.
2. If the local use-case regression already passes, keep
   `dissolve_group_use_case.dart` unchanged and document that the local path was
   already owned.
3. Tighten `group_message_listener.dart` so `group_dissolved` requires a
   current admin member rather than accepting `group.createdBy` alone.
4. Tighten `drain_group_offline_inbox_use_case.dart` so replayed system events
   pass the outer transport sender identity into `handleReplayEnvelope(...)`
   instead of trusting `payload['senderId']` when those values differ.
5. Re-run the direct suites and the `groups` gate.
6. If the direct tests show no code change is needed beyond the new
   regressions, stop there rather than broadening into unrelated membership
   auth work.

## Risks and edge cases

- Do not weaken the already-landed creator/admin authorization model for other
  membership events unless the source doc or failing tests prove it necessary.
- Replay envelopes can legitimately omit payload `senderId`; the new logic
  needs a safe fallback when the outer sender is all that exists.
- Idempotent repeat-dissolve handling must remain intact after the auth change.
- Offline drain should still route regular non-system messages and reactions the
  same way after the system-event sender change.

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/groups/application/dissolve_group_use_case_test.dart`
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh groups`

## Known-failure interpretation

- The worktree is already dirty in unrelated notification/push files. Treat
  failures outside the touched group authority seam as pre-existing unless the
  direct group tests or the `groups` gate show a new regression in the touched
  path.
- If the full `groups` gate fails in an untouched unrelated area, record that
  explicitly instead of widening this session.

## Done criteria

- The three new regressions exist and pass.
- Authorized admin dissolve still passes.
- Demoted creator dissolve is rejected on live and replay paths.
- Replay drain no longer trusts spoofed payload sender identity for system
  events.
- The `groups` gate passes, or any unrelated pre-existing failure is documented
  honestly.

## Scope guard

- Do not change reaction behavior in this session.
- Do not change feed projection or local-delete UX in this session.
- Do not redesign all membership-event authorization unless the new regressions
  prove dissolve cannot be fixed narrowly.
- Do not reopen Report `62`'s storage, timeline, send-block, or rejoin-skip
  work.

## Accepted differences / intentionally out of scope

- The local dissolve use case may remain implemented via `group.myRole` if the
  new regression proves that path already enforces the current-admin rule.
- Broader creator/admin auth hardening for non-dissolve membership events stays
  out of scope for this session unless the narrow dissolve fix is impossible
  without it.

## Dependency impact

- Session `2` depends on this session to establish one trustworthy dissolve
  authority contract before reaction-freeze work is accepted.
- If Session `1` expands beyond dissolve-specific auth, the later sessions must
  be refreshed against that broader blast radius before execution.

## Structural blockers remaining

- None at planning time.

## Incremental details intentionally deferred

- Whether `group_membership_smoke_test.dart` also gains a former-creator
  dissolve rejection case can be decided after the direct regressions land.

## Accepted differences intentionally left unchanged

- No extra local-use-case code change if the new regression proves the current
  `group.myRole` check is already sufficient.

## Exact docs/files used as evidence

- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/features/groups/application/dissolve_group_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

## Why the plan is safe to implement now

- The session is narrow, evidence-backed, and grounded in one clear trust seam.
- The first step is red-test proof, so the session can stop before unnecessary
  code changes if the local dissolve path is already correct.
- The required validation is small and direct before the broader `groups` gate.
