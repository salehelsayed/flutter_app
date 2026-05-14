Status: accepted/closed

# GE-015 Session Plan - App Restart On Admin During Mutation

## Planning Progress

- 2026-05-13T14:46:58Z - Role: Arbiter completed. Files inspected since last update: reviewed GE-015 plan. Decision/blocker: no structural blockers remain; the plan is execution-ready and must stay scoped to GE-015. Next action: execute only from this plan when implementation is requested.
- 2026-05-13T14:46:58Z - Role: Reviewer completed. Files inspected since last update: draft GE-015 plan. Decision/blocker: sufficient after adding exact add/remove boundary language, device/relay proof profile, rollback rules, and no-doc-update guard. Next action: arbiter classification.
- 2026-05-13T14:46:58Z - Role: Planner completed. Files inspected since last update: evidence set below. Decision/blocker: reclassify GE-015 from `needs_repo_evidence` / `evidence-gated` to `needs_code_and_tests` / `implementation-ready`; missing proof support is repo-owned. Next action: reviewer sufficiency pass.
- 2026-05-13T14:46:58Z - Role: Evidence Collector completed. Files inspected since last update: GE-015 source row, breakdown rows 1578/1797/2054, GE-014 plan, GE-006 through GE-014 closure patterns, group mutation/fanout code, resume/retry code, criteria/runner/harness support, and test gate definitions. Decision/blocker: exact GE-015 host, criteria, runner, and device-harness proof is absent. Next action: draft code/tests plan.
- 2026-05-13T14:43:45Z - Role: Evidence Collector started. Files inspected since last update: target plan file. Decision/blocker: no blocker; collect repo-owned proof seams before drafting. Next action: inspect GE-015 row context, nearby completed row plans/tests, mutation/key fanout code, and reliability gates.

## Execution Progress

- 2026-05-13T14:51:19Z - Role: Controller contract extracted. Files inspected since last update: this GE-015 plan, `git status --short`, `codex exec --help`, and `rg -n "ge015|GE-015" integration_test test lib go-mknoon -S`. Decision/blocker: spawned execution is available through `codex exec`; current code search returned no GE-015 support, matching the plan gap; dirty worktree contains broad prior rollout changes and must be preserved. Next action: spawn isolated Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-05-13T14:53:06Z - Role: Executor started. Files inspected since last update: this GE-015 plan and `git status --short`. Command run: `rg -n "ge015|GE-015" integration_test test lib go-mknoon -S`. Decision/blocker: command returned no matches, confirming the required GE-015 proof/support is absent before implementation; no blocker. Next action: run the focused host proof to capture the expected red/missing-test baseline.
- 2026-05-13T14:53:26Z - Role: Executor red proof. Files inspected/touched since last update: touched this plan only. Command run: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015'`. Result: failed with exit 79, `No tests ran. No tests match "GE-015"`. Decision/blocker: expected red/missing proof; production changes remain gated until a real failing GE-015 behavior is modeled. Next action: inspect group fake-network tests/helpers and add exact host regression support.
- 2026-05-13T14:56:33Z - Role: Executor inspection. Files inspected since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`, `lib/features/groups/application/group_membership_update_listener.dart`, `lib/features/groups/application/record_group_invite_delivery_attempts.dart`, `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart`. Decision/blocker: existing fake restart/held-delivery seams can model GE-015; add path needs durable pre-fanout invite status support before the UI can honestly survive a restart before invite fanout. Next action: add narrow GE-015 host proof, criteria support, runner/harness scenario, and the smallest invite-status production hardening if the host proof requires it.
- 2026-05-13T14:55:24Z - Role: Controller checkpoint. Files inspected since last update: `git diff --name-only --` GE-015 plan/host/criteria/runner/harness/prod candidate paths, and this plan header. Files changed so far by this GE-015 execution: this plan's `## Execution Progress` only; no new GE-015 code/test/harness change has landed yet. Existing dirty target paths from prior rollout/user work remain present and must not be reverted or overwritten. Current command/test status: isolated Executor is still running after the red focused host selector; latest completed test remains `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015'` failing with exit 79 because no GE-015 test exists. Decision/blocker: no blocker. Next action: continue Executor pass with the smallest focused GE-015 host regression before any production changes.
- 2026-05-13T15:11:44Z - Role: Controller blocked checkpoint. Files inspected since last update: GE-015 plan progress, `git diff --name-only` for touched GE-015 candidate paths, `rg -n "ge015|GE-015" integration_test test lib -S`, focused host output, focused criteria output, format output, and scoped analyzer output. Files changed so far in this GE-015 attempt: `lib/features/groups/application/record_group_invite_delivery_attempts.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and this plan; `dart format` also touched pre-existing dirty `test/features/groups/integration/group_membership_smoke_test.dart`. Current command/test status: no command is still running; Executor was interrupted after failing to produce a trustworthy handoff. Last completed commands: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015'` passed; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-015'` passed; `dart format --set-exit-if-changed ...` exited 1 after formatting `test/features/groups/integration/group_membership_smoke_test.dart`; scoped `dart analyze test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` exited 2 with unused GE-015 harness constants. Decision/blocker: blocked, class `spawn_or_tool_failure` with incomplete implementation evidence; runner/harness support for `--scenario ge015` is not complete because only role/constant stubs were added and the runner has no GE-015 routing. Next safe action: complete the GE-015 runner and real-device harness branches, use or remove the unused harness constants, rerun format/analyze/focused host/criteria/broader group gates/device relay proof, then spawn QA review only after the Executor path completes cleanly.
- 2026-05-13T15:30:38Z - Role: Local execution fallback completed. Files inspected/touched since last update: `lib/features/groups/application/record_group_invite_delivery_attempts.dart`, `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/features/groups/presentation/contact_picker_wired_test.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, and this plan. Decision/blocker: no blocker remains; GE-015 implementation and proof are ready for closure. Evidence: focused GE-015 host passed (`+1`), focused GE-015 criteria passed (`+4`), full criteria passed (`+182`), scoped analyzer clean, Dart-only format clean, full `contact_picker_wired_test.dart` passed (`+21`), full `group_messaging_smoke_test.dart` passed (`+31`), required three-device `--scenario ge015` relay proof passed with run id `1778685690376`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw`, and orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw/gmp_1778685690376_ge015_orchestrator_verdict.json` reporting `ge015 verdicts valid for alice, bob, charlie`; `git diff --check` on GE-015 owned files plus this plan passed. Next action: closure audit must update source matrix row GE-015, breakdown ledgers, and test inventory with this concrete evidence.

## Final Verdict

GE-015 is accepted/closed as a code/tests gap-closure session. The repo now has exact GE-015 host proof, criteria support, runner support, three-device harness support, and narrow production hardening for honest pending invite fanout status. Closure updated the source matrix, session breakdown ledgers, and test inventory with the concrete file/test/device evidence below; residual-only none for GE-015.

## Execution Evidence

Implementation evidence:

- Added `recordPendingGroupInviteFanoutAttempts(...)` in `lib/features/groups/application/record_group_invite_delivery_attempts.dart` so existing-group add/re-add fanout can persist `GroupInviteDeliveryStatus.needsResend` with `lastError: 'invite_fanout_pending_after_membership_update'` before invite delivery finishes.
- Updated `lib/features/groups/presentation/screens/contact_picker_wired.dart` to record pending invite fanout attempts after local member/config mutation and to delete that pending status on rollback if config update fails.
- Added `test/features/groups/integration/group_messaging_smoke_test.dart::GE-015 admin restart during add/remove repairs fanout honestly`, proving remove-fanout interruption before admin restart, fail-closed key promotion, repair after restart, no removed-window Charlie plaintext, durable invite `needsResend` pending status before repair, final sent status, and active peer convergence.
- Added/updated `ge015` criteria support in `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart`.
- Added `--scenario ge015` runner routing in `integration_test/scripts/run_group_multi_party_device_real.dart`.
- Added Alice/Bob/Charlie `ge015` real-device harness roles in `integration_test/group_multi_party_device_real_harness.dart`.

Validation evidence:

- `dart format --set-exit-if-changed integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/integration/group_messaging_smoke_test.dart lib/features/groups/presentation/screens/contact_picker_wired.dart lib/features/groups/application/record_group_invite_delivery_attempts.dart test/features/groups/presentation/contact_picker_wired_test.dart` passed after the earlier Markdown-format invocation was corrected to Dart-only files.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-015'` passed (`+4`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` passed (`+182`).
- `dart analyze lib/features/groups/application/record_group_invite_delivery_attempts.dart lib/features/groups/presentation/screens/contact_picker_wired.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart` passed with no issues.
- `flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart` passed (`+21`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` passed (`+31`).
- Required three-device relay proof passed: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge015 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; run id `1778685690376`; shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw`; orchestrator verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge015_zhM5bw/gmp_1778685690376_ge015_orchestrator_verdict.json`; verdict `ge015 verdicts valid for alice, bob, charlie`.
- `git diff --check` on GE-015 owned files plus this plan passed.

## Evidence Collector Findings

- Source matrix row GE-015 says: "App restart on admin during mutation"; setup is "A restarts after local config update before key fanout completes"; steps are start add/remove, restart A, resume/repair, verify all peers; expected result is "No partial mutation leaves members stranded; retry/fanout status is honest."
- Breakdown row 174 and detailed row 2054 initially classified GE-015 as `needs_repo_evidence` / `evidence-gated`, with "Missing/row-owned: add or verify exact `GE-015` regression for App restart on admin during mutation." Closure reclassified and accepted the row as `needs_code_and_tests` / `covered/accepted`.
- `rg -n "ge015|GE-015"` found no runtime, host-test, criteria, runner, or harness support outside docs and this plan.
- `integration_test/scripts/run_group_multi_party_device_real.dart` supports GE-001 through GE-014 and its usage text stops at `ge014`; there is no `--scenario ge015`.
- `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, and `test/integration/group_multi_party_device_criteria_test.dart` contain neighboring `ge014` support but no GE-015 branch or criteria validator.
- `lib/features/groups/presentation/screens/contact_picker_wired.dart` adds members locally, updates the bridge config, publishes `members_added`, then sends invite/key fanout and records delivery attempts. A restart before invite fanout completes is not proven to leave retry status honest.
- `lib/features/groups/presentation/screens/group_info_wired.dart` removes a member, updates local DB/bridge config, publishes/direct-stores removal replay, then calls `rotateAndDistributeGroupKey` for remaining-member key fanout. A restart during that fanout is not covered by exact proof.
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` fail-closes live execution by promoting the admin key only after recipient distribution succeeds, and tests prove timeout/failure does not call `group:updateKey`; those tests do not prove process death/restart while the fanout future is pending.
- `lib/core/lifecycle/handle_app_resumed.dart` rejoins group topics, drains group inbox, retries stuck group sends/uploads/inbox stores, but evidence did not find an admin-mutation invite/key fanout repair path on resume.
- `GroupInviteDeliveryAttempt` plus `resendGroupInvite` can represent `sent`, `queued`, `needsResend`, and `cannotSend`, but current evidence shows resend is UI-driven and not an exact GE-015 resume/repair proof.
- GE-006 through GE-014 are useful patterns for fake-network host proof, criteria support, runner scenario support, and three-device relay proof. They are not GE-015 proof because none restarts admin A after local mutation state is persisted and before key/invite fanout completes.

## Exact Row Reclassification

| Source | Current classification | GE-015 plan classification | Reason |
| --- | --- | --- | --- |
| Source matrix GE-015 | Initially `Open`, P0 | `Covered` after execution and closure | The row is resolved with concrete source-matrix evidence. |
| Breakdown ordered row 174 | Initially `needs_repo_evidence` / `evidence-gated` | `needs_code_and_tests` / `covered/accepted` | Required gap-closure mode reclassified missing repo-owned proof support into code/tests work, then closure accepted the concrete evidence. |
| Execution mode | Evidence-only unless proof exists | Code/tests gap closure, accepted | Host, criteria, runner, device harness, and narrow invite-status production hardening were added before closure. |

## Real Scope

This session owns exactly GE-015:

- Add exact proof for admin Alice restarting after local membership/config mutation is persisted and before required key or invite fanout completes.
- Cover both repo-owned mutation boundaries that can strand members: existing-member remove with remaining-member key rotation fanout, and existing-group add/re-add with invite/key fanout. If implementation discovers a single shared admin-mutation repair path, both boundaries still need GE-015 evidence fields or subtests.
- Add criteria, runner, and three-device harness support for `ge015`.
- Add the narrowest production repair/status changes only after the red proof shows the current app cannot recover honestly.

This session does not close GE-017 or later property/soak rows, does not redesign group membership, and does not update source matrix, breakdown ledger, closure docs, or test inventory.

## Closure Bar

GE-015 is good enough only when the repo proves this exact boundary:

- Alice/admin begins an add or remove mutation in a private A/B/C group.
- Alice persists the local membership/config mutation before recipient key/invite fanout completes.
- Alice's app/node restarts before the fanout finishes.
- On resume, Alice either repairs the incomplete fanout or leaves durable, user-visible, honest retry status such as `needsResend` or pending repair. Silent loss, fake `sent`, and forgotten pending fanout are failures.
- Bob and Charlie are not stranded: entitled peers receive the required key/invite/update, removed peers do not receive new plaintext, and all active peers converge on membership, key epoch, and message delivery.
- The exact host proof, criteria proof, broader group regression gate, and required three-device relay proof pass.

## Source Of Truth

- Current code and tests win over stale prose.
- Source matrix row GE-015 defines the behavioral contract.
- This plan defines the execution contract for this one session.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; the script wins on disagreement.
- GE-006 through GE-014 can be copied as test/harness patterns only. They cannot be cited as GE-015 closure evidence.

## Session Classification

`implementation-ready`

The row started as evidence-gated, but exact repo-owned proof support is absent, so it must be implemented as code/tests gap closure.

## Exact Problem Statement

Admin-side membership mutation currently has unproven restart safety at the most dangerous point: after Alice changes local group membership/config state but before the required key or invite fanout settles. In that window, a mobile restart can kill in-memory work. The user-visible failure modes are a member who remains locally added but never receives a usable invite/key, a remaining member who cannot decrypt after removal/key rotation, a removed member retaining access beyond the cutoff, or Alice reporting `sent`/complete while fanout is actually incomplete.

Behavior that must stay unchanged:

- Key promotion must remain fail-closed. Alice must not promote a new local/admin key before all required recipient key updates are delivered or durably repairable.
- Removed-window plaintext must remain unavailable to removed members.
- Existing GE-006 through GE-014 contracts must continue to pass.
- Manual invite resend/status behavior must not become less honest.

## File Ownership

Primary proof and harness files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`: first red GE-015 fake-network proof for restart during admin mutation fanout.
- `test/features/groups/integration/group_membership_smoke_test.dart`: use only if invite/status assertions fit existing membership-status patterns better than messaging smoke.
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`: focused proof for process-death-safe or repairable key fanout semantics if production key fanout changes.
- `test/features/groups/presentation/contact_picker_wired_test.dart`: existing-group add/invite status proof if `contact_picker_wired.dart` changes.
- `test/features/groups/presentation/group_info_wired_test.dart`: remove/key-rotation status proof if `group_info_wired.dart` changes.
- `test/integration/group_multi_party_device_criteria_test.dart`: valid and negative `ge015` criteria tests.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: `ge015` requirements and verdict validator.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: `--scenario ge015` orchestration.
- `integration_test/group_multi_party_device_real_harness.dart`: Alice/Bob/Charlie role support for the restart boundary.
- `test/shared/fakes/group_test_user.dart` and `test/shared/fakes/fake_group_pubsub_network.dart`: test-helper seams only if existing restart/held-delivery tools cannot model the exact boundary.

Production files to inspect and touch only if the red proof requires them:

- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/features/groups/application/record_group_invite_delivery_attempts.dart`
- `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart`
- `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`

If no existing durable status table can represent admin mutation fanout repair, the narrow production extension is a group admin mutation repair/outbox model, repository, DB helper, and migration after `068_removed_group_member_snapshots`; do not add this table unless the red GE-015 proof demonstrates the need.

## Files And Repos To Inspect Next

Before editing, inspect the exact local state and restart seams:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/application/resend_group_invite_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

## Existing Tests Covering This Area

- `rotate_and_distribute_group_key_use_case_test.dart` proves live fanout order and fail-closed key promotion, including timeout behavior. It does not prove app restart recovery after local membership/config mutation.
- GE-006 through GE-009 prove offline/partition membership mutation convergence, but not admin restart during unfinished fanout.
- GE-010 and GE-011 prove honest durable message fallback for zero/partial live topic peers, not admin mutation fanout.
- GE-014 proves a restarted re-added member can recover persisted invite/key material, not that admin Alice can recover an unfinished mutation fanout.
- Group invite delivery attempt tests prove status persistence and manual resend surfaces, but not automatic resume/repair from the GE-015 crash window.

## Regression/Tests To Add First

Add the host proof first, before production changes:

`test/features/groups/integration/group_messaging_smoke_test.dart`

Suggested test names:

- `GE-015 admin restart during remove repairs key fanout honestly`
- `GE-015 admin restart during add repairs invite fanout honestly`

Minimum remove/key-rotation proof:

1. Start Alice/Bob/Charlie in a private group with shared key state.
2. Alice removes Charlie and persists the local/config mutation.
3. Hold or block Bob's key-update fanout after the mutation is locally visible and before `rotateAndDistributeGroupKey` can finish.
4. Restart Alice with persisted repositories while the fanout future is unresolved.
5. Resume/repair the pending admin mutation.
6. Verify Bob has the required key/update and can exchange post-removal messages with Alice.
7. Verify Charlie receives no post-removal plaintext.
8. Verify Alice reports honest pending/needs-resend status during the interrupted window and complete/sent only after repair actually settles.

Minimum add/invite proof:

1. Alice starts adding or re-adding Charlie and persists local member/config state.
2. Interrupt invite/key fanout before Charlie receives usable material.
3. Restart Alice.
4. Resume/repair sends or records `needsResend` honestly.
5. Verify Charlie can join only after repaired fanout and all active peers converge.
6. Verify any failed recipient remains visible as `needsResend`, not silent success.

Add criteria tests after the host proof shape is fixed. Negative criteria must reject missing restart boundary, missing pending fanout evidence, dishonest `sent`, missing repair, stranded Bob/Charlie, removed-window leakage, and divergent final membership/key epoch.

## Step-By-Step Implementation Plan

1. Reconfirm absence of current support with `rg -n "ge015|GE-015" integration_test test lib go-mknoon -S`.
2. Add the focused GE-015 host regression in `group_messaging_smoke_test.dart`. Use existing fake restart, held delivery, blocked send, and durable replay patterns before adding helpers.
3. If the red proof passes with tests/harness-only orchestration, do not change production code; proceed to criteria/runner/harness support.
4. If the proof fails because test helpers cannot model process death, add the smallest helper-only seam in `GroupTestUser` or `FakeGroupPubSubNetwork`.
5. If the proof fails because production has no durable repair/status for interrupted admin mutation fanout, add a narrow application-level pending admin mutation repair path. Prefer reusing `GroupInviteDeliveryAttempt` for add/invite statuses and adding only the missing key-rotation/admin-mutation repair persistence needed for remove.
6. Wire resume repair through `handle_app_resumed.dart` and `main.dart` only if a production repair use case is added.
7. Keep key promotion fail-closed: do not call `group:updateKey` or save Alice's new key until required recipient key fanout is delivered or durably represented for retry.
8. Ensure add/invite fanout records each recipient as `sent`, `queued`, `needsResend`, or `cannotSend` before the UI can imply completion.
9. Add `ge015` criteria support and focused valid/invalid criteria tests.
10. Add `ge015` to the multi-party runner usage, scenario routing, and orchestration.
11. Add Alice/Bob/Charlie harness role branches:
    - Alice seeds group, starts mutation, persists local config, blocks fanout, exits/restarts, resumes repair, emits final honest fanout status.
    - Bob proves remaining-member convergence and post-repair send/receive.
    - Charlie proves add/re-add join after repaired invite/key or removed-member exclusion after removal.
12. Run focused tests, criteria, analyzer, group regression commands, and required three-device relay proof.
13. Stop after code/test evidence. Do not update source matrix, breakdown ledger, closure docs, or test inventory in this session unless a later closure task explicitly asks for it.

Stop early if evidence disproves the product gap and exact GE-015 proof can close with tests/harness only.

## Acceptance Contract

The session is acceptable only if all are true:

- `ge015` exists in host test, criteria, runner, and device harness.
- The proof shows Alice/admin restarts after local config update and before required key/invite fanout completes.
- Resume/repair either completes missing fanout or leaves durable, visible, honest retry status.
- No member is stranded: Bob and Charlie can send/receive according to final entitlement, and all active peers converge on membership and key state.
- Removed peers receive no post-removal plaintext.
- Alice never reports completed/sent fanout before recipient delivery or durable retry eligibility is proven.
- Criteria tests reject dishonest or incomplete GE-015 verdicts.
- Existing GE-006 through GE-014 focused selectors and broader group smoke/membership/resume coverage remain green.
- Only code/tests/harness files needed for GE-015 are touched during implementation; docs/inventory remain unchanged for this plan-only scope.

## Risks And Edge Cases

- False proof from in-memory futures: the test must model process death, not merely delayed async work that eventually completes.
- Local config and bridge config can diverge if rollback or repair handles only one side.
- Removing a member before key rotation can leave old key access unless rotation repair is completed or failure is surfaced.
- Adding a member before invite/key fanout can leave a locally visible member who cannot join.
- Manual resend status must not be overwritten from `needsResend` to `sent` without a real send.
- Duplicate resume repair must be idempotent and must not duplicate timeline membership messages.
- Existing dirty worktree changes in target files must be preserved.

## Exact Tests And Gates To Run

Focused format, adjusted to include any new GE-015 files:

```bash
dart format --set-exit-if-changed \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/group_multi_party_device_real_harness.dart
```

Focused host proof:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015'
```

Focused application/presentation proofs if production files are touched:

```bash
flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'GE-015'
flutter test --no-pub test/features/groups/presentation/contact_picker_wired_test.dart --plain-name 'GE-015'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'GE-015'
```

Criteria proof:

```bash
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'GE-015'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

Broader host regression:

```bash
flutter test --no-pub \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/features/groups/integration/group_resume_recovery_test.dart
```

Named gate if production group send, receive, retry, resume, invite, or announcement behavior changes:

```bash
./scripts/run_test_gates.sh groups
```

Scoped analyzer and diff hygiene:

```bash
dart analyze \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/group_multi_party_device_real_harness.dart

git diff --check -- \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GE-015-plan.md
```

If a DB migration is added, also run the focused migration/full-chain tests that cover the new migration and helpers.

## Device/Relay Proof Profile

Use the current proven three-device trio unless implementation discovers a better currently booted trio:

- Alice/admin: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- Bob: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`
- Charlie: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`

Relay environment:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Required device proof command:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario ge015 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

The device verdict must record the interrupted boundary, restart signal, repair attempt/result, final fanout status, final membership, final key epoch, no stranded peer, and no removed-window leakage.

## Residual/Rollback Rules

- If repair cannot complete after bounded attempts, preserve the durable mutation/fanout record with `needsResend` or equivalent pending status. Do not silently mark it complete.
- If add/invite fanout cannot be repaired, keep affected invite delivery attempts visible as `needsResend` or `cannotSend` with `lastError`; do not erase the member row unless the mutation is explicitly rolled back by code under test.
- If remove/key-rotation fanout cannot be repaired, do not promote Alice's new key or report complete fanout. Existing active members must either remain on the last valid key or receive a repaired key rotation before closure.
- If a new migration/outbox is added and must be rolled back during implementation, remove only the GE-015 repair wiring and new table/helpers added in that implementation attempt. Do not revert unrelated group membership, invite, or key-rotation changes from prior sessions.
- Residual-only closure is allowed only for environment proof blockers, such as unavailable simulators. A started GE-015 proof with missing repair, dishonest status, stranded peer, or leaked removed-window plaintext is a product/test failure, not residual.

## Known-Failure Interpretation

- A missing `ge015` scenario before implementation is expected and confirms the gap; it is not closure evidence.
- Failures in existing GE-006 through GE-014 selectors after GE-015 edits are regressions unless independently reproduced on the pre-GE-015 worktree.
- Device proof that cannot start because a simulator is unavailable is an environment blocker, not a product pass.
- Device proof that starts but reports missing repair, dishonest status, divergent membership/key state, or removed-window plaintext is a GE-015 failure.

## Done Criteria

- The plan remains `Status: execution-ready`.
- GE-015 host proof is green and fails for the intended negative condition before the fix or criteria hardening.
- `ge015` criteria, runner, and harness support exists.
- Focused GE-015, criteria, broader host, analyzer/format/diff, and required device relay proof pass.
- The implementation leaves no silent pending admin mutation fanout and no stranded member.
- No source matrix, breakdown ledger, closure docs, or test inventory files are updated as part of this plan-only request.

## Scope Guard

Do not:

- Implement GE-017 or property/fuzz rows.
- Redesign all group membership architecture.
- Replace the existing invite/status UI.
- Add broad background job infrastructure unrelated to admin group mutation fanout.
- Treat GE-014 member restart proof as GE-015 admin restart proof.
- Mark any docs or inventory row covered before green GE-015 implementation evidence exists.

Overengineering includes a generic workflow engine, multi-relay redesign, or broad migration of unrelated group send/retry paths. The only acceptable new persistence is the minimum needed to make interrupted admin mutation fanout repairable and honest.

## Accepted Differences / Intentionally Out Of Scope

- GE-015 is admin-side restart during mutation; GE-014 is recipient-side restart after persisted invite/key. The two can share harness patterns but have different proof boundaries.
- Device/relay proof is required for closure, but the named Group Messaging Gate remains host-side.
- Go `go-mknoon/node/pubsub.go` and `go-mknoon/node/group_inbox.go` are inspect-only unless the device proof shows native relay/pubsub state is the actual source of stranding.

## Dependency Impact

GE-015 closure becomes prerequisite evidence for later random mutation, key-rotation property, and soak rows. If GE-015 requires a durable admin mutation repair repository or migration, later rows should reuse that repair/status contract instead of adding separate mutation recovery mechanisms. If GE-015 closes as tests/harness-only, later rows must not assume any new production repair behavior was added.

## Reviewer Findings

The plan is sufficient with the adjustments included here. The required missing pieces are explicit: exact host regression, criteria support, runner scenario, harness branch, validation commands, device proof profile, and rollback/residual behavior. The main stale assumption to avoid is treating existing GE-014 or live key-rotation fail-close tests as restart proof. The decomposition is narrow enough because production changes are gated by a red GE-015 proof and stop if tests/harness evidence is sufficient.

## Arbiter Decision

- Structural blockers: none remaining.
- Incremental details deferred: exact names of any new production model/repository files, because they should be chosen only if the red GE-015 proof proves existing invite/status persistence is insufficient.
- Accepted differences: GE-015 may close tests/harness-only if exact proof passes without production changes; otherwise it may require a narrow durable admin mutation repair path. Both outcomes are valid if the acceptance contract and validation commands pass.
