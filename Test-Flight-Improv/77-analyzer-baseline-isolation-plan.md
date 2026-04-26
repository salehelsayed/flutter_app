# 77 Analyzer Baseline Isolation Plan

## Final verdict

Session classification: `implementation-ready`.

The repo-wide `flutter analyze` backlog is now a reliability problem for the
full-regression runner, not a reason to start a broad analyzer cleanup session.
Current evidence shows `flutter analyze` has no analyzer errors after the
Report 76 fixture repairs, but it still exits non-zero because Flutter treats
warnings and infos as fatal by default. The focused fix is to add a checked-in
analyzer baseline gate that fails on new analyzer regressions while reporting
the known warning/info debt as isolated debt.

## Final plan

### 1. real scope

Implement only baseline isolation for repo-wide analyzer output:

- add a deterministic analyzer-output parser and baseline comparator
- add a checked-in current analyzer baseline for warning/info findings
- add a small shell wrapper that runs analyzer, compares current output against
  the baseline, and prints a concise debt/delta summary
- update the full-regression runner to call the analyzer baseline gate instead
  of treating all existing warning/info debt as a fresh failure
- add parser/comparator unit tests with small synthetic analyzer logs

Do not clean the 1,700 existing warning/info findings, do not disable analyzer
rules globally, and do not change product/test code solely to reduce the
baseline count in this session.

### 2. closure bar

Good enough means:

- analyzer errors are always build-blocking and cannot be hidden in the
  baseline
- existing warning/info findings are represented in a committed, reviewable
  baseline artifact
- new warning/info findings above the baseline fail the analyzer baseline gate
  with exact path/rule/message evidence
- removed findings are reported as baseline shrink opportunities but do not
  fail the gate
- the full-regression summary distinguishes analyzer baseline debt from new
  analyzer regressions
- no named test gate semantics change

### 3. source of truth

Priority order:

1. Current `flutter analyze` output from this repo.
2. `flutter analyze --help` for fatal-warning/fatal-info behavior.
3. `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh`.
4. `analysis_options.yaml`.
5. `Test-Flight-Improv/76-full-regression-follow-up-plan.md`.
6. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.

Current analyzer output wins over stale failure counts in older logs. The
full-regression runner script is the source of truth for full-regression labels
and summary behavior. `scripts/run_test_gates.sh` remains the source of truth
for named gates and is not the right place for this analyzer gate.

### 4. session classification

`implementation-ready`

The needed implementation seams are small and visible: a parser/comparator, one
shell wrapper, one baseline artifact, and one full-regression runner call-site.

### 5. exact problem statement

The full-regression runner currently runs:

```bash
flutter analyze
```

Because Flutter defaults `--fatal-infos` and `--fatal-warnings` to on, the
runner reports the entire repo-wide analyzer backlog as a red full-regression
failure. That makes it hard to tell whether a new change introduced a real
build-blocking analyzer regression or merely re-observed old debt.

Current evidence after the Report 76 fixture repairs:

- current `flutter analyze` probe: 1,700 findings, 0 errors
- severity split: 1,502 infos, 198 warnings
- path split: `integration_test` 993, `lib` 408, `test` 299
- largest rules: `avoid_print` 1007, `deprecated_member_use` 99,
  `file_names` 94, `unused_import` 69, `use_null_aware_elements` 58

The user-visible behavior that must improve is release confidence: a full
regression run should fail when analyzer debt grows or analyzer errors appear,
while clearly reporting that unchanged existing warning/info debt is not a new
regression.

### 6. files and repos to inspect next

Implementation files:

- `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh`
- `analysis_options.yaml`
- `scripts/check_flutter_analyze_baseline.sh` (new)
- `tool/analyzer_baseline/analyzer_baseline.dart` or equivalent pure-Dart
  parser/comparator module (new)
- `tool/analyzer_baseline/flutter_analyze_baseline.tsv` (new)

Tests:

- `test/unit/analyzer_baseline_parser_test.dart` (new)

Evidence/log references:

- `.codex-test-logs/flutter_analyze_baseline_probe_20260426.txt`
- `.full_regression_logs/20260426_103445/004_flutter_analyze.log`
- `.full_regression_logs/20260426_103445/summary.tsv`
- `Test-Flight-Improv/76-full-regression-follow-up-plan.md`

### 7. existing tests covering this area

Already covered:

- `scripts/run_test_gates.sh completeness-check` verifies named test-file
  classification, but it does not cover analyzer behavior.
- Full-regression runner logs and `summary.tsv` already preserve per-command
  pass/fail labels.
- `flutter analyze --help` exposes `--no-fatal-infos` and
  `--no-fatal-warnings`, which are enough to separate analyzer errors from
  warning/info debt.

Missing:

- No parser test for analyzer output.
- No checked-in analyzer baseline artifact.
- No full-regression step that reports "known analyzer debt unchanged" versus
  "new analyzer regression".

### 8. regression/tests to add first

Add `test/unit/analyzer_baseline_parser_test.dart` before wiring the runner.
It should use small embedded analyzer-output snippets and prove:

- parser extracts severity, rule, path, message, line, and column from standard
  Flutter analyzer rows
- normalization omits line/column from the primary comparison key and keeps a
  count per key, so harmless line drift does not create false new debt
- baseline comparison fails when a current warning/info key count exceeds the
  baseline count
- baseline comparison fails on any `error`, even if the error text appears in
  the baseline file
- baseline comparison reports removed warning/info keys as non-failing
  improvements

These tests prove the baseline seam without needing to manufacture analyzer
errors inside the real repo.

### 9. step-by-step implementation plan

1. Add the pure parser/comparator.
   - Prefer a small Dart module under `tool/analyzer_baseline/`.
   - Parse human `flutter analyze` rows of the form
     `severity • message • path:line:column • rule`.
   - Represent comparison keys as `severity`, `rule`, `path`, `message`.
   - Store `count` for duplicate findings with the same key.
   - Keep line/column only in diagnostic output, not in the stable key.

2. Add the parser/comparator unit tests.
   - Put them under `test/unit/` so existing gate completeness rules already
     classify them.
   - Do not add a new named gate.

3. Generate the initial baseline from the current repo.
   - Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and capture the
     output.
   - Confirm the command exits 0 with the current 0-error state.
   - Generate `tool/analyzer_baseline/flutter_analyze_baseline.tsv` containing
     only warning/info normalized keys and counts.
   - Include a header with generation command, date, and current counts.

4. Add `scripts/check_flutter_analyze_baseline.sh`.
   - Run `flutter analyze --no-fatal-infos --no-fatal-warnings`.
   - Save raw output to a temporary or caller-provided log path.
   - Invoke the Dart comparator against the checked-in baseline.
   - Exit non-zero on any analyzer error or any warning/info count above
     baseline.
   - Exit zero when all warning/info findings are within baseline, while
     printing the known debt count and any shrink opportunities.

5. Wire the full-regression runner.
   - Replace `run_step "flutter analyze" flutter analyze` with a clearer label
     such as `run_step "flutter analyze baseline gate"
     ./scripts/check_flutter_analyze_baseline.sh`.
   - Keep the step early in the run, after `flutter pub get`.
   - Preserve the existing full-regression behavior of continuing after a
     failing step and failing at the final summary.

6. Stop if the analyzer error count is not zero.
   - If the current repo has any analyzer `error`, do not baseline it.
   - Fix or separately plan that error first, then regenerate the warning/info
     baseline.

7. Run the direct tests and a dry/full regression probe.
   - First run the parser unit test and baseline script.
   - Then run full-regression `--dry-run` to verify the command label.
   - Finally run a non-dry-run full regression only after the baseline script
     passes.

### 10. risks and edge cases

- Flutter analyzer human output can change formatting across SDK upgrades. Keep
  parser tests small and explicit, and fail closed if parsing sees an analyzer
  row it cannot normalize.
- If a dependency upgrade changes many lint messages, the baseline gate should
  fail with a clear delta instead of silently accepting churn.
- If line numbers shift without semantic analyzer changes, the normalized key
  should avoid false positives.
- If a finding moves to a different file or rule, treat it as new debt unless
  the baseline is intentionally regenerated in review.
- Do not allow `error` severity in the baseline. Errors are build-blocking.
- The baseline file can become stale as debt is fixed. Treat shrink as a
  non-failing update prompt, not an implementation blocker.

### 11. exact tests and gates to run

Focused tests:

```bash
flutter test test/unit/analyzer_baseline_parser_test.dart
```

Analyzer proof:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
./scripts/check_flutter_analyze_baseline.sh
```

Runner shape proof:

```bash
/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh \
  --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app \
  --dry-run
```

Final confidence:

```bash
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 \
  /Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh \
  --repo /Users/I560101/Project-Sat/mknoon-2/flutter_app
```

Optional compatibility check if the parser test changes test-file coverage:

```bash
./scripts/run_test_gates.sh completeness-check
```

### 12. known-failure interpretation

- Current warning/info debt at or below the committed baseline is pre-existing
  analyzer debt, not a new full-regression failure.
- Any analyzer `error` is a build-blocking analyzer regression and must fail
  immediately; it is never accepted as baseline debt.
- Any warning/info key count above baseline is new analyzer debt and should fail
  the analyzer baseline gate until fixed or intentionally accepted by updating
  the baseline in review.
- Missing baseline keys are improvements and should not block the run.
- A raw `flutter analyze` command will still exit non-zero while fatal warnings
  and infos remain enabled; the baseline gate becomes the release-confidence
  command for full regression until full analyzer cleanup is complete.

### 13. done criteria

- `test/unit/analyzer_baseline_parser_test.dart` passes.
- `./scripts/check_flutter_analyze_baseline.sh` exits 0 on the current repo and
  reports 1,700 known warning/info findings, 0 errors.
- Adding a synthetic current finding in the parser test fails comparison.
- Adding a synthetic error in the parser test fails comparison even if present
  in a baseline fixture.
- Full-regression dry run shows an analyzer baseline gate label instead of a raw
  `flutter analyze` label.
- A non-dry full-regression run no longer fails solely because of unchanged
  analyzer warning/info backlog.

### 14. scope guard

Non-goals:

- no broad analyzer cleanup
- no global lint disabling in `analysis_options.yaml`
- no changing analyzer fatal defaults outside the wrapper command
- no changing named gate membership
- no hiding analyzer errors
- no per-feature lint policy redesign
- no CI provider or GitHub Actions work unless a CI file already calls the raw
  full-regression runner and must be kept consistent

Overengineering includes building a custom analyzer plugin, introducing a new
package dependency for TSV/JSON parsing, or trying to classify every analyzer
finding by product area in this session.

### 15. accepted differences / intentionally out of scope

- The raw command `flutter analyze` remains red until the repo actually fixes
  or suppresses warning/info debt.
- Existing lints stay enabled; the baseline records debt, it does not redefine
  style policy.
- Baseline isolation is a release-confidence bridge, not a substitute for a
  future analyzer cleanup project.
- Named runtime/test gates remain separate from static analyzer gating.

### 16. dependency impact

This plan unblocks meaningful full-regression interpretation after Report 76:
future full-regression runs can show whether tests/gates failed and whether the
analyzer regressed, without marking unchanged warning/info debt as new failure.

Later release or TestFlight work should still treat full analyzer cleanup as a
separate hygiene task. If the analyzer baseline gate starts failing, skip broad
feature work until the delta is fixed or explicitly accepted by a reviewed
baseline update.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Deciding whether the baseline artifact should be TSV or JSON during
  implementation; TSV is sufficient, JSON is acceptable if the code stays
  dependency-free and reviewable.
- Adding a separate "update baseline" convenience command. Initial
  implementation can generate the baseline through the comparator itself or a
  documented one-off command.
- Grouping analyzer debt by feature owner in docs.
- Cleaning the largest debt buckets such as `avoid_print` and
  `deprecated_member_use`.

## Accepted differences intentionally left unchanged

- `flutter analyze` remains red as a raw command.
- The full-regression runner stays non-fail-fast and reports all failed labels
  at the end.
- `analysis_options.yaml` keeps the Flutter lints include and does not suppress
  current findings.
- Report 76 remains closed; this plan only changes analyzer failure
  interpretation.

## Exact docs/files used as evidence

- `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md`
- `/Users/I560101/.codex/skills/flutter-full-regression-runner/scripts/run_full_regression.sh`
- `analysis_options.yaml`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/76-full-regression-follow-up-plan.md`
- `.full_regression_logs/20260426_103445/summary.tsv`
- `.full_regression_logs/20260426_103445/004_flutter_analyze.log`
- `.codex-test-logs/flutter_analyze_baseline_probe_20260426.txt`
- `flutter analyze --help`

## Why the plan is safe or unsafe to implement now

The plan is safe to implement now because it does not change product behavior,
test semantics, or lint policy. It adds an evidence layer around existing
analyzer output and changes full-regression reporting from "all old debt is a
fresh failure" to "errors and debt deltas fail; unchanged debt is isolated."

Implementation would be unsafe only if the current repo had analyzer errors,
because baselining errors would hide build-breaking regressions. The current
probe has 0 errors, so the session can proceed with warning/info baseline
isolation.

## Reviewer pass

Reviewer verdict: sufficient with adjustments.

Required adjustments applied:

- made analyzer `error` severity explicitly unbaselineable
- required a parser/comparator unit test before runner wiring
- specified stable comparison keys and count semantics
- required full-regression dry-run proof for the changed command label
- kept `analysis_options.yaml` and named gates out of scope

## Arbiter pass

Structural blockers: none.

Incremental details: baseline artifact format and convenience update command can
be decided during implementation without changing the plan.

Accepted differences: raw `flutter analyze` remains red; full analyzer cleanup
is a separate task.
