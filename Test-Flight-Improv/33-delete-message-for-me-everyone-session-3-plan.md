# 33 - Delete Message For Me / Everyone Session 3 Plan

## Final Verdict

Session `3` is `implementation-ready` for feed parity and final acceptance.
Session `1` and Session `2` are already `accepted` in this turn, so this plan
only covers the remaining feed-side work and closure pass for report `33`.

## Real Scope

- Add feed-side delete affordance parity for 1:1 message cards using the
  accepted Session `1` delete contract and the accepted Session `2` Orbit
  affordance/confirmation flow as the behavioral baseline.
- Make feed cards reflect delete fallout honestly when the latest or only
  message disappears, including next-latest fallback and empty-state
  transitions.
- Keep quoted-message previews honest when the quoted parent has been deleted
  or hidden, so feed surfaces show unavailable state instead of stale content.
- Finish report `33` closure only after feed behavior matches the contract and
  the named gates pass.

## Closure Bar

Report `33` is closed only when all of the following are true:

- feed cards expose the same delete affordance expectations as the 1:1
  conversation surface where the product contract allows it
- deleted latest rows no longer leave stale latest-message, preview, or badge
  state behind in feed projections
- quote previews on feed surfaces show unavailable when the quoted parent is
  deleted or hidden
- empty-state and next-latest fallback behavior remains stable when a thread
  loses its visible tail message
- Session `1` and Session `2` remain accepted and are not reopened by feed
  parity work

## Source Of Truth

- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/26-long-press-message-context-menu-session-breakdown.md`
- `Test-Flight-Improv/31-edit-last-sent-message-session-breakdown.md`
- Current code in `lib/features/feed/presentation/screens/feed_wired.dart`
- Current code in `lib/features/feed/presentation/screens/feed_screen.dart`
- Current code in `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- Current code in `lib/features/feed/presentation/widgets/message_bubble.dart`
- Current code in `lib/features/feed/domain/models/feed_item.dart`
- Current code in `lib/features/feed/application/feed_store.dart`

Current repo facts that matter:

- `feed_wired.dart` already rebuilds feed projections from snapshot helpers and
  uses `FeedStore` as the mutable projection layer.
- `feed_screen.dart` already treats missing quoted parents as unavailable in
  quote previews, so Session `3` should extend that seam rather than invent a
  separate quote-rendering model.
- `scrollable_message_preview.dart` and `message_bubble.dart` already have
  unavailable quote rendering paths that can be reused for deleted parents.
- `FeedStore` already owns contact/thread projection sorting and message-id
  membership tracking, which is the right seam for delete fallout and reaction
  cleanup.

## Session Classification

- `implementation-ready`

## Exact Problem Statement

- Feed threads can still show stale latest-message or quote-preview state after
  a deleted message should no longer be visible.
- The feed-side projection path does not yet own the delete parity surface the
  way conversation/orbit does, so delete-related fallout can be missed in
  collapsed cards, open cards, or empty-state transitions.
- Current feed quote handling already knows how to say "unavailable" for
  missing parents, but Session `3` needs to prove that deleted parents and
  deleted latest rows resolve through the same honest fallback path.

## Files And Repos To Inspect Next

Production:

- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/application/feed_store.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`

Tests:

- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`

## Existing Tests Covering This Area

- `feed_screen_test.dart` already covers empty-state rendering and quote
  preview mapping.
- `scrollable_message_preview_test.dart` already covers unavailable quote
  rendering for missing parents.
- `open_mode_card_body_test.dart` and `collapsed_mode_card_body_test.dart`
  already pin current reply/quote preview behavior.
- `message_bubble_test.dart` already pins quote-bar and unavailable quote
  rendering.
- `feed_wired_test.dart` already covers feed refresh, projection, and quote
  workflow behavior, but not delete parity.

## Regression Tests To Add First

- Add feed-wire regressions that prove a deleted latest row causes the feed
  projection to refresh instead of leaving stale content behind.
- Add widget regressions that prove quoted parents render as unavailable when
  the parent row is deleted or hidden.
- Add a feed-card regression for next-latest fallback when the latest visible
  message disappears.
- Add an empty-state regression for the case where a feed thread loses its
  last visible message.

## Step-By-Step Implementation Plan

1. Inspect the current feed projection and refresh path in `feed_wired.dart`
   and `feed_store.dart` so delete fallout is handled in the existing snapshot
   layer rather than by ad hoc widget mutation.
2. Extend the feed host delete path only where needed to surface the accepted
   delete contract and to trigger snapshot refreshes after delete-for-me or
   delete-for-everyone land.
3. Update feed quote resolution and latest-message fallback behavior so deleted
   or hidden parents resolve to the existing unavailable copy.
4. Add focused feed widget and feed wired regressions before broadening to the
   higher-level feed integration suite.
5. Run the feed gate plus the companion reliability gates, then close the
   session only after the report ledger and acceptance verdict are updated.

## Risks And Edge Cases

- A deleted latest row can change both the visible card body and the unread/
  active thread classification, so the projection refresh must not leave stale
  `latestMessage`-driven UI behind.
- Quote fallback must remain honest for deleted parents, not just missing
  parents.
- Feed parity should not reopen unrelated 1:1 reliability, group messaging, or
  transport/bootstrap behavior.
- The feed refresh path already sorts by timestamps and rebuilds projections, so
  a delete change that bypasses those helpers would be a regression risk.

## Exact Tests And Gates To Run

Direct tests first:

- `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test --no-pub test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `flutter test --no-pub test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`
- `flutter test --no-pub test/features/feed/presentation/widgets/message_bubble_test.dart`
- `flutter test --no-pub test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`

Named gates:

- `./scripts/run_test_gates.sh feed`
- `./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`

Do not pull in `transport` unless this session unexpectedly changes bootstrap,
reconnect, inbox-drain, or transport-fallback wiring.

## Known-Failure Interpretation

- Treat existing macOS/Xcode deployment warnings and `open returned 1` output
  from the gate scripts as environment noise if the test suites themselves
  pass.
- Treat any pre-existing quote-preview assertions in feed widgets as stable
  baseline behavior unless this session changes the quoted-parent contract.
- Do not misclassify stale 1:1 delete tests as Session `3` failures; Session
  `3` is feed parity only.

## Done Criteria

- Feed delete parity is implemented on the current architecture without
  broadening scope beyond 1:1 feed cards and their quote/latest/empty-state
  fallout.
- All direct feed regressions pass.
- `feed`, `1to1`, and `baseline` pass.
- The Session `3` row in
  `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
  is marked accepted.
- The final program acceptance block in the breakdown artifact is updated to a
  closed verdict.

## Scope Guard

- Do not add batch delete, undo, time limits, or history recovery.
- Do not add contact-level delete semantics.
- Do not reopen group-delete scope.
- Do not invent a second delete architecture for feed if the existing snapshot
  and feed-store refresh seam can express the required behavior.
- Do not touch unrelated startup, transport, or notification work.

## Accepted Differences / Intentionally Out Of Scope

- Group delete remains out of scope.
- Batch delete, undo, and time limits remain out of scope.
- Contact-level delete and failed-media delete continue to be owned by their
  existing surfaces.
- Older clients may ignore an unknown delete signal as long as they do not
  crash.
- Session `1` and Session `2` are already accepted and should stay closed
  unless this session exposes a real regression.

## Dependency Impact

- Session `3` depends on the accepted Session `2` Orbit/shared-overlay work
  and the accepted Session `1` delete contract.
- Later closure work depends on this session for feed parity and final report
  acceptance.
- If feed work exposes a real mismatch in the shared contract, revisit the
  breakdown ledger first instead of widening Session `3` into a new shared
  persistence session.

## Final Plan

- Use the existing feed snapshot/rebuild seam to surface delete fallout.
- Prove deleted latest rows, deleted quoted parents, and empty-state fallback
  with direct feed tests before broad gates.
- Keep the session focused on feed parity and final acceptance only.

## Structural Blockers Remaining

- none

## Incremental Details Intentionally Deferred

- Exact UI affordance placement on feed cards, provided the accepted delete
  contract remains honest and the feed projection refreshes correctly.
- Minor copy polish, if any, that does not change the delete contract or
  fallback semantics.

## Accepted Differences Intentionally Left Unchanged

- The feed surface may continue to use existing unavailable-quote copy as the
  fallback string.
- The feed projection may still rebuild from snapshot helpers rather than
  gaining a new delete-specific store.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/33-delete-message-for-me-everyone-session-breakdown.md`
- `Test-Flight-Improv/33-delete-message-for-me-everyone.md`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/scrollable_message_preview.dart`
- `lib/features/feed/presentation/widgets/message_bubble.dart`
- `lib/features/feed/application/feed_store.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- `lib/features/feed/domain/models/feed_item.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/widgets/scrollable_message_preview_test.dart`
- `test/features/feed/presentation/widgets/message_bubble_test.dart`
- `test/features/feed/presentation/widgets/open_mode_card_body_test.dart`
- `test/features/feed/presentation/widgets/collapsed_mode_card_body_test.dart`

## Why The Plan Is Safe To Implement Now

- Session `1` already established the shared delete contract.
- Session `2` already established the Orbit affordance and confirmation flow.
- The remaining work is isolated to feed projection and feed rendering, which
  already have existing snapshot and unavailable-quote seams.
- The direct tests and named gates are explicit, so implementation can stop
  if feed deletion proves to be already covered or if a narrower projection fix
  is sufficient.
