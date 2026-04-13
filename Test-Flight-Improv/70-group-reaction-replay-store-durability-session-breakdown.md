# 70 - Group Reaction Replay Store Durability Session Breakdown

## Decomposition Artifact

- Artifact path:
  `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/70-group-reaction-replay-store-durability.md`
- Decomposition date:
  `2026-04-13`

## Downstream Execution Path

- reuse the existing doc-scoped session plan when safe
- execute the session with
  `$implementation-execution-qa-orchestrator`
- close the session with `$implementation-closure-audit-orchestrator`
- persist the final program verdict in this breakdown artifact

## Recommended Plan Count

- `3`

## Overall Closure Bar

Report `70` is closed only when sender-side group reaction add/remove
durability no longer depends on best-effort replay storage and the repo owns
one truthful recovery path for offline members:

- if live reaction publish succeeds but replay storage fails, the app persists
  enough sender-owned state to retry later instead of silently losing offline
  convergence
- the shipped retry owner replays both reaction adds and removes without
  duplicate or stale final state for later reconnecting members
- existing live reaction behavior for online peers remains immediate and
  truthful
- existing receive-side sender binding, announcement/member reaction
  permissions, and replay dedupe stay intact
- the maintained group audit, matrix, and test inventory stop carrying this gap
  as residual best-effort behavior once code and tests prove the owned
  recovery path

## Source Of Truth

Primary governing docs:

- `Test-Flight-Improv/70-group-reaction-replay-store-durability.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Accepted repo facts after execution:

- `sendGroupReaction(...)` and `removeGroupReaction(...)` now stage an exact
  encrypted reaction replay payload in a durable outbox row before the first
  `group:inboxStore` attempt
- the durable outbox row transitions to `stored` on immediate success and to
  `failed` on immediate store failure; later retry logic only loads retryable
  rows, so keeping successful rows is a truthful accepted difference rather
  than an open bug
- `retryFailedGroupInboxStores(...)` now owns both the existing failed
  group-message inbox store lane and the new reaction replay retry lane, while
  preserving message-first ordering
- `main.dart` passes the reaction replay outbox repository into the shipped
  resume and pending-retrier callbacks instead of inventing a second lifecycle
  owner
- `announcement_happy_path_test.dart` now proves the announcement-reader
  reaction path also leaves a durable replay row that ends `stored`
- `group_resume_recovery_test.dart` now proves offline add and later remove
  replay-store failures still converge to the final removed state after
  resume-triggered retry
- the maintained audit, matrix, and inventory docs now describe this seam as a
  landed sender-owned recovery path instead of a residual best-effort gap

## Session Ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Persist a durable sender-owned reaction replay retry contract for add/remove` | `implementation-ready` | `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-breakdown.md`, `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-1-plan.md` | Landed migration `054`, helper/model/repository seams, and exact-payload staging in `sendGroupReaction(...)` plus `removeGroupReaction(...)`. Immediate success now marks rows `stored`; failed store attempts leave `failed` rows for later retry. |
| `2` | `Ship retry/resume orchestration and offline convergence proof for missed reaction replays` | `implementation-ready` | `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-breakdown.md`, `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-2-plan.md` | Reused `retryFailedGroupInboxStores(...)` as the shared owner, wired it through `main.dart`, fixed the related `startup_router.dart` typed-seam regression, and added announcement plus resume-convergence proof. |
| `3` | `Close the maintained group docs and residual notes for Report 70` | `closure-only` | `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`, `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-breakdown.md`, `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-3-plan.md` | Closed the maintained docs after the code and tests proved one owned sender-side replay recovery contract for reaction add/remove. |

## Pipeline Progress

- `2026-04-13`: Reusable doc-70 breakdown and session-1 plan artifacts were
  created via bounded local fallback after the spawned controller path did not
  leave trustworthy doc-owned artifacts.
- `2026-04-13`: Session `1` was accepted after landing the
  `group_reaction_replay_outbox` migration, helper, model, repository, fake,
  and the exact-payload send/remove staging contract, then passing the direct
  migration and use-case suites plus `./scripts/run_test_gates.sh groups` and
  `./scripts/run_test_gates.sh baseline`.
- `2026-04-13`: Session `2` was accepted after extending
  `retryFailedGroupInboxStores(...)` to drain reaction replay rows after
  message rows, threading the outbox repository through `main.dart` resume and
  pending-retrier callbacks, removing the stray
  `groupReactionReplayOutboxRepository` argument from the share-target route
  path in `startup_router.dart`, and passing the focused lifecycle suites plus
  the same-day `groups`, `baseline`, and
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  rerun.
- `2026-04-13`: Session `3` was accepted after refreshing the maintained group
  audit, matrix, and inventory docs so they stop describing sender-side
  reaction replay durability as a residual best-effort gap and instead cite the
  landed Report `70` evidence.

## Final Program Verdict

- Status:
  `closed`
- Last updated:
  `2026-04-13`
- Why:
  - sender-owned reaction add/remove replay no longer ends as silent best-effort
    loss when the initial `group:inboxStore` call fails
  - the shipped retry owner now replays failed reaction add/remove store work
    during resume and pending recovery without reopening message ordering or
    dedupe regressions
  - the maintained docs now match the landed code and regression evidence

## Closure Outcome

### What Is Now Closed

- Session `1` is accepted: the repo now owns a dedicated durable outbox for
  sender-side reaction replay add/remove attempts.
- Session `2` is accepted: the shipped retry lane now converges failed reaction
  replay add/remove storage during resume and pending recovery, and the
  integration proof covers the final removed-state case.
- Session `3` is accepted: the maintained audit, matrix, and inventory docs no
  longer describe Report `70` as a best-effort durability gap.

### Residual-Only Items

- None for Report `70`. Broader group reaction UX work such as participant
  inspection or other audit rows remains outside this rollout.

### Accepted Differences

- Successful immediate reaction replay storage leaves a `stored` outbox row
  rather than deleting it. Retry loaders ignore non-retryable rows, so this is
  an intentional persistence choice rather than an open correctness gap.
- Session `2` reused the existing `retryFailedGroupInboxStores(...)` owner
  rather than adding a second reaction-specific lifecycle use case.

## Ordered Session Breakdown

### Session 1

- Title:
  `Persist a durable sender-owned reaction replay retry contract for add/remove`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-1-plan.md`
- Accepted scope:
  - add the `group_reaction_replay_outbox` table plus helper/model/repository
    seams
  - persist exact encrypted replay payloads for reaction add/remove before the
    first `group:inboxStore` attempt
  - mark immediate success `stored` and immediate failure `failed` while
    preserving live publish and local reaction truth
- Verification:
  - `flutter test test/features/groups/application/send_group_reaction_use_case_test.dart`
  - `flutter test test/features/groups/application/remove_group_reaction_use_case_test.dart`
  - `flutter test test/core/database/migrations/054_group_reaction_replay_outbox_test.dart`
  - `flutter test test/core/database/integration/full_migration_chain_test.dart`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`

### Session 2

- Title:
  `Ship retry/resume orchestration and offline convergence proof for missed reaction replays`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-2-plan.md`
- Accepted scope:
  - extend `retryFailedGroupInboxStores(...)` so it drains retryable reaction
    replay rows after message rows and updates them to `stored` or `failed`
  - pass `reactionReplayOutboxRepo` through the shipped pending-retrier and
    resume callbacks in `main.dart`
  - tighten the announcement and resume convergence proof for reaction
    add/remove retry behavior
- Verification:
  - `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
  - `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "resume retry replays failed reaction add/remove stores and converges to the final removed state"`
  - `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
  - `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
  - `flutter test test/core/services/pending_message_retrier_test.dart`
  - `flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart`
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh baseline`
  - `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`

### Session 3

- Title:
  `Close the maintained group docs and residual notes for Report 70`
- Session id:
  `3`
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/70-group-reaction-replay-store-durability-session-3-plan.md`
- Accepted scope:
  - remove the residual best-effort wording from the maintained group audit,
    matrix, and test inventory
  - refresh `RX-006` and `RY-016` notes so they cite the new sender-owned
    reaction replay durability evidence without overclaiming beyond the landed
    contract
  - persist the final closed verdict for Report `70`
- Verification:
  - closure reuses the same-day code and test evidence from Sessions `1` and
    `2`
