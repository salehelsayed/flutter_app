# GM-016 Removed Member Topic Unsubscribe Plan

Status: accepted by execution QA; closed by closure audit

## Planning Progress

- 2026-05-11T03:37:55+02:00 - Planner completed. Files inspected since last update: draft plan sections and evidence notes in this file. Decision/blocker: draft is `implementation-ready` with tests/harness-first closure and conditional production fixes only. Next action: Reviewer checks sufficiency, stale assumptions, gate coverage, and scope boundaries.
- 2026-05-11T03:37:55+02:00 - Reviewer started. Files inspected since last update: this draft plan. Decision/blocker: no blocker; review against mandatory section list and GM-016 row contract. Next action: identify structural blockers vs incremental details.
- 2026-05-11T03:38:42+02:00 - Reviewer completed. Files inspected since last update: this draft plan and mandatory-section index. Decision/blocker: sufficient with one incremental tightening; simulator criteria must require explicit stale discovery/register stimulus or post-leave quiet-window proof. Next action: patch that detail, then Arbiter classifies findings.
- 2026-05-11T03:39:14+02:00 - Arbiter started. Files inspected since last update: reviewer notes and patched closure/test criteria wording. Decision/blocker: no new structural blocker identified at start. Next action: classify reviewer findings and decide whether the artifact can become execution-ready.
- 2026-05-11T03:39:34+02:00 - Arbiter completed. Files inspected since last update: final reviewer notes, closure bar, regression/test contract, known-failure interpretation, and scope guard. Decision/blocker: no structural blockers remain; incremental stale-state proof detail is patched; artifact is execution-ready. Next action: hand off GM-016 for execution only.

## Execution Progress

- 2026-05-11T03:41:45+02:00 - Contract extracted. Files inspected since last update: this GM-016 plan and `implementation-execution-qa-orchestrator` skill. Decision/blocker: execution contract is concrete; nested spawned Executor/QA tools are not exposed in this environment, so the run will use the skill's local sequential fallback only if no partial child work exists and the workflow remains bounded. Next action: run required simulator availability checks, then inspect GM-016 owner files and existing dirty diffs before editing.
- 2026-05-11T03:42:29+02:00 - Availability checks finished. Files inspected since last update: command output from `flutter devices --machine` and `xcrun simctl list devices available`. Decision/blocker: required simulator IDs are available and booted; real external devices are present but excluded from GM-016 proof. Next action: inspect GM-016 owner diffs and existing harness/criteria shape before adding row-owned tests.
- 2026-05-11T03:46:46+02:00 - Executor local fallback started. Files inspected since last update: `group_message_listener.dart`, `leave_group_use_case.dart`, `rejoin_group_topics_use_case.dart`, `group_test_user.dart`, fake pubsub network, focused group tests, criteria, runner, and multi-party harness. Decision/blocker: no partial nested child work exists; app behavior appears suitable for tests/harness-first GM-016 proof, with production fixes conditional on focused failures. Next action: add GM-016 host tests and criteria/harness support in owner files only.
- 2026-05-11T03:53:21+02:00 - Executor edits landed and formatted. Files touched since last update: `group_message_listener_test.dart`, `leave_group_use_case_test.dart`, `group_startup_rejoin_smoke_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`. Decision/blocker: no production source change made; GM-016 support is tests/harness-only so far. Next action: run focused GM-016 selectors.
- 2026-05-11T03:55:03+02:00 - Focused host selectors finished. Files inspected/touched since last update: GM-016 focused test output and `group_membership_smoke_test.dart`. Decision/blocker: all focused GM-016 selectors pass; one membership smoke setup failure was triaged as this-session test data using a stale fixed `removedAt` before the membership watermark, then fixed with a current removal timestamp. Next action: run targeted analyzer over touched files.
- 2026-05-11T03:56:15+02:00 - Targeted analyzer finished. Files inspected/touched since last update: analyzer output and `group_startup_rejoin_smoke_test.dart`. Decision/blocker: analyzer passed after removing an unused touched-test import. Next action: run exact GM-016 three-simulator proof.
- 2026-05-11T04:02:06+02:00 - Exact GM-016 three-simulator proof passed. Files inspected since last update: simulator/orchestrator output and verdict locations. Decision/blocker: `gm016` verdicts are valid for Alice, Bob, and Charlie using simulators only; proof directory is `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm016_pfv9ja` with `gmp_1778464599719_{alice,bob,charlie}_verdict.json`. Next action: run required repository gates: groups, completeness-check, and `git diff --check`.
- 2026-05-11T04:02:47+02:00 - Required `./scripts/run_test_gates.sh groups` gate passed. Files inspected since last update: group gate output. Decision/blocker: no GM-016 regression or unrelated blocking failure in the group gate. Next action: run `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-11T04:03:04+02:00 - Required `./scripts/run_test_gates.sh completeness-check` and `git diff --check` passed. Files inspected since last update: completeness-check output and whitespace diff check. Decision/blocker: all 731 test files are classified and no whitespace errors were found. Next action: perform local QA Reviewer pass over scope, diffs, and evidence because spawned QA tooling is unavailable.
- 2026-05-11T04:04:29+02:00 - Local QA Reviewer pass completed. Files inspected since last update: GM-016 focused diffs, criteria/harness GM-016 sections, and Alice/Bob/Charlie verdict JSON. Decision/blocker: no blocking QA findings; verdicts prove Alice sent only to Bob, Bob persisted one post-removal message, and Charlie had zero post-leave join/discovery/inbound/reaction/parse/decrypt/plaintext counts with deleted group/member/key state. Next action: final status check and report `accepted`.
- 2026-05-11T04:05:00+02:00 - Final status check completed. Files inspected since last update: scoped status and final `git diff --check`. Decision/blocker: GM-016 owner files are the only files changed by this session, alongside the GM-016 plan progress entry; pre-existing dirty files outside this scope remain untouched. Final execution verdict: `accepted`.

## Closure Audit

Closure verdict: `closed` / accepted for GM-016. Accepted execution proves removed Charlie leaves the group topic path, loses local group/member/key state, does not rejoin from stale/deleted state, and receives no post-removal group traffic while Bob keeps delivery.

What is now closed:

- Source matrix row GM-016 is `Covered`.
- GM-016 landed as tests/harness/criteria support only; no production source changes were required.
- Row-owned proof files are `group_message_listener_test.dart`, `leave_group_use_case_test.dart`, `group_startup_rejoin_smoke_test.dart`, `group_membership_smoke_test.dart`, `group_multi_party_device_criteria_test.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`.

Accepted simulator proof:

- Exact simulator-only `--scenario gm016` proof passed on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
- Verdict `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm016_pfv9ja/gmp_1778464599719_gm016_orchestrator_verdict.json` records `scenario: gm016`, `ok: true`, and `gm016 verdicts valid for alice, bob, charlie`.
- Role/criteria proof shows Alice sent only to Bob, Bob persisted Alice's post-removal message once, and Charlie had `leaveRequested: true`, `leaveResponseOk: true`, no group recreation after a 5002ms quiet window, zero member/key rows, zero post-leave join/inbound/reaction/discovery/parse/decrypt/plaintext counts, and `receivedAlicePostRemoval: false`.

Maintenance gates passed:

- Focused GM-016 host selectors for listener, leave, startup rejoin, membership smoke, and criteria.
- Targeted analyzer over touched files, exact three-iOS-simulator `gm016`, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check` (`731/731`), and `git diff --check`.

Residual-only items:

- None for the GM-016 product/test contract.

Still-open items: GM-017 stale removed-member publish validation and later removed-member/durable-recipient/re-add rows remain open; no final program verdict is written from this GM-016 closure.

Accepted differences:

- Execution used the execution skill's local sequential fallback because nested Executor/QA child tools were unavailable. This is accepted execution mode, not a product residual.
- Direct `--scenario gm016` simulator proof is sufficient; `--scenario all` expansion is not part of GM-016 closure.
- Checkpoint policy was skipped because dirty overlapping aggregate rollout artifacts and unrelated/overlapping product/test edits make a clean scoped checkpoint unsafe. Simulator/Xcode `info.plist` `LastAccessedDate` metadata is ignored and was not reverted.

Reopen GM-016 only on a real regression against removed-member leave/unsubscribe, deleted local state, no rejoin after quiet/stale stimulus, no post-leave events/plaintext, Alice Bob-only recipient selection for this proof, or Bob exact-once post-removal receipt.

## Evidence Collector Findings

- Source row GM-016 is `Open`: C was removed and app called `LeaveGroupTopic`; after stale discovery/register state and A's post-removal send, C must have no active discovery loop/subscription and emit no post-removal message.
- Breakdown currently labels GM-016 `needs_repo_evidence` / `evidence-gated`, but the runner, criteria, and harness only support `gm001` through `gm015`; `gm016` is rejected today.
- `leaveGroup` calls `callGroupLeave`, then removes members, keys, and the group from local persistence. `callGroupLeave` sends `cmd: group:leave`.
- `GroupMessageListener._handleMemberRemoved` calls `leaveGroup` when the removed peer is the local user, emits `groupRemovedStream`, and returns before applying remaining-member config updates.
- `rejoinGroupTopics` only iterates persisted groups and skips groups with no key, so a successfully deleted removed-member group should not be rejoined on startup/resume recovery.
- Existing Flutter tests prove self-removal calls `group:leave`, local cleanup happens, and removed members do not receive normal fake-network post-removal messages. They do not directly prove stale post-leave discovery/register state cannot reactivate C or that a real app harness emits no post-removal transport events.
- Existing Go node tests include `TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave`, `TestLeaveGroupTopic_CancelsDiscoveryContext`, `TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish`, and `TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit`. This proves the Go `LeaveGroupTopic` primitive, but not the Flutter app/harness row contract by itself.
- `flutter devices --machine` and `xcrun simctl list devices available` both show the requested iOS simulators as available and booted: Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.

## real scope

Own source row `GM-016` only: removed member Charlie remains unsubscribed after app-level self-removal calls `LeaveGroupTopic`, stale discovery/register state does not reactivate Charlie's group topic, Alice can send after removal, Bob receives normally, and Charlie emits no post-removal inbound group message/reaction/parse/decrypt/discovery-work events for that group.

This session should add row-owned Flutter host proof, criteria proof, and exact three-iOS-simulator `--scenario gm016` proof. Production Flutter or Go code changes are only in scope if the new RED-first proof shows a real GM-016 behavior gap. Do not change GM-001 through GM-015 closure state, do not implement GM-017+, and do not write a final program verdict.

## closure bar

GM-016 is closable only when row-owned proof shows all of the following:

- Charlie was an active member before removal and app processing of `member_removed` called `group:leave` / `LeaveGroupTopic` exactly for the removed group.
- After Charlie's leave, local app state for Charlie has no group, no members, and no group key that can drive startup/resume topic rejoin.
- A measured stale discovery/register stimulus or post-leave quiet window is present after Charlie's leave, and it does not recreate Charlie's group subscription, trigger `group:join`, or persist/emit a post-removal group message on Charlie.
- Alice's post-removal send is healthy and Bob receives it once.
- Charlie records no post-removal inbound `group_message:received`, `group_reaction:received`, `group:payload_parse_failed`, `group:decryption_failed`, or `group:discovery` work for the removed group after the leave baseline.
- Exact simulator-only command `--scenario gm016` passes on Alice `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, Bob `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and Charlie `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.

## source of truth

Current code and tests beat stale prose. Source matrix row GM-016 and this plan define the row contract. `scripts/run_test_gates.sh` is the command source of truth if it disagrees with `Test-Flight-Improv/test-gate-definitions.md`. Existing GM-001 through GM-015 plan and closure docs are read-only context. Existing Go GL-008 leave proof is valid supporting evidence for the Go primitive, but it does not close the Flutter app/device row without GM-016-specific app/harness proof.

## session classification

`implementation-ready`.

Closure type: `tests/harness proof first`, not evidence-only. Code changes are conditional. If the RED host/device proof already passes after only adding assertions and `gm016` harness/criteria support, close as tests-only. If it shows Charlie can be rejoined by stale state, receives post-removal events, or A/B delivery breaks, fix the smallest app or bridge seam shown by that proof and close as code/tests.

## exact problem statement

The repo currently proves pieces of removed-member cleanup, but it does not have one exact GM-016 proof that combines app self-removal, `LeaveGroupTopic`, stale discovery/register state, post-removal publish, and multi-party delivery observation. The missing user-visible guarantee is that a removed member cannot silently reappear as a live group subscriber after removal and receive post-removal group traffic, while remaining members keep normal delivery.

Must stay unchanged: remaining-member removal/key/config behavior, re-add semantics, GM-014/GM-015 accepted contracts, and the GM-017 validator backstop for stale subscription publish acceptance.

## files and repos to inspect next

Production/app files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/group_key_update_listener.dart` only if stale key/config replay appears involved
- `go-mknoon/node/pubsub.go` only if app/device proof implicates Go topic cleanup

Tests, harnesses, and infra:

- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/shared/fakes/group_test_user.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `group_message_listener_test.dart` already covers self-removal calling `group:leave`, LP003 replay self-removal as a ban-equivalent leave path, and non-self removal not calling leave.
- `leave_group_use_case_test.dart` covers `group:leave` dispatch and local group/member/key cleanup.
- `group_membership_smoke_test.dart` covers removed members not receiving normal fake-network post-removal messages and self-removal cleanup.
- `group_startup_rejoin_smoke_test.dart` covers startup rejoin for persisted groups with keys and fake-network resubscription behavior.
- `go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go` covers Go post-leave discovery/inbound silence for GL-008.

Missing: exact GM-016-named proof that stale discovery/register state after app `LeaveGroupTopic` does not reactivate Charlie, exact criteria validation for the required proof fields, and `--scenario gm016` support in the multi-party device runner and harness.

## regression/tests to add first

Add the RED proof before production fixes:

1. `group_message_listener_test.dart`: a `GM-016` self-removal test where Charlie processes `member_removed`, bridge records one `group:leave`, local group/member/key state is gone, then a stale post-removal envelope for the same group is delivered on the old incoming stream. Assert no `groupMessageStream` emission, no saved post-removal message, no `group:join`, and no second leave loop.
2. `group_startup_rejoin_smoke_test.dart` or `leave_group_use_case_test.dart`: a `GM-016` rejoin guard proving deleted removed-member state is not rejoined by `rejoinGroupTopics`, even when stale fake network/discovery state is present outside persisted app state.
3. `group_membership_smoke_test.dart`: a `GM-016 removed member remains unsubscribed from topic` fake-network integration proof. Keep A/B delivery healthy and assert Charlie remains unsubscribed, has no local group/key, receives no post-removal text, and no fake `subscribe`/bridge `group:join` happens after removal.
4. `group_multi_party_device_criteria_test.dart`: criteria acceptance and rejection cases for `gm016RemovedUnsubscribeProof`.
5. `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_real_harness.dart`: add `gm016` support and role verdict fields that measure actual leave request, stale discovery/register stimulus or post-leave quiet-window proof, post-leave discovery event count, post-leave inbound event count, Charlie local cleanup, A/B post-removal delivery, and zero Charlie post-removal plaintext.

If these tests fail for missing production behavior, fix only the implicated seam. Likely candidates are self-removal cleanup ordering in `group_message_listener.dart`, `leaveGroup` cleanup/error handling, or stale persisted group/key state causing `rejoinGroupTopics` to rejoin a removed group. Touch Go only if the exact evidence shows `LeaveGroupTopic` itself leaves discovery/subscription state active.

## step-by-step implementation plan

1. Re-read the GM-016 source row, this plan, and the current dirty diffs in the GM-016 owner files before editing. Do not rewrite unrelated user edits.
2. Add the focused host RED tests named `GM-016` for listener stale post-leave events, deleted-state rejoin guard, and fake-network A/B healthy post-removal delivery with Charlie unsubscribed.
3. Run the focused RED host selectors. If they unexpectedly pass without code changes, keep the tests and continue to harness proof. If they fail for a real bug, patch the smallest owner seam.
4. Add criteria model support for `gm016` and required proof fields. Add criteria tests that fail on missing leave proof, any post-leave discovery work, any post-leave inbound event, any Charlie post-removal plaintext, missing A/B delivery, or unsupported scenario wiring.
5. Add runner and harness support for `--scenario gm016` with roles Alice/Bob/Charlie only.
6. Harness flow: establish group membership, confirm Charlie active pre-removal, have Alice remove Charlie, wait for Charlie to process self-removal and record `GROUP_FL_BRIDGE_LEAVE_REQUEST/RESPONSE`, record Charlie's post-leave event baseline, record either an explicit stale discovery/register stimulus or a bounded post-leave quiet window over the old state, have Alice send post-removal, require Bob receive once, require Charlie receive/emit zero post-removal events and keep no local group/key.
7. If the harness cannot directly introspect Go internal maps, combine app event proof with existing Go `LeaveGroupTopic` proof. Do not add production debug APIs just for the test unless no existing event or command log can prove the row.
8. Run the exact focused tests, analyzer, exact three-simulator command, `groups`, `completeness-check`, and diff checks.
9. Update only the GM-016 source row/breakdown/plan closure sections if execution later accepts the row. Do not update GM-001 through GM-015 or write a final program verdict.

Stop early if current evidence disproves the need for production code: after row-owned tests/harness pass with no production edits, classify execution as tests-only closure.

## Device/Relay Proof Profile

Use simulators only. Do not use the attached Android device or any real external device for this row.

Current availability:

- Alice: `38FECA55-03C1-4907-BD9D-8E64BF8E3469` (`iPhone 17 Pro`, iOS 26.1, booted, supported by Flutter)
- Bob: `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` (`iPhone Air`, iOS 26.1, booted, supported by Flutter)
- Charlie: `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`, iOS 26.1, booted, supported by Flutter)

These exact devices are sufficient for GM-016's three-role proof. Refresh availability during execution with:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Required relay profile:

```bash
export MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
```

Exact simulator command after `gm016` support exists:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm016 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

## risks and edge cases

- Stale app persistence could keep a removed group/key and let startup/resume rejoin the topic.
- A stale transport event could still reach the Dart listener after leave; it must be ignored and not persisted.
- `leaveGroup` bridge failure ordering matters: do not delete local state before a failed `group:leave` unless the row explicitly requires a retry/recovery policy.
- Event-silence checks must start after a clear post-leave baseline to avoid counting legitimate pre-leave discovery/message events.
- Criteria must reject pseudo-proof that only says "no messages" without proving leave was requested, stale discovery/register stimulus or quiet-window proof was exercised, and A/B post-removal delivery remained healthy.
- Simulator app build or log-reader flakes must not be misread as a GM-016 product failure.

## exact tests and gates to run

Focused host tests:

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-016'
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'GM-016'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GM-016'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-016'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name GM-016
```

Adjacent direct tests if touched or if failures cluster there:

```bash
flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart
flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'GM-014'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'self-removal calls leaveGroup and emits on groupRemovedStream'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP003 member_removed self-removal is the ban-equivalent leave path'
```

Targeted analyzer, adjusted to actual touched files:

```bash
dart analyze lib/features/groups/application/group_message_listener.dart lib/features/groups/application/leave_group_use_case.dart lib/features/groups/application/rejoin_group_topics_use_case.dart lib/core/bridge/bridge_group_helpers.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart
```

Exact simulator proof:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm016 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
git diff --check
```

Conditional Go proof, only if Go pubsub files are touched or app evidence implicates `LeaveGroupTopic` cleanup:

```bash
(cd go-mknoon && go test ./node -run 'TestGL008LeaveGroupTopicStopsDiscoveryAndInboundAfterLeave|TestLeaveGroupTopic_CancelsDiscoveryContext|TestLeaveGroupTopic_RemovesPubSubStateAndBlocksFuturePublish|TestLP003LeaveGroupTopicStopsLiveDeliveryAfterExit' -count=1)
```

## known-failure interpretation

Do not accept GM-016 if Charlie receives/persists/emits post-removal traffic, Charlie rejoins the topic after self-removal, `group:leave` is missing, A/B delivery fails, or criteria lacks row-specific proof.

Treat simulator/Xcode/Flutter build-state problems as fixable infrastructure during execution, not terminal row blockers. Allowed cleanup actions include refreshing device inventory, booting the exact simulators with `xcrun simctl boot <id>`, shutting down unrelated simulators if needed, uninstalling the app from the exact simulators, clearing DerivedData if Xcode build state is stale, running `flutter clean` and `flutter pub get`, then rerunning the same commands. `info.plist` simulator metadata churn such as `LastAccessedDate` is not GM-016 evidence.

Missing or mismatched `MKNOON_RELAY_ADDRESSES` is a setup failure; set the exact relay profile and rerun. A failure in `--scenario all` is not GM-016 evidence; GM-016 requires direct `--scenario gm016` proof.

## done criteria

- Source supports `gm016` in runner, criteria, harness, and criteria tests.
- Focused GM-016 host tests pass and prove leave request, local cleanup, stale event non-persistence/non-emission, no rejoin, and A/B healthy delivery.
- Exact three-iOS-simulator `--scenario gm016` proof passes and records accepted Alice/Bob/Charlie role verdict JSONs.
- `groups`, `completeness-check`, targeted analyzer, and `git diff --check` pass or any unrelated pre-existing failure is documented with rerun evidence.
- If production code changed, direct adjacent tests for the touched seam pass.
- GM-016 source matrix/breakdown closure updates are left for the execution/closure step, not this planning step.

## scope guard

Do not broaden into GM-017 stale subscription publish acceptance, post-removal notification routing, durable offline replay privacy, re-add epoch repair, group validator redesign, or final program status. Do not rewrite GM-001 through GM-015 closure state. Do not replace existing harness architecture or add broad production debug APIs when existing event logs, bridge command logs, verdict JSON, and Go direct tests can prove the row.

Overengineering includes adding new group lifecycle state machines, changing key rotation policy, changing last-admin behavior, altering group retention/deletion policy, or changing `--scenario all` expansion for unrelated rows.

## accepted differences / intentionally out of scope

- The Go node's direct GL-008 proof remains supporting evidence, not the acceptance artifact for the Flutter GM-016 row.
- GM-016 proves Charlie is no longer subscribed/receiving after leave; GM-017 owns validator backstop behavior if a stale or malicious removed member attempts to publish from an old subscription.
- Offline inbox replay rows own queued post-removal content. GM-016 may assert no live post-removal plaintext for Charlie but should not claim full queued replay privacy.
- Re-add rows own legitimate future rejoin after a new membership start; GM-016 must not make re-add impossible.

## dependency impact

GM-017 and later removed-member/post-removal rows can depend on GM-016 only for app-level leave/unsubscribe and no post-removal inbound events after removal. If GM-016 discovers that local deletion/rejoin behavior is wrong, later rows that assume removed members cannot rejoin from stale app state should wait for the GM-016 fix. If GM-016 lands as tests-only proof, later rows should reuse the criteria/harness proof style but not reopen GM-016 absent a real regression.

## Reviewer Notes

Reviewer result: sufficient with adjustment. Mandatory sections are present, the session is narrow enough for execution, current code/tests are correctly treated as authoritative, and the exact simulator/gate contract is explicit. No structural blocker remains after requiring explicit stale discovery/register stimulus or post-leave quiet-window proof in the closure bar, harness flow, and criteria fields.

Minimum needed for sufficiency: keep GM-016 implementation tests/harness-first, keep production fixes conditional on RED proof, and keep GM-017 publish-validator backstop out of scope.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details: the reviewer-requested stale discovery/register stimulus or quiet-window requirement was accepted and patched into the closure bar, regression plan, harness flow, criteria expectations, and risk interpretation.

Accepted differences: Go GL-008 remains supporting primitive evidence rather than the GM-016 closure artifact; GM-017 stale removed-member publish-validator backstop remains intentionally out of scope; `--scenario all` is not part of GM-016 closure.

Arbiter stop rule: stop now. No further planning loop is needed because the closure bar, source of truth, direct tests, simulator proof profile, known-failure interpretation, done criteria, and scope guard are explicit.
