# Notification Behavior & E2E Coverage Map (UI-23)

- **Maps:** [PRD v1.2](./Mknoon_Private_Reliable_Notifications_PRD_v1.2.md) user-visible notification behavior (§6, §6.1–6.4, §9, §13, AC-01–AC-12) ↔ the tests that exist ↔ the gaps.
- **Siblings:** the [Codebase Coverage and Gap Assessment](./Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) owns the A-01–A-30 architecture traceability and GAP-N01–N12; this file owns the narrower, user-visible question: *which notification appears, with which sound, under which condition — and which test proves it on a real device*.
- **Closure vehicle:** [Plan 378](../Test-Flight-Improv/378-notification-e2e-sound-and-suppression-verification-tdd-plan.md) — **EXECUTED 2026-08-17 at host/contract tier**. G1, G2, G3, G5, G6 and G-reg are implemented and green at host tier; their **device** legs were blocked by the G9 harness-start defect, which is **FIXED** (2026-08-17, §4.9) — the first full S1–S16 campaign run is the remaining step. G4 was carved out to [Plan 379](../Test-Flight-Improv/379-muted-group-device-verification-carveout.md), which **closed it at device tier on 2026-08-18** (§4.2).
- **Assessed:** 2026-08-17, branch `protected-view`. All `file:line` anchors verified against source that day; line numbers drift — re-locate with `python3 graphify-arch/tdd_context.py query "<symbol>" --profile general --budget 600` before trusting an anchor in the future.
- **Reading the statuses:** "HOST-STRICT" below means the disposition is now *enforced by a machine contract* (`scripts/test/notification_sound_disposition_contract_test.sh`) and the device scenario exists and is registered, but no device run has yet produced its evidence — the G9 harness blocker is fixed (§4.9); the campaign run is pending.

---

## 1. The expected model — three dispositions, no "low sound" tier

The PRD (§6, §6.1–6.3, §9), the adopted OQ-01/OQ-05 resolutions (coverage doc §6.1/§6.5), and the actual decision engine (`lib/features/push/application/show_notification_use_case.dart:74-376`) define **three outcomes, identical for 1:1 and group**. There is no quiet-volume sound anywhere in the app — the middle tier is a fully silent visible update.

| Disposition | What the user experiences | Mechanism |
|---|---|---|
| **Audible** | OS card + default sound + vibration | High channel `mknoon_messages` (Importance.high, playSound) — `lib/core/notifications/local_notification_support.dart:16-21`. iOS `presentSound: true`. |
| **Silent-visible** (colloquially "low sound") | OS card posts/updates in place; **no sound, no vibration**, low importance | Silent channel `mknoon_messages_silent` (`playSound: false`, `enableVibration: false`, `onlyAlertOnce: true`) — `local_notification_support.dart:23-30`, selection seam `:85`. iOS `presentSound: false`. |
| **Suppressed** | Nothing — no card, no sound; the open timeline just updates | `maybeShowNotification` returns before the native show boundary. |

### 1.1 What picks audible vs silent — the 30-second tone window

Per-conversation window, anchored to the **last audible** tone (silent updates do not extend it):

- First notification for a conversation after ≥30s of quiet → **audible**; every further one for that conversation within the window → **silent-visible**.
- Foreground/live path: in-memory `NotificationToneTracker` (`lib/core/notifications/notification_tone_tracker.dart:34-43`).
- FCM background isolate + main app share the file-locked `DurableNotificationToneLease` (same 30s window, `lib/core/notifications/durable_notification_tone_lease.dart:349`); the production listener wires it **by default** (`lib/features/conversation/application/chat_message_listener.dart:166-168`); background handler reserve at `lib/features/push/application/background_message_handler.dart:955-971`. **Fail-open to audible** if lease storage breaks (`:971`).
- Forced silent (silent-visible regardless of window): explicit `forceSilent`, the iOS mailbox-alert silent replay context, and the Android headless-recovery generic-alert ambiguity marker — `show_notification_use_case.dart:101-104`.

### 1.2 What picks suppressed

- **Same chat open** — app `resumed` + exact 1:1 peer or exact `group:<id>` visible → suppress entirely (`show_notification_use_case.dart:129-139`). No sound, no haptic, no in-chat cue; the visual timeline update is the only cue (**adopted OQ-01 baseline** — do not add a cue without a product decision). All producers reuse this one gate: text/media `chat_message_listener.dart:674-705`, 1:1 reactions `handle_incoming_reaction_use_case.dart:376-413`, group message/media/reaction `group_message_listener.dart:1244-1275`, `:1364-1392`.
- **Muted group** — indefinite, per-group, installation-local (the only mute that exists; **direct chats have no mute**, OQ-05) → no card/sound/vibration for group text, media, announcement messages, and eligible group reactions; delivery, persistence, and in-app unread preserved; muted group excluded from the badge projection (`canonical_notification_badge_state_db_helpers.dart:138`) and its existing card retired on mute (`group_repository_impl.dart:377-387` → reconciler; background fence `background_group_notification_post_show_fence.dart:100-108`). Policy gate: `group_notification_display_policy.dart:109-110` (reason `'muted'`).
- **Not the reaction audience** — upstream of the decision engine: no notification is *attempted*; the reaction is still persisted and visible in the timeline (PRD §6.5, added 2026-08-18). A reaction alerts only the reacted-to message's author. 1:1: the incoming reaction must target a locally authored outgoing message (`_targetWasAuthoredByLocalRecipient`, `handle_incoming_reaction_use_case.dart:472-482`, gating the notify at `:434-436`); REMOVE/stale/replay branches return before the notify, so un-reacts never alert. Group/announcement: reactor-is-self skip + author-only target filter before any outbox staging (`group_message_listener.dart:1241-1248`; identical filter on the compat lane `:3647-3659`, which also admits `actionAdd` only, so removals are silent) — the group lane additionally requires an ordinary-media target, so reactions to private/protected messages alert nobody. Relay-side wake nomination is author-only too (Plan 315; self-reaction → empty nomination by design). Host pins: `group_message_listener_test.dart:17160` (notifies target author, not reactor or bystander), `:16983` (group REMOVE silent), `handle_incoming_reaction_use_case_test.dart:522` (1:1 ADD notifies recipient), `:669` (1:1 REMOVE silent). Anchors verified 2026-08-18.
- **Recovery replay of an already-handled event** — `suppressNotification` (reason `recovery_replay`) is terminal suppression, `show_notification_use_case.dart:116-127`. (Distinct from §1.1's forced-*silent* recovery presentations, which do show a silent card.)
- **Duplicate paths** — live-wins marker (`:141-172`) + durable per-event claim (`:186-247`) ensure one `event_id` arriving via live path *and* FCM renders once; PRD §9 adds: a late path must never re-alert audibly.

### 1.3 Per-condition expectation matrix (announcement behaves like group)

| Condition | 1:1 text/media/reaction | Group & announcement text/media/reaction |
|---|---|---|
| Foreground, **same chat** open | Suppressed | Suppressed |
| Foreground, other chat / chat list / settings | Card; **audible** if first in 30s window, else silent-visible | Same |
| Background-running (incl. still-connected direct delivery, AC-04/G-06) | Card; audible/silent per tone window | Same |
| Suspended/killed → FCM wake | Card; tone window via durable lease | Same |
| Second+ event, same conversation, <30s | Silent-visible in-place update (same stable notification ID) | Same |
| Muted group | n/a (no direct mute) | Nothing; unread kept; badge excludes; card retired |
| Reaction where this user is **not** the reacted-to message's author (incl. all self-reactions) | Nothing — silent state update, no card/sound (PRD §6.5) | Same |
| Recovery replay of already-displayed event | Suppressed (`recovery_replay`) | Same |
| Forced-silent recovery presentation (iOS mailbox replay / Android headless-recovery ambiguity) | Silent-visible | Same |
| Same event via 2 paths (live + FCM) | One render, one audible max | Same |
| Media copy | "Photo" / "Video" / "Voice message" / GIF / File — caption-first (`show_notification_use_case.dart:38-65`); private media → generic redacted copy | Same |

---

## 2. PRD traceability — clause → proof → status

Status legend: **HOST** deterministic host test green today · **HOST-STRICT** host contract now *enforces* the clause and the device scenario is written + registered, device evidence pending the first post-G9-fix campaign run · **DEVICE** device/e2e proof exists today · **PARTIAL** proof exists but does not assert the full clause · **GAP-Gn** no e2e (see §4) · **TARGET** PRD target state whose mechanism is default-off / not implemented — owned by the coverage doc's GAP-N program, not by this map.

### 2.1 §6 decision-matrix rows and core ACs

| PRD clause | Expected behavior | Existing proof | Status |
|---|---|---|---|
| §6 row 1 / §6.1 / AC-01 | Same chat A foreground-active: update in place, no OS banner, no cue (OQ-01) | HOST `test/features/push/application/show_notification_use_case_test.dart:1153-1186` (exact direct **and** group suppression); DEVICE sound-smoke S4 (1:1, OS-level zero-records); **S15 group same-chat suppression + post-clear notify control** now exists (`run_notification_sound_smoke.dart` S15 block, harness `groupConversationTracker.setActive('group:<id>')`) | HOST + DEVICE(1:1) + HOST-STRICT(group). Announcement device leg deliberately **not** duplicated: the lane seam is prefix-based `group:` for chat and announcement alike (`show_notification_use_case.dart:105-110`), so no defect can separate them there — group-type policy divergence stays host-owned |
| §6 row 2 / §6.2 / AC-02 | Chat B open: A still gets its OS notification, B stays open | HOST use-case tests; DEVICE approximated by S1 (foreground, off-conversation staging screen — not literally another chat) | PARTIAL (host-exact; device approximate) |
| §6 row 3 / AC-03 | Chat list / settings / other screen: A still notifies | Same as AC-02 (S1 is exactly "other screen") | HOST + DEVICE |
| §6 rows 4–5 / §6.3 / AC-04 / G-06 | Inactive/background-running (incl. still-live direct connection): OS notification required; reachability ≠ visibility | Group flavor DEVICE: `groups.reaction_notification_campaign` → `group_reaction_background_connected_recipient`; **1:1 flavor now S16** — logical lifecycle `paused`, no active conversation, live bridge, real `FlutterNotificationService` + dumpsys, `audibleStrict` disposition | DEVICE(group) + HOST-STRICT(1:1, S16). Boundary honestly labeled: S16 proves still-connected + non-foreground-active only; **true process suspension stays owned by payload-campaign b12**. The PRD §11 stale-visible-thread freshness leg was **cut** — `TrackerBackedAppVisibility.maySuppress` short-circuits to false whenever lifecycle ≠ resumed (`test/shared/fakes/fake_app_visibility.dart:21-27`), so a paused+tracker-set leg cannot fail for the freshness reason; that seam is host-owned |
| §6 row 6 | Suspended/terminated: generic push wakes native processing, render locally | DEVICE `notifications.android_payload_campaign` (b12: background-isolate staged, airplane tap visible, cold-kill startup ingest) + `notifications.android_recovery_completion` (zero-Activity recovery, Plan 374) | DEVICE (custody/visibility). Sound disposition on THIS path remains unasserted — b12 rows still carry no channel assertion; only `tc_b13` does (see AC-10) |
| §6 row 8 / AC-08 | Already read/handled: no re-alert; cancel/update stale | DEVICE a6 replay-before-ack + no-duplicate-render; `groups.notification_projection_durability` read-zero exact cancel; full OQ-03/OQ-04 read-predicate target | PARTIAL + TARGET (OQ-02/03 adopted, not implemented) |
| §6 row 9 / OQ-05 | Muted group: block presentation without changing payload; unread/badge/card semantics per §1.2 | DEVICE `group_mute_notification_db_proof_test.dart` (**SQLCipher projection hop only**); HOST `group_message_listener_test.dart:16483+` (muted suppression persists message), `:17033+` (muted ADD reaction does not notify), `background_message_handler_test.dart:4683-4742`, badge fixture `canonical_notification_badge_state_db_helpers_test.dart:186-239`; sibling independence in `group_multi_device_real_harness.dart`; **NEW** `test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart` — the E2E probe now reports `canonicalBadgeState` from the *production* helper, so a muted group's badge exclusion is observable on device | HOST + **DEVICE**; GAP-G4 **CLOSED** by Plan 379 (2026-08-18, runs 14/15) — card-absence on the live AND FCM/background paths, badge exclusion, unread preserved, delivery unharmed, each with an in-window positive control. Sound/vibration and the media flavour remain unproven |
| AC-05 | Delivery ack without `wake_not_required` must not suppress the wake | N03 coordinator foundations are default-off (Plans 369/370) | TARGET (GAP-N03) |
| AC-06 / OQ-02 | Opening A during build prevents stale A without clearing B | HOST regression captures today's post-then-cancel behavior (`group_notification_read_projector_test.dart:61-109`) — the *target* pre-effect gate is not implemented | TARGET (GAP-N05/N11) |
| AC-07 | Backgrounding between decision and post → final recheck still notifies | No final pre-effect recheck exists on the live path (coverage doc §6.2 race gap) | TARGET (GAP-N05) |
| AC-09 | Dismiss ≠ read; Mark-Read clears exactly | HOST projector tests; DEVICE read-zero exact cancel (projection durability campaign) | HOST + DEVICE |
| AC-10 | One local event, one unread transition, one conversation notification, normally one audible | HOST dedupe rows (use-case tests); DEVICE a6.no_duplicate_render; **NEW** `tc_b13_dual_path_single_alert` in `notifications.android_payload_campaign` — backgrounded-but-connected emulator recipient, `b13.single_card` + `b13.single_audible_channel` (raw-dump `Notification(channel=` == `mknoon_messages`) + `b13.losing_path_typed_suppression` (discriminator union) + `b13.dual_attempt` (both legs proven to have attempted, else inconclusive-red). Host leg green: `scripts/test/notification_tap_campaign_adapter_contract_test.sh` | HOST-STRICT (adapter contract green; device leg needs FCM credentials + a prebuilt `android.production_fcm` APK) |
| AC-11 | Fixed provider payload shape, no forbidden fields | Host fixture census (Plan 368: 44 fixed provider requests), Android classifier (Plan 375) — **default-off**; rich provider path still live | TARGET (GAP-N02; strict score unchanged until activation) |
| AC-12 | Launch after missed pushes: full sync, no duplicate local events | DEVICE payload campaign (b11/b12) + recovery completion campaign | DEVICE |

### 2.2 §9 race rules

| §9 race | Proof | Status |
|---|---|---|
| Direct first, inbox later → one local event | payload campaign a6 (replay-before-ack, ack-purges-relay, no-duplicate-render) | DEVICE |
| Push first, direct later → losing path exits without second alert | HOST dedupe/claim rows; device render-once via a6; **`tc_b13` now asserts the losing path's TYPED suppression** via a union — `NOTIFICATION_SUPPRESSED × {recent_remote_push, message_event_already_claimed}` when the live path loses, `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED × {recent_duplicate_background_push, message_event_already_claimed}` when FCM loses (`integration_test/support/android_notification_payload_campaign.dart`) | HOST-STRICT |
| Open A while A's notification is being built | TARGET (OQ-02 final gate not implemented); host regression documents current post-then-cancel | TARGET |
| Background between decision and post | TARGET (no final recheck on live path) | TARGET |
| Direct persists while background-running → present or leave push as owner | group flavor DEVICE (background-connected recipient); 1:1 now S16 | DEVICE(group) + HOST-STRICT(1:1) |
| Late push after locally posted notification → update, **no second audible** | tone lease HOST-proven; device now S14 (`toneDebounce`: flags `[false,true]` + one record + same notification id, channel `mknoon_messages_silent`) and `tc_b13` | HOST-STRICT |
| Late push after read → no recreation | a6 + read-zero cancel | DEVICE (partial read-predicate caveats per OQ-03) |
| Crash after persistence before outcome → inbox+push recover | recovery completion campaign (process-death resume, Plan 374) | DEVICE |

### 2.3 §13 required-test families (Android legs)

| §13 family | Status |
|---|---|
| Payload forbidden-field / fixed shape | TARGET (host fixtures exist, mechanism default-off — GAP-N02) |
| Event identity & idempotency per path order | DEVICE (a6/b11/b12) + HOST |
| Visible-thread isolation | HOST full; DEVICE 1:1 (S4); group S15 written + registered (HOST-STRICT) |
| Lifecycle transition (deliver around resign-active/onPause) | S16 written + registered (HOST-STRICT, logical-lifecycle boundary); group flavor DEVICE |
| Sound disposition (audible vs silent-visible vs suppressed) | **NEW FAMILY** — machine-pinned S1–S16 disposition table, byte-compared by `scripts/test/notification_sound_disposition_contract_test.sh` and enforced per scenario at the OS-capture verdict. HOST-STRICT |
| Final gate (open A or background between decision and post) | TARGET (GAP-N05) |
| Acknowledgement separation | TARGET (GAP-N03) |
| Shared-ledger concurrency | HOST (Plan 372 owners); native adoption ongoing (N07/N08) |
| Read/cancel (dismiss, open, mark read, delayed wake) | PARTIAL (see AC-08/AC-09) |
| Android real-device: Doze, WorkManager continuation, permission denied, channel disabled, token refresh, OEM | **DEVICE (Plan 380, 2026-08-19) for Doze, permission denied, channel disabled, and mid-session token refresh** — one clean `notifications.android_payload_campaign` run, 9/9 assertions, evidence in §4.4. **Two corrections since, both in §4.5:** the permission-denied leg is non-deterministic and does not close on that run (§4.4 correction, 3 further reds 2026-08-19); and the channel-disabled leg was blocking BOTH message channels, which let the OS enforce the row — it now blocks only `mknoon_messages`, and the per-channel product leak it exposed (**G25**) is fixed and device-proven. WorkManager continuation DEVICE (Plan 374). Token refresh **corrected 2026-08-17**: SDK rotation + startup re-registration are DEVICE-proven already (preflight→relay-registration chain, §3.2) — only the mid-session live-refresh leg is missing, owned by [Plan 380](../Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md) (`tc_g7_token_refresh_mid_session`). OEM: `N/A (target unavailable by project policy)` — the one row Plan 380 could not close (**G23**) — stock-Google-only matrix; optional AOSP proxies under GAP-N12 |
| iOS real-device matrix | Deferred to consolidated GAP-N12 iOS phase (adopted §9.1 sequencing) — deliberately not counted here |

---

## 3. Existing e2e inventory (Android device + emulator)

### 3.1 Sims-registered campaigns (required, automation-ready; `android.production_fcm` build, physical + emulator pair, staging relay)

| Campaign | What it proves |
|---|---|
| `notifications.android_payload_campaign` | 1:1 custody: replay-before-ack, ACK purges relay, no duplicate render, staged-visible-before-drain, background-isolate staging, airplane-mode tap, cold-kill startup ingest. **G16 caveat (2026-08-17):** existing evidence predates relay v1.8.0 — a fresh run fatal-times-out at `_waitForProviderSend` on the warm leg (provider markers removed); blocked until [Plan 380 W0](../Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md) adapts the journal grammar (§4.8 G16) |
| `notifications.android_recovery_completion` | Headless direct+group recovery, foreground handoff, custody recovery, history counts, zero-Activity recovery (Plan 374) |
| `groups.reaction_notification_campaign` | Group & announcement message unread lifecycle, group/announcement reaction recipient cards, group reaction to a background-but-connected recipient. **G16 caveat (2026-08-17):** existing evidence predates relay v1.8.0 — a fresh capture against the pinned/deployed v1.8.0 relay reds all six scenarios at `$.evidence[provider_fcm]` (provider markers removed); re-runs are blocked until the G16 grammar repair lands (§4.8) |
| `groups.notification_projection_durability` | Two-group read-zero exact cancel, media-reaction semantic kinds (photo/video/voice), stable single card |
| `intro.accept_notification_campaign` | Three-party intro accept notifications (physical + emulator introducer) |

### 3.2 Runner-registered harnesses (reliability discovery rows, adb-driven)

- **Notification sound smoke** — `integration_test/scripts/run_notification_sound_smoke.dart` + `integration_test/notification_sound_smoke_harness.dart`. Scenario register:

| Scenario | Lane / content | Pinned disposition | Asserted |
|---|---|---|---|
| S1 | 1:1 text, receiver foreground off-conversation | `audibleStrict` | exactly one OS record on `mknoon_messages`, recorded `silent` flags `[false]`, sender/body/payload |
| S2 | Group discussion text | `audibleStrict` | same (group lane) |
| S3 | Group announcement text | `audibleStrict` | same (announcement lane) |
| S4 | 1:1 same-chat suppression | `suppressed` | zero calls + zero OS records |
| S5–S7 | 1:1 image / video / voice | `consistency` | one record whose channel **agrees with the recorded `silent` flag** — timing-free by design, because consecutive same-lane scenarios legitimately fall inside the 30s window |
| S8–S10 | Group discussion image / video / voice | `consistency` | same |
| S11–S13 | Group announcement image / video / voice | `consistency` | same (descriptions reworded to `Group announcement …` so the discovery family filter admits them) |
| **S14** | 1:1 tone-window debounce (two texts <30s) | `toneDebounce` | flags exactly `[false, true]`, one record, **same notification id** across the audible→silent update, channel `mknoon_messages_silent`. Two-phase capture; 31s cooldown first; a msg1→msg2 gap ≥30s fails the row as inconclusive |
| **S15** | Group discussion same-chat suppression + post-clear control | `suppressed` | zero calls + zero OS records while the group is active; then a control message after `clear()` must notify audibly — that control is what separates "suppressed" from "lane is dead" |
| **S16** | 1:1 backgrounded-but-connected (logical lifecycle `paused`, no active conversation) | `audibleStrict` | one record on `mknoon_messages`, flags `[false]`, via the **real** `FlutterNotificationService` + dumpsys |

  **Verdict mechanics (rewritten by Plan 378).** The scenario→disposition table is the single source of truth: `dart integration_test/scripts/run_notification_sound_smoke.dart --print-disposition-contract` emits it and the sh contract byte-compares it. One pure decision function (scenario disposition + parsed records + recorded `silent` flags → verdict) is shared by the live device path and the offline `--verify-os-capture <scenario> <dump> <verdict-json>` mode, so the contract test exercises the same predicate the device run enforces. The harness now asserts the recorded `silent`-flag sequence (`silentFlagsMatch`); the orchestrator enforces the **exact expected channel** per scenario, replacing the old either-channel predicate.

  **Two HEAD defects found and fixed during execution** (neither was in the plan): the harness constructed `GroupMessageListener` with `groupConversationTracker:` but **no `appVisibility:`**, and since Plan 371 (`3c7e704e7`) the compat show lane is gated on `_appVisibility != null` (`group_message_listener.dart:3306-3312`) — so **every group and announcement row had been posting zero notifications** and no gate noticed; and the orchestrator's `finally { … exit(failed ? 1 : 0) }` reported an aborted run as a **pass** (see G8/G10).

- `notification_open_during_other_chat` — background→notify→tap-routes (fake notification service; call-log assertion only, **no OS-level record check**; logical-lifecycle backgrounding).
- `notification_open_ui_smoke` — 1:1/group/intro tap routing rows.
- 1:1 reaction device proof (`run_1to1_reaction_notification_device.dart`, capture-owned artifacts).
- `group_mute_notification_db_proof_test.dart` — real-SQLCipher `is_muted` projection hop (the DB read the mute decision depends on), **not** the end-visible mute effect.
- Sibling mute independence — `group_multi_device_real_harness.dart` (muted sibling stays quiet, unmuted sibling presents, both keep unread).
- **Token-rotation → production relay registration chain** (added to this inventory 2026-08-17; previously missed, which is why G7 wrongly claimed "token refresh: zero e2e") — `capture_android_background_crypto_preflight.dart` (in-app `deleteToken` rotation via a staged, subject-hash-bound command file; real FCM delivered to the ROTATED token at a killed process) chained into `capture_android_push_relay_registration.dart` (drives the PRODUCTION main, requires `PUSH_REGISTER_RELAY_PROOF_COMPLETE` + `PUSH_REGISTER_COORDINATOR_SUCCESS` in the flow log). Device-proves the A-07/A-08 rotation+registration path; the **mid-session live `onTokenRefresh`** in the running app is the only unproven half → [Plan 380](../Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md) `tc_g7_token_refresh_mid_session`.

### 3.3 Host tier (deterministic, green today — the *logic* of §1 is fully proven here)

`test/features/push/application/show_notification_use_case_test.dart` (56 tests: suppression, dedupe, forceSilent, copy), `test/core/notifications/notification_tone_tracker_test.dart`, `test/core/notifications/durable_notification_tone_lease_test.dart`, `test/core/notifications/local_notification_support_test.dart` (channel definitions), mute decision in `background_message_handler_test.dart` + `group_message_listener_test.dart`, badge exclusion fixture, `flutter_notification_service_test.dart` (`:214` audible default channel, `:385-405` silent channel).

Added by Plan 378:
- `scripts/test/notification_sound_disposition_contract_test.sh` — three cases: the byte-pinned S1–S16 disposition table, the offline OS-capture decision function against ≤3 canned dumpsys fixtures, and the 16-row discovery census. Auto-registered by the `scripts/test/*_test.sh` glob into `./scripts/run_test_gates.sh sims-contracts`.
- `test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart` — the probe's `canonicalBadgeState` comes from the production helper `dbLoadCanonicalNotificationBadgeState`, so dropping `AND g.is_muted = 0` re-reds it.

**The structural point (updated):** host proves the *decision*, and the disposition contract now makes the device tier assert it. The device tier has not yet shown anything for the sound smoke — the harness-start blocker (G9) is fixed as of 2026-08-17 (§4.9), and the first full S1–S16 campaign run is the remaining step.

---

## 4. Gap register — what no e2e verifies on the device pair

Read §4.1 and §4.8 together: Plan 378 closed six gaps *as work*. The harness-start blocker **G9** is FIXED (2026-08-17, see §4.9) — both roles now complete device setup — but the full S1–S16 campaign has not yet been executed, so nothing in §4.1 is claimed as device-proven yet.

### 4.1 Closed by Plan 378 (implemented, host-tier green 2026-08-17)

| Gap | Was | Closed by | Verified |
|---|---|---|---|
| **G1** | Sound disposition never asserted on device — "expect sound" rows passed even if every card landed silent | Pinned S1–S16 disposition table + `--print-disposition-contract`; strict per-scenario channel replacing the either-channel predicate at the OS-capture verdict; harness `silentFlagsMatch` | sh contract PASS; mutation re-reds recorded — flipping S1's table entry to `mknoon_messages_silent` reds the `cmp`, and restoring the either-channel predicate reds "audible-expected accepted a silent-channel record" |
| **G2** | No tone-window (30s) e2e | S14 (`toneDebounce`), two-phase capture, 31s cooldown, flags `[false,true]` **mandatory in both the primary and the channel-fallback assertion sets** | registered + analyzed; the flags assertion is what excludes the "second message was simply suppressed" degenerate pass |
| **G3** | Same-chat suppression e2e was 1:1-only | S15 group leg + the `appVisibility` wiring it required + a post-clear notify control | registered; announcement leg deliberately not duplicated (identical prefix-based seam) |
| **G5** | Dual-path "one audible max" not asserted | `tc_b13_dual_path_single_alert` — single card, audible channel from the raw dump, losing-path discriminator union, bounded dual-attempt evidence | `scripts/test/notification_tap_campaign_adapter_contract_test.sh` PASS (causal RED recorded first) |
| **G6** | 1:1 backgrounded-but-connected only incidentally covered | S16 on the real service + dumpsys | registered; freshness leg cut with evidence (fake short-circuits on paused) |
| **G-reg** | S5–S13 invisible to the reliability discovery contract | Nine literal `_runScenario` blocks; S11–S13 reworded `Group announcement …` | census **4 → 16 rows**, `./scripts/check_reliability_simulation_discovery.sh` exit 0 |

### 4.2 Closed by Plan 379 (device tier, 2026-08-18 — reproduced runs 14 and 15)

Unlike §4.1, these ARE claimed as device-proven: `groups.muted_notification_campaign PASS assertions=5`, both scenarios `ok: true`, on the pinned pair (sender `emulator-5554`, recipient `21071FDF600CSC`), real FCM, relay v1.8.0, APK `0a8c93f6…`.

| Item | Was | Closed by | Verified |
|---|---|---|---|
| **G4** | **No full-effect muted-group Android campaign** — only the SQLCipher `is_muted` projection hop was device-proven. Required: no card for text/media/reaction on the foreground **and** FCM/background paths, card retirement on mute, badge exclusion, unread preserved. | Two out-of-catalog scenarios in the proven Plan-330 lane (`android_group_muted_message_suppression`, `android_group_muted_reaction_background_suppression`) with their own validator, runner, proof test and sims capability — so the G11 suffix-dispatch sites and both byte-pinned censuses stay untouched, and the lane is immune to the dead G16 provider grammar | Both artifacts validator-accepted; `groupIsMuted: true` read from the real encrypted DB in both lanes; delivery unharmed on both. See the two rows below for the per-path claims |
| **G4 / live path (TC-379-05)** | Nothing proved a muted group stays silent while the app is in use | App FOREGROUND on Orbit; message sent to the muted group after toggling the real Group Info switch; arrival bound to the id the sender published before any silence is asserted | Zero cards for the muted group; unread grew **0 → 1** with `read_at` NULL (id-bound); message persisted; badge `available: true`, muted group **excluded**, control **included**. Both confound controls held: the group under test posted a card BEFORE mute (1), and the unmuted control posted one INSIDE the suppression window (1) — so a dead notification lane cannot masquerade as a working mute |
| **G4 / FCM path (TC-379-06)** | Nothing proved suppression survives a killed process, and the leg was blocked outright by G17 until Plan 383 landed | Recipient process `terminated`, real FCM; in ONE window the sender reacts in the muted group and in the unmuted control; a throwaway warm-up push is sent first so neither graded push is the un-gradeable first wake | Muted reaction → `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` bound to its own fcm messageId (reason `group_reaction_local_state_ineligible`, recorded not pinned), **zero cards**; unmuted control reaction → `PUSH_BACKGROUND_NOTIFICATION_SHOWN` bound to its own fcm messageId, **card posted**; the suppressed reaction is still delivered (`reactionRowsObserved: 1`); badge still excludes the muted group. Push digests differ and each is bound to its own event, so the two cannot be confused |
| **G16 — the capture-blocking half only** | Commit `8d86501e4` also deleted `[PUSH] Token registered for …`, which the shared capture waited on at `run():747` **before** lifecycle dispatch — so it blocked **every** Android scenario in the driver, not just the provider-evidence assertion | Attribution moved to the recipient boundary: `androidRelayPushRegistrationAccepted()` waits on the device's own log for `relay_push_registration_success platform=android` / `PUSH_REGISTER_TOKEN_SUCCESS`, both derived from the bridge `ok` the Go node sets only after the relay replied `Status:"OK"` — server-side acceptance, not client intent. `PUSH_REGISTER_TOKEN_SENDING` is explicitly rejected | Zero relay changes; Plan 368's pinned `[PUSH]` vocabulary untouched and no identifier re-added. Strictly better attribution than the deleted line, which carried only a 20-char peer prefix. A census host test now pins every literal the capture waits on against its real emission site. **The provider-evidence half of G16 remains OPEN** (§4.8) |
| **G17 residual (Plan-379-owned)** | The muted adapter still red at `capture…:3417` (`suppressed.isNotEmpty`) after Plan 383's fix, because the muted group's FIRST post-kill push exits at `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of the mute gate | A throwaway warm-up push absorbs the un-gradeable first wake, and the validator machine-enforces it: ≥3 wakes, and neither graded push may be the first | `suppressed.isNotEmpty` was **NOT** weakened — it now passes on its own terms. Four new validator rules, each mutation-checked to red exactly its own host row and nothing else |
| **Harness soundness (three defects, found runs 11-13)** | (a) the live arrival gate counted `GROUP_MESSAGES_DB_INSERT_SUCCESS` occurrences and required `count > baseline` — unsound, because the logcat ring rotates; (b) the warm-up gate enumerated notification dispositions; (c) the reaction-row probe raced the offline-inbox drain | (a) arrival bound to the sender's published message id, plus a monotonic accumulator behind every recipient log read; (b) gate on `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS` — storage warmth, the cost actually being absorbed; (c) poll the probe until the row lands, 3-minute bound | Runs 11/12/13 red → 14/15 green. (a) was replayed against run 11's own device logs before re-running and is pinned as a negative host row so the unsound delta cannot return; (c) keeps `reactionRowsObserved >= 1`, so a genuinely lost reaction still fails the lane. Evidence: `docker-ws/plan379_run11_rotation_evidence.txt` |

**Not closed by Plan 379 — carried forward, so the G4 row above is not read as more than it is.** The muted lane contains ZERO assertions on channel, importance, sound, tone or vibration: tone-absence is *entailed* by channel-agnostic card-absence (the matcher accepts a pkg record on ANY channel, and no independent audio/haptic path for incoming messages exists), not independently observed. The FCM leg closes that escape by binding the suppression event to the muted messageId — no show call ever happened — but the LIVE leg has no analogous field and rests on card count alone. Only **2 of G4's 6 flavour × path cells** ran (text/live, reaction/FCM); muted reaction on the live path and muted text on the FCM path are untested, and a muted-text-on-FCM assertion would currently pass **vacuously** because per **G19** the unmuted group-text killed-path leg dies at `push_decrypt_preview` parity before any display decision. The media flavour is host-tier only by design (the policy gate is a single content-agnostic seam ahead of any kind dispatch). "Card retirement on mute" is asserted as absence but is **not causally attributed** to mute: the choreography opens the group's own Group Info to reach the switch, and opening a conversation clears its card independently. iOS legs remain deferred to GAP-N12. Gaps found *by* this work but not closed by it: **G19** (killed-path group-text parity failure — since CLOSED by Plan 384, §4.6) and **G20** (catalog-lane evidence-capture soundness, still open in §4.8).

### 4.3 Closed by Plan 383 (2026-08-18 — G17, scoped)

**Verified before filing here** (4 evidence strands + 3 adversarial lenses, 2026-08-18). One lens refuted a wholesale move: G17's statement was written wider than what was fixed, so the mechanism closure is recorded below and the three sub-claims that did NOT close were carved out to **G21** (first-wake storage deadline) and **G22** (1:1 device evidence), which stay in §4.8, with **G19** covering the killed-path group-text hole — G19 itself is now CLOSED by Plan 384 (§4.6). Read this row together with those three.

| Item | Was | Closed by | Verified |
|---|---|---|---|
| **G17 — killed-app card for authenticated typed events** | The background isolate posted NO card on the suspended/killed FCM path, breaking §1.3's `Suspended/killed → FCM wake` promise. A genuinely NEW event arriving at a killed app has no staged display-outbox row (the isolate only READS them; the writers are the running app), so the resolver returned null and the handler took a silent early return. Observed 2026-08-17: both pushes woke the isolate, zero suppression events, and no card for the UNMUTED control group | The three NON-deadline exits of the `requiresDurableEffect` block now fall through to the existing non-durable typed show lane instead of releasing owners and returning: authority-null (`:1063-1070`), generation-invalid (`:1076-1086`, which previously emitted no flow event at all), and authority-read-failed (`:1116-1125`). The enabling change is binding the resolver result to a local so `durableEffectContext` stays null on fall-through. `releaseProvisionalNotificationOwners` drops from 5 call sites to 2 — only `storage_deferred` and `final_authority_invalid` survive. The DEADLINE exit deliberately still defers (that is G21) | **DEVICE, group reaction only, 4 observations:** Plan 383 runs 1-2 (`docker-ws/plan383_g17_device_evidence.txt`) plus Plan 379 runs 14-15 — the latter are independent confirmation from a different plan's lane, produced after Plan 383 wrote its status. The unmuted control reaction emits `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED{reason: exact_sql_authority_unavailable, presentation: nondurable_fallback}` then `PUSH_BACKGROUND_NOTIFICATION_SHOWN` (no `durable` key) and posts an OS card, where 08-17 produced none. Attribution is triple-bound: the SHOWN messageId byte-matches the control wake's and differs from the muted one's, the SHOWN payload names the control group, and the process was machine-verified dead (`am kill`, escalate to `am stop-app`, then block on `pidof` empty) with one constant isolate pid across the graded window. **HOST:** 96/96 green on the Mac host, covering direct message, direct reaction, group reaction and group message plus the generation-invalid and read-failed exits. **Plan 383's own TC-383-10 device gate — which its status line records as BLOCKED — is now satisfied** by Plan 379 runs 14/15 (`ok: true`) |

**Caveats this closure carries — it is scoped, not total.**
- **THE FIX IS UNCOMMITTED.** HEAD `3f863ba90` contains **zero** occurrences of `nondurable_fallback`; the working tree has three. `lib/features/push/application/background_message_handler.dart` and both host test files are ` M`. The closure is true of the working tree only — a stash or checkout in this shared checkout silently reopens G17 while this row reads CLOSED. **Commit before relying on it.**
- **Device coverage is one flavour:** group reaction, one recipient (`21071FDF600CSC`), one debug-JIT `android.production_fcm` APK `0a8c93f6…`. Release AOT is unmeasured. 1:1 and the other kinds are host-only — that is G22.
- **The "muted AND unmuted alike" half of the old headline is RE-ATTRIBUTED, not fixed.** On 08-17 the muted push was the FIRST post-kill wake, so its silence was the storage deadline firing upstream of the mute gate (G21), not this seam — and a muted group is *supposed* to be silent. Plan 383 is credited only with the unmuted control leg, whose "before" is one push in one run.
- **Regression protection, so this is auditable.** Host: both test files are curated `GROUP_TESTS` members (`scripts/run_test_gates.sh:679` and `:681`), re-run by `run_test_gates.sh groups`. Device: `groups.muted_notification_campaign` (`critical_features.json:892`, required). On regression the device lane reds at `_waitForGroupNotificationBodyChange` (180s timeout + a `background_control_card_not_refreshed` diagnostic dump), then at `resolveMutedBackgroundPushBinding` returning null with `shown=0`.
- **Known blind spots in that protection.** The device gate carries `allowedNaReason: target_unavailable_by_project_policy`, and the sims verdict layer treats `notApplicable` as PASSING — so the only device detector can silently degrade to N/A instead of red when the pinned phone is absent. It covers the group-reaction kind only, so a 1:1 regression on the same `:1040` arm reds nothing on device; it stays GREEN under the "keep the owner release, drop only the return" mutation; and it structurally cannot observe G21. At host tier the claim-COMMIT semantics rest on exactly ONE row (`background_message_handler_test.dart:1535`).
- **Accepted behavioural difference:** the fallback lane skips the durable path's final-barrier visibility recheck, so a user foregrounding into that exact conversation mid-handler can get a card the durable lane would have withheld. Owner: the N05 final-effect race family.

### 4.4 Closed by Plan 380 (device tier, 2026-08-19 — G12 + G7, two clean 9-of-9 runs)

`notifications.android_payload_campaign` **PASS, `assertions=9`, exit 0**, `Builds: actual=1,
cacheHits=0`, zero child builds, byte-exact OS-state restoration (the campaign's end-verify
compares the dumpsys channel fingerprint against its own preflight baseline and deletes every
artifact on mismatch). Pinned pair: physical `21071FDF600CSC` (sender, Android 16 / SDK 36) +
`emulator-5554` (receiver, Android 17 / SDK 37 — every OS mutation and every assertion runs
there). Artifacts: `build/sims/proofs/notifications.android_payload_campaign/`.
`releaseEligible=false` on that run is the filtered-run rule (`--only`), stated as such by the
assessment itself — not a leg failure.

> **RESOLVED (run 7, same day).** The permission leg's non-determinism had a MEASURED cause: the
> leg read its typed health event 60-120 s after the relaunch through `logcat -d -t <cursor>`, and
> the emulator's `main` ring is 2 MiB against ~1.6 MB/min of campaign traffic — so the event could
> rotate out, and a rotated window is EMPTY, indistinguishable from "never emitted". The campaign
> now starts a LIVE `adb logcat` reader before any leg (cursors are byte offsets into a file adb
> writes itself), re-checks the OS after the relaunch and reports `_Blocked('deviceOsState')`
> instead of a failure when the permission came back, and asserts the record immediately after the
> relaunch. **Run 7: 9 of 9, exit 0**, with all four permission checks true
> (`PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` x1, 0 cards, custody preserved, audible regrant).
> **Reconciled with §4.5.** That section's three further reds (01:17, 01:26, 02:10) all PREDATE this
> change, and its own diagnosis — *"needs a live `adb logcat` started BEFORE the run: the emulator
> ring rotates past an entire campaign within minutes, so the post-hoc `logcat -d` was empty"* — is
> exactly what this fix implements. Run 7 (03:03) is the first run carrying it.
>
> One caveat survives closure: the leg does NOT exercise Plan 385's NM override on this image —
> firebase_messaging answered `denied` honestly 3x with zero `PUSH_PERMISSION_OS_STATE_OVERRIDE`,
> independently confirming §4.5's G24. It proves the coordinator's denied branch, not the 385 fix.
> (An earlier draft of this note also claimed the silent-channel leak was merely intermittent —
> WRONG, and corrected: run 7 used a different APK, `1235650e4340…` rather than run 4's
> `1e0de3238478…`, carrying §4.5.2's G25 read-back fix. The leg is a working detector.)
> See Plan 380 Execution Findings F13-RESOLVED / F15 / F16.
>
> **Superseded correction, kept for provenance — the concurrent-run failure that prompted all this.** A CONCURRENT session
> re-ran this capability 40 minutes later on the BYTE-IDENTICAL APK (`1e0de3238478…`, cache hit,
> zero builds), the same working tree (385 seam still present, grep-verified) and the same device
> pair, and it **FAILED at assertion 6** — *"G7 permission denied recorded no typed
> `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` health event"*, which is the original bug-385
> signature. Identical inputs, opposite verdicts, so **`tc_g7_permission_denied` is
> non-deterministic and one green run does not close it.** Plan 385's F3 had already recorded that
> `pm revoke` + `user-fixed` reads honest only *sometimes* on this SDK-37 image, which points at the
> leg's PRECONDITION rather than the product as the unstable part — but that is a hypothesis, not a
> measurement: the failing run's logs were not captured and the campaign uninstalls the app on exit.
> **G12 (rows 3-4) is unaffected and stays closed**, as do G7 rows 7-9. See Plan 380 Execution
> Findings F13/F14. That run also deleted run 4's nine per-scenario artifacts through its own
> startup cleanup; run 4 survives as an attested manifest carrying a SHA-256 for each deleted file,
> and the per-leg values below were transcribed before deletion.

| Gap | Was | Closed by | Verified (device evidence from the run-4 artifacts) |
|---|---|---|---|
| **G12** | b12 rows carried **no sound assertion** — the suspended/terminated FCM path (§6 row 6) proved custody and visibility only, so a cold-launch card landing on the silent channel would have passed | `b12.warm_audible_channel` + `b12.cold_audible_channel`, read per-record out of the raw dumpsys `NotificationRecord` block (`ActiveNotificationCard` carries no channel field and plan 378 deliberately did not add one), plus enforced 31 s tone-window spacing before every audible-asserting send so a silent card is a real defect and not a debounce artefact | `warmAlertChannel == mknoon_messages`; `coldAlertChannel == mknoon_messages` — the cold row additionally carrying `receiverPidEmptyBeforeTap` + `newPidObservedAfterTap`, i.e. the channel was measured on a card that survived a real process kill. **These two rows also discharge the 1:1 killed-app device evidence Plan 383 deferred here** (`383:71` names `b12.cold_audible_channel`/`b12.warm_audible_channel` by name). G22 asked whoever took this to confirm the rows cover the EXISTENCE claim and not merely the channel — they do: the cold leg calls `_terminateReceiver()` **before** the send, so the staged envelope and the card are both produced by the background isolate of an already-killed app, and a channel cannot be read off a card that does not exist. Scope is 1:1 MESSAGE only — see the narrowed G22 |
| **G7** — all four legs proven (permission-denied leg re-proven in run 7 after its rotation defect was removed); OEM carved out to **G23** | PRD §13 Android real-device cases with zero e2e: **Doze**, **permission denied**, **channel disabled**, and the *mid-session* half of **token refresh**. (The 2026-08-17 correction stands: SDK rotation + startup re-registration were already device-proven via the preflight→relay-registration chain; only the mid-session leg was missing) | Four new campaign legs — `tc_g7_permission_denied`, `tc_g7_token_refresh_mid_session`, `tc_g7_channel_disabled`, `tc_g7_doze_delivery` — plus one new debug probe action (`notification_delete_push_token`: `deleteToken` then a bounded poll until the token hash actually changes, receipts carrying hash PREFIXES only), and finally-tracked mutation flags so every OS mutation is restored even on a mid-leg throw | **permission denied:** `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` ×1, `permissionDeniedCardCount=0`, custody preserved (1 msg), regrant control card audible on `mknoon_messages`. **token refresh:** pid `6608 == 6608` (same process — not a relaunch), token hash `771a58fddbaf → f25bd9a03827`, `tokenRefreshStartupAttemptsInWindow=0`, delivery audible. **channel disabled:** both message channels driven to importance `0`, `channelDisabledCardCount=0`, custody preserved, restored to `4`/`2`, control card audible. **Doze:** `IDLE` sampled at BOTH boundaries (before send and at observation), `dozeDisposition=delivered_during_idle`, 1 card, 1 message |
| **G16 — payload half only** | `relayJournalContainsAndroidProviderSend` grepped a log line commit `8d86501e4` had deleted, and `_waitForProviderSend` is a fatal 2-minute wait on all three payload FCM legs — so a fresh `notifications.android_payload_campaign` could not survive its warm leg at all | Plan 380 **W0**: the predicate re-derived against the v1.8.0 grammar (`[PUSH] outcome=success attempt=N total_attempts=N` / `fallback=strict`). Recipient binding moved into the journal **scope** (`journalctl --since <sentAt>`) rather than the matched line, and a source freeze pins that scoping | DEVICE: the campaign reaches and passes all three FCM legs — the failure mode this gap described is gone. **The reaction-side half remains OPEN and unowned — see G16 in §4.8** |

**Three harness oracles had to be repaired to reach this run, and none was a product defect.**
Each was found in an instrumented device log, not by reading code. They are recorded here because
all three were previously mis-attributed — twice to "device-state flake".
- **A6's relay pending-list assertion was a single-sample race.** It threw the instant
  `callP2PInboxRetrievePending` returned a non-empty list, but the relay re-serves an entry until
  its ACK purges it — measured: two `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS
  {requested:1,acked:1}` 0.8 s apart against ONE `INBOX_STAGED_CHAT_COMMITTED`. Its sibling
  `_observeDrainConvergence` had always treated the same field as a convergence input. Duplicate
  COMMITS still fail closed on the first sample.
- **A `dumpsys notification` channel read is not a valid audible-alert oracle.** When both paths
  reach one message the loser reconciles the claim and publishes a silent SAME-ID in-place update
  (`local_notification_support.dart:47-49`), MOVING the record to `mknoon_messages_silent`.
  Measured twice, identically: `PUSH_BACKGROUND_NOTIFICATION_SHOWN` → 2.5 s →
  `NOTIFICATION_LEGACY_CLAIM_RECONCILE` → 140 ms → `NOTIFICATION_SHOWN {"silent":true}`. That is
  B13 *passing* — one alert, one card — but no dumpsys poll is fast enough to sample the ~2.6 s
  audible window. B13's verdict moved onto the cursor-scoped log; the remaining channel reads now
  consume the SAME dump that first saw the card.
- **The background isolate never reported whether its post ALERTED.**
  `PUSH_BACKGROUND_NOTIFICATION_SHOWN` carried no `silent` flag while the live path's
  `NOTIFICATION_SHOWN` always has — and the background isolate is the path that WINS whenever the
  app is merely backgrounded, so the winning alert was structurally unprovable. One production
  line: `'silent': ?publishedSilently` on both detail shapes. Deliberately `bool?` via a
  null-aware element, so an event emitted without any native show reports NO flag rather than
  falsely reading as audible.

**Product finding recorded here — now FIXED, see §4.5.2.** This section originally filed "turning
off the *Messages* channel does not stop message notifications" as unowned device evidence for the
deferred channel-disabled decision, and recorded that the matrix leg had been changed to block BOTH
channels. Both halves are superseded: the leak is closed in `lib/`, and blocking both channels is
now understood to be the wrong leg design (it lets the OS enforce the row so the app is never
tested). Do not re-derive either from this section.

### 4.5 Closed by Plan 385 (2026-08-19) — the app posting when the OS has already said no

Two defects in one family: the app believed it was allowed to post when the OS had already decided
otherwise, and in both cases the existing "notifications are off" UX was unreachable because nothing
in the stack read the OS state that had actually changed. **G24** and **G25** are assigned here for
traceability; neither had a gap id before.

#### 4.5.1 G24 — `requestPermission()` answers `authorized` while notifications are off

| Was | Closed by | Verified |
|---|---|---|
| **firebase_messaging short-circuits `requestPermissions()` to `authorized` off a bare `Context.checkSelfPermission(POST_NOTIFICATIONS)` on SDK ≥ 33** and never consults `NotificationManagerCompat.areNotificationsEnabled()` (FM 15.2.10). A user with notifications off got `granted=true`, a registered token, and cards the OS silently discarded — and the already-built "Open notification settings" banner never appeared, because `PushRegistrationCoordinator` gates its whole denied branch on that boolean, so `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` was unreachable and no durable health record was written | Optional `osNotificationsEnabledFn` on `requestPushPermission` (`request_push_permission_use_case.dart`), defaulting to `AndroidFlutterLocalNotificationsPlugin.areNotificationsEnabled()` — an unconditional NM read on every SDK. It only ever **narrows** a granted-looking result; a request-level denial is returned untouched and never pays for the read. Emits `PUSH_PERMISSION_OS_STATE_OVERRIDE`, stamps `osEnabled` into `PUSH_PERMISSION_REQUEST_RESULT`, and fails **OPEN** behind a deliberately broad `catch` with `PUSH_PERMISSION_OS_CHECK_FAILED` as the discriminator that separates a fail-open `true` from a genuine one | Host tier: 8 rows, 8 mutants each killing exactly their predicted rows, `feed` lane 323 exit 0, analyze clean. **Device tier does NOT demonstrate this fix — see the caveat below** |

**Do not "fix" this through the two APIs that look right.** `FirebaseMessaging.getNotificationSettings()`
and permission_handler's `Permission.notification.status` are BOTH `checkSelfPermission`-backed on
SDK ≥ 33 (`PermissionManager.java:639-654` — `areNotificationsEnabled()` only below 33), so each
repeats the identical lie. flutter_local_notifications is the only truthful Dart-reachable oracle,
and it is also the poster whose cards get dropped in the bug state.

**Device caveat, stated plainly: the matrix leg cannot prove this one.** `tc_g7_permission_denied`
passes at HEAD *too* on `emulator-5554` — `pm revoke` + `user-fixed` yields an honest `denied` from
firebase_messaging on that image today — so the checkSelfPermission/NM divergence is not
reproducible there and the leg discriminates nothing. Four campaign runs; the run carrying the fix
was byte-identical in outcome to a HEAD control, which establishes **no regression and nothing
more**. To exercise G24 deliberately, do not use `pm revoke`: construct the divergence with
`cmd appops set <pkg> POST_NOTIFICATION ignore` while the runtime permission stays GRANTED —
`areNotificationsEnabled()` honours the appop, bare `checkSelfPermission` does not.

**New measurement bearing on §4.4's correction.** `tc_g7_permission_denied` failed **3 of 3** full
campaign runs on 2026-08-19 (01:17, 01:26, 02:10) on the cached APK that had passed 9/9 at 00:54 —
the same non-determinism §4.4 records, now with three more reds. Two of those runs predate the G25
fix existing in any build, so **neither fix in this section is implicated**. Diagnosis still needs a
live `adb logcat` started BEFORE the run: the emulator ring rotates past an entire campaign within
minutes, so the post-hoc `logcat -d` used after each failure was empty.

#### 4.5.2 G25 — a blocked "Messages" channel still delivered, via the silent channel

| Was | Closed by | Verified |
|---|---|---|
| **`mknoon_messages_silent` is a continuation of `mknoon_messages`, not an independent subscription** — it exists so the tone debounce and the same-ID reconcile can refresh a card without alerting twice. With **no channel read-back anywhere**, a user who switched "Messages" off kept receiving the same message cards through "Messages (silent)". Neither `areNotificationsEnabled()` nor POST_NOTIFICATIONS moves when a single channel is blocked, so no app-level check could see it | `resolveMknoonMessagePublicationSilence` + `mknoonPrimaryMessageChannelEnabled` (`local_notification_support.dart`) read live importance via `AndroidFlutterLocalNotificationsPlugin.getNotificationChannels()` — the only read-back that sees this state — and withdraw the silent downgrade while the primary is blocked. The publication then stays on the blocked channel and the OS refuses it, which **deliberately keeps the post ATTEMPT real**: `channelDisabledPostAttemptEvent` requires one, so explicit suppression would have reddened the very row this closes. Fails **OPEN**. Wired at all THREE publication sites — `flutter_notification_service.dart` show closure + canonical rebuild, and `background_message_handler.dart` | Device replication → fix on the same isolated leg (below); host 125/125 on the touched files, 148/148 graph-affected, 76/76 on the path-string census the graph structurally cannot see, analyze clean, runtime-roots `drift: false`; 9 of 9 mutants killed |

**Replicated before it was fixed, on the device pair.** Pre-fix build, leg blocking only the audible
channel: *"G7 channel disabled posted 1 card(s) on `mknoon_messages_silent` when no card may be
posted."* The run was a build-cache hit, which is what proves it exercised the genuine older APK —
the cache is content-keyed, so reverting the seam reproduced the earlier key exactly. The same
isolated leg on the fixed build (a real rebuild, new key) **PASSES**.

**The app is provably the decider, not the OS.** `NOTIFICATION_SILENT_CHANNEL_WITHHELD` ×1 with
**ZERO** `NOTIFICATION_CHANNEL_STATE_READ_FAILED` on the device log. The second half is not
decoration: without it a fail-open pass and a real pass are indistinguishable.

**The matrix leg was itself wrong and is corrected.** It had been changed to block BOTH message
channels, which is why it read green — with both off the OS refuses every card, so the row passes
without the app deciding anything and a regression that re-opened the silent route still reads
green. The leg now blocks **only** `mknoon_messages` and asserts `channelDisabledSilentImportance
== 2` (leak route provably OPEN) before the send; `tool/sims/device_criteria.dart` pins that 2, not
0. That restores the row's declared contract — *"user-blocked `mknoon_messages` channel posts no
card on any channel"* (`run_notification_tap_device_real.dart:147`).

**Two landmines worth not re-paying for.**
- **Do NOT gate the channel read on `dart:io Platform.isAndroid`.** Host tests move
  `defaultTargetPlatform`, not `Platform`, so that gate makes every row silently unreachable — it
  cost three green-looking tests that were asserting nothing. Use
  `resolvePlatformSpecificImplementation` returning null, as `ensureMknoonNotificationChannel` does.
- **The canonical-rebuild site is the one a reviewer misses.** Its open-channel test stays on the
  silent channel whether or not the site is wired, so only a blocked-channel row can tell the two
  apart. That mutant **survived** the first mutation pass and exposed the site as genuinely
  untested; a blocked-channel rebuild row now kills it.

**Regression coverage with the fix:** legs 1-5 PASS, legs 7-9 PASS, leg 8 is the fixed row. Leg 6 is
independently red (§4.5.1). **Evidence provenance:** `build/sims/latest/report.json` and
`build/sims/proofs` are shared slots that concurrent sessions clobber, so the verdicts quoted here
are taken from each run's own stdout and from the device log, not from the shared report.

### 4.6 Closed by Plan 384 (device tier, 2026-08-19) — G19

**G19 — a killed-app group TEXT posted no OS card, because the plaintext parity predicate rejected an
inner sender that was never on the wire.**

The two halves, both source-verified and adversarially re-derived before the fix:

1. **Producer reality.** The default group send does NOT push the Dart replay envelope.
   `sendGroupMessage` → `callGroupSendReliable` (`send_group_message_use_case.dart:3079`) reaches the Go
   producer, which stores a LIVE envelope (`go-mknoon/node/pubsub.go:424-441,:497-539`) whose encrypted
   payload struct (`go-mknoon/internal/group_envelope.go:42-47`) is `{text, timestamp, username, extra}` —
   **no sender key and no group-id key anywhere**. `extra` is the bridge opts minus `timestamp`, plus the
   producer's own `messageId` and `publishedAtNano` (`pubsub.go:1860-1876,:496`; opts at
   `go-mknoon/bridge/bridge.go:2698-2741`), and none of its ~10 keys is one the parity reader treats as a
   sender. The relay forwards it verbatim as 9 FCM data keys (`go-relay-server/inbox.go:854-899,:1221-1256`):
   no `kind`, no outer sender-ACCOUNT key, and `sender_transport_peer_id` — which is exactly what resolves
   the recipient-owned context that armed the failing clause.
2. **Predicate asymmetry.** The parity check OR'd six clauses into one collapsed reason. The group-id
   clause null-guarded an absent inner group id; the **sender clause did not**, so `decodedSender == null`
   fired it on every killed-app delivery that had a resolved context. The group-message resolver was the
   only one of the four preview resolvers doing hand-rolled per-field extraction on a raw JSON map; direct
   message, direct reaction and group reaction all use typed factories that reject absent identity fields
   into distinct reasons.

**The fix** (`lib/features/push/application/push_decrypt_preview.dart`, the only production file changed):
add the same `decodedSender != null` guard the group-id clause already had, so a plaintext that OMITS the
sender is cross-checked against nothing and the card renders from trusted context facts (title = local
group name, sender prefix = roster username — the copy path already refuses decrypted names when a context
exists). A sender that is PRESENT but wrong still throws; the genuine-tamper posture is unchanged and
test-locked. The same change also gives the `group_parity_mismatch` flow event a `clause` discriminator
naming the first true clause, so the next parity red is one log read instead of a multi-agent bisect —
the collapsed catch-all was called out by G19's own row.

**Why the host tier lied.** Plan 383's host row for exactly this leg passed while the device posted
nothing: the host fixture stubbed the whole resolver, and every context-bearing fixture in
`push_decrypt_preview_test.dart` used the Dart `inboxPayload` shape, which is id-complete. The
null-`decodedSender` arm therefore had **zero** rows in either direction. The new rows build the Go live
envelope's byte-shape instead, with the Go anchors pinned in a comment.

| Proof | Tier | What it pins |
|---|---|---|
| `push_decrypt_preview_test.dart` `'live Go envelope without inner sender key renders the trusted group card'` | host | trusted title/body, trusted comparand binding, `PUSH_ANDROID_DATA_DECRYPT_OK`, and **zero** `PUSH_ANDROID_DATA_DECRYPT_FAIL` — the last one is what kills a fix that keeps the clause firing and skips only the throw |
| same file, `'live Go envelope media flavor renders a card instead of throwing'` | host | the media flavour, which closes at host tier because the relay strips oversized media envelopes to the 6-key `preview_unavailable` fallback before they can reach parity on device |
| same file, five `'parity mismatch reports <clause> clause'` rows | host | each clause individually; deleting any one reds its own row. The group-id row is fixture-pinned **sender-ABSENT**, which is what rejects a guard hoisted above the whole clause chain (that variant silently disables tamper checks for sender-absent payloads and otherwise passes every row) |
| `group_muted_notification_criteria_test.dart` — killed-card validator + binding groups | host | the device artifact grammar: SHOWN bound to the graded push by id, zero `PUSH_BACKGROUND_NOTIFICATION_ERROR` in the post-kill window, the graded push may not be the first wake, and the graded card's body must carry the graded marker |
| `android_group_text_killed_app_card` in `groups.muted_notification_campaign` | **device** | the boundary the stubs could not reach: an OS card on a killed process for a real-composer group text |

**Device evidence** (`docker-ws/plan384_g19_device_evidence.txt`; run 2026-08-19, capture
`capture-1787125915764845-93175`, recipient `21071FDF600CSC`, sender `emulator-5554`, real FCM, relay
v1.8.0, prepared `android.production_fcm` APK `cb78193…`, `childBuildCount: 0`). The runner reported
`PASS groups.muted_notification_campaign assertions=6` with all three artifacts validated. Both post-kill
wakes in the new scenario ran `PUSH_BACKGROUND_MESSAGE_RECEIVED → PUSH_ANDROID_DATA_DECRYPT_OK →
PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED → PUSH_BACKGROUND_NOTIFICATION_SHOWN`, and the graded OS card read
`android.text=String (Alice: Plan384Grad9d466ffff3)` — the roster username, not a decrypted one. The
`DURABLE_EFFECT_DEFERRED → SHOWN` pair is Plan 383's non-durable fall-through doing exactly the job this
plan depended on it for. **The strongest single line of evidence is in the OTHER scenario:** the muted
background lane's cold-start warm-up is the same group TEXT that died at
`PUSH_ANDROID_DATA_DECRYPT_FAIL{group_parity_mismatch} → PUSH_BACKGROUND_NOTIFICATION_ERROR` 3-of-3 in Plan
379 runs 13/14/15; on this build it decrypts and cards. Across every post-kill window in the run there were
**zero** `PUSH_ANDROID_DATA_DECRYPT_FAIL` and **zero** `PUSH_BACKGROUND_NOTIFICATION_ERROR` lines.

**Discipline the new scenario inherits and must keep.** The graded push is never the first post-kill wake
— a throwaway warm-up absorbs the cold-start storage deferral (G21), gated on storage warmth, never on the
warm-up's own disposition. And post-fix the warm-up **cards too**, under the same conversation-keyed
notification id, so the graded observation is bound to the graded marker rather than to card presence or
to "the body changed": both of those latch on the warm-up.

**Not closed here.** The strict-authority lane emits no group-message push at all — recorded as **G26**
in §4.8, found by this plan's producer census and explicitly out of its scope.

### 4.7 Closed by the G26 relay lane (host tier, 2026-08-19) — pending a relay deploy

**G26 — a strict-authority group's messages were delivered to custody and then went silent.**

Strict/fresh-authority groups (Plan 377) are the only group traffic that never reaches the Go group
topic. `sendGroupMessage` returns before `callGroupSendReliable`
(`send_group_message_use_case.dart:3040-3072`) and instead signs ONE `group_offline_replay` envelope
per recipient into the DIRECT inbox under the `group_content_v1` ack-custody namespace
(`group_offline_replay_envelope.dart:1286-1325`). The relay admitted and stored those envelopes
(`ack_custody.go:331-440`) and then pushed nothing, because the direct push seam understood only two
shapes: a `type: message_reaction` direct reaction, and the `envelope["type"]` switch in
`extractChatPushMetadata` (`inbox.go:1358-1468`). A replay envelope has **no `type` field at all**, so
it fell to that switch's `default` and produced `ShouldNotify: false`. There was no counter either —
the silence was invisible to every dashboard.

**Scope of the outage:** total for that lane. §1.3's `Suspended/killed → FCM wake → Card` row was
unreachable for strict groups by construction — not a parity failure like G19, an absent push. The
message itself was never lost; it sat in custody until the recipient's app next ran and drained the
inbox.

**The fix** (`go-relay-server/group_content_push.go`, new): recognize strict group content at the
direct push seam and route it through the SAME `buildGroupPushMessage` the group topic lane uses. The
envelope already carries every field that builder needs — `groupId`, `keyEpoch`, top-level
`ciphertext`/`nonce`, `messageId`, `senderTransportPeerId` — and `addGroupEncryptedPushData` already
reads that exact shape. **The recipient needed no change:** it routes on the `type: group_message` data
key it already handles, and the strict plaintext is the id-complete `inboxPayload`, so the recipient's
plaintext parity check agrees with the outer push (this is the shape that never needed G19's null
guard). Custody recipients are `device.transportPeerId`, the same namespace push tokens are registered
under (`register_token` keys by the authenticated `remotePeer`), so the route resolves.

**Deliberately NOT done — strict group REACTIONS stay silent custody.** They share the custody
namespace but carry their own audience rule (author-only alerting, PRD §6.5) and a separate
notification-extension grammar; routing them onto the group-message push would alert every member.
`extractGroupContentPushMetadata` returns them *recognized-but-ineligible* so they can never fall
through to the chat switch, and a host row pins that. This is the remaining half of G26 and is
recorded as **G27** in §4.9.

| Proof | Tier | What it pins |
|---|---|---|
| `group_content_push_test.go` `TestExtractChatPushMetadata_StrictGroupContentIsInvisible` | host (Go) | the root cause itself: the generic extractor cannot see this envelope, so a dedicated lane is required rather than optional |
| same file, `TestInboxStore_StrictGroupContentWakesTheRecipient` | host (Go) | the causal row — asserts the 7 data keys the recipient routes on. Deleting the new branch reds exactly this row and the fallback row |
| same file, `…StaysSilentWhenDisabled` / `…StrictGroupReactionStaysSilentCustody` / `…WithUnusableEpochStillWakes` | host (Go) | the kill switch never drops custody; reactions stay silent; an unusable key epoch degrades to a routing-only push rather than to silence |
| `push_decrypt_preview_test.dart` `'strict-lane group content push renders the trusted group card'` + the routing-only fallback row | host (Dart) | the recipient half — the exact 10 data keys the relay now emits produce a trusted card with zero `PUSH_ANDROID_DATA_DECRYPT_FAIL` |

**Status is HOST-GREEN, not device-proven, and the behaviour is OFF in production.** The flag
`GROUP_CONTENT_PUSH_ENABLED` is default-OFF, matching every sibling push flag
(`DIRECT_REACTION_PUSH_ENABLED`, `GROUP_REACTION_PUSH_ENABLED`). Deploying the binary alone changes
nothing. Two steps remain and neither has been taken: **(1)** deploy the relay and set the env var,
**(2)** a device leg — the existing muted/killed campaign creates ORDINARY groups, so no registered
scenario reaches this path. Until both land, treat this row as "the code is right and proven at host
tier", not as a closed device promise. The sibling landmine is on record: the Plan-344 custody
admission flag sat default-off and silently killed every offline send until it was flipped on
2026-08-16.

### 4.8 Still open

| Gap | Statement | Evidence | Owner |
|---|---|---|---|
| **G15** | **~20 integration harnesses outside `setupGroupMultiDeviceStack` still cannot reach the Go bridge on Android.** `f1b568bca` (2026-08-17) made `MainActivity` construct `GoBridge` lazily behind the Dart canonical-runtime lease acquire→attach (see G9, §4.9); every direct `GoBridgeClient()` construction — `routing_smoke_harness`, `smoke_test`, `soak_e2e_test`, `group_recovery_cli_e2e_test`, `wifi_relay_fallback_smoke_test`, `conversation_bridge_test`, `background_reconnect_test`, `android_background_crypto_preflight_app`, `transport_census_harness`, the benchmark harnesses, … — gets `MISSING_PLUGIN` on every bridge call. iOS is unaffected (`AppDelegate.swift:375` still constructs GoBridge eagerly). | grep census 2026-08-17: ~20 `GoBridgeClient()` sites outside the shared stack, none lease-acquiring | unowned — each must call `ensureCanonicalRuntimeAttachedForTest()` (exported from `group_multi_device_real_harness.dart`) before first bridge use |
| **G11** | **The reaction campaign's criteria validator cannot express a muted scenario.** It dispatches message-vs-reaction on the id suffix `_message_unread_lifecycle` at six sites (`group_reaction_notification_device_criteria.dart:1173, :1665, :1691, :1730, :1960, :2449`) and hard-asserts `unreadCount == 0`, `expectedProviderSendCount == 2`, exactly-2 cards, and a provider marker that flips on the same suffix. A muted scenario needs unread **preserved** and **zero** cards — a direct contradiction. | verified in source 2026-08-17 | **Still true of the in-catalog campaign, but no longer a blocker for muted scenarios.** Plan 379 closed G4 (2026-08-18) WITHOUT redesigning the classifier, by modelling both muted scenarios as out-of-catalog ids in the proven Plan-330 lane with their own validator — so a lane needing unread-preserved and zero-cards now has a working precedent. Unowned for the six catalog scenarios themselves |
| **G16 — reaction campaign only** | **Provider-evidence grammar is dead on relay v1.8.0 for the REACTION lane.** (Scope narrowed 2026-08-19: the payload-campaign half was Plan 380 W0 and is CLOSED and device-proven — see §4.4. What follows is the unowned remainder.) Commit `8d86501e4` (2026-08-15) removed both `[PUSH] Group notification sent to` and `[PUSH] Notification sent to`; v1.8.0 (production since 2026-08-16) emits only unattributed `[PUSH] outcome=success attempt=…` (`go-relay-server/inbox.go:626`). The criteria/capture provider greps (`group_reaction_notification_device_criteria.dart:1980-1995`, capture `:4280-4286`) therefore match zero lines — **all six existing reaction scenarios red at `$.evidence[provider_fcm]` on any fresh capture**. Deeper: the `expectedProviderSendCount == 2` pin is structurally wrong under v1.8.0 wake-outcome admission — admitted recipients skip the immediate group-attributed send (`inbox.go:2813-2822`) and a connected recipient completing the correlation within the 500 ms debounce yields **zero** provider sends (`wake_outcome.go:616-698`); any repaired grammar must count wake-outcome dispositions, not immediate sends. **Plan 380 W0's payload-side fix is the working reference**: match `[PUSH] outcome=success` with `attempt=N total_attempts=N` or `fallback=strict`, and carry recipient binding in the journal SCOPE (`journalctl --since <sentAt>`) instead of in the matched line. | found + source-verified 2026-08-17 (Plan 379 planning, wf_4471f5b3-082 refute pass); payload half closed 2026-08-19 | **OWNED by [Plan 386](../Test-Flight-Improv/386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) W1** (planned 2026-08-19). Two corrections from that planning: a fresh run reds EARLIER than this row says — the capture driver's `_waitForProviderSendCount` (`capture:4511-4523`) times out after 2 min at `:1726`/`:1742`/`:2616`/`:2642` *before* `provider_fcm.log` is ever written, so the `$.evidence[provider_fcm]` red only applies to re-validating an existing artifact; and the reaction lane's REGISTRATION wait is already v1.8.0-compatible (`capture:763` → `:4451-4459`), only the iOS leg still greps the deleted token line (GAP-N12). Plan 386 reuses Plan 380 W0's predicate rather than re-deriving one. Plan 379's muted lane deliberately avoids the dead grammar |
| **G21** | **The killed-app FIRST-WAKE storage deadline still presents nothing — carved out of G17, which is otherwise closed (§4.3).** On Android the first FCM wake after a kill can exhaust the 2s `display_eligibility` phase budget on cold background-isolate warm-up and exit at `PUSH_BACKGROUND_STORAGE_DEFERRED{outcome: storage_deferred}` — a bare `return` at `background_message_handler.dart:681-693` that is UPSTREAM of both the `!shouldDisplay` suppression branch (`:694-706`) and every show lane, so a tripped wake yields no card AND no `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED`; nothing downstream can observe it. Plan 383 deliberately left this exit deferring and test-locked it (`background_storage_deadline_test.dart` 'durable effect authority timeout stays storage-deferred with no fallback card') — **do not read that green test as evidence the behaviour is wanted at product level; its severity is explicitly unmeasured.** The deadline is live in EVERY Android build mode, not debug-gated (`:625-629` enables it on `defaultTargetPlatform == TargetPlatform.android` with the production constants at `:78-85`). The alert is lost but the MESSAGE is not — `direct_stage` completed in both measurements, so the envelope was staged. **Mechanism re-attributed 2026-08-18, do NOT chase SQLCipher:** decomposing the clean run — wake → ART profile install +0.55s → `libgojni.so` dlopen +1.20s → SQLCipher keying +1.55s → first query +1.66s → last query +1.96s → deferral +2.18s — the eligibility resolver's own DB reads take ~0.30s and FINISH ~0.22s BEFORE the timeout; the budget goes to generic cold-isolate first-touch warm-up, and whatever crossed the line after the reads completed was never isolated. Run 1's readonly-open / `PRAGMA cipher_migrate` sequence is NOISE (run 2 has neither and trips at 2.180s against run 1's 2.170s — a 10ms delta, which is the best evidence the deferral is robust rather than a fixture accident). It is NOT universal: in Plan 379 runs 13/14/15 the first post-kill push was a group TEXT and did not trip it, dying at the G19 parity error instead (that error is fixed — §4.6 — so a re-measurement on the current build may well trip the deadline where run 13/14/15 did not). | Plan 383 device runs 1-2 (`docker-ws/plan383_g17_recipient_logcat_run1.txt` / `_run2.txt`): `PUSH_BACKGROUND_STORAGE_DEFERRED{phase: display_eligibility, elapsedBucket: 2s_to_8s}` at 2.170s and 2.180s from wake, no card, no suppression event. **Severity UNMEASURED:** N=2, one device, one kind (`group_reaction`), overrunning by only ~170-180ms, and both measurements are on a DEBUG JIT apk (`critical_features.json:53-58`) AND on the first process start after an APK install (ProfileInstaller runs inside the measured window in both). A release AOT build on a warmed install is entirely unmeasured and may sit comfortably under 2s. No campaign artifact preserves a deferral line — Plan 379's warm-up push now absorbs it by design, so the ONLY surviving device evidence is those two raw logs. | owner named but vehicle inert: Plan 334 built the 8s/2s deadline and books storage-timeout non-display as an explicitly accepted fail-closed degradation; Plan 383 assigns the `storage_deferred` variant to the dropped-push-recovery activation wave (GAP-N08 / WP), whose `recoveryWorkEnabled` retry vehicle is default-off and uninjected. **Structurally undetectable by the one device gate that exists**: `groups.muted_notification_campaign` machine-enforces a throwaway warm-up push and rejects any artifact whose graded push is the first wake, so it can never observe this outcome. First experiments: re-measure on a release AOT build with a warmed install; add exact per-phase elapsed to the deferral event so `2s_to_8s` stops being the only signal; widen the kind sweep to 1:1 text, 1:1 reaction and group text. |
| **G22 — narrowed 2026-08-19** | **The 1:1 MESSAGE half is now device-proven; the remaining kinds are not.** Carved out of G17 (§4.3), whose statement stressed 'NOT group-only'. The seam is kind-agnostic — `requiresDurableEffect` gates on `routeTarget.kind == NotificationRouteTargetKind.conversation` (`background_message_handler.dart:1040`) as well as `.group` (`:1041`). **CLOSED for 1:1 message:** `payload_fast_path_cold_kill` (Plan 380 run 4, 2026-08-19) terminates the receiver BEFORE the send, then observes the background isolate stage the envelope and post a card on `mknoon_messages` — an existence proof, not just a channel one, which is exactly the confirmation this row previously asked for. **STILL OPEN:** 1:1 REACTION on the killed path (host-only, `background_message_handler_test.dart:896`); group/announcement MEDIA; and the announcement variant — untested on the killed path at every tier beyond the shared-gate inference. **Host green still does not imply device green on this seam:** Plan 383's group-MESSAGE host row (`:1271`) passed while the same leg on device posted nothing — G19, a parity failure upstream of this seam, observed 3x. That specific divergence is CLOSED (Plan 384, §4.6), but it is why a host green on this seam is not evidence: the host row stubbed the resolver the device actually ran. | 1:1 message: Plan 380 device run 2026-08-19 (`receiverPidEmptyBeforeTap`, `coldAlertChannel == mknoon_messages`, terminate-before-send verified in the leg source). Remaining kinds: device coverage census over all four killed-app observations (Plan 383 runs 1-2, Plan 379 runs 14-15) — every one is `group_reaction` on `21071FDF600CSC`, one APK, debug JIT | the two dependencies this row was blocked behind (Plan 380 execution, its W0 grammar repair) are both DISCHARGED. Remaining kinds unowned — the cheapest next step is a 1:1 REACTION flavour of the same cold leg |
| **G18** | **PRD §6.5 audience legs without device e2e: the non-author silent leg and the self-reaction no-alert leg.** The reaction campaign's `*_reaction_recipient` scenarios prove only the author leg on device (and that evidence predates relay v1.8.0 — G16). Host tier DOES pin the full audience rule (`group_message_listener_test.dart:17160` three-peer author-not-reactor-not-bystander; REMOVE-silent 1:1 `handle_incoming_reaction_use_case_test.dart:669` + group `:16983`; only the 1:1 observer-of-a-self-reaction leg has no named host pin found) — the gap is device evidence for zero-cards-on-a-non-author-device. Planning constraints: zero-card assertions are exactly what the criteria classifier cannot express (G11 — the same blocker as G4); the campaign topology is a 2-device pair, so a true third-member observer needs the three-party pattern (`intro.accept_notification_campaign` has one) — cheap partial proxy: assert zero cards on the sender device, since the reactor is also a non-author member. | production gates + host pins source-verified 2026-08-18 (paths corrected 2026-08-19: the 1:1 file is `lib/features/conversation/…`, not `features/chat/…`, at the same lines) plus a fourth, previously-unrecorded gate carrying the host-pinned SHOW lane (`group_message_listener_reaction_ingress_processor.dart:414-526`) | **PARTIALLY owned by [Plan 386](../Test-Flight-Improv/386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) W3** (planned 2026-08-19). **Three corrections, one of them structural.** (1) The 'only the 1:1 observer-of-a-self-reaction leg lacks a host pin' clause is REFUTED — `handle_incoming_reaction_use_case_test.dart:547-598` pins exactly that leg; it was missed because its name carries no self-reaction phrase. (2) The 'cheap partial proxy — assert zero cards on the sender device' suggestion is REFUTED and must not be built: `send_group_reaction_use_case.dart:1307` excludes the reactor's own device from `replayRecipients`, so it never receives its own reaction and NO mutation of the audience gate can make a card appear there; the assertion is vacuous by wire topology, before the separate foreground-suppression objection even applies. (3) A group SELF-reaction sends no push to anyone (empty nomination → `inbox.go:2513`, `:2539-2541`, `:2695-2699`), so a device zero-card there is vacuous too — the honest observable is the relay's `[GROUP_REACTION_WAKE] outcome=no_wake_recipients` line. **Consequence: the non-author bystander card leg is IMPOSSIBLE on the 2-device pair** (a bystander needs a third member; the driver has two slots, `capture:320-321`) and the 3-role `group_multi_party` lane has ZERO card assertions. Plan 386 lands the nomination-level self-reaction proof plus a host row for the unpinned protected/replay TWIN (`group_message_listener.dart:3636-3675`), and defers the bystander leg with its cost: a third `--bystander` slot, a three-member group fixture, and a third exclusive resource in `critical_features.json:748-766` — template `run_intro_accept_notification_android.dart`. A second emulator satisfies the hardware need, so this is harness cost, not a hardware blocker |
| **G27** | **Strict-authority group REACTIONS are still silent custody — the remaining half of G26.** The relay now wakes strict group MESSAGES (§4.7) but deliberately declines `payloadType: group_reaction` on the same custody namespace, because that lane's audience is author-only (PRD §6.5) and its copy comes from a separate notification-extension grammar (`reaction_push.go`); routing it onto the group-message push would alert every member instead of the target's author. `extractGroupContentPushMetadata` returns those envelopes recognized-but-ineligible, and a host row pins that they never fall through. So a reaction to your message in a strict group still reaches you only when your app next drains the inbox. | Source + host rows: `group_content_push_test.go` `declines a strict group reaction without falling through` and `TestInboxStore_StrictGroupReactionStaysSilentCustody`. No device observation — no registered scenario creates a strict group. | unowned. The natural shape is a strict-custody sibling of `fanOutGroupReactionPush` that reuses the group-topic reaction's audience resolution rather than the group-message fanout |
| **G20** | **Catalog reaction-lane device evidence is captured by single `adb logcat -d` reads and graded with exact-count predicates, so it can silently under-report.** Harness-soundness defect, NOT a product defect: every cited line is in `integration_test/scripts/`, no `lib/` code is implicated, and the `[FLOW]` substrate exists only in debug/E2E builds (`flow_event_emitter.dart:6` `= kDebugMode`; the lane's `android.production_fcm` profile is a `provider-configured-debug-apk`, `critical_features.json:53-58`). `_readAndroidLogcat` (`capture_group_reaction_notification_device.dart:5570-5588`) is a bare `adb logcat -d -v threadtime` — no `-T`, and no `-G` buffer sizing anywhere in the repo — and `_collectBoundedLogs` (`:2785-2794`) takes exactly ONE read per device after the lane's UI phase; those reads become the authoritative `sender_app` / `recipient_app` / `android_logcat` evidence blocks (`:4841-4870`) for all six catalog scenarios. **Two directions, two evidence tiers — do not conflate them.** FALSE-FAIL is MEASURED: the physical recipient's main ring held ~4 minutes under campaign load (`docker-ws/plan379_run11_rotation_evidence.txt`), which is how Plan 379 run 11 died. FALSE-PASS is STRUCTURAL and UNMEASURED: the exact upper bounds `GROUP_REACTION_SEND_QUEUED != 2` / `GROUP_REACTION_REMOVE_QUEUED != 1` (`group_reaction_notification_device_criteria.dart:2153-2160`), `exactRetryEvents.length == 1` (`:2339-2346`) and the positional send-outcome index (`capture:3834-3836`) all grade `sender_app`, i.e. the EMULATOR (`run_group_reaction_notification_sims.dart:236-240` passes `--sender <emulator> --recipient <physical>`), whose ring retention was never measured. Both false-PASS classes are further backstopped by the rotation-immune relay journal (`journalctl --since @epoch`, exact-count-gated at `capture:2604`, `:2706`, `:2798` and `criteria:2130-2138`), so the surviving hole is narrow: a spurious queued event that the relay dedupes before it reaches the provider AND whose logcat line has aged out of the emulator ring. The recipient half fails CLOSED with a named stage error (`capture:4849-4856` `android_background_group_crypto_marker_missing`), so that direction is a diagnosability problem — a rotation-caused red is indistinguishable from a real crypto-path red — not a silent mis-grade. | census + source audit 2026-08-18 (post-Plan-379 verification workflow, two adversarial lenses, neither able to refute). Ring window measured ONCE, on physical recipient `21071FDF600CSC`, in the Plan-379 MUTED lane — a different lane from the ones this row indicts. **Zero observed impact to date:** the only capture on disk under `build/sims/proofs/groups.reaction_notification_campaign/` is `capture-1786999840782112-51801`, `capture_failed` at `provider_registration` with no evidence blocks, so no catalog artifact has ever been shown to under-report. The measured ring pressure is also partly self-inflicted — uiautomator dump polling, installs and forced FLOW logging, not product log volume. | **OWNED by [Plan 386](../Test-Flight-Improv/386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) W2** (planned 2026-08-19), which is also the G16 owner — exactly the vehicle this row predicted, since that plan must re-run all six catalog scenarios and needs their evidence trustworthy to declare closure. **Two corrections from that planning:** the positional index does NOT only grade the emulator — `capture:3496`/`:3498` send from the PHYSICAL recipient, the one device whose ~4-minute retention IS measured; and an unlisted site of the same defect class exists, `_waitForSenderEventCount` (`capture:4494-4509`, 6 call sites), an absolute-count predicate over a fresh `logcat -d`. **G16 is a sequencing dependency, not the owner** (its remit is provider grammar; it would not touch `_collectBoundedLogs` or the exact-count criteria). Latent today: G16 reds all six scenarios at `$.evidence[provider_fcm]` before any of this evidence is graded. The ONE exposure running today is the `_sendGroupText` count-delta plus positional index (`capture:3820`/`:3834`), which rides every Android lane including the muted lane that currently passes. Remedy: extend Plan 379's recipient accumulator (`capture:3241-3268`) to the sender path and to `_collectBoundedLogs`, replace the positional index with an identity-bound selector, and MEASURE the emulator ring first — the applicable device is currently unmeasured. Prior art, so this is not re-derived as novel: Plan 379 harness-defect 1 (same mechanism, fixed for the muted lane only), its helper-scoped host row (`test/integration/reaction_notification_proof_support_test.dart:149-181`, which cannot constrain the capture sites), and the `logcat-main-vs-system-buffer-heads` landmine (general rule, false-FAIL direction only). Residual inside the fix itself: the accumulator dedupes on exact line text (`capture:3257`), so byte-identical threadtime lines collapse — direction is false-FAIL, safe. iOS sites (`capture:1699-1721`) are latent only under GAP-N12. |
| **G23 — carved out of G7 (§4.4)** | **OEM background restrictions have no device e2e and cannot get one on the hardware this project owns.** Plan 380 closed the other four PRD §13 Android rows but always scoped OEM as `N/A (target unavailable by project policy)`: the pinned pair is a Pixel 6 plus a stock AOSP emulator, and the behaviours at issue (aggressive app-kill policies, vendor battery managers, non-standard doze) exist only on Xiaomi/Huawei/Samsung/Oppo builds. This is a hardware-availability gap, not a missing test — no amount of harness work closes it on stock Google targets. | Plan 380 device run 2026-08-19 closed Doze / permission-denied / channel-disabled / mid-session-token-refresh; OEM was never in reach | deferred — optional AOSP proxies under **GAP-N12**, or acquiring an OEM device for the lab |

### 4.9 Defects found and fixed during Plan 378 execution (recorded so they are not re-derived)

| # | Defect | Impact | Status |
|---|---|---|---|
| **G8** | **Orchestrator false green.** `finally { … exit(failed ? 1 : 0) }` swallowed both the abort and its exit code; with zero scenarios every lane was trivially "stable", so `failed` computed false. An aborted 16-scenario run reported **PASS**. | Any harness/setup failure was invisible — the exact "invisible-but-green" class this map exists to catch | **FIXED**: tracks `runCompleted`/`runError`, compares outcome count vs expected, prints `INCOMPLETE: n/16 … (aborted: …)`. Proven: the identical aborted run went exit **0 → 1** |
| **G9** | **Sound-smoke harness died ~1s into `setupGroupMultiDeviceStack` on every Android device.** Root cause: `f1b568bca` ("close Android notification recovery and storage liveness gaps", committed 2026-08-17 10:34) removed `MainActivity`'s eager `GoBridge` construction — the `com.mknoon/go_bridge` Method/EventChannels now register only after Dart acquires the canonical-runtime lease and calls `attachRuntime` (`mknoon/canonical_runtime_lease`), which only production bootstrap did. Every bridge call returned `MISSING_PLUGIN`; `generateNewIdentity` collapsed it into `GenerateIdentityResult.coreLibError` → `StateError` right after the SQLCipher open. Not plan-378, not device state, not Pixel-specific; iOS unaffected (eager `AppDelegate`). | Blocked every device leg of G1/G2/G3/G6; error text invisible (see the debugPrint-throttle note, §5) | **FIXED**: `ensureCanonicalRuntimeAttachedForTest()` in `group_multi_device_real_harness.dart` mirrors the production acquire→attach (Android-only, fixed binding — the Kotlin broker re-returns the token only for an identical owner/binding/role triple, keeping repeat setups idempotent) before bridge construction. Device-proven 2026-08-17: Alice (Pixel `21071FDF600CSC`) reaches `alice_ready` + a 271ms relay send-proof; Bob (emulator-5554) reaches `bob_identity.json` + real-`FlutterNotificationService` rewiring. Full S1–S16 campaign still to run |
| **G10** | **Group notification lane dead since Plan 371.** Commit `3c7e704e7` (2026-08-16) gated the compat show lane on `_appVisibility != null` (`group_message_listener.dart:3306-3312`); the harness passed only `groupConversationTracker:`, which post-371 is a discarded compat param (`:313-315`). S2/S3/S8–S13 posted **zero** notifications for a day and every gate stayed green. | Plan 378's review recorded the opposite as a "refuted finding"; the refutation was wrong | **FIXED** in the harness. Now guarded: S2/S3 are `audibleStrict`, so a recurrence reds on card count |
| **G13** | `scripts/test/group_reaction_notification_device_contract_test.sh` pinned a 5-row scenario census while the runner emits 6 (Plan 315 added `android_group_reaction_recipient_background_connected` without repinning). It sits inside `sims-contracts`, so that gate could never go green. | pre-existing red, unrelated to Plan 378 | **FIXED** — repinned to the 6 real rows, PASS |
| **G14** | `tool/sims/device_criteria.dart` `_notificationRequirements` is a **10th** registration surface for a payload-campaign scenario; omitting it makes `validateNotificationArtifact` throw `'unknown notification scenario'` at runtime, after the device work is done. It was absent from Plan 378's checklist. | silent late failure | **DOCUMENTED + registered** for `tc_b13`; see §5 |

(iOS legs are deliberately deferred to the consolidated GAP-N12 closure phase per the adopted §9.1 sequencing — not counted as gaps here.)

---

## 5. Maintenance notes

- **The disposition contract is now the pinned version of §1.3.** `dart integration_test/scripts/run_notification_sound_smoke.dart --print-disposition-contract` is byte-compared by `scripts/test/notification_sound_disposition_contract_test.sh` under `./scripts/run_test_gates.sh sims-contracts`. Prefer linking it over duplicating it here; if §1.3 and the contract disagree, the contract wins.
- **Adding a sound-smoke scenario:** it must be a literal `_runScenario(id: 'Sn', … description: '…')` block (the discovery awk sees only single-line quoted literals closed by a whitespace-only `)`/`),`/`);` line); its description must contain `1:1`/`conversation` for the 1to1 family or `group` for the group family and **never both** (the filter lowercases, and a row matching both families would break the 16-row census); and it must be added to `_dispositionContract` — from which `_allScenarioIds` and `laneFor` are now derived, so those no longer drift independently. Suppressed dispositions are excluded from `laneFor` on purpose: they post no record, and counting them would make their own lane look unstable.
- **Adding a payload-campaign scenario: 10 surfaces, not 9.** Catalog `_Scenario`; `_androidPayloadCampaignIds`; **`tool/sims/device_criteria.dart` `_notificationRequirements`** (G14 — omit it and `validateNotificationArtifact` throws at runtime); the checks const; the leg + `_writeScenarioArtifact`; the `_assertionsAttempted` ladder **and both terminal literals**; `_removeScenarioArtifacts`; `critical_features.json` assertions; the adapter contract sh expectation (ordered by `_scenarios` declaration order); and the source-slice freezes in `test/integration/android_notification_payload_campaign_support_test.dart` + the adapter sh's inline `python3` heredoc — **nothing may be inserted inside those windows**.
- **Run `scripts/test/*_test.sh` via `/claude-host-bin/host-run`.** Several build a fake `adb`/`ssh` in `$(mktemp -d)` and prepend it to `PATH`; container `/tmp` is invisible to the host-bridged `dart`/`flutter`, so they fail spuriously in-container. Only a host-run red is a real red.
- **Landmines for future device runs:** `flutter test -d` on the physical phone destroys a stamped release install (restore from the state-guard backup) — and both the Pixel and the emulator currently hold **debug test builds** from the 2026-08-17 G9 diagnosis runs, so re-deploy the stamped build before any release-build evidence run; the Pixel's secure keyguard blocks uiautomator legs while locked; campaign artifact lists (`_removeScenarioArtifacts`) must include any new scenario ID or a failed run leaves stale "evidence".
- **Android bridge harnesses must acquire the canonical-runtime lease before first bridge use** (G9 fixed / G15 open). `setupGroupMultiDeviceStack` does it automatically; anything constructing `GoBridgeClient()` directly must call `ensureCanonicalRuntimeAttachedForTest()` first. A `MISSING_PLUGIN` or bare `coreLibError` ~1s into setup is this, not a stale build.
- **A blank device-test failure is a debugPrint-throttle artifact, not a missing exception.** The test framework's failure dump and all FL-layer `[FLOW]` events go through `debugPrint` (~12KB/s throttle); a fresh-DB migration flood saturates the queue and `flutter test` kills the process ~1s after a failure, so the text dies unflushed — absent from stdout **and** logcat. `print()` is not throttled. The sound-smoke harness `main()` now mirrors `reportTestException` through `print()`; copy that pattern into any harness whose failure comes up blank.
- **Cheap hardening, unowned:** `generateNewIdentity` discards the bridge `errorCode`/`errorMessage` into a throttled `[FLOW]` event and returns bare `coreLibError`; surfacing them in the returned/thrown value would have made G9 a five-minute diagnosis.
- **Do not trust a green from an orchestrator that reports zero scenarios.** G8 was exactly that. The summary JSON's scenario count is the thing to check, not the exit code alone.
- **The FIRST FCM wake after an app kill is not gradeable — never put the push under test in that slot.** It can exhaust the 2s `display_eligibility` phase budget on cold background-isolate warm-up and exit at `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of every policy gate, producing no card AND no suppression event, so any push in that position is silent for a reason unrelated to what you are testing (see **G21**, §4.8). Plan 379's working pattern: send a throwaway warm-up push first and grade only later wakes. Gate the warm-up on `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS` (storage actually warm), NOT on a list of notification dispositions — a warm-up group TEXT USED TO end at `PUSH_ANDROID_DATA_DECRYPT_FAIL` / `PUSH_BACKGROUND_NOTIFICATION_ERROR` with its storage open perfectly complete (G19, fixed by Plan 384, §4.6) — and post-fix it goes the other way and CARDS, which is just as fatal to a disposition list. Either way the storage-warmth signal is the oracle that survived both behaviours. Related: the background isolate is READ-ONLY, so a reaction arriving at a killed app is persisted by the offline-inbox drain on the NEXT app run — which is the SQLCipher probe's own foreground start; poll the probe until the row lands or a single-shot read reports `reactionRows: 0` and looks like a lost reaction.
- **Never build a device wait on a count delta over `adb logcat -d`; bind it to an identity.** The ring rotates (~4 minutes on the physical recipient under campaign load), so a `count(event) > baseline` predicate can be structurally unsatisfiable while the awaited thing happens on time — this cost a full campaign run on 2026-08-18 (`docker-ws/plan379_run11_rotation_evidence.txt`). Bind to the message id the sender published (`GROUP_SEND_MSG_USE_CASE_SUCCESS.messageId`), which the recipient reuses verbatim because incoming group messages store under the envelope's `stableMessageId`; accept `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with a non-empty `existingLocalRowId` as equivalent evidence. Fold every read into a monotonic accumulator so a lane's view only grows. The catalog lanes still do NOT do this — that is G20.
- **`groupIdentityCount` is NOT the number of groups, and a count that exceeds the length of `groupConversationIdSha256` is CORRECT** (checked 2026-08-18 and refuted as a defect, recorded so it is not re-raised on the next campaign run): the count counts unread group MESSAGE rows while the id list is an explicitly deduped set of their conversation ids (`group_reaction_e2e_probe.dart` `.toSet()`). Plan 379 runs 14/15 show count 2 with one listed id because the unmuted control group holds two unread rows; the listed sha byte-equals `controlGroupIdSha256` in every run.
- **Do not re-litigate closed product decisions** when extending tests: same-chat cue = none (OQ-01), read/unread/badge/cleanup are installation-local (OQ-04), mute is per-group installation-local only (OQ-05).
