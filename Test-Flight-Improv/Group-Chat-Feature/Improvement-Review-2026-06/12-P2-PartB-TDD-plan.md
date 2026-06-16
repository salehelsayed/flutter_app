# 12-P2 Part B — B1b convergence build: TDD plan

> Companion to `12-P2-multi-device-honesty.md`. Drives the **deferred** Part B work to host/Go-verified completion. Decision locked: **B1b** (per-device keys). Everything stays behind `kMultiDeviceSyncEnabled` (default-OFF). Device-matrix verification is the only step that cannot run on host and remains the final external gate before the flag is enabled and UX-013 re-closed.

Authored from a 6-agent graphify assessment (2026-06-16). Key corrected facts:
- **Live DB version is `81`**; `081_group_pending_reactions.dart` is taken by concurrent reaction work. **The next free migration is `082`** (not `081`/`080` as the proposal text says).
- **`admitSiblingDeviceIfTrusted` has a real delivery bug**: it only triggers the drain, which processes *pre-existing* pending rows. A newly-admitted device on an already-keyed member has no pending row, so the key is never delivered. Must **enqueue + drain**.
- **The shipped `localNotifications`/`mutePreference` asserts ARE present** in `group_message_listener.dart` (an assessment agent's "Binary file matches" misread it as absent).
- **Go needs no receiver code change**: `groupTopicValidator → activeMemberDeviceForEnvelope → verifyGroupEnvelopeSignature` already *accepts* any sibling device that is an active entry in the receiver's local `config.Members[].Devices`. Only a **positive test** is missing.
- `group_key_update` is a **1:1 P2P `ChatMessage`**, not a pubsub message; in-process sims replay it via a `StreamController<ChatMessage>` into a `GroupKeyUpdateListener` (pattern: smoke `KE-007`).

## Non-breaking design decisions (avoid premature product calls)
- **B4 safety numbers**: `ContactSafetyNumber.build` gains an **optional** `deviceFingerprints` param. When empty (every current caller, every same-`peerId` member today) the material is **byte-identical to v1** — so no user's displayed number changes. Divergence only appears once distinct per-device material exists under B1b. **No blanket v1→v2 bump.**
- **B5 add-rotation**: new params are **optional**; rotation only fires when `rotateKeyOnAdd && kMultiDeviceSyncEnabled && self==creator && creds present`. Default behavior unchanged → **zero existing call-site churn**. Rotation runs **after** the irreversible config-sync and a rotation failure is logged, not reverted (no epoch-vs-member divergence).

## Waves (dependency-ordered, each TDD, each verified before the next)

### Wave 1 — fix the keystone delivery + prove it end-to-end
1. **Fix `admitSiblingDeviceIfTrusted`**: after `saveMember`, read `getLatestKey`; if present, **enqueue** a deferred distribution `(groupId, peerId, keyEpoch)` via a new process-wide `triggerDeferredGroupKeyDistributionEnqueue` (mirrors `triggerDeferredDistributionDrainForPeer`, calls the wired enqueue sink), **then** drain. Inject both as defaulted params. Update the unit test to assert enqueue-then-drain (not just drain).
2. **Go positive receiver test** (`pubsub_test.go`): clone the unregistered-sibling reject fixture (`:3003`) but add the sibling as an active `Devices` entry; assert `validateGroupEnvelopeForTransportPeer == accept`. Add the revoked-device negative twin. **No Go code change.**
3. **B1b sibling-sim integration test** (`test/features/groups/integration/group_sibling_device_admission_test.dart`): shared `_InMemoryGroupPendingKeyDistributionRepository` fake → real `GroupPendingKeyDistributionRunner` wired to a captured `sendP2PMessage` replayed into a sibling `GroupKeyUpdateListener`; admit a distinct sibling → runner re-distributes current key → sibling repo `getLatestKey` populated → sibling decrypts a subsequent live message. RED first (no enqueue → no delivery), then GREEN after Wave-1.1.

### Wave 2 — `device_announce` wire (the real B2 trigger)
- Add `device_announce` to `requiresSignedGroupTransitionAudit` + a `buildGroupSystemTransitionSubject` case (subject = announced device fields). The announce is **account-key-signed** (`member.publicKey` is the trust anchor; the not-yet-rostered device cannot vouch for itself).
- Add an injectable `AdmitSiblingDeviceFn` seam + constructor param to `GroupMessageListener` (mirror `TriggerDeferredDistributionDrainForPeerFn`), and a `else if (sysType == 'device_announce')` dispatch branch (before the `:2300` UNKNOWN else) that calls the admit fn with `verifiedAccountSigningPublicKey` = the account key `verifyGroupTransitionAudit` authenticated. Handle the not-yet-rostered-device exemptions in the pre-dispatch gates.
- New `announceRestoredDeviceToGroups` use case (per active non-dissolved group: build+sign device_announce, `publishGroupSystemMessage`). Wire best-effort post-restore. Round-trip + dispatch tests.

### Wave 3 — B3 hydration
- `hydrateGroupsFromPeers` use case composing the real primitives (`acceptPendingGroupInvite`/`drainGroupOfflineInboxForGroup`/`rejoinGroupTopics`) — no new migration required for the core path. Migrate `group_multi_device_convergence_test.dart` off `mirrorJoinedGroupState` to the real admit+hydrate path (guarded `multiDeviceSyncEnabled:true`).

### Wave 4 — B4 per-device safety numbers (non-breaking)
- `ContactSafetyNumber.build` optional `deviceFingerprints` (byte-identical when empty). `GroupMemberIdentitySafety.compare` gains `savedDevices`. **Migration `082`** `group_member_identity_snapshots` (clone `068`) + helpers + repo + both UI call sites + TOFU write on first safety compute. Tests: build divergence, compare identityChanged on device change, migration-chain, helper round-trip.

### Wave 5 — B5 forward rotation on add (non-breaking)
- `addGroupMember` optional `senderPublicKey/PrivateKey/Username` + `sendP2PMessage`/`storeP2PMessageInInbox` + `rotateKeyOnAdd=false`; gated rotation after config-sync. Prod caller `contact_picker_wired` opts in; `create_group_with_members` stays `false`. Tests: rotates when gated-on, no-op otherwise, no revert-divergence.

## Implementation status — 2026-06-16 (host-complete; flag default-OFF)

Waves 1, 2, 3, 5 IMPLEMENTED + TESTED (host); Wave 4 deferred. Adversarial multi-agent review run (11 agents) — **trust boundary verified fail-closed (no spoofing/self-compromise vector)**; all confirmed correctness findings fixed:

- **Wave 1 (delivery)** — `admitSiblingDeviceIfTrusted` enqueue/REOPEN-then-drain; Go positive sibling-acceptance test (`pubsub_test.go`, no Go code change); end-to-end sibling sim (`group_sibling_device_admission_test.dart`).
- **Wave 2 (device_announce)** — wire format + signed-audit; listener dispatch (`AdmitSiblingDeviceFn` seam + gate exemption + `_handleDeviceAnnounce`); emit use case `announceRestoredDeviceToGroups`. Dispatch + emit tests; full listener suite green (179).
- **Wave 3 (hydration)** — `hydrateGroupsFromPeers` (rejoin + per-group drain) + tests.
- **Wave 5 (add-rotation)** — non-breaking `rotateKeyOnAdd` opt-in, rotation after config-sync (no divergence) + tests.

**Review fixes landed:**
- **(HIGH) eventAt mismatch** — receiver now reconstructs the signed `eventAt` for `device_announce` (was deriving the Go publish time → every real announce failed `payload_mismatch`). Without this the whole path was dead on the wire.
- **(HIGH/MED) terminal-row no-op** — the `(group,peer)` pending row is device-independent, so a 2nd device of an already-converged member (or an `unreachable`-finalized row) never got the key. Fixed with a **dedicated reopen path** (`reopenForRedelivery` repo method + `dbReopenGroupPendingKeyDistributionForRedelivery` + `triggerDeferredGroupKeyDistributionReopen` sink, wired in `main.dart`) that re-arms a terminal row on admission (overriding INV-D4 exhaustion *only* for a genuine device-set change, never for stale rotation re-enqueues). Admission now delivers on both new-admit and re-announce. Regression test: admit A → finalize → admit B → B is targeted.
- **(LOW) account-key resolution** — `_resolveActorSigningPublicKey` resolves the ACCOUNT key for `device_announce` (re-announce of a rostered device now verifies + re-arms).
- **(LOW) comment** — corrected the no-key convergence path (next rotation, not app-resume drain).

**Migration note:** no migration was needed for Waves 1/2/3/5 (B5 reuses existing rotation; reopen reuses the existing `group_pending_key_distributions` table). The next free migration is **`083`** (DB v82 live — a concurrent `082_message_reaction_tombstone` landed) for Wave 4's snapshot table.

## Remaining / deferred work

**The full consolidated plan for everything still missing — B4, the emit-on-restore wiring (the built emit has zero prod callers), the trust-prompt UI security gate, B5 enablement, device matrix, cleanups — is `12-P2-PartB-REMAINING-TDD-plan.md` (R1–R7 with decision gates D1–D5).** Wave 4 (B4 per-device safety numbers) is item **R3** there: `ContactSafetyNumber.build` optional `deviceFingerprints` (byte-identical when empty → non-breaking) + `compare` `savedDevices` + **migration `083`** `group_member_device_snapshots` (clone `068`) + helpers + repo + both UI call sites + a **TOFU-vs-explicit-verify** policy decision (D2).

## What remains external (cannot run on host)
- Device-matrix verification of real ML-KEM key separation + cross-device convergence (FakeBridge crypto is passthrough → host sims prove wiring/routing, not confidentiality).
- The **trust-prompt UI** (safety-number / admin-signed device-add) that must wrap `device_announce` admission before the flag is enabled — a self-compromise vector if auto-admission ships without it.
