# 122 — Group Lifecycle Round 2: Whole-Row Select, Removal Fail-Closed, Re-add Restore, Roster Truthfulness & Dissolve Convergence (TDD Plan)

Status: execution-ready
Date: 2026-06-14
Branch: 121-improvements (the "121" fixes are IMPLEMENTED but **uncommitted** in the working tree; HEAD = commit `c79a0fa7` predates them)
Source findings: a fresh 3-device field repro (Alice=admin/creator, Bob=removed-then-re-added, Charlie=stays) for group `cdd05122`, captured 2026-06-14 in `alice.log` / `bob.log` / `charlie.log` at the repo root, plus an 8-thread graph-first recon + adversarial-verify workflow (every load-bearing claim below is graph-confirmed-in-source at file:line and cross-checked against the device logs). The decisive B4 relaxation mechanism was additionally hand-verified in source.
Predecessor (do NOT duplicate; this plan CORRECTS two of its conclusions): `Test-Flight-Improv/121-group-message-invite-removal-dissolve-tdd-plan.md`.

---

## Headline — this is NOT a build-skew problem; the 121 fixes shipped but are incomplete

My first hypothesis was build skew (the device ran a build older than the working tree). **That is refuted with hard evidence.** The Jun 14 run executed the uncommitted 121 working tree (at least the Dart/Flutter side):

- **Proof = a CHANGED failure mode, not a fixed one.** The 121 field run rejected `group_dissolved` with reason `device_mismatch` then `transport_mismatch`. The Jun 14 logs contain **zero** `device_mismatch`/`transport_mismatch` in any of the three logs; instead Charlie now rejects `group_dissolved` with reason **`previous_transition_hash_mismatch`** (`charlie.log` @08:03:07.807 and @08:03:23.936). In the verifier (`signed_group_transition_audit.dart:235-252`) the device/transport-binding checks run **before** the pre-transition-hash check — reaching `previous_transition_hash_mismatch` is only possible once the signed binding already matched the observed binding, which proves the working-tree **Option-A signer fix ran on device**.
- **B3 retain also ran.** `bob.log` routes the self-removal of `cdd05122` @07:59:11.729 through `GROUP_MESSAGE_LISTENER_SELF_REMOVED_HISTORY_RETAINED` with **no** `GROUPS_DB_DELETE` for `cdd05122` (the lone `GROUPS_DB_DELETE id:7893f932` @07:56:05 is the *prior* session's group, cleaned up before this run — do not misattribute it).

So the 121 B3/B4 fixes are **live but incomplete**, and three of the five reported bugs are real residual gaps (not regressions, not skew). Two reported items are NOT bugs in current code: Bug 2's security posture is already correct, and Bug 1 is a genuinely new UI defect untouched by 121.

### Mapping the five reported bugs

| # | Reported symptom | Verdict | Working-tree status |
|---|---|---|---|
| 1 | Group-creation member rows: only the **name** is tappable; whole row should select | **New UI bug** | not-addressed (net-new) |
| 2 | After removal: were keys rotated? could a removed Bob still send via a hidden composer? | **Already correct** — keys rotated, removed member fail-closed at every layer | fixed (coverage-only gap) |
| 3 | Re-added Bob gets no intro, can't read new messages, composer stays hidden | **Real residual** — re-add invite dropped at the wrong layer; 121 fixed a dead wrapper | partially-fixed (wrong layer) |
| 3.1 | Alice's group settings shows Bob "joined" when he is not | **Real bug** — admin counts her *own* add as join confirmation | not-addressed |
| 4 | Dissolve: Charlie gets no notice and keeps a live composer | **Real residual** — Option A landed (binding fixed) but convergence still fails via a DIFFERENT gate | partially-fixed (Option A only; Option B as written cannot fix it) |

A sixth, cross-cutting defect (compose-bar recompute wiring) underlies 2/3/4 and is tracked as **B5**; test-coverage + a build-provenance gate are **B6**.

---

## Field timeline (group `cdd05122`, 2026-06-14, UTC)

| t (UTC) | Event | Bug |
|---|---|---|
| 07:58:50–51 | Alice `MEMBER_JOINED` for Bob & Charlie (epoch 1) | — |
| 07:58:59 / 07:59:03 | Group active: messages "a", "c" delivered to Bob | — |
| 07:59:11.729 | Alice removes Bob → Bob `SELF_REMOVED` → `SELF_REMOVED_HISTORY_RETAINED` (group **retained**, no delete of `cdd05122`) | B2/B3 |
| 07:59:11.804 | Alice `GROUP_ROTATE_KEY_DONE` epoch 1→2, `distributedTo:1` (Charlie only; Bob excluded by design), `topicPeers:1` | B2 |
| 07:59:11.867 | Charlie rejects `key_rotated` audit notice with `payload_mismatch` (got the real key 1:1 → reaches epoch 2) | B4 (family) |
| 08:00:40.493 | Alice re-adds Bob `GROUP_ADD_MEMBER_USE_CASE_SUCCESS`; re-invite `SEND_START`→`SUCCESS` @08:00:41.6/42.0 | B3 |
| 08:00:41.602 | Charlie rejects one `members_added` audit (`payload_mismatch`); **applies** another @08:00:41.717 (`count:1`→`memberCount:3`) | B4 (family) |
| 08:00:41.701 | **Bob drops the re-invite**: `GROUP_INVITE_STORE_PENDING_DUPLICATE_GROUP` (retained shell already exists) | **B3** |
| 07:59:27 → 08:03:57 | Bob repeatedly `GROUP_REJOIN_TOPICS_SKIP_NO_KEY` for `cdd05122` — never rejoined the topic, never got epoch-2 key | **B3** |
| 08:03:07.807 / 08:03:23.936 | Alice `GROUP_DISSOLVE_USE_CASE_SUCCESS recipientCount:2` (`topicPeers:1`); Charlie rejects `group_dissolved` with **`previous_transition_hash_mismatch`** → `isDissolved` never flips | **B4** |
| 08:03:23 / 08:03:53 | Charlie keeps `GROUP_REJOIN_TOPICS_JOINED` (never `SKIP_DISSOLVED`); only Alice honors the dissolve | **B4** |

Two distinct dissolve-miss mechanisms in this run: **Charlie** = `previous_transition_hash_mismatch` (state-hash divergence with a known admin device); **Bob** = never a live member after re-add (keyless shell, `SKIP_NO_KEY`) so he never received the dissolve at all. Bob's miss is a *consequence of B3* — fixing B3 makes Bob a live member who receives the dissolve.

---

## Methodology — RED-first, mutation-checked, masking-aware

1. Behavioral bugs (B1, B3, B4, B5) get a genuine RED: fails on the current working tree for the documented reason, passes after the GREEN edit. Each RED names the exact current failure and the production edit.
2. Pure guards / already-correct invariants (B2 rotation/fail-closed) use **mutation checks** (revert the invariant → test goes RED) since they pass on current code; they are coverage locks, not behavioral REDs. Label them as such — do not pretend a coverage test is a behavioral RED.
3. **Anti-masking discipline (critical for B4):** every existing dissolve unit test bypasses `verifyGroupTransitionAudit` (`group_message_listener_test.dart` references `group_dissolved` 17×, `signedTransitionAudit` 0×), and `dissolveGroupViaBridge` (`group_test_user.dart:702-748`) threads the binding **symmetrically** so signer==observed and the pre-hash always matches. A new RED MUST recreate the field divergence: a **known active admin device** (so device/transport pass and we exercise `previous_transition_hash_mismatch`, not `device_mismatch`) **plus a diverged local transition-state hash**. Use `GroupTestUser` + `FakeGroupPubSubNetwork`, not the masking bridge helper.
4. Reuse existing harnesses (`GroupTestUser`, `FakeGroupPubSubNetwork`, `InMemoryGroupRepository`, the real wired widget harnesses). No new fakes required.
5. Widget-test gotchas in this codebase: use the screen test files' existing `pumpFrames` helper, **never `pumpAndSettle`** (the `AmbientBackground` animation never settles); use **sync** dart:io in `testWidgets`.

---

## B1 (land first — isolated, trivial, no risk): whole-row member selection

**Root cause (confirmed):** the selectable friend row is `ContactPickerRow`, whose tap target is a `GestureDetector` with the **default `HitTestBehavior.deferToChild`** (`lib/features/groups/presentation/widgets/contact_picker_row.dart:32-34` — `return GestureDetector(onTap: onTap, child: Padding(...))`, no `behavior:`). `deferToChild` only registers a hit over a *painted* child (the name `Text`, avatar, trailing icon); the transparent gaps in the row (padding band, empty space right of a short name) are not hit-tested, so taps there do nothing. The user's "I have to tap the name" is exactly this. The selected-state affordance already exists (`check_circle` vs `add_circle_outline` at `:65-69`) and needs no change.

`ContactPickerRow` is shared, so a single fix corrects **both** consumers: the group-creation picker (`create_group_picker_screen.dart:292-296`) and the add-members picker (`contact_picker_screen.dart:291-295`).

**GREEN production change (one line):**
- `contact_picker_row.dart` — insert `behavior: HitTestBehavior.opaque,` into the `GestureDetector` (between `onTap: onTap,` and `child: Padding(`), making the entire row rectangle one tap target. Mirrors the established in-repo idiom at `friend_picker_screen.dart:290` and `group_card.dart:42`.

**RED tests:**
1. `test/features/groups/presentation/widgets/contact_picker_row_test.dart` → `'ContactPickerRow.onTap fires when an empty (non-name) region of the row is tapped'`. **Geometry caveat (mandatory):** wrap the row at a realistic height (≈52px ListView row), not as the sole Scaffold body (which expands to the full 800×600 surface and makes almost any tap land on a child). Give the row a short username so there is genuine transparent space, then `tester.tapAt` an offset measured inside the row rect but over an unpainted area; assert the `onTap` callback fired. **Current code fails** (`deferToChild` → no hit on the gap).
2. `test/features/groups/presentation/create_group_picker_screen_test.dart` → `'tapping a contact row''s empty region toggles selection'`. Use the file's existing `pumpFrames` helper (never `pumpAndSettle`). Pump with one contact, `tester.getRect(find.byType(ContactPickerRow).first)`, tap a non-name offset, assert selection toggled. **Current code fails.**
3. Anti-regression (stays green): tapping the name still toggles selection (locks that the opaque change doesn't break the existing target).

**Open decision (OQ-B1):** plain `HitTestBehavior.opaque` (matches sibling idiom) vs an `InkWell`/`Material` ripple for tactile feedback. Recommend `opaque` for consistency; ripple is a separate UX polish.

---

## B2: removal already fails-closed — answer the security question, then lock it with coverage

**The user's two questions, answered (both build-skew-independent — verified via `git diff HEAD`):**

1. **Were the keys rotated?** Yes. Admin removal publishes `member_removed` then `rotateAndDistributeGroupKey` (`group_info_wired.dart:~1033`), advancing the epoch and distributing the new key to **remaining members only** — the removed member is already gone from `getMembers` before `distributionTargets` is built. Device confirms: `alice.log GROUP_ROTATE_KEY_DONE` epoch 1→2 `distributedTo:1` (Charlie), `topicPeers:1` @07:59:11.804. `rotate_and_distribute_group_key_use_case.dart` is **unchanged from HEAD** (not in the 121 diff) — robust regardless of any build question.
2. **If removed Bob reached a hidden composer, could he send?** **No.** Fail-closed at every layer:
   - **Local send gate** `send_group_message_use_case.dart:853-893` returns `unauthorized` when self is not an active member / has no current send key (after self-removal, `removeMember(self)` + `removeAllKeys` ran).
   - **Receiver gate (Go)** rejects on `pubsub.go:1527-1531` (`non_member`, after `callGroupUpdateConfig` drops Bob from the roster) and `:1554-1557` (`bad_signature_or_epoch`, since the group rotated to epoch 2 which Bob lacks). These are independent — either alone blocks him.
   - **Composer** auto-disables: `_canWriteForGroup` (`group_conversation_wired.dart:4113-4131`) returns false on `!_isCurrentUserActiveMember` (`:1166-1169`) or `!_hasCurrentSendKey` (`:4120`).

**Working-tree status: fixed.** No production change required for the core invariants. But these were **not exercised on device** (Bob never attempted a post-removal send) and coverage is thin. Two latent hazards to track:

- **`members.isEmpty` fail-OPEN** at `group_conversation_wired.dart:1168`: `_isCurrentUserActiveMember` defaults true when the member list is empty. Today it's backstopped by `_hasCurrentSendKey` (`removeAllKeys` nulls the key), but any future path that keeps a key while emptying members would re-open the composer. Harden by not fail-opening, or assert the backstop in a test.
- **Non-creator-admin rotation gap:** `rotate_and_distribute_group_key_use_case.dart:84` hard-requires `group.createdBy == selfPeerId`. A non-creator admin who removes a member updates the Go roster (so the receiver-side `non_member` gate still blocks the removed peer) but cannot rotate the Dart epoch — so forward secrecy on that removal is weaker. Real hardening item, separate scope.

**RED / coverage tests:**
1. *(Behavioral RED — this is the one that genuinely fails on the divergent B3 path)* `member_removal_integration_test.dart` → `'a removed member on a QUIET (sys-only) group keeps a retained read-only shell and cannot send'`: after self `member_removed` on a content-free group, assert `getGroup(id) isNotNull`, `getMember(self) isNull`, `getLatestKey(id) isNull`; then `sendGroupMessage(senderPeerId: self)` returns `SendGroupMessageResult.unauthorized` and writes nothing. **Fails on HEAD** (quiet group was hard-deleted → query targets gone); **passes on the working tree** (retain). This doubles as the B3-retain lock.
2. *(Mutation/coverage — NOT a behavioral RED; label it)* `rotate_and_distribute_group_key_use_case_test.dart` → `'rotation on removal advances the epoch and EXCLUDES the removed member from distribution'`: assert `keyGeneration == prev+1` and the removed peer/devices receive **no** `group_key_update`. Passes on current code; only goes RED if you mutate the pre-removal member list at `rotate_and_distribute:170-181`. Keep it as the exclusion lock.
3. `group_conversation_wired_test.dart` (adapt `~:5533-5591`): removed member's composer stays read-only on the retained group and is **never re-shown on reload/re-entry**.

---

## B3 + B3.1: re-add must actually restore Bob; the admin must not show a false "joined"

### B3 — re-add invite is dropped at the wrong layer (real residual)

**Root cause (confirmed, with a correction to 121):** the production incoming-invite path is `listener → storeIncomingPendingGroupInvite → (stored pending) → acceptPendingGroupInvite/materialize`. `storeIncomingPendingGroupInvite` short-circuits to `StorePendingGroupInviteResult.duplicateGroup` **whenever a group row already exists** (`handle_incoming_group_invite_use_case.dart:596-608`), regardless of whether self is still a member. Because B3 now **retains** a keyless read-only shell after removal, the re-add invite is treated as a duplicate and dropped. Device proof: `bob.log GROUP_INVITE_STORE_PENDING_DUPLICATE_GROUP` @08:00:41.701, after which Bob never rejoins (`GROUP_REJOIN_TOPICS_SKIP_NO_KEY` from @07:59:27 through @08:03:57) and never obtains the epoch-2 key — hence "no intro, can't read, no composer".

**This line is byte-identical to HEAD.** The 121 work added a `selfIsActiveMember` guard to a *different* function — `handleIncomingGroupInvite` — which has **no production caller** (dead w.r.t. the real path). 121 fixed the right idea at the wrong layer.

**GREEN production change:**
- `handle_incoming_group_invite_use_case.dart:596-608` (in `storeIncomingPendingGroupInvite`) — gate the duplicate short-circuit on active membership:
  ```
  final self = ownPeerId?.trim();
  final selfIsActiveMember =
      self == null || self.isEmpty ? true : (await groupRepo.getMember(payload.groupId, self)) != null;
  if (existingGroup != null && selfIsActiveMember) {
    return (StorePendingGroupInviteResult.duplicateGroup, null);
  }
  ```
  When the group row exists but self is **not** an active member (the B3 retained keyless shell), emit `GROUP_INVITE_STORE_PENDING_REJOIN_AFTER_REMOVAL` and **fall through** to store the pending invite so the existing accept/materialize path re-joins (re-saves the epoch-2 key + self membership). This unblocks both auto-accept and manual accept. The detection rule is sound: a *voluntarily left* group is hard-deleted (`getGroup == null`), so "row exists + self absent" uniquely identifies the retained-removed shell — the same rationale 121 documented for its (dead) wrapper fix.
- **Confirm the materialize/accept path re-saves the current (epoch-2) key and self membership** so Bob can decrypt new traffic. If the re-accept does not pull/receive the post-rotation key, add that (the admin re-add should deliver the current `group_key_update` to the re-added member, mirroring initial join). Without this, Bob rejoins but still can't read (`SKIP_NO_KEY`).

**MANDATORY companion edit (regression):** `store_pending_group_invite_use_case_test.dart:816-841` (`'returns duplicateGroup …'`) currently seeds an existing group **without** self as a member; after the guard it would no longer return `duplicateGroup`. Update it to `groupRepo.saveMember(self active)` so it still asserts `duplicateGroup` (mirror `handle_incoming_group_invite_use_case_test.dart:601-609`).

**RED tests:**
1. `store_pending_group_invite_use_case_test.dart` → `'retained keyless shell (self not a member) STORES the pending invite, not duplicateGroup'`: seed a `GroupModel` row for the invite's groupId with self (`ownPeerId 'myPeerId'`) **not** a member and no key; assert `storeIncomingPendingGroupInvite` returns `storedPending` (not `duplicateGroup`). **Fails on current tree** (returns `duplicateGroup` whenever `getGroup != null`).
2. `member_removal_integration_test.dart` (or `invite_round_trip_test.dart`) → `'removed-then-re-added member re-materializes key + active membership and regains write'`: accept (epoch 1) → self `member_removed` retains keyless shell (`getGroup != null`, `getMember(self) == null`, `getLatestKey == null`) → admin re-add (epoch 2) invite via the **listener/store path** → assert `getMember(self) != null`, `getLatestKey(id)` is the epoch-2 key, and the send gate now permits. **Fails on current tree** (re-invite dropped → nothing to accept).

### B3.1 — admin roster shows "joined" for a member who never rejoined

**Root cause (confirmed):** the member-status derivation `_loadLatestJoinEvidenceAt` (`group_info_wired.dart:238-260`) treats the admin's **own** `members_added` system row as join evidence. After Alice re-adds Bob she writes a local `members_added` at `t2`; `_isCurrentJoinEvidence` sees it and renders Bob "joined", even though no confirmation ever came back from Bob (`alice.log` shows only `MEMBER_JOINED_DUPLICATE_IGNORED`, never a fresh rejoin receipt).

**GREEN production change:**
- `group_info_wired.dart:238-260` — status must reflect a confirmation **from the member**, not the admin's local add. Either (a) drop `'members_added'` from `_loadLatestJoinEvidenceAt`'s queried event types so only a genuine `member_joined` receipt / acked `GroupInviteDeliveryStatus.joined` marks "joined"; or (b) introduce a distinct **"pending/invited"** status when a post-removal `members_added` exists with no corresponding `member_joined`. Recommend (b) — it surfaces the truth ("invited, not yet rejoined") rather than hiding the member.
- Confirm option (a) is safe for first-join: a brand-new member still produces a `member_joined` receipt and/or an acked delivery status, so first joins remain "joined".

**RED test:** `group_info_wired_test.dart` → `'a re-added member is NOT shown joined until a real join confirmation arrives'`: seed Bob + `member_removed(t1)` + **only** an admin-authored `members_added(t2>t1)` (no `member_joined`, no acked joined attempt); assert Bob's rendered status is pending/invited, **not** joined. **Fails on current tree** (`members_added` counts as evidence → "joined").

**Track as hardening (out of immediate scope):** there is no rejoin-receipt channel from a re-added device back to the admin, so even option (b) can only show "pending" until a `member_joined` arrives. Adding an explicit rejoin receipt is a separate item.

---

## B4: dissolve must converge on receivers — Option A landed, but the 121 "Option B" cannot fix the field case

**What's already correct (keep):** Option A — the dissolve call site signs the actor binding (`group_info_wired.dart:485-510`: `resolveGroupSenderDeviceBinding` → `actorDeviceId/actorTransportPeerId/actorKeyPackageId` into `dissolveGroup`). This eliminated the `device_mismatch`/`transport_mismatch` rejections (zero in the Jun 14 logs). The `_currentSenderDeviceId`-as-both-`preferredDeviceId`-and-`preferredTransportPeerId` detail is **benign** (verified: `resolveGroupSenderDeviceBinding`/`_resolveDevice` treat them as independent hints and the output `transportPeerId` always comes from `device.transportPeerId`). And the whole downstream is correct once `isDissolved` flips: a visible `sys-group_dissolved:` notice (`_handleGroupDissolved` ~`group_message_listener.dart:3996-4065`), the send gate (`send_group_message_use_case.dart:766`), the receive gate (`handle_incoming_group_message_use_case.dart:175-176`, drops at/after `dissolvedAt`), and the composer (`_canWriteForGroup`) all key off `isDissolved`. **So once convergence is fixed, the user's "Charlie should see a dissolve notice and lose the composer" is satisfied with no further UI work** (lock it with a regression test).

**The residual gap:** receivers now reject `group_dissolved` with `previous_transition_hash_mismatch` (`signed_group_transition_audit.dart:245-252`). The receiver computes the expected pre-transition hash from its **own local state** (`buildGroupTransitionStateHash`, called at `group_message_listener.dart:1789-1791`); Charlie's locally-computed hash does not canonically equal the `preTransitionStateHash` Alice signed, so the otherwise-correctly-bound dissolve is rejected and `isDissolved` never commits. This is the same canonicalization family that produced the upstream `key_rotated`/`members_added` `payload_mismatch` rejections — which 121 explicitly deferred as out-of-scope, and which is now the *proximate blocker* of dissolve convergence.

**CRITICAL correction to the 121 plan — "Option B" as written cannot fix this (source-verified):** 121 recommended adding `'group_dissolved'` to `_allowsSnapshotBackedSystemSender` (`group_message_listener.dart:2504-2508`) to relax the hash. But the relaxation path `_shouldRelaxSnapshotBackedPreTransitionHash` (`:2190-2228`) only returns true when the sender's **device can be bootstrapped from the snapshot**, and `_canBootstrapSnapshotBackedSenderDevice` (`:2394-2434`) **returns `false` whenever the sender's device is already known locally** (`localDeviceById != null` → `return false` at `:2421-2426`; same for `localDeviceByTransport`). At dissolve time Charlie **already knows Alice's admin device** (he applied `members_added` and reached epoch 2), so no bootstrap helper fires → relax is false → the strict hash is enforced. Adding `group_dissolved` to the allowlist is **necessary but not sufficient**: the relaxation machinery is designed for *unknown* sender devices, not for a *known* admin whose only divergence is the state hash.

### Fix (two layers; choose the targeted relaxation as the shippable primary)

- **PRIMARY (targeted, shippable now): a dedicated relaxation for an admin-signed *terminal* `group_dissolved`.** Add a branch that, for `sysType == 'group_dissolved'`, **skips the `preTransitionStateHash` equality check** (sets `relaxSnapshotBackedPreTransitionHash`/`expectedPreTransitionStateHash = null` at `group_message_listener.dart:1789-1791`) **gated on the already-running admin-role authorization** (`_isAuthorizedMembershipEventSender` returns `senderMember?.role == MemberRole.admin` for `group_dissolved` at `:2589-2590`) **and** the signature verification. Rationale: the pre-transition hash exists to keep the transition *chain* tamper-evident; `group_dissolved` is **terminal** — no subsequent transition's integrity depends on it — so relaxing the chain hash for an authenticated admin dissolve loses nothing while letting the dissolve converge despite upstream state drift. This is a deliberate, documented deviation from the 121 line-138 rule "do NOT loosen the verifier", scoped strictly to the terminal event.
  - Pair the allowlist addition (`'group_dissolved'` in `_allowsSnapshotBackedSystemSender`) **with** the new terminal-relaxation branch — the allowlist alone is inert here (see correction above).
  - **MANDATORY paired negative test:** a non-admin or forged dissolve must still reject (at `_isAuthorizedMembershipEventSender` / signature). The relaxation must not open a forgery hole.
- **ROOT follow-up (broader, also clears `members_added`/`key_rotated`): fix the transition subject / state-hash canonicalization** so receiver and signer compute identical hashes (`buildGroupTransitionStateHash` / `buildGroupSystemTransitionSubject`, `signed_group_transition_audit.dart:305-446`). This removes the `payload_mismatch` family at the root and would make even the strict pre-transition-hash pass. Larger and riskier; track as its own item but reference it here because it is the true cause of the divergence.
- **Reconciliation / defense-in-depth (covers offline & re-added members):** `rejoin_group_topics_use_case.dart:~75` only **reads** local `isDissolved`; there is no path that re-derives dissolved state from a relayed/durable `group_dissolved`. A member who misses the live publish (Bob, keyless after re-add; or any offline member) stays permanently live. Add a durable/relayed `group_dissolved` drain on rejoin/recovery that routes through `_handleGroupDissolved`, so a missed dissolve still converges. (Bob's specific miss in this run is fixed by B3 — once he's a live member again he receives the live dissolve — but the reconciliation path is the general guarantee.)
- **Do NOT loosen the binding check** at `signed_group_transition_audit.dart:235-244` — that is correct and is what Option A made pass. Only the terminal-event pre-hash policy changes.

**RED tests (must recreate the field divergence — known admin device + diverged state hash):**
1. `group_message_listener_test.dart` (new test in the `group_dissolved` group ~`:12371`) → `'group_dissolved with a present, matching signed binding but a diverged local pre-transition state is REJECTED on current tree and APPLIED after the terminal relaxation'`. Seed an **admin sender member with a known device** (so device/transport pass and we hit the *hash* check, not the binding check); build a `group_dissolved` `__sys` carrying a **real** `signedTransitionAudit` (thread `preTransitionStateHash`) and wire `_appendGroupEventLogEntry` so `_shouldRequireSignedTransitionAudit` (`:2510-2519`) forces the audit branch; arrange the receiver's local membership/key state so `buildGroupTransitionStateHash` differs from the signed value. Assert: current tree → `isDissolved == false` + `previous_transition_hash_mismatch`; after fix → `isDissolved == true`, `dissolvedBy` set, no rejection. **This de-masks the vacuous existing dissolve tests** (which carry no `signedTransitionAudit`).
2. `group_membership_smoke_test.dart` (integration, `GroupTestUser` + `FakeGroupPubSubNetwork`, **not** `dissolveGroupViaBridge`) → `'admin dissolve with a diverged receiver → Charlie cannot send, cannot receive, does not rejoin the dissolved topic'`. Force receiver-state divergence (Charlie misses/rejects a prior `key_rotated`/`members_added` so his transition-state hash differs), deliver the dissolve through the network. Current tree → diverged receiver rejects (`previous_transition_hash_mismatch`), `isDissolved` stays false, Bob's send returns `success`, Charlie renders post-dissolve traffic, Charlie keeps `GROUP_REJOIN_TOPICS_JOINED`. After fix → Bob send → `groupDissolved`, Charlie drops at/after `dissolvedAt`, Charlie does **not** rejoin the dissolved topic.
3. `group_message_listener_test.dart` → paired **negative**: a non-admin/forged `group_dissolved` still rejects after the relaxation lands (forgery lock).
4. `rejoin_group_topics_use_case_test.dart` (or a new reconciliation test) → `'a missed/relayed group_dissolved re-applies dissolved state on rejoin/recovery'`: member with local `isDissolved == false` but a durable/relayed `group_dissolved` available; run rejoin/recovery; assert `isDissolved` becomes true and the topic is **not** rejoined. **Fails on current tree** (rejoin only reads the flag).
5. `group_conversation_wired_test.dart` → regression-lock (passes once convergence is fixed): with `isDissolved` true + a `sys-group_dissolved:` row, assert the dissolve notice bubble shows and `_canWriteForGroup` is false. Guards the user's explicit "see a notice AND lose compose" requirement.

---

## B5 (cross-cutting; lands with B3/B4): composer recompute wiring

The composer **gate** (`_canWriteForGroup` `group_conversation_wired.dart:4113-4131`) and per-state **banner** (`_readOnlyBannerText` `:4133-4148`) are already correct and complete (they predate 121). The bugs are in the *recompute wiring* — the composer can't transition without re-entry:

- **Defect 1 — membership/key changes don't recompute send-capability.** The live-message handler (`:1357-1359`) only matches `sys-group_metadata_updated:` / `sys-group_dissolved:` → calls `_refreshVisibleGroup` (`:4275-4291`), which reloads **only the group row** (not membership or keys). So a live removal/re-add/role-change does not flip the composer until the user leaves and re-enters. **Fix:** extend the branch to also match `sys-members_added:` / `sys-member_removed:` / `sys-member_joined:` (and consider `sys-member_role_updated:` for the reader/writer gate) and, for those, call `_loadSecurityStatus()` (`:1158-1225`, which re-derives `_isCurrentUserActiveMember` `:1166-1169` and `_hasCurrentSendKey` `:1221` and `setState`s) — **not** `_refreshVisibleGroup` (which leaves those gates stale). This makes the composer **reappear** on a live re-add (B3) and **disappear** on a live removal (B2). **RED-test caveat:** seed at least one *other* member before `removeMember(self)` so the `members.isEmpty ||` fail-open at `:1168` doesn't mask the assertion; the GREEN must call `_loadSecurityStatus()`.
- **Defect 2 — removed-while-viewing still pops the screen.** `_handleCurrentGroupRemoved` (`:1426-1439`) still `Navigator.popUntil((r) => r.isFirst)` (`:1438`), even though B3 now retains the group row. A member viewing the chat when removed is ejected, contradicting the read-only-retain intent. **Fix:** when `getGroup(id) != null` (retained shell), do an **in-place** refresh (`_refreshVisibleGroup` + `_loadMessages` + `_loadSecurityStatus`) and keep the snackbar; pop only when `getGroup(id) == null` (true hard-delete fallback). Optionally stop emitting `_emitGroupRemoved` on retain (`group_message_listener.dart:3148-3152`) to avoid double-handling.
- **Defect 3 — dissolve gate fed a stale flag.** Until B4 convergence lands, the dissolved composer gate is correct in code but `isDissolved` stays false on every non-dissolver. Resolved by B4.

**RED tests:**
1. `group_conversation_wired_test.dart` → `'composer disappears on a LIVE sys-member_removed without re-entry'` (seed self + another member; `removeMember(self)` + `removeAllKeys`; push `sys-member_removed:`; assert composer gone). **Fails on current tree** (`:1357` ignores membership types). GREEN = `_loadSecurityStatus()`.
2. `group_conversation_wired_test.dart` → `'composer reappears on a LIVE sys-members_added(self) without re-entry'` (inverse). **Fails on current tree.**
3. `group_conversation_wired_test.dart` → `'self member_removed while viewing keeps the conversation open read-only in place (no pop)'`: retained shell + `removedStreamController.add(id)`; assert the route **stays** and the composer is read-only. **Fails on current tree** (`popUntil(isFirst)`).
4. `group_conversation_wired_test.dart` → dissolved-banner widget test is a **regression-lock only** (it already passes in widget isolation because `:1357` handles `sys-group_dissolved:`); the fix-proving dissolve RED lives at the audit/listener level (B4 test 1/2).

---

## B6: coverage + a build-provenance gate (so "fixed in tree, broken on device" is caught)

The Jun 14 run *did* exercise the working tree, so the real lesson is that the unit suite **passes while the integrated behavior fails** — because the tests mask the audit path and there is no full-lifecycle integration test.

- **De-masking unit (mandatory):** every existing dissolve test bypasses `verifyGroupTransitionAudit` (`group_dissolved` 17×, `signedTransitionAudit` 0×). The new B4 test 1 must carry a real `signedTransitionAudit` and wire `_appendGroupEventLogEntry` so `_shouldRequireSignedTransitionAudit` forces the audit branch.
- **Full-lifecycle E2E (highest value):** `group_membership_smoke_test.dart` (new, `GroupTestUser` + `FakeGroupPubSubNetwork`) → `create → invite → accept → remove(rotate epoch 1→2) → re-add → dissolve`, asserting **after each transition** that Bob and Charlie converged to Alice's membership/key state, and **after dissolve** that both have `isDissolved == true`, Bob's send → `groupDissolved`, Charlie drops post-dissolve traffic. On the current tree this fails (receivers reject `key_rotated`/`members_added` → state diverges → dissolve `previous_transition_hash_mismatch`), which is exactly the field bug reproduced in CI. Split the **re-added-member key-delivery** assertion (Bob never got epoch-2 key, `SKIP_NO_KEY`) from the **dissolve-convergence** assertion (Charlie's hash mismatch) — they are distinct mechanisms.
- **Option-A mutation lock:** add a `signActorBinding:false` vs `true` contrast at the dissolve call site (sibling to `group_membership_smoke_test.dart:~16826`): `false` → live dissolve rejected; `true` → converges. Locks the binding fix against regression.
- **Build-provenance gate (recommended, catches the whole skew class):** emit one `APP_BUILD_INFO` FLOW milestone at `main.dart` startup with git short-SHA + dirty flag (`--dart-define=GIT_SHA=$(git rev-parse --short HEAD)` + `git status --porcelain` check) + build ts; hard-assert in the device harnesses (`group_multi_party_device_real_harness.dart`, `group_multi_device_real_harness.dart`) that the logged SHA equals the SHA under test. This would have *instantly* resolved the "skew?" question for this very investigation. Unit-test the milestone emission (`test/core/app_build_info_test.dart`).

---

## Recommended landing order

1. **B1** — one-line `HitTestBehavior.opaque` + 2 widget tests. Isolated, zero risk, immediate UX win. De-risks the rest.
2. **B2 coverage** — the behavioral retain/fail-closed RED (test 1) + the rotation-exclusion mutation lock. No production change; locks the security posture and the B3-retain invariant before touching the re-add path.
3. **B3 + B3.1** — `storeIncomingPendingGroupInvite` guard (+ the mandatory companion test edit) and the materialize-path key re-save; the join-evidence truthfulness fix. This is the highest-impact functional fix (restores a re-added member) and a prerequisite for Bob receiving any future dissolve.
4. **B4** — the terminal-dissolve relaxation (+ allowlist) with the forgery negative test and the divergent-receiver integration RED; then the reconciliation/durable-drain. Security-sensitive — do after B3 so the integration test has a real re-added member, and gate every relaxation behind the existing admin-role + signature checks.
5. **B5** — the composer recompute wiring + the no-pop-on-retain fix. Lands cleanly on top of B3/B4 and makes the UI reflect the now-correct state live.
6. **B6** — the full-lifecycle E2E, de-masking unit, Option-A mutation lock, and `APP_BUILD_INFO` gate. Run last to lock everything and prevent recurrence.

B1/B2/B5(UI) are independent of the crypto-path work (B3/B4); B5's dissolve half depends on B4 convergence.

---

## Gate / acceptance per phase

- Per phase: the listed RED tests fail on the current working tree for the documented reason and pass after the GREEN edit; B2's rotation lock and the Option-A lock pass their revert-mutation checks; the B4 forgery negative stays green throughout.
- Suite gates (run `-j 1` to avoid the known shared-global-gate parallel flake): `flutter test test/features/groups/` and `test/features/orbit/`, plus `dart analyze` showing zero new issues.
- **Device re-verification (Pixel↔iPhone, same 3-device scenario), capturing fresh `alice/bob/charlie.log`:**
  - whole row toggles selection during group creation;
  - removed member: read-only retained group, composer hidden, **no** successful send; rotation epoch +1 to remaining only;
  - **re-add: Bob receives the invite, rejoins, reads new messages, composer reappears; Alice's settings shows Bob "joined" only after a real rejoin (otherwise "pending")**;
  - **dissolve: Charlie sees a dissolve notice and loses the composer; grep the NEW logs for `previous_transition_hash_mismatch` (it must be GONE) — do NOT grep for `device_mismatch`/`transport_mismatch` (already fixed)**; every member logs `GROUP_REJOIN_TOPICS_SKIP_DISSOLVED`.
  - Rebuild **both** Flutter and Go from the working tree before the run (`cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`) to eliminate native skew as a confound; confirm the `APP_BUILD_INFO` SHA matches once B6 lands.

---

## Open questions (owner decisions)

- **OQ-B4 (primary):** terminal-dissolve pre-hash relaxation (targeted, shippable, deviates from 121 line 138 but gated on admin-role + signature + forgery test) vs the canonicalization root-fix (broader, also clears `members_added`/`key_rotated` `payload_mismatch`, larger blast radius). Recommend: ship the targeted relaxation now, schedule the canonicalization fix as the follow-up. Do we also want a defense-in-depth send/receive fail-safe (block on positive evidence of dissolution even if `isDissolved` didn't commit)?
- **OQ-B3.1:** drop `members_added` from join-evidence (simple) vs add an explicit "pending/invited" status (truthful) — and do we build a rejoin-receipt channel so the admin can ever show a re-added member as genuinely "joined"?
- **OQ-B3:** when a re-added member's composer reappears, show a transient "you were re-added" affordance, or let it silently re-enable?
- **OQ-B2:** harden the `members.isEmpty` fail-open and the non-creator-admin rotation gap now, or track separately?
- **OQ-B1:** `HitTestBehavior.opaque` vs `InkWell` ripple.

---

## Evidence appendix (Jun 14 device-log anchors; corrected timestamps)

- **B1:** no FLOW signature (pure client-side hit-test geometry); verified in source only.
- **B2:** `alice.log` @07:59:11.804 `GROUP_ROTATE_KEY_DONE` epoch 1→2 `distributedTo:1` `topicPeers:1`; `bob.log` @07:59:11.729 `SELF_REMOVED_HISTORY_RETAINED` (no `GROUPS_DB_DELETE id:cdd05122`). Fail-closed send not exercised on device (Bob made no post-removal send) — proven in source.
- **B3:** `alice.log` @08:00:40.493 `GROUP_ADD_MEMBER_USE_CASE_SUCCESS`, re-invite `SEND_START`→`SUCCESS` @08:00:41.6/42.0; `bob.log` @08:00:41.701 `GROUP_INVITE_STORE_PENDING_DUPLICATE_GROUP`, then `GROUP_REJOIN_TOPICS_SKIP_NO_KEY` @07:59:27 … @08:03:57 (never rejoined, never got epoch-2 key). **B3.1:** `alice.log` `MEMBER_JOINED_DUPLICATE_IGNORED` (no fresh rejoin receipt).
- **B4:** `charlie.log` @07:59:11.867 `REJECTED type:key_rotated reason:payload_mismatch`; @08:00:41.602 `REJECTED type:members_added reason:payload_mismatch` (and `members_added` APPLIED @08:00:41.717, `memberCount:3`, epoch 2); @08:03:07.807 & @08:03:23.936 `REJECTED type:group_dissolved reason:previous_transition_hash_mismatch`; @08:03:23/53 `GROUP_REJOIN_TOPICS_JOINED` (never `SKIP_DISSOLVED`). `alice.log` @08:03:07.823 `GROUP_DISSOLVE_USE_CASE_SUCCESS recipientCount:2` (`topicPeers:1`); only Alice logs `SKIP_DISSOLVED`. **Zero `device_mismatch`/`transport_mismatch` in all three logs** (proves Option A shipped).
- **B5:** verified in source (`:1357-1359` refresh branch omits membership types; `:1426-1439` still `popUntil(isFirst)`).
