# Private Group Chat Reliability Matrix GM-003 Plan

Status: execution-ready

## Planning Progress

- 2026-05-10 12:32:06 CEST - Role: Planner completed. Files inspected since last update: none. Decision/blocker: draft plan complete; no structural blocker known. Next action: run Reviewer against scope, closure bar, regression-first rule, and gate contract.
- 2026-05-10 12:33:45 CEST - Role: Reviewer started. Files inspected since last update: draft plan content in this file. Decision/blocker: controller wait signal refreshed; no blocker. Next action: review mandatory sections, test/gate contract, stale assumptions, and over-scope risk before arbiter.
- 2026-05-10 12:34:23 CEST - Role: Reviewer completed. Files inspected since last update: draft mandatory sections, exact tests/gates, closure instructions, accepted differences, and scope guard. Decision/blocker: sufficient with adjustments; no structural blocker. Next action: Arbiter to classify minor refinements and decide whether to patch before execution-ready.
- 2026-05-10 12:34:58 CEST - Role: Arbiter started. Files inspected since last update: reviewer findings and draft plan. Decision/blocker: no structural blocker identified so far. Next action: classify findings into structural blockers, incremental details, and accepted differences, then finalize.
- 2026-05-10 12:35:24 CEST - Role: Arbiter completed. Files inspected since last update: reviewer findings and final plan sections. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: hand off to executor; do not close GM-003 until row-specific evidence and closure doc updates exist.

## Execution Progress

- 2026-05-10 12:37:43 CEST - Role: Execution controller contract extracted. Files inspected since last update: this plan, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`. Decision/blocker: scope is GM-003 only; exact direct tests/gates and four-simulator relay proof are present; spawned-agent isolation is available through `codex exec`. Next action: spawn Executor with model `gpt-5.5` and reasoning effort `xhigh`.
- 2026-05-10 12:38:02 CEST - Role: Execution controller spawn retry. Files inspected since last update: none. Decision/blocker: first Executor spawn command exited before child work because approval flags were passed after `exec`; no repo edits were made by that failed child. Next action: retry Executor spawn with approval/sandbox flags passed as top-level Codex options.
- 2026-05-10 12:39:40 CEST - Role: Executor started. Files inspected since last update: this plan, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`, `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, `integration_test/group_multi_device_real_harness.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, `lib/features/groups/application/send_group_message_use_case.dart`. Decision/blocker: GM-001/GM-002 scaffold exists; GM-003 criteria/orchestrator/harness support is absent; fake network held deliveries can model Dana offline for the host regression without new test files. Next action: patch GM-003 criteria/tests and the row-owned host regression.
- 2026-05-10 12:44:30 CEST - Role: Executor command started. Files touched since last update: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan. Command: `dart format integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: formatting GM-003 criteria/test edits before focused criteria validation. Next action: run formatter and then focused criteria test.
- 2026-05-10 12:44:51 CEST - Role: Executor command finished. Files touched since last update: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`. Command: `dart format integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`. Result: passed; formatter changed both files. Next action: run `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`.
- 2026-05-10 12:44:51 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: focused GM-003 criteria validation after adding positive and negative guards. Next action: triage output before continuing to host regression.
- 2026-05-10 12:45:29 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Result: passed, 17 tests; GM-003 positive and negative guards are green. Next action: add the row-owned host regression in `test/features/groups/integration/group_messaging_smoke_test.dart`.
- 2026-05-10 12:46:44 CEST - Role: Executor command started. Files touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`, this plan. Command: `dart format test/features/groups/integration/group_messaging_smoke_test.dart`. Decision/blocker: row-owned host regression added; formatting before focused host run. Next action: run formatter and then the GM-003 named host regression.
- 2026-05-10 12:46:59 CEST - Role: Executor command finished. Files touched since last update: `test/features/groups/integration/group_messaging_smoke_test.dart`. Command: `dart format test/features/groups/integration/group_messaging_smoke_test.dart`. Result: passed; formatter changed the host smoke file. Next action: run `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'`.
- 2026-05-10 12:46:59 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'`. Decision/blocker: validate the new row-owned host regression before device harness changes. Next action: triage any failure before product edits.
- 2026-05-10 12:48:14 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'`. Result: passed, 1 test; no product fix needed from host proof. Next action: patch `integration_test/scripts/run_group_multi_party_device_real.dart` and `integration_test/group_multi_party_device_real_harness.dart` for `--scenario gm003`.
- 2026-05-10 12:50:58 CEST - Role: Executor command started. Files touched since last update: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, this plan. Command: `dart format integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`. Decision/blocker: GM-003 device orchestrator/harness support patched; formatting before re-running focused criteria and host suites. Next action: run formatter.
- 2026-05-10 12:52:36 CEST - Role: Executor command finished. Files touched since last update: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`. Command: `dart format integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`. Result: passed; formatter changed both files. Next action: record structural analyze and stale-doc wording updates.
- 2026-05-10 12:52:36 CEST - Role: Executor command finished. Files inspected/touched since last update: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`. Command: `dart analyze integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_party_device_real_harness.dart`. Result: passed; docs updated only where GM-001/GM-002-only multi-party harness wording became stale after adding GM-003. Next action: rerun required focused tests, then device discovery and row proof.
- 2026-05-10 12:53:01 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: required focused criteria rerun on landed tree. Next action: record result, then rerun focused GM-003 host regression.
- 2026-05-10 12:53:19 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Result: passed, 17 tests. Next action: run focused host regression.
- 2026-05-10 12:53:19 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'`. Decision/blocker: required row-owned host proof rerun on landed tree. Next action: record result, then run adjacent onboarding suite.
- 2026-05-10 12:53:41 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'`. Result: passed, 1 test. Next action: run `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`.
- 2026-05-10 12:53:41 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`. Decision/blocker: required adjacent onboarding suite. Next action: record result, then run pending invite accept/drain focused test.
- 2026-05-10 12:54:05 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`. Result: passed, 7 tests. Next action: run pending invite accept/drain focused test.
- 2026-05-10 12:54:05 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'accepts pending invite, persists group, and drains inbox'`. Decision/blocker: required direct invite/key/config drain proof. Next action: record result, then refresh device discovery.
- 2026-05-10 12:54:27 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'accepts pending invite, persists group, and drains inbox'`. Result: passed, 1 test. Next action: refresh device discovery with `flutter devices --machine` and `xcrun simctl list devices available` before row proof.
- 2026-05-10 12:54:27 CEST - Role: Executor command started. Files touched since last update: none. Command: `flutter devices --machine`. Decision/blocker: required fresh device discovery before GM-003 four-app proof. Next action: record concise output summary, then run `xcrun simctl list devices available`.
- 2026-05-10 12:55:04 CEST - Role: Executor command finished. Files touched since last update: none. Command: `flutter devices --machine`. Result: passed; detected Pixel 6 `21071FDF600CSC`, iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`, macOS, and Chrome. Next action: run `xcrun simctl list devices available`.
- 2026-05-10 12:55:04 CEST - Role: Executor command started. Files touched since last update: none. Command: `xcrun simctl list devices available`. Decision/blocker: confirm the four required simulator IDs are booted/available before row proof. Next action: record concise output summary, then run GM-003 four-app relay proof.
- 2026-05-10 12:55:26 CEST - Role: Executor command finished. Files touched since last update: none. Command: `xcrun simctl list devices available`. Result: passed; required iOS 26.1 simulators are booted: iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`. Next action: run GM-003 four-app relay proof.
- 2026-05-10 12:55:26 CEST - Role: Executor command started. Files touched since last update: none. Command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm003 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Decision/blocker: required row-specific four-app relay proof. Next action: record shared artifact directory/verdict paths or classify failure before fixing.
- 2026-05-10 13:02:17 CEST - Role: Executor command finished. Files touched since last update: none. Command: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm003 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`. Result: passed; orchestrator reported `gm003 verdicts valid for alice, bob, charlie, dana`. Evidence: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm003_HQxXEh/gmp_1778410554671_gm003_orchestrator_verdict.json`, role logs/verdicts in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm003_HQxXEh`. Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-05-10 13:02:48 CEST - Role: Executor command started. Files touched since last update: this plan. Command: `./scripts/run_test_gates.sh groups`. Decision/blocker: required named groups gate after focused GM-003 tests and device proof. Next action: record result or triage failures before continuing.
- 2026-05-10 13:03:34 CEST - Role: Executor command finished. Files touched since last update: none. Command: `./scripts/run_test_gates.sh groups`. Result: passed; Group Messaging Gate completed with all tests passed. Next action: run `git diff --check`.
- 2026-05-10 13:03:34 CEST - Role: Executor command started. Files touched since last update: this plan. Command: `git diff --check`. Decision/blocker: required whitespace/conflict-marker validation before final classification. Next action: record result, then run `./scripts/run_test_gates.sh completeness-check` because test classification docs changed beyond wording.
- 2026-05-10 13:03:56 CEST - Role: Executor command finished. Files touched since last update: none. Command: `git diff --check`. Result: passed with no output. Next action: run `./scripts/run_test_gates.sh completeness-check` because GM-003 harness/test classification docs changed.
- 2026-05-10 13:03:56 CEST - Role: Executor command started. Files touched since last update: this plan. Command: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: required conditional completeness gate because classification docs changed beyond wording. Next action: record result or triage failures before final completion entry.
- 2026-05-10 13:04:21 CEST - Role: Executor command finished. Files touched since last update: none. Command: `./scripts/run_test_gates.sh completeness-check`. Result: passed; completeness check reported `731/731 test files classified`. Next action: final status/diff review and completion entry.
- 2026-05-10 13:05:20 CEST - Role: Executor command started. Files inspected/touched since last update: `git status --short`, focused diff stats, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm003_HQxXEh/gmp_1778410554671_gm003_orchestrator_verdict.json`, this plan. Command: `git diff --check`. Decision/blocker: final whitespace/conflict-marker validation after correcting the recorded artifact path. Next action: record result and final completion entry.
- 2026-05-10 13:05:47 CEST - Role: Executor command finished. Files touched since last update: none. Command: `git diff --check`. Result: passed with no output. Next action: final completion entry.
- 2026-05-10 13:05:47 CEST - Role: Executor completed. Files inspected/touched since last update: this plan. Decision/blocker: GM-003 implementation evidence exists; no required command failed; source matrix/breakdown closure remains intentionally untouched for the later closure pass. Next action: report files changed, tests/gates, artifact paths, and residual uncertainty.

## real scope

Own exactly GM-003: "Add D while D is offline, then D opens app."

Implement only the narrow row proof that is missing today:

- Extend the accepted GM multi-party device harness and criteria so `--scenario gm003` is supported and validated.
- Add or tighten a row-owned host/fake-network regression proving the GM-003 membership window: Alice can send before and after Dana is added; Dana receives no pre-add message, receives exactly the post-add message after opening/joining/catching up, and can send after key/config install.
- Run row-specific four-app relay proof with the accepted relay env and four distinct app targets.
- Update only directly relevant harness/docs/test classification wording if the new `gm003` support makes existing GM-001/GM-002-only text stale.

Do not change product code unless the new GM-003 host proof or device proof exposes a real product gap. If a gap appears, stop broadening and make the smallest code/test change needed for the failed GM-003 contract.

## closure bar

GM-003 is good enough only when execution produces row-specific evidence that:

- Alice/Bob/Charlie start as current members on one group/topic/key epoch.
- Alice sends one pre-add message before Dana is a member; Dana never receives or persists that message.
- Alice adds Dana while Dana's app is offline/not running for the add and post-add send.
- Alice sends one post-add message while Dana is still offline; Dana receives/persists that post-add message exactly once after opening/joining/catching up.
- Dana has installed group config/key, converges on A/B/C/D membership, and sends one message that Alice/Bob/Charlie receive exactly once.
- The proof validates receiver `messageId`, text/plaintext, `senderPeerId`, and `keyEpoch` against sender `sentMessages`, and rejects sender-only, duplicate, missing, or pre-add leakage evidence.

Planning must not mark GM-003 covered. GM-003 may only be marked `Covered` after execution produces row-specific evidence and a closure pass updates both the source matrix and this breakdown.

## source of truth

- Current code and direct tests win over stale prose.
- Source matrix row GM-003 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` defines the scenario, preconditions, steps, expected result, and current `Open` status.
- Breakdown row GM-003 in `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` defines the row owner files, current `evidence-gated` posture, and closure discipline.
- `Test-Flight-Improv/test-gate-definitions.md` defines named gate membership; direct/manual orchestrator entries are supporting evidence, not frozen named gates.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` records existing group test inventory and accepted multi-party harness caveats.
- GM-001 and GM-002 closure rows are precedents for row-specific host proof plus four-app relay proof, not substitute evidence for GM-003.

## session classification

`implementation-ready`

Reason: the source/breakdown classification starts as `needs_repo_evidence` / `evidence-gated`, but exact planning found missing row-owned harness and criteria support for `gm003`. That missing support is repo-owned implementation work. Product behavior remains evidence-gated: only change app/Go product code if the new GM-003 proof fails for a product reason.

## exact problem statement

GM-003 is still open because no exact row proof currently demonstrates the offline-add window. Existing evidence covers adjacent behavior:

- GM-001 proves A/B/C creation and fan-out.
- GM-002 proves adding Dana while everyone is online.
- Existing host tests prove new-member no-backfill, add/send boundaries, pending invite accept plus inbox drain, and offline replay mechanics.

The missing proof is the combined user-visible path where Dana is invited while offline, Alice sends before and after the invite, Dana later opens the app, catches up only to allowed post-add content, and can send after key/config installation.

What must stay unchanged:

- Do not weaken GM-001/GM-002 criteria or existing harness validation.
- Do not accept a single `FLUTTER_DEVICE_ID` run as multi-party proof.
- Do not convert this session into removal, media, reaction, MLS, first-class per-device identity, or UI invite-status work.

## files and repos to inspect next

Primary harness and criteria:

- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`

Primary host regression candidates:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`

Product seams to inspect only if a proof fails:

- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

Docs to adjust only if execution changes proof inventory text:

- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `test/features/groups/integration/group_messaging_smoke_test.dart` includes the accepted GM-002 host proof for adding Dana while A/B/C are online and converging post-add delivery.
- `test/features/groups/integration/group_new_member_onboarding_test.dart` already proves new members receive only post-join text/media, multi-add epoch convergence, current metadata/roles without pre-join history, and the add/send subscription boundary.
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart` proves accepting a pending invite persists group/key state and drains inbox backlog.
- `test/features/groups/integration/invite_round_trip_test.dart` includes offline re-invite and send-after-rejoin coverage.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` has broad offline replay, signature, sender binding, duplicate, cursor, and mixed-epoch drain coverage.
- `test/integration/group_multi_party_device_criteria_test.dart` currently guards GM-001/GM-002 device proof shape only.

Missing:

- No criteria or orchestrator support for `gm003`.
- No exact host regression combines pre-add exclusion, offline post-add catch-up, and Dana send-after-install in one GM-003-owned proof.
- No row-specific four-app relay artifact exists for GM-003.

## regression/tests to add first

Add criteria coverage before harness/device execution:

- In `test/integration/group_multi_party_device_criteria_test.dart`, add `gm003` scenario requirement assertions for Alice/Bob/Charlie/Dana.
- Add a valid GM-003 verdict fixture proving:
  - `aliceBeforeDanaAdd` sent by Alice is received exactly once by Bob and Charlie only.
  - `aliceAfterDanaOfflineAdd` sent by Alice is received exactly once by Bob, Charlie, and Dana.
  - `danaAfterOfflineJoin` sent by Dana is received exactly once by Alice, Bob, and Charlie.
  - Dana's verdict proves late/offline join and inbox/catch-up path using explicit GM-003 proof fields.
- Add negative criteria tests rejecting Dana receiving `aliceBeforeDanaAdd`, missing Dana post-add catch-up, missing Dana send, duplicate receiver persistence, and missing GM-003 offline/catch-up proof fields.

Add one direct host regression before product edits:

- Prefer `test/features/groups/integration/group_messaging_smoke_test.dart` with a test named like `GM-003 adds D while D is offline, catches up post-add only, and D can send`.
- Use existing fake user helpers where possible. Model Dana as not subscribed/not started for the pre-add send; after add/key install, hold Dana's delivery or otherwise model offline backlog until Dana "opens"; then release/catch up, verify no pre-add row, verify exactly one post-add row, and verify Dana can send to A/B/C.
- If the existing fake helpers cannot express the row without ad hoc setup, add the smallest helper to `FakeGroupPubSubNetwork` or `GroupTestUser`; do not create a parallel fake networking framework.

Only after the criteria and host regression are meaningful, extend the device harness.

## step-by-step implementation plan

1. Update `group_multi_party_device_criteria.dart` to recognize `gm003` with roles Alice/Bob/Charlie/Dana while preserving all GM-001/GM-002 behavior.
2. Extend expected GM-003 proof messages and criteria validation:
   - Alice pre-add message: receivers Bob/Charlie only.
   - Alice post-add/offline message: receivers Bob/Charlie/Dana.
   - Dana post-join message: receivers Alice/Bob/Charlie.
   - Required GM-003 offline/catch-up proof fields so an online-Dana run cannot masquerade as GM-003.
3. Add focused criteria tests and run `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart`. Stop and fix criteria if these tests fail.
4. Add the host/fake-network GM-003 regression. First make it fail for the current missing proof if practical; then implement only test/helper changes unless the failure points to product code.
5. Run the focused host regression. If it fails because existing product behavior admits pre-add content to Dana, fails post-add catch-up, or blocks Dana's send after key/config install, classify that as product implementation work and apply the smallest targeted fix in the owner file identified by the failure.
6. Extend `run_group_multi_party_device_real.dart` for `--scenario gm003`. It must not launch all four apps as fully active from the start. It should support a Dana identity/preflight or equivalent setup, keep Dana offline/not running during Alice's add and post-add send, then launch Dana late using a stable identity/db so the proof represents "D opens app."
7. Extend `group_multi_party_device_real_harness.dart` for GM-003 role flows:
   - Alice creates A/B/C group and waits for Bob/Charlie.
   - Alice sends `aliceBeforeDanaAdd`.
   - Alice adds Dana, publishes/stores the members-added/config payload, and writes Dana's group/key fixture for late install.
   - Alice sends `aliceAfterDanaOfflineAdd` while Dana is offline.
   - Bob/Charlie receive both Alice messages and later Dana's send.
   - Dana starts late, imports/installs group config/key, drains/catches up, receives only `aliceAfterDanaOfflineAdd`, sends `danaAfterOfflineJoin`, and writes explicit offline/catch-up proof fields.
8. Update `test-inventory.md` and `test-gate-definitions.md` only where the current GM-001/GM-002-only multi-party harness description becomes stale after adding GM-003.
9. Run the exact tests/gates below. If row-specific device proof fails for a product reason, do not relax criteria; fix the smallest product seam and rerun the direct proof.
10. Leave GM-003 source matrix and breakdown status unchanged during implementation planning/execution. A later closure-audit pass owns marking `Covered` after row evidence is accepted.

## risks and edge cases

- Dana may accidentally be online/subscribed during the post-add send; criteria must reject that as non-GM-003 evidence.
- Pre-add message leakage to Dana is a row-blocking failure, not an acceptable difference.
- Post-add message can arrive live instead of through offline catch-up if Dana starts too early; the harness must sequence Dana's launch after Alice's post-add send.
- The invite/key/config install path may be represented by a harness fixture like GM-002. If actual pending-invite accept behavior fails in host tests, fix that product path rather than hiding it in harness setup.
- Offline replay duplicates must be rejected by criteria and host assertions.
- Device proof depends on four distinct app targets and the exact relay env; single-target `FLUTTER_DEVICE_ID` gates are insufficient.
- Dirty worktree contains unrelated modified/untracked files; execution must avoid reverting or staging unrelated work.

## exact tests and gates to run

Direct host/criteria:

```sh
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-003 adds D while D is offline, catches up post-add only, and D can send'
```

Adjacent direct suites after harness/host changes:

```sh
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'accepts pending invite, persists group, and drains inbox'
```

Row-specific four-app relay proof:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm003 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485
```

Named/supporting gates:

```sh
./scripts/run_test_gates.sh groups
git diff --check
```

Run `./scripts/run_test_gates.sh completeness-check` if execution adds new test files or updates test classification docs beyond wording for existing files.

Fresh device profile recorded for the row-specific proof:

- `flutter devices --machine` confirmed Pixel 6 `21071FDF600CSC`, iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`, plus macOS and Chrome.
- `xcrun simctl list devices available` confirmed the four iOS 26.1 simulator ids above are booted.

## known-failure interpretation

- Before implementation, `--scenario gm003` failing as unsupported is expected and proves the harness gap; after GM-003 support lands, unsupported-scenario output is a blocker.
- Any proof where Dana receives `aliceBeforeDanaAdd` is a product or harness failure and cannot be accepted.
- Any proof where Dana's post-add message is only sender-side evidence, lacks receiver persistence, lacks key/config install, lacks offline/catch-up proof fields, or lacks Dana's successful send-after-join is not GM-003 coverage.
- A failure caused by missing/terminated simulators, unavailable relay, or wrong relay env is an environment blocker; rerun device discovery and relay setup before classifying product behavior.
- Pre-existing failures outside the focused GM-003 commands and `groups` gate must be documented separately and not used to close GM-003. New failures in focused criteria, focused host regression, or GM-003 device proof are row blockers.

## done criteria

- The plan remains execution-ready and GM-003 remains Open until closure.
- `gm003` is supported by criteria, orchestrator, and harness without weakening GM-001/GM-002.
- Focused criteria test passes and includes negative GM-003 guards.
- Focused host/fake-network GM-003 regression passes.
- Row-specific four-app relay proof with `--scenario gm003` passes and writes an orchestrator verdict with `scenario: gm003`, `ok: true`, role/device mapping, and per-role verdict paths.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass, or any unrelated pre-existing failure is clearly separated with evidence.
- Later closure updates the GM-003 source matrix row and breakdown row/session ledgers only after evidence exists.

## scope guard

Do not:

- Mark GM-003 `Covered` in this planning session.
- Treat GM-001, GM-002, prerequisite-shaped artifacts, or a single-device gate as GM-003 evidence.
- Weaken receiver tuple validation, duplicate detection, membership convergence checks, key epoch checks, or relay env validation.
- Add broad product architecture, MLS semantics, per-device revocation, media/reaction expansion, removal/re-add behavior, notification routing, or UI invite-status work.
- Change Go/libp2p code unless row-specific proof identifies a Go-side group inbox or pubsub membership failure.
- Rewrite the harness framework when a scenario extension is enough.

## accepted differences / intentionally out of scope

- The device harness may use the established fixture/import pattern for Dana's key/config install, matching the accepted GM-002 precedent. Full UI invite acceptance is not required unless the direct host invite/drain proof or device flow exposes a product gap.
- Pixel 6 is available but not required for the primary row proof when the four booted iOS simulators provide distinct Flutter app targets.
- `group-real-network-nightly` with one `FLUTTER_DEVICE_ID` is not a substitute for the GM-003 four-role orchestrator proof.
- Closure documentation is intentionally out of scope for this planning step; closure must run after execution evidence exists.

## dependency impact

- GM-004 and later membership-mutation rows can reuse the GM-003 late-role/offline harness pattern, but this session should not pre-build removal or re-add scenarios.
- Criteria changes must preserve GM-001 and GM-002 accepted closures; regression failures there block the harness change.
- If GM-003 exposes a product gap in invite accept, offline inbox recipient filtering, group config sync, or send-after-install, later GM rows should wait for the smallest fix before using GM-003 evidence as a precedent.

## Reviewer Findings

- Sufficiency: sufficient with adjustments; no structural blocker.
- Missing files/tests/gates: no required files are missing. The plan names the owner harness, criteria, host regression, relevant product seams, and row device proof. It also includes the `groups` gate and `git diff --check`.
- Stale assumptions: none found. The plan explicitly treats current GM-003 unsupported-scenario behavior as the proof gap and records fresh device/simulator discovery.
- Overengineering check: acceptable. The plan extends the existing GM harness instead of inventing a parallel orchestrator, and it forbids product changes unless row proof exposes a product gap.
- Decomposition check: sufficient. Criteria tests come first, then host regression, then harness/device proof, then closure.
- Minimum adjustment before execution-ready: keep the optional `completeness-check` condition explicit because no new files are planned; update only if execution adds new files or classification docs beyond wording.

## Arbiter Decision

- Structural blockers: none.
- Incremental details intentionally deferred: exact implementation names for new helper methods and verdict fields may be chosen by the executor as long as the GM-003 criteria still proves late/offline Dana, post-add-only catch-up, and Dana send-after-install.
- Accepted differences intentionally left unchanged: the device harness may use the existing fixture/import pattern for Dana key/config install, and `completeness-check` remains conditional because no new files are required by the plan.
- Stop rule: no structural blocker was found, so no further planning loop is needed.
- Final verdict: execution-ready. GM-003 remains Open until execution evidence exists and a later closure pass updates the source matrix and breakdown.
