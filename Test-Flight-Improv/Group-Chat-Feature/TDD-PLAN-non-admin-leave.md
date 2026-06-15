# TDD Fix Plan — Non-admin member cannot voluntarily leave a group

**Status:** IMPLEMENTED (production + host tests) on `121-improvements` (uncommitted) — 2026-06-15. Sender best-effort rotation, wired teardown, and **creator-only** receiver re-key all landed; **7 host test cases across 3 files** (Step 4 is a group of 4 — see §4). Cleanup of `voluntaryLeaveRotationFailedMessage` done (0 refs in `lib/` or `test/`). **HOST VERIFICATION GREEN (2026-06-15, `-j 1`):** the 3 changed files pass **255/255** (all 7 new cases ran) and the §5 blast-radius locks (GKR-001 / ML-013 / sole+last-admin leave) pass **47/47** — no regressions. The full ~2000-test groups suite was NOT run (carries known pre-existing reds — 114/115/116 `'inboxed'`, device-criteria proofs — unrelated to this change). **H-01 DEVICE-GREEN (2026-06-15, 3 iOS sims):** the device run surfaced a real, pre-existing receiver bug (a relay-delivered self-authored `member_removed` was rejected with `transport_mismatch`, blocking convergence + the creator re-key) — fixed with a narrow self-leave binding relaxation + a leave-aware verdict validator; the proof then PASSED (orchestrator: "verdicts valid for alice, bob, charlie"). See §6.2. Derived from verified multi-agent recon + direct source read; reconciled to the as-built tests + device proof on 2026-06-15.
**Branch target:** `121-improvements`
**Bug doc:** `Test-Flight-Improv/Group-Chat-Feature/BUG-writer-cannot-voluntarily-leave.md`
**Implemented in:** `broadcast_voluntary_leave_use_case.dart` (`VoluntaryLeaveBroadcastResult.rotationDeferred`, set at `:211`); `group_message_listener.dart` `_maybeRotateGroupKeyAfterRemoteRemoval` (`:3320+`, callback field `:128`, creator-only gate); wired at `group_info_wired.dart` + `main.dart:1993`.

---

## 1. Problem recap + confirmed root cause

When a non-admin **writer** (or even a non-creator admin) taps **Leave Group**, the leave dead-ends and they stay in the group. The voluntary-leave path forces the *departing* member to perform the forward-secrecy key rotation, but rotation is permission- and creator-gated, so a normal member is denied and the error aborts the leave before local teardown runs. Concretely: the UI renders Leave for every non-dissolved group with no role gate (`group_info_screen.dart:115-118`, `:586-595`); `_onLeave` awaits `_broadcastSelfRemovalIfNeeded()` (`group_info_wired.dart:361`) **before** `leaveGroup()` (`group_info_wired.dart:363`); `_broadcastSelfRemovalIfNeeded` delegates to `broadcastVoluntaryLeaveAndRotateKey` (`group_info_wired.dart:680-694`); that use case rotates whenever members remain and hard-throws on a null result — `if (remainingMembers.isNotEmpty) { rotatedKey = await rotateAndDistributeGroupKey(...); if (rotatedKey == null) throw StateError(voluntaryLeaveRotationFailedMessage); }` (`broadcast_voluntary_leave_use_case.dart:185-200`, message constant `:51-52`).

**Confirmed root cause (two independent gates inside the rotation, BOTH block a normal leaver):**
- **Gate A — permission:** `canRotate = selfMember.permissions.allows(GroupMemberPermission.rotateKeys, selfMember.role)`; false → emit `GROUP_ROTATE_KEY_PERMISSION_DENIED`, return null (`rotate_and_distribute_group_key_use_case.dart:67-82`). Default permission is admin-only for every permission including `rotateKeys` (`group_member.dart:325-339 _defaultForRole` returns `role == MemberRole.admin`; members default to `GroupMemberPermissions.empty`, `group_member.dart:378`, so a writer's `allows(rotateKeys, writer) == false`).
- **Gate B — creator-only:** `if (group.createdBy != selfPeerId) { emit GROUP_ROTATE_KEY_PERMISSION_DENIED; return null; }` (`rotate_and_distribute_group_key_use_case.dart:84-93`). Even a non-creator admin (or a writer with a `rotateKeys` override) fails this.

The throw at `broadcast_voluntary_leave_use_case.dart:198-200` is caught in `_onLeave` (`group_info_wired.dart:375-394`). The catch only rolls back when `_isNativeLeaveFailure(e)` is true, and that matches **only** `BridgeCommandException` with `command == 'group:leave'` (`group_info_wired.dart:728-729`). A rotation `StateError` is neither, so the catch just SnackBars the message and `leaveGroup()` (`leave_group_use_case.dart:12-64`, which itself does **no** rotation) never runs — membership stays intact. The device log chain `GROUP_ROTATE_KEY_PERMISSION_DENIED → Bad state: Failed to rotate group key before leaving` matches exactly.

---

## 2. Intended-behavior decision (explicit)

The product intent is **"any member can leave."** The fix adopts these rules:

1. **Any member can leave** regardless of role/permission/creator status. Leave is offered to all non-dissolved members by design — the Dissolve button right above it *is* admin-gated, proving the asymmetry is deliberate (`group_info_screen.dart:105-110` vs `:115-118`). L10n is role-neutral (`group_leave = 'Leave Group'`, no "only admins can leave" string).
2. **The last/sole admin is still blocked** from leaving (they must Dissolve). Preserve the existing guard `if (group.myRole == GroupRole.admin && adminCount <= 1) return VoluntaryLeaveBroadcastResult.skippedLastAdmin;` (`broadcast_voluntary_leave_use_case.dart:74-76`) and the parallel `leaveGroup` last-admin throw (`leave_group_use_case.dart:26-43`).
3. **Forward-secrecy invariant preserved:** after a member leaves with members remaining, the group must converge to a **new key epoch the leaver does NOT possess**. The re-key is the **group's / a remaining admin's** responsibility, NOT the departing member's — exactly mirroring admin-removal, where the remover (a creator-admin) drives rotation at `group_info_wired.dart:1050-1069` and `removeGroupMember` itself intentionally does NOT rotate (`remove_group_member_use_case.dart:39-41`). The leaver must NOT be required to hold `rotateKeys` nor be the creator.

---

## 3. Chosen fix approach + rejected alternatives

### Chosen: Option C + Option B combined — "decouple leave from rotate; remaining admin re-keys on receipt"

**Part 1 (C — sender side, unblock the leave).** In `broadcastVoluntaryLeaveAndRotateKey`, make the departure rotation **best-effort** instead of fatal: still attempt `rotateAndDistributeGroupKey` (so a privileged leaver — e.g. the creator-admin — keeps rotating exactly as today), but when it returns null because the leaver lacks permission/creator status, **do NOT throw** — record the un-rotated outcome and let the caller proceed to `leaveGroup()`. The signed `member_removed` system message + offline-replay envelope to remaining peers are already published *before* the rotation attempt (`broadcast_voluntary_leave_use_case.dart:139-182`), so the departure signal still reaches the group. Distinguish "skipped because last-admin" (existing) from "rotation-not-permitted-for-this-leaver" so the caller never surfaces the old error.

**Part 2 (B — receiver side, restore forward secrecy).** A **remaining admin** that receives the `member_removed` for a member it did not itself remove, and where no `key_rotated` for the post-departure epoch has arrived, performs the rotation itself via `rotateAndDistributeGroupKey` (it passes both gates: it has `rotateKeys` by default and, for the creator, Gate B). Wire this into `_handleMemberRemoved` (`group_message_listener.dart:3108`, the non-self branch ~`:3242`/`:3318`). This closes the forward-secrecy gap that Part 1 alone would leave open (the departed member would otherwise retain the current epoch key until some unrelated rotation).

**Rationale.** This is the smallest sender-side change that unblocks the universal action, and it mirrors the *already-proven* admin-removal re-key model (remover/remaining-admin owns rotation) rather than inventing a new crypto bypass. Part 2 keeps the forward-secrecy invariant a hard guarantee, driven by the same actor and gates that already work for admin removal — no relaxation of Gate A or Gate B, so the security-locked tests GKR-001 / ML-013 stay green untouched.

### Rejected alternatives
- **Option A — scoped self-removal rekey (let the leaver rotate without `rotateKeys`).** Rejected: must defeat **both** Gate A *and* Gate B (a non-creator writer fails B even with a `rotateKeys` override). It would require a `selfRemovalRotation` bypass inside the most security-sensitive use case, directly colliding with GKR-001 (`rotate_and_distribute_group_key_use_case_test.dart:235-279`) and ML-013 (`:281-332`) and forcing an audit of ~38 other rotation call sites. Highest blast radius and crypto risk for no extra correctness over B.
- **Option D — role-gate the Leave button (hide it from non-admins).** Rejected outright: it would hide leave from exactly the writers who need it and contradicts product intent (Leave is deliberately shown to all). Listed only to reject.

---

## 4. TDD step sequence — AS IMPLEMENTED (reconciled 2026-06-15)

Dependency order: sender best-effort → privileged regression lock → wired teardown → receiver creator re-key → device proof. **7 host test cases across 3 files** (Steps 1–3 one each, Step 4 a group of 4), then the device-real **H-01** (Step 5). Run host tests with `flutter test <file>` (`-j 1` for the groups suite per project convention if parallel flakes) — NOT executed in this doc-update session per the no-tests instruction; the tests below are present in the tree but unverified here.

> **Step 0 (characterization) — FOLDED INTO STEP 1, not kept standalone.** The plan's "currently throws"
> RED test was not retained as its own case: its fixture became Step 1's and the assertion flipped
> directly to "broadcasts and does NOT throw." Because `voluntaryLeaveRotationFailedMessage` is now
> removed (0 refs in `lib/` or `test/`), a throws-characterization test would no longer compile against
> the new vocabulary anyway.

### Step 1 — Sender: best-effort rotation, no throw for a non-permitted leaver  ✅ IMPLEMENTED
- **Test (as built):** `test/features/groups/application/member_removal_integration_test.dart:949`
  **`'non-creator writer voluntary leave broadcasts member_removed and does NOT throw'`** (NOT the
  originally-planned `broadcast_voluntary_leave_use_case_test.dart`). Fixture: local `myRole =
  GroupRole.member`; `peer-alice` is a writer with empty permissions (no `rotateKeys`); `createdBy =
  adminPeerId` (≠ leaver); `peer-bob` + admin remain. Asserts:
  - completes **without throwing**; `result.didBroadcast == true`;
  - `result.rotatedKey == null` AND **`result.rotationDeferred == true`**;
  - `result.skipReason == null` (a real leave — distinct from last-admin / not-found);
  - `bridge.commandLog` contains `group:publish` (the signed `member_removed`);
  - the offline-replay inbox payload's `recipientPeerIds` is `unorderedEquals([adminPeerId, 'peer-bob'])`
    (read via `_lastGroupInboxStorePayload(bridge)`);
  - `getLatestKey(groupId).keyGeneration == 1` (no epoch generated by the departing writer).
- **GREEN (landed):** `broadcastVoluntaryLeaveAndRotateKey` records `rotationDeferred = (rotatedKey ==
  null)` and continues instead of throwing (`broadcast_voluntary_leave_use_case.dart:211`); the
  `rotationDeferred` field was added to `VoluntaryLeaveBroadcastResult` (`:32,:39`). The old
  `throw StateError(voluntaryLeaveRotationFailedMessage)` is gone.

### Step 2 — Sender: privileged leaver (creator-admin) STILL rotates (regression lock)  ✅ IMPLEMENTED
- **Test (as built):** same file, `member_removal_integration_test.dart:1011`
  **`'creator-admin voluntary leave still rotates to a new epoch'`**. Fixture: `createdBy = 'peer-alice'`
  (Gate B passes for self); leaver promoted to `MemberRole.admin` (Gate A); `peer-admin` stays admin so
  the leaver is not the last admin. Asserts `result.didBroadcast == true`, `result.rotatedKey != null`,
  **`result.rotationDeferred == false`**, and `getLatestKey(groupId).keyGeneration == 2`.
- **GREEN:** No new production change — the Step 1 edit preserves the rotate-on-success path. This locks
  that the best-effort change did not disable rotate-on-leave for those who CAN rotate.

### Step 3 — Wired: leave reaches `leaveGroup()` and tears down membership when rotation is deferred  ✅ IMPLEMENTED
- **Test (as built):** `test/features/groups/presentation/group_info_wired_test.dart:4195`
  **`'writer Leave tears down local membership even when rotation is deferred'`** (NOT the
  originally-planned `group_info_wired_leave_test.dart`). Drives a non-creator writer through
  `GroupInfoWired` (`makeMemberGroup()` with `myRole == member`, `createdBy == peer-admin`; admin +
  `peer-bob` + the writer saved via `makeMember`; `_saveGroupReplayKey`; `PassthroughCryptoBridge`
  stubbing `group:leave`/`group:publish`/`group:inboxStore`), opens Info, taps Leave
  (`tapLeaveGroupButton`). Asserts:
  - `bridge.commandLog` contains `group:publish`, and **exactly one** `group:leave`;
  - `bridge.commandLog` does NOT contain `group:generateNextKey` (rotation deferred, not performed);
  - `groupRepo.getGroup('group-1') == null` (local membership torn down);
  - NO `'Failed to rotate group key before leaving'` SnackBar and NO `'Failed to leave group'` SnackBar;
  - pops back to the first route (`GroupInfoScreen` gone, `Open Info` shown).
- **GREEN:** No `_onLeave` ordering change needed once Step 1 stops the throw — `leaveGroup()`
  (`group_info_wired.dart:363`) is reached normally. `_isNativeLeaveFailure` (`:728-729`) + the rollback
  branch stay untouched (still guard the genuine `group:leave` native failure).

### Step 4 — Receiver: remaining CREATOR re-keys on `member_removed` (forward-secrecy invariant)  ✅ IMPLEMENTED
- **Tests (as built):** `test/features/groups/application/group_message_listener_test.dart:3060`
  `group('creator re-key on remote member departure (forward secrecy)')` — **4 cases**, each injecting a
  `rotateGroupKeyAfterRemoteRemoval` spy into `GroupMessageListener` and feeding a `member_removed`
  (helpers `saveBobWriter`, `memberRemovedEvent`):
  1. `:3120` **`'remaining creator rotates group key on member_removed it did not author'`** — self =
     `peer-admin` (creator), peer-sender voluntarily leaves ⇒ member removed AND `rotateCalls == ['group-1']`.
  2. `:3153` **`'creator does not double-rotate on a duplicate member_removed'`** — a redelivery (new
     envelope id, peer already gone) ⇒ still `rotateCalls == ['group-1']` (idempotent, single epoch bump).
  3. `:3192` **`'a non-creator member does not auto-rotate on member_removed'`** — self = `peer-bob`
     (remaining writer, not creator) ⇒ member removed but `rotateCalls` empty.
  4. `:3222` **`'creator does not rotate on a removal it authored itself'`** — sender = `peer-admin`
     (self-authored; admin-removal already rotated locally) ⇒ `rotateCalls` empty.
- **GREEN (landed):** `_maybeRotateGroupKeyAfterRemoteRemoval`
  (`group_message_listener.dart:3320+`; callback field `_rotateGroupKeyAfterRemoteRemoval` `:128`; wired
  at `main.dart:1993`). Guard order: skip if the group emptied → **idempotency** (only the delivery that
  removed an *active* member rotates; duplicates no-op) → skip if `removalAuthorPeerId == selfPeerId`
  (self-authored) → **`group.createdBy != selfPeerId` ⇒ return (CREATOR-ONLY)** → invoke the rotate
  callback, emitting flow event `group_creator_rekey_on_remote_removal`. Other remaining members converge
  via the creator's `key_rotated` (existing handler `:2125`) — no new wire type.
- **Decision — resolves §7 OQ/Risk #1 (rotation race).** The **creator** is the single deterministic
  auto-rotator (the unique Gate-B holder), so multiple remaining admins never race. The creator-less-group
  case (creator already departed ⇒ no auto-rotator) stays an open follow-up — see §7 #3.

### Cleanup (folded into the above) — Dead vocabulary removed  ✅ DONE
- `voluntaryLeaveRotationFailedMessage` removed from `broadcast_voluntary_leave_use_case.dart` — grep
  confirms **0 references** in `lib/` or `test/`. **No role gate added to the Leave button** (intended
  behavior keeps it visible to all). UI string `group_info_leave_failed` stays (genuine native-leave
  failures only).

### Step 5 — End-to-end proof (device-real H-01)  ✅ GREEN (2026-06-15, 3 iOS sims)
- Ran `run_group_multi_party_device_real.dart --scenario private_voluntary_leave_convergence` on the
  `UP004 Alice/Bob/Charlie` sims against the `mknoun.xyz` relay. **The run surfaced a real pre-existing bug
  (see §6.2), which was fixed; the re-run then PASSED:** orchestrator reported *"private_voluntary_leave_convergence
  proof passed: verdicts valid for alice, bob, charlie"*, `transport_mismatch` count 0, all three role test
  bodies `All tests passed!`. Verdicts: alice keyEpoch **1→2** (`keyEpochAdvanced`, `rotationDeferred:false`),
  bob converged to **2**, charlie `rotationDeferred:true` + epoch 0 + `groupHardDeletedLocally`, charlie
  excluded from alice & bob rosters. GREEN bar fully met (charlie can't decrypt epoch 2). Evidence:
  `Test-Flight-Improv/124-h01-evidence/group-h01-2026-06-15-{alice,bob,charlie}.log` + `*_verdict.json`.
- The harness/verifier source was already de-masked (test-only co-admin/`rotateKeys` promotion removed,
  `group_multi_party_device_real_harness.dart:16656`/`:16801`); feature is **Dart-only — no gomobile rebuild**.
- PENDING (optional): a real Pixel→iPhone pair re-run for field confirmation.

---

## 5. Blast radius — existing tests that lock current behavior and how they change

| Test (file:line) | Currently locks | Required change |
|---|---|---|
| EK004 `member_removal_integration_test.dart:848-945` (leaver = writer **with** `rotateKeys: true` override + `createdBy = leaver`, `:860,869-870`) | voluntary leave **with** rotation succeeds and stores replay envelope | KEEP green. It exercises the privileged path (rotates). Optionally assert the new `rotationDeferred == false`. Do NOT delete — it locks Step 2 success path. |
| Epoch test `member_removal_integration_test.dart:1155-1302` (writer + `rotateKeys: true` + `createdBy = leaver`, `:1180,1200-1201,1227,1237`) | rotation excludes leaver; remaining members send on rotated epoch | KEEP green (privileged leaver). Forward-secrecy assertion still holds via the privileged rotate path. |
| GM-015 `member_removal_integration_test.dart:948-1079` | last-admin leave returns `skipReason == lastAdmin`, `leaveGroup` throws | KEEP unchanged — last-admin guard is **preserved** (§2 rule 2). |
| `leave_group_use_case_test.dart:179-216` ('blocks sole admin') and `:218-311` ('GM-015 blocks creator/admin') | sole/last admin cannot leave | KEEP unchanged. |
| `leave_group_use_case_test.dart:55-177` (plain `leaveGroup` cleanup) | `leaveGroup` teardown, no rotation | KEEP unchanged — `leaveGroup` never rotated. |
| GKR-001 `rotate_and_distribute_group_key_use_case_test.dart:235-279` (non-owner admin → null) | Gate B (creator-only) returns null | KEEP unchanged — fix does NOT relax Gate B. Critical security lock. |
| ML-013 `rotate_and_distribute_group_key_use_case_test.dart:281-332` (bare writer + removed peer → null) | Gate A + member gate return null | KEEP unchanged — fix does NOT relax Gate A. Critical security lock. |
| **NEW gap (recon "test blind spot"):** no test drives a plain non-creator writer through the voluntary-leave path | — | ADD the Step 1 / Step 3 tests; this is the regression that was uncaught. |

The ~38 other `rotateAndDistributeGroupKey` call sites in the rotation test (creator-self / admin-self) are unaffected — the fix changes only the *caller's* reaction to a null, not the gates.

---

## 6. End-to-end proof — H01 `private_voluntary_leave_convergence` becomes device-real green  ⏳ PENDING (this is Step 5)

> **Harness edit ✅ DONE (source); only the RUN remains.** The test-only promotion described below was
> already removed (comments at `group_multi_party_device_real_harness.dart:16656` & `:16801`) and the
> harness emits the proof keys (`:16854`, `:37563-37585`). Dart-only — no gomobile rebuild. The numbered
> items below are now the **run recipe**, not pending code.

**Originally the harness masked the bug.** `_runVoluntaryLeaveConvergenceCharlie`
(`group_multi_party_device_real_harness.dart:16785-16807`) force-promoted charlie's self-member to
`MemberRole.admin` + `GroupMemberPermissions(rotateKeys: true)` AND sets local `myRole = admin` "to
guarantee charlie can rotate-on-leave"; the Alice side does the same (`:16650-16663`). But the fixture's
`createdBy` is alice (via `_createGroupFixture` → `createGroupWithMembers(identity: stack.identity)`,
`:16640-16648`), so charlie still fails **Gate B** — the workaround only addresses Gate A, which is why
the row could never truly pass for a real writer.

**After the fix:**
1. **Remove the test-only co-admin/`rotateKeys` promotion** at `:16785-16807` (charlie side) and
   `:16650-16663` (alice side). Let charlie leave as the **real writer** he is in the field repro
   (`group-h01-recheck*.log`).
2. Charlie's `_onLeave` now: publishes signed `member_removed` + offline-replay (already pre-rotation),
   gets `rotatedKey == null` / `rotationDeferred == true` (Step 1) WITHOUT throwing, then runs
   `leaveGroup()` (Step 3) → charlie is out locally.
3. Alice (creator-admin, remaining) receives `member_removed` and **auto-rotates** (Step 4) →
   broadcasts `key_rotated`; bob converges to the new epoch via the existing `key_rotated` handler
   (`group_message_listener.dart:2125`). Forward secrecy holds: charlie lacks the new epoch.
4. The H01 verifier sub-proof at `group_multi_party_device_criteria.dart:23297-23306` asserts the
   **alice last-admin-skip** sub-case and is a *different* scenario branch — confirm it still references
   the correct actor; it is not affected by the writer-leave change but re-verify the proof keys
   (`voluntaryLeaveBroadcastOutcome`, `voluntaryLeaveBroadcastSkipReason`) emitted at
   `harness:37563-37584` after the harness edit.
5. Run the reliability-sim row on iOS 26.1 sims (3 sims: alice creator, bob + charlie writers), then the
   real Pixel→iPhone device pair, capturing fresh `group-h01-*.log`. GREEN = charlie leaves, alice/bob
   converge to the rotated epoch, charlie cannot decrypt post-departure traffic.

This drops the test-only workaround entirely so H01 proves the real writer-leave behavior and stops
masking future regressions.

---

## 6.1 H-01 run recipe — exact commands  ⏳ TO EXECUTE ON HARDWARE

**Orchestrator interface (verified in `integration_test/scripts/run_group_multi_party_device_real.dart`):**
`main()` (`:2522`) reads the relay from the **`MKNOON_RELAY_ADDRESSES` env var** (`:2526`); `--scenario`
(`:267`) selects the scenario; `-d` / `--device` (`:284`) takes a **comma-separated device list mapped IN
ORDER to the scenario's roles**. For `private_voluntary_leave_convergence` the roles are
`[alice, bob, charlie]` (criteria `:252-255`) ⇒ device1 = **alice (creator)**, device2 = **bob (writer)**,
device3 = **charlie (writer — the leaver)**. `runId` + a `systemTemp` shared dir are auto-created; per-role
logs land at `<sharedDir>/<role>.log`, verdicts at `<sharedDir>/gmp_<runId>_<role>_verdict.json`. Identity
handshake budget 90 min, verdict budget 15 min.

**Prereqs**
- Build is **Dart-only** — NO `make all`/gomobile rebuild (zero Go refs in this feature); a normal fresh
  app build of `121-improvements` per target.
- A reachable relay: `export MKNOON_RELAY_ADDRESSES=<relay multiaddr(s), comma-separated>`.
- 3 run targets. List ids with `flutter devices` (Android/iOS) and `xcrun simctl list devices booted` (sims).

**Option A — 3 iOS simulators (run this first; sidesteps the iPhone13 blockers below)**

```bash
# Boot 3 sims and capture their UUIDs as ALICE_SIM / BOB_SIM / CHARLIE_SIM.
export MKNOON_RELAY_ADDRESSES=<relay-multiaddr>
dart run integration_test/scripts/run_group_multi_party_device_real.dart \
  --scenario private_voluntary_leave_convergence \
  -d $ALICE_SIM,$BOB_SIM,$CHARLIE_SIM
```

**Option B — real Pixel→iPhone (field proof)**
- Device blockers (project memory): iPhone13 has an iOS signing blocker AND an iOS 26.5 debug-JIT crash
  (EXC_BAD_ACCESS) — debug `flutter run` is unstable on it; use **`--profile`/AOT** for the iPhone role and
  prefer Pixel6 (`21071FDF600CSC`) for any debug role. With only two physical devices, run charlie on a sim.
- Same command, real ids: `-d <pixel-or-iphone>,<device2>,<device3>` (order = alice,bob,charlie).

**GREEN bar (proves the fix on real transport)**
1. **charlie (writer leaver):** harness emits `voluntaryLeaveBroadcastOutcome` = broadcast (not skipped),
   `rotationDeferred == true` (`harness:16854`, `:37563-37585`); leaves locally with NO
   "Failed to rotate group key before leaving".
2. **alice (creator):** auto-rotates on charlie's `member_removed` → new key epoch (final > initial).
3. **bob (writer, remaining):** converges to alice's new epoch via `key_rotated`; keeps sending/receiving.
4. **forward secrecy:** charlie CANNOT decrypt group traffic published after departure (post-rotation epoch).
5. Orchestrator writes `gmp_<runId>_<scenario>_orchestrator_verdict.json` = pass + per-role verdicts pass.

**Capture:** copy `<sharedDir>/{alice,bob,charlie}.log` to repo root as `group-h01-<date>.log`, then record
the result in §6 + the status banner. On failure, the per-role `<role>.log` + verdict JSON pinpoint the
broken invariant.

---

## 6.2 H-01 device run — bug found + fixed (the device proof did its job)

The first H-01 device run (3 iOS sims, real `mknoun.xyz` relay) made the **sender side pass** (charlie's
verdict: `rotationDeferred:true`, `charlieExcludedFromRoster:true`, `leaveTimelineRendered:true`,
`groupHardDeletedLocally:true`) but **failed end-to-end**: alice + bob both timed out on
`_waitForMemberExclusion`. Root cause from the logs: alice/bob *received and decrypted* charlie's
`member_removed` but **rejected it every ~2s** with
`GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED {type: member_removed, reason: transport_mismatch}` →
charlie was never excluded → the creator re-key (Step 4) never fired.

**Root cause (pre-existing, B5-class — the old harness mask hid it).** A voluntary leaver signs the
`member_removed` transition audit with `transportPeerId = its own peerId`
(`broadcast_voluntary_leave_use_case.dart:120-121`). Over a relay/circuit, the receiver OBSERVES the leaver
through a relayed connection, so the observed transport peer differs from the self-signed one. The receiver's
`verifyGroupTransitionAudit` (`signed_group_transition_audit.dart:240-244`) then rejects with
`transport_mismatch`. The previous H-01 harness masked this by force-promoting charlie to creator/admin, so
a real writer self-leave over relay had never been exercised. This is the same signer/observer binding
asymmetry class as the **B4 dissolve** bug.

**Fix 1 — production (`group_message_listener.dart`, `_expectedSignedAuditActorBindingForSystemEvent`).**
For a **self-authored** `member_removed` (`removedPeerId == senderId`) ONLY, relax the device/transport
binding (return an empty `_SignedTransitionAuditActorBinding` so the verifier skips the device/transport
checks). **Still enforced:** the actor signature, the actor signing public key, the transition subject, and
the output hash — and a self-removal can only remove the signer, so there is **no spoofing surface**.
Admin-authored removals (`removed != signer`) keep the strict binding. Mirrors the B4 relaxation rationale.

**Fix 2 — test verdict criteria (`group_multi_party_device_criteria.dart`).** The generic cross-role
validator was leave-unaware: it required the leaver to have a positive `keyEpoch` and demanded every role
retain the full `{alice,bob,charlie}` roster. Made it leave-aware — charlie (leaver) may have epoch 0
(allow-list at `:825`), and a new `private_voluntary_leave_convergence` membership branch asserts alice+bob
converge to `{alice,bob}` and **exclude** charlie (mirrors the `private_concurrent_admin_membership_edits`
precedent). The rigorous `_validateVoluntaryLeaveConvergenceProof` (`:8072`) was already correct and stays —
so this is **leave-aware modeling, not test-weakening**.

**Verification.** Listener host suite **173/173** green after Fix 1 (incl. the ML-013 security lock); the
H-01 re-run then PASSED end-to-end (§Step 5). Both findings (transport binding asymmetry; generic validator
leave-unawareness) are now closed.

**FOLLOW-UP (host coverage).** Add a host regression test in `group_message_listener_test.dart` that delivers
a *signed* self-authored `member_removed` (via `signedAuditSystemPayload` with `actorTransportPeerId = X`) to
a **non-self** receiver with an observed envelope `transportPeerId = Y` (Y ≠ X), asserting it is ACCEPTED and
the member excluded — plus an **admin-authored** control (`removed != signer`) with a mismatched binding that
must STILL be rejected with `transport_mismatch`. (Handle the pre-transition state hash via
`buildGroupTransitionStateHash` over the seeded state.) Until then, the device H-01 run is the authoritative
regression artifact for Fix 1.

---

## 7. Risks / open questions

1. **Multiple-admin rotation race (Step 4).** ✅ RESOLVED as planned: the implemented
   `_maybeRotateGroupKeyAfterRemoteRemoval` rotates ONLY when `group.createdBy == selfPeerId`
   (`group_message_listener.dart:3320+`), so the **creator** is the single deterministic auto-rotator and
   remaining admins never collide; case 3 (`'a non-creator member does not auto-rotate'`,
   `group_message_listener_test.dart:3192`) locks it. **Residual (→ #3):** if the creator is the one who
   left, the group has no auto-rotator and stays on the old epoch until a future rotation — a
   designated-rotator fallback is still open.
2. **Offline / unreachable admin (forward-secrecy window).** Part 1 unblocks leave immediately, but the
   re-key (Part 2) is asynchronous and depends on a remaining admin being online to receive
   `member_removed`. Between charlie's leave and alice's auto-rotate, charlie still holds the current
   epoch key. Whether this transient window is acceptable is a **product/security decision** under the
   group-crypto threat model (admin removal already has the same async property). Flag for sign-off.
3. **Non-creator admin still cannot rotate (Gate B).** A non-creator admin can now *leave* (Part 1) but
   cannot itself *re-key* — re-key still depends on the creator. This is consistent with admin-removal
   today, but means a creator-less group (creator already departed) has no auto-rotator. Out of scope to
   fix here; document as a follow-up (possibly relax Gate B to "any admin" in a separate, security-reviewed
   change with its own GKR test update).
4. **Go-side validator convergence on a writer self-removal.** Not verified in recon whether remaining
   members' Go configs converge without the leaver performing `callGroupUpdateConfig`. The `member_removed`
   receive path updates the Go topic validator config for remaining members (`_handleMemberRemoved`), but
   confirm during implementation that the new epoch's validator promotion (driven by alice's rotation)
   reaches Go correctly. Flag for the device run.
5. **B3 read-only retention interaction.** Self-removal now retains a quiet group as a read-only shell
   (`group_message_listener.dart:3127-3158`). Ensure the *voluntary* leaver's local teardown
   (`leaveGroup` from `_onLeave`) and the self-`member_removed` duplicate-ignore
   (`:3137-3146`) do not conflict — Step 3 test must assert exactly one leave/emit.
6. **Tests not executed in planning.** All blast-radius claims are from source inspection; run the full
   groups suite (`-j 1`) after each step to confirm no unlisted lock breaks.
