# 392 - Android Notification E2E Recurrence And Permission-Divergence Closure

Status: COMPLETE / host-green / typed device PASS / S1-S16 device PASS / G24 policy-N/A
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md`; user request after Plan 391 closure
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-20 | Evidence Collector | both UI-23 assessments; Plans 378, 385, 388, 391; sound, payload, reaction, recovery runners | Three bounded proof gaps belong here: recurring typed-reaction ownership, G24's real Android divergence, and the first retained S1-S16 device run | write causal contract |
| 2026-08-20 | Planner | Graphify snapshot plus current source/tests/gates named below | Keep this harness-only; do not mix N11 production behavior or the incomplete recovery campaign into the same plan | independent counterexample review |
| 2026-08-20 | Independent Reviewer | fresh review-profile Graphify query; plan commands; Sims planner/wrapper; reaction, payload, sound, state-guard, runtime-root, and inventory source | `plan-fixes-required`: build-only closure command, stale-evidence path, state leaks/restoration order, vague G24 causality, report overwrite, and two overbroad ownership edits | apply bounded plan fixes |
| 2026-08-20 | Arbiter | reviewer findings rechecked against current source | Accept the blockers; keep one plan; preserve the shared seven-scenario runner/proof classification instead of excluding or reclassifying them wholesale | execution handoff |
| 2026-08-20 | Final Reviewer | revised literal commands, availability rules, Flutter child cleanup, focused gates, and restoration contracts | `ready`: relay aliases, receiver-specific API33 rule, package-absent sound boundary, report retention, and minimized gates are exact | causal REDs |

## Problem And Evidence

- Behavior to improve: notification behavior that already works must be runnable and graded through repeatable Android E2E simulation instead of depending on one-off device evidence or an undiscriminating scenario.
- Impact: Plan 391 proved one killed-recipient typed 1:1 reaction, but that proof is not a Sims capability; G24 is implemented but its device row uses ordinary permission revocation and cannot exercise the Android app-op/runtime-permission disagreement; S1-S16 are implemented and host-registered but have never completed one retained post-G9 device campaign.
- Confirmed current gaps:
  - `android_typed_reaction_smoke` is selectable in `integration_test/scripts/run_1to1_reaction_notification_device.dart:28-178` and graded by `integration_test/one_to_one_reaction_notification_proof_test.dart:91-174`, but `tool/sims/critical_features.json` has no owning capability. The current runner emits no `SIMS_RESULT_JSON`, consumes no centrally prepared build environment, and its capture path builds child APKs at `integration_test/scripts/capture_1to1_reaction_head_provenance.dart:835-915`.
  - `requestPushPermission` already narrows a granted Firebase result with `areNotificationsEnabled()` and emits `PUSH_PERMISSION_OS_STATE_OVERRIDE` at `lib/features/push/application/request_push_permission_use_case.dart:54-113`; the existing payload row instead revokes `POST_NOTIFICATIONS` at `integration_test/scripts/notification_android_payload_campaign.dart:1435-1508`, so it proves the ordinary denied branch rather than G24's granted-permission/app-op-disabled boundary.
  - The S1-S16 disposition table, live/offline verdict, and discovery census are implemented in `integration_test/scripts/run_notification_sound_smoke.dart:95-214`, `:1215-1278`, `:1739-1812` and `scripts/test/notification_sound_disposition_contract_test.sh`; the host contract is GREEN today, while the E2E map states that the first complete device campaign remains absent. Review also found that this runner installs/grants on both targets and raw Flutter integration-test cleanup can uninstall the package. Exact closure therefore requires a read-only package-absent preflight before any child/mutation, one local guard for that absent baseline, and a package-specific notification-state before/after comparison.
- Existing coverage:
  - Plan 391's retained artifact proves killed process, typed card, recipient-side provider attribution, tap route, and unread lifecycle for the standalone reaction run.
  - `test/features/push/application/request_push_permission_use_case_test.dart:129-153` proves the G24 decision and typed events with an injected OS check.
  - `scripts/test/notification_sound_disposition_contract_test.sh` byte-pins all sixteen sound/suppression rows and exercises the same OS-capture decision function used live.
- Missing coverage: recurring typed-reaction Sims ownership and central-build provenance; a real Android G24 divergence with runtime permission still granted; one complete retained S1-S16 Android-pair run whose child installs cannot leak pre-run device state.
- Refuted findings:
  - N11 is not merely a missing E2E row. Direct/group/linked read eligibility and ordinary-route activation cleanup have confirmed production gaps, so they cannot be closed honestly by this harness-only plan.
  - `notifications.android_recovery_completion` is not automation-ready despite the E2E map's inventory heading. Current manifest `automationReady` is false and `--driver-preflight` exits 78 with nine missing seams. A manifest flip is not a valid fix.
  - Plan 391's typed card does not prove the durable direct-reaction arm; its closure explicitly records the non-durable fallback. This plan preserves that claim boundary.
- Highest-risk bet, source-confirmed but device-gated: the centrally prepared `android.production_fcm` profile already combines `E2E_TEST_MODE=true`, `PRODUCTION_FCM=true`, and wake-token emission, and the group reaction lane already uses one such APK for setup plus real FCM with zero child builds. Plan 391 deliberately replaced its recipient with an `E2E_TEST_MODE=false` APK, so Plan 392 claims recurrence on the instrumented production-FCM main-app profile, not byte-equivalence with that two-build choreography. TC-392-02/03 must still prove the 1:1 behavior before closure; stop rather than create a second profile if it cannot.
- G24 premise, source-confirmed but target-bounded: `pubspec.lock:290-309` locks `firebase_messaging` 15.2.10; on Android API 33+ its request path derives authorization from `checkSelfPermission(POST_NOTIFICATIONS)`, while the app's second check uses NotificationManager `areNotificationsEnabled()`. A granted runtime permission plus ignored `POST_NOTIFICATION` app-op can therefore reach the production override branch. The device leg must measure, not assume, that conjunction.
- Execution correction, 2026-08-20: the only configured emulator is Android 17 / API 37. Its shell returns success and can transiently print `Uid mode: ... ignore`, but `AppOpService` logs `Blocked setUidMode call for runtime permission app op` and NotificationManager remains enabled. The final harness recognizes that platform rejection as `targetUnavailable`, restores the UID/app/outer baselines, and records G24 only as `N/A (target unavailable by project policy)`; it never substitutes `pm revoke` or calls the aggregate PASS.
- Affected production, test, and gate files: no production file is planned. Expected scope is `integration_test/scripts/run_1to1_reaction_notification_sims.dart` (new), `run_1to1_reaction_notification_device.dart`, `capture_1to1_reaction_head_provenance.dart`, `one_to_one_reaction_notification_proof_test.dart`, `run_notification_sound_smoke.dart`, `notification_android_payload_campaign.dart`, `run_notification_tap_device_real.dart`, `tool/sims/critical_features.json`, `tool/sims/device_criteria.dart`, `tool/runtime_roots/runtime_roots.json`, `scripts/check_reliability_simulation_discovery.sh`, the exact payload/Sims tests named below, one new adapter shell contract, and two existing notification shell contracts. The shared proof file keeps its current `1to1/test` discovery classification.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `0c3e874a47628f55`; current at planning query time.
- Initial query / profile: `python3 graphify-arch/tdd_context.py query "Android notification presentation and lifecycle E2E closure after Plan 391: notification_sound_smoke_harness S1-S16, notification_open_during_other_chat, runtime permission appops divergence, read activation cleanup, android_typed_reaction_smoke Sims registration, android recovery completion" --profile tdd --budget 900` -> `confidence=broad`.
- Refinement: `python3 graphify-arch/tdd_context.py query "notification_sound_smoke_harness.dart DirectNotificationPresentationCoordinator conversation_wired.dart group_conversation_wired.dart direct_notification_projection_owner.dart critical_features.json" --profile tdd --budget 1000` -> `confidence=anchored`.
- Anchors: `waitForShown` -> `integration_test/notification_sound_smoke_harness.dart`; direct/group notification projection owners -> `lib/core/notifications/direct_notification_projection_owner.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`.
- Surfaced proof/gate files: notification presentation/projector tests plus the sound harness.
- Graph gaps requiring source search: `integration_test/scripts/**`, shell discovery/contract gates, and `tool/sims/critical_features.json` relationships are incomplete in the architecture graph; all load-bearing runner, manifest, and registration claims above were verified in current source.
- Review query / profile: `python3 graphify-arch/tdd_context.py query "Plan 392 counterexamples: requestPushPermission PUSH_PERMISSION_OS_STATE_OVERRIDE ShowNotificationUseCase waitForShown FlutterNotificationService DirectNotificationPresentationCoordinator" --profile review --budget 800` -> `confidence=anchored`, fingerprint unchanged.
- Reuse rule: these anchors may seed execution/review; the graph output is not acceptance evidence.

## Scope Contract And Guard

In scope:
- Add exactly one required, active, automation-ready Sims-manifest capability for `android_typed_reaction_smoke`, appended after the existing capability rows. Back it with one thin adapter that uses the central `android.production_fcm` APK, emits one typed `SIMS_RESULT_JSON`, writes content-addressed evidence, and runs zero child builds.
- Reuse the Plan 391 capture and named proof oracle. Add only the prepared-artifact/state-ownership flags needed to let the Sims adapter drive a unique per-invocation directory safely and bind both installed roles to the prepared SHA/profile.
- Add one `tc_g24_permission_appop_divergence` row to the existing `notifications.android_payload_campaign`; keep runtime permission granted, set `POST_NOTIFICATION` app-op to `ignore`, grade the G24-specific same-window events/outcome, restore the leg-local app-op for a recovery send, then restore the campaign-entry app-op after `AndroidAppStateGuard.restoreAll()`.
- Add a fail-before-mutation preflight to the existing S1-S16 runner: `com.mknoon.app` must be absent on both targets because Flutter child cleanup may uninstall it and an installed app's Keystore cannot then be reconstructed. For that absent baseline only, add one local `AndroidAppStateGuard` plus exact package-card/channel snapshot/re-read; do not change scenario logic. Run once, unfiltered and non-interactive, retaining passing artifacts only after restoration succeeds.

Must preserve:
- Plan 391 semantics: killed recipient measured absent immediately before reaction; typed copy; recipient-bound provider evidence; tap route; unread sequence; non-durable fallback honestly labeled -> existing `android_typed_reaction_smoke` proof test.
- Other 1:1 proof scenarios remain directly runnable and keep their current discovery/proof classification; only the typed selector is enrolled in the new capability -> runner catalog/list and inventory sentinels.
- The nine existing Android payload scenarios and their checks remain unchanged -> payload support/criteria tests plus the full capability run.
- The sound command mutates only an initially package-absent pair and restores that exact absent plus card/channel baseline; both Sims commands restore their arbitrary captured package/data/permission/process state, and central prepared APK bytes survive -> focused preflight/state-guard plus SHA/app-op evidence.
- S1-S16's existing dispositions and 16-row discovery registration -> `scripts/test/notification_sound_disposition_contract_test.sh`.

Hard `Do not`:
- Do not edit `lib/`, Android/iOS production source, DB schema, relay/wire protocol, notification architecture, or notification copy in this plan.
- Do not invent a generic device framework, second notification ledger, new lifecycle authority, or shared app-op abstraction.
- Do not reclassify the shared `one_to_one_reaction_notification_proof_test.dart` as capture-owned, exclude the whole seven-scenario 1:1 runner from the legacy aggregate, or add scenario-aware legacy scheduling merely for this adoption.
- Do not activate or paper over `notifications.android_recovery_completion`; do not implement N11 read/activation; do not fix G21/G27 or run Plan 388 Wave 3 here. Those remain owned by the second notification implementation/correctness plan.
- Do not add iOS/OEM/manual-tap proof, interactive acoustic grading, or full `host-all` to this plan.

Deferred / accepted difference:
- N11 strict read eligibility and independent exact-generation activation cleanup -> second notification implementation/correctness plan; current source proves production behavior is wrong, not merely untested.
- Recovery completion's missing receiver/observer/choreography and activation -> second notification implementation/correctness plan; `--driver-preflight` must stay fail-closed until that work exists.
- G21/G27 and Plan 388 Wave 3 -> second notification implementation/correctness plan; Plan 392 neither claims nor masks durable/fixed-wake behavior.
- Actual acoustic output and haptic feel -> not claimed. Non-interactive S1-S16 grades OS channel, notification record, and recorded `silent` decisions.
- Typed recurrence uses the instrumented `android.production_fcm` APK (`E2E_TEST_MODE=true`) on both roles. Plan 391's two-build run used an `E2E_TEST_MODE=false` recipient before the graded push. Plan 392 preserves the killed/card/tap/unread behavior claim, not compile-mode byte equivalence.
- The shared direct runner remains a compatibility/manual entrypoint for seven scenarios and stays visible to legacy discovery. The new typed capability is the single authoritative Sims-manifest owner; path-level legacy exclusion is deliberately rejected because it would hide six siblings.

Dependencies:
- Plan 391 is closed and supplies the typed scenario plus proof oracle.
- Plan 390/G9 runtime-lease repair must remain green for the sound harness.
- Execution requires the availability-bounded default Android pair, staging relay/FCM credentials, and the Sims-owned central `android.production_fcm` build.
- S1-S16 requires `com.mknoon.app` to be absent on both selected targets at its read-only preflight. An installed package is a typed pre-mutation blocker; the harness must not uninstall it automatically or claim it can preserve Keystore state.
- G24 device closure requires the configured Android emulator receiver to be API 33+ and expose a readable/settable `cmd appops` boundary. If that receiver capability is absent from the live matrix, only that version-specific row is policy-bounded N/A; an API33+ physical sender cannot substitute because the campaign mutates receiver notification state.

Stop-if conditions:
- If the central APK cannot exercise both setup and the killed-recipient typed path without a second build, stop before adding a build profile or weakening `childBuildCount == 0`; replan the capability boundary.
- If the configured API33+ emulator receiver accepts and reads back app-op `ignore` but the measured runtime/Firebase/OS discriminators cannot establish G24, retain the failed evidence and stop/replan. That is a harness/core-bet failure, not target-unavailable N/A; never substitute the physical sender or `pm revoke`.
- If either sound target already has the app package installed, exit BLOCKED/78 before guard capture, child launch, permission grant, install, or notification mutation. Do not auto-uninstall or weaken the exact-state claim.
- If S1-S16 exposes a production or harness defect, retain the failed artifact and open a causal repair delta; do not expand this acceptance row silently.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-392-01 | The typed reaction has one exact, recurring Sims-manifest owner while the shared seven-scenario runner/proof remain correctly classified | `scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh::manifest_owner_and_shared_runner_preservation`; `test/tool/sims/sims_manifest_test.dart::typed reaction reuses the central production APK`; runtime-root inventory | host / real manifest, compiled major/full plans, discovery TSV, runtime-root JSON | causal RED: capability/adapter/runtime root absent -> one required active automation-ready major/full row owns the exact selector; adapter is support-classified; shared runner remains `1to1/runner` and proof remains `1to1/test` | remove capability/runtime root/support classification, reclassify the shared proof, or add a whole-path legacy exclusion -> focused contract red | direct shell contract; exact manifest tests; runtime-root check; `sims-contracts --list` registration; full-inventory preservation contract |
| TC-392-02 | The adapter fails closed without prerequisites, consumes one central APK, performs zero child builds, cannot reuse stale raw evidence, does not delete/change the APK, and emits typed content-addressed Sims evidence | `scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh::prepared_artifact_unique_capture_no_child_build_contract` | host / process contract plus fake prerequisites, stale-preseed fixture, raw/aggregate provenance fixtures | causal RED: adapter and central path absent; current capture shells two builds -> missing prerequisites return BLOCKED/78 with one sentinel; each run creates a unique empty capture directory; raw `buildMode`, `buildProfile`, `childBuildCount`, sender/recipient hashes and aggregate SHA equal the prepared artifact; before/after prepared SHA matches | preseed a passing raw artifact, route prepared mode through either `flutter build`, omit one role hash, or mutate/delete the prepared APK -> contract/provenance audit red | direct shell contract; exact manifest/runtime-root/discovery checks |
| TC-392-03 | Sims recurrence preserves Plan 391's killed-recipient typed behavior on the accepted instrumented production-FCM profile | `notifications.android_typed_reaction_smoke` -> `integration_test/one_to_one_reaction_notification_proof_test.dart::android_typed_reaction_smoke` | device / one central production-FCM APK, real staging relay, USB Android sender + emulator recipient | device-only gap: standalone proof exists but no Sims invocation -> capability PASS only after fresh capture proves process absent before reaction, typed card, recipient push attribution, tap route, unread lifecycle, raw artifact audit, exact state restore, and aggregate audit | omit `--live-typed-smoke`, move process-absence measurement after reaction, accept generic copy, or run build-only instead of capability -> oracle/closure red | `.claude/skills/sims/scripts/run_with_devices.sh major --only notifications.android_typed_reaction_smoke` without `--prepare-builds`; manifest major/full registration |
| TC-392-04 | G24 is a distinct, fully registered payload scenario, not an alias of ordinary permission denial | `scripts/test/notification_tap_campaign_adapter_contract_test.sh::scenario_catalog`; `test/integration/notification_tap_device_criteria_test.dart::G24 app-op divergence artifact is mandatory and exact` | host / catalog, exact manifest assertion set, positive and negative artifacts | causal RED: scenario/check set absent -> catalog, dispatch, cleanup, assertion count, validator requirements and artifact removal include it exactly once; manifest adds exactly `g24.permission_appop_divergence`, `g24.os_state_override_typed`, `g24.no_post_custody_preserved`, `g24.appop_restore_recovery` | remove one surface/check or accept an artifact missing a required G24 field -> contract/negative fixture red | payload shell contract; exact criteria test; existing AUTO classifications |
| TC-392-05 | G24 derives its premises from ADB/log probes and restores both the leg-local and campaign-entry app-op exactly on success or failure | `test/integration/android_notification_payload_campaign_support_test.dart::G24 app-op divergence is probe-derived and restores both baselines` | host / pure known-mode parser, fake ADB choreography, same-window flow-record fixtures | causal RED: no app-op choreography -> capture campaign-entry mode before fresh install, capture leg-local mode before `ignore`, set mutation flag first, restore leg-local for recovery, then after `appStateGuard.restoreAll()` restore/re-read campaign-entry state; absent original package stays absent | hard-code `true`/`ignore`, hard-code restore `allow`, set flag after mutation, restore only before `restoreAll`, use `pm revoke`, or throw between mutation/restore -> host contract red | exact payload support test; AUTO `test/integration/*_test.dart` registration |
| TC-392-06 | On API 33+ Android, Firebase reports authorized while OS posting is disabled; the app narrows it, records exact typed evidence, posts no card, preserves custody, and recovers after exact restore | `notifications.android_payload_campaign::tc_g24_permission_appop_divergence` | device / real `cmd appops`, central APK, FCM, staging relay, emulator receiver | device-only gap: old row uses `pm revoke` -> one cursor captured after `ignore` and before relaunch binds runtime grant `true`, app-op `ignore`, exactly one override `{requestStatus:authorized, osEnabled:false}`, exactly one result `{status:authorized, granted:false, osEnabled:false}`, zero OS-check-failed events, coordinator denied health, zero card, one persisted message, exact restore, and audible-channel recovery | use old revoke path, scan stale logs, drop an event/result field, retain a card, skip custody or restore -> live/negative-artifact red | full existing payload capability; four exact manifest assertions added |
| TC-392-07 | S1-S16's machine contract/discovery stay exact, and raw Flutter child cleanup cannot destroy an installed baseline | `scripts/test/notification_sound_disposition_contract_test.sh::disposition_discovery_and_absent_package_state_boundary` | host / deviceless verdict fixtures plus fake ADB/child lifecycle | causal RED: runner currently starts children without the precondition -> package installed on either target returns BLOCKED/78 with zero mutating ADB/child commands; absent on both captures package-specific card/channel baseline, then guard; restore/readback precede exit 0/passing summary; 16-row oracle stays byte-stable | report package absent while fake `pm path` says installed, launch a child before both checks, remove notification-state comparison/restore, or write PASS first -> contract red; Plan 378 wrong-channel mutations still re-red oracle | sound contract only; discovery-only `sims-contracts --list` registration |
| TC-392-08 | One complete post-G9 S1-S16 run proves direct/group/announcement channel, suppression, debounce, and stable-card behavior on the Android pair | guarded `run_notification_sound_smoke.dart` S1-S16 plus `notification_sound_smoke_summary.json` | device / package-absent USB Android sender + package-absent emulator recipient, real service and Android notification manager | device acceptance gap -> exit 0 after restoring the exact absent/card/channel baseline; exactly S1-S16 once; all programmatic/OS verdicts pass; every applicable lane is complete/nonzero/stable | N/A for behavior mutation here: Plan 378 plus TC-392-07 own causal oracle/restoration mutations | direct unfiltered guarded run with explicit pair and `--non-interactive`; existing reliability discovery, no new capability |
| TC-392-09 | Existing reaction selectors, original nine payload rows, reports, prepared bytes, and unrelated device state survive adoption | runner catalog sentinel; payload/state tests; sound absent-baseline proof; two distinct Sims reports; final exact-state/SHA/app-op evidence | host + device preservation | GREEN sentinels -> seven reaction selectors unchanged, ten payload rows after additive G24, one report per capability; sound restores its required absent baseline and Sims restore captured baselines | remove an old selector/row, bypass sound preflight, reuse one report path, accept stale evidence, mutate prepared SHA, or omit final state/app-op check -> sentinel red | exact commands in Acceptance Gates; no broad family gate because no production file changes |

### Test Notes

- TC-392-02/03 must validate a newly captured raw artifact before writing aggregate Sims PASS. `SIMS_RESULT_JSON` alone is not an oracle. The raw artifact must say `buildMode: central_prebuilt`, `buildProfile: android.production_fcm`, `childBuildCount: 0`, and bind both role APK hashes to the adapter's before/after prepared SHA. A stable proof directory or pre-existing scenario JSON is rejected.
- Prepared execution reuses the existing flag vocabulary: the adapter prepares/restores both targets, then invokes the child with `--prebuilt-android-apk <central-path> --no-child-builds --android-state-prepared`. Standalone Plan 391 mode remains unchanged.
- TC-392-01 must not add the shared proof file to `_captureOwnedBindings`: that generic registry requires an all-file capture-owned classification and would falsely absorb six sibling selectors. The dedicated adapter/manifest contract binds only the named `android_typed_reaction_smoke` oracle.
- TC-392-06 requires all discriminators from one bounded window after app-op mutation and before relaunch: measured runtime grant, measured `ignore`, exact override event, exact result event, no OS-check-failed event, and coordinator denial. The coordinator event alone can come from the old `pm revoke` path.
- TC-392-05 records two app-op baselines for different purposes. The leg-local baseline makes the audible recovery control meaningful; the campaign-entry baseline is restored only after `AndroidAppStateGuard.restoreAll()` because its `pm grant/revoke` restoration may otherwise overwrite app-op state.
- The G24 scenario artifact uses one closed field set: `runtimePermissionGrantedBeforeOverride`, `appOpModeAtCampaignEntry`, `appOpModeBeforeOverride`, `appOpModeDuringOverride`, `appOpModeAfterRecovery`, `appOpModeAfterCampaignRestore`, `permissionOverrideRequestStatus`, `permissionOverrideOsEnabled`, `permissionResultStatus`, `permissionResultGranted`, `permissionResultOsEnabled`, `permissionOsCheckFailedCount`, `permissionDeniedHealthEvent`, `disabledCardCount`, `disabledMessageCount`, and `recoveryAlertChannel`. Criteria require runtime `true`; during-mode `ignore`; override/result `authorized` with `false` OS/final grant; zero failed/card counts; health `PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED`; one message; recovery `mknoon_messages`; and equality to the measured baselines as applicable. Package-absent campaign entry restores to package absent rather than inventing an app-op.
- TC-392-07/08 add only a safe ownership boundary around existing S1-S16 logic. Both read-only package checks and the notification-state snapshot happen before guard/child/mutation. Because the baseline is package-absent, Flutter's child uninstall cannot destroy an existing Keystore. Guard restoration plus exact package-specific card/channel readback are part of exit 0; scenario logic is not redesigned.
- TC-392-08 runs first because its debug-test installs can replace a Sims-prepared install. Its own guard restores the pre-sound baseline before either Sims command captures its baseline.

## Implementation Steps

1. Snapshot `git status --short`; preserve the pre-existing Graphify tooling edits. Add TC-392-01/02/04/05/07 host contracts first and record their causal REDs.
2. Implement one thin typed-reaction Sims adapter and central-prebuilt mode in the existing runner/capture path. Keep standalone mode; create a unique invocation directory; validate raw behavioral and central-build provenance; restore state; audit content-addressed aggregate evidence; emit one sentinel. Append the capability as manifest index 41, support-classify the adapter, and add runtime-root evidence at `capabilities.41.command.2`. Do not exclude/reclassify the shared legacy runner/proof.
3. Before S1-S16 mutates anything, read-check package absence on both targets and snapshot package-specific card/channel state. Installed on either target -> BLOCKED/78 with no child/mutation. For the accepted absent baseline, use one local two-device `AndroidAppStateGuard`; restore in `finally`, re-read exact notification state, and make both prerequisites for exit 0/passing summary. Do not change sound decisions or add a wrapper framework.
4. Add `tc_g24_permission_appop_divergence` to the existing payload campaign. Keep parsing/choreography local. Immediately after `AndroidAppStateGuard.capture()` and before fresh-install mutation, capture campaign-entry app-op/package state; capture leg-local app-op before `ignore`; derive artifact values from ADB and one log window; restore leg-local mode for recovery; after outer state restoration, restore/re-read campaign-entry mode before aggregate PASS.
5. Run focused GREENs, a discovery-only `sims-contracts --list` registration check, the runtime-root inventory check, exact preservation sentinels, scoped analysis, and hygiene. Do not execute the unrelated Sims contract catalog or full `host-all`.
6. When devices are free, resolve and record the live Android pair/API. Run guarded S1-S16 first, then the typed capability, then the full payload capability when the emulator receiver is API33+. Otherwise record only G24's policy N/A and do not claim an aggregate payload PASS. Retain the applicable proof roots, distinct Sims reports, and exact prepared-build hashes.
7. If a device row fails, classify it before editing. Make only a causal in-scope harness repair; any production change, second build profile, recovery activation, or lifecycle policy change requires replanning.

## Risks And Blind Spots

- Central-profile claim: the 1:1 capture currently switches from E2E to normal APK, while Plan 392 deliberately proves the instrumented central profile -> accepted difference plus TC-392-02/03; do not call it release-profile equivalence or add a second build profile.
- False G24 positive: a normal permission denial produces the same coordinator event -> guarded by the runtime-granted + app-op-ignore + override-event conjunction in TC-392-06.
- Destructive device state: raw Flutter cleanup may uninstall the sound app and app-op is outside current guards -> TC-392-07 blocks installed sound baselines before mutation and verifies exact absent/card/channel restoration; TC-392-05/09 own two app-op snapshots, post-guard restore, and failure paths.
- Ownership granularity: legacy exclusions are path-only and the proof file is shared -> TC-392-01 keeps both intact and gives only the exact selector a Sims-manifest owner.
- Stale proof: the direct runner skips capture when raw JSON already exists -> TC-392-02 requires a unique empty directory and raw hashes/profile matching this invocation.
- Report clobbering: Sims defaults both runs to `build/sims/latest/report.json` -> distinct `SIMS_REPORT_PATH` values in the literal closure commands.
- Target capability: G24's divergence relies on API33+ semantics on the emulator receiver -> that receiver's SDK determines proof versus policy N/A; a capable physical sender alone is insufficient, and a failed premise on a capable receiver never becomes N/A.
- Lifecycle / derived-state durability: N/A - this plan changes no production lifecycle or derived state; unread behavior is preservation-only in the existing reaction oracle.
- Sibling-surface consistency: direct typed reaction plus the existing nine payload rows and all sound lanes are explicit; group reaction, mute, iOS, recovery, and N11 are unchanged with named owners.
- Invariant re-verification under new transitions: adapter failure and device-loss paths must still restore state and must never emit PASS without a validated artifact.

## Gate Cadence

- Per-plan closure: the three affected shell contracts; exact named Sims manifest/payload/permission/reaction sentinels; discovery-only Sims-contract registration; runtime-root/full-inventory checks; scoped analysis/hygiene; then the three ordered Android proof commands.
- Time bound: do not run the 44+ unrelated `sims-contracts` scripts, whole Flutter test files when a named row proves the changed contract, any host family sweep, or full `host-all` in Plan 392.
- No `core-host-all`, `feature-host-all`, or full `host-all` is justified: this plan changes harness/orchestration only. Run `./scripts/run_host_test_gates.sh host-all` once after the second notification dependency wave completes and again at final rollout/release closure.
- Shared tests outside feature/core globs run by the exact commands below and remain registered for later aggregate closure.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated changes.
git status --short

# Causal REDs after authoring the tests/contracts, before harness edits.
bash scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh
bash scripts/test/notification_tap_campaign_adapter_contract_test.sh
bash scripts/test/notification_sound_disposition_contract_test.sh
flutter test test/integration/notification_tap_device_criteria_test.dart \
  --plain-name 'G24 app-op divergence artifact is mandatory and exact'
flutter test test/integration/android_notification_payload_campaign_support_test.dart \
  --plain-name 'G24 app-op divergence is probe-derived and restores both baselines'

# Focused GREEN and preservation; all exit 0 with the named target selected.
bash scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh
bash scripts/test/notification_tap_campaign_adapter_contract_test.sh
bash scripts/test/notification_sound_disposition_contract_test.sh
./scripts/run_test_gates.sh sims-contracts --list | \
  grep -F 'bash scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh'
flutter test test/tool/sims/sims_manifest_test.dart \
  --plain-name 'typed reaction reuses the central production APK'
flutter test test/integration/notification_tap_device_criteria_test.dart \
  --plain-name 'G24 app-op divergence artifact is mandatory and exact'
flutter test test/integration/notification_tap_device_criteria_test.dart \
  --plain-name 'G7 permission-denied proof binds attempt, custody, and recovery'
flutter test test/integration/android_notification_payload_campaign_support_test.dart \
  --plain-name 'G24 app-op divergence is probe-derived and restores both baselines'
flutter test test/integration/android_notification_payload_campaign_support_test.dart \
  --plain-name 'permission-denied leg separates an OS precondition from a defect'
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'each capture branch stem matches its scenario id'
flutter test test/features/push/application/request_push_permission_use_case_test.dart \
  --plain-name 'emits PUSH_PERMISSION_OS_STATE_OVERRIDE and an honest RESULT when the OS overrides an authorized request'
./scripts/check_runtime_root_inventory.sh check --format text
bash scripts/test/sims_full_inventory_contract_test.sh

# Sims discovery; each selected plan contains the capability exactly once.
dart tool/sims/sims.dart major --only notifications.android_typed_reaction_smoke \
  --list --format json
dart tool/sims/sims.dart major --only notifications.android_payload_campaign \
  --list --format json

# Scoped analysis and hygiene.
dart analyze \
  integration_test/scripts/run_1to1_reaction_notification_sims.dart \
  integration_test/scripts/run_1to1_reaction_notification_device.dart \
  integration_test/scripts/capture_1to1_reaction_head_provenance.dart \
  integration_test/scripts/run_notification_sound_smoke.dart \
  integration_test/scripts/notification_android_payload_campaign.dart \
  integration_test/scripts/run_notification_tap_device_real.dart \
  integration_test/one_to_one_reaction_notification_proof_test.dart \
  test/integration/notification_tap_device_criteria_test.dart \
  test/integration/android_notification_payload_campaign_support_test.dart \
  test/tool/sims/sims_manifest_test.dart
git diff --check

# Device discovery only when execution reaches the boundary phase. Record literal IDs.
flutter devices --machine
adb devices
export PLAN392_PHYSICAL_ANDROID_ID='<discovered-usb-android-id>'
export PLAN392_ANDROID_EMULATOR_ID='<discovered-android-emulator-id>'
adb -s "$PLAN392_PHYSICAL_ANDROID_ID" shell getprop ro.build.version.sdk
adb -s "$PLAN392_ANDROID_EMULATOR_ID" shell getprop ro.build.version.sdk
export MKNOON_RELAY_ADDRESSES='<staging-relay-multiaddrs>'
export SIMS_PROVIDER_FCM_CREDENTIAL_PATH='<fcm-service-account.json>'
export MKNOON_257_RELAY_TARGET='<staging-relay-ssh-target>'
export MKNOON_257_RELAY_KEY='<staging-relay-ssh-key>'
export MKNOON_257_STAGING_MANIFEST='<staging-manifest.json>'
export SIMS_NOTIFICATION_RELAY_TARGET="$MKNOON_257_RELAY_TARGET"
export SIMS_NOTIFICATION_RELAY_KEY="$MKNOON_257_RELAY_KEY"

# Run first: its state guard restores the baseline after the debug-test installs.
dart run integration_test/scripts/run_notification_sound_smoke.dart \
  -d "$PLAN392_PHYSICAL_ANDROID_ID,$PLAN392_ANDROID_EMULATOR_ID" \
  --artifact-dir build/plan392/sound-smoke \
  --non-interactive

# Then execute (not merely prepare) the two Sims-owned proof legs. Separate
# report paths prevent the second run from overwriting the first run's report.
SIMS_REPORT_PATH=build/plan392/typed/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN392_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN392_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only notifications.android_typed_reaction_smoke

SIMS_REPORT_PATH=build/plan392/payload/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN392_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN392_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only notifications.android_payload_campaign
```

## Device/Relay Proof Profile

- Profile: paired-device + OS-notification + staging relay.
- Boundary being proven: Android NotificationManager/app-op behavior, real FCM/relay delivery, killed-recipient typed reaction, OS card/channel state, tap routing, and cross-device unread lifecycle.
- Live availability check: deliberately not run during planning/review. At execution, `flutter devices --machine` plus `adb devices` must yield one USB physical Android sender and one Android emulator receiver; their literal IDs and SDK levels are recorded before use. If the emulator receiver is below API 33, G24 alone is `N/A (target unavailable by project policy)` and the payload aggregate is not represented as G24 PASS even when the physical sender is API33+. No unavailable version-specific target blocks the other rows.
- Required setup: unlocked USB Android and Android emulator on which `com.mknoon.app` is absent for the sound leg, FCM service-account path, exported staging relay addresses/SSH target/key/manifest expected by the adapters, one centrally prepared `android.production_fcm` APK, distinct writable proof/report paths, and enough local space for exact state backups. The runner verifies absence read-only and blocks rather than uninstalling; all later setup/navigation/actions/assertions are automated.
- Two-peer default: physical Android sender + Android emulator recipient. No iPhone and no user taps.
- Closure role: required availability-bounded closure evidence; host tests supplement but do not replace these OS/relay claims.
- `FLUTTER_DEVICE_ID`: host selector only; both explicit Android IDs are still required.
- Registration: S1-S16 stays in reliability discovery; typed reaction is one new appended Sims major/full capability, one support discovery record, and one runtime root; G24 extends the existing Android payload capability. The shared runner/proof classification and legacy full path remain unchanged.
- Discovery commands: the two `dart tool/sims/sims.dart ... --list --format json` commands above plus the sound contract's 16-row census.
- Closure commands: the three ordered commands above. Success on the availability-bounded live matrix means the sound summary has S1-S16 complete after restoration; the typed report is PASS with fresh raw and audited aggregate evidence; and the payload report either passes G24 on a genuinely settable receiver or records the exact policy-N/A classification when the configured receiver rejects the runtime-backed override. Prepared bytes and exact package/data/permission/process/app-op state must restore in every outcome; a policy-N/A G24 row is never mislabeled as an aggregate PASS.
- Deferred device work: recovery, N11, G21/G27, Plan 388 Wave 3, iOS, and OEM remain outside this plan with the owners named above.

## Execution Interpretation And Done Criteria

- Expected RED: the new typed Sims contract fails because the adapter/capability/central path are absent; G24 catalog/criteria/support tests fail because the scenario and reversible app-op choreography are absent.
- Green sentinel: existing Plan 391 proof support, seven reaction selectors/shared proof classification, nine original payload rows, S1-S16 dispositions, and scenario discovery stay green.
- Pre-existing dirty tree: planning began clean, then unrelated concurrent edits appeared in `graphify-arch/GRAPH_SELECTION.md`, `graphify-arch/tdd_context.py`, `graphify-arch/tests/test_graphify_arch_tooling.py`, and `graphify-arch/query-benchmark.json`; preserve and exclude them from Plan 392 attribution.
- Environment blocker: missing credentials/relay, a device disappearing mid-run, or an already-installed app at the sound preflight is typed environment evidence; the sound case blocks before mutation and never auto-uninstalls. Unavailable hardware/version is policy-bounded N/A, never a product failure. A behavior assertion on an available prepared target is a test failure.
- Scope drift: any required `lib/`, native production, DB, relay, lifecycle, recovery, or wire change blocks this plan pending replanning.

- [x] Every row has a named automated host test or real device proof. TC-392-08 completed all sixteen positive device rows after the user-authorized exact-package uninstall established the required absent baseline; the fail-before-mutation installed-package negative proof remains green too.
- [x] Causal REDs, focused GREENs, and representative mutation re-reds are recorded; S1-S16 behavior acceptance reuses Plan 378's recorded oracle mutations while the new state-owner mutation is recorded here.
- [x] Typed reaction has exactly one Sims-manifest owner; its adapter is support/runtime-root registered without absorbing the shared runner/proof; it uses one unchanged central artifact, performs zero child builds, rejects stale raw evidence, and emits audited aggregate evidence.
- [x] G24 derives granted runtime permission plus ignored app-op and exact override/result events from real probes on a genuinely settable target, posts no card, preserves custody, then restores both app-op baselines and proves recovery. A receiver below API 33 **or one whose platform rejects the runtime-backed override** is recorded only as policy N/A; API-37 produced that exact final result and no aggregate G24 PASS was claimed.
- [x] The payload capability retains all pre-existing rows; all ten rows and 31 assertions stay host-registered/validated. The live API-37 receiver is policy-N/A for G24, so the distinct payload report is `BLOCKED/targetUnavailable`, not an aggregate PASS; the original-row preservation sentinels remain green.
- [x] S1-S16 proved both packages absent before mutation, ran unfiltered, and exited 0 with exactly sixteen complete rows. Every programmatic and OS verdict passed; direct/group/announcement card identity was stable at 6/6, 4/4 and 4/4 observations; and package/card/channel state restored exactly to the absent baseline. The installed-package negative fixture still launches no child and mutates nothing.
- [x] Harness, manifest, runtime-root, and discovery registration are verified; no whole-runner legacy exclusion or shared-proof reclassification was introduced.
- [x] Typed and payload Sims reports are retained at distinct paths. The typed PASS binds content-addressed evidence; the payload report retains the policy-N/A verdict without fabricating passing evidence.
- [x] Scoped analysis has no issues; `git diff --check` is clean; unrelated Graphify edits are preserved.
- [x] The Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `bash scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh` after adding its expectations; it must fail because the adapter/capability do not exist.
- Preservation command: `bash scripts/test/notification_sound_disposition_contract_test.sh` plus the exact Plan 391/payload support tests above.
- Manual registration: append one manifest capability; add one adapter support-discovery record and one JSON runtime root; extend the existing payload capability with four G24 assertions/check surfaces. No legacy path exclusion, shared-proof reclassification, or separate G24 capability.
- Migration: none.
- Boundary closure: completed on physical Android `21071FDF600CSC` + emulator `emulator-5554`: sound PASS, typed Sims PASS, and payload G24 policy-N/A on the API-37 receiver after exact restoration.
- Residual device evidence: none inside Plan 392. A future already-available Android target with a genuinely settable runtime-backed notification app-op may add optional G24 confidence, but unavailable hardware is not a closure condition and neither a second APK nor `pm revoke` is an allowed substitute.

## Reviewer Findings

Initial `$tdd-review` verdict: `plan-fixes-required`; disposition: `apply-plan-fixes`.

- R1 blocking: the typed closure command used `--prepare-builds`, which rewrites the plan to build rows and never executes the capability. Removed from the closure command.
- R2 blocking: stable raw artifact paths could let the existing runner validate stale evidence. Required a unique empty capture directory plus raw/aggregate prepared-SHA/profile binding and a stale-preseed negative fixture.
- R3 blocking: S1-S16 installed/granted before any exact state owner, so later Sims guards would preserve an already-mutated baseline. Added an absent-package preflight, one local guard lifecycle, exact notification-state readback, and restoration before exit 0.
- R4 blocking: restoring G24 app-op before `AndroidAppStateGuard.restoreAll()` can be overwritten by its runtime-permission restore. Required separate leg-local and campaign-entry baselines, with final restore/readback after the outer guard.
- R5 plan-fix: the shared proof validates seven selectors and cannot honestly become capture-owned; whole-path legacy exclusion would hide six siblings. Both overbroad edits were removed.
- R6 plan-fix: adapter support discovery, appended manifest registration, runtime-root evidence, and exact manifest/runtime-root gates were missing. Added them without a new abstraction; the broad Sims-contract lane is checked only with `--list`, while the affected shell contracts run directly.
- R7 plan-fix: G24 evidence could be hard-coded or swept from stale logs. Required ADB-derived values, an exact cursor-bounded event/result window, negative fixtures, and two exact restore cuts.
- R8 plan-fix: missing relay exports and shared default Sims report paths caused preflight failure/report overwrite. Added explicit prerequisites and distinct report paths.
- R9 plan-fix: per-leg N/A was not representable by the atomic payload capability. Limited policy N/A to an emulator receiver below API33 and prohibited claiming aggregate G24 PASS in that outcome.
- R10 final command audit: the typed adapter and payload runner consume different relay aliases. Exported `SIMS_NOTIFICATION_RELAY_TARGET/KEY` from the same staging values and pinned G24 capability to the emulator receiver.
- R11 final reversibility audit: raw Flutter integration-test cleanup can uninstall the app, and Keystore state cannot be reconstructed afterward. Bounded S1-S16 to package-absent targets and required a negative preflight fixture with zero mutation/child launches.

## Arbiter Decision

Final verdict after source recheck: `ready`.

- Accepted every behavior, false-PASS, reversibility, command, and registration blocker above.
- Chose a local guard in the existing sound runner rather than a new wrapper/framework.
- Rejected reviewer suggestions that implied excluding the full legacy runner or adding the shared proof to the capture-owned registry; both are broader than the one-selector adoption and would reduce sibling visibility.
- Kept typed adoption, G24, and the existing S1-S16 acceptance run in one plan. Their shared boundary is Android notification E2E closure; only recovery/N11/Wave-3 correctness work remains separate.
- Applied the user's time constraint after review: only causal/new tests and one exact preservation sentinel per changed surface execute; aggregate registration is discovery-only and all host-family sweeps remain deferred.
- No user-owned product decision remains. Execution may start with the listed causal REDs and must stop on the named scope boundaries.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-20 | causal REDs | new typed Sims shell contract; sound/payload shell contracts; G24 criteria/support tests; Sims manifest test | all five prescribed RED surfaces exit 1: adapter missing; payload catalog 9≠10; sound preflight missing; G24 validator rejects; app-op parser absent | failures are causal and isolated to TC-392-01/02/04/05/07; pre-existing Graphify edits preserved | none; implementation stays harness-only | typed adapter and local state/probe seams |
| 2026-08-20 | implementation GREEN | typed adapter/runner/capture/proof; sound state boundary; payload G24 runner/support/criteria; Sims manifest/runtime/discovery | three shell contracts PASS; all exact Plan-392 and preservation Flutter rows PASS; runtime-root `trustworthy: true`, `drift: false`; full-inventory and exact Sims discovery PASS; scoped analysis clean | exactly one typed capability; one central profile; zero child builds; G24 is the tenth payload row with 31 manifest assertions; sound checks package absence before guard/child/mutation | no production `lib/`, native, DB, relay or wire changes | ordered live matrix |
| 2026-08-20 | sound preflight RED and authorized baseline transition | `run_notification_sound_smoke.dart` on `21071FDF600CSC,emulator-5554` | first live attempt returned `BLOCKED/78 package_installed_before_sound_smoke` before setup; the user then explicitly authorized uninstalling only `com.mknoon.app` from those two exact targets | the negative boundary proved fail-before-mutation, and the authorized removal established the plan-required package-absent pair without broadening destructive scope | none | run the unfiltered positive campaign |
| 2026-08-20 | sound device PASS | `build/plan392/sound-smoke/notification_sound_smoke_summary.json` | wrapper exit 0; both Flutter children `All tests passed`; run `1787244621233`; summary SHA `4fed5a4b72edd015adb432808fba6fc3e6fbb64ee29c406662b2fc353b5a2c1f` | exactly S1-S16; all sixteen `programmaticPass=true` and `osNotification.pass=true`; direct/group/announcement stable ids 6/6, 4/4, 4/4; `androidStateBoundary.restorationVerified=true`; package/card/channel hashes identical before/after and both packages absent | none | typed capability |
| 2026-08-20 | typed Sims device PASS | `notifications.android_typed_reaction_smoke`; distinct report `build/plan392/typed/report.json` | final hardened run PASS assertions=1; zero actual builds, one central cache hit; content-addressed evidence SHA `b509372f8fccf5e0046def6257ebfa305220ca6b68cce69e8e62578054b2f4ce` | APK SHA `d7eff44b400426a734e1215f153e349559e73657dac10dba4a1b98420472e7d7` before/after, both roles, `childBuildCount=0`, `appStateRestored=true`; raw capture SHA `fc983b0cef98a12d1ed698356b5d4617bcc2db99555dbed8048e35dfdff0ba31`; existing Plan-391 behavior oracle passed | none | payload capability |
| 2026-08-20 | live-harness TDD hardening | typed capture, sound shade capture, payload package census | causal REDs reproduced stale contact deletion, Orbit all-chats readiness, the prelaunch Android notification permission prompt, notification-shade retry collapse, and API-37 `pm path` exit-1/empty absence | completion-receipt-bound fixture cleanup; bounded semantic readiness and Orbit inner-circle recovery; prelaunch `POST_NOTIFICATIONS` grant under exact restore; dump-before-scroll SystemUI verification; and a pure fail-closed package census now cover each measured failure | none | rerun all three device boundaries unchanged |
| 2026-08-20 | G24 live classification | `notifications.android_payload_campaign`; distinct report `build/plan392/payload/report.json` | final report SHA `7190662e0821ecefbf1da731c7feb2890fb2b55f061ce51f927a04a1a9a729b2`; `BLOCKED`, `blocker: targetUnavailable`, exitCode 78; zero child builds and one central cache hit | unchanged run reached G24 after the earlier campaign rows; Android 17 logged `Blocked setUidMode call for runtime permission app op`; final package census was absent on both targets and no aggregate G24 PASS/evidence was fabricated | G24 is `N/A (target unavailable by project policy)` on the configured emulator | final host gates and map reconciliation |
| 2026-08-20 | final host/registration closure | all Plan-392 host files, manifest/runtime roots/discovery, Graphify impact set, UI-23 map | three shell contracts PASS; focused Flutter suite 192 PASS; Graphify-adjacent preservation suite 25 PASS; typed artifact oracle PASS; runtime inventory trustworthy/no drift; full inventory PASS; exact capability discovery PASS; scoped analysis clean; incremental Graphify refresh complete; `git diff --check` clean | UI-23 §4.13 records typed recurrence, S1-S16 behavior/state closure, and G24 policy-N/A; no Plan-392 item remains in §4.14 | none | complete |
