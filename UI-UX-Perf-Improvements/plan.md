# UI/UX Performance Execution Plan

## Purpose

This file is the execution plan for finishing the remaining `PERF-xx` work in a fresh session with minimal supervision.

Current status:
- `PERF-09` is already implemented locally and must be treated as `implemented, but not yet fully audited / reconciled with the rest of the plan`.
- All other `PERF-xx` items in [`impl-backlog.md`](./impl-backlog.md) remain open unless proven otherwise in the future session.

This plan is designed for multi-agent execution, but one constraint is real:
- this document can define the correct order, file ownership, review gates, and stop conditions
- it cannot by itself force the runtime to spawn sub-agents or create isolated worktrees

Best case:
- the next session discovers the new performance skills and supports isolated agent execution
- several lanes run in parallel
- follow-up review happens after each lane automatically

Fallback case:
- the next session does not discover the new skills, or cannot isolate lanes safely
- the same plan still applies, but fewer lanes should mutate code at the same time

## Non-Negotiable Rules

1. Read [`impl-backlog.md`](./impl-backlog.md) and this file before touching code.
2. Treat `PERF-09` as existing in-progress work, not as untouched backlog.
3. Do not let two mutating agents edit the same file cluster at the same time.
4. Every `PERF-xx` requires a follow-up pass after implementation.
5. Visible UX changes must be validated against the observation routes in [`impl-backlog.md`](./impl-backlog.md).
6. If the session cannot isolate worktrees safely, serialize conflicting lanes instead of forcing parallel edits.

## Is Unattended Execution Possible?

Yes, mostly.

What is realistic:
- a well-instructed future session can execute this plan with limited supervision
- it can run multiple lanes in parallel when the file clusters are disjoint
- it can perform a review and QA pass after each lane
- it can stop only on real blockers instead of requiring constant watch

What is not realistic to guarantee from this file alone:
- automatic sub-agent spawning in every runtime
- conflict-free merges if the future session edits overlapping file clusters without isolation
- perfect conflict handling if the runtime ignores lane ownership or shared-component boundaries

Practical expectation:
- if the runtime supports parallel isolated lanes, wall-clock time should be much lower than the sum of all items
- if it does not, this plan still reduces active supervision by making the sequence and follow-up explicit

## Pre-Flight For The Next Session

The next execution session should do this first, in this exact order.

1. Read this file and [`impl-backlog.md`](./impl-backlog.md).
2. Inspect `git status` and capture the current dirty state.
3. Checkpoint the current `PERF-09` work before any broad parallel execution.
4. Confirm whether the new performance skills are discoverable in the new session.
5. If the skills are not discoverable, follow the routing table in this document manually.
6. Capture a lightweight baseline before new code changes.
7. Create separate worktrees or equivalent isolation per mutating lane if the runtime supports it.
8. Create a running execution log and update it after every lane.

Checkpoint rule for `PERF-09`:
- do not start broad parallel execution against the current dirty feed work unless it has been safely checkpointed first
- a local commit, dedicated branch, or exported patch is acceptable
- the reason is simple: `PERF-09` already touches core Feed files and must not be lost or accidentally mixed with unrelated lanes

## Baseline Strategy

Do not let `PERF-00` become a week-long profiling project. Use a lightweight baseline first, then strict follow-up after each item.

Required initial baseline routes:
- launch app into Feed
- Feed scroll with enough cards to represent a realistic hot path
- open one 1:1 conversation from Feed
- open Orbit and scroll/search
- open one group conversation and receive or simulate incoming activity if possible

Required baseline outputs:
- notes on route-entry delay
- notes on obvious jank during scroll
- notes on typing / recording responsiveness
- screenshots or short video captures for visible loading states

The future session can expand profiling later, but it should not block coding longer than necessary.

## Status Board

| PERF | Status at start of next session | Notes |
| --- | --- | --- |
| PERF-00 | Pending | Use lightweight baseline first, then ongoing QA gates |
| PERF-01 | Pending | Shared component; keep `UserAvatar` API stable if possible |
| PERF-03 | Pending | Can run early in parallel |
| PERF-06 | Pending | Can run early in parallel |
| PERF-07 | Pending | Feed structural refactor; must account for existing `PERF-09` work |
| PERF-08 | Pending | Can run early in parallel |
| PERF-09 | Implemented locally, audit required | Needs audit, tests, and later reconciliation with `PERF-07` |
| PERF-10 | Pending | Depends on `PERF-08` |
| PERF-11 | Pending | Cleanup item; do last |

## Skill Routing

If the next session discovers the new skills, route work like this.

| Work item | Primary skill chain | Secondary support |
| --- | --- | --- |
| PERF-00 | `flutter-ui-performance-profiler` -> `mobile-perf-qa` | `flutter-test-orchestrator` for regression harnesses if needed |
| PERF-01 | `flutter-rendering-optimization` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-03 | `flutter-state-incremental-updates` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-06 | `flutter-state-incremental-updates` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-07 | `flutter-sliver-virtualization` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-08 | `flutter-sliver-virtualization` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-09 | `flutter-state-incremental-updates` -> `flutter-test-orchestrator` -> `mobile-perf-qa` | `flutter-ui-performance-profiler` |
| PERF-10 | `flutter-state-incremental-updates` -> `mobile-perf-qa` | `flutter-test-orchestrator` |
| PERF-11 | `flutter-rendering-optimization` -> `mobile-perf-qa` | `flutter-test-orchestrator` |

Controller rule for the next session:
- if `flutter-ui-performance-orchestrator` is discoverable, use it as the top-level routing skill
- if it is not discoverable, use the table above manually and keep this plan as the source of truth

## Dependency Graph

These rules control the order.

Hard dependencies:
- `PERF-09 audit` must happen before any new Feed lane edits continue
- `PERF-08` must finish before `PERF-10`
- `PERF-11` must happen after the main structural and state lanes

Soft but strongly recommended dependencies:
- `PERF-07` should be completed before final `PERF-09` reconciliation is signed off
- `PERF-01` should land early if it can keep the shared avatar API stable
- `PERF-07` should settle before `PERF-11` touches Feed-specific layout cleanup
- `PERF-08` should settle before `PERF-11` touches Orbit or intro list cleanup

Parallel-safe early lane candidates:
- `PERF-01`
- `PERF-03`
- `PERF-06`
- `PERF-08`
- `PERF-00` baseline and `PERF-09` audit as read-mostly setup work

Parallel-safe later lane candidates:
- `PERF-10` can run in parallel with non-Feed lanes once `PERF-08` is done
- follow-up QA agents can run in parallel with unrelated implementation lanes

Do not run these together in the same worktree without isolation:
- any two Feed items among `PERF-07`, `PERF-09`, `PERF-11`
- any two Orbit items among `PERF-08`, `PERF-10`, `PERF-11`
- `PERF-01` if it requires a breaking `UserAvatar` API change and other lanes have already started

## Lane Ownership

Use one mutating agent per lane.

### Lane A: QA / Baseline

Ownership:
- profiling notes
- route captures
- review checklists
- final pass / fail record

This lane should not perform broad product refactors.

### Lane B: Shared Avatar

Ownership:
- `lib/features/home/presentation/widgets/user_avatar.dart`
- any shared avatar cache or resolver introduced for `PERF-01`

Constraint:
- keep the public API stable if possible so this lane does not conflict with Feed, Orbit, Conversation, or Settings lanes

### Lane C: Conversation

Ownership:
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/widgets/recording_overlay.dart`

### Lane D: Group Conversation

Ownership:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

### Lane E: Feed

Ownership:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/application/...`
- `lib/features/feed/presentation/widgets/...`

Constraint:
- this lane starts with a `PERF-09` audit because Feed already has local changes

### Lane F: Orbit

Ownership:
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/application/...`
- Orbit row widgets and intros integration

### Lane G: Cleanup

Ownership:
- `PERF-11`
- residual small layout hotspots after the main work is stable

## Wave Plan

### Wave 0: Setup, Baseline, and Feed Audit

Run these first.

#### Lane A0: `PERF-00` Lightweight Baseline

Goals:
- capture the minimum useful before-state
- establish route videos/screenshots for comparison
- create initial pass/fail checkpoints

Deliverables:
- baseline notes for the required routes
- screenshots or clips for loading states and key scroll routes
- a short benchmark table or log entry

#### Lane E0: `PERF-09` Audit And Gap List

Goals:
- inspect the current local `PERF-09` diff
- confirm whether it really replaced full feed reload behavior across the intended event types
- identify missing tests or regressions before more Feed work lands on top

Required outputs:
- go / no-go decision to build further Feed work on top of the current implementation
- list of missing tests
- list of issues to fold into the later Feed reconciliation step

Rule:
- no additional Feed implementation lane should mutate Feed files until this audit completes

### Wave 1: Safe Parallel Implementation Lanes

Start these once Wave 0 is complete enough to proceed.

#### Lane B1: `PERF-01`

Run in parallel with Conversation, Group, Orbit, and Feed only if the `UserAvatar` API can remain stable.

Deliverables:
- avatar cache / resolver moved out of widget hot path
- no synchronous avatar file probing inside widget `build`
- regression checks on Feed, Orbit, Conversation headers, and Settings avatars

#### Lane C1: `PERF-03`

Deliverables:
- recording and processing state isolated from page-wide rebuilds
- message list and header stay outside high-frequency rebuilds
- conversation route remains visually stable during recording / video processing

#### Lane D1: `PERF-06`

Deliverables:
- group incoming events update only changed messages or attachments
- list churn and attachment flicker removed or materially reduced
- scroll position remains stable during active group traffic

#### Lane F1: `PERF-08`

Deliverables:
- Orbit list virtualization in place
- hero section separated from list rendering path where appropriate
- search and filter remain functional under virtualization

#### Lane E1: `PERF-07`

Start this only after Lane E0 signs off that the current `PERF-09` diff is safe to build on.

Deliverables:
- Feed moved to builder-backed or sliver-backed rendering
- visible card state preserved across scrolling and updates
- Feed ready for final `PERF-09` reconciliation

### Wave 2: State Reconciliation And Dependent Structural Work

#### Lane F2: `PERF-10`

Start after `PERF-08` is stable.

Deliverables:
- Orbit rows and unread state update incrementally
- no full Orbit recomputation on isolated events
- search and filters preserve context while new events arrive

#### Lane E2: `PERF-09` Reconciliation / Hardening

This is the step that closes the loop on the already-implemented `PERF-09`.

Goals:
- merge the Wave 0 audit findings into the existing Feed incremental-update implementation
- ensure the incremental store still works cleanly after `PERF-07`
- add or finish missing tests
- verify no obvious full reload paths remain on common incoming events

Deliverables:
- `PERF-09` behaves correctly on top of virtualized Feed rendering
- missing tests from the audit are added
- Feed route behavior remains stable on message, reaction, intro, and read-state updates

### Wave 3: Residual Cleanup

#### Lane G3: `PERF-11`

Run last.

Reason:
- this is residual cleanup and should target only what remains after the main lanes are merged

Deliverables:
- intrinsic sizing and nested list hotspots cleaned up where still relevant
- no cleanup changes that fight ongoing structural work

### Wave 4: Final Verification

Lane A4 performs the closeout pass.

Required outputs:
- final route-by-route QA result
- final regression test result
- list of intentional visible changes
- list of unresolved issues, if any
- explicit confirmation that each `PERF-xx` had a follow-up pass after implementation

## Per-PERF Implementation And Follow-Up

These sections tell the future session what to do for each item and what follow-up must happen before the item is marked done.

### PERF-00 Baseline And Regression Gates

Goal:
- establish a lightweight before-state and enforce after-state validation on every lane

Implementation steps:
- capture the required baseline routes
- define pass / fail notes for scroll, route entry, typing, recording, and attachment flows
- keep the notes lightweight and update them after every lane

Follow-up required:
- after every `PERF-xx`, rerun only the relevant observation routes from [`impl-backlog.md`](./impl-backlog.md)
- do not wait until the very end to discover regressions

Stop conditions:
- if no device or emulator path exists for route verification, note the limitation clearly and continue with the best available fallback

### PERF-01 Move Avatar Lookup And Caching Out Of Widget Build

Primary files:
- `lib/features/home/presentation/widgets/user_avatar.dart`
- any new avatar cache / resolver introduced

Implementation steps:
- remove synchronous file existence checks from widget build paths
- resolve avatar state before build or behind a cache
- preserve the current rendering outputs and fallbacks
- keep the `UserAvatar` API stable if possible

Follow-up required:
- search the codebase for sync avatar probing in hot UI paths
- manually verify Feed cards, Orbit rows, conversation header avatars, and Settings avatar rendering
- check for avatar pop-in, stale image display, and fallback flashes

Special rule:
- if an API break is unavoidable, merge this lane before restarting any other mutating lanes

### PERF-03 Isolate Recording, Processing, And Progress State From Page Rebuilds

Primary files:
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` if shared patterns apply
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/widgets/recording_overlay.dart`

Implementation steps:
- isolate the high-frequency state into smaller controllers, notifiers, or scoped builders
- keep message list and header outside those rebuild paths
- preserve current visible recording and processing behavior

Follow-up required:
- verify conversation remains stable while recording voice
- verify progress updates do not visibly shake or rebuild the header or list
- run targeted regression tests if practical

### PERF-06 Make Group Conversation Updates Incremental

Primary files:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`

Implementation steps:
- update only the changed messages, media, and pending downloads
- preserve scroll position on incoming group activity
- avoid full attachment or media map churn

Follow-up required:
- verify that incoming group activity no longer causes broad list churn
- verify that attachments do not flicker or re-resolve unnecessarily
- run group conversation routes from [`impl-backlog.md`](./impl-backlog.md)

### PERF-07 Virtualize Feed With Slivers Or Builders

Primary files:
- `lib/features/feed/presentation/screens/feed_screen.dart`
- Feed card widgets and related list composition widgets

Implementation steps:
- replace eager full-page rendering with a virtualized list structure
- preserve sectioning, card expansion behavior, and nav behavior
- keep stateful card interactions stable across scroll reuse

Follow-up required:
- verify long Feed scroll on realistic data volume
- verify expansion / collapse behavior still feels correct
- verify inline reply state and reaction state do not disappear unexpectedly during reuse

Special rule:
- do not sign this off until `PERF-09` reconciliation has been rerun on top of it

### PERF-08 Virtualize Orbit With Slivers Or Builders

Primary files:
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- Orbit row widgets and intros integration

Implementation steps:
- virtualize the list section
- preserve swipe behavior, search behavior, and hero section layout
- keep the intros section from forcing nested eager layout

Follow-up required:
- verify Orbit scroll and search responsiveness
- verify swipe actions still behave correctly under virtualization
- verify search and filters do not lose context unexpectedly

### PERF-09 Replace Full Feed Reloads With Incremental Thread State

Current state:
- already implemented locally before this plan
- not yet fully audited or reconciled with the rest of the backlog

Implementation steps for the next session:
- audit the current diff first
- identify event types that still trigger full reload behavior
- add missing tests
- after `PERF-07`, rerun Feed update logic against the virtualized structure and fix integration issues

Follow-up required:
- verify new messages update one thread instead of rebuilding the whole Feed
- verify reactions, unread changes, intro updates, and thread ordering behave correctly
- verify no focused inline reply field is lost unnecessarily
- rerun Feed route checks after the `PERF-07` integration step

This item is only done when:
- the initial audit is complete
- missing tests are added
- Feed virtualization and incremental updates work together cleanly

### PERF-10 Replace Full Orbit Reloads With Incremental State Updates

Primary files:
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/orbit/application/load_orbit_groups_use_case.dart`

Implementation steps:
- introduce an incrementally updated Orbit state model
- update only changed rows and counters on incoming events
- preserve search and filter projections separately from source state where practical

Follow-up required:
- verify single incoming events do not trigger full Orbit reload behavior
- verify row order, unread badges, blocked / archived state, and search context remain stable
- rerun Orbit observation routes

### PERF-11 Remove Remaining Nested Layout Hotspots

Primary files:
- `lib/features/home/presentation/widgets/editable_username_widget.dart`
- `lib/features/introduction/presentation/widgets/intros_tab.dart`
- `lib/features/introduction/presentation/screens/friend_picker_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`

Implementation steps:
- only inspect these after the larger lanes are done
- remove residual intrinsic sizing and nested list patterns that still matter
- simplify preview fade behavior only if it is still a measured hotspot

Follow-up required:
- verify username editing width still feels correct
- verify preview fade behavior still reads correctly
- verify picker and intro surfaces did not regress visually

## Mandatory Follow-Up Pattern After Every Lane

The future session should use this exact closeout pattern for every completed lane.

1. The implementation agent finishes coding and runs its own local checks.
2. A separate follow-up agent reviews the diff against the relevant `PERF-xx` acceptance criteria.
3. The QA lane reruns only the observation routes touched by that lane.
4. If tests exist for the touched cluster, run them.
5. If the lane changed visible UX, capture a before / after screenshot set.
6. Only then mark the item as done.

If follow-up finds gaps:
- return the item to the same lane for one correction pass
- rerun the follow-up pattern again

## Stop Conditions

The future session should continue automatically until one of these conditions is hit.

Stop and report if:
- the current `PERF-09` work cannot be safely checkpointed
- the runtime cannot isolate overlapping mutating lanes safely
- a lane needs a breaking shared-component API change after other lanes already started
- tests fail and the root cause is unclear
- profiling or manual validation contradicts the claimed performance win

If none of those happen, the session should continue through the next wave without waiting for manual approval.

## Rough Time Model

Use this only for planning, not as a hard contract.

Reference point:
- `PERF-09` already took about 1 hour

Reasonable rough ranges for the remaining work:
- `PERF-00` lightweight baseline: 0.5 hour
- `PERF-01`: 0.5 to 1 hour
- `PERF-03`: 0.75 to 1.25 hours
- `PERF-06`: 0.75 to 1.25 hours
- `PERF-07`: 1 to 2 hours
- `PERF-08`: 1 to 2 hours
- `PERF-09` audit and reconciliation: 0.75 to 1.5 hours
- `PERF-10`: 0.75 to 1.5 hours
- `PERF-11`: 0.5 to 1 hour

What this means:
- serial execution could still be most of a workday
- well-isolated parallel execution should reduce wall-clock time materially
- the main time sink is not coding alone; it is the required follow-up after each lane

## Minimal Prompt For The Next Session

If you want to hand this plan to the next session directly, use something close to this:

"Read `UI-UX-Perf-Improvements/plan.md` and `UI-UX-Perf-Improvements/impl-backlog.md`. Execute the plan as written. Treat `PERF-09` as already implemented locally and start with its audit. Use the new Flutter performance skills if they are discoverable, especially the orchestrator. Run parallel lanes only where file ownership is disjoint. After each `PERF-xx`, run a separate follow-up review and targeted QA before marking it done. Continue automatically across waves unless a documented stop condition is hit."

## Definition Of Done For The Entire Effort

The overall effort is done only when:
- each remaining `PERF-xx` has been implemented or consciously deferred with a reason
- `PERF-09` has been audited and reconciled with Feed virtualization
- every item has a recorded follow-up pass
- final route checks from [`impl-backlog.md`](./impl-backlog.md) were completed
- unresolved risks, if any, are written down clearly instead of being hidden
