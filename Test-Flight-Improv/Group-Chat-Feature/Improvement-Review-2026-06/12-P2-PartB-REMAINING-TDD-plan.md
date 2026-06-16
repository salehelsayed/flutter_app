# 12-P2 Part B — Remaining / deferred work: consolidated TDD plan

> Companion to `12-P2-multi-device-honesty.md` and `12-P2-PartB-TDD-plan.md`. Covers **everything still missing or deferred** to take the same-user multi-device convergence build (B1b) from *host-complete-but-inert* to *enabled + UX-013 re-closed*. Grounded by a 5-agent graphify pass against current source (2026-06-16).
>
> **Already shipped (host-verified, behind default-OFF `kMultiDeviceSyncEnabled`):** the admission primitive (`admitSiblingDeviceIfTrusted`), the `device_announce` wire + **listener dispatch `_handleDeviceAnnounce`** (`group_message_listener.dart:2344-2395`) + emit use case (`announceRestoredDeviceToGroups`), `hydrateGroupsFromPeers`, B5 add-rotation *mechanism*, the dedicated reopen path, and the Go positive-acceptance test. Adversarial review: trust boundary fail-closed; eventAt / terminal-row / account-key bugs fixed. This plan is the rest.
>
> **Migration number:** next free is **`083`** (DB `v82` live; `078`–`082` taken — `082_message_reaction_tombstone` landed after the earlier "082" estimate). Re-check at landing.

---

## Implementation status — 2026-06-17

> **Implemented this pass (host-green, behind default-OFF flags): R1, R3, and the R5 legacy-fallback lock.** Decisions taken: D1=safety-number prompt, D2=TOFU, D3=B5 off-by-default, D4=one-shot-with-retry. All inert until `kMultiDeviceSyncEnabled` + device verification.

- **R1 — emit-on-restore: DONE.** New `group_device_announce_marker.dart` (one-shot `group_device_announce_pending`, written on restore success in `restore_identity_use_case`); `maybeAnnounceRestoredDeviceOnStartup` orchestrator (marker → build binding from `p2pService.currentState.peerId` + identity keys → `announceRestoredDeviceToGroups` → clear with D4 retry semantics), wired into `startup_router._doStartP2P`. 6 orchestrator tests; restore + mnemonic regressions green.
- **R3 — B4 per-device safety numbers: DONE.** `ContactSafetyNumber.build` optional `deviceFingerprints` (byte-identical v1 when empty, `v2` when present); `GroupMemberIdentitySafety.compare` nullable `savedDevices` (null = exact v1); **migration `084`** `group_member_device_snapshots` (next free was `084`, not `083` — `083_groups_last_membership_event_id` landed; DB v83→v84) + DB helpers + `GroupMemberDeviceSnapshotRepository` mixin (impl + in-memory); TOFU read-path helper `resolveGroupMemberDeviceSafety` wired into BOTH `group_info_wired` + `group_conversation_wired` via a runtime cast (no DI threading). **Gated by `kMultiDeviceSyncEnabled`** so flag-OFF keeps exact v1 numbers (avoids the cross-version mismatch). 12 model + 2 DB + 3 TOFU tests; both wired screens + full migration chain (v84) green.
- **R5 — legacy-fallback lock: DONE** (`group_member_legacy_device_fallback_test`, 3 tests) — locks that a device-less (un-backfilled) member resolves via `legacyDeviceIdentity`, so **no backfill migration is needed**. R5 item 1 (hydrate single-read, trivial) and item 3 (convergence-test mirror migration) NOT done — low value / risk vs benefit.

**Corrected findings (vs the plan below):**
- **Migration number is `084`** (a concurrent `083` landed mid-session). DB v84 live.
- **B4 is flag-gated** (`kMultiDeviceSyncEnabled`): per-device safety numbers are a user-facing v1→v2 security-string change with a cross-version mismatch risk, so they only activate in the multi-device build — flag-OFF is unchanged.
- **R4 (B5 enablement) has a real blocker the grounding missed:** `contact_picker_wired._inviteSelected` uses the **batch** path (`addGroupMember(syncBridgeConfig:false)`), so `addGroupMember`'s per-member `rotateKeyOnAdd` rotation is **skipped** (the `!syncBridgeConfig` early-return precedes it). B5 there needs a **single post-batch rotation** after the config-sync + `members_added` broadcast (after `contact_picker_wired.dart:382`), gated by a default-off preference, with `p2pService.sendMessage` + an inbox-store adapter. Deferred — B5's mechanism is already tested; this is a careful, optional, off-by-default integration.

**Still remaining:** R2 (trust-prompt gate — flag-enable prerequisite), R4 (B5 enablement per the corrected finding), R5 items 1/3, R6 (device matrix), R7 (flag flip + UX-013 re-close).

## Dependency graph (do in this order)

```
            ┌─ R5 cleanups (independent, any time) ─────────────────────────┐
            │                                                               │
R1 emit-wiring ──► R3 B4 safety numbers ──► R2 trust-prompt UI ──► R6 device-matrix ──► R7 flag-flip + UX-013 re-close
            │           (decision D2)          (decision D1, GATES flag)      (decision D5)
            └─ R4 B5 enablement (independent; decision D3) ──────────────────────────────┘
```

- **R1 → R3 → R2 → R6 → R7** is the critical path to flipping the flag.
- **R2 (trust-prompt UI) is the hard gate:** `kMultiDeviceSyncEnabled` MUST NOT be enabled until it lands (auto-admitting any account-signed device is a self-compromise vector — `admit_sibling_device_use_case.dart:78-84`). R2 builds on R3's per-device safety number.
- **R4 (B5)** and **R5 (cleanups)** are independent and can land any time.

## Decisions that must be made by a human first (each blocks its phase)

| # | Decision | Blocks | Options |
|---|---|---|---|
| **D1** | Trust-establishment UX for admitting a sibling device | R2 + flag enable | (a) first-use safety-number compare/accept prompt in the group security panel; (b) admin-signed device-add transition; (c) both. Also: one-time-per-device (TOFU on account key) vs re-verify each announce. |
| **D2** | B4 cold-start snapshot policy | R3 | (a) **TOFU** — auto-persist a member's device-set as trusted on first observe (matches today's contacts model); (b) **explicit-verify** — empty until the user marks-verified (safer, needs the R2 UI). Plus: confirm a **`mknoon-safety-v2`** prefix (don't reinterpret existing account-level numbers). |
| **D3** | B5 forward-rotation-on-add scope | R4 | per-group setting vs global preference vs always-on; whether B5 ships independently of `kMultiDeviceSyncEnabled` (it currently is independent). |
| **D4** | Emit marker durability | R1 | one-shot (clear marker on first emit) vs retry-until-≥1-group-succeeds; whether `keyPackageId` must be populated before enabling (currently always null in prod). |
| **D5** | Device-matrix target | R6 | two physical devices (needs a network/host-mediated signal channel — `/tmp` isn't shared) vs simulators on one host (shared fs, real Go ML-KEM on iOS-sim). And: flag-on via test-only `--dart-define` (keep prod const default-OFF). |

---

## R1 — Wire the device-announce EMIT into restore (make the built emit reachable)

**Why:** `announceRestoredDeviceToGroups` (`announce_restored_device_use_case.dart:23`) has **zero production callers** — only its unit test. A freshly-restored device never announces, so admission/re-distribution never fire for it. The wire + listener dispatch exist; only the *trigger* is missing.

**Design (graph-confirmed):** a one-shot restore marker (mirroring the ML-KEM contact re-announce marker) written at restore, read+cleared by a post-`node:start` startup hook that builds this device's own binding from local identity and calls the emit. Fire-and-forget; flag default-OFF makes it a no-op until enabled.

**TDD steps**
1. **RED** (`startup_router` harness): after a successful restore + `startP2PNode` success with a `group_device_announce_pending` marker set, assert `announceRestoredDeviceToGroups` is invoked once (injected spy) with `announcedDevice.deviceId == p2pService.currentState.peerId`, `deviceSigningPublicKey == identity.publicKey`, `mlKemPublicKey == identity.mlKemPublicKey`, account-signing keys from identity, **and the marker is cleared**. Fails (no call site).
2. **RED**: a **normal restart** (no marker) does NOT invoke the emit.
3. **GREEN — detection seam:** new `group_device_announce_marker.dart` (mirror `contact_request/application/mlkem_reannounce_marker.dart:12-56`, key `'group_device_announce_pending'`); write it in `restore_identity_use_case.dart:195-209` success block (covers both `mnemonic_input_wired` and the auto `recover_identity_from_secure_store_use_case.dart:44` path).
4. **GREEN — emit injection seam:** add an injectable `announceRestoredDeviceToGroupsFn` (default = real use case) to `StartupRouter` so the wiring is spy-able.
5. **GREEN — insertion:** in `startup_router.dart` `_doStartP2P`, inside `runWithGroupRecoveryGate` immediately after `reconcile` (`:680`): read the marker via `widget.secureKeyStore` (used at `:629` — thread into the gate closure); if set, build `GroupMemberDeviceIdentity{deviceId: p2pService.currentState.peerId, transportPeerId: same, deviceSigningPublicKey: identity.publicKey, mlKemPublicKey: identity.mlKemPublicKey}` (canonical pattern: `create_group_with_members_use_case.dart:171-189`) and call the emit; clear the marker per **D4**. Wrap `unawaited`/try so it never blocks startup.
6. **VERIFY:** groups + identity + startup_router host suites; 0 new analyze; assert flag-OFF path emits nothing.

**Risks:** `p2pService.currentState.peerId` must be stable post-`startP2PNode` (else a bad binding the receiver can't match); marker clear-on-partial-success can silently lose the announce — settle D4; the announced ML-KEM is the device's NEW key, so admission MUST re-distribute the current key to it (the reopen/drain fix is the linkage — already landed).

---

## R3 — B4 per-device safety numbers (+ migration 083)

**Why:** the safety number is **account-level today** (`contact_safety_number.dart:11-40`, `mknoon-safety-v1`), so adding/swapping a device produces an identical number and `identityChanged=false` — no warning. Per-device material exists on `GroupMember.devices`/`activeDevicesWithLegacyFallback()` but is never folded in. **Non-breaking:** add an *optional* `deviceFingerprints` so the material is byte-identical when empty (every current caller, every same-`peerId` member) — divergence only appears once distinct per-device keys exist.

**TDD steps**
1. **RED** — `ContactSafetyNumber.build` optional `deviceFingerprints: List<String>`: two calls with same ed25519/ml-kem but different device sets → DIFFERENT numbers; empty list → byte-identical to v1. GREEN: append a sorted, newline-joined `device:<deviceSigningPublicKey>:<mlKemPublicKey>` block and bump to **`mknoon-safety-v2`** *only when non-empty* (per D2).
2. **RED** — migration **`083_group_member_device_snapshots`**: table PK `(group_id, peer_id)`, `devices_json`, `public_key`, `ml_kem_public_key`, `saved_at`. GREEN: clone `068_removed_group_member_snapshots.dart:5-52`; bump `app_database_version.dart` → 83; wire `main.dart` onCreate after `:485` + onUpgrade `if (oldVersion < 83)` after `:732`.
3. **RED** — DB helpers `dbUpsertGroupMemberDeviceSnapshot` / `dbLoadGroupMemberDeviceSnapshot` (round-trip + replace-on-conflict). GREEN: clone `group_members_db_helpers.dart:204-290` (insert `ConflictAlgorithm.replace` stamping `saved_at`; load by `(group_id, peer_id)` order `saved_at DESC limit 1`). Add a repo method.
4. **RED** — `GroupMemberIdentitySafety.compare` gains `savedDevices` (default `const []`): `identityChanged == true` when `member.activeDevicesWithLegacyFallback()` differs from `savedDevices` even with identical account keys. GREEN: source current devices from the member, saved from the snapshot.
5. **RED + GREEN — wire both call sites:** `group_info_wired.dart:331` (`_loadMemberSafety`) and `group_conversation_wired.dart:1183` (`_loadSecurityStatus`) load the snapshot and pass `savedDevices` into `compare`; write the snapshot per the **D2** trigger (TOFU on first observe, or on an explicit verify action). `_IdentityChangedWarning` (`group_member_row.dart:252-340`) lights up for free.
6. **VERIFY:** migration-chain test; groups host suites; 0 new analyze; confirm displayed numbers are unchanged for members with no distinct devices.

**Risks:** the `v1`→`v2` bump is a user-facing security-string change — keep it scoped to the non-empty-device case; `GroupSecurityStatusViewState.fromSnapshot` may need a signature change if per-device cardinality is surfaced.

---

## R2 — Trust-prompt UI (REQUIRED security wrapper before the flag flips)

**Correction vs the proposal:** the listener `_handleDeviceAnnounce` dispatch + `admitSiblingDeviceIfTrusted` call **already exist** (`group_message_listener.dart:2344-2395`). What's missing is the **user-decision gate** layered on top — today admission fires on account-key match alone (auto-admit), which is the self-compromise vector. R2 adds the explicit trust decision (built on R3's per-device safety number).

**TDD steps** (per **D1**)
1. **RED** — `GroupSecurityStatusViewState` (`group_security_status_view_state.dart:5-121`) carries a NEW `pendingSiblingDevices` field (peerId, deviceId, per-device safety number); a widget test on `group_info_screen.dart` `_buildSecurityStatusCard` (`:239-348`) renders a verify-safety-number prompt with accept/reject keys. Fails (field/widget don't exist).
2. **GREEN** — add `pendingSiblingDevices` + a prompt widget modeled on `_IdentityChangedWarning`/`_SafetyNumberLine` (`group_member_row.dart:252-340`); surface the announced device's safety number (R3) for the user to compare.
3. **RED** — the listener's `_handleDeviceAnnounce` admit call must consult a **user-decision store** before invoking `AdmitSiblingDeviceFn`: an un-verified pending device is held (persisted as pending), NOT auto-admitted, even with a valid account signature. Test: account-signed announce for an *unverified* device → held (no `saveMember`, no reopen/drain); after the accept callback records verification → admitted.
4. **GREEN** — add the pending-device store + thread an `isSiblingDeviceTrusted(...)` check into `_handleDeviceAnnounce` ahead of the admit; the accept callback (from R2.2) marks-verified and re-drives admission. *(If D1 = admin-signed device-add transition instead, gate on a verified admin signature rather than a local-user prompt.)*
5. **VERIFY:** listener host suite green; the auto-admit-without-verification path is now impossible (regression lock).

**Risk:** shipping the listener handler without this gate is unsafe; shipping the UI without the handler change leaves it inert. They land together; the flag stays OFF until both are in.

---

## R4 — B5 enablement (forward rotation on real add)  *(independent; decision D3)*

**Why:** the B5 *mechanism* is in `addGroupMember` (`add_group_member_use_case.dart:128-147`, rotation `:411-426`) but the real add path doesn't pass the params, so it's inert.

**TDD steps**
1. **RED** — extend a `contact_picker_wired` `_inviteSelected` test: `addGroupMember` is called with `rotateKeyOnAdd: <pref>` + `senderPublicKey/PrivateKey/Username` + send/inbox sinks when the forward-secrecy preference is on. Fails (call at `contact_picker_wired.dart:313-320` omits them).
2. **GREEN** — at `:313`, pass `rotateKeyOnAdd: <pref>`, `senderPublicKey: identity.publicKey`, `senderPrivateKey: identity.privateKey`, `senderUsername: identity.username` (identity loaded `:283-284`), `sendP2PMessage: (p,m) => widget.p2pService.sendMessage(p,m)` (`:102/:483`), and a **`storeP2PMessageInInbox` adapter** (note: `callGroupInboxStore` at `:468` is a bridge call, NOT the `(peerId,message)` sink shape — needs a small adapter).
3. **VERIFY:** rotation is creator-gated + best-effort (no member revert on rotation failure); surface/telemeter the `GROUP_ADD_MEMBER_FORWARD_ROTATION fullyDistributed=false` case so a silently-skipped forward-secrecy is visible.

**Risk:** B5 adds a full key rotation + per-device distribution to every add (latency/cost) — D3 decides scope/UX; the wrong inbox adapter could skip inbox custody for offline recipients during distribution.

---

## R5 — Cleanups & residue  *(independent, low risk)*

1. **hydrate double `getAllGroups`** (`hydrate_groups_from_peers_use_case.dart:47,50` + `rejoin_group_topics_use_case.dart:67`): test counts a single enumeration; refactor to fetch once and pass the non-dissolved subset to the drain loop **without** changing rejoin's need to iterate dissolved groups (it skips+logs them). Trivial.
2. **Legacy-fallback lock test (no backfill needed):** migration 062 leaves `devices_json` NULL, but `GroupMember.legacyDeviceIdentity` (`group_member.dart:388-402`) synthesizes a device from account columns, and every device path uses `activeDevicesWithLegacyFallback()`. Add a migration-chain test: a pre-062 member (NULL `devices_json`) resolves via the legacy device in `rotate_and_distribute` + `admitSiblingDeviceIfTrusted` — locking the contract so no one adds an unneeded backfill. (Guard: a member with both account keys NULL yields a null legacy device → silently non-deliverable; assert/telemeter.)
3. **Convergence-test mirror migration:** port one `group_multi_device_convergence_test.dart` case (`mirrorJoinedGroupState:27-47`) onto the real `announceRestoredDeviceToGroups → _handleDeviceAnnounce → admitSiblingDeviceIfTrusted → hydrateGroupsFromPeers` path; keep a lightweight mirror only for the device-local-state cases (mute/unread/unsubscribe), which are orthogonal to admission. *(Must exercise the flag-ON branch or it passes vacuously.)*

---

## R6 — Device-matrix verification (the final external gate)

**Why:** host sims use passthrough crypto (`FakeBridge`), so they prove wiring/routing, **not** real ML-KEM per-device key separation. Only a real-Go-bridge device run proves a restored sibling's DISTINCT ML-KEM secret actually decrypts. No existing scenario exercises the real B1b wire path — `ge012/ge013/ra012/ra013` all hand-copy device material and teleport the key via `importJoinedGroupFixture` (`group_multi_device_real_harness.dart:1116-1164`).

**New scenario `b1b_sibling_device_convergence`** (roles: alice=admin, bob=member-primary, charlie=bob-sibling-restore). **The sibling MUST NOT receive the key by fixture** — that's the whole point.

**TDD steps**
1. **RED** — register the scenario id in `scripts/group_multi_party_device_criteria.dart` (`allGroupMultiPartyDeviceScenarioIds` + `scenarioRequirement`), `run_group_multi_party_device_real.dart::_scenariosToRun`, and the harness `_rolesByScenario` (no handlers → throws).
2. **Flag plumbing** — `--dart-define=GROUP_MULTI_PARTY_MULTI_DEVICE_SYNC=true` read in the harness, threaded into the `AdmitSiblingDeviceFn` seam + the emit (override the otherwise default-OFF const **test-scoped only**, per D5). Failing assertion first: admit returns `disabled` without it.
3. **`_runB1bAlice`** (admin): create group with bob; publish `group_fixture`; wait `bob_joined`; send a pre-announce proof message; after the sibling announces, assert `getMember(bob).activeDevices` grows to 2 + a `GROUP_SIBLING_DEVICE_ADMITTED` event; send a POST-admit live proof message; write verdict.
4. **`_runB1bBob`** (primary): `importJoinedGroupFixture` (real join of the primary only); signal `bob_joined`; witness; verdict.
5. **`_runB1bCharlie`** (sibling): launch with `restoreMnemonic=bob's` + `useFreshTransportIdentityForRestoredAccount=true` (`group_multi_device_real_harness.dart:909-975`) → same logical peerId, DISTINCT transport peerId + fresh random ML-KEM. **Do NOT** `importJoinedGroupFixture`. Build a `GroupMemberDeviceIdentity` from its OWN `p2pService.currentState.peerId` + own `mlKemPublicKey`; call `announceRestoredDeviceToGroups`. **Decrypt proof:** `waitForCondition` that `getLatestKey(groupId)` populates (via the runner's re-distribution → `GroupKeyUpdateListener`), then `drainGroupOfflineInboxForGroup` and assert alice's POST-admit message decrypts on the sibling. Verdict: `{siblingTransportPeerId, siblingMlKemPublicKey (≠ logical), keyEpochReceived, decryptedPostAdmitText}`.
6. **Criteria** (`evaluateGroupMultiPartyVerdicts`): (a) alice `admitOutcome==admitted`; (b) bob+sibling distinct transportPeerIds under one logical peerId; (c) sibling `mlKemPublicKey != primary`; (d) sibling `keyEpochReceived == current`; (e) sibling `decryptedPostAdmitText == alice's`.
7. **Orchestrator** — sibling launch passes `restoreMnemonic` so `isStatefulRelaunch` SKIPS `_uninstallRunnerApp` (`run_group_multi_party_device_real.dart:207-231`); forward the multi-device-sync dart-define. Run on the matrix (iPhone-sim + Pixel, real Go bridge); capture role logs/verdicts. **Pin the build to post-reopen-fix HEAD** (else the 2nd-device-keyless bug reappears as a false failure).

**Known device blockers:** cross-device `/tmp` isn't shared (two physical phones need a network/host-mediated signal channel — D5); `flutter test`/`simctl uninstall` wipes the restored DB on a fresh launch (must be skipped for restore roles); ML-KEM is random-per-restore (assertions must compare the sibling's OWN key, never the shared logical fixture). **A green HOST run is NOT device verification.**

---

## R7 — Flag flip + UX-013 re-closure (only after R1–R3, R2, R6)

1. Enable `MKNOON_ENABLE_MULTI_DEVICE_SYNC=true` in the target build **only after** R2 (trust prompt) + R6 (device matrix) are green.
2. Flip `groupMultiDeviceImplemented` for the convergence facets (already keyed off `kMultiDeviceSyncEnabled`) — the contract test `group_multi_device_policy_contract_test.dart` then requires the facets to be implemented; keep it green.
3. Re-close **UX-013** in `libp2p_group_chat_test_matrix_full_with_rules.md:273` + the two derived matrices, citing the device-matrix verdict. Record the run in a `Test-Flight-Improv/` matrix.

---

## Test strategy summary

| Phase | Unit | Widget | Integration / sim | Device matrix |
|---|---|---|---|---|
| R1 emit-wiring | marker write/clear | — | startup_router emit-on-restore vs restart | (covered in R6) |
| R3 B4 | build v2, compare savedDevices, DB helpers, migration-chain | both call sites render warning | — | (covered in R6) |
| R2 trust-prompt | pending-device gate holds un-verified | security-card prompt accept/reject | listener: un-verified announce held | — |
| R4 B5 | (existing) | contact_picker passes B5 params | — | — |
| R5 cleanups | single-enumeration; legacy-fallback lock | — | 1 convergence test → real path | — |
| R6 device matrix | — | — | host sim already green | **b1b_sibling_device_convergence** (real Go ML-KEM) |

## Top risks (carried)

- **Enabling the flag without R2 is a self-compromise vector** — auto-admit of any account-signed device. R2 is a hard gate.
- **Vacuous device test** — if the sibling reuses `importJoinedGroupFixture`, re-distribution is never exercised and the test passes for nothing. The sibling must get the key only via the real announce→admit→re-distribute path.
- **Host-green ≠ verified** — passthrough crypto can't prove per-device ML-KEM confidentiality; only the device matrix can.
- **Migration `083` contention** — re-check the next free number at landing.
- **Marker durability (D4)** — clearing on partial-success can silently lose the announce; never-clearing churns every startup.
