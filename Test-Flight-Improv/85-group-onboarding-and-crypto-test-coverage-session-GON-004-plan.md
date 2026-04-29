# GON-004 Plan: New-Member Epoch Convergence, Rejoin, And Add-Send Race Contract

## real scope

- Add host-side fake-network coverage for:
  - multi-member add convergence on the same observable latest epoch and post-add delivery
  - the deterministic add/send boundary currently implied by the fake group network: Bob is receive-eligible only after his group topic subscription is active
- Preserve existing re-add/current-epoch evidence from `group_membership_smoke_test.dart` rather than duplicating the large remove/rotate/re-add flow.

## closure bar

- `TC-7` has direct automated evidence that Bob and Charlie receive the same post-add message at the same latest epoch.
- `TC-8` is explicitly mapped to the existing re-add test evidence for fake-network/current-epoch behavior and absence-window no-backfill.
- `TC-24` has a pinned deterministic fake-network contract: a message sent while Bob's add is staged but not subscribed is not backfilled, while the first post-subscription message is delivered once.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-004`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-7, TC-8, and TC-24.
- Existing coverage: `group_membership_smoke_test.dart` re-add/current-state test and `create_group_with_members_use_case_test.dart` unit invite/config fan-out tests.

## session classification

`implementation-ready`

## exact problem statement

The repo has unit-level multi-recipient create/add coverage and a large fake-network re-add proof, but the Report 85 source doc still lacks a single onboarding-boundary proof that multiple newly-added members share observable epoch state and that the add/send overlap has a deterministic contract.

## files and repos to inspect next

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`

## existing tests covering this area

- `create_group_with_members_use_case_test.dart` proves member config and invite fan-out for multiple contacts at the unit layer.
- `group_membership_smoke_test.dart` proves a removed member can be re-added with epoch 2, resumes send/receive, and does not receive absence-window traffic.
- `group_messaging_smoke_test.dart` proves multi-user fan-out and member-list hydration, but not explicit epoch convergence for newly-added users.

## regression/tests to add first

- Extend `group_new_member_onboarding_test.dart` with:
  - a multi-add epoch convergence test for Bob and Charlie
  - a staged-add/send-boundary test that pins the current subscribe-effective contract

## step-by-step implementation plan

1. Add a small test helper for saving fake `GroupKeyInfo` rows.
2. Add Bob, then Charlie, with both newly-added users receiving epoch state and the member-added hydration event.
3. Send a bridge-backed post-add message and assert Bob/Charlie both receive it with the same `keyGeneration`.
4. Stage Bob's membership locally without subscribing him to the fake group topic.
5. Have an existing member send a message before Bob subscribes, then subscribe Bob and send another message.
6. Assert Bob receives only the post-subscription message and all members converge on Bob's membership.
7. Run the updated onboarding suite and the existing focused re-add test.
8. Update source docs, closure docs, and this ledger when the evidence passes.

## risks and edge cases

- The staged-add boundary test intentionally uses the fake network's subscription as the effective live-delivery boundary; it must not overclaim real-network or real-crypto behavior.
- Existing `addMember` subscribes immediately, so TC-24 needs direct repo staging to model the in-progress add state deterministically.
- Rejoin real-crypto decrypt remains out of scope for this session and belongs to `GON-005`.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart --name "removed member can be re-added with current state and resumes send/receive"`

## known-failure interpretation

- A failure in the updated onboarding suite is a session blocker.
- A failure in the focused re-add test means TC-8 can no longer be mapped to existing evidence and must be fixed or reclassified.

## done criteria

- Direct onboarding suite passes.
- Focused re-add evidence passes.
- TC-7, TC-8, and TC-24 are recorded truthfully in the source doc and breakdown ledger.

## scope guard

- Do not add real-crypto, simulator, foreground-push, notification, or relay work in this session.
- Do not change production membership semantics unless the deterministic tests expose a direct bug.

## accepted differences / intentionally out of scope

- This session closes fake-network/app-layer evidence only. Real decrypt and simulator evidence remain later-session work.

## dependency impact

- `GON-005` owns the stronger real-crypto re-add decrypt proof and should not treat this session as satisfying that closure bar.
