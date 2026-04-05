# 56 - Deterministic Remove-vs-Send Boundary Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
- Supporting docs:
  - `Test-Flight-Improv/09-network-group-messaging.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Decomposition date:
  `2026-04-05`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Run Session `1` first, then Session `2`.
- Each session should run through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Do not record a finished doc verdict until both blocking rows for this doc,
  `MR-015` and `SC-012`, tell the same truthful story across code, tests, and
  the touched matrix/architecture docs.

## Recommended plan count

- `2`

## Overall closure bar

Report doc `56` as closed only when all of the following are true at the same
time:

- the repo defines one explicit remove-vs-send boundary rule for group
  membership changes instead of leaving the outcome as best-effort ordering
- the sender-side write path, the remaining-member receive path, and any
  replay or retry path all apply that same boundary rule rather than accepting
  or rejecting messages based only on arrival timing
- a removed member's in-flight or retried send cannot produce ghost local
  success, duplicate delivery, or split-brain peer state after the accepted
  cutoff
- any send that legitimately crosses the accepted cutoff remains durable and is
  not later rolled back inconsistently when membership cleanup or reconnect
  completes
- direct repo-owned tests prove both the live remove-vs-send seam and the
  offline/replay convergence seam
- `Test-Flight-Improv/09-network-group-messaging.md`,
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, and
  `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` are updated so
  `MR-015` and `SC-012` no longer describe the boundary as open or best-effort
- the required named gates and direct suites for the touched seams pass

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`

Current repo facts that govern the split:

- `lib/features/groups/application/send_group_message_use_case.dart`
  pre-persists group sends before publish completes, which is strong adjacent
  durability evidence but not the remove-versus-send cutoff contract itself.
- `test/features/groups/application/send_group_message_use_case_test.dart`
  already proves the pre-persist contract by gating `group:publish`, so it is
  the correct direct regression family for the sender-side race seam.
- `test/features/groups/integration/group_membership_smoke_test.dart` already
  proves the easier post-cleanup case where a removed member can no longer send
  after self-removal has fully settled, but it does not define the exact
  outcome for a message already in flight at the boundary.
- `lib/features/groups/application/remove_group_member_use_case.dart` updates
  local membership and Go validator config, and
  `test/features/groups/application/member_removal_integration_test.dart`
  proves the first remaining-member post-removal send uses the rotated epoch,
  which is adjacent evidence for validator/key state after removal rather than
  proof of the removed-sender cutoff.
- `lib/features/groups/application/group_message_listener.dart` and
  `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  already own the replay and reconnect paths that must converge with whatever
  boundary rule Session `1` chooses.
- `Test-Flight-Improv/09-network-group-messaging.md` still records strict
  ordering as best-effort, and both `MR-015` and `SC-012` remain open in the
  current group matrices, so the repo still lacks one explicit persisted rule
  for this race.

Source-of-truth conflicts that materially affected decomposition:

- the proposal intentionally does not pre-select sender-first,
  remover-first, or epoch-based semantics; Session `1` must choose one rule
  that fits the existing validator/key architecture instead of pretending the
  choice is already made in prose
- current closure docs are allowed to remain narrower than this boundary until
  the implementation lands, so this breakdown keeps final matrix/architecture
  truth updates at the end rather than claiming closure from adjacent evidence
  alone

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Choose and enforce the live remove-vs-send cutoff` | `implementation-ready` | `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-1-plan.md` | none | `completed` | `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md` | Completed on `2026-04-05`: the repo now applies one sender-specific cutoff rule, `message.timestamp < persisted member_removed.removedAt`, on both the remaining-peer listener path and the admin/remover path. Direct regressions landed in `handle_incoming_group_message_use_case_test.dart`, `group_membership_smoke_test.dart`, `group_message_listener_test.dart`, and `group_info_wired_test.dart`; `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh baseline` both passed after the cutoff work landed. |
| `2` | `Prove replay and reconnect convergence for the same cutoff` | `implementation-ready` | `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-2-plan.md` | `1` | `completed` | `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md` | Completed on `2026-04-05`: replay and reconnect now honor the same persisted `member_removed.removedAt` cutoff as the live path. Direct regressions landed in `drain_group_offline_inbox_use_case_test.dart` and `group_resume_recovery_test.dart`, the architecture and matrix docs now close `MR-015` and `SC-012` on that rule, and the named reruns passed with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` after a minimal baseline-harness callback-name fix in `integration_test/loading_states_smoke_test.dart`. |

## Ordered session breakdown

### Session 1

- Title:
  `Choose and enforce the live remove-vs-send cutoff`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-1-plan.md`
- Exact scope:
  - choose one deterministic user-visible cutoff rule for a member send that
    races with removal, based on the current validator/key/membership
    architecture rather than abstract ordering theory
  - make the sender-side and admin-side live path enforce that same cutoff so
    an in-flight send is either accepted or rejected truthfully at one stable
    boundary
  - ensure local optimistic persistence and terminal status semantics stay
    honest around the cutoff instead of leaving a ghost `sent`/`pending` row
    for a now-invalid send
  - add or update the smallest direct regressions needed to pin the chosen
    cutoff in the live path, including a gated or delayed send/removal race
    rather than only the already-settled post-cleanup case
  - update only the doc-scoped breakdown notes needed to record the chosen rule
    and the session result; do not claim whole-doc closure yet
- Why it is its own session:
  - this is the canonical contract-setting seam, and Session `2` cannot
    truthfully validate replay/reconnect behavior until the live cutoff exists
  - the likely code-entry points and direct regression family are concentrated
    around send/remove/validator wiring rather than inbox-drain recovery
  - combining this with the wider replay/reconnect proof would make it harder
    to distinguish a wrong cutoff rule from a later recovery mismatch
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
    if the chosen rule depends on key-epoch promotion timing
  - `lib/features/groups/domain/models/group_model.dart` or related repository
    files only if one persisted cutoff marker is needed for truthful local
    decisions
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/features/groups/application/member_removal_integration_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
    only if one live three-user race proof is needed beyond the unit/integration
    application tests
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline` because shared Flutter production
    group code is expected to change
  - `./scripts/run_test_gates.sh transport` only if the chosen cutoff requires
    startup/resume/reconnect wiring changes instead of staying on the live
    write path
  - `./scripts/run_test_gates.sh 1to1` only if shared bridge/send/retry
    infrastructure outside group-local code is touched
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
  - not yet required:
    - keep `Test-Flight-Improv/09-network-group-messaging.md`
      and the two matrix docs for Session `2`, because the live cutoff alone
      does not finish the replay/reconnect closure bar
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## Finished doc verdict

- Verdict date:
  `2026-04-05`
- Current doc status:
  `closed`
- Stop-policy result:
  `finish_current_doc_before_advancing` satisfied; doc `57` may start
- Closure basis:
  - the repo now defines one explicit remove-vs-send rule for this seam:
    `message.timestamp < persisted member_removed.removedAt`
  - live remaining-peer handling, admin/remover persistence, replay, inbox
    drain, and reconnect all apply that same rule instead of relying on
    arrival timing alone
  - `Test-Flight-Improv/09-network-group-messaging.md`,
    `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`, and
    `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    now tell the same truthful closure story for `MR-015` and `SC-012`
  - direct evidence passed in:
    `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`,
    `test/features/groups/application/group_message_listener_test.dart`,
    `test/features/groups/presentation/group_info_wired_test.dart`,
    `test/features/groups/integration/group_membership_smoke_test.dart`,
    `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
    and `test/features/groups/integration/group_resume_recovery_test.dart`
  - named gates passed with:
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` and
    `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Residual truth outside this doc's scope:
  - strict total ordering across arbitrary concurrent senders still remains
    best-effort outside the explicit removed-sender cutoff
  - membership-event authentication remains open under `SC-015` and was not
    changed by this report

### Session 2

- Title:
  `Prove replay and reconnect convergence for the same cutoff`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-2-plan.md`
- Exact scope:
  - make replayed, queued, retried, or reconnect-delivered traffic honor the
    same cutoff rule chosen in Session `1` instead of reopening the race by
    arrival timing
  - add the smallest direct recovery or fake-network proofs needed to show that
    all peers converge on the same accepted-or-rejected result after offline
    windows, inbox drain, or retry
  - verify the removed sender cannot create ghost duplicates or later
    contradictory local state when a retried or replayed send falls on the
    rejected side of the cutoff
  - update the architecture and matrix docs so `MR-015` and `SC-012` reflect
    the landed boundary rule, the concrete test evidence, and any truthful
    residual note that remains after closure
  - persist the finished doc verdict in this breakdown once the whole doc is
    truly closed or record a real blocker if convergence still fails
- Why it is its own session:
  - replay/reconnect convergence is a different seam from the live write path
    and may require different direct regressions and possibly the transport
    gate
  - Session `1` can land a deterministic live contract without yet proving
    cursor-drain or reconnect behavior, so keeping this proof separate avoids
    overclaiming closure too early
  - this session also owns the truthful matrix/architecture updates, which only
    make sense after both the live and replay paths align
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/rejoin_group_topics_use_case.dart`
    only if reconnect sequencing must change to preserve the cutoff
  - test fake-network helpers under `test/shared/fakes/` only if deterministic
    recovery orchestration needs small harness support
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
    if the final closure proof is easiest to express in the existing three-user
    membership surface
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh transport` if inbox-drain, rejoin, or resume
    sequencing changes
  - `./scripts/run_test_gates.sh 1to1` only if shared recovery/transport
    infrastructure outside groups is touched
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary-session-breakdown.md`
    - `Test-Flight-Improv/09-network-group-messaging.md`
    - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
    - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - conditional:
    - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
      only if the landed cutoff meaningfully changes the maintained closure
      contract rather than staying a matrix/architecture clarification
- Dependency on earlier sessions:
  - Session `1` must finish first because replay/reconnect proof needs the
    canonical live cutoff and its persisted evidence
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
