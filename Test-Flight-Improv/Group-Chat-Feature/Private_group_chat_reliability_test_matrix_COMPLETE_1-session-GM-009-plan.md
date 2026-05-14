# GM-009 Remove C Twice Is Idempotent Planning

Status: closed

Planning model: roles simulated sequentially in this controller pass because no spawned role agents were requested.

Closure audit model: roles simulated sequentially in this controller pass for `Completion Auditor`, `Closure Writer`, and `Closure Reviewer`.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 20:40:46 CEST | Controller contract extraction | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-009-plan.md`; dirty worktree status | Execution contract extracted for GM-009 only. Required closure is duplicate remove idempotence, at-most-once key rotation/distribution for the same logical remove, Charlie stays removed, A/B delivery remains reliable, direct GM-009 host/criteria/analyzer/simulator/named-gate evidence. Existing dirty matrix/breakdown edits are out of scope and must not be reverted or edited. | Spawn isolated Executor for implementation and required gates. |
| 2026-05-10 20:42:35 CEST | Executor start | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-009-plan.md`; `git status --short`; GM-009 allowed surface diffs | Isolated Executor began. Worktree already contains dirty source matrix/breakdown docs plus GM-008-oriented harness/criteria/test edits; those are treated as pre-existing and will not be reverted. GM-009 remains the only implementation target. | Inspect GM-009 host, criteria, runner, and harness seams before editing. |
| 2026-05-10 20:44:30 CEST | Executor inspection | `remove_group_member_use_case.dart`; `group_membership_smoke_test.dart`; GM multi-party runner/criteria/harness files | Found direct duplicate-remove gap: absent member throws before considering the existing membership event watermark. Existing shared device files contain GM-008 additions; GM-009 support is missing. | Add GM-009 host regression first, then run it before production fix. |
| 2026-05-10 20:45:50 CEST | Host regression added | `test/features/groups/integration/group_membership_smoke_test.dart` | Added focused GM-009 smoke test covering duplicate same-event Charlie removal, one removal timeline, at-most-one update/rotation/distribution, Charlie exclusion, and A/B delivery. | Run focused GM-009 test before product fix. |
| 2026-05-10 20:46:37 CEST | Focused host RED | `group_membership_smoke_test.dart`; `remove_group_member_use_case.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'` failed as expected: duplicate same-event remove throws `Bad state: Member not found` at `remove_group_member_use_case.dart`. | Patch duplicate same-event remove to no-op only when the event watermark proves it was already applied. |
| 2026-05-10 20:47:10 CEST | Product fix | `lib/features/groups/application/remove_group_member_use_case.dart` | Added strict duplicate no-op guard for absent target only when `eventAt` exactly matches the group's applied membership watermark; normal unknown absent-member removes still throw. | Rerun focused GM-009 host test. |
| 2026-05-10 20:47:55 CEST | Focused host GREEN | `group_membership_smoke_test.dart`; `remove_group_member_use_case.dart` | `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'` passed. | Add direct GM-009 criteria, runner, and harness support. |
| 2026-05-10 20:52:45 CEST | GM-009 device proof wiring | `integration_test/scripts/group_multi_party_device_criteria.dart`; `test/integration/group_multi_party_device_criteria_test.dart`; `integration_test/scripts/run_group_multi_party_device_real.dart`; `integration_test/group_multi_party_device_real_harness.dart` | Added `gm009` scenario requirements, focused criteria, runner selection/help text, and Alice/Bob/Charlie harness branches. `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-009` passed. | Run targeted analyzer and required host suites. |
| 2026-05-10 20:53:23 CEST | Analyzer cleanup | `lib/features/groups/application/remove_group_member_use_case.dart` | Targeted analyzer first found one warning: redundant `removedMember != null` after flow promotion. Removed the redundant check and kept rollback behavior. | Rerun targeted analyzer. |
| 2026-05-10 20:54:26 CEST | Required host/discovery gates | Host tests; analyzer; `flutter devices --machine`; `xcrun simctl list devices available` | Passed: focused GM-009 smoke, `member_removal_integration_test.dart`, full `group_membership_smoke_test.dart`, `group_new_member_onboarding_test.dart`, focused GM-009 criteria, targeted analyzer. Flutter and simctl show booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`; physical devices are ignored for closure. | Run exact three-iOS-simulator GM-009 proof with the first three simulator IDs. |
| 2026-05-10 20:59:48 CEST | First simulator proof | `integration_test/group_multi_party_device_real_harness.dart`; GM-009 orchestrator artifacts in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm009_ZkvQFd` | Exact simulator command with IDs `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` failed criteria validation: Alice `gm009DuplicateRemovalProof.removalTimelineCount` was `0` instead of `1`. Role app tests completed; failure is harness evidence shape, not Xcode/Simulator state. | Patch harness removal helper to persist Alice's local removal timeline row like the app path, then rerun analyzer and exact simulator proof. |
| 2026-05-10 21:00:56 CEST | Harness evidence fix | `integration_test/group_multi_party_device_real_harness.dart` | `_removeCharlieAndPublish` now saves the synthetic `member_removed` timeline message immediately after successful local removal, matching the app/fake removal path before broadcast/offline replay. | Rerun targeted analyzer and exact GM-009 simulator proof. |
| 2026-05-10 21:01:08 CEST | Analyzer rerun | Targeted analyzer surfaces | `dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart lib/features/groups/application/remove_group_member_use_case.dart` passed with `No issues found!`. | Rerun exact GM-009 simulator proof. |
| 2026-05-10 21:04:30 CEST | Simulator proof GREEN | Three iOS simulators; verdicts in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm009_BVfZlR` | Exact `--scenario gm009` proof passed. Orchestrator verdict `gmp_1778439691828_gm009_orchestrator_verdict.json` has `scenario: gm009`, `ok: true`, and detail `gm009 verdicts valid for alice, bob, charlie`. Devices: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. | Run named gates and diff hygiene. |
| 2026-05-10 21:05:35 CEST | Final gates and hygiene | `./scripts/run_test_gates.sh groups`; `./scripts/run_test_gates.sh completeness-check`; `git diff --check` | Passed: groups gate, completeness check (`731/731 test files classified`), and diff whitespace check. No Executor blocker remains. Existing dirty out-of-scope files (`source matrix`, `session-breakdown`, `info.plist`, `group_test_user.dart`, GM-008/other rollout docs) were left untouched. | Hand off GM-009 Executor evidence for isolated QA review. |
| 2026-05-10 21:15:04 CEST | Closure audit completed | GM-009 plan; source matrix GM-009 row; breakdown GM-009 row inventory, row-disposition, session closure ledger, session ledger, ordered-session row; accepted GM-009 simulator verdict | `closed` for GM-009. Source row is now `Covered` by the focused host regression, GM-009 criteria guard, targeted analyzer, exact `--scenario gm009` three-simulator verdict, groups gate, completeness-check, and `git diff --check`. GM-010 and later rows remain open. | Apply checkpoint policy and keep overall program verdict unset. |

## Closure Audit Verdict

Closure verdict: `closed`.

GM-009 is now covered by row-specific evidence for duplicate remove-C idempotence. The host regression proves the same logical Charlie removal is a strict idempotent no-op after the first application, records one logical removal/timeline effect, rotates/distributes the replacement key at most once, excludes Charlie, and preserves A/B delivery.

Simulator evidence is accepted from `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm009_BVfZlR/gmp_1778439691828_gm009_orchestrator_verdict.json`, which records `scenario: gm009`, `ok: true`, and `gm009 verdicts valid for alice, bob, charlie` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Alice's role verdict records `removedCharlieOnce: true`, `duplicateRemoveIgnored: true`, `removalTimelineCount: 1`, `rotationCount: 1`, `keyDistributionCount: 1`, `distributedKeyToCharlie: false`, and final epoch `2`; Bob excludes Charlie and receives Alice's post-duplicate-remove message exactly once; Charlie has no group after duplicate removal, has no rotated epoch, stores zero post-removal plaintext, and post-removal publish is rejected.

Required gates recorded as passed: focused GM-009 host regression, `member_removal_integration_test.dart`, full `group_membership_smoke_test.dart`, `group_new_member_onboarding_test.dart`, focused GM-009 criteria test, targeted analyzer, exact `--scenario gm009` simulator proof, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`.

Residual-only items: none for GM-009.

Still-open items: GM-010 and later source rows remain open and must keep their own row-scoped closure evidence.

Accepted differences: `--scenario all` does not need to include GM-009 for this row to close; direct `--scenario gm009` proof is sufficient. The first simulator attempt failed because the harness evidence omitted Alice's local removal timeline row; the harness was corrected and the exact GM-009 proof passed.

Checkpoint policy: `checkpoint_skipped` for this closure pass because a clean scoped commit is unsafe in the current dirty worktree with overlapping aggregate rollout docs and unrelated dirty product/test files. No files were staged.

## Executor Handoff

GM-009 implementation and evidence are complete for Executor scope.

Files changed by this Executor:
- `lib/features/groups/application/remove_group_member_use_case.dart`: duplicate same-event absent-member removal is now a strict idempotent no-op when the event watermark proves the logical removal was already applied; unknown absent-member removals still throw.
- `test/features/groups/integration/group_membership_smoke_test.dart`: added focused GM-009 host regression for duplicate Charlie removal, one logical timeline/removal effect, at-most-one rotation/distribution, Charlie exclusion, and A/B delivery.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: added direct `gm009` requirement and acceptance/rejection criteria.
- `test/integration/group_multi_party_device_criteria_test.dart`: added GM-009 positive and negative criteria coverage.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: added direct `--scenario gm009` runner support.
- `integration_test/group_multi_party_device_real_harness.dart`: added GM-009 role branches and persisted the local removal timeline row in the harness helper so simulator proof matches app behavior.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-009-plan.md`: recorded Executor progress, command outcomes, and this handoff.

Required evidence:
- PASS `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'`.
- PASS `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`.
- PASS `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`.
- PASS `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`.
- PASS `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-009`.
- PASS targeted `dart analyze` on the plan-listed files.
- PASS `flutter devices --machine` and `xcrun simctl list devices available`; three distinct iOS simulator IDs were selected.
- PASS exact simulator command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm009 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- PASS `./scripts/run_test_gates.sh groups`.
- PASS `./scripts/run_test_gates.sh completeness-check`.
- PASS `git diff --check`.

Simulator verdict path:
- `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm009_BVfZlR/gmp_1778439691828_gm009_orchestrator_verdict.json`

Blockers:
- None for GM-009 Executor scope. First simulator run failed only because harness evidence omitted Alice's local removal timeline row; the harness was corrected and the exact proof passed.

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 20:37:21 CEST | Evidence Collector completed | `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-009; `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` GM-008/GM-009 rows; GM-008 plan; `remove_group_member_use_case.dart`; `group_message_listener.dart`; membership smoke and listener tests; GM multi-party runner/criteria/harness files; `test-gate-definitions.md` | Historical planning-time finding: GM-009 was then Open and `needs_code_and_tests`. GM-008 was covered by a recovered exact three-iOS-simulator verdict and must not be reopened. Direct remove then threw when the member was absent; listener duplicate-removal replay had adjacent idempotence coverage but did not prove the direct row contract. | Draft one-row execution plan for GM-009 only. |
| 2026-05-10 20:37:21 CEST | Planner completed | Evidence Collector notes and current dirty worktree status | Drafted a proof-first plan: add GM-009 host regression, add direct `gm009` runner/criteria/harness proof, make product edits only if the regression proves duplicate remove is not idempotent. | Run sufficiency review against mandatory plan sections and device-proof constraints. |
| 2026-05-10 20:37:21 CEST | Reviewer completed | Current plan draft | Sufficient with required adjustments: device proof must be simulator-only, closure must reject physical-device-only proof, and GM-008 accepted evidence must remain closed/out of scope. | Apply adjustments and arbitrate remaining caveats. |
| 2026-05-10 20:37:21 CEST | Arbiter completed | Reviewer findings and adjusted plan | No structural blockers remain. The optional exact simulator IDs are an execution detail; the closure rule is simulator-only proof with recorded IDs and verdict JSON. | Plan is reusable for a later GM-009 implementation pass. |
| 2026-05-10 20:37:21 CEST | Finalization completed | Final plan file | Plan is `execution-ready`; no product, test, source-matrix, or breakdown files were edited. | Execute GM-009 only in a later implementation pass. |

## Final Verdict

GM-009 is `implementation-ready`. The session should implement or verify exactly one behavior: applying the same remove-C operation twice must be idempotent, must rotate/distribute the replacement key at most once for the same logical remove event, must leave one canonical A/B membership state, and must preserve A/B delivery.

GM-008 is already covered by the recovered exact three-iOS-simulator verdict and is not part of this plan. Do not reopen GM-008 unless a real regression appears in shared code while executing GM-009.

## Final Plan

Use a regression-first implementation pass. Start with host coverage for duplicate remove, then add direct `gm009` multi-party criteria/runner/harness proof. Change production code only if the host/device proof exposes a real duplicate-remove behavior gap. Any device proof must use simulators, not real external devices.

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

The exact simulator UUIDs may be discovered at execution time. If the previously used three booted iOS simulators are available, use them; otherwise use any three distinct booted iOS simulators found by `xcrun simctl list devices available` and visible in `flutter devices --machine`. Record the actual IDs in execution evidence.

## Accepted Differences Intentionally Left Unchanged

`--scenario all` currently expands to the earlier supported multi-party scenarios and does not need to include GM-009 for this row to close. Direct `--scenario gm009` proof is sufficient.

GM-008 restart/re-add semantics remain accepted and covered by its own exact three-iOS-simulator verdict. GM-009 must not reuse GM-008 as a blocker or closure target.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-009.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` rows GM-008 and GM-009.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-008-plan.md`.
- `lib/features/groups/application/remove_group_member_use_case.dart`.
- `lib/features/groups/application/group_message_listener.dart`.
- `lib/features/groups/application/group_membership_event_watermark.dart`.
- `test/features/groups/integration/group_membership_smoke_test.dart`.
- `test/features/groups/application/member_removal_integration_test.dart`.
- `test/features/groups/application/group_message_listener_test.dart`.
- `integration_test/scripts/run_group_multi_party_device_real.dart`.
- `integration_test/group_multi_party_device_real_harness.dart`.
- `integration_test/scripts/group_multi_party_device_criteria.dart`.
- `test/integration/group_multi_party_device_criteria_test.dart`.
- `Test-Flight-Improv/test-gate-definitions.md`.

## Why The Plan Is Safe To Implement Now

The plan owns one source row and names the exact app, test, and simulator proof surfaces. It starts with a failing/passing GM-009 regression before product edits, treats existing duplicate listener replay tests as adjacent evidence rather than closure, keeps GM-008 closed, and requires simulator-backed device proof instead of physical external devices.

## real scope

Own exactly source row `GM-009`: Remove C twice is idempotent.

In scope:
- Add or verify a GM-009 host regression proving duplicate remove of Charlie leaves Alice/Bob as the only members, records one logical removal effect, rotates/distributes at most one replacement key for the same remove event, and preserves A/B send/receive.
- Add direct `gm009` support to the existing multi-party proof surfaces if missing:
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
- Modify `removeGroupMember` or membership event handling only if the regression proves duplicate direct removal still throws, duplicates state, duplicates key rotation, or breaks A/B delivery.

Out of scope:
- GM-008 restart/re-add proof, GM-006 immediate re-add semantics, GM-007 history boundaries, stale out-of-order remove/add sequencing beyond the same logical duplicate remove event, role changes, media, notifications, multi-relay failover, physical-device proof, and final rollout verdicts.
- Source matrix, session breakdown, and unrelated rollout docs during implementation unless a later closure-only pass explicitly asks for those edits.

## closure bar

GM-009 is good enough when row-specific evidence proves:
- A/B/C start in the same private group and can exchange allowed baseline traffic.
- Alice removes Charlie once; Bob converges to A/B membership and Charlie loses group access.
- Reapplying the same logical remove-C event does not throw in the user-visible path selected for the test, does not re-add or duplicate Charlie, does not create duplicate durable timeline rows for the same source event, and does not cause a second effective key rotation/distribution for the same remove event.
- Alice and Bob keep exactly one canonical A/B member list and the same current key epoch after both remove applications.
- Charlie cannot send or decrypt post-removal content.
- Alice and Bob can send post-removal messages and each receives the other message exactly once.
- Direct `gm009` criteria rejects missing duplicate-remove proof, duplicate rotation, duplicate Charlie state, stale Charlie access, and missing A/B delivery.
- Exact simulator proof writes an orchestrator verdict JSON for `scenario: gm009`, `ok: true`, and per-role verdicts validated by GM-009 criteria.

## source of truth

Authoritative inputs:
- Source matrix row `GM-009` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown row `GM-009` in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code/tests in the group membership use cases, listener, host smoke tests, and GM multi-party proof harness.
- `Test-Flight-Improv/test-gate-definitions.md` for named gates.

Conflict rule:
- Current code/tests beat stale prose.
- The GM-009 source row wins for scope.
- Existing GM-008 accepted evidence remains closed and must not be reopened by planning language.
- `scripts/run_test_gates.sh` wins over gate prose if the two disagree.

## session classification

`implementation-ready`

Rationale: the row is Open and classified `needs_code_and_tests`. Current evidence shows adjacent duplicate system-event replay coverage but no exact GM-009 direct duplicate-remove proof or device verdict. The implementation path is narrow and test-first.

## exact problem statement

Applying the same remove-C operation twice can be user-visible if a duplicate membership event, retry, or repeated admin action reaches the app. The required behavior is idempotence: no duplicate member state, no duplicate effective key rotation for the same logical event, and no A/B delivery loss.

Current risk:
- `removeGroupMember` throws `StateError('Member not found')` when the target member is already absent, so direct duplicate remove may not satisfy the GM-009 user-visible idempotence contract.
- `GroupMessageListener` has duplicate replay safeguards for system messages, including duplicate non-self `member_removed` tests, but those prove listener replay idempotence rather than the full row with key-rotation and A/B delivery.

Behavior that must stay unchanged:
- Removed members still fail closed for send/decrypt.
- Remaining members keep delivery.
- Signed/stale membership event protections remain intact.
- GM-004 through GM-008 accepted row behavior remains valid.

## files and repos to inspect next

Production/app seams:
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`

Host/test seams:
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`

Simulator proof seams:
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Fallback only if app proof shows a lower-level runtime issue:
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

Adjacent coverage:
- `group_membership_smoke_test.dart::GM-004 removes C while online, rotates key, A/B continue, and C loses access`.
- `group_membership_smoke_test.dart::GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues`.
- `group_membership_smoke_test.dart::GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic`.
- `group_membership_smoke_test.dart::GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages`.
- `group_membership_smoke_test.dart::GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch`.
- `group_message_listener_test.dart::duplicate non-self member_removed keeps one timeline row and removal`.
- `group_message_listener_test.dart::duplicate self-removal emits one removal signal and leaves once`.

Missing for GM-009:
- No GM-009-named host regression that applies the same remove-C operation twice and then proves one A/B state, one effective rotation, Charlie exclusion, and A/B delivery.
- No direct `gm009` scenario requirement, criteria validation, runner support, harness role branches, or exact simulator verdict.

## regression/tests to add first

Add a GM-009 host regression before product fixes:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'
```

The regression should:
- Create A/B/C with epoch 1.
- Remove Charlie with a stable duplicate remove event identity or timestamp.
- Attempt the same logical remove again through the path the implementation chooses to make idempotent.
- Assert Alice/Bob member lists exclude Charlie and contain no duplicate rows.
- Assert key generation advances at most once for that logical remove and key distribution targets exclude Charlie.
- Assert Charlie cannot send post-removal.
- Assert Alice and Bob can send post-removal and receive each other exactly once.

Then add criteria coverage:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-009
```

If `--plain-name GM-009` is too narrow for grouped criteria tests, run the whole criteria suite:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

## step-by-step implementation plan

1. Confirm the current dirty worktree and do not revert unrelated edits.
2. Add the GM-009 host regression in `group_membership_smoke_test.dart`.
3. Run the focused GM-009 host regression. If it already passes without production edits, keep production unchanged.
4. If the focused host regression fails because duplicate remove throws for an already-removed member, make the smallest app change in `remove_group_member_use_case.dart` or the event-handling layer so the same logical duplicate remove is a no-op while preserving last-admin and authorization checks.
5. If key rotation/distribution can be invoked twice for the same logical event, gate the test or implementation around a stable duplicate event identity/watermark so the second application does not create a second effective rotation.
6. Add `gm009` to `scenarioRequirement`, device-selection messages, criteria evaluation, and negative criteria tests.
7. Add direct `--scenario gm009` runner support. Keep `--scenario all` unchanged unless the existing runner structure forces a tiny enum/help-text update.
8. Add GM-009 role branches in `integration_test/group_multi_party_device_real_harness.dart` for Alice, Bob, and Charlie.
9. Run direct host and criteria tests, targeted analyzer, simulator proof, named gates, completeness-check, and diff hygiene.
10. Stop without editing the source matrix or breakdown; leave closure docs to a later closure-specific pass unless explicitly requested.

## risks and edge cases

- Treating every absent-member remove as success could hide a real wrong-target/admin error. Keep authorization and group-existence checks strict; only the duplicate already-removed target should become idempotent if product code changes are needed.
- Duplicate remove may arrive via live PubSub and offline replay. Listener replay already has adjacent coverage; GM-009 should verify the chosen path without weakening signed transition, source-event, or watermark checks.
- Rotating twice for the same logical removal can strand A/B on different epochs or leak intent to Charlie. Criteria must reject duplicate effective rotation.
- A duplicate timeline row could mislead users even if member state is correct. Host/criteria proof should pin one logical timeline/removal effect where durable timeline rows are present.
- Simulator state can be stale after prior device runs. Execution should clean or reboot simulator app state if a device proof fails from build/session contamination, as GM-008 did.

## exact tests and gates to run

Direct host tests:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery'
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
```

Criteria and analyzer:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
dart analyze integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_membership_smoke_test.dart lib/features/groups/application/remove_group_member_use_case.dart
```

Simulator discovery and proof:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm009 -d <alice_ios_simulator_id>,<bob_ios_simulator_id>,<charlie_ios_simulator_id>
```

The `<..._ios_simulator_id>` values must be three distinct iOS simulator IDs visible to Flutter. Do not use physical iOS or Android devices as GM-009 closure proof. If the prior GM-008 simulators are booted and visible, the expected command shape is:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm009 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## known-failure interpretation

- A simulator proof that fails from Xcode DerivedData, stale app container, or stale runner session is an environmental blocker, not GM-009 closure. Clean simulator/app build state, rerun the exact `--scenario gm009` simulator command, and record both the failed and recovered artifact paths.
- A physical-device-only pass is not GM-009 closure evidence.
- Existing unrelated dirty files or unrelated untracked rollout docs must not be staged, reverted, or classified as GM-009 changes.
- Existing GM-008 recovered proof remains accepted and should not be downgraded because GM-009 requires new direct proof.

## done criteria

- GM-009 host regression exists and passes.
- Any necessary production fix is limited to duplicate remove idempotence and does not weaken authorization, stale-event, or removed-member fail-closed behavior.
- `gm009` criteria, runner, and harness support exist and pass direct validation.
- Exact three-iOS-simulator `--scenario gm009` proof passes with an `ok: true` orchestrator verdict and recorded simulator IDs.
- Direct tests, `groups`, `completeness-check`, analyzer, and `git diff --check` pass or have clearly documented pre-existing/environmental failures.
- No source matrix or breakdown files are edited during the GM-009 implementation pass unless a later closure request explicitly asks for closure docs.

## scope guard

Do not broaden this session into restart/re-add, history-boundary, role-permission, media, notification, transport failover, final rollout closure, or matrix maintenance work.

Do not require real external devices. Simulator proof is mandatory for device-backed closure.

Do not reopen GM-008. GM-008 is covered by its recovered exact three-iOS-simulator verdict and remains separate from GM-009.

Do not change `--scenario all` unless the smallest clean runner update requires help-text or scenario list consistency. Direct `--scenario gm009` is the proof target.

## accepted differences / intentionally out of scope

- Listener duplicate replay tests are accepted adjacent evidence, not GM-009 closure by themselves.
- A/B/C simulator proof is enough for this row; four-device Dana paths are irrelevant.
- Multi-relay and real physical-device diversity are out of scope for GM-009 and should stay in nightly/release pools if needed later.
- Source matrix and breakdown closure updates are intentionally out of scope for this planning-only turn.

## dependency impact

GM-009 closes a duplicate membership mutation reliability gap needed before later removal/idempotence rows can rely on remove-event dedupe behavior. If GM-009 reveals that duplicate remove requires a new durable source-event watermark not currently modeled by the app, later membership replay rows should depend on that narrower fix instead of inventing per-row duplicate guards.

If GM-009 passes with test/harness additions only, later rows should treat direct duplicate remove as covered by GM-009 evidence and should not reopen GM-008 restart/re-add proof.

## QA Review Progress

| Timestamp | Phase | Files/evidence inspected | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-10 21:11:31 CEST | Isolated QA review completed | `git diff --stat`; `git diff --name-only`; `git status --short`; GM-009 diffs in `remove_group_member_use_case.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_criteria_test.dart`; recorded gate evidence; simulator verdict JSON and role verdict JSON files; rerun `git diff --check` | `accepted`: no GM-009 blocking issue found. Duplicate same-event remove is idempotent, update-config/rotation/distribution evidence is at most once, Charlie remains removed, A/B delivery is proven, required gate evidence is recorded as passed, exact three-iOS-simulator `--scenario gm009` verdict exists with `ok: true`, and no physical-device-only proof is used. Current dirty out-of-scope files (`source matrix`, `session-breakdown`, `info.plist`, `group_test_user.dart`, GM-008/other rollout docs) remain present and are treated as pre-existing per executor progress; QA did not edit them. | Report accepted QA verdict; leave closure/source matrix updates to a later closure-only pass. |

## QA Review Verdict

Verdict: `accepted`.

Blocking findings: none.

Evidence checked:
- Worktree review: current tracked diff includes GM-009 implementation/proof surfaces plus pre-existing out-of-scope dirty files; untracked GM-008/other rollout docs are present. QA edited only this GM-009 plan file.
- Behavior review: duplicate Charlie remove uses the same `eventAt` watermark and returns before a second config update; host proof asserts one removal timeline row, one key generation, one remaining-recipient distribution, Charlie exclusion, and exact A/B post-removal delivery.
- Criteria/harness review: direct `gm009` scenario support validates missing duplicate proof, duplicate rotation/distribution, Charlie stale membership/access, Charlie plaintext leakage, and missing A/B delivery.
- Recorded gates: focused GM-009 host regression, `member_removal_integration_test.dart`, full `group_membership_smoke_test.dart`, `group_new_member_onboarding_test.dart`, focused GM-009 criteria test, targeted analyzer, exact three-iOS-simulator `--scenario gm009`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` are recorded as passed.
- Independent artifact check: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm009_BVfZlR/gmp_1778439691828_gm009_orchestrator_verdict.json` exists and contains `scenario: gm009`, `ok: true`, and role devices for Alice/Bob/Charlie iOS simulators.
- Independent hygiene check: rerun `git diff --check` passed with no output.

Residual risks:
- QA did not rerun the full simulator proof or all host gates; this review relies on recorded gate results plus the existing `ok: true` verdict artifacts and a fresh diff hygiene check.
- The worktree still contains pre-existing out-of-scope dirty files, so any later commit or closure pass must stage by explicit path and avoid source matrix/session-breakdown/GM-008 doc churn unless that pass explicitly owns it.
