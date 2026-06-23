# 150 - Invite-accept & join outcomes as per-row inline state (replace the 11-arm accept snackbar)  (Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | accept_pending_group_invite_use_case.dart, group_list_wired.dart, group_list_screen.dart, orbit_screen.dart, pending_group_invite_card.dart, group_list_wired_test.dart, app_en/ar/de.arb, run_test_gates.sh | verify→refute complete: 11-arm switch confirmed at :333-372; recovery-retry wrapper :395 retries bridgeError(group==null & invite present) only; 3 bridgeError shapes confirmed in use-case (:565/:568, :677, :715, success-like :562-566); `group_invite_joined_recovery` exists in en/ar/de but is referenced NOWHERE; `group_invite_waiting_for_key` absent; no migration needed (pure presentation) | Planner |
| 2026-06-23 | Planner | (as above) | Per-row state keyed by invite id alongside `_processingInviteIds` (:108), cleared in `_loadGroups` (:136); 8 terminal outcomes → restyle/remove row + reason; repairPending → "Waiting for key" spinner; bridgeError(keep-pending) → inline Retry re-entering `_onAcceptPendingInvite` (guard preserved); success-like bridgeError(group!=null) → wire dead `group_invite_joined_recovery`; drop 11 accept snackbars + Joining snackbar | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 150; files go to 149)

## Session Classification
implementation-ready (host-only closure; no migration, no device-proof — all behavior is local screen-state + render of an already-resolved use-case result)

## Exact Problem Statement
Accepting a pending group invite resolves to one of **11** `AcceptPendingGroupInviteResult` values (`accept_pending_group_invite_use_case.dart:25-40`: `success, notFound, expired, expiredFreshness, revoked, alreadyUsed, wrongIdentity, repairPending, invalidPayload, duplicateGroup, bridgeError`). The wired handler `_onAcceptPendingInvite` (`group_list_wired.dart:299`) maps **every non-success arm to a transient ~4s snackbar** via an 11-arm switch (`:333-372`): `notFound:343`, `expired:346`, `expiredFreshness:349`, `revoked:352`, `alreadyUsed:355`, `wrongIdentity:358`, `repairPending:361→group_invite_needs_key`, `invalidPayload:364`, `duplicateGroup:367`, `bridgeError:370`. Only `success:334` navigates into the new group.

This is the same UX defect class as 144/149: the **outcome is detached from the row it belongs to**. The invite card (`PendingGroupInviteCard`, keyed `pending-group-invite-<groupId>`) stays unchanged while a floating snackbar — easily missed if scrolled or backgrounded — carries the only feedback. The user can't tell *which* invite failed, can't retry an honestly-transient `bridgeError`, and gets a confusing "Failed to accept invite" even when the group **did** materialize (the success-like `bridgeError`-with-group at use-case `:562-566`, where `group != null` but the relay drain hadn't completed). A second redundancy: the stuck-rejoin `_onRetryStuckRejoin` shows a `group_joining_in_progress` ("Joining…") snackbar (`:569-572`) even though the **inline** "Joining…" badge already exists on the group card (`group_list_screen.dart:255-265` via `GroupCard.statusText`).

What must improve:
- Each accept outcome becomes **per-row inline state on `PendingGroupInviteCard`**:
  - **8 terminal outcomes** (`expired, expiredFreshness, notFound, revoked, alreadyUsed, wrongIdentity, invalidPayload, duplicateGroup`) → restyle/remove the row with a **one-line inline reason** (no snackbar).
  - **repairPending** → trailing spinner with **"Waiting for key"** (new key `group_invite_waiting_for_key`); keep the row (background key repair finishes it).
  - **bridgeError (keep-pending / retryable)** → trailing **inline Retry** that re-enters `_onAcceptPendingInvite` (re-entrancy guard preserved).
  - **bridgeError (success-like, group materialized)** → treat as join-with-recovery; wire the **dead** key `group_invite_joined_recovery` (`app_en.arb:1300`, referenced nowhere today) and navigate, instead of "Failed to accept invite".
  - **success** keeps the navigate.
- Drop the **11 accept snackbars** (`:335,343,346,349,352,355,358,361,364,367,370`) and the redundant **`group_joining_in_progress` snackbar** in `_onRetryStuckRejoin` (`:569,572`).

What must stay unchanged (→ preserved-green sentinels):
- The re-entrancy guard `_processingInviteIds` (`:302` contains-check, `:306` add, `:390` remove) — the inline Retry must route through `_onAcceptPendingInvite` so rapid taps don't double-arm.
- The recovery-retry wrapper `_acceptPendingInviteWithRecoveryRetry` (`:395`) and its 5×500ms loop (`:452-469`) — unchanged.
- The inline **"Joining…" badge** + stuck-group **Retry/Leave** actions (`group_list_screen.dart:255-265,296-324`, keys `group-stuck-retry-<id>`/`group-stuck-leave-<id>`).
- Decline path snackbars (`:526,529,532,548`) — OUT of scope (this plan is accept-only).
- Group gates (groups suite), feed/LetterCard suites, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
**Confirmed on HEAD** (uncommitted `new-feed`; not build-skew — the 11-arm switch is the live code path):
- The presentation layer collapses a rich 11-value result into ephemeral toasts: `group_list_wired.dart:333-372` is an 11-arm `switch (result)` where 10 arms call `_showSnackBar(...)` (`:335` success-toast is also a snackbar) and only `:339` navigates. There is **no per-row state surface** — `PendingGroupInviteCard` exposes only `invite/isProcessing/onAccept/onDecline` (`pending_group_invite_card.dart:9-21`), so there is nowhere to render a row-scoped outcome.
- The success-like `bridgeError`-with-group is **mis-bucketed**: the use-case returns `(bridgeError, group)` at `:562-566` when the group materialized but the inbox drain hadn't advanced, yet the handler's `bridgeError:370` arm ignores `group != null` and shows `group_invite_accept_failed`. The dead l10n key `group_invite_joined_recovery` (en `:1300`, ar `:1248`, de `:1248`) was authored for exactly this state but **wired to nothing** (`grep` of `lib/` finds zero references).
- The "Joining…" outcome is double-surfaced: an inline badge (`group_list_screen.dart:261-264` → `GroupCard.statusText` `:269`) AND a snackbar (`group_list_wired.dart:569,572`).

Refuted / do-NOT-re-introduce:
- ❌ "the result enum has 12 values" — **FALSE**. Exactly **11** (`accept_pending_group_invite_use_case.dart:25-40`).
- ❌ "repairPending already keeps the row inline" — **PARTIAL**. The use-case keeps the pending invite (`:248/:310/:596`) so the *card* stays, but the only repairPending *feedback* is the **transient** `group_invite_needs_key` snackbar (`:361`); the existing test asserts that snackbar text (`group_list_wired_test.dart:1273`), still visible at 30 pumps. There is no inline row state — migrating to inline requires rewriting that assertion.
- ❌ "bridgeError is one shape" — **FALSE**. Three shapes: (a) keep-pending retryable `(bridgeError, null)` with the invite still present (`:464`, `:538`, `:568`, `:677`, `:715`); (b) success-like `(bridgeError, group)` materialized (`:562-566`); the recovery-retry wrapper (`:452-456`) re-attempts only shape (a).
- ❌ "stuck-Retry has no inline surface, keep its snackbar" — **FALSE**. The inline "Joining…"/"Couldn't join — retry" badge already renders from `_rejoinAttempts` (`group_list_screen.dart:255-265`); the snackbar is pure redundancy.
- ❌ "needs a DB migration" — **FALSE**. All state is in-State presentation; no schema, no persisted field. DB stays v92, next-free 093 untouched.

## Real Scope
In scope:
- `PendingGroupInviteCard` (`pending_group_invite_card.dart`): add an **outcome param** (e.g. `outcome` of a new small presentation enum `PendingInviteRowState { idle, processing, waitingForKey, retryable, joinedRecovery }` + optional `inlineReasonText`/`onRetry`) so the row can render: a one-line reason, a "Waiting for key" trailing spinner, or an inline **Retry** control — preserving the existing `isProcessing` in-button spinner (`:152-161`) and the `ValueKey('pending-group-invite-<groupId>')` (`:45`).
- `group_list_screen.dart` (`:206-225`): thread the per-row outcome map + `onRetryPendingInvite` callback down into `PendingGroupInviteCard`, alongside the existing `processingInviteIds.contains` wiring.
- `orbit_screen.dart` (`:848`): same `PendingGroupInviteCard` is rendered there — thread the new params (or default them so Orbit keeps current behavior; pick one and lock it with a test note).
- `group_list_wired.dart`:
  - Add per-row outcome state keyed by invite id alongside `_processingInviteIds` (`:108`), **cleared in `_loadGroups`** (`:136`, on the next list refresh).
  - Rewrite the 11-arm switch (`:333-372`): 8 terminal arms → set inline reason / drop row, **no snackbar**; `repairPending` → `waitingForKey`; `bridgeError`+`group!=null` → `joinedRecovery` (navigate + `group_invite_joined_recovery`); `bridgeError`+`group==null` → `retryable` inline Retry; `success` → navigate.
  - Add `_onRetryPendingInvite(invite)` that re-enters `_onAcceptPendingInvite(invite)` **without bypassing** `_processingInviteIds`.
  - Drop the `group_joining_in_progress` snackbar in `_onRetryStuckRejoin` (`:569,572`); keep `forceGroupRejoinEligible` + `rejoinGroupTopics` + `_loadGroups`.
- l10n: **add 1 new key** `group_invite_waiting_for_key` (plain string, no @-metadata) to en/ar/de **by KEY**; **wire** the existing dead `group_invite_joined_recovery`. Reuse `btn_retry` for the inline Retry label and existing terminal copy strings (`group_invite_no_longer_available`, `group_invite_expired`, etc.) as the inline reason text.
- Harness: **add `test/features/groups/presentation/group_list_wired_test.dart` to `GROUP_TESTS`** in `scripts/run_test_gates.sh` (it is swept by host-all auto-glob today but is NOT in the curated `groups` gate). New `pending_group_invite_card_test.dart` lands under `test/features/groups/presentation/widgets/` (auto-globbed by host-all; also explicitly run via the direct `flutter test` gate).

Out of scope (owning work named):
- The **decline** path (`_onDeclinePendingInvite` `:511`, snackbars `:526/:529/:532/:548`) — a future "decline outcomes inline" session.
- The sender-side `GroupInviteDeliveryStatus` / `group_invite_status_presentation.dart` — a **different enum** (delivery, not accept); not touched. No overlap with plan 144's banner (that lives only in `group_conversation_wired.dart`).
- Any change to `accept_pending_group_invite_use_case.dart` result values, the recovery-retry loop timing, or the relay/drain layer.

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_list_wired.dart` — handler `_onAcceptPendingInvite` `:299`; guard `_processingInviteIds` `:108`/`:302`/`:306`/`:390`; 11-arm switch `:333-372`; recovery-retry wrapper `:395-471`; `_loadGroups` clear point `:136-177`; `_onRetryStuckRejoin` `:568-587` (drop snackbar `:569,572`); `_showSnackBar` `:559`; `build` wiring `:622-639`.
- `lib/features/groups/presentation/screens/group_list_screen.dart` — `PendingGroupInviteCard` render `:206-225`; "Joining…" badge `:255-265`; stuck actions `:296-324`; `_joinGiveUpThreshold` `:247`.
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` — ctor params `:9-21`; key `:45`; in-button spinner `:152-161`.
- `lib/features/orbit/presentation/screens/orbit_screen.dart` — second `PendingGroupInviteCard` callsite `:848`.
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart` — result enum `:25-40` (NOT edited); bridgeError shapes `:464/:538/:565/:568/:677/:715`, success-like `:562-566`.
- `lib/l10n/app_en.arb` (`group_invite_joined_recovery:1300`, `group_invite_needs_key:1297`), `app_ar.arb`, `app_de.arb` — append-by-key.
Direct tests:
- `test/features/groups/presentation/group_list_wired_test.dart` — rewrite repairPending `:1250-1276`; add per-outcome inline rows + inline-Retry + success-like-recovery + no-snackbar locks.
- `test/features/groups/presentation/widgets/pending_group_invite_card_test.dart` — NEW (render-only widget tests for the new outcome param).
Dependency-only context:
- `lib/features/groups/domain/models/pending_group_invite.dart` (invite shape — not edited).

## Existing Tests Covering This Area
- `group_list_wired_test.dart:1111` "EK011 accepts a key-package-bound pending invite …" — success row-removal + navigate; asserts row gone `:1138-1141`, `Joined Package Room` `:1143`. PASSES. **Sentinel — keep green** (success unchanged).
- `group_list_wired_test.dart:1210` "accept drains all inbox cursor pages before clearing spinner" — success row-removal `:1238-1241`, `Joined Cursor Room` `:1242`. PASSES. **Sentinel.**
- `group_list_wired_test.dart:1155` "bridgeError accept of an inline invite consumes it and materializes the group …" — inline-consume (shape b/duplicate path): invite gone `:1190`, group present `:1193`, row gone `:1196`, `Book Club` listed `:1203`; snackbar **not** asserted (`:1201-1202`). PASSES. **Sentinel** (materialize-and-consume must keep working).
- `group_list_wired_test.dart:1031` "accept retries rollback until latest metadata is recovered" — asserts `Joined test 3` `:1102` and **no** "Invite accepted, but recovery is still catching up" / "Failed to accept invite" (`:1104,:1107`). PASSES. Note: the asserted-absent recovery text is NOT the `group_invite_joined_recovery` copy — keep this green (success path, not bridgeError-with-group).
- `group_list_wired_test.dart:1250` "repair-pending accept keeps the invite row and shows key-material warning" — asserts invite kept `:1266`, row present `:1270-1272`, and `find.text('Invite needs fresh key material')` `:1273` (the TRANSIENT `group_invite_needs_key` snackbar). PASSES. **Locks OLD snackbar behavior → must be REWRITTEN to assert the inline `group_invite_waiting_for_key` row state.**
- `group_list_wired_test.dart:1278` "IJ014 repairable join-material failure keeps pending invite visible" — also asserts `Invite needs fresh key material` `:1307` (repairPending). PASSES. **Rewrite** to the inline reason OR keep (both reach repairPending) — pin to inline.
- `group_list_screen.dart` "Joining…" badge — exercised by `group_list_wired_test.dart:772-790` (`find.text('Joining…')` `:786`) and stuck-retry `:791-808` (`Couldn't join — retry` `:807`, tap `group-stuck-retry-g-1` `:550`). PASSES. **Sentinel** — must stay green after dropping the stuck-Retry snackbar.

Missing coverage gaps (ZERO assertions today): the **8 terminal outcomes** as inline row state; the **inline Retry** for keep-pending `bridgeError`; the **success-like `bridgeError`-with-group** → join+recovery navigate; the **no-snackbar** lock for accept outcomes; the **no-snackbar** lock for stuck-Retry; `PendingGroupInviteCard` rendering of the new outcome param.

Already in curated family arrays?: `letter_card_test.dart` ✅ in `GROUP_TESTS` (`:129`). `group_conversation_screen_test.dart` ✅ (`:130`), `group_conversation_wired_test.dart` ✅ (`:131`). **`group_list_wired_test.dart` ❌ NOT in `GROUP_TESTS`** — it is swept only by the host-all auto-glob (`classify_path` subdir patterns, `run_test_gates.sh:608` covers feature-root files only; `presentation/` files match a recognized subdir and run under `feature-host-all`/`host-all`, not the curated `groups` gate). → **registration step required.** The new `pending_group_invite_card_test.dart` under `test/features/groups/presentation/widgets/` is likewise host-all-globbed only (peers `group_name_panel_test.dart`, `glow_fab_test.dart` already there) → also add to `GROUP_TESTS` (or run via the direct gate; this plan adds it to `GROUP_TESTS` for curated coverage).

## RED Test Catalog  (add/rewrite BEFORE any production code — INV-RED-FIRST)

1. `group_list_wired_test.dart`::"terminal accept outcome shows an inline reason on the invite row and no snackbar"  *(data-driven over the 8 terminal results)*
   - Tier: integration/widget (wired screen, fakes + real repos in setUp)
   - Shape/setup: for each of `notFound, expired, expiredFreshness, revoked, alreadyUsed, wrongIdentity, invalidPayload, duplicateGroup`, drive the use-case to that result (stub `bridge`/`pendingInviteRepo`/`groupRepo` so accept resolves to it — e.g. `overrideGroupKey:''`→repairPending is excluded; use the same makePendingInvite seams the existing terminal arms hit, e.g. expired invite, revoked tombstone), tap `pending-group-invite-accept-<id>`, pump.
   - RED on HEAD because: HEAD shows the matching `_showSnackBar` text (`:343-367`) and renders NO inline reason on the card. Asserting the inline reason text is a descendant of `find.byKey(ValueKey('pending-group-invite-<id>'))` finds nothing; asserting the corresponding snackbar is **absent** fails (it is shown).
   - GREEN asserts: per outcome, the row (or its replacement) shows the mapped reason text **scoped to the card subtree** (`find.descendant(of: card, matching: find.text(reason))`); **no** `ScaffoldMessenger` snackbar with that text (`find.byType(SnackBar)` → 0, or the reason text not found outside the card).
   - Mutation that re-reds: restore one terminal arm's `_showSnackBar(...)` + remove its inline-state assignment → snackbar reappears / inline gone → red.
   - Distinct-event discriminator: assert reason text present **inside the card** AND `find.byType(SnackBar)` `findsNothing` (separates "inline" from "still a toast").

2. `group_list_wired_test.dart`::"bridgeError keep-pending accept shows an inline Retry that re-runs accept through the guard"
   - Tier: integration/widget
   - Shape/setup: stub accept's first attempt to resolve `(bridgeError, null)` with the invite still present (shape a — e.g. `group:join` fails AND the recovery-retry loop exhausts; or force the wrapper to return shape a by leaving the pending invite present). Tap accept; pump past the 5×500ms recovery loop.
   - RED on HEAD because: HEAD shows `group_invite_accept_failed` snackbar (`:370`) and leaves the card in its idle state — there is NO inline Retry control (`find.byKey(ValueKey('pending-group-invite-retry-<id>'))` findsNothing). Asserting that Retry key present fails.
   - GREEN asserts: card shows an inline Retry keyed `pending-group-invite-retry-<id>`; tapping it re-enters `_onAcceptPendingInvite` (assert `bridge.commandLog`/accept invocation count increments, or the spinner re-appears); `group_invite_accept_failed` snackbar **absent**; the `_processingInviteIds` guard is respected (a rapid double-tap does NOT double-arm — assert accept invoked once per tap).
   - Mutation that re-reds: drop the `retryable` branch (route bridgeError-null back to `_showSnackBar`) → Retry key gone → red. Second mutation: make `_onRetryPendingInvite` bypass `_processingInviteIds` → double-tap double-arms → guard assertion reds.

3. `group_list_wired_test.dart`::"bridgeError with materialized group navigates and reports join-with-recovery (not failure)"  *(wires the dead `group_invite_joined_recovery`)*
   - Tier: integration/widget
   - Shape/setup: drive accept to `(bridgeError, group)` (shape b — group materialized, inbox not drained: stub so `group != null` returns from `:562-566`). Tap accept; pump.
   - RED on HEAD because: HEAD's `bridgeError:370` arm ignores `group != null` → shows `group_invite_accept_failed` and does NOT navigate. Asserting navigation into `GroupConversationScreen` + the `group_invite_joined_recovery` outcome (and NOT `Failed to accept invite`) fails.
   - GREEN asserts: navigates to the group (`find.byType(GroupConversationScreen)` or `_onGroupTap` fired); `group_invite_accept_failed` snackbar **absent**; the join-with-recovery copy `group_invite_joined_recovery` is surfaced (inline or as the single permitted success-style notice) — assert its text present.
   - Mutation that re-reds: revert the `bridgeError`+`group!=null` branch back to the generic `bridgeError` arm → no navigate / failure copy → red.

3a. `group_list_wired_test.dart`::"l10n source-wiring lock: group_invite_joined_recovery is referenced from the accept handler"
   - Tier: widget/source-lock (string presence in the rendered tree under shape-b)
   - RED on HEAD: the key is dead (zero references) → no path renders it → assertion finds nothing.
   - GREEN: covered by TC-03's text assertion; this row guards that the key stops being dead. Mutation: remove the `joinedRecovery` wiring → key dead again → red.

4. `group_list_wired_test.dart`::"repair-pending accept shows an inline 'Waiting for key' row and no snackbar"  *(rewrite of `:1250-1276`)*
   - Tier: integration/widget
   - Shape/setup: `makePendingInvite(overrideGroupKey: '')` (the existing repairPending seam, `:1253`); tap accept; pump 30.
   - RED on HEAD because: HEAD keeps the row but the only feedback is the transient `group_invite_needs_key` snackbar (`:361`, asserted at `:1273`); there is NO inline `group_invite_waiting_for_key` text and no trailing spinner state on the card. Asserting the new inline text + absence of the snackbar fails (snackbar still shows on HEAD).
   - GREEN asserts: invite row still present (`find.byKey(ValueKey('pending-group-invite-<id>'))` findsOneWidget, unchanged from `:1270`); inline `group_invite_waiting_for_key` ("Waiting for key") text inside the card; trailing spinner state present; **no** `group_invite_needs_key` snackbar; `group:join` still not called (`:1274` preserved).
   - Mutation that re-reds: restore `_showSnackBar(l10n.group_invite_needs_key)` for repairPending + remove the `waitingForKey` row state → snackbar back / inline gone → red.

5. `group_list_wired_test.dart`::"no accept snackbar is shown for any outcome (lock)"  *(blanket no-snackbar lock)*
   - Tier: integration/widget
   - Shape/setup: run accept to a representative terminal result (e.g. notFound) and to repairPending; after pump, assert `find.byType(SnackBar)` `findsNothing` (covering that the 11-arm snackbars are gone). Success/joinedRecovery navigate, not snackbar.
   - RED on HEAD because: HEAD shows a `SnackBar` for every non-navigating arm → `findsNothing` fails.
   - Mutation that re-reds: re-add any single `_showSnackBar` to an accept arm → `SnackBar` present → red.

6. `group_list_wired_test.dart`::"stuck-rejoin Retry updates the inline badge without a snackbar"  *(new lock; today there is none)*
   - Tier: integration/widget
   - Shape/setup: reuse the stuck-group setup from `:791-808` (rejoinAttempts ≥ `_joinGiveUpThreshold`); tap `group-stuck-retry-<id>` (`:550`); pump.
   - RED on HEAD because: HEAD's `_onRetryStuckRejoin` shows the `group_joining_in_progress` snackbar (`:572`). Asserting `find.byType(SnackBar)` `findsNothing` after the tap fails.
   - GREEN asserts: after tapping stuck-Retry, **no** snackbar; the inline badge/state path still runs (`forceGroupRejoinEligible` + `rejoinGroupTopics` invoked via `bridge.commandLog` / repo spy; `_loadGroups` ran). The existing "Joining…"/"Couldn't join — retry" badge assertions (`:786,:807`) stay green.
   - Mutation that re-reds: restore the `_showSnackBar(joiningMessage)` in `_onRetryStuckRejoin` → snackbar back → red.

7. `pending_group_invite_card_test.dart`::"renders inline reason / waiting-for-key spinner / Retry per outcome param"  *(NEW widget file)*
   - Tier: widget (pump `PendingGroupInviteCard` directly under a `MaterialApp` + `AppLocalizations`)
   - Shape/setup: pump the card with each new outcome value — `idle` (existing accept/decline buttons), `processing` (existing in-button spinner `:152-161` preserved), `waitingForKey` (trailing spinner + `group_invite_waiting_for_key`), `retryable` (inline Retry keyed `pending-group-invite-retry-<id>` fires `onRetry`), `joinedRecovery`/terminal (inline reason text, if rendered on the card).
   - RED on HEAD because: the new outcome param + `onRetry` + `pending-group-invite-retry-<id>` key don't exist → compile-time red (param absent).
   - GREEN asserts: each outcome renders its control; `processing` still shows the in-button `CircularProgressIndicator`; `retryable` Retry key present + fires `onRetry`; existing `pending-group-invite-accept-<id>`/`-decline-<id>` keys + key `pending-group-invite-<id>` unchanged.
   - Mutation that re-reds: remove the `waitingForKey`/`retryable` render branch in `pending_group_invite_card.dart` → controls gone → red.

8. `group_list_wired_test.dart`::"success accept still navigates and removes the row (preservation)"  *(sentinel — existing `:1111`/`:1210` kept green)*
   - Tier: integration/widget
   - Asserts: a `success` accept removes `pending-group-invite-<id>` and lists the group (parity with `:1138-1143`/`:1238-1242`). No change expected; guards the switch rewrite against breaking the navigate arm.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 8 terminal outcomes → inline reason, no snackbar | screen state + reason scoped to card | integration/widget | wired::"terminal accept outcome shows an inline reason …" | HEAD shows snackbar `:343-367`, no inline row state | restore one terminal `_showSnackBar` + drop inline assign | `./scripts/run_test_gates.sh groups` | **add `group_list_wired_test.dart` to `GROUP_TESTS`** |
| TC-02 bridgeError(keep-pending) → inline Retry via guard | inline Retry + guard preserved | integration/widget | wired::"bridgeError keep-pending accept shows an inline Retry …" | HEAD shows `group_invite_accept_failed`, no Retry key | route bridgeError-null back to `_showSnackBar` / bypass `_processingInviteIds` | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-03 bridgeError(group!=null) → navigate + recovery copy | navigate + dead-key wired | integration/widget | wired::"bridgeError with materialized group navigates …" | HEAD `:370` ignores `group!=null`, shows failure, no nav | revert `bridgeError`+`group!=null` branch | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-03a `group_invite_joined_recovery` source-wiring lock | dead-key now referenced | widget/source-lock | wired::"l10n source-wiring lock: group_invite_joined_recovery …" | key dead, zero references → not rendered | remove joinedRecovery wiring | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-04 repairPending → inline "Waiting for key" row, no snackbar | inline row state (rewrite of `:1250`) | integration/widget | wired::"repair-pending accept shows an inline 'Waiting for key' row …" | HEAD shows `group_invite_needs_key` snackbar `:361/:1273` | restore needs_key snackbar + drop waitingForKey row | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-05 no accept snackbar for any outcome | blanket no-snackbar lock | integration/widget | wired::"no accept snackbar is shown for any outcome (lock)" | HEAD shows a SnackBar per non-nav arm | re-add any one `_showSnackBar` accept arm | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-06 stuck-Retry no snackbar, badge updates | redundant-snackbar drop | integration/widget | wired::"stuck-rejoin Retry updates the inline badge without a snackbar" | HEAD shows `group_joining_in_progress` snackbar `:572` | restore `_showSnackBar(joiningMessage)` in `_onRetryStuckRejoin` | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |
| TC-07 card renders outcome param | widget render | widget | pending_group_invite_card_test::"renders inline reason / waiting-for-key spinner / Retry per outcome param" | new outcome/`onRetry` params absent → compile red | remove waitingForKey/retryable render branch | `./scripts/run_test_gates.sh groups` | **add `pending_group_invite_card_test.dart` to `GROUP_TESTS`** (also AUTO host-all glob) |
| TC-08 success navigate+row-removal preserved | preservation | integration/widget | wired::"success accept still navigates and removes the row (preservation)" | n/a (sentinel) | break the success navigate arm → re-reds | `./scripts/run_test_gates.sh groups` | add `group_list_wired_test.dart` to `GROUP_TESTS` |

## Invariants (locked by tests)
- INV-1: every non-navigating accept outcome renders as **per-row inline state** on `PendingGroupInviteCard`, never a snackbar → TC-01/04/05.
- INV-2: a keep-pending `bridgeError` exposes an inline **Retry** that re-enters `_onAcceptPendingInvite` **through** the `_processingInviteIds` guard (no double-arm on rapid taps) → TC-02.
- INV-3: a `bridgeError` whose group materialized (`group != null`) **navigates** and reports join-with-recovery via `group_invite_joined_recovery` — never "Failed to accept invite" → TC-03/03a.
- INV-4: `repairPending` keeps the row with an inline **"Waiting for key"** (`group_invite_waiting_for_key`) state, not a transient snackbar → TC-04.
- INV-5: **no accept snackbar** is shown for any of the 11 outcomes (the 11-arm `_showSnackBar` calls are gone); **no stuck-Retry "Joining…" snackbar** → TC-05/06.
- INV-6: `success` accept still navigates + removes the row; the inline "Joining…"/stuck Retry/Leave badges stay unchanged → TC-08 (+ `:786/:807` sentinels).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`; add/rewrite the catalog tests; run the focused commands and confirm each fails for its documented reason.
2. `pending_group_invite_card.dart`: introduce `enum PendingInviteRowState { idle, processing, waitingForKey, retryable, joinedRecovery }` (or keep `isProcessing` and add an `outcome` param + `inlineReasonText`/`onRetry`); render: preserve the existing in-button spinner for `processing` (`:152-161`); for `waitingForKey` show a trailing spinner + `group_invite_waiting_for_key`; for `retryable` show an inline Retry keyed `pending-group-invite-retry-<groupId>` calling `onRetry`; render `inlineReasonText` as a one-line reason. Keep the `ValueKey('pending-group-invite-<groupId>')` and accept/decline keys intact.
3. `group_list_screen.dart` `:206-225`: pass a per-invite outcome map + `onRetryPendingInvite` into `PendingGroupInviteCard` (alongside `processingInviteIds.contains`).
4. `orbit_screen.dart` `:848`: thread the new params (default to `idle`/no-retry to keep Orbit behavior unless a row outcome is wired) — lock the chosen default in a one-line test note in TC-07.
5. `group_list_wired.dart`: add `Map<String, _InviteRowOutcome> _inviteRowOutcomes` (keyed by invite id) next to `_processingInviteIds` (`:108`); **clear it in `_loadGroups`** (`:136`, in the `setState` at `:169-177`) so a list refresh resets stale row state. Add `_onRetryPendingInvite(invite) => _onAcceptPendingInvite(invite)` (no guard bypass). Pass the map + retry callback through `build` (`:622-639`).
6. `group_list_wired.dart` rewrite the switch (`:333-372`): `success` → navigate (unchanged `:338-340`); `bridgeError` → if `group != null` set `joinedRecovery` + navigate + surface `group_invite_joined_recovery`, else set `retryable`; `repairPending` → set `waitingForKey`; the 8 terminal arms → set their inline reason (reuse existing copy: `group_invite_no_longer_available`, `group_invite_expired`, `group_invite_expired_ask_resend`, `group_invite_revoked`, `group_invite_already_used`, `group_invite_wrong_identity`, `group_invite_invalid`, `group_invite_duplicate_group`) and **delete the `_showSnackBar` call**. Delete the success-arm snackbar (`:335`). **Stop-if:** the use-case can't distinguish shape-a vs shape-b → it already does via `group` (`:562-568`); do not add a new result value.
7. `group_list_wired.dart` `_onRetryStuckRejoin` (`:568-587`): delete the `joiningMessage` snackbar (`:569,:572`); keep `forceGroupRejoinEligible` + `rejoinGroupTopics` + `_loadGroups`.
8. l10n: add `"group_invite_waiting_for_key": "Waiting for key"` (plain string, no @-metadata) to `app_en.arb`, `app_ar.arb`, `app_de.arb` **by KEY** (append where the other `group_invite_*` keys sit; en vs ar/de line offsets diverge). `group_invite_joined_recovery` already exists in all three — no add, only wire. Regenerate l10n (`flutter gen-l10n` / build).
9. `scripts/run_test_gates.sh`: add `test/features/groups/presentation/group_list_wired_test.dart` and `test/features/groups/presentation/widgets/pending_group_invite_card_test.dart` to the `GROUP_TESTS` array (`:116-132`).
10. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Stale row state across refreshes**: a row outcome set on accept must clear on the next `_loadGroups` (group joined → row removed; invite re-listed → reset) → pinned by clearing in `_loadGroups` (`:136`) and by TC-01/TC-08.
- **Guard bypass via inline Retry**: routing Retry around `_processingInviteIds` would double-arm rapid taps → pinned by TC-02's double-tap assertion.
- **Shape-a vs shape-b bridgeError mis-bucket**: keying off `group != null` is the only discriminator → TC-02 (null→Retry) vs TC-03 (non-null→navigate) lock both sides.
- **Existing repairPending tests** (`:1250`, `:1278`) assert the transient snackbar copy — both touch repairPending; rewrite/align both to inline (TC-04). Do not leave one asserting the dropped snackbar.
- **Orbit callsite** (`orbit_screen.dart:848`) shares the widget — adding required params without defaults would compile-break Orbit; default to `idle`/no-retry there.
- **SnackBar finder scope**: `find.byType(SnackBar)` is global; assert reason text via `find.descendant(of: card)` to avoid confusing inline reason with a toast (TC-01 discriminator).

## Device/Relay Proof Profile
host-only for closure. No OS-boundary / ML-KEM / relay / multi-device leg — the accept result is produced by an already-host-tested use-case; this plan only re-renders that result as local screen state. No migration, no flag flip.
Deferred device work → none.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'terminal accept outcome shows an inline reason'
flutter test test/features/groups/presentation/group_list_wired_test.dart \
  --plain-name 'repair-pending accept shows an inline'
flutter test test/features/groups/presentation/widgets/pending_group_invite_card_test.dart \
  --plain-name 'renders inline reason'

# Direct GREEN (after fix)
flutter test test/features/groups/presentation/group_list_wired_test.dart
flutter test test/features/groups/presentation/widgets/pending_group_invite_card_test.dart

# Preservation + named gate (after adding both tests to GROUP_TESTS)
./scripts/run_test_gates.sh groups        # expect prior green count + the new wired/card cases; the 2 PRE-EXISTING failing wired tests (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
./scripts/run_test_gates.sh feed          # surface/LetterCard variants stay green

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: TC-01..07 before the fix (snackbar-instead-of-inline / missing params / dead key).
- Pre-existing dirty (NOT mine): the Groups suite has **2 pre-existing failing wired tests** — GMAR-004 reopen-hydration and incoming-group-image-refresh (media reopen/hydration, unrelated). Record before execution; do not "fix" by reverting. (`group_list_wired_test.dart` itself is expected green on HEAD aside from my RED edits — snapshot it.)
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside the listed files/tests, or any touch to the decline path / use-case enum / sender-side delivery status.

## Done Criteria
- [ ] RED added/rewritten first, failed for the expected reason.
- [ ] Each fix mutation-verified (re-red revert named in the matrix).
- [ ] Direct GREEN + groups/feed preservation gates pass; the 2 pre-existing wired fails unchanged.
- [ ] No migration introduced (DB stays v92; all state is in-State presentation).
- [ ] `group_list_wired_test.dart` AND `pending_group_invite_card_test.dart` added to `GROUP_TESTS` and confirmed running in `./scripts/run_test_gates.sh groups`.
- [ ] 1 new l10n key `group_invite_waiting_for_key` present in en/ar/de; `group_invite_joined_recovery` now referenced (no longer dead); l10n regenerated.
- [ ] 11 accept snackbars + the stuck-Retry "Joining…" snackbar removed (no remaining consumers); `flutter analyze` 0-new; `git diff --check` clean.

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump the identity DB version (no schema change — DB v92 stays).
- Do not edit `accept_pending_group_invite_use_case.dart` result values or the recovery-retry loop timing.
- Do not touch the decline path (`_onDeclinePendingInvite`) or the sender-side `group_invite_status_presentation.dart` (different enum).
- Do not bypass `_processingInviteIds` from the inline Retry (INV-2).
- Do not keep any accept snackbar "just in case" — the inline row state is the replacement (INV-5).

## Accepted Differences / Intentionally Out Of Scope
- The **decline** outcomes stay on snackbars — accepted; owner = a future "decline outcomes inline" session (the accept switch is the reviewed surface).
- Terminal inline reason reuses the **existing** terminal copy strings (no new per-outcome keys) — accepted (avoids 8×3 new l10n entries); only `group_invite_waiting_for_key` is genuinely new and `group_invite_joined_recovery` is resurrected.
- Orbit's `PendingGroupInviteCard` keeps default `idle`/no-retry behavior unless its own accept flow wires outcomes — accepted (this plan scopes the outcome surface to the group list / stuck-rejoin review).

## Dependency Impact
- None outbound. The harness-registration fix (adding `group_list_wired_test.dart` to `GROUP_TESTS`) also retroactively gates ALL pre-existing accept/decline/stuck-rejoin behavior under the curated Group gate — a standalone hardening win (today that file only runs under host-all).

## Reviewer Findings
<sufficiency / missing-coverage / scope-risk verdict — to be filled at review>

## Arbiter Decision
Structural blockers: … | Deferred details: … | Accepted differences: … (final structural verdict at review)

## Final Execution Verdict
Verdict: (accepted/rejected) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner):
