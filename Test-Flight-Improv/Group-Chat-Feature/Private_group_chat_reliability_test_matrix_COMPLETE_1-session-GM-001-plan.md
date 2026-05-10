Status: execution-ready

# GM-001 Plan - Three-member private group baseline delivery

## Planning Progress

- 2026-05-10T09:17:25Z - Planner completed. Files inspected since last update: this plan. Decision/blocker: draft is evidence-gated and row-owned for GM-001 only; it removes the obsolete missing-harness blocker without marking GM-001 covered. Next action: reviewer sufficiency pass.
- 2026-05-10T09:17:25Z - Reviewer started. Files inspected since last update: this plan. Decision/blocker: review must check that the plan includes exact device/relay proof, closure guard, host proof, gates, failure classification, and no GM-002 or production/test edits during planning. Next action: classify any missing structural requirements.
- 2026-05-10T09:19:43Z - Reviewer completed. Files inspected since last update: this plan. Decision/blocker: sufficient as-is; no missing mandatory section, stale missing-harness blocker, closure overclaim, or GM-002 scope bleed found. Next action: arbiter classification.
- 2026-05-10T09:19:43Z - Arbiter started. Files inspected since last update: reviewer findings in this plan. Decision/blocker: classify review findings and decide whether a structural patch/final review loop is required. Next action: finalize or patch once if structural blockers exist.
- 2026-05-10T09:20:15Z - Arbiter completed. Files inspected since last update: reviewer pass, mandatory sections, exact command/gate list, and closure guard in this plan. Decision/blocker: no structural blockers; incremental details are documented and do not require a second plan patch/review loop. Next action: hand off as execution-ready.

## Execution Progress

- 2026-05-10T09:22:10Z - Execution controller started. Files inspected or touched: this plan, `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`, `git status --short`. Command currently running: none. Decision/blocker: dirty worktree contains many unrelated modified/untracked files; preserve all unrelated edits and stage/commit nothing. Next action: extract contract and spawn Executor.
- 2026-05-10T09:22:10Z - Contract extracted. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: exact scope is GM-001 evidence only; required proof is fresh device discovery, focused GM-001 host test, criteria guard, exact three-role device command with relay env, verdict JSON inspection, `./scripts/run_test_gates.sh groups`, and `git diff --check`; no GM-002, source matrix, breakdown ledger, or acceptance-criteria weakening allowed. Next action: spawn Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-10T09:22:33Z - Executor spawn/running. Files inspected or touched: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: starting isolated Executor for evidence-only GM-001 pass. Next action: wait for Executor result, then spawn QA Reviewer.
- 2026-05-10T09:23:16Z - Executor spawn retry. Files inspected or touched: this plan. Command currently running: none. Decision/blocker: first spawn command failed before child materialization because `-a` was passed after `codex exec`; no repo changes or partial child work occurred. Next action: restart Executor with Codex top-level options before `exec`.
- 2026-05-10T09:24:29Z - Executor owner-file inspection starting. Files inspected or touched: this plan and `/Users/I560101/.codex/skills/implementation-execution-qa-orchestrator/SKILL.md`. Command currently running: none. Decision/blocker: GM-001 execution contract is evidence-only with exact command order, no source matrix/breakdown closure edits, and no production/test edits unless row-specific proof exposes a product gap. Next action: inspect the GM-001 owner files named by the plan.
- 2026-05-10T09:25:08Z - Executor owner-file inspection completed. Files inspected or touched: `test/features/groups/integration/group_messaging_smoke_test.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, `git status --short`. Command currently running: none. Decision/blocker: owner files already contain the focused GM-001 host proof, three-role orchestrator, exact relay/device criteria guard, and optional/manual inventory classification; dirty worktree has many unrelated edits and must be preserved. Next action: run `flutter devices --machine`.
- 2026-05-10T09:25:26Z - Device discovery started. Files inspected or touched: this plan. Command currently running: `flutter devices --machine`. Decision/blocker: first required command is starting in exact plan order. Next action: record fresh Flutter device inventory.
- 2026-05-10T09:25:57Z - Device discovery completed. Files inspected or touched: this plan. Command completed: `flutter devices --machine` (pass). Decision/blocker: Flutter reports the planned iOS simulator trio available plus spare `1B098DFF-6294-407A-A209-BBF360893485`; physical Pixel 6, physical iPhone, macOS, and Chrome are also visible. Next action: run `xcrun simctl list devices available`.
- 2026-05-10T09:26:09Z - Simulator discovery started. Files inspected or touched: this plan. Command currently running: `xcrun simctl list devices available`. Decision/blocker: second required command is starting after Flutter device discovery passed. Next action: confirm selected simulator runtime availability.
- 2026-05-10T09:26:23Z - Simulator discovery completed. Files inspected or touched: this plan. Command completed: `xcrun simctl list devices available` (pass). Decision/blocker: planned role mapping remains available with iPhone 17 Pro `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, iPhone Air `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and iPhone 17 `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` booted; spare iPhone 16e `1B098DFF-6294-407A-A209-BBF360893485` is booted and not needed. Next action: run focused GM-001 host proof.
- 2026-05-10T09:26:37Z - Focused GM-001 host proof started. Files inspected or touched: this plan. Command currently running: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'`. Decision/blocker: third required command is starting after both device discovery commands passed. Next action: record focused host proof result.
- 2026-05-10T09:27:09Z - Focused GM-001 host proof completed. Files inspected or touched: this plan. Command completed: `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'` (pass). Decision/blocker: host fake-network A/B/C shared epoch and exact fanout tuple proof passed. Next action: run criteria guard.
- 2026-05-10T09:27:22Z - Multi-party criteria guard started. Files inspected or touched: this plan. Command currently running: `flutter test test/integration/group_multi_party_device_criteria_test.dart`. Decision/blocker: fourth required command is starting after focused host proof passed. Next action: record criteria guard result without changing acceptance criteria.
- 2026-05-10T09:27:48Z - Multi-party criteria guard completed. Files inspected or touched: this plan. Command completed: `flutter test test/integration/group_multi_party_device_criteria_test.dart` (pass). Decision/blocker: criteria guard passed, including GM-001 role count, exact relay profile, receiver tuple matching, duplicate rejection, missing-role rejection, and epoch/text/message mismatch rejection. Next action: run row-specific GM-001 device proof with the planned simulator trio.
- 2026-05-10T09:28:04Z - GM-001 device proof started. Files inspected or touched: this plan. Command currently running: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Decision/blocker: primary simulator trio is available, so no spare substitution is used. Next action: capture orchestrator shared directory, role mapping, and verdict artifact.
- 2026-05-10T09:33:20Z - GM-001 device proof completed. Files inspected or touched: this plan. Command completed: `MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F` (pass). Decision/blocker: orchestrator printed `gm001 proof passed: gm001 verdicts valid for alice, bob, charlie`; shared directory is `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da`, run id `1778405304614`, with no spare substitution. Next action: inspect `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da/gmp_1778405304614_gm001_orchestrator_verdict.json`.
- 2026-05-10T09:33:40Z - Orchestrator verdict inspection started. Files inspected or touched: this plan. Command currently running: `jq . /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da/gmp_1778405304614_gm001_orchestrator_verdict.json`. Decision/blocker: required verdict JSON inspection is starting after the device proof passed. Next action: verify `ok: true`, `scenario: gm001`, role devices, role verdict paths, and detail text.
- 2026-05-10T09:34:15Z - Orchestrator verdict inspection completed. Files inspected or touched: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da/gmp_1778405304614_gm001_orchestrator_verdict.json`, this plan. Command completed: `jq . /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da/gmp_1778405304614_gm001_orchestrator_verdict.json` (pass). Decision/blocker: verdict JSON shows `scenario: gm001`, `ok: true`, detail `gm001 verdicts valid for alice, bob, charlie`, role devices for alice/bob/charlie on the planned simulators, and per-role verdict paths. Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-05-10T09:34:36Z - Groups gate started. Files inspected or touched: this plan. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: mandatory named gate is starting after direct host, criteria, device proof, and verdict inspection all passed. Next action: record gate result.
- 2026-05-10T09:35:25Z - Groups gate completed. Files inspected or touched: this plan. Command completed: `./scripts/run_test_gates.sh groups` (pass). Decision/blocker: Group Messaging Gate passed with `00:11 +106: All tests passed!`. Next action: run `git diff --check`.
- 2026-05-10T09:35:49Z - Diff hygiene check started. Files inspected or touched: this plan. Command currently running: `git diff --check`. Decision/blocker: final required hygiene command is starting after the groups gate passed. Next action: record whitespace/conflict marker result.
- 2026-05-10T09:36:15Z - Diff hygiene check completed. Files inspected or touched: this plan. Command completed: `git diff --check` (pass). Decision/blocker: no whitespace or conflict-marker errors reported by the required diff hygiene command. Next action: record Executor final result for QA handoff.
- 2026-05-10T09:36:44Z - Executor final result recorded. Files inspected or touched: this plan and artifact existence check for `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da/gmp_1778405304614_gm001_orchestrator_verdict.json`. Command currently running: none. Decision/blocker: all required GM-001 evidence commands and gates passed; no production, test, source matrix, or breakdown closure edits were made; completeness-check and Go tests were not triggered by the plan conditions. Next action: hand off to QA Reviewer.
- 2026-05-10T09:37:22Z - QA Reviewer spawn/running. Files inspected or touched: this plan. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh" ...`. Decision/blocker: starting isolated QA Reviewer after Executor completed with all required GM-001 evidence green. Next action: wait for QA sufficiency result.
- 2026-05-10T09:39:38Z - QA Reviewer completed. Files inspected or touched: this plan, `/tmp/gm001-executor-result.md`, orchestrator and per-role verdict JSONs under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_gm001_kd81Da`, scoped git status/diff output, `flutter devices --machine`, `xcrun simctl list devices available`, and `git diff --check`. Command currently running: none. Decision/blocker: no blocking issues; required GM-001 host, criteria, three-simulator device, verdict, groups gate, and diff hygiene evidence is sufficient; completeness-check and Go tests were correctly skipped. Next action: accept GM-001 execution session.
- 2026-05-10T09:39:38Z - Final QA classification recorded. Files inspected or touched: this plan only. Command currently running: none. Decision/blocker: final verdict `accepted`; non-blocking follow-ups: none; source matrix, breakdown closure, GM-002, production, and tests remain out of execution write scope. Next action: closure phase may use the captured GM-001 artifact path without treating this execution pass as a source-row closure edit.

## real scope

Own exactly source row GM-001:

`Create private group with A, B, C and all join same topic/key epoch`.

This plan is for row-owned gap closure evidence only. It covers:

- Rerun or verify the existing host GM-001 regression.
- Run the row-specific A/B/C Flutter-app device proof through the accepted `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS`.
- Capture the resulting orchestrator verdict artifact path and detail.
- Run required hygiene/gates for the evidence session.
- Hand off to closure only after row-specific proof passes.

This plan does not cover GM-002, later membership mutation rows, new harness design, broad relay architecture, or source matrix/breakdown closure edits during execution. The source row stays `Open` until the separate closure phase updates it after proof passes.

## closure bar

GM-001 is closure-ready only when all of the following are true:

- The existing host proof passes: `test/features/groups/integration/group_messaging_smoke_test.dart::GM-001 creates private A/B/C group with shared epoch and exact fanout tuple`.
- The row-specific device proof runs with three distinct Flutter app peers for `alice`, `bob`, and `charlie` using the accepted multi-party harness.
- The orchestrator verdict JSON has `ok: true` and reports `gm001 verdicts valid for alice, bob, charlie`.
- The verdict validates receiver `messageId`, text/plaintext, `senderPeerId`, `keyEpoch`, unique role verdicts, shared group membership, exact receiver persistence, and exact relay profile.
- Required hygiene/gates pass after any execution changes.

Do not mark GM-001 `Covered` or `Closed` during the execution session. Closure docs may be updated only in a later closure pass after the row-specific proof passes.

## source of truth

Authoritative inputs:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row GM-001.
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` rows for GM-001 and `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS`.
- `Test-Flight-Improv/test-gate-definitions.md` for named gate and optional/manual suite classification.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` for accepted prerequisite evidence notes.
- Current accepted harness files:
  - `integration_test/scripts/run_group_multi_party_device_real.dart`
  - `integration_test/group_multi_party_device_real_harness.dart`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`
  - `test/integration/group_multi_party_device_criteria_test.dart`
- Current host proof: `test/features/groups/integration/group_messaging_smoke_test.dart`.

On disagreement, current code/tests and accepted harness criteria beat stale prose. The stale assertion that no exact fixture exists is no longer authoritative because `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS` is accepted. The source matrix row still wins for closure status: GM-001 remains `Open` until its row-specific proof and closure update pass.

## device/relay proof profile

Live availability was checked during planning:

- `flutter devices --machine` reported physical Pixel 6 `21071FDF600CSC`, physical iPhone `00008030-001A6D2801BB802E`, booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, plus `macos` and `chrome`.
- `xcrun simctl list devices available` reported four booted iOS 26.1 simulators:
  - `38FECA55-03C1-4907-BD9D-8E64BF8E3469` - iPhone 17 Pro
  - `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` - iPhone Air
  - `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` - iPhone 17
  - `1B098DFF-6294-407A-A209-BBF360893485` - iPhone 16e

Use this exact relay environment:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g
```

Primary GM-001 row-specific proof command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

Role mapping for that command is `alice=38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `bob=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, and `charlie=5BA69F1C-B112-47BE-B1FF-8C1003728C8F`. Keep `1B098DFF-6294-407A-A209-BBF360893485` as a same-runtime spare if one selected simulator becomes unavailable.

A single `FLUTTER_DEVICE_ID` gate, including `group-real-network-nightly`, is not sufficient for GM-001 closure because the source row requires exact A/B/C `3-Party E2E` proof.

## session classification

`evidence-gated`

The host proof and accepted multi-party harness already exist. The remaining GM-001 work is to produce row-specific device/relay evidence, not to design a new fixture. Execution is safe to start, but closure remains gated on the live proof result.

## exact problem statement

GM-001 remains `Open` because the source row requires exact A/B/C Flutter-app `3-Party E2E` proof. Prior host evidence is useful but non-closing, and prior prerequisite-shaped device artifacts proved the reusable harness rather than the GM-001 source row.

The behavior to prove is narrow:

- A, B, and C join the same private group topic/config/key epoch.
- A sends one baseline message.
- B and C each persist exactly one incoming message with the same `groupId`, `messageId`, sender, epoch, and plaintext.

What must stay unchanged:

- Do not weaken `group_multi_party_device_criteria.dart`.
- Do not accept sender-only, two-party, two-device-plus-CLI, or single-device evidence.
- Do not close GM-001 from prerequisite artifacts alone.
- Do not edit source matrix/breakdown during execution; closure owns those edits after proof passes.

## files and repos to inspect next

Inspect before execution or when triaging failure:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Inspect production only if row-specific proof fails due product behavior:

- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox.go`

The scoped status check showed the accepted prerequisite files and rollout docs as untracked in this worktree, while `group_messaging_smoke_test.dart` is modified. Do not revert or recreate those files; treat them as the current accepted working context unless the user explicitly asks for cleanup.

## existing tests covering this area

Current direct host proof:

- `test/features/groups/integration/group_messaging_smoke_test.dart::GM-001 creates private A/B/C group with shared epoch and exact fanout tuple` proves the host fake-network A/B/C baseline shared config/topic/member set, non-zero epoch-1 shared key, exact subscribers, Bob/Charlie incoming tuples, and Alice outgoing/no incoming echo.

Accepted prerequisite harness coverage:

- `test/integration/group_multi_party_device_criteria_test.dart` validates GM-001/GM-002 role counts, distinct app targets, exact relay env, sender/receiver tuple matching, duplicate persistence rejection, missing role rejection, message id mismatch rejection, text mismatch rejection, and epoch mismatch rejection.
- `integration_test/scripts/run_group_multi_party_device_real.dart` launches one Flutter app process per role and writes an orchestrator verdict JSON.
- `integration_test/group_multi_party_device_real_harness.dart` builds real app stacks for GM roles and emits per-role verdicts.

Gate docs classify the criteria test and orchestrator as optional/manual direct proof, not frozen named gates. That classification is acceptable for row-specific GM-001 proof as long as the exact command and verdict artifact are captured.

## regression/tests to add first

No new regression should be added before the first execution attempt. The required host regression and accepted criteria tests already exist.

If the GM-001 device proof fails because of product behavior, add or adjust the smallest direct regression that reproduces the failing seam before changing production code. Do not weaken the accepted harness criteria to make a failing product behavior pass.

## step-by-step implementation plan

1. Reconfirm live availability with:

```sh
flutter devices --machine
xcrun simctl list devices available
```

2. Rerun the focused host proof:

```sh
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'
```

3. Rerun the accepted host-side criteria guard:

```sh
flutter test test/integration/group_multi_party_device_criteria_test.dart
```

4. Run the row-specific device proof with the exact relay env and three selected booted iOS simulators:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

5. Capture the orchestrator verdict path from the command output. The expected filename shape is `gmp_<runId>_gm001_orchestrator_verdict.json` under the printed shared temp directory.

6. Inspect the orchestrator verdict. It must record `ok: true`, `scenario: gm001`, `roleDevices` for alice/bob/charlie, per-role verdict paths, and detail `gm001 verdicts valid for alice, bob, charlie`.

7. If the proof fails:

- Classify simulator boot, device selection, process launch, or relay availability failures as environment/harness execution blockers and rerun only after the environment is corrected.
- Classify tuple mismatch, missing receiver persistence, duplicate persistence, divergent `groupId`, missing role verdict, sender mismatch, text mismatch, or epoch mismatch as a code/product gap.
- For product gaps, add the smallest direct failing regression and fix the production/test seam within GM-001 scope. Do not weaken `group_multi_party_device_criteria.dart`.

8. Run required gates/hygiene after the proof or after any fix:

```sh
./scripts/run_test_gates.sh groups
git diff --check
```

9. Run `./scripts/run_test_gates.sh completeness-check` only if execution adds, removes, or reclassifies tests/docs that affect the test inventory or gate definitions.

10. Stop before closure edits. Hand off the passing verdict artifact path and gate evidence to a closure pass, which may update the source matrix and breakdown while keeping the row-owned evidence explicit.

## risks and edge cases

- Booted simulators can disappear or become unhealthy between planning and execution; rerun device discovery immediately before the harness command.
- The relay profile must match exactly; a typo in `MKNOON_RELAY_ADDRESSES` is a non-product failure.
- Three roles must run as three distinct Flutter app targets; duplicate device IDs are invalid.
- Partial sender-only success is non-closing; Bob and Charlie must each persist exactly one matching incoming tuple.
- Duplicate receiver persistence is a failure, not acceptable extra delivery.
- A single-device `FLUTTER_DEVICE_ID` nightly gate is useful supporting signal only and cannot replace A/B/C proof.
- Physical Pixel and physical iPhone are visible but are not the primary planned role targets; mixing physical and simulator targets should be a deliberate retry choice, not an accidental fallback.

## exact tests and gates to run

Planning evidence commands already run:

```sh
flutter devices --machine
xcrun simctl list devices available
```

Execution commands:

```sh
flutter devices --machine
xcrun simctl list devices available
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple'
flutter test test/integration/group_multi_party_device_criteria_test.dart
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario gm001 -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
./scripts/run_test_gates.sh groups
git diff --check
```

Conditional commands:

```sh
./scripts/run_test_gates.sh completeness-check
cd go-mknoon && go test ./...
```

Run `completeness-check` only if test inventory/gate classification changes. Run Go checks only if execution touches Go code or the device verdict points at Go relay/node behavior.

## known-failure interpretation

The focused GM-001 host proof, criteria test, and row-specific device proof have no acceptable known red state in this plan. A failure in any of them blocks GM-001 closure.

Pre-existing unrelated broad-suite failures must not be attributed to GM-001 unless they reproduce in the focused host proof, accepted criteria test, row-specific device proof, or `groups` gate after GM-001 changes.

If the device proof fails due environment setup, record it as a blocker and do not mark the row covered. If it fails due product behavior, classify it as a code/product gap and fix the code/tests in GM-001 scope rather than changing acceptance criteria.

## done criteria

- Live device availability is recorded from fresh `flutter devices --machine` and `xcrun simctl list devices available` output.
- Focused host GM-001 proof passes.
- Criteria guard passes.
- Row-specific GM-001 multi-party device command exits successfully.
- Orchestrator verdict JSON path is captured and records `ok: true` with `gm001 verdicts valid for alice, bob, charlie`.
- `./scripts/run_test_gates.sh groups` passes.
- `git diff --check` passes.
- No GM-002 or later-row work is included.
- Source matrix and breakdown are not marked covered during execution; they are updated only by a later closure pass after proof passes.

## scope guard

Non-goals:

- Do not redesign the accepted multi-party harness.
- Do not weaken criteria validation.
- Do not convert optional/manual proof into a frozen named gate.
- Do not close GM-001 from the prior prerequisite-shaped artifact.
- Do not use a two-party, two-device-plus-CLI, single-simulator, or single `FLUTTER_DEVICE_ID` gate as closure proof.
- Do not update GM-002 or other rows.
- Do not touch production code/tests during planning.

During execution, production or test edits are allowed only if the row-specific proof reveals a GM-001 product behavior gap. Such edits must stay at the failing seam and must be followed by the direct proof and gates in this plan.

## accepted differences / intentionally out of scope

- The accepted prerequisite harness artifacts prove reusable harness support, not GM-001 source-row closure.
- The host fake-network GM-001 regression is required supporting evidence but not sufficient without A/B/C device proof.
- Existing two-simulator routing/group smoke fixtures and two-device-plus-CLI fixtures remain useful references but are non-closing for GM-001.
- `group-real-network-nightly` remains supplemental because it is single-device driven and cannot prove A/B/C receiver persistence.
- GM-002's A/B/C/D or equivalent proof is intentionally out of scope.

## dependency impact

GM-001 is the baseline for later GM membership mutation rows. If the row-specific GM-001 proof passes, closure can update the source matrix and breakdown for GM-001 and unblock stronger confidence for later GM rows. If it fails due product behavior, later GM rows should wait because mutation behavior cannot be trusted until baseline A/B/C delivery is correct. If it fails due environment, later row execution should not reinterpret that as product coverage.

## reviewer pass

Verdict: sufficient as-is.

Sufficiency questions:

- Is the plan sufficient as-is, sufficient with adjustments, or insufficient? Sufficient as-is.
- What files, tests, regressions, or gates are missing? None structurally. The plan names the source row, breakdown, host proof, accepted harness files, criteria test, exact GM-001 device command, `groups`, conditional `completeness-check`, conditional Go checks, and `git diff --check`.
- What assumptions are stale or incorrect? The stale missing-harness/device-proof-blocked assumption was removed. The plan treats `PREREQ-GM-MULTI-PARTY-DEVICE-HARNESS` as accepted and keeps GM-001 `Open` until row-specific proof passes.
- What is overengineered? No overengineering found. It avoids new harness design and starts with evidence reruns.
- Is the work decomposed enough to minimize hallucination during implementation? Yes. Execution has a direct host proof, criteria guard, exact device command, artifact capture, and explicit failure classification.
- What is the minimum needed to make the plan sufficient? Already present: exact relay profile, exact device IDs, single-device non-closure warning, closure-only source doc update guard, and product-gap rule that code/tests must be fixed rather than criteria weakened.

## arbiter decision

Structural blockers: none.

Incremental details:

- If the primary simulator trio is unhealthy at execution time, use the fourth booted iOS simulator as a replacement only after rerunning device discovery and recording the adjusted role mapping.
- If execution touches source/gate classification docs during a later closure pass, rerun `./scripts/run_test_gates.sh completeness-check`.

Accepted differences:

- The accepted prerequisite harness remains optional/manual in gate docs; this row can still use it as exact row proof by recording the command and verdict artifact.
- The prior prerequisite-shaped GM-001 artifact proves harness capability only, not GM-001 source-row closure.

Arbiter stop rule: no structural blocker was found, so no final reviewer loop is required.

## final planning output

Final verdict: execution-ready for GM-001 row-specific evidence.

Final plan: rerun the focused host GM-001 regression, rerun the criteria guard, run the accepted three-role GM-001 device harness with the exact relay profile and selected booted iOS simulators, capture the orchestrator verdict JSON, run required gates/hygiene, and leave source matrix/breakdown closure updates for the later closure pass after proof passes.

Structural blockers remaining: none.

Incremental details intentionally deferred: simulator substitution details are deferred to execution-time device discovery; completeness-check is conditional on classification/doc changes.

Accepted differences intentionally left unchanged: single-device and prior prerequisite artifacts are supporting but non-closing evidence; GM-002 and later rows are out of scope.

Exact docs/files used as evidence: source matrix GM-001 row, session breakdown GM-001 and prerequisite rows, accepted harness files, criteria test, direct host proof, gate definitions, test inventory, scoped git status, `flutter devices --machine`, and `xcrun simctl list devices available`.

Why the plan is safe to implement now: the obsolete missing-harness blocker is gone, live devices are available, the exact relay/device command is specified, failure classification prevents criteria weakening, and closure overclaim is blocked until row-specific proof passes.

Status: execution-ready
