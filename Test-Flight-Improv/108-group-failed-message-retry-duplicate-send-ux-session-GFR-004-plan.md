# Report 108 Session GFR-004 Plan - Lifecycle, Integration, and Gate Acceptance

Status: accepted

## Planning Progress

- 2026-06-06 13:30:03 CEST - Role: Arbiter completed. Files inspected since
  last update: final GFR-004 plan, reviewer finding, simulator closure rule,
  scope guard, and coverage ledger. Decision/blocker: no structural blocker;
  simulator overclaiming is handled by mandatory proof-field inspection or
  harness extension before closure, and GFR-005 remains out of scope. Next
  action: update the GFR-004 breakdown ledger row to `execution-ready`.
- 2026-06-06 13:29:51 CEST - Role: Arbiter started. Files inspected since last
  update: reviewer finding and patched device-resolution wording.
  Decision/blocker: no structural blocker has been identified so far; arbiter
  will classify simulator overclaiming, optional host additions, and GFR-005
  exclusion. Next action: finalize arbiter verdict and set execution readiness
  if no structural blocker remains.
- 2026-06-06 13:29:33 CEST - Role: Reviewer completed. Files inspected since
  last update: mandatory section headings, GFR-004 checklist coverage ledger,
  simulator closure bar, exact test/gate command list, and known-failure rules.
  Decision/blocker: no structural blocker; the only adjustment is to make
  device resolution explicit for transport and simulator acceptance. Next
  action: patch that wording, then run arbiter classification.
- 2026-06-06 13:29:10 CEST - Role: Reviewer started. Files inspected since
  last update: GFR-004 plan draft. Decision/blocker: no blocker known; review
  is checking checklist parity, simulator gate sufficiency, source-of-truth
  ordering, scope guard, and GFR-005 exclusion. Next action: record findings
  and either patch one structural gap or advance to arbiter.
- 2026-06-06 13:29:00 CEST - Role: Planner completed. Files inspected since
  last update: completed GFR-004 draft sections, acceptance coverage ledger,
  exact test/gate/simulator command list, and known-failure rules.
  Decision/blocker: no blocker; draft is acceptance-only and preserves GFR-005
  final closure ownership. Next action: reviewer sufficiency pass against the
  implementation-plan-orchestrator mandatory sections and checklist mapping.

## Execution Progress

- 2026-06-06 17:22:03 CEST - Phase: GFR-004 simulator acceptance rerun
  accepted after local harness fix. Files inspected since last update: this
  GFR-004 plan, the Report 108 breakdown, required simulator command output,
  per-role logs, Bob proof JSONs, and role/orchestrator verdict JSONs under
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_reconnect_group_recovery_UsHiHF`
  and
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_GjdNzJ`.
  Last completed commands/results:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
  passed and discovered 123 group commands, including
  `private_relay_reconnect_group_recovery` as command `#54` and
  `private_background_resume_group_delivery` as command `#56`;
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  passed on run `1780758396971`;
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`
  passed on run `1780758894898`. Decision/blocker: no GFR-004 blocker
  remains. The original schema blocker is cleared because Alice, Bob, and
  Charlie logged `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` for
  migration `074_group_message_logical_delivery_id` in both accepted runs, and
  per-role log inspection found no `DatabaseException` or `no column named
  logical_delivery_id`. The post-schema Bob proof blocker is cleared:
  Alice's `GROUP_PUBLISH_DEBUG` for
  `aliceMissedDuringRelayDrop` on run `1780758396971` and
  `aliceDuringBackgroundBeforeEdit` on run `1780758894898` both show
  `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and
  `inboxStored:true`; Bob wrote
  `gmp_1780758396971_bob_received_aliceMissedDuringRelayDrop.json` and
  `gmp_1780758894898_bob_received_aliceDuringBackgroundBeforeEdit.json`,
  both with `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`;
  both orchestrator verdict JSONs are `ok:true` and all Alice/Bob/Charlie role
  verdict JSONs exist. Final GFR-004 execution verdict is `accepted`. Next
  action: update the breakdown ledger and let dependent GFR-005 perform final
  source/stable doc closure and whole-program verdict work.
- 2026-06-06 16:05:00 CEST - Phase: GFR-004 simulator blocker verification
  rerun. Files inspected since last update: this GFR-004 plan, the Report 108
  breakdown, required simulator command output, and current per-role logs under
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_reconnect_group_recovery_4KE07K`
  and
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_ThsVVf`.
  Last completed commands/results:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
  passed and resolved the available simulator plan;
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  exited `255`;
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`
  exited `255`. Decision/blocker: the prior schema blocker
  `simulator_schema_missing_group_message_logical_delivery_id` is cleared for
  these reruns. Alice, Bob, and Charlie all emitted
  `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` for migration
  `074_group_message_logical_delivery_id` in both required scenarios, and log
  inspection found no `DatabaseException` or `no column named
  logical_delivery_id` failure. GFR-004 still cannot close because both
  required simulator scenarios fail after schema migration and after the
  offline-drain wait started retrying drains while waiting: Bob never writes the
  required received-proof JSON. New exact blocker:
  `simulator_bob_missing_received_proof_after_offline_drain_retry`. In
  `private_relay_reconnect_group_recovery` run `1780753444911`, Alice wrote
  `gmp_1780753444911_alice_sent_aliceMissedDuringRelayDrop.json`, but her
  publish debug showed `deliveryMode:"live_only"`, `inboxStored:false`,
  `expectedRecipientCount:0`; Charlie received/persisted the message live; Bob's
  repeated offline drains returned `count:0`, Bob timed out waiting for proof
  message `aliceMissedDuringRelayDrop`, Alice timed out waiting for
  `gmp_1780753444911_bob_received_aliceMissedDuringRelayDrop.json`, Charlie
  timed out waiting for `gmp_1780753444911_bob_nw004_recovered_ready`, and no
  role verdict JSON was written. In `private_background_resume_group_delivery`
  run `1780754053119`, Alice wrote
  `gmp_1780754053119_alice_sent_aliceDuringBackgroundBeforeEdit.json`, but her
  publish debug again showed `deliveryMode:"live_only"`, `inboxStored:false`,
  `expectedRecipientCount:0`; Charlie wrote
  `gmp_1780754053119_charlie_received_aliceDuringBackgroundBeforeEdit.json` and
  `gmp_1780754053119_charlie_verdict.json`; Bob's retrying offline drains
  replayed a `member_removed` item and logged
  `GROUP_MESSAGE_LISTENER_STALE_MEMBERSHIP_EVENT_IGNORED`, but never produced the
  expected pre-edit message proof, timed out waiting for
  `aliceDuringBackgroundBeforeEdit`, and the runner reported Bob exited before
  writing a verdict. Next action: leave GFR-004 blocked and leave GFR-005
  skipped because GFR-004 is still not accepted.
- 2026-06-06 14:53:47 CEST - Phase: GFR-004 fix-pass Executor intake and
  doc patch start. Files inspected since last update:
  `/tmp/gfr004-qa-final.txt`, `/tmp/gfr004-executor-final.txt`, this GFR-004
  plan, and the GFR-004 breakdown row. Last completed command/result: no
  host, simulator, or named gate was rerun in this fix pass; QA result was
  `fail` for two bookkeeping blockers only. Current command/log being
  inspected: none. Decision/blocker: doc-only alignment is required; the
  execution blocker remains
  `simulator_schema_missing_group_message_logical_delivery_id`, classified as
  `test_or_gate_failure`. Next action: patch this plan status/final execution
  verdict and the GFR-004 breakdown row, then run required doc hygiene
  commands `graphify update .` and `git diff --check`.
- 2026-06-06 14:51:27 CEST - Phase: QA Reviewer completed; fix pass start.
  Files inspected since last update: `/tmp/gfr004-qa-final.txt`, this GFR-004
  plan, and the GFR-004 breakdown row. Last completed command/result: spawned
  QA Reviewer exited `0` with `QA verdict: fail`. Blocking findings: this plan
  lacks the required standalone final execution verdict and still reports
  `Status: execution-ready`; the GFR-004 breakdown row records blocker details
  but leaves `Final execution verdict` as `pending`. Current command/log being
  inspected: no gate or simulator command is running. Blocker state:
  doc-bookkeeping fix required only; simulator acceptance remains blocked by
  missing `group_messages.logical_delivery_id`. Next action: spawn a fresh
  GFR-004 fix-pass Executor to add the `blocked` verdict, align the breakdown
  row, and run `graphify update .` plus `git diff --check`. GFR-005 remains
  untouched.
- 2026-06-06 14:47:43 CEST - Phase: Executor completed; QA Reviewer start.
  Files inspected since last update: this GFR-004 plan, GFR-004 breakdown row,
  current `git status --short`, and `/tmp/gfr004-executor-final.txt`. Last
  completed command/result: spawned Executor exited `0`; it added three
  GFR-004 host acceptance tests, passed focused/direct host tests plus required
  named gates, attempted both required simulator scenarios, and recorded the
  simulator schema blocker. Current command/log being inspected: no simulator
  or gate command is running; next spawned command will be the separate QA
  Reviewer. Blocker state: simulator acceptance remains evidence-gated because
  both required group simulator scenarios failed before verdict on missing
  `group_messages.logical_delivery_id`; procedural QA item noted for review:
  the plan has the coverage ledger and breakdown blocker but does not yet show
  a standalone final execution verdict line. Nested Executor no-progress
  classification: `not_no_progress`; local sequential fallback is not active.
  Next action: run fresh QA Reviewer for GFR-004 only, then apply a bounded
  fix loop only if QA finds blocking gaps. GFR-005 remains untouched.
- 2026-06-06 14:45:36 CEST - Phase: final whitespace rerun completed.
  Files inspected or touched since last update: this GFR-004 plan. Current
  command completed: `git diff --check` passed again with exit `0` and no
  output after the final plan progress edit. Decision/blocker: final hygiene
  remains clean. Executor work is ready for the separate QA Reviewer.
- 2026-06-06 14:45:06 CEST - Phase: hygiene completed; Executor handoff
  ready. Files inspected or touched since last update: this GFR-004 plan,
  GFR-004 breakdown row, `graphify-out`, and current `git status --short`.
  Current commands completed:
  `dart format test/features/groups/integration/group_resume_recovery_test.dart`
  passed with `Formatted 1 file (0 changed) in 0.14 seconds.`;
  `graphify update .` passed with AST extraction `4857/4857 files (100%)` and
  rebuilt `graphify-out/graph.json` plus `graphify-out/GRAPH_REPORT.md`;
  `git diff --check` passed with exit `0` and no output. Dirty-tree summary:
  unrelated pre-existing modified production/test/doc files and untracked
  agent/graphify/report docs remain present; GFR-004 Executor-scoped changes
  are the added host acceptance tests in
  `test/features/groups/integration/group_resume_recovery_test.dart`, this
  GFR-004 plan ledger/progress, the GFR-004 breakdown row, and graphify output.
  Decision/blocker: no formatter, graphify, or whitespace blocker remains.
  GFR-004 remains evidence-gated, not closed, because both required simulator
  scenarios failed before verdict on the missing
  `group_messages.logical_delivery_id` simulator DB column and no Report
  108-specific failed/queued attempt simulator proof ran. Next action: separate
  QA Reviewer should review executor evidence and decide the formal QA outcome;
  GFR-005 remains untouched.
- 2026-06-06 14:42:20 CEST - Phase: hygiene start. Files inspected or
  touched since last update: this GFR-004 plan and the GFR-004 breakdown row.
  Current commands starting sequentially:
  `dart format test/features/groups/integration/group_resume_recovery_test.dart`;
  `graphify update .`; `git diff --check`. Decision/blocker: GFR-004 has no
  production changes, but the touched Dart acceptance test, graphify index, and
  whitespace hygiene must be verified before Executor handoff. Next action:
  record command results exactly and leave final acceptance to QA.
- 2026-06-06 14:39:57 CEST - Phase: background resume simulator scenario
  completed with blocker; coverage ledger and hygiene start. Files inspected
  or touched since last update: this GFR-004 plan,
  `/tmp/gfr004_sim_private_background_resume_group_delivery.log`, and the
  per-role Alice log under
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_background_resume_group_delivery_S1V8ZA/alice.log`.
  Current command completed:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`
  exited `255`. Device proof for the command came from the preceding group
  list resolution: Alice/Bob/Charlie/Dana set
  `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
  Exact failure: Alice exited with code `1` before writing a verdict because
  `dbInsertGroupMessage` failed with `DatabaseException(... "table
  group_messages has no column named logical_delivery_id" ...)`; Bob and
  Charlie timed out waiting for
  `gmp_1780748994255_alice_sent_aliceDuringBackgroundBeforeEdit.json`.
  Decision/blocker: this is the same simulator schema/harness evidence
  blocker as the relay reconnect run, not duplicate-send product evidence.
  Required simulator attempts are complete but blocked; GFR-004 must remain
  evidence-gated until the simulator DB schema can create or migrate
  `group_messages.logical_delivery_id` and a Report 108-specific failed/queued
  attempt proof can run. Next action: fill the itemized GFR-004 coverage
  ledger, update the breakdown GFR-004 row, then run required hygiene
  (`graphify update .`, `git diff --check`; Dart formatting was already run
  after the touched Dart test file).
- 2026-06-06 14:29:03 CEST - Phase: relay reconnect simulator scenario
  completed with blocker; background resume simulator scenario start. Files
  inspected or touched since last update: this GFR-004 plan,
  `/tmp/gfr004_sim_private_relay_reconnect_group_recovery.log`, and the
  per-role Alice log under
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_relay_reconnect_group_recovery_0JWNGZ/alice.log`.
  Current command completed:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  exited `255`. Device proof for the command came from the preceding group
  list resolution: Alice/Bob/Charlie/Dana set
  `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
  Exact failure: Alice exited with code `1` before writing a verdict because
  `dbInsertGroupMessage` failed with `DatabaseException(... "table
  group_messages has no column named logical_delivery_id" ...)`; Bob then
  timed out waiting for
  `gmp_1780748254471_alice_sent_aliceMissedDuringRelayDrop.json`, and Charlie
  timed out waiting for `gmp_1780748254471_bob_nw004_recovered_ready`.
  Decision/blocker: this is a simulator schema/harness evidence blocker, not
  duplicate-send product evidence. Current command starting:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`.
  Next action: run the background resume simulator scenario and record pass,
  fail, or blocker with the same exactness.
- 2026-06-06 14:21:47 CEST - Phase: relay reconnect simulator scenario
  still running under the spawned Executor. Last completed command/result:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
  passed with one-device, two-device, and four-device simulator role resolution
  recorded below. Current command/log being inspected:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  with log `/tmp/gfr004_sim_private_relay_reconnect_group_recovery.log`; process
  inspection shows the scenario active, with Alice launched and Bob currently
  running through `flutter drive`. Blocker state: no active blocker; nested
  Executor no-progress classification is `not_no_progress` because it already
  added GFR-004 host acceptance tests, completed focused/direct host proof,
  completed required named gates, resolved devices, and entered mandatory
  simulator acceptance. Local sequential fallback is not active because the
  child is making observable progress and the plan remains safe. Next action:
  continue polling the spawned Executor until the relay reconnect scenario
  returns, then record that result and run or verify the required background
  resume group simulator scenario before the separate QA Reviewer pass.
- 2026-06-06 14:16:48 CEST - Phase: simulator list completed; relay
  reconnect scenario start. Files inspected or touched since last update: this
  GFR-004 plan and `/tmp/gfr004_sim_group_list.log`. Current command
  completed:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
  passed. Resolved devices: one-device
  `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; two-device
  `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`;
  intro/four-device
  `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
  Group dry-run discovered 123 planned commands and used default
  `MKNOON_RELAY_ADDRESSES`. Current command starting:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`.
  Decision/blocker: list/device-resolution proof is available; next evidence
  depends on scenario execution and whether scenario criteria expose Report
  108 failed/queued attempt identity fields. Next action: record relay
  reconnect scenario result, then run background resume scenario.
- 2026-06-06 14:16:05 CEST - Phase: completeness-check completed;
  simulator graphify/list start. Files inspected or touched since last update:
  this GFR-004 plan, `/tmp/gfr004_gate_completeness.log`, reliability-sim skill
  instructions, and graphify output. Current commands completed:
  `./scripts/run_test_gates.sh completeness-check` passed with
  `Completeness check: 769/769 test files classified. Completeness check PASS.`;
  `graphify query "Report 108 group failed retry simulator criteria private_group_failed_retry_single_copy failed queued attempt sender recipient count"`
  passed but returned broad adjacent retry/replay nodes rather than a narrow
  Report 108 simulator proof node. Current command starting:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`.
  Decision/blocker: named gates are complete; simulator acceptance now uses the
  reliability-sim helper and must record list/device-resolution proof plus
  exact scenario pass/fail/proof-field status. Next action: run group list and
  required scenario commands.
- 2026-06-06 14:15:26 CEST - Phase: baseline gate completed;
  completeness-check start. Files inspected or touched since last update: this
  GFR-004 plan and `/tmp/gfr004_gate_baseline_device.log`. Current command
  completed:
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`
  passed with host baseline `00:54 +100: All tests passed!`,
  `loading_states_smoke_test.dart` `00:04 +7: All tests passed!`, and
  `posts_phase1_fake_test.dart` `00:01 +1: All tests passed!`. Current
  command starting: `./scripts/run_test_gates.sh completeness-check`.
  Decision/blocker: selected baseline rerun resolves the prior ambiguous-device
  environment failure; no baseline product blocker remains. Next action: record
  completeness-check result, then run simulator acceptance commands.
- 2026-06-06 14:10:43 CEST - Phase: baseline gate ambiguous-device rerun
  start. Files inspected or touched since last update: this GFR-004 plan,
  `/tmp/gfr004_gate_baseline.log`, and `scripts/run_test_gates.sh` device
  selection logic. Current command completed: `./scripts/run_test_gates.sh baseline`
  exited `1` after the host baseline portion passed with
  `00:53 +100: All tests passed!`; failure output was Flutter device ambiguity:
  "More than one device connected; please specify a device with the '-d
  <deviceId>' flag" and listed multiple supported targets including
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Current command starting:
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`.
  Decision/blocker: first failure is an environment selector issue in the
  integration leg, not product evidence; the gate script's
  `integration_test_args()` uses `FLUTTER_DEVICE_ID`, so a device-selected
  baseline rerun is valid evidence. Next action: record selected baseline
  rerun result, then run completeness-check.
- 2026-06-06 14:08:31 CEST - Phase: mandatory groups/transport gates
  completed; baseline gate start. Files inspected or touched since last
  update: this GFR-004 plan and named gate logs
  `/tmp/gfr004_gate_groups.log` and `/tmp/gfr004_gate_transport.log`. Current
  commands completed: `./scripts/run_test_gates.sh groups` passed with
  `00:53 +324: All tests passed!`;
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  passed on selected simulator `iPhone 17`
  (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`), including
  `wifi_relay_fallback_smoke_test.dart` (`00:01 +1`),
  `transport_e2e_test.dart` (`00:05 +3`), and
  `media_stable_id_smoke_test.dart` (`00:09 +7`). Current command starting:
  `./scripts/run_test_gates.sh baseline`. Decision/blocker: mandatory group
  and transport gate proof is available; continue with required baseline
  whole-program confidence. Next action: record baseline result, then run
  completeness-check.
- 2026-06-06 14:07:17 CEST - Phase: orchestrator progress heartbeat while
  the spawned Executor continues GFR-004 acceptance gates. Files inspected or
  touched since last update: this GFR-004 plan only. Last completed
  command/result observed from the active Executor stream:
  `./scripts/run_test_gates.sh groups` passed with `00:53 +324: All tests
  passed!`. Current command/log being inspected: spawned Executor is running
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  with log `/tmp/gfr004_gate_transport.log`; no local log triage has started in
  this controller. Decision/blocker: nested Executor no-progress classification
  is `not_no_progress` because it already added GFR-004 host acceptance tests,
  passed direct suites, resolved devices, and entered the required named gates;
  no evidence blocker is active. Next action: continue polling the spawned
  Executor, then run the separate spawned QA Reviewer after Executor completion.
- 2026-06-06 13:58:10 CEST - Phase: Flutter device resolution completed;
  named gates start. Files inspected or touched since last update: this
  GFR-004 plan and `flutter devices --machine` output. Current command
  completed: `flutter devices --machine` passed and listed supported targets:
  physical `Pixel 6` (`21071FDF600CSC`, Android 16), physical
  `Saleh’s iPhone` (`00008030-001A6D2801BB802E`, iOS 26.5), physical
  `iPhone` (`00008110-00184D622289801E`, iOS 26.5), bootable iOS simulators
  `UP004 Alice iPhone 17 Pro iOS 26.2`
  (`5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`),
  `UP004 Bob iPhone Air iOS 26.2`
  (`279B82AE-2BB9-4924-9AAE-581870ED3FA9`),
  `UP004 Charlie iPhone 17 iOS 26.2`
  (`116B4AF6-C1A9-4F36-B929-0A7130B5E83C`),
  `Gap Closure Dana iPhone 16e iOS 26.2`
  (`CD5929A6-EA0A-421D-A6D3-55BD707E0F76`), `iPhone 17 Pro`
  (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`), `iPhone Air`
  (`347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`), `iPhone 17`
  (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`), `iPhone 16e`
  (`1B098DFF-6294-407A-A209-BBF360893485`), plus `macos` and `chrome`.
  Selected device for `transport` gate:
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (`iPhone 17`, iOS 26.1 simulator).
  Current commands starting sequentially: `./scripts/run_test_gates.sh groups`;
  `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`;
  `./scripts/run_test_gates.sh baseline`;
  `./scripts/run_test_gates.sh completeness-check`. Decision/blocker: device
  proof is available; gate failures will be classified by exact command output.
  Next action: run named gates and record pass/fail/blocker.
- 2026-06-06 13:57:39 CEST - Phase: Flutter device resolution start.
  Files inspected or touched since last update: this GFR-004 plan and direct
  suite outputs. Current command starting: `flutter devices --machine`.
  Decision/blocker: `transport` and simulator acceptance require explicit
  device proof; missing or ambiguous devices must be recorded as environment
  blockers, not success. Next action: record available target list and select a
  device id if one is usable.
- 2026-06-06 13:57:18 CEST - Phase: direct host suite sweep completed.
  Files inspected or touched since last update: this GFR-004 plan and direct
  suite temp logs under `/tmp/gfr004_*_direct.log`. Current commands completed:
  `flutter test test/features/groups/integration/group_messaging_smoke_test.dart`
  passed with `00:53 +88: All tests passed!`;
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
  passed with `00:09 +92: All tests passed!`;
  `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`
  passed with `00:01 +9: All tests passed!`;
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  passed with `00:00 +15: All tests passed!`;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  passed with `00:00 +20: All tests passed!`;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
  passed with `00:02 +142: All tests passed!`;
  `flutter test test/core/services/pending_message_retrier_test.dart`
  passed with `00:42 +23: All tests passed!`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  passed with `00:00 +16: All tests passed!`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
  passed with `00:00 +3: All tests passed!`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  passed with `00:00 +2: All tests passed!`;
  `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  passed with `00:00 +48: All tests passed!`;
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  passed with `00:17 +118: All tests passed!`;
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
  passed with `00:02 +49: All tests passed!`;
  `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
  passed with `00:01 +50: All tests passed!`. Decision/blocker: no direct
  host blocker; production remains unchanged. Next action: resolve available
  Flutter devices, run named gates, and attempt simulator acceptance commands.
- 2026-06-06 13:52:18 CEST - Phase: direct host suite sweep start.
  Files inspected or touched since last update: this GFR-004 plan and focused
  GFR-004 filter output. Current commands starting sequentially:
  `flutter test test/features/groups/integration/group_messaging_smoke_test.dart`;
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart`;
  `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`;
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart`;
  `flutter test test/core/services/pending_message_retrier_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`;
  `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`;
  `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`;
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`;
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`;
  `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`.
  Decision/blocker: direct suites are required to connect the new GFR-004 host
  acceptance to existing integration, retry, lifecycle, repository, wired UI,
  screen UI, and LetterCard coverage. Next action: record pass/fail result for
  each direct suite, then continue to device/gate/simulator evidence.
- 2026-06-06 13:52:01 CEST - Phase: remaining focused GFR-004 filters
  completed. Files inspected or touched since last update: this GFR-004 plan
  and focused filter output. Current commands completed:
  `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GFR-004"`
  exited `79` with `No tests ran. No tests match "GFR-004".`;
  `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name "GFR-004"`
  exited `79` with `No tests ran. No tests match "GFR-004".`;
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "GFR-004"`
  exited `79` with `No tests ran. No tests match "GFR-004".`.
  Decision/blocker: exact no-match filter behavior only; no product failure and
  no missing host evidence because the required GFR-004 host tests were added
  and passed in `group_resume_recovery_test.dart`. Next action: run direct host
  suites.
- 2026-06-06 13:51:23 CEST - Phase: remaining focused GFR-004 filters start.
  Files inspected or touched since last update: this GFR-004 plan and focused
  prerequisite output. Current commands starting sequentially:
  `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GFR-004"`;
  `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name "GFR-004"`;
  `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "GFR-004"`.
  Decision/blocker: the new GFR-004 tests were added to
  `group_resume_recovery_test.dart`; these filters verify whether adjacent
  files already carry additional GFR-004 labels. Next action: record exact
  pass/no-matching-test behavior before direct suites.
- 2026-06-06 13:51:05 CEST - Phase: focused prerequisite confidence
  completed. Files inspected or touched since last update: this GFR-004 plan
  and focused test output. Current commands completed:
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"`
  passed with `00:00 +3: All tests passed!`;
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`
  passed with `00:00 +4: All tests passed!`;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`
  passed with `00:00 +1: All tests passed!`;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`
  passed with `00:00 +1: All tests passed!`;
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"`
  passed with `00:01 +4: All tests passed!`;
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"`
  passed with `00:01 +3: All tests passed!`. Decision/blocker: no
  contradictory prerequisite evidence; GFR-004 can continue as
  acceptance-only. Next action: run the direct host suites required by the
  closure bar.
- 2026-06-06 13:49:52 CEST - Phase: focused prerequisite confidence start.
  Files inspected or touched since last update: this GFR-004 plan and
  `test/features/groups/integration/group_resume_recovery_test.dart`. Current
  commands starting sequentially:
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"`;
  `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`;
  `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`;
  `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`;
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"`;
  `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"`.
  Decision/blocker: prerequisite closure evidence is accepted historically, but
  GFR-004 reruns the focused slices to detect contradictory current evidence.
  Next action: record command-by-command pass/fail results before direct
  suites.
- 2026-06-06 13:47:32 CEST - Phase: focused GFR-004 host acceptance rerun
  completed. Files inspected or touched since last update:
  `test/features/groups/integration/group_resume_recovery_test.dart` and this
  GFR-004 plan. Current command completed:
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"` passed with `00:00 +3: All tests passed!`.
  Decision/blocker: formatted GFR-004 host acceptance remains green. Next
  action: run prerequisite focused GFR-001/GFR-002/GFR-003 confidence slices.
- 2026-06-06 13:47:16 CEST - Phase: Dart format completed; focused rerun
  start. Files inspected or touched since last update:
  `test/features/groups/integration/group_resume_recovery_test.dart` and this
  GFR-004 plan. Current command completed:
  `dart format test/features/groups/integration/group_resume_recovery_test.dart`
  formatted 1 file. Current command starting:
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"`.
  Decision/blocker: no formatter blocker; rerun focused GFR-004 slice after
  formatted Dart changed. Next action: record focused rerun result and advance
  to prerequisite/direct suites.
- 2026-06-06 13:47:05 CEST - Phase: Dart format start.
  Files inspected or touched since last update: this GFR-004 plan and
  `test/features/groups/integration/group_resume_recovery_test.dart`. Current
  command starting:
  `dart format test/features/groups/integration/group_resume_recovery_test.dart`.
  Decision/blocker: formatter required after GFR-004 Dart test edits. Next
  action: run formatter and then continue focused/direct validation.
- 2026-06-06 13:46:39 CEST - Phase: focused GFR-004 host acceptance
  completed. Files inspected or touched since last update:
  `test/features/groups/integration/group_resume_recovery_test.dart` and this
  GFR-004 plan. Current command completed:
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"` passed with `00:00 +3: All tests passed!`.
  Decision/blocker: no host acceptance blocker found for the added GFR-004
  tests; production remains unchanged. Next action: run formatter on the
  touched Dart test, then continue required direct/prerequisite suites and
  named gates.
- 2026-06-06 13:46:10 CEST - Phase: focused GFR-004 host acceptance start.
  Files inspected or touched since last update:
  `test/features/groups/integration/group_resume_recovery_test.dart` and this
  GFR-004 plan. Current command starting:
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"`.
  Decision/blocker: added only GFR-004-labeled host acceptance tests and a
  test-only fake bridge publish-response queue; no production files changed.
  Next action: run the focused host acceptance slice, then either fix
  GFR-001..GFR-003-surface regressions or record exact test failure evidence.
- 2026-06-06 13:45:00 CEST - Phase: nested Executor partial file evidence.
  Files inspected or touched since last update: process list,
  `/tmp/gfr004-executor-final.txt`, scoped diff stats, `rg -n "GFR-004"` in
  `group_resume_recovery_test.dart`, and this GFR-004 plan. Last completed
  command/result: scoped diff stat now shows a 57-line test-only helper change
  in `test/features/groups/integration/group_resume_recovery_test.dart`
  (pending-message retrier/node-state imports, publish response queue support,
  and GFR-004 helper functions); no production files changed and no final
  Executor output exists. Current command/log being inspected: spawned
  Executor remains active as PIDs 84968/84969 for about 7m59s, with no current
  child command visible in this controller. Decision/blocker:
  `executor_active_partial_file_evidence`; this is not yet a trustworthy
  Executor result because no `GFR-004`-labeled tests, required command results,
  coverage ledger, or simulator evidence have landed. Next action: allow one
  more short bounded wait for the child to land the promised acceptance tests
  or final summary; if it stalls again, stop the child, classify
  `spawn_or_tool_failure`, inspect the partial test helper for safe reuse or
  cleanup, and continue only through a bounded local fallback if no hidden
  state ambiguity remains.
- 2026-06-06 13:43:00 CEST - Phase: nested Executor bounded wait
  extension. Files inspected or touched since last update: active Executor
  stream, process list, `/tmp/gfr004-executor-final.txt`, scoped diff stats,
  and this GFR-004 plan. Last completed command/result observed from the child
  stream: owner-path inspection of `pending_message_retrier.dart`,
  `send_group_message_use_case.dart`, and `bridge_group_helpers.dart`
  completed while designing deterministic GFR-004 acceptance tests. Current
  command/log being inspected: spawned Executor process remains active as PIDs
  84968/84969 for about 5m51s; no final-output file exists and no scoped
  GFR-004 test/harness diff has landed yet. Decision/blocker:
  `executor_active_pending_file_evidence`; not yet `spawn_or_tool_failure`
  because the first bounded interval produced fresh assigned-step inspection
  progress, but the next wait must produce file-backed evidence or a
  trustworthy final summary. Next action: allow one additional bounded wait;
  if no file-backed Executor result appears, classify nested Executor
  no-progress and continue through the local sequential fallback inside this
  GFR-004 execution child.
- 2026-06-06 13:42:00 CEST - Phase: nested Executor state check.
  Files inspected or touched since last update: this GFR-004 plan, process
  list for `codex exec`, `/tmp/gfr004-executor-final.txt`, and scoped diff
  stats for the GFR-004 plan/breakdown, `group_resume_recovery_test.dart`, and
  simulator criteria/harness files. Last completed command/result:
  `ps -axo ... | rg 'codex .*gfr004|gfr004-executor|019e9cb9|codex.*exec'`
  showed the spawned Executor still running as PIDs 84968/84969 for about
  4m38s; `/tmp/gfr004-executor-final.txt` did not exist or was empty; scoped
  diff stat for expected GFR-004 test/harness files was empty except this plan
  heartbeat. Current command/log being inspected: no child command output is
  currently being tailed; the active child process is the current evidence
  source. Decision/blocker: `executor_active_pending_result`; do not classify
  no-progress yet because the child materialized, updated this plan, ran
  graphify, inspected owner files, and reported concrete GFR-004 test gaps
  before the interruption. Next action: wait one bounded interval for child
  file-backed evidence or final summary; if no repo evidence or trustworthy
  result appears, classify `spawn_or_tool_failure` and use the local
  sequential fallback only if the plan remains safe.
- 2026-06-06 13:41:00 CEST - Phase: parent progress request heartbeat.
  Files inspected or touched since last update: this GFR-004 plan only.
  Last completed command/result observed from the nested Executor stream:
  helper/owner-file inspection around `group_resume_recovery_test.dart`,
  `pending_message_retrier_test.dart`, and `handle_app_resumed` call sites
  completed successfully; the Executor reported concrete host gaps and stated
  it was adding narrow GFR-004 acceptance tests in
  `group_resume_recovery_test.dart`. Current command/log being inspected: none
  yet after the user interruption; the nested Executor process state and any
  landed file evidence have not yet been rechecked. Decision/blocker:
  `pending_executor_state_check`; no product blocker or no-progress
  classification is justified from the last observed stream because the child
  had materialized and was making scoped progress. Next action: inspect the
  nested Executor process/final-output state and current scoped diffs, then
  either wait for a trustworthy Executor result, classify
  `spawn_or_tool_failure`, or use the execution-QA local sequential fallback
  inside this GFR-004 child if the plan remains safe.
- 2026-06-06 13:38:44 CEST - Phase: graphify-first code/test context
  completed. Files inspected or touched since last update: graphify result and
  this GFR-004 plan. Current command completed: `graphify query "GFR-004 group failed retry auto recovery integration simulator sender recipient history"`
  passed and returned scoped hits for
  `test/integration/group_multi_party_device_criteria_test.dart` plus adjacent
  sender-history nodes. Decision/blocker: graph result is too narrow for all
  host owner files but sufficient to direct simulator criteria inspection;
  continue with the plan-listed owner tests and criteria only. Next action:
  inspect accepted GFR-001/GFR-002/GFR-003 closure notes, host integration
  tests, and simulator criteria fields.
- 2026-06-06 13:38:42 CEST - Phase: graphify-first code/test context.
  Files inspected or touched since last update: this GFR-004 plan. Current
  command starting: `graphify query "GFR-004 group failed retry auto recovery integration simulator sender recipient history"`.
  Decision/blocker: pending graph context; no raw owner-file source browsing
  will start until the graph query returns or records a tool blocker. Next
  action: use the scoped graph result to inspect only owner tests and simulator
  criteria needed for the GFR-004 coverage ledger.
- 2026-06-06 13:38:19 CEST - Phase: Executor-start intake.
  Files inspected or touched since last update: this GFR-004 plan, Report 108
  source doc, session breakdown GFR-004 row, prior GFR-001/GFR-002/GFR-003
  closure-note locations, test-gate definitions, gate scripts, and current
  `git status --short`. Current command: none. Decision/blocker: no
  execution-start blocker; scope remains acceptance-only, unrelated dirty docs,
  untracked agent files, `info.plist` timestamp churn, and prior Report 108
  code/test diffs are preserved as baseline. Next action: inspect accepted
  prerequisite closure evidence, graphify-first code/test context, host
  integration coverage, and simulator proof fields before adding any GFR-004
  acceptance tests.
- 2026-06-06 13:37:45 CEST - Phase: Executor spawn retry.
  Files inspected or touched since last update: this GFR-004 plan. Current
  command completed: `codex exec ... -a never ...` failed before child
  materialization because `-a` is a top-level Codex CLI option, not an
  `exec` subcommand option. Decision/blocker: no GFR-004 product or evidence
  blocker; this is a launch syntax correction before any Executor work.
  Next action: relaunch Executor with `codex -a never exec ...`.
- 2026-06-06 13:36:02 CEST - Phase: execution controller intake.
  Files inspected since last update: execution-QA orchestrator skill tail,
  GFR-004 plan exact test/gate sections, source doc acceptance evidence,
  breakdown GFR-004 ledger row, `git status --short`, `codex exec --help`,
  and graph presence check. Current command: none. Decision/blocker: no
  execution-start blocker; nested spawned agents are available through
  `codex exec`, graphify-out/graph.json exists, and the dirty tree is
  pre-existing/unrelated except prior Report 108 surfaces. Next action: spawn
  fresh GFR-004 Executor with `model: gpt-5.5` and
  `reasoning_effort: xhigh`.
- 2026-06-06 13:33:24 CEST - Phase: execution contract extracted.
  Files inspected since last update: execution-QA orchestrator skill, GFR-004
  execution-ready plan, current `git status --short`, and breakdown GFR-004
  ledger row. Current command: none. Decision/blocker: no blocker to start;
  scope is acceptance-only for GFR-004, required proof includes host
  integration/direct/named gates plus mandatory relay reconnect/background
  resume simulator evidence, and GFR-005 remains out of scope. Next action:
  spawn a fresh Executor for coverage inspection, minimal missing GFR-004 proof,
  required tests/gates, graph refresh after modifications, and file-backed
  evidence recording.
- 2026-06-06 13:31:56 CEST - Phase: execution/QA launch. Files inspected since
  last update: GFR-004 execution-ready plan header, breakdown GFR-004 ledger row,
  stale planner process check, and execution-QA orchestrator contract.
  Current command: none yet. Decision/blocker: no execution-start blocker; no
  active GFR-004 planning process remains after reconciliation, the plan is
  `Status: execution-ready`, and the breakdown row is `execution-ready`. Next
  action: launch a fresh GFR-004 execution/QA orchestrator child from this plan;
  keep GFR-005 untouched until GFR-004 closes or records an exact blocker.

## real scope

GFR-004 is an acceptance-only session for the behavior already landed by
GFR-001, GFR-002, and GFR-003. It verifies the whole group failed-message
recovery journey across sender UI, retry identity, pending/in-doubt recovery,
relay/readiness auto recovery, app resume, reaction replay ownership, open
conversation row updates, named gates, and simulator-backed sender/recipient
history.

Allowed work:

- inspect and run existing focused, integration, named-gate, and simulator
  evidence
- add or extend GFR-004-labeled host integration tests when a required
  acceptance item has no direct proof
- add or extend simulator harness/criteria fields only when existing
  multi-party scenarios do not prove the Report 108 failed/queued attempt as
  one sender-visible and one recipient-visible delivery
- make production fixes only for defects discovered by GFR-004 acceptance
  evidence, and only inside the already-owned GFR-001 through GFR-003 behavior
  surface
- update this GFR-004 plan and the GFR-004 breakdown ledger row during
  execution/closure

Out of scope:

- do not reopen GFR-001, GFR-002, or GFR-003 only because their accepted
  residuals mention GFR-004
- do not plan or close GFR-005
- do not write the final stable Report 108/source closure verdict
- do not change group wire protocol, relay-side dedupe, reaction UX semantics,
  media retry/delete UX, membership/key repair, notification routing, or 1:1
  retry behavior unless a GFR-004 proof exposes a direct regression caused by
  the prior Report 108 changes

## closure bar

GFR-004 is closeable only when every coverage row below has recorded evidence or
an exact blocker. Host tests alone are insufficient because GFR-004 owns the
GFR-002 explicit follow-up for whole-journey group simulator acceptance across
relay reconnect/background resume delivery.

| GFR-004 requirement | Required proof |
| --- | --- |
| Failed text recovery settles one original row | Existing GFR-001/GFR-003 focused tests plus a GFR-004 integration proof in `group_resume_recovery_test.dart` or `group_messaging_smoke_test.dart` showing one sender row and one recipient copy after failure plus retry. |
| Retry-plus-Send for the same visible failed text does not duplicate | Existing GFR-003 wired proof plus a GFR-004 integration test if no current test drives the combined UI/repository/send path. |
| Rapid Retry and manual/automatic overlap coalesce | Existing GFR-001/GFR-002 focused tests plus host integration proof that retrier and row retry target the same attempt. |
| Send while offline queues once and auto-delivers on reconnect | GFR-002 focused tests plus GFR-004 host integration and simulator proof. |
| Pending/in-doubt row recovers and is not stranded or duplicated | Existing GFR-001/GFR-002 retry tests plus GFR-004 integration proof for the recipient-visible result. |
| Multiple queued texts deliver once each and in order | GFR-004 host integration proof in `group_resume_recovery_test.dart` or `group_edge_cases_smoke_test.dart`; simulator proof if the added/extended scenario supports it, otherwise record why host order proof is accepted and simulator covers single-attempt lifecycle. |
| App resume and relay-ready recovery coalesce | Existing lifecycle/retrier tests plus the `private_background_resume_group_delivery` simulator scenario or a Report 108-specific simulator extension. |
| Active `GroupRecoveryGate` and announcement `group_recovery_pending` do not create a fresh duplicate attempt | Existing lifecycle/UI proof plus GFR-004 integration assertion if no current integration test crosses send/retry with the gate. |
| Open conversation observes queued/retrying/sent/failed state in place | Existing GFR-003 wired proof plus direct wired/screen suite reruns; add no simulator requirement for this UI-only observation unless a simulator harness exposes row state. |
| `retryFailedGroupInboxStores(...)` preserves message-first and reaction replay ownership | Existing direct suite plus GFR-004 acceptance note; add a GFR-004-labeled direct test only if execution changes inbox-store/reaction behavior. |
| Failed media controls and text rows avoid media controls | Existing GFR-003 screen/LetterCard proof plus direct suite reruns. |
| Receiver-side message-id/logical-delivery dedupe remains observable | Existing GFR-001/GFR-002 tests plus named `groups` gate; add integration proof only if new GFR-004 host tests expose a gap. |
| Distinct intentional same-text messages remain possible after recovery settles | Existing GFR-001 direct proof; rerun the direct suite as regression evidence. |
| Existing resume recovery order remains intact | `handle_app_resumed_group_recovery_test.dart`, `pending_message_retrier_test.dart`, and `./scripts/run_test_gates.sh transport`. |
| Whole-journey simulator sender/recipient history confirms one copy | Mandatory `$run-flutter-reliability-sims` group list plus existing `private_relay_reconnect_group_recovery` and `private_background_resume_group_delivery`; add or extend a Report 108-specific scenario if those do not assert failed/queued attempt identity and sender/recipient counts. |

If simulator/device resolution is unavailable, GFR-004 must not be marked
closed. Persist the exact command, device count found, device count required,
and failure output in this plan and in the breakdown ledger as an
`evidence-gated` or blocked acceptance result.

## GFR-004 coverage ledger

Execution result: accepted. Host and named-gate evidence remains complete and
green, and the mandatory whole-journey simulator proof now passes on the
available simulator set after the version-74 migration alignment,
offline-drain proof retry, and direct-fixture invitee join-state harness fix.
The prior missing `group_messages.logical_delivery_id` schema failure did not
recur, and the prior Bob received-proof absence is cleared by the accepted
simulator reruns recorded below.

| GFR-004 requirement | Execution evidence / blocker |
| --- | --- |
| Failed text recovery settles one original row | Covered by new `test/features/groups/integration/group_resume_recovery_test.dart` test `GFR-004 failed retry plus auto recovery settles one group text once`. Focused command `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"` passed twice (`00:00 +3`) before and after `dart format`. Direct suite `flutter test test/features/groups/integration/group_resume_recovery_test.dart` passed (`00:09 +92`). The test asserts initial failed row, one successful retry, exactly one sender row, and one Bob/Charlie recipient copy. |
| Retry-plus-Send for the same visible failed text does not duplicate | Covered by prerequisite GFR-003 focused/direct proof plus the new GFR-004 manual/auto overlap integration test above. Focused GFR-003 reruns passed for `group_conversation_wired_test.dart --plain-name "GFR-003"` (`00:01 +4`) and `group_conversation_screen_test.dart --plain-name "GFR-003"` (`00:01 +3`); direct wired/screen suites passed (`00:17 +118`, `00:02 +49`). |
| Rapid Retry and manual/automatic overlap coalesce | Covered by new `GFR-004 failed retry plus auto recovery settles one group text once`: manual retry is held behind `group:publish`, `handleAppResumed` invokes auto recovery during the in-flight retry, manual retry returns `1`, resume retry returns `0`, and only initial failure plus one retry publish exist for the message id. Focused GFR-001/GFR-002 reruns also passed. |
| Send while offline queues once and auto-delivers on reconnect | Host covered by new `GFR-004 send while offline auto delivers once after reconnect`, focused `GFR-004` pass, direct `group_resume_recovery_test.dart` pass, and GFR-002 focused reruns. The test forces `NO_USABLE_TRANSPORT`, emits relay-ready `NodeState`, verifies one auto retry call, one retried failed row, two publishes total for the same message id, and one sender/Bob/Charlie copy. Simulator portion blocked by the mandatory scenario failures recorded below. |
| Pending/in-doubt row recovers and is not stranded or duplicated | Covered by prerequisite retry suites plus the new GFR-004 recipient-visible assertions. Focused reruns passed: `retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"` (`00:00 +3`), `pending_message_retrier_test.dart --plain-name "GFR-002"` (`00:00 +4`), `send_group_message_use_case_test.dart --plain-name "GFR-002"` (`00:00 +1`), and `retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"` (`00:00 +1`). Direct retry/retrier suites passed as recorded in Execution Progress. |
| Multiple queued texts deliver once each and in order | Host covered by new `GFR-004 multiple offline queued texts deliver once each in order`. It forces two offline `NO_USABLE_TRANSPORT` sends, reconnect auto retry, one auto retry call, two retried rows, publish sequence `[first, second, first, second]`, and sender/Bob/Charlie visible ids `[first, second]`. Simulator order proof is not available because the required scenarios failed before verdict. |
| App resume and relay-ready recovery coalesce | Host/lifecycle covered by the new manual/auto overlap test, `PendingMessageRetrier` direct suite (`00:42 +23`), and lifecycle direct suites: `handle_app_resumed_group_recovery_test.dart` (`00:00 +16`), `handle_app_resumed_group_inbox_retry_test.dart` (`00:00 +3`), and `handle_app_resumed_group_stuck_sending_test.dart` (`00:00 +2`). Mandatory background simulator portion is blocked by the `private_background_resume_group_delivery` failure below. |
| Active `GroupRecoveryGate` and announcement `group_recovery_pending` do not create a fresh duplicate attempt | Covered by existing lifecycle/UI proof and direct suites; no GFR-004 production defect exposed. GFR-003 focused/direct wired and screen suites passed, and the new manual/auto overlap test proves an active recovery attempt suppresses the duplicate retry path for the same message id. |
| Open conversation observes queued/retrying/sent/failed state in place | Covered by GFR-003 focused/direct reruns: wired focused `00:01 +4`, screen focused `00:01 +3`, wired direct `00:17 +118`, screen direct `00:02 +49`. No simulator UI row-state proof required by plan. |
| `retryFailedGroupInboxStores(...)` preserves message-first and reaction replay ownership | Covered by unchanged direct suite `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` (`00:00 +15`). The GFR-004 plain-name filter for this file exited `79` because no tests are GFR-004-labeled there; this is not a gap because GFR-004 did not change inbox-store/reaction behavior. |
| Failed media controls and text rows avoid media controls | Covered by GFR-003 screen/direct proof plus `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart` (`00:01 +50`). GFR-004 did not change media controls. |
| Receiver-side message-id/logical-delivery dedupe remains observable | Covered by prerequisite GFR-001/GFR-002 focused tests, new GFR-004 sender/Bob/Charlie one-copy assertions, direct `group_edge_cases_smoke_test.dart` (`00:01 +9`), and mandatory `./scripts/run_test_gates.sh groups` (`00:53 +324`). |
| Distinct intentional same-text messages remain possible after recovery settles | Covered by accepted GFR-001 proof and direct `flutter test test/features/groups/application/send_group_message_use_case_test.dart` (`00:02 +142`). No contradictory GFR-004 evidence. |
| Existing resume recovery order remains intact | Covered by lifecycle/retrier direct suites and mandatory selected-device transport gate. `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport` passed, including `wifi_relay_fallback_smoke_test.dart` (`00:01 +1`), `transport_e2e_test.dart` (`00:05 +3`), and `media_stable_id_smoke_test.dart` (`00:09 +7`). |
| Whole-journey simulator sender/recipient history confirms one copy | Accepted. `run_with_devices.sh group --list` passed and resolved one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`, and four-device `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`. The stale schema blocker is cleared: Alice, Bob, and Charlie all emitted `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` in both accepted scenarios, and per-role log inspection found no `DatabaseException` or `no column named logical_delivery_id`. `private_relay_reconnect_group_recovery` run `1780758396971` passed with orchestrator verdict `ok:true`; Alice's `GROUP_PUBLISH_DEBUG` for `gmp_1780758396971_private_relay_reconnect_group_recovery_aliceMissedDuringRelayDrop_alice` showed `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and `inboxStored:true`; Bob wrote `gmp_1780758396971_bob_received_aliceMissedDuringRelayDrop.json` with `usedOfflineDrain:true`, `liveOnly:false`, and `persistedCount:1`; Alice, Bob, and Charlie verdict JSONs were written. `private_background_resume_group_delivery` run `1780758894898` passed with orchestrator verdict `ok:true`; Alice's `GROUP_PUBLISH_DEBUG` for `gmp_1780758894898_private_background_resume_group_delivery_aliceDuringBackgroundBeforeEdit_alice` showed `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and `inboxStored:true`; Bob wrote `gmp_1780758894898_bob_received_aliceDuringBackgroundBeforeEdit.json` with `usedOfflineDrain:true`, `liveOnly:false`, and `persistedCount:1`; Alice, Bob, and Charlie verdict JSONs were written. Together with accepted GFR-001/GFR-002/GFR-003 host proof for stable attempt identity, row-scoped retry coalescing, queued auto recovery, and open-conversation one-row UX, these simulator runs satisfy GFR-004 whole-journey lifecycle acceptance. |

## source of truth

- Primary session contract:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`,
  session `GFR-004`.
- Product acceptance source:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`.
- Accepted prerequisite inputs:
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-001-plan.md`,
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-002-plan.md`,
  and
  `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-GFR-003-plan.md`.
- Named gate source:
  `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with
  `scripts/run_test_gates.sh`, the script wins.
- Simulator runner source:
  `/Users/I560101/.codex/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`,
  `scripts/run_reliability_simulations.sh`,
  `integration_test/scripts/run_group_multi_party_device_real.dart`, and
  `integration_test/scripts/group_multi_party_device_criteria.dart`.
- Current code and tests win over stale prose. Dirty/untracked unrelated files
  are not evidence against GFR-004 and must not be reverted.

Graphify evidence used before raw source browsing:

- `graphify query` for group failed-message retry lifecycle acceptance surfaced
  lifecycle/retry persistence concepts but was broad.
- `graphify query` for retry inbox-store/reaction replay surfaced
  `retry_failed_group_inbox_stores_use_case.dart` and its
  `GroupReactionReplayOutboxRepository` relationship.
- `graphify explain` confirmed `handleAppResumed`, `PendingMessageRetrier`,
  `retryFailedGroupMessages`, `GroupRecoveryGate`, and
  `group_recovery_e2e_test.dart` nodes.
- `graphify path` connected `PendingMessageRetrier` to `handleAppResumed`
  through `group_recovery_gate.dart`, and connected
  `handleAppResumed` to `retryFailedGroupMessages` through group repository
  imports.

## session classification

`acceptance-only`

The plan is execution-ready for acceptance work. It is not a product
implementation plan and it is not a GFR-005 closure plan.

## exact problem statement

Report 108 is not complete until the already-landed lower-layer retry identity,
readiness auto recovery, and open-conversation UI behavior are proven together.
The specific risk is that the same group text intent could still be sent once
by manual retry, once by a restored composer/send-now path, once by relay-ready
recovery, or once by app-resume recovery, especially around reconnect,
background/foreground, pending rows, reaction replay draining, and open
conversation row updates.

GFR-004 must prove the user-visible journey: a failed, queued, or in-doubt
group text attempt stays represented once, recovers without extra user
management when appropriate, and appears once in sender and recipient histories
after recovery. Existing GFR-001, GFR-002, and GFR-003 closure notes are
accepted inputs; this session must not re-litigate them except on a concrete
acceptance failure.

## files and repos to inspect next

Acceptance docs and gates:

- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux.md`
- `Test-Flight-Improv/108-group-failed-message-retry-duplicate-send-ux-session-breakdown.md`
- GFR-001/GFR-002/GFR-003 plan files listed above
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `scripts/run_reliability_simulations.sh`
- `/Users/I560101/.codex/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`

Host integration and direct test files:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`

Production files to inspect only for defect triage:

- `lib/core/services/pending_message_retrier.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/p2p/domain/models/node_state.dart`
- `lib/features/groups/application/group_recovery_gate.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`

Simulator files:

- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/scripts/run_group_recovery_e2e.dart`

## existing tests covering this area

- GFR-001 closure accepted focused/direct proof for same-row retry coalescing,
  pending retry eligibility, stable message/logical delivery identity, settled
  row no-op behavior, receiver duplicate suppression, failed media boundaries,
  `groups` gate, graph refresh, and diff hygiene.
- GFR-002 closure accepted focused/direct proof for `PendingMessageRetrier`
  readiness return, readiness flapping, external app-resume suppression,
  `enableResumeGroupRecovery` behavior, no-transport queued retryable row,
  `groups` gate, device-selected `transport` gate, graph refresh, and diff
  hygiene. It explicitly deferred whole-journey simulator acceptance to GFR-004.
- GFR-003 closure accepted focused/direct proof for clearing the duplicate
  composer path, row-scoped retry in-flight state, retry disabled under active
  recovery gate, failed media preservation, quote/draft handling, open
  conversation local status updates, `groups` gate, graph refresh, and diff
  hygiene.
- `group_resume_recovery_test.dart` already has host integration coverage for
  full lifecycle round-trip and failed message retry after network recovery.
- `group_edge_cases_smoke_test.dart` and `group_messaging_smoke_test.dart`
  contain duplicate-delivery and high-fanout group assertions that protect
  receiver history against duplicate rows.
- `retry_failed_group_inbox_stores_use_case_test.dart` already covers pending
  inbox-store retry, idempotent pending retry, message rows before reaction
  replay rows, reaction replay success/failure, and legacy row skips.
- The group multi-party simulator criteria already validate three-role
  `private_relay_reconnect_group_recovery` and
  `private_background_resume_group_delivery`, including
  `duplicateVisibleMessageCount == 0`, route/lifecycle diagnostics without full
  peer IDs, and sender/recipient delivery classifications.

Missing or not yet accepted for GFR-004:

- explicit GFR-004 host proof for the combined Retry-plus-Send/manual-plus-auto
  group journey if no existing test now drives that exact combined path
- explicit GFR-004 host proof for multiple offline queued texts delivered once
  each and in order after reconnect
- explicit simulator proof that the failed/queued Report 108 attempt itself is
  the message counted once in sender and recipient histories; the existing
  NW-004/NW-010 scenarios prove lifecycle delivery and no visible duplicates,
  but execution must inspect whether they expose the failed/queued attempt
  identity fields needed for Report 108 closure

## regression/tests to add first

GFR-004 should add acceptance tests only where inspection finds no existing
equivalent proof. Add tests before any production fix.

1. In `test/features/groups/integration/group_resume_recovery_test.dart`, add
   `GFR-004 failed retry plus auto recovery settles one group text once` if no
   current test overlaps failed retry with automatic readiness/app-resume
   recovery. Assert one sender row id, one Bob row id, one Charlie row id, and
   no fresh composer/send row for the same text.
2. In `test/features/groups/integration/group_resume_recovery_test.dart`, add
   `GFR-004 send while offline auto delivers once after reconnect` if current
   coverage does not assert queued row identity plus automatic recovery. Assert
   no user retry is required, the original row settles, and recipient histories
   contain one copy.
3. In `test/features/groups/integration/group_edge_cases_smoke_test.dart` or
   `group_resume_recovery_test.dart`, add `GFR-004 multiple offline queued texts
   deliver once each in order` if existing high-fanout/offline tests do not
   prove the queued-send ordering requirement.
4. In `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`,
   add a `GFR-004`-prefixed assertion only if execution changes
   `retryFailedGroupInboxStores(...)` or discovers that existing message-first
   and reaction replay tests do not cover the Report 108 ownership boundary.
5. In the simulator harness, first inspect whether
   `private_relay_reconnect_group_recovery` and
   `private_background_resume_group_delivery` can expose the specific
   failed/queued attempt id, sender visible count, recipient visible count, and
   duplicate count. If not, extend their proof fields or add one targeted
   scenario named `private_group_failed_retry_single_copy`. Do not add a new
   multi-device runner; use the existing
   `integration_test/scripts/run_group_multi_party_device_real.dart` and
   criteria flow.

## step-by-step implementation plan

1. Reconcile the current dirty tree without reverting unrelated work. Record a
   pre-execution `git status --short` summary in GFR-004 execution notes.
2. Inspect the GFR-001/GFR-002/GFR-003 closure sections and treat their
   focused/direct/named-gate evidence as accepted prerequisite input.
3. Inspect the current host integration tests listed above and fill the
   GFR-004 coverage ledger with "covered by existing test", "add GFR-004 test",
   or "simulator-only proof required" for every row.
4. Add only missing GFR-004-labeled host acceptance tests. Do not edit
   production code during this step.
5. Run focused `--plain-name "GFR-004"` host tests if any are added. If no
   GFR-004-labeled tests are added, run the exact existing focused tests named
   under "exact tests and gates to run" and record that no new host test was
   necessary for the item.
6. Run the direct suites for GFR-001 through GFR-003 owner surfaces that are
   still relevant to the whole journey.
7. Inspect simulator scenario criteria and proof fields. Run the group
   reliability list pass, then the two required existing group multi-party
   scenarios. If they lack Report 108 failed/queued attempt fields, add or
   extend the simulator proof first and run that targeted scenario.
8. Run named gates: `groups`, device-selected `transport`, `baseline`, and
   `completeness-check` when required by added tests or gate-doc edits.
9. If an acceptance test fails because product behavior regressed inside the
   GFR-001 through GFR-003 surface, fix the smallest responsible code path and
   rerun the failed focused test, affected direct suite, named gate, and
   simulator proof. Record why the fix stayed within GFR-004 acceptance scope.
10. If evidence cannot safely proceed because required simulators/devices,
    relay fixture, or scenario harness fields are unavailable, stop and persist
    the exact blocker in this plan and in the GFR-004 breakdown ledger. Do not
    mark GFR-004 closed.
11. After code/test/doc changes, run `dart format` on touched Dart files,
    `graphify update .`, and `git diff --check`.
12. Update only the GFR-004 breakdown ledger row after execution/closure. Leave
    final stable Report 108 docs and final program verdict to GFR-005.

## risks and edge cases

- Simulator scenarios may prove general reconnect/resume delivery but not the
  exact failed/queued Report 108 attempt identity; that gap requires harness
  extension before closure.
- Multiple Flutter targets can make `transport` or simulator runs fail before
  tests start. Use explicit device selection and classify the initial ambiguity
  as environment setup, not product regression.
- A host integration test can falsely pass by checking only sender state.
  GFR-004 must assert sender and recipient histories for single-copy closure.
- Reaction replay shares `retryFailedGroupInboxStores(...)`; message retry
  acceptance must not absorb reaction rows or reclassify them as message sends.
- Active `GroupRecoveryGate` and `enableResumeGroupRecovery` flag behavior must
  remain explicit. Ambiguous half-enabled recovery is not acceptable evidence.
- If a GFR-004 proof requires product changes outside GFR-001 through GFR-003,
  record a blocker rather than expanding scope.

## exact tests and gates to run

Focused prerequisite confidence:

```bash
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"
flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"
```

Focused GFR-004 host acceptance, if GFR-004 tests are added:

```bash
flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"
flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GFR-004"
flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name "GFR-004"
flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name "GFR-004"
```

Direct suites:

```bash
flutter test test/features/groups/integration/group_messaging_smoke_test.dart
flutter test test/features/groups/integration/group_resume_recovery_test.dart
flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart
flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/core/services/pending_message_retrier_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart
flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/conversation/presentation/widgets/letter_card_test.dart
```

Named gates:

```bash
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

`groups` is mandatory. `transport` is mandatory because GFR-004 closes
reconnect/resume acceptance. `baseline` is required for whole-program
confidence after presentation/startup wiring changed in the prior sessions
unless execution records a specific reason it is redundant. `completeness-check`
is mandatory if any new test file, integration test classification, simulator
scenario, or gate definition changes.

Resolve `<device-id>` from the GFR-004 execution environment before running the
transport gate. Prefer the reliability helper's environment output or
`flutter devices --machine`; record the selected device id, the available
target list, and any initial no-device or ambiguous-device failure in execution
notes.

Simulator acceptance:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery
```

If a Report 108-specific scenario is added:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_group_failed_retry_single_copy
```

Hygiene:

```bash
dart format <touched dart files>
graphify update .
git diff --check
```

## known-failure interpretation

- Unrelated dirty docs under
  `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/`,
  untracked agent files, and pre-existing graphify outputs are not GFR-004
  regressions and must not be reverted.
- `info.plist` simulator/Xcode `LastAccessedDate` timestamp churn is unrelated
  unless GFR-004 execution intentionally edits app metadata.
- A failure in a new GFR-004 test is a GFR-004 acceptance issue until proven to
  be a stale assertion or missing test fixture.
- A failure in an existing GFR-001/GFR-002/GFR-003 direct suite after
  acceptance-only changes is likely an unintended regression in the landed
  behavior; do not broaden GFR-004 beyond the failed accepted surface.
- A simulator runner failure before test launch due to device discovery,
  missing booted devices, or relay env setup is an environment blocker. Record
  the exact command, exit code, discovered devices, and required role count.
- A simulator scenario that passes without sender and recipient history counts
  for the Report 108 attempt is incomplete evidence, not a pass.
- Known gate failures documented outside group/retry/lifecycle/presentation
  surfaces should be recorded and left to their owner unless the failure is
  caused by GFR-004 changes.

## done criteria

- The coverage ledger in this plan is updated during execution with exact
  passing proof or exact blockers for every GFR-004 requirement.
- Existing GFR-001, GFR-002, and GFR-003 focused proof is rerun or explicitly
  accepted from closure notes with no contradictory current evidence.
- Any missing GFR-004 host acceptance tests are added first and pass.
- Direct suites for group integration, retry, lifecycle, repository, wired UI,
  screen UI, and LetterCard pass or have exact unrelated known-failure
  classification.
- `./scripts/run_test_gates.sh groups`, device-selected `transport`, and
  required baseline/completeness gates pass or have exact blockers recorded.
- Simulator evidence includes at least one relay reconnect group journey and
  one background resume group journey, and either those scenarios or a
  GFR-004-specific scenario prove the Report 108 failed/queued attempt appears
  once in sender and recipient histories.
- `graphify update .` and `git diff --check` complete after modifications.
- The GFR-004 breakdown ledger row is updated to `closed` only after closure
  audit. During planning, it is updated to `execution-ready`.

## scope guard

Do not:

- plan or execute GFR-005
- rewrite final stable Report 108 docs
- add a second background recovery owner
- add new relay-side dedupe or group wire protocol semantics
- weaken simulator criteria to make a lifecycle scenario pass
- collapse sender-only and recipient-visible evidence into one assertion
- treat missing devices as success
- remove red tests from gate membership to make gates green
- revert unrelated dirty/untracked work

## accepted differences / intentionally out of scope

- GFR-004 can accept host integration proof for multiple queued message order
  if simulator proof covers the single-attempt lifecycle journey and the plan
  records why multi-message ordering is host-only.
- GFR-004 does not need to polish UI copy. GFR-003 accepted the visible retry
  label and row disabled semantics.
- GFR-004 does not need to change reaction UX. It only verifies the
  `retryFailedGroupInboxStores(...)` message-first and reaction replay boundary.
- GFR-004 does not produce the final Report 108 stable-source verdict. GFR-005
  owns that closure doc reconciliation.

## dependency impact

- GFR-004 depends on GFR-001 stable same-attempt retry identity.
- GFR-004 depends on GFR-002 readiness-driven queued recovery and app-resume
  coalescing.
- GFR-004 depends on GFR-003 open-conversation row recovery UX.
- GFR-005 must not start until GFR-004 has a closure verdict or an exact
  evidence blocker.
- If GFR-004 finds a real regression in the accepted prerequisite scope, the
  downstream GFR-005 final verdict must wait for the fix and rerun evidence.

## sufficiency review

Reviewer finding: sufficient with one required adjustment already included in
this draft. The plan names exact source docs, files, direct suites, named
gates, simulator commands, known-failure interpretation, and item-by-item
coverage. The structural risk is simulator overclaiming: the existing NW-004
and NW-010 scenarios prove lifecycle delivery and no visible duplicates, but
GFR-004 must inspect or extend them so the failed/queued Report 108 attempt
identity is the counted message. The plan records that as mandatory before
closure.

Missing files/tests/gates: none structurally. Execution may add
GFR-004-labeled host tests or a simulator scenario only after inspecting whether
existing coverage is equivalent.

Overengineering check: no new recovery architecture, no broad refactor, and no
final stable doc rewrite are planned.

## arbiter decision

Structural blockers: none.

Incremental details:

- Prefer extending existing host integration tests and simulator criteria before
  adding new files.
- Keep simulator scenario additions under the existing
  `run_group_multi_party_device_real.dart` runner.

Accepted differences:

- Host proof may cover multi-message queued ordering if simulator proof covers
  the required single-attempt lifecycle journey.
- GFR-005 final source-doc closure remains intentionally out of scope.

Decision: `execution-ready`.

## Final Execution Verdict

Final execution verdict: `accepted`

Verdict scope: GFR-004 execution only. This is not a final Report 108 program
verdict and does not close the source proposal. GFR-005 is now unblocked and
owns final stable source/closure docs plus the final Report 108 program
verdict.

Blocker class: `none`

Exact blocker: none.

Passing focused host evidence recorded:

- `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "GFR-004"`
  passed twice with `00:00 +3: All tests passed!`, before and after
  `dart format`.
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-001"`
  passed with `00:00 +3: All tests passed!`.
- `flutter test test/core/services/pending_message_retrier_test.dart --plain-name "GFR-002"`
  passed with `00:00 +4: All tests passed!`.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GFR-002"`
  passed with `00:00 +1: All tests passed!`.
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name "GFR-002"`
  passed with `00:00 +1: All tests passed!`.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GFR-003"`
  passed with `00:01 +4: All tests passed!`.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "GFR-003"`
  passed with `00:01 +3: All tests passed!`.

Passing direct host evidence recorded:

- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart`
  passed with `00:53 +88: All tests passed!`.
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
  passed with `00:09 +92: All tests passed!`.
- `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`
  passed with `00:01 +9: All tests passed!`.
- `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  passed with `00:00 +15: All tests passed!`.
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  passed with `00:00 +20: All tests passed!`.
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
  passed with `00:02 +142: All tests passed!`.
- `flutter test test/core/services/pending_message_retrier_test.dart` passed
  with `00:42 +23: All tests passed!`.
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  passed with `00:00 +16: All tests passed!`.
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
  passed with `00:00 +3: All tests passed!`.
- `flutter test test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  passed with `00:00 +2: All tests passed!`.
- `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  passed with `00:00 +48: All tests passed!`.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`
  passed with `00:17 +118: All tests passed!`.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
  passed with `00:02 +49: All tests passed!`.
- `flutter test test/features/conversation/presentation/widgets/letter_card_test.dart`
  passed with `00:01 +50: All tests passed!`.

Passing named gate evidence recorded:

- `./scripts/run_test_gates.sh groups` passed with
  `00:53 +324: All tests passed!`.
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`
  passed on selected simulator `iPhone 17`
  (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`), including
  `wifi_relay_fallback_smoke_test.dart` (`00:01 +1`),
  `transport_e2e_test.dart` (`00:05 +3`), and
  `media_stable_id_smoke_test.dart` (`00:09 +7`).
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh baseline`
  passed after the unselected baseline run failed on Flutter device ambiguity;
  the selected-device rerun recorded host baseline
  `00:54 +100: All tests passed!`, `loading_states_smoke_test.dart`
  `00:04 +7: All tests passed!`, and `posts_phase1_fake_test.dart`
  `00:01 +1: All tests passed!`.
- `./scripts/run_test_gates.sh completeness-check` passed with
  `Completeness check: 769/769 test files classified. Completeness check PASS.`

Device resolution and simulator list evidence recorded:

- `flutter devices --machine` passed and listed supported targets, including
  bootable iOS simulators for UP004 Alice, Bob, Charlie, Dana, and selected
  `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`) for the `transport`
  gate.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list`
  passed. It resolved one-device
  `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device
  `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`,
  and four-device
  `279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76,5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
  The group dry-run discovered 123 planned commands and used default
  `MKNOON_RELAY_ADDRESSES`.

Simulator commands and accepted results recorded:

- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_relay_reconnect_group_recovery`
  passed on run `1780758396971`. Schema inspection is clean for this run:
  Alice, Bob, and Charlie all logged
  `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` for migration
  `074_group_message_logical_delivery_id`, and no `DatabaseException` or
  `no column named logical_delivery_id` appeared in the role logs. Alice wrote
  `gmp_1780758396971_alice_sent_aliceMissedDuringRelayDrop.json`; Alice's
  publish debug for
  `gmp_1780758396971_private_relay_reconnect_group_recovery_aliceMissedDuringRelayDrop_alice`
  showed `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and
  `inboxStored:true`; Bob wrote
  `gmp_1780758396971_bob_received_aliceMissedDuringRelayDrop.json` with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`; the
  orchestrator verdict was `ok:true`, and Alice/Bob/Charlie verdict JSONs were
  written.
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/scripts/run_group_multi_party_device_real.dart:private_background_resume_group_delivery`
  passed on run `1780758894898`. Schema inspection is clean for this run as
  well: Alice, Bob, and Charlie all logged
  `GROUP_MESSAGE_LOGICAL_DELIVERY_ID_MIGRATION_SUCCESS` for migration
  `074_group_message_logical_delivery_id`, and no `DatabaseException` or
  `no column named logical_delivery_id` appeared in the role logs. Alice wrote
  `gmp_1780758894898_alice_sent_aliceDuringBackgroundBeforeEdit.json`; Alice's
  publish debug for
  `gmp_1780758894898_private_background_resume_group_delivery_aliceDuringBackgroundBeforeEdit_alice`
  showed `deliveryMode:"live_and_inbox"`, `expectedRecipientCount:2`, and
  `inboxStored:true`; Bob wrote
  `gmp_1780758894898_bob_received_aliceDuringBackgroundBeforeEdit.json` with
  `liveOnly:false`, `usedOfflineDrain:true`, and `persistedCount:1`; the
  orchestrator verdict was `ok:true`, and Alice/Bob/Charlie verdict JSONs were
  written.

GFR-005 handoff:

- GFR-004 is accepted and unblocks GFR-005.
- GFR-005 owns final stable source/closure docs and the final Report 108
  program verdict.
