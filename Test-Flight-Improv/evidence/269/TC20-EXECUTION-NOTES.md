# TC-269-20 Execution Notes

Date: 2026-07-23
Final status: **FAIL — bypassed by explicit user instruction after the single
allowed final run**

TC-269-20 is the physical-iOS boundary proof for group-media receive
reliability. It is intentionally separate from the default two-Android proof
because it exercises iOS application suspension, native critical-task
ownership, process termination, and cold-relaunch recovery.

## What TC20 does

The proof uses a prepared Android sender, a prepared physical-iOS receiver, a
real relay, disposable identities, and the production SQLCipher role
databases. It performs two phases without building child applications during
the proof:

1. **Phase A — fast background completion**
   - Arm the iOS receiver and establish live transport identity.
   - Put the receiver in the background.
   - Deliver group media from the Android sender.
   - Require a durable receipt/database observation and one native
     critical-task terminal result for normal completion.

2. **Phase B — forced interruption and cold recovery**
   - Arm a named post-claim/pre-commit barrier.
   - Press Home and deliver another group-media item.
   - Require the receiver to durably claim the item.
   - Terminate the owning application process and prove that ownership ended.
   - Relaunch a fresh process without navigating into the group.
   - Require resume-after-drain recovery to settle the same durable item once
     and publish exactly one final group-media UI effect.

The native simulator suite separately proves deterministic expiry and
late-end idempotence. TC20's physical-device purpose is the real Home,
termination, relaunch, and recovery boundary.

## What was investigated and changed

The TC20 work took substantially longer than the final test duration because
several independent build, device-control, fixture, and readiness problems had
to be isolated before the scenario could reach its intended assertion:

- A physical-iOS build initially exhausted local disk space. Only obsolete,
  plan-owned DerivedData, caches, and prepared bundles were removed; unrelated
  workspace files were preserved.
- CoreDevice occasionally timed out during idempotent device information and
  copy operations. A bounded recovery runner was added for those specific
  operations.
- Native Runner events were not reliably observable after suspension, so the
  existing proof channel was supplemented with persistent public native
  logging that contains no secret payloads.
- Standalone fixture copying was made recoverable, with an explicit distinction
  between an absent device file and a failed read/copy.
- Cold-relaunch identity validation originally compared an entire newly signed
  QR payload. That incorrectly treated expected timestamp/signature rotation as
  identity loss. The comparison now binds stable account, transport, public,
  and ML-KEM identity keys.
- A universal “full relay custody” readiness predicate blocked cold relaunch
  for up to 120 seconds even when the current phase required only identity or
  receive-recovery readiness. Phase-specific readiness now keeps full custody
  for phases that need it, live transport identity for the identity phase, and
  inbox/recovery capability for the receive-recovery phase.
- The updated causal host suite passed all 23 TC20-oriented tests before
  closure.

Before the user's one-run cap, a diagnostic install timed out before TC20
started. It is not counted as a post-cap TC20 run. After the cap was stated,
exactly one final TC20 attempt was made. No further TC20 attempt is permitted.

## Single allowed final run

Run label: `p269-tc20-final-single-v15`

The prepared iOS bundle and Android APK both passed custody validation, and
their build guards remained empty, proving that the scenario did not perform a
child build.

The run successfully produced:

- Phase A receipt, production-database, and native-task evidence.
- Phase B claim receipt, production-database, and native-task evidence.
- A host-owned Phase B termination record.
- A started cold-relaunch recovery phase.
- Final allowlisted device cleanup.

The run failed at the last required outcome:

- The fresh receiver process did not publish the expected final group-media UI
  effect.
- XCUITest `testReceiverBackgroundRecovery()` therefore failed after 4 minutes
  21 seconds at the final UI-effect assertion.
- No validated TC20 result artifact was emitted.

After the assertion had already failed, Xcode automatically launched an
optional `devicectl diagnose` collection. That collector requested an
administrator password and prolonged command completion; it was not causal to
the test failure. No credential was supplied. Only that post-failure diagnostic
collector was stopped so the harness could finish its own cleanup.

The iPhone remaining on the Home Screen is expected: Phase B explicitly presses
Home, and the final cleanup does not leave the proof application in the
foreground. The Home Screen is not evidence of a still-running test.

## Closure interpretation

TC20 is neither PASS nor N/A. A supported physical iPhone was available and the
proof ran, but its final cold-relaunch UI-effect condition failed. Per the
user's explicit instruction, execution bypasses TC20 after this one final
attempt and continues with the remaining Plan 269 verification.

The implementation and host/native causal tests for this path remain in place,
but the physical-device claim “forced interruption plus cold relaunch converges
to exactly one visible group-media effect” remains unproven.
