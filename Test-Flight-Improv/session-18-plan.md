# Session 18 Plan: Reduce Repeated Single-Post Lookups In Pinned Paths

**Date:** 2026-03-26
**Status:** Plan only

## 1. real scope

Remove the still-real repeated single-post fetch loop in the pinned-post load path before considering any heavier posts SQL work.

Concrete repo evidence:
- `lib/features/posts/application/load_pinned_posts_use_case.dart` still does:
  - `final activePins = await postRepo.loadActivePinStates();`
  - then a `for` loop with `await postRepo.getPost(pinState.postId)` for each pin
- `lib/features/posts/domain/repositories/post_repository_impl.dart` maps `getPost(...)` to `dbLoadPost(...)`
- `lib/core/database/helpers/posts_db_helpers.dart` shows `dbLoadPost(...)` is still the heavy single-post query with the same multi-join projection shape used by feed/post surfaces
- `lib/features/posts/application/load_posts_feed_use_case.dart` already uses `postRepo.loadFeed()` once and then batch-ish surface hydration helpers, so the older broad framing of “heavy post query once per feed post” is stale

This makes the broad old report partially stale, but the remaining Session 18 issue is still real and narrow:
- stale part: the feed path is not doing one `getPost()` per rendered post
- still-real part: pinned-post loading still amplifies `dbLoadPost(...)` by calling it once per active pin

Inspect-but-do-not-assume scope expansion:
- `lib/features/posts/application/post_notification_open_coordinator.dart` still polls `postRepository.getPost(target.postId)` when post changes arrive
- `lib/features/posts/presentation/screens/posts_wired.dart` still does `widget.postRepo.getPost(target.postId)` inside `_tryResolvePendingTarget()`

These are relevant one-by-one paths to inspect, but the minimum safe Session 18 target is the pinned loop first.

Out of scope:
- materialized views
- generic query caches
- broad hydrator rewrites
- comment/reaction batching across the whole posts surface
- notification/open-flow redesign unless the same narrow repository contract fixes it trivially

## 2. session classification

`implementation-ready`

Why:
- `Test-Flight-Improv/05-database-storage-performance.md` already narrows this to a concrete implementation target rather than a profiling question
- the hot path is directly visible in `load_pinned_posts_use_case.dart`
- `dbLoadPost(...)` is still the expensive join-backed single-post loader in `posts_db_helpers.dart`
- the repo already uses batch loaders elsewhere (`loadPostMediaAttachmentsForPosts`, `loadRepostHeartBaselinePeerIdsForPosts`, `loadPassAvatarSnapshotsForPosts`, `loadViewerSharedToCountsForPosts`), so a narrow bulk post-load contract is a consistent next step

Still real or stale:
- stale as a broad “posts query architecture rewrite now” claim
- still real as a focused repeated-`getPost()` pinned-path issue

## 3. files and repos to inspect next

Primary production files:
- `lib/features/posts/application/load_pinned_posts_use_case.dart`
- `lib/features/posts/domain/repositories/post_repository.dart`
- `lib/features/posts/domain/repositories/post_repository_impl.dart`
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/features/posts/application/post_surface_hydrator.dart`
- `lib/main.dart` if a new repository helper/contract needs production constructor wiring

Inspect-only adjacent call sites:
- `lib/features/posts/presentation/screens/posts_wired.dart`
- `lib/features/posts/application/post_notification_open_coordinator.dart`

Primary tests and fakes:
- `test/features/posts/phase5/load_pinned_posts_use_case_test.dart`
- `test/features/posts/phase1/posts_core_repository_test.dart`
- `test/features/posts/phase5/handle_incoming_post_pins_use_case_test.dart`
- `test/features/posts/phase5/posts_wired_pinned_section_test.dart`
- `test/features/posts/phase1/post_notification_open_flow_test.dart`
- `test/features/posts/phase1/posts_wired_test.dart`
- `test/features/posts/phase5/posts_pins_repository_test.dart`
- `test/features/posts/improvement/post_delivery_runner_test.dart`
- `test/shared/fakes/in_memory_post_repository.dart`

## 4. existing tests covering this area

Current useful coverage:
- `test/features/posts/phase5/load_pinned_posts_use_case_test.dart` already proves:
  - active pins load
  - local dismissals hide pinned posts
  - pinned posts remain or leave the normal feed based on age
- `test/features/posts/phase5/handle_incoming_post_pins_use_case_test.dart` already protects pin state transitions and missing-post tolerance behavior
- `test/features/posts/phase5/posts_wired_pinned_section_test.dart` already protects recipient pinned-section rendering and removal behavior
- `test/features/posts/improvement/post_pin_remove_delivery_integration_test.dart` already covers real pin/remove delivery behavior
- `test/features/posts/phase1/post_notification_open_flow_test.dart` and `test/features/posts/phase1/posts_wired_test.dart` already cover pending-target open/focus behavior

What is missing:
- no current regression proves `loadPinnedPosts(...)` avoids one-by-one `getPost()` calls
- no repository/helper test currently covers a bulk post-by-IDs contract because that contract does not exist yet

## 5. regression/tests to add first, if any

Add one focused regression first at the pinned use-case layer.

Preferred first regression:
- extend `test/features/posts/phase5/load_pinned_posts_use_case_test.dart`
- use a counting fake repository built on `InMemoryPostRepository`
- prove the pinned loader:
  - does not depend on per-pin `getPost()` calls once the new contract lands
  - preserves active-pin ordering from `loadActivePinStates()`
  - still skips dismissed pins
  - still tolerates missing post rows
  - still returns hydrated surface-ready posts

If the implementation introduces a repository/helper bulk contract:
- add or extend one repository-level proving test in `test/features/posts/phase1/posts_core_repository_test.dart` to prove the bulk load returns the expected posts for a supplied ID set
- if the batch contract is introduced directly at the DB-helper layer first, add the narrow helper assertion at that seam instead of forcing pin-state tests to prove row mapping
- let the use case remain responsible for restoring pin-state order if SQL returns rows in a different order

Do not add notification-open regressions first unless those files are actually changed.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not required. This session is not profile-gated.

The necessary evidence is already concrete in code:
- `loadPinnedPosts(...)` loops `getPost(...)`
- `getPost(...)` goes through `dbLoadPost(...)`
- `dbLoadPost(...)` is the heavy single-post join projection
- `loadPostsFeed(...)` already avoids that repeated-single-post pattern on the normal feed path

## 7. step-by-step implementation or evidence-collection plan

1. Reconfirm the narrow target by reviewing `load_pinned_posts_use_case.dart`, `post_repository.dart`, `post_repository_impl.dart`, and `posts_db_helpers.dart`.
2. Keep the broad stale-vs-real call explicit:
   - broad feed rewrite is not justified here
   - pinned repeated `getPost()` is still real
3. Add the RED regression in `test/features/posts/phase5/load_pinned_posts_use_case_test.dart` with a counting fake repository.
4. Introduce the smallest bulk-load contract needed for this session, most likely a repository method such as `loadPostsByIds(List<String> postIds)`.
5. Back that contract in `PostRepositoryImpl` with a narrow DB/helper addition in `posts_db_helpers.dart` that loads the same post projection for a bounded ID set.
6. If that contract is constructor-injected into `PostRepositoryImpl`, wire the new dependency in `lib/main.dart` so production instantiation matches the new repository shape.
7. Update `InMemoryPostRepository` to support the same contract so existing test style remains deterministic.
8. Update `loadPinnedPosts(...)` to:
   - load active pin states
   - filter dismissed pins
   - bulk-load candidate posts once
   - restore current pin-state order in Dart
   - keep missing-post tolerance
   - pass the final list through `hydratePostSurfaceItems(...)` unchanged
9. Reinspect `PostNotificationOpenCoordinator` and `PostsWired._tryResolvePendingTarget()` after the pinned fix lands.
10. Only if the same new contract trivially removes an obvious repeated single-target lookup there without widening the session, apply that minimal follow-up and add the direct pending-target tests.
11. Run targeted tests first, then broader posts suites, then Posts / Privacy Gate, then Baseline Gate.

## 8. risks and edge cases

- A batch SQL/helper path may not preserve the active-pin order from `post_pins`; `loadPinnedPosts(...)` must restore ordering from `loadActivePinStates()`.
- Missing posts must still be tolerated silently, matching current behavior.
- Dismissed pins must still be filtered before hydration.
- `hydratePostSurfaceItems(...)` already batches several side loads, but still loads comments/reactions per post; do not broaden Session 18 into solving that larger question.
- `post_notification_open_coordinator.dart` and `posts_wired.dart` also use `getPost(...)`, but they are single-target wait paths, not the primary pinned loop. Touch them only if the new contract makes the change truly small.
- Do not replace this with a cache or materialized projection layer.

## 9. exact tests to run after implementation, if code changes occur

Targeted tests first:
- `flutter test test/features/posts/phase5/load_pinned_posts_use_case_test.dart`
- `flutter test test/features/posts/phase5/handle_incoming_post_pins_use_case_test.dart`
- `flutter test test/features/posts/phase5/posts_wired_pinned_section_test.dart`
- `flutter test test/features/posts/improvement/post_pin_remove_delivery_integration_test.dart`

If repository/helper contract changes:
- `flutter test test/features/posts/phase1/posts_core_repository_test.dart`

If `lib/core/database/helpers/posts_db_helpers.dart` changes:
- `flutter test test/core/database/helpers/posts_db_helpers_test.dart`

If pending-target open path changes:
- `flutter test test/features/posts/phase1/post_notification_open_flow_test.dart`
- `flutter test test/features/posts/phase1/posts_wired_test.dart`

Broader verification after targeted green:
- `flutter test test/features/posts/phase5`
- `flutter test test/features/posts/improvement`
- `flutter test test/features/posts`

Then gates:
- Posts / Privacy Gate
- Baseline Gate

## 10. subsystem gate(s), if relevant

`Posts / Privacy Gate`

Canonical command from `Test-Flight-Improv/14-regression-test-strategy.md`:

```bash
flutter test \
  integration_test/posts_phase1_fake_test.dart \
  integration_test/posts_phase2_fake_test.dart \
  integration_test/posts_phase3_fake_test.dart \
  integration_test/posts_phase4_fake_test.dart \
  integration_test/posts_phase5_fake_test.dart \
  test/features/posts/phase3/post_presence_listener_test.dart
```

## 11. whether Baseline Gate is required

Yes.

Reason:
- Session 18 is implementation-ready, not profiling-only
- changes are expected in Flutter production code under posts repository/use-case/helper paths

## 12. whether Startup / Transport Gate is required

No, in planned scope.

Reason:
- this session is about posts repository/query usage, not transport/startup behavior
- notification open flow may be inspected, but the planned work does not change inbox drain, reconnect, or transport recovery semantics

Re-evaluate only if implementation somehow changes notification-driven drain/recovery ordering outside posts-local behavior.

## 13. done criteria

Session 18 is complete when all of these are true:
- the pinned-post path no longer performs avoidable per-pin `getPost()` lookups
- user-visible pinned behavior is unchanged
- dismissed pins, ordering, hydration, and missing-post tolerance remain correct
- no broad SQL architecture rewrite was introduced

And one of these is true:
- the session fixes only the pinned path and explicitly defers the notification/open-path single-post polling as a separate narrow follow-up
- or the session also removes one of the inspect-only repeated single-post open-path lookups, but only because the same new contract made it trivial

## 14. dependency impact on later sessions if this session blocks

- Session 19 can still proceed independently because its work is index/profiling-gated
- but a blocked Session 18 leaves a real repeated-single-post amplification path in place, which can mask or dilute the value of later posts/storage perf improvements
- later posts performance conclusions should not assume pinned loading has already been normalized unless Session 18 lands

## 15. scope guard

- Do not build a materialized view here.
- Do not introduce project-wide query caches.
- Do not rewrite `hydratePostSurfaceItems(...)` broadly.
- Do not turn this into a generic “replace all `getPost()` calls” sweep.
- Keep the primary target on the pinned loop in `loadPinnedPosts(...)`.
- Only touch `PostNotificationOpenCoordinator` or `PostsWired` if the same narrow repository contract fixes them with negligible extra scope.
