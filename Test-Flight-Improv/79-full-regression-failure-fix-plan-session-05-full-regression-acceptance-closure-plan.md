# Session 05 Plan: Full Regression Acceptance Closure

## Final verdict

`accepted_with_explicit_follow_up`.

Session 05 is acceptance-only. It does not implement new product behavior. The current repo-local failures from doc 79 are either closed by Sessions 01, 03, and 04, or externally blocked by Session 02's Android emulator relay DNS preflight.

Do not launch a broad full-regression sweep while the selected Android emulator cannot resolve `mknoun.xyz`; the transport and benchmark-sim portions would produce known-invalid relay/readiness failures and obscure the acceptance classification.

## Final plan

### 1. real scope

Record final doc 79 acceptance status after Sessions 01-04:

- summarize closed readiness proof evidence
- preserve the external relay/device preflight blocker
- summarize aggregate feature-test stale/already-covered evidence
- summarize feed performance harness stabilization evidence
- classify the full regression runner as follow-up-blocked by emulator relay DNS, not by message retry UX

Do not change product code, gate definitions, relay architecture, or message retry UX in Session 05.

### 2. closure bar

Session 05 is complete when:

- source doc 79 has a final verdict that does not claim a clean full-regression pass
- the breakdown ledger has terminal statuses for Sessions 01-05
- the final acceptance section names the exact external preflight blocker
- direct validation commands that remain valid in this environment are recorded
- invalid device-backed relay gates are explicitly deferred until emulator-side DNS is healthy

### 3. source of truth

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- Session plans/evidence for Sessions 01-04
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh`

Current preflight evidence beats stale historical logs. Script commands beat prose when gate docs disagree.

### 4. session classification

`acceptance-only`.

Terminal doc status: `accepted_with_explicit_follow_up`.

### 5. exact problem statement

Doc 79 cannot honestly close as a clean full-regression pass because `emulator-5554` still cannot resolve `mknoun.xyz` from inside Android. The remaining invalid test surface is relay/readiness runtime validation, not the already-closed readiness semantics, aggregate feature stability, or feed performance harness issues.

### 6. files and repos to inspect next

- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-01-readiness-proof-semantics-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-02-relay-device-startup-diagnosis-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-03-feature-aggregate-flake-stability-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-04-feed-performance-baseline-and-fix-plan.md`
- `.full_regression_logs/20260427_185248/summary.tsv`

### 7. existing tests covering this area

- Session 01 readiness proof direct tests passed.
- Session 03 feature aggregate direct, together, serial aggregate, and normal aggregate commands passed.
- Session 04 feed performance passed three post-fix same-device runs on `emulator-5554`.
- `./scripts/run_test_gates.sh completeness-check` passed after Session 04.

### 8. regression/tests to add first

None. Session 05 is acceptance-only and must not add tests.

### 9. step-by-step implementation plan

1. Refresh emulator relay DNS preflight.
2. If Android still cannot resolve `mknoun.xyz`, do not run transport, benchmark-sim, or the full regression runner as a claimed acceptance run.
3. Run valid lightweight acceptance checks that are not invalidated by relay DNS.
4. Update source doc 79 with final `accepted_with_explicit_follow_up` verdict.
5. Update the breakdown ledger with Session 05 terminal status and final doc verdict.

### 10. risks and edge cases

- Running full regression under a known relay DNS blocker would create noisy red logs and could misattribute external relay failures to message retry UX.
- Claiming doc 79 fully closed would overstate confidence because device-backed relay/readiness gates remain unvalidated.
- Reopening Session 03 or Session 04 without a new current-tree failure would churn already-closed evidence.

### 11. exact tests and gates to run

Valid checks run for Session 05:

```bash
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell getprop sys.boot_completed
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 mknoun.xyz
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ping -c 1 8.8.8.8
nc -vz mknoun.xyz 4001
dart format --output=none --set-exit-if-changed integration_test/feed_performance_test.dart
./scripts/run_test_gates.sh completeness-check
```

Deferred until emulator relay DNS is healthy:

```bash
FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh transport
FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh benchmark-sim
FLUTTER_DEVICE_ID=emulator-5554 /Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app
```

### 12. known-failure interpretation

- Android `ping -c 1 mknoun.xyz` returning `unknown host` is an external preflight blocker for relay/readiness validation.
- `background_reconnect_test.dart`, `cold_start_sendable_no_user_action_test.dart`, transport gate, benchmark-sim, and full regression failures under that preflight are not valid retry-message UX regressions.
- Feed performance is no longer a blocking source-doc failure after Session 04's three post-fix passes.

### 13. done criteria

- Source doc 79 records final verdict `accepted_with_explicit_follow_up`.
- The breakdown records Session 05 as terminal.
- Deferred commands and the exact blocker are named.
- No invalid full-regression pass is claimed.

### 14. scope guard

Do not:

- implement new product changes
- change relay config or architecture
- edit gate definitions
- run known-invalid device relay gates and treat their red result as new evidence
- mark doc 79 `closed` until relay DNS is healthy and the deferred commands pass

### 15. accepted differences / intentionally out of scope

- A full green release-confidence sweep is intentionally deferred to a healthy Android relay DNS environment.
- Session 02 remains retry-only; its blocker is external preflight, not a known repo-local code defect.

### 16. dependency impact

Future release confidence depends on rerunning the deferred transport, benchmark-sim, and full-regression commands after Android can resolve `mknoun.xyz`. No remaining doc 79 in-repo implementation session is open.

## Structural blockers remaining

None for acceptance documentation. A clean full-regression pass is externally blocked by emulator-side relay DNS.

## Incremental details intentionally deferred

- Capturing a new `.full_regression_logs/<timestamp>/` run after DNS is healthy.
- Retrying Session 02 direct device-backed relay tests after the preflight passes.

## Accepted differences intentionally left unchanged

- Session 02 stays `blocked_external_preflight`.
- Session 03 stays `stale/already-covered`.
- Session 04 stays `closed` without running `feed` or `1to1` gates because only the integration benchmark harness changed.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `/Users/I560101/.codex/skills/flutter-full-regression-runner/SKILL.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan.md`
- `Test-Flight-Improv/79-full-regression-failure-fix-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh`

## Why the plan is safe to implement now

It preserves the real confidence boundary: in-repo deterministic failures are closed, while device-backed relay/readiness confidence is deferred with exact preflight evidence instead of being hidden behind noisy full-regression failures.
