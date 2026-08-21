# 393 - Android Notification Lifecycle, Killed-Path, And Recovery Closure

Status: EXECUTION-COMPLETE / required Android device + host closure PASS / final Android-led notification plan / not release-eligible
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md`; Plan 392 closure; user request to finish the required Android-led implementation and E2E gaps
Classification: evidence-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-20 | Evidence Collector | Plan 392 closure; both UI-23 assessments; Plans 374, 375, 384, 388, 389, 391; current notification, relay, Sims and device-runner source | Plan 392 closed typed recurrence and S1-S16, but deliberately deferred N11, recovery activation, G21/G27, strict device proof and Plan-388 Wave 3 | consolidate the remaining required Android work |
| 2026-08-20 | Planner | Graphify TDD snapshot plus current source/tests named below | One final plan with four ordered slices is sufficient; separate plans would split shared device fixtures and recovery evidence without isolating a deployment boundary | independent `$tdd-review` |
| 2026-08-20 | Independent Reviewers | review-profile Graphify snapshot; current Dart/Go/Kotlin/Sims owners; literal commands and restoration order | Plan-fixes-required: successful G21 timing and downstream headroom were unobservable; recovery could publish PASS before restore; fixed-wake selection and G30 were absence-heavy; strict/recovery registration and old-assertion disposition were underspecified; focused sound claim was false | apply the smallest causal fixes, then rerun review |
| 2026-08-20 | Independent Reviewers, final rerun | revised Test Contract, acceptance commands, strict/recovery/G21/G30 source boundaries | READY: all false-PASS, cleanup-order, registration, assertion-mapping and command-order blockers are closed; no split or added framework is justified | hand off the evidence-gated causal REDs |

## Problem And Evidence

- Behavior to improve: Android notification presentation must make the final lifecycle/read decision at the last safe boundary, survive first-wake storage delay, wake the correct strict-group reaction author, and recur through real killed/background recovery simulations.
- Impact: a background-mounted direct chat can mark unread content read; an exact-chat activation can leave a stale card; compatibility/fallback paths can post after the chat becomes visible or the event becomes read; G21 can stage a message but lose its alert; strict-authority reactions remain silent custody; and the dormant recovery capability cannot prove the fixed-wake architecture or the durable first-delivery reaction outcome.
- Plan 392 outcome and limitations:
  - `notifications.android_typed_reaction_smoke` is now recurring and passed with one central APK, and S1-S16 passed 16/16 with exact state restoration.
  - G24 is terminal policy-N/A on the available API-37 emulator because Android rejects the required runtime-permission/app-op divergence. It is not work for this plan.
  - Plan 392 explicitly left N11, recovery activation, G21/G27, fixed wake and Plan-388 Wave 3 to this successor.
- Confirmed implementation gaps:
  - N11 read eligibility is fail-open. Direct initial/recovery/live triggers reach `_markAsRead()` without requiring resumed lifecycle plus the exact tracked peer at `lib/features/conversation/presentation/screens/conversation_wired.dart:1381-1458,2215,2437,2643-2663,7717-7728`. Group still treats unknown lifecycle and an absent tracker as readable at `lib/features/groups/presentation/screens/group_conversation_wired.dart:723-736`.
  - Exact activation cleanup is still coupled to read/tap. `AppVisibilityRouteRegistry._becameTop` synchronously owns the exact active conversation at `lib/core/notifications/app_visibility_route_binding.dart:154-160`, but it does not retire that conversation's captured notification generation.
  - The durable anchored path already has a correct final barrier at `lib/core/notifications/durable_local_notification_effect_coordinator.dart:487-514`; the remaining holes are narrower: compatibility publication supplies `() async => true` at `lib/features/push/application/show_notification_use_case.dart:378-387`, unanchored group fallback evaluates visibility before projection then calls the service directly at `background_push_notification_fallback.dart:488-522`, and background nondurable publication authorizes unconditionally at `background_message_handler.dart:1251-1254` before direct/group canonical checks run only after the native post.
  - G21 remains a real rich-compatibility defect. `display_eligibility` uses the ordinary two-second phase bound and records `storage_deferred` then returns at `background_message_handler.dart:718-730`, before either policy suppression or presentation. The resolver includes account/block/archive/membership/mute authority; a policy-blind generic card is therefore forbidden. The wake already has an eight-second aggregate bound at `:78-85`.
  - G27 is a production relay gap. `go-relay-server/group_content_push.go:54-97` recognizes strict group reactions but marks them ineligible; `go-relay-server/inbox.go:2137-2179` then returns with silent custody. The existing signed author-device parser and typed reaction builder are at `go-relay-server/reaction_push.go:130-297,454-540`.
  - G30 is current, not historical. Plan 392's retained typed log contains `PUSH_BACKGROUND_DIRECT_POST_SHOW_UNKNOWN` with `SqfliteDatabaseException`; current direct post-show validation opens then closes a nominally independent read-only handle at `background_message_handler.dart:1492-1550,1794-1821`. `openEncryptedDatabaseReadOnlyTolerant` already requests `readOnly:true, singleInstance:false` at `lib/core/database/encrypted_db_opener.dart:190-223`, so the exact owner is unresolved and must be reproduced before a fix is selected.
- Confirmed test/recurrence gaps:
  - `notifications.android_recovery_completion` is required and active but `automationReady:false` at `tool/sims/critical_features.json:706-724`. Its current validator requires six scenarios in both receiver roles, pins historical device IDs, and its source preflight requires three files that do not exist. Completing that twelve-leg Plan-331 design would duplicate newer Plan-374/375 owners, but narrowing it is allowed only after every old assertion is mapped to a retained owner or explicitly retired below.
  - The durable direct-reaction probe is honestly RED: the visually correct card came from the nondurable fallback because the app's canonical event arrived after the wake decision. A card-only assertion cannot close this. First-delivery durable recovery must use the existing fixed-wake/WorkManager/canonical-presentation-and-generic-retirement vehicle, not a manifest flip.
  - Strict group messages are host/deploy green but no phone has observed the card. Strict reactions need both the G27 production change and an author-only device observation. One shared strict fixture can prove both.
  - G22b still needs one representative killed incoming group-media message. Existing `groups.notification_projection_durability` proves reactions to photo/video/voice targets, not a killed recipient receiving the media message itself.
  - Plan-388 Wave 3 is partly stale: Plan 389 already refreshed the announcement reaction. Only the existing `groups.notification_projection_durability` media-reaction capability needs one current run; it can carry the new killed-photo leg in the same invocation.
  - The fixed-wake mechanism already has injected Android proof in Plans 374/375. The missing boundary is live relay/FCM selection under a controlled client cohort, followed by silent generic fallback, WorkManager canonical recovery, canonical presentation plus retirement of the reserved generic card, and no duplicate or second tone. The two cards do not share an ID and must not be described as a stable-ID replacement.
- Refuted findings:
  - Do not rerun the ordinary five-scenario group campaign or full S1-S16: both are current device-PASS evidence. Only S4 is regraded from that runner; the new strict fixture owns group exact-chat suppression and the new recovery fixture owns background-connected behavior.
  - Do not turn G11 suffix dispatch into work. It no longer blocks a required scenario.
  - Do not build the old twelve-leg recovery campaign or the three missing Plan-331 observer files. Retarget its existing manifest owner to one causal scenario using the shipped Plan-374/375 mechanism.
  - Do not treat a generic timeout card as a G21 repair, call full `fanOutGroupReactionPush` from strict per-recipient custody, or infer G30's root cause from the exception name.
- Unresolved findings:
  - G21's current warmed profile-AOT timing and downstream tail are unmeasured. The first execution checkpoint adds a measurement-only, identifier-free success receipt and, only in that instrumented build, lets `display_eligibility` use the raw aggregate remainder so the current two-second failure cannot erase the tail being measured. The receipt also records aggregate elapsed/remaining time at eligibility start because direct staging already consumed part of the eight seconds. Production behavior is unchanged during measurement. If eligibility cannot fit the measured eligibility-start remainder while preserving the reserve rule below, this plan stops instead of inventing a new deadline or unsafe fallback.
  - G30's app-owned repair is not yet proven. If causal reproduction requires a SQLCipher plugin fork or cross-engine database lease architecture, this plan stops and is amended; it does not hide the exception or add a database manager.
- Affected production, test, and gate files: the named direct/group conversation, app-visibility, notification presentation/background handler, encrypted-opener (only if causal), dropped-push/fixed-wake composition, Go strict-content/reaction files, existing 1:1/group/recovery capture and criteria files, `tool/sims/critical_features.json`, `tool/sims/build_orchestrator.dart`, runtime/discovery registration, exact tests below, both UI-23 assessments, this plan and the index.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `f9c2ab443d0fde0c`; current at the planning query.
- Query / profile: `python3 graphify-arch/tdd_context.py query "background_message_handler display_eligibility storage_deferred group_content_push strict group reaction conversation_wired _markAsRead notification recovery completion DirectNotificationPresentationCoordinator WorkManager fixed wake canonical replacement" --profile tdd --budget 700` -> `confidence=anchored`.
- Independent review queries / profile: `python3 graphify-arch/tdd_context.py query "Plan 393 counterexamples Android notification lifecycle final barrier G21 display eligibility G30 SQLCipher strict group reaction recovery fixed wake Sims profile group media" --profile review --budget 800`, refined once with `AppVisibilityRouteRegistry._becameTop`, `publishAtNativeBoundary`, `extractGroupContentPushMetadata` and the recovery runner -> `confidence=anchored`.
- Anchors: direct `_markAsRead` -> `conversation_wired.dart`; `DirectNotificationPresentationCoordinator` -> direct presentation/read ownership; background handler -> storage deadline and nondurable publication.
- Surfaced proof/gate files: direct/group notification projector and presentation tests.
- Graph gaps requiring source search: Sims manifests/adapters, Go strict direct-inbox routing, Android debug receiver, shell registration and retained device artifacts; every load-bearing claim above was checked in current source.
- Reuse rule: these anchors seed review/execution; graph output is not acceptance evidence.

## Scope Contract And Guard

In scope:
- Slice A — N11 presentation authority: require `resumed && exact non-null tracker` for every direct/group local read trigger; cancel only the captured current generation after both a new exact top-route transition and resume-time `republishCurrentTopConversation`, independently of SQL read; and add a last-moment authorizer to compatibility direct/group, unanchored group, raw direct-message/reaction and nondurable paths using existing visibility/canonical readers. Non-conversation intros remain unchanged.
- Slice B — rich first-wake and database liveness: add one measurement-only, identifier-free receipt for a warmed profile-AOT direct-text first wake, including successful eligibility and downstream-native-entry elapsed time; allow raw aggregate remainder only in that instrumented measurement build, then give production `display_eligibility` a named bound of `aggregate remainder - evidence-backed downstream reserve`; diagnose G30 on the base-profile rich typed path, then apply only a causally proven app-owned opener/handler repair and emit a positive closed-domain validator disposition.
- Slice C — strict/group killed paths: wire the existing `GROUP_REACTION_PUSH_ENABLED` setting into `InboxStore`; add one per-recipient strict-reaction wake using the existing signed author list and group-reaction push builder; add one Sims-owned strict fixture covering exact-chat suppression, a killed strict message and an author-targeted ADD reaction; extend the existing projection capability with one fixed killed incoming JPEG/photo phase.
- Slice D — recurring recovery/fixed wake: map and retire the stale Plan-331 assertion shape, then narrow the dormant capability to one physical-sender -> emulator-receiver direct-reaction scenario containing distinct background-connected and killed transitions. Run it under literal build profile `android.production_fcm.fixed_wake`, build capability `build.android.production_fcm.fixed_wake`, and prepared-artifact environment `SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE`; its defines are the base profile's exact three defines plus only `MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR=true`.

Must preserve:
- Unknown/stale visibility, background/other-chat state and unresolved canonical facts continue to fail toward notification; only fresh foreground-active exact-chat or verified exact read/delete/retire may deny native entry -> TC-393-03/04.
- Dismiss never marks read; activation cleanup never marks read; read cancellation remains exact-generation; a newer same-conversation generation and every other conversation survive -> TC-393-01/02.
- G17's authority-null rich compatibility fallback remains available outside the controlled fixed-wake cohort; the new cohort proves the intended first-delivery durable architecture without globally activating it -> TC-393-11/12.
- Eligibility remains policy-complete: delayed muted/blocked/archived/removed/wrong-account decisions yield zero cards, while delayed eligible content yields one; the aggregate hard stop and every other two-second phase stay bounded -> TC-393-05.
- Strict custody remains durable for all recipients. ADD alerts only signed target-author devices; bystander, REMOVE, malformed/tampered, disabled, unauthorized, incapable and duplicate rows store without a wake -> TC-393-07.
- The existing five group scenarios, three media-reaction kinds, Plan-392 typed scenario, Plan-374/375 native invariants, base `android.production_fcm` defines/cache identity and S1-S16 dispositions remain unchanged -> preservation commands below.
- Every touched runner uses its existing exact state owner (`AndroidAppStateGuard` for Sims adapters and the direct capture's incumbent package/data guard), restores owned package/data/permission/process state in `finally`, uses a unique fresh evidence directory, binds evidence to the prepared APK/profile and performs zero child builds except the explicitly one-off profile-AOT measurement build. Because these state owners do not restore OS notification cards, each campaign requires a zero app-card baseline before mutation (`BLOCKED/78` otherwise), cancels only its campaign cards, and verifies the zero baseline before PASS. The S4 sound runner retains Plan 392's narrower read-only package-absence preflight and absent-baseline guard; an installed package returns `BLOCKED/78` before mutation. A durable aggregate PASS is published only after relay cleanup, card cleanup, local restoration and post-restore readback succeed; a failure retains backups and no valid PASS artifact.
- The controlled cohort uses a fresh ephemeral test identity whose route must not survive the campaign. While that identity is still active, its `finally` path authenticates `inbox:unregister_token` through the existing seam and verifies the test route is absent; it never treats the post-setup fixed-wake capability set as a restorable baseline. Only after route absence and zero-card readback does it call `AndroidAppStateGuard.restoreAll()`. It never relaunches the restored incumbent app or mutates an unrelated incumbent route to republish capabilities.

Hard `Do not`:
- Do not add a notification architecture, second ledger, new queue/scheduler, generic device framework, database manager, SQL schema/version, wire format, notification copy redesign or global fixed-wake activation.
- Do not call `fanOutGroupReactionPush` from strict direct-inbox custody; that seam is already per recipient and full fanout can duplicate/wake the wrong device.
- Do not fall back to a generic G21 card, extend the aggregate above eight seconds without new evidence, suppress on unknown/stale authority, or make durable SQL authority from an outer/provider identity alone.
- Do not implement the old six-scenario x two-role recovery matrix or create the three missing Plan-331 receiver/observer/campaign files.
- Do not add a third-device bystander leg, all-media x all-group-type matrix, announcement rerun, full S1-S16 rerun, ordinary group 5/5 rerun, payload/G24 rerun, mute campaign, iOS, OEM, release rollout or production deployment.
- Do not fix unrelated G28 or use aggregate `sims-contracts` as a closure signal.

Deferred / accepted difference:
- iOS/APNs/NSE, release/production cohort activation, Doze/OEM/token-refresh rollout evidence and Android MessagingStyle -> consolidated platform/release work, explicitly excluded by the user.
- Non-author bystander device proof -> optional third-Android follow-up. Host proof must establish delivery/custody plus author-list discrimination; a vacuous zero-card proxy is forbidden.
- Every media/group-type/flavor combination -> unnecessary. One killed JPEG exercises the shared message seam; host policy tests cover content-agnostic branches.
- Rich compatibility first-delivery may remain nondurable outside the controlled cohort. It must still alert once and pass the new final authorizer; controlled fixed wake owns the durable first-delivery claim pending later release activation.
- G21 timing uses a warmed, instrumented profile-mode AOT receiver because it permits bounded receipt extraction without opening a production diagnostics surface. It is not release acceptance or rollout evidence; the fixed production deadline is still host-tested and the explicitly excluded release phase owns independent release-mode confirmation.
- Actual sound pressure/haptics -> not claimed. The plan asserts requested tone ownership and OS notification state.

Dependencies:
- Plan 392 is complete and provides state-safe S4/S15/S16 plus recurring typed-reaction proof.
- Plans 374/375 provide fixed ingress, silent generic fallback, WorkManager, canonical presentation and generic-retirement owners; Plan 384 provides strict-message relay behavior; Plan 389 provides current ordinary group/reaction evidence.
- Device execution resolved to USB Android `21071FDF600CSC` plus Android emulator `emulator-5554`, real FCM credentials, and zero manual taps. Missing version-specific hardware remained policy-N/A only for that hardware-specific row.
- The strict/projection rows used the tested relay-server v1.9.0 boundary. Recovery used a disposable instance of the production relay code with encrypted route state and the wake-outcome ledger in ephemeral Redis. No production deployment or migration was part of this plan.

Stop-if conditions:
- If the warmed profile-AOT probe cannot positively measure successful eligibility, `remainingAtEligibilityStart` and final native-entry tail even when its measurement-only flag gives eligibility the raw aggregate remainder, or if `eligibilityPhaseElapsed > remainingAtEligibilityStart - reserve` where `reserve = max(existing two-second phase bound, measured tail + 500 ms)`, retain the measurement and stop/replan G21; do not notify without policy or guess a larger deadline.
- If G30 reproduction points outside the app-owned opener/handler boundary to plugin or cross-engine lease architecture, retain the causal evidence and stop/amend before implementation. Logging suppression or removing every `close()` is not closure.
- If exact fixed-wake route selection cannot be positively attributed after measured registration/readiness on the controlled profile, stop at the failed capability; do not substitute an injected wake, a shared provider-success delta or a rich FlutterFire card.
- If the available pair cannot construct strict authority, treat that as a fixture/harness failure, not hardware N/A. If either target itself is unavailable, only device rows are policy-N/A; host implementation remains required.

### Recovery assertion disposition (before manifest edits)

| Current assertion | Disposition in Plan 393 | Retained/new owner |
|---|---|---|
| `notifications.headless_direct_group_recovery` | Retain as host/native safety, do not repeat twelve device legs | Plan-374 `TC-374-02` exhaustive direct/group adapters and `TC-374-08` real process-death proof; exact preservation test here |
| `notifications.foreground_handoff_new_generation` | Retain as host concurrency safety; the new device transition uses a distinct second reaction/cursor | Plan-374 `TC-374-06` foreground/headless handoff plus TC-393-13 distinct-transition oracle |
| `notifications.direct_custody_recovery` | Retain and specialize to authenticated direct reaction | New TC-393-12 production-headless direct-reaction row plus TC-393-13 device proof |
| `notifications.synthetic_outer_id_recovery` | Retire as obsolete and unsafe | Plan-375 `TC-375-04` requires an identity-free wake and forbids synthetic event authority; canonical authenticated reaction identity replaces the old synthetic-ID premise |
| `notifications.history_count_projection` | Retain outside recovery matrix | Existing `conversation_notification_snapshot_test.dart`; exact `flutter_notification_service_test.dart::android conversation card carries canonical history and uncapped number`; and the one `groups.notification_projection_durability` invocation |
| `notifications.registration_health_live_recovery` | Split its concerns rather than repeat them on device | Plan-375 `TC-375-07` plus `push_registration_coordinator_test.dart::transient failures warn at three and success clears live` own threshold/retry/clear; `push_registration_health_surface_test.dart::permission warning is localized and opens notification settings` and `::safe transient reason uses Retry and never renders raw errors` own warning actions; TC-393-11/13 own live fixed-route registration/readback |
| `notifications.recovery_copy_locales` | Retain as exact native host proof, not a device matrix | `MknoonFirebaseMessagingServiceTest` locale rows plus `android_recovery_string_resources_test.dart` |
| `notifications.zero_taps_zero_child_builds` | Retain in the narrowed capability | TC-393-12/13 aggregate evidence, with the central Sims build counted separately from runner child builds |

The manifest assertion list changes only after a contract test proves this table has one disposition per old assertion. No old device leg is deleted merely because the new artifact is smaller.
The narrowed capability then owns exactly:
`notifications.fixed_wake_live_route_selected`,
`notifications.direct_reaction_canonical_recovery`,
`notifications.generic_recovery_card_retired`,
`notifications.no_duplicate_or_second_tone`,
`notifications.state_and_route_restored`, and
`notifications.zero_taps_zero_child_builds`.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-393-01 | Every direct and group read trigger requires resumed lifecycle and a non-null tracker viewing the exact conversation | `conversation_wired_test.dart::TC-393-01 direct read requires resumed exact tracking`; `group_conversation_wired_test.dart::TC-393-01 group read fails closed on unknown lifecycle or tracker` | host / widget fakes | causal RED: direct marks while paused/untracked and group accepts null state/tracker -> paused/inactive/unknown/missing/mismatched never mark; resumed+exact and resume-after-arrival mark once | restore direct unguarded `_markAsRead`, or make either group null arm true -> named row red | exact Flutter tests; AUTO feature-host glob; curated `1to1` and `groups` |
| TC-393-02 | Exact route activation and resume-time top-route republication update synchronous visibility, retire only the generation captured after activation, never mark read and preserve B/newer-A | `app_visibility_route_binding_test.dart::TC-393-02 exact activation cleanup is generation safe and read independent`; `production_canonical_direct_projection_composition_test.dart::TC-393-02 production wires exact generation cancellation` | host / held metadata lookup, fake authority and real-capability composition | causal RED: both activation seams only project visibility -> activate A, hold lookup, background A, publish replacement A, complete lookup; replacement A and B survive, original captured A retires, zero read callback; production supplies the real lookup+CAS cancellation capability | omit resume republication, snapshot before activation, cancel stable ID, wire a fake-only callback, or call read projector -> named row red | exact core/bootstrap tests; final wave gate |
| TC-393-03 | Every non-durable foreground conversation surface rechecks fresh exact visibility immediately before native entry: compatibility direct/group, unanchored group, and raw direct message/reaction | `show_notification_use_case_test.dart::TC-393-03 compatibility final visibility barrier`; `background_push_notification_fallback_test.dart::TC-393-03 all conversation fallbacks use the final visibility barrier` | host / held native callback + fresh/stale visibility fake | causal RED: flip to exact-visible after every preceding await and immediately before each native callback -> zero post; exact-visible->background, unknown/stale/other-chat still post; intros/non-conversation behavior is byte-preserved | restore `() async => true`, keep raw `showNotification`, or perform only the early evaluation -> row red | exact feature tests; `1to1`; `groups` |
| TC-393-04 | Nondurable background direct/group publication uses existing exact canonical and visibility validators at the final native boundary and releases event/tone owners on deny | `background_message_handler_test.dart::TC-393-04 nondurable final barrier prevents canonical or visible race`; final-barrier source census | host / held pre-native callback, fake owners and plugin | causal RED: flip read/delete/exact-visible after every prior await and immediately before native entry -> zero native calls and released owners; unknown/error posts and retains retry semantics | move validation after show, validate only once early, swallow deny as success, or leak either owner -> row red | exact handler test; `groups`; final wave gate |
| TC-393-05 | G21 gives policy-complete eligibility only `aggregate remainder - fixed measured downstream reserve`, preserves the hard aggregate/all sibling phase bounds, and cannot fix first wake by starving the next phase | `background_storage_deadline_test.dart::TC-393-05 display eligibility reserves measured native-entry tail without policy bypass` | host / fake monotonic clock, delayed eligible/ineligible resolvers and downstream phases | causal RED: >2s eligibility records `storage_deferred` and returns -> delays just below and above the old two-second ceiling complete through final card or policy suppression; measured upper-bound eligibility leaves enough tail for the same final outcomes; true aggregate exhaustion stays bounded/custody-retained; sibling phase remains two seconds | use raw remainder, apply widened bound to siblings, emit generic card, omit final outcome, or exceed aggregate -> row red | exact deadline/handler tests; `groups` |
| TC-393-06 | One warmed profile-AOT first wake positively measures successful eligibility plus downstream native-entry tail and closes on one exact policy/card outcome | `android_first_wake_profile_aot`; `one_to_one_reaction_notification_proof_test.dart::android_first_wake_profile_aot`; new `one_to_one_first_wake_profile_aot_contract_test.sh` | device / profile APK receiver, debug setup sender, E2E-only identifier-free receipt, real FCM, direct capture's exact package/data/card state guard | evidence gap -> measurement-only raw aggregate remainder produces a pre-fix receipt binding profile mode/APK SHA, aggregate elapsed/remaining at eligibility start, eligibility elapsed, native-entry tail, terminal outcome and receipt inventory; production freezes `reserve=max(2 s, measured tail + 500 ms)` only if `eligibilityPhaseElapsed <= remainingAtEligibilityStart - reserve`, and the post-fix run proves killed warmed receiver, eligible direct text and one card | ignore pre-eligibility time, leave raw remainder enabled in production, grade cold/debug, omit successful receipt/tail, accept staged-without-card, reuse artifact, or write PASS before restore -> oracle red | explicit direct-runner/capture CLI work; one retained diagnostic and one acceptance artifact, not Sims registration |
| TC-393-07 | A newly stored strict ADD wakes exactly the current recipient when it is in the signed author-device list; the existing reaction flag is production-wired; every invalid/non-author/REMOVE/duplicate case remains silent custody | `group_content_push_test.go::TestInboxStore_StrictGroupReactionWakesSignedAuthorDevice`; `...StrictGroupReactionBystanderStaysSilentCustody`; bootstrap/env and table-driven negatives | host / real signed envelope + fake route/gateway/custody | causal RED: strict reaction is recognized-ineligible and `InboxStore` lacks the existing flag -> one typed `group_reaction` push for the signed current route; no registered token set preserves incumbent fail-open, but registered-unauthorized, disabled, incapable, bystander, REMOVE, malformed/tampered and duplicate rows store with zero wake; fixed-cardinality reaction outcome increments | call full fanout, parse `[toPeerId]` instead of the full signed set, omit `entry.From` authentication/current-recipient membership/route capability, or wire only a test setter -> exact Go row red | exact `go test . -run`; `groups` Go tail |
| TC-393-08 | One recurring strict fixture proves exact-chat suppression, a killed strict message, and an author-targeted strict ADD on the Android pair | `groups.strict_notification_closure` -> `android_strict_group_notification_closure`; new `run_group_strict_notification_sims.dart`; `group_strict_notification_criteria.dart`; literal manifest `artifactValidator: integration_test/group_strict_notification_proof_test.dart` | device / strict group, real staging relay/FCM, central base APK | device-only gap + G27 RED -> active exact group suppresses; killed message shows after RECEIVED->DECRYPT_OK->SHOWN and strict-content attempted delta; reaction to recipient-authored target shows typed card plus strict-reaction attempted delta; artifact binds strict authority construction, staging relay revision/SHA and cursors | create ordinary group, react to sender-authored target, accept a card without strict relay counters/flow binding, or invoke old 5/5 adapter -> criteria/proof red | one appended Sims capability + support/runtime/proof binding; exact host criteria/proof test; separate thin adapter; old five-scenario capability unchanged |
| TC-393-09 | One fixed killed incoming JPEG/photo phase exercises G22b and records whether relay sent full ciphertext or `preview_unavailable` routing-only fallback | `groups.notification_projection_durability` -> `group_notification_projection_android_proof_test.dart::TC-393-09 killed incoming photo message` | device / emulator author -> killed physical recipient, real relay/FCM | device gap: current fixture sends media the opposite way and only grades media-target reactions -> recipient card/flow and exact relay branch bind to the photo event | keep recipient alive, send from physical, accept any media-reaction card, or omit branch discriminator -> proof red | extend the existing capability/criteria with one fixed phase; no generic selector or new scenario |
| TC-393-10 | The remaining Plan-388 Wave-3 media-reaction proof stays current while no announcement or 5/5 rerun is added | existing `groups.notification_projection_durability` photo/video/voice reaction criteria | device / same invocation as TC-393-09 | GREEN sentinel -> all three existing reaction kinds and stable-card/read-zero criteria still pass alongside the one new photo-message leg | remove one existing kind or conflate message with target reaction -> existing oracle red | same single capability run; no new scenario |
| TC-393-11 | Literal profile `android.production_fcm.fixed_wake` and build capability `build.android.production_fcm.fixed_wake` are provider-credential-bound, additive and leave base `android.production_fcm` byte-for-byte defined/cache-isolated | `sims_manifest_test.dart::TC-393-11 fixed wake cohort is additive and exact`; `sims_profile_build_fingerprint_contract_test.sh::provider cohort digest` | host / real manifest + build-input fake | causal RED: profile/dependency absent and provider digest special-cases one ID -> exact four-define profile, generated env `SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE`; provider digests derive from `provider-configured-debug-apk`; credential change invalidates each profile without cross-cache reuse | drop credential digest, mutate base profile, add unrelated define, wrong env/dependency/resource, or reuse base cache key -> contract red | exact manifest/fingerprint/proof-binding tests; appended build capability |
| TC-393-12 | Recovery recurrence maps every old assertion, removes historical target pins/nonexistent seams, and owns one restored two-transition direct-reaction artifact | `android_notification_recovery_completion_criteria_test.dart::TC-393-12 one controlled fixed-wake scenario is fail closed`; new `android_notification_recovery_completion_adapter_contract_test.sh`; new production-headless direct-reaction row | host / raw+aggregate artifact, fake ADB/child/restore and real-SQLite recovery | causal RED: current 6x2 criteria/preflight/pinned IDs -> discovered Sims IDs, distinct background+killed reaction IDs/cursors, central SHA/profile/env, zero child builds/taps/activity; old assertion disposition complete; PASS finalized only after authenticated ephemeral-route unregister/absence, campaign zero-card readback and local-state restoration | accept old schema/pins, missing transition, first-card reuse, stale evidence, rich-FCM/injected substitution, incumbent relaunch, post-setup capability restoration, nonzero card baseline, or PASS before all cleanup cuts -> criteria/adapter red | retarget existing capability/runner/proof; `automationReady:true`; support + runtime root + proof-binding registry |
| TC-393-13 | Attributable live opaque selection drives fixed native ingress -> silent reserved generic -> WorkManager -> canonical direct-reaction presentation -> exact generic retirement once | `notifications.android_recovery_completion` -> `android_fixed_wake_direct_reaction_recovery`; `production_headless_canonical_recovery_test.dart::TC-393-13 authenticated direct reaction settles through inbox reconciler` | device + host / controlled profile, real FCM/staging relay, background-connected then killed receiver | device gap: injected proof exists but no live route -> registration/readiness and bounded `relay_push_route_selected_total{route="opaque"}` delta observed; no rich FlutterFire; authenticated reaction becomes `directReaction`, `SQL_READY/INBOX_RECONCILER/SETTLED`, marker ACK; killed-transition evidence binds process-absent-before-send plus worker `reason=fixed_wake`, generation, PID, attempt, terminal outcome and exact marker ACK; generic tag/id 329 retires after separate canonical card; one tone/no duplicate | shared provider delta, inject wake, permit rich callback, reuse transition-one card/cursor, omit worker/process provenance, leave generic, create synthetic authority, or request second tone -> proof red | one existing capability invocation/distinct report; native/relay evidence content-addressed |
| TC-393-14 | G30 is causally reproduced on the base rich typed path and every actual direct post-show validator emits positive `keep|read|retire`; fixed recovery contains zero database-closed/unknown events only as preservation | `background_message_handler_test.dart::TC-393-14 direct post-show completion cannot be skipped`; existing 1:1 Sims adapter `PLAN393_EXPECT_G30_DIAGNOSTIC` + `--validate-g30-diagnostic-report`; conditional `encrypted_db_read_only_liveness_test.dart` only when causal; two typed raw-log artifacts | host + device / real Android multi-engine rich callback first, real SQLCipher host only when causal, sanitized E2E diagnostics | evidence-gated RED: pre-fix typed run exits nonzero and retains content-addressed proof of the exact G30 predicate, base profile, zero-card/local restoration -> actual validator emits one closed-domain completion and the post-fix typed run has no `database_closed`/`DIRECT_POST_SHOW_UNKNOWN`; exact disposition matches card/read state; fixed wake never substitutes because it bypasses FlutterFire | accept BLOCKED/credential/device/stale/wrong-profile/restoration failure as causal RED, skip validator, hide catch event, infer success from fixed-wake absence, or leave disposition unknown -> host/device oracle red | exact existing adapter shell contract; handler test; conditional DB test/analyze; one typed diagnostic plus one typed acceptance run; recovery absence is preservation only |
| TC-393-15 | Row ownership, restoration and exclusions cannot false-green | exact TC-393 census; strict/recovery/profile adapter contracts; runtime-root/discovery/full-inventory/proof-binding tests; state/relay-cleanup failure fixtures | host / fake ADB, fake authenticated unregister, manifest and path inventories | causal RED for registrations/recovery automation; every planned row appears exactly once; reports distinct; unregister/card/local restoration failure keeps backups and prevents valid PASS | omit row/runtime root, shift old owner, reuse report, leave ephemeral route, fail absence readback, or return PASS before restore -> exact contract red | exact shell/Dart checks and `--list`; no aggregate `sims-contracts` |

### Test Notes

- TC-393-01: initial load, recovery drain, coalesced live arrival and resume all route through the same guarded direct seam. No viewport/scroll-to-latest rule is introduced.
- TC-393-02: install one narrow activation callback at production composition. Invoke it only after synchronous top identity is current, from both `_becameTop` and successful resume-time `republishCurrentTopConversation`; its lookup and generation-CAS cancellation failures keep the card and never broaden to stable-ID cancellation.
- TC-393-03/04: final denial is narrow. Fresh foreground-active exact conversation or verified exact canonical read/delete/retire denies; missing identity, stale/unknown snapshot, background lifecycle and other chat continue toward notification.
- TC-393-06: setup may use the central debug/E2E APK, then replace only the receiver with a profile-AOT APK through `adb install -r` so data remains. Its exact defines are the base profile's `E2E_TEST_MODE=true`, `PRODUCTION_FCM=true`, `MKNOON_EMIT_WAKE_TOKEN=true` plus only `MKNOON_NOTIFICATION_G21_MEASUREMENT=true`; fixed-wake admission stays off. Under that flag alone, `display_eligibility` may consume the raw aggregate remainder to expose its successful completion and downstream tail while the eight-second aggregate remains hard. Production never reads that override. The receipt records aggregate elapsed/remaining at eligibility start; select `reserve=max(existing two-second phase bound, measured tail + 500 ms)` only when eligibility fits `remainingAtEligibilityStart - reserve`, and record the chosen constant in the acceptance artifact. The success receipt is app-private, identifier-free and fixed-domain. Launch once to warm the install, kill, record the receipt inventory cursor, send one direct text, then restore exact pre-run state. Raw `flutter test` cleanup is forbidden.
- TC-393-07: strict custody already invokes the push seam per recipient. Parse the existing signed notification extension with `extractGroupReactionPushMetadata(message, metadata.GroupID, entry.From, nil)`, require `toPeerId` membership in the returned full `NotificationRecipientTransportPeerIDs`, the existing group-reaction flag, the incumbent absent-set fail-open / registered-set authorization rule, and a `groupReactionCapability` route; call `sendGroupReactionNotificationForRoute` once. Never call `fanOutGroupReactionPush`.
- TC-393-08: the recipient authors the target before it is killed. The same strict group first proves active exact-chat suppression, then receives a distinct killed strict text and an ADD by the other peer. Host rows, not a third phone, prove bystander delivery/custody and silence.
- TC-393-08 manifest assertions are exactly `groups.strict_exact_chat_suppressed`, `groups.strict_message_killed_card`, `groups.strict_reaction_author_card`, `groups.strict_relay_provenance`, and `groups.strict_state_restored`; the adapter must emit all five from one fresh artifact.
- TC-393-12: normal Sims execution already centrally prepares/cache-checks the selected build profile before running its capability. Do not pass `--prepare-builds`: that option rewrites the plan to build rows only and cannot close the device behavior.
- TC-393-13: transition one uses reaction/cursor A with the receiver alive/backgrounded, then programmatically activates the exact chat and observes exact card retirement. It fully converges/clears before transition two uses reaction/cursor B with the receiver killed. Neither transition may reuse the other's card, logs or metric window. The killed artifact records process absence before send plus the worker's `reason=fixed_wake`, generation, PID, attempt, terminal outcome and exact marker ACK. The fixed-cardinality relay route counter is identifier-free; the generic card is reserved tag/id 329 and is retired after a separately identified canonical card. G30 is not graded here because exact fixed wake bypasses FlutterFire.
- TC-393-14: E2E diagnostics are closed-domain and identifier-free (phase, sanitized sqflite code, independent-handle state, validator disposition). `PLAN393_EXPECT_G30_DIAGNOSTIC=true` is accepted only by the existing Sims adapter's report-validation mode when the capability is `FAIL` for that exact predicate, uses base `android.production_fcm`, retains fresh content-addressed raw evidence and proves zero-card/local restoration; `BLOCKED` or any other failure stops execution. They may identify the repair but cannot become a new runtime database authority. Plan 393 cannot become COMPLETE by merely documenting or amending G30: it needs an app-owned fix plus the positive host/device regression; a plugin/cross-engine result leaves the plan BLOCKED/PARTIAL.

## Implementation Steps

1. Snapshot `git status --short`, preserve all Plan-392/user changes, and add the named causal tests/contracts before production edits.
2. Slice A: route every direct/group read trigger through the strict predicate; install the existing exact-generation cancellation capability at production composition and invoke it after synchronous top identity from both route activation and resume republication; use the existing native-publication boundary to re-evaluate visibility/canonical state for compatibility, unanchored group, raw direct message/reaction and nondurable native entry. Stop if an edit requires a new ledger or navigation-wide framework.
3. Slice B checkpoint 1: add the explicit `android_first_wake_profile_aot` runner/capture CLI, command contract, E2E-only successful measurement receipt and shared state guard. Run it once before changing G21; only that measurement build gives eligibility the raw aggregate remainder. Record `remainingAtEligibilityStart`; if `eligibilityPhaseElapsed <= remainingAtEligibilityStart - max(2 s, measured tail + 500 ms)`, freeze that reserve and add one narrowly named production deadline method that subtracts it only for `display_eligibility`; make both eligible-card and ineligible-suppression end states green.
4. Slice B checkpoint 2: add bounded sanitized G30 diagnostics with a positive `keep|read|retire` receipt plus the existing Sims adapter's fail-closed diagnostic/report-validation mode. Run the base-profile rich typed scenario once to reproduce the real Android multi-engine handle sequence, and accept its nonzero exit only after that validator proves the exact G30 predicate, fresh evidence, base profile and restoration. Apply only the identified app-owned opener/handler fix, then rerun the typed scenario as acceptance; no example retry is pre-authorized, and plugin/cross-engine scope stops the plan.
5. Slice C: wire the existing group-reaction flag into production `InboxStore`, implement strict per-recipient reaction wake and its negative matrix, and use existing strict message/reaction counters. Add `run_group_strict_notification_sims.dart` as one thin adapter/capability. Add exactly one fixed killed-JPEG phase to the existing projection fixture; do not add a generic media selector.
6. Slice D: add literal profile/build IDs from TC-393-11, generalize provider digests by artifact kind, update the recovery runner from its hard-coded base artifact name to `SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE`, and add one fixed-cardinality opaque-vs-rich selected-route counter. First enforce the old-assertion disposition table; then narrow the existing recovery criteria/runner/proof to the one two-transition scenario, remove model-specific IDs, reuse the Plan-374 barrier/observer/current 1:1 choreography, and add only an arm-without-injecting debug operation if the real route needs it. Remove stale Plan-331 source requirements rather than creating their files.
7. Register only the new strict capability, its literal `integration_test/group_strict_notification_proof_test.dart` validator, fixed-cohort build profile/build capability and activated existing recovery runner in the manifest, discovery, proof-binding and runtime-root inventories. Keep existing capability IDs/owners and base profile unchanged. In recovery cleanup, authenticate unregister for the fresh ephemeral identity while it is active and verify its route is absent, cancel and verify the campaign's zero-card baseline, then restore local state; publish the aggregate only after all three cuts pass.
8. Run focused GREEN/mutations/preservation, then the ordered availability-bounded device commands. Update both UI-23 documents with actual outcomes and exclusions, refresh Graphify once, and run the single notification-wave aggregate gate only after every focused/device row is closed.

## Risks And Blind Spots

- Policy-blind G21 fallback could alert blocked/muted/removed users, while a raw aggregate remainder could starve the next phase -> forbidden by TC-393-05's delayed-ineligible and final-outcome/tail-reserve rows.
- A card can pass while the durable/fixed branch never ran -> TC-393-12/13 require relay selection, native ingress, worker and exact retirement provenance, and forbid rich FlutterFire substitution.
- Strict per-recipient custody plus full fanout can duplicate author wakes -> TC-393-07 requires one current-recipient route and negative bystander/duplicate rows.
- A final barrier can leak tone/event leases when it denies -> TC-393-04 mutates each release independently.
- Profile or Sims evidence can reuse stale raw files, reuse transition A for B, or overwrite reports -> unique capture roots, distinct IDs/cursors, SHA/profile binding and distinct `SIMS_REPORT_PATH` in TC-393-06/12/15.
- Lifecycle / derived-state durability: resume reconstructs the strict read predicate from current lifecycle/tracker; fresh worker startup reconstructs recovery from durable store/ledger -> TC-393-01/13.
- Sibling-surface consistency: direct and group reads share the adopted predicate; compatibility/unanchored/nondurable surfaces share the same narrow final decision -> TC-393-01/03/04.
- Destructive-action side effects: activation/read cancel exact generation only; each device campaign starts from a zero app-card baseline; the fresh ephemeral route is authenticated-unregistered before local-state restoration; no incumbent relaunch, post-setup route preservation, auto-uninstall, DB migration or production deployment -> TC-393-02/12/15.
- Invariant re-verification under new transitions: background->visible and visible->background, read/delete-before-callback, background-connected->killed, generic->canonical and restore failure are all explicit rows.

## Gate Cadence

- Per-plan causal closure: exact TC-393 Flutter/Go/Kotlin/shell tests, an exact row census, exact preservation sentinels, curated `1to1`, curated `groups`, and the one final wave-level aggregate below. A separate `core-host-all` would be redundant because final `host-all` subsumes it.
- Do not run full S1-S16, the ordinary group 5/5, payload/G24, mute, all-media or per-slice `host-all`. The sound runner is selected only through S4; S1-S3 still execute as its disclosed sequential setup prerequisites, with OS acceptance graded only for S4.
- This plan completes the two-plan Android notification dependency wave begun by Plan 392. Run `./scripts/run_host_test_gates.sh host-all` exactly once at the final wave checkpoint after all Plan-393 focused and device proof passes; do not repeat it during implementation. Final rollout/release owns its later independent aggregate gate.
- Shared tests outside feature/core globs run by exact command: Go strict rows, Kotlin native classes, Sims adapter/profile contracts and runtime/discovery inventories.

## Acceptance Gates

```bash
# Snapshot and preserve the user's dirty Plan-392 tree.
git status --short

# Representative causal REDs after authoring tests, before corresponding production edits.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'TC-393-01 direct read requires resumed exact tracking'
flutter test test/core/notifications/app_visibility_route_binding_test.dart \
  --plain-name 'TC-393-02 exact activation cleanup is generation safe and read independent'
flutter test test/features/push/application/background_storage_deadline_test.dart \
  --plain-name 'TC-393-05 display eligibility reserves measured native-entry tail without policy bypass'
(cd go-relay-server && go test . -run '^TestInboxStore_StrictGroupReactionWakesSignedAuthorDevice$')
flutter test test/integration/android_notification_recovery_completion_criteria_test.dart \
  --plain-name 'TC-393-12 one controlled fixed-wake scenario is fail closed'

# Implement and GREEN only the two diagnostic harness contracts before spending
# device time. These do not authorize either evidence-gated production fix.
bash scripts/test/one_to_one_first_wake_profile_aot_contract_test.sh
bash scripts/test/one_to_one_reaction_sims_adapter_contract_test.sh

# Resolve devices only during execution, then collect the two evidence-gated
# checkpoints before choosing either G21 or G30 production repair.
flutter devices --machine
adb devices
export PLAN393_PHYSICAL_ANDROID_ID='<discovered-usb-android-id>'
export PLAN393_ANDROID_EMULATOR_ID='<discovered-android-emulator-id>'
export MKNOON_RELAY_ADDRESSES='<staging-relay-multiaddrs>'
export SIMS_PROVIDER_FCM_CREDENTIAL_PATH='<fcm-service-account.json>'
export MKNOON_257_RELAY_TARGET='<staging-relay-ssh-target>'
export MKNOON_257_RELAY_KEY='<staging-relay-ssh-key>'
export MKNOON_257_STAGING_MANIFEST='<staging-manifest.json>'
export SIMS_NOTIFICATION_RELAY_TARGET="$MKNOON_257_RELAY_TARGET"
export SIMS_NOTIFICATION_RELAY_KEY="$MKNOON_257_RELAY_KEY"

# Checkpoint 0, after G30 diagnostic instrumentation but before its fix. This
# command must be nonzero specifically because the rich typed artifact contains
# TC-393-14's post-show failure; BLOCKED, missing/stale evidence, wrong profile,
# nonzero card baseline, or failed state restoration is not an accepted RED.
set +e
PLAN393_EXPECT_G30_DIAGNOSTIC=true \
SIMS_REPORT_PATH=build/plan393/typed-g30-diagnostic/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN393_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN393_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only notifications.android_typed_reaction_smoke
PLAN393_G30_DIAGNOSTIC_EXIT=$?
set -e
test "$PLAN393_G30_DIAGNOSTIC_EXIT" -ne 0
dart run integration_test/scripts/run_1to1_reaction_notification_sims.dart \
  --validate-g30-diagnostic-report \
  build/plan393/typed-g30-diagnostic/report.json

# Checkpoint 1, before the G21 production edit: one retained warmed profile-AOT
# measurement whose dedicated flag alone exposes the eligibility/tail timing.
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --scenario android_first_wake_profile_aot \
  --sender "$PLAN393_PHYSICAL_ANDROID_ID" \
  --recipient "$PLAN393_ANDROID_EMULATOR_ID" \
  --artifact-dir build/plan393/g21-profile-aot-measurement \
  --relay-target "$MKNOON_257_RELAY_TARGET" \
  --relay-key "$MKNOON_257_RELAY_KEY" \
  --service-account "$SIMS_PROVIDER_FCM_CREDENTIAL_PATH" \
  --staging-manifest "$MKNOON_257_STAGING_MANIFEST" \
  --measurement-only

# Stop here and apply the evidence-gated G21/G30 fixes. Do not continue to
# focused GREEN unless both retained checkpoint validators pass their exact
# diagnostic predicates and neither stop-if condition is reached.

# Focused GREEN. The census prevents a missing file/row from making a broad name filter vacuous.
bash scripts/test/plan393_notification_test_contract_census_test.sh
for test_file in \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/core/notifications/app_visibility_route_binding_test.dart \
  test/core/bootstrap/production_canonical_direct_projection_composition_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/background_message_handler_test.dart \
  test/features/push/application/background_storage_deadline_test.dart \
  test/core/bootstrap/production_headless_canonical_recovery_test.dart \
  test/integration/group_strict_notification_criteria_test.dart \
  test/integration/android_notification_recovery_completion_criteria_test.dart \
  test/integration/android_app_state_guard_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  test/tool/sims/sims_proof_binding_registry_test.dart
do
  flutter test "$test_file" --plain-name 'TC-393-'
done

# Exact preservation rows; do not broaden these to whole families here.
flutter test test/core/notifications/local_notification_final_effect_test.dart \
  --plain-name 'content activation crash intent is opaque and resumes exact old-card retirement'
flutter test test/core/bootstrap/production_headless_canonical_recovery_test.dart \
  --plain-name 'TC-374-02 exhaustive typed direct group adapters and all custody totals converge without fallback'
flutter test test/core/bootstrap/production_headless_canonical_recovery_test.dart \
  --plain-name 'TC-374-06 concurrent foreground headless contenders share one owner and hand off newer work without loss'
flutter test test/core/bootstrap/production_headless_canonical_recovery_test.dart \
  --plain-name 'TC-375-04 fixed wake carries no event authority and canonical drain remains inbox reconciler'
flutter test test/core/notifications/local_notification_projection_convergence_test.dart \
  --plain-name 'TC-375-05 fixed generic stays silent in both orders while deletion ambiguity is never downgraded'
flutter test test/core/notifications/android_opaque_wake_readiness_test.dart \
  --plain-name 'TC-375-07 primary and linked Android serialize one qualified physical route through every retry'
flutter test test/core/notifications/flutter_notification_service_test.dart \
  --plain-name 'android conversation card carries canonical history and uncapped number'
flutter test test/features/push/application/push_registration_coordinator_test.dart \
  --plain-name 'transient failures warn at three and success clears live'
flutter test test/features/push/presentation/push_registration_health_surface_test.dart \
  --plain-name 'permission warning is localized and opens notification settings'
flutter test test/features/push/presentation/push_registration_health_surface_test.dart \
  --plain-name 'safe transient reason uses Retry and never renders raw errors'
flutter test test/integration/reaction_notification_proof_support_test.dart \
  --plain-name 'each capture branch stem matches its scenario id'
flutter test test/core/notifications/android_recovery_string_resources_test.dart

# Exact relay, native and harness contracts.
(cd go-relay-server && go test . -run '^(TestExtractGroupContentPushMetadata|TestInboxStore_StrictGroupContentWakesTheRecipient|TestInboxStore_StrictGroupReactionWakesSignedAuthorDevice|TestInboxStore_StrictGroupReactionBystanderStaysSilentCustody|TestInboxStore_StrictGroupReactionProductionFlagWiring|TestStoreAckCustody_StrictGroupContentWakesTheRecipient|TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly|TestSelectedPushRouteCounterDistinguishesOpaqueFromRich)$')
./android/gradlew -p android :app:testDebugUnitTest \
  --tests '*MknoonFirebaseMessagingServiceTest*' \
  --tests '*DroppedPushRecoveryWorkSchedulerTest*' \
  --tests '*HeadlessCanonicalRecoveryWorkerTest*'
bash scripts/test/android_notification_recovery_completion_adapter_contract_test.sh
bash scripts/test/group_strict_notification_sims_adapter_contract_test.sh
bash scripts/test/group_reaction_notification_device_contract_test.sh
bash scripts/test/sims_profile_build_fingerprint_contract_test.sh
./scripts/check_runtime_root_inventory.sh check --format text
bash scripts/test/sims_full_inventory_contract_test.sh

# Exact discovery; each capability must appear once and the old group 5/5 stays unchanged.
dart tool/sims/sims.dart major --only groups.strict_notification_closure --list --format json
dart tool/sims/sims.dart major --only groups.notification_projection_durability --list --format json
dart tool/sims/sims.dart major --only notifications.android_recovery_completion --list --format json
dart tool/sims/sims.dart major --only notifications.android_typed_reaction_smoke --list --format json

# Affected curated/family gates, once after focused GREEN.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Scoped analysis and hygiene.
dart analyze \
  lib/core/notifications/app_visibility_route_binding.dart \
  lib/app/bootstrap/production_application_bootstrap.dart \
  lib/app/bootstrap/production_canonical_direct_projection_composition.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/push/application/show_notification_use_case.dart \
  lib/features/push/application/background_push_notification_fallback.dart \
  lib/features/push/application/background_message_handler.dart \
  lib/features/push/application/background_storage_liveness_journal.dart \
  integration_test/scripts/run_1to1_reaction_notification_device.dart \
  integration_test/scripts/capture_1to1_reaction_head_provenance.dart \
  integration_test/scripts/run_group_strict_notification_sims.dart \
  integration_test/scripts/group_strict_notification_criteria.dart \
  integration_test/group_strict_notification_proof_test.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/run_group_notification_projection_android.dart \
  integration_test/scripts/group_notification_projection_android_criteria.dart \
  integration_test/scripts/run_android_notification_recovery_completion.dart \
  integration_test/scripts/android_notification_recovery_completion_criteria.dart \
  integration_test/one_to_one_reaction_notification_proof_test.dart \
  integration_test/group_notification_projection_android_proof_test.dart \
  integration_test/android_notification_recovery_completion_proof_test.dart \
  tool/sims/build_orchestrator.dart

# Conditional only if G30's causal checkpoint changes the opener; otherwise do not run it.
if git diff --name-only -- lib/core/database/encrypted_db_opener.dart | rg -q '^lib/core/database/encrypted_db_opener\.dart$'; then
  flutter test test/core/database/encrypted_db_read_only_liveness_test.dart \
    --plain-name 'TC-393-14'
  dart analyze lib/core/database/encrypted_db_opener.dart \
    test/core/database/encrypted_db_read_only_liveness_test.dart
fi
git diff --check

# After G21 GREEN, rerun the same profile-AOT scenario as acceptance.
dart run integration_test/scripts/run_1to1_reaction_notification_device.dart \
  --scenario android_first_wake_profile_aot \
  --sender "$PLAN393_PHYSICAL_ANDROID_ID" \
  --recipient "$PLAN393_ANDROID_EMULATOR_ID" \
  --artifact-dir build/plan393/g21-profile-aot-acceptance \
  --relay-target "$MKNOON_257_RELAY_TARGET" \
  --relay-key "$MKNOON_257_RELAY_KEY" \
  --service-account "$SIMS_PROVIDER_FCM_CREDENTIAL_PATH" \
  --staging-manifest "$MKNOON_257_STAGING_MANIFEST" \
  --require-alert

# Direct exact-chat device sentinel. The sequential harness necessarily executes S1-S3
# as setup prerequisites, grades OS acceptance only for S4, and exits immediately after S4.
dart run integration_test/scripts/run_notification_sound_smoke.dart \
  -d "$PLAN393_PHYSICAL_ANDROID_ID,$PLAN393_ANDROID_EMULATOR_ID" \
  --rows S4 \
  --artifact-dir build/plan393/sound-focused \
  --non-interactive

# Post-fix rich-path typed acceptance is G30's positive device proof; distinct reports prevent overwrite.
SIMS_REPORT_PATH=build/plan393/typed/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN393_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN393_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only notifications.android_typed_reaction_smoke

SIMS_REPORT_PATH=build/plan393/strict/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN393_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN393_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only groups.strict_notification_closure

# One run closes killed photo plus the still-relevant media-reaction half of Plan-388 Wave 3.
SIMS_REPORT_PATH=build/plan393/projection/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN393_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN393_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only groups.notification_projection_durability

# Real controlled-cohort relay/FCM fixed-wake recovery. Normal Sims execution centrally
# prepares/cache-checks android.production_fcm.fixed_wake and then runs this capability;
# never pass --prepare-builds, which would select build rows without executing the proof.
SIMS_REPORT_PATH=build/plan393/recovery/report.json \
SIMS_ANDROID_PHYSICAL_DEVICE_ID="$PLAN393_PHYSICAL_ANDROID_ID" \
SIMS_ANDROID_EMULATOR_DEVICE_ID="$PLAN393_ANDROID_EMULATOR_ID" \
.claude/skills/sims/scripts/run_with_devices.sh major \
  --only notifications.android_recovery_completion

# One aggregate gate because this closes the Plan-392/393 notification dependency wave.
./scripts/run_host_test_gates.sh host-all

# Refresh app-owned graph once after coherent implementation.
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

## Execution Closure

- **N11 / final authority:** direct and group reads now require `resumed` plus the exact non-null tracked conversation. Exact route activation and resume-time top-route republication invoke independent exact-generation cleanup without marking read. Compatibility, unanchored group, raw direct/reaction, and nondurable paths reread visibility/canonical authority at the last safe boundary; unknown/stale facts fail toward notification.
- **G21:** the warmed profile-AOT measurement recorded 7,995 ms remaining at eligibility start, 172 ms eligibility, and a 175 ms downstream native-entry tail. Production reserves `max(2 s, tail + 500 ms) = 2 s`, changes only `display_eligibility`, preserves the 8 s aggregate and every sibling 2 s phase, and never uses a policy-blind card. Measurement SHA-256 `4c427494ed6a…`; acceptance SHA-256 `95dbe1af302a…`.
- **G30:** the diagnostic reproduced `direct_post_show_database_closed`. Root cause was returning the validator Future from inside `try/finally`, allowing the non-singleton read-only handle to close before later SQL reads completed. The repair awaits validation before close and emits a closed-domain `keep|read|retire` disposition. Diagnostic aggregate SHA-256 `57888647…`; post-fix typed aggregate SHA-256 `4b4554d8d4c8…`.
- **G27 / strict:** signed author-device authority now gates one per-recipient strict reaction wake; negative custody rows remain silent and no full fanout occurs from the strict seam. `groups.strict_notification_closure` passed 5/5; aggregate SHA-256 `7db8f1843c8d…`.
- **G22b / projection:** one killed incoming JPEG records the exact relay branch in the existing projection owner; photo/video/voice reaction projection remains green. `groups.notification_projection_durability` passed 6/6; aggregate SHA-256 `434cbab15fc8…`.
- **Fixed wake / recovery:** the historical 6×2 contract is assertion-mapped into one recurring two-transition scenario. Alive/background reaction settled canonically; killed reaction selected the opaque route, reserved a silent generic card, continued through WorkManager without an Activity, presented one separate canonical card, retired the generic card, requested no second tone, authenticated-unregistered the ephemeral route, verified zero cards, and restored local state. `notifications.android_recovery_completion` passed 6/6; report SHA-256 `80f05ac6f5d7…`, aggregate `3fea2988d45c…`, raw evidence `a2a94b61…`.
- **Wave gate:** `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 2 --reporter failures-only` passed 14,588 Flutter tests with 11 intentional skips and all 16 Go/relay/native tails. The final Android native gate selected 9 Plan-374/375/393 classes / 68 methods.

## Device/Relay Proof Profile

- Profile: availability-bounded paired Android + OS notifications + real FCM. Strict/projection used the tested relay v1.9.0 boundary; recovery used a disposable production-code relay with ephemeral Redis. No staging or production deployment was performed for recovery.
- Boundary being proven: measured profile-AOT first wake, exact lifecycle suppression/activation, strict direct-inbox message/reaction wakes, killed group photo, attributable live fixed opaque route selection, native silent generic card, WorkManager continuation, separate canonical presentation, exact generic retirement and no-duplicate/tone behavior.
- Live availability: `flutter devices --machine` / `adb devices` resolved physical `21071FDF600CSC` and emulator `emulator-5554`; every device command was pinned to those IDs.
- Required setup used: unlocked targets, working `adb`, zero active `com.mknoon.app` cards, FCM service account, tested relay binaries/fixtures, isolated writable evidence/report paths, and sufficient backup/build space. Setup/navigation/actions/assertions were harness-driven with no user taps.
- Two-peer default: USB physical Android sender + Android emulator receiver. TC-393-09 intentionally reverses those two roles because the existing media fixture needs emulator author -> killed physical recipient; it adds no target or second campaign. iPhone is excluded.
- Closure role: required device evidence. Host/fake tests cannot substitute for relay audience, OS card, profile-AOT or process-death claims.
- `FLUTTER_DEVICE_ID`: host selector only; both explicit Android IDs remain required.
- Registration: one new strict capability; literal profile `android.production_fcm.fixed_wake` plus `build.android.production_fcm.fixed_wake`; existing recovery capability assertion-mapped, simplified and activated; existing projection capability extended. The profile-AOT measurement is a retained one-off scenario, not a Sims build profile.
- Discovery commands: the four exact `--list` commands above.
- Closure commands completed in order: typed G30 diagnostic, profile-AOT measurement/acceptance, S4 with its disclosed S1-S3 setup prerequisites, typed G30 acceptance, strict, projection, and recovery. Each runner restored owned state and verified its card baseline; recovery additionally authenticated unregister for the fresh route and verified absence before local restoration.
- Deferred device work: iOS, OEM, production rollout, third-device bystander and exhaustive media/flavor matrix only.

## Execution Interpretation And Done Criteria

- Expected RED: N11 read/activation/final-barrier rows; >2s eligibility; strict reaction wake; strict/device/photo selectors; cohort profile; simplified recovery artifact; and G30 causal reproduction all fail for the named current-source reason.
- Green sentinels: Plan-392 typed proof, existing five group scenarios, media-reaction trio, Plan-374/375 fixed/native invariants, unknown-authority fail-toward-notification and exact-generation cancellation remain green.
- Pre-existing dirty tree: Plan-392 implementation, both UI-23/map updates and Graphify files are user-owned/current work. Execution records the initial snapshot and never reverts unrelated changes.
- Environment-blocker rule was retained: missing credentials/relay or a disappearing target would have produced typed environment evidence; unavailable hardware is policy-N/A only for device rows. No required Plan-393 row ended blocked or N/A, and both G21/G30 stop-if checkpoints cleared.
- Scope drift: DB schema/plugin fork, new notification ledger/framework, global fixed-wake activation, production deployment, third device, iOS/OEM or unrelated G28 work blocks completion pending explicit replanning.

- [x] Every required Android-led behavior has a named causal test or real device proof.
- [x] N11 direct/group read, exact activation cleanup and all remaining pre-effect barriers satisfy their positive, negative, race and owner-release rows.
- [x] One warmed profile-AOT receipt positively binds aggregate elapsed/remaining at eligibility start, successful eligibility, downstream native-entry tail, profile mode and APK SHA; G21 proceeds only when eligibility fits `remainingAtEligibilityStart - max(2 s, tail + 500 ms)`, and eligible/ineligible/hard-bound behavior is green without policy-blind fallback, downstream starvation or a larger aggregate.
- [x] G30 has a causal app-owned fix and positive `keep|read|retire` host/device regression from the base-profile rich typed path; its pre-fix diagnostic and post-fix acceptance artifacts are distinct. Recovery's clean log is preservation only. Diagnosis or amendment alone is not completion.
- [x] G27 alerts exactly the signed strict target author while all negative custody rows stay silent; one strict message+reaction device artifact passes.
- [x] One killed incoming photo passes with an exact relay-branch discriminator, and the existing photo/video/voice reaction projection remains green in the same run.
- [x] Recovery is automation-ready with literal fixed-cohort profile/build ownership, complete old-assertion disposition, two distinct transitions, attributable opaque-route selection, process-absent/worker-generation/PID/attempt/outcome/marker provenance, zero child builds/taps/activity, and content-addressed PASS written only after authenticated ephemeral-route unregister/absence, zero-card verification and local restoration.
- [x] Background-connected reaction is durably/canonically represented; killed fixed wake yields one silent reserved generic card, then one separately identified canonical card and exact generic retirement, with no duplicate or second requested tone.
- [x] Device work is limited to one pre-fix and one post-fix typed run, two profile-AOT runs of one scenario, S4 plus its unavoidable S1-S3 setup prerequisites, and one each of strict, projection and recovery; excluded campaigns are not repeated.
- [x] Exact host/native/harness contracts, `1to1`, `groups`, then the one notification-wave `host-all` pass with semantic outcomes; no redundant `core-host-all` runs.
- [x] Runtime/discovery/manifest/proof-binding registration and the TC-393 row census are exact; scoped/conditional analysis, Graphify refresh and `git diff --check` are clean.
- [x] Both UI-23 documents and the index state what closed and retain only the explicit iOS/release/OEM/optional exclusions.
- [x] Scope Contract And Guard is respected.

## Closure Handoff

- Causal REDs, preservation sentinels, and every `TC-393-` row were implemented before their production slice and are retained under the exact owners named above.
- Registration is complete: one strict capability, literal `android.production_fcm.fixed_wake` / `build.android.production_fcm.fixed_wake`, narrowed active recovery ownership, extended projection ownership, and exact support/runtime/proof-binding roots.
- Migration: none; DB remains v116.
- Boundary closure: physical `21071FDF600CSC` + emulator `emulator-5554`, real FCM, two distinct profile-AOT artifacts, distinct G30 diagnostic/acceptance reports, and strict/projection/recovery Sims reports. Recovery used an isolated disposable production-code relay with ephemeral Redis rather than a staging/production deployment.
- Required Android unresolved evidence: none. Remaining Apple/release/OEM/optional boundaries are recorded in both UI-23 documents and do not reopen this plan.

## Independent Review Findings

Initial `$tdd-review` verdict: `plan-fixes-required`; disposition: `apply-plan-fixes`. Three independent source/command reruns returned `READY` after the following corrections:

- Problem validity: Plan 392's actual closure was respected—typed recurrence and S1-S16 remain current, while G24 stays policy-N/A on the available receiver. N11, G21, G27, G30, strict device proof, killed photo, remaining media-reaction currency and fixed-wake recurrence are current-source gaps rather than stale document claims.
- Behavior contract: G21 measurement now exposes the otherwise-unobservable tail only in a dedicated build and accounts for time consumed before eligibility; G30 positive proof is assigned to rich FlutterFire rather than fixed wake; strict reaction uses the signed author-device set and never full fanout; every remaining final barrier fails toward notification on unknown authority.
- Verification quality: strict proof has a literal artifact validator and host criteria test; the stale recovery assertion set has a one-for-one retained/retired owner map; G30's expected RED must carry exact fresh failure/restoration evidence; fixed wake binds route selection, worker provenance, generic retirement and no duplicate/tone outcome rather than accepting a card alone.
- Feasibility and cleanup: normal Sims execution prepares then runs the selected capability without `--prepare-builds`; the controlled route is always authenticated-unregistered while its ephemeral identity is active; zero app-card baselines are preconditions because the app-state guard does not own cards; PASS is emitted only after route, card and local-state cleanup.
- Delivery scope: one final plan is sufficient. The review removed the old 12-leg recovery matrix, broad S1-S16/group/payload/mute reruns, generic media selector, redundant `core-host-all`, aggregate `sims-contracts` and any new notification/database framework. Only affected exact tests, `1to1`, `groups`, and one final notification-wave `host-all` remain.
- Command audit: diagnostic harness contracts run before device time; G30/G21 evidence checkpoints run before their production fixes; focused GREEN and acceptance follow; distinct reports prevent overwrite. A device/credential/restoration failure cannot masquerade as the expected G30 RED.

## Arbiter Decision

Final verdict: `ready with mandatory evidence-gated checkpoints`.

- The core bet is viable in current source: existing recovery, publication, relay-authority and device-runner owners can close the required Android behavior without a redesign.
- This is the second and final planned Android-led notification plan after Plan 392. No third plan is pre-created and no separate plan is needed for the known required scope.
- G21 timing and G30 ownership are honest execution-time decision points. If either stop condition is reached, Plan 393 remains `BLOCKED/PARTIAL` and must be explicitly amended or replanned; that outcome cannot be described as full gap closure.
- Excluded iOS/release/OEM, production rollout, third-device bystander and exhaustive media/flavor coverage remain excluded exactly as requested.
- Planning and review used no emulator, USB device, simulator, staging mutation or test execution; live targets are discovered and pinned only during implementation.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-21 | Slice A — N11/final barriers | Direct/group conversation, route registry, compatibility/unanchored/background presentation owners and causal tests | focused Flutter/contract/architecture gates PASS | strict resumed+exact read authority, independent activation cleanup, final visibility/canonical rereads, exact-generation preservation | closed; no schema/ledger change | G21 checkpoint |
| 2026-08-21 | Slice B1 — G21 | background storage deadline/journal, measurement capture/oracle | measurement then acceptance PASS | measurement SHA `4c427494ed6a…`; 7,995 ms remaining, 172 ms eligibility, 175 ms tail, 2,000 ms reserve; acceptance SHA `95dbe1af302a…` | checkpoint cleared within unchanged 8 s aggregate | G30 checkpoint |
| 2026-08-21 | Slice B2 — G30 | direct post-show validator, diagnostics, typed capture/oracle | expected diagnostic FAIL reproduced, focused fix green, typed device acceptance PASS | exact `direct_post_show_database_closed` before repair; await-before-close root fix; acceptance aggregate `4b4554d8d4c8…` | checkpoint cleared with app-owned repair | strict/projection |
| 2026-08-21 | Slice C — strict + killed media | relay strict reaction authority, strict fixture, projection fixture/criteria/registration | strict 5/5 PASS; projection 6/6 PASS | aggregate SHAs `7db8f1843c8d…` and `434cbab15fc8…` | G27 and G22b closed | recovery |
| 2026-08-21 | Slice D — recurring fixed wake | recovery signal/worker/process handoff, production headless control consumption, two-transition capture/criteria/manifest | recovery 6/6 PASS | report `80f05ac6f5d7…`; aggregate `3fea2988d45c…`; raw `a2a94b61…`; route/card/state cleanup and zero taps/builds/activity | controlled-cohort mechanism closed; no production deployment | wave gate |
| 2026-08-21 | Final host/native wave | affected production/tests/contracts plus registered tails | `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 2 --reporter failures-only` PASS | 14,588 Flutter / 11 intentional skips; 16/16 Go/relay/native tails; Plan 374/375/393 native 9 classes / 68 methods | stable concurrency 2 selected after concurrency 4 exposed resource-pressure-only failures; deterministic stale contracts repaired | documentation/hygiene |
| 2026-08-21 | Closure documentation and hygiene | this plan, index, both UI-23 assessments, Graphify architecture graph | Plan-393 exact contracts/analysis, incremental Graphify refresh, and `git diff --check` PASS | required Android residual none; Apple/release/OEM/optional exclusions retained | complete / not release-eligible | none |
