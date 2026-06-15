# 121 — Group Message Lifecycle Bugs: Accept‑Open, Orbit Count, Removal‑Retain & Dissolve‑Convergence (TDD Plan)

Status: execution-ready
Date: 2026-06-13
Branch: 121-improvements
Source findings: a 3‑device field repro (Alice/Bob/Charlie, group `7893f932` "test") captured in `alice.log` / `bob.log` / `charlie.log` at the repo root, plus a 10‑agent graph‑first recon + adversarial‑verify workflow. Every load‑bearing claim below is **graph‑confirmed‑in‑source** (file:line) and cross‑checked against the device logs. Peer map: Alice=`12D3KooWSB` (admin/creator), Bob=`12D3KooWJ8`, Charlie=`12D3KooWF3`.
Related plans / memory (do NOT duplicate): `103-group-invite-acceptance-stale-metadata-recovery-*` (accept settlement — BUG1 navigation is downstream of it), `Group-Chat-Feature/Improvement-Review-2026-06/` (removal‑rotation P0 theme — BUG3), and the group-status/key-rotation infra mapped in §Shared infra.

---

## Field timeline (the four bugs in one session)

| t (UTC) | Event | Bug |
|---|---|---|
| 19:36:56 | Bob `PENDING_GROUP_INVITE_ACCEPT_START` → `GROUPS_DB_INSERT_SUCCESS`; conversation does **not** open until 19:36:59.6 via a separate `GROUP_CONV_FL_SCREEN_INIT` (manual re‑tap, 3.5 s gap) | **B1** |
| (render) | Bob roster: 1 contact (Alice) + 1 joined group ("test", 3 members) → Orbit "All" badge reads **1** | **B2** |
| 19:38:58 | Alice `GROUP_REMOVE_MEMBER_USE_CASE_BEGIN` (Bob); `member_removed` published `topicPeers:2`. Bob: `SELF_REMOVED` → `GROUP_MEMBERS/KEYS/GROUPS_DB_DELETE` (whole group wiped, no visible notice). Alice `GROUP_ROTATE_KEY_DONE newEpoch:2 distributedTo:1` (Charlie only; Bob excluded by design) | **B3** |
| 19:40:38 | Alice re‑invites Bob → Bob re‑accepts (`HANDLE_SUCCESS`) → live member again at dissolve time | — |
| 19:41:02 | Alice `GROUP_DISSOLVE_USE_CASE_BEGIN` → `group_dissolved` published `topicPeers:2`. Bob **and** Charlie: `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED type:group_dissolved reason:device_mismatch` (then `transport_mismatch`) → neither marks `isDissolved` | **B4** |
| 19:41:11–13 | Bob `GROUP_SEND_MSG_USE_CASE_SUCCESS` (msg "b"); Charlie `GROUP_HANDLE_INCOMING_MSG_SUCCESS text:'b'`; Charlie keeps `GROUP_REJOIN_TOPICS_JOINED memberCount:3` after dissolve | **B4** |

Only the dissolver (Alice) ever honored the dissolve (`GROUP_REJOIN_TOPICS_SKIP_DISSOLVED`).

---

## Problem statement

Four independent group‑lifecycle defects, all reproduced on device and confirmed in source:

- **B1 — accepting an invite does not open the group chat.** On `AcceptPendingGroupInviteResult.success` both wired handlers only show a "Joined …" SnackBar and refresh the list; **no `Navigator.push`** to `GroupConversationWired`. The use case already returns the fully‑committed `GroupModel`. (`orbit_wired.dart:1100‑1102`, `group_list_wired.dart:314‑318`.)
- **B2 — Orbit "All" badge excludes groups.** `activeCount: _activeFriends.length` counts 1:1 contacts only; the sibling `archivedCount` correctly adds `_archivedGroups.length`. 1 contact + 1 group renders two rows but reads "All 1". (`orbit_wired.dart:289` vs `:290`.)
- **B3 — removing a member hard‑deletes the group on the removed device.** When the removed member has no non‑`sys-` content (a quiet group), `_handleMemberRemoved`'s self branch runs `_deleteSelfRemovedLocalGroup` → `removeAllMembers` + `removeAllKeys` + **`deleteGroup`**, and `_emitGroupRemoved` pops the conversation to root. A backgrounded Bob never learns he was removed — the chat just vanishes; the only row written is an empty `status:'cutoff'` placeholder that is purged with the group. (`group_message_listener.dart:3084‑3142`, `:3242‑3260`.)
- **B4 — a dissolved group stays live for every member except the dissolver.** The dissolve is **rejected on receivers** at the signed‑transition‑audit gate (`device_mismatch`/`transport_mismatch`), so their local `isDissolved` never flips, and both the send gate (`send_group_message_use_case.dart:744`) and receive gate (`handle_incoming_group_message_use_case.dart:175`) — which key purely off local `isDissolved` — pass. Bob keeps sending and Charlie keeps receiving.

**Shared sub‑root‑cause behind B4 (and the related `key_rotated`/`members_added` rejections seen in the logs): a signed‑transition‑audit actor‑binding asymmetry.** The production dissolve call site signs the audit **without** `actorDeviceId`/`actorTransportPeerId`; the signer omits absent keys; the receiver then compares the **observed** live transport/device binding (always present, stamped by Go) against the **absent** signed binding and hard‑rejects. See §B4 and §Shared findings.

---

## Methodology — RED‑first, with mutation verification and harness reuse

1. **Behavioral bugs (B1, B3, B4)** get a genuine RED: a test that fails on HEAD for the documented reason, then passes after the production change. Each RED step names the exact HEAD failure and the GREEN production edit.
2. **Pure guards / one‑line value changes (B2)** additionally use a **mutation check**: after GREEN, revert the production edit and confirm the test goes RED again — a guard that survives its own mutation is worthless.
3. **Reuse existing harnesses** — `GroupTestUser` + `FakeGroupPubSubNetwork`, `InMemoryGroupRepository`/`InMemoryGroupMessageRepository`, the real `_OrbitWiredState`/`group_list_wired_test.dart` widget harnesses. **No new fakes are required.**
4. **Anti‑masking discipline (critical for B4):** existing dissolve tests pass *vacuously* (the listener test at `group_message_listener_test.dart:12170` builds `group_dissolved` with **no** `signedTransitionAudit` field, skipping the gate; `GroupTestUser.dissolveGroupViaBridge:703‑719` threads the binding **symmetrically** into both signer and transport). A new RED test **must deliberately recreate the production asymmetry** (sign with the binding absent while the observed transport binding is present) or it proves nothing.

---

## B2 (land first — trivial, de‑risks the rest): Orbit "All" badge counts groups

Root cause (confirmed): `orbit_wired.dart:289` `activeCount: _activeFriends.length` — friends only. State lists `_activeFriends`/`_activeGroups` are separate (`:198‑199`); the rendered All list `mergedItems` (`:273‑276`) DOES include `_activeGroups` (when `!_searchActive`); the badge flows `_buildListProjection` (`:289`) → `OrbitViewProjection.activeCount` → `orbit_screen.dart:433` → `friends_filter_toggle.dart:40` (`count: activeCount, showCount: true`). The next line `:290` already sums `_archivedFriends.length + _archivedGroups.length`, proving the omission is the asymmetry.

RED (new, in `test/features/orbit/presentation/screens/orbit_wired_test.dart` — drives the real `_OrbitWiredState`):
- `'All tab badge counts active friends plus active groups'` — seed exactly one active contact (`contactRepo.addContact(...)`, pattern at `:2563‑2564`) and one active group (`groupRepo.saveGroup(GroupModel(... myRole: GroupRole.admin))`, pattern at `:1604‑1614`); pump; assert `tester.widget<FriendsFilterToggle>(find.byType(FriendsFilterToggle)).activeCount == 2`. **Asserting the widget field, not rendered "2" text**, avoids matching incidental numerals. **HEAD fails**: `activeCount == _activeFriends.length == 1`.
- `'All badge equals merged active items for a groups‑only roster'` — 0 contacts + 2 active groups → assert `activeCount == 2` (HEAD = 0).

GREEN production change (single line):
- `orbit_wired.dart:289` → `activeCount: _activeFriends.length + _activeGroups.length,` (mirrors `:290`).
- **Mutation check:** revert to `_activeFriends.length` → both tests RED → reapply → GREEN.

Refactor notes / do‑NOT‑touch: leave `OrbitHeaderProjection.allFriends` (`:254`) and `OrbitViewProjection.allFriends` (`:285`) friends‑only — they feed the orbital ring/header intentionally. The simple sum is exact parity with `mergedItems` because the toggle (and badge) is hidden during search (`orbit_screen.dart:429`), so `_searchActive` never diverges the count. A `mergedItems.length`‑derived count is marginally more future‑proof but unnecessary and inconsistent with the existing `archivedCount` style.

---

## B1: accepting a group invite auto‑opens the group conversation

Root cause (confirmed): `_onAcceptPendingInvite` success case shows a SnackBar and `break`s with no navigation — `orbit_wired.dart:1100‑1102` (literal `_showSnackBar('Joined ${group?.name ?? invite.groupName}')`) and `group_list_wired.dart:314‑318` (l10n `_showSnackBar(l10n.group_invite_joined(group?.name ?? invite.groupName))`). The use case returns the committed group: `acceptPendingGroupInvite` → `(success, group)` at `accept_pending_group_invite_use_case.dart:366` (`group = getGroup(acceptedId)` at `:331`) and `(success|bridgeError, group)` at `:442‑446`. `GroupConversationWired.group` is a `GroupModel` (`group_conversation_wired.dart:122`), so the returned model passes directly. Navigation templates already exist: `_onGroupTap` at `orbit_wired.dart:2010‑2044` (takes `OrbitGroup`, passes `group.group`) and `group_list_wired.dart:241‑273` (takes `GroupModel` directly).

> **MANDATORY correctness note:** the `:366` success return is **not** guarded by `group != null`, so success can carry a null group (drain rollback at `:338‑344`). The fix's `if (group != null && mounted)` guard is **required**, not defensive.

RED (mutation‑genuine; reuse the mature accept harnesses):
1. `group_list_wired_test.dart` → `'accepting a pending invite auto‑opens the group conversation'` — extend the existing real success‑accept at `:727‑816` (taps `ValueKey('pending-group-invite-accept-<id>')`, ends in `find.text('Joined Book Club')`); after pump add `expect(find.byType(GroupConversationScreen), findsOneWidget)` (the exact assertion the tap‑to‑navigate test at `:1136‑1148` already uses). **HEAD fails** — success case never pushes.
2. `orbit_wired_test.dart` → `'accepting a pending group invite auto‑opens GroupConversationWired'` — extend the "Joined Writers Room" success test at `:2911‑2924`; assert `expect(find.byType(GroupConversationWired), findsOneWidget)` (assertion already used by the `_onGroupTap` nav tests at `:3415` / `:3510`). **HEAD fails.**
3. `group_list_wired_test.dart` → `'non‑success accept does NOT open a conversation'` (anti‑regression, **green on HEAD, must stay green**) — drive a `notFound`/`repairPending` result (pattern around `:1075‑1107`) and assert `find.byType(GroupConversationScreen)` is `findsNothing`. Locks the push strictly inside the `success` branch.

GREEN production change — extract a shared `void _openGroupChat(GroupModel group)` in each wired screen that performs the `Navigator.push(MaterialPageRoute(builder: (_) => GroupConversationWired(group: group, ...)))` using the **exact** arg set from that screen's `_onGroupTap`, plus the existing post‑pop refresh (`.then(() { _markGroupChanged(group.id); unawaited(_refreshOrbitGroup(group.id)); })` on orbit; `.then(() { _changedGroupIds.add(group.id); _loadGroups(); })` on group list). Call it from the `success` case behind `if (group != null && mounted)`:
- `orbit_wired.dart:1100‑1102` — pass the returned `GroupModel` directly (there is no `OrbitGroup` here; do **not** write `group.group`). The orbit helper must source `groupInviteDeliveryAttemptRepository` (`:2018‑2019`) and `historyGapRepairRepo` (`:2034`) from `widget` fields, matching `_onGroupTap` exactly.
- `group_list_wired.dart:314‑318` — `_onGroupTap` here already takes a `GroupModel`; mirror its arg set precisely (note it does **not** pass `historyGapRepairRepo`) so an auto‑opened chat is configured identically to a manually‑tapped one.

Refactor notes / risks: keep the push **inside** the `success` case (not a post‑`switch` block) so non‑success never navigates. The handler already does `if (!mounted) return;` before the switch (`orbit_wired.dart:1097` / `group_list_wired.dart:308`); the helper must not re‑`await` before pushing. Use `push` (consistent with `_onGroupTap`), not `pushReplacement`.

Open decisions (OQ‑B1): (a) keep or drop the "Joined …" SnackBar once the chat auto‑opens (recommend drop); (b) the use case can return `(bridgeError, group!=null)` at `:442‑446` — today both bridgeError branches show "Failed to accept" and won't auto‑open even when a usable group exists; auto‑opening that partial‑success is **out of scope** here but should be a documented decision.

---

## B3: removing a member retains a read‑only group with a visible "Alice removed Bob" notice

Root cause (confirmed): `_handleMemberRemoved` self branch (`group_message_listener.dart:3046‑3143`) gates delete‑vs‑keep on `_hasRetainableSelfRemovalHistory` (`:3262‑3282`), which returns true only when a message id does **not** start with `sys-` (`:3274`). On a quiet group it is false → `_deleteSelfRemovedLocalGroup` (`:3242‑3260`) runs `callGroupLeave` + `removeAllMembers` + `removeAllKeys` + **`deleteGroup`**, and the only row written is an empty `status:'cutoff'` placeholder (`:3107‑3124`, id prefix `sys-member_removed_cutoff:`) that is purged with the group. `_emitGroupRemoved` (`:3141`) → `groupRemovedStream` (`:192`) → `group_conversation_wired.dart:1372` → `_handleCurrentGroupRemoved` (`:1426‑1439`) → `Navigator.popUntil(isFirst)` pops the card.

> **Two corrections that shrink the fix dramatically:**
> 1. **The retain path already does the right thing.** `_retainSelfRemovedLocalHistory` (`:3284‑3349`) keeps the group row and writes the **visible** `buildMemberRemovedTimelineMessage` for self (`:3320‑3332`). The bug is purely that (a) the **delete** path is taken for quiet groups and (b) even the retain path still fires `_emitGroupRemoved`, which pops the UI. The fix unifies onto the retain behavior and softens the removed‑signal — it does **not** invent new logic.
> 2. **Read‑only needs NO new flag or DB migration.** `_canWriteForGroup` (`group_conversation_wired.dart:4113‑4131`) already returns false when `!_isCurrentUserActiveMember` (`:4117`, derived from `members.any(self)` at `:1166‑1169`) or `!_hasCurrentSendKey` (`:4120`). Both become true once self+keys are removed but the **group row is kept**, so the composer auto‑disables. A new `GroupModel` "removed/left" flag (+ migration) is **optional**, only for a distinct "You were removed" banner vs the generic disabled composer.

Remaining members are already correct: the non‑self branch (`:3146‑3240`) emits the visible "Alice removed Bob" timeline message (`buildMemberRemovedTimelineMessage`, `group_membership_timeline_message.dart:109`).

RED:
1. `group_message_listener_test.dart` → `'self member_removed keeps the group row and emits a visible self‑removal timeline message'` — mirror the existing self‑removal setup (PGC‑008 / `pgc008-self-removal` at `:3562‑3605`: `getSelfPeerId 'peer-self'`, `saveSelfMember`, **no content messages**). After feeding the `member_removed` `__sys` for self, assert (a) `getGroup('group-1')` is `isNotNull` and (b) `getMessagesPage` contains a row `id.startsWith('sys-member_removed:')` with non‑empty text ("Admin removed Self"). **HEAD fails** — quiet‑group path deletes the group (`removeAllMembers`/`removeAllKeys`/`deleteGroup` at `:3256‑3258`) and writes only the empty cutoff placeholder.
2. `member_removal_integration_test.dart` → `'self‑removal on a quiet group retains the group and writes a visible removal message'` — reuse the setup of `'direct membership update applies removal replay without relay drain'` (test starts `:420`, only members+key, no content). Assert `getGroup(groupId)` `isNotNull`. **HEAD fails at the existing `:552` assertion which expects `isNull`** — that assertion is **inverted** by this fix. (Correction: the `:684` `isNotNull` assertion is the impostor‑signature‑rejected test at `:560`, **not** a retain‑path test — do not treat it as precedent.)
3. `group_conversation_wired_test.dart` → `'current group removal keeps the conversation open in read‑only mode and shows the removal message'` — adapt the existing widget test at `:5533‑5591`. With `msgRepo` seeded with a `sys-member_removed:` row and self absent from members, after `removedStreamController.add(group.id)` assert the route **stays** (`find.byType(GroupConversationScreen)` `findsOneWidget`), the composer is read‑only, and the removal bubble is visible. **HEAD fails** — `_handleCurrentGroupRemoved` pops via `Navigator.popUntil(isFirst)` (`:1438`); the current test asserts `findsNothing` at `:5586` (also inverted by this fix).
4. `member_removal_integration_test.dart` → `'removed member can no longer send'` — after the retained self‑removal, assert `getMember(groupId, self)` `isNull` AND `getLatestKey(groupId)` `isNull` (send path fail‑closed) while `getGroup(groupId)` stays non‑null. **HEAD fails** — the whole group (and these query targets) is gone.
5. `member_removal_integration_test.dart` → `'re‑add after retained self‑removal restores active membership'` — self removed (retained) then a `members_added` re‑add `__sys` for self arrives; assert `getGroup` stays non‑null throughout and `_isCurrentUserActiveMember` becomes true again, without `_handleMemberRemoved`'s early‑return swallowing the re‑add. Protects the existing GM‑019 re‑add behavior.

GREEN production change:
- `group_message_listener.dart:3084‑3142` — drop the delete branch; route **all** self‑removals through retain behavior: keep the group row, `removeMember(self)` + `removeAllKeys` + `callGroupLeave`, and write the **visible** `buildMemberRemovedTimelineMessage` for self (copy `:3320‑3332`) instead of the empty cutoff placeholder.
- `group_message_listener.dart:3242‑3260` — stop calling `deleteGroup` (and `removeAllMembers`); keep only `removeMember(self)` + `removeAllKeys` + `callGroupLeave`. (Or delete this method and unify both branches onto `_retainSelfRemovedLocalHistory`.)
- `group_message_listener.dart:3262‑3282` — `_hasRetainableSelfRemovalHistory` no longer decides delete‑vs‑keep (always keep).
- `group_message_listener.dart:188‑192, 327‑335` — repurpose `_emitGroupRemoved`/`groupRemovedStream` as a **soft** "you‑were‑removed" signal (or stop emitting), so the UI no longer pops.
- `group_conversation_wired.dart:1426‑1439` — `_handleCurrentGroupRemoved` must **not** pop; reload messages so the removal bubble shows and let `_canWriteForGroup` gate the composer read‑only. Keep/adjust the snackbar.
- `group_conversation_wired.dart:4113‑4131` — **no change required** (auto‑gates). Optional banner state only if product wants distinct UX.

Refactor notes / risks:
- `_deleteContentMessagesAtOrAfterRemoval` (called at `:3217` non‑self and `:3334` retain) must still purge post‑removal content so Bob can't see traffic after the cutoff — but must **not** purge the new removal message (verify its `removedAt` timestamp vs the `_recordMembershipEventWatermark` cutoff ordering).
- `_repairLateSelfRemovalLeaveIfReadded` (`:3249‑3253` delete / `:3296‑3300` retain): keeping the row likely **simplifies** re‑add (no resurrection), but preserve the `selfRemovalCompleted=false → skip _emitGroupRemoved` semantics so a re‑added Bob is not shown as removed.
- There is **no `isSystemMessage` column**; `sys-member_removed:` rows render through the normal letter‑card path (`group_conversation_wired.dart:1355‑1361` only special‑cases metadata/dissolved for refresh) — verify the removal row is not filtered out anywhere.
- Existing UI test at `group_conversation_wired_test.dart:5593‑5648` (old‑group removal must not clear a newer active group key) must stay consistent with the soft‑signal semantics.

Encryption‑key rotation on removal (the bug's "key should be rotated" requirement): **already satisfied for the creator‑admin removal flow** — `group_info_wired.dart` publishes `member_removed` first (`:937`) then `rotateAndDistributeGroupKey` (`:1015`); the device log shows epoch 1→2 distributed to remaining members (`distributedTo:1` = Charlie), with Bob excluded by design (he is no longer a member). `removeGroupMember` deliberately does **not** rotate (`remove_group_member_use_case.dart:39‑41`); rotation hard‑requires `group.createdBy == selfPeerId` (`rotate_and_distribute_group_key_use_case.dart:84`). **Decision (OQ‑B3):** keeping rotation in the admin UI is acceptable since it is the only removal UI; "guarantee rotation on every removal entry point" is a separate hardening, and a **non‑creator admin has no rotator today** (a real gap to track, not in this plan's core scope).

---

## B4: a dissolved group converges to `isDissolved=true` on every member (no send / no receive)

Root cause (confirmed, definitive — the field trigger is NOT offline/relay‑delete and NOT a roster‑role gap; the authorization gate passed):
1. Production dissolve entry `group_info_wired.dart:485‑494` calls `dissolveGroup` **without** `actorDeviceId`/`actorTransportPeerId`.
2. `signGroupTransitionAudit` (`signed_group_transition_audit.dart:136‑141`) **omits** `deviceId`/`transportPeerId` from the signed `actor` map when null/empty → Alice's signed audit has no device/transport binding.
3. On receipt, `group_message_listener.dart:1802‑1803` passes `expectedAuditActorBinding.deviceId/.transportPeerId` derived from the **observed** live envelope (`:755‑758`, stamped by Go via `go_bridge_client.dart`) as the **expected** values — these are non‑empty.
4. `group_dissolved` is **not** in `_allowsSnapshotBackedSystemSender` (`:2504‑2508` lists only `group_metadata_updated`, `members_added`, `member_role_updated`), so `_expectedSignedAuditActorBindingForSystemEvent` short‑circuits (`:2243‑2244`) to the raw observed `defaultBinding` — no reconciliation.
5. `verifyGroupTransitionAudit:235‑244` rejects observed‑present‑vs‑signed‑absent → `device_mismatch` then `transport_mismatch`.
6. `_handleGroupDissolved` (`:4005‑4065`) — the **only** non‑admin writer of `isDissolved=true` (`:4018‑4025`) — never runs.
7. Send gate `send_group_message_use_case.dart:744‑756` and receive gate `handle_incoming_group_message_use_case.dart:174‑187` both key off the local flag → both pass.
8. `rejoin_group_topics_use_case.dart:75‑78` only **reads** local `isDissolved` (`SKIP_DISSOLVED`) and otherwise re‑joins the live topic → Charlie keeps `memberCount:3` after dissolve. **No reconciliation path re‑derives dissolved state.**

This same signer/receiver asymmetry is the family behind the log's `key_rotated`/`members_added` `payload_mismatch` rejections (see §Shared findings) — though those have a different reason code and are lower severity.

### Fix (choose A as primary; B is defense‑in‑depth)

- **Option A (PRIMARY — production‑parity, lowest risk): sign the binding at the dissolve call site.** `group_info_wired.dart:485‑494` — pass `actorDeviceId`/`actorTransportPeerId` into `dissolveGroup` (the local device id + the transport peer id Go stamps on outbound group system messages), mirroring how the `members_added`/`member_role_updated`/`group_metadata_updated` sibling flows source the actor binding. Then Alice signs the **same** binding receivers observe live and the audit validates.
- **Option B (defense‑in‑depth / alternative): receiver‑side reconciliation.** Add `'group_dissolved'` to `_allowsSnapshotBackedSystemSender` (`group_message_listener.dart:2504‑2508`) so the snapshot‑backed binding reconciliation in `_expectedSignedAuditActorBindingForSystemEvent` (`:2231‑2295`) applies to dissolve — the same reconciliation that already protects the sibling membership events. Pair with verifying the bootstrap helpers (`_canBootstrapSnapshotBackedSignedAuditActorDevice:2298‑2323`, `_canAcceptLegacySnapshotBackedAccountSender:2325‑`) accept the dissolver.
- **Do NOT loosen the verifier** at `signed_group_transition_audit.dart:235‑244` — the strict binding check is correct; the asymmetry must be fixed at the signer (A) or the expected‑binding computation (B). A genuinely forged/non‑binding dissolve must still reject.
- **Optional fail‑safe (recommended, additive):** the admin‑role authorization gate (`:2589‑2590`) already runs first; keep it. As belt‑and‑suspenders, the send/receive gates may also block when there is positive evidence of dissolution even if the flag didn't commit — but the **root fix is convergence of `isDissolved`**, not gate hardening.

RED (must recreate the production asymmetry — existing tests mask it):
1. `group_message_listener_test.dart` → `'group_dissolved with absent signed binding but observed live transportPeerId is REJECTED on HEAD and APPLIED after fix'` — build a `group_dissolved` `__sys` whose `signedTransitionAudit` is signed with `actorDeviceId`/`actorTransportPeerId = null` (matching `group_info_wired.dart:485`), wire `_appendGroupEventLogEntry` so the audit branch is required, and feed an envelope carrying a **non‑empty** `transportPeerId`/`senderDeviceId` (as the live Go path does). **HEAD fails the intended way:** assert `group.isDissolved == false` and a `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED type:group_dissolved` event is emitted. After fix: same envelope → assert `isDissolved == true`, `dissolvedBy` set, **no** rejection. **Plus a paired negative:** a genuinely forged/non‑admin or non‑snapshot‑backed dissolve still rejects. *(The existing dissolve test at `:12170‑12212` has no `signedTransitionAudit` field and passes vacuously — the new test MUST include it.)*
2. `dissolve_group_use_case_test.dart` → `'dissolveGroup without actor binding signs an audit whose actor OMITS device/transport (production parity)'` — call `dissolveGroup` exactly as production (no `actorDeviceId`/`actorTransportPeerId`), decode the published `group_dissolved` `signedTransitionAudit.signedPayload`, and assert (for the FIX direction) the actor **should** carry the binding → **HEAD fails** because the UI passes nothing and the signer omits absent keys (`signed_group_transition_audit.dart:136‑141`). (If Option B is chosen, reframe this as a documentation/guard test.)
3. `group_membership_smoke_test.dart` (integration) → `'admin dissolve with asymmetric binding → Bob cannot send and Charlie cannot receive'` — `GroupTestUser` + `FakeGroupPubSubNetwork`; force the asymmetry by calling `dissolveGroup` directly with `actorDeviceId`/`actorTransportPeerId = null` while the fake network still delivers with `senderDeviceId`/`transportPeerId` set. **HEAD**: Bob/Charlie `isDissolved` stay false → Bob's `sendGroupMessage` returns `success` (not `groupDissolved`) and Charlie's `handleIncoming` renders the post‑dissolve message — reproducing the logs. After fix: Bob send → `SendGroupMessageResult.groupDissolved`; Charlie `handleIncoming` drops at/after `dissolvedAt`; Charlie does **not** `GROUP_REJOIN_TOPICS_JOINED` for the dissolved group. **Do NOT use `dissolveGroupViaBridge` (`group_test_user.dart:703‑719`)** — it threads the binding symmetrically and masks the bug.
4. *(Option B only)* `group_message_listener_test.dart` → `'_expectedSignedAuditActorBindingForSystemEvent for group_dissolved reconciles to the snapshot/signed binding'` — assert that with a member whose stored device snapshot matches the signed actor, the expected binding is reconciled rather than the raw observed `defaultBinding`. HEAD fails (short‑circuit at `:2243‑2244`); GREEN after adding `group_dissolved` to `_allowsSnapshotBackedSystemSender`.

GREEN production change: Option A — thread the binding through `group_info_wired.dart:485‑494` → `dissolveGroup`. (Or Option B — the one‑word `_allowsSnapshotBackedSystemSender` addition + bootstrap verification.)

Refactor notes / risks:
- Option A changes the **wire/audit content** of `group_dissolved`. Confirm the value Alice signs as `actorTransportPeerId` equals what Go stamps as the receiver‑observed `transportPeerId`, or the mismatch merely inverts. Update any fixture that hand‑builds a `group_dissolved` audit without the binding.
- Option B widens snapshot‑bootstrap acceptance to dissolve; the admin‑role gate (`:2589‑2590`) still runs first, but test the interaction so a non‑admin/stale forged dissolve cannot slip through.
- Convergence race: until `isDissolved` commits, `rejoin_group_topics_use_case.dart:75‑78` self‑heals the dead group (observed in `charlie.log`). The fix must make first‑receipt apply the dissolve reliably; if a reconciliation/recovery sweep is added later, it should re‑apply dissolved state when a durable/relayed `group_dissolved` is drained.
- **No assertion is masked silently:** the integration RED only proves the fix if it avoids `dissolveGroupViaBridge` and the unit RED only proves it with a real `signedTransitionAudit` present.

---

## Shared findings & related hardening (not blockers; track separately)

- **Signed‑audit actor‑binding asymmetry is a family bug.** The logs show Charlie also rejecting `key_rotated` (`payload_mismatch`, `charlie.log:2290`) and `members_added` (`payload_mismatch`, `charlie.log:2658`). `members_added` IS in `_allowsSnapshotBackedSystemSender` yet still failed — that is a **subject/`groupConfigHash` mismatch** (different from B4's device/transport binding), i.e. the receiver's reconstructed `expectedTransitionSubject` (`buildGroupSystemTransitionSubject(parsed)`, `signed_group_transition_audit.dart:305‑372`) does not canonically equal what the admin signed. Worth a focused follow‑up; out of scope for the four reported bugs.
- **`key_rotated` rejection ≠ key not delivered.** The actual rotated key is distributed 1:1 via `group_key_update` envelopes inside `rotateAndDistributeGroupKey`; the `key_rotated` `__sys` is only a broadcast **notice**. So B3's "key rotated" requirement is met even though Charlie rejected the notice audit. The notice‑audit rejection is the same asymmetry family, lower severity.
- **No status enum.** Group lifecycle is boolean+timestamp columns: `is_dissolved`/`dissolved_at`/`dissolved_by` (migration `052`), `is_archived`/`archived_at`; "I was removed" is **derived** (no own row in `group_members` + `member_removed` timeline + `removed_group_member_snapshots`, migration `068`). Two look‑alike role enums: `GroupModel.GroupRole{admin,member}` (local `my_role`) vs `MemberRole{admin,writer,reader}` (per member). Any new flag (optional B3 banner) needs a migration in the `lib/core/database/migrations/` pattern + `fromMap`/`toMap`/`copyWith` updates.

---

## Recommended landing order

1. **B2** — one‑line value fix + 2 widget tests + mutation check. Quick, isolated, de‑risks.
2. **B1** — additive navigation; shared `_openGroupChat` helper; 3 widget tests across both surfaces. No interaction with B2.
3. **B4** — well‑isolated signer fix (Option A) + 1 unit + 1 use‑case + 1 integration RED. Security‑sensitive but the asymmetry fix is targeted; do before B3 so the dissolve convergence is provably correct.
4. **B3** — most cross‑cutting: inverts two existing assertions (`member_removal_integration_test.dart:552`, `group_conversation_wired_test.dart:5586`), softens `groupRemovedStream` semantics, touches the conversation UI. Land last with the full RED set (5 tests) and the documented test inversions.

All four are independent in source (B3 and B4 touch different regions of `group_message_listener.dart`); the order above optimizes risk, not dependency.

## Gate / acceptance per phase

- Per phase: the listed RED tests fail on HEAD for the documented reason, pass after the GREEN edit; B2 also passes its revert‑mutation check.
- Suite gates (run `-j 1` to avoid the known shared‑global‑gate parallel flake): `flutter test test/features/groups/` and `test/features/orbit/`, plus `dart analyze` showing zero new issues.
- Device re‑verification (Pixel↔iPhone, the same 3‑device scenario): accept→auto‑open; "All" badge counts the group; admin‑remove leaves a read‑only "Alice removed Bob" bubble on the removed device with the composer disabled; admin‑dissolve blocks Bob's send and Charlie's receive (`GROUP_REJOIN_TOPICS_SKIP_DISSOLVED` on every member). Capture fresh `alice/bob/charlie.log`.

## Open questions (owner decisions)

- **OQ‑B1:** keep or drop the "Joined …" SnackBar on auto‑open? Auto‑open on `(bridgeError, group!=null)` partial success (`:442‑446`) — in or out?
- **OQ‑B3:** add a distinct "You were removed" banner + `GroupModel` flag/migration, or rely on the generic disabled composer (no migration)? Should a removed user be able to manually delete/leave the retained group, or must it persist until acted on?
- **OQ‑B4:** Option A (sign the binding at the dissolve call site) vs Option B (receiver snapshot reconciliation) vs both? Add the send/receive fail‑safe gates as defense‑in‑depth, or rely solely on `isDissolved` convergence?
- **Cross‑cutting:** schedule the `members_added`/`key_rotated` `payload_mismatch` (subject‑hash) follow‑up and the non‑creator‑admin rotation gap as separate items?

---

### Evidence appendix (device‑log anchors)

- **B1:** `bob.log` @19:36:56.132 `PENDING_GROUP_INVITE_ACCEPT_START` → @19:36:56.192 `GROUP_INVITE_HANDLE_SUCCESS`; conversation `GROUP_CONV_FL_SCREEN_INIT` not until @19:36:59.677 (3.5 s gap, no navigation events between). Same pattern on the second accept.
- **B2:** `bob.log` @19:35:01 single `CONTACT_REQUEST_ACCEPT_SUCCESS` (Alice); @19:36:59.831 `CONTACTS_DB_LOAD_NOT_FOUND` (Charlie — co‑member, not a contact); @19:36:59.798 `GROUP_MEMBERS_DB_LOAD_ALL_SUCCESS count:3` (group renders) → badge tracks the friends table, not membership.
- **B3:** `bob.log` @19:38:58.534 `GROUP_MESSAGE_LISTENER_SELF_REMOVED` → @19:38:58.567‑.597 `GROUP_MEMBERS_DB_DELETE_ALL` / `GROUP_KEYS_DB_DELETE_ALL` / `GROUPS_DB_DELETE id:7893f932`; @19:38:58.621 `GROUPS_DB_LOAD_NOT_FOUND` (gone). `alice.log` @19:38:58.69 `GROUP_ROTATE_KEY_DONE newEpoch:2 distributedTo:1`.
- **B4:** `bob.log`/`charlie.log` @19:41:02.9 `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED type:group_dissolved reason:device_mismatch` (then `transport_mismatch`); `bob.log` @19:41:11‑13 `GROUP_SEND_MSG_USE_CASE_SUCCESS`; `charlie.log` @19:41:13 `GROUP_HANDLE_INCOMING_MSG_SUCCESS text:'b'`, @19:41:27/56/+ `GROUP_REJOIN_TOPICS_JOINED memberCount:3`. `alice.log` @19:41:02 `GROUP_DISSOLVE_USE_CASE_BEGIN`/`_SUCCESS recipientCount:2`, @—`GROUP_REJOIN_TOPICS_SKIP_DISSOLVED` (only the dissolver honors it).
