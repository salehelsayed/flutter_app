# GM-010 Re-add C Twice Is Idempotent Plan

Status: closed/accepted

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source session: `GM-010`
Intended plan path: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-010-plan.md`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 21:22:41 CEST | Evidence Collector completed | `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-010; GM-008 and GM-009 accepted row notes/plans; `add_group_member_use_case.dart`; `group_message_listener.dart`; `group_members_db_helpers.dart`; `group_repository_impl.dart`; `in_memory_group_repository.dart`; `group_membership_smoke_test.dart`; `add_group_member_use_case_test.dart`; `group_message_listener_test.dart`; GM multi-party runner/criteria/harness files; `test-gate-definitions.md`; `test-inventory.md`; worktree status. | GM-010 is Open and `needs_code_and_tests`. GM-008 and GM-009 have recovered/passing exact three-iOS-simulator verdicts and must stay closed. Adjacent duplicate listener and DB uniqueness coverage exists, but direct duplicate re-add and multi-party GM-010 proof support are missing. | Draft the narrow GM-010 execution plan. |
| 2026-05-10 21:22:41 CEST | Planner completed | Evidence Collector findings and current dirty worktree status. | Drafted a regression-first plan for duplicate Charlie re-add: add host proof first, add `gm010` criteria/runner/harness support, then patch only the direct add/re-add seam if the regression proves the duplicate operation is not idempotent. | Run sufficiency review against closure bar, simulator-only proof, and scope guard. |
| 2026-05-10 21:22:41 CEST | Reviewer completed | Current plan draft. | Sufficient with adjustments: require proof of one active Charlie membership/device binding, no duplicate topic joins, no duplicate durable inbox recipients, reliable A/B/C delivery, and no source matrix/breakdown edits during execution. | Apply adjustments and arbitrate remaining caveats. |
| 2026-05-10 21:22:41 CEST | Arbiter completed | Reviewer findings and adjusted plan. | No structural blockers remain. Direct `--scenario gm010` simulator proof with recorded iOS simulator IDs is required; physical-device-only proof is explicitly rejected. | Finalize plan as reusable. |
| 2026-05-10 21:22:41 CEST | Finalization completed | Final GM-010 plan file. | Plan is `execution-ready`; only this adjacent plan file was edited. | Execute GM-010 only in a later implementation pass. |

## Final verdict

GM-010 is `closed/accepted`. The accepted execution made the duplicate Charlie add/re-add path idempotent for a strict identical member/device operation, while preserving conflicting duplicate-add rejection. Final proof shows one active Charlie membership/device binding, one harness-measured Charlie group-config join after re-add, no duplicate durable inbox recipient entries, reliable exact-once post-readd delivery between Alice, Bob, and Charlie, and final A/B/C convergence.

## real scope

Own source row `GM-010`: `Re-add C twice is idempotent`.

In scope:
- Add a GM-010 host regression proving duplicate re-add/add of Charlie is idempotent.
- Add direct `gm010` support to the multi-party simulator proof surface: criteria, runner, and harness.
- Patch only the smallest product seam required by the failing GM-010 regression, likely the direct add/re-add path in `add_group_member_use_case.dart` or the invite acceptance path if the regression points there.
- Preserve existing duplicate listener replay behavior and DB uniqueness guarantees.

Out of scope during execution:
- Source matrix edits, breakdown edits, closure ledger edits, broad rollout verdicts, and closure status changes.
- Reopening or downgrading GM-008 or GM-009. They are already covered by recovered/passing exact three-iOS-simulator verdicts.
- Real external device orchestration. Device-backed proof for this row must be simulator-only.
- GM-011/GM-012 stale out-of-order membership events, GM-014 simultaneous re-add/send races, GM-019 durable recipient-window policy, GM-021 fresh key-package policy, and GM-022 broad duplicate member-list cleanup unless a direct GM-010 regression proves a shared helper must be changed.

## closure bar

GM-010 is good enough when row-specific evidence proves all of the following:
- Applying the duplicate Charlie re-add/add event twice completes without throwing for the same logical operation.
- Alice, Bob, and Charlie converge on one A/B/C member set with exactly one Charlie row.
- Charlie has exactly one active device binding for the proof device, and duplicate re-add does not create duplicate device entries.
- The bridge/topic layer performs at most one effective join for Charlie after re-add.
- Durable inbox storage for post-readd messages includes each intended recipient once; no duplicate Charlie inbox recipient is stored from duplicate re-add.
- Alice and Bob receive Charlie's post-readd message exactly once, and Charlie receives Alice's post-readd message exactly once.
- The exact `gm010` simulator proof writes an orchestrator verdict JSON with `scenario: gm010`, `ok: true`, and Alice/Bob/Charlie role verdicts validated by GM-010 criteria.

## source of truth

- Source row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GM-010`.
- Row ownership/index: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests beat stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates.
- Existing accepted GM-008 and GM-009 row artifacts are authoritative for those rows and are not GM-010 blockers.

## session classification

`closed/accepted`

Rationale: the row started as `Open` and classified as `needs_code_and_tests`. Execution added the row-specific host regression, GM-010 criteria/runner/harness support, and the narrow product idempotence fix in `add_group_member_use_case.dart`. The accepted fix-pass proof uses measured Charlie join fields and closes the row; GM-011 and later rows remain separate work.

## exact problem statement

Charlie can receive duplicate invite/add/re-add events after a remove/re-add sequence. The product must treat the duplicate as the same logical membership operation, not as a second active membership. User-visible behavior must be stable: Charlie should appear once, use one active device binding, not join the group topic twice, not receive duplicate durable inbox fanout, and still exchange post-readd messages reliably.

What must stay unchanged:
- Unauthorized adds still fail.
- Adding a different already-active member by a normal user action must not silently overwrite member state unless the GM-010 regression proves it is the same logical event.
- Existing GM-008 restart re-add and GM-009 duplicate remove contracts remain closed and should only reopen on a real regression introduced by shared code changes.

## files and repos to inspect next

Production/application:
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`

Persistence/model:
- `lib/core/database/helpers/group_members_db_helpers.dart`
- `lib/core/database/migrations/017_groups_tables.dart`
- `lib/core/database/migrations/062_group_member_device_identities.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/shared/fakes/group_test_user.dart`

Proof surfaces:
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`

## existing tests covering this area

- `add_group_member_use_case_test.dart` covers normal add, permission checks, duplicate member rejection before sync, limit checks, and rollback.
- `group_message_listener_test.dart` covers duplicate `member_added` replay with one canonical member state and one UI event, duplicate `members_added` replay with one timeline row/member set, and stale membership watermark behavior.
- `group_members` persistence has primary key `(group_id, peer_id)` and `ConflictAlgorithm.replace`; in-memory repo stores members by peer ID.
- `group_membership_smoke_test.dart` now covers GM-006, GM-007, GM-008, and GM-009 remove/re-add/remove-twice flows, but does not cover re-add twice.
- `group_new_member_onboarding_test.dart` covers add/send boundary and exactly-once post-add delivery for a new member, but not duplicate re-add after removal.
- Multi-party simulator proof currently supports `gm001` through `gm009`; no `gm010` requirement, runner branch, criteria validation, or harness role branch exists yet.

## regression/tests to add first

Add the host regression before production changes:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010 re-adds C twice idempotently, keeps one device binding, and preserves A/B/C delivery'
```

The regression should:
- Create A/B/C, remove Charlie, rotate to the current epoch, and re-add Charlie.
- Apply the duplicate re-add/add for Charlie a second time using the same logical event or invite fixture.
- Assert no throw for the duplicate logical operation.
- Assert Alice, Bob, and Charlie each have one Charlie membership row and one active Charlie device binding.
- Assert the fake network/topic helper sees Charlie subscribed once after re-add.
- Send Alice and Charlie post-readd messages and assert exactly-once receipt by intended recipients.
- Assert durable inbox/replay recipient lists, if stored in the host path, do not contain duplicate Charlie recipient entries.

Then add GM-010 criteria tests:

```sh
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-010
```

Criteria must accept a valid GM-010 Alice/Bob/Charlie verdict and reject missing duplicate-readd proof, duplicate Charlie member row/device binding, duplicate topic join, duplicate inbox recipient fanout, missing post-readd delivery, and incomplete final convergence.

## step-by-step implementation plan

1. Capture the starting dirty worktree and do not revert or edit unrelated existing changes.
2. Add the GM-010 host regression in `group_membership_smoke_test.dart` using existing GM-006/GM-007/GM-008/GM-009 helpers and fake network assertions.
3. Run the focused GM-010 host regression and record whether it fails because duplicate re-add throws, duplicates state, duplicates topic subscription, duplicates inbox recipients, or misses delivery.
4. If the direct add use case fails by throwing `Member already exists` for the same logical duplicate event, patch only the direct add/re-add seam. Prefer a strict idempotence guard that no-ops only when the existing member matches the duplicate Charlie identity/device binding and the operation is the same logical membership event. Do not turn arbitrary add-existing-member user actions into silent overwrites.
5. If invite acceptance is the failing seam, patch only the pending invite/consumption path needed to make duplicate acceptance converge without a second join or duplicate inbox fanout.
6. Rerun the focused GM-010 host regression until green.
7. Extend `group_multi_party_device_criteria.dart` with `gm010` scenario requirements and validation of `gm010DuplicateReaddProof`.
8. Add positive and negative GM-010 criteria tests in `group_multi_party_device_criteria_test.dart`.
9. Extend `run_group_multi_party_device_real.dart` to accept direct `--scenario gm010`. Leave `--scenario all` unchanged unless the executor has spare time after required direct proof; direct `gm010` proof is sufficient.
10. Extend `group_multi_party_device_real_harness.dart` with Alice/Bob/Charlie `gm010` branches. The proof should remove Charlie, re-add Charlie, replay the duplicate add/re-add operation, send both directions, and write proof fields for member rows, active device bindings, topic join count/effective subscription, durable recipient uniqueness, and delivery counts.
11. If a shared test helper such as `GroupTestUser` needs one narrow counter or fixture hook for topic subscription count or recipient list inspection, add only that hook and keep it test-scoped.
12. Run the exact GM-010 command on three iOS simulators with recorded simulator IDs and the accepted relay env.
13. Run named gates and hygiene. Stop after GM-010 evidence is complete; do not close source matrix or breakdown in this execution session.

## risks and edge cases

- A broad no-op on existing member could hide legitimate duplicate-user-action errors or stale invite misuse. Keep idempotence strict to the same logical operation and same Charlie identity/device binding.
- Device identity merging must not create duplicate active bindings for the same device ID or transport peer ID.
- Duplicate topic joins may be hidden if the current fake network stores subscriptions as a set. Add a counter/hook only if needed to prove at-most-one effective join.
- Durable inbox storage may dedupe recipients by set in one path but not another. Criteria should verify recipient uniqueness in the actual proof fields used by the harness.
- `flutter drive`/simulator runs can have stale app state or Xcode DerivedData failures, as seen in GM-008. Those are environment recovery issues, not reason to downgrade GM-008 or GM-009.
- If GM-010 touches shared remove/re-add helpers, rerun GM-006 through GM-009 host smoke tests to avoid regressing accepted nearby rows.

## exact tests and gates to run

Direct host tests:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010 re-adds C twice idempotently, keeps one device binding, and preserves A/B/C delivery'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate member_added'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate members_added'
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-010
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Targeted analyzer:

```sh
dart analyze lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/accept_pending_group_invite_use_case.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/application/add_group_member_use_case_test.dart
```

Exact simulator proof, using three distinct iOS simulators only:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm010 -d <alice-ios-simulator-udid>,<bob-ios-simulator-udid>,<charlie-ios-simulator-udid>
```

Named gates and hygiene:

```sh
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Conditional nearby-row checks if shared remove/re-add helpers or shared proof helpers change:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'
```

## known-failure interpretation

- Existing unrelated dirty files are not GM-010 regressions. Do not revert them.
- GM-008 and GM-009 are accepted by exact three-iOS-simulator verdicts; do not reopen or downgrade them because GM-010 is still Open.
- A physical-device-only run cannot close GM-010. It may be supporting evidence, but closure requires simulator-backed proof with three distinct iOS simulator IDs and a passing `gm010` verdict.
- If `--scenario all` omits GM-010, treat that as accepted operator convenience unless the direct `--scenario gm010` command fails. Direct `gm010` proof is the required closure artifact.
- If the first simulator attempt fails from stale app sessions, DerivedData, or build cache, clean/reboot/rerun before classifying product failure.

## done criteria

- This plan remains scoped to GM-010; it reached `Status: execution-ready` before implementation and now records `Status: closed/accepted` after closure audit.
- A GM-010-named host regression exists and passes.
- GM-010 criteria accept valid proof and reject duplicate member/device/topic/inbox/delivery failures.
- `run_group_multi_party_device_real.dart` supports direct `--scenario gm010`.
- `group_multi_party_device_real_harness.dart` writes Alice/Bob/Charlie GM-010 proof fields.
- Exact three-iOS-simulator GM-010 proof passes with a recorded verdict JSON.
- Required direct tests, targeted analyzer, `groups`, `completeness-check`, and `git diff --check` pass or have explicit known-failure classification.
- No source matrix or breakdown closure updates are made by the implementation pass.

## scope guard

Do not:
- Modify source matrix or breakdown files during GM-010 execution.
- Broaden into stale out-of-order event rows, simultaneous race rows, or durable recipient-window policy rows.
- Require real external devices.
- Replace membership storage, redesign invite policy, or refactor group repositories.
- Change Go/libp2p code unless direct GM-010 proof identifies a Go-layer duplicate join defect that cannot be solved in the app/harness layer.
- Treat GM-008 or GM-009 accepted evidence as incomplete.

## accepted differences / intentionally out of scope

- Listener duplicate replay coverage is useful evidence but not enough to close GM-010 because the row requires duplicate invite/add/re-add behavior across membership, topic join, inbox fanout, and delivery.
- DB primary key/replace semantics prevent duplicate member rows in storage, but GM-010 also requires device binding, topic join, durable recipient, and delivery proof.
- Direct `--scenario gm010` proof is enough; `--scenario all` does not need to expand to GM-010.
- Simulator-only proof is required. Physical devices are intentionally out of scope.

## dependency impact

Later rows can rely on GM-010 only after row-specific closure records exact host, criteria, and simulator evidence. GM-011/GM-012 should not use this plan as stale event-ordering coverage. GM-019, GM-021, and GM-022 may reuse the GM-010 proof fields for recipient/device/member uniqueness, but must still run their own row contracts.

If GM-010 exposes a shared product defect in duplicate logical membership-event handling, later duplicate/out-of-order membership rows should pause until the narrow fix and GM-010 regression gates pass.

## Reviewer sufficiency notes

Plan sufficiency: sufficient as-is after adjustments.

Missing files/tests/gates: none for planning. Execution must add GM-010 host regression, criteria, runner, and harness support before closure.

Stale assumptions: GM-008 and GM-009 are no longer open; both have accepted exact simulator evidence and remain out of scope.

Overengineering check: the plan avoids broad repository refactors, physical-device orchestration, `--scenario all` widening, and stale/out-of-order row work.

Minimum needed: one host regression, one exact simulator scenario, strict idempotence only for duplicate logical Charlie re-add, and the named gates above.

## Arbiter decision

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 21:26:30 CEST | Contract extracted | GM-010 plan; implementation-execution-qa-orchestrator skill; dirty worktree status; current diffs in expected GM-008/GM-009 adjacent files | Scope is exactly GM-010. Required proof includes focused host regression, criteria/runner/harness support, exact three-iOS-simulator `--scenario gm010`, required host/analyzer/named gates, and no matrix/breakdown edits. Existing dirty source matrix/breakdown and GM-008/GM-009 changes must be preserved. | Spawn isolated Executor agent with model `gpt-5.5` and reasoning effort `xhigh`. |
| 2026-05-10 21:28:13 CEST | Executor started | GM-010 plan; implementation-execution-qa-orchestrator skill; `git status --short`; current diffs in expected GM-010/adjacent files | Running locally as the isolated Executor requested by the user. Worktree has pre-existing dirty changes in forbidden source matrix/breakdown and adjacent GM-008/GM-009 files; they will be preserved and not reverted. | Inspect current test/harness/product seams before adding GM-010 host regression. |
| 2026-05-10 21:29:35 CEST | Files inspected | `group_membership_smoke_test.dart`; `add_group_member_use_case.dart`; `add_group_member_use_case_test.dart`; `group_member.dart`; `fake_group_pubsub_network.dart`; `group_test_user.dart`; GM multi-party criteria/runner/harness search results | Current `addGroupMember` rejects every existing member before sync. Existing duplicate-add tests cover conflicting identity/role and must remain rejecting. Host fake network stores effective subscriptions as a set, which can prove one effective Charlie topic subscription. | Add the GM-010 host regression first, before product changes. |
| 2026-05-10 21:31:38 CEST | Host regression added | `test/features/groups/integration/group_membership_smoke_test.dart` | Added the GM-010 focused host regression with duplicate Charlie re-add, one active device binding assertion, one effective topic subscription assertion, durable recipient uniqueness checks, and exact-once A/B/C post-readd delivery checks. | Run the focused GM-010 host regression and use the result to decide whether `addGroupMember` needs a narrow idempotence patch. |
| 2026-05-10 21:32:51 CEST | Focused host regression RED | `test/features/groups/integration/group_membership_smoke_test.dart`; `lib/features/groups/application/add_group_member_use_case.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-010 re-adds C twice idempotently, keeps one device binding, and preserves A/B/C delivery'` failed from this session as expected: duplicate Charlie re-add throws `Bad state: Member already exists` in `addGroupMember`. | Patch only the direct add/re-add seam with a strict identical-member/device no-op; keep conflicting duplicate adds rejected. |
| 2026-05-10 21:33:37 CEST | Focused host regression GREEN | `lib/features/groups/application/add_group_member_use_case.dart`; `test/features/groups/integration/group_membership_smoke_test.dart` | Added strict identical duplicate-member/device no-op in `addGroupMember`. Focused GM-010 host regression passed after patch. Conflicting duplicate-add tests are preserved for the required app suite. | Add GM-010 criteria, runner, and harness support. |
| 2026-05-10 21:39:52 CEST | GM-010 proof surface added | `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart` | Added `gm010` scenario requirement, criteria validation, criteria positive/negative tests, direct runner support, and Alice/Bob/Charlie harness branches with duplicate re-add proof fields. | Format touched Dart files, then run GM-010 criteria tests and required host suites. |
| 2026-05-10 21:40:22 CEST | GM-010 criteria focused GREEN | `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart` | `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-010` passed, including valid proof and missing proof, duplicate row/device/topic, duplicate recipient, and missing delivery/convergence rejects. | Run the required direct host test suite list. |
| 2026-05-10 21:42:13 CEST | Required host suites GREEN | GM-010 touched host/application/criteria files | Passed: full `group_membership_smoke_test.dart`; full `add_group_member_use_case_test.dart`; `group_message_listener_test.dart --plain-name 'duplicate member_added'`; `group_message_listener_test.dart --plain-name 'duplicate members_added'`; full `group_new_member_onboarding_test.dart`; full `group_multi_party_device_criteria_test.dart`; targeted `dart analyze ...` from the plan. | Run conditional nearby GM-006 through GM-009 checks because shared harness proof helpers changed, then attempt exact simulator proof. |
| 2026-05-10 21:51:08 CEST | Conditional focused checks GREEN | `test/features/groups/integration/group_membership_smoke_test.dart` | Because shared harness/proof helpers changed, ran GM-006, GM-007, GM-008, and GM-009 focused host checks. All passed; no GM-008/GM-009 reopening or matrix/breakdown edits. | Record simulator evidence and run required named gates. |
| 2026-05-10 21:51:08 CEST | Exact simulator proof GREEN | `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart` | Ran exact simulator-only command with iOS UDIDs `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. GM-010 proof passed for Alice/Bob/Charlie. Verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm010_mT2xfk/gmp_1778442327812_alice_verdict.json`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm010_mT2xfk/gmp_1778442327812_bob_verdict.json`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm010_mT2xfk/gmp_1778442327812_charlie_verdict.json`. | Run `./scripts/run_test_gates.sh groups`. |
| 2026-05-10 21:51:08 CEST | `groups` gate started | group gate command | Starting `./scripts/run_test_gates.sh groups`. | Record result, then run completeness-check. |
| 2026-05-10 21:52:00 CEST | `groups` gate GREEN | group gate command | `./scripts/run_test_gates.sh groups` passed. | Run `./scripts/run_test_gates.sh completeness-check`. |
| 2026-05-10 21:52:00 CEST | `completeness-check` gate started | completeness gate command | Starting `./scripts/run_test_gates.sh completeness-check`. | Record result, then run `git diff --check`. |
| 2026-05-10 21:52:27 CEST | `completeness-check` gate GREEN | completeness gate command | `./scripts/run_test_gates.sh completeness-check` passed: 731/731 test files classified. | Run `git diff --check`. |
| 2026-05-10 21:52:27 CEST | Diff check started | worktree diff | Starting `git diff --check`. | Record result and Executor handoff. |
| 2026-05-10 21:52:53 CEST | Diff check GREEN | worktree diff | `git diff --check` passed with no whitespace errors. | Record Executor handoff. |
| 2026-05-10 21:53:41 CEST | Generated timestamp cleanup | `info.plist`; worktree diff | Restored the Xcode workspace `LastAccessedDate` timestamp generated by simulator/build activity; it was outside GM-010 scope. Re-ran `git diff --check`, which passed. | Record Executor handoff. |
| 2026-05-10 21:53:41 CEST | Executor handoff | GM-010 implementation files and plan file | GM-010 implementation complete with host regression, narrow idempotence patch, criteria/runner/harness proof, exact three-iOS-simulator proof, required host/analyzer/gate evidence, and no edits to the source matrix or session breakdown. | Handoff to QA reviewer. |
| 2026-05-10 22:02:23 CEST | Fix-pass Executor started | `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; GM-010 plan; dirty worktree status | QA blocker confirmed: GM-010 role verdicts hard-code `charlieTopicJoinCount: 1`, so the simulator does not credibly prove the at-most-one effective Charlie join condition. Scope remains GM-010; source matrix and source session breakdown remain untouched. | Replace the literal topic-count proof with a harness-measured Charlie group-config join count after re-add and criteria semantics that reject duplicate joins. |
| 2026-05-10 22:11:51 CEST | Fix-pass proof contract updated | `integration_test/group_multi_party_device_real_harness.dart`; `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart` | Replaced the literal `charlieTopicJoinCount: 1` field with harness-observed `charlieGroupConfigJoinCountAfterReadd`, `duplicateReaddTriggeredCharlieGroupConfigJoin`, and `charlieJoinMeasurementSource` proof fields. Criteria now reject duplicate Charlie group-config joins and require a non-empty measurement source. | Rerun focused criteria tests, targeted analyzer, exact simulator proof, named gates, and diff hygiene. |
| 2026-05-10 22:11:51 CEST | Fix-pass focused checks GREEN | GM-010 criteria/analyzer/simulator commands | Passed `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-010`; passed targeted `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart`; exact three-iOS-simulator `--scenario gm010` proof passed with verdict directory `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm010_8wG9iD`. Verdicts derive Charlie join proof from measured fields and no longer include `charlieTopicJoinCount`. | Run required named gates and diff hygiene. |
| 2026-05-10 22:11:51 CEST | Fix-pass required gates GREEN | `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check` | `groups` passed with 114 tests; `completeness-check` passed with 731/731 test files classified; `git diff --check` passed with no whitespace errors. | Record fix-pass Executor handoff. |
| 2026-05-10 22:13:01 CEST | Fix-pass generated timestamp cleanup | `info.plist`; worktree diff | Restored the Xcode workspace `LastAccessedDate` timestamp generated by simulator/build activity; it was outside GM-010 scope. Re-ran `git diff --check`, which passed. | Record fix-pass Executor handoff. |
| 2026-05-10 22:13:01 CEST | Fix-pass Executor handoff | GM-010 harness/criteria/test files and GM-010 plan file | QA blocker resolved. The GM-010 simulator proof now uses a harness-observable Charlie group-config join count after re-add and rejects duplicate joins through criteria. No source matrix or source session breakdown edits were made in this fix pass; GM-008 and GM-009 remain closed. | Handoff to QA reviewer. |

## Closure Audit Verdict

Closure verdict: `closed` / `accepted`.

What is now closed:
- GM-010 row contract: duplicate Charlie re-add/add is idempotent for the same strict member/device operation.
- Product behavior in `lib/features/groups/application/add_group_member_use_case.dart`: identical duplicate member/device add or re-add is a no-op; conflicting duplicate adds remain rejected.
- Proof surfaces: focused GM-010 host regression, GM-010 criteria tests, direct `--scenario gm010` runner support, and Alice/Bob/Charlie harness proof fields.

Accepted final evidence:
- Final exact simulator-only proof passed with `--scenario gm010` on iOS simulators Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Final orchestrator verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm010_8wG9iD/gmp_1778443518461_gm010_orchestrator_verdict.json`, with `scenario: gm010`, `ok: true`, and detail `gm010 verdicts valid for alice, bob, charlie`.
- Role verdict facts: one Charlie membership row, one active Charlie device binding, `charlieGroupConfigJoinCountAfterReadd: 1`, `duplicateReaddTriggeredCharlieGroupConfigJoin: false`, non-empty `charlieJoinMeasurementSource`, unique durable inbox recipients, exact-once Alice/Bob/Charlie post-readd delivery, and final convergence on A/B/C at epoch `2`.

QA blocker closure:
- The earlier `group_multi_party_gm010_mT2xfk` proof is historical only. It was not accepted as final because topic/join evidence used a literal count.
- The accepted `group_multi_party_gm010_8wG9iD` proof uses harness-measured Charlie group-config join fields, and criteria reject duplicate joins.

Maintenance gates:
- Focused GM-010 host regression.
- Full `group_membership_smoke_test.dart`.
- `add_group_member_use_case_test.dart`.
- Duplicate `member_added` and `members_added` listener checks.
- `group_new_member_onboarding_test.dart`.
- GM-010 criteria tests and full criteria suite.
- Targeted analyzer.
- Conditional GM-006 through GM-009 focused host checks.
- Exact three-iOS-simulator `gm010`.
- `./scripts/run_test_gates.sh groups`.
- `./scripts/run_test_gates.sh completeness-check`.
- `git diff --check`.

Residual-only items:
- None for GM-010. Reopen only on a real regression against duplicate identical re-add idempotence, conflicting duplicate-add rejection, Charlie member/device uniqueness, measured join uniqueness, durable-recipient uniqueness, or A/B/C exact-once post-readd delivery.

Still-open items:
- GM-011 and later source rows remain open. GM-010 does not close stale out-of-order membership events, simultaneous re-add/send races, durable recipient-window policy, fresh key-package policy, or broader duplicate member-list cleanup rows.

Accepted differences:
- `--scenario all` does not need to include GM-010.
- Simulator-only proof is the closure artifact; no real external devices are required or claimed.

Checkpoint policy:
- `checkpoint_skipped`; a clean scoped checkpoint/commit is unsafe because the source matrix, breakdown, and GM-010 plan are overlapping aggregate rollout artifacts, while the worktree also contains unrelated or overlapping product/test edits from other work. Leave unrelated and aggregate rollout paths unstaged.

Structural blockers remaining: none.

Incremental details intentionally deferred:
- Exact simulator IDs are execution-time choices, but they must be iOS simulator IDs and must be recorded with the verdict.
- The exact proof field names can change during implementation as long as GM-010 criteria validate the required member/device/topic/inbox/delivery facts.

Accepted differences intentionally left unchanged:
- GM-008 and GM-009 closure evidence remains accepted.
- `--scenario all` can remain limited to earlier scenarios.
- Physical devices remain out of scope.

Exact docs/files used as evidence:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-008-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-009-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Code/test files listed in `files and repos to inspect next`.

Why the plan is safe to implement now: it is one-row scoped, regression-first, simulator-only for device proof, explicit about GM-008/GM-009 staying closed, and includes exact direct tests, named gates, known-failure handling, and a stop rule that prevents source-matrix/breakdown edits during execution.
