# 379 - Muted-Group Full-Effect Device Verification (G4 closure, out-of-catalog lane)

Status: executed — device closure GREEN. TC-379-05 and TC-379-06 both CLOSED at device tier (2026-08-18, reproduced runs 14 and 15: `groups.muted_notification_campaign PASS assertions=5`).
Type: Modification
Spec: [379-muted-group-device-verification-carveout.md](379-muted-group-device-verification-carveout.md) (carved out of plan 378 TC-378-08/09; gap G4 in the [UI-23 E2E map](../UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md) §4.2)
Classification: evidence-gated
Closure tier: device

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-17 | Evidence Collector + Planner (wf_4471f5b3-082: 4 ground + 4 adversarial refute agents; relay-marker + Plan-330 wiring re-verified inline) | criteria/capture/runner/sims wrapper, probe, relay Go, critical_features.json, registry pins, contract shells | Design question answered: **out-of-catalog (Plan-330) lane**, NOT the kind-field classifier redesign | Emit Test Contract |
| 2026-08-17 | /tdd-review (wf_fcc39e38-17d: factual verifier + counterexample constructor; lead re-verified every blocker linchpin in source) | probe (`:19-31,:89-111,:274-297`), bmh (`:2564-2582,:3423-3453`), runtime_roots.json, registry/discovery pins, lease | Verdict plan-fixes-required → **fixes applied same day** (see Reviewer Findings) | Execute |

## Problem And Evidence

- Behavior to improve: **G4 — no device e2e proves the full end-visible muted-group effect.** Only the SQLCipher `is_muted` projection hop is device-proven. Required: no card/sound/vibration for a muted group on the live **and** the FCM/background path, unread preserved, badge exclusion, card retirement, delivery unharmed.
- Impact: mute is a headline OQ-05 behavior; every production seam exists and is host-locked, but nothing on a real device proves the user-visible composite. A regression in any one seam (policy gate, badge SQL, reconciler) ships invisibly.
- Confirmed current gap (survived refute): the reaction campaign cannot express a muted scenario — G11. The suffix `_message_unread_lifecycle` is dispatched at **twelve** sites: six in the criteria (`group_reaction_notification_device_criteria.dart:1173,:1665,:1691,:1730,:1960,:2449`), five in the capture driver (`capture_group_reaction_notification_device.dart:702,:2007,:3745,:3923,:4281`), and one in the **probe's marker-shape gate** (`lib/core/debug/group_reaction_e2e_probe.dart:98-111` — non-suffix ids must send target-only markers; review-found). Hard assertions contradict mute: `unreadCount != 0` fails (criteria `:2437`, capture throw `:3728-3740`), `expectedProviderSendCount` literal `2` (`:1166-1172`), per-branch card snapshots require ≥1 card (`:2497-2572`; capture `_waitForNotificationCard` demands exactly one card in 2 min `:3067-3078`), UI timeline pin `'0,1,1,2,0'` (`:3923-3929`). No data-level opt-out exists (measurements key set exact `:1140-1153`; `evidenceRequirements.markers` declarative-only).
- **Blocker-class pre-existing finding (G16, widened by review):** relay **v1.8.0** (production since 2026-08-16; pinned campaign candidate) emits NEITHER `[PUSH] Group notification sent to` NOR `[PUSH] Notification sent to` — `8d86501e4` replaced both with unattributed `[PUSH] outcome=success attempt=%d total_attempts=%d` (`inbox.go:626`). All six existing reaction-campaign scenarios red at `$.evidence[provider_fcm]` on any fresh capture, and the `==2` pin is structurally wrong under wake-outcome admission (0..2 legitimate; `inbox.go:2813-2822`, `wake_outcome.go:616-698`). Review additionally proved the **payload campaign** is broken by the same removal (owned by Plan 380 W0). The muted lane deliberately avoids the dead grammar with recipient-boundary evidence.
- Design decision (the carveout's open question, answered): **model the two muted scenarios as out-of-catalog scenarios in the proven Plan-330 lane.** Precedent verified end-to-end: `groupNotificationProjectionAndroidSourceScenario` (`criteria:690-706`) is out-of-catalog, resolved by `groupReactionNotificationScenario()` lookup precedence (`:708-718`); its thin runner (`run_group_notification_projection_android.dart`) spawns the SHARED capture driver with `--scenario` (`:228-253`) and validates the artifact **in-process** (`:289-295`); the shared capture resolves ids via the lookup (`capture:324`) — so the lookup extension is genuinely required; the sims row's `artifactValidator` is an **audited ID string, never executed** (`tool/sims/executor.dart:591-607`); the proof test is a dart-define-gated manual re-validation binding; **no `_manifestOwnedSupportFacades` entry is needed** (that set holds only two facades; 330's runner is not in it). This needs zero edits to the 12 dispatch sites, the two byte-pinned censuses, and the sims wrapper's auto-enrollment (`run_group_reaction_notification_sims.dart:25-26` filters the catalog) — and decouples G4 from G16.
- Q3 (carveout open decision 3) resolved statically: the relay has **zero mute knowledge** (mute is SQLCipher-local; the only mirror is the iOS NSE keychain via `group_repository_impl.dart:530`; the sole non-mutex relay "mute" hit is a comment delegating to the client, `inbox.go:996`). This plan asserts delivery at the **recipient boundary** (persisted rows + client flow events), never via relay `[PUSH]` grammar.
- Existing coverage: policy-gate host locks (`group_message_listener_test.dart:16481+` muted suppression persists message; `background_message_handler_test.dart:4683-4742` muted member end-to-end via the **fallback resolver**, reason `muted`, no `.show`); badge fixture + probe badge observation (`test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart`, 378 TC-378-10); retire-on-mute host lock (`group_notification_reconciliation_wiring_test.dart:172-197`); SQLCipher projection hop device proof; sibling mute independence (`group_multi_device_real_harness.dart`).
- Missing coverage: the end-visible composite on the pinned pair, both paths — TC-379-05/06.
- Refuted findings (do NOT re-introduce):
  - **In-catalog kind-field classifier redesign**: rejected (couples G4 to the dead provider grammar; 12 dispatch sites + censuses in play for zero evidence gain).
  - **`expectedProviderSendCount == 2` for muted scenarios**: structurally wrong on v1.8.0.
  - **Pinning `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reason `muted` on the device FCM leg** (review blocker, source-confirmed): production `type=='group_reaction'` traffic is intercepted BEFORE the fallback resolver and its suppression collapses into the catch-all `group_reaction_local_state_ineligible` (`background_message_handler.dart:2566-2576`; the muted policy consult at `:3432` is one of ~20 OR'd conditions in the combined null). The bmh host lock's `reason=='muted'` fires only on the fallback path production group types never reach. The FCM leg therefore binds EVENTS (below), records the reason as evidence, and never pins the `muted` literal.
  - **"no escape hatch exists in the criteria file"**: no *data-level* opt-out, but the Plan-330 out-of-catalog lane is a proven structural one — this plan uses it.
  - **"fresh-campaign redness is never this plan's"** (review-corrected): the expected-red excuse is scoped to EXACTLY the `$.evidence[provider_fcm]` failure key (G16). A fresh six-scenario failure at ANY OTHER stage/key after this plan's capture-driver edits is attributed to this plan.
- Unresolved findings (evidence-gated): (a) whether relay `[GROUP_INBOX]` custody lines survive v1.8.0 (optional additive evidence only); (b) Pixel keyguard state at run time; (c) live confirmation that the Group-Info Switch bounds-tap lands (guarded by the validator's `is_muted` requirement — a missed tap now REDs, see TC-379-01).
- Affected production / test / gate files: `lib/core/debug/group_reaction_e2e_probe.dart` (**two debug-only edits**: allow-list + `groupIsMuted` observation field); EDITED `integration_test/scripts/group_reaction_notification_device_criteria.dart` (out-of-catalog consts next to Plan-330's + lookup extension + the pure dispatch function — catalog const untouched), `capture_group_reaction_notification_device.dart` (two stages + dispatch consumption at the four run()-level sites), `tool/sims/critical_features.json` (+1 capability, **appended at the END of the array**), `tool/runtime_roots/runtime_roots.json` (runner entrypoint + tooling root), `test/tool/sims/sims_proof_binding_registry_test.dart`, `scripts/check_reliability_simulation_discovery.sh` (3 records); NEW `integration_test/scripts/group_muted_notification_android_criteria.dart` (validator only), `integration_test/scripts/run_group_muted_notification_android.dart`, `integration_test/group_muted_notification_proof_test.dart`, `test/integration/group_muted_notification_criteria_test.dart`, `test/core/debug` probe rows, `scripts/test/group_muted_notification_device_contract_test.sh`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `585839a9908225b8`; `stale:integration_test/notification_sound_smoke_harness.dart` (expected — plan 378 uncommitted edits; no backstop marker).
- Query / profile: `python3 graphify-arch/tdd_context.py query "android_notification_payload_campaign b12 b13 channel assertion validateNotificationArtifact _notificationRequirements dumpsys" --profile tdd --budget 700`; refined by workflows `wf_4471f5b3-082` (plan grounding) and `wf_fcc39e38-17d` (adversarial review), all claims `file:line`-cited from the working tree.
- Anchors: 12 dispatch sites (criteria `:1173,:1665,:1691,:1730,:1960,:2449`; capture `:702,:2007,:3745,:3923,:4281`; probe `:98-111`); Plan-330 lane (criteria `:690-718`; runner `:228-253,:289-295`; executor `:591-607`); mute seams (`group_notification_display_policy.dart:109-111`, `group_repository_impl.dart:523-534`, `canonical_notification_badge_state_db_helpers.dart:138`, `group_info_screen.dart:495-559`); probe (`:19-31,:89-111,:274-297`); runtime-roots (`runtime_roots.json:363-377,:400,:1480-1495`; `runtime_root_inventory.dart:1126-1145,:1685-1695`).
- Surfaced proof/gate files: `group_reaction_notification_device_criteria_test.dart:119-131`, `group_reaction_notification_device_contract_test.sh:12-19`, `sims_proof_binding_registry_test.dart:72-124,:321-404,:630-639`, discovery records `:242-243,:446-448,:528-531` (330's), `sims_manifest_test.dart:92-107`.
- Graph gaps that required raw source search: relay Go literals, sims/runtime-roots JSON, contract shells, markdown.
- Reuse rule: anchors are search starting points; line numbers drift — re-verify at execution.

## Scope Contract And Guard

In scope:
- Two out-of-catalog muted scenarios — `android_group_muted_message_suppression` (live path) and `android_group_muted_reaction_background_suppression` (FCM path) — with dedicated capture stages, own validator, own proof test, one new sims capability `groups.muted_notification_campaign`.
- **Two debug-only probe edits** (`lib/core/debug/group_reaction_e2e_probe.dart`): (1) allow-list the two ids; (2) add a `groupIsMuted` boolean to the sqlcipher observation payload (read from the same encrypted DB query path; redaction-safe), each with a host row.
- A pure top-level dispatch function `groupReactionCaptureDispatchFor(scenarioId) → {lifecycleStage, observationKind, validatorKind}` in the shared criteria file, consumed by capture `run()` at all four run()-level sites, host-tested for all 8 ids.
- Host criteria tests + contract shell making the muted validator's anti-G11 semantics machine-enforced.

Must preserve:
- The six existing catalog scenarios + both byte-pinned censuses → TC-379-03 sentinel + M5 mutation.
- Capture dispatch for existing ids → TC-379-07's 8-id dispatch test (behavioral, replaces the review-refuted grep-order pin) + M4 reverse mutation.
- Probe contract for existing scenarios → existing `group_reaction_e2e_probe_test.dart` rows stay green.
- Closed product decisions: OQ-01/OQ-04/OQ-05.

Hard `Do not`:
- Do not touch the six criteria suffix-dispatch sites, the catalog const, `_processAliveReactionScenarioIds`, or the sims wrapper `_androidScenarios` filter.
- Do not grep for `[PUSH] … sent to` or pin any immediate provider-send count (dead/wrong on v1.8.0).
- Do not pin `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` reason `muted` on the device leg (unreachable for production group types — record the reason, bind the messageId).
- Do not send `firstMarker`/`secondMarker` in muted probe requests — the probe's marker-shape gate (`:98-111`) requires the reaction shape (targetMarker only) for non-suffix ids.
- Do not insert the new sims capability row anywhere except the END of the capabilities array — six runtime-roots keyPaths are INDEX-pinned (`capabilities.33/34/36…`, `runtime_roots.json:400,:456,:372,:415`) and resolved live.
- Do not print extra stdout in any sims-adapter blocked/preflight lane (single `SIMS_RESULT_JSON` line rule).
- Do not re-implement badge observation — the probe's `canonicalBadgeState` is the only badge read.

Deferred / accepted difference:
- **G16 grammar repair** (six existing scenarios + payload-campaign helper) → reaction-campaign side unowned (own repair plan); payload-campaign side owned by Plan 380 W0. Expected-red interpretation is scoped to `$.evidence[provider_fcm]` ONLY.
- Announcement-muted and media-muted device legs → host-owned (single-seam `isMuted` early return precedes type dispatch; listener/bmh host locks cover the types); device tier samples message(live) + reaction(FCM).
- Card-retirement attribution → non-attributing observation (host lock owns attribution).
- The latent reachability of muted ids into the reaction validator via the standalone validate script (`:74`) / device runner (`:329`) → accepted, fail-closed (schema+evidence+relay+provider axes all reject; identical residue Plan-330 accepted). Optional guard row in TC-379-01.
- iOS legs → GAP-N12.

Dependencies:
- Plan 378's worktree edits (probe `canonicalBadgeState`, badge host test) present.
- Device closure needs the stamped `android.production_fcm` build re-deployed (both devices hold 08-17 debug builds) + the staging manifest (relay v1.8.0 pin).

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-379-01 | Muted validator enforces anti-G11 semantics, with **builder-derived negatives** (every negative = the happy artifact with exactly ONE field mutated through the shared builder — review fix: kills fixture-keyed validators). Rejected: `unreadCount == 0`; any active card for the muted group; badge state containing the muted group; **`groupIsMuted` false/absent** (kills the missed-Switch-tap capture); FCM artifact missing `PUSH_BACKGROUND_MESSAGE_RECEIVED`; FCM artifact whose suppression-event messageId ≠ the muted reaction's messageId; **raw-vs-summary consistency** (summary says 0 cards but the embedded raw dump slice contains a pkg-matching record → REJECT). Accepted: the happy artifacts (msg2 `read_at` NULL bound to msg2's id from the sender receipt; zero cards; badge-excluded; `groupIsMuted` true; control evidence present). Optional guard: the muted artifact fed to `validateGroupReactionNotificationArtifact` is REJECTED | `test/integration/group_muted_notification_criteria_test.dart` (one named row per predicate) | host / shared artifact builder (same code the capture stages use) | causal RED (`validateGroupMutedNotificationAndroidArtifact` absent — compile-RED; presents as a suite load failure with nonzero exit, which IS the documented RED) → negatives rejected, positives accepted | M3: delete the unread-preserved requirement → its row red; M6: delete the `groupIsMuted` requirement → its row red | `flutter test test/integration/group_muted_notification_criteria_test.dart` (host-all-only dir → direct gate; auto-classifies via the `test/integration/*_test.dart` arm, `run_test_gates.sh:1515-1519`); `completeness-check` |
| TC-379-02 | Lookup resolves the two muted ids out-of-catalog; catalog unchanged (consts live NEXT TO Plan-330's in the OLD criteria file — no import cycle; the new file holds only the validator) | same file, `::'muted ids resolve via lookup and stay out of the catalog'` | host / criteria import | causal RED (lookup returns null) → resolves both; catalog list length 6 | remove the lookup extension → red | same direct gate |
| TC-379-03 | The six existing scenarios and both byte-pinned censuses untouched | `test/integration/group_reaction_notification_device_criteria_test.dart:119-131` + `scripts/test/group_reaction_notification_device_contract_test.sh` | host + sh contract | GREEN sentinel → byte-identical | M5: add a muted id to the catalog const → both red | `flutter test …criteria_test.dart`; `host-run bash …contract_test.sh` |
| TC-379-04 | Probe accepts muted ids with **reaction-shaped (target-only) marker requests** and rejects them with first/second markers (the 12th dispatch site, `:98-111`); un-allow-listed ids still rejected; **`groupIsMuted` observation field** present and truthful | `test/core/debug/group_reaction_e2e_probe_test.dart` new rows + a `groupIsMuted` row beside the badge-observation rows | host / probe unit fixtures | causal RED ×2: (a) muted id → **FormatException 'Plan 257 runtime probe request rejected'** (review-corrected wording — the capture-side `contract_mismatch` string is not what a host test observes); (b) `groupIsMuted` key absent from the observation → GREEN: allow-listed target-only ACCEPTED, first/second REJECTED, field truthful from an `is_muted=1` fixture | remove the ids from the allow-list → (a) red; remove the field → (b) red | `flutter test test/core/debug/group_reaction_e2e_probe_test.dart`; AUTO (`test/core/**`) |
| TC-379-05 | **Muted message, live path, full effect** (device). Choreography (review-hardened): HOME → control msg to muted-group-to-be G1 → exactly one audible card (parser/package liveness) → open G1 Group Info → Switch bounds-tap → back → **open unmuted control group G2 then HOME** (structurally overwrites any stale conversation-tracker state — a visibility-suppression confound on G1 is impossible after the G2 visit) → **post-mute control msg to G2 → exactly one audible card** (lane liveness at msg2 time; kills every lane-dead/listener-death confound) → msg2 to G1 → **zero pkg-matching records for msg2's marker on ANY channel**, msg2 `read_at` NULL (id-bound), `groupIsMuted` true, badge `available==true` ∧ G1 absent ∧ G2 present, msg2 persisted; prior-card state recorded (non-attributing) | `integration_test/group_muted_notification_proof_test.dart::android_group_muted_message_suppression` via `run_group_muted_notification_android.dart` → capture stage | device proof / pinned pair, stamped `android.production_fcm`, staging manifest v1.8.0 | manual/device-only proof → artifact passes the muted validator | M1: drop the `isMuted` early return (`group_notification_display_policy.dart:109-111`) → device red on card count AND host siblings red (`group_message_listener_test.dart:16481+`, bmh test `:4683+`). Path-faithful: the FCM reaction path consults the SAME policy function (`bmh:3357-3368` gated at `:3432`) — no bypassing bg `is_muted` read exists (review-verified) | `run_with_devices.sh major --only groups.muted_notification_campaign` |
| TC-379-06 | **Muted reaction, FCM/background path** (device). Recipient backgrounded/terminated; in the SAME backgrounded window the sender reacts in muted G1 **and** in unmuted G2. Assert: G2's reaction card appears via the bg path (pipeline-health control — kills the broken-nomination/epoch degenerate); `PUSH_BACKGROUND_MESSAGE_RECEIVED` present for BOTH fcm messageIds (proves the bg isolate ran — kills the foregrounded-app degenerate); `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` present **bound to the muted reaction's messageId** (reason recorded as evidence, NOT pinned — production emits the catch-all); zero cards for G1's reaction; reaction row persisted; badge still excludes G1; recipient process/foreground state recorded at send time | same proof test `::android_group_muted_reaction_background_suppression` | device proof / same fixture | manual/device-only proof → artifact passes | M1 (same policy mutation) → red on nonzero cards; M2: drop `AND g.is_muted = 0` (`canonical_notification_badge_state_db_helpers.dart:138`) → badge assertion red AND `group_reaction_e2e_probe_badge_observation_test.dart` red at host | same capability run |
| TC-379-07 | **Capture dispatch is behaviorally pinned for all 8 ids** (review fix — replaces the refuted grep-order pin): pure `groupReactionCaptureDispatchFor(id)` in the shared criteria file returns the stage/observation/validator selection; capture `run()` consumes it at all four run()-level sites (stage select, sqlcipher observation, artifact write, self-validation). Host test asserts the mapping for 6 catalog + Plan-330 + 2 muted ids. This row doubles as the **six-scenario capture-driver sentinel** | `test/integration/group_muted_notification_criteria_test.dart::'capture dispatch routes all eight ids'` | host / pure function | causal RED (function absent) → 8-id mapping asserted | M4: route `android_group_message_unread_lifecycle` to the muted stage (reverse mutation) → its mapping row red, others green | same direct gate |
| TC-379-08 | Muted-lane contract shell: validator fixture re-checks (unread-0 REJECT / happy PASS); adapter stdout purity (single `SIMS_RESULT_JSON` line in blocked lane); runner `--list-scenarios` behavior | `scripts/test/group_muted_notification_device_contract_test.sh` (3 cases) | sh contract / canned fixtures | causal RED (case 1 fails until the validator rejects unread-0; shell + fixtures authored before validator logic) → all cases pass | flip the happy fixture's `unreadCount` to 0 → case red | AUTO (`scripts/test/*_test.sh` glob into `sims-contracts`); run via `/claude-host-bin/host-run` |
| TC-379-09 | Sims + runtime-roots registration real and pinned: capability `groups.muted_notification_campaign` (unique command/proofBoundary, `artifactRequired`, artifactValidator = the proof-test path as an audited ID, `required: true`, buildProfile `android.production_fcm`, **appended at the END of the capabilities array**); registry byte-pin (`toJson()`) + capture-owned discovery records; **runner registered in `runtime_roots.json` BOTH as an external entrypoint AND a tooling root with json-value evidence bound to the new row's command path** (mirror `:363-377`/`:1480-1495` — its import closure reaches `lib/` via `reaction_notification_proof_support.dart:7`) | `sims_manifest_test.dart` + `sims_proof_binding_registry_test.dart` (new pin block) + `test/unit/runtime_root_inventory_test.dart` + `./scripts/check_runtime_root_inventory.sh check` | host / meta-gates | GREEN sentinel today → still green WITH the new row + roots pinned (an unregistered runner or a mid-array insert reds these gates — that is the enforcement) | remove the capture-owned discovery record → registry test red; move the capability row mid-array → runtime-roots red on existing index-pinned entries | `flutter test test/tool/sims/sims_manifest_test.dart test/tool/sims/sims_proof_binding_registry_test.dart test/unit/runtime_root_inventory_test.dart`; `./scripts/check_runtime_root_inventory.sh check`; `./scripts/check_reliability_simulation_discovery.sh` exit 0 |
| TC-379-10 | Sibling mute independence unchanged | existing `group_multi_device_real_harness.dart` muted-sibling row | device harness (existing) | GREEN sentinel → unchanged | guarded by M1/M2 (same seams) | unchanged; not re-run per-plan unless graph-affected names it |

### Test Notes
- Q1 answered: unread preservation is asserted as msg2's `read_at` NULL **bound to msg2's message id from the sender receipt** plus conversation unread strictly greater than the phase-1 baseline — never a global `unreadCount` equality.
- Q2 answered: keep 378's confound-free ordering, extended with the G2 visit + post-mute G2 control (review fix — the pre-mute control alone proves dump liveness, not lane liveness; the G2 visit makes G1 tracker-staleness structurally impossible because visiting G2 overwrites the tracker, and a stale-G2 tracker fails the G2 control itself).
- Evidence grammar: recipient-boundary only — persisted rows + cursor-scoped client flow events (`PUSH_BACKGROUND_MESSAGE_RECEIVED` carries `messageId`, `bmh:611-620`) + dumps + probe (`canonicalBadgeState`, `groupIsMuted`). Relay journal evidence optional/additive.
- Probe requests from BOTH muted stages use the reaction shape: `targetMarker` = the message-under-test marker, first/second empty (probe gate `:98-111`).
- `groupReactionNotificationScenario()` has **6 call sites** today (runner `:329`, validate `:74`, criteria `:739`, projection runner `:78,:447`, capture `:324`) — re-derive the census at execution; all must tolerate out-of-catalog ids (they do today via the 330 precedent).
- Recipient = physical Pixel 6 (`21071FDF600CSC`), sender = `emulator-5554`. Check `adb shell dumpsys window policy | grep secure` FIRST; secure-locked keyguard → typed blocker, fail fast.
- Reuse `validateGroupReactionNotificationStagingManifest` for the muted ids (varies only on `recipientPlatform`).
- New ids are non-nesting and carry neither suffix.

## Implementation Steps
1. Snapshot `git status --short` (plan 378 worktree edits expected — do not revert). Author TC-379-01/02/04/07 tests + the TC-379-08 shell with fixtures FIRST; record the causal REDs.
2. Shared criteria file (`group_reaction_notification_device_criteria.dart`): add the two out-of-catalog consts next to Plan-330's (`:690-706` area; empty `evidenceRequirements`), extend the lookup (`:708-718`), add `groupReactionCaptureDispatchFor()`. Catalog const untouched. Stop-if: any edit would touch a suffix-dispatch site → replan.
3. New `group_muted_notification_android_criteria.dart`: `validateGroupMutedNotificationAndroidArtifact` + the shared artifact builder (used by both the capture stages and the host fixtures). Probe edits: allow-list + `groupIsMuted` observation field.
4. Capture: two muted stages implementing TC-379-05/06 (target-only probe requests; zero-records asserted channel-agnostically against the msg2/reaction marker; artifact via the shared builder; self-validate with the muted validator); `run()` consumes `groupReactionCaptureDispatchFor()` at the four run()-level sites (muted ids resolved BEFORE the suffix check, Plan-330 precedent `capture:699-708`).
5. Registration sweep: runner `run_group_muted_notification_android.dart` (mirror 330's CLI contract; in-process validation; spawns the shared capture per scenario); proof test (`*_proof_test.dart` auto-classifies in `run_test_gates.sh` ONLY — all three new Dart files still need explicit `check_reliability_simulation_discovery.sh` records, proof-test/validator notes containing `capture-owned`; the contract `.sh` needs none); sims row **appended at the END** of `critical_features.json` capabilities; registry `toJson()` pin + capture-owned rows; **`runtime_roots.json`: external entrypoint + tooling root with json-value evidence** for the runner.
6. Focused GREEN → sentinels → gates per Acceptance Gates; then the device closure run.

## Risks And Blind Spots
- Pre-existing campaign redness on v1.8.0 misattributed → expected-red interpretation scoped to `$.evidence[provider_fcm]` exactly; ANY other fresh failure after this plan's capture edits is this plan's to triage (review fix). TC-379-07's 8-id dispatch test is the standing driver sentinel.
- Lifecycle / derived-state durability: TC-379-06's fresh background process reads persisted `is_muted` — suppression reconstructs from DB.
- Sibling-surface consistency: device tier samples message(live)+reaction(FCM); single-seam early return + host locks own text/media/announcement (justified in Scope Contract).
- Destructive-action side effects: runner purges both artifact ids (`<id>.json`, `<id>_capture_failure.json`) before capture; checked in TC-379-08.
- Invariant re-verification under new transitions: the post-mute G2 control re-verifies the notification lane after the mute transition; unmute recovery stays host-owned (deliberate).
- Construction/call-site census: 6 lookup call sites + `grep -rn 'groupReactionCaptureDispatchFor(' integration_test/` at execution (must be ≥4 — the four run()-level sites).
- Build-artifact provenance: stamped-build post-install verify before the closure run.
- Permission/ACL verb symmetry: N/A — no permission/ACL change.
- Fake side-effect fidelity: host fixtures are produced by the SAME shared builder the capture stages use; negatives are single-field mutations of the happy artifact (review fix — no independently hand-built fixtures).
- Composite-node assertions: card↔channel from the same dumpsys record block; badge↔group from the production helper's one query; msg2 unread bound to msg2's id.

## Gate Cadence
- Per-plan closure: TC-379-01/02/04/07 direct host tests + TC-379-08 shell + sims/runtime-roots meta-gates + `sims-contracts` + the `groups` curated lane (the `lib/` edits are the two probe edits — same cadence 378 used for the same file) + the device capability run.
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/core/debug/group_reaction_e2e_probe.dart integration_test/scripts/capture_group_reaction_notification_device.dart integration_test/scripts/group_reaction_notification_device_criteria.dart --budget 600` → run the named test files directly BEFORE the lane.
- Full `host-all` is NOT a per-plan gate — GAP-N12 wave + final release closure.
- Shared tests outside feature/core globs (exact commands): `flutter test test/integration/group_muted_notification_criteria_test.dart test/integration/group_reaction_notification_device_criteria_test.dart`.

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot before execution (plan 378 worktree edits are EXPECTED — do not revert)
git status --short

# Causal REDs (before implementation) — each must FAIL for the documented reason
flutter test test/integration/group_muted_notification_criteria_test.dart          # RED: validator + dispatch fn absent (suite load failure, nonzero exit — that IS the RED)
flutter test test/core/debug/group_reaction_e2e_probe_test.dart --plain-name 'muted'   # RED: FormatException 'runtime probe request rejected' rows + groupIsMuted field absent
/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh   # RED: case 1 (validator absent/permissive)

# Focused GREEN (after implementation) — expect exit 0, zero failures
flutter test test/integration/group_muted_notification_criteria_test.dart
flutter test test/core/debug/group_reaction_e2e_probe_test.dart test/core/debug/group_reaction_e2e_probe_badge_observation_test.dart
/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh

# Preservation sentinels — byte-pinned censuses unchanged, expect exit 0
flutter test test/integration/group_reaction_notification_device_criteria_test.dart
/claude-host-bin/host-run bash scripts/test/group_reaction_notification_device_contract_test.sh

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected lib/core/debug/group_reaction_e2e_probe.dart integration_test/scripts/capture_group_reaction_notification_device.dart integration_test/scripts/group_reaction_notification_device_criteria.dart --budget 600
# then: flutter test <each named file>

# Registration — grep-verified + meta-gates (never run-verify curated gates)
grep -c 'android_group_muted_message_suppression' integration_test/scripts/group_reaction_notification_device_criteria.dart   # expect ≥2 (const + lookup)
grep -c 'groups.muted_notification_campaign' tool/sims/critical_features.json    # expect ≥1
python3 - <<'EOF'
import json; caps=json.load(open('tool/sims/critical_features.json'))['capabilities']
assert caps[-1]['id']=='groups.muted_notification_campaign', 'muted row must be LAST (index-pinned runtime-roots keyPaths)'
print('capability appended at end: OK')
EOF
grep -c 'run_group_muted_notification_android' tool/runtime_roots/runtime_roots.json   # expect ≥2 (entrypoint + tooling root)
flutter test test/tool/sims/sims_manifest_test.dart test/tool/sims/sims_proof_binding_registry_test.dart test/unit/runtime_root_inventory_test.dart
./scripts/check_runtime_root_inventory.sh check --format text                     # PASS
./scripts/check_reliability_simulation_discovery.sh                               # exit 0, zero unclassified
/claude-host-bin/host-run ./scripts/run_test_gates.sh completeness-check          # PASS, 0 unmatched
dart tool/sims/sims.dart major --list --format tsv | grep groups.muted_notification_campaign   # row listed

# Affected curated lane (probe lib edits) + contracts
/claude-host-bin/host-run ./scripts/run_test_gates.sh sims-contracts
/claude-host-bin/host-run ./scripts/run_test_gates.sh groups

# Device closure (stamped build re-deployed + post-install provenance verify FIRST)
.claude/skills/sims/scripts/run_with_devices.sh major --list                       # capability listed
.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign   # PASS, both artifacts validated

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: the three causal-RED commands, each for its documented mechanism (TC-379-01's presents as a suite load failure).
- GREEN sentinel: 6-id census pair + probe existing rows + sims/runtime-roots meta-gates.
- Pre-existing dirty tree / known failure: plan 378's uncommitted edits; fresh `groups.reaction_notification_campaign` runs red at `$.evidence[provider_fcm]` on v1.8.0 (G16) — **only that key**; any other fresh failure is this plan's.
- Environment blocker (NOT product): missing FCM credentials / stamped APK not deployed / Pixel keyguard secure-locked / relay-manifest mismatch.
- Scope drift (BLOCKING): any diff in the criteria catalog const, the suffix-dispatch sites, or the reaction-campaign censuses.

- [x] Every behavior has a named test or a justified device proof.
- [x] Causal RED → GREEN and at least M1+M3+M4+M6 mutation re-reds recorded.
- [x] Sentinels + named gates pass with semantic outcomes.
- [x] Registration implemented AND verified (greps, meta-gates incl. runtime-roots, completeness, discovery, capability-appended-last check).
- [x] Device capability run passes with both artifacts validator-accepted (runs 14 and 15).
- [x] `flutter analyze` clean; `git diff --check` clean; Scope Contract respected.

## Handoff
- First causal RED command: `flutter test test/integration/group_muted_notification_criteria_test.dart` (after authoring the test file).
- Preservation command: `flutter test test/integration/group_reaction_notification_device_criteria_test.dart`.
- Manual registration: sims capability (END of array) + registry byte-pins + 3 discovery records + runtime-roots entrypoint/tooling root + probe allow-list.
- Migration: none.
- Boundary closure: `run_with_devices.sh major --only groups.muted_notification_campaign` on the pinned pair.
- Unresolved evidence: `[GROUP_INBOX]` v1.8.0 survival (optional); keyguard state; first-run confirmation of the Switch bounds-tap (now fail-closed via `groupIsMuted`).

## Device/Relay Proof Profile
- Profile: paired-device (os-notification device lab).
- Boundary being proven: OS-level absence of the muted card/sound across live and FCM paths, real SQLCipher, real relay custody, real FCM wake — with in-window lane-liveness and pipeline-health controls.
- Live availability check: `adb devices -l` (this session): `21071FDF600CSC` (Pixel 6, SDK 36) + `emulator-5554` (SDK 36).
- Pinned targets: sender `emulator-5554`, recipient `21071FDF600CSC` (keyguard check first).
- Automation: fully harness-driven (uiautomator bounds-tap for the mute switch; no user taps).
- Closure role: required closure evidence.
- `FLUTTER_DEVICE_ID`: host selector only; both ids pinned in runner argv.
- Registration: sims capability + discovery records + runtime-roots + proof-test auto-arm (`run_test_gates.sh` only).
- Discovery command: `.claude/skills/sims/scripts/run_with_devices.sh major --list` → capability listed.
- Closure command: `.claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign` → PASS, artifacts validated.
- Deferred device work: iOS legs (GAP-N12); G16 grammar repair (reaction side unowned; payload side Plan 380 W0);
  killed-app group-MESSAGE integrity parity failure (see "Out-of-scope observation" in the DEVICE RESULT);
  `storage_deferred`-variant alerting (Plan 383 → dropped-push-recovery wave N08/WP).

## Reviewer Findings (wf_fcc39e38-17d, 2026-08-17 — fixes applied same day)
- Verdict was **plan-fixes-required / apply-plan-fixes**; core bet (out-of-catalog lane) **confirmed sound and minimal** (a new thin runner + one capability is the smallest structure satisfying unique command/proofBoundary + muted-grammar self-validation; the only thinning option would break the house contract pattern).
- Blocker fixed: the deferred FCM-path discriminator was REFUTED at source — production group-reaction traffic never reaches the fallback path that emits reason `muted` (`bmh:2566-2576` catch-all precedes it); TC-379-06 now binds events by messageId + an unmuted bg control and records the reason.
- Plan-fixes applied: runtime-roots registration + END-of-array capability append (index-pinned keyPaths); `groupIsMuted` probe field (the old "is_muted via SQLCipher probe" wording was unimplementable — the probe had no such field — and the "sole lib edit" scope line contradicted it); 12th suffix site (probe marker-shape gate) + target-only marker constraint; TC-379-01 hardened (builder-derived single-field-mutation negatives, `groupIsMuted` negative, FCM-leg negatives, raw-vs-summary consistency); TC-379-05 lane-liveness + tracker-staleness controls (post-mute G2 visit + G2 control); TC-379-07 grep-order pin replaced by the 8-id behavioral dispatch test (doubles as the six-scenario driver sentinel); G16 expected-red scoped to `$.evidence[provider_fcm]`; consts co-located with Plan-330's (no import cycle); 0/78 facade over-spec removed; discovery-record and compile-RED presentation notes; M1 verified path-faithful for BOTH device legs (single policy function, `bmh:3432`).

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-17 | Grounding (wf_fb19f3db-530: 6 parallel readers over criteria/capture/probe/runner/registration) | all target surfaces | — | 12 dispatch sites re-verified; **plan corrections found** (see below) | proceed with corrections | author causal REDs |
| 2026-08-17 | TC-379-01/02/07 RED→GREEN | `group_muted_notification_criteria_test.dart` (NEW), `group_muted_notification_android_criteria.dart` (NEW), shared criteria consts+lookup+dispatch | `flutter test test/integration/group_muted_notification_criteria_test.dart` → RED (suite load failure, exit 1) → **GREEN 35/35** | builder-derived negatives; M3/M4/M6 re-red their own rows only | — | probe rows |
| 2026-08-17 | TC-379-04 RED→GREEN | `group_reaction_e2e_probe.dart` (allow-list + `groupIsMuted`), probe tests | RED ×2 (FormatException `Plan 257 runtime probe request rejected`; `groupIsMuted` null) → **GREEN 30/30** | mute state read from the same encrypted `groups` row | — | registration |
| 2026-08-17 | TC-379-08 | `group_muted_notification_device_contract_test.sh` (NEW), runner `--emit-fixture`/`--validate-artifact` | `host-run bash …` → **PASS**; M3 mutation → shell RED | shell and host tier share one builder | — | registration |
| 2026-08-17 | TC-379-09 registration | sims manifest, runtime_roots ×3, discovery ×3, registry pins, discovery contract pins | runtime-roots **PASS**, discovery **exit 0**, completeness **PASS**, meta-gates **151/151** | capability index 40 (last); `tooling.group-muted-notification-android` validated=true | — | capture stages |
| 2026-08-17 | TC-379-05/06 capture stages | `capture_group_reaction_notification_device.dart` (2 stages, 4 run()-level dispatch sites, muted writer), runner, proof test | `flutter analyze lib integration_test test tool` → **0 issues**; host suite green | code authored + compile-clean; **device run not executed** | **BLOCKED (environment)**: no FCM service account, relay key, or prepared `android.production_fcm` APK in this session | device closure when lab creds are present |
| 2026-08-17 | Mutations | production seams | M1 (drop `isMuted` early return) → policy host locks RED; M2 (drop `AND g.is_muted = 0`) → badge observation RED; M3/M4/M6 RED | all five reverted; tree clean | — | — |
| 2026-08-17 | Mute-targeting device smoke (user-selected, low-cost) | Pixel `21071FDF600CSC` | installed the existing `app-debug.apk`, launched, 3× `uiautomator dump` over ~4 min | app never leaves the splash: engine up, `flutter :` prints stop after the VM-service line, semantics tree empty (1509-byte bare `FrameLayout`) | **Smoke inconclusive** — a plain debug install cannot reach Orbit/Group Info without the harness's identity seeding (`intro_e2e_config.json`) that the capture driver performs | retry inside a real capture run, or seed identity first |

| 2026-08-17 | Device closure attempt | `run_with_devices.sh major --only groups.muted_notification_campaign` | run 1 BLOCKED (`relay_configuration`, my launcher had `mknoon.xyz` for `mknoun.xyz`); run 2 FAIL at `provider_registration` | `completedStages` = device_inventory, relay_configuration, android_role_install, android_identity_setup, **group_fixture_setup**, provider_registration | **BLOCKED by a pre-existing out-of-scope defect (G16-wider, below)** | relay-grammar repair plan |
| 2026-08-17 | Attribution parity test | `run_with_devices.sh major --only groups.reaction_notification_campaign` (untouched catalog lane) | FAIL: `android_group_message_unread_lifecycle capture/validation exited 1: timed_out_waiting_for_capability-bearing recipient android token registration` | **identical stage and message on a scenario this plan never touched** | attribution proven: not this plan's regression | — |
| 2026-08-18 | **Device closure (runs 11-15)** | capture (cold-start warm-up, id-bound arrival, accumulating flow reader, drain-bounded probe), `group_muted_notification_android_criteria.dart` (pure push-binding resolver + 4 background rules), `reaction_notification_proof_support.dart` (+2 helpers), host rows in `group_muted_notification_criteria_test.dart` and `reaction_notification_proof_support_test.dart` | `host-run bash docker-ws/run_muted_campaign_383.sh` ×5 | run 11 red (rotating-ring arrival delta), run 12 red (warm-up disposition gate), run 13 red (probe raced the drain), **runs 14 and 15 PASS assertions=5, both scenarios `ok:true`** | **TC-379-05 + TC-379-06 CLOSED at device tier**; three harness defects fixed, one out-of-scope device finding recorded | plan closed |

### DEVICE RESULT (2026-08-17, runs 1-10 on the pinned pair)

**TC-379-05 (live muted message): CLOSED at device tier.** Reproduced across runs 9 and 10;
`android_group_muted_message_suppression_orchestrator_verdict.json` → `"ok": true`, capture
self-validated by `validateGroupMutedNotificationAndroidArtifact`. Artifact claims, all read from
real hardware:

| claim | value |
|---|---|
| `groupIsMuted` (SQLCipher) | **true** |
| `mutedCardCount` | **0** |
| unread | **0 → 1** (grew, id-bound) |
| `underTestReadAtNull` | **true** |
| `persistedRowObserved` | **true** (delivery unharmed) |
| badge | `available:true, includesMutedGroup:false, includesControlGroup:true, groupIdentityCount:1` |
| controls | pre-mute card on the muted group = 1; post-mute liveness card = 1 |

Both confound controls held: the group under test **could** post a card before mute, and the
unmuted control **did** post one inside the suppression window.

**TC-379-06 (FCM/background muted reaction): CLOSED at device tier (2026-08-18).** Reproduced
across runs 14 and 15 on the pinned pair; both `_orchestrator_verdict.json` files report `ok: true`
and the campaign reports `groups.muted_notification_campaign PASS assertions=5`. Recipient process
state `terminated`, real FCM, APK `0a8c93f6…` (the Plan-383 fixed build).

The graded window, read from the recipient's own flow log:

| wake | push | disposition |
|---|---|---|
| 1 | warm-up text (**ungraded**) | absorbs the cold-isolate first-touch cost |
| 2 | **muted group reaction** | `PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED` bound to its own fcm id, reason `group_reaction_local_state_ineligible` — no card |
| 3 | **unmuted control reaction** | `PUSH_BACKGROUND_NOTIFICATION_SHOWN` bound to its own fcm id — card posted |

| claim | value |
|---|---|
| `groupIsMuted` (SQLCipher) | **true** |
| `mutedCardCount` | **0** |
| `underTestReadAtNull` | **true** |
| `persistedRowObserved` | **true** |
| `reactionRowsObserved` | **1** (the suppressed reaction is still delivered) |
| badge | `available:true, includesMutedGroup:false, includesControlGroup:true` |
| controls | pre-mute control card = 1; in-window post-mute control card = 1 |
| push digests | muted ≠ control, each bound to its own event |

**What had blocked it, and why it was never a mute question.** Plan 383 fixed the seam that made the
killed-app path present nothing (G17). What remained was a lane defect this plan owns: the muted
reaction was the FIRST push after the kill, so it spawned the background isolate cold and paid its
first-touch warm-up. Measured on the pinned Pixel (Plan 383 runs: 2.170s and 2.180s from wake to
deferral), that warm-up outruns the 2s `display_eligibility` phase budget
(`background_message_handler.dart:78-85`), so the push exits at
`PUSH_BACKGROUND_STORAGE_DEFERRED` **upstream of the mute gate** and the capture's
`suppressed.isNotEmpty` predicate was right to refuse it — that silence proved nothing about mute.
**Attribution corrected 2026-08-18 after an adversarial re-read of the raw logs:** the cost is NOT
slow SQLCipher. Decomposing the clean run — wake → ART profile install +0.55s → `libgojni.so` dlopen
+1.20s → SQLCipher keying +1.55s → first query +1.66s → last query +1.96s → deferral +2.18s — the
eligibility resolver's own DB reads take ~0.3s and finish ~0.2s BEFORE the timeout fires. Run 1's
readonly-open / `PRAGMA cipher_migrate` sequence is noise: run 2 has neither and trips 10ms later,
which is the best evidence the deferral is robust rather than a fixture accident. Severity is
unmeasured — both runs are a DEBUG JIT apk on the first process start after an install.
The lane now lands a throwaway warm-up push first so both graded pushes travel the warm path, and
the validator machine-enforces it (≥3 wakes; neither graded push may be the first wake).

The deferral itself is real production behaviour and is NOT owned here: Plan 383 defers
`storage_deferred`-variant alerting to the dropped-push-recovery activation wave (N08/WP).

Relay rollout flags were verified live and are not the cause:
`GROUP_REACTION_PUSH_ENABLED=true`, `DIRECT_REACTION_PUSH_ENABLED=true`,
`DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true`.

### Harness defects found and fixed during the 2026-08-18 closure (runs 11-15)

1. **The live lane's arrival gate was unsound against a rotating logcat ring (run 11).** It counted
   `GROUP_MESSAGES_DB_INSERT_SUCCESS` occurrences and required `count > baseline`, but `adb logcat
   -d` returns only what is still in the ring. Under campaign load that Pixel's ring holds ~4
   minutes, so baseline occurrences aged out and the count went DOWN; the predicate was
   structurally unsatisfiable. Device proof that the message HAD arrived:
   `docker-ws/plan379_run11_rotation_evidence.txt` — sender published `6e4e1d63` at 11:10:48.327Z,
   recipient row `createdAt 11:10:52.034882Z`, harness gave up at 11:13:52. Now bound to the id the
   sender published (`latestGroupSendMessageId` → `groupMessageStoredWithId`, accepting a replayed
   duplicate that reports an existing local row), and every recipient logcat read folds into a
   monotonic accumulator so rotation cannot shrink what the lane has seen. The unsound delta is
   pinned as a negative host row so it cannot return, and the fix was replayed against run 11's own
   logs before re-running.
2. **The warm-up gate enumerated dispositions instead of asserting its purpose (run 12).** The
   warm-up text ended at `PUSH_ANDROID_DATA_DECRYPT_FAIL{group_parity_mismatch}` →
   `PUSH_BACKGROUND_NOTIFICATION_ERROR`, outside the enumerated set, even though its SQLCipher open
   had completed normally. The gate now waits for `GROUP_MESSAGES_DB_LOAD_ALL_SUCCESS` — the cost
   being absorbed — and the warm-up's own outcome stays ungraded.
3. **The reaction-row probe raced the offline-inbox drain (run 13).** The background isolate is
   read-only, so the suppressed reaction is written by the drain on the next app run — which is the
   probe's own foreground start. A single-shot probe read `reactionRows: 0` while every other claim
   held, reading a delivered-but-suppressed reaction as a lost one. The probe now polls until the
   row lands (3-minute bound); `reactionRowsObserved >= 1` is unchanged, so a genuinely lost
   reaction still fails the lane.

### Out-of-scope observation recorded, not chased
A group TEXT push on the killed path failed notification integrity parity
(`PUSH_ANDROID_DATA_DECRYPT_FAIL{group_parity_mismatch}` →
`OrdinaryMessageNotificationIntegrityException(group_plaintext_parity_mismatch)`,
`push_decrypt_preview.dart:1002-1019`) and posted nothing — on both runs where a warm-up text was
sent. Plan 383's host row for that leg (`presents the non-durable fallback card (group message)`)
passes, so the host row and the device disagree, and the device fails UPSTREAM of the seam 383
fixed. This lane does not grade the warm-up, so nothing here depends on it. Owner: whoever takes
the killed-app group-message leg (Plan 380 b12 rows / N08 recovery wave).

### Capture-driver corrections made during device execution
1. **Live lane must stay FOREGROUND on Orbit.** The original choreography pressed HOME, which
   backgrounds the app, moves delivery onto push-wake, and lets storage defer to
   inbox-drain-on-resume — non-deterministic (run 6 stored msg2, run 7 did not, same code) and it
   silently made the "live" lane a second background lane.
2. **Group Info targeting was rebuilt against the real accessibility tree.** "Mute Notifications"
   and its subtitle are NOT exposed (every `text=` is empty; the switch carries `NAF="true"`), so
   label-keyed helpers could never fire on device. Now: surface = the `Group Info` app-bar label;
   target = the screen's unique checkable node (ambiguity fails closed); state = the switch's own
   `checked` attribute. `findGroupInfoEntryCenter` was already correct (tap landed at 996,212).
3. **`GROUP_MESSAGE_STORED` never existed.** Replaced with `GROUP_MESSAGES_DB_INSERT_SUCCESS`
   (`group_messages_db_helpers.dart:76`), bound by a COUNT DELTA because that event also fires for
   the control messages in the same window.
4. **Control-card counts relaxed to `>= 1`** (the FCM lane's control group legitimately holds a
   baseline message card and a reaction card). The muted side stays exact at zero.
5. Diagnostic UI/notification dumps are now written on every targeting failure.

### BLOCKER: G16 is wider than this plan documented (fixed during execution)

The plan scoped expected v1.8.0 redness to "EXACTLY the `$.evidence[provider_fcm]` failure key". That is **wrong**. The same commit `8d86501e4` also deleted the token-registration log line, and that failure happens **much earlier and blocks the capture outright**:

- `capture_group_reaction_notification_device.dart:3983` `_waitForRelayTokenRegistration` waits up to 3 minutes for the relay journal to contain
  `[PUSH] Token registered for <peerPrefix> (android)`.
- That literal **no longer exists in `go-relay-server`**. v1.8.0 emits `log.Printf("[PUSH] outcome=registered")` (`inbox.go:191`).
- `git log -S "Token registered for"` → removed in **`8d86501e4`**, the same commit this plan already blames for `[PUSH] … sent to`.
- The waiter runs at `run():747`, **before** the lifecycle dispatch at `:754`, so it gates **every** Android scenario in this driver: all six Plan-257 reaction scenarios, Plan-330's projection, and both muted ids.

**A faithful harness-side repair does not exist.** `inbox.go:185-191` has `peerId` and `platform` in scope but logs neither, and `push_permanent_error_closure_test.go:266-272` (`…ProviderWakeLogsOmitPrivateValues`) *asserts* those lines omit private values — the anonymity is deliberate. Any harness-only "fix" would have to weaken a capability-bearing, peer-bound, platform-bound assertion into "some token registered by someone", which the sender also satisfies. That is a design decision with privacy implications and belongs to the owning repair plan, not to an improvised edit here — and this plan's Scope Contract already defers it ("G16 grammar repair → reaction-campaign side unowned") while its Hard `Do not` forbids leaning on the dead `[PUSH]` grammar.

**RESOLVED 2026-08-17 without touching the relay.** Attribution moved to the recipient boundary:
`androidRelayPushRegistrationAccepted()` (`reaction_notification_proof_support.dart`) waits on the
device's own log for `[PUSH_DIAG] relay_push_registration_success platform=android` or
`[FLOW] PUSH_REGISTER_TOKEN_SUCCESS {platform: android}`. Both derive from the bridge's `ok`, which
the Go node sets only after the relay replied `Status:"OK"` — i.e. after the relay persisted the
route — so this is server-side acceptance, not client intent. `PUSH_REGISTER_TOKEN_SENDING` is
explicitly rejected. Attribution is strictly BETTER than the deleted relay line, which carried only
a 20-char peer prefix; the device log is unambiguously that device's.

Zero relay changes: Plan 368's pinned `[PUSH]` vocabulary is untouched and no identifier — hashed or
otherwise — was added back. The old wait's "capability-bearing" label was dropped rather than carried
forward: even the deleted relay line never printed the capability set, and no channel logs it today.
The iOS caller keeps the relay-journal wait, now explicitly labelled dead-on-v1.8.0 (iOS legs are
deferred to GAP-N12 and unexercised).

A census host test now pins every literal this capture waits on against its real emission site, so a
harness grepping a string that no longer exists is caught at host tier in seconds instead of after a
9-minute device run.

### Device-tier status (TC-379-05/06) — SUPERSEDED 2026-08-18 by the DEVICE RESULT above
Recorded before any device run had executed; kept for the record. All three risks below were
resolved by the closure: the Group Info targeting matched the real tree, the pair carried a fresh
`android.production_fcm` build, and the `[FLOW]` bindings TC-379-06 asserts were present. Original
text:
- The geometric Group Info targeting has six host rows against a synthetic uiautomator dump, but has **never been matched against the real tree**. This is the carve-out's open question (c), still open.
- `com.mknoon.app` is installed on **neither** device (only `sims.groupmedia269` and `app.visibilityproof`), so the plan's "both devices hold 08-17 debug builds" dependency is stale; closure needs a fresh `android.production_fcm` build plus installs on both.
- The FCM lane assumes `flowEventLoggingEnabled` is true on the stamped build, since the `[FLOW] {json}` lines are the only source of the `messageId` bindings TC-379-06 asserts.

### Plan corrections found during execution (all source-verified)
1. **Plan-330's runner has no `--list-scenarios`/`--scenario` CLI** (it is zero-arg + env). Plan line 106 ("mirror 330's CLI contract") and TC-379-08 ("`--list-scenarios` behavior") were mutually inconsistent. Resolved as a hybrid: 330's verdict/sentinel body plus a `--list-scenarios` census, since this lane genuinely drives two scenarios.
2. **The artifact purge (plan line 113) exists nowhere at HEAD.** 330 avoids stale artifacts with a fresh `capture-<micros>-<pid>` directory. Implemented both: fresh directory *and* an explicit per-scenario purge of `<id>.json` + `<id>_capture_failure.json`, because this runner reuses one directory for two ids.
3. **Six index-pinned `capabilities.NN` keyPaths, not four** (plan cited `:400,:456,:372,:415`; `:1491` and `:1507` in `restrictedRoots` were missed). A `requiredRestrictedRoots` ↔ `restrictedRoots` bijection is also required and was not mentioned. The capability is appended last (index 40) and a new jq gate pins that.
4. **`scripts/test/reliability_simulation_discovery_contract_test.sh` was not in the plan's surface list** but byte-pins support paths and capability rows. Updated.
5. **Only ONE of the five capture suffix sites is inside `run()`** (`:702`). The plan's other three "run()-level sites" dispatched on `_isPlan330`, not on the suffix. All four are now dispatch-driven; the remaining helper-level suffix sites are unreachable on the muted path (proven by routing muted captures to their own observation/writer/validator).
6. **TC-379-07 asserts NINE ids, not eight.** The plan's "eight" counted Android-only scenarios; the dispatch function is total over all registered ids (6 catalog + Plan-330 + 2 muted) and returns null for unknown ids so callers fail closed.
7. **M3 did not re-red on first attempt.** The "unread did not grow" negative was being rejected by the raw-vs-summary cross-check rather than by the unread rule, leaving that rule untested. The negative now moves the summary and its raw probe observation together, and M3 re-reds correctly.
8. **The probe's `groupIsMuted` needed a fixture schema change**: `group_reaction_e2e_probe_test.dart` builds `groups` by hand without `is_muted`. The column was added there only; the badge projection's `available: false` branch stays exercised because it also needs `is_archived`/`is_dissolved`/`self_removed_at`/media columns.
9. **`grep -c 'android_group_muted_message_suppression' <criteria>` returns 1, not the plan's expected ≥2.** The lookup iterates a source-scenario list instead of repeating the literal; TC-379-02 proves resolution behaviorally.
10. **M1's real path is `lib/features/push/application/group_notification_display_policy.dart:109-111`** (the plan omitted `features/push/`).
11. **Neither Group Info affordance is labelled** — the header info control is a bare `IconButton` (no tooltip/Semantics) and `Switch.adaptive` carries only a `ValueKey`. Both are targeted geometrically, and the targeting is implemented as PURE functions with six host rows, so the bounds heuristics are not device-only.
