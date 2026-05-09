# Group Invitation Status Regression Coverage Plan Session Breakdown

Decomposition artifact updated: 2026-05-09

Source doc: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

Downstream workflow rule: detailed planning happens one session at a time. Later work inside the session must be refreshed against landed code before execution, especially before the simulator proof because runner availability and simulator IDs are environment-dependent.

## Run Mode Snapshot

- Refreshed: 2026-05-09.
- Active mode: `standard`.
- Degraded local continuation explicitly allowed: no.
- Source proposal/matrix/closure doc: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`.
- Source status vocabulary: source doc status `accepted_with_explicit_follow_up`; session classification `evidence-gated`; session ledger statuses `pending`, `accepted`, `accepted_with_explicit_follow_up`, `stale/already-covered`, `skipped_due_to_dependency`, `blocked`, `prerequisite-blocked`.
- Overall closure bar: stale re-invite regression, accepted-member `Joined` preservation, six-label deterministic host/widget matrix, four-iOS-simulator creator-side Group Info Members proof or truthful actionable simulator failure evidence, and discoverability updates in `_current-test-map.md`, `test-gate-definitions.md`, or relevant simulator docs.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; do not overclaim four-simulator proof if the live simulator/fixture check or runner command is unavailable.
- Initial dirty snapshot before session processing: `M Test-Flight-Improv/_current-test-map.md`; `M lib/features/groups/presentation/screens/group_info_wired.dart`; `M pubspec.yaml`; `M test/features/groups/presentation/group_info_wired_test.dart`; untracked source/breakdown docs and `Test-Flight-Improv/93-group-system-push-preview-sanitization-plan.md`.
- Live device availability check before planning: `flutter devices --machine` listed four booted supported iOS simulators: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`; `xcrun simctl list devices available` also listed those IDs as booted.

## Controller Progress

- 2026-05-09: Controller refreshed run-mode snapshot, recorded the initial dirty worktree, and verified four booted supported iOS simulators before spawning the session planner.

## Closure Progress

- 2026-05-09: Closure Auditor started. Files inspected since last update: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`, `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/test-gate-definitions.md`, and `git status --short`. Decision/blocker: session execution evidence supports `accepted_with_explicit_follow_up`; source status and breakdown ledger need closure alignment; no product-code edits are needed for closure. Next action: write the narrow closure doc updates.
- 2026-05-09: Closure Writer completed. Files inspected or touched since last update: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`, `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-breakdown.md`, `Test-Flight-Improv/_current-test-map.md`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: source doc now records `accepted_with_explicit_follow_up`, passed gates, seeded simulator classification, and residual-only relay/testpeer follow-up; the breakdown ledger records the session status without writing a final program verdict. Next action: review the doc diff for overclaiming, stale wording, and accidental scope expansion.
- 2026-05-09: Closure Reviewer completed. Files inspected or touched since last update: closure diff for the source doc and breakdown, `git status --short`, and `git diff --check`. Decision/blocker: no blocking closure issues found; historical planning wording and the breakdown source-status snapshot were tightened; `git diff --check` passed; closure docs avoid claiming real relay/testpeer lifecycle proof and keep the only follow-up non-blocking. Next action: return session closure result to the outer pipeline without writing a final program verdict.

## Recommended Plan Count

Recommended plan count: `1`

The source doc already classifies this as one `evidence-gated` implementation session with three internal stages:

1. Host regressions.
2. Production stale join overlay fix.
3. Four-simulator display proof.

This breakdown preserves that shape. The host tests, production fix, simulator runner, and documentation update all protect the same user-visible outcome: the creator's Group Info Members list must show current invite status labels instead of stale `Joined` evidence.

## Overall Closure Bar

The rollout is complete when:

- A stale re-invite regression proves an old `member_joined` event no longer makes a newly re-invited pending member display `Joined`.
- Accepted members with current join evidence still display `Joined`, including the existing missing-attempt-row fallback.
- One deterministic host/widget test covers the six visible labels: `Invite sent`, `Invite queued`, `Needs resend`, `Cannot send`, `Joined`, and `Invite unknown`.
- A four-iOS-simulator runner can prove creator-side Group Info Members UI for accepted and failed or unaccepted invitees, or fail with actionable logs and screenshots.
- `Test-Flight-Improv/_current-test-map.md`, `Test-Flight-Improv/test-gate-definitions.md`, or the relevant simulator discovery docs point future maintainers to the new direct tests and simulator runner.

## Source Of Truth

Primary source doc:

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`

Regression and gate docs:

- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`

Likely production files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_info_screen.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`

Likely tests and harnesses:

- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `integration_test/group_multi_device_real_harness.dart`

Evidence collected:

- `GroupInfoWired` currently overlays durable `member_joined` timeline state onto invite delivery statuses by calling `getLatestSystemEventTimestampForTarget(..., eventType: 'member_joined', targetId: member.peerId)`.
- `GroupInviteDeliveryAttempt` exposes `attemptedAt` and `updatedAt`, which can support comparison between current invite attempts and older join evidence.
- `GroupMessageRepository.getLatestSystemEventTimestampForTarget` supports deterministic system-event timestamp lookup by event type and target ID, so the stale-join fix can inspect `member_removed` evidence if needed.
- Existing widget coverage already proves durable accepted-member `Joined` fallback behavior and badge rendering, but the source doc identifies missing stale re-invite and full-label matrix coverage.
- `./scripts/run_test_gates.sh groups` is the named group gate for group send, receive, retry, resume, invite, and membership behavior.
- `_current-test-map.md` already names `test/features/groups/presentation/group_info_wired_test.dart` as the direct suite for admin Members invite-status display, accepted-member `Joined` rendering, and durable `member_joined` overlay behavior.

## Session Ledger

| Session ID | Title | Classification | Plan File | Depends On | Status | Execution Verdict | Closure Docs Touched | Simulator Classification | Non-Blocking Follow-Up |
|---|---|---|---|---|---|---|---|---|---|
| `01` | Group invitation status stale re-invite coverage, fix, and four-simulator proof | `evidence-gated` | `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up`; QA found no blocking issues; required host, group, diff, and four-simulator commands passed | Updated this breakdown and `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`; verified existing `_current-test-map.md` and `test-gate-definitions.md` invite-status entries | Passed as seeded creator-side `GroupInfoWired` Members invite-status display proof on four requested simulators; `relayLifecycleProof: false`; real relay/testpeer lifecycle proof is not claimed | Separate real relay/testpeer lifecycle invite proof only if a future acceptance bar requires organic multi-device invite acceptance instead of seeded display proof |

## Ordered Session Breakdown

### Session `01`: Group Invitation Status Stale Re-Invite Coverage, Fix, And Four-Simulator Proof

Session classification: `evidence-gated`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md`

Dependency on earlier sessions: none.

Exact scope:

- Add the stale re-invite regression in `test/features/groups/presentation/group_info_wired_test.dart` before the production fix.
- Add or preserve coverage proving accepted members with valid current join evidence still render `Joined`.
- Add one deterministic host/widget status matrix for `sent`, `queued`, `needsResend`, `cannotSend`, `joined`, and missing/unknown status.
- Narrowly update production status loading so stale durable `member_joined` timeline evidence does not override a newer current invite attempt or a later removal/re-invite cycle.
- Add a four-simulator runner and harness, likely adjacent to `integration_test/scripts/run_group_multi_device_real.dart` and `integration_test/group_multi_device_real_harness.dart`, to prove the real creator UI displays expected Members labels for accepted and failed or unaccepted invitees.
- Update the existing test map, gate definitions, or simulator discovery documentation so the new direct tests and runner remain findable.

Internal stage order:

1. Host regressions: create the stale re-invite failing test first, then add the full label matrix.
2. Production fix: make the `GroupInfoWired` overlay trust durable join evidence only when it is current relative to removal evidence and the current invite attempt.
3. Four-simulator display proof: add a new four-device runner or harness path, then document and run it when four simulator IDs are available.

Why it is its own session:

- The host regression, production fix, and simulator proof all validate the same Group Info invite-status contract.
- Splitting the simulator proof into a separate plan would leave the rollout half-closed even though the source doc's closure bar requires it.
- The session is evidence-gated, not implementation-ready only, because the final simulator proof depends on four available iOS simulator IDs and may need a new runner.

Likely code-entry files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` if a new runner is added.
- `integration_test/group_invite_status_matrix_harness.dart` if a new harness is added.

Likely direct tests/regressions:

```bash
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/presentation/group_info_screen_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
```

Likely named gates:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Simulator proof command:

```bash
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart \
  -d <creator_sim>,<accepted_one_sim>,<accepted_two_sim>,<pending_or_failed_sim>
```

If the runner is registered with existing reliability simulation scripts or another named simulator gate, run and document that command during implementation.

Matrix/closure docs to update when done:

- `Test-Flight-Improv/_current-test-map.md`
- `Test-Flight-Improv/test-gate-definitions.md` if the new runner or direct suite needs classification.
- `Test-Flight-Improv/50-two-simulator-user-journey-tests.md` or `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md` only if implementation intentionally extends the simulator journey catalog.

## Why This Is Not Fewer Sessions

The minimum safe count is already one. There is no smaller downstream plan count that can preserve the required execution handoff.

## Why This Is Not More Sessions

More sessions would create bookkeeping overhead without improving verification:

- The stale re-invite regression and production overlay fix need to land together because the regression should fail before the fix and pass after it.
- The full status matrix protects the same display mapping and belongs beside the stale overlay regression.
- The four-simulator proof is acceptance evidence for the same user-visible creator-side Members UI, not a separate product feature.
- Documentation updates are closure work for this exact coverage addition and should not become a standalone plan.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` applies this way:

- Add a permanent regression for the escaped production risk before changing production behavior.
- Run the direct suite containing the bug fix.
- Run the relevant subsystem gate because the work touches group invite and membership display behavior.
- Keep device-backed simulator proof explicit and environment-gated rather than silently widening the normal host gate.

`Test-Flight-Improv/test-gate-definitions.md` applies this way:

- `./scripts/run_test_gates.sh groups` is required because the Group Messaging Gate covers group invite and membership behavior.
- New direct host tests remain focused in `test/features/groups/presentation/group_info_wired_test.dart` unless implementation evidence proves another suite is required.
- New simulator coverage should be classified as optional/manual, nightly/release, or a named simulator gate entry during closure rather than being left undiscoverable.

Minimum expected command set:

```bash
flutter test test/features/groups/presentation/group_info_wired_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
./scripts/run_test_gates.sh groups
git diff --check
dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart \
  -d <creator_sim>,<accepted_one_sim>,<accepted_two_sim>,<pending_or_failed_sim>
```

`test/features/groups/presentation/group_info_screen_test.dart` should also run directly if badge rendering code changes.

## Matrix Update Contract

The single session owns all closure documentation for this source doc.

Required update targets after implementation:

- Update `Test-Flight-Improv/_current-test-map.md` so the direct invite-status display tests and simulator runner are findable from the Groups area.
- Update `Test-Flight-Improv/test-gate-definitions.md` if a new runner or direct suite needs formal classification.

Conditional update targets:

- Update the two-simulator journey docs only if the implementation intentionally adds this four-simulator proof to that manual journey catalog.

## Downstream Execution Path

Session `01` should next go through:

1. `$implementation-plan-orchestrator` using `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md`.
2. `$implementation-execution-qa-orchestrator` after the plan is accepted.
3. `$implementation-closure-audit-orchestrator` after implementation and verification evidence are available.

The downstream planner must keep the three internal stages in order and must not create shared generic session plan paths.

## Structural Blockers Remaining

None for decomposition.

Execution remains evidence-gated by simulator availability. That is an execution constraint, not a decomposition blocker.

## Accepted Differences Intentionally Left Unchanged

- The full enum display matrix may be proven with host/widget coverage.
- The four-simulator proof should prove real accepted-member lifecycle and creator-side display, but it does not need to organically force every possible failed-delivery state through real networking when deterministic seeded rows provide stronger display regression evidence.
- Transport retry, inbox durability, key repair, push notification behavior, and group media delivery stay out of scope unless implementation evidence shows they directly affect invite status display.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/_current-test-map.md`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

- It matches the source doc's explicit single-session classification instead of inventing sibling or generic sessions.
- It uses a doc-scoped, non-colliding intended plan path.
- It preserves the required regression-first order while keeping simulator proof and closure documentation in the same verified rollout.
- It names the direct host tests, group gate, diff check, simulator command, and documentation targets needed for later execution.

## Final Program Verdict

Verdict: `accepted_with_explicit_follow_up`

Ledger sanity summary:

- Recommended plan count is `1`; the session ledger contains exactly session `01`.
- Session `01` is resolved as `accepted_with_explicit_follow_up`; by the runnable-session definition, no runnable sessions remain.
- The source doc and session plan both record `accepted_with_explicit_follow_up`, matching the session ledger.

Gate and simulator evidence summary:

- Required host gates are recorded as passed: `flutter test test/features/groups/presentation/group_info_wired_test.dart`, `flutter test test/features/groups/application/group_message_listener_test.dart`, `./scripts/run_test_gates.sh groups`, and `git diff --check`.
- The four-simulator command is recorded as passed for seeded creator-side `GroupInfoWired` Members invite-status display on the requested simulator IDs.
- The simulator proof intentionally reports `relayLifecycleProof: false`; real relay/testpeer lifecycle proof is not claimed.

Docs updated summary:

- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan.md` records the closure status, passed gates, seeded simulator classification, and residual follow-up.
- `Test-Flight-Improv/_current-test-map.md` and `Test-Flight-Improv/test-gate-definitions.md` make the direct invite-status coverage and four-simulator runner discoverable without widening named gates.
- `Test-Flight-Improv/Group-Chat-Feature/group-invitation-status-regression-coverage-plan-session-01-plan.md` records the final execution verdict and QA result.

Residual/non-blocking follow-up summary:

- The only remaining item is a separate real relay/testpeer lifecycle invite proof if a future acceptance bar requires organic multi-device invite acceptance instead of seeded display proof.
- That follow-up is explicitly non-blocking for this rollout.
