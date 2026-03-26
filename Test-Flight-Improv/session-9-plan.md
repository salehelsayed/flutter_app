# Session 9 Plan: Add Small Identity Cache

## 1. Scope
- Implement a small in-memory cache inside `lib/features/identity/domain/repositories/identity_repository_impl.dart`.
- This session still needs repository/code edits; validation-only execution is not sufficient because `loadIdentity()` currently does one DB read plus three secure-storage reads per call, and the callers in `lib/main.dart`, `feed_wired.dart`, `settings_wired.dart`, `posts_wired.dart`, `orbit_wired.dart`, and `startup_decision.dart` invoke it repeatedly.
- Keep the change repo-instance scoped only. Do not redesign identity state management, add TTLs, or introduce a shared/global cache.
- Preserve current identity semantics: same identity data, same fallback behavior for pre-migration rows, same save contract, but fewer repeated storage reads on repeated loads.

## 2. Files To Inspect Next
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/identity/domain/repositories/identity_repository.dart`
- `lib/features/identity/application/startup_decision.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/settings/presentation/screens/settings_wired.dart`
- `lib/features/posts/presentation/screens/posts_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/main.dart`
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `test/features/identity/application/startup_decision_test.dart`
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `test/features/identity/presentation/screens/startup_router_test.dart`
- `test/features/settings/presentation/screens/settings_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/settings/integration/profile_picture_flow_test.dart`

## 3. Existing Tests Covering This Area
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart` covers load/save correctness, secure-storage fallback, missing-secret handling, avatar fields, and save write-through behavior.
- `test/features/identity/application/startup_decision_test.dart` covers startup decision behavior around identity presence, but it uses a fake repository and should be treated as caller smoke rather than cache-proof.
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart` already proves startup routing can call `loadIdentity()` more than once during recovery.
- `test/features/identity/presentation/screens/startup_router_test.dart` covers startup decision routing around identity presence.
- `test/features/settings/presentation/screens/settings_wired_test.dart` covers settings-screen identity loading and reload-after-update behavior, but it uses a fake repository and is smoke only for this session.
- `test/features/feed/presentation/screens/feed_wired_test.dart` covers feed initialization that loads identity before building the screen, but it uses a fake repository and is smoke only for this session.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` covers Orbit initialization and identity loading, but it uses a fake repository and should only be used if repository changes surface a caller-specific edge case.
- `test/features/settings/integration/profile_picture_flow_test.dart` is a secondary smoke for identity/profile update behavior, not primary cache proof.

## 4. Regressions / Tests To Add First
- Extend `test/features/identity/domain/repositories/identity_repository_impl_test.dart` with a small counting fake or local counters so the test can prove:
  - repeated `loadIdentity()` calls return the same values
  - repeated loads do not re-hit the DB and secure storage once the cache is warm
  - `saveIdentity()` refreshes the cache so a later load sees the new identity
- Add one repository failure-path regression proving a failed `saveIdentity()` does not poison the cache:
  - warm the cache with an existing identity
  - force a secure-storage write or DB upsert failure during `saveIdentity()`
  - prove the subsequent `loadIdentity()` still returns the last successfully persisted identity rather than unsaved cached data
- Cache `null` results too, and add one explicit repository regression for that path:
  - first load with no DB row returns `null`
  - a later `saveIdentity()` followed by `loadIdentity()` returns the saved identity, not a stale `null`
- Use a counting wrapper or counting fake around secure-storage reads/writes; do not assume the existing `FakeSecureKeyStore` alone can prove cache-hit behavior.
- Do not add a new widget or integration test first unless the repository tests expose a caller-specific regression.

## 5. Step-By-Step Implementation Plan
1. Add private cache state to `IdentityRepositoryImpl` for the last loaded identity, including a cached `null`, and whether the cache has been populated.
2. Update `loadIdentity()` to return the cached value on repeat calls, while preserving the existing flow events and the current DB/secure-storage fallback logic on cache miss.
3. Update `saveIdentity()` so it writes through first and only refreshes the cache after the secure-storage writes and DB upsert succeed.
4. Keep pre-migration fallback behavior intact: DB columns still act as fallback sources when secure storage is empty.
5. Add the repository regression tests first, including the chosen cached-`null` behavior and the counting read-path assertions, then run the direct suites and the baseline gate.
6. Treat caller tests in settings/feed/startup as smoke only. Only pull Orbit or profile-picture smoke into the execution set if the repository cache exposes a caller-specific edge case.
7. If any caller behavior changes unexpectedly, keep the fix local to the repository cache rather than widening scope into the screen layers.

## 6. Risks And Edge Cases
- A partially failed `saveIdentity()` must not leave the cache pointing at unsaved data.
- If the cache stores `null`, repeated onboarding/startup reads should stay correct and a later save must replace the cached `null`.
- Existing flow-event emission should stay stable enough that diagnostics and tests do not regress.
- The cache must not go stale if future code adds another identity mutation path; today `saveIdentity()` is the only runtime app-level mutation path in this repo.
- Required gate handling must use the current rerun result, not older known-failure notes from Session 1.
- Avatar bytes, avatar version, username, and ML-KEM secret handling must remain identical to current behavior after caching is added.

## 7. Exact Tests To Run After Implementation
- `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `flutter test test/features/settings`
- `flutter test test/features/feed`
- `./scripts/run_test_gates.sh baseline`
- If multiple Flutter targets are attached for the integration-backed baseline items, set `FLUTTER_DEVICE_ID=<device-id>` for the baseline rerun.
- Treat the current baseline rerun as authoritative. Stale known-failure notes are documentation only; any new or broadened rerun failure is blocking, and an unchanged unrelated rerun failure may be explicit follow-up only if the direct suites are green and the current output proves it is outside Session 9 scope.

## 8. Subsystem Gate(s) And Whether Startup/Transport Tests Are Needed
- Required subsystem gate: Baseline Gate.
- Startup / Transport tests are not needed for this session because the scope is repository-local identity caching, not bootstrap, resume, relay fallback, or device/simulator transport behavior.
- No 1:1, feed, posts, or transport gate is required beyond the baseline for this slice.
- Gate handling rule for execution: the baseline script rerun is the source of truth for Session 9. Do not decide status from older gate notes alone.

## 9. Done Criteria
- `IdentityRepositoryImpl` uses a small in-memory cache and still returns the same identity data as before.
- Repeated `loadIdentity()` calls no longer perform repeated DB and secure-storage reads once the cache is warm.
- The chosen cached-`null` behavior is explicit and covered by repository regression tests.
- A failed `saveIdentity()` leaves the cache on the last successfully persisted identity and is covered by repository regression tests.
- `saveIdentity()` refreshes the cache so callers see the updated identity immediately after save.
- The direct identity, settings, and feed suites pass, and the Baseline Gate passes.
- The change stays inside the repository-level cache scope with no identity-state redesign.

## 10. Explicit Assumptions For Review
- `IdentityRepositoryImpl` is the only runtime app-level identity writer in this session's scope, so invalidating or refreshing on `saveIdentity()` is sufficient.
- The cache is in-memory only and scoped to one repository instance; it does not need persistence across app restarts.
- There is no `deleteIdentity()` path to handle today, so no extra invalidation branch is required.
- Caching `null` is acceptable in this repo as long as `saveIdentity()` replaces the cached `null` immediately and the repository regression proves that path.
- Caller tests in Orbit and profile-picture flows are smoke only; treat them as follow-up only if the repository cache itself is correct and the required direct suites remain green.
