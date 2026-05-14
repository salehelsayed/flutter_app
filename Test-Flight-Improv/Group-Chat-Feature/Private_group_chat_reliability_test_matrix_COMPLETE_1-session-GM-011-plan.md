# GM-011 Plan - Remove Then Stale Add Arrives Out Of Order

Status: closed/accepted

## Planning Progress

- 2026-05-10 22:29 CEST - Evidence Collector starting. Files inspected since last update: `git status --short`, `implementation-plan-orchestrator/SKILL.md`, target plan path existence. Decision/blocker: target plan file was missing; create this doc-scoped work surface and preserve all other dirty files. Next action: inspect GM-011 source row, session breakdown, direct group membership listener tests, criteria runner, harness, and gate definitions.
- 2026-05-10 22:39 CEST - Evidence Collector completed; Planner starting. Files inspected since last update: source matrix row GM-011, session breakdown row GM-011, `group_message_listener.dart`, `group_membership_event_watermark.dart`, `group_message_listener_test.dart`, `group_membership_smoke_test.dart`, group multi-party runner/criteria/harness files, `Test-Flight-Improv/test-gate-definitions.md`, `flutter devices --machine`, and `xcrun simctl list devices available`. Decision/blocker: no blocker; GM-011 needs row-owned proof support and possibly a narrow stale-add/old-key fix if tests expose one. Next action: draft the execution-ready GM-011 plan.
- 2026-05-10 22:47 CEST - Planner completed; Reviewer starting. Files inspected since last update: `test/shared/fakes/group_test_user.dart` and existing stale replay helpers in `group_membership_smoke_test.dart`. Decision/blocker: draft plan is implementation-ready if the executor keeps proof-first order and treats simulator/Xcode failure as fixable environment state. Next action: review for missing gates, stale assumptions, scope drift, and closure bar sufficiency.
- 2026-05-10 22:51 CEST - Reviewer completed; Arbiter starting. Files inspected since last update: draft plan content. Decision/blocker: sufficient with one incremental adjustment to list simulator discovery and doc hygiene commands explicitly; no structural blocker. Next action: classify reviewer findings and finalize execution-ready status.
- 2026-05-10 22:54 CEST - Arbiter completed. Files inspected since last update: reviewer pass and final plan sections. Decision/blocker: no structural blockers remain; incremental simulator discovery/doc hygiene adjustment is applied; accepted differences are documented. Next action: run doc hygiene and report final verdict.

## real scope

Own exactly GM-011: remove C after an older add event exists, then deliver the older add after the newer removal, then prove sends still obey the final removed membership.

Allowed changes:

- Add row-owned GM-011 host regressions and exact criteria coverage.
- Add `--scenario gm011` runner, criteria, and three-role iOS simulator harness support.
- Make the smallest product fix only if proof-first tests show the current timestamp watermark guards or config/key handling can resurrect Charlie, include Charlie in a stale config, accept Charlie's old key, or break A/B delivery.

Do not edit the source matrix or session breakdown during execution. Do not reopen GM-001 through GM-010. Preserve all existing dirty/user/other-agent edits and avoid unrelated formatting churn.

## closure bar

GM-011 can close only when all of these are true:

- A held `member_added` event at version 2, represented by an older membership event timestamp, is delivered after a `member_removed` event at version 3.
- Alice and Bob finish with member lists excluding Charlie, no validator/config state includes Charlie, and their latest usable key remains the post-removal epoch.
- Charlie is not resurrected by the stale add: no group access, no current member row that permits send, no rotated key, no old-key acceptance, no post-removal plaintext, and no successful post-removal publish.
- Alice-to-Bob and Bob-to-Alice delivery remains exact and reliable after the stale add is processed.
- Criteria tests reject stale-add resurrection, old-key acceptance, Charlie post-removal plaintext, Charlie successful publish, stale durable recipients, and missing A/B delivery.
- Exact simulator verdict records `scenario: gm011`, `ok: true`, and valid Alice/Bob/Charlie role verdicts on iOS simulators only.
- `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check` pass.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named gates; if they disagree, the script wins.
- Source matrix row GM-011 defines the row behavior: older add version 2 delivered after newer remove version 3; final membership remains removed; stale add must not resurrect C or old keys.
- The session breakdown row GM-011 identifies this as `implementation-ready` work with row-owned tests and possible code changes.
- This plan was the active GM-011 execution contract once it reached `Status: execution-ready`; the closure audit below is the current final state.

## session classification

implementation-ready

Reason: the repo already has likely seams for stale membership ordering, host fake-network delivery, criteria validation, and simulator orchestration. The missing work is row-owned proof and a narrow fix only if that proof fails.

## exact problem statement

GM-011 is open because the repo has no row-specific proof that a stale add cannot undo a newer removal in the complete private group flow. The user-visible risk is that Charlie could regain membership, old key access, durable-recipient eligibility, or publish ability after Alice removed Charlie and rotated membership/key state, which could also disrupt A/B delivery.

What must improve: add a regression and simulator proof where an older add event is intentionally delivered out of order after a newer remove. What must stay unchanged: covered GM-001 through GM-010 behavior, normal add/remove/idempotency flows, group invite/onboarding behavior, and existing named gate composition unless completeness classification requires a local doc update during later execution.

## files and repos to inspect next

Production and helper seams:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_membership_event_watermark.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `test/shared/fakes/group_test_user.dart`

Tests, runner, and criteria:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Repo-local Go files are inspect-only unless the Flutter/device proof shows validator or inbox behavior cannot be proven at the app seam:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

## existing tests covering this area

- `test/features/groups/application/group_message_listener_test.dart` already includes `older member_added cannot revive state after a newer removal across restart`. It proves the listener timestamp watermark can ignore a stale `member_added`, but it does not own GM-011 criteria, old-key rejection, durable-recipient proof, or A/B simulator delivery.
- The same file includes `older member_removed cannot roll back a newer added admin state after restart`, which pins the opposite stale-remove direction for GM-012-like risk but does not close GM-011.
- `test/features/groups/integration/group_membership_smoke_test.dart` carries GM-004 through GM-010 host membership/key/remove/re-add coverage and fake-network replay helpers. GM-009 and GM-010 are useful context only and stay closed.
- `integration_test/scripts/group_multi_party_device_criteria.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, and `integration_test/group_multi_party_device_real_harness.dart` currently support scenarios through `gm010`; GM-011 support is missing.
- `Test-Flight-Improv/test-gate-definitions.md` defines the Group Messaging Gate and requires completeness classification for new integration/cross-feature/orchestration tests.

## regression/tests to add first

Add failing/row-specific proof before any product fix:

1. Add a focused GM-011 listener regression in `group_message_listener_test.dart`.
   - Arrange a group with Alice/Bob/Charlie and an initial key/window.
   - Create the stale add payload at version 2 timestamp, including a group config that contains Charlie.
   - Apply a newer removal at version 3 timestamp and persist the membership watermark.
   - Deliver the version 2 stale add after restart or after queue drain.
   - Assert Charlie is still absent, no stale config sync re-adds Charlie, and the watermark remains at version 3.

2. Add a GM-011 host integration test in `group_membership_smoke_test.dart`.
   - Hold a stale add envelope before removal, remove Charlie, rotate/distribute only to Alice/Bob, deliver the stale add after removal to the app-layer listener path, then send from Alice and Bob.
   - Assert Alice/Bob exclude Charlie, use the post-removal epoch, and receive each other's post-stale-add messages exactly once.
   - Assert Charlie has no current group/key access, cannot publish, cannot decrypt/read Alice/Bob post-removal plaintext, and is not in durable recipients.

3. Add criteria positive and negative tests in `group_multi_party_device_criteria_test.dart`.
   - Positive fixture accepts only a complete `gm011StaleAddRemovalProof`.
   - Negative fixtures must fail stale-add resurrection, old-key acceptance, successful Charlie publish, Charlie plaintext leak, stale durable recipient inclusion, missing A/B delivery, missing proof fields, duplicate/mismatched role verdicts, and non-`gm011` scenario names.

Stop before product edits if these tests already pass with only test/harness support. If a direct product failure appears, fix only the failing stale-add/old-key seam.

## step-by-step implementation plan

1. Snapshot dirty state with `git status --short`; do not revert or normalize unrelated edits.
2. Add the focused GM-011 listener regression. Run it by plain name and confirm the exact failure or pass.
3. Add the host GM-011 fake-network integration proof. Reuse existing GM-009/GM-010 setup patterns and existing stale-envelope helpers where possible. Extend `GroupTestUser` only if needed to inject a controlled `member_added` timestamp or stale group config cleanly.
4. If host proof fails because a stale add is applied, patch the narrow app-layer seam:
   - Prefer preserving the existing `lastMembershipEventAt` timestamp watermark model.
   - Prevent stale `member_added` or its `groupConfig` snapshot from saving Charlie, syncing a config that contains Charlie, restoring a deleted self group, or making old keys usable.
   - Keep duplicate add/re-add idempotency behavior from GM-010 unchanged.
5. If host proof fails because old key material or durable recipients remain eligible, patch only the narrow key/recipient eligibility seam needed for removed Charlie after stale add.
6. Add `gm011` to `group_multi_party_device_criteria.dart` requirements, scenario dispatch, expected messages, and scenario-specific proof validation.
7. Add GM-011 positive and negative criteria tests in `group_multi_party_device_criteria_test.dart`.
8. Add `--scenario gm011` support in `run_group_multi_party_device_real.dart` and `group_multi_party_device_real_harness.dart`.
   - Roles: Alice, Bob, Charlie.
   - Alice creates the group and the held version 2 stale add, then removes Charlie at version 3 and rotates/distributes only to Alice/Bob.
   - The harness forces the stale add through the same app-layer delivery path used by real replay/proof, then sends Alice/Bob proof messages and records Charlie rejection/no-leak evidence.
9. Run the focused host and criteria tests. Fix only GM-011 failures.
10. Run the exact simulator proof using only iOS simulators:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm011 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Current local discovery found these exact booted simulator mappings:

- Alice: `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (`iPhone 17 Pro`)
- Bob: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`)
- Charlie: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`)

11. If simulator/Xcode state fails, do not leave GM-011 blocked. Fix simulator/build state, then rerun the exact command. Acceptable cleanup includes clearing relevant Runner/Pods DerivedData, removing `build/ios`, uninstalling app and extension bundles from the exact simulators, rebooting the exact simulators, and rerunning discovery plus the exact proof command.
12. Run named gates and diff hygiene. Do not edit the source matrix or breakdown closure rows in this GM-011 execution session.

## risks and edge cases

- Timestamp-as-version ambiguity: the row says version 2/version 3, while current app code uses event timestamps and `lastMembershipEventAt`. The implementation should encode version order as deterministic timestamps unless code evidence proves a real membership version field exists.
- Charlie self-removal cleanup: a stale add delivered after `leaveGroup` must not recreate a usable local group, orphan member access, old key use, or topic subscription.
- Config snapshot ordering: stale `groupConfig` containing Charlie must not overwrite the newer remove snapshot on Alice/Bob.
- Durable recipients: post-removal Alice/Bob sends must not include Charlie because the stale add was processed late.
- Key epoch drift: Alice/Bob must remain on the post-removal epoch; Charlie must not regain old epoch access.
- Simulator reliability: device discovery, DerivedData, stale app containers, or build cache issues are environment state to fix, not a reason to close without E2E proof.

## exact tests and gates to run

Focused proof:

```bash
git status --short
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-011'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011 remove then stale add arrives out of order'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-011
```

Direct regression suites:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
```

If `add_group_member_use_case.dart` or `remove_group_member_use_case.dart` changes, also run:

```bash
flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
```

Targeted analyzer:

```bash
dart analyze \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/application/group_membership_event_watermark.dart \
  lib/features/groups/application/add_group_member_use_case.dart \
  lib/features/groups/application/remove_group_member_use_case.dart \
  integration_test/group_multi_party_device_real_harness.dart \
  integration_test/scripts/run_group_multi_party_device_real.dart \
  integration_test/scripts/group_multi_party_device_criteria.dart \
  test/integration/group_multi_party_device_criteria_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/shared/fakes/group_test_user.dart
```

Exact simulator proof:

```bash
flutter devices --machine
xcrun simctl list devices available
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
  dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario gm011 \
  -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md
git diff --check
```

## known-failure interpretation

- A new focused GM-011 test failing before a product fix is expected evidence; it is not a regression until implementation claims closure.
- Existing dirty changes in unrelated files are not failures to fix or revert unless they directly break GM-011 proof.
- Failures in GM-001 through GM-010 focused proof are regressions only if caused by GM-011 changes; those rows remain covered and should not be reopened for unrelated cleanup.
- Simulator/Xcode/build-state failures must be cleaned up and rerun on the exact iOS simulators. They cannot be accepted as "blocked" closure evidence.
- A device proof using a physical phone, Android target, or only host tests is insufficient for this row.

## done criteria

- `group_message_listener_test.dart` has a GM-011 stale-add-after-remove regression proving the version 2 add cannot roll back version 3 removal.
- `group_membership_smoke_test.dart` has a row-owned GM-011 integration proof for final removed membership, no old key resurrection, Charlie send/decrypt rejection, and A/B delivery.
- Criteria validation has GM-011 positive and negative tests for stale-add resurrection, old-key acceptance, Charlie leak/publish, stale durable recipients, and missing delivery.
- Runner/harness supports `--scenario gm011`.
- Exact three-iOS-simulator proof produces an orchestrator verdict with `scenario: gm011` and `ok: true` on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Required direct tests, `groups`, `completeness-check`, and `git diff --check` pass.
- The executor records evidence paths and exact command output in the implementation closure notes without editing this session's source matrix or breakdown closure state.

## scope guard

Non-goals:

- Do not implement GM-012 or later stale/race rows.
- Do not modify GM-001 through GM-010 closure text or reroute their already accepted behavior.
- Do not introduce a new membership-version architecture unless deterministic tests prove timestamps cannot express the row.
- Do not broaden into unrelated group UI, invite status, announcement, relay failover, push, or TestFlight telemetry work.
- Do not change `--scenario all` semantics as part of GM-011 unless a test already requires it for direct GM-011 proof.
- Do not use real external devices. The row's E2E proof is simulator-only.

Overengineering signals:

- Rewriting membership storage or key distribution instead of fixing the stale-add application seam.
- Promoting the multi-party runner into a named gate.
- Editing source matrix/breakdown closure rows during execution.
- Adding broad Go relay changes without a Flutter/device proof failure that requires them.

## accepted differences / intentionally out of scope

- The app currently uses timestamp watermarks as the app-layer ordering mechanism. GM-011 can model "version 2" and "version 3" as deterministic older/newer event timestamps unless evidence proves a separate version field is required.
- `--scenario all` currently expands only to early scenarios. Direct `--scenario gm011` proof is sufficient for this row.
- Real external device proof is intentionally out of scope and would not satisfy the user constraint.
- GM-012's add-then-stale-remove inverse remains a separate open row.

## dependency impact

- GM-012 and later stale/race rows can reuse the GM-011 criteria and harness pattern, but they must stay separate sessions.
- If GM-011 changes the stale-event model, later membership ordering rows must inspect the new contract before planning.
- If GM-011 cannot be proven without a broader membership-version architecture, stop and reopen planning before implementation expands scope.

## rollback and reopen conditions

Rollback or reopen GM-011 if:

- Any accepted proof later shows Charlie can be restored by stale add, send after removal, decrypt post-removal messages, or receive durable inbox copies.
- Alice/Bob delivery fails only after the stale add is injected.
- Criteria accept an incomplete or unsafe GM-011 verdict.
- Exact simulator proof cannot be made to run after simulator/build-state cleanup.
- A product fix breaks GM-009 duplicate removal or GM-010 duplicate re-add behavior.

## reviewer pass

Verdict: sufficient with adjustments.

Reviewer answers:

- Missing files, tests, regressions, or gates: no structural omissions after adding explicit simulator discovery and doc-scoped `git diff --check` hygiene. The candidate file list is broad enough for GM-011 without forcing Go changes.
- Stale or incorrect assumptions: the plan correctly treats version 2/version 3 as timestamp-ordered events because current code uses `lastMembershipEventAt`; it also requires reopening planning if a real version field becomes necessary.
- Overengineering: none required. The plan tells the executor to stop if tests pass with proof-only changes and to avoid new membership architecture.
- Decomposition sufficiency: adequate. The order is proof-first host, criteria, runner/harness, exact simulator proof, named gates.
- Minimum needed: keep the closure bar strict, preserve prior rows, and require the exact simulator verdict before closure.

## arbiter decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact implementation naming for GM-011 helper functions and proof-field keys can be chosen during execution, as long as criteria require stale-add rejection, old-key rejection, Charlie no-leak/no-send evidence, and A/B delivery.
- `--scenario all` expansion remains unchanged unless later execution finds a direct GM-011 need.

Accepted differences intentionally left unchanged:

- Timestamp watermarks remain the planned ordering mechanism for version 2/version 3 unless proof shows they cannot express the row.
- Go relay/pubsub files remain inspect-only unless Flutter/device proof exposes a validator or inbox failure that cannot be closed at the app layer.
- Source matrix and breakdown closure edits are out of scope for GM-011 execution.

## Execution Progress

- 2026-05-10 22:36 CEST - Controller contract extracted. Files inspected/touched: `implementation-execution-qa-orchestrator/SKILL.md`, this GM-011 plan, `git status --short`, `codex exec --help`. Decision/blocker: no blocker; plan has explicit scope, acceptance bar, owner files, direct tests, simulator proof, named gates, and scope guard. Spawn path available via `codex exec` with `model: gpt-5.5` and `reasoning_effort: xhigh`. Next action: spawn isolated Executor for GM-011 only.
- 2026-05-10 22:37 CEST - Executor spawn attempted. Files inspected/touched: this plan only. Command: `codex exec ... -a never ...`. Decision/blocker: child did not materialize because `-a` is a top-level Codex CLI flag, so no Executor work or repo state was produced. Next action: relaunch isolated Executor with corrected top-level approval flag syntax.
- 2026-05-10 22:38 CEST - Executor started and contract extracted. Files inspected/touched: this GM-011 plan, `implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`, owner-file diffs, owner-file GM/stale membership search. Decision/blocker: no blocker; execute GM-011 only, preserve existing dirty GM-008/GM-010 edits, do not edit source matrix or session breakdown closure rows, and require focused host tests, direct suites, targeted analyzer, exact iOS simulator proof, named gates, and diff hygiene. Next action: inspect owner files in detail and add row-owned GM-011 proof-first tests/harness support.
- 2026-05-10 22:41 CEST - Owner-file inspection completed; proof-first edits starting. Files inspected/touched: `group_message_listener.dart`, `group_membership_event_watermark.dart`, `add_group_member_use_case.dart`, `remove_group_member_use_case.dart`, `group_message_listener_test.dart`, `group_membership_smoke_test.dart`, `group_test_user.dart`, criteria, runner, and harness files. Decision/blocker: no product blocker found yet; existing listener watermark should be proven by GM-011-specific regressions before any source fix. Next action: add GM-011 listener, host integration, criteria, runner, and harness support.
- 2026-05-10 22:49 CEST - GM-011 proof edits completed and formatted. Files inspected/touched: `group_message_listener_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, `run_group_multi_party_device_real.dart`, `group_multi_party_device_real_harness.dart`, this plan. Decision/blocker: no product fix applied yet; tests will decide whether the existing watermark path is sufficient. Next action: run focused GM-011 listener test.
- 2026-05-10 22:49 CEST - Focused listener test started. Files inspected/touched: `group_message_listener_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-011'`. Decision/blocker: running proof-first listener regression. Next action: record result and triage any failure.
- 2026-05-10 22:50 CEST - Focused listener test passed. Files inspected/touched: `group_message_listener_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-011'`. Decision/blocker: no listener product gap exposed. Next action: run focused GM-011 host integration proof.
- 2026-05-10 22:50 CEST - Focused host integration test started. Files inspected/touched: `group_membership_smoke_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011 remove then stale add arrives out of order'`. Decision/blocker: running row-owned host proof. Next action: record result and triage any failure.
- 2026-05-10 22:50 CEST - Focused host integration test passed. Files inspected/touched: `group_membership_smoke_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011 remove then stale add arrives out of order'`. Decision/blocker: no host product gap exposed; GM-011 proof-only product path still holds. Next action: run focused GM-011 criteria tests.
- 2026-05-10 22:50 CEST - Focused criteria tests started. Files inspected/touched: `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, this plan. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-011`. Decision/blocker: running GM-011 positive/negative verdict checks. Next action: record result and triage any failure.
- 2026-05-10 22:51 CEST - Focused criteria tests passed. Files inspected/touched: `group_multi_party_device_criteria.dart`, `group_multi_party_device_criteria_test.dart`, this plan. Command finished: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-011`. Decision/blocker: GM-011 criteria positive and negative coverage passes. Next action: run direct regression suites.
- 2026-05-10 22:51 CEST - Direct regression suite started. Files inspected/touched: `group_message_listener_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: running full listener regression after GM-011 addition. Next action: record result and triage any failure.
- 2026-05-10 22:52 CEST - Direct regression suite passed. Files inspected/touched: `group_message_listener_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: listener regression green. Next action: run full group membership smoke regression.
- 2026-05-10 22:52 CEST - Direct regression suite started. Files inspected/touched: `group_membership_smoke_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`. Decision/blocker: running full host membership smoke regression. Next action: record result and triage any failure.
- 2026-05-10 22:52 CEST - Direct regression suite passed. Files inspected/touched: `group_membership_smoke_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart`. Decision/blocker: host membership smoke regression green. Next action: run member removal integration regression.
- 2026-05-10 22:52 CEST - Direct regression suite started. Files inspected/touched: `member_removal_integration_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`. Decision/blocker: running removal regression. Next action: record result and triage any failure.
- 2026-05-10 22:52 CEST - Direct regression suite passed. Files inspected/touched: `member_removal_integration_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart`. Decision/blocker: removal regression green. Next action: run new member onboarding regression.
- 2026-05-10 22:52 CEST - Direct regression suite started. Files inspected/touched: `group_new_member_onboarding_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: running onboarding regression. Next action: record result and triage any failure.
- 2026-05-10 22:53 CEST - Direct regression suite passed. Files inspected/touched: `group_new_member_onboarding_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: onboarding regression green. Next action: run full criteria regression.
- 2026-05-10 22:53 CEST - Direct regression suite started. Files inspected/touched: `group_multi_party_device_criteria_test.dart`, this plan. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: running full criteria regression. Next action: record result and triage any failure.
- 2026-05-10 22:53 CEST - Direct regression suite passed. Files inspected/touched: `group_multi_party_device_criteria_test.dart`, this plan. Command finished: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: full criteria regression green. Next action: run conditional add/remove use-case regression for dirty owner use-case files.
- 2026-05-10 22:53 CEST - Conditional use-case regression started. Files inspected/touched: `add_group_member_use_case.dart`, `add_group_member_use_case_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`. Decision/blocker: running because add/remove use-case files are dirty in the worktree; removal regression already passed. Next action: record result and triage any failure.
- 2026-05-10 22:54 CEST - Conditional use-case regression passed. Files inspected/touched: `add_group_member_use_case.dart`, `add_group_member_use_case_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart`. Decision/blocker: add-member regression green; no product fix needed for GM-011. Next action: run targeted analyzer.
- 2026-05-10 22:54 CEST - Targeted analyzer started. Files inspected/touched: app owner files, GM-011 harness/criteria/tests, `group_test_user.dart`, this plan. Command: `dart analyze lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_membership_event_watermark.dart lib/features/groups/application/add_group_member_use_case.dart lib/features/groups/application/remove_group_member_use_case.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/shared/fakes/group_test_user.dart`. Decision/blocker: running compile-shape/analyzer check. Next action: record result and triage any failure.
- 2026-05-10 22:56 CEST - Targeted analyzer failed and was triaged. Files inspected/touched: `group_message_listener.dart`, `group_test_user.dart`, this plan. Command result: analyzer found existing warning-level nullability hygiene in owner/helper files, not GM-011 behavior failures. Decision/blocker: required analyzer evidence must pass, so applied narrow mechanical nullability cleanup and removed one unused private metadata watermark helper. Next action: rerun the exact targeted analyzer command.
- 2026-05-10 22:56 CEST - Targeted analyzer rerun started. Files inspected/touched: app owner files, GM-011 harness/criteria/tests, `group_test_user.dart`, this plan. Command: exact targeted analyzer command from plan. Decision/blocker: verifying mechanical analyzer cleanup. Next action: record result and triage any remaining failure.
- 2026-05-10 22:58 CEST - Targeted analyzer rerun failed and was triaged. Files inspected/touched: `group_message_listener.dart`, this plan. Command result: two `_autoDownloadMedia` argument type errors after removing stale null assertions. Decision/blocker: mechanical cleanup needed non-null local captures; applied local capture guard only. Next action: format listener and rerun the exact targeted analyzer command.
- 2026-05-10 22:58 CEST - Targeted analyzer rerun started. Files inspected/touched: app owner files, GM-011 harness/criteria/tests, `group_test_user.dart`, this plan. Command: exact targeted analyzer command from plan. Decision/blocker: verifying final listener nullability cleanup. Next action: record result and triage any remaining failure.
- 2026-05-10 22:59 CEST - Targeted analyzer passed. Files inspected/touched: app owner files, GM-011 harness/criteria/tests, `group_test_user.dart`, this plan. Command finished: exact targeted analyzer command from plan. Decision/blocker: analyzer clean after mechanical nullability cleanup. Next action: rerun affected listener regression because listener source changed after earlier proof.
- 2026-05-10 22:59 CEST - Direct regression rerun started. Files inspected/touched: `group_message_listener.dart`, `group_message_listener_test.dart`, this plan. Command: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: verifying final listener source state. Next action: record result and triage any failure.
- 2026-05-10 22:59 CEST - Direct regression rerun passed. Files inspected/touched: `group_message_listener.dart`, `group_message_listener_test.dart`, this plan. Command finished: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: final listener source state is covered. Next action: run simulator discovery with allowed iOS IDs.
- 2026-05-10 22:59 CEST - Simulator discovery started. Files inspected/touched: this plan only. Commands: `flutter devices --machine`; `xcrun simctl list devices available`. Decision/blocker: verifying allowed simulator IDs before exact GM-011 proof. Next action: record result and fix simulator/Xcode state if needed.
- 2026-05-10 23:00 CEST - Simulator discovery passed. Files inspected/touched: this plan only. Commands finished: `flutter devices --machine`; `xcrun simctl list devices available`. Decision/blocker: allowed Alice/Bob/Charlie simulator IDs are present, supported, and booted; real devices ignored per scope. Next action: run exact GM-011 simulator proof with required relay addresses.
- 2026-05-10 23:00 CEST - Exact GM-011 simulator proof started. Files inspected/touched: `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, criteria files, this plan. Command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm011 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Decision/blocker: running exact required proof only on allowed iOS simulators. Next action: record result and fix environment/build state if needed.
- 2026-05-10 23:04 CEST - Exact GM-011 simulator proof passed. Files inspected/touched: `group_multi_party_device_real_harness.dart`, `run_group_multi_party_device_real.dart`, criteria files, this plan. Command finished: exact GM-011 simulator proof with required relay addresses and allowed Alice/Bob/Charlie simulator IDs. Verdict path: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm011_9PPfPc`; alice/bob/charlie verdict JSONs accepted. Decision/blocker: no simulator, Xcode, relay, or GM-011 proof blocker. Next action: run named groups gate.
- 2026-05-10 23:04 CEST - Named gate started. Files inspected/touched: group test gate surface, this plan. Command: `./scripts/run_test_gates.sh groups`. Decision/blocker: running required groups gate after simulator proof. Next action: record result and triage any failure.
- 2026-05-10 23:05 CEST - Named gate passed. Files inspected/touched: group test gate surface, this plan. Command finished: `./scripts/run_test_gates.sh groups`. Decision/blocker: groups gate green, including GM-011 smoke coverage. Next action: run completeness-check gate.
- 2026-05-10 23:05 CEST - Named gate started. Files inspected/touched: completeness test gate surface, this plan. Command: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: running required completeness gate. Next action: record result and triage any failure.
- 2026-05-10 23:05 CEST - Named gate passed. Files inspected/touched: completeness test gate surface, this plan. Command finished: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: completeness check green. Next action: run doc-scoped diff hygiene.
- 2026-05-10 23:05 CEST - Diff hygiene started. Files inspected/touched: this plan. Command: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`. Decision/blocker: checking plan progress edits for whitespace errors. Next action: record result and run full diff hygiene.
- 2026-05-10 23:06 CEST - Diff hygiene passed. Files inspected/touched: this plan. Command finished: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`. Decision/blocker: plan progress edits have no whitespace errors. Next action: run full diff hygiene.
- 2026-05-10 23:06 CEST - Diff hygiene started. Files inspected/touched: full dirty worktree diff. Command: `git diff --check`. Decision/blocker: checking all dirty tracked diffs, including pre-existing dirty files, for whitespace errors. Next action: record result and inspect final diff/status.
- 2026-05-10 23:07 CEST - Diff hygiene passed and generated workspace noise removed. Files inspected/touched: full dirty worktree diff, `info.plist`, this plan. Command finished: `git diff --check`; result clean. Decision/blocker: exact simulator run had updated only `info.plist` `LastAccessedDate`, so restored that generated timestamp to keep GM-011 scope narrow. Next action: rerun doc-scoped and full diff hygiene after final progress edits.
- 2026-05-10 23:07 CEST - Final diff hygiene started. Files inspected/touched: this plan, full dirty worktree diff. Commands: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`; `git diff --check`. Decision/blocker: final verification after all progress entries. Next action: record result and prepare Executor handoff.
- 2026-05-10 23:07 CEST - Final diff hygiene passed. Files inspected/touched: this plan, full dirty worktree diff. Commands finished: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`; `git diff --check`. Decision/blocker: no whitespace errors. Next action: final status/diff inspection and Executor handoff.
- 2026-05-10 23:07 CEST - Executor completed GM-011. Files inspected/touched: GM-011 plan, listener test, host smoke test, criteria, criteria tests, runner, real-device harness, analyzer cleanup files. Decision/blocker: GM-011 proof, direct suites, simulator proof, named gates, analyzer, and hygiene all passed; no product behavior fix was needed beyond mechanical analyzer cleanup in owner files. Next action: hand off to controller/QA Reviewer.
- 2026-05-10 23:08 CEST - QA Reviewer started. Files inspected/touched: this GM-011 plan, `/tmp/gm011-executor-final.md`, `git status --short`, GM-011 diffs, simulator verdict artifacts. Decision/blocker: review-only pass launched in a separate `codex exec` child with `model: gpt-5.5` and `reasoning_effort: xhigh`; no blocker yet. Next action: verify scope, evidence, focused tests, analyzer, diff hygiene, and simulator artifact.
- 2026-05-10 23:13 CEST - QA Reviewer accepted GM-011. Files inspected/touched: this GM-011 plan, executor handoff, listener/host/criteria/runner/harness/test files, source matrix and session breakdown for scope separation, simulator verdict JSONs. Commands rerun: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-011'`; `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-011 remove then stale add arrives out of order'`; `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-011`; exact targeted `dart analyze`; plan-scoped `git diff --check`; full `git diff --check`. Decision/blocker: QA verdict accepted with no blocking findings; simulator artifact `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm011_9PPfPc/gmp_1778446826367_gm011_orchestrator_verdict.json` records `scenario: gm011`, `ok: true`, and required Alice/Bob/Charlie simulator IDs. Next action: controller final diff hygiene and final report.
- 2026-05-10 23:13 CEST - Controller final verification passed. Files inspected/touched: this GM-011 plan and full dirty worktree diff. Commands finished: `git diff --check -- Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`; `git diff --check`; `git status --short`. Decision/blocker: no blockers; final report can mark GM-011 execution+QA accepted while preserving unrelated dirty files and leaving source matrix/session breakdown closure rows untouched. Next action: final response.

## Closure Audit Verdict

Closure verdict: `closed` / `accepted`.

What is now closed:
- GM-011 row contract: an older `member_added` stale add delivered after a newer `member_removed` is ignored, final membership remains removed, and Charlie is not resurrected through config, key, durable recipient, publish, decrypt, or plaintext access.
- Existing timestamp watermark handling in `lib/features/groups/application/group_message_listener.dart` is accepted as sufficient for stale add-after-remove. No GM-011 product behavior fix was required beyond mechanical analyzer cleanup in owner/helper files.
- Proof surfaces: focused GM-011 listener regression, focused GM-011 host integration, GM-011 criteria positive/negative checks, direct `--scenario gm011` runner support, and Alice/Bob/Charlie simulator harness evidence.

Accepted final evidence:
- Final exact simulator-only proof passed with `--scenario gm011` on iOS simulators Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Final orchestrator verdict: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm011_9PPfPc/gmp_1778446826367_gm011_orchestrator_verdict.json`, with `scenario: gm011`, `ok: true`, and detail `gm011 verdicts valid for alice, bob, charlie`.
- Role verdict facts: Alice and Bob applied remove version 3, delivered stale add version 2, ignored the stale add, excluded Charlie from member/config state, held final epoch `2`, and exchanged post-stale-add messages reliably. Charlie received the stale add delivery attempt but had no current group/member state, no old or rotated key access, no post-removal plaintext, no successful post-removal publish, and no Alice/Bob post-removal messages.
- Criteria reject stale-add resurrection, old-key acceptance, Charlie leak/publish, stale durable recipients, and missing Alice/Bob delivery.

Maintenance gates:
- Focused GM-011 listener regression.
- Focused GM-011 host integration.
- Focused GM-011 criteria.
- Full `group_message_listener_test.dart`.
- Full `group_membership_smoke_test.dart`.
- `member_removal_integration_test.dart`.
- `group_new_member_onboarding_test.dart`.
- Full `group_multi_party_device_criteria_test.dart`.
- Conditional dirty-owner `add_group_member_use_case_test.dart`.
- Targeted analyzer.
- Exact three-iOS-simulator `gm011`.
- `./scripts/run_test_gates.sh groups`.
- `./scripts/run_test_gates.sh completeness-check`.
- `git diff --check`.

Residual-only items:
- None for GM-011. Reopen only on a real regression against stale-add rejection after newer removal, Charlie exclusion/non-access, durable-recipient exclusion, old-key rejection, or Alice/Bob post-removal delivery.

Still-open items:
- GM-012 and later source rows remain open. GM-011 does not close stale-remove-after-add, simultaneous remove/send, simultaneous re-add/send, durable-recipient-window, fresh-key-package, or later membership/race rows.

Accepted differences:
- Timestamp watermark ordering is accepted as the implementation model for this row; no new membership-version architecture was required.
- Proof is simulator-only on the recorded iOS simulators. No real external devices are required or claimed.
- Mechanical analyzer cleanup in owner/helper files is accepted as non-behavioral GM-011 execution cleanup.

Checkpoint policy:
- `checkpoint_skipped`; a clean scoped checkpoint/commit is unsafe because the source matrix, breakdown, and GM-011 plan are overlapping aggregate rollout artifacts, while the worktree also contains unrelated or overlapping product/test edits from other work. Leave unrelated and aggregate rollout paths unstaged.

Structural blockers remaining: none.

Exact docs/files used as evidence:
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-011-plan.md`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/group_test_user.dart`
