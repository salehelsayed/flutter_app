# DTR Plan 287 and Wave 3 host-all evidence

Date: 2026-07-27
Scope: terminally retained DTR-09, terminally complete DTR-10, and
owner-approved DTR-11 / Plan 287
Execution shape: frozen synthetic commit, batched Flutter, concurrency 4,
`failures-only`

All archives are deterministic `gzip -n` copies of the original logs. The
“uncompressed SHA-256” values identify the exact original log bytes.

| Gate | Accepted result | Archive | Uncompressed SHA-256 | Archive SHA-256 |
|---|---|---|---|---|
| Plan 287 `groups` | 3,235 Flutter tests plus every configured bridge/node/relay tail; exit 0 | `plan287-groups-accepted.log.gz` | `7500982c5d74e2f8e53b0ac8d347980c8f2275b5ecf9807cf21fcf680e05a37e` | `5e20467642c610567ae0d430aac08adc890e51873fbdd13854e7677d49962003` |
| Plan 287 `1to1` | 2,441 Flutter tests plus relay toolchain/server tails; exit 0 | `plan287-1to1-accepted.log.gz` | `1e873f8dcee87d4194ad6cfd2794a7f8d3e77f50c84fe39cd7387c0081061b76` | `d19b0a4e8b2f63537c0999c8b41a894cfe45b39dc2d734e1bfefe21540998bcf` |
| Plan 287 `feature-host-all` | 805 exact Dart paths; 8,410 passed, one skipped, zero failed; exit 0 | `plan287-feature-host-all-accepted.log.gz` | `c796a42ff5076cc3a57c06b7a80cb23f9d8568f4ee87c08e59f4378c8b08dd54` | `b60bbc32322b135f6fa5d1dc1595f57b6b1668c016fb220dffc21a69391c48bc` |
| Plan 287 `core-host-all` | 354 exact Dart paths; 2,794 passed, zero failed; profile/release renderer contract passed; exit 0 | `plan287-core-host-all-accepted.log.gz` | `1b1b33a128fcb2f770e4b61c58a988b27fa9cf26f11afdc1930a0c719e74ce08` | `2daf66ac8f7754336405348fd36fe28417befdf0013ed9795710620453146cb8` |
| Wave 3 aggregate `host-all` | 1,250 exact Dart paths; 12,755 passed, one skipped, zero failed; all eight Go tails passed; exit 0 | `wave3-host-all-accepted.log.gz` | `4b45449c2d064c8358fc895b580e249404faf995e95d12a7a6369600fab338d9` | `55ac78d1a0fd2a98b70884194e5cb6677ff0dba474ca24594f469165e97806f7` |

## Frozen tested state

The accepted gates ran in a detached worktree created from an alternate index,
so concurrent changes in the shared dirty workspace could not enter the test
set and the shared index was not rewritten.

- synthetic commit:
  `ec268ce4a41d94450919170c9df2b1bf1a7ef987`;
- synthetic tree:
  `897a285f68f1266dc6945f727f2425272151f068`;
- durable repository tag:
  `dtr-wave3-tested-tree-20260727`;
- shared-index SHA-256 before and after snapshot creation:
  `e3121a0ad4f4c712fc3eafaddcf5cb3caeaba158d148b9f85ec108c369b77009`.

The tested-state commit is the direct parent of the closure-record commit, so
the exact tested tree and this evidence pack are repository-reachable rather
than dependent on an unreferenced local object.

The detached worktree initially omitted local, Git-ignored build/runtime
prerequisites. Exact byte-identical copies from the shared workspace were
restored before the affected accepted feature/core runs and the aggregate:

- `ios/Runner/GoogleService-Info.plist`;
- the iOS device, iOS simulator, and macOS `GoMknoon` framework binaries;
- `android/app/libs/GoMknoon.aar`;
- `android/gradlew` and `android/gradle/wrapper/gradle-wrapper.jar`.

One initial feature attempt stopped on the missing plist. A first core attempt
stopped on the missing native binaries; its retry completed all Flutter paths
but stopped when the renderer checker found the missing Gradle wrapper. Those
three fixture diagnostics are not acceptance evidence. No tracked source or
test correction was made in response. After restoration, the exact wake-binary
freshness selector and the profile/release Android renderer manifest contract
both passed, followed by the complete accepted family runs.

## Wave 3 aggregate

The aggregate command was run only after Plan 287's focused, curated, feature,
core, analyzer, completeness, runtime-root, l10n, and Graphify gates were
green:

```bash
./scripts/run_host_test_gates.sh host-all \
  --continue-on-failure \
  --batch-flutter \
  --concurrency 4 \
  --reporter failures-only
```

It planned and passed all 1,258 items:

- 1,250 exact Flutter test paths;
- 12,755 tests passed and one declared SQLCipher-capability test skipped;
- all eight separate Go tails passed;
- final `PASS: host tests completed for scope: host-all`;
- process exit 0.

This receipt accepts Wave 3. It clears DTR-12/DTR-13's temporal Wave-3
dependency; it does not approve DTR-13's separately open QA + release
composition-root decision.
