# Notification Behavior & E2E Coverage Map (UI-23)

- **Maps:** [PRD v1.2](./Mknoon_Private_Reliable_Notifications_PRD_v1.2.md) user-visible notification behavior (§6, §6.1–6.4, §9, §13, AC-01–AC-12) ↔ the tests that exist ↔ the gaps.
- **Siblings:** the [Codebase Coverage and Gap Assessment](./Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) owns the A-01–A-30 architecture traceability and GAP-N01–N12; this file owns the narrower, user-visible question: *which notification appears, with which sound, under which condition — and which test proves it on a real device*.
- **Closure vehicle:** [Plan 378](../Test-Flight-Improv/378-notification-e2e-sound-and-suppression-verification-tdd-plan.md) — **EXECUTED 2026-08-17 at host/contract tier**. G1, G2, G3, G5, G6 and G-reg were implemented and made host-strict there; the G9 harness-start defect is **FIXED** (2026-08-17, §4.16). [Plan 392](../Test-Flight-Improv/392-android-notification-e2e-recurrence-and-permission-divergence-tdd-plan.md) is **COMPLETE 2026-08-20**: after the user-authorized removal of only `com.mknoon.app` from the two pinned Android targets, the guarded S1–S16 campaign passed all sixteen programmatic and OS rows and restored the exact absent/card/channel baseline; the recurring killed-recipient typed-reaction Sims capability also passed; and G24 ended in the required API-37 policy-N/A classification rather than a fabricated aggregate PASS (§4.13). G4 was carved out to [Plan 379](../Test-Flight-Improv/379-muted-group-device-verification-carveout.md), which **closed it at device tier on 2026-08-18** (§4.2).
- **Final Android closure:** [Plan 393](../Test-Flight-Improv/393-android-notification-lifecycle-killed-path-and-recovery-closure-tdd-plan.md) is **EXECUTION-COMPLETE 2026-08-21** at required Android device + host tier. It closes N11, G21, G22b, G27, G30, and controlled-cohort fixed-wake/recovery; §4.14 contains the evidence and §4.15 retains only Apple/release/OEM/optional exclusions.
- **Assessed:** original source assessment 2026-08-17, branch `protected-view`; closure refresh 2026-08-21. Historical `file:line` anchors drift — re-locate with `python3 graphify-arch/tdd_context.py query "<symbol>" --profile general --budget 600` before trusting an anchor in the future.
- **Reading the statuses:** "HOST-STRICT" means a clause is enforced by a machine contract and its device scenario exists, but this map does not cite a passing device artifact for that exact clause. Plan 392 advanced the S1–S16 sound/suppression rows from HOST-STRICT to DEVICE; any remaining HOST-STRICT label below refers to a different boundary (for example the atomic dual-path payload artifact), not to a missing sound campaign.

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

Status legend: **HOST** deterministic host test green today · **HOST-STRICT** a host contract enforces the clause and a device scenario is registered, but no passing artifact is cited here for that exact boundary · **DEVICE** device/e2e proof exists today · **PARTIAL** proof exists but does not assert the full clause · **GAP-Gn** no e2e (see §4) · **TARGET** PRD target state whose mechanism is default-off / not implemented — owned by the coverage doc's GAP-N program, not by this map.

### 2.1 §6 decision-matrix rows and core ACs

| PRD clause | Expected behavior | Existing proof | Status |
|---|---|---|---|
| §6 row 1 / §6.1 / AC-01 | Same chat A foreground-active: update in place, no OS banner, no cue (OQ-01) | HOST `test/features/push/application/show_notification_use_case_test.dart:1153-1186` (exact direct **and** group suppression); DEVICE sound-smoke S4 (1:1, OS-level zero-records); DEVICE S15 group same-chat suppression + post-clear audible control (`run_notification_sound_smoke.dart` S15 block, harness `groupConversationTracker.setActive('group:<id>')`) | HOST + DEVICE (1:1 and group). Announcement device leg deliberately **not** duplicated: the lane seam is prefix-based `group:` for chat and announcement alike (`show_notification_use_case.dart:105-110`), so no defect can separate them there — group-type policy divergence stays host-owned |
| §6 row 2 / §6.2 / AC-02 | Chat B open: A still gets its OS notification, B stays open | HOST use-case tests; DEVICE approximated by S1 (foreground, off-conversation staging screen — not literally another chat) | PARTIAL (host-exact; device approximate) |
| §6 row 3 / AC-03 | Chat list / settings / other screen: A still notifies | Same as AC-02 (S1 is exactly "other screen") | HOST + DEVICE |
| §6 rows 4–5 / §6.3 / AC-04 / G-06 | Inactive/background-running (incl. still-live direct connection): OS notification required; reachability ≠ visibility | Group flavor DEVICE: `groups.reaction_notification_campaign` → `group_reaction_background_connected_recipient`; 1:1 flavor DEVICE S16 — logical lifecycle `paused`, no active conversation, live bridge, real `FlutterNotificationService` + dumpsys, `audibleStrict` disposition | DEVICE (group and 1:1). Boundary honestly labeled: S16 proves still-connected + non-foreground-active only; **true process suspension stays owned by payload-campaign b12**. The PRD §11 stale-visible-thread freshness leg was **cut** — `TrackerBackedAppVisibility.maySuppress` short-circuits to false whenever lifecycle ≠ resumed (`test/shared/fakes/fake_app_visibility.dart:21-27`), so a paused+tracker-set leg cannot fail for the freshness reason; that seam is host-owned |
| §6 row 6 | Suspended/terminated: generic push wakes native processing, render locally | DEVICE `notifications.android_payload_campaign` (b12: background-isolate staged, airplane tap visible, cold-kill startup ingest) + `notifications.android_recovery_completion` (zero-Activity recovery, Plan 374) | DEVICE (custody/visibility). Sound disposition on THIS path remains unasserted — b12 rows still carry no channel assertion; only `tc_b13` does (see AC-10) |
| §6 row 8 / AC-08 | Already read/handled: no re-alert; cancel/update stale | DEVICE a6 replay-before-ack + no-duplicate-render; `groups.notification_projection_durability` read-zero exact cancel; full OQ-03/OQ-04 read-predicate target | PARTIAL + TARGET (OQ-02/03 adopted, not implemented) |
| §6 row 9 / OQ-05 | Muted group: block presentation without changing payload; unread/badge/card semantics per §1.2 | DEVICE `group_mute_notification_db_proof_test.dart` (**SQLCipher projection hop only**); HOST `group_message_listener_test.dart:16483+` (muted suppression persists message), `:17033+` (muted ADD reaction does not notify), `background_message_handler_test.dart:4683-4742`, badge fixture `canonical_notification_badge_state_db_helpers_test.dart:186-239`; sibling independence in `group_multi_device_real_harness.dart`; **NEW** `test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart` — the E2E probe now reports `canonicalBadgeState` from the *production* helper, so a muted group's badge exclusion is observable on device | HOST + **DEVICE**; GAP-G4 **CLOSED** by Plan 379 (2026-08-18, runs 14/15) — card-absence on the live AND FCM/background paths, badge exclusion, unread preserved, delivery unharmed, each with an in-window positive control. Sound/vibration and the media flavour remain unproven |
| AC-05 | Delivery ack without `wake_not_required` must not suppress the wake | N03 coordinator foundations are default-off (Plans 369/370) | TARGET (GAP-N03) |
| AC-06 / OQ-02 | Opening A during build prevents stale A without clearing B | HOST regression captures today's post-then-cancel behavior (`group_notification_read_projector_test.dart:61-109`) — the *target* pre-effect gate is not implemented | TARGET (GAP-N05/N11) |
| AC-07 | Backgrounding between decision and post → final recheck still notifies | No final pre-effect recheck exists on the live path (coverage doc §6.2 race gap) | TARGET (GAP-N05) |
| AC-09 | Dismiss ≠ read; Mark-Read clears exactly | HOST projector tests; DEVICE read-zero exact cancel (projection durability campaign) | HOST + DEVICE |
| AC-10 | One local event, one unread transition, one conversation notification, normally one audible | HOST dedupe rows (use-case tests); DEVICE a6.no_duplicate_render; DEVICE S14 proves one stable conversation card across audible→silent update; `tc_b13_dual_path_single_alert` in `notifications.android_payload_campaign` separately requires a backgrounded-but-connected emulator recipient, `b13.single_card` + `b13.single_audible_channel` + losing-path typed suppression + bounded dual-attempt evidence. Host leg green: `scripts/test/notification_tap_campaign_adapter_contract_test.sh` | DEVICE for render-once/tone-window stability; HOST-STRICT for the atomic retained dual-path B13 artifact |
| AC-11 | Fixed provider payload shape, no forbidden fields | Host fixture census (Plan 368: 44 fixed provider requests), Android classifier (Plan 375) — **default-off**; rich provider path still live | TARGET (GAP-N02; strict score unchanged until activation) |
| AC-12 | Launch after missed pushes: full sync, no duplicate local events | DEVICE payload campaign (b11/b12) + recovery completion campaign | DEVICE |

### 2.2 §9 race rules

| §9 race | Proof | Status |
|---|---|---|
| Direct first, inbox later → one local event | payload campaign a6 (replay-before-ack, ack-purges-relay, no-duplicate-render) | DEVICE |
| Push first, direct later → losing path exits without second alert | HOST dedupe/claim rows; device render-once via a6; **`tc_b13` now asserts the losing path's TYPED suppression** via a union — `NOTIFICATION_SUPPRESSED × {recent_remote_push, message_event_already_claimed}` when the live path loses, `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED × {recent_duplicate_background_push, message_event_already_claimed}` when FCM loses (`integration_test/support/android_notification_payload_campaign.dart`) | HOST-STRICT |
| Open A while A's notification is being built | TARGET (OQ-02 final gate not implemented); host regression documents current post-then-cancel | TARGET |
| Background between decision and post | TARGET (no final recheck on live path) | TARGET |
| Direct persists while background-running → present or leave push as owner | group flavor DEVICE (background-connected recipient); 1:1 S16 passed under Plan 392 | DEVICE (group and 1:1) |
| Late push after locally posted notification → update, **no second audible** | tone lease HOST-proven; DEVICE S14 (`toneDebounce`: flags `[false,true]` + one record + same notification id, channel `mknoon_messages_silent`); `tc_b13` retains the separate dual-path assertion | DEVICE for tone-window update; HOST-STRICT for the atomic B13 dual-path artifact |
| Late push after read → no recreation | a6 + read-zero cancel | DEVICE (partial read-predicate caveats per OQ-03) |
| Crash after persistence before outcome → inbox+push recover | recovery completion campaign (process-death resume, Plan 374) | DEVICE |

### 2.3 §13 required-test families (Android legs)

| §13 family | Status |
|---|---|
| Payload forbidden-field / fixed shape | TARGET (host fixtures exist, mechanism default-off — GAP-N02) |
| Event identity & idempotency per path order | DEVICE (a6/b11/b12) + HOST |
| Visible-thread isolation | HOST full; DEVICE 1:1 (S4) and group (S15 with post-clear positive control) |
| Lifecycle transition (deliver around resign-active/onPause) | DEVICE S16 (logical-lifecycle boundary); group flavor DEVICE |
| Sound disposition (audible vs silent-visible vs suppressed) | **DEVICE** — machine-pinned S1–S16 disposition table, byte-compared by `scripts/test/notification_sound_disposition_contract_test.sh`, enforced per scenario at the OS-capture verdict, and passed unfiltered under Plan 392 (§4.13) |
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
| `notifications.android_payload_campaign` | 1:1 custody: replay-before-ack, ACK purges relay, no duplicate render, staged-visible-before-drain, background-isolate staging, airplane-mode tap, cold-kill startup ingest. **G16 caveat CLEARED 2026-08-19** — was: blocked, a fresh run fatal-timed-out at `_waitForProviderSend` because relay v1.8.0 removed the attributed provider markers. [Plan 380 W0](../Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md) re-derived the predicate against the v1.8.0 grammar and the campaign now reaches and passes all three FCM legs on device (§4.4). [Plan 392](../Test-Flight-Improv/392-android-notification-e2e-recurrence-and-permission-divergence-tdd-plan.md) appends G24 as the tenth strict scenario and four assertions, but the only API-37 emulator rejects the runtime-backed UID override, so the current report is policy-N/A/`targetUnavailable` and no 10-of-10 aggregate PASS is claimed (§4.13). The reaction lane's half of G16 is separate and is now **CLOSED by Plan 386** (§4.8). |
| `notifications.android_typed_reaction_smoke` | Recurring killed-recipient 1:1 typed-reaction proof, added by [Plan 392](../Test-Flight-Improv/392-android-notification-e2e-recurrence-and-permission-divergence-tdd-plan.md): one centrally prepared `android.production_fcm` APK on both roles, zero child builds, fresh unique capture, typed card/provider/tap/unread oracle, content-addressed aggregate evidence, unchanged APK SHA, and exact Android state restoration. Device PASS 2026-08-20 on physical `21071FDF600CSC` + emulator `emulator-5554` (§4.13). |
| `notifications.android_recovery_completion` | Plan-393 recurring fixed-wake direct-reaction recovery: distinct alive/background and killed transitions, live opaque-route selection, silent generic reservation, no-Activity WorkManager continuation, canonical settlement/presentation, exact generic retirement, authenticated ephemeral-route removal, zero cards, and exact local restoration. Device PASS 2026-08-21 (§4.14). |
| `groups.reaction_notification_campaign` | Group & announcement message unread lifecycle, group/announcement reaction recipient cards, group reaction to a background-but-connected recipient. **G16 caveat CLEARED 2026-08-19** — was: a fresh capture red all six scenarios at `$.evidence[provider_fcm]` because relay v1.8.0 removed the attributed provider markers. [Plan 386](../Test-Flight-Improv/386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) moved provider evidence onto relay COUNTER DELTAS and rebuilt the log substrate (G16 + G20, §4.8). **5 of 5 Android scenarios pass on device since 2026-08-19.** The two killed-recipient reaction scenarios were blocked downstream by the cold-wake storage deferral (**G21**, §4.14), not by anything in this lane; [Plan 389](../Test-Flight-Improv/389-reaction-lane-post-kill-warmup-and-group-scoped-cards-tdd-plan.md) unblocked them with a post-kill warm-up text into a SECOND group plus group-scoped card and unread assertions (§4.10). |
| `groups.notification_projection_durability` | Two-group read-zero exact cancel, killed incoming JPEG with exact relay-branch discriminator, media-reaction semantic kinds (photo/video/voice), stable single card. Plan-393 device PASS 2026-08-21 (§4.14). |
| `groups.strict_notification_closure` | Exact-chat suppression plus killed strict-group message and author-targeted strict ADD reaction, with relay provenance and state restoration. Added and device-passed by Plan 393 (§4.14). |
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

  **Device closure (Plan 392, 2026-08-20).** Run `1787244621233` on physical `21071FDF600CSC` + emulator `emulator-5554` completed exactly sixteen rows. Every `programmaticPass` and `osNotification.pass` was true; direct/group/announcement notification IDs were stable for all applicable observations (6/6, 4/4, 4/4); and the guarded package/card/channel snapshot was byte-identical after both packages were restored to absent. Retained summary: `build/plan392/sound-smoke/notification_sound_smoke_summary.json`, SHA-256 `4fed5a4b72edd015adb432808fba6fc3e6fbb64ee29c406662b2fc353b5a2c1f`.

  **Two HEAD defects found and fixed during execution** (neither was in the plan): the harness constructed `GroupMessageListener` with `groupConversationTracker:` but **no `appVisibility:`**, and since Plan 371 (`3c7e704e7`) the compat show lane is gated on `_appVisibility != null` (`group_message_listener.dart:3306-3312`) — so **every group and announcement row had been posting zero notifications** and no gate noticed; and the orchestrator's `finally { … exit(failed ? 1 : 0) }` reported an aborted run as a **pass** (see G8/G10).

- `notification_open_during_other_chat` — background→notify→tap-routes (fake notification service; call-log assertion only, **no OS-level record check**; logical-lifecycle backgrounding).
- `notification_open_ui_smoke` — 1:1/group/intro tap routing rows.
- 1:1 reaction device proof (`run_1to1_reaction_notification_device.dart`, capture-owned artifacts).
  **`android_typed_reaction_smoke` added and device-proven 2026-08-20**
  ([Plan 391](../Test-Flight-Improv/391-killed-path-1to1-reaction-device-proof-tdd-plan.md), §4.12):
  the recipient is killed on the common path, the reaction is driven by real UI on the sender, and
  the artifact records a MEASURED `recipientProcessAbsentBeforeReaction` beside the typed card, its
  tap route and the unread lifecycle. Provider attribution is DEVICE-SIDE — the relay's peer-
  attributed push line no longer exists. A forced-fresh final run at `5f4df8c0a` reproduced the
  device closure and passed the runner's own artifact oracle; the closed 1:1 obligation now lives
  only in §4.12, not in §4.14. The recurring-ownership caveat is closed by Plan 392 (§4.13): the
  exact selector now has one required, automation-ready Sims owner and passed from one unchanged
  central APK with zero child builds and exact state restoration. The remaining caveat is that the
  card came from the non-durable fallback, not the durable arm. **A second scenario
  `android_durable_reaction_background_connected` (`TC-DURABLE-DIRECT-REACTION`) was added
  2026-08-20** to grade the durable arm itself: it BACKGROUNDS the recipient instead of killing it,
  records a measured `recipientProcessAliveBeforeReaction`, and fails closed unless the recipient's
  own log shows a durable `direct_reaction` show. **It is RED on device today and that is the
  finding, not a broken lane** — see **G29** in §4.12a.
- `group_mute_notification_db_proof_test.dart` — real-SQLCipher `is_muted` projection hop (the DB read the mute decision depends on), **not** the end-visible mute effect.
- Sibling mute independence — `group_multi_device_real_harness.dart` (muted sibling stays quiet, unmuted sibling presents, both keep unread).
- **Token-rotation → production relay registration chain** (added to this inventory 2026-08-17; previously missed, which is why G7 wrongly claimed "token refresh: zero e2e") — `capture_android_background_crypto_preflight.dart` (in-app `deleteToken` rotation via a staged, subject-hash-bound command file; real FCM delivered to the ROTATED token at a killed process) chained into `capture_android_push_relay_registration.dart` (drives the PRODUCTION main, requires `PUSH_REGISTER_RELAY_PROOF_COMPLETE` + `PUSH_REGISTER_COORDINATOR_SUCCESS` in the flow log). Device-proves the A-07/A-08 rotation+registration path; the **mid-session live `onTokenRefresh`** in the running app is the only unproven half → [Plan 380](../Test-Flight-Improv/380-notification-device-matrix-and-b12-sound-tdd-plan.md) `tc_g7_token_refresh_mid_session`.

### 3.3 Host tier (deterministic, green today — the *logic* of §1 is fully proven here)

`test/features/push/application/show_notification_use_case_test.dart` (56 tests: suppression, dedupe, forceSilent, copy), `test/core/notifications/notification_tone_tracker_test.dart`, `test/core/notifications/durable_notification_tone_lease_test.dart`, `test/core/notifications/local_notification_support_test.dart` (channel definitions), mute decision in `background_message_handler_test.dart` + `group_message_listener_test.dart`, badge exclusion fixture, `flutter_notification_service_test.dart` (`:214` audible default channel, `:385-405` silent channel).

Added by Plan 378:
- `scripts/test/notification_sound_disposition_contract_test.sh` — three cases: the byte-pinned S1–S16 disposition table, the offline OS-capture decision function against ≤3 canned dumpsys fixtures, and the 16-row discovery census. Auto-registered by the `scripts/test/*_test.sh` glob into `./scripts/run_test_gates.sh sims-contracts`.
- `test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart` — the probe's `canonicalBadgeState` comes from the production helper `dbLoadCanonicalNotificationBadgeState`, so dropping `AND g.is_muted = 0` re-reds it.

**The structural point (updated):** host proves the *decision*, and the disposition contract makes the device tier assert the same predicate. Plan 392 completed that device tier: the installed-package negative preflight first proved fail-before-mutation, the user-authorized exact-package removal established the required absent baseline, and the subsequent unfiltered S1–S16 run passed and restored that baseline (§4.13).

---

## 4. Gap register — what no e2e verifies on the device pair

Read §4.1, §4.13 and §4.14 together: Plan 378 closed six gaps *as work*. The harness-start blocker **G9** is FIXED (2026-08-17, see §4.16), and Plan 392 closed both the destructive state-ownership hole and the positive S1–S16 device acceptance. The §4.1 sound/suppression rows are now device-proven where §4.13 says so; Plan 393 closes the later required Android residuals in §4.14.

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
| **G16 — the capture-blocking half only** | Commit `8d86501e4` also deleted `[PUSH] Token registered for …`, which the shared capture waited on at `run():747` **before** lifecycle dispatch — so it blocked **every** Android scenario in the driver, not just the provider-evidence assertion | Attribution moved to the recipient boundary: `androidRelayPushRegistrationAccepted()` waits on the device's own log for `relay_push_registration_success platform=android` / `PUSH_REGISTER_TOKEN_SUCCESS`, both derived from the bridge `ok` the Go node sets only after the relay replied `Status:"OK"` — server-side acceptance, not client intent. `PUSH_REGISTER_TOKEN_SENDING` is explicitly rejected | Zero relay changes; Plan 368's pinned `[PUSH]` vocabulary untouched and no identifier re-added. Strictly better attribution than the deleted line, which carried only a 20-char peer prefix. A census host test now pins every literal the capture waits on against its real emission site. The provider-evidence half of G16 is now **CLOSED by Plan 386** (§4.8). |
| **G17 residual (Plan-379-owned)** | The muted adapter still red at `capture…:3417` (`suppressed.isNotEmpty`) after Plan 383's fix, because the muted group's FIRST post-kill push exits at `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of the mute gate | A throwaway warm-up push absorbs the un-gradeable first wake, and the validator machine-enforces it: ≥3 wakes, and neither graded push may be the first | `suppressed.isNotEmpty` was **NOT** weakened — it now passes on its own terms. Four new validator rules, each mutation-checked to red exactly its own host row and nothing else |
| **Harness soundness (three defects, found runs 11-13)** | (a) the live arrival gate counted `GROUP_MESSAGES_DB_INSERT_SUCCESS` occurrences and required `count > baseline` — unsound, because the logcat ring rotates; (b) the warm-up gate enumerated notification dispositions; (c) the reaction-row probe raced the offline-inbox drain | (a) arrival bound to the sender's published message id, plus a monotonic accumulator behind every recipient log read; (b) gate on `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS` — storage warmth, the cost actually being absorbed; (c) poll the probe until the row lands, 3-minute bound | Runs 11/12/13 red → 14/15 green. (a) was replayed against run 11's own device logs before re-running and is pinned as a negative host row so the unsound delta cannot return; (c) keeps `reactionRowsObserved >= 1`, so a genuinely lost reaction still fails the lane. Evidence: `docker-ws/plan379_run11_rotation_evidence.txt` |

**Not closed by Plan 379 — carried forward, so the G4 row above is not read as more than it is.** The muted lane contains ZERO assertions on channel, importance, sound, tone or vibration: tone-absence is *entailed* by channel-agnostic card-absence (the matcher accepts a pkg record on ANY channel, and no independent audio/haptic path for incoming messages exists), not independently observed. The FCM leg closes that escape by binding the suppression event to the muted messageId — no show call ever happened — but the LIVE leg has no analogous field and rests on card count alone. Only **2 of G4's 6 flavour × path cells** ran (text/live, reaction/FCM); muted reaction on the live path and muted text on the FCM path are untested, and a muted-text-on-FCM assertion would currently pass **vacuously** because per **G19** the unmuted group-text killed-path leg dies at `push_decrypt_preview` parity before any display decision. The media flavour is host-tier only by design (the policy gate is a single content-agnostic seam ahead of any kind dispatch). "Card retirement on mute" is asserted as absence but is **not causally attributed** to mute: the choreography opens the group's own Group Info to reach the switch, and opening a conversation clears its card independently. iOS legs remain deferred to GAP-N12. Gaps found *by* this work but not closed by it: **G19** (killed-path group-text parity failure — since CLOSED by Plan 384, §4.6) and **G20** (catalog-lane evidence-capture soundness — since CLOSED by Plan 386, §4.8).

### 4.3 Closed by Plan 383 (2026-08-18 — G17, scoped)

**Verified before filing here** (4 evidence strands + 3 adversarial lenses, 2026-08-18). One lens refuted a wholesale move: G17's statement was written wider than what was fixed, so the mechanism closure is recorded below and the three sub-claims that did NOT close at that time were carved out to **G21** (first-wake storage deadline), **G22** (1:1 device evidence), and **G19** (the killed-path group-text hole). G19 was closed by Plan 384 (§4.6), the 1:1 portion of G22 by Plan 391 (§4.12), and the renamed media-only G22b plus G21 by Plan 393 (§4.14).

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
| **G16 — payload half only** | `relayJournalContainsAndroidProviderSend` grepped a log line commit `8d86501e4` had deleted, and `_waitForProviderSend` is a fatal 2-minute wait on all three payload FCM legs — so a fresh `notifications.android_payload_campaign` could not survive its warm leg at all | Plan 380 **W0**: the predicate re-derived against the v1.8.0 grammar (`[PUSH] outcome=success attempt=N total_attempts=N` / `fallback=strict`). Recipient binding moved into the journal **scope** (`journalctl --since <sentAt>`) rather than the matched line, and a source freeze pins that scoping | DEVICE: the campaign reaches and passes all three FCM legs — the failure mode this gap described is gone. The reaction-side half is now **CLOSED by Plan 386** (§4.8), which reused this very predicate rather than re-deriving one. |

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

**Device caveat, updated by Plan 392: the current matrix still cannot prove this one, and now says
why with a typed result.** `tc_g7_permission_denied` remains the ordinary `pm revoke` row and does
not stand in for G24. Plan 392 added distinct `tc_g24_permission_appop_divergence`, keeps runtime
permission granted, captures/restores both app-op baselines, and requires the exact override/result,
no-card, custody and recovery evidence before it can pass. On the only available emulator
(`emulator-5554`, Android 17 / API 37), package-mode writes are rejected and UID-mode `ignore`
produces `AppOpService: Blocked setUidMode call for runtime permission app op`; the app consequently
reports the truthful measured state it sees on that image:
`authorized/granted:true/osEnabled:true`. The final Sims run therefore records
`BLOCKED`, `blocker: targetUnavailable`, with the exact policy-N/A detail and no aggregate payload
PASS, then restores the UID override, runtime permission, package state and outer guard baseline.
This is `N/A (target unavailable by project policy)` for the current live matrix, not a product
failure and not permission to substitute `pm revoke`, the physical sender, or an unavailable API
band. The Plan-385 host proof remains the positive regression oracle; a future already-available
emulator with a genuinely settable runtime/app-op divergence may supply optional additional device
confidence.

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

### 4.6 Closed by Plan 384 (2026-08-19) — G19 (device tier) and G26 (host tier + live deploy)

#### 4.6.1 G19 — the parity false positive (Wave 1, device tier)

**A killed-app group TEXT posted no OS card, because the plaintext parity predicate rejected an
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
in §4.14, found by this plan's producer census and explicitly out of its scope.

#### 4.6.2 G26 — the strict-authority lane's missing push (Wave 2, host tier + live deploy)

**G26 — a strict-authority group's messages were delivered to custody and then went silent.**
Same closure vehicle as G19 above: [Plan 384](../Test-Flight-Improv/384-killed-path-group-text-parity-card-tdd-plan.md), Wave 2.

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
recorded as **G27** at the time and later closed by Plan 393 (§4.14).

| Proof | Tier | What it pins |
|---|---|---|
| `group_content_push_test.go` `TestExtractChatPushMetadata_StrictGroupContentIsInvisible` | host (Go) | the root cause itself: the generic extractor cannot see this envelope, so a dedicated lane is required rather than optional |
| same file, `TestInboxStore_StrictGroupContentWakesTheRecipient` | host (Go) | the causal row — asserts the 7 data keys the recipient routes on. Deleting the new branch reds exactly this row and the fallback row |
| same file, `…StaysSilentWhenDisabled` / `…StrictGroupReactionStaysSilentCustody` / `…WithUnusableEpochStillWakes` | host (Go) | the kill switch never drops custody; reactions stay silent; an unusable key epoch degrades to a routing-only push rather than to silence |
| `push_decrypt_preview_test.dart` `'strict-lane group content push renders the trusted group card'` + the routing-only fallback row | host (Dart) | the recipient half — the exact 10 data keys the relay now emits produce a trusted card with zero `PUSH_ANDROID_DATA_DECRYPT_FAIL` |

**Status: HOST-GREEN and LIVE, but NOT device-proven.** Relay **v1.9.0** was deployed to production on
2026-08-19T10:11:54Z with `GROUP_CONTENT_PUSH_ENABLED=true` (sha
`3bdf81f66127c4fcd9318582a1d75e40f8363114def69b47c7b1b3c297359dbc`, backup
`relay-server.pre-1.9.0-20260819T101139Z`). Verified live: the banner, `strict group content push
enabled=true`, `backend=redis durable=true`, `relay_backend_durable 1`, push tokens preserved exactly
across the restart (563 android / 1226 ios), `NRestarts=0` at t+108s, zero panics, zero `Refusing
oversized`. The prerequisite `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED` was already true — without it
strict content is never stored and this lane is never reached.

**What is still NOT proven:** no device leg exists. The muted/killed campaign creates ORDINARY groups,
so no registered scenario reaches this path, and the first live strict-group send has not yet been
observed. Every statement about production behaviour here is inference from host rows plus a clean
startup — not a card on a phone. The first real evidence will be
`relay_group_content_wake_total{outcome="attempted"}` moving off zero; the counter is absent from
`/metrics` until then, which is normal for an unobserved Prometheus label set and is NOT itself a
fault signal. Treat this row as "shipped and live, awaiting field confirmation", not as a closed
device promise.

### 4.7 Closed by Plan 387 (host tier, 2026-08-19) — the sims-contracts gate could not run past its 4th contract

**Not a notification defect. A gate defect that hid notification defects.**
`./scripts/run_test_gates.sh sims-contracts` returns on the first failing contract
(`scripts/run_test_gates.sh:1706-1760`), and it had been failing at contract **#4** since at least
2026-08-17. Everything after #4 — 40 contracts, including the ones plans 384 and 385 register into —
was simply not being run. This is the same class as **G13** (§4.16): a stale pin inside `sims-contracts`
that keeps the whole gate from ever going green.

| Gap | What was wrong | Fix | Outcome |
|---|---|---|---|
| **G13-class, H1** | `dtr13_profile_entrypoint_preservation_contract_test.sh` — the `DTR13-AUTH-01` byte lock had **TWO** drifted roots, not one: `lib/smoke_test_main.dart` (`522bc158…`→`c99e6212…`) **and** `lib/smoke_test_restore.dart` (`09cefe37…`→`43226bf4…`). The assert sits inside `for path, expected_hash in expected_hashes.items()` (`:211-213`), so the loop died on the first and the second was invisible. Plan 380's note recorded only the first — a one-hash fix would have redded again on the next run | Both re-pinned **after** provenance verification: `git log -1` names `87f0f7ba0` for both, and `git show` is one line each, `identity/domain/repositories` → `identity/data/repositories` (the DTR-18 relocation). The old path no longer exists, so reverting would not compile — re-pinning was the only correct fix. A **key-set assertion** was added before the loop, because the dict was only ever iterated: an executor could have deleted an entry instead of re-pinning it, exited 0, and silently removed a freeze | **CLOSED.** Three mutations recorded: appending a byte to `smoke_test_main.dart` reds naming it; appending to `smoke_test_restore.dart` reds naming **it** (proving the previously-shadowed pin is live); deleting an entry now reds with `DTR13-AUTH-01 byte-lock key set changed` |
| **G13-class, H2** | `intro_accept_notification_sims_adapter_contract_test.sh` — the failing assertion was **not** the one Plan 380 named. Plan 380 blamed `'final output = await _adbShell'`, which still matches. The real failure is the launch-status regex at contract line 42: the literal moved out of `_launchAll()` into the top-level helper `isAndroidActivityStartAccepted` (`run_intro_accept_notification_android.dart:82-87`) and was widened to `(?:ok\|timeout)`, with its rationale at `:75-81` | The contract now slices **both** regions: `_launchAll()` must call `isAndroidActivityStartAccepted(`, and the helper slice must carry the exact widened literal. The `monkey` ban and the `am`/`-W`/`-n` fragments are untouched | **CLOSED.** Both mutations recorded and required: widening the helper regex reds the helper slice (`<stdin>`:20); deleting the call from `_launchAll` reds the launch slice (`<stdin>`:11). Deleting the failing assertion is no longer a passing "fix" |
| **G13-class, H3** | `project_memory_recall_contract_test.sh` — red from **committed** code, not from the untracked plan-381 work Plan 380 blamed (`project-memory/` is clean at HEAD; both files landed in `90bc7d601`). `test_memory_never_overrides_plan_facts` compares `source_doc` against the **unresolved** `TemporaryDirectory` name (`test_project_memory.py:902`, `:910`) while `build_graph.py:699` stores `str(path.resolve())`. On macOS `$TMPDIR` is `/var/folders/…` with `/var` → `private/var`, so both memory rows miss the prefix and the count is 2 | Both prefixes resolved, **test-side only**. `project-memory/src/` is in the plan's hard `Do not` and `git diff --stat project-memory/src/` is the wrong-fix guard | **CLOSED**, with a landmine recorded: the wrong fix — dropping `.resolve()` at `build_graph.py:699` — makes the suite pass. It is caught **only** by the source-diff guard, not by any assertion. The sibling `leaked` check at `:902` stays structurally vacuous (the plan pass writes a **relative** `source_doc`, the memory pass an **absolute** one, so no prefix can match either way); resolving it is correct hygiene, not a fix, and that is stated rather than claimed |

**Gate outcome, stated honestly.** `sims-contracts` now **runs every contract** instead of aborting at
#4 — `--continue-on-failure` reports **43 PASS / 1 FAIL** where it previously reported 40 PASS / 4 FAIL.
It still **exits 1**, on a fourth red that Plan 387's step-1 measurement discovered and deliberately did
not fix. That red was recorded as **G28**: it is a behavior decision, not gate hygiene, and Plan 393 removes it from notification still-open accounting (§4.15).

**Why this belongs in this map.** Every notification device plan closes through `sims-contracts`
(Plan 380's TC-380-10, Plan 384's scenario census, Plan 385's registration). While the gate aborted at
#4, none of those registrations was actually being verified end-to-end, and a fourth contract had been
red for **ten days** without anyone seeing it. The measurement step that found it is the durable lesson:
when a gate fails fast, run it with `--continue-on-failure` before trusting any prior list of what is red.

### 4.8 Closed by Plan 386 (2026-08-19) — G16 and G20 (device tier), G18's self-reaction leg (device tier)

[Plan 386](../Test-Flight-Improv/386-reaction-lane-evidence-repair-and-audience-device-legs-tdd-plan.md) —
EXECUTED `4040feb82`, `9c6874e25`, `59ce6b818`, `c6603d840`, `e19ed5424`, `d26ff90ec`. Harness, test and
gate source only: **no `lib/` change and no `go-relay-server/` change**. Three defects, none of them a
product bug.

| Gap | What was wrong | What closed it | Evidence tier |
|---|---|---|---|
| **G16 — reaction lane** | Relay `8d86501e4` deleted every attributed `[PUSH]` line, so four client sites grepped a dead grammar. A fresh capture died on a 2-minute provider wait **before** `provider_fcm.log` was ever written; re-validating an old artifact red at `$.evidence[provider_fcm]`. | Provider evidence moved off the journal onto an exact **relay counter delta**. The capture scrapes `:2112/metrics` raw at the capture-window start and again after quiescence, writes both as a new `relay_metrics` evidence kind, and the validator **re-derives** the delta rather than trusting a number the capture wrote. Split by lane, because `fanOutPush` emits zero `log.Printf` and has no wake counter: reaction scenarios require `attempted == expectedRelayWakeAttempts` **and** `route_error == 0` **and** `incapable_skipped == 0`; message scenarios keep `[GROUP_INBOX] Stored message for group` plus a floor on `relay_push_sent_total`. The v1.8.0 acceptance grammar is **imported** from Plan 380 W0 and a census pins that exactly one file defines it. | **DEVICE.** `relay_push_sent_total{result="success"}` 1 → 3 on the message lane; on the reaction lane `attempted` 4 → 6 (delta 2) while the REMOVE landed in `invalid_or_disabled` and the duplicate redrive in `duplicate_suppressed` — all four transitions in different buckets, only the two ADDs counted. `provider_fcm.log` now carries real acceptance lines where the dead filter wrote it empty. |
| **G20** | Every graded read was a one-shot `adb logcat -d` whose retry predicate was `exitCode == 0` only, so a rotated, empty-but-successful window was **accepted and never retried**. Two such reads became three evidence kinds. On top of that: a positional send-outcome index, absolute-count waits, and a flow accumulator that deduped on exact line text. | Both devices now stream `adb logcat -T 1` to a run-local file; every window is a **byte-offset cursor**. The eight `logcat -c` clears stay exactly where they are — `_adb` intercepts each one and raises a stream **floor** instead of destroying evidence, so a new clear can never be added without its floor. The graded send outcome is selected by a breadcrumb the harness **mints into the device's own log** for that send (`adb shell log -t MKNOON386 send_marker=<marker>`), and fails closed when it is absent. The accumulator folds as a **multiset**, so two distinct events that render identically stop collapsing into one. | **DEVICE.** Both device logs streamed to disk for whole runs with no rotation. A scoped seam in `group_reaction_notification_device_contract_test.sh` bans the exact 4-element post-hoc read on graded paths while permitting the two `--pid=`-scoped setup polls; re-adding one reds it. |
| **G18 — self-reaction leg** | PRD §6.5 says a group reaction alerts only the target's author. On device this was untested, and at host tier the protected/replay twin had **no negative row at any tier** — its only exercise seeded an author-owned target, so the author-only clause at `group_message_listener.dart:3651` could be deleted without reddening anything. | One extra graded step inside the existing muted background scenario (**no new scenario id**): the sender reacts to its own warm-up message. Plus three host rows driving the protected twin directly, one of them shaped to isolate the author check from `target.isIncoming`, which otherwise shadows it. | **DEVICE + host.** Across the self-reaction transition: `no_wake_recipients` absent → 1 (delta 1), `attempted` 4 → 4 (delta 0), `relay_push_sent_total` 25 → 25 (delta 0 — no push existed at all), sentinel 6343 → 6365. Cards: recipient 1 → 1, sender 0 → 0. Mutation-verified at host: deleting the author-only clause reds the isolating row while the 227-test live-path suite stays green. |

**Two facts worth not re-deriving.**

1. **A labelled relay counter is absent from `/metrics` until its first increment.** Both graded families
   are `promauto.NewCounterVec`s. Measured against the production box after the v1.9.0 restart: a healthy
   endpoint served 53 KB with **zero** `relay_group_reaction_wake_total` and **zero** `relay_push_sent_total`
   lines. Liveness must key on a PLAIN counter — this lane uses `relay_group_inbox_retrieves_total`
   (`go-relay-server/metrics.go:384`), which is also monotonic within a process and therefore doubles as a
   **process-continuity oracle**: a relay that restarted mid-capture is rejected even when the graded deltas
   look perfect in isolation.
2. **The ring-size figure in §4.4 is the EMULATOR's.** Measured 2026-08-19: `emulator-5554` main ring =
   **2 MiB**, physical `21071FDF600CSC` main ring = **256 KiB**. At the ~800 KB/min a campaign emits, every
   post-hoc `logcat -d` read on the graded physical recipient was a **~19-second** window. G20 was more
   severe than it was assessed to be.

**Residual — TC-386-11 was 3 of 5; CLOSED 2026-08-19 by [Plan 389](../Test-Flight-Improv/389-reaction-lane-post-kill-warmup-and-group-scoped-cards-tdd-plan.md) (§4.10), now 5 of 5.** The record below is kept because its reasoning about *why* a warm-up could not work here was refuted in source. `android_group_message_unread_lifecycle`,
`android_announcement_message_unread_lifecycle` and `android_group_reaction_recipient_background_connected`
all pass on device. The two killed-recipient reaction scenarios are blocked **downstream of everything this
plan owns**, by the cold-wake storage deferral — see **G21** in §4.14, whose row now records the measurement.
Closing them means re-scoping those scenarios' evidence contract (unread pins, UI unread snapshots, card
assertions), which is a scope change Plan 386 deliberately did not make. **The coordination with
[Plan 388](../Test-Flight-Improv/388-killed-path-cold-wake-deferral-observability-tdd-plan.md) is RESOLVED
(2026-08-19, §4.9):** 388's Waves 1-2 landed at host and device tiers, and its Wave 3 deliberately did NOT
re-run these two — 388 *measures* the deferral rather than fixing it, and its own hard rule forbids adding
a card, a retry or any alerting change. The evidence-contract re-scope therefore stays here. One plan-fix
388 contributed for whoever resumes: the Plan-330 media-target reactions are in
`groups.notification_projection_durability`, **not** this campaign, so they are independently runnable and
do not sit behind this lane's fail-fast.

To re-run one scenario without the whole fail-fast campaign:
`/claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh <scenario-id>`.

### 4.9 Closed by Plan 388 (2026-08-19) — G21's measurement instrument (host tier) and its blind device slot (device tier)

[Plan 388](../Test-Flight-Improv/388-killed-path-cold-wake-deferral-observability-tdd-plan.md) —
Waves 1-2 EXECUTED. **This plan closes the INSTRUMENT, not the defect.** G21 itself — a killed-app
first wake losing its alert — is unchanged and stays in §4.14; the plan's own hard rule is *"do not add
a fallback card, a retry, or any alerting change for `storage_deferred`. This plan measures."* What
closed is the three reasons G21's severity could not be measured or observed.

| Fragment | What was wrong | What closed it | Evidence tier |
|---|---|---|---|
| **G21-a — the only timing signal was a three-value bucket** | Both surfaces discarded the exact elapsed and emitted `bucketBackgroundStorageElapsed` instead (boundaries 2s and 8s). Nobody could tell a comfortable 0.4s from a 1.97s near-miss, and the raw milliseconds existed exactly once, in an unused `toString()`. Worse, the exception carried only TOTAL elapsed: **no phase-start stamp existed anywhere in `run<T>`**, so phase-local time was not merely unemitted, it was never computed. | `BackgroundStorageDeadlineExceeded` gains `phaseElapsed` and `budget`; `_BackgroundStorageDeadline` stamps `_phaseStartedAt` as the first statement after the `enabled` guard — **before** the `remaining` check, because `run<T>` is not `async` and the aggregate-exhausted branch throws synchronously. `budget` is the bound actually applied, `min(remaining, phase)`, not the configured constant. The FL event and the durable journal record both gain `elapsedMs`, `phaseElapsedMs`, `budgetMs`; the record goes 6 keys → 10 and stays `<String, String>` alongside the unchanged bucket. | **HOST.** Exact equalities against an injected `_FakeMonotonicClock`, with total / phase-local / budget deliberately three DIFFERENT numbers so an implementation emitting one of them three times cannot pass: ordinary `727/137/300`, aggregate-remainder `843/53/**110**` (the configured phase was 400), aggregate-exhausted `690/**0**/**0**`. |
| **G21-b — two different exits were indistinguishable in the record** | The phase name was mapped through an enum whose `_ => localState` default swallowed everything unlisted, so `preview_resolution` and `durable_effect_authority` were **permanently identical** in both the event and the journal apart from timings. Plan 383 pinned that collapse as truthful-current. | A sibling closed enum `BackgroundStorageDeadlinePhaseName` (the 11 real `.run` phases + `unknown` + `fromWireName`) rides alongside the mapped family. The journal's documented privacy invariant — *"values are fixed rather than caller-provided strings so an identifier cannot accidentally be persisted"* — is preserved and re-established, not merely asserted in prose. | **HOST.** Both phases drive real deferrals through `firebaseMessagingBackgroundHandler` and land on one decoded record each: `phase` still `local_state`, `phaseName` distinct. Guarded by a source census over all 11 `.run(` first arguments (each must be a compile-time literal inside the domain), an all-member `fromWireName` round-trip, and a member-by-member freeze of the wire names. |
| **G21-c — no device gate could observe the outcome** | G21's row recorded that `groups.muted_notification_campaign` machine-enforces a warm-up push and rejects any artifact whose graded push is the first wake, so *"it can never observe this outcome"*. That was true of that lane — but **`_runColdPayloadLeg` in `notifications.android_payload_campaign` already sat in the exact G21 slot and threw the evidence away.** It kills the receiver, takes a rotation-proof cursor, sends, and waits for the card, with nothing touching the receiver in between: its graded push IS the first wake, on a WARM install (so Plan 383's ProfileInstaller confound is absent for free). If G21 tripped, the leg died as an untyped `_waitForNotification` timeout 48 lines before it read its own window. | The cold cursor is kept on the instance; the graded window is scanned and latched clean immediately after the frozen kill/network triple, before the tap and the cold relaunch; `run()`'s cold dispatch goes through a classifier that re-types a card-wait failure as a **named** deferral carrying the phase and the exact milliseconds; and `coldWakeDeferralScan` is now REQUIRED evidence on every `payload_fast_path_cold_kill` artifact. No new parser and no new file — the existing format-agnostic `androidNotificationFlowRecords` / `_flowRecordsSince` do the reading. | **DEVICE.** Campaign PASS, 9 assertions, sender `21071FDF600CSC` + receiver `emulator-5554`. `payload_fast_path_cold_kill.json` @ 2026-08-19T16:14:23Z carries `coldWakeDeferralScan: "clean"` beside `coldAlertChannel: "mknoon_messages"`. Understood as **harness-integration evidence, not proof of the Wave-1 fields** — on the clean path no deferral record is emitted, so a stale APK would produce a byte-identical pass. Wave 1 closes at host tier. |

**Two traps this cost real time to find, both caught by adversarial review rather than by a test.**

1. **The record's `outcome` is the enum WIRE name, never the call-site argument.**
   `_recordBackgroundStorageDeferred(outcome: 'post_show_unknown')` maps through
   `BackgroundStorageTerminalOutcome.shownStateUnknown`, whose `wireName` is `shown_state_unknown`. A
   consumer filtering on `post_show_unknown` matches nothing and silently filters nothing. The three
   reachable wire values are `storage_deferred`, `custody_write_pending`, `shown_state_unknown`.
2. **`pending_overlay` records `storage_deferred` and then FALLS THROUGH.** It is the only
   `storage_deferred` site that does not `return` — the encrypted overlay is enrichment, so the card is
   still published. Treating *"a `storage_deferred` record exists"* as *"the alert was lost"* fails runs
   that delivered correctly. The card-killing set is `storage_deferred` + `custody_write_pending`, minus
   `phase == 'pending_overlay'`. Both traps would have turned a correct cold run red.

A third, for anyone timing a deadline behind an injected clock: **a fake monotonic clock cannot tell
phase-ENTRY stamping from phase-EXIT stamping.** `Future.timeout` fires on the REAL timer while the fake
clock only moves when a stubbed resolver moves it, so consecutive phases start and end at the same fake
instant and both designs report identical numbers. The discriminator is to spend time BETWEEN phases —
`_initializeBackgroundNotifications()` runs outside every `.run`, and its MethodChannel `initialize` is a
clean hook. For the same reason `phaseElapsed == bound` is un-assertable with this fixture, and
`budget == phase` is the non-discriminating case.

**G21's severity is no longer N=2.** Plan 386's device run adds a third real-device sample and the first
on a post-`f1b568bca` build (emulator, 2026-08-19, deferral at +2.388s, `elapsedBucket=2s_to_8s`,
`kind=group_reaction`), and Plan 388's own run adds a fourth datapoint of the opposite sign: an emulator
warm-install first wake that did **not** defer. Direction of travel unresolved — that comparison is
cross-device, since Plan 383's two samples are Pixel.

**What Plan 388 deliberately did NOT close.** G21 itself (the alert is still lost; alerting is deferred to
the dropped-push-recovery activation wave, GAP-N08/WP). The release/profile AOT re-measurement (sims builds
debug only, the E2E poller is `kDebugMode`-gated, and the state guard restores the APK). The kind sweep to
1:1 text, 1:1 reaction and group text. And **Wave 3 (TC-388-13) was not run at all**: Plan 386's device legs
were still open at the time, and both plans' rules said Wave 3 waits — its first scenario,
`android_announcement_reaction_recipient`, was blocked by G21 itself. **That dependency no longer fires: [Plan 389](../Test-Flight-Improv/389-reaction-lane-post-kill-warmup-and-group-scoped-cards-tdd-plan.md) closed both reaction scenarios on device 2026-08-19 (§4.10) and the campaign is 5 of 5, so Wave 3 is UNBLOCKED.** One plan-fix for whoever resumes it:
TC-388-13's gate command covers only half its own row, because the Plan-330 media-target reactions live in
`groups.notification_projection_durability`, not `groups.reaction_notification_campaign`, and are therefore
independently runnable rather than stuck behind that campaign's fail-fast.

### 4.10 Closed by Plan 389 (device tier, 2026-08-19) — the two reaction scenarios G21 was blocking

[Plan 389](../Test-Flight-Improv/389-reaction-lane-post-kill-warmup-and-group-scoped-cards-tdd-plan.md)
EXECUTED and closed at device tier. **`groups.reaction_notification_campaign` is PASS, `assertions=5`
— 5 of 5.** This closes G21's CONSEQUENCE, not G21 itself: the deadline exit at
`background_message_handler.dart:681-693` was untouched by that plan and G21 remained open then;
Plan 393 later closed it (§4.14). What Plan 389 closed is that the reaction lane no longer puts a graded push in the un-gradeable
first-wake slot. Plan 386's residual (TC-386-11 at 3/5) is now 5/5, and Plan 388's Wave 3 is
unblocked.

| Gap | What was blocking | Fix | Evidence |
|---|---|---|---|
| **G21's blocking half — `android_group_reaction_recipient` and `android_announcement_reaction_recipient`** | The killed recipient's FIRST FCM wake IS the graded one. It exhausts the 2s `display_eligibility` budget on cold background-isolate warm-up and exits at `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of every show lane, so no card is posted and the lane grades nothing. The lane could not simply send a warm-up first, because its own graded assertions forbade the only warm-up it could send: `_waitForNotificationCard()` requires exactly ONE active record across the whole app package — and returns `null` rather than failing, so a second card makes it HANG for two minutes rather than red; `_validateNotificationRaw` rejects any evidence block that does not hold exactly one content card; and `_validateUiRaw` scans every UI block for the bare substring `'unread message'` with no group qualifier. | A post-kill throwaway **TEXT** into a **SECOND** group, created in `group_fixture_setup` — both groups must exist before the kill, because for these two ids `_createAndAcceptGroup` picks the RECIPIENT as creator and immediately launches it. Gated on `_waitForBackgroundPushWakes(1)` → `_waitForRecipientStorageWarm()` (`GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS`) → a 15s settle, never on the warm-up's own disposition. A text and not a reaction, because `relay_group_reaction_wake_total` is the exact counter this lane grades a delta on. Four graded assertions widened to a **CLOSED allow-list of {graded group, warm-up group}** under an explicit `messageScenario` selector, the unread scan replaced by one whole-label regex `Open group <graded>, \d+ unread message`, and the two reaction card waits made group-scoped (the message lane's two deliberately untouched). The warm-up group's name is DERIVED from the graded name by digest — `$.measurements` is exact-keyed, so a new measurement key would reject every artifact this lane has ever written. **ZERO `lib/` change, no new file, no new scenario id, measurement key or evidence kind.** | **DEVICE.** Both scenarios validate standalone and the full campaign is PASS, `assertions=5`. In both runs all **three** post-kill wakes were served by **one resident background isolate pid** (11332 and 17297), with **zero** `PUSH_BACKGROUND_STORAGE_DEFERRED` in the graded window — the same-pid result is what makes this the mechanism rather than luck. Warm-up → replacement card measured **61.1s** and **81.2s**, inside the 57–114s residency the muted captures had shown. A new `>= 3` post-kill wake floor on `recipient_app` machine-enforces the warm-up; **two** is exactly what the lane emitted WITHOUT one (ADD + re-ADD), so a ported `>= 2` rule would have been vacuous. The rule is cardinal, not identity-bound: the reaction push's flow event carries `{'kind': 'group_reaction'}` and no message id. |
| **G11's blocking half for those same two ids** | The suffix dispatch also carried the package-wide card rule and the bare-substring unread scan, which is what made a warm-up unrepresentable for the two catalog reaction scenarios. | Group-scoping under an explicit `messageScenario` selector, **not** the suffix refactor — which stays open and unowned in §4.14, censused at 18 live sites across 5 files. Second precedent, after Plan 379's out-of-catalog modelling, that a lane with different card/unread semantics can be expressed without redesigning the classifier. | **HOST + DEVICE.** 55/55 host rows; **6 causal REDs** recorded against HEAD in a git worktree (never a mutation-revert in the live checkout), including one confirming the reviewer's finding that `reaction title/body mismatch` never evaluates at HEAD because the count check `continue`s first, and one where an artifact with ZERO post-kill wakes validates; **7/7 mutations re-red**, each by exactly one row. On device, **both message lanes still pass**, which proves the selector preserved the package-wide contract at device tier and not merely against host fixtures — and the background-connected reaction, which gets NO warm-up, still validates, so the widening did not quietly become the only path that works. |

**Two device-only findings, each of which cost a full run and neither of which the plan predicted.**

1. **Orbit's all-chats filter EXCLUDES active group rows.** Accepting a group invite lands Orbit on
   the `Intros` filter; the create-group FAB stays mounted there but group nodes do not render. With
   one group the lane never noticed. The SECOND accept leaves the device on that filter, so
   `findSemanticNodeCenter(dump, 'Open group <name>')` returns null and the run died at
   `orbit_surface_not_reached_on_emulator-5554` — before the kill, before the warm-up sent anything.
   Fixed by routing the lane's five navigation sites through
   `findPlan330OrbitGroupWithInnerCircleRecovery`, which the muted and Plan-330 lanes already use,
   and only when a warm-up group exists.
2. **A warm-up group that inherits `scenario.groupType` is admin-only in the announcement lane.**
   `_createAndAcceptGroup` derived the type from the scenario, so the announcement scenario's warm-up
   group was an announcement group — and its admin is the creator, which for a reaction scenario is
   the RECIPIENT, the device this lane deliberately kills. The surviving sender had no composer:
   `group_compose_marker_editorUnavailable_on_emulator-5554`, with the UI showing *"Only admins can
   send messages in this group"*. **That is correct product behaviour, not a membership defect** — the
   join row still renders and the member can read. `_createAndAcceptGroup` now takes an explicit
   `groupType`, and a throwaway warm-up group is always `'chat'`.

**One unplanned repin.** `scripts/test/group_reaction_notification_device_contract_test.sh:169` pins
the capture driver's `logcat -c` site count; the post-kill clear makes nine. Repinned 8 → 9 with the
reason, never weakened.

**What Plan 389 deliberately did NOT close.** G21 itself — the deadline still defers and the alert is
still lost when it trips; alerting stays with the dropped-push-recovery activation wave (§4.14). Note
that both of this plan's runs recorded ZERO deferrals, which is a datapoint about the trip being
intermittent, not evidence of a fix. G11's structural suffix dispatch (18 sites, unowned). A 1:1
warm-up helper — none exists in the 6492-line capture driver. And the iOS legs (GAP-N12).

### 4.11 Closed by Plan 390 (2026-08-19) — G15, the harnesses that could not reach the Go bridge

[Plan 390](../Test-Flight-Improv/390-android-bridge-harness-runtime-lease-tdd-plan.md) —
EXECUTED, host census plus one device leg with its mutation re-red.

**The row this replaces was wrong four ways, and the fix it prescribed would have made things
worse.** `f1b568bca` is dated **4 Aug 2026**, not 08-17. `wifi_relay_fallback_smoke_test` and
`background_reconnect_test` were named as broken when the same commit had already leased them,
alongside `transport_e2e_test`. The reusable seam is `_support/canonical_runtime_device_test_lease.dart`,
not `ensureCanonicalRuntimeAttachedForTest()` — and calling that function from a harness that
already holds a lease is precisely the defect below. "~20 harnesses" counted construction sites;
only 16 were unleased, and they map to **15 entrypoints**, because a file with no `main()` cannot
repair itself.

| Fragment | What was wrong | What closed it |
|---|---|---|
| **G15-a — the model harness was itself double-leasing** | `group_multi_device_real_harness.dart` took the lease in `main()` under `group-multi-device-real-<role>` and then `setupGroupMultiDeviceStack` acquired again under the fixed `v1:0000…`. Same ownerId and role, different binding, so the broker's identical-triple branch misses, state is ACTIVE not RELEASED, it returns null, Kotlin answers `lease_unavailable`, and `MethodChannelCanonicalRuntimeLeaseGateway.acquire` does not catch the `PlatformException` — setup died before the first bridge call on the three runners that target that `main()` directly. Introduced `90bc7d601`, one day old. | Wave 0: the shared joiner reads `status()` first and acquires only when nothing owns the runtime. No `lib/` change — `status()` was already on the gateway. |
| **G15-b — 15 entrypoints reached the bridge with no lease at all** | 13 of them are run by a real command (a dispatched gate, an `active` sims capability, the reliability-sim runner set, or a script that `flutter test`s them). Nothing had failed only because nothing had run them: there is no CI in this repo, so every gate is a human-issued command. | Wave 2: all 15 leased. 13 take the `setUpAll`/`tearDownAll` seam with a per-harness binding; two self-guard, because a `runApp` APK target and a shared sims dispatcher cannot use it. |
| **G15-c — nothing could catch the next one** | No test, no `scripts/test/*.sh` contract and no `tool/` check failed when a harness constructed `GoBridgeClient()` without a lease. | Wave 1: `test/integration/android_bridge_runtime_lease_census_test.dart`, host-all-only, 7 cases. Empty allow-list, cross-checked against the executed list so it cannot be made green by exemption. |

**Device proof.** `flutter test -d emulator-5554 integration_test/group_real_crypto_onboarding_test.dart`
— real Gradle `assembleDebug`, real install, `GO_BRIDGE_INIT_SUCCESS` with `"type":"native"`, and
successful bridge calls for `identity.generate`, `mlkem.keygen`, `node:start`, `group:create`,
`group:updateConfig`, `payload.sign`, `message.encrypt`, `message.decrypt`. 4/4 passed. Reverting
only that harness's lease and re-running on the same emulator gives four
`GO_BRIDGE_MISSING_PLUGIN` on `com.mknoon/go_bridge` and 0/4.

**Three traps worth keeping.**

1. **`GO_BRIDGE_INIT_SUCCESS type:native` fires even when the bridge is completely unreachable.**
   `initialize()` only subscribes to the EventChannel, whose `MissingPluginException` lands
   asynchronously, and both `invokeMethod` sites share one `on MissingPluginException` catch that
   returns `ok:false`. There is no init-time signal. The only honest oracle is the run's own
   pass/fail — a log line will lie to you here.
2. **"Every harness needs a lease" is the wrong invariant.** The right one is *exactly one acquire,
   with one binding, per runtime path*. Seven harnesses reach the bridge only through
   `setupGroupMultiDeviceStack`, which takes the lease next to the construction; adding a lease to
   them would have recreated G15-a seven times.
3. **A pairing check on bare `.acquire` / `.release` tokens is a trap.**
   `group_multi_device_real_harness.dart` alone carries an unrelated `traceLease.release()` and the
   joiner's own `gateway.acquire`. Bind the count to the owner's variable.

**What Plan 390 deliberately did NOT close.** `lib/smoke_test_main.dart` and
`lib/smoke_test_restore.dart` are manual `flutter run -t` roots with no automated executor, and are
hash-pinned by `dtr13_profile_entrypoint_preservation_contract_test.sh:202-241`; running either by
hand on Android still hits this defect. The other 14 repaired entrypoints are covered by the census
plus the one representative device proof, not individually device-run. And the census remains a
regression tripwire, not a proof: it cannot see a lease reference in dead code or a comment, and it
is deliberately blind to dispatch-conditional reachability.

### 4.12 Closed and revalidated by Plan 391 (device tier, 2026-08-20) — G22(a), the killed-path 1:1 reaction, and the durable-arm residual it left (G29, device tier, same day)

[Plan 391](../Test-Flight-Improv/391-killed-path-1to1-reaction-device-proof-tdd-plan.md) —
EXECUTED, 4 causal host rows + 3 sentinels + one device leg, 8 of 8 mutations re-red. Final
independent revalidation landed in `e588fe7ce` against the harness snapshot `5f4df8c0a`; it forced a
new capture rather than accepting the older `50898bf8e` artifact.

**The vehicle already existed and had never once run end to end.**
`capture_1to1_reaction_head_provenance.dart` already terminates the recipient on the COMMON path
(`:357`, no conditional, ending in `_waitForProcessAndActivityAbsent`), drives a real reaction from
the sender by uiautomator and grades the killed device's dump. What was missing was a way to select
it and an oracle that still worked. Three of the six fragments below are the same defect wearing
different clothes: **a live wait grepping a string its producer stopped emitting.** Two of those
strings are relay lines `8d86501e4` (v1.8.0) deleted — the removal Plan 368 pins deliberately — and
the third is a pinned host expectation that had never been run against a device.

| Fragment | What was wrong | What closed it |
|---|---|---|
| **G22a-a — the card-asserting variant was unreachable** | The driver derives its scenario from FLAGS, not `--scenario` (a census of `--scenario` over the file returns zero). The runner forwarded six options and not `--live-typed-smoke`, and its 5-entry catalog had no `android_typed_reaction_smoke`. The reachable default TOLERATES zero cards — `:422-428` throws only when `providerMatchedEvent && cards.length != 1` and `:429-435` only when `!providerMatchedEvent && cards.isNotEmpty`, so zero cards with no matched send falls through both. **A TC-00 pass was never evidence that any card was posted.** | Catalog row + the `switch` case naming its capture driver + `--live-typed-smoke` forwarded for that scenario only. All three links are load-bearing: a catalog-only edit still exits **78 ENVIRONMENT BLOCKED**, and `--list-scenarios` returns before both, so it proves catalog membership ONLY. |
| **G22a-b — the artifact could not prove its own premise** | The `observation` map recorded card, producer, lifecycle, tap route and copy — and **no recipient process state**. The killed-path claim was unfalsifiable from the evidence the lane wrote. | A MEASURED bool taken inside the `reaction_capture` stage, immediately before the reaction is driven, recorded as `observation.recipientProcessAbsentBeforeReaction`. Non-throwing on purpose (`_recipientProcessAndActivityAbsentWithin`): that stage is shared with TC-00, which must gain no new failure mode. Absence at KILL time was already established and asserting it again would be vacuous. |
| **G22a-c — the runner aborted after a successful capture** | `_validateArtifacts` shells `flutter test … --plain-name <scenario.id>` after every capture, against a file declaring exactly one test per catalog id. A sixth id with no test matches nothing and exits **79** — after a fully successful device run. A stem/id mismatch (`live_typed_reaction_smoke` vs `android_typed_reaction_smoke`) additionally made `_artifactFor` exit **66** `Missing artifact:` against a FLAT write. | Every capture branch's stem now equals its scenario id, and the sixth test exists and is the evidence oracle: it asserts the card, the measured absence, the typed copy and the attribution together. |
| **G22a-d — the token-registration wait grepped a deleted relay line** | `[PUSH] Token registered for <peerPrefix> (android)`. **Measured 2026-08-20:** the recipient logged `[PUSH_DIAG] relay_push_registration_success platform=android` at 07:49:06Z and the capture still failed at 07:51:12Z with `Timed out waiting for recipient FCM token registration`. This blocked EVERY Android capture on the lane. | Attributed on the recipient device's own log via the already-host-tested `androidRelayPushRegistrationAccepted` — the move `capture_group_reaction_notification_device.dart` had already made. Better attribution too: the log is unambiguously that device's rather than a 20-char peer prefix. The `directTextOnly` arm keeps the relay-journal wait on purpose and is therefore still dead; that lane owns it. |
| **G22a-e — provider attribution grepped a deleted relay line** | `classifyRelayCapture` derives `providerMatchedEvent` from `[PUSH] (Group )?Notification sent to <recipientPrefix>`; a recursive census of `Notification sent to` over `go-relay-server/` returns **ZERO**. So the typed smoke threw whether or not the card was posted (`:429-435` when it was, `:436-441` when it was not) — **TC-391-09 was unpassable on any build** — and `providerConfirmedNoSend` (`relayMatchedEvent && !providerMatchedEvent && !providerFailureMatched`) made **every TC-00 capture write a false `providerConfirmedNoSend: true`**. | Attributed on the recipient device: `androidDirectReactionBackgroundPushObserved` accepts only `PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK` with `details.kind == 'reaction'` (`background_message_handler.dart:2870`), which fires only after the background isolate decrypted a reaction addressed to that recipient with that recipient's own ML-KEM secret. It rejects `kind: 'group_reaction'` (`:2831`) and a bare `PUSH_BACKGROUND_MESSAGE_RECEIVED`. The recipient's logcat is cleared inside the reaction window so a stale marker cannot satisfy a capture, and the artifact names its source (`providerEvidenceSource`, `recipientBackgroundPushObserved`, `providerEvidencePath`). Plan 386 W1's rejected option is still rejected: the surviving `[PUSH] outcome=success` line carries no attribution at all. |
| **G22a-f — returning to Orbit started a SECOND Flutter engine** | `_reopenRecipientAtOrbit` relaunched with `NEW_TASK\|CLEAR_TASK` (`0x10008000`). CLEAR_TASK destroys the activity while the process keeps living, so a second engine starts in a process whose FIRST engine still owns the canonical Go runtime and the SQLCipher handle. **Device-measured:** `GO_BRIDGE_PLATFORM_ERROR … 'This Flutter engine does not own the active Go runtime'`, `DatabaseException(database_closed)`, `FlutterGeolocator: There is still another flutter engine connected`, and a **BLACK SCREEN** whose entire UI dump was one node with an empty `content-desc` — so the unread wait could never observe anything and timed out. | Resume the task instead of clearing it, then walk back to Orbit and VERIFY with `extractOrbitUnreadCount` rather than assuming. A clean single-engine launch of the same build renders Orbit with `Open chat with Bob` and no unread suffix, proving the count really was 0 and the tap had committed the read. The host sentinel that pinned `0x10008000` was written from reasoning and had never been device-run; it now pins the resume, with that evidence beside it, and keeps both of its real prohibitions. |

**Final device proof.** `dart run integration_test/scripts/run_1to1_reaction_notification_device.dart
--scenario android_typed_reaction_smoke --sender 21071FDF600CSC --recipient emulator-5554` →
**exit 0**, which means the capture passed AND the runner's own `_validateArtifacts` validated the
artifact it had just written. `android_typed_reaction_smoke.json` @ `5f4df8c0a`, relay v1.9.0:
`observation.cardPresent: true`, `observation.recipientProcessAbsentBeforeReaction: true`,
`observation.recipientProcessAliveBeforeReaction: false`,
title `Bob`, body `Reacted 👍 to your message`, `tapRoute: conversation`,
`sourceAttribution.providerEvidenceSource: recipient_background_push`, and
`unreadLifecycle.unreadCounts [0,1,1,2,0]`. Revalidation gates: support **122/122**,
Graphify-affected neighbors **149/149**, payload-campaign sentinel **22/22**, `groups` **4596/4596**
plus the Go bridge/relay gates, `completeness-check` **1469/1469**, focused analysis clean, and a
fresh Graphify review fingerprint `0c3e874a47628f55`. Zero `lib/` diff.

**What this leg does NOT prove — durable authority, not G21.** The graded push produced its card through the
**non-durable fallback**, not the durable arm. Both device runs logged, in order:
`PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK kind=reaction` →
`PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED reason=exact_sql_authority_unavailable
presentation=nondurable_fallback` → `PUSH_BACKGROUND_DIRECT_POST_SHOW_UNKNOWN
errorType=SqfliteDatabaseException` → `PUSH_BACKGROUND_NOTIFICATION_SHOWN silent=false`. So G22(a)'s
user-visible behaviour is device-proven — a killed 1:1 recipient IS alerted, with typed copy, and
the tap routes — while the `directReaction` arm of the durable resolver, which this plan's Proof
Profile named as the boundary under test, **did not execute**. Per the plan's hard `Do not`, no
warm-up push, deferral scan or classifier was added to this lane. **That residual — "the durable 1:1
reaction arm remains device-unproven" — is discharged below, and the answer is not the one the
sentence expected: the arm is not unproven, it is UNREACHABLE, and no warm-up could have changed
that.**

**Three traps worth keeping.**

1. **A never-executed device lane is a list of unverified oracles, not a working lane.** Three of
   this lane's waits named strings their producers had stopped emitting, and each was found only by
   running it. Budget for that shape rather than for one fix.
2. **Check which arm a passing card came from.** The lane goes green on a card the fallback posted.
   Without reading the flow events beside it you would record the durable arm as proven.
3. **A second Flutter engine in one process fails silently and completely.** Live process, resumed
   activity, no crash, nothing above warning level — and a UI dump of one empty node. This is the
   `f1b568bca` one-owner-per-runtime invariant on a PRODUCT path; Plan 390 (§4.11) closed the
   harness side. It is not shown to be user-reachable — a launcher tap resumes a task rather than
   clearing it — but anything that recreates the activity without killing the process lands here.

#### 4.12a — G29, the durable-arm residual, discharged on device 2026-08-20

Follow-on work, **no plan number** — a scoped device investigation of the one thing §4.12 recorded as
unproven, not part of Plan 391's own execution. Files touched: the two 1:1 reaction scripts, their
shared support library, the proof test and its host suite. Zero `lib/` diff.

**What closed is the EVIDENCE OBLIGATION, not the behaviour.** The durable arm still does not run.
It is now measured, explained, and guarded by a probe, so it is no longer an unverified gap — which
is the only thing §4.14 tracks. The product decision it leaves is named at the end of this block.

**The question Plan 391 left.** Its Proof Profile named the `directReaction` arm of the background
durable-effect resolver as the boundary under test, and that arm did not execute. The map recorded
the caveat against G21, i.e. as a first-wake timing failure a warm-up would fix.

**Both halves of that reading were wrong, and the source says so.**

- **It is not G21.** `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED{reason: exact_sql_authority_unavailable}`
  is the authority-null fall-through at `background_message_handler.dart:1098-1109` — G17's own
  designed exit, taken when `_resolveBackgroundSqlEffectAuthority` returns null. G21's deadline emits
  a different event, `PUSH_BACKGROUND_STORAGE_DEFERRED{outcome: storage_deferred}` at `:681-693`,
  after a 2 s budget. Neither Plan 391 run logged one. G21's row is corrected accordingly, and its
  kind sweep is open again for 1:1 text, 1:1 reaction and group text.
- **A warm-up cannot fix it.** Warming storage does not create a row. The arm resolves an EXACT
  display-outbox row that must already be `isReady` when the push is handled (`:2129-2154` direct,
  `:2170-2180` group). **Only the live app runtime writes those rows** — census over `lib/` for
  `dbStageDirectNotificationDisplayOutboxEntry` / `dbPromoteDirectNotificationDisplayOutboxReadyIfExact`
  returns three call sites: `production_application_bootstrap.dart:1030`/`:1046`,
  `production_canonical_inbox_projection_composition.dart:1915`/`:1930`, and the
  `android_headless_recovery_374_fixture.dart` DEBUG fixture. The background handler only ever calls
  `dbLoad…`. Its own comment at `:1080-1087` states the consequence: *"A killed app has no staged
  display-outbox row for a genuinely new event (only the foreground runtime writes those)."*

**So the killed path was never the variable.** The probe below keeps the recipient ALIVE and
backgrounded — the only state where the arm can execute — and the arm still deferred.

| | Measured |
|---|---|
| **1:1 reaction, alive + backgrounded** (`android_durable_reaction_background_connected`, emulator recipient, 2026-08-20) | push `11:02:15.932` → deferral `11:02:16.288` → fallback card `11:02:16.365` → **`MSG_RECEIVED_TRANSPORT` `11:02:18.193`** → `REACTION_RECEIVE_STORED` `11:02:18.282`. The app's own copy of the event is **1.905 s LATE**, and the whole push-to-card path took **436 ms** on warm storage — no deadline was anywhere near |
| **group reaction, alive + connected** (`android_group_reaction_recipient_background_connected`, Plan 386, 2026-08-19), both graded pushes | push `14:34:06.950` → deferral `14:34:11.373` → `GROUP_REACTION_RECEIVE_STORED` `14:34:17.210` (**5.84 s late**); push `14:34:33.896` → deferral `14:34:36.366` → stored `14:34:43.062` (**6.70 s late**) |
| **1:1 reaction, killed** (Plan 391, above) | structurally impossible — no row is ever staged |

**The mechanism, stated once: the FCM push is what WAKES the transport.** The app's own delivery of
the same event therefore lands *after* the arm has already decided. Reaction rows in particular are
built by `direct_notification_projection_owner.dart:477`/`:496` and promoted by
`promoteReactionReadyIfExact`, both driven by `ReactionListener` on transport delivery
(`production_application_bootstrap.dart:6449-6451`) — which is downstream of the wake.

**The corpus agrees, and it also kills the comparison that motivated this work.** Every
`durable: true` sighting under `docker-ws/` and `build/sims/proofs` — **14 of them** — has the
OPPOSITE ordering: all `direct_message`, all in processes running the FULL foreground app runtime
that had already drained the inbox. `docker-ws/plan380_emu_logcat_run.txt` pid 6130 (1633 lines,
`APP_LIFECYCLE_STATE_CHANGED`, `PRESENCE_SELF_PUBLISH`): `MLKEM_FL_BRIDGE_DECRYPT_RESPONSE`
`02:50:02.758` **before** `PUSH_BACKGROUND_NOTIFICATION_SHOWN{durable:true}` `02:50:03.088`. **Zero
come from a cold wake and none of any kind is a reaction.** So "the message arm resolves while the
reaction arm returns null on the same hardware" is **not a controlled comparison** — the variable is
delivery order, not kind. Do not re-derive it as a reaction-specific SQL bug.

**The instrument.** `android_durable_reaction_background_connected` (`TC-DURABLE-DIRECT-REACTION`) on
`run_1to1_reaction_notification_device.dart`, zero `lib/` diff. It backgrounds the recipient instead
of killing it (`_backgroundRecipient`, HOME then a proven-alive check), records a **measured**
`observation.recipientProcessAliveBeforeReaction`, and refuses to write a passed artifact unless the
recipient's own log carries `PUSH_BACKGROUND_NOTIFICATION_SHOWN{durable:true, producer:direct_reaction,
disposition:osPosted}` with an EMPTY deferral list. **It is RED on device today and that is the
finding, not a broken lane.** Do NOT make it green by asserting the deferral — that pins the defect
as wanted, the mistake this map already warns about for Plan 383's test-locked deadline. Evidence:
`docker-ws/durable_reaction_arm_device_evidence_2026-08-20.txt`; runner wrapper
`docker-ws/run_durable_reaction_leg.sh`.

**Gates.** `reaction_notification_proof_support_test.dart` **122/122** (10 new rows: 5 behavioural
over `androidDurableDirectReactionShow`, 2 over the alive-and-backgrounded predicates, 3 source-slice
over reachability, lifecycle and the measured verdict). Four mutations applied together → exactly
four reds, one per mutation, then green again. The proof-test oracle discriminates against real
fixtures: it passes the durable shape and fails the deferred/fallback shape. Preservation: Plan 391's
typed smoke passes against its **real** captured artifact, TC-00 keeps its zero-card tolerance, the
payload-campaign tripwire is 22/22, the four graph-named dependents 144/144, `completeness-check`
1469/1469, `flutter analyze` clean. `groups` exited 1 on **one** test of 4594 —
`background_storage_deadline_test.dart` `one deferral must write one record` — which passes in
isolation (18/18) and at lane concurrency across all of `test/features/push/` (553/553), and which
imports no file this work touched; recorded as a shared-liveness-journal race, **not** a green lane.

**Two traps worth keeping.**

1. **A posted card is not evidence the durable arm ran.** The fallback card is visually identical.
   Any lane asserting only `cardPresent` goes green while the arm never executes — which is exactly
   what happened to Plan 391.
2. **A live recipient rotates its logcat ring in about a minute.** The killed-path legs get away with
   one `logcat -d` because a dead app writes almost nothing. The buffer pulled straight after this
   run reached back only **11 s** before the graded push. Poll and FOLD snapshots
   (`AndroidDurableDirectReactionShow.mergedWith` keeps the per-reason maximum, because rotation only
   drops from the front); never read a single snapshot at the end.

**Residual — a product decision, not an evidence gap, and deliberately not filed as a device gap.**
Should a first-delivery event get durable authority at all? Making it so needs a `lib/` change —
the background isolate minting its own authority, or the dropped-push retry vehicle (`recoveryWorkEnabled`,
default-off and uninjected) activated — and it reverses a deliberate Plan 383 design that chose the
fallback. The alternative is to accept that the arm is correctly scoped to LATE or DUPLICATE pushes
for events the app already holds, in which case this is closed as designed behaviour and the probe
stays as a tripwire. **Owner: unassigned.** The separate defect this run surfaced, the background
isolate closing SQLCipher under the live runtime, was later causally reproduced and closed as **G30** by Plan 393 (§4.14).

### 4.13 Closed by Plan 392 (2026-08-20) — recurring typed reaction plus state-safe Android permission/sound boundaries

[Plan 392](../Test-Flight-Improv/392-android-notification-e2e-recurrence-and-permission-divergence-tdd-plan.md)
was harness-only: zero `lib/`, native, DB, relay or wire changes. It closed the recurring ownership
gap left by Plan 391, made G24 a distinct causal Android row, and removed two false-closure paths:
reusing stale typed-reaction evidence and letting a sound run destroy an installed app baseline.

| Item | Was | Closed by | Verified |
|---|---|---|---|
| **Recurring killed-recipient typed 1:1 reaction** | Plan 391 had one passing standalone device artifact, but no Sims capability owned the selector; the capture built two child APKs, used a reusable directory, and had no aggregate central-build/state-restoration proof | Exactly one appended required/active/automation-ready capability, `notifications.android_typed_reaction_smoke`; a support/runtime-root registered adapter; one unique empty capture per invocation; one central `android.production_fcm` APK on both roles; zero child builds; raw + candidate-build provenance audit; unchanged before/after APK SHA; exact arbitrary Android state restore; one content-addressed Sims result. The shared seven-scenario runner and proof keep their legacy classifications | **DEVICE PASS**, physical `21071FDF600CSC` + emulator `emulator-5554`: final report `build/plan392/typed/report.json`, `assertions=1`, zero actual builds/one cache hit, central APK SHA `d7eff44b4004…` before/after, `childBuildCount=0`, `appStateRestored=true`; aggregate evidence SHA `b509372f8fcc…`, raw capture SHA `fc983b0cef98…`. The Plan-391 oracle re-proved process absent before reaction, typed card/provider attribution, tap route and unread lifecycle |
| **G24 causal row and target classification** | The payload campaign's ordinary G7 revoke row could never distinguish Firebase `authorized` from NotificationManager disabled, and there was no exact app-op probe/restore or G24 artifact contract | A tenth scenario, `tc_g24_permission_appop_divergence`, plus four manifest assertions; closed-domain UID app-op parser; leg-local restore before the recovery control; campaign-entry restore after `AndroidAppStateGuard.restoreAll()`; exact override/result/no-card/custody/recovery criteria; a platform-log discriminator for API images that reject the runtime-backed UID override while returning shell success; and an API-37 `pm path` exit-1/empty-output package-absence parser that still fails shut on transport errors | Host criteria/support/adapter contracts PASS. The retained `build/plan392/payload/report.json` (SHA `7190662e0821…`) reached G24 after the earlier campaign rows and returned `BLOCKED/targetUnavailable`: Android logged `Blocked setUidMode call for runtime permission app op`, so G24 is terminal `N/A (target unavailable by project policy)` on this matrix and the aggregate is deliberately not called PASS. Zero child builds, one central cache hit, no validation errors, and both packages absent after restoration |
| **S1–S16 state ownership** | Flutter child cleanup could uninstall a pre-existing `com.mknoon.app`; its Keystore/data could not then be reconstructed, yet the runner had no fail-before-mutation ownership boundary | Parallel read-only package checks on both targets before snapshot/guard/child; installed baseline → typed `package_installed_before_sound_smoke` `BLOCKED/78`; for an accepted absent baseline, one local `AndroidAppStateGuard` plus exact package/card/channel snapshot and post-restore readback; child cleanup is awaited before restore | Shell contract PASS, including the installed-package negative fixture proving both `pm path` reads and zero child/mutation. The first live command returned `BLOCKED/78` before setup; after the user-authorized exact-package uninstall, the positive run completed and `androidStateBoundary.restorationVerified=true` with identical absent/card/channel hashes before and after |
| **S1–S16 behavior acceptance (G1/G2/G3/G6/G-reg device boundary)** | Plan 378 had byte-pinned and registered all sixteen rows, but no retained post-G9 device campaign had completed | The existing scenario oracle ran unchanged and unfiltered: direct/group/announcement audible rows, 1:1 and group same-chat suppression, media consistency, S14 tone debounce/stable replacement, S15 post-clear control, and S16 backgrounded-but-connected | **DEVICE PASS**, run `1787244621233`: exactly 16/16 rows, all programmatic and OS verdicts true; direct/group/announcement stable IDs 6/6, 4/4, 4/4; both Flutter children passed; retained summary SHA `4fed5a4b72ed…`; exact state restoration completed before exit 0 |

Registration and preservation evidence is green: the three affected shell contracts; 192 focused
Flutter causal/preservation tests; 25 Graphify-adjacent preservation tests; the retained typed
artifact oracle; Sims-manifest and full-inventory contracts; runtime-root inventory
(`trustworthy: true`, `drift: false`); exact major-mode discovery for both capabilities; scoped
analysis; incremental Graphify refresh; and `git diff --check`. No per-plan `host-all` was run.

**Plan-392 residual: none.** The exact uninstall authority supplied during execution resolved the
only live sound precondition without weakening the state contract, and the subsequent run closed
all sixteen rows. G24's API-37 policy-N/A is a terminal availability classification under project
policy, not an item for the still-open table.

### 4.14 Closed by Plan 393 (2026-08-21) — final required Android-led notification closure

[Plan 393](../Test-Flight-Improv/393-android-notification-lifecycle-killed-path-and-recovery-closure-tdd-plan.md)
closed every required Android implementation and device-evidence item assigned to the final
Android-led notification wave. The retained pair was physical Android `21071FDF600CSC` plus
`emulator-5554`; provider delivery used real FCM. The fixed-wake recovery proof used a disposable
instance of the production relay code with ephemeral Redis, not a staging or production deployment.
This is Android mechanism/device closure, not release eligibility or cohort rollout.

| Item | Closed by Plan 393 | Verified |
|---|---|---|
| **N11 lifecycle, read, activation, and final-effect authority** | Direct and group reads now require `resumed` plus the exact non-null tracked conversation; exact route activation and resume-time top-route republication retire only the captured current generation without marking read; compatibility, unanchored group, raw direct/reaction, and nondurable paths reread visibility/canonical authority at the last safe boundary and fail unknown state toward notification. | Positive, negative, race, owner-release, exact-generation, architecture-boundary, criteria, and curated preservation tests passed; strict-device exact-chat suppression also passed. |
| **G21 first-wake eligibility deadline** | A measurement-only profile-AOT receipt exposed the policy-complete eligibility cost and downstream native-entry tail. Production now gives only `display_eligibility` the aggregate remainder minus a fixed 2 s reserve while preserving the 8 s aggregate and every sibling 2 s phase; muted/blocked/archived/removed/wrong-account outcomes still produce no card and no policy-blind fallback. | Measurement artifact SHA-256 `4c427494ed6a…`: 7,995 ms remaining at eligibility start, 172 ms eligibility, 175 ms native-entry tail, selected reserve 2,000 ms, one card. Acceptance artifact SHA-256 `95dbe1af302a…`: one eligible card, no measurement flag/receipt, exact state restore. |
| **G22b killed group-media message** | The existing projection capability gained one killed incoming JPEG leg with an exact full-ciphertext versus `preview_unavailable` relay-branch discriminator; photo/video/voice reaction projection stayed in the same owner. | `groups.notification_projection_durability` passed 6/6; aggregate SHA-256 `434cbab15fc8…`. |
| **G27 strict-authority reaction wake** | Strict direct-inbox custody now reuses signed author-device authority and the existing typed reaction builder to wake only the target author for ADD. Bystander, REMOVE, malformed/tampered, disabled, unauthorized, incapable, and duplicate rows remain silent durable custody; full group fanout is never invoked from the per-recipient seam. | `groups.strict_notification_closure` passed 5/5 for exact-chat suppression, killed strict message, author-targeted reaction, relay provenance, and restoration; aggregate SHA-256 `7db8f1843c8d…`. |
| **G30 post-show SQLCipher ownership** | The exact failure was reproduced before repair: the background post-show validator returned its Future from inside `try/finally`, so `finally` closed the read-only handle before later SQL reads completed. The handler now awaits the validator before closing, reports a closed-domain `keep|read|retire` disposition, and leaves unknown state with staged-ingestion ownership. | Pre-fix diagnostic reproduced `direct_post_show_database_closed` (aggregate SHA-256 `57888647…`); post-fix base-profile typed acceptance passed (aggregate SHA-256 `4b4554d8d4c8…`, raw capture SHA-256 `9b13d00…`) with no `database_closed` path. |
| **Recurring controlled-cohort fixed wake and recovery** | The inert historical 6×2 recovery matrix was assertion-mapped and replaced by one automation-ready physical-sender/emulator-receiver scenario. It proves distinct alive/background and killed direct-reaction transitions, live opaque-route selection, silent reserved generic card, no-Activity WorkManager continuation, canonical settlement/presentation, exact generic retirement, one requested tone, authenticated ephemeral-route removal, zero cards, and local restoration. | `notifications.android_recovery_completion` passed 6/6; report SHA-256 `80f05ac6f5d7…`, aggregate SHA-256 `3fea2988d45c…`, raw evidence SHA-256 `a2a94b61…`; zero taps, zero child builds, zero production ingress injection, and zero MainActivity launches during killed recovery. |
| **Wave preservation and registration** | S4 sound ownership, the Plan 392 typed path, current strict/projection owners, fixed-wake native invariants, runtime/discovery/manifest/proof binding, and the exact TC-393 census remain registered and green. | One official concurrent `host-all` run passed 14,588 Flutter tests with 11 intentional skips, all 16 Go/relay/native tails, and the Plan 374/375/393 Android native suite at 9 classes / 68 methods. |

**Plan-393 required Android residual: none.** The fixed-wake proof is deliberately
availability-bounded and filtered, so it does not claim production activation or release eligibility.

### 4.15 Still open

No required Android implementation or device-evidence item assigned to Plan 393 remains here.

| Remaining boundary | Status | Owner |
|---|---|---|
| **Apple/iOS closure** | Real APNs-to-NSE execution, Apple lifecycle/lock/file-protection states, main-app/NSE ownership, communication presentation, delivered-card/badge cleanup, and muted blank/passive-item behavior remain consolidated GAP-N12 work on available Apple targets. | GAP-N12 / WP-07 |
| **Release and cohort rollout** | The controlled fixed-wake cohort proves the mechanism with real FCM and an isolated production-code relay fixture. Release-mode confirmation, production cohort activation, rollout/rollback telemetry, operations, and final release eligibility remain separate work. | WP-07 / release owner |
| **G23 OEM restrictions** | Xiaomi/Huawei/Samsung/Oppo-specific background managers remain `N/A (target unavailable by project policy)` on the current Pixel + stock-emulator matrix; optional evidence requires an available OEM target. | Optional hardware follow-up |
| **Optional structural/coverage follow-ups** | G11's non-blocking suffix-dispatch cleanup, G18's third-device non-author bystander observation, Android `MessagingStyle`, and exhaustive media/group/flavor combinations are not required Plan-393 closure conditions. Host authority/policy coverage and the representative killed-photo leg remain the retained causal owners. | Optional follow-up |

G28 is intentionally absent: it is an unrelated Docker-runner behavior decision, not a notification
implementation, device-evidence, or release-closure gap.

### 4.16 Defects found and fixed during Plan 378 execution (recorded so they are not re-derived)

| # | Defect | Impact | Status |
|---|---|---|---|
| **G8** | **Orchestrator false green.** `finally { … exit(failed ? 1 : 0) }` swallowed both the abort and its exit code; with zero scenarios every lane was trivially "stable", so `failed` computed false. An aborted 16-scenario run reported **PASS**. | Any harness/setup failure was invisible — the exact "invisible-but-green" class this map exists to catch | **FIXED**: tracks `runCompleted`/`runError`, compares outcome count vs expected, prints `INCOMPLETE: n/16 … (aborted: …)`. Proven: the identical aborted run went exit **0 → 1** |
| **G9** | **Sound-smoke harness died ~1s into `setupGroupMultiDeviceStack` on every Android device.** Root cause: `f1b568bca` ("close Android notification recovery and storage liveness gaps", committed 2026-08-17 10:34) removed `MainActivity`'s eager `GoBridge` construction — the `com.mknoon/go_bridge` Method/EventChannels now register only after Dart acquires the canonical-runtime lease and calls `attachRuntime` (`mknoon/canonical_runtime_lease`), which only production bootstrap did. Every bridge call returned `MISSING_PLUGIN`; `generateNewIdentity` collapsed it into `GenerateIdentityResult.coreLibError` → `StateError` right after the SQLCipher open. Not plan-378, not device state, not Pixel-specific; iOS unaffected (eager `AppDelegate`). | Blocked every device leg of G1/G2/G3/G6; error text invisible (see the debugPrint-throttle note, §5) | **FIXED**: `ensureCanonicalRuntimeAttachedForTest()` in `group_multi_device_real_harness.dart` mirrors the production acquire→attach (Android-only, fixed binding — the Kotlin broker re-returns the token only for an identical owner/binding/role triple, keeping repeat setups idempotent) before bridge construction. Device-proven 2026-08-17: Alice (Pixel `21071FDF600CSC`) reaches `alice_ready` + a 271ms relay send-proof; Bob (emulator-5554) reaches `bob_identity.json` + real-`FlutterNotificationService` rewiring. The full S1–S16 campaign later passed under Plan 392 (§4.13) |
| **G10** | **Group notification lane dead since Plan 371.** Commit `3c7e704e7` (2026-08-16) gated the compat show lane on `_appVisibility != null` (`group_message_listener.dart:3306-3312`); the harness passed only `groupConversationTracker:`, which post-371 is a discarded compat param (`:313-315`). S2/S3/S8–S13 posted **zero** notifications for a day and every gate stayed green. | Plan 378's review recorded the opposite as a "refuted finding"; the refutation was wrong | **FIXED** in the harness. Now guarded: S2/S3 are `audibleStrict`, so a recurrence reds on card count |
| **G13** | `scripts/test/group_reaction_notification_device_contract_test.sh` pinned a 5-row scenario census while the runner emits 6 (Plan 315 added `android_group_reaction_recipient_background_connected` without repinning). It sits inside `sims-contracts`, so that gate could never go green. | pre-existing red, unrelated to Plan 378 | **FIXED** — repinned to the 6 real rows, PASS |
| **G14** | `tool/sims/device_criteria.dart` `_notificationRequirements` is a **10th** registration surface for a payload-campaign scenario; omitting it makes `validateNotificationArtifact` throw `'unknown notification scenario'` at runtime, after the device work is done. It was absent from Plan 378's checklist. | silent late failure | **DOCUMENTED + registered** for `tc_b13`; see §5 |

(iOS legs are deliberately deferred to the consolidated GAP-N12 closure phase per the adopted §9.1 sequencing — not counted as gaps here.)

---

## 5. Maintenance notes
- **Plan 393 supersedes the historical open-status statements for G21, G22b, G27, G30, and controlled-cohort fixed wake below.** Keep their old measurements as provenance, but use §4.14 for current Android closure and §4.15 for the bounded Apple/release/OEM/optional residuals.
- **A posted card is not evidence the DURABLE arm ran, and "the app is alive" does not make it run.** The durable upgrade needs an exact display-outbox row that is already ready when the push is handled, and only the live runtime writes those. On a first delivery the FCM push is what WAKES the transport, so the app's own copy of the event lands **after** the arm has already decided — measured 1.9 s late for a 1:1 reaction and 5.8/6.7 s late for two group reactions, all with the recipient alive and backgrounded (**G29**, §4.12a). The fallback card is visually identical, so any lane that asserts only `cardPresent` will go green while the arm never executes. Assert `PUSH_BACKGROUND_NOTIFICATION_SHOWN{durable:true, producer:…, disposition:osPosted}` and an EMPTY `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` list, never the card alone.
- **`PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` is NOT the G21 storage deadline.** `{reason: exact_sql_authority_unavailable}` is the authority-null fall-through at `background_message_handler.dart:1098-1109` — G17's designed exit, reached in a few hundred milliseconds on warm storage. G21's deadline emits `PUSH_BACKGROUND_STORAGE_DEFERRED{outcome: storage_deferred}` at `:681-693` after a 2 s budget. Counting one as the other overstates G21's severity; it already happened once and was corrected on 2026-08-20.
- **A live recipient rotates its logcat ring in about a minute.** The killed-path legs get away with a single `logcat -d` because a dead app writes almost nothing; an ALIVE recipient on the emulator fills the 2 MiB ring fast — the buffer pulled right after the 2026-08-20 durable run reached back only 11 s before the graded push. Poll and FOLD snapshots (`AndroidDurableDirectReactionShow.mergedWith`, which keeps the per-reason maximum because rotation only drops from the front), never read one snapshot at the end.

- **The disposition contract is now the pinned version of §1.3.** `dart integration_test/scripts/run_notification_sound_smoke.dart --print-disposition-contract` is byte-compared by `scripts/test/notification_sound_disposition_contract_test.sh` under `./scripts/run_test_gates.sh sims-contracts`. Prefer linking it over duplicating it here; if §1.3 and the contract disagree, the contract wins.
- **Adding a sound-smoke scenario:** it must be a literal `_runScenario(id: 'Sn', … description: '…')` block (the discovery awk sees only single-line quoted literals closed by a whitespace-only `)`/`),`/`);` line); its description must contain `1:1`/`conversation` for the 1to1 family or `group` for the group family and **never both** (the filter lowercases, and a row matching both families would break the 16-row census); and it must be added to `_dispositionContract` — from which `_allScenarioIds` and `laneFor` are now derived, so those no longer drift independently. Suppressed dispositions are excluded from `laneFor` on purpose: they post no record, and counting them would make their own lane look unstable.
- **Adding a payload-campaign scenario: 10 surfaces, not 9.** Catalog `_Scenario`; `_androidPayloadCampaignIds`; **`tool/sims/device_criteria.dart` `_notificationRequirements`** (G14 — omit it and `validateNotificationArtifact` throws at runtime); the checks const; the leg + `_writeScenarioArtifact`; the `_assertionsAttempted` ladder **and both terminal literals**; `_removeScenarioArtifacts`; `critical_features.json` assertions; the adapter contract sh expectation (ordered by `_scenarios` declaration order); and the source-slice freezes in `test/integration/android_notification_payload_campaign_support_test.dart` + the adapter sh's inline `python3` heredoc — **nothing may be inserted inside those windows**.
- **Run `scripts/test/*_test.sh` via `/claude-host-bin/host-run`.** Several build a fake `adb`/`ssh` in `$(mktemp -d)` and prepend it to `PATH`; container `/tmp` is invisible to the host-bridged `dart`/`flutter`, so they fail spuriously in-container. Only a host-run red is a real red.
- **Landmines for future device runs:** `flutter test -d` on the physical phone destroys a stamped release install (restore from the state-guard backup) — and both the Pixel and the emulator currently hold **debug test builds** from the 2026-08-17 G9 diagnosis runs, so re-deploy the stamped build before any release-build evidence run; the Pixel's secure keyguard blocks uiautomator legs while locked; campaign artifact lists (`_removeScenarioArtifacts`) must include any new scenario ID or a failed run leaves stale "evidence".
- **Android bridge harnesses must hold the canonical-runtime lease before first bridge use — exactly one owner per runtime path** (G9 and G15 both fixed; G15 by Plan 390, §4.11). A `MISSING_PLUGIN` or bare `coreLibError` ~1s into setup is this, not a stale build. The seam for a new harness is `_support/canonical_runtime_device_test_lease.dart` with a per-harness binding and the full `setUpAll(acquire)`/`tearDownAll(release)` pair — **not** `ensureCanonicalRuntimeAttachedForTest()`, which is the group harness's internal joiner. Anything reaching `setupGroupMultiDeviceStack` is already covered and must NOT add a second lease: two owners with different bindings is rejected by the broker and kills setup. `test/integration/android_bridge_runtime_lease_census_test.dart` enforces both halves.
- **A blank device-test failure is a debugPrint-throttle artifact, not a missing exception.** The test framework's failure dump and all FL-layer `[FLOW]` events go through `debugPrint` (~12KB/s throttle); a fresh-DB migration flood saturates the queue and `flutter test` kills the process ~1s after a failure, so the text dies unflushed — absent from stdout **and** logcat. `print()` is not throttled. The sound-smoke harness `main()` now mirrors `reportTestException` through `print()`; copy that pattern into any harness whose failure comes up blank.
- **Cheap hardening, unowned:** `generateNewIdentity` discards the bridge `errorCode`/`errorMessage` into a throttled `[FLOW]` event and returns bare `coreLibError`; surfacing them in the returned/thrown value would have made G9 a five-minute diagnosis.
- **Never relaunch an Android app under test with `FLAG_ACTIVITY_CLEAR_TASK`.** It destroys the activity while the process keeps living, so a SECOND Flutter engine starts in a process whose first engine still owns the canonical Go runtime and the SQLCipher handle. The result is a BLACK SCREEN with no crash and nothing above warning level — the whole UI dump is one node with an empty `content-desc`, so every semantic wait times out for a reason unrelated to what you are testing. Look for `GO_BRIDGE_PLATFORM_ERROR 'This Flutter engine does not own the active Go runtime'` and `DatabaseException(database_closed)`. Resume the task instead and walk back with `KEYCODE_BACK`, verifying the surface you landed on (G22a-f, §4.12).
- **Do not trust a green from an orchestrator that reports zero scenarios.** G8 was exactly that. The summary JSON's scenario count is the thing to check, not the exit code alone.
- **The first post-kill FCM wake is gradeable after Plan 393, but it still needs the G21-aware oracle.** `display_eligibility` alone may use the 8 s aggregate remainder minus the fixed 2 s downstream reserve; every sibling phase keeps its 2 s cap and the aggregate remains 8 s. A first-wake test must distinguish eligible card, policy suppression, and typed storage deferral rather than assuming card presence. Historical Plan 379/384/389 warm-up choreography remains valid for those frozen campaigns, but it is no longer a product workaround required by the current handler. The background isolate remains read-only, so poll the foreground/headless canonical drain for the reaction row rather than trusting a single-shot SQL probe.
- **Adding a SECOND group to a device lane trips two things, and only a real run finds them** (both measured 2026-08-19, Plan 389, §4.10). (a) Accepting a group invite lands Orbit on the all-chats `Intros` filter, which **excludes active group rows** — so `findSemanticNodeCenter(dump, 'Open group <name>')` returns null and `_ensureOrbit` dies at `orbit_surface_not_reached_on_<device>` before anything under test happens. Navigate with `findPlan330OrbitGroupWithInnerCircleRecovery` instead, which taps "Show inner circle" first. (b) A helper that derives group type from the scenario makes the warm-up group an **announcement** group in an announcement lane; its admin is the creator, which for a reaction scenario is the recipient the lane kills, leaving the surviving device with no composer (`group_compose_marker_editorUnavailable_on_<device>`). That is the admin-only posting rule, NOT a membership defect — the join row still renders. Pin a throwaway warm-up group to `'chat'`.
- **A warm-up must not move a counter the lane grades.** The reaction lane grades an EXACT `relay_group_reaction_wake_total` delta, so its warm-up has to be a TEXT. And prove the warm-up actually happened with a wake-COUNT floor over `recipient_app`, not by asserting the deferral returns when you remove it: the trip is intermittent — four cold first-wakes on the pinned Pixel did not trip it, and neither did either of Plan 389's passing runs.
- **Never build a device wait on a count delta over `adb logcat -d`; bind it to an identity.** The ring rotates (~4 minutes on the physical recipient under campaign load), so a `count(event) > baseline` predicate can be structurally unsatisfiable while the awaited thing happens on time — this cost a full campaign run on 2026-08-18 (`docker-ws/plan379_run11_rotation_evidence.txt`). Bind to the message id the sender published (`GROUP_SEND_MSG_USE_CASE_SUCCESS.messageId`), which the recipient reuses verbatim because incoming group messages store under the envelope's `stableMessageId`; accept `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with a non-empty `existingLocalRowId` as equivalent evidence. Fold every read into a monotonic accumulator so a lane's view only grows. The catalog lanes still do NOT do this — that is G20.
- **`groupIdentityCount` is NOT the number of groups, and a count that exceeds the length of `groupConversationIdSha256` is CORRECT** (checked 2026-08-18 and refuted as a defect, recorded so it is not re-raised on the next campaign run): the count counts unread group MESSAGE rows while the id list is an explicitly deduped set of their conversation ids (`group_reaction_e2e_probe.dart` `.toSet()`). Plan 379 runs 14/15 show count 2 with one listed id because the unmuted control group holds two unread rows; the listed sha byte-equals `controlGroupIdSha256` in every run.
- **Do not re-litigate closed product decisions** when extending tests: same-chat cue = none (OQ-01), read/unread/badge/cleanup are installation-local (OQ-04), mute is per-group installation-local only (OQ-05).
