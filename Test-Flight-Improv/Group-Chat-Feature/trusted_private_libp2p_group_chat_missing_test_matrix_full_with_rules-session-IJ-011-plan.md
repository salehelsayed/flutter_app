# IJ-011 Session Plan - New-member authorized state and history

Status: execution-accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T04:54:40+02:00 | Evidence Collector completed | `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; `group_new_member_onboarding_test.dart`; `group_test_user.dart`; `group_member.dart`; `group_config_payload.dart` | IJ-011 is not code-blocked: current fake-network onboarding tests already prove current metadata, roles, and no pre-join message backfill, but the row remains Partial because explicit permission overrides and pin-related permission state are not pinned. | Draft narrow test-only plan. |
| 2026-05-01T04:55:00+02:00 | Planner completed | same | Add a focused assertion set to the existing IJ-011 onboarding scenario for explicit `GroupMemberPermissions`, including `pinMessages`, and prove the new member has no pre-join timeline/history before receiving post-join traffic. | Review plan sufficiency. |
| 2026-05-01T04:55:20+02:00 | Reviewer completed | same | Plan is sufficient if it does not claim first-class group pinned-item sync, because the repo has no group pinned-message model or table; only the shipped pin-related permission flag can be row-owned here. | Arbiter classification. |
| 2026-05-01T04:55:40+02:00 | Arbiter completed | same | execution-ready; no structural blocker. Accepted difference: post-wide pinned posts are outside group chat, and first-class group pinned items are not a shipped surface in this repo. | Execute focused test update and gates. |

## Execution Progress

| timestamp | phase | files inspected or touched | command / evidence | decision | next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-01T04:56:00+02:00 | Executor completed focused patch | `test/features/groups/integration/group_new_member_onboarding_test.dart` | Added explicit permission override assertions, including `pinMessages`, and strengthened no-pre-join-history assertion. | No production code changed. | Run focused IJ-011 test. |
| 2026-05-01T04:56:10+02:00 | Focused test passed | same | `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'new member receives current metadata and roles without pre-join history'` passed (`+1`). | Focused seam is green. | Run preservation gates. |
| 2026-05-01T04:56:50+02:00 | Preservation gates passed | same plus invite/onboarding suites | `group_new_member_onboarding_test.dart` passed (`+6`); `invite_round_trip_test.dart` passed (`+14`); `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`); `./scripts/run_test_gates.sh groups` passed (`+97`); `git diff --check` passed. | IJ-011 execution accepted. | Run closure doc updates. |
| 2026-05-01T04:57:00+02:00 | Supporting nightly classified | env check | `group-real-network-nightly` not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. | External fixture unavailable; non-blocking for row-owned fake-network/app closure. | Persist matrix/inventory/breakdown closure. |

## execution and closure evidence

Final execution verdict: accepted.

The focused IJ-011 test update in `test/features/groups/integration/group_new_member_onboarding_test.dart` passed along with the full onboarding suite, invite round trip suite, invite application wildcard, groups gate, and `git diff --check`. The source matrix IJ-011 row, `test-inventory.md` IJ-011 row, and this breakdown now record IJ-011 as `Covered`/accepted with the explicit caveat that first-class group pinned-message sync is not a shipped group-chat surface.

## real scope

Close IJ-011 for the current group-chat architecture by adding focused repo evidence that a newly added trusted member receives only authorized current group state and future traffic:

- latest metadata snapshot
- latest membership snapshot
- latest role snapshot
- explicit member permission overrides, including the existing `pinMessages` permission flag
- no pre-join message, reaction, metadata, or role-history rows
- post-join message delivery after the member is subscribed

No production feature work is planned unless this focused regression exposes a current implementation gap.

## closure bar

IJ-011 can move from `Partial` to `Covered` only if the source matrix, inventory, and breakdown cite a passing row-owned test that proves current-state sync plus future-only history for a newly added member. The docs must state that first-class group pinned-item state is not currently a shipped group surface; this session only pins the existing group permission field related to message pinning.

## source of truth

- Primary row: `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` IJ-011.
- Current coverage note: `test-inventory.md` IJ-011.
- Direct integration surface: `test/features/groups/integration/group_new_member_onboarding_test.dart`.
- Current group state model: `GroupModel`, `GroupMember`, `GroupMemberPermissions`, and `GroupTestUser.addMember`.
- Current code/tests win over broad matrix wording when a named product surface, such as group pinned items, does not exist.

## session classification

`implementation-ready` test-only closure. The original ledger classification is `evidence-gated`, but repo evidence shows the missing row-owned proof is a focused integration assertion gap rather than a missing production behavior.

## exact problem statement

The repo already proves that new members get current metadata/roles and future-only history, but IJ-011 remains `Partial` because the proof does not pin explicit custom permissions or the current pin-related permission state. The row must not overclaim nonexistent first-class group pinned-item sync.

## files and repos to inspect next

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/application/group_config_payload.dart`

## existing tests covering this area

- `new member receives only post-join text and media with descriptors`
- `multiple newly-added members converge on latest epoch and receive the same post-add message`
- `new member receives current metadata and roles without pre-join history`
- `add-send boundary delivers only after the new member is subscribed`
- `new member receives post-join reactions without pre-join reaction state`
- `quoted reply to pre-join parent keeps missing-parent fallback for new member`

## regression/tests to add first

Tighten `new member receives current metadata and roles without pre-join history` so it also proves:

- Charlie's explicit custom permissions are copied into Bob's new-member snapshot.
- `pinMessages` is preserved as the existing group pin-related permission state.
- Bob has an empty pre-join message/timeline surface before post-join traffic.
- Bob receives the post-join message and never receives the pre-join history row.

## step-by-step implementation plan

1. Update the existing IJ-011 onboarding test to save explicit permission overrides for Charlie after the role change and before Bob joins.
2. Assert Bob's member snapshot preserves those permissions, including `pinMessages: true` and denied invite/edit permissions.
3. Strengthen the pre-post boundary assertion so Bob has no pre-join messages before the post-join send.
4. Run the focused onboarding test, invite preservation tests, the groups gate, and `git diff --check`.
5. If all pass, update the source matrix, inventory, plan evidence, and breakdown ledger to `Covered`/accepted.

## risks and edge cases

- `GroupTestUser` is a fake-network harness, not real device proof.
- Current group chat has no first-class pinned-message state; overclaiming pinned-item sync would be inaccurate.
- Manual member saves must preserve the existing public key, join time, and role to avoid fabricating unrelated membership changes.
- The test must avoid adding backfill behavior; current trusted-private behavior is future-only history.

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart --plain-name 'new member receives current metadata and roles without pre-join history'`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart`
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart`
- `./scripts/run_test_gates.sh groups`
- `git diff --check`
- Supporting only when configured: `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly`

## known-failure interpretation

If `group-real-network-nightly` is unconfigured because `FLUTTER_DEVICE_ID` or `MKNOON_RELAY_ADDRESSES` is unset, record that as a non-blocking external fixture gap for IJ-011. Do not classify unrelated broad-suite failures as IJ-011 regressions unless they affect new-member authorized state/history.

## done criteria

- Focused IJ-011 onboarding test passes.
- Required preservation tests and `groups` gate pass.
- Source matrix IJ-011 row is `Covered`.
- `test-inventory.md` IJ-011 crosswalk is `Covered`.
- Breakdown counts, current-session closure state, matrix row inventory, session ledger, and ordered session row all record IJ-011 as accepted/Covered.
- Residual notes do not claim first-class group pinned-item sync or live device proof.

## scope guard

Do not implement group pinned-message storage, history backfill policy controls, paired-device admission, real relay setup, account/device registry, or broad role-conflict semantics in IJ-011. Those are separate product or matrix rows.

## accepted differences / intentionally out of scope

First-class pinned posts exist in the posts feature, not group chat. Group chat currently exposes only a `pinMessages` permission override, and this session pins that state. Real-device live proof is supporting evidence only while the fixture is unavailable.

## dependency impact

IJ-011 closure lets later sessions treat new-member current-state and future-only history as covered at the fake-network app layer. IJ-013 remains responsible for richer identity/device binding. RP and EK rows remain responsible for broader authorization, conflict, and signature/key semantics.
