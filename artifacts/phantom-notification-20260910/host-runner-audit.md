# Host runner and fixture diagnostic audit

No source changes were needed in `scripts/run_host_test_gates.sh`.

## 1to1 runner diagnostic

The completed 1to1 log records **3747 passing tests, 4 skipped tests**, followed
by `PASS: Flutter batch (222 test paths)` and `status: unbound variable`. The
command returned 0.

The runner's top-level EXIT trap only removes its four temporary plan/failure
files. Every normal `$status` expansion follows an assignment in a failure
branch; this is not an EXIT-trap variable-scope defect.

The runner was edited in place while Bash waited for Flutter:

- First timestamped Flutter output: 2026-09-10 08:28:58.960681 UTC.
- Runner file modification: 2026-09-10 10:30:02 CEST, or 08:30:02 UTC.
- Completed gate log modification: 2026-09-10 10:31:35 CEST, or 08:31:35 UTC.

An isolated copy of the real runner with a blocked fake Flutter command
reproduces the diagnostic when bytes are inserted before Bash's saved script
read offset. Once the already-parsed batch conditional finishes, Bash resumes
inside an old failure-branch statement at the displaced offset.

| Isolated execution | Exit | Final host PASS | Unbound status | Temporary files before/after |
| --- | --- | --- | --- | --- |
| Intact runner copy | 0 | Present | Absent | 4 / 0 |
| Runner copy edited while fake Flutter waits | 0 | Missing | Present | 4 / 0 |

Reproduce with:

```sh
python3 artifacts/phantom-notification-20260910/host_runner_edit_offset_repro.py
```

The harness changes only temporary runner copies. It redirects temporary-file
creation into an isolated directory to check the actual EXIT cleanup. Complete
output is in `host_runner_edit_offset_repro.log`.

The actual 1to1 inventory explicitly says **222 Dart paths and 0 separate
non-Flutter invocations**. Therefore **zero test steps remained** after its
successful Flutter batch. The interrupted suffix only checks the failures file
and prints the final host summary. The reproducer confirms that the EXIT trap
still removes all four temporary files; historical temp filenames from the
actual run were not logged and cannot be independently enumerated afterward.

## Disposable production-call fixture diagnostic

`Shell: Disposable production-call fixture teardown failed.` is a separate,
expected failure-injection diagnostic from the test
`adapter stops the combined fixture after every central terminal path` in
`test/integration/android_production_audio_call_campaign_test.dart:1561`.

The test injects a fake fixture whose stop callback increments a counter, then
throws for one case. It asserts that stop runs once, the fake central operation
runs once, and the adapter returns 1 for the teardown failure. The production
adapter emits the exact message at
`integration_test/scripts/run_production_audio_call_sims.dart:278`.

Running that exact test alone prints the same diagnostic and passes:

```sh
/Users/I560101/development/flutter-3.47.2/bin/flutter test \
  test/integration/android_production_audio_call_campaign_test.dart \
  --no-pub \
  --plain-name 'adapter stops the combined fixture after every central terminal path' \
  --reporter expanded
```

See `fixture_teardown_diagnostic_focused.log`. The injected dependencies do not
start a real relay or coturn fixture, so this diagnostic does not indicate an
unreleased real fixture from the host gate.

## Core-host-all continuation inventory

`core-host-gate.log` records 452 Dart paths and **2 separate non-Flutter
invocations**. Its Flutter batch exited 1 for the two DTR18 sentinel failures,
before the non-Flutter loop. These exact tails still require execution:

```sh
./scripts/check_android_renderer_manifest_contract.sh
./scripts/check_dropped_push_recovery_manifest_contract.sh
```

They are planned items 1 and 2 respectively. The runner supports
`--only <planned-index|exact-path>` for one item and `--start-at` for a suffix.
It has no rerun-failed mode. After correcting only the two frozen-hash sentinel
expectations, rerun their exact Dart files with the pinned Flutter executable
and execute the two scripts above; this audit does not call for replaying the
thousands of already-passing tests.

Graph navigation used the supplied runner query
`d1e7f3753e77460e` / `a17b573a1eea2e0d`, and the fixture branch query
`9286d00d6c4a4a3c` / `0c4c55dc37183c4d`. No source file was edited during this
audit, and no full Flutter suite was rerun.

## Manifest-check recovery outcome

The two initially parallel manifest checks both reached `:app:buildGoAar`, which
launched independent gomobile builds writing the same generated AAR and input
stamp. Renderer failed to rename `GoMknoon.inputs.sha256.tmp` because that shared
temporary file had disappeared. Dropped-push then failed Jetifier transformation
with `ZipException: invalid bit length repeat`. Independent full ZIP checking
confirmed the generated AAR was corrupt. The original Gradle logs are preserved
as `core-android-renderer-original-gradle.log` and
`core-dropped-push-original-gradle.log`.

Both wrappers had already exited when interruption was requested; no process was
killed. After verifying no Android gomobile builders remained, the ignored input
stamp was moved into the artifact folder, and the existing
`bash scripts/ensure_go_android_bindings.sh` path rebuilt the AAR once from current
source with Go 1.25.0. Full ZIP verification passed for the archive and all four
Android ABI JNI entries.

The checks then ran strictly sequentially and both passed:

| Check | Gradle result | Manifest result |
| --- | --- | --- |
| Renderer profile/release | BUILD SUCCESSFUL in 18s | PASS Skia/OpenGLES, Impeller=false, PiP/share/egress preserved |
| Dropped-push debug | BUILD SUCCESSFUL in 6s | PASS custom messaging owner/receiver and required priorities |

Final evidence:

- `android-aar-recovery-build.log`
- `android-aar-recovery-zip-check.log`
- `core-android-renderer-contract-final.log`
- `core-android-renderer-final-gradle.log`
- `core-dropped-push-contract-final.log`
- `core-dropped-push-final-gradle.log`

The final AAR SHA-256 is
`f6c16f714b2b49cf7ee4c70bbb71df542ffdfe98e2fc7b336588f6b1e07f78fa`;
its ZIP integrity was rechecked after both manifest tasks. No source changes or
unrelated process cleanup were made during this recovery. This completes the
two non-Flutter tails omitted by the original failed core batch.
