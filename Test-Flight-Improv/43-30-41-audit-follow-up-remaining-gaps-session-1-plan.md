# Audit 43 Session 1 Plan: Feed Inline-Reply Unread Projection Fix And Proof

## Final Verdict

- `implementation-ready`
- Session 1 is still a live implementation seam, not `stale/already-covered`.
- Current repo evidence still shows the feed 1:1 inline-reply success path marks the conversation read and then reuses the stale in-memory thread for follow-up projection, while no direct regression yet covers `A1 incoming -> B1 inline reply -> A2 incoming -> older unread excluded`.

## Evidence Collector

- Active contract:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
    still classifies Session `1` as `implementation-ready` and keeps scope on
    the feed-owned unread-projection seam.
- Problem statement:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
    still says Feed inline reply marks the conversation read but then merges
    into the existing in-memory thread instead of forcing a fresh post-read
    snapshot, and it records `TC-43-RG-02` plus the missing
    `incoming -> inline reply -> later incoming -> older unread excluded`
    regression.
- Prior decomposition:
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
    still narrows this to the feed-owned unread projection seam, not a
    notification-route/callback problem, and preserves the `feed` plus
    companion `1to1` gate contract.
- Code facts:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
    already has a fresh snapshot path in `_refreshContactFeedItem`, but the
    successful inline-reply branch instead calls `markConversationRead(...)`
    and then `_applyIncomingContactMessageToFeed(...)`, which merges onto the
    current in-memory thread.
  - `lib/features/feed/presentation/screens/feed_wired.dart`
    computes conversation state from `ThreadMessage.isUnread`, so stale unread
    flags remain behaviorally relevant after that merge.
  - `lib/features/feed/domain/models/feed_item.dart`
    derives open-mode preview content from `unreadMessages`, so it will
    faithfully expose any stale unread state fed into the thread.
- Existing adjacent proofs:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
    already covers later incoming reopening, expand-after-reply behavior, and
    optimistic session reply.
  - `test/features/feed/application/feed_projection_test.dart`
    already proves a mark-read transition matches a fresh cold-load snapshot.
  - `test/features/feed/integration/feed_card_flow_test.dart`
    already proves the card primitive reopens correctly when a session reply is
    cleared.
- Executed spot checks during planning:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "incoming message clears session reply so card shows open mode"`
  - `flutter test test/features/feed/application/feed_projection_test.dart --plain-name "mark-read transition matches cold load"`
  - `flutter test test/features/feed/integration/feed_card_flow_test.dart --plain-name "session reply cleared on incoming allows open mode to show"`
  - All three passed.
- Coverage gap that remains:
  - no current direct regression proves the exact escaped Session 1 sequence.

## Final Plan

### Real Scope

- Fix only the feed-owned 1:1 inline-reply success seam so an answered unread
  row does not reappear in later open-mode preview state.
- Add the missing direct regression for
  `A1 incoming -> B1 inline reply -> A2 incoming`, plus only the smallest
  adjacent longer-thread proof if the same failing seam owns it.
- Keep the existing optimistic session-reply UI, collapse/reopen behavior,
  expand-after-reply behavior, and feed-to-1:1 entry contract unchanged.
- Default edit target is
  `lib/features/feed/presentation/screens/feed_wired.dart`.
- `lib/features/feed/domain/models/feed_item.dart` is supporting evidence for
  current unread projection, not a default edit target.
- Only touch snapshot/projection helpers if the narrow `feed_wired.dart` fix
  cannot preserve current behavior.

### Closure Bar

- After `A1 incoming -> B1 inline reply`, the card reflects truthful post-read
  state and no longer exposes `A1` as unread/open-mode content.
- After `A2 incoming`, the card reopens with only genuinely unread rows rather
  than resurfacing `A1`.
- Existing optimistic session reply, reopen-on-incoming, and expand-after-reply
  behavior remain green.
- Required direct tests and named gates pass.

### Source Of Truth

- Active session contract:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
- Live problem and regression contract:
  `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
- Prior bounded decomposition:
  `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate execution truth:
  `Test-Flight-Improv/test-gate-definitions.md`
- On disagreement, current code/tests beat stale prose, and
  `./scripts/run_test_gates.sh` beats markdown wording for named gates.

### Session Classification

- `implementation-ready`

### Exact Problem Statement

- In `lib/features/feed/presentation/screens/feed_wired.dart`, the successful
  inline-reply branch marks the conversation read and then applies the outgoing
  message through `_applyIncomingContactMessageToFeed(...)`, which merges onto
  the current in-memory thread instead of reloading post-read truth.
- In the same file, conversation state is recomputed from `ThreadMessage`
  unread flags, so old unread rows can remain behaviorally active after that
  merge.
- In `lib/features/feed/domain/models/feed_item.dart`, open-mode preview uses
  `unreadMessages`, so any stale unread flags continue to surface as unread
  content.
- Existing tests prove neighboring behavior, but no direct test proves older
  answered unread rows stay hidden after the next incoming message arrives.

### Files And Repos To Inspect Next

- `lib/features/feed/presentation/screens/feed_wired.dart`
  - primary production edit target
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  - primary regression target
- `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
  - inspect only if the narrow fix needs the existing snapshot loader directly
- `test/features/feed/application/feed_projection_test.dart`
  - extend only if production changes move into snapshot/projection ownership
- `lib/features/feed/domain/models/feed_item.dart`
  - read-only unless the new regression disproves the current getter contract
- `test/features/feed/integration/feed_card_flow_test.dart`
  - only if widget-level proof cannot honestly pin the user-visible seam

### Existing Tests Covering This Area

- `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `incoming message clears session reply so card shows open mode`
  - `tap to expand works after inline reply from collapsed card`
  - `inline reply shows session reply immediately before network completes`
- `test/features/feed/application/feed_projection_test.dart`
  - `mark-read transition matches cold load`
- `test/features/feed/integration/feed_card_flow_test.dart`
  - `session reply cleared on incoming allows open mode to show`
- These tests currently pass, but none pins
  `A1 incoming -> B1 inline reply -> A2 incoming -> older unread excluded`.

### Regression/Tests To Add First

- Add a widget regression in
  `test/features/feed/presentation/screens/feed_wired_test.dart` that:
  1. seeds earlier incoming unread `A1`;
  2. performs a successful inline reply `B1` from Feed;
  3. proves the post-reply state is collapsed/replied and no longer exposes
     `A1` as unread preview content;
  4. injects later incoming `A2`;
  5. proves open-mode preview shows `A2` but not `A1`.
- If the same stale seam only becomes obvious with one extra history row, keep
  that proof in the same widget suite rather than creating a new harness.
- Do not add a new integration test first. Current evidence says the gap is the
  feed-owned state refresh seam, while `feed_card_flow_test.dart` already
  covers the card primitive behavior underneath it.

### Step-By-Step Implementation Plan

1. Add the failing widget regression in
   `test/features/feed/presentation/screens/feed_wired_test.dart` for the exact
   `A1 -> B1 -> A2` sequence.
2. Change only the successful 1:1 inline-reply branch in
   `lib/features/feed/presentation/screens/feed_wired.dart` so the post-send
   card state comes from a fresh post-read contact snapshot before later
   incremental merges depend on it.
3. Prefer the existing targeted refresh path over unread-model rewrites. Stop
   if the new regression passes and adjacent feed tests stay green.
4. Only if that narrow fix cannot preserve behavior, reuse the existing contact
   snapshot loader or projection helper in the smallest local way. Do not alter
   `ThreadFeedItem.unreadMessages` or broader feed projection ownership unless
   the new regression proves those layers are actually wrong.
5. Re-run direct feed widget tests. Only update
   `test/features/feed/application/feed_projection_test.dart` or
   `test/features/feed/integration/feed_card_flow_test.dart` if the chosen
   production seam truly moved there.
6. Run the required named gates and stop. Do not widen into notification-open,
   transport, or group surfaces from this session.

### Risks And Edge Cases

- Breaking optimistic session-reply rendering before the send completes.
- Clearing draft, quote, or session-reply state during a targeted post-read
  refresh.
- Regressing reopen-on-incoming or expand-after-reply behavior already covered
  by existing feed widget tests.
- Losing attachment/reaction decoration if the refresh path replaces a contact
  snapshot incorrectly.
- Longer same-contact histories where only the truly unread tail should reopen.

### Exact Tests And Gates To Run

- Direct suite:
  - `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- Conditional direct suites if touched:
  - `flutter test test/features/feed/application/feed_projection_test.dart`
  - `flutter test test/features/feed/integration/feed_card_flow_test.dart`
- Named gates:
  - `./scripts/run_test_gates.sh feed`
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
- Named gate scope from `Test-Flight-Improv/test-gate-definitions.md`:
  - `feed`:
    `test/features/feed/integration/feed_card_flow_test.dart`,
    `test/features/feed/integration/expanded_collapsed_card_test.dart`,
    `test/features/feed/integration/feed_color_smoke_test.dart`
  - `1to1`:
    `test/features/conversation/integration/two_user_message_exchange_test.dart`,
    `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`,
    `test/features/conversation/integration/media_attachment_flow_test.dart`,
    `test/features/conversation/integration/media_retry_smoke_test.dart`,
    `test/features/conversation/integration/voice_message_exchange_test.dart`,
    `test/features/conversation/integration/incomplete_upload_recovery_test.dart`,
    `test/features/conversation/integration/send_then_lock_delivery_test.dart`,
    `test/features/conversation/integration/stuck_sending_recovery_test.dart`,
    `test/features/conversation/integration/quote_reply_thread_test.dart`
  - `baseline`:
    `test/features/identity/presentation/screens/startup_router_recovery_test.dart`,
    `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`,
    `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`,
    `integration_test/loading_states_smoke_test.dart`,
    `integration_test/posts_phase1_fake_test.dart`,
    `test/features/groups/integration/group_messaging_smoke_test.dart`
- Do not run `./scripts/run_test_gates.sh transport` unless the final diff
  reaches bridge, resume, reconnect, bootstrap, or inbox-drain behavior.

### Known-Failure Interpretation

- Treat any failure in the new `A1 -> B1 -> A2` regression or the existing feed
  inline-reply widget tests as Session 1-relevant until disproven.
- Treat failures inside the named `feed`, `1to1`, or `baseline` gate files as
  blocking unless there is concrete evidence they were pre-existing and outside
  the feed inline 1:1 seam.
- Do not mark a named-gate failure unrelated without naming the exact file/test
  and why its seam is out of scope.
- Ignore dependency-version chatter from `flutter test` package resolution
  output; only actual test failures affect acceptance.

### Done Criteria

- The new `A1 -> B1 -> A2` regression exists, fails before the fix, and passes
  after it.
- Successful feed inline reply uses truthful post-read state for the card.
- Later incoming reopens the card with only genuinely unread rows.
- Existing adjacent feed inline-reply behaviors remain green.
- Required direct suites and named gates pass, or any unrelated pre-existing
  failure is documented explicitly with evidence.

### Scope Guard

- Do not redesign unread-count UX, read-receipt semantics, feed/conversation
  routing, notification-open behavior, or transport/bootstrap behavior.
- Do not widen into group-thread parity unless the new failing regression proves
  shared code corruption.
- Do not edit frozen gate definitions for this session.
- Overengineering for Session 1 would include moving general feed projection
  ownership out of `feed_wired.dart`, rewriting unread getters in
  `feed_item.dart`, or adding a new shared architecture layer without a failing
  regression that forces it.

### Accepted Differences / Intentionally Out Of Scope

- Report `40` stays interpreted as a feed-owned unread-projection seam, not a
  notification-route/callback rewrite.
- Companion `1to1` gate coverage is required, but Session 1 does not reopen the
  broader 1:1 reliability closure bar.
- Higher-layer integration expansion remains optional only if the widget
  regression cannot honestly protect the visible seam.
- Group inline-reply behavior stays untouched unless the new regression proves
  the same bug through shared code.

### Dependency Impact

- Session `7` depends on Session 1 landing with the permanent regression and
  required gate evidence before closure docs can be trusted.
- Sessions `2` through `6` remain independent because this plan does not touch
  their send/delete/notification/intro seams.
- If implementation unexpectedly requires transport or notification-root work,
  stop and reclassify instead of silently absorbing that scope here.

## Reviewer

- Sufficiency verdict: `sufficient with adjustments`, now patched into the
  final plan.
- Missing before patch:
  - explicit proof that the seam is still live in current code
  - explicit executed spot checks
  - a stronger stop rule keeping `feed_item.dart` and snapshot helpers out of
    default edit scope
- After patch:
  - all mandatory sections are present
  - regression-first execution is explicit
  - exact named gates are explicit
  - the decomposition is narrow enough to avoid hallucinated architecture work

## Arbiter

### Structural Blockers Remaining

- none

### Incremental Details Intentionally Deferred

- Whether the adjacent longer-thread proof belongs in the main widget
  regression or a second nearby widget test.
- Whether `test/features/feed/application/feed_projection_test.dart` needs an
  extra parity assertion; only revisit if production changes move there.
- Whether `test/features/feed/integration/feed_card_flow_test.dart` needs a new
  assertion after the widget regression lands.

### Accepted Differences Intentionally Left Unchanged

- No gate-definition edits.
- No closure-doc refresh beyond this plan file; Session `7` owns final matrix
  and index updates.
- No `transport` gate unless the implementation blast radius changes.

## Exact Docs/Files Used As Evidence

- Docs:
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps-session-breakdown.md`
  - `Test-Flight-Improv/43-30-41-audit-follow-up-remaining-gaps.md`
  - `Test-Flight-Improv/40-feed-stack-card-keeps-earlier-notification-messages-after-inline-reply-session-breakdown.md`
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Production files:
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - `lib/features/feed/domain/models/feed_item.dart`
  - `lib/features/feed/application/load_contact_feed_snapshot_use_case.dart`
- Test files:
  - `test/features/feed/presentation/screens/feed_wired_test.dart`
  - `test/features/feed/application/feed_projection_test.dart`
  - `test/features/feed/integration/feed_card_flow_test.dart`

## Why The Plan Is Safe Or Unsafe To Implement Now

- Safe to implement now because:
  - the live seam is isolated to one feed-owned success path
  - the missing regression is explicit and reproducible without widening scope
  - adjacent behavior already has passing coverage
  - required named gates are exact and bounded
  - the stop rule prevents silent expansion into projection redesign,
    notification routing, or transport work
- It becomes unsafe only if the new failing regression proves the bug cannot be
  fixed without broader snapshot ownership or cross-surface behavior changes.
  If that happens, stop and reclassify instead of improvising architecture in
  Session 1.
