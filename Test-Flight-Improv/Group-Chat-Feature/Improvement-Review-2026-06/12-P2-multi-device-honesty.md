> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P2** · [Findings appendix](./appendix-findings.md)

---

# Make multi-device real or stop claiming it

**Priority: P2** · Theme: same-user multi-device group convergence · Effort: Large (real convergence) / Small (honest down-scope)

> **Re-validated against HEAD on 2026-06-16** (19-agent graphify-first verification). Every core claim still holds: **Part A is implementable as written**, and **Part B's convergence goal is still unbuilt**. Two substantive updates were folded in: **(1)** the next free DB migration is `081` (078/079/080 already shipped, DB `v80` is live) — the doc previously said `080`; **(2)** B1b's single-device key-re-distribution trigger and the durable deferred-distribution-with-resume that the doc called "missing" **already exist** (Finding 03 Slice 2: `distributeCurrentGroupKeyToDeferredPeer` + `GroupPendingKeyDistributionRunner`), so B1b/B3 should *reuse* them — the only remaining B1b gap is sibling-device **admission** into `member.devices`. Stale `file:line` citations shifted by those migrations/refactors have been corrected throughout.

## Implementation status — 2026-06-16

> **Part A: COMPLETE. Part B: STARTED behind a default-off flag (B1b path chosen).** Host-test-green; analyze clean (0 new issues); arch graph updated. Device-matrix verification of Part B is still outstanding and cannot run in this environment.

**Part A (the P2 deliverable) — shipped:**
- **A1** — UX-013 reopened from a premature `Closed` to **`Partial / Device-local-only`** in the source matrix (`libp2p_group_chat_test_matrix_full_with_rules.md:273`), re-added as a row to both derived matrices (`..._matrix_not_fully_implemented.md`, `..._policy_needed_matrix.md`), and the runtime-vs-contract gap recorded in `65-...session-breakdown.md`.
- **A2** — `group_multi_device_policy.dart`: file comment now states shared scope is *contractual intent, not produced at runtime*; added `groupMultiDeviceImplemented` map + `isGroupMultiDeviceImplemented(facet)` helper (the three convergence facets resolve to `kMultiDeviceSyncEnabled`, i.e. **not implemented** until Part B is enabled).
- **A3** — device-local `assert(isGroupMultiDeviceDeviceLocal(...))` guards added at the mute seam (`set_group_muted_use_case.dart`), the unread seams (`group_message_repository_impl.dart` get/getTotal/markAsRead), and the notification-suppression branch (`group_message_listener.dart`); **new guardrail** `group_multi_device_policy_contract_test.dart` mechanically blocks marking the convergence facets implemented while the flag is off (8 tests).
- **A4** — honest restore notice: `MnemonicInputWired` shows a one-time, non-blocking SnackBar when restore hydrates zero groups (new l10n `restore_groups_device_local_notice` in en/ar/de; `groupRepo` threaded `StartupRouter → IdentityChoiceWired → MnemonicInputWired`; 3 widget tests). `restore_identity_use_case.dart` left group-agnostic by design.

**Part B — foundation + B1b keystone shipped behind `kMultiDeviceSyncEnabled` (default-OFF):**
- **Decision recorded: B1b** (per-device ML-KEM keys + sibling admission + re-distribution) is the chosen path, not B1a. Rationale: forward secrecy preserved; reuses the already-built `distributeCurrentGroupKeyToDeferredPeer` + `GroupPendingKeyDistributionRunner`.
- **Flag** `lib/core/config/multi_device_sync_flag.dart` (`kMultiDeviceSyncEnabled`, build-time, default-off).
- **B2 keystone** `lib/features/groups/application/admit_sibling_device_use_case.dart` — `admitSiblingDeviceIfTrusted(...)`: flag-gated + account-key trust-gated + **idempotent** admission of a sibling `GroupMemberDeviceIdentity` into `member.devices`, then fires the existing `triggerDeferredDistributionDrainForPeer` so the current key is re-distributed to the new device. This is the recon-confirmed *only remaining gap (i)* for B1b — re-distribution (ii) already exists and is reused, not rebuilt. 7 unit tests (admit/idempotent/untrusted/disabled/invalid/memberNotFound/same-peerId-legacy-noop).

**Part B — convergence build (follow-up session, host-complete behind the flag).** See the companion plan `12-P2-PartB-TDD-plan.md` for the full wave breakdown + the adversarial-review outcome. Summary:
1. ✅ **Device-announce wire + emit-on-restore** — signed `device_announce` transition (`signed_group_transition_audit.dart`) + listener dispatch (`AdmitSiblingDeviceFn` seam + gate exemption + `_handleDeviceAnnounce`) + emit use case `announceRestoredDeviceToGroups`. The receiver reconstructs the signed `eventAt` and resolves the ACCOUNT key, so account-signed announces verify and re-arm. *(The trust wrapper — safety-number prompt / admin-signed device-add — is still required before the flag is enabled.)*
2. ✅ **Go receiver acceptance** — confirmed the `groupTopicValidator → activeMemberDeviceForEnvelope` receive path already accepts an admitted sibling device (no Go code change); locked with a positive `pubsub_test.go` test (+ revoked-twin negative).
3. ✅ **B3 hydration** — `hydrateGroupsFromPeers` (rejoin + per-group drain) + the end-to-end sibling sim that exercises the real admit→re-distribute→converge path (the production analogue of the hand-copying `mirrorJoinedGroupState`). No migration needed.
4. ⏳ **B4 per-device safety numbers** — needs **migration `083`** (a concurrent `082` landed) + a TOFU-vs-verify cold-start policy decision.
5. ✅ **B5 forward rotation on add** — non-breaking `rotateKeyOnAdd` opt-in in `addGroupMember`, rotation after config-sync (no epoch-vs-member divergence). *Mechanism only* — enabling at `contact_picker_wired` is unwired (product cost decision).
6. ⏳ **Device matrix** — drive the two-device harnesses; only then enable the flag and re-close UX-013 with the contract test green.

**⚠️ Two gaps the convergence build still has before it can be enabled (full plan: `12-P2-PartB-REMAINING-TDD-plan.md`):** (i) the EMIT `announceRestoredDeviceToGroups` has **zero production callers** — it is built + tested but never invoked from the restore/startup path, so a restored device never announces yet; (ii) the **trust-prompt UI** that must gate auto-admission does not exist — `kMultiDeviceSyncEnabled` MUST stay OFF until it lands (auto-admitting any account-signed device is a self-compromise vector). The listener dispatch + admit primitive themselves are built.

**Stale citations corrected** (recon-verified): per-device encrypt is in `_distributeRotatedKeyToDevice` (`rotate_and_distribute_group_key_use_case.dart`), not the public entrypoint; the live DB version is **81** and **the next free migration is `082`** (concurrent reaction work took `081` after this doc was written — the doc body's "next free is 081" is now stale); `GroupMemberIdentitySafety.compare` spans `:16-53`; accept-path epoch-key persistence is `accept_pending_group_invite_use_case.dart:287` → `handle_incoming_group_invite_use_case.dart:953`. Design note: in the same-`peerId` model a true sibling already passes device-binding, so admission only adds genuinely-distinct per-device identities (the legacy account-derived device is treated as already-present).

## Why this matters (user experience)

The repo documents and unit-models a same-user multi-device contract — "membership, group metadata, and message history converge across all of a user's joined devices; mute/unread/notifications stay device-local" — and on `2026-04-05` it marked **UX-013** *closed* on that basis (`Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md:11-12`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md:20-21`).

At runtime that contract does not hold. A user who restores their identity on a second device (new phone, reinstall) gets, **for group purposes, a fresh install**:

- **No groups, no members, no metadata.** Restore writes only the identity row; nothing pulls the user's existing groups, rosters, or metadata onto the new device.
- **No history, and no ability to decrypt it.** The restored device cannot decrypt incoming group messages because it holds no group keys — and worse, it cannot ever obtain the *old* keys it was sent, because restore **regenerates a brand-new random ML-KEM keypair** (`restore_identity_use_case.dart:171-172`). All historic group-key distributions were encrypted to the *original* device's ML-KEM public key, which no longer exists.
- **Silent.** There is no error, no "this device is not synced" state. The user simply sees an empty group list and silently drops every incoming group message.

For a security-focused PQ messenger, an over-claimed "closed" contract is itself a reliability defect: it tells maintainers and testers a guarantee exists that the code never delivers. The honest options are (A) build real second-device hydration + sibling admission, or (B) down-scope the claim to "device-local until a real sync channel exists." This proposal specifies both, recommends doing (B) now and (A) later, and adds a guardrail so the gap can't silently reopen.

## Current behaviour & evidence

| Concern | What the code does today | Evidence |
|---|---|---|
| Restore hydrates nothing group-related | Validates mnemonic → `callRestore` → regenerates ML-KEM → `saveIdentity`. No group/member/key fetch. (A contact-only ML-KEM re-announce marker at `:195-209` was added since this doc was written, but it re-announces to *contacts* only — no group/member/key hydration.) | `lib/features/identity/application/restore_identity_use_case.dart:31-222` |
| ML-KEM key is regenerated on restore | New random keypair from `callMlKemKeygen()`, so the device can't decrypt anything ever sent to the old ML-KEM key. | `restore_identity_use_case.dart:73,171-172` |
| Rejoin only re-subscribes *local* groups | `rejoinGroupTopics` iterates `groupRepo.getAllGroups()` and rejoins; pulls nothing from peers. A fresh install has zero local groups → nothing to rejoin. | `lib/features/groups/application/rejoin_group_topics_use_case.dart:67,102-139` |
| "Convergence" is test-only | The accepted proof copies state by hand: `getGroup/getMembers/getLatestKey` from source, `saveGroup/saveMember/saveKey` into target, then `subscribeToGroup`. No production analogue exists for *state* hydration (group/member/metadata copy). **Note:** a production *key-re-distribution* drain now exists (`distributeCurrentGroupKeyToDeferredPeer` + `GroupPendingKeyDistributionRunner`, Finding 03 Slice 2), but it only re-sends the current key to roster devices that regained a key — it does not pull or copy group/member/metadata state. | `test/features/groups/integration/group_multi_device_convergence_test.dart:27-47` |
| Policy map is inert | `groupMultiDeviceScopeFor` / `isGroupMultiDeviceShared` / `isGroupMultiDeviceDeviceLocal` are referenced only by the file itself and its unit test. No send/receive/notification/mute code branches on them. | `lib/features/groups/domain/models/group_multi_device_policy.dart:32-40` |
| No sibling-device admission persistence | Grep for `registerSenderDevice` / `admitDevice` / `learnDevice` and for `saveMember`-with-new-device returns nothing in `lib/features/groups` except the creator's self-registration. The offline-replay path builds a transient `GroupMemberDeviceIdentity` purely to verify a signature and never persists it. | `lib/features/groups/application/handle_incoming_group_message_use_case.dart:1043-1060`; `lib/features/groups/application/group_offline_replay_envelope.dart:595-631` |
| Roster asymmetry | Creator self-registers exactly one device; added members start with `devices == const []`; migration 062 ALTERs only, no backfill. | `create_group_with_members_use_case.dart:171-232`; `lib/core/database/migrations/062_group_member_device_identities.dart:30-32` |
| Safety number ignores devices | `currentSafetyNumber` derives from `member.publicKey + member.mlKemPublicKey` only; `identityChanged` is account-key equality. Per-device key material is never inspected. | `lib/features/groups/domain/models/group_member_identity_safety.dart:24-52` |
| New member, no forward rotation | Add/accept-invite persist the *current* epoch key straight from the invite; only removal/voluntary-leave rotate. (`add_group_member_use_case.dart:319` fires `triggerDeferredDistributionDrainForPeer`, which re-distributes the *existing* current key — not a new epoch — so it is **not** add-time forward rotation.) | `add_group_member_use_case.dart`; `handle_incoming_group_invite_use_case.dart:947-953`; `accept_pending_group_invite_use_case.dart:670-676,706-709`; `rotate_and_distribute_group_key_use_case.dart` |

### One nuance that constrains the design

In this identity model the libp2p transport peer **is** the account peer: the node ID is derived from the same ed25519 identity key, so a restored sibling presents the **same `peerId`** for both account and transport. That means the `_isSenderDeviceBound` checks (`handle_incoming_group_message_use_case.dart:1043-1060`) actually *pass* for a same-identity sibling — the creator's self-registered device has `transportPeerId == accountPeerId`, and the legacy empty-devices branch keys on the same value. So the predicted "every sibling message is silently dropped" outcome does **not** occur for true same-identity siblings; the device-bound check is not the blocker.

The real blockers are therefore: **(1)** no state/key hydration on restore, **(2)** the regenerated ML-KEM key making old keys undecryptable, and **(3)** an inert policy + over-claimed matrix. Sibling-device admission and per-device safety numbers matter only once distinct per-device keys exist, which they don't today. This reframing materially shrinks the necessary work and is reflected in the priorities below.

## Root cause(s)

1. **Identity is single-install, single-row, with no account-sync channel.** The breakdown states this explicitly: "identity persistence is explicitly single-install and single-row" and "there is no out-of-tree account sync system in this repo" (`65-...-breakdown.md:54-79`). There is simply no production mechanism by which device B learns device A's group state.
2. **Restore is identity-only and key-destructive.** It re-mints ML-KEM keys, severing access to any key material ever distributed to the device.
3. **A declarative contract was treated as an implemented one.** The policy map and the hand-copying unit test were accepted as proof of a runtime guarantee and the matrix row was closed, with nothing in production producing or checking the guarantee.

## Proposed improvements

The work splits cleanly into a **cheap honesty fix (do now)** and a **real convergence build (do later, behind a flag)**. Do the honesty fix unconditionally; it is the actual P2 deliverable.

### Part A — Down-scope the claim and add a guardrail (Small, do now)

**A1. Reopen / restate UX-013.** In `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md` and `..._policy_needed_matrix.md`, change UX-013 from *closed* to a `Partial`/`Device-local-only` status with explicit wording: *"membership/metadata/history converge only for devices that already materialized the group locally; a freshly restored second device does NOT hydrate group state or keys. Shared-across-devices is aspirational until a sync channel exists."* Add a one-line forward-pointer to Part B.

**A2. Annotate the policy as aspirational and split the enum semantics.** In `group_multi_device_policy.dart`, the `sharedAcrossJoinedDevices` scope currently overstates reality. Either (a) rename the runtime-honest variant, or (b) keep the enum but add a second map `groupMultiDeviceImplemented: { facet -> bool }` and a helper `isGroupMultiDeviceImplemented(facet)` that returns `false` for `membershipState/groupMetadata/messageHistory` today. Update the file-level comment (lines 14-16) to state that shared scope is *contractual intent*, not produced at runtime.

**A3. Wire the policy into the seams that already honor it, plus a contract test.** Make the device-local facets *assert* their scope so the guarantee can't silently flip:
- Notification suppression / unread counting / mute should call `assert(isGroupMultiDeviceDeviceLocal(facet))` (or branch on it) at the point they persist installation-local state (`set_group_muted_use_case.dart`, the unread/notification seams).
- Add `test/features/groups/domain/models/group_multi_device_policy_contract_test.dart` that fails if any facet's declared scope diverges from a small fixture of "what the code actually does," and that fails if `messageHistory` is ever marked implemented without a corresponding hydration entry point existing. This is the guardrail that prevents UX-013 from being re-closed prematurely.

**A4. Make restore honest to the user.** When restore completes on a device that finds zero local groups, surface a one-time, non-blocking state — *"Your groups will reappear when this device is re-admitted; group history from before this device existed cannot be recovered."* No new wire/DB needed; this is a UI/string + a flag read off `groupRepo.getAllGroups().isEmpty` post-restore. (No silent empty list.)

*No wire/DB/migration impact for Part A.*

### Part B — Real second-device hydration + sibling admission (Large, flagged, do later)

This is the genuine convergence build. Gate the whole thing behind a `multiDeviceSync` feature flag so the matrix can only re-close UX-013 once B is verified on-device.

**B1. Persist ML-KEM secret across the identity backup, OR add a per-device key handshake.** The hard blocker is that restore re-mints the ML-KEM key. Two options:
- **B1a (simpler, weaker secrecy):** include the ML-KEM secret key in the identity backup material so a restored device reconstructs the *same* ML-KEM key and can decrypt previously-distributed group keys. Changes `restore_identity_use_case.dart:171-172` to *restore* rather than *regenerate* when backup material is present. Trade-off: ties ML-KEM secrecy to the mnemonic/backup blob.
- **B1b (preferred, forward-secret):** keep per-device ML-KEM keys but have the new device **announce its fresh device identity** and have a sibling/admin **re-distribute current group keys to the new device's ML-KEM key** via the existing per-device channel. `rotateAndDistributeGroupKey` already encrypts the key per recipient *device* using `device.mlKemPublicKey` (`rotate_and_distribute_group_key_use_case.dart:920`, v2 `group_key_update` envelope at `:947-955`), so the distribution primitive exists. **The single-device re-distribution trigger also already exists** — `distributeCurrentGroupKeyToDeferredPeer` (`rotate_and_distribute_group_key_use_case.dart:591-674`) re-sends the *current* persisted key to one peer's now-deliverable devices, driven by the durable `GroupPendingKeyDistributionRunner` (`group_pending_key_distribution_service.dart:54-180`; migration 078), wired in `main.dart:1419/2303/3799` (Finding 03 Slice 2). So what's *actually* missing is only **(i) admitting the new sibling device into `member.devices`** so it becomes a deliverable target; (ii) is implemented and B1b should **reuse** it, not rebuild it.

**B2. Sibling-device admission.** Add an explicit admission step: when a wire message/system event is **account-signed** (`member.publicKey` matches the signing key) but arrives from a device not in `member.devices`, persist a new active `GroupMemberDeviceIdentity` (fields per `group_member.dart:79-98`; `fromConfigMap` at `:503`, `toConfigJson` at `:553`: `deviceId`, `transportPeerId`, `deviceSigningPublicKey`, `mlKemPublicKey`, optional `keyPackageId`) via `groupRepo.saveMember(member.copyWith(devices: [...member.devices, newDevice]))`, **gated by trust** (admin-signed device-add transition, or first-use-on-trusted-account-key behind a safety-number prompt). Mirror the same admission in the Go validator (`go-mknoon/node/pubsub.go:525-634`, the `resolveGroupSenderDeviceBinding` resolution block; active-device admission gate at `:564-588`). Note: given the same-peerId identity model, this is only meaningful once devices carry *distinct* signing/ML-KEM material — i.e. it must land together with B1b. Propagate admitted devices to other members through the existing config payload path (`group_config_payload.dart`, `GroupMember.toConfigJson`/`fromConfigMap`).

**B3. Hydration on restore.** After restore + admission, the new device must pull current group config + latest key. Add a `hydrateGroupsFromPeers` use case that, for each group the device learns of (via an admin/sibling config push or an explicit request channel), fetches the latest `GroupKeyInfo` distributed to *its* device key and writes `saveGroup/saveMember/saveKey`, then calls the existing `rejoinGroupTopics` to subscribe. This is the production analogue of the test-only `mirrorJoinedGroupState`. (This restore-time peer-*pull* of group state is still genuinely missing. Do **not** conflate it with the existing `GroupPendingKeyRepairRunner` (`group_pending_key_repair_service.dart:106-125`), which decrypt-replays already-received-but-undecryptable messages, nor with `GroupPendingKeyDistributionRunner`, which re-distributes keys to *roster* devices — neither pulls or writes new group/member state on a fresh device.)

**B4. Per-device safety numbers.** Once distinct per-device keys exist (B1b/B2), fold active device signing keys / keyPackage material into `GroupMemberIdentitySafety.compare` (`group_member_identity_safety.dart:24-52`) so adding/rotating a device shows as an identity change requiring re-verification, and surface it in `group_security_status_view_state.dart`.

**B5. Forward rotation on add (optional, security).** Rotate the group key when a member is *added*, not just removed, so a joiner cannot read prior-epoch traffic obtained via inbox/history-gap replay. (`drainGroupOfflineInbox`'s `shouldSkipPreJoinReplay` already bounds *replayed* history to post-join; the residual exposure is same-epoch live/GossipSub traffic.) Wire an `add`-time call to `rotateAndDistributeGroupKey` in `add_group_member_use_case.dart`.

**New wire/DB/migration impact (Part B only):**
- **Wire:** a device-announce / device-add signed transition type. The re-distribute-key-to-one-device trigger already exists (`distributeCurrentGroupKeyToDeferredPeer`, Finding 03 Slice 2) and reuses the existing `group_key_update` v2 envelope shape (`rotate_and_distribute_group_key_use_case.dart:947-955`).
- **DB/migration:** device rows already exist (migration 062); B may need a backfill migration to populate device entries for existing members (062 intentionally skipped backfill) and a small "hydration pending" flag table or column. **Migrations 078/079/080 are already taken** (deferred-distribution queue / message dedup / repair-status index) and DB version is already `80`, so the new Part-B migration must claim `081` / DB `v81`.
- **Go:** validator change in `pubsub.go` to accept admitted sibling devices.

## Affected files & components

**Part A (do now):**
- `lib/features/groups/domain/models/group_multi_device_policy.dart` — annotate scope as intent; add implemented-map + helper.
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md` — reopen/restate UX-013.
- `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md` — record the runtime-vs-contract gap and the down-scope decision.
- `lib/features/groups/application/set_group_muted_use_case.dart` (+ unread/notification seams) — assert device-local scope.
- `test/features/groups/domain/models/group_multi_device_policy_contract_test.dart` *(new)* — guardrail contract test.
- `lib/features/identity/application/restore_identity_use_case.dart` — surface the honest "groups will reappear / pre-device history unrecoverable" state.

**Part B (later, flagged):**
- `lib/features/identity/application/restore_identity_use_case.dart:171-172` — restore vs regenerate ML-KEM (B1a) or trigger device-announce (B1b).
- `lib/features/groups/application/rejoin_group_topics_use_case.dart` — invoked after hydration; possibly extend to pull-from-peer.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart:1043-1060` — sibling admission on account-signed/unregistered-device.
- `lib/features/groups/application/group_offline_replay_envelope.dart:595-631` — persist (not just verify) admitted devices.
- `lib/features/groups/application/group_message_listener.dart`, `group_config_payload.dart`, `lib/features/groups/domain/models/group_member.dart` — propagate admitted devices.
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` — re-distribute-to-one-device entry point **already exists** (`distributeCurrentGroupKeyToDeferredPeer:591-674`, reuse for B1b); add-time rotation hook (B5) still missing.
- `lib/features/groups/application/add_group_member_use_case.dart`, `handle_incoming_group_invite_use_case.dart:947-953`, `accept_pending_group_invite_use_case.dart:670-676,706-709` — forward rotation on add (B5).
- `lib/features/groups/domain/models/group_member_identity_safety.dart`, `group_security_status_view_state.dart` — per-device safety numbers (B4).
- `go-mknoon/node/pubsub.go:525-634` (`resolveGroupSenderDeviceBinding`; active-device gate `:564-588`) — validator-side sibling admission.
- New migration under `lib/core/database/migrations/` (next free is `081_*`; 078/079/080 already exist and DB version is already `80`) — device backfill + hydration-pending flag.

## Test & verification strategy

**Part A (unit + matrix, no device needed):**
- Contract test `group_multi_device_policy_contract_test.dart` fails if any facet's declared scope diverges from actual behavior, and fails if `messageHistory/membershipState/groupMetadata` are marked implemented without a hydration entry point. This is the gate that keeps UX-013 from being re-closed.
- A restore unit test asserting that, post-restore with zero local groups, the honest UI state is emitted (not a silent empty list).
- Doc review: confirm both matrix files no longer assert `closed` for UX-013.

**Part B (unit → in-process harness → device matrix):**
- **Unit:** sibling-admission tests on `handle_incoming_group_message_use_case` (account-signed + unregistered device → persisted device row, gated by trust; untrusted → rejected). Re-distribution tests on `rotate_and_distribute_group_key_use_case` for a single new device target. Per-device safety-number change tests.
- **In-process integration harness:** replace the hand-copying `mirrorJoinedGroupState` in `test/features/groups/integration/group_multi_device_convergence_test.dart` with the **real** `hydrateGroupsFromPeers` path, so the proof exercises production code. Extend `FakeGroupPubSubNetwork`/`GroupTestUser` so a same-identity sibling can receive a re-distributed key and decrypt history.
- **Device matrix:** drive the existing two-device harnesses — `integration_test/group_multi_device_real_harness.dart` and `integration_test/group_multi_party_device_real_harness.dart` (runner `integration_test/scripts/run_group_multi_party_device_real.dart`) — for the canonical scenario: device A creates a group + sends history → restore same identity on device B → assert B hydrates group/members/latest key, joins the topic, and can decrypt both new and (per B1 choice) historic messages. Note the known device-blockers from prior multi-device sessions (cross-device `/tmp`, `flutter test` uninstall, ML-KEM-random-per-restore — the last of which B1 directly addresses). Record results in a `Test-Flight-Improv/` matrix before flipping the flag or re-closing UX-013.

## Risks, trade-offs & rollout

- **Down-scoping is a doc/UX change, near-zero risk.** Worst case is a contract test that's too strict; it touches no message flow. Recommend shipping Part A immediately and independently.
- **B1a (restore ML-KEM from backup) weakens forward secrecy** — the ML-KEM secret becomes recoverable from the mnemonic/backup blob. **B1b (per-device keys + re-distribution)** preserves per-device secrecy but is more work and depends on B2 admission. Prefer B1b; B1a is an acceptable interim only if explicitly documented in the trust model.
- **Sibling admission is a trust-boundary change.** Auto-admitting any account-signed device is a self-compromise vector; admission must be gated (admin-signed transition or safety-number prompt) and mirrored in Go, or it widens attack surface. Given the same-peerId identity model, admission is also *largely inert* until distinct per-device keys exist — so ship B2 only with B1b, never alone.
- **Forward rotation on add (B5) adds latency/cost** to every member-add (a full key rotation + per-device distribution) and is only worthwhile if post-join secrecy is a stated goal; otherwise document the current "joiner gets current epoch" trust model explicitly instead.
- **Rollout:** flag `multiDeviceSync` default-off. Land A (reopen UX-013) → land B unit + harness behind flag → device-matrix verification recorded in `Test-Flight-Improv/` → only then enable the flag and re-close UX-013 with the contract test green. The contract test is the mechanical gate tying the doc claim to runtime reality.

## Effort estimate

| Work | Size | Notes |
|---|---|---|
| **Part A** — reopen UX-013, annotate policy, assert device-local seams, contract test, honest restore UI | **Small** (~1–2 days) | Pure doc/UX/test; no message-flow risk. This is the actual P2 deliverable. |
| **Part B1** — restore-time ML-KEM continuity (a) or device-announce (b) | **Medium–Large** | B1b couples to B2; B1a is a smaller but secrecy-weakening shortcut. |
| **Part B2/B3** — sibling admission + peer hydration (Dart + Go validator + config propagation + migration) | **Large** | Core convergence build; trust-gating and the Go mirror dominate the cost. |
| **Part B4** — per-device safety numbers | **Medium** | Only meaningful after B1b/B2. |
| **Part B5** — forward rotation on add | **Large** | Optional; reuses `rotateAndDistributeGroupKey`. |
| **Verification** — replace test-only mirror with real path; device matrix runs | **Medium** | Subject to known multi-device device-test blockers. |

**Recommendation:** ship **Part A now** (honest claim + guardrail) as the P2 deliverable; schedule **Part B** as a separately-planned large workstream gated behind `multiDeviceSync` and the contract test.
