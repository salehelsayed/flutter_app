# Session 8 Plan: Cache Posts Schema Capabilities / Remove Hot-Path PRAGMA Checks

## 1. Scope
- Validate the helper-local posts schema capability cache already present in the worktree, and only patch helper code or tests if current verification shows a gap.
- Keep the scope limited to schema capability detection and reuse for the existing helper functions in the posts DB layer.
- Prefer a helper-local or DB-instance-local capability cache over broader repository or query rewrites.
- Do not add new product behavior, rewrite feed queries, or broaden into unrelated database cleanup.
- This session is expected to be validation-only if the current helper/test footprint already proves the contract.

## 2. Files To Inspect Next
- `lib/core/database/helpers/posts_db_helpers.dart`
- `lib/core/database/helpers/post_passes_db_helpers.dart`
- `lib/core/database/helpers/post_recipients_db_helpers.dart`
- `lib/core/database/helpers/post_repost_state_db_helpers.dart`
- `lib/core/database/helpers/post_schema_capabilities.dart`
- `test/core/database/migrations/027_posts_core_test.dart`
- `test/core/database/migrations/028_posts_engagement_test.dart`
- `test/core/database/migrations/029_posts_nearby_test.dart`
- `test/core/database/migrations/030_posts_pass_along_test.dart`
- `test/core/database/migrations/032_posts_retry_recipient_context_test.dart`
- `test/core/database/migrations/035_posts_repost_delivery_state_test.dart`
- `test/core/database/migrations/036_posts_pass_encrypted_snapshots_test.dart`
- `test/core/database/migrations/037_posts_repost_engagement_state_test.dart`
- `test/core/database/migrations/040_posts_repost_visual_metrics_test.dart`
- `test/features/posts/phase1/posts_core_repository_test.dart`
- `test/features/posts/phase2/load_posts_feed_viewer_metrics_query_test.dart`
- `test/features/posts/phase2/posts_engagement_repository_test.dart`
- `test/features/posts/phase4/posts_pass_repository_test.dart`
- `test/core/database/helpers/posts_db_helpers_test.dart`
- `test/core/database/helpers/post_passes_db_helpers_test.dart`
- `test/core/database/helpers/post_recipients_db_helpers_test.dart`
- `test/core/database/helpers/post_repost_state_db_helpers_test.dart`
- `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart`
- `test/features/posts/phase5/posts_pins_repository_test.dart`

## 3. Existing Tests Covering This Area
- `test/core/database/migrations/027_posts_core_test.dart` covers the base `posts` and `post_recipients` tables.
- `test/core/database/migrations/028_posts_engagement_test.dart` covers `media_kind` and `last_engagement_at` on `posts`.
- `test/core/database/migrations/029_posts_nearby_test.dart` covers nearby-related columns such as `nearby_distance_m`.
- `test/core/database/migrations/030_posts_pass_along_test.dart` covers `post_passes`.
- `test/core/database/migrations/032_posts_retry_recipient_context_test.dart` covers the retry-recipient context columns on `post_recipients`.
- `test/core/database/migrations/035_posts_repost_delivery_state_test.dart` covers `delivery_owner_kind` / `delivery_owner_id` on `post_recipients`.
- `test/core/database/migrations/036_posts_pass_encrypted_snapshots_test.dart` covers `inner_payload_json` on `post_passes`.
- `test/core/database/migrations/037_posts_repost_engagement_state_test.dart` covers the base `post_repost_projection_state` table before `shared_to_count_baseline` is introduced.
- `test/core/database/migrations/040_posts_repost_visual_metrics_test.dart` covers `recipient_count` on `post_passes` and `shared_to_count_baseline` on `post_repost_projection_state`.
- `test/core/database/helpers/posts_db_helpers_test.dart` already validates legacy versus expanded schema behavior for `dbInsertPost`, `dbLoadPost`, and `dbLoadPostsFeed`.
- `test/core/database/helpers/post_passes_db_helpers_test.dart` already validates pass upserts and retryable outgoing pass filtering across legacy and expanded schemas.
- `test/core/database/helpers/post_recipients_db_helpers_test.dart` already validates recipient delivery writes and reads across legacy and expanded schemas.
- `test/core/database/helpers/post_repost_state_db_helpers_test.dart` already validates `shared_to_count_baseline` stripping and preservation across legacy and newer schemas.
- `test/features/posts/phase1/posts_core_repository_test.dart` exercises `dbInsertPost`, `dbLoadPost`, `dbLoadPostsFeed`, and recipient delivery round trips on the newer schema.
- `test/features/posts/phase2/load_posts_feed_viewer_metrics_query_test.dart` proves the query-layer metrics path that depends on `recipient_count`.
- `test/features/posts/phase4/posts_pass_repository_test.dart` exercises pass persistence and repost/share baseline behavior that depends on `post_passes`, `post_recipients`, and repost state helpers.
- `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart` and `test/features/posts/phase5/posts_pins_repository_test.dart` provide broader repository coverage against the same posts helper stack.

## 4. Regressions/Tests To Add First
- Add or confirm one explicit helper-level cache-boundary regression for `post_schema_capabilities.dart` before accepting validation-only execution.
- Preferred shape: `test/core/database/helpers/post_schema_capabilities_test.dart`, or the smallest equivalent extension to an existing helper test if that keeps the signal tighter.
- Minimum contract for that regression:
- open separate legacy and newer `Database` instances
- load capabilities on both in an order that would reveal stale `Expando` reuse
- prove legacy and newer DBs keep distinct capability sets for columns such as `media_kind`, `last_engagement_at`, `recipient_count`, and `shared_to_count_baseline`
- If the worktree already contains that regression by the time execution starts, validation-only remains acceptable; otherwise add it first before relying on the cache.
- Reuse migration setup that creates older and newer schema states explicitly; do not simulate "old schema" by mocking database rows.

## 5. Step-by-Step Implementation Plan
1. Inspect the current helper functions and the `post_schema_capabilities.dart` cache to confirm that the hot-path helpers now read capability state from a DB-local cache instead of per-call `PRAGMA table_info(...)`.
2. Confirm the migration evidence set covers every schema branch the cache reads, including `028_posts_engagement_test.dart` and `037_posts_repost_engagement_state_test.dart`, not just the later nearby/pass/repost-visual migrations.
3. Verify the existing helper tests in `test/core/database/helpers/` cover the legacy and expanded schema branches for `posts`, `post_passes`, `post_recipients`, and `post_repost_projection_state`.
4. Add the cache-boundary regression first if it is still missing, then run the direct helper suites and the broader posts feature suites to confirm the cache does not change behavior.
5. Run the required subsystem gate and baseline gate using the current rerun output as the source of truth.
6. If validation exposes a gap, patch only the smallest helper-level code or test issue and rerun the affected direct suite plus any impacted gate.
7. Keep migrations and `lib/main.dart` unchanged unless a currently failing verification result proves the schema chain itself is incomplete.

## 6. Risks And Edge Cases
- The main correctness risk is stale capability state. If the cache survives across different `Database` instances or schema versions, helpers could strip the wrong columns or execute the wrong query shape.
- Another risk is partial caching. Leaving one helper hot path on per-call PRAGMA while the others use cached capabilities would undercut the intended behavior change and make reasoning inconsistent.
- Legacy-schema coverage still matters because these helpers intentionally support columns introduced across migrations `029`, `032`, `035`, `036`, and `040`; a cache that only matches the latest schema would break upgrade safety.
- Legacy coverage also includes `028` and `037`, because the cache reads `posts` engagement columns and `post_repost_projection_state` before `shared_to_count_baseline` exists.
- This session should not turn into a general posts-query optimization pass. Rewriting `dbLoadPostsFeed` or single-post hydration logic is outside scope unless validation proves a compatibility issue.
- If the cache ends up depending on migration order or database version constants, that is a warning sign; the safer contract is capability-by-opened-schema, not version-by-assumption.
- The Posts / Privacy Gate already includes heavier integration-backed tests, and some of those may still be environment-sensitive on macOS. Execution should record current evidence rather than weaken the gate definition.

## 7. Exact Tests To Run After Implementation
- `flutter test test/core/database/helpers`
- `flutter test test/core/database/helpers/post_schema_capabilities_test.dart` if added
- `flutter test test/core/database/helpers/posts_db_helpers_test.dart` only if narrower isolation is needed during RED/GREEN
- `flutter test test/core/database/helpers/post_passes_db_helpers_test.dart` only if narrower isolation is needed during RED/GREEN
- `flutter test test/core/database/helpers/post_recipients_db_helpers_test.dart` only if narrower isolation is needed during RED/GREEN
- `flutter test test/core/database/helpers/post_repost_state_db_helpers_test.dart` only if narrower isolation is needed during RED/GREEN
- `flutter test test/core/database/migrations`
- `flutter test test/features/posts`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh posts`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Treat the current `posts` and `baseline` gate reruns as authoritative. Record any failing gate item from current evidence instead of relying on older notes.
- Gate disposition rule:
- any new or broadened failure in `posts` or `baseline` after the Session 8 changes is blocking
- an unchanged rerun failure may be carried only as explicit follow-up if the direct helper/migration/posts suites stay green and the rerun output shows the failure is pre-existing or environment-bound rather than a cache regression

## 8. Subsystem Gates And Whether Startup/Transport Tests Are Needed
- Required subsystem gate: `Posts / Privacy Gate`.
- Required baseline gate: `Baseline Gate`.
- Startup / transport tests are not needed.
- Reason: this session stays inside posts database helpers and schema-compatibility logic. It does not modify transport/bootstrap/resume code, relay behavior, or device-only startup recovery flows.
- Gate handling rule for execution: the `posts` and `baseline` gates must both be rerun, and the current rerun results are the source of truth for Session 8. Any new or broadened rerun failure is blocking. An unchanged rerun failure may be explicit follow-up only if the direct helper/migration/posts suites are green and the rerun output shows the failure is unrelated to the Session 8 cache/helper scope.

## 9. Done Criteria
- The helper cache in `post_schema_capabilities.dart` is the source of truth for posts schema capability detection in the current worktree.
- A dedicated cache-boundary regression proves separate legacy and newer `Database` instances do not reuse stale schema capabilities.
- Helper-level regressions prove older and newer schema states still behave correctly for posts, post passes, recipient deliveries, and shared-to baseline logic.
- Repository/posts feature behavior remains stable under the existing posts test suites.
- The `Posts / Privacy Gate` and `Baseline Gate` are run for this session.
- Any `posts` or `baseline` gate failure is evaluated from the current rerun output, not copied forward from older gate notes, and only unchanged unrelated rerun failures may be deferred as explicit follow-up.
- No broad query rewrite, generic cache layer, or unrelated migration churn is introduced.

## 10. Explicit Assumptions For Review
- I am assuming Session 8 can be concluded with validation only if the current helper/test footprint passes as written; no new migration or database-version bump is expected.
- I am assuming validation-only is safe only after the cache-boundary regression exists and passes, because the new cache introduces a DB-instance reuse risk that older helper tests did not cover directly.
- I am assuming helper-level tests are the right proving layer because the risky behavior is schema-shape branching inside DB helpers, not posts UI orchestration.
- I am assuming `post_repost_state_db_helpers.dart` belongs in scope only for the shared `shared_to_count_baseline` capability path.
- I am assuming the current integration-backed `Posts / Privacy Gate` should be rerun as-is and judged from the current rerun output, even if some macOS-backed integration files remain environment-sensitive.
- I am assuming `./scripts/run_test_gates.sh completeness-check` is only needed if the validation step changes the integration/gate inventory.
