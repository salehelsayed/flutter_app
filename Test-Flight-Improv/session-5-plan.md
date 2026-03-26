# Session 5 Plan: Nearby Post Presence Rejection Matrix

**Final Verdict:** sufficient as revised

## 1. Scope

- Keep Session 5 limited to nearby post-presence validation and privacy correctness in `lib/features/posts/application/handle_incoming_post_presence_use_case.dart` and the thin listener wiring in `lib/features/posts/application/post_presence_listener.dart`.
- Do not expand into broader posts send/delivery work, feed surfaces, startup redesign, or transport/reconnect behavior.
- The roadmap is slightly under-specific here, not structurally stale: `Test-Flight-Improv/01-unit-test-coverage.md` already calls out the missing direct `handle_incoming_post_presence_use_case_test.dart`, so this session should add that regression first.

## 2. Files To Inspect Next

- Primary production contracts:
  - `lib/features/posts/application/handle_incoming_post_presence_use_case.dart`
  - `lib/features/posts/application/post_presence_listener.dart`
- Direct support files:
  - `lib/features/posts/domain/models/contact_presence_snapshot.dart`
  - `lib/features/posts/domain/repositories/contact_presence_snapshot_repository.dart`
  - `test/shared/fakes/in_memory_contact_repository.dart`
  - `test/shared/fakes/in_memory_contact_presence_snapshot_repository.dart`
- Existing adjacent coverage:
  - `test/features/posts/phase3/post_presence_listener_test.dart`
  - `test/features/posts/phase3/nearby_eligibility_service_test.dart`
  - `test/features/posts/phase3/contact_presence_snapshot_repository_test.dart`
  - `test/features/posts/phase3/load_posts_feed_nearby_test.dart`
  - `test/features/posts/phase3/handle_app_resumed_nearby_test.dart`
  - `test/features/posts/phase3/nearby_location_service_test.dart`
  - `test/features/posts/phase3/refresh_nearby_on_startup_use_case_test.dart`
  - `test/core/services/incoming_message_router_posts_presence_test.dart`
  - `test/features/posts/phase1/handle_incoming_post_use_case_test.dart`
  - Optional only if review reaches outbound fanout parity:
    - `test/features/posts/phase3/publish_post_presence_update_use_case_test.dart`
- Only if row-mapping assumptions turn out to matter:
  - `Test-Flight-Improv/05-database-storage-performance.md`

## 3. Existing Tests Covering This Area

- `test/features/posts/phase3/post_presence_listener_test.dart` already covers active snapshot persistence, unknown sender rejection, and inactive snapshot overwrite.
- `test/features/posts/phase3/contact_presence_snapshot_repository_test.dart` covers active and inactive snapshot persistence.
- `test/features/posts/phase3/nearby_eligibility_service_test.dart` covers active direct-friend filtering and stale local snapshot behavior.
- `test/core/services/incoming_message_router_posts_presence_test.dart` covers routing `post_presence_update` envelopes into the listener stream.
- `test/features/posts/phase3/startup_router_nearby_wiring_test.dart` is adjacent startup wiring evidence, but it is not the Session 5 target.
- No direct `handle_incoming_post_presence_use_case_test.dart` exists yet, which is the core gap this session is meant to close.
- `test/features/posts/phase3/publish_post_presence_update_use_case_test.dart` is outbound fanout coverage, so it is adjacent evidence rather than the required core regression for this session.

## 4. Regressions/Tests To Add First

- Add `test/features/posts/phase3/handle_incoming_post_presence_use_case_test.dart` first; that is the direct missing regression.
- Cover one happy path plus the explicit reject matrix: `notPostPresenceUpdate`, `invalidPayload`, `unknownSender`, `blockedSender`, and `staleSnapshot`.
- Within `invalidPayload`, sample each validation class at least once: sender mismatch, malformed or missing ISO8601 timestamps for both `created_at` and `captured_at`, missing payload, missing or unknown status, missing active coordinates, missing inactive reason, and unknown inactive reason.
- Add one explicit case proving `created_at` can be absent and correctly falls back to `message.timestamp`.
- For the stale branch, assert both the returned result and that the previously stored newer snapshot remains unchanged in the repository.
- Prefer return-value and repository-state assertions over plumbing assertions. Only test `emitFlowEvent` behavior if a seam already exposes it cleanly.

## 5. Step-By-Step Implementation Plan

- Re-read the use case and adjacent tests to lock the payload shape, `created_at` fallback behavior, inactive-reason validation, and repository expectations before changing tests.
- Write the direct use-case test file around the in-memory contact and snapshot repositories.
- Add one canonical valid presence update, one explicit `created_at` fallback case, and a focused reject matrix, keeping each test tied to one branch.
- If `post_presence_listener_test.dart` needs a small extension, limit it to proving `snapshotUpdated` still forwards and rejected inputs do not emit snapshots.
- Re-run the new direct test and `post_presence_listener_test.dart` first, then `flutter test test/features/posts`, then the posts gate, then the baseline gate.
- Record known preexisting red gate states instead of weakening the gate list to force a green result.
- Apply the review exit rule: if review finds only incremental details, stop after one patch round; only a structural blocker justifies another pass.

## 6. Risks And Edge Cases

- `created_at` falls back to `message.timestamp`; test at least one canonical payload and one malformed-timestamp rejection.
- `sender_peer_id` must match `message.from`; that spoofing guard should be exercised explicitly.
- Inactive status only accepts `sharing_disabled`, `permission_revoked`, and `services_disabled`; any other reason should fail.
- Stale comparison uses `capturedAt`, not `updatedAt`; tests need older `capturedAt` values to reproduce the guard.
- A stale rejection should preserve the already stored newer snapshot rather than partially mutating state.
- The current posts gate is already documented as red on macOS for `integration_test/posts_phase2_fake_test.dart` through `integration_test/posts_phase5_fake_test.dart`; do not confuse that existing attach issue with a Session 5 regression.
- The current baseline gate is already documented as red because `integration_test/loading_states_smoke_test.dart` no longer builds after `StartupRouter` began requiring `postRepository`; record that as a preexisting gate failure, not a Session 5 regression.
- Do not let nearby presence work pull in send-side or startup lifecycle changes.

## 7. Exact Tests To Run After Implementation

- `flutter test test/features/posts/phase3/handle_incoming_post_presence_use_case_test.dart`
- `flutter test test/features/posts/phase3/post_presence_listener_test.dart`
- `flutter test test/features/posts`
- `flutter test test/core/services/incoming_message_router_posts_presence_test.dart` only if listener/router assertions are extended
- `./scripts/run_test_gates.sh posts`
- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh transport` only if the implementation unexpectedly touches startup, resume, or transport wiring.

## 8. Subsystem Gate(s) And Whether Startup/Transport Tests Are Needed

- Required gate: Posts / Privacy Gate.
- Required gate: Baseline Gate.
- Not required: Startup / Transport Gate, because this session is limited to incoming presence validation and privacy correctness, not bootstrap or reconnect behavior.
- Posts / Privacy Gate is currently known red on macOS for `integration_test/posts_phase2_fake_test.dart` through `integration_test/posts_phase5_fake_test.dart`; rerun it and record whether that state remains unchanged.
- Baseline Gate is currently known red because `integration_test/loading_states_smoke_test.dart` does not build against the current `StartupRouter` constructor; rerun it and record whether that state remains unchanged.
- If the implementation starts touching startup wiring or `lib/main.dart`, that is a scope violation and should be treated as a plan failure, not a reason to widen the gate list.

## 9. Done Criteria

- The direct `handle_incoming_post_presence_use_case_test.dart` exists and covers the happy path plus the explicit reject matrix, including `created_at` fallback and invalid inactive-reason handling.
- Existing listener and adjacent posts tests remain green or need only minimal test-only adjustments.
- `flutter test test/features/posts` has been rerun, and the Posts / Privacy Gate and Baseline Gate have been rerun with preexisting red states documented instead of being mistaken for new regressions.
- No startup/transport changes, no production code redesign, and no broad posts expansion were introduced.
- The review exit rule was honored: stop after the first structural-blocker pass instead of looping on incremental details.

## Structural Blockers Remaining

- None.

## Incremental Details Intentionally Deferred

- Whether `post_presence_listener_test.dart` needs any tiny assertion cleanup after the direct use-case regression lands.
- Whether `test/features/posts/phase3/handle_incoming_post_presence_use_case_test.dart` stays as one file or is split into one happy-path block plus one rejection block.

## Why It Is Safe To Execute Now

- The scope is narrow and anchored to the exact missing direct regression identified in the coverage reports.
- The gate commands are valid and already frozen in `scripts/run_test_gates.sh`.
- No structural blocker remains after review, so this can execute without reopening the gate-definition work.
