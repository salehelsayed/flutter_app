# Plan 400 evidence — host closure 2026-09-04

Toolchain: host Mac Flutter (via `/claude-host-bin/flutter`), Xcode simulator for Swift, Gradle JVM for Kotlin.
Checkpoint commit before execution: `f2974b067`.

| Row | RED (before production edit) | GREEN | Notes |
|---|---|---|---|
| TC-400-01 | `Expected: null / Actual: CallAudioRouteException(selectionFailed)` | adapter file 59/59 | mutation re-red: `_releaseEndedHandleAudio` short-circuit removed → `selectionFailed`; restored → GREEN. Also asserts `deactivateAudio` after end makes no native call |
| TC-400-01b | GREEN sentinel | 59/59 | native terminal event → `_releaseRetainedTerminalAudio` |
| TC-400-02 | `Expected: CallAudioFailure.none / Actual: cleanupFailed` | audio controller 26/26 | second `close()` makes no further engine calls |
| TC-400-03 | `Expected: length 1 / Actual: []` (no `CALL_MEDIA_CLOSE_FAILURE_STAGE`) | diagnostics 7/7 | stages `audio_cleanup` / `engine_release` (+ `interruption_release`) |
| TC-400-04/05 | GREEN sentinels | 59/59, 26/26 | |
| TC-400-07/07b/07c/08 | revokes + `failClosed` recorded, `isStarted == false` (HEAD) | live-call guard 6/6 | 08b GREEN sentinel; 08c GREEN after 08 |
| TC-400-09 | `Expected: true / Actual: false` (`isStarted`) | composition 58/58 | `CALL_SIGNALING_RECONCILE_RESULT outcome=advertisement_deferred` |
| TC-400-10/12 | GREEN sentinels | 58/58, 19/19 | |
| TC-400-11 | `Expected: empty / Actual: [(epoch: 31, kind: iosVoip)]` | coordinator 19/19 | second publish is a real `publishToken` (2 publications) |
| TC-400-14/15 | not recorded separately | Swift 25/25 (`swift_runner_tests_2026-09-04.txt`) | `MknoonVoipPushRegistryTests` + `IosCallConfigurationTests` unchanged |
| TC-400-17/17b/17c/19 | `endpointMismatch` / `signalingUnavailable`, no pin | adapters 15/15 | 17c GREEN on HEAD; census `pinnedEndpoint(` = 4 |
| TC-400-18/18b | GREEN sentinels | 15/15 | |
| TC-400-06/13/16/20 | — | PENDING | device proofs are user-driven; tooling: `docker-ws/relay_ssh.py`, `docker-ws/relay_call_registry_probe.sh` |

Gates: `curated_1to1_lane_2026-09-04.txt` (Flutter leg 4165/4165; trailing device leg unselected → exit 1),
`host_1to1_batch_2026-09-04.txt` (PASS, 191 paths), `kotlin_call_unit_sentinel_2026-09-04.txt` (BUILD SUCCESSFUL),
`swift_runner_tests_2026-09-04.txt` (TEST SUCCEEDED). `affected` → 21 unit files 316/316. `completeness-check` PASS 1549/1549.
`flutter analyze`: No issues found. `git diff --check`: clean.
