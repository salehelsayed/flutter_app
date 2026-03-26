# Session 10 Plan: Low-Risk Cleanup Pass

## 1. Scope
- Keep this session limited to the confirmed `cupertino_icons` dependency removal only.
- The only confirmed change right now is removing `cupertino_icons` from `pubspec.yaml`, with `pubspec.lock` expected to update via `flutter pub get`.
- Do not delete `lib/smoke_test_main.dart`, `lib/smoke_test_restore.dart`, or `lib/smoke_test_messages.dart`. They are explicit `flutter run -t` entrypoints and remain workflow-dependent.
- Do not modify `C4/infrastructure.md` or `C4_MODEL.md` in this session; they are out of scope even though they still mention `cupertino_icons`.
- Treat this as a dependency-only slice.

## 2. Files To Inspect Next
- `pubspec.yaml`
- `pubspec.lock`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/06-dead-code-lib.md`
- `Test-Flight-Improv/07-dead-code-deps-config.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/15-session-todo-roadmap.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/smoke_test_main.dart`
- `lib/smoke_test_restore.dart`
- `lib/smoke_test_messages.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/posts/phase3/post_presence_listener_test.dart`
- `integration_test/loading_states_smoke_test.dart`
- `integration_test/posts_phase1_fake_test.dart`

## 3. Existing Tests Covering This Area
- There is no direct test for `CupertinoIcons` usage, so the safety net is build and regression validation rather than a file-specific test.
- The nearest broad coverage is `integration_test/loading_states_smoke_test.dart`, `integration_test/posts_phase1_fake_test.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, and `test/features/posts/phase3/post_presence_listener_test.dart`.
- The manual smoke entrypoints are not CI-tested; their status must be decided by search and workflow confirmation, not by automated coverage.

## 4. Regression / Tests To Add First
- None by default.
- If the dependency removal unexpectedly crosses into behavior, add the smallest direct regression in that subsystem before closing out.

## 5. Step-By-Step Implementation Plan
1. Re-run `rg` to confirm `CupertinoIcons` does not appear in `lib/`, `test/`, or `integration_test/`.
2. Remove `cupertino_icons` from `pubspec.yaml`.
3. Run `flutter pub get` so `pubspec.lock` drops the dependency if the resolver no longer needs it.
4. Leave `lib/smoke_test_main.dart`, `lib/smoke_test_restore.dart`, `lib/smoke_test_messages.dart`, `C4/infrastructure.md`, and `C4_MODEL.md` untouched.

## 6. Risks and Edge Cases
- `pubspec.lock` may rewrite more than expected after `flutter pub get`; only the dependency removal should remain in the final diff.
- The manual smoke entrypoints may still be workflow-dependent even if `CupertinoIcons` is unused in code.
- A dependency cleanup can still surface an unexpected build or startup break if something indirect depended on the package.
- `C4/infrastructure.md` and `C4_MODEL.md` are intentionally out of scope for Session 10, even though they still mention `cupertino_icons`.

## 7. Exact Tests To Run After Implementation
- `rg -n "CupertinoIcons" lib test integration_test`
- `flutter pub get`
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`
- Do not add startup / transport runs for this slice unless the cleanup unexpectedly touches bootstrap or resume paths, which it should not.

## 8. Subsystem Gate(s) And Whether Startup/Transport Tests Are Needed
- Baseline Gate is mandatory after every dependency-only slice.
- The current baseline source of truth in this workspace is `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- No subsystem gate is required for this session because the only justified edit is `pubspec.yaml` plus the lockfile refresh.
- Startup / transport tests are not needed unless the cleanup reaches app bootstrap, resume, transport fallback, or device-backed flows.

## 9. Done Criteria
- `cupertino_icons` is removed from `pubspec.yaml`, and `pubspec.lock` no longer lists it after `flutter pub get`.
- Manual smoke entrypoints remain intact unless a later workflow review explicitly retires them.
- `CupertinoIcons` does not appear in `lib/`, `test/`, or `integration_test/`.
- `C4/infrastructure.md` and `C4_MODEL.md` remain unchanged in this session.
- Baseline Gate passes after the cleanup slice.

## 10. Explicit Assumptions For Review
- The current `rg` result is enough to confirm `CupertinoIcons` is unused in app, test, and integration-test code.
- `lib/smoke_test_main.dart`, `lib/smoke_test_restore.dart`, and `lib/smoke_test_messages.dart` are preserved until a product or workflow owner confirms they are obsolete.
- `C4/infrastructure.md` and `C4_MODEL.md` are intentionally out of scope for this session.
- The baseline rerun command is the source of truth for safety on this slice.
