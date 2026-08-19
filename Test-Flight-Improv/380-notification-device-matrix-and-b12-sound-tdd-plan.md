# 380 - Notification Device Matrix (PRD §13) And b12 Sound Assertions (G7 + G12)

Status: **Device tier CLOSED (run 7, 2026-08-19, 9 of 9, exit 0)** — the second clean full run, and this one after the leg-6 flake had a MEASURED cause removed rather than a lucky pass. **G12 closed** (b12 warm/cold audible-channel evidence). **G7 closed** for Doze, permission denied, channel disabled and mid-session token refresh; OEM stays a typed N/A (carved out as G23 in the PRD map). TWO caveats that are deliberately NOT closure blockers but must not be forgotten: (1) `tc_g7_permission_denied` does NOT exercise Plan 385's NM override on this image — firebase_messaging answered `status=denied` honestly 3x with ZERO `PUSH_PERMISSION_OS_STATE_OVERRIDE` events, so the leg proves the coordinator's denied branch, not the 385 fix (F15); (2) the silent-channel leak did NOT reproduce in run 7, so it is INTERMITTENT, not fixed (F16).
Type: Modification
Spec: free-text intent (no formal spec) — closes gaps **G12** and the closable part of **G7** from the [UI-23 E2E map](../UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md) §4.2; PRD clauses at `Mknoon_Private_Reliable_Notifications_PRD_v1.2.md:411` (Android device cases), `:277` (expedited WorkManager + generic fallback), `:390` (AC-04), `:396` (AC-10)
Classification: evidence-gated
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-17 | Evidence Collector + Planner (wf_4471f5b3-082) | campaign runner/support, catalog, device_criteria, freeze/contract shells, push coordinator, FCM service Kotlin, payload-e2e probe, PRD §13 | G12 = extend existing b12 legs; G7 = 4 new legs + OEM typed N/A; token-refresh premise corrected | Emit Test Contract |
| 2026-08-17 | /tdd-review (wf_fcc39e38-17d; lead re-verified every blocker linchpin in source) | support `:115-128,:299-318`, runner `:228-244,:574-578,:700-701`, device_criteria `:596-616`, lease `:994-1006`, guard, fingerprint freeze | 3 blockers found (dead provider-send wait; check/capture unbinding; fingerprint self-destruct) → **fixes applied same day** (see Reviewer Findings) | Execute |

## Problem And Evidence

- Behavior to improve: **G12** — the suspended/terminated FCM path (b11/b12 rows) proves custody/visibility only; a silent-channel card passes every existing assertion (`_warmChecks:74-81`/`_coldChecks:82-88` carry zero channel entries; `mknoon_messages_silent` is visible+tappable, `local_notification_support.dart:23-30`). **G7** — PRD §13's Android device cases have zero device e2e for Doze, permission-denied behavior, channel-disabled behavior, and mid-session token refresh; OEM restrictions are not provable on available hardware.
- **W0 — prerequisite this plan now owns (review blocker, source-confirmed): the payload campaign is broken against relay v1.8.0.** `relayJournalContainsAndroidProviderSend` (`support:117-127`) requires `[PUSH] Notification sent to <peer-prefix>` — removed by `8d86501e4` (2026-08-15); v1.8.0 (production since 2026-08-16) emits only recipient-free `[PUSH] outcome=success attempt=%d total_attempts=%d` (`inbox.go:626`). `_waitForProviderSend` is a fatal 2-minute wait on ALL THREE FCM legs (runner `:576` warm, `:698` cold, `:835` b13), so a fresh campaign run dies on the warm leg before any G12/G7 assertion executes. The freeze suite still pins the OLD literal (`support_test:262-278`). This widens **G16** to both campaigns; the payload-side adaptation is THIS plan's W0; the reaction-side repair stays separately owned.
- Confirmed current state per case (survived adversarial refute; working tree = HEAD):
  - **G12 mechanics:** b13's capture pattern transplantable (dump = host-adb into system_server; card survives kill/airplane; windows: warm `:578-608`, cold post-`:709` pre-`:726`). Tone hazards (review-sharpened): all sends share ONE conversation tone key; the durable lease survives kill/tap; ≥31 s observation-keyed spacing is sound against reserve/commit in the normal path, BUT (a) **interrupted-publication repair is fail-closed-SILENT** — a kill between native show and commit leaves a `publishing` residue whose repair restarts a fresh 30 s silent window at the NEXT reservation attempt (`durable_notification_tone_lease.dart:994-1005,:1364-1385` — "never reclaim it for an immediate second sound"), and the cold leg's own observe-then-kill adjacency (`:700-701`) is exactly that hazard, poisoning the later b13 strict assert; (b) storage-exception fail-open-audible (`bmh:968-976`) is a DIFFERENT path — both are true, the plan's old blanket "fail-open" claim was wrong.
  - **Check-to-capture binding (review blocker):** artifact checks are built unconditionally true from static const lists (`support:301-317` — `{for check in passedChecks: check: true}`) and `validateNotificationArtifact` validates check KEYS only for Android scenarios (`device_criteria.dart:596-608`; the evidence-key schema is iOS-only `:615-659`). Without evidence-level validation, removing a capture while keeping the const entry produces a validating LIE. Fixed by W1's required-evidence design below.
  - **Fingerprint self-destruct (review blocker, fail-closed consequence source-confirmed; byte-drift platform-unresolved):** the campaign end-verify `_verifyExactNotificationOsState` (runner `:232` → `:1250-1266`) requires the dumpsys channel fingerprint (`androidNotificationChannelStateSha256`, `support:14-49` — only `mLastNotificationUpdateTimeMs` masked) to equal the preflight baseline (`:438-442`); on mismatch the finally DELETES ALL artifacts and throws (`:234-243`). A Settings channel toggle (and possibly a pm revoke/grant cycle) plausibly persists `userSet`/user-locked provenance in the hashed lines. TC-380-08/07 carry a mandatory first-device probe + a chosen policy (below).
  - **Doze:** mechanisms exist (relay `Priority "high"`; `onDeletedMessages` → expedited WorkManager CONNECTED → headless recovery); plan 374 proved WorkManager continuation and deferred Doze; zero `deviceidle` usage repo-wide except 374's ANTI-idle bucket forcing (`run_android_headless_recovery_374.sh:236`, frozen) — never co-run.
  - **Permission denied:** full production mechanism host+Robolectric-locked (coordinator denied → health record + `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED`, no retry; banner → settings intent; native guard covers only the recovery card; the Dart path posts blind and the OS drops). Zero denied-behavior device e2e. Helpers reusable (`capture_android_background_crypto_preflight.dart:2968-3008`). Review additions: the foreground FCM drain never reaches a notification decision (runner `:806-813`) so zero-records is vacuous without a background-isolate post-attempt requirement; and a single revoke leaves the permission re-requestable on SDK 33+ — the startup attempt can raise a live OS dialog unattended (`pm set-permission-flags … user-fixed` avoids it, device-verify first run).
  - **Channel disabled:** NO production read-back exists anywhere; no adb setter exists; programmatic downgrade is a ONE-WAY door. Settings-UI automation via the direct deep link + one bounded toggle tap. Review refuted the leg's old self-guard: within the 30 s window the post lands on `mknoon_messages_silent` — a DIFFERENT channel unaffected by blocking `mknoon_messages` — so "zero records on the audible channel" passed with the toggle skipped. Fixed contract below (spacing + channel-agnostic zero-records + post-toggle importance probe).
  - **Token refresh (premise corrected at planning; sharpened at review):** production re-registration EXISTS (coordinator + lazy `onTokenRefresh` stream; `PUSH_REGISTER_TOKEN_REFRESH_EVENT` emitted ONLY on the stream path, sole emit `push_registration_coordinator.dart:66-70`) and rotation+startup registration is already device-proven (preflight→relay-registration chain). Only the mid-session leg is missing. Review: a crash/relaunch between deleteToken and success ALSO traverses the stream path in the new process — same-process must be pinned by PID equality + zero additional `trigger=startup` attempts in-window; and deleteToken alone may never rotate — the in-repo precedent polls `getToken` until a different hash (`android_background_crypto_preflight_app.dart:609,:630-631`).
  - **OEM:** no mechanism, no coverage, no OEM hardware (Pixel 6 + emulator-5554, stock SDK 36).
- Existing coverage: b13 channel assert (`runner:863-882`); coordinator locks (`:18/:95/:195/:226`); Robolectric denied/channel-recreate; 374 WorkManager proof; token-rotation chain.
- Missing coverage: everything in the Test Contract.
- Refuted findings (do NOT re-introduce):
  - "Token refresh has no production handler / bmh re-registers per launch" — false; never plan a build-the-handler row.
  - "Channel delete+recreate resets importance" — false; one-way door.
  - "b12 rows already assert channel somewhere" — refuted across all surfaces.
  - **"Removing the capture fails closed at artifact write"** (this plan's own earlier mutation claim) — refuted: checks are claimed-true consts; only the W1 evidence-binding makes capture removal red.
  - **"The channel-disabled leg self-guards via the audible-channel zero-records"** — refuted (silent-channel escape); the corrected contract (spacing + channel-agnostic zero-records + importance probe) is the guard.
  - **"Tone-lease breakage always fails open audible"** — the storage-exception path does (`bmh:968-976`); interrupted-publication repair fails CLOSED-silent (`lease:994-1005`).
  - "`pm revoke` can straddle a running probe" — revoke kills the process; revoke → relaunch → assert.
- Unresolved findings (evidence-gated): (a) Doze delivery-vs-deferral on first instrumented run; (b) SDK-36 fingerprint byte-drift after toggle/revoke cycles (mandatory pre-authoring probe); (c) `user-fixed` permission-flag behavior on SDK 36 (device-verify); (d) whether v1.8.0's wake-outcome admission ever CANCELS the push for b13's connected recipient (zero provider sends → W0's wait would time out on that leg only; warm/cold killed receivers cannot complete the correlation, so their wakes always fire) — first run decides; a b13-only W0 timeout is a 378/G16 design question, not a G12/G7 failure; (e) the `android.production_fcm` debug-profile flow-logging premise (FLOW-based checks note it).
- Affected production / test / gate files: `lib/core/debug/android_notification_payload_e2e_protocol.dart` + `android_notification_payload_e2e.dart` (new probe action, debug-only); `integration_test/support/android_notification_payload_campaign.dart` (W0 helper + fingerprint redaction policy); `integration_test/scripts/notification_android_payload_campaign.dart` (b12 captures, spacing, 4 legs, finally flags); `integration_test/scripts/run_notification_tap_device_real.dart`; `tool/sims/device_criteria.dart` (checks + required-evidence); `tool/sims/critical_features.json`; `test/integration/notification_tap_device_criteria_test.dart`; `test/integration/android_notification_payload_campaign_support_test.dart` (W0 + fingerprint freeze re-derives); `scripts/test/notification_tap_campaign_adapter_contract_test.sh` (census re-pin); `test/core/debug/android_notification_payload_e2e_test.dart` (exists — TC-380-05 rows land there).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `585839a9908225b8`; `stale:integration_test/notification_sound_smoke_harness.dart` (expected — 378 uncommitted edits).
- Query / profile: `python3 graphify-arch/tdd_context.py query "android_notification_payload_campaign b12 b13 channel assertion validateNotificationArtifact _notificationRequirements dumpsys" --profile tdd --budget 700`; refined by workflows `wf_4471f5b3-082` (grounding) and `wf_fcc39e38-17d` (adversarial review).
- Anchors: legs (`runner:548-674,:676-783,:814-915`), artifacts (`:1585-1625`), finally (`:200-244`), provider waits (`:576,:698,:835`); support helper (`:117-127`), artifact builder (`:301-317`), fingerprint (`:14-49`); catalog (`run_notification_tap_device_real.dart:9-123`); validator (`device_criteria.dart:557-659,:946-1005`); freezes (`support_test:10-97,:262-278,:293-338`; adapter sh `:16-31,:142-245`); token pipeline (`push_registration_coordinator.dart:64-93`, bootstrap `:6185-6214`); probe actions (protocol `:8-30`, e2e `:43-122`); lease (`:349,:994-1005,:1011-1033,:1190-1203,:1364-1385`).
- Surfaced proof/gate files: `notification_tap_device_criteria_test.dart:44-77`; `android_app_state_guard_test.dart:1633-1642`; guard (`:16-31,:1613-1653`).
- Graph gaps requiring raw source search: PRD/plan markdown, relay Go literals, platform feasibility (labeled).
- Reuse rule: anchors are starting points; re-verify at execution.

## Scope Contract And Guard

In scope:
- **W0:** adapt `relayJournalContainsAndroidProviderSend` (+ its freeze rows) to the v1.8.0 `outcome=success` grammar, recipient binding dropped with recorded justification (single-recipient topology + since-`sentAt` scoping).
- **W1 (G12):** channel assertions on the existing b12 warm/cold rows via checks **plus validator-required evidence keys** populated only from the measured capture; ≥31 s observation-keyed spacing generalized to **every audible-asserting send in the campaign**; a 2–5 s post-observation grace before every `_terminateReceiver` that follows a card observation.
- **W2 (G7):** four new legs — `tc_g7_permission_denied`, `tc_g7_token_refresh_mid_session`, `tc_g7_channel_disabled`, `tc_g7_doze_delivery` — plus one new debug probe action (`notification_delete_push_token`: deleteToken + bounded different-hash `getToken` poll, receipt carries old/new hash prefixes); campaign-finally tracked mutation flags (`_permissionRevoked`, `_channelToggledOff`, `_dozeForced`, `_tokenRotationInFlight`) with `attempt()` restore entries mirroring `_networkMutated` (`runner:200-244`).
- Fingerprint policy for the two OS-state-mutating legs (mandatory first-device probe; policy below).
- OEM: `N/A (target unavailable by project policy)`; optional AOSP proxies deferred (TC-380-11).

Must preserve:
- The five existing scenario behaviors and `tc_b13`'s assertions → TC-380-04 sentinel + census re-pin discipline.
- Freeze semantics → the only hard no-insert zone is runner `:700-:703` (T1's adjacency trio); new leg functions go AFTER `:915` (outside every sliced span); any touched freeze is RE-DERIVED, never weakened. Banned-literal checklist: `'force-stop'` (in `:1369-1396`), `'monkey'` (in `:1429-1451`), `'pm clear'`, `["'logcat', '-c'"]`, the literal `'clear',` (file-wide, `android_app_state_guard_test.dart:1638`), the T1 absent-string, raw `${result['errorType']}` interpolation.
- Permission/channel/doze/battery device state → per-leg restore inside the leg + campaign-finally flags; permission mutations happen strictly AFTER `AndroidAppStateGuard.capture` and are restored BEFORE `appStateGuard.restoreAll` runs (the guard snapshots once at start and heals at end — it has NO per-leg API; review-corrected).
- Coordinator/host denied+refresh locks and Robolectric rows stay green.

Hard `Do not`:
- Do not add a channel field to the shared `ActiveNotificationCard` parser — always a fresh `_notificationDump()` + `androidNotificationChannelsForBody`.
- Do not mint new scenario ids for G12.
- Do not downgrade or delete a notification channel programmatically — Settings-UI automation only, on the emulator.
- Do not run the Doze leg concurrently with (or reusing) 374's `set-standby-bucket active` forcing.
- Do not build channel-disabled detection/surfacing (new health reason + read-back) — deferred product decision.
- Do not treat `assertionsAttempted` literals as self-updating (fail-open; both quoting forms must be bumped and both grep-gated).
- Do not populate any required evidence key from anything but the measured capture (the const-checks lie is the exact defect W1 exists to kill).

Deferred / accepted difference:
- **OEM restrictions** → `N/A (target unavailable by project policy)`; optional standby-bucket `restricted`/battery-saver proxies under **GAP-N12** (which is the owner of record; plans 374/375's "WP-07" label bridges here).
- **Channel-disabled detection/surfacing** → own product decision + plan.
- **Real-radio Doze on the Pixel** → optional follow-up (stated physical-topology reason); closure legs run emulator-receiver.
- **Reaction-campaign G16 repair** → separately owned; W0 fixes only the payload-side helper.
- iOS §13 matrix → GAP-N12.

Dependencies:
- Device closure requires FCM service-account credentials + the prebuilt stamped `android.production_fcm` APK (devices hold 08-17 debug builds — redeploy + provenance-verify first).
- The first full campaign run also lands `tc_b13`'s first device evidence (subject to unresolved (d)); sound smoke runs FIRST in any combined session (its debug install destroys stamped builds).

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-380-00 | **W0: provider-send wait works against v1.8.0.** `relayJournalContainsAndroidProviderSend` matches a since-`sentAt`-scoped `[PUSH] outcome=success` line (recipient binding dropped — recorded justification: single-recipient topology + timestamp scoping; the v1.8.0 line is attribution-free by design) | `test/integration/android_notification_payload_campaign_support_test.dart` — W0 rows: helper TRUE on a v1.8.0-shaped journal fixture, FALSE on empty/pre-`sentAt`-only fixtures; old-literal freeze rows (`:262-278`) re-derived to the new grammar | host / journal-string fixtures | causal RED (on HEAD the helper returns FALSE for a v1.8.0 fixture — that IS the broken campaign) → true/false rows pass; freeze re-derived | revert the helper to the dead literal → the v1.8.0-fixture row red | `flutter test test/integration/android_notification_payload_campaign_support_test.dart` |
| TC-380-01 | **Validator binds b12 channel checks to measured evidence** (review-hardened): `_notificationRequirements` gains `b12.warm_audible_channel`/`b12.cold_audible_channel` AND `validateNotificationArtifact` gains required-EVIDENCE validation for Android scenarios — `warmAlertChannel`/`coldAlertChannel` must be present and equal `'mknoon_messages'`. Negatives: check absent → REJECT; check true but evidence key absent → REJECT; evidence key `'mknoon_messages_silent'` → REJECT | `test/integration/notification_tap_device_criteria_test.dart` new negative rows + existing b12 fixtures (`:44-77`) updated with checks+evidence | host / artifact fixtures | causal RED (on HEAD the validator accepts channel-free b12 artifacts AND validates no Android evidence keys — both halves of the gap) → all rows pass | revert the `_notificationRequirements` additions → check-negatives red; revert the evidence validation → evidence-negatives red | `flutter test test/integration/notification_tap_device_criteria_test.dart` (host-all-only dir → direct gate; auto-classifies via `run_test_gates.sh:1515-1519`) |
| TC-380-02 | **b12-warm card audible** (device): second dump in window `:578-608`; `androidNotificationChannelsForBody` on the warm marker → exactly one record, channel `mknoon_messages`; in-leg throw on mismatch; **evidence key `warmAlertChannel` populated ONLY from the capture**; check `b12.warm_audible_channel` | payload campaign warm leg | device proof / pinned pair, stamped APK, FCM credentials | manual/device-only proof → check + evidence validator-enforced | remove `b12.warm_audible_channel` from `_warmChecks` → validator missing-check red at artifact write (`:1588-1594`); remove the dump/evidence write → validator missing-evidence red (TC-380-01's binding — review-corrected mutation, the old "remove capture → fail-closed" claim was refuted) | campaign run; surfaces: `_warmChecks`, catalog `requiredChecks`, `_notificationRequirements`, json assertions |
| TC-380-03 | **b12-cold card audible under enforced spacing** (device): ≥31 s wait keyed to the warm-card observation timestamp before the cold send; same spacing before the b13 send; **2–5 s post-observation grace before `_terminateReceiver` at `:700-701`** (the observe-then-kill adjacency leaves a `publishing` residue whose repair silences the NEXT card regardless of spacing — review); dump post-`:709` pre-`:726` → one record, `mknoon_messages`; evidence `coldAlertChannel`; a silent card coinciding with a publishing-residue repair is a **typed inconclusive-red, retry once** — never a product-red | payload campaign cold leg, check `b12.cold_audible_channel` | device proof / same fixture | manual/device-only proof → check + evidence enforced; measured warm→cold gap logged into evidence (settles the timing question) | as TC-380-02 (const removal / evidence removal); remove the spacing wait → strict assert becomes timing-dependent (flake-red on a compressed run) | campaign run; same surfaces |
| TC-380-04 | Freeze/pin suite + state-guard pin unchanged | `android_notification_payload_campaign_support_test.dart` T1–T3 + `android_app_state_guard_test.dart:1633-1642` | host / source-slice freezes | GREEN sentinel → still green (no-insert zone `:700-:703` respected; new legs after `:915`; banned literals absent; W0/fingerprint rows are RE-DERIVES, recorded per-slice) | post-fix mutation: move the cold dump into `:700-:703` → T1 adjacency regex red (pin proven live) | `flutter test` both files |
| TC-380-05 | New probe action `notification_delete_push_token`: allow-listed; calls injected `deleteToken` then polls injected `getToken` (bounded) until a different hash; receipt carries old/new token-hash prefixes; unknown actions still rejected with **FormatException** (loud, not silent — review-corrected) | `test/core/debug/android_notification_payload_e2e_test.dart` new rows (file EXISTS — hedge removed) | host / injected fake messaging whose deleteToken visibly changes the token hash (side-effect fidelity) | causal RED (unknown action → FormatException at protocol `:73-75`) → dispatch + receipt + hash-change asserted | remove the allow-list entry (`protocol:22-30`) → red | direct `flutter test`; AUTO (`test/core/**`). Surfaces: protocol const + allow-list, switch arm; adapter-sh required-token census addition is OPTIONAL discipline (nothing pins the protocol/e2e file bodies — review-verified) |
| TC-380-06 | **Mid-session token refresh** (device, `tc_g7_token_refresh_mid_session`): wait for `PUSH_REGISTER_COORDINATOR_ATTEMPT trigger=startup`; capture receiver PID; stage the probe action; assert `PUSH_REGISTER_TOKEN_REFRESH_EVENT` → `PUSH_REGISTER_COORDINATOR_SUCCESS` with **details `trigger=token_refresh`**, **PID at SUCCESS == PID before staging**, and **zero additional `trigger=startup` ATTEMPT events in the cursor window** (a relaunch also traverses the stream path — review); then FCM to the NEW token posts a card (spacing-compliant). Checks `g7.token_refresh_event_observed` / `g7.token_refresh_reregistered_same_process` / `g7.token_refresh_new_token_delivery`; evidence: PID pair + token-hash prefixes | new campaign leg | device proof / same fixture | manual/device-only proof → checks + evidence enforced (evidence keys required per the W1 pattern) | comment out the coordinator's refresh subscription (`:64-74`) → leg red at the refresh event AND host lock `:95` red | campaign run; 10-surface sweep (TC-380-10) |
| TC-380-07 | **Permission denied** (device, `tc_g7_permission_denied`, emulator receiver): after guard capture — `pm revoke` (kills process) + **`pm set-permission-flags … android.permission.POST_NOTIFICATIONS user-fixed`** (auto-denies re-requests without a dialog; cleared on restore; device-verify first run) → relaunch → **receiver HOME'd (KEYCODE_HOME) before the send** → deliver → assert: **background-isolate post-attempt evidence required BEFORE zero-records counts** (`PUSH_BACKGROUND_MESSAGE_RECEIVED` for the fcm messageId — kills the vacuous foreground-drain pass, `runner:806-813`), dump AFTER custody confirmation shows zero pkg-matching records, process alive, `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` in window, message persisted + unread; banner node via uiautomator = **secondary evidence** (primary = the flow event + health record); then `pm grant` + clear flags + retry → `PUSH_REGISTER_COORDINATOR_SUCCESS` + spacing-compliant control posts audibly | new campaign leg (helpers lifted from preflight `:2968-3008`) | device proof / same fixture | manual/device-only proof → checks `g7.permission_denied_no_post` (attempt-gated), `g7.permission_denied_typed_health`, `g7.permission_custody_preserved`, `g7.permission_regrant_recovery` | drop the coordinator denied short-circuit (`:205-229`) → typed-health red AND host locks `:18/:226` red | campaign run; 10-surface sweep; `_permissionRevoked` finally flag |
| TC-380-08 | **Channel disabled** (device, `tc_g7_channel_disabled`, emulator): open the exact channel screen (`am start -a android.settings.CHANNEL_NOTIFICATION_SETTINGS` + APP_PACKAGE/CHANNEL_ID extras), one bounded toggle tap OFF → **post-toggle probe: dumpsys channel section shows `mknoon_messages` blocked/IMPORTANCE_NONE before sending** (kills selector-drift false-greens) → spacing-compliant delivery → assert: **`androidNotificationChannelsForBody(dump).isEmpty` for the marker — channel-agnostic zero-records** (kills the silent-channel escape: within the tone window the post targets `mknoon_messages_silent`, a different channel unaffected by the block — review), process alive, persisted + unread; toggle back ON (same automation) → spacing-compliant control posts audibly | new campaign leg (uiautomator precedent `run_intro_accept_notification_android.dart:923-1003`) | device proof / same fixture; **fingerprint policy applies (see W3 in steps)** | manual/device-only proof → checks `g7.channel_disabled_no_post` (probe-gated), `g7.channel_custody_preserved`, `g7.channel_reenable_recovery`; leg is evidence-gated on Settings-UI viability + the fingerprint probe | none in app code (no production mechanism — recorded finding); the leg self-guards NOW via the importance probe + channel-agnostic zero-records (a skipped toggle fails the probe) | campaign run; 10-surface sweep; `_channelToggledOff` finally flag |
| TC-380-09 | **Doze delivery** (device, `tc_g7_doze_delivery`, emulator): terminate receiver → `dumpsys battery unplug` → `deviceidle force-idle deep` → **`dumpsys deviceidle get deep` == IDLE captured at BOTH boundaries — immediately before the send AND at card observation — raw state strings in evidence** (review: a one-shot check lets "delivered-during-idle" be claimed for an awake device; `IDLE_MAINTENANCE` at delivery classifies into the deferred arm) → FCM high-priority send → typed disposition: delivered-during-idle (expected) vs `g7.doze_deferred_delivery` (distinct, never a silent pass; convergence is load-bearing ONLY in this arm) → `deviceidle unforce` + `battery reset` → post-unforce convergence, no duplicate render (AC-04/AC-10). Recovery-card rows never assert sound (fixed-wake cards are deliberately silent) | new campaign leg | device proof / same fixture | manual/device-only proof, pass predicate evidence-gated on the first instrumented run; both arms require `g7.doze_forced_idle_proven` (both raw states) + bounded dual-attempt-style evidence | flip the leg to skip `force-idle` → `doze_forced_idle_proven` red (state strings absent/NOT-IDLE) | campaign run; 10-surface sweep; `_dozeForced` finally flag (unforce + battery reset in the run()-finally `attempt()` list, `runner:200-244` — the correct always-runs surface; `:1228-1248` is card-cleanup only, citation corrected) |
| TC-380-10 | Registration complete and byte-pinned: catalog +4 rows (`mode` is a free-form display string — no legal-value constraint); `_androidPayloadCampaignIds` +4; leg bodies + `_writeScenarioArtifact` calls; `_assertionsAttempted` ladder; **BOTH count literals 5→9 with their exact quoting** (`assertionsAttempted: 9` at `:278`; `'assertionsAttempted': 9` at `:283`) + detail string `:287-291`; `_removeScenarioArtifacts` +4; `_notificationRequirements` +4 (checks AND required evidence); json assertions; adapter-sh census re-pinned 5→9 in declaration order; host fixture rows (positive+negative) for all 4 new ids | adapter sh + criteria test + grep gates | host + sh contract | causal RED by construction (catalog edit reds the sh `cmp :22-29` until re-pinned; an id missing from `_notificationRequirements` fails CLOSED at artifact write — the G14 lesson) → all green after the sweep | remove any one surface → its named gate red | `/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh`; `sims-contracts`; grep gates below |
| TC-380-11 | **OEM restrictions** — no device row | `N/A (target unavailable by project policy)` — no OEM-skinned hardware in the live matrix; no production mechanism to host-test (zero battery-optimization/autostart code) | N/A | N/A — not a blocker, not an evidence gap; optional AOSP proxies under GAP-N12 | N/A — no test exists to mutate | recorded here + map G7 row; owner GAP-N12 |
| TC-380-12 | Host policy layer stays locked | coordinator test rows `:18/:95/:226`; Robolectric `MknoonFirebaseMessagingServiceTest.kt:159-207` | host / existing | GREEN sentinel → unchanged | guarded by TC-380-06/07 mutations (same seams) | `flutter test test/features/push/application/push_registration_coordinator_test.dart` |

### Test Notes
- Evidence keys use fresh names (`warmAlertChannel`, `coldAlertChannel`, `g7.*` values, PID pairs, token-hash prefixes, doze state strings) — none normalize into the secret-scan denylist (`device_criteria.dart:919-930`); populate them ONLY from measured captures.
- The ≥31 s spacing is a property of **every audible-asserting send** (cold, b13, token-leg delivery, permission-regrant control, channel-reenable control), keyed to the previous card's observation timestamp; log each measured gap into evidence.
- Marker uniqueness is proven safe (12 random bytes/leg, pkg-scoped full-line match, channel read from the same `NotificationRecord` block — review-verified); carry that composite-node rule into the new legs verbatim.
- Leg order: append the 4 new legs after b13; the campaign aborts on the first `_Failure` (sequential legs in one try, `runner:186-199`) so cross-leg leakage is moot EXCEPT via the finally — hence the four tracked mutation flags.
- TC-380-06 waits for the startup attempt BEFORE staging the probe (early refresh is dropped by design, bootstrap `:6185-6196`).
- FLOW-event-based checks (token leg mostly) depend on the `android.production_fcm` debug-profile flow logging (378 `:34`, not re-verified) — dumpsys + DB probes stay primary wherever possible.
- New ids are non-nesting; none end in `_message_unread_lifecycle`.

## Implementation Steps
1. Snapshot `git status --short` (378 worktree edits expected). Author TC-380-00 + TC-380-01 negatives + TC-380-05 rows FIRST; record causal REDs.
2. **W0:** update `relayJournalContainsAndroidProviderSend` to the `outcome=success` grammar; re-derive its freeze rows (`support_test:262-278`). Stop-if: the helper's call sites turn out to pass journal slices NOT scoped since `sentAt` → add the scoping rather than widening the match.
3. **W1 (G12):** `_notificationRequirements` +2 checks AND the Android required-evidence mechanism in `validateNotificationArtifact`; update host fixtures; warm/cold captures + evidence writes + in-leg throws; spacing waits + the 2–5 s post-observation grace; checks consts + catalog `requiredChecks` + json assertions. Insertion rules per TC-380-04 (only `:700-:703` is forbidden; anything touching a slice = re-derive in the same commit).
4. **W3 fingerprint probe (before authoring TC-380-07/08 legs):** on `emulator-5554`, capture `androidNotificationChannelStateSha256`, perform toggle OFF→ON and `pm revoke`→`grant` cycles, re-capture, diff. If bytes drift: PRIMARY policy — extend the fingerprint redaction to the exact provenance/user-locked tokens the probe names (importance values STAY hashed, so an unrestored OFF state still reds; re-derive the fingerprint freeze `support_test:293-338`); FALLBACK — run the two mutating legs last + receiver reinstall + re-baseline before the finally verify. Record the chosen path in TC-380-07/08. Stop-if: neither policy holds on the probe evidence → carve the two legs to their own campaign phase.
5. **W2:** probe action (protocol + allow-list + switch arm; injected messaging seam); then the four legs in order (permission → token → channel → doze), each with artifact writes, cleanup entries, per-leg restores, and its finally flag.
6. Registration sweep per TC-380-10.
7. Focused GREEN → sentinels → gates; device closure = one full campaign run when FCM credentials + stamped APK are present.

## Risks And Blind Spots
- Tone-window flakes → spacing everywhere audible is asserted + the post-observation grace + typed inconclusive-red for publishing-residue coincidence (the two lease failure modes are now stated correctly: storage-exception → audible; interrupted-publication repair → silent).
- Lifecycle / derived-state durability: cold + Doze legs exercise fresh-process reconstruction (staging store, lease file, WorkManager continuation).
- Sibling-surface consistency: the native-guard vs Dart-blind-post split is asserted honestly (no "app skipped the post" claim anywhere).
- Destructive-action side effects: `_removeScenarioArtifacts` +4; per-leg restores + the four finally flags (a mid-leg throw can no longer strand the emulator unplugged/idle-forced/denied/unregistered).
- Invariant re-verification under new transitions: regrant/re-enable controls re-verify audible posting after each restore (spacing-compliant).
- Construction/call-site census: `grep -rn 'isAndroidNotificationPayloadE2EAction\|_actions' lib/core/debug/` — const + allow-list + switch (3 sites); TC-380-05's mutation proves the allow-list; optional source pin: require ≥3 `androidNotificationChannelsForBody(` call sites in the runner.
- Build-artifact provenance: stamped-build post-install verify before the run; campaign preflight fingerprints channel state (`:425-442`).
- Permission/ACL verb symmetry: POST_NOTIFICATIONS exercised deny AND regrant, with flag set/clear symmetric.
- Fake side-effect fidelity: TC-380-05's fake messaging changes the token hash on deleteToken (the real side effect), mirroring the preflight race discipline.
- Composite-node assertions: channel read from the marker's own record block; PID pair read from the same process observation points.

## Gate Cadence
- Per-plan closure: TC-380-00/01/05 direct host tests + freeze/pin sentinels + `sims-contracts` + graph-affected dependents + the `1to1` curated lane ONLY if graph-affected names its members (lib edits are debug-probe-only) + the device campaign run.
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/core/debug/android_notification_payload_e2e.dart lib/core/debug/android_notification_payload_e2e_protocol.dart integration_test/scripts/notification_android_payload_campaign.dart integration_test/support/android_notification_payload_campaign.dart tool/sims/device_criteria.dart --budget 600` → run named test files BEFORE any lane. (Path-string freeze/census tests have no import edge — covered by the direct commands.)
- Full `host-all` is NOT a per-plan gate — GAP-N12 wave + final release closure.
- Shared tests outside feature/core globs (exact commands): `flutter test test/integration/notification_tap_device_criteria_test.dart test/integration/android_notification_payload_campaign_support_test.dart test/integration/android_app_state_guard_test.dart`.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot (378 worktree edits expected — do not revert)
git status --short

# Causal REDs (before production edits) — must FAIL for the documented reason
flutter test test/integration/android_notification_payload_campaign_support_test.dart --plain-name 'provider send helper accepts the v1.8.0 outcome journal'   # RED: helper still greps the dead literal
flutter test test/integration/notification_tap_device_criteria_test.dart --plain-name 'b12 warm artifact without the audible-channel check is rejected'        # RED: validator accepts it on HEAD
flutter test test/integration/notification_tap_device_criteria_test.dart --plain-name 'b12 warm artifact with the check but no measured evidence is rejected'  # RED: no Android evidence validation exists on HEAD
flutter test test/core/debug/android_notification_payload_e2e_test.dart --plain-name 'delete-push-token action dispatches'                                     # RED: unknown action (FormatException)

# Focused GREEN (after the fix)
flutter test test/integration/android_notification_payload_campaign_support_test.dart
flutter test test/integration/notification_tap_device_criteria_test.dart
flutter test test/integration/android_app_state_guard_test.dart
flutter test test/core/debug/android_notification_payload_e2e_test.dart
flutter test test/features/push/application/push_registration_coordinator_test.dart

# Graph-affected dependents BEFORE any lane
python3 graphify-arch/tdd_context.py affected lib/core/debug/android_notification_payload_e2e.dart lib/core/debug/android_notification_payload_e2e_protocol.dart integration_test/scripts/notification_android_payload_campaign.dart integration_test/support/android_notification_payload_campaign.dart tool/sims/device_criteria.dart --budget 600
# then: flutter test <each named file>

# Contracts + registration (sh gates via host bridge; grep-verified, never run-verified)
/claude-host-bin/host-run bash scripts/test/notification_tap_campaign_adapter_contract_test.sh    # PASS with the 9-id census
/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts
grep -c 'b12.warm_audible_channel' tool/sims/device_criteria.dart               # expect ≥2 (check + evidence requirement)
grep -c 'tc_g7_' integration_test/scripts/run_notification_tap_device_real.dart # expect ≥8 (4 ids × catalog+ids-set)
grep -c "assertionsAttempted: 9" integration_test/scripts/notification_android_payload_campaign.dart    # expect 1 (unquoted, :278)
grep -c "'assertionsAttempted': 9" integration_test/scripts/notification_android_payload_campaign.dart  # expect 1 (quoted PASS-path literal, :283)
dart integration_test/scripts/run_notification_tap_device_real.dart --list-scenarios   # exit 0, 10 rows (9 campaign + the iOS row)
/claude-host-bin/host-run ./scripts/run_test_gates.sh completeness-check               # PASS, 0 unmatched
./scripts/check_reliability_simulation_discovery.sh                                    # exit 0

# Fingerprint probe (BEFORE authoring the permission/channel legs — records the policy decision)
# emulator-5554: baseline sha → toggle OFF→ON via Settings deep link → pm revoke→grant → re-capture → diff; record drifting tokens in the plan

# Device closure (FCM credentials + stamped android.production_fcm redeployed + provenance-verified FIRST)
.claude/skills/sims/scripts/run_with_devices.sh major --list                           # notifications.android_payload_campaign listed
.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign   # PASS: 9 artifacts incl. b12 channel evidence + 4 g7 legs (+ tc_b13, subject to unresolved (d))

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: the four causal-RED commands; the adapter-sh `cmp` between the catalog edit and its re-pin (same-change resolution).
- GREEN sentinel: freeze suite, state-guard pin, coordinator locks, Robolectric rows.
- Pre-existing dirty tree / known failure: 378 uncommitted edits; the reaction campaign's `$.evidence[provider_fcm]` redness (G16 reaction side — separately owned).
- Environment blocker (NOT product): missing FCM credentials, stamped APK not deployed, Settings-UI selector drift (TC-380-08 evidence-gated), `user-fixed` flag behaving differently (TC-380-07 first-run verify), a b13-only W0 timeout caused by wake-outcome cancellation for connected recipients (378/G16 design question, not this plan's failure).
- Scope drift (BLOCKING): any behavior change in production notification code (lib edits are debug-probe-only), any weakened freeze/census, any evidence key populated from anything but a measured capture.

- [ ] Every behavior has a named test/proof or the justified OEM N/A.
- [ ] Causal RED → GREEN + the named mutation re-reds recorded (TC-380-00/01/05 at minimum).
- [ ] Sentinels + `sims-contracts` + adapter sh pass with semantic outcomes.
- [ ] Fingerprint probe run and policy recorded BEFORE the permission/channel legs are authored.
- [ ] 10-surface sweep grep-verified + completeness/discovery green.
- [ ] Device campaign run passes with all 9 artifacts validated (b12 evidence keys measured; Doze disposition pinned from first-run evidence).
- [ ] `flutter analyze` clean; `git diff --check` clean; Scope Contract respected.

## Handoff
- First causal RED command: `flutter test test/integration/android_notification_payload_campaign_support_test.dart --plain-name 'provider send helper accepts the v1.8.0 outcome journal'` (after authoring the row).
- Preservation command: `flutter test test/integration/android_notification_payload_campaign_support_test.dart` (whole file).
- Manual registration: the TC-380-10 sweep + the probe-action surfaces (protocol const, allow-list, switch arm; adapter-sh token census optional).
- Migration: none.
- Boundary closure: one full `notifications.android_payload_campaign` device run (blocked on FCM credentials + stamped APK).
- Unresolved evidence: Doze first-run predicate; fingerprint byte-drift probe; `user-fixed` flag on SDK 36; wake-outcome cancellation for b13's connected recipient; debug-profile flow-logging premise.

## Device/Relay Proof Profile
- Profile: paired-device (os-notification device lab), emulator receiver for all four G7 legs (keyguard-free UI automation); Pixel 6 as the second peer.
- Boundary being proven: OS-level channel/sound truth on the suspended/terminated FCM path; OS permission/channel/idle interaction; live mid-session FCM token rotation.
- Live availability check: `adb devices -l` (this session): `21071FDF600CSC` (Pixel 6, SDK 36) + `emulator-5554` (SDK 36).
- Pinned targets: receiver `emulator-5554`, peer `21071FDF600CSC`. Real-radio Doze on the Pixel = optional follow-up (stated physical-topology reason).
- Automation: fully harness-driven (adb + uiautomator bounded taps; no user interaction).
- Closure role: required closure evidence for G12 + G7(closable); OEM = typed N/A.
- `FLUTTER_DEVICE_ID`: host selector only; both ids pinned in campaign argv.
- Registration: catalog `--scenario` rows + existing sims capability `notifications.android_payload_campaign` (assertions array updated).
- Discovery command: `.claude/skills/sims/scripts/run_with_devices.sh major --list` → capability listed.
- Closure command: `.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_payload_campaign` → PASS, 9 validated artifacts.
- Deferred device work: OEM proxies + real-radio Doze + iOS matrix → GAP-N12; reaction-side G16 repair → own plan.

## Reviewer Findings (wf_fcc39e38-17d, 2026-08-17 — fixes applied same day)
- Verdict was **plan-fixes-required / apply-plan-fixes**; the G12 premise, tone-window analysis, freeze insertion points, catalog mechanics, and all coordinator/permission/probe seams **verified accurate**; the marker-uniqueness/composite-record design survived attack.
- Blockers fixed: (1) the campaign's provider-send wait greps a relay line deleted in `8d86501e4` — fatal on all three FCM legs before any new assertion runs → W0/TC-380-00 (also widened map G16 to the payload campaign; the plan's earlier "different campaign, not this plan's" interpretation line was wrong and is removed); (2) artifact checks are claimed-true consts and the validator checked keys only — a removed capture produced a validating lie → TC-380-01's required-evidence binding + corrected mutations; (3) the permission/channel legs mutate exactly the state the campaign's byte-exact fingerprint verify hashes, and a mismatch DELETES all artifacts → W3 mandatory probe + redaction-or-reinstall policy.
- Plan-fixes applied: channel-leg self-guard was refuted (silent-channel escape) → spacing on every audible-asserting send + channel-agnostic zero-records + post-toggle importance probe; token leg gains PID/trigger/no-second-startup bindings + delete-then-poll probe semantics; permission leg gains the background-post-attempt evidence requirement, `user-fixed` flag, HOME-before-send, dump-after-custody, banner demoted to secondary; Doze gains both-boundary IDLE state capture + arm-scoped convergence; four campaign-finally mutation flags added; lease failure modes stated correctly (repair = fail-closed-silent) + post-observation grace before kills; literal gates fixed (both `assertionsAttempted` quoting forms; `--list-scenarios` = 10 rows); T1 wording corrected (only `:700-:703` is forbidden; new legs after `:915`; banned-literal checklist); TC-380-05's file pinned (`android_notification_payload_e2e_test.dart` exists) and "silently rejects" corrected to FormatException; guard wording corrected (one-shot capture; revoke-after-capture / restore-before-verify); dangling `:1520` anchor fixed to `run_test_gates.sh:1515-1519`.

## Live-environment corrections (2026-08-18)
- **The emulator is Android 17 / SDK 37, not SDK 36.** The plan's Device/Relay Proof Profile
  records both targets as SDK 36; measured today, `emulator-5554` is `ro.build.version.sdk=37`
  (release 17) and only the Pixel 6 sender `21071FDF600CSC` is SDK 36 (release 16). Every W3
  measurement below was therefore taken on SDK 37 — which is the platform the legs will actually
  run on, so the policy holds, but do not re-derive it against SDK 36.
- **The Pixel 6 sender is behind a secure keyguard** (`showing=true secure=true`). The campaign
  never drives UI on the sender — it launches via `am start` and stages config through `run-as` —
  so this is not a blocker for this campaign, only for anything that needs on-screen input there.
- **Relay v1.8.0 verified by symbol probe, not the banner.** `/usr/local/bin/relay-server`
  (sha256 `a964fee7…`, deployed 2026-08-16 22:09) contains
  `outcome=success attempt=%d total_attempts=%d` and `outcome=success fallback=strict`, and ZERO
  occurrences of the deleted `Notification sent to %s (attempt %d/%d)` — so W0's grammar is
  matched against the binary actually serving production, and a real journal line reads verbatim
  `2026/08/18 12:30:21 [PUSH] outcome=success attempt=1 total_attempts=3`.

## W3 Fingerprint Probe — RESULT (2026-08-18, `emulator-5554`, Android 17 / SDK 37)

Run before authoring TC-380-07/08, as the plan requires. Proxy package
`com.mknoon.sims.groupmedia269` (an installed sims build carrying the identical
`mknoon_messages` importance-4 / `mknoon_messages_silent` importance-2 channel
pair; the campaign package itself was not installed, and the question is OS
behaviour, not app behaviour).

| Cycle | Fingerprint vs baseline | Drifting bytes |
|---|---|---|
| `pm revoke` + `pm set-permission-flags … user-fixed` | DIFFERS | header `importance=DEFAULT userSet=false` -> `importance=NONE userSet=true` |
| … then `pm clear-permission-flags … user-fixed` + `pm grant` | **IDENTICAL** | none — restored byte for byte |
| Settings channel toggle OFF | DIFFERS | `mImportance=4 -> 0`, `mUserLockedFields=0 -> 4` |
| … then toggle back ON | DIFFERS | `mImportance` restored to 4; **`mUserLockedFields=4` is permanent** |

**Policy chosen: PRIMARY (redaction), scoped to exactly one token.**
`mUserLockedFields=<digits>` is masked alongside the pre-existing
`mLastNotificationUpdateTimeMs` mask. `mImportance` STAYS hashed, so a leg that
fails to re-enable the channel still reds `_verifyExactNotificationOsState`.
The permission leg needs no redaction at all, provided the flag is cleared as
well as the grant restored — which `_restorePostNotifications` does.

`pm set-permission-flags … user-fixed` and its `clear-permission-flags` inverse
both work (`flags=[ USER_FIXED|…]` observed and cleared), settling
unresolved (c). `dumpsys deviceidle force-idle deep` -> `get deep` == `IDLE`,
`unforce` + `dumpsys battery reset` -> `ACTIVE`, all verified live on the same
emulator. The Settings channel deep link resolves and its master toggle is
`android:id/switch_widget` (every secondary row on that screen uses the
distinct `com.android.settings:id/switchWidget`), verified by driving it OFF
and back ON.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-18 | Causal REDs | criteria test, support test, e2e test | 3 REDs recorded | (1) validator accepted channel-free b12 artifacts AND validated no Android evidence keys (4 rows red); (2) `relayJournalContainsAndroidProviderSend` FALSE for a v1.8.0 `outcome=success` journal and TRUE for the deleted literal; (3) `notification_delete_push_token` not allow-listed | proceed | W0 |
| 2026-08-18 | W0 | support + support test + campaign | `flutter test …support_test.dart` 15/15 | helper re-derived to the v1.8.0 grammar; accepts BOTH `inbox.go:626` (`attempt=/total_attempts=`) and `inbox.go:664` (`fallback=strict`); recipient binding dropped, `--since sentAt` scoping now pinned by its own source-freeze row | done | W1 |
| 2026-08-18 | W3 probe | live `emulator-5554` | see table above | PRIMARY redaction policy, one token (`mUserLockedFields`) | done | W1/W2 |
| 2026-08-18 | W1 (G12) | device_criteria, criteria test, campaign | `flutter test …notification_tap_device_criteria_test.dart` 16/16 | required-EVIDENCE validation for Android scenarios; b12 warm/cold checks + measured `warmAlertChannel`/`coldAlertChannel`; >=31 s tone spacing on every audible-asserting send; 3 s post-observation grace before every kill | done | W2 |
| 2026-08-18 | TC-380-05 | protocol, e2e action, e2e test | `flutter test …android_notification_payload_e2e_test.dart` 14/14 | `notification_delete_push_token` = deleteToken + bounded different-hash poll; receipt carries hash PREFIXES only; a stale unrotated read is polled past; no-token fails closed WITHOUT mutating the provider | done | W2 |
| 2026-08-18 | W2 (G7) | campaign | `flutter analyze` clean | 4 legs after `:915` + 4 tracked finally flags (`_permissionRevoked`, `_channelToggledOff`, `_dozeForced`, `_tokenRotationInFlight`) with restores ordered before `appStateGuard.restoreAll` | done | registration |
| 2026-08-18 | Registration | catalog, ids, requirements, artifacts list, counts, adapter sh, critical_features | adapter sh PASS with the 9-id census; `--list-scenarios` = 10 rows | all 6 id surfaces carry 9 ids in declaration order; both `assertionsAttempted` literals 5->9 | done | gates |
| 2026-08-18 | Gates | — | 94 focused host tests PASS; 25 graph-affected dependents PASS; completeness-check PASS (1468/1468); discovery exit 0; adapter sh PASS | parsers additionally validated against REAL `emulator-5554` dumps (switch node at the measured coordinates, importance 4->0->4, fingerprint policy holds on real bytes) | device closure BLOCKED: no FCM service-account credentials, no `MKNOON_RELAY_ADDRESSES`, no stamped `android.production_fcm` APK in this environment | device run when credentials + APK exist |

### Execution deviations from the plan (all deliberate, none weakening)
- **Post-observation grace placement.** The plan asks for a 2-5 s grace "before `_terminateReceiver` at `:700-701`", but `:700-:703` is the frozen T1 adjacency trio the same plan declares a hard no-insert zone. Resolved by putting the 3 s grace at the TOP of `_terminateReceiver()` — a superset of every kill that can follow a card observation — leaving T1 byte-intact.
- **Cold-leg channel dump** sits in the plan's stated `post-:709 pre-:726` window (after the airplane-mode wait and PID check), not next to the kill, for the same reason.
- **W0 grammar covers two lines, not one.** The plan named `inbox.go:626`; the relay also emits `[PUSH] outcome=success fallback=strict` at `:664` on the payload-too-large path, which is equally a provider acceptance. Matching only `:626` would hang the campaign on that path.
- **"unread" is not separately asserted** in the permission/channel legs. No probe surface exposes unread state and the plan scopes exactly ONE new probe action, so custody is proven as staged-envelope + post-restart drain convergence (`messageCount == 1`, `pendingRelayEntries == 0`). The checks are named `g7.*_custody_preserved`, which is what they measure.
- **No banner probe.** The plan already demoted the settings-banner node to secondary evidence; it is not implemented at all, so nothing claims it. Primary evidence is the typed `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` flow record plus the background-receipt requirement.
- **Doze arm typing** is carried as a value-constrained evidence key (`dozeDisposition` in {`delivered_during_idle`, `deferred_until_maintenance`}) rather than an either-or check, because the validator's check model cannot express OR. Both arms still require `g7.doze_forced_idle_proven` and BOTH raw idle state strings.
- **`PUSH_REGISTER_TOKEN_REFRESH_EVENT` carries no `trigger` key** (its details map is literally `{}`, `push_registration_coordinator.dart:66-70`). The `trigger=token_refresh` binding is asserted on the following `PUSH_REGISTER_COORDINATOR_SUCCESS`, which is what the plan's row actually says.
- **Gate literal correction.** `grep -c 'b12.warm_audible_channel' tool/sims/device_criteria.dart` returns **1**, not the >=2 the plan predicted: the plan's own TC-380-01 names the evidence key `warmAlertChannel`, so the check name and the evidence key are different strings. Intent-preserving replacement: `grep -c 'b12.warm_audible_channel'` == 1 AND `grep -c 'warmAlertChannel'` == 1 (same for the cold pair).
- **Hardening beyond the plan:** the validator additionally enforces two relational facts for the token leg (PID before == PID after, token hash before != after), so a hand-written artifact cannot claim a same-process rotation it did not perform.

### Adversarial review of the implementation (4 dimensions, 18 agents) — findings applied
Four confirmed defects were found in the first-pass implementation and fixed; the rest were refuted against source.

1. **Required evidence keys written as literals (major, CONFIRMED twice independently).** Six G7 keys (`permissionDeniedBackgroundAttemptEvent`, `permissionDeniedHealthEvent`, `permissionDeniedCardCount`, `tokenRefreshEvent`, `tokenRefreshSuccessTrigger`, `channelDisabledCardCount`) were constants, so deleting the capture still produced a validating artifact — W1's own defect class, reproduced one layer up. Fixed: `_requireNoCardForMarker` and `_requirePostAttempt` now RETURN their measurements, the health event is read off the parsed device record (`denied.first.event`), and the token-refresh event/trigger are read off the observed flow records. A census over all **31** required evidence keys now shows zero literals, and deleting a capture is a compile error rather than a silent pass.
2. **The "no post" gate was vacuous (major, CONFIRMED).** `PUSH_BACKGROUND_MESSAGE_RECEIVED` is the background handler's FIRST statement — upstream of staging, the display-eligibility gate, and every suppression return — so a wake that stood down (likely here, since the backgrounded receiver is still P2P-connected and the live listener can claim the event) satisfied it while posting nothing. Fixed with a UNION post-attempt predicate over the two real post-attempt markers, `NOTIFICATION_SHOWN` (`flutter_notification_service.dart:473-492`) and `PUSH_BACKGROUND_NOTIFICATION_SHOWN` (`background_message_handler.dart:1529-1543`), both of which fire even when the OS then drops the card. The zero-card census also became a sustained 8 s observation rather than one instantaneous sample.
3. **`_channelToggledOff` set after the mutation (minor, CONFIRMED).** `_setAudibleChannelEnabled` is a non-atomic UI drive with two post-mutation throw paths, so a flake could leave `mknoon_messages` blocked on the shared emulator with the finally repair skipped. Fixed by setting the flag before the mutation (and the same ordering applied to `_permissionRevoked`).
4. **Doze deferred arm accepted a woken device (major).** Fixed before the review completed: an `ACTIVE` observation is now a typed inconclusive red in the leg and rejected by the validator (`dozeStateAtObservation` constrained to `IDLE`/`IDLE_MAINTENANCE`).

Refuted: the W0 recipient-binding concerns (the old binding was already dead, and the leg order makes the claimed cross-traffic false-pass unreachable), the rotation-probe deadline arithmetic, and the `grep -c >= 2` count (inert — see the gate-literal correction above).

### Plan premise refuted on hardware
The plan's **Refuted-findings** list records "`pm revoke` can straddle a running probe — revoke kills the process; revoke -> relaunch -> assert". Measured on `emulator-5554` (Android 17 / SDK 37): revoking `POST_NOTIFICATIONS` does **NOT** kill the app process — the pid was unchanged across the revoke and still unchanged 5 s later. A leg written to that premise would have hung on a 30 s wait-for-death every run. The leg now terminates the receiver itself before relaunching, which preserves the plan's causal intent (the relaunch is what makes the coordinator re-evaluate permission and emit its typed denied record) without depending on an OS kill that does not happen.

### Device execution (2026-08-18) — wrapper written, campaign run, 5 defects found by running it

`docker-ws/run_payload_campaign_380.sh` now exists (the missing repo-resident wrapper; the
container->Mac bridge drops env vars and refuses `bash -c`, so a wrapper is the only way to get
`MKNOON_RELAY_ADDRESSES` / `FIREBASE_SERVICE_ACCOUNT` / the device ids to the sims planner).
Closure command: `/claude-host-bin/host-run bash docker-ws/run_payload_campaign_380.sh`.

The campaign had **never been run end-to-end on device before** (plan 378 recorded "device leg not
run"). Running it surfaced five real defects, each fixed with device evidence:

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | `_launch` fails on a cold first launch of a freshly installed build | `am start -W` returned `Status: timeout WaitTime: 10433` while pid 17690 was alive and `topResumedActivity == com.mknoon.app/.MainActivity`; a second call returned `Status: ok` | bounded 4x retry in `_launch`; the exact `Status: ok` predicate and the `result.exitCode != 0` literal are unchanged, so the frozen adapter contract still passes |
| 2 | The `run()` finally MASKED every leg failure | a throw from `finally` replaces the in-flight exception, so a leg failure plus a restoration failure surfaced only "restoration failed at campaign-notifications" | capture the leg error and report BOTH; this alone turned an opaque run into a diagnosable one |
| 3 | A6 fails on libp2p dial backoff after the airplane-mode restore | `P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR {"errorMessage":"empty scan reached 0/1 relays: connect to relay: failed to dial ... dial backoff"}` -> `pending['ok'] != true` -> `StateError('relay replay/ack did not remain exactly once')` | in `_observeReplayBeforeAck`, a NOT-OK pending response is a transport state and retries inside the action budget; a duplicate or a non-empty pending list stays immediately fatal |
| 4 | A6 posts a real card it never owns | `NOTIFICATION_SHOWN {"durable":true,"producer":"direct_message","disposition":"osPosted","silent":false}` — the next leg's empty-slate precondition and the finally's cleanup both failed on a card A6 created | A6 registers its marker in `_campaignNotificationBodies` and cleans up after itself; observing a card during cleanup also stamps the tone clock, because that card consumed the conversation's reservation |
| 5 | **tc_b13's discriminator union was unsatisfiable on real hardware** | the losing path emitted `NOTIFICATION_LEGACY_CLAIM_RECONCILE {"reason":"message_event_already_claimed"}` x3 and `NOTIFICATION_SUPPRESSED` x0 | the union now accepts the reconcile event names; the REASON allow-list is unchanged, so an unexplained stand-down still fails |

**Defect 5 refutes a documented premise.** `android_notification_payload_campaign.dart` asserted the
reconcile variants "are deliberately absent: they require a `durableEffectContext`, which the 1:1
live listener never passes". Device evidence says otherwise — the 1:1 direct path runs durable in
the shipped build (`NOTIFICATION_SHOWN {"durable":true,"producer":"direct_message"}`) and the
reconcile event is exactly how its losing side records the stand-down. Host rows now pin both the
widened event set and the unchanged reason set.

**Best run reached assertion 5 of 9** (run 4): A6, B11, **B12 warm and B12 cold all PASSED on
device — including this plan's new measured `warmAlertChannel` / `coldAlertChannel` ==
`mknoon_messages` evidence**, which is G12's closure evidence for those legs. It then failed at
B13 on defect 5, now fixed.

**Remaining blocker is transport flake in pre-existing legs, not this plan's code.** Later runs
failed non-deterministically and progressively earlier — cold-leg send (`CHAT_MSG_SEND_FAILED
reason=peer_not_found`, with 161 `failed to dial` / 72 `no good addresses` on the sender) and then
contact convergence — while the relay stayed healthy throughout (active, `conns=3`, four
`[PUSH] outcome=success` during the runs). The four new G7 legs (6-9) have therefore still never
executed; they remain unproven on device.

### Device run — CLOSED (2026-08-19, run 4: 9 of 9, exit 0)

`PASS notifications.android_payload_campaign assertions=9`, `Builds: actual=1, cacheHits=0`,
`releaseEligible=false` only because the run was filtered (`--only`) — the assessment's own
wording, not a leg failure. Artifacts in
`build/sims/proofs/notifications.android_payload_campaign/`.

| # | Scenario | Device result | Measured evidence |
|---|---|---|---|
| 1 | `tc_a6_replay_before_ack_custody` | PASS | staged->ack order, `ackedEntries=1`, `pendingAfterSecondDrain=0` |
| 2 | `tc_b11_payload_persist_pre_drain` | PASS | staged envelope visible pre-drain, no duplicate after |
| 3 | `payload_fast_path_android_receiver` (B12 warm) | PASS | **`warmAlertChannel == mknoon_messages`** |
| 4 | `payload_fast_path_cold_kill` (B12 cold) | PASS | **`coldAlertChannel == mknoon_messages`**, pid empty before tap, new pid after |
| 5 | `tc_b13_dual_path_single_alert` | PASS | `alertSilent=false` (log-measured), 1 card, `NOTIFICATION_LEGACY_CLAIM_RECONCILE:message_event_already_claimed` |
| 6 | `tc_g7_permission_denied` | PASS | `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` x1, 0 cards, custody 1 msg, regrant card audible |
| 7 | `tc_g7_token_refresh_mid_session` | PASS | pid `6608 == 6608`, token hash `771a58fddbaf -> f25bd9a03827`, 0 extra startup attempts |
| 8 | `tc_g7_channel_disabled` | PASS | both channels at importance 0, 0 cards, custody 1 msg, restored to 4 and 2 |
| 9 | `tc_g7_doze_delivery` | PASS | `IDLE` at both boundaries, `delivered_during_idle`, 1 card, 1 msg |

**G12 is closed at the device tier** (rows 3-4) and **G7 is closed** (rows 6-9; OEM restrictions
stay the typed N/A this plan always scoped them as). Rows 3-4 double as the device evidence Plan
383 deferred here (`383:71`, `383:78`).

## Execution Findings (2026-08-19 — device closure session)

- **F13-RESOLVED — the leg-6 non-determinism had a measured cause, now removed by construction.**
  The leg took a log cursor, relaunched the app, and read
  `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` **60-120 s later** through
  `logcat -d -t <cursor>`. Measured on `emulator-5554`: the `main` ring is **2 MiB** (`logcat -g`)
  while a busy campaign minute emits **~1.6 MB**, so the event can rotate out before the read — and
  a rotated window is EMPTY, which is indistinguishable from "the app never emitted it". That is a
  silent wrong answer, not an error, and it is why the leg could pass and fail on the identical APK.
  Three changes: (a) `_startDeviceLogStream()` starts a LIVE reader before any leg and lets **adb
  itself** write `<proofs>/device-logcat.txt` through a shell redirect, with cursors becoming byte
  offsets into that file — nothing can rotate, and a failing run now leaves its log behind;
  (b) the leg re-checks the OS after the relaunch and raises `_Blocked('deviceOsState')` if the
  permission came back, so an environment miss can never be read as a regression; (c) the typed
  record is awaited immediately after the relaunch instead of after the send/census.
  Verified in run 7: 10.9 MB / 91,528 lines captured, and all three
  `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED` events are present in the stream.
  **Honest limit:** the original failure was not reproduced-then-fixed; a measured unsoundness was
  removed. One green run is consistent with determinism, not proof of it.
  *(A first attempt piped `process.stdout` into `File.openWrite()`. That is WRONG:
  `IOSink.flush()` sets `_isBound`, so every cursor read raced the stdout listener and threw
  `Bad state: StreamSink is bound to a stream` — it killed run 5 at assertion 1. Letting the OS own
  the write removes the sink, the flush and the race together.)*
- **F15 — leg 6 is green but does NOT exercise Plan 385's fix on this image.** Run 7's stream shows
  `PUSH_PERMISSION_REQUEST_RESULT` 8x `{"status":"authorized","granted":true,"osEnabled":true}` and
  3x `{"status":"denied","granted":false}`, with **zero** `PUSH_PERMISSION_OS_STATE_OVERRIDE` and
  **zero** `PUSH_PERMISSION_OS_CHECK_FAILED`. So under `pm revoke` + `user-fixed`, firebase_messaging
  reports denied HONESTLY here and the NM-side override never runs — confirming the "stale
  permission cache" arm of Plan 385's unresolved finding and refuting the auto-grant arm, and
  matching 385's own F3. Consequence: this leg passes at HEAD too and is not a regression detector
  for 385, whose device path remains only statically proven (385 F4). Constructing the real
  divergence needs `appops set <pkg> POST_NOTIFICATION ignore` — permission granted, NotificationManager
  off — which is a separate leg, not a change to this one.
- **F16 — the silent-channel leak is INTERMITTENT and was not reproduced in run 7.** The
  channel-disabled leg now blocks only the audible channel and requires
  `mknoon_messages_silent` to stay OPEN (`channelDisabledSilentImportance == 2`) so a leak stays
  observable; run 7 measured `channelDisabledCardCount: 0`, i.e. no card escaped. Combined with the
  2026-08-18 observation of a surviving silent card, the leak depends on the same tone/reconcile
  race as B13 rather than being deterministic. The leg is currently GREEN, which means it is not
  yet a reliable detector — do NOT read this pass as "the leak is fixed".


- **F13 — `tc_g7_permission_denied` is NOT deterministic; the 9/9 run is one sample, not closure.**
  Run 4 (00:44-00:54) passed all nine. A concurrent session's run at **01:34:45** consumed the same
  cached artifact — `artifactDigests.android.production_fcm = 1e0de3238478…`, `actualBuilds: 0`,
  `hits: 1`, i.e. the identical APK — against the identical working tree (the 385 seam is still
  present, grep-verified) and the same pinned device pair, and FAILED at assertion 6 with the
  ORIGINAL bug-385 signature. Same binary, same tree, same devices, opposite verdicts. This is
  consistent with Plan 385's own F3, which recorded that on this SDK-37 image `pm revoke` +
  `user-fixed` sometimes yields an honest `denied` from firebase_messaging and sometimes does not —
  i.e. the leg's PRECONDITION is environment-dependent, so it can fail for a reason unrelated to the
  product. Not diagnosable after the fact: that run's logs were not captured and the campaign
  uninstalls the app on exit. Next step is a leg-level precondition assertion (prove the OS really
  is in the denied state at the moment the coordinator re-evaluates, and fail as BLOCKED rather than
  as a product failure when it is not) — plus `appops POST_NOTIFICATION ignore` to CONSTRUCT the
  divergence deterministically instead of relying on `pm revoke` behaving.
- **F14 — sims proof artifacts are a single shared slot and concurrent runs clobber them.** The
  01:34 run's startup `_removeScenarioArtifacts()` deleted all NINE of run 4's per-scenario JSONs,
  and `build/sims/latest/report.json` — one file, not per-run — now records that run's FAIL instead
  of run 4's PASS. What survives of run 4 is its campaign-level manifest
  (`notifications.android_payload_campaign-1787100886178923-48966.json`): `status: "passed"`, all
  nine `scenarioIds`, the prepared-APK sha, and a **SHA-256 for each of the nine deleted artifacts**
  — so the run stays attested and hashed even though the payloads are gone, and the per-leg evidence
  values were transcribed into this plan and the PRD map before deletion. Two operational rules
  follow: copy proof artifacts OUT of `build/sims/proofs/` immediately after a run worth citing, and
  do not run this capability from two sessions against one checkout — they also share the two phones.


Plan 385 landed and is host-green (8/8 focused, 21/21 preservation sentinels), which unblocked
leg 6. Reaching a clean 9/9 then required repairing **three harness oracles**. None of the three
was a product defect, and none was found by reasoning — each came from an instrumented device log.

- **F8 — A6's relay pending-list assertion was a single-sample race (FIXED).**
  `_observeReplayBeforeAck` threw `StateError('relay replay/ack did not remain exactly once')` the
  instant `callP2PInboxRetrievePending` returned a non-empty list. The relay re-serves an entry
  until its ACK purges it, so a sample taken inside a replay window reads non-empty on a
  *correct* delivery — measured: two `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS
  {requested:1,acked:1}` 0.8 s apart against ONE `INBOX_STAGED_CHAT_COMMITTED`. Its sibling
  `_observeDrainConvergence:243-250` had always treated the same field as a convergence input, not
  a verdict. Now polls; duplicate COMMITS still fail closed on the first sample. Host rows added
  (the replay probe had none), mutation-verified: restoring the immediate throw reds exactly the
  new retry row.
- **F9 — a `dumpsys notification` channel read is not a valid audible-alert oracle (FIXED).**
  When both delivery paths reach one message the loser reconciles the claim and publishes a silent
  SAME-ID in-place update (`local_notification_support.dart:47-49`), which MOVES the record onto
  `mknoon_messages_silent`. Measured twice, identically: `PUSH_BACKGROUND_NOTIFICATION_SHOWN` ->
  2.5 s -> `NOTIFICATION_LEGACY_CLAIM_RECONCILE` -> 140 ms -> `NOTIFICATION_SHOWN {"silent":true}`.
  That is B13 *passing* — one alert, one card — but no dumpsys poll is fast enough to sample the
  ~2.6 s audible window, so the leg reported correct behaviour as a silent alert. This is the same
  reading Plan 385's F3 wrote off as "device-state flake": it is not flake, it is a race the
  harness loses whenever the loser reconciles instead of standing down.
  Two-part fix: (a) `_waitForNotificationObservation` returns the channels from the SAME dumpsys
  read that first saw the card, and the four remaining channel assertions consume that instead of
  a later dump; (b) B13's verdict moved off dumpsys entirely onto the cursor-scoped log.
  B12 cold deliberately keeps the fresh-dump read — its receiver process is proven dead two
  statements earlier, so nothing can reconcile — and its observe-then-kill adjacency is frozen.
- **F10 — the background isolate never reported whether its post ALERTED (FIXED, 1 production
  line).** `PUSH_BACKGROUND_NOTIFICATION_SHOWN` carried no `silent` flag while the live path's
  `NOTIFICATION_SHOWN` always has — and the background isolate is the path that WINS whenever the
  app is merely backgrounded, so the winning alert was structurally unprovable. Added
  `'silent': ?publishedSilently` to both detail shapes, mirroring
  `flutter_notification_service.dart:406-415`. Deliberately `bool?` via a null-aware element: an
  event emitted without any native show reports NO flag rather than falsely reading as audible,
  and the campaign requires the key to be present AND false. Census-checked first — every existing
  consumer keys off the event NAME or the existing `messageId`/`payload` keys, so the addition is
  non-breaking. 81/81 handler tests plus all four graph-named dependents stayed green.
- **F11 — `tc_g7_channel_disabled` now blocks BOTH message channels (leg redesign, and a real
  product finding).** The leg blocked only `mknoon_messages`, and a card came through on
  `mknoon_messages_silent`. The app selects between its two channels from tone state alone and has
  **no channel read-back anywhere**, so it cannot know either is blocked — meaning *disabling the
  "Messages" channel does not stop message notifications*. That is a genuine user-visible finding,
  and it is exactly the deferred product decision this plan already records ("Do not build
  channel-disabled detection/surfacing"); it is recorded here as that decision's concrete device
  evidence. It is NOT what this matrix row measures, and "the OS forbids any notification" — the
  sentence the census failure prints — is only true once both are off. The leg now drives both
  toggles, probes both importances before the send (0/0) and after restore (4/2), and a source
  freeze pins the two-channel contract.
- **F12 — campaign diagnosability gap (worked around, not fixed).** A failing installed-action
  probe surfaces only as `errorType=StateError` in the sims verdict, and the campaign UNINSTALLS
  the app on exit, deleting `app_flutter/intro_e2e_result.json` before it can be read. The receipt
  is deliberately message-free (`android_notification_payload_e2e_test.dart:148` pins that as a
  privacy invariant), so the message cannot simply be added. Diagnosing F8 cost two runs for this
  reason. `docker-ws/scrape_e2e_receipts_380.sh` snapshots the receipt live during a run; a
  durable fix would be distinct exception TYPES per assertion so `errorType` discriminates.
- **Residual (accepted, not observed):** B12 warm and the three G7 control cards still take their
  audible verdict from a first-observation channel read. In both instrumented runs the silent
  re-post occurred ONLY at B13 — B11 and B12 warm got the reconcile with no silent re-post,
  because those legs stop the node or kill the app so the live path cannot publish. Converting
  them would trade `warmAlertChannel == mknoon_messages`, G12's stated closure artifact and now
  twice-proven on hardware, for a weaker key. If one ever flakes, the failure text names the
  mechanism and `androidNotificationFirstPostAttemptSilent` is already there to switch to.

**Re-run command** (Pixel must be UNLOCKED — a locked sender throttles background networking and
the campaign fails in the transport layer at varying points):

```bash
/claude-host-bin/host-run bash docker-ws/run_payload_campaign_380.sh
```

<!-- superseded snapshot below, kept for provenance -->

### Device run — superseded snapshot (2026-08-18, best run reached assertion 6 of 9)

| # | Scenario | Device result |
|---|---|---|
| 1 | `tc_a6_replay_before_ack_custody` | PASS |
| 2 | `tc_b11_payload_persist_pre_drain` | PASS |
| 3 | `payload_fast_path_android_receiver` (B12 warm) | **PASS — `warmAlertChannel == mknoon_messages` measured** |
| 4 | `payload_fast_path_cold_kill` (B12 cold) | **PASS — `coldAlertChannel == mknoon_messages` measured** |
| 5 | `tc_b13_dual_path_single_alert` | PASS (first device evidence ever) |
| 6 | `tc_g7_permission_denied` | **RED — production bug, see [385](385-push-permission-gate-false-authorized-bug.md)** |
| 7 | `tc_g7_token_refresh_mid_session` | not reached |
| 8 | `tc_g7_channel_disabled` | not reached |
| 9 | `tc_g7_doze_delivery` | not reached |

**G12 is closed at the device tier.** Rows 3 and 4 are this plan's reason for existing and
they now carry measured audible-channel evidence from real hardware. They double as the
device evidence Plan 383 deferred here (`383:71`, `383:78`).

**G7 is NOT closed and this plan must stay open.** `tc_g7_permission_denied` fails because
the app's push-permission gate returns `authorized` while the OS has POST_NOTIFICATIONS
revoked, so the coordinator's entire denied branch — durable health record, diagnostic,
`PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED`, early return — is unreachable. Owner
decision: this is a product defect, filed as plan 385; the leg is deliberately NOT
narrowed and stays red until 385 lands. Legs 7-9 are queued behind it and remain
unproven.

**Re-run command** (Pixel must be UNLOCKED — a locked sender throttles background
networking and the campaign fails in the transport layer at varying points):

```bash
/claude-host-bin/host-run bash docker-ws/run_payload_campaign_380.sh
```

### Pre-existing reds (NOT caused by this plan)
`run_test_gates.sh sims-contracts` aborts at its 4th contract. Three contracts are red on a clean HEAD tree, all untouched by this change:
- `dtr13_profile_entrypoint_preservation_contract_test.sh` — DTR13-AUTH-01 byte lock expects `522bc158…` for `lib/smoke_test_main.dart`; the file is unmodified at HEAD and hashes `c99e6212…`. The pin was not updated when `87f0f7ba0` last changed that file.
- `intro_accept_notification_sims_adapter_contract_test.sh` — source assertion `'final output = await _adbShell' in launch` no longer matches `run_intro_accept_notification_android.dart::_launchAll()`; that file is clean at HEAD.
- `project_memory_recall_contract_test.sh` — untracked plan-381 work in progress.

Every other sims contract passes. (`host_test_gate_batch_contract_test.sh` failed once during execution because a temporary probe test file existed while the batch enumerated Dart paths; it PASSES on the clean tree — a self-inflicted transient, recorded here so the log is not misread.)
