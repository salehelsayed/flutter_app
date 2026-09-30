---
name: mknoon-wave2-rerun
description: Rerun Mknoon Wave 2 acceptance checks on the current candidate with fresh evidence, pinned available devices, exact cleanup review, and a scoped verdict. Invoke as $mknoon-wave2-rerun; optionally request android, ios, or host scope.
---

# Mknoon Wave 2 rerun

Use this skill only when the user's current message affirmatively invokes
`$mknoon-wave2-rerun`. An invocation authorizes the tests in the requested
scope. With no scope, rerun the complete Wave 2 acceptance set: focused host
checks, one wave-boundary `host-all`, the four Android campaigns, and the iOS
native Plan 373 result. `android`, `ios`, and `host` limit execution to that
scope. Do not invoke another skill unless the user names it separately.

This is a **new candidate rerun**, not a replay of the historical verdict.
Preserve all earlier receipts and failures. Never write into an existing run
directory, commit or push, start Waves 3–5, or treat this as release approval.
The user accepted the native S16 speaker-path receipt as Wave 2 audible-device
evidence; direct acoustic hearing remains unverified. Run the original 17-case
sound campaign when Android is in scope, but do not launch extra recording or
repeat campaigns solely to try to hear S16.

## Establish the candidate and targets

1. Read the relevant Wave 2 entries in `docs/testing/TESTING.md`, the current
   closure section in `docs/testing/production-bootstrap-migration-crosswalk.md`,
   and the executable IDs in `tool/testing/selection.json`. Follow the root
   `AGENTS.md` availability, ownership, and first-failure rules.
2. From the repository root, use Flutter
   `/Users/I560101/development/flutter-3.47.2/bin` if it still exists and
   reports Flutter 3.47.2 / Dart 3.13.2. The default shell Flutter was 3.41.4
   at skill creation and caused a pre-assertion iOS build failure. If the
   expected SDK is unavailable, resolve the repository-compatible SDK before
   testing; do not silently use the default.
3. Discover live IDs with `flutter devices --machine`, `adb devices`, and
   `xcrun simctl list devices available`. Pin every command. Prefer the
   historical USB Pixel `21071FDF600CSC` plus `emulator-5554` only if both are
   available and unowned. The recorded ignored device config is
   `.codex-test-logs/production-bootstrap-migration-20260928/wave2-continuation-001/provider-device-config-emulator-5554.json`
   (recorded SHA-256
   `38a3095fa6210407423372aaacfe9eaa66a81d3d05cce8e8cf551c3404cfb5c2`).
   Verify its disposable accounts, provider readiness, exact device IDs and
   current hash without printing secrets. If a different available emulator
   or config is needed, validate it and record the new identity. Do not take
   another owner's device. An unavailable version-specific target is N/A by
   project policy, not a failed gate.
4. Resolve a verified explicit `--base`. The historical Wave 2 comparison
   commit is `06d5ab5704cf0106e730f0dab17b0abfd645fe7c`; use it only if
   it exists and is an ancestor of the current candidate, or use a different
   base supplied and verified for the intended comparison. Include `--local`
   when staged, unstaged, or nonignored untracked changes are part of the
   candidate. Do not assume `HEAD~1` is the base. Record `git rev-parse HEAD`,
   dirty status, tool versions, device/config identities, and run scope.
5. Create a unique ignored directory, such as
   `mktemp -d .codex-test-logs/wave2-rerun.XXXXXX`. Keep plans, wrapper
   results, host logs, native logs, first failures, and a concise summary
   there. Never overwrite a prior attempt.

## Plan and execute

Run `python3 scripts/mknoon_checks.py validate`, then preview with
`python3 scripts/mknoon_checks.py plan --mode change --base "$WAVE2_BASE"
--local --device-config "$WAVE2_CONFIG" --output "$WAVE2_RUN/plan"` when
`--local` applies. Review selected IDs, setup prerequisites and unmapped
changes. A successful setup or plan is not a passing test. Use the wrapper's
preflight before each long device campaign. Keep one automation owner per
device; end your Appium MCP session before handing it to Maestro or native
instrumentation. Use Appium MCP for live UI diagnosis if needed, without
building another generic UI harness.

For `host` or the default full scope, run the eight focused IDs through
`mknoon_checks.py run --mode change` with the same base/local/config and a fresh
`--output`, using:

`workflow,provider-schema,strict-group-media-manifest,runtime-roots,debug-composition-boundaries,sims-plan-contract,production-journey-contracts,maestro-flow-contracts`

Use `--only` for that exact list only if the current preview selects the IDs;
otherwise identify and explain the current applicable focused selection. Then
run **one** `bash scripts/run_host_test_gates.sh host-all --batch-flutter
--continue-on-failure` on the candidate, with a bounded Flutter concurrency
chosen from current host capacity, a live pinned
`MKNOON_NATIVE_IOS_SIMULATOR_ID`, and all output redirected into a fresh log.
That full gate includes the Go/relay tails and native Plans 371, 373 and 374;
inspect each result rather than inferring a full pass from the Dart total.
If no iOS target is available, run the applicable host portions, mark that
specific native target N/A, and do not mislabel the full script's status.
Keep any first batch failure visible; use exact causal diagnostics before a
justified rerun. Do not automatically repeat the full host sweep.

For `ios` or the default full scope, verify the Plan 373 native result from
the full host run. If the host gate did not execute Plan 373, or if `ios` was
requested alone, run `bash scripts/test/run_ios_nse_native_373.sh` with a
discovered available simulator pinned by
`MKNOON_NATIVE_IOS_SIMULATOR_ID=<id>` and a fresh
`PLAN373_NATIVE_RESULT_DIR=<new-output-dir>`. This wrapper temporarily mutates
Swift source. Ensure exclusive source/device ownership, check all three
expected-red controls, the restored control, and the 28-method final summary,
then verify the source was restored and owned DerivedData cleaned. Do not
count a toolchain/setup failure as a native assertion failure.

For `android` or the default full scope, run these four `--only` checks **in
order and one at a time** through `mknoon_checks.py run --mode change` with the
same verified base, local flag and ignored `--device-config`. Give each a new
`--output` subdirectory:

1. `production-notification-open`
2. `production-private-media`
3. `production-routing`
4. `production-notification-sound`

Before the next campaign, inspect the current one's named `PASS`/`FAIL`, SIMS
report, first-failure artifact, and `cleanup.json` exact restoration for both
pinned peers. The `--only` wrapper can be overall `BLOCKED` because other
selected checks are intentionally `NOT RUN`; that status does not replace the
named campaign verdict. Never use `--rerun-failed` for device campaigns. After
a launched failure or setup block, diagnose the cause, retain the first
attempt, verify owned-state cleanup, and make a fresh invocation only if a
causal repair or transient setup check justifies it. Keep original assertions
and deadlines. Stop and report a genuine unavailable prerequisite rather
than silently substituting historical passes for the current candidate.

## Assess and report

Compare campaign source digests, ignored config identity, APK artifact hashes,
build/cache ledgers, selected case counts, empty oracles, cleanup receipts,
and the host/native source and result summaries. Reuse is valid only for
attested compatible artifacts. A later different source/configuration needs
its own evidence; historical Wave 2 passes remain historical. For S16,
distinguish the 17-case functional/native result and speaker-path observation
from direct acoustic hearing. Do not claim a waveform or human hearing.

Report the exact run directory, candidate/base, target IDs, each PASS/FAIL/
BLOCKED/NOT RUN/N/A and reason, build/cache accounting, cleanup, first failures,
and whether this **new run** supports a scoped Wave 2 verdict. Note wider
dirty-tree and release obligations separately. Update `docs/testing/TESTING.md`
only for confirmed new regression, dependency, runtime or reliability
knowledge, with raw evidence retained under the ignored run directory.
