# Android audio-call thermal investigation handover

Prepared 2026-09-19 for a new session in `/Volumes/CrucialX9/flutter_app`.

## Only task to continue

Investigate the remaining **thermal/throttling observation during long audio
calls**. Establish whether current application work materially contributes,
identify the responsible work if reproducible, and fix and measure any confirmed
app defect. The existing evidence does not establish a thermal fix or isolate
the effect on users.

The functional audio-call repairs and available Android scenario checks have
their own passing evidence. This handover does not reopen them or assign the
separate final full-regression backlog. Use the findings documents as evidence,
not as instructions to rerun their historical failure catalog.

Read root [AGENTS.md](../../AGENTS.md) first. No skill or subagent is implicitly
authorized. Prefer actual Appium MCP tools for device UI and lifecycle work;
use existing native/media instrumentation for facts UI inspection cannot prove.

## Established facts and their limits

The original measurements used a build-137 debug app, a USB-connected Pixel 6,
and an Android emulator. They are historical observations, not measurements of
the newly committed source.

| Observation | Retained measurement |
| --- | --- |
| Physical phone originates | Connected for 616.435 seconds; six twelve-second bidirectional PCM probes, normal End and resource cleanup passed. |
| Physical phone during that run | Thermal status rose from 1 to 3. Battery-service temperature rose from 387 to 430 tenths °C, or 38.7 to 43.0 °C. |
| After that call | Screen-off/secure-lock idle readings still showed status 3 and 43.6 °C. At 522.612 seconds after End, status was 2 and battery temperature was 42.2 °C. |
| Emulator originates next | Connected for 617.713 seconds; all six PCM probes, End and cleanup passed. The physical phone started at status 2 and about 41.7 °C, stayed at status 2, and reached 43.0 °C at the end of the hold. |
| Measurement conditions | The physical phone remained USB powered. Thermal override was false. The cooldown intervention was screen off/secure lock; charging configuration was not changed and the app was not stopped. |

Android status 3 was the severe-throttling observation recorded in the findings.
Battery-service temperature is a separate measurement from individual thermal
sensors. Raw `thermalservice` dumps contain both **cached temperatures** and
**current temperatures from HAL**; keep their provenance separate when parsing.

The different initial temperatures, preceding device workload, screen state,
debug instrumentation, charging and unmeasured ambient conditions prevent a
direction-dependent or app-only causal conclusion. A short CPU snapshot cannot
exclude GPU, modem or charging contributions. Short PSS growth does not prove a
memory leak. Successful decoded PCM does not establish perceived speech quality
or thermal efficiency.

An earlier repair already suspends the obscured route's animations using
`TickerMode` in
[foreground_call_overlay.dart](../../lib/features/call/presentation/foreground_call_overlay.dart).
Its [widget tests](../../test/features/call/presentation/foreground_call_overlay_test.dart)
prove ticker behavior. **No measured heat, CPU or battery improvement has been
attributed to that repair.** Treat it as an existing change to measure, not an
established explanation for the old thermal result.

## Start from these records

Canonical explanations:

- [Findings: long-call measurements and resource observations](audio-call-beta-findings.md#long-call-measurements-and-resource-observations).
- [Findings: thermal observation row](audio-call-beta-findings.md#additional-defects-and-evidence-corrections).
- [Scenario catalog](audio-call-beta-scenarios.md): historical `AUDIO06` and its limits.
- [Testing knowledge](TESTING.md): search for `Keep resource and thermal observations`
  and `TickerMode`; these distinguish verified behavior from thermal hypotheses.

Original local evidence, retained under ignored `.codex-test-logs/`:

- [Physical-origin result](../../.codex-test-logs/android-audio-beta-20260916/137-long01-rel02-physical/result.json).
- [Physical-origin samples](../../.codex-test-logs/android-audio-beta-20260916/137-long01-rel02-physical/resource-samples/):
  `before-call.json`, `before-hold.json`, `hold-120s.json`, `hold-240s.json`,
  `hold-360s.json`, `hold-480s.json`, `after-hold.json`, `after-call.json`,
  plus the original per-device thermal and memory dumps.
- [Cooldown summary](../../.codex-test-logs/android-audio-beta-20260916/137-long01-rel02-physical/between-case-review/cooldown-summary.json)
  and its referenced `cooling-check01.json` through `cooling-check03.json`.
- [Emulator-origin result](../../.codex-test-logs/android-audio-beta-20260916/137-long01-rel02-emulator/result.json)
  and the adjacent `resource-samples/` directory with the same sample names.

These local artifacts are not included in Git. Preserve them and their original
verdicts; do not overwrite them with a new measurement. If unavailable in a new
checkout, record that limitation and use the same-workstation retained copy.

## Environment and source identity

- Current workspace: `/Volumes/CrucialX9/flutter_app`, branch `main` at handover.
  Record the actual `git rev-parse HEAD` and working-tree status at session start;
  the local commit containing this handover captures the completed repair batch.
- The last pre-commit MAIN source fingerprint was
  `a11d15c7451ba30f34783879ab851e39fdb15fe948f4d9c694da82de1bc9d6c9`.
  It is a retained validation identity, not an installed-APK identity or a thermal
  result. Recheck the candidate's source, build mode, configuration, package,
  version, APK digest and installed artifact before measuring.
- Last observed targets: physical `21071FDF600CSC` (Pixel 6, Android 17/API 37)
  and `emulator-5554` (Android 17/API 37). Resolve current availability with
  `flutter devices --machine` and `adb devices -l`, then pin explicit IDs.
  The physical phone supplies thermal evidence; emulator thermals do not stand
  in for physical hardware. No iOS or unavailable accessory is a required leg.
- Flutter SDK used for the retained checks:
  `/Users/I560101/development/flutter-3.47.2/bin`; Android SDK ADB:
  `/Users/I560101/Library/Android/sdk/platform-tools/adb`.
  Match `.dart_tool/package_config.json` before running checks.
- Use the existing AWS relay configuration at `mknoun.xyz`, as the user requested.
  Protected-media admission remains enabled in source and persistently enabled
  on AWS. Keep that setting and SSH rule `sgr-03654f6ce286fe215` in security group
  `sg-00631436a462a9bad`. Thermal measurements need no relay restart, firewall
  change or temporary admission window.
- The last APK used for AWS11 was a **group-media fixture**
  (`com.mknoon.sims.groupmedia269`); it is not the audio-call thermal candidate.
  Do not assume the primary installed call app matches the latest source.
- At the end of the prior work, task-owned tests, observers and Appium sessions
  were stopped, both devices had idle instrumentation, and the phone was locked
  with `stay_on_while_plugged_in=2`. Recheck current ownership and settings;
  preserve foreign sessions and restore only changes owned by the new run.

## Bounded investigation sequence

1. Read the original samples and reconstruct one timeline per call: initial
   temperature/status, connection and PCM intervals, screen state, End and
   cooldown. Preserve battery and HAL sensor sources separately. Write down
   what was not measured rather than filling it in from assumptions.
2. Establish a current-source baseline using the available Android pair and
   disposable test identities. Record charging/power state, brightness and
   screen state, network/transport, build mode, installed artifact and starting
   thermal condition. Observe a comparable settled baseline before comparing
   runs; log ambient conditions if known and state when they are unknown.
3. Use the smallest matched comparison that can isolate a contribution: idle
   versus active call under the same screen, power, network and sampling
   conditions. If evidence points at UI work, vary foreground/background or
   covered-route state in a separate comparison. Vary one factor at a time and
   keep any further direction reversal or screen-off comparison evidence-led.
4. Collect bounded CPU/thread, frame/render, thermal and memory measurements,
   and preserve existing call audio/control/cleanup checks. Reuse the established
   resource sampler and native media proof where suitable. Appium should own
   setup and UI actions; a narrow read-only sampler may collect OS/process facts.
   Record sampling/profiling overhead and avoid continuous heavy dumps or
   screenshots that would become the workload. If a profile build is useful,
   retain its distinct artifact/configuration and do not treat it as identical
   to the original debug build.
5. Follow measured work to its current source owner. UI tickers, render work,
   native audio processing, logging and periodic work are hypotheses until
   supported. If an app defect is isolated, make the smallest repair, add a
   meaningful causal regression, and run the focused affected checks. Repeat
   only the necessary matched device comparison to measure the effect while
   retaining the first failure and original assertions.

Do not disable or override Android thermal protection to make a run pass. End
the workload and allow normal cooling if device protection requires it. Keep
credential-entry intervals outside observers, recordings and retained raw logs.
Do not replace Appium with a new general UI harness. End the task's own Appium
instrumentation before handing a device to another instrumentation owner.

Before any code-changing validation, consult `TESTING.md` and
`tool/testing/selection.json`, validate the manifest, and preview/run the relevant
selection with an explicit verified `--base` and `--local`. The full suite is not
an automatic per-bug rerun, and the unrelated final batch sweep is outside this
handover. Report omitted checks without presenting them as passing.

## Completion evidence

Update the thermal finding in the existing findings/scenario records and add
confirmed reusable knowledge to `TESTING.md`. Retain raw measurements privately
in a new ignored artifact directory and link a concise conclusion showing:

- Exact source/build/configuration and the physical-device conditions measured.
- Comparable baseline, active-call and cooldown observations, including any
  reproduction failure or unavailable metric.
- The supported cause and measured effect of a fix, or evidence that narrows
  attribution without establishing an app defect. `Not reproduced` is not
  equivalent to `fixed`; leave unresolved attribution explicit.
- Preserved audio/control/cleanup behavior and restoration of owned device state.

The acceptance decision is about the thermal observation. Another functional
call PASS alone cannot close it.

## Prompt for the new session

> Read AGENTS.md and docs/testing/audio-call-thermal-handover.md. Investigate only
> the remaining Android audio-call thermal/throttling observation. Use actual
> Appium MCP where applicable, matched physical-device measurements and existing
> native/media proof. Fix and validate any confirmed app cause, preserve the
> original observations, and keep AWS enabled and the SSH rule unchanged. Do not
> expand into the broader regression backlog.
