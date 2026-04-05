# 66 - Event-Driven Group Continuity Sweep Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/66-event-driven-group-continuity-sweep.md`
- Decomposition date:
  `2026-04-05`

## Downstream execution path

- detailed planning happens one session at a time
- later sessions must be refreshed against landed code before execution

## Recommended plan count

- `3`

## Overall closure bar

Report `66` closed only when the repo owns one explicit retrier-side recovery
contract for `needsGroupRecovery` instead of relying on the next periodic tick:

- a `false -> true` `needsGroupRecovery` edge while online triggers immediate
  retrier-owned group recovery rather than waiting for the next timer
- the existing 30-second group continuity timer remains present and unchanged
  as the fallback path
- the existing 5-minute full retry timer remains present and unchanged
- any successful retrier-owned `nodeRequestedRecovery` rejoin sends
  `group:acknowledgeRecovery`, regardless of whether the trigger was the new
  immediate edge, the 30-second continuity timer, or the 5-minute full retry
- failed retrier-owned rejoins never send the ack
- regression coverage proves the immediate trigger, the ack/no-ack rules, and
  the unchanged fallback timer behavior without widening into adaptive timer
  policy, Go discovery-loop work, or inbox cursor optimization

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/66-event-driven-group-continuity-sweep.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Current repo facts that govern the split:

- `PendingMessageRetrier` already owns the 30-second group continuity timer and
  the 5-minute full retry timer, so this rollout must preserve those timers
  rather than replacing them
- the retrier already evaluates `needsGroupRecovery` indirectly through the
  `rejoinGroupTopicsFn` wiring, but it has no immediate forward path from the
  relay-state edge
- the retrier currently has no `group:acknowledgeRecovery` path, while
  `handleAppResumed` already acks successful `nodeRequestedRecovery` rejoins
- the highest-risk code seams are `pending_message_retrier.dart`,
  `main.dart` retrier wiring, and the existing unit suite in
  `test/core/services/pending_message_retrier_test.dart`
- the named regression gate for this area is still `./scripts/run_test_gates.sh groups`

Source-of-truth conflicts that materially affected decomposition:

- the source doc names two related gaps, immediate trigger and missing ack;
  the breakdown keeps them as separate sessions so the timer-preservation
  contract and the retrier-owned ack contract can be verified independently
- the source doc is explicit that the 30-second and 5-minute timers stay
  unchanged; any adaptive backoff or cadence rework is therefore out of scope

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Trigger immediate retrier-owned group recovery on the online false-to-true edge` | `implementation-ready` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`, `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-1-plan.md` | Accepted with the online `needsGroupRecovery` edge trigger in `pending_message_retrier.dart` and focused regressions proving the immediate path plus unchanged 30-second fallback cadence. |
| `2` | `Acknowledge all successful retrier-owned nodeRequestedRecovery rejoins` | `implementation-ready` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`, `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-2-plan.md` | Accepted with retrier-owned ack eligibility plus `main.dart` wiring so successful `nodeRequestedRecovery` rejoins ack on immediate and retry-sweep paths while failed rejoins do not. |
| `3` | `Run final verification and persist the doc-66 closure verdict` | `closure-only` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`, `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-3-plan.md` | Accepted after the focused doc-66 regressions and the named `groups` gate both passed without widening scope. |

## Pipeline progress

- `2026-04-05`: Reusable doc-66 breakdown artifact created via bounded local
  decomposition fallback after the isolated decomposition agent left no
  doc-owned artifact inside the first bounded wait. Session `1` is the first
  runnable session.
- `2026-04-05`: The isolated pipeline controller left no doc-66 plan, ledger,
  or code progress under the first bounded wait, so the rollout entered the
  single allowed local pipeline fallback for the remaining session loop.
- `2026-04-05`: Session `1` accepted. `PendingMessageRetrier` now triggers an
  immediate retrier-owned continuity sweep on an online
  `needsGroupRecovery` `false -> true` edge without changing the existing
  30-second fallback timer or the existing 5-minute retry timer.
- `2026-04-05`: Session `2` accepted. Retrier-owned successful
  `nodeRequestedRecovery` rejoins now send `group:acknowledgeRecovery` on the
  immediate and retry-sweep paths, while failed rejoins still skip the ack.
- `2026-04-05`: Session `3` accepted after
  `flutter test test/core/services/pending_message_retrier_test.dart test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  and `./scripts/run_test_gates.sh groups` both passed.

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-05`
- Completion summary:
  - decomposition finished through bounded local fallback after the isolated
    decomposition agent left no reusable artifact
  - pipeline execution finished through bounded local fallback after the
    isolated pipeline controller left no doc-66 progress under the first
    bounded wait
  - session `1` accepted with immediate online-edge recovery plus unchanged
    30-second and 5-minute fallback timers
  - session `2` accepted with retrier-owned ack coverage for successful
    `nodeRequestedRecovery` rejoins and no ack on failed rejoin
  - session `3` accepted with focused regressions and the named `groups` gate
    both passing
  - scope guard held: no adaptive timer backoff, no Go discovery-loop changes,
    and no inbox cursor optimization

## Ordered session breakdown

### Session 1

- Title:
  `Trigger immediate retrier-owned group recovery on the online false-to-true edge`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-1-plan.md`
- Exact scope:
  - extend `PendingMessageRetrier`'s state-listener handling so an online
    `needsGroupRecovery` `false -> true` edge can trigger immediate
    retrier-owned group recovery instead of waiting for the next scheduled tick
  - preserve the existing 30-second group continuity timer unchanged as the
    fallback path
  - preserve the existing 5-minute full retry timer unchanged
  - keep the new immediate trigger behind the current retrier guards:
    online-only, feature-enabled, not already sweeping, not already retrying,
    and not while external recovery is active
  - add focused regression coverage for the immediate trigger and the unchanged
    fallback timer cadence/behavior
- Why it is its own session:
  - the event-driven trigger is the core behavioral gap identified by the
    source doc and can be verified without yet changing the retrier ack
    contract
  - separating timer-preservation work from the ack work reduces the risk of
    hiding timer regressions inside broader bridge/wiring changes
- Likely code-entry files:
  - `lib/core/services/pending_message_retrier.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `lib/core/services/p2p_service_impl.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 2

- Title:
  `Acknowledge all successful retrier-owned nodeRequestedRecovery rejoins`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-2-plan.md`
- Exact scope:
  - make retrier-owned `nodeRequestedRecovery` rejoins send
    `group:acknowledgeRecovery` after any successful rejoin, regardless of
    whether the trigger came from the new immediate edge, the 30-second
    continuity sweep, or the 5-minute full retry
  - keep `group:acknowledgeRecovery` absent when rejoin fails or when no
    `nodeRequestedRecovery` work occurred
  - add or adjust the bridge/callback wiring needed so the retrier can own the
    ack call without changing `handleAppResumed` semantics
  - add regression coverage for ack after successful retrier-owned recovery,
    no ack on failed rejoin, and the successful-ack path inside the existing
    fallback timers
- Why it is its own session:
  - this is a distinct retrier-to-bridge contract change that touches
    constructor/wiring seams in addition to retry flow logic
  - separating it from the immediate-trigger slice keeps the ack contract
    honest across all retrier-owned recovery entry points, not only the new
    edge-triggered path
- Likely code-entry files:
  - `lib/core/services/pending_message_retrier.dart`
  - `lib/main.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Run final verification and persist the doc-66 closure verdict`
- Session id:
  `3`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-3-plan.md`
- Exact scope:
  - rerun the focused retrier regression suite and the required named gate
  - refresh the doc-66 breakdown ledger with the final accepted-session status
    and persisted program verdict
  - confirm the rollout stayed within the explicit scope guard: no timer
    backoff changes, no Go discovery-loop work, no inbox cursor optimization
- Why it is its own session:
  - the proposal closes on code-plus-proof rather than broader maintained-doc
    churn, so the final pass should stay narrowly focused on honest closure
  - keeping closure separate prevents the execution sessions from silently
    claiming success without the required same-day verification record
- Likely code-entry files:
  - `Test-Flight-Improv/66-event-driven-group-continuity-sweep-session-breakdown.md`
  - `test/core/services/pending_message_retrier_test.dart`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
