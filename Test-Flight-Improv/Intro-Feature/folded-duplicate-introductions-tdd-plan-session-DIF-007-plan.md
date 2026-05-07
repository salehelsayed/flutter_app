# DIF-007 - Regression, Documentation, and Final Closure Plan

Status: accepted

## Execution Progress

- 2026-05-07 14:33 CEST - Orchestrator intake / contract recovery completed.
  Files inspected: `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/test-gate-definitions.md`, and prior `DIF-006` plan
  evidence. Command currently running: none. Decision/blocker: the intended
  plan path did not exist locally, so this acceptance-only plan artifact was
  recovered from the governing DIF-007 breakdown entry and source matrix row;
  no production code or tests were changed. Next action: spawn the isolated
  Executor to capture final regression evidence and update only DIF-007-owned
  docs if the evidence supports closure.
- 2026-05-07 14:34 CEST - Executor spawned/running. Files inspected since last
  update: this recovered plan and governing docs. Command currently running:
  spawned Executor `019e026e-e746-79a0-8a70-9b2c91245c91` is extracting the
  DIF-007 contract and starting required acceptance evidence. Decision/blocker:
  isolation contract satisfied for the Executor phase with model `gpt-5.5` and
  reasoning effort `xhigh`. Next action: wait for Executor result, then spawn a
  separate QA Reviewer.
- 2026-05-07 14:35 CEST - Executor contract extraction completed. Files
  inspected: this plan,
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`,
  `folded-duplicate-introductions-tdd-plan.md`, `test-inventory.md`,
  `test-gate-definitions.md`, and current `git status --short`. Command
  currently running: none. Decision/blocker: DIF-007 is acceptance-only and may
  touch only DIF-007-owned docs unless a required gate fails and triage proves a
  real DIF-007-owned regression; required exact commands are the host-side
  direct suite, `./scripts/run_test_gates.sh intro`, simulator fixture intake,
  preferred uninterrupted `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`,
  shell syntax, and `git diff --check`. Next action: start required direct host
  suite evidence.
- 2026-05-07 14:35 CEST - Required direct host suite started. Files inspected
  or touched: this plan only. Command currently running: `flutter test --no-pub
  test/features/introduction/application/load_introductions_test.dart
  test/features/introduction/application/folded_introduction_response_use_case_test.dart
  test/features/introduction/application/accept_introduction_test.dart
  test/features/introduction/application/pass_introduction_test.dart
  test/features/introduction/application/mutual_acceptance_test.dart
  test/features/introduction/presentation/widgets/intro_row_test.dart
  test/features/introduction/presentation/widgets/intros_tab_test.dart
  test/features/introduction/presentation/widgets/intros_tab_extended_test.dart
  test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
  test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
  test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart
  test/features/orbit/presentation/screens/orbit_wired_test.dart
  test/features/feed/presentation/screens/feed_wired_test.dart`. Decision/blocker:
  pending. Next action: record pass/fail and triage before any fix.
- 2026-05-07 14:36 CEST - Required direct host suite finished. Files inspected
  or touched: this plan only. Command currently running: none. Result: passed
  with `+266` and `All tests passed!`. Decision/blocker: no DIF-007 regression
  found, no production/test code changes needed. Next action: start
  `./scripts/run_test_gates.sh intro`.
- 2026-05-07 14:36 CEST - Named intro gate started. Files inspected or touched:
  this plan only. Command currently running: `./scripts/run_test_gates.sh
  intro`. Decision/blocker: pending. Next action: record pass/fail and triage
  before any fix.
- 2026-05-07 14:36 CEST - Named intro gate finished. Files inspected or
  touched: this plan only. Command currently running: none. Result:
  `./scripts/run_test_gates.sh intro` passed with `+185` and `All tests
  passed!`. Decision/blocker: no intro-gate regression found, no
  production/test code changes needed. Next action: collect simulator fixture
  intake.
- 2026-05-07 14:36 CEST - Simulator fixture intake started. Files inspected or
  touched: this plan only. Commands currently running: `flutter devices
  --machine` and `xcrun simctl list devices available`. Decision/blocker:
  pending. Next action: record available device evidence before final simulator
  proof.
- 2026-05-07 14:37 CEST - Simulator fixture intake finished. Files inspected or
  touched: this plan only. Command currently running: none. Result:
  `flutter devices --machine` passed and listed physical `Pixel 6`, physical
  `Saleh's iPhone`, `macOS`, and `Chrome`; `xcrun simctl list devices
  available` passed and listed available iOS simulator fixtures including
  iPhone 17 Pro/Max/Air/17/16e families across iOS 26.1, 26.2, and 26.4.
  Decision/blocker: device inventory is sufficient to attempt the final
  simulator proof. Next action: start preferred uninterrupted
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`.
- 2026-05-07 14:37 CEST - Final simulator proof started. Files inspected or
  touched: this plan only. Command currently running:
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`. Decision/blocker: pending.
  Next action: preserve uninterrupted pass evidence if the command completes,
  or record an explicit resumed-scenario ledger if interrupted.
- 2026-05-07 14:56 CEST - Final simulator proof failed during triage intake.
  Files inspected or touched: this plan only. Command currently running: none.
  Result: `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` exited `1` in
  scenario 3/11, `Re-send revives a passed intro`, with `ERROR: Timed out
  waiting for pass-handshake on 5BA69F1C-B112-47BE-B1FF-8C1003728C8F` and
  payload `{"stepId":"pass-handshake","status":"running"}`. Decision/blocker:
  required final simulator evidence is not green; triage required before any
  fix or closure doc updates. Next action: inspect available harness artifacts
  and classify the failure.
- 2026-05-07 14:57 CEST - Final simulator proof failure triaged. Files
  inspected: current simulator Documents result/config files for devices A
  `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, B
  `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and C
  `1B098DFF-6294-407A-A209-BBF360893485`, plus relevant
  `smoke_test_friends.sh` handshake/wait logic. Command currently running:
  none. Decision/blocker: candidate environment/harness timeout before intro
  send/pass/folded behavior because A and C completed `pass-handshake` while B
  stayed `running` until the shell timeout; no production/test fix attempted.
  Next action: rerun the exact required `INTRO_E2E_SCENARIO=all
  ./smoke_test_friends.sh` once for clean uninterrupted evidence.
- 2026-05-07 14:57 CEST - Final simulator proof retry started. Files inspected
  or touched: this plan only. Command currently running:
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`. Decision/blocker: pending;
  prior failure remains triaged as an environment/harness-timeout candidate
  unless the retry proves a repeatable regression. Next action: record pass/fail
  and decide closure or blocked status.
- 2026-05-07 15:55 CEST - Final simulator proof retry finished. Files inspected
  or touched: this plan only. Command currently running: none. Result: exact
  retry `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` passed with
  `=== Intro E2E harness passed ===` after advancing through scenarios 1-11,
  including scenario 11 `Four-identity folded duplicate acceptance`. Decision:
  the earlier scenario 3 `pass-handshake` timeout is classified as a transient
  environment/harness timeout because the same exact full run passed on retry
  without production/test changes. Next action: run required hygiene commands.
- 2026-05-07 15:55 CEST - Hygiene checks started. Files inspected or touched:
  this plan only. Commands currently running: `bash -n smoke_test_friends.sh
  reset_simulators.sh` and `git diff --check`. Decision/blocker: pending. Next
  action: record hygiene results before closure doc updates.
- 2026-05-07 15:56 CEST - Hygiene checks finished / closure docs update
  started. Files inspected or touched: this plan only so far. Command currently
  running: none. Results: `bash -n smoke_test_friends.sh reset_simulators.sh`
  passed with no output; `git diff --check` passed with no output.
  Decision/blocker: all required DIF-007 evidence is green after the exact
  final simulator proof retry; closure docs may be updated. Next action: update
  only DIF-007-owned docs with concrete evidence and final handoff.
- 2026-05-07 15:58 CEST - Executor completed / QA Reviewer spawned. Files
  inspected or touched by Executor:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`,
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`, and
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`.
  Command currently running: spawned QA Reviewer. Decision/blocker: Executor
  recommendation is `ready_for_qa`; no production or test code changed; exact
  full `INTRO_E2E_SCENARIO=all` retry passed after a triaged transient first
  attempt. Next action: QA reviews scope adherence, evidence sufficiency, docs,
  and final program verdict.
- 2026-05-07 16:00 CEST - Closure docs updated. Files touched:
  `folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md`, `test-inventory.md`, and
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`. Command
  currently running: none. Decision/blocker: source row `DIF-007`,
  intro inventory, session ledger, DIF-007 closure audit, and final program
  verdict now record concrete green evidence; no production/test code changed
  in DIF-007. Next action: run final scoped validation/hygiene after doc edits.
- 2026-05-07 16:01 CEST - Final Executor handoff written. Files touched:
  `folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md`, `test-inventory.md`, and
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`. Command
  currently running: none. Result: post-doc-update `git diff --check` passed
  with no output. Decision/blocker: no blocking Executor issue remains;
  recommendation is `ready_for_qa`. Next action: hand off to separate QA
  Reviewer.
- 2026-05-07 16:04 CEST - QA Reviewer completed. Files inspected:
  `folded-duplicate-introductions-tdd-plan-session-DIF-007-plan.md`,
  `folded-duplicate-introductions-tdd-plan.md`, `test-inventory.md`,
  `folded-duplicate-introductions-tdd-plan-session-breakdown.md`, and
  `test-gate-definitions.md`. Command currently running: none. Result:
  current `git diff --check` passed with no output. Decision/blocker:
  `no_blocking_issues`; recorded direct suite, intro gate, simulator fixture
  intake, triaged first `all` timeout, exact green `all` retry, and hygiene
  evidence are sufficient for acceptance. Next action: outer controller may
  accept DIF-007.

## Real Scope

This session is acceptance-only final closure for the folded duplicate
introductions rollout.

In scope:

- Verify final host-side regression evidence for the folded intro projection,
  folded count, folded Accept/Pass, folded UI, Orbit/Feed integration, and
  existing intro journeys.
- Verify the named intro gate.
- Prefer a literal uninterrupted
  `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` final simulator proof. If
  the environment or user interrupts that run, preserve an explicit resumed
  full-scenario evidence ledger and classify whether that evidence is
  sufficient or blocked.
- Update only DIF-007-owned closure docs after evidence is green:
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`, and
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`.
- Record the final program verdict in the breakdown.

Out of scope:

- Production code changes unless required evidence fails and triage proves a
  real session-owned regression.
- Reopening or re-executing `DIF-001` through `DIF-006` unless a required
  DIF-007 gate proves a real regression in those accepted slices.
- Database migrations, persisted introduction schema changes, protocol changes,
  friend-picker resend eligibility changes, permanent pass-blocking semantics,
  mutual-acceptance contact creation changes, group delete semantics, or broad
  Orbit rewrites.

## Closure Bar

`DIF-007` is complete only when all of the following are true:

- `DIF-001` through `DIF-006` remain accepted/Closed and are not reopened by
  documentation-only closure.
- Duplicate active intros to the same target render as one row.
- Multi-introducer attribution is visible in that row.
- Accept and Pass each appear only once for the folded row.
- Accept/Pass applies to all current underlying pending intro records in the
  fold.
- Upgrade-style already-persisted pending intro rows still read through the
  folded review design without data loss.
- Orbit and Feed user-facing badge/review counts count folded targets.
- The intro gate passes.
- The final simulator evidence proves the folded duplicate scenario remains in
  the full intro matrix.
- The source matrix row `DIF-007`, intro test inventory, session ledger, and
  final program verdict record concrete evidence.

## Source Of Truth

- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`
  row `DIF-007` defines final closure requirements.
- `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`
  defines this session's one-session scope and final verdict policy.
- `Test-Flight-Improv/Intro-Feature/test-inventory.md` is the intro coverage
  inventory that must be updated with folded duplicate evidence.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`
  define the named intro gate; if they disagree, the script wins.
- Current code and tests win over prose if there is a conflict.

## Session Classification

`acceptance-only`

`DIF-006` is accepted/Closed. This plan must not implement product code unless
required evidence fails and triage proves a real DIF-007-owned regression.

## Recent Evidence Intake

- Standalone `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` passed
  after `offline-first-chat` receiver `chat_poll_cycles` was raised to `120`.
- Scenario 1 passed before a user-requested stop.
- Resumed scenarios `refresh`, `pass`, `repair`, `copy`, `partial`,
  `partition`, `offline-chat`, `pass-fallback`, `split-brain`, and
  `folded-duplicate` passed sequentially.
- The recent resumed ledger is accepted as intake, but DIF-007 should still
  prefer a literal uninterrupted `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh`
  for final closure if practical.

## Exact Direct Tests And Gates

Run these host-side direct suites unless a narrower equivalent is justified by
current code ownership and recorded explicitly:

```bash
flutter test --no-pub \
  test/features/introduction/application/load_introductions_test.dart \
  test/features/introduction/application/folded_introduction_response_use_case_test.dart \
  test/features/introduction/application/accept_introduction_test.dart \
  test/features/introduction/application/pass_introduction_test.dart \
  test/features/introduction/application/mutual_acceptance_test.dart \
  test/features/introduction/presentation/widgets/intro_row_test.dart \
  test/features/introduction/presentation/widgets/intros_tab_test.dart \
  test/features/introduction/presentation/widgets/intros_tab_extended_test.dart \
  test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart \
  test/features/orbit/presentation/screens/orbit_screen_loading_test.dart \
  test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  test/features/feed/presentation/screens/feed_wired_test.dart
```

Run the final intro regression gate:

```bash
./scripts/run_test_gates.sh intro
```

Run simulator fixture intake before device-backed proof:

```bash
flutter devices --machine
xcrun simctl list devices available
```

Run final simulator proof:

```bash
INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh
```

Run hygiene:

```bash
bash -n smoke_test_friends.sh reset_simulators.sh
git diff --check
```

If `INTRO_E2E_SCENARIO=all` cannot complete uninterrupted because of an
environment/user interruption, the Executor must preserve an explicit resumed
full-scenario ledger, including the recent evidence intake above, and QA must
classify whether that ledger is sufficient or blocked. A required gate failure
must be triaged before any fix attempt.

## Docs To Update Only After Evidence Supports Closure

- Source matrix row `DIF-007` in
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan.md`.
- Folded duplicate coverage and command inventory in
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`.
- Session ledger, `DIF-007` closure audit, and final program acceptance verdict
  in
  `Test-Flight-Improv/Intro-Feature/folded-duplicate-introductions-tdd-plan-session-breakdown.md`.

## Done Criteria

- No blocking QA issues remain.
- Required direct suites and named intro gate have current green evidence.
- Final simulator proof is current and explicitly classified.
- Only DIF-007-owned docs changed during closure, unless failed evidence proves
  and triages a real session-owned regression first.
- Final program verdict is persisted as closed only if every `DIF-*` source row
  is `Closed` with concrete evidence.

## Executor Handoff

- Verdict recommendation: `ready_for_qa`
- Production code changes: none in DIF-007
- Test code changes: none in DIF-007
- Doc changes: this plan, source matrix row `DIF-007`, `test-inventory.md`, and
  the session breakdown ledger/closure audit/final program verdict
- Required evidence: direct host suite passed `+266`; intro gate passed `+185`;
  `flutter devices --machine` passed; `xcrun simctl list devices available`
  passed; first exact `INTRO_E2E_SCENARIO=all` attempt timed out in scenario 3
  `pass-handshake` before intro send/pass/folded behavior and was triaged as
  transient environment/harness timeout after the exact uninterrupted retry
  passed scenarios 1-11 with `=== Intro E2E harness passed ===`; `bash -n
  smoke_test_friends.sh reset_simulators.sh` and `git diff --check` passed
  with no output.

## Final Execution Verdict

- Verdict: `accepted`
- QA result: `no_blocking_issues`
- Blocking issues: none
- Non-blocking follow-ups: none
- Local sequential fallback used: no
- Closure note: the accepted evidence is the current direct host suite, named
  intro gate, simulator fixture intake, exact green `all` retry, shell syntax,
  and diff hygiene. The first `all` timeout is not accepted as closure proof;
  it is recorded only as a triaged transient timeout before the successful
  exact retry.
