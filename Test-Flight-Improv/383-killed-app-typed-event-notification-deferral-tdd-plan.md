# 383 - Killed-App Typed-Event Notification Deferral (G17)

Status: executed — host closure GREEN, device semantic PROVEN (2 fresh captures); adapter PASS blocked by a Plan-379-scope predicate (see Execution Progress)
Type: Bug
Spec: free-text intent (no formal spec) — G17 register entry, `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md` §4.2; PRD §6 row 6 + §6.5/AC-13 (2026-08-18 addendum)
Classification: implementation-ready
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-18 | Evidence Collector | `background_message_handler.dart` (:622-:1129, :1340-:1450, :2018-:2100, :2522+), `push_decrypt_preview.dart` (:577-:1120), `background_message_handler_test.dart` (:620-:905), writers census across `lib/`, `git log -S`, recall.py, adb device probes | Spike resolved at planning time (see Spike Matrix): the hole is BROAD — all four authenticated typed kinds defer at a killed app; deferral is Plan-372-pinned seam behavior whose retry vehicle is default-off. Fix lane chosen: fall through into the existing non-durable typed show lane. | Emit contract |
| 2026-08-18 | Planner | tier-matrix, run_test_gates.sh (GROUP_TESTS declared :466, entry :679; 1 hit), critical_features.json (:892 `groups.muted_notification_campaign`) | 11-row contract (TC-383-03 later dropped at review → 10 rows); host rows all land in the already-registered `background_message_handler_test.dart`; device closure rides Plan 379's muted campaign (its unmuted pipeline-health control IS this defect's device gate) | /tdd-review |
| 2026-08-18 | Reviewer (2-worker adversarial audit, wf_04040dec) | bmh :1112-1360 full publish path, cancel/CAS paths, 379 adapter+capture+criteria, eligibility resolvers | **plan-fixes-required → applied same session** (see Reviewer Findings): core bet CONFIRMED sound; 5 contract-gaming escapes closed; TC-383-03 dropped as over-engineering; device gate honesty fixed; mute question resolved affirmatively | Execution |

## Problem And Evidence
- Behavior to improve: an Android user whose app process is killed/suspended receives **no OS notification** for a genuinely new authenticated typed event — 1:1 text, 1:1 reaction, group/announcement text, group/announcement reaction — until they spontaneously open the app. The FCM wake fires, the isolate runs, custody is staged, and presentation is silently deferred. Live user harm, not test debt.
- Impact: violates PRD §6 row 6 (suspended/terminated ⇒ "render locally or leave the generic fallback" — on Android data-only pushes no OS-rendered generic exists, so "leave the fallback" leaves **nothing**) and AC-13/PRD §6.5 (the reacted-to author must be alerted). Regression window starts `650f8cbe6` (Plan 372, 2026-08-16). Blocks Plan 379 TC-379-06, whose unmuted pipeline-health control correctly refuses to pass.
- Confirmed root cause (survived refute): `firebaseMessagingBackgroundHandler` durable-effect gate at `lib/features/push/application/background_message_handler.dart:1035-1041` — on Android, when `resolvedEventIdentity != null && contentMetadata != null && routeTarget.kind ∈ {conversation, group}`, presentation authority must come from a **pre-staged ready display-outbox row** (`:2043-2060` direct, `:2084+` group). The background isolate only reads those rows; the writers are the running app only (`production_canonical_inbox_projection_composition.dart`, `production_application_bootstrap.dart`; handler census: `dbLoad*` only, zero `dbStage*`). On null authority the handler emits `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` and returns **without showing** (`:1052-1066`; sibling silent returns: generation-invalid `:1071-1076`, authority-read-failed `:1098-1110`). The intended retry vehicle is default-off and uninjected: `recoveryWorkEnabled: false` (`lib/core/notifications/canonical_runtime_lease.dart:471,504`; `lib/core/notifications/dropped_push_recovery_bridge.dart:122,159`).
- Scope refinement over the G17 register entry: the hole covers exactly the **authenticated** typed path. `resolvedEventIdentity` is minted by the decrypt preview for all four kinds (`lib/features/push/application/push_decrypt_preview.dart:577,701,823,848,1023-1029`). Typed payloads **without** an authenticated inner identity already take the existing non-durable show lane with post-show fences (`background_message_handler.dart:1353-1426` group retire/read validator; `:1427+` direct validator) and DO alert. Decrypt failure alerts generically. The production rich-payload common case is the hole.
- Existing coverage: the deferral **silence** is pinned as intended at `test/features/push/application/background_message_handler_test.dart:773-823` ("authenticated durable-authority deferral releases provisional owners for retry" — expects zero `show` calls); the staged-ready durable path is pinned at `:620-771` (show + ledger + read-only SQL custody `:750-754`). Device: G17 measured live 2026-08-17 (Plan 379 runs 9-10, stamped `android.production_fcm`, relay v1.8.0, relay flags verified NOT the cause).
- Missing coverage: no test anywhere asserts that a killed-app typed event **alerts**. b12 legs prove staging + eventual visibility only, predate v1.8.0, and are G16-blocked for fresh runs; the sound smoke runs a harness build, not the FCM path.
- Refuted findings (do NOT re-introduce):
  - "Relay rollout flags cause the missing cards" — refuted live 2026-08-17 (`GROUP_REACTION_PUSH_ENABLED=true`, `DIRECT_REACTION_PUSH_ENABLED=true`, `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true`).
  - "All killed-app notifications are dead" — refuted: no-identity typed payloads and decrypt-failure generics still show (`:1353`/`:1427` lanes are live).
  - "Pin `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reason `muted` on the device FCM leg" — refuted by Plan 379 review (production does not emit it there); muted assertions stay behavioral (zero cards), never event-name-pinned on device.
  - "The background isolate should stage display-outbox rows" — rejected as the fix lane: `:750-754` pins read-only background SQL custody (Plan 372 receipt-bound); making the isolate a writer contradicts a frozen invariant when a cheaper lane exists.
  - Review hypothesis (2026-08-18): "the fallback card's `createConversationNotificationGeneration()` generation lets it survive a later read/open — stale-card leak (AC-08)" — REFUTED: every cancel path captures the generation from the registry itself and CAS-cancels, never ledger-derived (`flutter_notification_service.dart:186-217` tap, `direct_notification_read_projector.dart:43-53`, `group_notification_read_projector.dart:367-383`, `direct_notification_canonical_reconciler.dart:66-88`; CAS predicate `durable_conversation_notification_id_registry.dart:398-399`).
  - Review hypothesis (2026-08-18): "the `:2324` `resolvedEventIdentity?.origin` branch diverges under the new (identity non-null, context null) state" — REFUTED: single call site, inside `_stageResolvedPushEnvelopeIfNeeded` (`:2319-2344`), runs at `:764-776` BEFORE the durable block; it cannot observe `durableEffectContext`.
- Unresolved findings: none remaining. The planning-time open question (does mute guard the fallback lane?) was resolved AFFIRMATIVELY by the independent review (2026-08-18): mute is enforced twice UPSTREAM of the durable block — the display-eligibility gate `:680-705` via per-type local-state resolvers `:2522-2583` (group message → `evaluateGroupNotificationDisplayPolicy` with `is_muted` from `:3822`, suppressed reason `'muted'` at `group_notification_display_policy.dart:109-111`; group reaction → `evaluateGroupReactionNotificationDisplayPolicy` `:3357-3368` gated `:3432`; legacy group routes honor mute `:3890-3897`), and again at preview re-resolution `:751-763` (group resolver throws on ineligibility `:2650-2652`). Muted events never reach the fall-through seam; TC-383-06 stays as a cheap sentinel, not an open question.
- Affected production / test / gate files: `lib/features/push/application/background_message_handler.dart` (one seam: the three silent returns inside the durable block); `test/features/push/application/background_message_handler_test.dart` (new rows + the `:773` pin rewrite); no new files, no schema, no wire, no native, no campaign-file edits.

### Spike Matrix (run before the contract, per instruction — resolved at planning time)
| Leg (killed app, genuinely new event) | HEAD outcome | Evidence tier |
|---|---|---|
| 1:1 text | `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED`, zero cards | **Executed host pin** — `background_message_handler_test.dart:773-823` drives the real handler with `type: new_message` + authenticated identity + null authority and asserts zero `show` calls (green on HEAD) |
| 1:1 reaction | same | Seam identity — same gate `:1035-1041` (reaction kind `:1012-1013`), direct reaction resolver branch `:2043+`; no reaction-specific pin exists (TC-383-02 adds it) |
| Group/announcement text | same | Seam identity — `groupContentKind` `:807-813`, group resolver `:2084+` |
| Group/announcement reaction | same | **Live device measurement** 2026-08-17 (Plan 379 runs 9-10): 2× `PUSH_BACKGROUND_MESSAGE_RECEIVED`, zero suppression events, no card for the UNMUTED control group; diagnostic dump archived in the G17 register entry |

Why the four-leg device re-run collapsed into the above at planning time: (1) the 1:1 leg is already executed-and-green as a host pin against the real handler; (2) the remaining legs share the line-verified kind-agnostic gate; (3) the group-reaction leg was measured live 20h earlier on the same cached APK (`build/sims/cache/android.production_fcm/adb03fc…/artifact.apk`, built 2026-08-17T20:38Z); (4) a fresh device pass requires reinstalling + reseeding the pair (verified this session: neither device currently has `com.mknoon.app` installed — only P269 sims and `visibilityproof` debug builds) plus a full sender-E2E rebuild (not in cache), and would end red on exactly this defect (TC-379-06's control). Device confirmation therefore moved to the closure gate (TC-383-10), which runs post-fix with a freshly prepared build anyway. Branch decision per the spike framing: **(a) broad killed-app hole**, with the (c) nuance that the seam is Plan-372-intended but its retry vehicle is not live — so the fix is presentation-level fall-through, not PRD weakening and not a background staging writer.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: refreshed this session via `/claude-host-bin/host-run bash ./graphify-arch/refresh_arch_graph.sh --incremental` (marker was present; exit 0).
- Query / profile: `python3 graphify-arch/tdd_context.py query "group reaction notification recipient author GroupMessageListener handleIncomingReaction reaction recipient card" --profile general --budget 600` (session-earlier §6.5 grounding) + targeted source verification for this plan.
- Anchors: `firebaseMessagingBackgroundHandler` → `lib/features/push/application/background_message_handler.dart`; `resolveBackgroundDurableLocalNotificationEffectInDatabase` → same file `:2031+`; `BackgroundPushNotificationFallback.resolvedEventIdentity` → `push_decrypt_preview.dart`; display-outbox writers → `production_canonical_inbox_projection_composition.dart` / `production_application_bootstrap.dart`.
- Surfaced proof/gate files: `test/features/push/application/background_message_handler_test.dart` (GROUP_TESTS member, `run_test_gates.sh:466` array, 1 grep hit), `integration_test/scripts/run_group_muted_notification_android.dart` + `groups.muted_notification_campaign` (`tool/sims/critical_features.json:892`).
- Graph gaps that required raw source search: array membership/line-number censuses (path-string, no import edges), build-cache attestation JSON, adb/device state.
- Reuse rule: anchors are search starting points; every conclusion above carries current-source line evidence.

## Scope Contract And Guard
In scope:
- Route the three deferral variants inside the durable-effect block (authority-null `:1052`, generation-invalid `:1071`, authority-read-failed `:1098`) into the **existing** non-durable typed presentation lane: fall through with `durableEffectContext == null` and `contentMetadata` intact, so the standard claim/tone/dedupe show runs and the existing post-show fences (`:1353-1426` group, `:1427+` direct) validate/retire it. Event behavior per branch (review-corrected): authority-null and read-failed KEEP their `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` emissions and gain `presentation: 'nondurable_fallback'`; generation-invalid emits NOTHING on HEAD (`:1071-1076` has no flow event) and GAINS a new emission (`reason: 'generation_invalid'`, same presentation detail). The branches' `releaseProvisionalNotificationOwners` calls are REMOVED (the show path commits or the outer catch releases, `:1565-1619`) — TC-383-09 pins the commit.
- Rewrite the `:773-823` pin to the new intended semantics; add the contract rows below.

Must preserve:
- Durable staged-ready path byte-for-byte (show + ledger record + read-only SQL custody) → TC-383-07 (existing test `:620-771`).
- Muted-group total silence on every background path → TC-383-06 + existing muted host rows (`background_message_handler_test.dart:4683+`, `group_message_listener_test.dart:16483+`, `:17033+`) via the `groups` lane.
- Storage-deadline deferral semantics unchanged (`BackgroundStorageDeadlineExceeded` → `storage_deferred`, no show) → TC-383-11.
- Ledger writes only under real authority (no `durableEffectContext` ⇒ no ledger record) → asserted inside TC-383-01.
- One-audible-max under redelivery/dual-path → TC-383-08 (+ untouched b13 adapter contract).

Hard `Do not`:
- Do not make the background isolate a display-outbox writer (Plan 372 receipt-frozen read-only custody).
- Do not activate `recoveryWorkEnabled`/dropped-push recovery (owned by the N08 activation wave).
- Do not touch relay/Go, campaign capture files, the G16 grammar, or `Test-Flight-Improv/379-*` device files.
- Do not weaken PRD §6 row 6 or AC-13 wording (the fix makes the app match the PRD, not vice versa).
- Do not pin muted suppression to an internal event name on any device leg (refuted).

Deferred / accepted difference:
- 1:1 killed-app OS-boundary device evidence → owner **Plan 380** (`b12.cold_audible_channel`/`b12.warm_audible_channel` after its W0 grammar repair), because the seam is host-pinned here (TC-383-01/02) and Plan 380 already builds that exact device row; duplicating a two-device 1:1 killed lane in this plan fails implementation economy.
- Deadline-variant alerting (`storage_deferred` still presents nothing) → owner: dropped-push-recovery activation wave (N08/WP), because deadline-exceed signals storage liveness trouble where the recovery worker is the correct vehicle; TC-383-11 test-locks the asymmetry so it is not an untested assumption.
- iOS NSE killed-path sibling behavior → owner GAP-N12 consolidated iOS phase (adopted sequencing).
- G16 reaction-campaign provider grammar → remains unowned; this plan's device gate deliberately rides the G16-immune muted lane.
- Plan 379 full closure (muted lanes, G4) → Plan 379; this plan only unblocks its TC-379-06 control.

Dependencies:
- Downstream: Plan 379 TC-379-06 becomes runnable post-fix (its command doubles as TC-383-10). Plan 380's b12 rows gain their intended meaning post-fix.
- Upstream: none — no schema, no wire, no flag.

## Test Contract
| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-383-01 | Killed-app authenticated **1:1 text** with no staged row presents the non-durable fallback card: `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` still emitted with `presentation: 'nondurable_fallback'`; `PUSH_BACKGROUND_NOTIFICATION_SHOWN` present **without** a `durable: true` detail (review-corrected: the non-durable emission `:1514-1528` carries no `durable` key at all — a `durable:false` assertion cannot pass); the recorded `show` call is **not silent** (fresh tone state; kills an always-silent wrong impl); after the show the **notification-id registry holds content metadata** for the conversation (kills the metadata-nulling wrong impl that would flip autoCancel `:1121`, skip `replaceContent` `:1233-1241`, and skip the direct post-show validator `:1427-1431`); **no** ledger record; outbox row count unchanged (0) | `test/features/push/application/background_message_handler_test.dart::'authenticated durable-authority deferral presents the non-durable fallback card (direct message)'` | host / real handler + **real in-db resolver** `resolveBackgroundDurableLocalNotificationEffectInDatabase` over an **empty** `direct_notification_display_outbox` (sqflite_common_ffi; plain SQLite — no cipher claim) — production-reachable state, per the `:697` pattern; mock plugin channel records `show` with its details | causal RED (deferral returns at `:1066` before `show`; zero `show` calls on HEAD) → exactly one non-silent `show`, the event pair with stated details, registry content metadata present, no ledger record for the correlation | restore the `releaseProvisionalNotificationOwners + return` block at `:1063-1066` → red (zero shows) | `flutter test test/features/push/application/background_message_handler_test.dart`; AUTO (feature glob) + already in GROUP_TESTS (declared `run_test_gates.sh:466`, entry `:679`; grep count 1, unchanged) |
| TC-383-02 | Same for **1:1 reaction** (distinct direct resolver branch: reaction alias entry) — fallback copy is the reaction copy from the resolved preview | same file::`'…deferral presents the non-durable fallback card (direct reaction)'` | host / as TC-01 with `type: message_reaction` + `reaction_id`, empty outbox | causal RED (same mechanism) → one `show` + deferral event | same revert → red | same |
| TC-383-04 | Same for **group reaction** (the G17 headline; group resolver `:2084+`, group comparand lane). Fixture MUST carry `event_id` equal to the comparand's bounded `notificationTransitionId` — a `reaction_id`-only fixture mismatches the alias, flips the post-show switch to RETIRE (`:1357-1381`) and the card flash-cancels right after the show (review counterexample). Assert **no** `PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED` event after the show | same file::`'…deferral presents the non-durable fallback card (group reaction)'` | host / group route target, empty `group_notification_display_outbox`, real in-db resolver | causal RED (same mechanism) → one `show` + deferral event + no post-show retire | same revert → red | same |
| TC-383-05 | **Authority-read-failure** (`catch` at `:1098-1110`) and **generation-invalid** (`:1071-1076`) also present the fallback instead of returning silently. Read-failure keeps deferral `reason: authority_read_failed` + gains `presentation: 'nondurable_fallback'`. Generation-invalid emits **nothing on HEAD** (review-verified: no flow event in that branch) — the fix ADDS a new `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` emission (`reason: 'generation_invalid'`, same presentation detail) so the lane keeps the same-run event-pair discriminator | same file::`'authority read failure still presents the non-durable fallback card'` AND same file::`'invalid durable generation still presents the non-durable fallback card'` | host / hand-throwing resolver for the read error; for the invalid-generation leg a resolver returning a context whose `eventCorrelation` fails the lowercase-digest regex (`durable_local_notification_effect_coordinator.dart:44-47` → null generation; context has a public const constructor) — both simulate the error, not the state (legitimate) | causal RED (silent returns on HEAD; zero shows) → one `show` each + stated details | restore either return block → its row red | same |
| TC-383-06 | **Muted group stays totally silent through the new lane**: muted group + killed app + reaction AND message flavors → zero `show` calls, zero cards (behavioral; no event-name pin) | same file::`'muted group killed-app events stay silent through the fallback lane'` (extends the `:4683+` muted block) | host / real in-db resolver + muted-group local state via the same fixtures the existing muted rows use | GREEN on HEAD (trivially — deferral silences everything); must STAY green after the fix (review-verified it will: muted events are stopped twice upstream of the seam, `:680-705` and `:751-763`, and never reach the fall-through) | post-fix mutation (review-corrected for honesty): delete the group arm of the shared upstream display-eligibility resolver (`resolveBackgroundPushNotificationDisplayEligibilityFromLocalState`, `:2522-2583`) → TC-06 reds **together with** the existing muted pin at `:4683-4743` — no fallback-lane-local mutation exists because no policy consult lives on the new lane; the value of TC-06 is the killed-app + fall-through variant coverage, not unique discrimination | same; muted siblings also guarded by `./scripts/run_test_gates.sh groups` |
| TC-383-07 | **Durable staged-ready path preserved**: ready row ⇒ durable show, ledger record `androidPushService`/`effectTerminal`, SQL custody read-only (`hasLength(1)`) | existing `background_message_handler_test.dart::'…authorized durable authority…'` block at `:620-771` (name as in file) | host / existing fixture (real in-db resolver + staged ready row) | GREEN sentinel (passes today) → still passes unmodified | post-fix: make the handler stage/write an outbox row before resolving → custody `hasLength(1)` and count assertions red | same |
| TC-383-08 | **Redelivery after fallback-show dedupes**: same message delivered twice ⇒ exactly one `show` total (recent-shown gate), second run emits `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reason `recent_duplicate_background_push` | same file::`'redelivery after a fallback presentation does not re-alert'` | host / as TC-01, handler invoked twice with the same message | causal RED (on HEAD both runs defer; total shows == 0, expected 1) → one show + suppression discriminator on run 2 | same revert → red (zero shows) | same |
| TC-383-09 | **Intended rewrite of the Plan-372 pin + claim-COMMIT pin**: `:773-823` "deferral releases provisional owners for retry" changes meaning — deferral now presents and **commits the event claim**. Review's strongest wrong impl: keep the `releaseProvisionalNotificationOwners` call and only delete the `return` — every other row stays green because run-2 dedupe comes from the recent-shown gate (`:1488-1502` marks lane-common; `:794-805` suppresses BEFORE claim acquisition), masking claim state, while a released claim lets the live/NSE path re-claim and re-alert. Pin: after the fallback show, reset the recent gate (`debugResetRecentBackgroundNotificationGate` — exists, used at bmh_test`:1014`) and deliver the same message again → `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reason `message_event_already_claimed`, zero additional shows | same file — rewrite in place, name stating the new contract, e.g. `'authenticated durable-authority deferral presents non-durably, defers the durable effect, and commits the claim'` | host / existing fixture of that test + the recent-gate debug reset | GREEN today **pinning the defect-adjacent silence** → rewritten assertions green post-fix (intended expectation change to a fresh Plan-372 pin, called out so execution does not misread its red as a regression) | keep the release call in the fall-through (the review counterexample) → the third-delivery leg reds on reason (`recent_duplicate_background_push`/none instead of `message_event_already_claimed`); revert the whole fix → red (zero shows) | same |
| TC-383-10 | **Device closure (group flavor, real FCM, killed process)**: Plan 379's `android_group_muted_reaction_background_suppression` scenario passes INCLUDING its unmuted pipeline-health control — a card appears for the unmuted control group's reaction at the killed app; muted group still shows nothing | `integration_test/group_muted_notification_proof_test.dart` via `run_group_muted_notification_android.dart` → capture (Plan 379 machinery, unmodified) | device proof / pinned pair (physical `21071FDF600CSC` + `emulator-5554`, verified live this session), fresh `android.production_fcm` build containing the fix (campaign prepare-build handles it) | manual/device-only proof (TODAY this exact control is red — that red IS G17) → adapter PASS with control card present | revert the fix, rerun → control red again (today's state) | `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign`; registration exists (Plan 379: capability `critical_features.json:892`, discovery records, runtime roots) — this plan adds none. **Gate honesty (review-corrected):** the adapter runs the 379-scope live-path scenario FIRST and aborts the loop on its failure (`run_group_muted_notification_android.dart:230-334`; order `group_muted_notification_android_criteria.dart:40-43`), so a foreign red can block the background capture entirely. Fallback closure: run the capture driver directly for the background scenario only (adapter child shape `:239-264` — `dart run integration_test/scripts/capture_group_reaction_notification_device.dart --scenario android_group_muted_reaction_background_suppression --sender <emulator> --recipient <physical> --artifact-dir … --prebuilt-android-apk … --no-child-builds --android-state-prepared` plus relay/credential args), then `dart run integration_test/scripts/run_group_muted_notification_android.dart --validate-artifact <artifact>.json` (`:543-561`). Either way closure requires a **FRESH capture**: the in-window control-card proof (body-change predicate) lives in the CAPTURE (`capture_group_reaction_notification_device.dart:2974-3016`, `:3381-3389`), not the validator — replaying the validator over an old artifact is NOT closure |
| TC-383-11 | **Deadline path unchanged**: `BackgroundStorageDeadlineExceeded` during authority read ⇒ `storage_deferred` record, no show (deliberate asymmetry, owner named in Scope) | existing `background_storage_deadline_test.dart` rows + the `:1088-1097` behavior (name per file) | host / existing deadline fixtures | GREEN sentinel → still passes | post-fix: route the deadline catch into the fallback show → red | `flutter test test/features/push/application/background_storage_deadline_test.dart`; AUTO (feature glob) + full GROUP_TESTS member (entry near `run_test_gates.sh:681` — review-corrected: it is in the curated array, not a nightly entry) |

**TC-383-03 (a separate group-TEXT fallback row) was DROPPED at review as over-engineering:** the seam gate is kind-agnostic; its only unique arm (the message-comparand equality `:1357-1361`) is already driven through the real handler on this exact non-durable lane by existing tests (`background_message_handler_test.dart:1027-1079` "post-show policy flip retires only the generation just shown", `:1081-1178` generation CAS); and the only wrong implementation it uniquely catches is a contrived double conditional ("fall through exactly for direct-message and group-reaction") — TC-383-01/02/04 red every single-axis wrong impl. Group-text killed-app behavior stays covered by the shared-gate rows plus those existing lane tests. Numbering is kept stable (there is deliberately no TC-383-03 row).

### Test Notes
- TC-383-01/02/04 must use the **real** `resolveBackgroundDurableLocalNotificationEffectInDatabase` over real empty ffi tables (fake-fidelity gate): the hand-constructed resolvers are reserved for TC-383-05's error simulation. Empty table == the production state a genuinely-new event sees (writers run only in the foreground app).
- Discriminator pattern (relationship, same handler run): `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED{presentation:'nondurable_fallback'}` **AND** `PUSH_BACKGROUND_NOTIFICATION_SHOWN` **without** a `durable: true` detail (review-corrected: the non-durable emission `:1514-1528` has no `durable` key; the durable lane emits `durable:true`) **AND NOT** any ledger record for the correlation — distinguishes the new lane from the durable lane and from the old silent deferral (no SHOWN).
- Killed-process device choreography (TC-383-10, execution reference): never `am force-stop` before expecting FCM (stopped-package bit blocks data-only FCM; the preflight capture proves the trap and the explicit component-start fix at `capture_android_background_crypto_preflight.dart:3146-3185`); Plan 379's capture already implements the correct kill.
- Sound disposition on the fallback lane follows the tone lease (audible if first in 30s window) — S1-style. Channel assertions for this path stay owned by Plan 380 (G12); do not duplicate them here.

## Implementation Steps
1. Snapshot `git status --short` (tree is already dirty with Plan 378/379 execution files — record, do not revert).
2. Add TC-383-01..05, -06, -08 tests and the TC-383-09 rewrite in `background_message_handler_test.dart`; run the RED set — every causal row must fail for the documented zero-show mechanism (TC-383-06 green, TC-383-07/11 green).
3. Edit `lib/features/push/application/background_message_handler.dart`: inside the `requiresDurableEffect` block, replace the three silent-return exits (`:1052-1066` authority-null, `:1071-1076` generation-invalid, `:1098-1110` read-failed) with fall-through. Per-branch events (review-corrected): authority-null and read-failed keep their `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED` emissions and gain `presentation: 'nondurable_fallback'`; generation-invalid emits nothing on HEAD and gains a NEW emission (`reason: 'generation_invalid'`, same presentation detail). REMOVE the branches' `releaseProvisionalNotificationOwners` calls — the show path commits the claim at the barrier (`:1145-1184`, commit read `:1340`) and the outer catch releases on failure (`:1565-1619`); keeping the release and falling through is the review's strongest wrong impl and TC-383-09's third-delivery leg reds it. Leave `durableEffectContext` null and `contentMetadata` intact so the existing non-durable publish + post-show validators run. Deadline catch (`:1088-1097`) untouched.
   Stop-if: TC-383-06 red after the edit ⇒ unexpected — review verified mute is enforced twice upstream (`:680-705`, `:751-763`) and never reaches this seam; a red here means the edit escaped the intended seam. STOP and re-derive; do not add a second mute reader.
   Stop-if: TC-383-07 red ⇒ the fall-through leaked into the durable path — replan the edit shape.
4. Registration: none new (all rows live in already-registered files; device row reuses Plan 379's registrations). Grep-verify counts unchanged.
5. Focused GREEN → graph-affected dependents → `groups` lane → device closure (TC-383-10) with a freshly prepared build.
6. Post-execution doc deltas: flip the Behavior map §4.2 G17 row to owned/closed-by-383 with the device evidence; project-memory rebuild.

## Risks And Blind Spots
- Fallback card flashes then retires for read/stale events → guarded by the existing post-show validators (`:1353-1426`, `:1427+`); TC-383-04 pins no-retire on the comparand-match path, and retire semantics are already pinned by their own tests (`bmh_test:1027-1079`, `:1081-1178`).
- Fallback lane skips the durable path's final-barrier visibility recheck (`durableFinalVisibility` assigned only at `:1087`, consumed `:1204-1216`): a user foregrounding into the exact conversation DURING the handler run can get a card the durable lane would have withheld. **Accepted difference** — pre-existing property of the `:1233` non-durable lane, window = one handler run, the early eligibility gate `:680-705` still applies; adding a recheck would be new behavior needing its own row (over-engineering guard). Owner if it ever matters: the N05 final-effect race program (AC-07/OQ-02 family).
- Muted leak through the new lane → TC-383-06 (+ Stop-if).
- Double-alert via redelivery or live/FCM dual path → TC-383-08; b13 adapter contract untouched.
- Lifecycle / derived-state durability: N/A — no new in-memory derived state; the later foreground durable completion updates the same conversation-scoped notification id under the existing generation CAS (pinned by existing registry/post-show tests).
- Sibling-surface consistency: iOS NSE killed path → deferred owner GAP-N12 (named); deadline variant → TC-383-11 locks the deliberate asymmetry; direct vs group fallback lanes both covered (TC-01..04).
- Destructive-action side effects: N/A — no delete/cleanup changed; provisional-owner release on the deferral path becomes commit-or-release via the show path, asserted in TC-383-01/09.
- Invariant re-verification under new transitions: the new transition (fallback-show → later durable completion) re-verifies one-audible-max (TC-383-08), ledger-only-under-authority (TC-383-01), read-only custody (TC-383-07).
- Construction/call-site census: `GRAPH_OK=1 grep -n 'releaseProvisionalNotificationOwners(' lib/features/push/application/background_message_handler.dart` → enumerate reasons; the three in-scope deferral reasons must all reach the show fall-through, `storage_deferred` must not (TC-383-11). Counts drift — re-run at execution, never assert a fixed list.
- Build-artifact provenance: N/A — Dart-only edit; the device gate consumes a freshly prepared stamped build via the campaign's own prepare-build (never gate on the 2026-08-17 cached APK, which predates the fix).
- Permission / ACL verb symmetry: N/A — no ACL; the pre-show display-eligibility gate (`:680-700`) runs before every lane, unchanged.
- Fake side-effect fidelity: TC-383-01..04 required to use the real in-db resolver + real empty tables (see Test Notes).
- Composite-node / relationship assertions: the same-run event-pair discriminator (Test Notes) binds the deferral and the presentation to one handler invocation.

## Gate Cadence
- Per-plan closure: focused causal tests + sentinels in `background_message_handler_test.dart` and `background_storage_deadline_test.dart` + the affected curated lane `./scripts/run_test_gates.sh groups` (owns the bmh file at `run_test_gates.sh:466` array and the muted siblings) + the TC-383-10 device gate. No `core-host-all`/`feature-host-all` sweep — one file's production surface changed.
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/features/push/application/background_message_handler.dart --budget 600`, then `flutter test` the named files directly, BEFORE the `groups` lane.
- Full `host-all` is not a per-plan gate: the aggregate run stays owned by the notification-wave batch (Plan 380 execution wave / next wave-level `host-all`), and again at release closure.
- Shared tests outside the feature/core globs: N/A — every host row lives under `test/features/push/`.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution (record; do not revert 378/379 execution files)
git status --short

# Causal RED (before the production edit) — each must FAIL with zero show calls
flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'authenticated durable-authority deferral presents the non-durable fallback card (direct message)'
flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'presents the non-durable fallback card (group reaction)'
flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'redelivery after a fallback presentation does not re-alert'

# Focused GREEN (after the fix) — exit 0, zero failures across the file
flutter test test/features/push/application/background_message_handler_test.dart

# Deadline asymmetry sentinel — exit 0
flutter test test/features/push/application/background_storage_deadline_test.dart

# Graph-affected dependents BEFORE the lane — run every named test file directly
python3 graphify-arch/tdd_context.py affected lib/features/push/application/background_message_handler.dart --budget 600
# flutter test <files named above>

# Curated lane owning the changed surface + muted siblings — exit 0
./scripts/run_test_gates.sh groups

# Registration unchanged (no new files) — grep-verified, never run-verified
GRAPH_OK=1 grep -c 'background_message_handler_test' scripts/run_test_gates.sh   # expect: 1
./scripts/run_test_gates.sh completeness-check                                   # expect: PASS, 0 unmatched

# Device closure (group flavor; fresh build prepared by the campaign itself)
.claude/skills/sims/scripts/run_with_devices.sh major --list --only groups.muted_notification_campaign   # capability listed
.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign
# semantic: adapter PASS; android_group_muted_reaction_background_suppression passes WITH its
# unmuted pipeline-health control card present at the killed app (today that control is red — that red IS G17)
# If the live-path scenario (379-scope, runs FIRST and aborts the loop) reds for a foreign reason:
#   run the capture driver directly for the background scenario (adapter child arg shape,
#   run_group_muted_notification_android.dart:239-264), then
#   dart run integration_test/scripts/run_group_muted_notification_android.dart --validate-artifact <artifact>.json
# Either way closure needs a FRESH capture: the in-window control-card (body-change) proof lives in the
# capture (capture_group_reaction_notification_device.dart:2974-3016, :3381-3389), not the validator —
# validator replay over an old artifact is NOT closure.

# Hygiene
flutter analyze            # 0 new issues
git diff --check           # clean

# After saving plan/doc edits
python3 project-memory/src/build_graph.py
```
Semantic outcomes: every causal RED fails only for the documented zero-show mechanism; every GREEN/sentinel command exits 0 with zero failures; the device command's pass criterion is the control-card semantic above, not merely exit 0 of unrelated scenarios.

## Execution Interpretation And Done Criteria
- Expected RED: TC-383-01..05, -08 fail on HEAD with zero `show` calls at the deferral returns; TC-383-09's rewritten form fails until the fix lands.
- GREEN sentinel: TC-383-06 (muted silence), TC-383-07 (durable path), TC-383-11 (deadline path) green before AND after.
- Pre-existing dirty tree / known failures: Plan 378/379 execution files are expected in `git status`; host-all's 9 pre-existing `test/integration` reds are not this plan's; a muted-campaign scenario failing for a **379-scope** reason (validator/choreography) is a 379 matter — the 383-owned semantic is solely the background scenario's unmuted control card.
- Environment blocker (NOT a product blocker): Pixel secure keyguard blocking a UI choreography leg (unlock required); FCM/relay outage; missing relay-key / FCM service-account credential files (the capture child requires `--relay-key` + `--service-account`, `run_group_muted_notification_android.dart:239-264` — present for runs 9-10); both devices currently hold debug harness builds — the campaign's prepare/install stage replaces them (never `flutter test -d` on the physical).
- Scope drift (BLOCKING): any red outside the Scope Contract (e.g., ledger/custody assertions moving, campaign-file diffs).

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Registration grep-verified + completeness-check PASS (no new surfaces expected).
- [ ] Device proof passes with the control-card semantic.
- [ ] `flutter analyze` clean; `git diff --check` clean.
- [ ] Scope Contract respected; G17 register row updated post-execution.

## Handoff
- First causal RED command: `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'authenticated durable-authority deferral presents the non-durable fallback card (direct message)'` (after authoring the row; fails on HEAD with zero show calls).
- Preservation command: `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'muted group killed-app events stay silent through the fallback lane'` + `./scripts/run_test_gates.sh groups`.
- Manual registration: none (all surfaces already registered; grep counts pinned above).
- Migration: none.
- Boundary closure: `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign` — unmuted control card at the killed app (fallback on a foreign live-path red: standalone background-scenario capture + `--validate-artifact`; FRESH capture required either way).
- Unresolved evidence: whether the mute consult already guards the fallback lane (TC-383-06 resolves; Stop-if names the remedy). 1:1 device flavor deferred to Plan 380 (named).

## Device/Relay Proof Profile
- Profile: paired-device (os-notification).
- Boundary being proven: real FCM wake of a killed production process posting an OS card (host tiers cannot exercise the OS process-death + FCM ingress boundary).
- Live availability check: `adb devices -l` (this session) → physical Pixel 6 `21071FDF600CSC` + `emulator-5554`, both `device` state.
- Pinned targets: physical Android `21071FDF600CSC` + Android emulator `emulator-5554` (repo-pinned pair; no iOS leg — iOS is GAP-N12).
- Automation: fully harness-driven via Plan 379's runner/capture (install, seeding, mute choreography, kill, FCM sends, dumpsys/logcat evidence); no user taps. Keyguard note: deploy works locked; UI choreography legs need the Pixel unlocked.
- Closure role: required closure evidence (TC-383-10).
- `FLUTTER_DEVICE_ID`: not sufficient — both IDs pinned via the campaign env (`SIMS_ANDROID_PHYSICAL_DEVICE_ID`, `SIMS_ANDROID_EMULATOR_DEVICE_ID`).
- Registration: pre-existing (Plan 379): capability `groups.muted_notification_campaign` (`critical_features.json:892`), discovery records, runtime-roots rows. This plan adds none.
- Discovery command: `.claude/skills/sims/scripts/run_with_devices.sh major --list --only groups.muted_notification_campaign` → capability listed.
- Closure command: `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign` → adapter PASS with the unmuted control card present at the killed app.
- Deferred device work: 1:1 killed-app flavor → Plan 380 b12 channel rows (post-W0); iOS legs → GAP-N12.

## Reviewer Findings (2026-08-18, /tdd-review — 2-worker adversarial audit, applied in place)

Verdict: **plan-fixes-required → all deltas applied same session; now execution-ready.** Core bet (fall-through lands in the existing non-durable lane with correct claim/tone/dedupe/post-show behavior): **CONFIRMED** by independent source read — `:1233-1241` replaceContent→publish, tone+claim barrier `:1145-1184`/`:1340`, outer-catch release `:1565-1619` (no double-release: fields nulled `:713-716`, `:1323-1326`), recent-gate marking lane-common `:1488-1502`, post-show fences entered `:1353-1426`/`:1427-1487`, reachability precedent `bmh_test:1027-1079`/`:1081-1178`.

Applied plan-fixes (most severe first):
1. **TC-383-01 `durable:false` assertion was impossible** — the non-durable SHOWN emission (`:1514-1528`) carries no `durable` key. Changed to absence-of-`durable:true` (no extra production surface).
2. **Metadata-nulling escape** — a wrong impl nulling `contentMetadata` for direct routes passed every direct row while flipping autoCancel and skipping registry/validator. TC-383-01 now asserts registry content metadata present post-show.
3. **Release-then-show escape** — keeping the owner release masked broken claim custody behind the recent-gate dedupe. TC-383-09 now pins claim COMMIT via recent-gate reset + third delivery expecting `message_event_already_claimed`.
4. **TC-383-04 flash-retire escape** — a `reaction_id`-only fixture mismatches the comparand alias → post-show RETIRE cancels the just-shown card while a show-count row stays green. Fixture id equality + no-`PUSH_BACKGROUND_GROUP_POST_SHOW_RETIRED` pinned.
5. **Device-gate hostage** — the muted adapter runs the 379-scope live scenario first and aborts on its failure (`:230-334`); added the standalone background-scenario capture + `--validate-artifact` fallback and the FRESH-capture requirement (in-window body-change proof is capture-owned, `capture…:2974-3016`).
6. **Generation-invalid branch emits nothing on HEAD** (`:1071-1076`) — step 3's "keep emitting" corrected: that branch gains a NEW deferral emission (`reason: 'generation_invalid'`).
7. **Silent-cards escape** — an always-silent impl passed all rows; TC-383-01 now asserts the recorded show is non-silent (channel/tone matrix stays Plan-380-owned).
8. **TC-383-03 dropped** (over-engineering): only discriminated a contrived double-conditional; unique arm already covered by existing lane tests (drop note under the contract).
9. Honesty/precision: TC-383-06 mutation reworded (mute is upstream-shared; co-reds with `:4683-4743` — no lane-local mutation exists) and the plan's unresolved mute question closed AFFIRMATIVELY; TC-383-11 is a full GROUP_TESTS member (not "nightly-adjacent"); GROUP_TESTS cite split into declared `:466` / entry `:679`; visibility-recheck asymmetry recorded as an accepted difference with owner.

Review-refuted hypotheses (recorded in Problem And Evidence; do NOT re-introduce): fallback-card stale-generation leak; `:2324` origin-branch divergence.

Dimension states: D1 clear · D2 clear (TC-03 drop applied) · D3 tighten→applied · D4 tighten→applied · D5 tighten→applied. Blind-spot sweep: hits were B-3 (durable:false / :466 cites), B-4 (device-gate semantics), both fixed; B-7 core bet independently confirmed; B-1/B-5/B-6/B-10/B-11/B-12 N-A (no migration/one-way/native/ACL); B-2/B-15 censuses re-derived (writers: 4 production sites + debug fixture; `:2243`/`:3585` group stagers included); B-8 device leg named with fresh-capture rule; B-9 sentinels carry mutations; B-13 same-run event-pair relationship asserted; B-14 real in-db resolver mandated.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
| 2026-08-18 | RED | `background_message_handler_test.dart` | `flutter test … --plain-name 'fallback'` + the TC-09 name | 7 causal rows fail, each with **zero `show` calls** (TC-01/02/04/05a/05b/08/09); TC-06 muted GREEN on HEAD | contract authored against the real in-db resolver over empty outbox tables | production edit |
| 2026-08-18 | GREEN | `background_message_handler.dart` (one seam, `:1042-1128`) | `flutter test background_message_handler_test.dart` → **80/80**; `background_storage_deadline_test.dart` → **15/15** | three silent exits fall through; `releaseProvisionalNotificationOwners` census 5 → 3 sites (definition + `storage_deferred` + `final_authority_invalid`) | — | mutations |
| 2026-08-18 | MUTATION | — | see "Mutation Ledger" below | A restores silence → TC-01/02/04/08/09 red; **B (reviewer's strongest wrong impl) → ONLY TC-09 red**; D neuters the shared mute reader → TC-06 co-reds with the `:4683` pin; E collapses the durable upgrade → TC-372-07b + 2 siblings red | all rows discriminate as designed | TC-383-11 correction |
| 2026-08-18 | **PLAN CORRECTION** | `background_storage_deadline_test.dart` (+1 row, +import) | mutation C (deadline catch → fall-through) left the deadline suite **14/14 GREEN** | TC-383-11's stated mutation was **FALSE**: no fixture in that file sets `resolvedEventIdentity`, so the durable block never executed there. Added `'durable effect authority timeout stays storage-deferred with no fallback card'` (holds the authority resolver past the phase budget). Mutation C now re-reds it | liveness `phase` asserts the truthful `local_state` (that phase has no dedicated bucket in the production switch) — pinning reality, not adding an enum (scope drift) | gates |
| 2026-08-18 | GATES | — | `run_test_gates.sh groups` → **4367 tests + Go bridge + relay Go gates, exit 0**; `completeness-check` → 1468/1468 PASS; `flutter analyze` → no issues; `git diff --check` clean on all touched files | graph-affected host dependents (5 files) → 101/101; registration greps unchanged (`background_message_handler_test` = 1; deadline test = GROUP_TESTS entry `run_test_gates.sh:681`) | — | device |
| 2026-08-18 | **DEVICE (TC-383-10)** | `docker-ws/run_muted_campaign_383.sh` (new host wrapper), `docker-ws/plan383_g17_device_evidence.txt` | `host-run bash docker-ws/run_muted_campaign_383.sh` ×2. Build PASS (fresh APK, `cacheHits=0`, 1m02s). Campaign FAIL | **383-owned semantic PROVEN, reproduced twice** on recipient `21071FDF600CSC`, killed process, real FCM: unmuted control reaction → `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED{reason: exact_sql_authority_unavailable, presentation: nondurable_fallback}` → `PUSH_BACKGROUND_NOTIFICATION_SHOWN` **without a `durable` key** (10:04:12/10:04:12 and 10:19:54/10:19:55 UTC). Muted group: zero cards, zero shows. On 2026-08-17 this identical leg produced **zero cards** | **Adapter red is Plan-379-scope**: `capture_group_reaction_notification_device.dart:3417` requires `suppressed.isNotEmpty`, but the muted group's FIRST post-kill push is storage-deferred at the `display_eligibility` phase (`PUSH_BACKGROUND_STORAGE_DEFERRED{elapsedBucket: 2s_to_8s}`), so it never reaches the mute gate that would emit `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED`. Deterministic across both runs. NOT touched — capture files are on this plan's Hard `Do not` list | 379 owns the predicate |
| 2026-08-18 | ADVERSARIAL | — | 4-lens attack + per-finding refutation panel (`wf_81dcefcc-f62`, 19 agents) | 15 findings raised, **14 refuted**; zero production defects found | 1 conceded coverage gap: no UNMUTED group-MESSAGE row, so a two-axis mutant (`kind == group && contentKind == message`) survived | coverage add |
| 2026-08-18 | COVERAGE ADD (beyond contract) | `background_message_handler_test.dart` | `flutter test …` → **81/81** | added `'…presents the non-durable fallback card (group message)'`. The two-axis mutant now reds **that row alone** (80 others pass) | **Deliberate widening of the plan's Test Contract**: the plan dropped TC-383-03 as over-engineering, but group text is the highest-volume killed-app typed event and the row costs ~40 lines with zero production change. Numbering kept stable (still no TC-383-03) | docs |

### Mutation Ledger (executed 2026-08-18)
| # | Mutation | Expected | Observed |
|---|---|---|---|
| A | restore `releaseProvisionalNotificationOwners` + `return` at authority-null | TC-01/02/04/08/09 red | red (TC-05a/05b stay green — different branches) ✔ |
| B | keep the owner release, drop only the `return` (review's strongest wrong impl) | ONLY TC-09 red, on a second `show` | exactly that ✔ |
| C | route the deadline catch into the fallback show | TC-383-11 red | **GREEN on the old fixtures → plan claim falsified**; red after the new row was added ✔ |
| D | neuter the shared mute reader (`groupMemberMessageDisplayEligibility` `isMuted: false`) | TC-06 co-reds with `:4683` | TC-06 + `:4683` pin + policy row-mapping pin red ✔ |
| E | collapse the durable upgrade into the fallback (`durableEffectContext = null`) | TC-383-07 red | TC-372-07b + 2 sibling durable tests red ✔ |
| F | two-axis kind gate (`group && message` returns silently) | group-message coverage row red | that row alone red, 80 others green ✔ |

### Execution note — device-campaign environment (recurring landmine)
The first campaign attempt returned `BLOCKED (environment)` claiming `MKNOON_RELAY_ADDRESSES`/`FIREBASE_SERVICE_ACCOUNT` were unset **even though they were exported**. Root cause is not the campaign: the container→Mac tool bridge builds the host process environment from the *server's* own env (`scripts/claude_host_tool_bridge.py:70-73`, `:204`), so container-side exports never reach the Mac-side `dart`/`flutter`. Device campaigns must run through a repo-resident wrapper invoked host-side:
`/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh`.
