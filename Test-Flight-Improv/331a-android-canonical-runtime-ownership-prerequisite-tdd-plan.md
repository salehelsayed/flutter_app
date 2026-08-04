# 331A - Android Canonical Runtime Ownership Prerequisite

Status: **H0 complete / device-verified (2026-08-03)** — the canonical runtime
ownership prerequisite passed on both currently available Android targets, so
Plan 331 may reuse the ownership foundation. This prerequisite does not prove
or supply the production direct/group recovery dependency graph; a subsequent
source audit found that graph still safety-gated. Inbox draining and recovery
generation acknowledgement remain disabled until Plan 331's own composition
and device gates pass.
Type: Bug
Parent: [331-android-notification-recovery-completion-tdd-plan.md](331-android-notification-recovery-completion-tdd-plan.md)
Classification: completed prerequisite; stop-and-replan on any future failed
real-boundary regression
Closure tier: Kotlin/Go host + real two-engine Android + real SQLCipher, no UI
root and no relay credential required
Baseline: `1c7540b17954a423264e23ecf3528d3c01beeb0a`

## Outcome

Prove one process-wide broker can safely serialize the foreground engine and a
minimal recovery engine across the process-global Go singleton and writable
SQLCipher database. Ownership is a state machine, not an admission flag:
`ACTIVE -> DRAINING -> RELEASED`. A transfer rejects new calls, waits for every
admitted JNI call and queued callback/result to settle, stops the node only
after an in-progress start settles, closes the Dart database explicitly, then
destroys the old engine on the Android main looper. A timeout or close failure
retains the old owner and never opens a second writer.

FlutterFire's background engine is the third member of the matrix. It owns no
Go runtime and may use only the existing read-only, non-singleton SQLCipher
path; it must not acquire or transfer the canonical writable lease.

## Scope Contract

In scope:

- A process-global native `GoRuntimeHost` with generation-fenced engine
  registration, in-flight JNI accounting, callback/result delivery fencing,
  deterministic unregister, and one Go `Initialize` call per process.
- A process-global `CanonicalRuntimeLease` used before **both** foreground and
  recovery Dart code opens the writable production database.
- Explicit Dart database-close acknowledgement before transfer or engine
  destruction; non-singleton writable connections only behind the lease.
- A minimal recovery-engine plugin registry. Automatic generated registration
  stays disabled for this engine; register only the binding, secure storage,
  SQLCipher, local notifications, Firebase prerequisites actually proven by the
  probe, the app Go bridge, and the recovery-result channel.
- A debug-only ADB/instrumentation probe that starts the process without
  `MainActivity`/`ApplicationRoot`, uses the real Go AAR and real SQLCipher,
  then drives recovery -> foreground transfer and records machine-readable
  state.
- Account/install binding contract: native stores an opaque current-account
  binding with each generation; acquisition and CAS acknowledgement recheck it.
  Logout/migration rotates the binding, cancels stale immediate work, and
  retires rather than runs an old-account marker.

Out of scope:

- Inbox draining, notification projection, WorkManager success semantics, and
  the paired relay campaign; those remain in Plan 331 after this gate passes.
- A prompt forced handoff. Foreground priority is cooperative and bounded; if
  Go cannot quiesce safely, foreground waits or the design returns to review.
- Any Swift/iOS edit, UI root construction, user force-stop promise, or second
  writable database owner.

## Grounding

- `GoBridge.kt` currently launches calls on an untracked cached executor and
  calls `GoMknoon.initialize(this)` per bridge.
- `go-mknoon/bridge/bridge.go` stores one callback and replaces it on repeat
  initialization; existing callback-swap tests prove the latest initializer
  steals future events.
- `ProductionApplicationBootstrap` opens `identity.db` writable before any
  proposed lease. The SQLCipher plugin keeps process-static handles and plugin
  detach does not imply database close.
- FlutterFire's Android background handler runs in another Flutter isolate/
  engine in the same app process; the existing source comment claiming a
  separate Android process is incorrect.
- The available proof pair on 2026-08-03 is USB Pixel
  `21071FDF600CSC` API36 and emulator `emulator-5554` API37.

## Test Contract

| Case | Behavior | Exact proof | HEAD -> GREEN | Mutation / stop rule |
|---|---|---|---|---|
| H0-01 | Go initializes once; only ACTIVE owner admits calls | `GoRuntimeHostTest::one initialization and active owner admission` and existing Go callback-swap tests | per-engine initialize -> broker callback | restore per-engine initialize or accept stale token -> red |
| H0-02 | Transfer drains long `StartNode`, ordinary JNI calls, queued results, and callbacks before release | `GoRuntimeHostTest::draining fences late call result and callback` plus `::stop waits for start` | cached work crosses handoff -> exact ACTIVE/DRAINING/RELEASED trace | deliver after token change, call Stop during Start, or force release on timeout -> red/stop |
| H0-03 | bridge detach clears channels/sink, drains executor, unregisters token | `GoRuntimeHostTest::dispose cannot leak engine callback or result` | no `GoBridge.dispose` -> deterministic teardown | leave handler/executor/callback registered -> red |
| H0-04 | foreground and recovery writable opens share one lease; read-only FCM engine never owns it | `canonical_runtime_lease_test.dart::foreground worker and fcm ownership matrix` | foreground bypasses lease -> one writer and read-only third engine | bypass foreground gate or let FCM acquire -> red |
| H0-05 | DB close acknowledgement precedes engine destroy/transfer; close failure retains owner | `canonical_runtime_lease_test.dart::database close fences transfer` | plugin detach can leave static handle -> explicit close trace | destroy first or transfer on close failure -> red/stop |
| H0-06 | account A marker cannot run or acknowledge under account B | `DroppedPushRecoveryStoreTest::binding rotation retires stale generation` | marker has generation only -> bound CAS | omit either pre-acquire or pre-ack binding check -> red |
| H0-07 | real non-UI recovery engine registers the minimal plugin set and opens real SQLCipher; MainActivity/ApplicationRoot remain absent | debug-only `scripts/run_android_canonical_runtime_h0_probe.sh <device-id>` | no secondary-engine host -> machine-readable pass artifact | Activity launch, generated broad registry, fake/plain DB, or missing plugin -> red/stop |
| H0-08 | real recovery -> foreground handoff keeps one Go callback/writer through long-call, process-kill, reopen, and close-one-owner cases | same probe with `--handoff` and `--process-death` on each device | no real boundary proof -> exact generation/handle trace | callback/result crosses owner, two writers, lost close, or forced transfer -> red/stop |

## Implementation Order

1. Add H0-01..06 causal tests and capture their missing-seam REDs.
2. Introduce the broker behind fake Go/DB facades; keep the existing Go
   callback-swap characterization unconditional.
3. Gate foreground bootstrap before its current writable DB open. Add explicit
   close acknowledgement and bridge disposal.
4. Add the minimal recovery-engine host and debug-only no-Activity probe. All
   FlutterEngine create/execute/destroy operations run on the Android main
   looper.
5. Run H0-07/08 on each explicit Android ID. A failed invariant ends this plan
   `not-ready`; do not implement Plan 331's recovery worker around it.

## Acceptance Gates

```bash
./android/gradlew -p android :app:testDebugUnitTest --tests 'com.mknoon.app.GoRuntimeHostTest' --tests 'com.mknoon.app.DroppedPushRecoveryStoreTest'
flutter test test/core/notifications/canonical_runtime_lease_test.dart
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./bridge -run 'TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents|Test.*CallbackAdapter' -count=1
flutter devices --machine
adb devices -l
./scripts/run_android_canonical_runtime_h0_probe.sh 21071FDF600CSC
./scripts/run_android_canonical_runtime_h0_probe.sh emulator-5554
./scripts/run_android_canonical_runtime_h0_probe.sh 21071FDF600CSC --handoff --process-death
./scripts/run_android_canonical_runtime_h0_probe.sh emulator-5554 --handoff --process-death
./scripts/run_test_gates.sh runtime-roots
flutter analyze
git diff --check
```

Each probe must emit one content-addressed artifact containing source/APK/device
digests, `mainActivityLaunchCount=0` for the recovery-only leg,
`applicationRootConstructed=false`, `goInitializeCount=1`,
`maxWritableDatabaseOwners=1`, zero stale callbacks/results, explicit close
before destroy, and a final released lease. No relay/FCM credential is needed.

## Done / Handoff

- [x] All host tests have causal RED, GREEN, and one representative mutation
      re-red recorded.
- [x] Both Android targets pass the non-UI and handoff/process-death probes.
- [x] Foreground bootstrap cannot open writable SQLCipher without the broker.
- [x] FlutterFire remains read-only/no-Go and is covered concurrently.
- [x] Any timeout/close failure retains ownership rather than forcing transfer.
- [x] Every H0 box is checked, so Plan 331 may use this ownership foundation;
      production activation still requires Plan 331's separate recovery graph.

## Execution Progress

| Time | Phase | Last command/result | Decision / next |
|---|---|---|---|
| 2026-08-03 review | plan split | `$tdd-review` falsified admission-only ownership and fake-only H0 proof | add causal tests, then implement the broker/probe |
| 2026-08-03 RED | missing seams | Dart lacked `canonical_runtime_lease.dart`; Kotlin lacked broker rebind/work-state seams; debug source checks lacked the receiver, entrypoint, and probe script | implement only the prerequisite broker and no-UI proof surface |
| 2026-08-03 GREEN | host contracts | exact Dart ownership/migration/identity/background slice: 96 tests passed; exact Kotlin broker/lease/probe/shutdown source slice and Go callback/`StopNode_NotStarted` tests passed | proceed to real-boundary H0 |
| 2026-08-03 GREEN | build boundary | disposable `com.mknoon.app.h0probe` APK assembled with the full Flutter build and Google services disabled; targeted Dart analyze, probe script syntax, and `git diff --check` passed | run against each explicit live Android ID |
| 2026-08-03 final GREEN | Pixel 6 API36 | recovery-only artifact [`b392c0d8...217ef`](../build/h0-probe/21071FDF600CSC/b392c0d846a65cdc3ae8716e5ead6db8f5ff66efb3c82dab9c3cdf46998217ef.json); handoff/process-death artifact [`98582c60...bbff5`](../build/h0-probe/21071FDF600CSC/98582c602c0da09fecfd0c9ce5603e8f29ed9b87cd09ef0c128befe5ab9bbff5.json), PIDs `23594 -> 23734` | PASS with zero Activity records, generations `[1,2]`, one writer, one read-only peer, final `RELEASED` |
| 2026-08-03 final GREEN | emulator API37 | recovery-only artifact [`35b2dd0f...357a3`](../build/h0-probe/emulator-5554/35b2dd0fdb024a606b510369f3374f64e0c589163fb8cf9553006dc0e34357a3.json); handoff/process-death artifact [`42a2bb94...61c7`](../build/h0-probe/emulator-5554/42a2bb9452295a32aa63defdc0f8875508db32e3c4685b79087980e5439661c7.json), PIDs `28860 -> 28967` | same exact invariants PASS |
| 2026-08-03 mutation re-red | visible stale-card ownership sentinel | removing the committed-rotation `retiredRecovery` cancellation made `DroppedPushRecoveryBridgeTest.binding rotation retires marker and cancels its visible card exactly once` fail at its cancellation assertion; restoring it returned GREEN | representative mutation detected; unchanged binding remains a zero-cancel sentinel |
| 2026-08-03 closure | cleanup | final source digest `9c956aa48a8e6af6d21bbec65dc5ad5458426d1d0c9dcea9bd7c52e99ded8a7d`; APK digest `26323df552b696de1492818c8e75b6cffe02902676880679d8761aa292ef4d36`; disposable package absent on both targets; recovery work remained unactivated in every artifact | H0 passed; unblock only Plan 331's ownership foundation, not production draining/acknowledgement |

The handoff artifacts record `goInitializeCount=1`, observed writable
generations `[1,2]`, `maxWritableDatabaseOwners=1`, maximum observed writable
and read-only handles of one each, three-engine concurrency, active-owner and
close-failure contention rejection, zero stale callback/result deliveries,
zero `ActivityRecord`s, no application-root construction, and final broker/Go
state `RELEASED`. The close-failure leg leaves the owner `DRAINING`, rejects a
second writer, and succeeds only after the same owner performs a real close and
release retry.
