# GM-029 Session Plan: Config Version Monotonicity Across Devices

Status: execution-ready

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-11 17:39:16 CEST | Planner completed | This GM-029 plan draft | Draft verdict: GM-029 is not evidence-only; it needs exact tests and likely code to make membership/config versions monotonic. | Run Reviewer on scope, proof, gates, and closure bar. |
| 2026-05-11 17:40:49 CEST | Reviewer started | This GM-029 plan draft and mandatory section checklist | Reviewer found the plan sufficient with adjustment: the regression contract needed a concrete event sequence/final state to minimize execution ambiguity. | Patch the test contract, then arbitrate. |
| 2026-05-11 17:40:49 CEST | Reviewer completed | This GM-029 reviewer-adjusted plan | Sufficient with adjustment; no structural blocker remains after naming baseline/v2/v3/v4, final A/B/C active set, role, key epoch, and topic/durable assertions. | Run Arbiter and finalize execution-ready status if no structural blocker remains. |
| 2026-05-11 17:41:16 CEST | Arbiter started | This GM-029 reviewer-adjusted plan | Reviewer finding is an incremental detail already handled, not a structural blocker. | Finalize status and stop if no new structural blocker remains. |
| 2026-05-11 17:41:16 CEST | Arbiter completed | This GM-029 final plan | No structural blockers remain; accepted differences and deferred details are documented. GM-029 is execution-ready and not evidence-only. | Hand off this single-session plan; do not write a final program verdict or matrix closure in this planning pass. |

## Final Verdict

GM-029 is `implementation-ready` for a narrow code-and-test session. The evidence-gated intake does not close as evidence-only because no exact GM-029 proof exists, the source matrix row remains `Open`, and current code does not make membership `configVersion` a monotonic source of truth across A/B/C event permutations.

Execution must add exact GM-029 proof first. If that proof unexpectedly passes unchanged, execution should stop product edits and use the new proof for a later closure pass. If it fails, implement only the missing monotonic version comparison and convergence fixes needed for GM-029.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Command | Decision / blocker | Next action |
| --- | --- | --- | --- | --- | --- |
| 2026-05-11 17:42:41 CEST | Contract extracted | `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-029-plan.md`; `Test-Flight-Improv/test-gate-definitions.md`; `git status --short` | `git status --short`; `sed -n '1,220p' Test-Flight-Improv/test-gate-definitions.md` | Contract is execution-ready and code/test scoped. Dirty worktree has many prior-session changes, so GM-029 must preserve unrelated GM-024/025/027/028 work and only update this plan plus GM-029 implementation/tests. | Spawn Executor with bounded GM-029 scope. |
| 2026-05-11 17:43:59 CEST | Executor baseline recorded | `git status --short`; this GM-029 plan | `git status --short` | Dirty baseline captured before owner-file edits; source matrix, session breakdown, closure ledger, and final program verdict are out of scope. | Inspect current diffs for dirty owner files before adding GM-029 proof. |
| 2026-05-11 17:50:36 CEST | GM-029 proof added | `test/features/groups/application/group_message_listener_test.dart`; `test/features/groups/integration/group_membership_smoke_test.dart` | pending: `flutter test --no-pub ... --plain-name 'GM-029'` selectors | Added proof-first GM-029 tests: focused stale-version listener proof plus A/B/C shuffled config convergence proof with role, permission, key epoch, topic/subscription, bridge config, stale-after-latest, and exact-once delivery assertions. | Run focused GM-029 selectors before product edits. |
| 2026-05-11 17:53:34 CEST | GM-029 RED/GREEN and fix | `lib/features/groups/application/group_config_payload.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/add_group_member_use_case.dart`; `lib/features/groups/application/remove_group_member_use_case.dart`; `lib/features/groups/application/update_group_member_role_use_case.dart`; GM-029 tests | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'` | RED before product edits: focused listener removed Charlie after stale v2; A/B/C proof recorded stale conflict/self-leave and watermark mismatch. Product fix added configVersion parsing/comparison, explicit-version stale remove ignore, membership-aware configVersion producers, and delayed release in proof for deterministic queued order. Both focused GM-029 selectors now pass. | Run adjacent GM-011/012/024/025 selectors, onboarding selector, groups gate, and `git diff --check`. |
| 2026-05-11 17:57:30 CEST | Executor validation complete | GM-029 implementation/tests; this GM-029 plan | Focused and adjacent Flutter selectors; `./scripts/run_test_gates.sh groups`; `git diff --check` | Focused GM-029 selectors passed after the monotonic version fix. Adjacent GM-011/GM-012/GM-024/GM-025 selectors passed; `group_new_member_onboarding_test.dart` passed; `groups` gate passed with `+133`; `git diff --check` passed with no output. Go product code was not touched, so Go non-race/race selectors were not required. | Hand off to separate QA Reviewer; do not mark source matrix closure or final QA acceptance in this Executor pass. |
| 2026-05-11 18:02:03 CEST | QA Reviewer reruns | GM-029 implementation/tests; this GM-029 plan | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'`; `git diff --check` | Focused GM-029 listener selector passed (`+1`), focused GM-029 A/B/C shuffled convergence selector passed (`+1`), and diff hygiene passed. Executor evidence for adjacent GM-011/012/024/025, onboarding, and groups gate was reviewed. | Record QA verdict; source matrix/breakdown/ledger/final verdict remain untouched. |
| 2026-05-11 18:05:10 CEST | Fix pass 1 started | This GM-029 plan; `/tmp/gm029-qa-result.md`; `lib/features/groups/application/group_config_payload.dart`; add/remove/role-update producer files; existing producer/listener/smoke tests | `cat /tmp/gm029-qa-result.md`; `git status --short`; `git diff -- ...`; targeted `sed`/`rg` inspection | QA blocker is isolated to membership producers emitting a configVersion from later metadata while persisting the membership event timestamp as the watermark. Existing dirty GM-024/025/027/028 and GM-029 first-pass diffs were inspected and must be preserved. | Add a narrow explicit membership config-version override, use it only in add/remove/role-update producers, then add focused GM-029 producer regressions. |
| 2026-05-11 18:06:15 CEST | Fix pass 1 RED proof | `test/features/groups/application/group_membership_config_version_producers_test.dart` | `flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart --plain-name 'GM-029'` | New GM-029 producer regression failed as expected: add/remove/role-update emitted metadata `configVersion` `2026-05-11T08:20:00.000Z` while the membership event/watermark expectation was `2026-05-11T08:05:00.000Z`; default metadata-only payload check passed. | Patch `buildGroupConfigPayload` with explicit version override and pass normalized membership event timestamps from the three producers. |
| 2026-05-11 18:06:49 CEST | Fix pass 1 producer fix | `lib/features/groups/application/group_config_payload.dart`; `lib/features/groups/application/add_group_member_use_case.dart`; `lib/features/groups/application/remove_group_member_use_case.dart`; `lib/features/groups/application/update_group_member_role_use_case.dart`; `test/features/groups/application/group_membership_config_version_producers_test.dart` | `dart format ...`; `flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart --plain-name 'GM-029'` | Added optional explicit config-version override and used it only for add/remove/role-update membership-producing snapshots. New GM-029 producer selector now passes (`+4`), including default metadata-only behavior without override. | Run existing required GM-029 selectors, adjacent selectors, onboarding, groups gate, and diff hygiene. |
| 2026-05-11 18:08:31 CEST | Fix pass 1 validation complete | GM-029 product/test fix; this GM-029 plan | Required focused producer selector; existing GM-029 listener/smoke selectors; adjacent GM-011/012/024/025; onboarding; `./scripts/run_test_gates.sh groups`; `git diff --check` | All required fix-pass validation passed: new producer selector `+4`, listener GM-029 `+1`, smoke GM-029 `+1`, adjacent selectors passed, onboarding `+7`, groups gate `+133`, and diff hygiene passed. Go product was not touched, so Go selectors were not required. | Hand back for QA review of fix-pass 1. Do not edit source matrix, session breakdown, closure ledger, or final program verdict. |
| 2026-05-11 18:11:23 CEST | Fix pass 1 QA re-review | GM-029 producer/listener/smoke implementation and tests; this GM-029 plan; `/tmp/gm029-fix1-executor-result.md`; source matrix/breakdown scope check | `flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart --plain-name 'GM-029'`; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'`; `git diff --check` | Accepted: producer proof covers later metadata for add/remove/role-update and default metadata-only payload behavior; GM-029 listener and A/B/C shuffled convergence proof still pass; adjacent/gate executor evidence reviewed; Go product was not touched by GM-029, so Go selectors were not required. | Ready for later closure pass; source matrix row remains intentionally unedited/Open and no breakdown/ledger/final verdict closure was written. |

### Executor Dirty Baseline

Captured with `git status --short` at 2026-05-11 17:43:59 CEST:

```text
 M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md
 M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md
 M go-mknoon/node/group_inbox.go
 M go-mknoon/node/group_inbox_test.go
 M go-mknoon/node/node.go
 M go-mknoon/node/pubsub.go
 M go-mknoon/node/pubsub_delivery_test.go
 M go-mknoon/node/pubsub_test.go
 M info.plist
 M integration_test/group_multi_device_real_harness.dart
 M integration_test/group_multi_party_device_real_harness.dart
 M integration_test/scripts/group_multi_party_device_criteria.dart
 M integration_test/scripts/run_group_multi_party_device_real.dart
 M lib/core/bridge/go_bridge_client.dart
 M lib/features/groups/application/add_group_member_use_case.dart
 M lib/features/groups/application/broadcast_voluntary_leave_use_case.dart
 M lib/features/groups/application/group_config_payload.dart
 M lib/features/groups/application/group_key_update_listener.dart
 M lib/features/groups/application/group_message_listener.dart
 M lib/features/groups/application/handle_incoming_group_message_use_case.dart
 M lib/features/groups/application/remove_group_member_use_case.dart
 M lib/features/groups/application/send_group_message_use_case.dart
 M lib/features/groups/domain/models/group_member.dart
 M lib/features/groups/presentation/screens/group_info_wired.dart
 M test/features/groups/application/add_group_member_use_case_test.dart
 M test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
 M test/features/groups/application/group_key_update_listener_test.dart
 M test/features/groups/application/group_message_listener_test.dart
 M test/features/groups/application/handle_incoming_group_message_use_case_test.dart
 M test/features/groups/application/leave_group_use_case_test.dart
 M test/features/groups/application/member_removal_integration_test.dart
 M test/features/groups/application/remove_group_member_use_case_test.dart
 M test/features/groups/application/send_group_message_use_case_test.dart
 M test/features/groups/integration/group_membership_smoke_test.dart
 M test/features/groups/integration/group_startup_rejoin_smoke_test.dart
 M test/integration/group_multi_party_device_criteria_test.dart
 M test/shared/fakes/group_test_user.dart
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-008-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-009-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-010-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-012-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-013-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-014-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-015-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-016-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-017-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-018-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-019-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-020-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-021-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-022-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-023-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-024-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-025-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-027-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-028-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-029-plan.md
?? Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
```

## Executor Evidence And Verdict

Executor verdict: implementation and test evidence are ready for separate QA Reviewer inspection. This is not final QA acceptance and does not update the source matrix row, session breakdown, closure ledger, or final program verdict.

Files changed by this GM-029 Executor pass:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-029-plan.md`

Tests added or updated:

- `GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent` in `test/features/groups/application/group_message_listener_test.dart`.
- `GM-029 config version monotonicity converges across A/B/C shuffled delivery` in `test/features/groups/integration/group_membership_smoke_test.dart`.

Exact command evidence:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'` - RED before product edits: stale v2 removal could remove Charlie after newer v4; PASS after monotonic version fix.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'` - RED before product edits: shuffled stale delivery exposed stale conflict/self-leave and watermark mismatch; PASS after monotonic version fix.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012'` - PASS after the equal-version add replay compatibility fix.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` - PASS (`+7`).
- `./scripts/run_test_gates.sh groups` - PASS (`+133`).
- `git diff --check` - PASS with no output.

Go product touched: no. The conditional Go non-race and race selectors were not required because this Executor pass changed only Dart product code, Dart tests, and this GM-029 plan.

Blocker class: none for the Executor pass.

Residual uncertainty for QA: the source matrix remains intentionally open for a later closure pass; QA still needs to review scope adherence and the landed diff. No device-backed optional integration test was run because the plan marks it optional when host/fake A/B/C proof covers ordering, roles, key epoch, and topic/discovery convergence.

## QA Reviewer Verdict

Final QA verdict: `blocked`.

Blocking issue:

- `qa_blocking_issue`: the local add/remove/role-update producers still can record a membership watermark that differs from the `groupConfig.configVersion` they emit. `buildGroupConfigPayload` chooses the latest of `createdAt`, `lastMetadataEventAt`, and `lastMembershipEventAt`, while the producers record only the membership event timestamp through `recordGroupMembershipEventWatermark`. If `lastMetadataEventAt` is later than the membership event timestamp, the bridge config can advertise a newer `configVersion` than the local `lastMembershipEventAt`, leaving the producer able to accept later stale membership/config events between those two timestamps. This misses the plan's local producer watermark/configVersion consistency requirement and has no direct regression proving add/remove/role-update producers record the same version they emit.

Non-blocking follow-ups:

- None separated from the blocker.

QA evidence reviewed or rerun:

- Reran `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- Reran `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- Reran `git diff --check` - PASS.
- Reviewed executor-recorded PASS evidence for GM-011/GM-012/GM-024/GM-025 focused selectors, `group_new_member_onboarding_test.dart`, and `./scripts/run_test_gates.sh groups`.
- Confirmed Go product was not touched by this GM-029 pass; conditional Go non-race/race selectors remain not required for GM-029.
- Confirmed source matrix row GM-029 remains `Open`; breakdown/closure ledger/final program verdict were not updated by this QA pass.

Recommended next retry focus:

- In a fix pass, make add/remove/role-update producers record the exact parsed `groupConfig.configVersion` they emit, or make `buildGroupConfigPayload` prefer an explicit membership event version for membership-producing calls. Add focused producer tests that set `lastMetadataEventAt` later than the membership event timestamp and assert emitted configVersion, persisted watermark, and stale-after-latest rejection stay aligned.

## Fix Pass 1 Evidence And Verdict

Fix-pass Executor verdict: ready for QA re-review. The QA blocker is resolved in the landed fix-pass scope.

Files changed by this fix pass:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `test/features/groups/application/group_membership_config_version_producers_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-029-plan.md`

Fix-pass behavior:

- `buildGroupConfigPayload` now accepts an optional explicit `configVersionOverride`.
- Add/remove/role-update producers pass the same normalized membership event timestamp to `configVersionOverride` that they persist through `recordGroupMembershipEventWatermark`.
- The default payload path still chooses the later metadata timestamp when no override is supplied, preserving metadata-only behavior outside membership-producing calls.

Fix-pass tests added:

- `GM-029 add producer emits membership configVersion when metadata is newer`
- `GM-029 remove producer emits membership configVersion when metadata is newer`
- `GM-029 role-update producer emits membership configVersion when metadata is newer`
- `GM-029 default config payload still uses later metadata version without override`

Exact command evidence:

- `flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart --plain-name 'GM-029'` - RED before product fix for add/remove/role-update (`configVersion` was `2026-05-11T08:20:00.000Z` instead of `2026-05-11T08:05:00.000Z`); PASS after fix (`+4`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'` - PASS.
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` - PASS (`+7`).
- `./scripts/run_test_gates.sh groups` - PASS (`+133`).
- `git diff --check` - PASS with no output.

Go product touched: no. The conditional Go non-race and race selectors were not required.

Source matrix, session breakdown, closure ledger, and final program verdict were not edited.

## Fix Pass 1 QA Re-review Verdict

Final QA verdict: `accepted` for this GM-029 plan execution.

Blocking issues remaining:

- None.

QA evidence rerun:

- `flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart --plain-name 'GM-029'` - PASS (`+4`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'` - PASS (`+1`).
- `git diff --check` - PASS with no output.

QA evidence reviewed:

- Fix-pass producer tests prove add/remove/role-update emit `groupConfig.configVersion` from the same normalized membership event timestamp persisted as `lastMembershipEventAt` even when `lastMetadataEventAt` is later.
- Default `buildGroupConfigPayload` behavior without override still uses the later metadata timestamp and validates the state hash.
- Existing GM-029 proof still covers shuffled A/B/C ordering, version comparison, active membership convergence, role/permission convergence, key epoch convergence, topic/discovery convergence, and stale-after-latest handling.
- Executor evidence for adjacent GM-011/GM-012/GM-024/GM-025 selectors, `group_new_member_onboarding_test.dart`, and `./scripts/run_test_gates.sh groups` was reviewed and remains sufficient.
- Go product was not touched by GM-029; conditional Go non-race and race selectors were not required.
- Source matrix row GM-029 remains intentionally unedited/Open for a later closure pass; the source matrix, session breakdown, closure ledger, and final program verdict were not updated by this QA re-review.

Non-blocking follow-ups:

- None.

Closure readiness: ready for closure by a later closure pass, which should update the source row/matrix with this concrete evidence.

## Final Plan

### real scope

Own exactly source row GM-029: `Config version monotonicity is enforced across devices`.

In scope:

- A/B/C receive the same versioned membership/config events in different deterministic shuffled orders.
- Each peer compares incoming event/config versions monotonically before applying local membership, role, bridge config, key, and topic/discovery state.
- Final active membership, roles/permissions, latest key epoch, and topic/discovery state converge on A, B, and C.
- Row-owned tests may touch fake-network host tests and targeted Go tests if stale config can reach the Go validator/topic layer.

Out of scope:

- No source matrix or breakdown closure edits in this planning pass.
- No final program verdict.
- Do not reopen GM-024, GM-025, GM-027, or GM-028 unless an exact GM-029 regression proves their concrete evidence is false.
- No redesign of group invite UX, notification routing, general signed-audit architecture, or real-device harnesses unless host proof cannot demonstrate the row.

### closure bar

GM-029 is good enough only when concrete evidence proves all of this:

- Event ordering: A/B/C each apply the same membership/config events in at least three different deterministic orders, including latest-first and stale-after-latest.
- Version comparison: every membership/config application compares the incoming version against the local applied membership/config version; older versions are ignored and same-version duplicates are idempotent.
- Active membership convergence: final peer sets and duplicate counts match across A/B/C.
- Role convergence: final roles and permission overrides match across A/B/C, including the member changed by the newest event.
- Key epoch convergence: final `GroupKeyInfo` latest generation and bridge key epoch are the newest epoch on A/B/C; delayed older key updates do not demote the active key.
- Topic/discovery convergence: all final active members are subscribed/joined, removed or stale members are not counted, bridge `group:updateConfig` payloads and Go expected-member counts reflect the same final active peer set, and post-convergence sends deliver exactly once to valid recipients.
- The source matrix row can later be updated to `Covered`/closed with exact GM-029 command evidence. GM-029 is not accepted while the source row remains `Open`.

### source of truth

Authoritative order:

- Current code and tests in this repo.
- Source matrix row GM-029 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`.
- Breakdown row 45 / GM-029 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; if they disagree, the script wins.
- Prior GM-024/GM-025/GM-027/GM-028 closure text is historical evidence only and must not be reopened without a concrete failing GM-029 proof.

### session classification

`implementation-ready`.

The session started as `evidence-gated`, but repo evidence shows the exact row proof is missing. Current evidence is not enough for acceptance-only or stale/already-covered closure.

### exact problem statement

A/B/C can receive membership/config events in different orders. Today, membership ordering is mostly guarded by event timestamps and `lastMembershipEventAt`, while `configVersion` is generated from metadata timestamps only and is dropped by Go's `GroupConfig` struct. That leaves no exact proof that a newer authoritative config cannot be overwritten by an older event/config snapshot on another peer, or that roles, key epoch, and topic/discovery state converge after shuffled delivery.

User-visible behavior that must improve:

- Devices must settle on the same active group roster, roles, key epoch, and ability to publish/receive after out-of-order membership delivery.
- Stale events must not remove active members, revive removed members, downgrade roles, demote key epoch, or alter topic/discovery expected counts.

Behavior that must stay unchanged:

- Valid membership add/remove/re-add, role update, key rotation, durable inbox, and live topic delivery continue to work.
- Existing GM-024/025/027/028 covered behavior remains covered.
- Legacy missing-version events keep the existing timestamp fallback where required for backward compatibility.

### files and repos to inspect next

Production files:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`

Tests:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub_delivery_test.go` only if live Go topic update behavior is changed.
- `integration_test/group_real_crypto_onboarding_test.dart` only if host/fake proof cannot cover key/topic convergence.

### existing tests covering this area

Already-covered adjacent behavior:

- GM-011 and GM-012 in `group_membership_smoke_test.dart` cover specific stale add/remove arrival orders.
- GM-024 covers A/B/C display, key epoch, durable recipient uniqueness, and topic state after Charlie re-add.
- GM-025 covers role/permission re-add correctness.
- GM-027 and GM-028 cover malformed member filtering and publish/discovery target safety.
- `group_key_update_listener_test.dart` already proves delayed older key updates after newer generations do not promote the active key.
- Go tests cover `UpdateGroupConfig` replacement, config clone normalization, discovery target counting, and race-free config readers.

Missing for GM-029:

- No exact `GM-029` selector exists.
- No property-style A/B/C permutation proof combines version comparison, active membership, role convergence, key epoch convergence, and topic/discovery convergence.
- No proof that `configVersion` is membership-aware; `_groupConfigVersion` currently uses only `lastMetadataEventAt ?? createdAt`.
- No proof that Go can preserve topic/discovery state if an older config update reaches `UpdateGroupConfig` after a newer one; Go currently has no `configVersion` field.

### regression/tests to add first

Add these before product changes:

- `group_membership_smoke_test.dart`: `GM-029 config version monotonicity converges across A/B/C shuffled delivery`.
  - Use seeded deterministic permutations rather than nondeterministic randomness.
  - Build full config snapshots with explicit increasing versions for a concrete sequence: baseline v1 `{A admin, B writer, C writer}` at key epoch 1; v2 removes C and rotates active A/B to epoch 2; v3 re-adds C as `reader` with epoch 3; v4 updates C to final `writer` permissions while keeping epoch 3.
  - Deliver events to A, B, and C in different orders using direct replay/listener entry points.
  - Include a stale event after the newest event on at least one peer.
  - Assert identical final member set `{A, B, C}`, exactly one row per member, final C role/permissions from v4, latest key epoch 3, topic joined/subscription state for all active peers, bridge `group:updateConfig` final member set, durable recipient set, and exact-once post-convergence delivery.
- `group_message_listener_test.dart`: focused unit/integration proof that an older versioned `member_added`, `members_added`, `member_removed`, or `member_role_updated` snapshot is ignored after a newer version is applied, while a same-version same-state replay is idempotent.
- `group_key_update_listener_test.dart`: add only if the GM-029 end-to-end test needs a row-owned selector for epoch permutation beyond the existing delayed older key proof.
- `go-mknoon/node/pubsub_test.go`: add only if stale configs can reach Go after Dart filtering. If needed, prove `UpdateGroupConfig` ignores older `ConfigVersion` values, accepts newer values, and keeps expected connected/dial target counts aligned with the newest config.

If the exact GM-029 host/fake proof passes before product edits, stop and record evidence-only closure requirements. If it fails, patch only the failing monotonic seam.

### step-by-step implementation plan

1. Record dirty baseline with `git status --short`. Before editing any dirty owner file, inspect its current diff and preserve unrelated accepted-session changes.
2. Add the focused GM-029 tests first with `--plain-name 'GM-029'` selectors.
3. Run the exact new selectors. Classify whether failures are missing proof only, Dart membership version comparison, key epoch demotion, bridge config sync, Go topic/discovery downgrade, or test fixture setup.
4. If membership/config versions are not monotonic, update `group_config_payload.dart` and the group config producers so membership snapshots carry an increasing ISO timestamp version. Prefer using the event's own membership timestamp; fall back to `lastMembershipEventAt`, `lastMetadataEventAt`, then `createdAt` for legacy compatibility.
5. In `group_message_listener.dart`, centralize incoming membership version resolution before applying `_applyAuthoritativeGroupConfigSnapshot` or `_syncGroupConfig`. Use strict newer-than comparison against the local applied membership watermark; treat same-version same-state as idempotent and same-version conflicting state as rejected/logged rather than applied.
6. Ensure add, remove, and role-update producers record or pass the same version they embed in `groupConfig`, so outgoing snapshots are monotonic and the local watermark cannot lag the emitted config version.
7. Preserve existing key monotonicity in `group_key_update_listener.dart`; patch only if the GM-029 proof shows a newer key can be demoted or bridge `group:updateKey` can be called with an older active epoch.
8. If stale config updates can still reach Go, add optional `ConfigVersion` support to `go-mknoon/node/group.go` and compare it in `UpdateGroupConfig` in `pubsub.go`. Keep legacy empty-version behavior compatible and avoid changing topic join/leave APIs beyond the version check.
9. Rerun focused GM-029 selectors, adjacent GM-011/GM-012/GM-024/GM-025 selectors, key listener selector if touched, Go selectors if touched, and the named gates below.
10. Leave matrix/breakdown closure to a later closure pass. The implementation session may update this GM-029 plan with execution evidence, but must not write a final program verdict unless separately instructed by the rollout pipeline.

### risks and edge cases

- Shuffled delivery must be deterministic to avoid flaky "random" proof.
- Missing or malformed legacy versions must not break existing deployed events; the timestamp fallback must be explicit.
- Same-version conflicting snapshots are dangerous because either order could win; they should be rejected or treated as non-closable until the signed/event source can disambiguate them.
- Local direct producers must not emit a config version and then record a different watermark.
- A self-removal stale event after re-add must not unsubscribe C or delete C's group after the newer re-add version.
- Topic/discovery convergence must check both local Flutter fake-network subscription and the bridge/Go config member set, because UI roster convergence alone is not enough.
- The worktree is already dirty across likely owner files; execution must not revert unrelated prior accepted sessions.

### exact tests and gates to run

Focused GM-029 selectors:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029'`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name 'GM-029'` if remove/local corruption proof is added there.
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-029'` if key listener proof or code changes are added.
- `(cd go-mknoon && go test ./node -run 'TestGM029|TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)` if Go code or tests are touched.
- `(cd go-mknoon && go test -race ./node -run 'TestGM029|TestGM028|TestGM027|TestGM023|TestFindMember_DuplicatePeerId' -count=1)` if Go config/topic code is touched.

Adjacent regression selectors:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-012'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-024'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-025'`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`

Named gates and hygiene:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check` if new tests/files require classification, or after any gate-definition change.
- `git diff --check`

Optional only if host proof is insufficient or integration harnesses are touched:

- `flutter test --no-pub integration_test/group_real_crypto_onboarding_test.dart`

### known-failure interpretation

- RED from the first exact GM-029 selector is expected if current code lacks monotonic version behavior.
- A pre-existing broad `groups` failure is not a GM-029 blocker if focused GM-029 and touched direct selectors pass and the failure is unrelated by file/stack.
- If `completeness-check` fails because unrelated pre-existing test files are unclassified, record that separately; only classify new GM-029 files if execution creates any. Prefer adding GM-029 tests to existing classified files.
- Simulator or native asset infrastructure failures are not GM-029 evidence unless they reproduce in a host/fake selector.

### done criteria

- Exact GM-029 tests exist and pass.
- Final A/B/C assertions prove event ordering, version comparison, active membership convergence, role convergence, key epoch convergence, and topic/discovery convergence.
- Product patches, if any, are limited to the monotonic version/config/key/topic seams proven by RED tests.
- Adjacent GM-011/GM-012/GM-024/GM-025 focused selectors still pass or any failure is proven unrelated.
- Required Go selectors and `-race` pass if Go code is touched.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass, or unrelated failures are documented with focused GM-029 green proof.
- Later closure can update source matrix row GM-029 to `Covered` with concrete evidence; this planning task does not do that.

### scope guard

Do not broaden GM-029 into:

- A general CRDT or distributed consensus rewrite.
- New group membership schema migrations unless a simple timestamp/config-version comparator cannot satisfy the row.
- A real-device multi-party harness unless host/fake proof is impossible.
- Reopening GM-024/025/027/028 without failing GM-029 proof.
- Retrofitting every group metadata or invite path beyond the config-version fields needed for membership monotonicity.

Overengineering signals:

- Adding nondeterministic randomized tests instead of seeded permutations.
- Creating a new event bus or snapshot store when `lastMembershipEventAt` and `configVersion` can carry the needed ordering.
- Changing UI roster rendering or permissions policy to mask stale config application.

### accepted differences / intentionally out of scope

- Existing key listener tests already cover delayed older key updates; GM-029 should reuse that evidence unless the combined A/B/C proof exposes a new key demotion.
- Metadata-only `configVersion` behavior can remain for pure metadata events if membership events get an explicit monotonic version path.
- Device-backed `integration_test/group_real_crypto_onboarding_test.dart` is optional, not required, if host/fake A/B/C proof covers ordering, roles, key epoch, and topic/discovery state.
- Closure documentation is out of this planning pass; source row remains Open until a later execution/closure pass records concrete evidence.

### dependency impact

- Later GM-029 closure depends on this plan producing exact evidence and, if needed, a small monotonic version implementation.
- Rows after GM-029 should not claim config-order convergence until GM-029 source row is `Covered`/closed.
- Any future group recovery, onboarding, or real-network reliability proof can depend on GM-029 only after the source matrix row is updated with concrete commands and results.

## Structural Blockers Remaining

None. Reviewer classified the plan as sufficient after the concrete v1/v2/v3/v4 GM-029 event sequence was added.

## Incremental Details Intentionally Deferred

- Exact helper names for parsing/comparing versions are deferred to implementation after the RED proof names the failing seam.
- Whether Go needs a `ConfigVersion` field is conditional on whether stale configs can reach `UpdateGroupConfig` after Dart listener filtering.

## Accepted Differences Intentionally Left Unchanged

- GM-029 does not require a broad final program verdict.
- GM-029 does not require reopening GM-024/GM-025/GM-027/GM-028 without concrete current failure.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/update_group_member_role_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/group.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/bridge/bridge.go`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`

## Why The Plan Is Safe Or Unsafe To Implement Now

Safe to implement now: the scope is one source row, the first step is exact RED/GREEN proof, product edits are conditional on proof failure, dirty-state handling is explicit, and closure requires concrete commands before any source-matrix Covered claim.
