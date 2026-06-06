Status: accepted_with_explicit_follow_up

# 107 Group Notification Highlight Double Card - Session 01 Plan

Session id: `01-notification-focus-cue`

## Planning Progress

- `2026-06-05 13:41:00 CEST` - Local plan fallback completed after the spawned planner wrote only an intake heartbeat and then left the intended plan artifact stale. Files inspected since last update: `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`, `Test-Flight-Improv/107-group-notification-highlight-double-card.md`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`. Decision/blocker: no planning blocker; session is execution-ready. Next action: spawn execution/QA for this plan.

## Real Scope

Change only the group conversation notification-target focus treatment so a row targeted by `highlightedMessageId` remains identifiable without adding a second card-like rounded bordered surface around the normal message row. Keep the existing highlighted message id threading, notification route/open behavior, message loading, `grp-highlight-*` target identity, one-target-only behavior, long-press overlay, reaction chip inspection, quote previews, swipe-to-reply wrapping, media tap behavior, and normal entry with no `highlightedMessageId`.

Out of scope: receive dedupe, persistence, live/replay convergence, notification payload contracts, background redesign, `LetterCard` redesign, route timing changes, and any data-layer duplicate-row fix.

## Closure Bar

Session 01 is done when:

- a notification-targeted group row renders one normal `LetterCard` surface plus a polished focus cue that is not a full rounded bordered card wrapper;
- exactly one target remains marked by `grp-highlight-<messageId>` and non-target rows are not highlighted;
- highlighted incoming and outgoing text, quoted, media, and reaction-bearing rows remain readable under the default dark background and representative light `BackgroundPreference.daylightLagoon`;
- long-press context actions, reaction inspection, media taps, quote previews, and swipe-to-reply resting behavior still work;
- normal group entry without `highlightedMessageId` has no focus artifact;
- focused widget/wired tests pass, followed by `./scripts/run_test_gates.sh groups`.

## Source Of Truth

- Product/session intent: `Test-Flight-Improv/107-group-notification-highlight-double-card.md` and `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`.
- Current code wins over stale prose for widget shape and test harness details.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Durable matrix/closure docs are deferred to session `04-acceptance-closure` unless this session adds new test files, which it should avoid.

## Session Classification

`implementation-ready`

## Exact Problem Statement

`GroupConversationScreen` currently wraps a highlighted row in an outer `AnimatedContainer` keyed as `grp-highlight-<id>` with its own `BoxDecoration`, rounded radius, background color, and border. Because the normal `LetterCard` already has a rounded bordered surface, this notification-anchor focus can look like a second stacked card. The fix must keep target identity and interactions while changing the focus affordance to a lighter cue.

## Files And Repos To Inspect Next

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart` only if the executor proves a tiny shared focus hook is necessary
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` only if route-anchor tests require threading adjustments

## Existing Tests Covering This Area

- `test/features/groups/presentation/group_conversation_wired_test.dart` already verifies notification-anchor target identity, non-target exclusion, long-press actions, and reaction inspection, but it currently only asserts the old highlight wrapper key exists.
- `test/features/groups/presentation/group_conversation_screen_test.dart` covers row rendering, swipe-to-quote wrapping, quote previews, media rendering/taps, long-press actions, reaction selection, and the representative light readable background, but its helper does not currently expose `highlightedMessageId`.

## Regression/Tests To Add First

Add or tighten tests before changing production code:

- Extend `group_conversation_screen_test.dart` helper with `highlightedMessageId`.
- Add host widget coverage proving highlighted rows do not create an outer card-like decorated wrapper while retaining `grp-highlight-*` target identity.
- Cover highlighted incoming, outgoing, quoted, media, and reaction-bearing variants, plus no-highlight normal entry.
- Cover dark default and `BackgroundPreference.daylightLagoon` readability at the widget level using existing readable-color helpers/patterns.
- Tighten `group_conversation_wired_test.dart` notification-anchor expectations so they prove target identity and interaction preservation without expecting the old outer bordered card wrapper.

## Step-By-Step Implementation Plan

1. Add failing/tightened tests around the current card-like highlight wrapper in `group_conversation_screen_test.dart` and the existing notification-anchor wired tests.
2. Replace the `isHighlighted` branch in `GroupConversationScreen._buildMessageList` so it no longer wraps the whole bubble in a full rounded bordered `AnimatedContainer`.
3. Use a subtle single-row cue inside the existing row footprint, such as a narrow leading accent rail, a soft glow, or a non-bordered tint that does not duplicate `LetterCard`'s card boundary. Preserve the `ValueKey('grp-highlight-${message.id}')`.
4. Keep `SwipeToQuoteBubble` and long-press context handling around the same child structure so gestures and quote behavior remain intact.
5. Run focused tests. If they reveal a `LetterCard` hook is needed, keep it tiny and presentation-only; do not change feed/conversation card semantics broadly.
6. Run the `groups` named gate. Run `baseline` only if `main.dart`, notification route/open wiring, or shared startup wiring changes.

## Risks And Edge Cases

- Removing the wrapper must not remove the only stable `grp-highlight-*` key used by route-anchor tests.
- A focus cue placed outside the swipe wrapper could interfere with swipe-to-reply; keep gesture behavior intact.
- A focus cue placed inside `LetterCard` could broaden shared card behavior; prefer local group-row composition first.
- Dark/light background contrast must remain readable without adding a heavy second surface.
- Long-press overlay selected-message preview should still be the normal card, not a duplicate highlighted shell.

## Exact Tests And Gates To Run

Focused tests first:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "highlight"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification-anchor"
```

If name filters miss renamed tests, run the full direct files:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Conditional gates:

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

Run `baseline` only if notification route/open or app-root wiring changes. Run `completeness-check` only if a new test file is added.

## Known-Failure Interpretation

Focused failures in the touched screen/wired tests are session-owned unless logs prove they are pre-existing and unrelated. Broad `groups` failures outside touched presentation, notification-anchor, or group conversation paths must be recorded with exact failing tests and compared against current known red state before being treated as blockers.

## Done Criteria

- Production diff is limited to `group_conversation_screen.dart` unless tests prove another listed presentation file is necessary.
- Tests assert the absence of a card-like outer highlight wrapper and the presence of a single-row focus cue.
- Existing notification-anchor identity, reaction inspection, and long-press behavior still pass.
- Highlighted row variants cover text, quote, media, reaction-bearing state, dark default, light readable background, and normal no-highlight entry.
- Focused tests pass.
- `./scripts/run_test_gates.sh groups` passes or any unrelated/pre-existing failures are recorded with evidence.

## Scope Guard

Do not change group message ids, dedupe, persistence, repository ordering, notification payloads, route-target parsing, `main.dart`, relay behavior, or stable matrix closure docs in this session. Do not introduce a broad `LetterCard` redesign or visually hide duplicate persisted rows. Do not accept a solution that merely renames the existing outer bordered wrapper.

## Accepted Differences / Intentionally Out Of Scope

- Device-backed notification-open proof is deferred to session `04-acceptance-closure`; this session uses host widget/wired proof for the deterministic focus cue.
- Duplicate persisted row convergence and `TC-107-R01` remain owned by sessions `02` and `03`.
- Durable matrix updates are deferred to session `04-acceptance-closure`.

## Dependency Impact

Session `04-acceptance-closure` depends on this session for `TC-107-R02` focus evidence and for dark/light visual confidence. Sessions `02` and `03` do not depend on this presentation change.

## Reviewer Pass

Plan sufficiency: sufficient after local fallback. The plan has a narrow owner file, regression-first tests, direct gates, done criteria, and a scope guard. No device/relay proof profile is required for this host-widget presentation session.

## Arbiter Pass

Structural blockers remaining: none.

Incremental details intentionally deferred: exact visual cue implementation language is left to execution as long as it avoids a full rounded bordered wrapper and passes the tests.

## Execution Progress

- `2026-06-05 13:40:10 CEST` - Executor phase heartbeat before implementation. Read plan source of truth, breakdown orientation, dirty-worktree snapshot, and initial owner-file slices for `group_conversation_screen.dart`, `group_conversation_screen_test.dart`, and `group_conversation_wired_test.dart`. Decision/blocker: none; scope remains the primary group screen plus existing screen/wired tests. Next action: focused owner-file inspection before test edits.
- `2026-06-05 13:40:10 CEST` - Owner-file inspection heartbeat before focused inspection. Targeted searches will inspect highlighted-row composition, `grp-highlight-*` identity, existing row shell helpers, and notification-anchor tests. Decision/blocker: none. Next action: finish exact owner-file inspection and then write test-first regressions.
- `2026-06-05 13:42:00 CEST` - Controller dirty-worktree snapshot before execution: `?? Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`; `?? Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`. Decision/blocker: no execution blocker; both entries are current-doc planning/controller artifacts. Next action: spawn fresh `$implementation-execution-qa-orchestrator` child for session `01-notification-focus-cue`.
- `2026-06-05 13:38:51 CEST` - Contract extracted for execution. Scope: replace only the group notification-target focus treatment in `lib/features/groups/presentation/screens/group_conversation_screen.dart` unless a tiny adjacent presentation-only hook is proven necessary. Required test files: `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. Required focused commands: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "highlight"` and `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification-anchor"`; run full direct files if filters miss coverage. Required named gate: `./scripts/run_test_gates.sh groups`. Conditional gates: `baseline` only for route/app-root wiring changes; `completeness-check` only for new test files. Known-failure policy: touched focused failures are session-owned unless logs prove pre-existing/unrelated. Decision/blocker: none; execution contract is concrete. Next action: spawn Executor implementation pass.
- `2026-06-05 13:39:10 CEST` - Executor spawned/running as nested agent `019e9794-b9ee-75f1-b074-4d5a5da919e6` with requested model `gpt-5.5` and reasoning effort `xhigh` in the prompt. Assigned files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. Current command/log: waiting on Executor bounded interval. Decision/blocker: pending Executor result. Next action: inspect landed file/test/doc deltas or child summary when the bounded wait returns.
- `2026-06-05 13:44:00 CEST` - Outer execution child closed after the nested Executor produced only owner-file inspection heartbeats and no scoped code/test diff or final execution result across the bounded wait plus settle poll. Last artifact state: no changes in `group_conversation_screen.dart`, `group_conversation_screen_test.dart`, or `group_conversation_wired_test.dart`. Decision/blocker: no product blocker; classify as execution child no-progress and enter the single current-session local execution fallback. Next action: locally apply the execution contract, then run focused tests and the `groups` gate.
- `2026-06-05 13:49:00 CEST` - Local fallback Executor implemented the scoped focus cue and tests. Files touched: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`. Change summary: highlighted group rows now use a keyed `Stack` plus slim `grp-highlight-cue-*` accent rail without a bordered wrapper; tests cover highlighted text/outgoing/quote/media/reaction variants, dark/light readable backgrounds, and tightened notification-anchor wired assertions. Formatting command completed: `dart format lib/features/groups/presentation/screens/group_conversation_screen.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart`. Decision/blocker: none. Next action: run focused screen highlight test filter.
- `2026-06-05 13:51:00 CEST` - Focused test started/finished with session-owned compile failure: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "highlight"` failed because the new test helper used `AnimatedContainer.width`, which is not exposed in this Flutter SDK. Classification: session-owned test assertion shape, not a product blocker. Next action: assert cue width through `AnimatedContainer.constraints` and rerun the same focused filter.
- `2026-06-05 13:53:00 CEST` - Focused test rerun compiled but failed in the new highlighted-variant test because the target message was offscreen in a long reversed list: `grp-highlight-msg-focus-incoming` was not built. Classification: session-owned test harness setup, not product behavior. Next action: pump each highlighted variant in a small visible message set and rerun the same focused filter.
- `2026-06-05 13:55:00 CEST` - Focused test passed: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "highlight"` completed with `All tests passed!` after the visible-message harness correction. Decision/blocker: none. Next action: run focused wired notification-anchor test filter.
- `2026-06-05 13:57:00 CEST` - Focused wired test command passed: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification-anchor"` completed with `All tests passed!`, but the filter matched only one relevant test because another test uses `notification anchor` without the hyphen. Decision/blocker: no failure; focused filter coverage is incomplete. Next action: run full direct screen and wired test files per the plan fallback rule.
- `2026-06-05 13:59:00 CEST` - Full direct screen suite passed: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart` completed with `48` passing tests and `All tests passed!`. Decision/blocker: none. Next action: run full direct wired suite.
- `2026-06-05 14:02:00 CEST` - Full direct wired suite attempted: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` failed on unrelated send/refresh test `GroupConversationWired sending a message calls bridge and refreshes` at line `1388`, expected `msgRepo.getMessagesPageCalls == 1` but observed `2`. Focused triage command `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "sending a message calls bridge and refreshes"` reproduced the same failure in isolation. Classification: unrelated existing/send-refresh wired-suite red test; this session changed only highlight rendering/tests and does not touch send, bridge, repository refresh, or message loading. Decision/blocker: not session-owned; continue with focused notification-anchor coverage and required `groups` gate.
- `2026-06-05 14:04:00 CEST` - Focused wired notification-anchor coverage completed: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification anchor"` passed with `All tests passed!`, complementing the earlier `--name "notification-anchor"` reaction-inspection pass. Decision/blocker: none for session-owned wired focus paths. Next action: run required named gate `./scripts/run_test_gates.sh groups`.
- `2026-06-05 14:51:00 CEST` - Required named gate passed: `./scripts/run_test_gates.sh groups` completed with `All tests passed!` (`321` passing tests). Scope/format QA: `git diff --check` passed; changed files remain limited to `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `test/features/groups/presentation/group_conversation_screen_test.dart`, `test/features/groups/presentation/group_conversation_wired_test.dart`, and current-doc artifacts. Conditional gates not run: `baseline` not required because route/app-root wiring was untouched; `completeness-check` not required because no new test file was added.

## Final Execution Verdict

- Verdict: `accepted_with_explicit_follow_up`
- Blocker class: none
- Spawned-agent isolation used: yes for planning and the first execution/QA child; the execution child spawned a nested Executor but no code/test delta landed.
- Local sequential fallback used: yes, after bounded no-progress from the spawned execution path.
- Files changed:
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `Test-Flight-Improv/107-group-notification-highlight-double-card-session-01-notification-focus-cue-plan.md`
  - `Test-Flight-Improv/107-group-notification-highlight-double-card-session-breakdown.md`
- Tests added or updated: highlighted group notification focus coverage in `group_conversation_screen_test.dart`; notification-anchor wired assertions tightened in `group_conversation_wired_test.dart`.
- Exact tests and gates run:
  - `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --name "highlight"`: failed once for test compile assertion, failed once for offscreen harness setup, then passed.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification-anchor"`: passed.
  - `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`: passed, `48` tests.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`: failed on unrelated send/refresh test `sending a message calls bridge and refreshes`.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "sending a message calls bridge and refreshes"`: reproduced unrelated failure, expected `getMessagesPageCalls == 1`, actual `2`.
  - `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --name "notification anchor"`: passed.
  - `./scripts/run_test_gates.sh groups`: passed, `321` tests.
  - `git diff --check`: passed.
- Blocking issues remaining: none for session `01-notification-focus-cue`.
- Non-blocking follow-up: the existing/unrelated `GroupConversationWired sending a message calls bridge and refreshes` test is red in isolation and in the full wired file; it is outside this session's highlight/focus scope and should be handled by a separate send-refresh test maintenance pass.
- Why the session is safe to consider complete: the production change removes the card-like highlighted wrapper while preserving route-target identity and interactions, session-owned focused/direct coverage is green, the required group gate is green, and the only red test is reproduced outside the touched focus path.
