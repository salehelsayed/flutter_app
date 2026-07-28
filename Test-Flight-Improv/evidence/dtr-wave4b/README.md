# DTR Wave 4B acceptance evidence

Date: 2026-07-28

Scope: DTR-14 / Plan 293 and DTR-15 / Plan 294

Wave verdict: **Wave-accepted** on 2026-07-28

Execution shape: full `host-all`, one serial Flutter batch, concurrency 1,
`failures-only`, continue-on-failure, followed by the required same-tree
`performance-host` replay with no intervening edits

## Acceptance receipt

The exact accepted commands, in order, were:

```bash
./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 1 --reporter failures-only
./scripts/run_host_test_gates.sh performance-host
```

The raw `tee` logs begin with each gate's internal command plan and end with
its scope-completion marker. The surrounding automation record, rather than
the raw logs themselves, retains the two top-level invocations, process return
codes, and durations.

The full `host-all` gate planned and passed all 1,273 items:

- 1,265 exact Flutter test paths in one serial batch;
- 12,825 Flutter tests passed, one declared test skipped, and zero failed;
- all eight serial Go tails passed;
- final `PASS: host tests completed for scope: host-all`;
- process exit 0;
- duration 1,898 seconds.

The required same-tree `performance-host` replay also passed:

- 21 exact Flutter test paths;
- 106 Flutter tests passed, zero skipped, and zero failed;
- final scope-completion marker present;
- process exit 0;
- duration 97 seconds.

The accepted original logs and deterministic `gzip -n` archives are:

| Artifact | Path | Size (bytes) | SHA-256 |
|---|---|---:|---|
| Original `host-all` log | `build/wave4b-logs/wave4b-host-all-accepted.log` | 14,707,574 | `24b623e2b9142e8c50aa8add4ae031ddb385fad1b958a4bd6f80defb912f1e97` |
| Deterministic `host-all` archive | `Test-Flight-Improv/evidence/dtr-wave4b/wave4b-host-all-accepted.log.gz` | 1,138,080 | `e6c66cc032380ef755c32565f7e491a851b80cc5af918f182333dcf057c35bed` |
| Original `performance-host` log | `build/wave4b-logs/wave4b-performance-host-accepted.log` | 72,560 | `b0fb2b84ad77a98032cc3a12365fa580810c080ceb3db9bcda133785861dbb63` |
| Deterministic `performance-host` archive | `Test-Flight-Improv/evidence/dtr-wave4b/wave4b-performance-host-accepted.log.gz` | 9,906 | `579c25b54a4fec6a28ba361ff82bac43805845eb7cef499ec0526f43d16a3256` |

Decompressing each archive reproduces its corresponding original-log SHA-256
exactly. The raw logs remain ignored under `build/wave4b-logs/`.

## Tested state and workspace disclosure

The pair ran in the shared dirty workspace, not in a detached worktree. It
used the workspace and toolchain state already present at execution time; no
ignored native or runtime prerequisite was copied into another worktree.

The `host-all` gate and required `performance-host` replay used the same frozen
tested state. No source or test file changed between the two accepted commands.
An alternate Git index captured tracked files plus untracked, nonignored files
without replacing the shared index.

The execution automation captured the following alternate-index checkpoints:

| Checkpoint | `HEAD` | Tested tree | Shared-index SHA-256 |
|---|---|---|---|
| Before `host-all` | `765be74523b25ce592ff200ff435653b35c66b4d` | `51455d3c1905a6bd70be63c59fdcc3860623778f` | `3a77c0c7081a9eddf26e45298a1589270a585444bae4d2ee6a3e34c263483383` |
| After `host-all`, before `performance-host` | `765be74523b25ce592ff200ff435653b35c66b4d` | `51455d3c1905a6bd70be63c59fdcc3860623778f` | `3a77c0c7081a9eddf26e45298a1589270a585444bae4d2ee6a3e34c263483383` |
| After `performance-host` | `765be74523b25ce592ff200ff435653b35c66b4d` | `51455d3c1905a6bd70be63c59fdcc3860623778f` | `3a77c0c7081a9eddf26e45298a1589270a585444bae4d2ee6a3e34c263483383` |

The pre-host porcelain-v2 workspace snapshot SHA-256 was
`56036def89b64011e08ef3d64d00398cc31a18920598102d6585479b4a4e9d13`.
The raw-log filesystem timestamps corroborate the execution order:
`host-all` was created at `2026-07-28T12:36:36+02:00` and closed at
`13:08:14`; `performance-host` was created at `13:08:52` and closed at
`13:10:29`; the retained tag was created afterward at `13:11:01`.

The retained tested-state identities are:

- base commit and unchanged `HEAD`:
  `765be74523b25ce592ff200ff435653b35c66b4d`;
- tested tree:
  `51455d3c1905a6bd70be63c59fdcc3860623778f`;
- synthetic commit:
  `4f36940866dd12e65f15c302c0c37e2d2a65899f`;
- annotated tag:
  `dtr-wave4b-tested-tree-20260728`;
- annotated-tag object:
  `35a406339ee282d8b9f64e28c7af8df68561be9e`;
- shared-index SHA-256 before and after the same-tree gate pair:
  `3a77c0c7081a9eddf26e45298a1589270a585444bae4d2ee6a3e34c263483383`.

The synthetic commit has the base commit as its parent and the tested tree as
its tree. The evidence README and deterministic archives postdate acceptance
and are intentionally not represented as files in that tagged tested tree.
The tag and evidence remain local-only unless they are later committed and
pushed.

Provenance boundary: the archived gate logs independently retain the internal
inventories, per-path results, totals, and final PASS markers. They do not
embed the external alternate-index commands or snapshots. The exact
top-level-command ordering and same-tree claim therefore rely on the captured
execution-automation record and checkpoints above, as do the literal process
exit-code claims. The log and tag timestamps corroborate ordering; none of
these facts is restated as if the raw logs alone proved it.

## Closure

This receipt accepts DTR-14 / Plan 293 and DTR-15 / Plan 294 in Wave 4B. Both
plans remain Plan-green and are now Wave-accepted. This clears the DTR-16 and
DTR-17 predecessor dependencies for planning only; it does not authorize Wave
4C execution.

Final release-closure `host-all` and the required `performance-host` replay
remain separate later obligations.
