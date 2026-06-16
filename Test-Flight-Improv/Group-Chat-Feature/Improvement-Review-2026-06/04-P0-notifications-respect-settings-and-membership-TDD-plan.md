> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · TDD plan for **[04-P0-notifications-respect-settings-and-membership.md](./04-P0-notifications-respect-settings-and-membership.md)**

---

# TDD Plan — Make notifications honor mute, membership, and one-per-message

**Status: PLAN ONLY.** Decomposed for TDD execution. Verified against HEAD `124-harness-refactor` (commit `41061593`).

> Companion to the [finding](./04-P0-notifications-respect-settings-and-membership.md). The finding describes *what's wrong* and proposes QW-1/2/3 + SI-1..SI-6. This plan re-verifies each against current source, **corrects two framing errors in the finding**, and carves out a **Dart-only, security-neutral, no-native-rebuild slice that ships now**, deferring the iOS-NSE / Android-decrypt / relay work to a separate native track with its own gates.

---

## 0. Resolution verification (is the finding still open?)

**Yes — open.** A graph-first verification + adversarial re-check pass (17 agents: 8 per-section verifiers, each independently refuted, then synthesis) scored the finding **6 items CONFIRMED_LIVE, 2 PARTIALLY_RESOLVED, 0 fully resolved**. Every behavioral claim that could be checked is accurate; only Dart-side **line numbers drifted** (the doc predates this branch) and two *framing* claims are wrong (corrected below).

| Item | § | Status | Anchor proof (HEAD `124-harness-refactor`) |
|---|---|--------|---------------------|
| **QW-1** sanitize live banner | §7 | **CONFIRMED_LIVE** | banner body interpolates **raw** wire fields `'$senderUsername: ${notificationBodyForMessage(text, …)}'` (`group_message_listener.dart:951-952`) from raw locals `:765`/`:767`; sanitized `result` is in scope + non-null at `:937`/`:925` but ignored by the banner |
| **QW-2** dead tap on missing group | §6 | **CONFIRMED_LIVE** | `resolution.group == null && !hasPendingInvite` → bare `return` with no nav, no feedback (`main.dart:3156-3173`); `grep ScaffoldMessenger\|SnackBar lib/main.dart` = **0 matches** |
| **QW-3** dedupe decode observability | §5 | **CONFIRMED_LIVE** | both gates `_loadEntries` end in `catch (_) { return {} }` with zero telemetry (`recent_remote_notification_gate.dart:135-137`, `recent_background_notification_gate.dart:96-98`); the non-Map branch (`:115-117`) silently returns `{}` too |
| **SI-1** mute honored everywhere | §1 | **CONFIRMED_LIVE** | mute consulted in exactly one place — live GossipSub (`group_message_listener.dart:937-940`); `setGroupMuted` writes DB only (`set_group_muted_use_case.dart:28-29`); NSE has zero mute refs; background + foreground push producers are mute-blind |
| **SI-2** membership across producers | §2 | **PARTIALLY_RESOLVED** | live path (`handle_incoming_group_message_use_case.dart:192`) **+ both Dart push producers** already gate membership (bg encrypted-DB `background_message_handler.dart:300-305`; fg repo-backed `resolve_group_notification_route_target_use_case.dart:112-119`). **Open: iOS NSE only** (`NotificationPreviewResolver.swift:252-262` key-presence only) **+ relay fanout** (`inbox.go` pushes the sender's recipient snapshot; no membership state) |
| **SI-3** Android generic previews | §3 | **CONFIRMED_LIVE** | resolver typedef carries only `RemoteMessage` (`background_message_handler.dart:28-29`,`:165`) → `decryptGroup`/`decryptOneToOne` always null → decrypt body dead (`push_decrypt_preview.dart:111-122`); forced generic copy (`background_push_notification_fallback.dart:258-262`). **Also kills 1:1 previews** (`_resolveOneToOnePreview :54-64`), not just group |
| **SI-4** durable gate storage | §5 | **CONFIRMED_LIVE** | both gates default to `Directory.systemTemp` (`recent_remote_notification_gate.dart:33-35`, `recent_background_notification_gate.dart:32-34`); no `path_provider`/app-support anywhere in `lib/core/notifications/` |
| **SI-5** NSE-vs-live dedupe | §4 | **CONFIRMED_LIVE** | NSE's only dedupe store is the app-group `NotificationServiceDedupe` lockfile (`NotificationPreviewResolver.swift:389,:398-417`); it writes **nothing** the Dart `systemTemp` gate reads → suppression of an NSE banner needs the Dart isolate to run |
| **SI-6** foreground drain fallback | §8 | **PARTIALLY_RESOLVED** | membership gate **landed** (`main.dart:3691-3699` → `resolve_…:112-119`, non-bypassable). Still **contentless** (forced generic `background_push_notification_fallback.dart:258-262`), **no decrypt**, **mute-blind** |

### Two framing errors in the finding (correct before citing it)

1. **§2 / SI-2 is over-stated as a clean open finding.** It is mostly **already landed on the Dart side** (commit `8ba68cd7`/"106", which *is* in this branch). The live path **and** both Dart push producers enforce local membership today. The genuinely open part is narrower: **the iOS NSE and the relay only.** Do **not** re-implement the Dart membership gates.
2. **§4 / SI-5 claim "the marker is written ONLY inside `firebaseMessagingBackgroundHandler`" is false.** The live 1:1 path also writes it (`chat_message_listener.dart:582-588`, "118 Phase-2 live-wins"). This does **not** weaken SI-5 (that writer still runs in the Dart isolate, so NSE-banner suppression still depends on the isolate firing) — but the plan must not assume a single writer.

Minor: §8/SI-6's **membership** sub-claim is already RESOLVED (don't re-do it); the doc's "`sanitizeMessageText` strips control chars" (§7/A2) is loose — the bidi regex strips a *specific* zero-width/legacy-bidi subset (`text_sanitizer.dart:17-21`) and intentionally preserves ZWJ/LRM/RLM/ALM/isolates. Conclusion unchanged. Citation drift is pervasive but cosmetic.

---

## 1. Critical assessment & scoping decision

The finding's nine items are **not a monolith** and splitting them is mandatory:

- **SI-2 (NSE membership) + SI-5 (NSE-authoritative dedupe) + SI-3 (Android decrypt) + SI-1's NSE half** all require **out-of-process / native work** — Swift edits + an Xcode/`pod install` rebuild + the iPhone13/Pixel6 device matrix, or a push-DI refactor to thread decrypt callbacks into the background isolate. They cannot be host-test-proven on this branch and several touch the crypto/key-distribution surface (the NSE reading a new app-group projection; a removed member's retained-epoch-key window).
- **SI-2's relay half** needs the relay to hold membership state it has **zero** of today (`grep` over `go-relay-server/*.go` = no membership state) — a relay protocol + redeploy change. Heaviest item.
- **QW-1, QW-3+SI-4, the Dart half of SI-1, and QW-2** are **pure Dart, security-neutral, no native rebuild**, and close the two most-broken user promises — *"I muted this"* (on Android background + all foreground) and *"don't render attacker-controlled text in my most-trusted surface"* (the banner) — plus the silent dead-tap and the silent dedupe-loss.

### The key simplification this plan makes over the finding

The finding's **SI-1** proposes an app-group `group_muted:<groupId>` projection as the mechanism for *every* producer to honor mute. **That is only necessary for the out-of-process iOS NSE.** Both Dart producers **already load the group row**:

- background encrypted-DB resolver calls `dbLoadGroup(db, groupId)` → row carries `is_muted` (`background_message_handler.dart:300`);
- foreground repo-backed resolver calls `groupRepo.getGroup(groupId)` → `GroupModel.isMuted` (`resolve_group_notification_route_target_use_case.dart:112`).

So **Slice 1 honors mute in both Dart producers with no projection, no new storage, no migration, no toggle-time write, no backfill** — a one-line suppression at each existing `allowCurrentMember()` site. The projection + backfill becomes a Slice-2 concern scoped strictly to the NSE.

### What Slice 1 actually delivers on each surface (be honest)

| Surface | Mute honored after Slice 1? | Why |
|---|---|---|
| Live in-app (both OS) | already honored | `group_message_listener.dart:940` |
| Foreground drain fallback (both OS) | **YES (new)** | repo-backed resolver reads `GroupModel.isMuted` |
| Android background banner | **YES (new)** | Dart bg handler `.show` gated by encrypted-DB resolver reading `is_muted` |
| **iOS background banner (NSE)** | **NO — deferred to Slice 2** | NSE can't open the encrypted DB; needs the app-group projection + Swift read |

### Recommended scope

- **Slice 1 (this plan, execution-ready):** `QW-1`, `QW-3 + SI-4`, `SI-1 (Dart half)`, `QW-2`. Four independent Dart-only sessions, each with an existing test seam, no DB migration, no native rebuild.
- **Slice 2 (specified, deferred):** the native/relay track — `SI-1 NSE projection+read`, `SI-2 NSE membership + relay fanout`, `SI-3 Android decrypt`, `SI-5 NSE-authoritative dedupe`, `SI-6 decrypt-on-fallback`. Each behind a threat-model note + the two-device matrix. Mirrors the finding's own rollout order (lowest-risk first).

No shared test-fake extraction prep is needed — every Slice-1 session uses an existing seam (contrast the undecryptable plan's Session 0).

---

## 2. Slice 1 — Dart-only (execution-ready, security-neutral)

All four sessions are TDD: write the RED test(s) first, then the minimal GREEN change. The four are **mutually independent** (no shared file beyond test scaffolding) and may land in any order or in parallel; the order below is by impact × isolation.

### Session 1 (QW-1) — banner uses sanitized, member-bound fields

**Root cause (§7).** The OS banner body interpolates the **raw wire** `senderUsername`/`text` (`group_message_listener.dart:951-952`, from locals `:765`/`:767`), while the timeline/DB record uses the sanitized, member-bound `result.senderUsername` (`= resolveGroupSenderDisplayName(…)`) and `result.text` (`= sanitizeMessageText(…)`). The banner can render bidi/zero-width/overlong content the timeline never shows, under a different name than the resolved member-bound one.

**RED tests (write first)** — `test/features/groups/application/group_message_listener_test.dart`:
1. *"banner body uses the sanitized/member-bound result, not raw wire fields"*: deliver a live group message whose wire `senderUsername` contains a zero-width/bidi sequence + a >30-char name and whose `text` contains a stripped control char; assert the captured `maybeShowNotification` `messageText` equals `'${result.senderUsername}: ${notificationBodyForMessage(result.text, …)}'` — i.e. the sanitized name (truncated ≤30, bidi-stripped) and sanitized text, **not** the raw wire bytes. Reuse the existing listener harness + the `maybeShowNotification` spy already in this file.
2. *Guard:* the banner **title** slot stays `groupName` (`group?.name ?? 'Group'`) — unchanged.
3. *Guard:* for a plain message, the new body is byte-identical to the old (sanitization is a no-op on clean input) — no regression in the common case.

**GREEN edit** — `group_message_listener.dart:951-952`, inside the `if (result != null)` block (`:925`):
```dart
messageText:
    '${result.senderUsername ?? ''}: '
    '${notificationBodyForMessage(result.text, persistedAttachments)}',
```
`result.senderUsername` is structurally non-null (`resolveGroupSenderDisplayName` terminal fallback `group_sender_display_name.dart:24` returns `groupPeerFallbackLabel`), so the `?? ''` never fires in practice but satisfies the nullable model field. **No wire/DB change.**

**Migration:** none. **Coupling:** none. **Risk:** essentially zero — `result` is already persisted from these exact values; this only redirects the banner to the same sanitized source the timeline uses.

---

### Session 2 (QW-3 + SI-4) — durable gate storage + decode-error observability

**Root cause (§5).** Both dedupe gates default `filePath` to `Directory.systemTemp` (OS-evictable) and both `_loadEntries` end in a bare `catch (_) { return {} }` (`recent_remote_notification_gate.dart:135-137`, `recent_background_notification_gate.dart:96-98`); the non-Map branch (`:115-117` / `:81-83`) also returns `{}` silently. A wiped/corrupt file is indistinguishable from "no entries" → silent dedupe bypass + silent lapse of the 12h redelivery guard (`recentRemoteNotificationMessageTtl`, `:7`), with zero telemetry.

**RED tests (write first)** — `test/core/notifications/recent_remote_notification_gate_test.dart` and `recent_background_notification_gate_test.dart`:
1. *Decode-error telemetry:* construct the gate with an injected `onLoadError` spy + an explicit `filePath` pointing at a file containing non-JSON garbage; call `consumeIfRecentAnnouncement`/`wasRecentlyShown`; assert the spy fired exactly once (and that a clean miss — absent/empty file — does **not** fire it).
2. *Non-Map telemetry:* same with a valid-JSON-but-non-object payload (`"[]"`); assert telemetry fires.
3. *Durable path:* construct the gate with an injected `supportDirectoryProvider` returning a temp dir; assert the resolved path lands under that dir (not `systemTemp`); and that an explicit `filePath` still wins over the provider (tests stay fully synchronous-pathed).
4. *Provider-failure fallback:* a provider that throws → path falls back to `systemTemp` **and** emits a fallback telemetry event (gate never crashes).

**GREEN edits** (both gate files, mirroring each other):
- Add `import 'package:flutter_app/core/utils/flow_event_emitter.dart';`.
- Add two optional ctor seams (alongside the existing `now` seam): `Future<Directory> Function()? supportDirectoryProvider` (default `getApplicationSupportDirectory` from `package:path_provider/path_provider.dart`) and `void Function(Object error, StackTrace stack)? onLoadError` (default emits `RECENT_REMOTE_NOTIFICATION_GATE_DECODE_ERROR` / `RECENT_BACKGROUND_NOTIFICATION_GATE_DECODE_ERROR`).
- Make path resolution **lazy + cached**: if an explicit `filePath` was passed, use it verbatim (sync, test-friendly); else on first IO `await supportDirectoryProvider()` once, build `'<dir>/mknoon_recent_*_notifications.json'`, cache it; on provider error fall back to `Directory.systemTemp` and emit a `…_DIR_FALLBACK` event. Every IO method (`_loadEntries`/`_writeEntries`/`clear`) awaits the resolver.
- In `_loadEntries`: change `catch (_)` → `catch (e, st) { onLoadError(e, st); return {}; }`, and emit on the non-Map branch too (a corrupt-but-valid-JSON file is still a decode failure).

**Migration:** none (files only). **Coupling:** none. **Risk:** `path_provider` uses platform channels — pure unit tests must inject either an explicit `filePath` or a fake provider (the production singletons resolve lazily, so app code is unaffected). The lazy resolver must be **idempotent and race-safe** (cache a `Future<String>`, not re-resolve per call). Tests that already construct gates with explicit temp `filePath`s remain 100% synchronous and unchanged — important for any sync-teardown test bootstrap (see [[feedback_testwidgets_sync_io_only]]).

---

### Session 3 (SI-1, Dart half) — honor mute in both Dart push producers

**Root cause (§1).** Mute (`group.isMuted`, migration 050) is read only on the live path. The background and foreground push producers each already resolve membership from the group row but never check mute, so a muted group still buzzes on Android background and on foreground drain-failure.

**RED tests (write first):**
1. `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` — *"a current member of a muted group is suppressed with reason `group_muted`"*: stub `groupRepo.getGroup` to return a `GroupModel` with `isMuted: true` and `getMember` non-null; assert `resolveGroupMessageNotificationDisplayEligibility(...).shouldDisplay == false` and `.reason == 'group_muted'`. Guard: `isMuted: false` member still `allowCurrentMember()`.
2. `test/features/push/application/background_push_notification_fallback_test.dart` — drive `showForegroundPushFallbackNotificationIfNeeded` with a `groupMessageDisplayEligibilityResolver` that returns `suppressed('group_muted')`; assert it returns `false` and `notificationService.showNotification` is **not** called, and a `PUSH_FOREGROUND_FALLBACK_NOTIFICATION_SUPPRESSED` event fires (existing suppression path — no new code, just coverage that mute routes through it).
3. `test/features/push/application/background_message_handler_test.dart` — the background encrypted-DB resolver path: seed the read-only `identity.db` fixture with a group row `is_muted = 1` + a present member row; assert the handler **suppresses** (`PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED`) and never calls `.show`. (If this test file already builds the in-memory `identity.db` fixture for the membership tests, extend it; otherwise the membership-suppression test it must already contain is the template.)

**GREEN edits** (two one-spot changes at the existing `allowCurrentMember()` sites):
- `resolve_group_notification_route_target_use_case.dart:118-120` (foreground / repo-backed):
```dart
if (localMember != null) {
  if (existingGroup.isMuted) {
    return const GroupMessageNotificationDisplayEligibility.suppressed('group_muted');
  }
  return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
}
```
- `background_message_handler.dart:303-305` (background / encrypted-DB):
```dart
if (memberRow != null) {
  if ((groupRow['is_muted'] as int? ?? 0) == 1) {
    return const GroupMessageNotificationDisplayEligibility.suppressed('group_muted');
  }
  return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
}
```
Both consume `displayEligibility.shouldDisplay` already (bg `:150`, fg `:157-174`), so suppression is automatic. **No projection, no new storage, no toggle-time write, no migration.** (Confirm `dbLoadGroup` is `SELECT * FROM groups` — `groups_db_helpers.dart:69`, the same row `GroupModel.fromMap` consumes — so `is_muted` is present.)

**Migration:** none. **Coupling:** none. **Risk:** mute is checked only for a confirmed member (you can't mute a non-membership), so it composes cleanly with the existing membership gate and matches the live path's semantics (mute = full suppression, not merely silent). **Explicitly out of scope here:** the iOS NSE (Slice 2) — call this out in the PR so the deferred surface is documented, not forgotten.

---

### Session 4 (QW-2) — feedback on the unrecoverable-group dead tap

**Root cause (§6).** Tapping a group push when `resolution.group == null` and there's no pending invite returns silently (`main.dart:3156-3173`) — no navigation, no toast. `main.dart` has **zero** `ScaffoldMessenger`/`SnackBar` usage, so there is no messenger to show feedback through.

**RED tests (write first):**
1. Refactor for testability first: extract the *decision* from `main.dart` into the already-tested use case. Add to `resolveGroupNotificationRouteTarget` (or a thin sibling) a typed outcome the handler can act on — e.g. `GroupNotificationRouteResolution.missing()` already exists; add a discriminator so the handler knows to **show feedback + route home** vs **redirect to intros** (pending invite). Test in `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` + augment `test/features/push/application/chat_and_group_push_open_flow_test.dart` to assert the missing-no-invite branch yields the "show feedback" outcome (not a silent miss).
2. Widget/route test (new, `test/.../group_missing_notification_tap_feedback_test.dart`) pumping a minimal `MaterialApp` with the `scaffoldMessengerKey`, invoking the missing-no-invite branch, asserting (a) a `SnackBar` is shown with the l10n string and (b) navigation falls back to the home/group-list route (not a no-op). This is the one **weak seam** (the logic currently lives inline in `main.dart`); the extraction in step 1 is what makes it testable.

**GREEN edits:**
- `main.dart`: add `static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();` next to `navigatorKey` (`:2705`) and set `scaffoldMessengerKey: MyApp.scaffoldMessengerKey` on the `MaterialApp` (`:3748-3750`).
- In the `resolution.group == null && !hasPendingInvite` branch (`:3156-3173`): keep the `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING` flow event; then show `MyApp.scaffoldMessengerKey.currentState?.showSnackBar(...)` with a Retry action and route the navigator to home/group-list instead of bare `return`. (The targeted drain inside `resolveGroupNotificationRouteTarget` `:88` already runs once; a Retry re-invokes the same tap handler — do **not** add an unbounded retry loop.)
- l10n: add the SnackBar string (e.g. `groupNotificationCatchingUp`) to `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb` and regenerate `app_localizations*.dart`.

**Migration:** none (l10n strings only). **Coupling:** none. **Risk:** lowest user-severity item (rare state), but the only one needing a `MaterialApp` wiring change + l10n regen; ship last. Keep the messenger-key addition minimal so it doesn't perturb existing navigator-key tests.

---

## 3. Slice 2 — native / relay track (specified, deferred)

Land **after** Slice 1 is device-verified. Each item needs a native rebuild and/or relay deploy, so none is host-test-only. Group the three NSE items so the app-group-projection plumbing is built once.

- **SI-1 NSE mute (completes Session 3 on iOS):** add `sharedGroupMutedKeyName(groupId) => 'group_muted:$groupId'` beside `sharedGroupPushKeyName` (`group_repository_impl.dart:11-12`); in `setGroupMuted`, mirror via `pushSharedKeyStore.write`/delete by **cloning `_mirrorGroupKeyForPush`** (`:463-490`) + a launch-time backfill from DB `isMuted` (reuse the existing key-mirror reconciliation pattern); read it in `NotificationPreviewResolver.resolveGroup()` and **suppress** the banner. *Threat model:* fail-open to generic on missing projection. *Gate:* Xcode rebuild + iOS device proof.
- **SI-2 NSE membership:** mirror a `group_membership:<groupId>` sentinel (same plumbing as the mute projection) updated on every membership change + **delete the epoch group key from the app-group Keychain on removal/leave** (`_deleteGroupKeyMirror` `group_repository_impl.dart:492-514` already exists — ensure it fires on remove/leave); NSE consults the sentinel to suppress. Closes the retained-epoch-key window. *Bundle with SI-1 NSE* (shared projection infra).
- **SI-2 relay fanout:** give the relay current-membership at fanout time so `fanOutPush` drops removed peers / includes new ones instead of trusting `req.RecipientPeerIds`. **Heaviest** — relay protocol + redeploy + 3-party device proof. The relay holds no membership state today.
- **SI-3 Android decrypt:** widen the `BackgroundPushNotificationResolver` typedef (`background_message_handler.dart:28-29`) to carry `decryptGroup`/`decryptOneToOne`, construct a headless Go bridge + app-group key reader in `firebaseMessagingBackgroundHandler`, and inject the decrypt closures (the `_resolveGroupPreview`/`_resolveOneToOnePreview` bodies are already written + unit-tested in `push_decrypt_preview.dart`). Delivers `sender: text` previews on Android (and 1:1). Pure Flutter-isolate work but a real push-DI refactor; medium effort, UX-only impact. Apply the Session-3 mute + membership checks here too once decrypt lands.
- **SI-5 NSE-authoritative dedupe:** have `NotificationService.didReceive` write a Dart-readable recent-remote marker into the **app-group container** (keyed `message:<payload>|<messageId>`, atomic `O_CREAT|O_EXCL` like the existing `AppGroupPushDedupeStore.claim`), and point `RecentRemoteNotificationGate` at the app-group container on iOS (depends on **SI-4** having relocated the gate). Removes the dependency on iOS scheduling the Dart isolate. *Prereq:* Session 2 (SI-4) done.
- **SI-6 decrypt-on-fallback:** on foreground group drain failure, retry the targeted drain once, then decrypt the preview in-process (bridge + keys available when foregrounded) so the fallback shows `sender: text`; the **mute** half is already delivered by Session 3 and the **membership** half already landed. Depends on the same decrypt seam as SI-3.

---

## 4. Test & verification strategy

**Slice 1 — host gates (deterministic, gate every PR):**
- Session 1: `test/features/groups/application/group_message_listener_test.dart` (banner sanitization + title-unchanged + clean-input no-op).
- Session 2: `test/core/notifications/recent_remote_notification_gate_test.dart` + `recent_background_notification_gate_test.dart` (decode-error telemetry, non-Map telemetry, durable-path resolution, explicit-`filePath` precedence, provider-failure fallback).
- Session 3: `resolve_group_notification_route_target_use_case_test.dart` (`group_muted` suppression) + `background_push_notification_fallback_test.dart` (foreground muted → no `showNotification`) + `background_message_handler_test.dart` (background `is_muted=1` → suppressed, no `.show`).
- Session 4: `resolve_group_notification_route_target_use_case_test.dart` + `chat_and_group_push_open_flow_test.dart` (missing-no-invite outcome) + new widget test for the SnackBar + home route.
- **Regression sweeps:** groups suite + `test/features/push/` + `test/core/notifications/` green; `flutter analyze` 0 new issues. Per project history these push/notification suites can flake under parallel test due to a shared-global-gate-file race — run `-j 1` if the parallel run is noisy (the SI-4 gate relocation should *reduce* this since prod no longer uses `systemTemp`, but verify).

**Slice 2 — device matrix (deferred, per item):** iOS NSE suppression of muted + removed-member banners (TestFlight); Android `sender: text` previews + mute/membership suppression on the Pixel6 (`21071FDF600CSC`); one-per-message under throttling for SI-5. Update `Test-Flight-Improv/52-notification-journey-test-matrix.md` so SM-004/GMN-102/GMN-103/RG-006 cite the new push/NSE coverage rather than only the live-listener test.

---

## 5. Risks, trade-offs & rollout

| Risk | Mitigation |
|---|---|
| SI-4 `path_provider` channel unavailable in pure unit tests | Lazy resolver only fires when no explicit `filePath`; tests inject `filePath` or a fake provider; prod falls back to `systemTemp` + telemetry on provider error |
| SI-4 lazy path resolution races across concurrent gate calls | Cache a single `Future<String>` and await it everywhere (resolve once) |
| Session 3 reads `groupRow['is_muted']` raw | Confirm `dbLoadGroup` is `SELECT *` (`groups_db_helpers.dart:69`); coalesce `as int? ?? 0` so a null/absent column fails *open* (notifies), never silently drops |
| Mute suppression hides a real message if `isMuted` is stale | DB is the source of truth and is read live each time on both Dart paths; no projection to drift (the projection-drift risk is a **Slice-2/NSE** concern only) |
| QW-2 `MaterialApp` messenger-key change perturbs navigator tests | Additive `GlobalKey`; extract the decision into the use case so the branch is unit-tested without `main.dart` |
| Push/notification suites flake under parallel test (pre-existing shared-gate-file race) | Run `-j 1` to confirm green; SI-4 removing `systemTemp` from prod paths should shrink the shared surface |

**Rollout order:** Slice 1 sessions are independent — land in impact order (1 → 3 → 2 → 4) or in parallel; each is individually shippable with no native rebuild. Then Slice 2, NSE items first (shared projection infra), relay last, each behind its device gate and (for SI-1/SI-2 NSE) a fail-open flag validated by `RG-007` degrade-rate telemetry before hard suppression.

---

## 6. Effort estimate

| Session | Effort | Notes |
|---|---|---|
| 1 — QW-1 banner sanitize | **S** | one-line body swap + 3 tests |
| 2 — QW-3 + SI-4 gate durability + telemetry | **S–M** | two gate files, lazy path + telemetry seams, 8 tests |
| 3 — SI-1 mute (Dart half) | **S** | two one-spot suppressions, 3 tests, **no projection/migration** |
| 4 — QW-2 dead-tap feedback | **M** | messenger key + use-case extraction + l10n regen + widget test |
| **Slice 1 total** | **Small–Medium** | Dart-only, no migration, no native rebuild, ships now |
| Slice 2 — NSE mute + membership | **L** | Swift + app-group projection + backfill + device proof |
| Slice 2 — Android decrypt | **L** | push-DI refactor (headless bridge in isolate) |
| Slice 2 — relay fanout | **L** | relay protocol + deploy + 3-party proof |
| Slice 2 — SI-5 / SI-6 | **M each** | depend on SI-4 / the decrypt seam |
