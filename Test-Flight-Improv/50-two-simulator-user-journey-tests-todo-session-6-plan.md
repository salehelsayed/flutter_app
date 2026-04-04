# Session 6 Plan: Posts create, media, engagement, and comment direct integration proof

## Real scope

- Close the remaining Session 6 coverage asks for `11.1`, `11.2`, `11.3`,
  and `11.4` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Treat the current `integration_test/posts_phase1_fake_test.dart` and
  `integration_test/posts_phase2_fake_test.dart` as the primary live seam,
  because they already prove sender/receiver fake-network delivery with the
  real posts listeners and repositories.
- Add the minimum extra direct proof needed so the repo has one honest
  cross-user posts journey that spans create/discovery, media, heart, and
  comment continuity.
- Keep `11.5` out of scope because the audit already marks pass-along as
  sufficiently covered.

## Closure bar

Session 6 is good enough when the repo has direct automated evidence that:

- a user can create a plain or media post and another user discovers it through
  the existing posts listener/feed seam,
- media metadata survives the sender-to-receiver journey for a normal post,
- another user can heart that post and the original sender observes the
  resulting persisted engagement state, and
- another user can comment on that post and the original sender observes the
  resulting persisted comment continuity, including offline replay if that is
  the cheapest honest proof.

The session should stay test-only unless the new posts fake integration
exposes a real production bug.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with current repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The posts repo already has strong adjacent coverage, but the direct evidence is
fragmented:

- `integration_test/posts_phase1_fake_test.dart` proves post creation plus live
  delivery and offline replay, which already gets close to `11.1`.
- `integration_test/posts_phase2_fake_test.dart` proves offline comment replay,
  deduped hearts, and media-post persistence/reload, but it does not yet give
  one concise cross-user create/media/heart/comment arc in the same direct
  flow.
- `test/features/posts/phase2/posts_wired_comments_test.dart`,
  `test/features/posts/phase2/load_posts_feed_engagement_test.dart`, and
  `test/features/posts/phase2/post_card_media_test.dart` already cover the
  UI/feed projection side of comments, heart counts, and media rendering.

The missing work is therefore likely one added fake-network integration test in
the existing phase-2 suite, not a posts architecture change.

## Files and repos to inspect next

Primary direct tests:

- `integration_test/posts_phase1_fake_test.dart`
- `integration_test/posts_phase2_fake_test.dart`
- `test/features/posts/phase1/post_notification_open_flow_test.dart`
- `test/features/posts/phase2/posts_wired_comments_test.dart`

Adjacent supporting evidence:

- `test/features/posts/phase2/load_posts_feed_engagement_test.dart`
- `test/features/posts/phase2/post_card_media_test.dart`

Production files only if a failing proof shows a real bug:

- `lib/features/posts/application/send_post_use_case.dart`
- `lib/features/posts/application/post_listener.dart`
- `lib/features/posts/application/send_post_reaction_use_case.dart`
- `lib/features/posts/application/send_post_comment_use_case.dart`
- `lib/features/posts/application/post_reaction_listener.dart`
- `lib/features/posts/application/post_comment_listener.dart`

## Existing tests covering this area

- `posts_phase1_fake_test.dart` already gives a direct create/discovery and
  offline replay path for ordinary posts.
- `posts_phase2_fake_test.dart` already gives direct comment replay and heart
  dedupe, plus media-post snapshot/reload coverage.
- `posts_wired_comments_test.dart` already proves comment-sheet UI refresh and
  local submission behavior.
- `load_posts_feed_engagement_test.dart` already proves feed projection counts
  for comments and hearts.
- `post_card_media_test.dart` already proves post-card media rendering basics.

## Regression/tests to add first

- Extend `integration_test/posts_phase2_fake_test.dart` with one concise
  cross-user image-post journey:
  sender creates a media post, recipient discovers it, hearts it, comments on
  it, and the sender observes the persisted heart/comment state.
- Prefer an offline-replay comment leg if it closes the continuity gap without
  introducing extra harness code.
- Keep the landing test-only unless the direct flow exposes a real posts bug.

## Step-by-step implementation plan

1. Re-read the Session 6 rows in the coverage audit and the current fake posts
   integration tests.
2. Add one direct phase-2 fake integration scenario inside
   `integration_test/posts_phase2_fake_test.dart` that covers `11.1` through
   `11.4` in one ordinary posts journey.
3. Reuse the existing fake network, routers, posts listeners, secure key
   store, and media upload stubs already present in that file.
4. Avoid new infrastructure or production changes unless the new test fails for
   a real product reason.
5. Run the exact direct Session 6 suites.
6. Run `./scripts/run_test_gates.sh posts`.
7. Run `./scripts/run_test_gates.sh baseline` only if execution touches shared
   startup or app-root production paths.

## Risks and edge cases

- The new posts proof must stay truly cross-user; a sender-only media reload
  test is not enough.
- A posts fake integration can accidentally duplicate coverage already owned by
  the notification-open or comments-sheet widget tests; keep the scope on
  end-to-end continuity, not routing chrome.
- Do not widen into pass-along or repost-thread scope; Session 6 owns only the
  plain post create/media/heart/comment journey.

## Exact tests and gates to run

Direct suites required for Session 6:

```bash
flutter test --no-pub integration_test/posts_phase1_fake_test.dart integration_test/posts_phase2_fake_test.dart test/features/posts/phase1/post_notification_open_flow_test.dart test/features/posts/phase2/posts_wired_comments_test.dart test/features/posts/phase2/load_posts_feed_engagement_test.dart test/features/posts/phase2/post_card_media_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh posts
```

Conditional named gate:

```bash
./scripts/run_test_gates.sh baseline
```

Run `baseline` only if execution touches shared Flutter production paths beyond
posts-owned files.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 6 direct suites or the `posts` gate fails.
- If the existing phase fake tests already close one of the audit rows without
  new code, record that honestly instead of forcing redundant edits.

## Done criteria

- Session 6 has direct proof or honest reclassification for `11.1`, `11.2`,
  `11.3`, and `11.4`.
- The exact direct suites are green.
- `./scripts/run_test_gates.sh posts` is green.
- No posts architecture or startup scope was pulled in unnecessarily.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No pass-along or repost-thread redesign.
- No app-root routing or notification-open changes.
- No group or 1:1 work.
- No gate-definition edits unless a new permanent suite truly needs
  classification.

## Accepted differences / intentionally out of scope

- Session 6 may use the existing phase fake harness rather than inventing a new
  posts-only driver.
- Session 6 does not own the final matrix refresh; Session `10` still does.

## Dependency impact

- Session `6` remains independent of Sessions `1`-`5`, but Session `10` should
  refresh the stable matrix rows against the landed posts evidence.
