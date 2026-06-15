# Group Media Local Durability TDD Plan

Status: accepted_with_explicit_follow_up

## Planning Progress

- 2026-06-09 - Arbiter addendum completed. Files inspected: `MIG-012-group-media-relay-leak-triage.md`, MIG-012 source plan, bundle transfer downgrade code/tests, existing durability plan. Decision: add migration fail-closed amplifier as required closure work; reject relay re-materialization and unproven receiver-status claims as out of scope.
- 2026-06-09 - Reviewer addendum completed. Files inspected: triage recommendations A-E and current plan scope. Decision: current plan was insufficient for the full relay-leak outcome because it fixed the deleter but left critical missing media sanitized into successful transfers.
- 2026-06-09 - Planner addendum completed. Files inspected: `account_migration_bundle_transfer.dart`, `migration_file_manifest.dart`, `account_migration_bundle_transfer_test.dart`, MIG-012 closure bar. Decision: keep feed durability as the trigger fix and add a second fail-safe phase for critical media bundle assembly.
- 2026-06-09 - Evidence addendum completed. Files inspected: `MIG-012-group-media-relay-leak-triage.md`, MIG-012 plan, migration downgrade code and tests. Decision: triage contributes one material, repo-backed gap: `sanitize_missing_media_without_relay` downgrades critical missing media and reports `relayDependencyRisk:false`.
- 2026-06-09 - Arbiter completed. Files inspected: reviewer findings, production seams, direct tests, gate definitions, reliability simulator helper. Decision: no structural blockers remain after requiring host regressions plus simulator/device evidence. Next action: implement with tests first.

## Execution Progress

- 2026-06-09 17:24 CEST - phase: contract extracted; files inspected: this plan, `Test-Flight-Improv/test-gate-definitions.md`, MIG-012 relay-independent media plan/triage references, scoped `graphify query` output, and `git status --short`; command/result: `graphify query "Execute Test-Flight-Improv/Move-Feature/group-media-local-durability-tdd-plan.md: group media local durability relevant code entry files, tests, gates, and ownership boundaries" --budget 1800` completed with version-skew warning and limited scoped context, `git status --short` shows a pre-existing dirty worktree including this untracked plan and broad feature files; decision/blocker: execution contract is concrete enough to spawn Executor, with dirty worktree treated as existing user/generated state and not reverted; next action: spawn isolated Executor with requested `model: gpt-5.5` and `reasoning_effort: xhigh` to add required red tests, implement feed verifier and migration fail-closed fixes, run required direct tests/gates, format, diff-check, graphify update, and record evidence.
- 2026-06-09 17:25 CEST - phase: Executor spawned/running; files inspected or touched: this plan; command currently running: spawned Executor agent `019eacfc-eabe-7a40-9f27-fb938e328ea0` (`Euclid`) with requested `model: gpt-5.5` and `reasoning_effort: xhigh`; decision/blocker: pending Executor implementation and required evidence; next action: wait for Executor final handoff before spawning QA Reviewer.
- 2026-06-09 17:25 CEST - phase: Executor contract extracted; files inspected: this plan, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/Move-Feature/MIG-012-group-media-relay-leak-triage.md`, `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-012-relay-independent-media-plan.md`, `/Users/I560101/Project-Sat/mknoon-2/flutter_app/.agents/skills/graphify/SKILL.md`, scoped `graphify query` output, and `git status --short`; command/result: `graphify query "group media local durability plan code entry files feed verifier migration manifest bundle transfer tests telemetry raw delete relationships" --budget 2200` completed with version-skew warning and limited context; decision/blocker: scope is constrained to feed group-media display verification/telemetry and critical migration fail-closed behavior, with relay re-materialization/plaintext-hash architecture out of scope and dirty worktree treated as pre-existing; next action: inspect named production/tests and add required RED tests before production changes.
- 2026-06-09 17:31 CEST - phase: RED tests added before production changes; files inspected or touched: `test/features/feed/application/load_feed_use_case_test.dart`, `test/features/feed/application/feed_projection_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/account_migration/application/account_migration_bundle_transfer_test.dart`; command currently running: planned RED confirmation `flutter test test/features/feed/application/load_feed_use_case_test.dart` followed by `flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart test/features/account_migration/application/migration_file_manifest_validator_test.dart test/features/account_migration/application/account_migration_bundle_transfer_test.dart`; decision/blocker: expected failures should show plaintext relay-hash media is still deleted/integrity-failed and critical missing chat media still sanitizes into success; next action: run listed direct commands and then implement minimal feed verifier/migration criticality changes.
- 2026-06-09 17:32 CEST - phase: RED failures confirmed; files inspected or touched: same RED test files; command/result: `flutter test test/features/feed/application/load_feed_use_case_test.dart` failed as expected with `loadGroupFeedItems preserves relay-hash done group media plaintext` returning `integrity_failed` instead of `done` and `loadGroupFeedItems emits missing file telemetry without delete` seeing no verifier telemetry; `flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart test/features/account_migration/application/migration_file_manifest_validator_test.dart test/features/account_migration/application/account_migration_bundle_transfer_test.dart` failed as expected on `missing critical chat media blocks bundle and leaves row unchanged` because current code emitted `MISSING_MEDIA_DOWNGRADE_START/SUCCESS`, made the issue non-blocking, mutated the row, and built the bundle; decision/blocker: RED behavior matches the plan defects, no unrelated failure triage needed before production edits; next action: remove plaintext hash validation/delete from feed display verification, add feed verifier telemetry, and make migration missing-media downgrade criticality-aware/fail-closed.
- 2026-06-09 17:37 CEST - phase: production implementation completed and formatted; files inspected or touched: `lib/features/feed/application/group_feed_media_verification.dart`, `lib/features/account_migration/domain/models/migration_file_manifest.dart`, `lib/features/account_migration/application/migration_file_manifest_builder.dart`, `lib/features/account_migration/application/account_migration_bundle_transfer.dart`, `test/features/feed/application/load_feed_use_case_test.dart`, `test/features/feed/application/feed_projection_test.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/account_migration/application/migration_file_manifest_builder_test.dart`, `test/features/account_migration/application/account_migration_bundle_transfer_test.dart`; command/result: `dart format ...` completed on touched Dart files; decision/blocker: feed verifier now skips plaintext hash validation for relay-hash group media and emits scoped telemetry, migration issues carry criticality, critical missing media is no longer downgraded, and audit risk includes sanitized missing media; next action: run required direct tests in plan order starting with `flutter test test/features/feed/application/load_feed_use_case_test.dart`.
- 2026-06-09 17:37 CEST - phase: direct test failed and triaged before fix; files inspected or touched: `test/features/feed/application/load_feed_use_case_test.dart`, `lib/features/feed/application/group_feed_media_verification.dart`, `lib/core/utils/flow_event_emitter.dart`; failing command/result: `flutter test test/features/feed/application/load_feed_use_case_test.dart` failed in `loadGroupFeedItems preserves relay-hash done group media plaintext`; focused triage: inspect emitted event payload showed `plaintextHashValidationSkipped` was present but sanitized to `[redacted]`; classification: session-caused telemetry sanitizer false positive, not the original verifier behavior and not pre-existing; next action: add a narrow sanitizer allowlist for this boolean diagnostic key and rerun the same required direct test.
- 2026-06-09 17:38 CEST - phase: direct test passed; files inspected or touched: `lib/core/utils/flow_event_emitter.dart`, `lib/features/feed/application/group_feed_media_verification.dart`, `test/features/feed/application/load_feed_use_case_test.dart`; command/result: `dart format lib/core/utils/flow_event_emitter.dart && flutter test test/features/feed/application/load_feed_use_case_test.dart` passed; decision/blocker: feed app path now proves relay-hash plaintext survives, missing files produce telemetry, and the boolean skip diagnostic is not redacted; next action: run `flutter test test/features/feed/application/feed_projection_test.dart`.
- 2026-06-09 17:39 CEST - phase: direct test passed; files inspected or touched: `test/features/feed/application/feed_projection_test.dart`, `lib/features/feed/application/group_feed_media_verification.dart`; command/result: `flutter test test/features/feed/application/feed_projection_test.dart` passed; decision/blocker: group snapshot path proves relay-hash plaintext survives with skipped-hash telemetry; next action: run `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`.
- 2026-06-09 17:39 CEST - phase: direct test failed and triaged before fix; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; failing command/result: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` failed to load because the new widget regression used `sha256` without importing `package:crypto/crypto.dart`; focused triage: compiler error at `feed_wired_test.dart:2567`; classification: session-caused test import miss; next action: add the import, format the test, and rerun the same required direct test.
- 2026-06-09 17:40 CEST - phase: direct test failed, pending triage; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; failing command/result: `dart format test/features/feed/presentation/screens/feed_wired_test.dart && flutter test test/features/feed/presentation/screens/feed_wired_test.dart` failed with two widget failures, but the failure names were truncated by command output; log path: none; focused triage command: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --reporter expanded`; classification: pending_triage; next action: run the focused expanded reporter command before any fix.
- 2026-06-09 17:41 CEST - phase: direct test still pending triage; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; failing command/result: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --reporter expanded` also failed with two widget failures but output was truncated before failure details; log path: none; focused triage command: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --reporter json > /tmp/feed_wired_test.jsonl 2>&1` followed by failure-record inspection; classification: pending_triage; next action: capture JSON log and inspect failure records only.
- 2026-06-09 17:44 CEST - phase: direct test failures triaged before fix; files inspected or touched: `/tmp/feed_wired_test.jsonl`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/feed/application/group_feed_media_verification.dart`; failing command/result: JSON log showed failures only in `incremental group message carries media attachments to feed card` and `incremental group message blocks tampered done media in feed card`, both with `FeedCard` not found; focused triage command/result: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "incremental group message carries media attachments to feed card" --reporter expanded` showed no verifier/error events after the listener emit, because the new verifier awaits real `File.exists()` before first telemetry and the widget test fake-async zone did not complete that I/O; classification: session-caused test-fixture async gap from added file verification, not a product behavior failure; next action: wrap the two media-test listener emits in `tester.runAsync`, then rerun the required widget command.
- 2026-06-09 17:46 CEST - phase: direct test failed after focused widget async fix, pending triage; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; failing command/result: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` failed with `+89 -2` after wrapping the two media-test listener emits in `tester.runAsync`; failing file/test: same required widget suite, specific failure names not visible in truncated output; log path: none; focused triage command: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --reporter json > /tmp/feed_wired_test_after_runasync.jsonl 2>&1` followed by failure-record inspection; classification: pending_triage; next action: capture JSON log and inspect failure records before any further fix.
- 2026-06-09 17:48 CEST - phase: direct test failures triaged before fix; files inspected or touched: `/tmp/feed_wired_test_after_runasync.jsonl`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`; failing command/result: JSON log still showed only `incremental group message carries media attachments to feed card` and `incremental group message blocks tampered done media in feed card`, both with `FeedCard` not found and no `GROUP_FEED_MEDIA_*` telemetry after initial feed load; focused triage result: emitting the fake broadcast stream event inside `tester.runAsync` prevented the subscription callback from being delivered by the widget-test fake-async pump path; classification: session-caused test-fixture async ordering issue, not a product verifier rejection; next action: emit the fake group event in the normal test zone, pump once to start the callback, then use `tester.runAsync` only to let real file I/O complete before final widget pumps.
- 2026-06-09 17:50 CEST - phase: direct test failures triaged before fixture refinement; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; command/result: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "refreshes feed on incoming group message" --reporter expanded` passed, while the two media-focused one-at-a-time runs still failed with `FeedCard` not found and no verifier telemetry; decision/blocker: group stream subscription is valid, but media verifier file I/O must be started inside `tester.runAsync` rather than after a fake-async callback begins; classification: session-caused test-fixture async ordering issue; next action: add an opt-in synchronous fake group stream for the two media tests and emit inside `tester.runAsync` so the verifier starts real file I/O in the real async zone.
- 2026-06-09 17:35 CEST - phase: Executor bounded wait extended; files inspected or touched: this plan, `lib/features/feed/application/group_feed_media_verification.dart`, feed direct test files, and account migration direct test files; command/result: first controller wait for Executor timed out, plan progress and `git diff --stat` show real assigned-step progress with RED failures confirmed and feed verifier/test edits landed; decision/blocker: no blocker, one additional bounded wait allowed by the no-progress rule because assigned-step progress exists; next action: wait for Executor final handoff.
- 2026-06-09 17:51 CEST - phase: Executor closed/no final handoff; files inspected or touched: this plan, targeted `git status --short`, targeted `git diff --stat`, and Executor progress entries through 17:50; command/result: second bounded wait timed out and spawned Executor `019eacfc-eabe-7a40-9f27-fb938e328ea0` was closed with previous status `running`; decision/blocker: child produced real partial implementation evidence but no trustworthy final report, so controller is using local verification recovery against the landed files rather than waiting or blindly respawning; next action: inspect the partial landing, finish any remaining Executor responsibilities locally, run required evidence, then spawn a separate QA Reviewer.
- 2026-06-09 17:52 CEST - phase: local recovery direct test failed, pending triage; files inspected or touched: `test/features/feed/presentation/screens/feed_wired_test.dart`; failing command/result: `dart format test/features/feed/presentation/screens/feed_wired_test.dart && flutter test test/features/feed/presentation/screens/feed_wired_test.dart` failed with `+89 -2` after adding synchronous fake delivery to the relay-hash media widget regression; failing file/test: same required widget suite, specific failure names truncated by command output; log path: none; focused triage command: `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --reporter json > /tmp/feed_wired_test_local_recovery.jsonl 2>&1` followed by failure-record inspection; classification: pending_triage; next action: capture JSON log and inspect failure records before any further fix.
- 2026-06-09 17:54 CEST - phase: local recovery direct test failures triaged before fixture fix; files inspected or touched: `/tmp/feed_wired_test_local_recovery.jsonl`, `test/features/feed/presentation/screens/feed_wired_test.dart`, `lib/features/feed/presentation/screens/feed_wired.dart`; failing command/result: focused one-at-a-time media widget runs still failed with `FeedCard` not found and no post-emit verifier or feed-refresh telemetry; focused triage result: existing non-media group refresh proves the production subscription path with normal async stream delivery, while the new synchronous-controller/runAsync fixture prevents the media events from reaching the widget callback; classification: session-caused test-fixture delivery issue; next action: revert media regressions to normal asynchronous fake stream delivery, emit in the widget-test zone, then use `runAsync` only as a real-I/O settle window.
- 2026-06-09 17:58 CEST - phase: local recovery widget verifier fix completed; files inspected or touched: `lib/features/feed/application/group_feed_media_verification.dart`, `test/features/feed/presentation/screens/feed_wired_test.dart`, and focused widget output; command/result: `dart format lib/features/feed/application/group_feed_media_verification.dart test/features/feed/presentation/screens/feed_wired_test.dart` passed, `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "incremental group message carries media attachments to feed card" --reporter expanded` passed, and `flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name "incremental group message blocks tampered done media in feed card" --reporter expanded` passed; decision/blocker: verifier file stat now uses sync `existsSync`/`lengthSync`, matching the existing sync MIME verifier and preventing widget fake-async stalls while preserving product behavior; next action: rerun all required direct tests in plan order.
- 2026-06-09 18:00 CEST - phase: required direct tests passed; files inspected or touched: feed verifier, feed application/projection/widget tests, account migration manifest/bundle tests, and download media tests; command/result: `flutter test test/features/feed/application/load_feed_use_case_test.dart` passed, `flutter test test/features/feed/application/feed_projection_test.dart` passed, `flutter test test/features/feed/presentation/screens/feed_wired_test.dart` passed, `flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart test/features/account_migration/application/migration_file_manifest_validator_test.dart test/features/account_migration/application/account_migration_bundle_transfer_test.dart` passed, and `flutter test test/features/conversation/application/download_media_use_case_test.dart` passed; decision/blocker: no direct-test blocker remains; next action: run named host gate `./scripts/run_test_gates.sh groups`.
- 2026-06-09 18:01 CEST - phase: required named host gate passed; files inspected or touched: group/feed/account migration touched files and group gate output; command/result: `./scripts/run_test_gates.sh groups` completed with exit code 0 and `00:55 +324: All tests passed!`; decision/blocker: no host-gate blocker remains; next action: inspect simulator entrypoints, add or reuse the required group-media durability simulator scenario, then run the required simulator list and focused scenario commands.
- 2026-06-09 18:02 CEST - phase: simulator closure pending; files inspected or touched: `integration_test/foreground_group_push_drain_test.dart`, `integration_test/group_new_member_media_simulator_proof_test.dart`, and reliability-sim skill instructions; command/result: nearby integration files inspected and the plan-named `integration_test/account_migration_group_media_durability_simulator_test.dart` is not present; decision/blocker: required simulator proof is still missing and must be added or mapped to an existing scenario before QA can accept closure; next action: implement the narrow simulator scenario with existing fake group/media/account-migration helpers, then run `run_with_devices.sh group --list --include-direct-targets` and the focused `--only` scenario.
- 2026-06-09 18:06 CEST - phase: simulator scenario added; files inspected or touched: `integration_test/account_migration_group_media_durability_simulator_test.dart`, `scripts/check_reliability_simulation_discovery.sh`, and `scripts/run_test_gates.sh`; command/result: new direct integration scenario added for relay-hash group media feed durability plus critical missing group-media bundle failure, and registered with reliability discovery/optional direct targets; `dart format integration_test/account_migration_group_media_durability_simulator_test.dart` formatted the Dart file, while the same accidental formatter invocation rejected shell-script inputs without modifying them; decision/blocker: no shell-format blocker, but the new scenario still needs compile/run evidence and reliability list/run evidence; next action: run the new integration target directly, fix any scenario compile/runtime issue, then run the required reliability list and focused `--only` command.
- 2026-06-09 18:07 CEST - phase: simulator direct run failed before test execution, pending triage; files inspected or touched: `integration_test/account_migration_group_media_durability_simulator_test.dart`; failing command/result: `flutter test integration_test/account_migration_group_media_durability_simulator_test.dart --reporter expanded` exited 1 because multiple devices were connected and no `-d` was specified, so no test body ran; log path: none; focused triage command: `run_with_devices.sh group --list --include-direct-targets` followed by the required focused `--only integration_test/account_migration_group_media_durability_simulator_test.dart`; classification: environment/tooling-related device selection miss, not a product/test assertion failure; next action: use the reliability device resolver required by the plan.
- 2026-06-09 18:12 CEST - phase: focused simulator run failed before test execution, pending triage; files inspected or touched: `integration_test/account_migration_group_media_durability_simulator_test.dart` and reliability wrapper output; failing command/result: `run_with_devices.sh group --include-direct-targets --only integration_test/account_migration_group_media_durability_simulator_test.dart` exited 1 during iOS build with Dart compile errors in the new test file (`MigrationDatabaseCipherMetadata`/`MigrationDatabaseCipherPolicy` not imported, `sqlcipher.databaseFactory` setter not found, and transfer SHA helpers not imported); log path: none; focused triage command: inspect account migration imports/API exports, patch only the new test imports/platform init/hash helpers, format, then rerun the same focused reliability command; classification: session-caused test compile issue; next action: fix new test compile shape without touching production behavior.
- 2026-06-09 18:13 CEST - phase: simulator scenario compile fix completed; files inspected or touched: `integration_test/account_migration_group_media_durability_simulator_test.dart`; command/result: imported the public migration database/transfer manifest models, switched desktop SQLite init to the FFI package's `databaseFactory`, formatted the file, and `dart analyze integration_test/account_migration_group_media_durability_simulator_test.dart` passed with no issues; decision/blocker: previous compile blocker is resolved; next action: rerun focused reliability command `run_with_devices.sh group --include-direct-targets --only integration_test/account_migration_group_media_durability_simulator_test.dart`.
- 2026-06-09 18:17 CEST - phase: required simulator closure passed; files inspected or touched: `integration_test/account_migration_group_media_durability_simulator_test.dart`, `scripts/check_reliability_simulation_discovery.sh`, and `scripts/run_test_gates.sh`; command/result: `run_with_devices.sh group --list --include-direct-targets` passed and listed the new scenario as group plan item #1 on single-device simulator `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`; `run_with_devices.sh group --include-direct-targets --only integration_test/account_migration_group_media_durability_simulator_test.dart` passed with `+2: All tests passed!` and `PASS: reliability simulations completed for scope: group`; decision/blocker: simulator/device evidence requirement is satisfied for the new durability scenario; next action: run final format, `git diff --check`, `graphify update .`, and then spawn QA Reviewer.
- 2026-06-09 18:21 CEST - phase: final hygiene and current-script host gate passed; files inspected or touched: all Dart files touched by this plan, `graphify-out/`, and current group gate output; command/result: `dart format ...` on 11 touched Dart files completed with 0 changes, `git diff --check` passed, `graphify update .` completed after AST extraction of 4969 files and rebuilt `graphify-out`, and rerun `./scripts/run_test_gates.sh groups` completed with `00:55 +324: All tests passed!`; decision/blocker: no formatter, whitespace, graph, direct-test, host-gate, or simulator-gate blocker remains before QA; next action: spawn isolated QA Reviewer with requested `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-09 18:22 CEST - phase: QA Reviewer spawned/running; files inspected or touched: this plan; command currently running: spawned QA Reviewer agent `019ead30-d86c-7730-8795-eaeb75ddc25b` (`McClintock`) with requested `model: gpt-5.5` and `reasoning_effort: xhigh`; decision/blocker: pending isolated QA sufficiency verdict; next action: wait for QA Reviewer result before final verdict.
- 2026-06-09 18:25 CEST - phase: QA Reviewer completed/final verdict written; files inspected or touched: QA Reviewer result and this plan; command/result: QA Reviewer agent `019ead30-d86c-7730-8795-eaeb75ddc25b` returned `no blocking issues`, with only non-blocking follow-ups for untracked files needing inclusion in the final patch/commit and optional test-gate docs polish; decision/blocker: accepted, no blocking issues remain and no fix pass is needed; next action: final controller response.

## 1. real scope

Fix local durability for already-downloaded group chat media by changing feed-side display verification so it no longer validates decrypted plaintext bytes against `MediaAttachment.contentHash`, because that field is the relay/encrypted blob hash. Keep relay download validation, MIME checks, size checks, import behavior, and Move Account relay-free policy unchanged.

The session also owns targeted telemetry around feed-side group media display verification and any feed-side quarantine/delete decision so the next run can distinguish: relay-hash mismatch avoided, missing local file, invalid metadata, plaintext MIME/size rejection, explicit delete/quarantine caller, and "display allowed without plaintext hash validation".

The triage adds a second required fail-safe scope: Move Account bundle assembly must not sanitize missing **critical** chat media into a successful transfer. Missing critical group/1:1 media bytes must remain blocking, must not null the source DB row as a "success" side effect, and must set audit risk clearly. Non-critical cache media can remain non-blocking.

## 2. closure bar

Good enough means:

- A group media row with `download_status='done'`, a local plaintext file, complete encryption metadata, and a relay/encrypted `contentHash` survives feed refresh and group incremental refresh.
- The feed verifier does not delete that plaintext merely because plaintext SHA-256 differs from relay blob SHA-256.
- Truly missing local files still surface as pending/recoverable and emit diagnostics.
- Malformed/missing required metadata still blocks display, but does not silently delete local plaintext without a caller/reason telemetry event.
- Move Account still bundles only local bytes and still reports missing files if bytes are not present.
- A Move Account transfer cannot succeed when required/critical chat media is missing locally.
- `sanitize_missing_media_without_relay` cannot downgrade critical media issues, cannot mutate critical rows to `local_path=NULL` as part of a successful transfer, and cannot report `relayDependencyRisk:false` when missing required media was sanitized.
- Host tests prove the feed seam. Simulator/device evidence proves the user-observed group media refresh path before claiming end-to-end closure.

## 3. source of truth

Current code and tests win over docs. `test-gate-definitions.md` is the gate source of truth. `MediaAttachment.contentHash` documentation is authoritative for hash semantics: it is the canonical SHA-256 digest for group media relay blob bytes. The MIG-012 relay-independent media plan is authoritative for Move Account closure: a transfer must fail before success if critical media bytes are truly missing locally. The triage report is useful evidence, but its agent-count/process claims and unavailable log-line citations are not independent proof; only repo-verifiable code paths and closure-bar contradictions are plan inputs.

## 4. session classification

implementation-ready, with simulator-backed closure required before calling the user journey fully closed. If simulators/devices are unavailable, implementation may be host-green but the session remains evidence-gated.

## 5. exact problem statement

During group media download, the app stores decrypted plaintext at `media/<groupId>/<blobId>.<ext>` and records `download_status='done'`. The feed verifier later validates that plaintext file against `contentHash`, but `contentHash` represents the encrypted relay blob. A mismatch can cause `File.delete()` from feed display code, bypassing `APP_OWNED_MEDIA_DELETE_*` telemetry and leaving the DB row as `done` with a valid local path but no file.

Move Account then correctly detects that the file is missing, but the current downgrade path can convert a blocking `missingRequiredFile` issue for critical chat media into a non-blocking sanitized issue, null the live source DB row, export that downgraded state, and report `relayDependencyRisk:false`. That is the relay-leak amplifier: it turns missing critical media into a successful transfer whose only practical recovery path is relay download after import.

## 6. files and repos to inspect next

Production:

- `lib/features/feed/application/group_feed_media_verification.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/load_group_feed_snapshot_use_case.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/core/media/app_owned_media_delete_telemetry.dart`
- `lib/core/utils/flow_event_emitter.dart`
- `lib/features/account_migration/application/migration_file_manifest_builder.dart`
- `lib/features/account_migration/application/account_migration_bundle_transfer.dart`
- `lib/features/account_migration/domain/models/migration_file_manifest.dart`

Tests:

- `test/features/feed/application/load_feed_use_case_test.dart`
- `test/features/feed/application/feed_projection_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/account_migration/application/migration_file_manifest_builder_test.dart`
- `test/features/account_migration/application/account_migration_bundle_transfer_test.dart`
- new or extended simulator proof under `integration_test/`

## 7. existing tests covering this area

Existing feed tests currently pin the wrong behavior and must be changed first:

- `loadGroupFeedItems blocks tampered done group media` expects a local file to be deleted after content hash mismatch.
- `feed_projection_test` has the same deletion expectation for group snapshots.
- `feed_wired_test` verifies malformed hash marks feed media integrity-failed but does not prove relay-hash plaintext survival.

Existing download tests cover relay/encrypted hash validation and delayed post-commit probes. Existing migration tests cover `source_file_missing` diagnostics and relay-free missing-media downgrade.

`test/features/account_migration/application/account_migration_bundle_transfer_test.dart` currently contains `downgrades missing chat media and continues relay-free`, which pins the amplifier as desired behavior. That test must be reversed or split into critical-vs-noncritical cases.

## 8. regression/tests to add first

Add or update failing tests before implementation:

- `load_feed_use_case_test`: create a local plaintext file with bytes A and a valid 64-char `contentHash` for different relay bytes B. Assert `loadGroupFeedItems` returns `done`, preserves/resolves `localPath`, does not delete the file, and emits feed verifier telemetry with `contentHashScope: relay_blob` and `plaintextHashValidationSkipped: true`.
- `feed_projection_test`: same proof through `loadGroupFeedSnapshot`.
- `feed_wired_test`: incremental group message refresh with a valid relay hash and complete encryption metadata must keep the local file and keep media displayable.
- `group_feed_media_verification` telemetry test: missing local file emits a distinct event and returns pending without delete telemetry.
- Update existing tampered tests so "malformed/missing relay hash" blocks display but does not assert raw plaintext deletion unless a new explicit quarantine path intentionally deletes with app-owned delete telemetry.
- Account migration guard test: after feed refresh on a local group media file with relay hash semantics, `migration_file_manifest_builder` still includes that file; this prevents regressions back to the 5/7 bundle outcome.
- Reverse the migration downgrade regression: missing critical chat media must throw `AccountMigrationBundleAssemblyException` with reason `fileManifestBlockingIssues`, leave the source DB media row unchanged, and emit an audit with `relayDependencyRisk:true`.
- Add a non-critical-cache control if the implementation keeps sanitization: missing `videoThumbnail` or other non-critical cache items may remain non-blocking, and only those may be sanitized.
- Add audit coverage that `sanitizedMissingMediaCount > 0` cannot produce `relayDependencyRisk:false`.

## 9. step-by-step implementation plan

1. Add the red tests above and confirm the current code fails by deleting or integrity-failing a valid downloaded plaintext whose hash differs from the relay hash.
2. In `group_feed_media_verification.dart`, remove plaintext SHA-256 validation against `attachment.contentHash` for encrypted group media. Treat valid `contentHash` as metadata presence and rely on download-time encrypted blob validation.
3. Preserve existing display refusal for missing/malformed `contentHash`, missing encryption metadata, missing file, invalid status, and unresolved path.
4. Add feed verifier telemetry events using `emitFlowEvent`, with sanitized fields only:
   - `GROUP_FEED_MEDIA_DISPLAY_VERIFY_START`
   - `GROUP_FEED_MEDIA_DISPLAY_VERIFY_ALLOWED`
   - `GROUP_FEED_MEDIA_DISPLAY_VERIFY_BLOCKED`
   - `GROUP_FEED_MEDIA_LOCAL_FILE_MISSING`
   - `GROUP_FEED_MEDIA_PLAINTEXT_HASH_VALIDATION_SKIPPED`
   Include attachment ID prefix, message ID prefix, path kind, file exists, file bytes, expected size, has content hash, has encryption metadata, status, reason, and whether delete was attempted.
5. If any feed-side delete remains necessary, route it through `deleteAppOwnedMediaFileIfExists` or `MediaFileManager.deleteFile` with caller/reason. Do not keep raw `File.delete()` for app-owned media.
6. Re-run direct tests. If tests show a real need for plaintext integrity beyond relay blob validation, stop and split a new design task for a separate plaintext hash column; do not overload `contentHash`.
7. Add the migration fail-closed red tests before changing migration code.
8. Make `_shouldDowngradeMissingChatMediaIssue` criticality-aware. If issue criticality is not available on `MigrationFileManifestIssue`, add minimal criticality plumbing or resolve criticality by source/kind without weakening manifest item semantics.
9. Preserve blocking issues for critical `media_attachments` missing files and throw before payload success. Do not null `local_path` or set `integrity_failed` on critical rows as part of a successful transfer.
10. Fix relay-free media audit semantics so sanitized missing media is visible as risk, not hidden by a post-downgrade `blockingIssueCount == 0`.
11. Add or extend one simulator/device scenario that downloads group media, lets feed/group refresh run, then verifies the source device local group media file exists before Move Account packaging, and verifies a deliberately missing critical media row fails the old-phone bundle assembly instead of producing a successful 5/N bundle.
12. Run closure gates and update docs only after tests pass.

## 10. risks and edge cases

- Security regression risk: do not weaken relay/encrypted blob integrity validation in `downloadMedia`.
- Tampered local plaintext after download: current schema does not have a plaintext hash. Do not pretend `contentHash` proves plaintext after decrypt. If product requires at-rest plaintext tamper detection, add a separate future plan.
- Missing files should remain recoverable/pending and should not be silently displayed.
- Foreground/background feed refresh can run within one second of download commit, so telemetry must prove ordering and delete attempts.
- Migration should not fetch relay media to paper over local durability failures.
- Fail-closed migration behavior will surface as a user-facing Move Account failure if critical bytes are genuinely absent. That is intentional per MIG-012; do not convert it back into a "successful" incomplete transfer.
- Adding criticality to manifest issues must not make cache files blocking.

## 11. exact tests and gates to run

Red/green direct tests:

```bash
flutter test test/features/feed/application/load_feed_use_case_test.dart
flutter test test/features/feed/application/feed_projection_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart test/features/account_migration/application/migration_file_manifest_validator_test.dart test/features/account_migration/application/account_migration_bundle_transfer_test.dart
flutter test test/features/conversation/application/download_media_use_case_test.dart
```

Named host gate:

```bash
./scripts/run_test_gates.sh groups
```

Simulator/device closure gate, list first:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list --include-direct-targets
```

Then run the new or extended group-media durability scenario:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --include-direct-targets --only integration_test/account_migration_group_media_durability_simulator_test.dart
```

If implementation chooses to extend `integration_test/foreground_group_push_drain_test.dart` instead of adding a new file, replace the `--only` path with that file and document the scenario name in the final evidence.

Final hygiene:

```bash
dart format <touched dart files>
git diff --check
graphify update .
```

## 12. known-failure interpretation

Pre-existing dirty files and unrelated failing gates do not block this session unless the same direct tests or group reliability scenario fail because of the changed verifier/telemetry. If `./scripts/run_test_gates.sh groups` fails in unrelated membership/invite suites, capture the first failing test, rerun the focused direct tests, and classify the session as evidence-gated until the unrelated failure is separated.

## 13. done criteria

- Direct feed tests prove valid relay-hash group media plaintext is not deleted by feed refresh.
- Direct feed tests prove missing file and invalid metadata produce telemetry and safe display state.
- Existing tampered tests no longer encode the false plaintext-vs-relay hash assumption.
- Migration manifest/account bundle tests prove the file remains includable after feed refresh.
- Account migration tests prove missing critical chat media blocks bundle assembly, does not mutate the source row to sanitized `integrity_failed`, and reports relay dependency risk truthfully.
- Account migration tests prove any remaining sanitization is limited to non-critical cache artifacts.
- No raw feed-side `File.delete()` remains for app-owned group media without app-owned delete telemetry.
- Required telemetry is asserted in tests and contains no plaintext, key, nonce, group name, sender name, or full peer ID.
- `./scripts/run_test_gates.sh groups` passes or failures are classified as unrelated.
- The group reliability simulator scenario passes, or closure is explicitly evidence-gated due to device/simulator unavailability.

Coverage ledger for user requirements:

- Pinpoint further blind spots: covered by feed verifier start/allowed/blocked/missing/skipped telemetry plus delete caller/reason telemetry.
- Sufficient tests: covered by direct feed, widget, migration guard, migration fail-closed, download regression, named group gate, and simulator/device scenario.
- Fix finding: covered by removing plaintext validation against relay hash, preserving local file durability before Move Account, and preventing a successful transfer when critical media is still missing.

## 14. scope guard

Do not change relay media upload/download wire format, encryption, relay store policy, Move Account bundle/import relay independence, or migration local file candidate ordering unless a red test proves it is necessary. Do not add a new media hashing architecture in this session. Do not fetch missing media from relay during Move Account. Do not implement "relay-aware re-materialization before bundling"; it is a product/architecture change that conflicts with relay-independent closure unless separately approved.

## 15. accepted differences / intentionally out of scope

At-rest plaintext tamper detection is out of scope because the existing `contentHash` is explicitly relay-blob scoped. A future design may add `plaintext_hash` or encrypted local storage, but this session should not overload `contentHash`. Relay re-materialization on the source phone is intentionally out of scope. The triage's iPhone receiver-status contradiction is not actionable for this fix beyond telemetry; the decisive import fact is that bytes were absent and the phone later used relay. Physical Pixel-to-iPhone acceptance is not required for host implementation, but simulator/device evidence is required before end-to-end closure.

## 16. dependency impact

Move Account media completeness depends on local group media durability and fail-closed handling for missing critical media. If this plan changes, MIG-012 relay-independent media acceptance must be re-evaluated because it assumes the source phone can only bundle bytes already durable locally and must not claim success when critical bytes are absent. Feed and group-message refresh paths also depend on this fix to avoid silently downgrading downloadable historical media.

## Reviewer Pass

Verdict: sufficient with adjustments. The original narrow feed fix is correct, but host-only closure is insufficient for the user-observed multi-device journey. The plan includes the missing simulator/device evidence gate and requires telemetry assertions, not only runtime logging.

Missing or weak areas resolved in this plan:

- Added `$run-flutter-reliability-sims` group closure command.
- Required replacing existing tests that currently assert deletion.
- Added migration guard proof after feed refresh.
- Added raw-delete telemetry guard.

## Arbiter Pass

Structural blockers: none remaining.

Incremental details intentionally deferred:

- Exact simulator scenario file can be new or an extension of `foreground_group_push_drain_test.dart`; implementation should choose based on nearby harness reuse.
- Optional documentation updates to `test-gate-definitions.md` can be done during closure if a new simulator file is added.

Accepted differences:

- The plan does not add plaintext hash persistence.
- The plan does not change Move Account to fetch missing relay media.
- The plan does not claim final Pixel-to-iPhone release acceptance without simulator/device evidence.
