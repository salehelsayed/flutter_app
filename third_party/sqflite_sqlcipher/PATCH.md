# Vendored `sqflite_sqlcipher` 3.4.0 — engine-owned Android scheduler

This fork was copied mechanically from the pub.dev-hosted
`sqflite_sqlcipher` **3.4.0** package pinned by the root lockfile. The hosted
archive/content SHA-256 recorded before the path override was:

```text
ba7733c5514cf0ccb0331997b771a890f73678bcd84cdfb5f7487a88a71f1738
```

Plan of record:
`Test-Flight-Improv/334-android-background-storage-queue-liveness-tdd-plan.md`.
The production edit was gated on the causal Pixel queue-inversion RED recorded
there on 2026-08-03 (nonce `b197a89d074548c7ad04d9410246172e`).

## Reviewed Android diff

The fork replaces the upstream process-static scheduler and ownership maps with
state owned by each `SqfliteSqlCipherPlugin` instance:

- one lazy FIFO `HandlerThread`/`Handler` per Flutter engine;
- per-engine database IDs, handle map, singleton/opening-path registries,
  locks, and mutable options;
- same-engine FIFO admission for open/query/execute/batch/insert/update/close/
  delete, while different engines progress independently;
- coalesced same-path singleton opens within an engine;
- detach fencing that stops admission, suppresses late Flutter results, drains
  admitted work, closes only that engine's handles, clears registries, calls
  `quitSafely()`, and acknowledges termination only after `join()`;
- close/delete/open ordering on the engine FIFO. Native-handle census reaches
  zero only after close succeeds; close failure remains visible and is returned
  to Flutter instead of being silently reported as success.

Delete coordination is intentionally engine-local. The isolation test proves
that deleting engine A's path does not stop engine B when B owns a different
path; it does not claim that one engine may delete a path still open in another
engine. App-owned production code has no database-delete caller. Any future
same-path delete must first establish exclusive runtime ownership outside this
plugin fork.

The exact allowlisted fork diff, excluding this provenance file, is:

- modified `android/build.gradle` — adds JUnit 4.13.2 only;
- modified
  `android/src/main/java/com/davidmartos96/sqflite_sqlcipher/SqfliteSqlCipherPlugin.java`;
- modified `SqlCommand.java` and `dev/Debug.java` beside it to replace the
  remaining process-static runtime debug flags with an immutable source-time
  switch and plugin-instance runtime options;
- added `EngineWorker.java`, `EngineState.java`,
  `HandlerThreadEngineWorker.java`, and `EngineDebugCensus.java` beside that
  plugin source;
- added
  `android/src/test/java/com/davidmartos96/sqflite_sqlcipher/EngineWorkerIsolationTest.java`.

`SqfliteSqlCipherPlugin.getDebugCensus()` exposes only aggregate H0 counters.
The existing `debug` method with `cmd: get` returns the same map under
`workerCensus`. Its exact fields are `liveInstances`, `liveWorkers`,
`liveHandles`, `queuedTasks`, `runningTasks`, `detachedInstances`,
`terminatedInstances`, and `suppressedResults`; it retains no engine IDs,
database IDs, paths, SQL, keys, or message content.

## Pinned boundary

The patched 171-file tree (all files except this `PATCH.md`, sorted by relative
path and hashed as `path + NUL + bytes + NUL`) has SHA-256:

```text
c4bcb962748f8bd99e4f514e6465003416dd03a502d773f51cf7493d7b763acb
```

Key file SHA-256 values are:

```text
8e3eaf01b834dc23f30917614f04055fecf57ad9b691d9319f161ca49beed8f6  SqfliteSqlCipherPlugin.java
db801df08a6cf8132ce9fcaded4331c0266b86c79699dd0d6ffaaf5c44b3891f  Database.java (unchanged)
d60687a780f186320fb3030beb43e582087c3b4f9505da2c9e2159c2606c90ce  SqlCommand.java
1b9e446b53f51f51a0b265c72d684b11a8880c147e2e138de11b85cf9dbf158f  dev/Debug.java
7eb11ec5587e68f19b45331f17660a214bffc16e57f6d6905440aeb9342c6730  EngineWorker.java
463c05c88110a83436998058ce8f920f1397eb9687efc03b1cd51bf1d55f49d3  EngineDebugCensus.java
952a623012ff061f793dd95c98c36a3e725e83be4396a56b118d5366dae49c4c  EngineState.java
1a0f20ad67ebf7f4b4418445ff1aa115b75ece861a60055f39a79120d8e56a07  HandlerThreadEngineWorker.java
7ac85f2b2437e9b165bc5971c41af4eafb53c8f7d2d9bfa9e44479af749e315e  EngineWorkerIsolationTest.java
c5538ba79ab511c68dd8189dd14ad15f102fb81e31b0b8a82eaaa29455db12a6  android/build.gradle
```

All 148 non-Android files — Dart package sources, iOS/macOS implementations,
examples, tests, metadata, and assets — remain byte-identical to hosted 3.4.0.
Their deterministic subtree SHA-256 is:

```text
9d99b174eae31ee0d391872f3a959f313cc465b12f7fed3acc71a2c99cd99ac4
```

The root `pubspec.yaml` and generated `pubspec.lock` select this directory.
Those resolution files are outside the vendored-package digest.

## Verification and rollback

```bash
flutter pub get
flutter test test/core/database/sqflite_sqlcipher_fork_contract_test.dart
./android/gradlew -p android :sqflite_sqlcipher:testDebugUnitTest \
  --tests '*EngineWorkerIsolationTest'
./android/gradlew -p android :sqflite_sqlcipher:compileDebugJavaWithJavac
```

The override and complete vendored tree must be committed and rolled back as a
unit. Hosted rollback removes only the root path override, regenerates the
lockfile to the pinned hosted 3.4.0 artifact above, proves package resolution,
then restores the fork. Never bless unrelated Dart, iOS, macOS, example,
package-source, or Android drift by updating these hashes without review.
