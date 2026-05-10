Status: executed-accepted

# PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS Plan

## Planning Progress

- 2026-05-10T08:07:36Z - Evidence Collector started. Files inspected since last update: workspace root, git status, intended plan path existence. Decision/blocker: target plan path confirmed; worktree is dirty with many unrelated modified and untracked files, so this planning task must edit only this plan file. Next action: inspect the breakdown artifact, reusable harness files, adjacent helpers, and live device availability.
- 2026-05-10T08:12:10Z - Evidence Collector completed; Planner started. Files inspected since last update: breakdown prerequisite/session ledger/checkpoint policy, `flutter devices --machine`, `xcrun simctl list devices available`, `integration_test/scripts/run_routing_smoke_e2e.dart`, `integration_test/scripts/run_group_multi_device_real.dart`, `integration_test/group_smoke_alice_harness.dart`, `integration_test/group_smoke_bob_harness.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/scripts/run_group_invite_status_matrix_sim.dart`, `integration_test/group_invite_status_matrix_harness.dart`, `scripts/run_test_gates.sh`, `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: evidence supports a repo-owned multi-party Flutter device/simulator harness prerequisite, not GM-001/GM-002 row closure. Next action: draft a narrow implementation-ready plan with device/relay proof profile, owner files, tests, and scope guards.
- 2026-05-10T08:18:40Z - Planner completed; Reviewer started. Files inspected since last update: same evidence set plus current plan draft. Decision/blocker: draft keeps this as shared prerequisite harness work and does not edit source matrix closure statuses. Next action: review the plan for missing device/relay profile details, owner files, gates, closure/docs boundaries, and scope guard.
- 2026-05-10T08:21:30Z - Reviewer completed; Arbiter started. Files inspected since last update: full plan draft, mandatory sections, device/relay proof profile, gate contract, closure/docs update boundary, checkpoint policy. Decision/blocker: sufficient with adjustment to make final execution-ready status explicit. Next action: classify findings and finalize.
- 2026-05-10T08:22:10Z - Arbiter completed. Files inspected since last update: reviewer findings and final plan artifact. Decision/blocker: no structural blockers remain; incremental filename flexibility is documented and does not weaken the execution contract. Next action: hand off as execution-ready.

## Execution Progress

- 2026-05-10T08:15:00Z - Controller started contract extraction. Files inspected or touched: this plan, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`, execution skill instructions. Command currently running: none. Decision/blocker: plan is concrete enough to execute; spawned isolation is available through `codex exec`. Next action: record required starting `git status --short`, `flutter devices --machine`, and `xcrun simctl list devices available` evidence before implementation.
- 2026-05-10T08:15:27Z - Controller completed contract extraction and starting evidence capture. Files inspected or touched: this plan only. Commands completed: `git status --short`, `flutter devices --machine`, `xcrun simctl list devices available`. Decision/blocker: worktree is already dirty with many unrelated modified/untracked files; this plan is untracked and now carries execution progress. Live Flutter targets include Pixel 6 `21071FDF600CSC`, Saleh's iPhone `00008030-001A6D2801BB802E`, booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`, plus macOS and Chrome; `simctl` confirms the four iOS 26.1 simulators are booted. Next action: spawn Executor agent for scoped harness implementation.
- 2026-05-10T08:16:19Z - Controller attempted Executor spawn. Files inspected or touched: this plan. Command completed: `codex exec ... -a never ...` failed before child materialization because this local `codex exec` subcommand rejected `-a`. Decision/blocker: command syntax issue only; no child work started and no code/test files were touched by the failed attempt. Next action: retry Executor spawn with supported `codex exec` flags while preserving `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10T08:17:18Z - Executor started scoped implementation pass. Files inspected or touched: this plan, implementation execution skill, current `git status --short`. Commands completed: `git status --short`, `date -u +%Y-%m-%dT%H:%M:%SZ`. Decision/blocker: scope remains the prerequisite harness only; unrelated dirty files will be left untouched. Next action: inspect referenced harness patterns, then add the criteria helper and host tests first.
- 2026-05-10T08:18:06Z - Executor completed live availability refresh. Files inspected or touched: this plan. Commands completed: `flutter devices --machine`, `xcrun simctl list devices available`. Decision/blocker: enough supported Flutter targets are currently live for GM-001 and GM-002 preparatory proof; four booted iOS simulators remain visible to Flutter (`38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`). Next action: inspect referenced harness patterns and add host-testable criteria first.
- 2026-05-10T08:20:24Z - Executor completed harness pattern inspection. Files inspected or touched: `integration_test/scripts/run_routing_smoke_e2e.dart`, `integration_test/scripts/run_group_multi_device_real.dart`, `integration_test/group_smoke_alice_harness.dart`, `integration_test/group_smoke_bob_harness.dart`, `integration_test/group_multi_device_real_harness.dart`, `integration_test/scripts/run_group_invite_status_matrix_sim.dart`, `integration_test/group_invite_status_matrix_harness.dart`, `integration_test/scripts/routing_smoke_group_criteria.dart`, `test/integration/routing_smoke_group_criteria_test.dart`, group message/member/use-case model files, this plan. Commands completed: `wc -l ...`, `rg -n ...`, multiple `sed -n ...` file reads. Decision/blocker: existing MD-004 and smoke harnesses provide reusable DB stack, group fixture import/export, shared signal, launch, and cleanup patterns; no production defect found. Next action: add `group_multi_party_device_criteria.dart` and focused host tests.
- 2026-05-10T08:23:51Z - Executor added and validated host criteria helper. Files inspected or touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan. Commands completed: `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (formatted two new files and exited 1 because changes were applied), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 8 tests). Decision/blocker: criteria now rejects under-specified devices, duplicate device targets, missing/wrong relay env, missing verdict roles, sender-only evidence, duplicate receiver persistence, and incomplete GM-002 membership convergence. Next action: implement the Flutter multi-party harness and orchestrator using this helper.
- 2026-05-10T08:30:45Z - Executor landed orchestrator/harness structural pass. Files inspected or touched: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan. Commands completed: `dart format --set-exit-if-changed integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` (first full run formatted two newly added harness files, rerun passed with 0 changed), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 8 tests), `flutter analyze integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, no issues after replacing harness `print` calls and interpolation nits). Decision/blocker: owned files compile/analyze structurally. Next action: attempt GM-001 and GM-002 device proof commands with the exact relay env and live simulator IDs.
- 2026-05-10T08:40:48Z - Executor completed required live device proof attempts. Files inspected or touched: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, this plan. Commands completed: `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (pass), `MKNOON_RELAY_ADDRESSES=... dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485` (pass). GM-001 logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_lB8gEC`, run id `1778401870395`; GM-002 logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_GnlXsv`, run id `1778402193277`. Decision/blocker: live prerequisite proof passed for A/B/C and A/B/C/D Flutter app peers; this does not close GM-001/GM-002 rows. Cleanup filter was narrowed afterward to suppress benign `found nothing to terminate` simulator messages in future runs. Next action: rerun final format/test/analyze after cleanup tweak, then run `./scripts/run_test_gates.sh groups` and `git diff --check`.
- 2026-05-10T08:42:13Z - Controller performed file-backed proof/handoff checkpoint after outer visibility concern. Files inspected or touched: this plan, `/tmp/prereq_gm_executor_result.md`, GM-001 artifact directory, GM-002 artifact directory, process table. Commands completed by controller: `ps -axo pid,etime,stat,command | rg 'run_group_multi_party_device_real|group_multi_party_device_real_harness|flutter drive|dart.*group_multi_party|codex exec'`, `ls -l /tmp/prereq_gm_executor_result.md`, `jq . /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_lB8gEC/gmp_1778401870395_gm001_orchestrator_verdict.json`, `jq . /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_GnlXsv/gmp_1778402193277_gm002_orchestrator_verdict.json`, `find .../group_multi_party_gm001_lB8gEC -maxdepth 1 -type f -print | sort`, `find .../group_multi_party_gm002_GnlXsv -maxdepth 1 -type f -print | sort`, `wc -c .../*.log`. Exact GM-001 proof command observed/recorded: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`; verdict: `ok: true`, detail `gm001 verdicts valid for alice, bob, charlie`; artifact/log directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_lB8gEC`; verdict file: `gmp_1778401870395_gm001_orchestrator_verdict.json`; role verdicts: `gmp_1778401870395_alice_verdict.json`, `gmp_1778401870395_bob_verdict.json`, `gmp_1778401870395_charlie_verdict.json`; logs: `alice.log` 106086 bytes, `bob.log` 76393 bytes, `charlie.log` 71734 bytes. Exact GM-002 proof command observed/recorded: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`; verdict: `ok: true`, detail `gm002 verdicts valid for alice, bob, charlie, dana`; artifact/log directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm002_GnlXsv`; verdict file: `gmp_1778402193277_gm002_orchestrator_verdict.json`; role verdicts: `gmp_1778402193277_alice_verdict.json`, `gmp_1778402193277_bob_verdict.json`, `gmp_1778402193277_charlie_verdict.json`, `gmp_1778402193277_dana_verdict.json`; logs: `alice.log` 142031 bytes, `bob.log` 179417 bytes, `charlie.log` 168164 bytes, `dana.log` 88295 bytes. Decision/blocker: no `run_group_multi_party_device_real` or `flutter drive` process remains because both device proof commands have completed successfully; internal Executor `codex exec` remains alive under PIDs `5845`/`5846`, and `/tmp/prereq_gm_executor_result.md` is absent because the child has not emitted its final handoff yet. At this checkpoint the Executor had just run `bash ./scripts/run_test_gates.sh groups` as child PID `19241`; that gate child exited before this entry was written, but the Executor handoff is still pending. Next action: wait briefly for Executor handoff or final gate/diff status, then proceed to QA Reviewer with the file-backed artifact evidence.
- 2026-05-10T08:44:08Z - Controller completed independent verification after stale Executor handoff. Files inspected or touched: owned harness/test files, this plan, process table, `/tmp/prereq_gm_executor_result.md`. Commands completed: `dart format --set-exit-if-changed integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, 0 changed), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 8 tests), `flutter analyze integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, no issues), `./scripts/run_test_gates.sh groups` (pass, 106 tests), `git diff --check` (pass). Decision/blocker: required direct tests/gates are green from the controller, and both device proof verdict artifacts are green; no implementation blocker found. Internal Executor `codex exec` remains alive under PIDs `5845`/`5846` with no active child process and no `/tmp/prereq_gm_executor_result.md` handoff. Next action: interrupt stale Executor process, record that cleanup, then spawn QA Reviewer with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10T08:45:29Z - Controller classified stale Executor handoff and prepared QA. Files inspected or touched: this plan, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `Test-Flight-Improv/test-gate-definitions.md`, process table, `/tmp/prereq_gm_executor_result.md`. Commands completed: interrupted Executor session `019e10f5-f912-79b2-82ba-8d5d9200ae5b`/PIDs `5845`/`5846` with Ctrl-C after it continued emitting large diff output and still did not write `/tmp/prereq_gm_executor_result.md`; `git status --short`; `git diff -- Test-Flight-Improv/test-gate-definitions.md Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`; `ps -axo pid,etime,stat,command | rg 'codex exec|run_group_multi_party_device_real|flutter drive|prereq_gm_executor_result|prereq_gm_qa_result'`. Decision/blocker: Executor implementation and proof work is usable and independently verified, but its final handoff lag is controller-classified as a non-code orchestration defect; no active `codex exec`, `run_group_multi_party_device_real`, or `flutter drive` process remains. The child also made classification-only doc updates to `test-inventory.md` and `test-gate-definitions.md` for the new criteria test and manual orchestrator, while preserving GM-001/GM-002 as non-closing prerequisite evidence. Next action: spawn fresh QA Reviewer against landed files, docs, tests, gate status, and GM-001/GM-002 artifact verdicts.
- 2026-05-10T08:49:04Z - QA Reviewer completed with blocking finding. Files inspected or touched: no edits by QA; QA read this plan, owned harness/helper/test files, source matrix GM rows, breakdown, `test-inventory.md`, `test-gate-definitions.md`, and GM-001/GM-002 artifact directories. Commands completed by QA included read-only `sed`/`nl`/`jq`/`find`/`wc`/`rg` over the plan, diffs, artifacts, and source matrix. Decision/blocker: QA verdict `needs_fix`; artifacts are real and green, GM-001/GM-002 source rows remain `Open`, but `integration_test/scripts/group_multi_party_device_criteria.dart` does not yet enforce receiver `messageId`, `text`/plaintext, and shared epoch against the sender `sentMessages` tuple, so future row sessions could trust an under-validated prerequisite verdict. Next action: spawn fresh Executor fix pass 1 with `model: gpt-5.5` and `reasoning_effort: xhigh` scoped to criteria/helper tests and required validation reruns.
- 2026-05-10T08:17:00Z - Executor spawned/running. Files inspected or touched by controller: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" -c approval_policy="never" -s danger-full-access ...` with output handoff `/tmp/prereq_gm_executor_result.md`. Decision/blocker: spawned child materialized with session id `019e10f5-f912-79b2-82ba-8d5d9200ae5b`, approval `never`, sandbox `danger-full-access`, model `gpt-5.5`, reasoning effort `xhigh`. Next action: bounded wait for Executor completion and inspect assigned files/evidence.
- 2026-05-10T08:44:12Z - Executor completed final validation and documentation classification. Files inspected or touched: `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan. Commands completed since the prior Executor entry: final `dart format --set-exit-if-changed ...` (pass, 0 changed), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 8 tests), `flutter analyze ...` (pass, no issues), `./scripts/run_test_gates.sh groups` (pass, `All tests passed!`), `./scripts/run_test_gates.sh completeness-check` after gate-doc classification (pass, `731/731` files classified), `git diff --check` before and after documentation edits (pass), and `git status --short` (still shows unrelated pre-existing dirty files plus this session's new harness files/docs). Decision/blocker: prerequisite harness implementation and GM-001/GM-002-shaped live proof are complete with no blocker; `test-gate-definitions.md` classifies the host criteria test and multi-party orchestrator as optional/manual and `test-inventory.md` records run commands without closing GM rows. GM-001 and GM-002 source row statuses were not edited and remain row-session work. Next action: hand off to QA Reviewer with artifact directories and command evidence.
- 2026-05-10T08:53:39Z - Executor fix pass 1 started for QA blocking finding. Files inspected or touched: this plan, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, recorded GM-001/GM-002 role verdict JSON artifacts. Commands completed: `git status --short`, read-only `nl`/`sed`/`jq`/`rg` over allowed files and existing artifacts. Decision/blocker: recorded artifacts already include compatible `messageId`, `text`, `senderPeerId`, and shared top-level `keyEpoch`; fix is scoped to binding receiver evidence back to the sender `sentMessages` tuple. Next action: implement strict tuple matching and focused negative tests.
- 2026-05-10T08:55:45Z - Executor fix pass 1 implementation checkpoint. Files inspected or touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan. Commands completed: `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` first applied formatting, rerun passed with 0 changed. Decision/blocker: helper now carries each expected sender `sentMessages` tuple into receiver validation and compares `messageId`, `text`/`plaintext`, `senderPeerId`, and sender/receiver `keyEpoch`; tests now include negative cases for wrong receiver id, wrong receiver text, and epoch mismatch. Next action: run required targeted tests, analyzer, and whitespace check.
- 2026-05-10T08:56:32Z - Executor fix pass 1 validation completed. Files inspected or touched: `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, this plan. Commands completed: `dart format --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, 0 changed), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 11 tests), `flutter analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, no issues), `git diff --check` (pass). Decision/blocker: QA blocking finding addressed within the allowed files; no production code, GM source matrix status, staging, commit, or revert was touched. Next action: return fix-pass handoff for QA.
- 2026-05-10T09:03:05Z - Final QA Reviewer and controller gate verification completed. Files inspected or touched: this plan, `/tmp/prereq_gm_qa2_result.md`, source matrix row statuses, owned harness/helper/test files, GM-001 and GM-002 verdict JSON artifacts, process table. Commands completed by final QA: `dart format --output=none --set-exit-if-changed integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, 0 changed), `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass, 11 tests), `flutter analyze integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` (pass, no issues), `git diff --check` (pass). Commands completed by controller after the fix pass: `./scripts/run_test_gates.sh groups` (pass, `00:07 +106: All tests passed!`), `git diff --check` (pass), `ps -axo pid,etime,stat,command | rg 'codex exec|run_group_multi_party_device_real|flutter drive|prereq_gm'` (no active child Executor, multi-party orchestrator, or `flutter drive` process beyond the checking command itself), `git status --short` (dirty worktree remains, with unrelated pre-existing modified/untracked files plus this session's owned files/docs). Decision/blocker: final QA verdict is `accepted`; the earlier QA blocker was fixed by binding receiver evidence to sender `sentMessages` tuple fields (`messageId`, `text`/`plaintext`, `senderPeerId`, `keyEpoch`); the internal Executor handoff lag remains classified as a non-code orchestration defect with file-backed controller verification substituted; no remaining implementation, QA, gate, or live-device blocker. GM-001 and GM-002 source matrix rows remain `Open`; this prerequisite harness is accepted and row-specific GM-001/GM-002 sessions may proceed, but this prerequisite alone does not cover or close either row.

## real scope

Build one reusable repo-owned Flutter integration/device harness prerequisite for private group multi-party proof.

In scope for the future implementation session:

- Add a multi-party orchestrator that launches three or more Flutter app peers on currently available devices/simulators and coordinates them through shared temp-dir signals/verdict JSON.
- Add a reusable Flutter integration harness that can run role-specific group peers for GM-001-style A/B/C creation/fanout and GM-002-style add-D convergence proof.
- Reuse the existing group stack and fixture helpers where practical rather than cloning all setup logic.
- Add focused host-side contract tests for any new pure criteria/parser/verdict validation helper.
- Run live device/simulator proof commands with the exact relay configuration below when enough supported devices are available.
- Update only session-owned closure/inventory notes after execution, and only to record the prerequisite harness result.

Out of scope:

- Do not mark GM-001 or GM-002 `Covered`, `Closed`, or equivalent in the source matrix.
- Do not change GM-001 or GM-002 source row statuses, closure verdicts, or row-specific evidence claims.
- Do not change production group messaging behavior unless the harness exposes a narrow, blocking bug that must be fixed before the harness can run; if that happens, stop and replan because this prerequisite is harness-first.
- Do not widen frozen named gates unless explicitly justified and reviewed; the likely classification is optional/manual or Nightly / Release Pool.

## closure bar

This prerequisite is complete when the repo has a reusable, documented multi-party Flutter app harness that future GM-001 and GM-002 row sessions can invoke without inventing row-local orchestration.

Minimum closure requirements:

- The orchestrator can select explicit role devices from a `-d <alice,bob,charlie[,dana]>` argument and fails clearly when fewer than the scenario-required supported Flutter targets are supplied.
- The orchestrator forwards the exact `MKNOON_RELAY_ADDRESSES` value from the environment into every launched Flutter peer.
- GM-001 preparatory proof is supported: A/B/C are real Flutter app peers in one private group/topic/key epoch; A sends; B and C each persist exactly one matching incoming message; the proof emits a machine-readable verdict.
- GM-002 preparatory proof is supported: A/B/C are online first; A adds D; D joins; A and D send; all eligible Flutter app peers converge on membership and exactly expected messages; the proof emits a machine-readable verdict.
- Direct host contract tests for new criteria/parser code pass.
- Device/simulator proof commands pass on a current three-party/four-party fixture, or the session records a hard blocker with live `flutter devices --machine` and `xcrun simctl list devices available` evidence.
- Closure notes explicitly state that GM-001 and GM-002 remain open until their row-specific sessions consume this harness and run their own proof.

## source of truth

- Current code and tests win over stale prose.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` is authoritative for this session ID, dependency, row-checkpoint policy, and the non-closing relationship to GM-001/GM-002.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are authoritative for named gates and optional/manual versus Nightly / Release Pool classification.
- Existing harness files are implementation evidence, not closure evidence for GM rows:
  - `integration_test/scripts/run_routing_smoke_e2e.dart`
  - `integration_test/scripts/run_group_multi_device_real.dart`
  - `integration_test/group_smoke_alice_harness.dart`
  - `integration_test/group_smoke_bob_harness.dart`
  - `integration_test/group_multi_device_real_harness.dart`
  - `integration_test/scripts/run_group_invite_status_matrix_sim.dart`
  - `integration_test/group_invite_status_matrix_harness.dart`

## session classification

`implementation-ready`

This is a shared prerequisite session with repo-owned code and tests. It is not a source matrix row and cannot close GM-001 or GM-002 by itself.

## exact problem statement

GM-001 and GM-002 already have host/config evidence, but their required Flutter-app multi-party proof is still missing. Existing reusable fixtures cover useful adjacent cases:

- two-simulator routing/group smoke with Alice and Bob;
- two devices plus a CLI peer for MD-004 same-user group behavior;
- four-simulator seeded invite-status display proof.

None of those fixtures proves exact A/B/C or A/B/C/D private group behavior with three or four Flutter app peers over the app relay. The missing piece is a reusable multi-party Flutter device/simulator harness. User-visible reliability improves only after future GM row sessions use this harness to prove real app peer convergence; this prerequisite only prepares that proof surface.

Behavior that must stay unchanged:

- Existing two-peer smoke and MD-004 scripts must keep their current behavior unless a small helper extraction is needed.
- GM-001 and GM-002 source matrix rows remain `Open`.
- Existing named gates remain stable unless a separately justified gate-doc update is made.

## Device/Relay Proof Profile

Classification: multi-party/three-party Flutter device/simulator harness work. This is not single-device proof, not host-only proof, and not two-simulator-only proof.

The future executor must rerun these availability checks immediately before choosing role devices:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Live availability recorded during planning on 2026-05-10T08:08Z:

| Source | Available target observed |
| --- | --- |
| `flutter devices --machine` | Pixel 6 `21071FDF600CSC`, supported Android physical, Android 16 API 36 |
| `flutter devices --machine` | Saleh's iPhone `00008030-001A6D2801BB802E`, supported iOS physical, iOS 26.4.2 |
| `flutter devices --machine` | iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, supported iOS simulator |
| `flutter devices --machine` | iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, supported iOS simulator |
| `flutter devices --machine` | iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, supported iOS simulator |
| `flutter devices --machine` | iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485`, supported iOS simulator |
| `flutter devices --machine` | macOS `macos`, supported desktop |
| `flutter devices --machine` | Chrome `chrome`, supported web |
| `xcrun simctl list devices available` | iOS 26.1 booted: iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485` |
| `xcrun simctl list devices available` | Additional shutdown iOS 18.6, 26.1, 26.2, and 26.4 simulators are available in `simctl`; use only after booting and confirming Flutter sees them |

Use the app relay configuration exactly:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Likely current proof devices if still available at execution time:

- GM-001 preparatory proof: `38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
- GM-002 preparatory proof: `38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485`

These IDs are planning evidence only. Do not hard-code them into source.

## files and repos to inspect next

Likely owner files for implementation:

- `integration_test/scripts/run_group_multi_party_device_real.dart` - new orchestrator for three/four Flutter app peers.
- `integration_test/group_multi_party_device_real_harness.dart` - new role-driven Flutter integration harness.
- `integration_test/scripts/group_multi_party_device_criteria.dart` - optional new pure criteria/verdict helper if the orchestrator needs testable validation logic.
- `test/integration/group_multi_party_device_criteria_test.dart` - optional host test for the criteria/helper.

Reusable reference files to inspect and reuse:

- `integration_test/scripts/run_routing_smoke_e2e.dart` - process launch, signal dir, relay dart-define forwarding, two-phase group smoke orchestration, simulator app termination.
- `integration_test/scripts/run_group_multi_device_real.dart` - two-device orchestration, CLI fixture, `make testpeer`, process piping, relay dart-define forwarding.
- `integration_test/group_smoke_alice_harness.dart` - Alice group creator role, identity exchange, group fixture write, send/drain loops.
- `integration_test/group_smoke_bob_harness.dart` - Bob group joiner role, group fixture import, receive/send/drain loops.
- `integration_test/group_multi_device_real_harness.dart` - reusable database setup, `setupGroupMultiDeviceStack`, `buildGroupFixture`, `importJoinedGroupFixture`, MD-004 role logic, group add-member and offline replay examples.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` - four-role simulator orchestration and verdict validation pattern; reference only because it is seeded UI proof and explicitly not relay/testpeer lifecycle proof.
- `integration_test/group_invite_status_matrix_harness.dart` - four-role harness pattern; reference only.
- `integration_test/scripts/routing_smoke_group_criteria.dart` and `test/integration/routing_smoke_group_criteria_test.dart` - existing pattern for extracting host-testable criteria from an integration orchestrator.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` - gate classification and named command source of truth.

Likely source files to inspect only if a real harness-blocking product defect appears:

- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/bridge/bridge_group_helpers.dart`

## existing tests covering this area

- `test/features/groups/integration/group_messaging_smoke_test.dart` has host/fake-network GM-001 and GM-002 evidence, but it is non-closing for required Flutter device proof.
- `test/features/groups/integration/group_membership_smoke_test.dart`, `group_new_member_onboarding_test.dart`, `member_removal_integration_test.dart`, and `group_startup_rejoin_smoke_test.dart` cover adjacent host group behavior.
- `integration_test/scripts/run_routing_smoke_e2e.dart` and `group_smoke_*_harness.dart` cover two Flutter app peers and group routing smoke scenarios, not A/B/C or A/B/C/D.
- `integration_test/scripts/run_group_multi_device_real.dart` and `group_multi_device_real_harness.dart` cover two Flutter app processes plus a CLI peer for MD-004 same-user/sibling-device behavior, not three/four independent Flutter app peers.
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` covers four simulator roles for seeded invite-status display only and explicitly rejects relay lifecycle proof.
- `./scripts/run_test_gates.sh groups` is the named host group messaging gate.
- `./scripts/run_test_gates.sh group-real-network-nightly` is a fixture-backed group real-network command for `integration_test/multi_relay_failover_test.dart`; it requires `FLUTTER_DEVICE_ID` and is not the multi-party GM harness.

Missing:

- No reusable three-party/four-party Flutter app orchestrator for private group creation, add-member convergence, and exact recipient persistence.
- No machine-readable multi-party verdict helper that future GM row sessions can use as proof input.

## regression/tests to add first

Add the smallest testable contract before wiring full device proof:

1. Add a pure helper for scenario requirements and verdict validation, likely in `integration_test/scripts/group_multi_party_device_criteria.dart`.
2. Add `test/integration/group_multi_party_device_criteria_test.dart` that fails first for the missing helper and then proves:
   - GM-001 requires exactly roles `alice`, `bob`, `charlie` with at least three device IDs.
   - GM-002 requires roles `alice`, `bob`, `charlie`, `dana` with at least four device IDs unless the executor explicitly documents an equivalent multi-party app-peer mapping.
   - Missing relay env, missing role verdicts, duplicate receiver messages, sender-only evidence, and incomplete convergence are rejected.
   - Valid GM-001 and GM-002 verdict payloads are accepted.

Then implement the orchestrator/harness until the host contract and device proof pass.

## step-by-step implementation plan

1. Re-check `git status --short`; record unrelated dirty files; do not revert, stage, or rewrite them.
2. Re-run live availability checks:

   ```bash
   flutter devices --machine
   xcrun simctl list devices available
   ```

   Stop with a prerequisite blocker if fewer than three supported Flutter app targets are available for GM-001 preparatory proof, or fewer than four are available for GM-002 preparatory proof and no explicit equivalent multi-party app-peer mapping is possible.
3. Add the pure criteria/verdict helper and its focused host test first.
4. Add `integration_test/scripts/run_group_multi_party_device_real.dart`:
   - parse `--scenario gm001|gm002|all` and `-d <role-ordered-device-list>`;
   - require the exact relay env to be present and forward it with `--dart-define=MKNOON_RELAY_ADDRESSES=...`;
   - create one shared temp dir and run id;
   - launch Flutter peers sequentially enough to avoid Xcode build/install contention, following the `run_routing_smoke_e2e.dart` pattern;
   - pipe per-role stdout/stderr to role logs;
   - wait for role verdict JSON and process exits;
   - validate verdicts with the helper and exit non-zero on incomplete proof;
   - terminate simulator Runner apps during cleanup when using iOS simulator UDIDs.
5. Add `integration_test/group_multi_party_device_real_harness.dart`:
   - reuse `initializeSqliteForCurrentPlatform`, `setupGroupMultiDeviceStack`, `buildGroupFixture`, `importJoinedGroupFixture`, shared JSON/signal helpers, and group send/drain patterns from existing harnesses;
   - support roles `alice`, `bob`, `charlie`, and `dana`;
   - isolate per-role databases with `E2E_DB_NAME`;
   - exchange identities through shared JSON;
   - for GM-001: Alice adds Bob and Charlie as contacts, creates a chat group, writes group fixture, Bob/Charlie import and join, Alice sends a unique message, Bob/Charlie each drain/listen and write exact verdicts;
   - for GM-002: Alice/Bob/Charlie join first, Dana starts as an online Flutter app peer outside the group, Alice adds Dana with `addGroupMember`, Dana imports/joins updated config, Alice and Dana send unique messages, all eligible peers write exact membership/message verdicts;
   - include group id, topic/config digest if available, key epoch, sender peer id, message id/text token, persisted message counts, and member peer ids in verdicts.
6. Keep existing two-peer and MD-004 scripts behavior-compatible. If helper extraction from existing files is useful, make it mechanical and covered by existing commands.
7. Run formatting/analyzer and host contract tests.
8. Run the device proof with the exact relay env and live-selected devices. Prefer the current booted iOS simulator set if still visible to Flutter; otherwise use whatever live checks show.
9. Run the named group gate and whitespace check.
10. Update only session-owned docs after implementation:
    - this plan with executor/QA evidence and final status;
    - the breakdown's `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS` session closure/ledger notes;
    - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and `Test-Flight-Improv/test-gate-definitions.md` only if classifying the new harness as optional/manual or Nightly / Release Pool is needed.
11. Explicitly do not update GM-001 or GM-002 source row statuses. Future row-specific sessions own those closures.

Stop early if evidence proves an existing reusable three/four-app harness already exists and only needs documentation; otherwise proceed with the smallest new harness above.

## risks and edge cases

- Device availability can change between planning and execution; use live checks, not embedded IDs.
- Multiple `flutter drive` processes can collide during Xcode build/install; launch the first role to ready state before starting the next role, following existing script patterns.
- Simulators may still have a stale Runner process; terminate by bundle id during cleanup for iOS simulator targets.
- Relay config omissions can create skipped pseudo-evidence; fail fast unless the exact `MKNOON_RELAY_ADDRESSES` env is present.
- PubSub discovery may be slower with three/four peers; use bounded waits and explicit verdict failures, not indefinite polling.
- Duplicate messages, sender-only local rows, and inbox-pending evidence must fail the criteria helper.
- D's GM-002 path must prove post-add membership/key convergence, not just receipt of a hand-written fixture.
- Existing dirty files may contain unrelated edits from prior sessions; do not revert them or absorb them into this prerequisite.

## exact tests and gates to run

Initial evidence and availability:

```bash
git status --short
flutter devices --machine
xcrun simctl list devices available
```

Host contract and static checks after implementation:

```bash
dart format --set-exit-if-changed integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test test/integration/group_multi_party_device_criteria_test.dart
flutter analyze integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/group_multi_party_device_real_harness.dart test/integration/group_multi_party_device_criteria_test.dart
```

Device/simulator proof commands, using live device IDs from the execution-time checks:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d <alice_device>,<bob_device>,<charlie_device>

MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g \
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm002 -d <alice_device>,<bob_device>,<charlie_device>,<dana_device>
```

Named gates and final hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Conditional checks:

- If `scripts/run_test_gates.sh` is edited, run `bash -n scripts/run_test_gates.sh`.
- If `Test-Flight-Improv/test-gate-definitions.md` is edited, verify the new harness remains classified consistently with device-bound optional/manual or Nightly / Release Pool policy.
- If production code is touched due to a discovered blocker, stop and replan before running broader production gates.

## known-failure interpretation

- Pre-existing dirty files are not this session's failures. Treat only failures in session-owned files or plan-listed proof commands as prerequisite regressions.
- A device-proof failure caused by fewer available devices is a blocker, not a code regression; record the live availability output and leave GM rows open.
- A relay proof run without the exact relay env is invalid and must not be recorded as passing evidence.
- A two-device-plus-CLI run, two-simulator Alice/Bob run, or four-simulator seeded invite-status run is useful adjacent evidence only; none can close this prerequisite unless the new harness exists and emits multi-party Flutter app peer verdicts.
- If `./scripts/run_test_gates.sh groups` fails in unrelated pre-existing dirty production/test files, record the exact failure and rerun the focused host contract/device proof. Do not silently classify unrelated red as this session's regression, but do not claim complete closure without explaining the gate status.

## done criteria

- New harness owner files exist and are limited to the planned surface.
- Host criteria/parser tests pass.
- The harness rejects under-specified device lists, missing relay env, missing peer verdicts, sender-only receiver evidence, duplicate receiver messages, and incomplete GM-002 convergence.
- GM-001 preparatory device/simulator proof passes with at least three Flutter app peers, or a live device-availability blocker is recorded.
- GM-002 preparatory device/simulator proof passes with at least four Flutter app peers or an explicitly documented equivalent multi-party app-peer mapping, or a live device-availability blocker is recorded.
- `./scripts/run_test_gates.sh groups` and `git diff --check` are run and recorded.
- Closure docs state that this prerequisite is complete or blocked without changing GM-001/GM-002 source row closure statuses.
- The final report lists exact devices, command lines, logs/verdict paths, and whether GM row execution may proceed.

## scope guard

Do not do any of the following in this session:

- Mark GM-001 or GM-002 covered, closed, accepted, or equivalent.
- Edit `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` source row closure statuses.
- Rewrite existing two-peer harnesses for style or broad cleanup.
- Add generalized test-lab scheduling, device pooling, cloud device logic, or a new gate framework.
- Change app UX, group repository semantics, relay protocol, database schema, or Go node behavior unless a harness-blocking bug forces a replan.
- Stage unrelated dirty files or use `git add .`.

## accepted differences / intentionally out of scope

- The existing MD-004 script uses two Flutter app processes plus a CLI peer. This prerequisite intentionally requires three/four Flutter app peers because GM-001 and GM-002 need app-peer proof.
- The existing group smoke path covers Alice/Bob only. It stays as a reference and should not be stretched into a brittle three-party proof unless that is clearly smaller than a new role-driven harness.
- Four-simulator invite-status matrix proof is seeded UI state and intentionally does not claim relay/testpeer lifecycle evidence.
- GM row closure is intentionally deferred to future row-specific sessions that consume this harness and update the source matrix with row evidence.

## dependency impact

- GM-001 depends on this prerequisite for required A/B/C Flutter-app `3-Party E2E` proof.
- GM-002 depends on this prerequisite for required A/B/C/D or equivalent multi-party Flutter-app proof.
- If this prerequisite blocks on device availability, GM-001 and GM-002 remain `Open` with blocker notes; do not attempt row closure from host evidence alone.
- Future GM rows may reuse the harness if they need multi-party Flutter app proof, but they must still own row-specific acceptance criteria and closure updates.

## rollback and blocker conditions

Rollback is scoped to session-owned files only:

- remove or revert `integration_test/scripts/run_group_multi_party_device_real.dart`;
- remove or revert `integration_test/group_multi_party_device_real_harness.dart`;
- remove or revert `integration_test/scripts/group_multi_party_device_criteria.dart` and `test/integration/group_multi_party_device_criteria_test.dart` if added;
- revert only this session's edits to this plan, breakdown ledger notes, test inventory, and gate definitions.

Do not revert unrelated dirty files.

Block execution and record a prerequisite blocker if:

- live checks show fewer than three supported Flutter app targets and no safe simulator boot path is available;
- GM-002 proof cannot access four supported Flutter app targets or an explicitly equivalent app-peer mapping;
- the relay env cannot be set exactly as required;
- multi-peer startup repeatedly fails before any role can reach online state and logs point to infrastructure/device availability rather than code;
- implementing the harness requires production behavior changes beyond a narrow test seam.

## closure/docs updates

Allowed future implementation closure updates:

- Update this plan with executor/QA evidence, command outputs, proof devices, and final verdict.
- Update `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` only for this prerequisite's closure ledger/session notes.
- Update `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` only to inventory the new harness and classify it without overclaiming GM row closure.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if the new harness needs optional/manual or Nightly / Release Pool classification.

Forbidden closure updates in this prerequisite:

- Do not edit GM-001/GM-002 source matrix statuses.
- Do not write a final rollout/program verdict.
- Do not claim GM-001/GM-002 are covered by this prerequisite alone.

## scoped checkpoint note

After closure is durably written and verified, the controller should apply the breakdown's `## Row Checkpoint Commit Policy` with explicit paths only, unless unsafe due to overlapping dirty files.

Explicit paths eligible for a scoped checkpoint, if they are actually owned by the completed session:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS-plan.md`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Before staging, run `git status --short` and inspect scoped diffs. Never stage unrelated dirty files, user edits, generated artifacts, or files being edited by another active session. If a clean scoped checkpoint is unsafe, record `checkpoint_skipped` in the session notes with the reason.

## Reviewer Findings

Reviewer verdict: sufficient with adjustments.

- The draft has the required multi-party device/relay profile and live availability evidence.
- The draft correctly treats existing harnesses as references, not GM closure proof.
- The draft includes owner files, direct tests, named gates, rollback conditions, closure/doc boundaries, and the checkpoint rule.
- Adjustment resolved before finalization: the top-level status is `Status: execution-ready`, Arbiter progress is recorded, and the plan ends with `Status: execution-ready`.

## Arbiter Decision

Structural blockers: none.

Incremental details:

- Future executor may choose slightly different new filenames if an adjacent local convention is discovered, but must keep the same responsibilities and update this plan before implementation if names change.
- The GM-002 "equivalent" mapping is allowed only if it still uses multiple Flutter app peers and is documented with role/device mapping; host-only or CLI-peer substitution is not accepted.

Accepted differences:

- This prerequisite can run GM-001/GM-002-shaped preparatory scenarios without closing those rows.
- Device-bound proof remains outside frozen named gates unless a later gate-doc change is explicitly justified.

## Final verdict

Final plan: execution-safe for exactly one shared prerequisite harness session.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact final filename choices may be adjusted only if the executor finds a stronger adjacent convention and updates this plan before editing code.
- Device role IDs must be selected from execution-time live checks.

Accepted differences intentionally left unchanged:

- This prerequisite prepares GM-001 and GM-002 device proof but does not close either row.
- Existing two-peer, CLI-peer, and seeded four-simulator fixtures remain references only.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `integration_test/scripts/run_routing_smoke_e2e.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `integration_test/group_smoke_alice_harness.dart`
- `integration_test/group_smoke_bob_harness.dart`
- `integration_test/group_multi_device_real_harness.dart`
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart`
- `integration_test/group_invite_status_matrix_harness.dart`
- live `flutter devices --machine`
- live `xcrun simctl list devices available`

Why the plan is safe to implement now: it defines a narrow repo-owned harness prerequisite, records current live device evidence without hard-coding it, requires exact relay configuration, names likely owner files and gates, blocks GM row overclaiming, and preserves unrelated dirty worktree state.

Status: executed-accepted
