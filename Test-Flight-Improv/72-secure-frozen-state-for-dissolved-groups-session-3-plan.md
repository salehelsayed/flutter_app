# Session 3 Plan - Propagate dissolved frozen-state truth into feed thread models and inline group surfaces

## Final verdict

- `implementation-ready`

## Real scope

- Thread dissolved-state facts into the feed-owned group thread model so feed
  writeability no longer derives only from announcement admin-vs-reader role.
- Split feed semantics between "can write" and "can react" so active
  announcement readers stay read-only for compose while still keeping
  reaction-entry affordances until dissolve.
- Remove dissolved-group compose, attach, quote-reply, and reaction-entry
  affordances from feed cards and long-press overlays while preserving
  readable history and read-only reaction inspection on already-stored chips.
- Add the stale-dissolve optimistic-reaction restore path in `FeedWired` so a
  reaction attempt that races against dissolve does not leave a ghost chip in
  the feed.
- Keep this session limited to feed domain/projection/presentation seams
  without widening into the local-delete cleanup flow from Session `4`.

## Closure bar

- `GroupThreadFeedItem` carries enough dissolved-state truth to derive both
  feed writeability and feed reaction-entry affordances correctly.
- Active announcement readers remain read-only for compose/quote/attach but
  still keep reaction entry in the feed while the group is active.
- Dissolved groups show feed read-only copy that matches the shipped
  conversation contract and expose no compose, attach, quote-reply, or
  reaction-entry affordances.
- Feed long-press group overlays keep copy/read-only inspection, but the
  reaction bar and reply action disappear when the thread is dissolved.
- A stale optimistic feed reaction attempt that receives
  `groupDissolved` restores truthful local reaction state, refreshes the group
  thread, and surfaces the dissolved snackbar instead of leaving a fake chip.
- Full-load and incremental feed projection both preserve the dissolved-state
  facts used by the UI.

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
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
  - `lib/features/feed/application/load_feed_use_case.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
  - `test/features/feed/domain/models/feed_item_test.dart`
  - `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/load_feed_use_case_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`

On disagreement:

- current code and tests beat older prose
- `test-gate-definitions.md` is the source of truth for named gates
- the feed dissolved banner copy should match the already-shipped
  `GroupConversationScreen` dissolved read-only banner instead of inventing a
  second ended-state wording
- active announcement readers already keep reaction capability in the repo via
  `announcement_happy_path_test.dart`, so feed must mirror that narrower
  write-vs-react split rather than collapsing everything into `canWrite`

## Session classification

- `implementation-ready`

## Exact problem statement

- Report `72` calls out that feed writeability still ignores dissolved state:
  `GroupThreadFeedItem.canWrite` only models announcement admin-vs-reader
  behavior, and the group feed builders never project `group.isDissolved`.
- `FeedScreen` currently gates group reply actions by `thread.canWrite`, but
  it shows the long-press reaction bar whenever `onGroupReactionSelected`
  exists, so dissolved group cards still imply participation.
- `OpenModeCardBody` and `CollapsedModeCardBody` show the generic
  announcement-reader read-only banner for every non-writable group card, even
  when the actual cause is that the group has been dissolved.
- `FeedWired._onGroupReactionSelected(...)` still performs optimistic feed
  reaction mutation without restoring prior state when
  `sendGroupReaction(...)` or `removeGroupReaction(...)` reports
  `groupDissolved`.
- This session must make feed surfaces tell the same frozen-state truth as the
  already-hardened conversation surface without breaking active announcement
  reader reactions or widening into cleanup UX.

## Files and repos to inspect next

- Production:
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
  - `lib/features/feed/application/load_feed_use_case.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/presentation/screens/feed_screen.dart`
  - `lib/features/feed/presentation/widgets/feed_card.dart`
  - `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
  - `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- Tests:
  - `test/features/feed/domain/models/feed_item_test.dart`
  - `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `test/features/feed/presentation/screens/feed_screen_test.dart`
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/load_feed_use_case_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`

## Existing tests covering this area

- `feed_item_test.dart`
  proves base `GroupThreadFeedItem` behavior such as `isOpenMode` and
  `hasSentMessage`, but it does not model dissolved-specific truth.
- `group_group_messages_into_threads_test.dart`
  proves announcement `myRole` and `canWrite` projection, but it does not
  preserve or assert `isDissolved` or a separate `canReact` contract.
- `feed_screen_test.dart`
  already proves announcement readers stay read-only for compose while keeping
  inline reaction inspection, and it proves group long-press overlays can show
  reply/copy/reaction entry. It does not yet prove the dissolved case for the
  banner text or the hidden reaction/reply affordances.
- `feed_wired_test.dart`
  already proves feed group long-press/reaction inspection alignment with the
  shared conversation surface, but it does not yet prove the stale-dissolve
  optimistic reaction restore path or dissolved feed affordance removal.
- `load_feed_use_case_test.dart`
  proves active groups appear in the feed, but it does not yet assert that
  dissolved state survives projection.
- `feed_projection_test.dart`
  proves parity between full-load and incremental feed updates, but its group
  item mapping omits dissolved-state facts.

## Regression/tests to add first

- Add feed domain regressions for:
  - active announcement reader: `canWrite == false`, `canReact == true`
  - dissolved group thread: `canWrite == false`, `canReact == false`
- Add thread-projection regressions that preserve `isDissolved` and derive the
  right `canWrite` / `canReact` split for admin, announcement reader, and
  dissolved cases.
- Add feed screen regressions for:
  - dissolved group banner uses the dissolved copy
  - dissolved group long-press overlay has copy only, with no reaction bar and
    no reply action
  - active announcement reader long-press still exposes the reaction bar while
    reply stays hidden
- Add feed wired regressions for:
  - dissolved group feed cards remain non-writable/non-reactable after refresh
  - stale optimistic feed reaction entry restores prior state and shows the
    dissolved snackbar when the underlying use case returns `groupDissolved`
- Extend projection/load regressions so dissolved state survives both
  `loadFeed(...)` and incremental feed refresh parity checks.

## Step-by-step implementation plan

1. Add the direct regressions above so the feed seam is red before code
   changes.
2. Extend `GroupThreadFeedItem` with dissolved-state truth, including a
   dedicated `canReact` computed getter while tightening `canWrite` to return
   false for dissolved groups.
3. Project `group.isDissolved` through both
   `group_group_messages_into_threads.dart` and
   `FeedWired._buildGroupThreadFeedItem(...)` so full-load and incremental
   feed paths stay consistent.
4. Update feed card/footer rendering to show dissolved-specific read-only copy
   and keep compose/attach/quote actions gated by `canWrite`.
5. Update feed long-press overlay logic so reply stays tied to `canWrite` and
   reaction entry is tied to `canReact` rather than callback presence alone.
6. Add the stale-dissolve restore path to `FeedWired._onGroupReactionSelected`
   for both optimistic add and optimistic remove, refreshing the visible group
   thread and restoring prior reaction state when needed.
7. Re-run the direct feed suites and the `feed` gate, then update the session
   breakdown ledger.

## Risks and edge cases

- Active announcement readers must remain able to react in feed surfaces;
  tying reaction entry to `canWrite` would silently regress shipped
  announcement behavior.
- Dissolved feed cards should still allow read-only reaction inspection via
  already-stored chips; only reaction mutation entry must disappear.
- Full-load and incremental projection must agree on dissolved truth, or the
  feed can flicker between writable and frozen after a refresh/restart.
- The stale callback path must restore the exact previous local reaction list
  for a message instead of bluntly clearing all reactions.
- Feed card copy should match the conversation surface closely enough that the
  user does not see two different definitions of "dissolved".

## Exact tests and gates to run

- Direct tests:
  - `flutter test test/features/feed/domain/models/feed_item_test.dart`
  - `flutter test test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
  - `flutter test test/features/feed/application/load_feed_use_case_test.dart`
  - `flutter test test/features/feed/application/feed_projection_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh feed`

## Known-failure interpretation

- The worktree is already dirty in unrelated notification/push files. Treat
  failures outside the touched feed dissolved-state seam as pre-existing
  unless the direct feed suites or the `feed` gate show a regression in the
  touched path.
- If the full `feed` gate fails in an untouched unrelated area, record that
  honestly instead of widening Session `3`.

## Done criteria

- Feed group thread models preserve dissolved truth and expose the correct
  `canWrite` / `canReact` split.
- Active announcement readers remain read-only for compose but still keep
  reaction entry in feed surfaces.
- Dissolved feed cards show dissolved-specific read-only copy and hide
  compose, attach, quote, and reaction entry.
- Feed long-press overlays for dissolved groups keep copy/read-only inspection
  but not reply or reaction mutation.
- Stale optimistic feed reaction mutations restore truthful state on
  `groupDissolved`.
- Full-load and incremental feed projection regressions pass.
- The `feed` gate passes, or any unrelated pre-existing failure is documented
  honestly.

## Scope guard

- Do not add the local-delete-after-dissolve affordance in this session.
- Do not redesign feed card visuals beyond the minimal truthful dissolved-state
  copy and affordance changes.
- Do not reopen group-conversation reaction-freeze logic from Session `2`
  unless this feed session cannot compile or verify without a narrow follow-on.
- Do not widen into archive/mute/group-info cleanup behavior.

## Accepted differences / intentionally out of scope

- Dissolved groups may still expose read-only reaction inspection on existing
  chips because that does not mutate state.
- Cleanup UX for removing dissolved groups locally stays in Session `4`.
- Stable docs and matrix refresh stay in Session `5`.

## Dependency impact

- Session `4` depends on this session so cleanup UX is layered onto feed
  surfaces that already tell the truth about dissolved frozen state.
- Session `5` depends on this session because the stable audits and matrices
  should not claim feed closure until these projection/presentation gaps are
  actually verified.

## Structural blockers remaining

- None at planning time.

## Incremental details intentionally deferred

- Whether the dissolved read-only copy should later be centralized across
  group conversation and feed can be decided after the narrow feed freeze
  contract lands.

## Accepted differences intentionally left unchanged

- Active announcement-reader compose restrictions remain unchanged; this
  session only prevents dissolved feed cards from looking writable/reactable
  while preserving the active reader reaction contract.

## Exact docs/files used as evidence

- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups-session-breakdown.md`
- `Test-Flight-Improv/72-secure-frozen-state-for-dissolved-groups.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/feed/domain/models/feed_item.dart`
- `lib/features/feed/domain/utils/group_group_messages_into_threads.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/feed/presentation/widgets/feed_card.dart`
- `lib/features/feed/presentation/widgets/open_mode_card_body.dart`
- `lib/features/feed/presentation/widgets/collapsed_mode_card_body.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/feed/domain/models/feed_item_test.dart`
- `test/features/feed/domain/utils/group_group_messages_into_threads_test.dart`
- `test/features/feed/presentation/screens/feed_screen_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/application/load_feed_use_case_test.dart`
- `test/features/feed/application/feed_projection_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`

## Why the plan is safe to implement now

- The gap is narrow, well-evidenced, and already isolated to the feed domain,
  projection, and presentation seam.
- Session `2` already established the underlying reaction-freeze contract, so
  this session only needs to project that truth into feed-owned models and
  optimistic UI behavior.
- The validation is direct, local, and small enough to stop before the later
  cleanup/doc-refresh sessions.
