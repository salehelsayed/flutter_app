# 34 - Orbit Intros Swipe Delete Missing Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing.md`
- Decomposition date:
  `2026-03-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Recommended plan count

- `1`
- The smallest safe split is one live Orbit intro delete session. The repo
  already has the hard-delete repository primitive, the confirmation dialog,
  the delete action button, and the one-open-row swipe pattern. What is
  missing is one bounded live Orbit intro UI and wiring slice plus the direct
  regressions that prove it.

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Plan file state | Local fallbacks used | Final execution verdict | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | Live Orbit intro swipe-delete affordance, confirmation, and count truth | `implementation-ready` | `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-1-plan.md` | none | `accepted` | `materialized 2026-03-31; reused as the accepted execution contract after the spawned planning step no-progressed` | `planning / execution / closure` | `accepted` | `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`, `Test-Flight-Improv/00-INDEX.md` | Accepted on `2026-03-31` after landing the live Orbit intro delete callback/wiring, delete-only swipe affordance, confirmation flow, grouped-list and empty-state cleanup, route-return pending-intro refresh reuse, and direct regressions, then verifying the direct Orbit intro suites plus `./scripts/run_test_gates.sh baseline`. No separate persistence or protocol follow-up session was needed. |

## Overall closure bar

Report `34` is closed only when the current live `Orbit > Intros` surface
honestly exposes the already-intended delete behavior without widening into a
new intro protocol, loader, or navigation architecture:

- a visible intro row on the live Orbit Intros screen can be swiped left to
  reveal a delete affordance
- only one live intro row can stay open at a time, and short or vertical drags
  preserve normal scroll behavior
- tapping delete presents a clear confirmation step before destructive action
- confirming deletion removes the intro from the current grouped list, drops
  now-empty introducer headers, and reaches the `No introductions yet` empty
  state when appropriate
- the live Orbit intro count and persistent-nav Orbit badge stay truthful after
  deletion, including when the pending row was contributing to the count
- existing accept, pass, blocked/unavailable, send-message, friend-swipe, and
  group-swipe behavior stay intact
- the work remains local to the current Orbit intro seam; no P2P delete
  signaling, DB schema change, or widened intro-status product scope is added

## Final program acceptance

- Closure verdict:
  `closed`
- Acceptance date:
  `2026-03-31`
- What is now closed:
  - live `Orbit > Intros` rows now support the intended swipe-left delete
    affordance using the existing one-open-row Orbit contract
  - tapping delete now reuses the existing Orbit confirmation dialog before
    destructive action
  - confirming delete removes the intro from the grouped list, drops
    now-empty introducer headers, reaches the empty state when appropriate,
    and keeps `projection.introsCount` / the persistent-nav Orbit badge
    truthful
  - the route-return refresh flag is now reused for the delete path so shared
    Feed/Orbit hosts do not keep stale pending-intro truth after leaving Orbit
  - accept, pass, send-message, friend-swipe, and group-swipe behavior stayed
    intact under the landed regressions
  - the direct Orbit intro suites and companion `baseline` gate passed on the
    accepted repo state
- Residual-only items:
  - none
- Still-open items:
  - none
- Reopen only on real regression:
  - if live Orbit intro rows stop revealing the delete affordance or the
    one-open-row contract regresses
  - if the confirmation/delete path stops removing rows, cleaning up
    now-empty introducer sections, or reaching the empty state honestly
  - if `projection.introsCount` or persistent-nav Orbit badge truth stops
    refreshing after local intro deletion
  - if accept, pass, send-message, friend-swipe, or group-swipe behavior
    regresses while touching this seam

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing.md`
- `Test-Flight-Improv/25-delete-intro-swipe.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
- `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`

Current repo facts that govern the closed seam:

- `lib/features/orbit/presentation/screens/orbit_screen.dart` now threads
  `OrbitIntrosViewData.onDelete` into the live intro list and wraps those rows
  in `SwipeableFriendRow` so the current Orbit one-open-row contract is reused
  for delete-only intro actions without changing friend/group row ownership.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` now owns
  `_onDeleteIntro` alongside the existing accept/pass handlers and the
  route-return `_refreshPendingIntroductionsOnPop` seam, so delete reuses the
  current intro-count and shared-host freshness path instead of inventing a
  new controller.
- `lib/features/introduction/presentation/widgets/intro_row.dart` still
  remains row-content/status UI only; the landed delete affordance stays in
  the Orbit wrapper seam rather than widening intro-row responsibilities.
- `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart` now
  supports delete-only active rows while preserving the bounded left-reveal
  plus one-open-row contract used elsewhere on Orbit.
- `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart` already
  exposes `DeleteActionButton`.
- `lib/features/orbit/presentation/widgets/confirmation_dialog.dart` already
  exposes the destructive confirmation dialog used elsewhere in Orbit.
- `lib/features/introduction/domain/repositories/introduction_repository.dart`,
  `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`,
  `lib/core/database/helpers/introductions_db_helpers.dart`, and
  `test/shared/fakes/in_memory_introduction_repository.dart` already implement
  hard delete and pending-count behavior; no new persistence contract is
  needed.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`,
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`,
  `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`,
  `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`,
  `test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`,
  and `test/features/introduction/presentation/widgets/intro_row_test.dart`
  now anchor the adjacent seam coverage, with the accepted landing adding
  direct proof for live intro delete on the current Orbit path.

Source-of-truth conflicts that materially shaped decomposition:

- Report `25` describes a broader status matrix, but current code wins over
  stale prose: `loadIntroductionsForUser(...)` still surfaces only live rows in
  status `pending` or `already_connected`, so this session targets the live
  rows the app can actually render today rather than reopening loader scope.
- Report `25` discusses a missing delete feature at a time when the repo lacked
  live Orbit wiring. Current repo evidence now shows the delete primitive,
  confirmation dialog, and swipe affordance building blocks already exist, so a
  separate shared persistence session would be artificial.

## Reviewer pass

- Sufficiency:
  `1` session is sufficient.
- Merge candidates:
  none.
- Required splits:
  none.
- Missing tests or named gates:
  none at decomposition time; execution still needs direct live Orbit intro
  delete regressions plus the companion `baseline` gate.
- Meaningful verified state:
  yes. One session can land the live delete affordance, confirmation,
  count/badge truth, and direct regressions without leaving a misleading
  half-state behind.
- Matrix responsibility:
  clear. Reuse this doc-scoped breakdown artifact plus `00-INDEX.md`; do not
  invent a new matrix doc for this seam.
- Minimum safe session set:
  `1`.

## Arbiter outcome

- Structural blockers:
  none.
- Mergeable sessions:
  none.
- Required splits:
  none.
- Accepted differences:
  - delete stays local-only; no P2P or cross-device delete semantics are added
  - the current intro loader is not widened to passed or expired rows
  - confirmation copy, button text, and whether cancel leaves a row visually
    open stay bounded planning-time choices inside the proposal's accepted
    ambiguity
  - friend-row and group-row swipe semantics remain unchanged

## Ordered session breakdown

### Session 1

- Title:
  `Live Orbit intro swipe-delete affordance, confirmation, and count truth`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-1-plan.md`
- Exact scope:
  - thread one delete callback through `OrbitIntrosViewData` and `OrbitWired`
    so the live Orbit intro path can invoke the already-existing repository
    delete primitive
  - add a bounded live intro swipe-to-reveal affordance that preserves the
    current one-open-row contract on Orbit and exposes a delete action for the
    intro rows the live loader currently renders
  - reuse the existing Orbit confirmation dialog before destructive delete
  - refresh live Orbit intro state after deletion so grouped rows, section
    headers, empty state, and `projection.introsCount` stay truthful
  - preserve existing accept, pass, blocked/unavailable, and send-message row
    behavior while adding delete affordance parity for the live intro rows
  - reuse the existing route-return refresh flag so embedded Feed/Orbit hosts
    do not regress pending-intro badge freshness when this delete path returns
    through the current shared-host seam
- Why it is its own session:
  - this is one cohesive user-visible slice on the live Orbit intro surface
  - the delete repository contract is already present, so there is no separate
    shared correctness seam to land first
  - the direct regressions all live in one family: Orbit intro screen behavior,
    Orbit intro wiring truth, and bounded adjacent swipe/dialog helpers
  - the session can land and be verified independently without waiting on any
    other architecture or product-scope work
- Likely code-entry files:
  - `lib/features/orbit/presentation/screens/orbit_screen.dart`
  - `lib/features/orbit/presentation/screens/orbit_wired.dart`
  - `lib/features/introduction/presentation/widgets/intro_row.dart` only if
    the live intro row needs a narrow callback or layout seam to support the
    swipe wrapper cleanly
  - `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart` only
    if execution chooses a bounded reuse or extraction path instead of an
    intro-specific wrapper
  - `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart` only
    if the intro path needs a tiny delete-button contract adjustment
  - `lib/features/orbit/presentation/widgets/confirmation_dialog.dart` only if
    the delete copy or semantics need a bounded extension
  - `lib/features/feed/domain/models/feed_route_changes.dart` only if the
    current route-return flag contract needs a narrow clarification rather than
    simple reuse
- Likely direct tests/regressions:
  - `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
    or a new narrow Orbit-screen intro-delete widget test file if the sliver
    assertions should stay isolated from archived-group coverage
  - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
  - `flutter test test/features/introduction/presentation/widgets/intro_row_test.dart`
    only if row content/status behavior changes
  - `flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
    only if shared swipe mechanics are touched
  - `flutter test test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
    only if confirmation behavior or copy plumbing changes
  - conditional:
    `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
    only if route-return refresh evidence forces a direct Feed-side assertion
    beyond the existing Orbit-owned `projection.introsCount` truth
- Likely named gates:
  - no frozen named gate owns this seam directly
  - run the direct Orbit/introduction suites above
  - run `./scripts/run_test_gates.sh baseline` as the companion top-level
    surface sanity gate
  - do not widen into `feed` unless the implementation materially changes Feed
    surface behavior beyond the existing intro-refresh return contract
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-breakdown.md`
  - `Test-Flight-Improv/00-INDEX.md` only if Session `1` lands and closes
    Report `34` into stable maintenance-time meaning
  - `Test-Flight-Improv/17-roadmap-closure-audit.md` only if the folder-level
    reading order or residual/open summary is intentionally refreshed in the
    same closure pass
- Dependency on earlier sessions:
  - none

## Why This Is Not Fewer Sessions

Zero sessions would leave the user-visible bug intact on the actual live Orbit
screen. Treating regressions or closure notes as informal follow-up would also
be unsafe because this is an escaped production bug: the landing must prove the
delete affordance, confirmation, row removal, section/empty-state cleanup, and
count truth together.

## Why This Is Not More Sessions

Further splitting would mostly create bookkeeping and hallucination bait:

- a separate repository or DB session is unjustified because delete and pending
  count behavior already exist in production and in-memory test repositories
- a separate swipe-mechanics session is unnecessary because the missing
  affordance only matters on the live Orbit intro path, not as a standalone
  reusable platform capability
- a separate Feed or closure-only session would only be justified if execution
  unexpectedly changes the broader Feed intro badge architecture, which current
  evidence does not require

## Regression And Gate Contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies here as a
  direct-regression-first escaped-bug fix: add a permanent regression for the
  live path that failed in production instead of relying on adjacent friend-row
  coverage.
- `Test-Flight-Improv/test-gate-definitions.md` already says no frozen named
  gate owns intro-to-Orbit follow-up wiring directly; maintain safety through
  explicit direct suites plus `baseline`.
- Minimum direct proof for Session `1`:
  - left swipe reveals delete on the live intro row while short or vertical
    drags do not
  - only one intro row can remain open at a time
  - delete confirmation appears before destructive action
  - confirm removes the row, drops empty headers, and reaches the empty state
    when appropriate
  - the Orbit intro badge/count stays truthful after deletion
  - accept, pass, send-message, friend swipe, and group swipe behavior do not
    regress
- Companion named gate:
  - `./scripts/run_test_gates.sh baseline`

## Matrix Update Contract

- No new matrix doc was created for Report `34`.
- This breakdown artifact is now the doc-scoped closure-owner ledger for the
  landed Orbit intro swipe-delete seam.
- Session `1` completed planning, execution, and closure against this
  artifact, and `Test-Flight-Improv/00-INDEX.md` was refreshed with the
  maintenance-time reference.
- `Test-Flight-Improv/17-roadmap-closure-audit.md` was intentionally left
  untouched in this closure pass because the live worktree diff there is
  broader folder-level closure work unrelated to this one-report acceptance.

## Downstream execution path

- Session `1` completed through planning, execution, and closure and is
  `accepted`.
- No executable sessions remain for Report `34`.
- This breakdown is now the maintenance-time closure-owner artifact for
  Report `34`.

## Pipeline run status

- Pipeline controller run date:
  `2026-03-31`
- Planning outcome:
  - the spawned plan step no-progressed under bounded wait, so the controller
    closed that child and created the doc-scoped plan artifact locally at
    `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-1-plan.md`
    without widening scope
- Execution / QA outcome:
  - the spawned execution / QA step also no-progressed under bounded wait, so
    the controller used the accepted doc-scoped plan as source of truth for a
    bounded local implementation and QA pass
  - the accepted landing updated:
    - `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
    - `lib/features/orbit/presentation/screens/orbit_screen.dart`
    - `lib/features/orbit/presentation/screens/orbit_wired.dart`
    - `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
    - `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
    - `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
    - `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  - direct proof run on `2026-03-31`:
    - `flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart`
    - `flutter test test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
    - `flutter test test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
    - `flutter test test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
    - `./scripts/run_test_gates.sh baseline`
- Closure outcome:
  - the spawned closure step did not return a trustworthy Report `34`
    acceptance summary, so the controller applied a bounded local closure
    refresh to this breakdown and `Test-Flight-Improv/00-INDEX.md`
- Final program acceptance verdict:
  `closed`
- Final program blocker:
  none

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- no P2P, relay, or cross-device intro delete sync
- no intro loader widening to passed, expired, or other non-live statuses
- no redesign of friend-row or group-row swipe actions
- no batch delete, undo, or recycle-bin behavior
- no new root-owned Orbit badge controller or broader Feed/Orbit navigation
  architecture work

## Exact docs/files used as evidence

- `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing.md`
- `Test-Flight-Improv/34-orbit-intros-swipe-delete-missing-session-1-plan.md`
- `Test-Flight-Improv/25-delete-intro-swipe.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/17-roadmap-closure-audit.md`
- `Test-Flight-Improv/28-orbit-intro-badge-session-breakdown.md`
- `Test-Flight-Improv/30-swipe-nav-feed-orbit-session-breakdown.md`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/introduction/presentation/widgets/intro_row.dart`
- `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart`
- `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart`
- `lib/features/orbit/presentation/widgets/confirmation_dialog.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`
- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
- `test/features/orbit/presentation/widgets/swipeable_friend_row_test.dart`
- `test/features/orbit/presentation/widgets/confirmation_dialog_test.dart`
- `test/features/introduction/presentation/widgets/intro_row_test.dart`

## Why the breakdown is now safe as the closure reference

The landed work stayed at the minimum safe size: one local Orbit intro
surface/wiring session with no follow-on persistence, protocol, or app-shell
phase required. The accepted breakdown now records the actual bounded fallback
history, the exact files changed, the direct regressions and named gate that
passed, and the reopen-only-on-real-regression bar. Future maintenance can use
this artifact directly instead of reconstructing Report `34` intent from the
proposal alone.
