Status: execution-ready

# Reliable-Send Timeout And In-Doubt Pending Retry Payloads Plan

Session id: `timeout-pending-retry`

Source doc: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`

Breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`

## Planning Progress

- 2026-06-03 20:58:43 CEST - Evidence Collector started. Files inspected since last update: skill contract and intended plan path existence. Decision/blocker: source row and exact write path confirmed; no blocker. Next action: inspect source docs, owner code, direct tests, and gate definitions before drafting.
- 2026-06-03 21:03 CEST - Controller local plan fallback started. Files inspected since last update: spawned planner output, source doc timeout/pending sections, session breakdown row, `bridge_group_helpers.dart`, `send_group_message_use_case.dart`, Go timeout config/pubsub evidence, DB helper retry query, retry inbox-store consumer, direct tests, and gate definitions. Decision/blocker: spawned planner produced only intake artifact and no reusable plan after bounded settle; breakdown entry is execution-safe, so artifact-only local plan fallback is allowed. Next action: write execution-ready plan and return to normal pipeline execution.
- 2026-06-03 21:03 CEST - Planner completed. Files inspected since last update: direct bridge/send/DB/lifecycle test seams and `scripts/run_test_gates.sh`. Decision/blocker: no structural blocker; plan owns only the default reliable-send timeout and valid in-doubt retry-payload persistence. Next action: execution/QA child may implement this plan.
- 2026-06-03 21:03 CEST - Reviewer completed. Files inspected since last update: completed plan sections. Decision/blocker: native early-custody signaling, stale-pending sweeps, DB migrations, local status broadcasts, stuck-sending timestamps, live/replay dedup, and final matrix closure are explicitly out of scope. Next action: arbiter pass.
- 2026-06-03 21:03 CEST - Arbiter completed. Files inspected since last update: reviewer notes and closure bar. Decision/blocker: direct host tests plus group/transport gates and a narrow group reliability simulator proof are sufficient; real slow-link/multi-party device reproduction remains final acceptance evidence, not this session's implementation scope. Next action: downstream execution/QA child.

## Execution Progress

- 2026-06-03 21:05 CEST | Phase: pre-execution dirty snapshot; execution/QA spawn pending | Files inspected or touched: this plan and `git status --short` | Dirty snapshot: unrelated/prior-session changes are present in `info.plist`, prior text/voice session group UI/l10n/test files, prior simulator proof file `integration_test/group_recovery_e2e_test.dart`, and untracked rollout plan/breakdown docs; no timeout-owned production delta has landed yet | Decision/blocker: no blocker; executor must preserve unrelated changes and treat new timeout-owned edits as limited to `bridge_group_helpers.dart`, `send_group_message_use_case.dart`, and scoped tests if needed | Next action: spawn fresh execution/QA child with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-06-03 21:06 CEST | Phase: contract extraction started | Files inspected or touched: this plan, `01-P0-duplicate-delivery-cascade-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md` | Command running: none | Decision/blocker: pending contract extraction; plan appears execution-safe with explicit scope, owner files, tests, gates, and known-failure interpretation | Next action: extract bounded execution contract before spawning Executor.
- 2026-06-03 21:07 CEST | Phase: contract extracted | Files inspected or touched: this plan, `01-P0-duplicate-delivery-cascade-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md` | Extracted contract: raise `callGroupSendReliable` default timeout to a named 40s constant while preserving explicit timeouts; keep ambiguous reliable-send results `pending`/success; persist a valid non-null inbox retry payload from native reliable `envelope` plus recipient ids when local replay-envelope construction failed; never persist plaintext/raw `wireEnvelope`/private-key-derived retry material; add bridge timeout and send-use-case fallback regressions; rerun required direct tests, `groups`, `transport`, simulator proof, and `git diff --check`; carry forward only exact known `GCA-004` if reproduced | Decision/blocker: no blocker; scope guard excludes native custody signaling, migrations, stale-pending sweeps, local status broadcasts, live/replay dedup, source-doc closure, and unrelated dirty files | Next action: spawn fresh Executor child.
- 2026-06-03 21:08 CEST | Phase: Executor spawned/running | Files inspected or touched: this plan | Spawned child: Executor `019e8ee2-6a35-7f52-8865-5762320fe7ef` with `model: gpt-5.5`, `reasoning_effort: xhigh` | Command running: child implementation/test pass in isolated context | Decision/blocker: no blocker; controller will not edit owner files while Executor owns the implementation pass | Next action: bounded wait for Executor completion evidence.
- 2026-06-03 21:13 CEST | Phase: first bounded Executor wait expired / progress inspection | Files inspected or touched: this plan, `git status --short`, scoped diff for timeout owner files and direct tests | Current child evidence: plan progress shows owner inspection, scoped touches, formatter passed, and focused bridge test started; diff shows `groupSendReliableDefaultTimeout = 40s`, `callGroupSendReliable` using that default, bridge timeout regression, and native-envelope fallback regression in `send_group_message_use_case_test.dart` | Command running: Executor child is continuing required direct tests/gates | Decision/blocker: real assigned-step progress found; no blocker; one additional bounded wait is allowed under the bounded wait rule | Next action: continue waiting for Executor completion evidence.
- 2026-06-03 21:08:17 CEST | Phase: Executor pass started / contract extracted before owner inspection | Files inspected or touched: this plan, `01-P0-duplicate-delivery-cascade-session-breakdown.md`, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short` | Command running: none | Decision/blocker: no blocker; Executor owns only session `timeout-pending-retry`, will preserve existing dirty files and limit production edits to the bridge timeout constant plus retry-payload fallback only if the regression requires it | Next action: inspect owner files and scoped tests before edits.
- 2026-06-03 21:09 CEST | Phase: owner inspection completed / before touches | Files inspected or touched: `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, existing diff for `send_group_message_use_case_test.dart` | Command running: none | Decision/blocker: no blocker; `callGroupSendReliable` still defaults to 10s, while `_nativeReliableInboxRetryPayload` already builds retry payloads from native `envelope` plus `recipientPeerIds` without plaintext | Next action: add timeout constant/regression and replay-envelope fallback regression, then run targeted proof.
- 2026-06-03 21:11:33 CEST | Phase: owner touches completed | Files inspected or touched: `lib/core/bridge/bridge_group_helpers.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart` | Command running: none | Decision/blocker: no blocker; introduced public `groupSendReliableDefaultTimeout = 40s`, used it only for `callGroupSendReliable`, added bridge timeout-constant regression, and added replay-envelope fallback regression; existing native retry-payload fallback code required no production change so far | Next action: format touched files, then run required formatter gate and direct tests.
- 2026-06-03 21:12 CEST | Phase: pre-required-format gate | Files inspected or touched: formatter normalized `test/core/bridge/bridge_group_helpers_test.dart` and `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` within the required direct-test set | Command running: `dart format --output=none --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/send_group_message_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` | Decision/blocker: pending | Next action: run required formatter gate.
- 2026-06-03 21:12 CEST | Phase: required-format gate passed / pre-focused-bridge test | Files inspected or touched: required formatter file set | Command completed: `dart format --output=none --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/send_group_message_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` exited 0, `Formatted 6 files (0 changed)` | Command running: `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` | Decision/blocker: pending | Next action: run focused bridge timeout/default tests.
- 2026-06-03 21:13 CEST | Phase: focused bridge test passed / pre-focused GIRD-001 test | Files inspected or touched: `test/core/bridge/bridge_group_helpers_test.dart`, `lib/core/bridge/bridge_group_helpers.dart` | Command completed: `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` exited 0 with 3 tests passed | Command running: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` | Decision/blocker: pending | Next action: run focused in-doubt reliable-send regressions.
- 2026-06-03 21:13 CEST | Phase: focused GIRD-001 test passed / pre-focused replay-envelope test | Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart` | Command completed: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` exited 0 with 3 tests passed, including new replay-envelope fallback regression | Command running: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "replay-envelope"` | Decision/blocker: pending | Next action: run exact replay-envelope filter proof.
- 2026-06-03 21:14 CEST | Phase: focused replay-envelope test passed / pre-focused pending DB test | Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart` | Command completed: `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "replay-envelope"` exited 0 with 1 test passed | Command running: `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "pending"` | Decision/blocker: no production fallback change needed beyond timeout constant; existing native-envelope fallback passed | Next action: run pending inbox retry eligibility DB proof.
- 2026-06-03 21:14 CEST | Phase: focused pending DB test passed / pre-lifecycle retry test | Files inspected or touched: `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` | Command completed: `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "pending"` exited 0 with 2 tests passed | Command running: `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` | Decision/blocker: pending | Next action: run resume retry invocation suite.
- 2026-06-03 21:15 CEST | Phase: lifecycle retry test passed / pre-full bridge suite | Files inspected or touched: `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` | Command completed: `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` exited 0 with 3 tests passed | Command running: `flutter test test/core/bridge/bridge_group_helpers_test.dart` | Decision/blocker: pending | Next action: run full bridge helper suite.
- 2026-06-03 21:15 CEST | Phase: full bridge suite passed / pre-full send-use-case suite | Files inspected or touched: `test/core/bridge/bridge_group_helpers_test.dart`, `lib/core/bridge/bridge_group_helpers.dart` | Command completed: `flutter test test/core/bridge/bridge_group_helpers_test.dart` exited 0 with 80 tests passed | Command running: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` | Decision/blocker: pending | Next action: run full send group message use-case suite.
- 2026-06-03 21:16 CEST | Phase: full send-use-case suite passed / pre-full DB reliability suite | Files inspected or touched: `test/features/groups/application/send_group_message_use_case_test.dart` | Command completed: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` exited 0 with 133 tests passed | Command running: `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` | Decision/blocker: pending | Next action: run full group message DB reliability suite.
- 2026-06-03 21:16 CEST | Phase: full DB reliability suite passed / pre-device availability check | Files inspected or touched: `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` | Command completed: `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` exited 0 with 44 tests passed | Command running: `flutter devices --machine` | Decision/blocker: pending | Next action: capture live device availability before named gates.
- 2026-06-03 21:17 CEST | Phase: device availability captured / pre-groups gate | Files inspected or touched: device output only | Commands completed: `flutter devices --machine` exited 0 and listed Pixel 6 `21071FDF600CSC`, physical iPhones, preferred simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and other booted iOS simulators; `xcrun simctl list devices available` exited 0 and confirmed the preferred simulator is Booted | Command running: `./scripts/run_test_gates.sh groups` | Decision/blocker: pending | Next action: run group messaging gate and triage any failure before classification.
- 2026-06-03 21:18 CEST | Phase: groups gate failed / gate-failure triage entry | Files inspected or touched: gate terminal output only | Failing gate command: `./scripts/run_test_gates.sh groups` exited 1; captured terminal tail shows `Some tests failed` with summary `+317 -1`, but the retained output did not preserve the exact failing assertion or file; log path: none, output was not redirected | Focused triage command about to run: `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` | Classification state: `pending_triage` | Next action: run known residual slice to verify whether the single groups failure is carried `GCA-004`.
- 2026-06-03 21:18 CEST | Phase: groups gate classified / pre-transport gate | Files inspected or touched: focused GCA-004 triage output | Commands completed: `./scripts/run_test_gates.sh groups` exited 1; `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` exited 1 with exact known residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>` | Command running: `./scripts/run_test_gates.sh transport` | Decision/blocker: groups failure is allowed carried `GCA-004`, not session-owned | Next action: run transport gate and classify separately if it fails.
- 2026-06-03 21:19 CEST | Phase: transport gate failed / gate-failure triage entry | Files inspected or touched: transport gate terminal output only | Failing gate command: `./scripts/run_test_gates.sh transport` exited 1 before test execution because multiple devices were connected and no device id was selected; log path: none, output was not redirected | Focused triage command about to run: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` | Classification state: `pending_triage` | Next action: rerun transport with the preferred booted iOS simulator id from the plan and device check.
- 2026-06-03 21:24 CEST | Phase: Executor bounded waits exhausted / local verification recovery started | Files inspected or touched: this plan, `git status --short`, `git diff --stat`, scoped timeout-owner diff, process list | Last completed child evidence: direct formatter and all required direct host tests passed; `groups` gate failed only with focused known `GCA-004`; transport rerun with selected device had been started but no result was recorded | Current command/log being inspected: none; no `flutter test`, `run_test_gates`, `run_with_devices`, or `dart format` process remains running | Decision/blocker: child `019e8ee2-6a35-7f52-8865-5762320fe7ef` was closed after two bounded waits without final result; coherent landing exists, so controller will use the skill's local verification recovery for missing required gate evidence instead of respawning the same Executor blindly | Next action: run selected-device transport gate, simulator proof, and `git diff --check`, then complete Executor evidence locally.
- 2026-06-03 21:24 CEST | Phase: local recovery pre-transport gate | Files inspected or touched: this plan | Command running: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` | Decision/blocker: pending; prior unselected-device transport failure was environment selection, not a product failure | Next action: capture selected-device transport result.
- 2026-06-03 21:28 CEST | Phase: selected-device transport gate passed / pre-simulator proof | Files inspected or touched: transport gate output | Command completed: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` exited 0; `background_reconnect_test.dart` skipped by its own fixture conditions, `wifi_relay_fallback_smoke_test.dart` passed in self-contained mode, `transport_e2e_test.dart` passed, and `media_stable_id_smoke_test.dart` passed with `+7` | Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` | Decision/blocker: no transport blocker | Next action: run required narrow group reliability simulator proof.
- 2026-06-03 21:30 CEST | Phase: simulator proof passed / pre-diff-check | Files inspected or touched: simulator proof output | Command completed: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` exited 0 on resolved one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; command `#8` `integration_test/group_recovery_e2e_test.dart` passed with `+7` and `PASS: reliability simulations completed for scope: group` | Command running: `git diff --check` | Decision/blocker: no simulator blocker | Next action: run final diff hygiene check.
- 2026-06-03 21:31 CEST | Phase: diff-check passed / Executor completed | Files inspected or touched: timeout owner files and direct tests; no breakdown ledger or closure evidence touched | Command completed: `git diff --check` exited 0 | Executor result summary: default reliable-send timeout constant and regression landed; native-envelope pending retry-payload regression landed and passed without production fallback changes beyond the timeout constant; required formatter, direct tests, `groups` gate triage, selected-device `transport`, simulator proof, and diff hygiene are recorded above | Decision/blocker: Executor phase complete via local verification recovery after child spawn no-final; no execution blocker identified | Next action: spawn separate QA Reviewer child with `model: gpt-5.5`, `reasoning_effort: xhigh`.
- 2026-06-03 21:31 CEST | Phase: QA Reviewer spawned/running | Files inspected or touched: this plan | Spawned child: QA Reviewer `019e8ef8-6bf2-7ee1-b7f1-aaa7c428c71d` with `model: gpt-5.5`, `reasoning_effort: xhigh` | Command running: isolated QA sufficiency review | Decision/blocker: pending QA; no fix pass will run unless QA reports blocking issues | Next action: bounded wait for QA completion evidence.
- 2026-06-03 21:32:11 CEST | Phase: QA Reviewer started | Files inspected or touched: this plan, `01-P0-duplicate-delivery-cascade-session-breakdown.md`, `git status --short` | Command running: scoped diff and test-evidence inspection | Decision/blocker: pending QA; no blocking issue identified yet | Next action: inspect session-owned diffs, direct test assertions, and recorded required gate evidence.
- 2026-06-03 21:33:49 CEST | Phase: QA Reviewer completed | Files inspected or touched: this plan, `01-P0-duplicate-delivery-cascade-session-breakdown.md`, `lib/core/bridge/bridge_group_helpers.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/send_group_message_use_case_test.dart`, `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`, Go timeout files by diff/read-only inspection | Commands completed: `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` exited 0 with 3 tests passed; `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` exited 0 with 3 tests passed; `git diff --check` exited 0 | Decision/blocker: no QA blocking issues; recorded `groups` gate residual is the carried known `GCA-004`, selected-device `transport` and required simulator proof are recorded as passing | Next action: controller may treat session as accepted for final verdict.
- 2026-06-03 21:34 CEST | Phase: final execution verdict writing started | Files inspected or touched: this plan and QA final summary | Command running: none | Decision/blocker: no blocking issues remain; final verdict will be `accepted_with_explicit_follow_up` only because the broad `groups` gate carries exact known unrelated `GCA-004` residual | Next action: persist final execution output below.
- 2026-06-03 21:34 CEST | Phase: final execution verdict written | Files inspected or touched: this plan | Command running: none | Decision/blocker: final execution verdict persisted; no fix pass required | Next action: stop execution/QA turn; closure and breakdown ledger updates remain owned by later fresh child.

## Final Execution Verdict

- Final verdict: `accepted_with_explicit_follow_up`
- Blocker class: none
- Spawned-agent isolation used: yes. Executor child `019e8ee2-6a35-7f52-8865-5762320fe7ef` was spawned with `model: gpt-5.5`, `reasoning_effort: xhigh`; QA Reviewer child `019e8ef8-6bf2-7ee1-b7f1-aaa7c428c71d` was spawned separately with the same model settings.
- Local sequential fallback used: yes, verification recovery only. The Executor child made coherent code/test/progress changes but did not return a final message after two bounded waits, so it was closed and the controller locally completed the missing selected-device `transport`, simulator proof, and `git diff --check` evidence before spawning QA.
- Files changed by this session: `lib/core/bridge/bridge_group_helpers.dart`; `test/core/bridge/bridge_group_helpers_test.dart`; `test/features/groups/application/send_group_message_use_case_test.dart`; formatter-only direct-test cleanup in `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`. `lib/features/groups/application/send_group_message_use_case.dart` needed no production change because the existing native-envelope retry-payload path passed the new regression.
- Tests added or updated: bridge default timeout regression for `groupSendReliableDefaultTimeout == 40s` and `>= 35s`; send-use-case regression `GIRD-001 replay-envelope fallback uses native reliable envelope for pending inbox retry`.
- Evidence captured: default reliable-send timeout is now a named 40 second constant used by `callGroupSendReliable`; explicit caller-provided timeout behavior remains covered; local replay-envelope failure plus native reliable `envelope`/recipient ids creates a pending, inbox-retry eligible row without persisting protected plaintext or private-key fragments.
- Exact tests and gates run:
  - `dart format --output=none --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/send_group_message_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` passed.
  - `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"` passed; Executor and QA spot check both recorded 3 tests passed.
  - `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"` passed; Executor and QA spot check both recorded 3 tests passed.
  - `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "replay-envelope"` passed with 1 test.
  - `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "pending"` passed with 2 tests.
  - `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` passed with 3 tests.
  - `flutter test test/core/bridge/bridge_group_helpers_test.dart` passed with 80 tests.
  - `flutter test test/features/groups/application/send_group_message_use_case_test.dart` passed with 133 tests.
  - `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` passed with 44 tests.
  - `flutter devices --machine` passed and listed the preferred simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`; `xcrun simctl list devices available` passed and confirmed it was Booted.
  - `./scripts/run_test_gates.sh groups` exited 1 only with carried known `GCA-004`; focused triage `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` reproduced the exact known residual at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`.
  - `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed; the first unselected `./scripts/run_test_gates.sh transport` attempt failed before test execution because multiple devices were connected.
  - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart` passed on one-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, command `#8`, with `+7`.
  - `git diff --check` passed; QA spot check passed again.
- Blocking issues remaining: none.
- Recommended next retry focus: not applicable.
- Non-blocking follow-ups deferred: carry forward only the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` residual for the later closure/acceptance owner; no session-owned follow-up remains.
- Why the session is safe to consider complete: implementation stayed inside the timeout/pending-retry scope, required regressions and direct tests passed, existing in-doubt rows remain `pending`/success, no plaintext/private-key retry payload was introduced, device-backed gates are either passing or narrowed to the exact allowed `GCA-004` residual, QA found no blocking issues, and the breakdown ledger/source closure were intentionally left untouched for the later closure child.

## Closure Progress

- 2026-06-03 21:43:14 CEST - Closure audit verdict: `accepted_with_explicit_follow_up`.
- Evidence checked: persisted final execution verdict, scoped timeout owner diff, native-envelope retry-payload code path, new direct regressions, selected-device `transport`, narrow group simulator proof, `git diff --check`, and exact known `GCA-004` residual classification.
- Durable closure record updated in `01-P0-duplicate-delivery-cascade-session-breakdown.md`: the `timeout-pending-retry` ledger row is now `accepted_with_explicit_follow_up` and the session closure evidence section records what is closed, residual-only follow-up, still-open later sessions, and accepted differences.
- No final whole-doc verdict was persisted; `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain pending.

## real scope

This session owns the no-schema reliable-send residue only:

- Raise the Dart `callGroupSendReliable` default timeout from the current 10 seconds to a named constant comfortably above the native reliable-send publish budget, target `Duration(seconds: 40)`.
- Preserve explicit caller-provided timeout behavior for tests and special callers.
- Keep reliable-send in-doubt handling intact for genuine slow/ambiguous cases: `BRIDGE_TIMEOUT` and publish-without-custody still save one outgoing row as `pending`, not `failed`, when the result is ambiguous.
- Ensure a pending in-doubt row remains inbox-retry eligible when the local Dart replay-envelope build failed but the native reliable-send result supplies a valid message envelope and recipient set.
- Prove the existing DB retry query continues to select pending rows only when `inbox_retry_payload IS NOT NULL`, and prove the resume/pending retrier path can still invoke the inbox retry sweep.

This session does not add native early-custody signaling, a stale-pending sweep, DB schema or migrations, local status broadcasts, status-change timestamps, live/replay dedup, notification behavior, source-matrix final closure, or gate-definition edits unless execution adds a new high-value test file that requires classification.

## closure bar

The session is closed when:

- `callGroupSendReliable` exposes and uses a default timeout above native reliable-send's concurrent publish budget (`PubSubTimeout=30s`; `InboxTimeout=15s` runs concurrently with publish in `go-mknoon/node/pubsub.go`).
- A direct bridge test proves the default timeout constant is at least 35 seconds and that explicit shorter timeouts still return the existing `BRIDGE_TIMEOUT` map.
- A direct send-use-case regression proves that when local replay-envelope construction fails but native reliable send returns an in-doubt result with a valid `envelope`, the saved row is `pending`, has `inboxStored == false`, has non-null `inboxRetryPayload`, and appears in `getMessagesWithFailedInboxStore()`.
- That retry payload must store a valid message string from an already-built envelope source (`reliableResult['envelope']` or the existing local replay envelope). Do not persist raw `inboxPayload`, plaintext publish params, or private-key-derived material as an inbox retry payload.
- Existing pending-row DB eligibility and resume retry invocation remain covered.
- Required direct tests and named gates below either pass, or fail only with a documented unrelated residual such as carried `GCA-004`.

## source of truth

- Current code beats stale prose when the source doc overstates payload behavior.
- The session scope comes from `01-P0-duplicate-delivery-cascade-session-breakdown.md`, session `timeout-pending-retry`.
- Timeout evidence comes from `lib/core/bridge/bridge_group_helpers.dart`, `go-mknoon/node/config.go`, and `go-mknoon/node/pubsub.go`.
- In-doubt and retry-payload behavior comes from `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`, and `lib/core/database/helpers/group_messages_db_helpers.dart`.
- `scripts/run_test_gates.sh` is the named-gate source of truth when docs disagree with gate script membership.

## session classification

`implementation-ready`

## exact problem statement

Flutter stops waiting for `group:sendReliable` after 10 seconds, but the native reliable send can legitimately spend up to the 30 second publish window while the 15 second inbox branch runs concurrently. The current 10 second default therefore pushes slow-but-bounded reliable sends into `BRIDGE_TIMEOUT` and `pending` in-doubt state too early.

The second residue is narrower: if the Dart offline replay-envelope build fails before pre-persist, `prePersistMessage.inboxRetryPayload` is null. For native reliable-send results that still return a valid envelope and recipient set, the pending/in-doubt row must use that native envelope as the retry payload so the existing inbox retry sweep can find and drain it. If neither local replay envelope nor native reliable envelope exists after a real Dart timeout, execution must not fabricate a malformed plaintext retry payload; the timeout bump is the scoped mitigation for that no-valid-envelope case.

## files and repos to inspect next

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/pubsub.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `test/core/bridge/bridge_group_helpers_test.dart` already covers explicit timeout behavior for `callGroupSendReliable`.
- `test/features/groups/application/send_group_message_use_case_test.dart` already covers GIRD-001 timeout rows staying `pending`, publish-without-custody rows staying in-doubt, retry payload recipient preservation, and retry-in-place behavior for many inbox failure cases.
- `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` already proves `dbLoadGroupMessagesWithFailedInboxStore` includes pending rows only when `inbox_retry_payload` is non-null.
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` already proves resume invokes `retryFailedGroupInboxStoresFn` and fault-isolates that step.

Missing coverage:

- No test pins the reliable-send default timeout above the native 30 second publish budget.
- No direct test isolates the local replay-envelope failure plus native reliable in-doubt envelope fallback.

## regression/tests to add first

Add the regression tests before or alongside implementation:

- In `test/core/bridge/bridge_group_helpers_test.dart`, add a test that asserts the exported/named default reliable-send timeout is at least 35 seconds and preferably exactly 40 seconds. Keep the existing explicit tiny-timeout test so caller-provided timeouts still return `BRIDGE_TIMEOUT`.
- In `test/features/groups/application/send_group_message_use_case_test.dart`, add a fake bridge that makes local replay-envelope construction fail, for example by returning `ok:false` for `group.encrypt` or failing signing, while `group:sendReliable` returns an in-doubt native result containing `envelope`, `recipientPeerIds`, `publishSucceeded:true`, `inboxStored:false`, `topicPeerCount:0`, and `expectedRecipientCount > 0`. Assert the saved row is `pending`, has non-null `inboxRetryPayload`, the payload's `message` is the native envelope, recipient ids are preserved when present, and `msgRepo.getMessagesWithFailedInboxStore()` returns that row.
- If that send-use-case regression unexpectedly already passes, keep it as coverage and limit production changes to the timeout constant.
- Keep `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart` and `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` as rerun coverage unless implementation changes those files.

## step-by-step implementation plan

1. In `lib/core/bridge/bridge_group_helpers.dart`, introduce a named compile-time constant for the reliable group send default timeout, target `const Duration(seconds: 40)`, and use it as the default value for `callGroupSendReliable(timeout: ...)`.
2. Do not change Go timeout constants unless current evidence disproves the 30 second publish / 15 second inbox concurrent model.
3. Add the direct bridge timeout constant regression in `test/core/bridge/bridge_group_helpers_test.dart`.
4. Add the replay-envelope-failure/native-envelope fallback regression in `test/features/groups/application/send_group_message_use_case_test.dart`.
5. If the fallback regression fails, adjust only the reliable-send retry payload resolution in `send_group_message_use_case.dart` or the helper around `_nativeReliableInboxRetryPayload` so an in-doubt native `envelope` is encoded as `{'groupId': groupId, 'message': envelope, 'recipientPeerIds': [...]}` when inbox custody is not complete.
6. Do not persist raw `inboxPayload`, the plaintext `wireEnvelope`, sender private keys, or any rebuild instruction that would require private signing material later.
7. Rerun formatting and the direct tests below.
8. Run the named gates and simulator proof below. If `groups` fails only with carried `GCA-004`, record that exact residual. If `transport` or simulator fixtures are unavailable, record exact device/fixture evidence and let closure classify it without weakening direct host proof.

## risks and edge cases

- A too-low default keeps creating false in-doubt pending rows; a too-high default can make the UI wait too long on a truly hung bridge. Forty seconds is bounded and just above the native 30 second publish budget with margin.
- Persisting malformed retry payloads is worse than a null payload because the retry sweep would repeatedly store invalid relay messages. Only valid envelope strings are acceptable.
- A native timeout result has no native envelope. Do not claim inbox retry eligibility for that exact case unless implementation has a valid envelope source.
- Existing in-doubt behavior must remain success-returning and single-row; this session must not revert to false `failed` rows.
- Transport/integration gates may require a live device target. Missing devices are evidence blockers for the gate, not a reason to edit product code outside this session.

## Device/Relay Proof Profile

Profile: `single-device` for gate evidence, plus host-only direct tests.

- Host-only required evidence: direct Flutter tests under `test/` listed below.
- Live device availability check before device-backed gates: `flutter devices --machine`. If iOS simulator routing is needed, also run `xcrun simctl list devices available`.
- Preferred single-device target from the pipeline default when available: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`.
- If that target is unavailable, execution may use one currently booted/available Flutter target for `./scripts/run_test_gates.sh transport` and must record the exact device id in `## Execution Progress`.
- No paired-device, three-party, OS notification, multi-relay, or APNs fixture is required for this session.
- Required simulator proof: run the narrow group reliability command after direct tests:
  `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart`
- Device-backed `transport` and simulator results are closure evidence for this session. If fixtures are unavailable after live checks, record `external-fixture-blocked` for that gate evidence; do not invent a green result.

## exact tests and gates to run

Run after implementation:

- `dart format --output=none --set-exit-if-changed lib/core/bridge/bridge_group_helpers.dart lib/features/groups/application/send_group_message_use_case.dart test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/core/database/helpers/group_messages_db_helpers_reliability_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `flutter test test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupSendReliable"`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "replay-envelope"`
- `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart --plain-name "pending"`
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `flutter test test/core/bridge/bridge_group_helpers_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh transport`
- `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only integration_test/group_recovery_e2e_test.dart`
- `git diff --check`

If the `--plain-name` filter names need adjustment after tests are added, use the final exact test names and record them in `## Execution Progress`.

## known-failure interpretation

- Carry forward only the known unrelated `GCA-004 bridgeError recovery drains inbox after settled materialized invite` failure at `test/features/groups/integration/invite_round_trip_test.dart:2930`, `Expected: not null`, `Actual: <null>`, if `./scripts/run_test_gates.sh groups` reproduces that same failure and focused rerun evidence matches prior session evidence.
- Do not classify a `transport` gate build/device failure as `GCA-004`; record the exact failing integration test or missing-device fixture separately.
- Any failure in the new timeout constant test, the new replay-envelope/native-envelope fallback test, direct send-use-case GIRD-001 tests, DB pending eligibility test, or resume retry invocation test is session-owned until fixed or honestly blocked.

## done criteria

- Plan status remains `execution-ready`.
- Product changes are limited to the timeout constant and any valid-envelope retry-payload fallback needed by the new regression.
- Direct tests prove the timeout default and pending retry-payload fallback.
- Existing in-doubt behavior stays `pending`/success, not false `failed`.
- `groups`, `transport`, simulator proof, and `git diff --check` are run or exact fixture blockers are recorded.
- Breakdown ledger is not updated by execution; closure owns final ledger state.

## scope guard

Do not implement:

- Native early-custody / accepted-custody signaling.
- Any DB migration or status timestamp column.
- A stale-pending-to-failed sweep.
- Local status broadcast streams.
- Live/replay delivery dedup or notification dedup.
- Group notification matrix or final source-doc closure.
- Broad refactors of send/retry repositories.
- Changes to `02-P0-undecryptable-messages-self-heal.md` or unrelated dirty files such as `info.plist`.

If execution discovers that a valid retry payload cannot be produced for a timeout result without a native envelope or local replay envelope, record that as an accepted limitation/blocker with evidence rather than persisting malformed plaintext.

## reviewer findings

- Structural blockers: none after adding explicit valid-envelope guardrails and device/relay proof profile.
- Incremental details: exact `--plain-name` filters may need adjustment after test names are written.
- Accepted differences: real slow-link multi-party reproduction from the source doc remains acceptance-session evidence; this session proves the timeout default and valid pending retry-payload contract with direct tests plus configured group/transport gates.

## arbiter decision

The session is execution-ready. The spawned planning child created only an intake artifact and did not produce durable planning progress after bounded waits, so the parent controller used the pipeline's local artifact-only plan fallback. The fallback is safe because the breakdown entry is execution-safe and current repo evidence identifies the exact owner files, tests, gates, scope guard, and closure bar.
