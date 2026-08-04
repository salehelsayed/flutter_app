# 332 - Android Standard Notification Badge/Count Closure (OEM Numeric Deferred)

Status: execution-ready
Type: Verification / regression hardening
Spec: free-text user intent and explicit product decision (2026-08-03): support standard Android notification badging on the available Pixel targets; reject ShortcutBadger and its 16 vendor permissions
Classification: standard-Android contract hardening; legacy OEM numeric compatibility intentionally deferred
Closure tier: device (host + availability-bounded USB Pixel / Android-emulator proof)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-03 | Evidence collector | `local_notification_support.dart`, `flutter_notification_service.dart`, notification snapshot/read/reconciliation tests, `flutter_local_notifications` 18.0.1 Android implementation | Android already publishes a positive canonical per-conversation unread total through `Notification.number`; both message channels are effectively badge-capable through plugin defaults | Freeze the supported standard contract and identify only genuine residual work |
| 2026-08-03 | Device boundary auditor | `flutter devices --machine`, `adb devices -l`, launcher resolution, secure badging settings, live `dumpsys notification --noredact` | Available Android targets are Pixel 6 `21071FDF600CSC` API 36 and emulator `emulator-5554` API 37; both use Pixel Launcher and currently have launcher badging enabled | Use independent fresh-install proof on those two targets; unavailable OEM brands are policy N/A |
| 2026-08-03 | Critical reviewer | Plans 330, 331, and 333; current source/tests; proposed aggregate/reconciler/plugin/permission design | Standard Android has no app-wide badge writer to feed. A global aggregate, native adapter, cross-engine ticketing, and vendor permissions would add risk without proving behavior on the available matrix | Remove the rejected machinery; retain per-card counts, exact cancellation, negative dependency/manifest guards, and standard device proof |
| 2026-08-03 | Product decision | Rejected `ShortcutBadger` compatibility exception and all 16 contributed vendor permissions | The former prerequisite is resolved by rejection, not acceptance | Execute this standard-only plan; any future OEM numeric work requires a new explicit decision and plan |

## Problem And Evidence

- Supported behavior: Android message notifications opt into the platform badge surface, carry the canonical unread total for their own conversation, retain bounded history, and disappear through exact per-conversation cancellation when that conversation reaches zero.
- Current implementation: `lib/core/notifications/local_notification_support.dart:16-30` defines the high and silent channels; `:72-103` maps a positive `ConversationNotificationSnapshot.totalUnreadMessageCount` to `AndroidNotificationDetails.number` and omits it at zero/null. `FlutterNotificationService` uses stable per-conversation IDs and exact cancellation.
- Plugin boundary: the pinned `flutter_local_notifications` 18.0.1 defaults both `AndroidNotificationChannel.showBadge` and `AndroidNotificationDetails.channelShowBadge` to `true`; its Android code maps these to `NotificationChannel.setShowBadge(...)` and `Notification.Builder.setNumber(...)`.
- Existing evidence: `flutter test test/core/notifications/local_notification_support_test.dart test/core/notifications/flutter_notification_service_test.dart test/core/notifications/android_notification_completion_scope_contract_test.dart` passed `+29`; `conversation_notification_snapshot_test.dart` passed `+1`. The snapshot test proves independent, uncapped direct/group conversation totals, not one app-wide total.
- Honest residual: app-owned constructors rely on dependency defaults, the silent/detail assertions are incomplete, the rejection of vendor badge code is not yet pinned against merged manifests, and there is no fresh-install device receipt dedicated to the standard contract.
- Platform boundary: Android says `setNumber` may be shown by launchers that support badging, while the launcher controls the visual form ([Android notification badges](https://developer.android.com/develop/ui/views/notifications/badges), [`Notification.Builder.setNumber`](https://developer.android.com/reference/android/app/Notification.Builder#setNumber(int))). Pixel Launcher may show a dot or notification shortcut instead of a numeric icon. This plan therefore proves OS records/channel state and exact cancellation, not pixels or a universal numeric result.
- Live read-only evidence, not closure: the physical Pixel currently has an owned silent notification with `number=2`, and both Mknoon channels report `mShowBadge=true`. The emulator has both channels badge-capable but its existing main-app notification setting is disabled, proving closure must use a fresh disposable install rather than inherited state.
- Resolved product decision: do not add ShortcutBadger, another OEM badge library, a vendor provider/broadcast bridge, or any of the rejected vendor permissions. Samsung/Xiaomi/Huawei/Oppo/Vivo/Sony/HTC and other unavailable launcher rendering is optional future sampling, never a Plan-332 closure condition.
- Affected files: `lib/core/notifications/local_notification_support.dart`; focused notification/snapshot/read/reconciliation tests; new `test/core/notifications/android_standard_launcher_badge_scope_contract_test.dart`; new `scripts/test/android_standard_badge_manifest_contract_test.sh` plus host-gate registration; `integration_test/support/sims_runtime_protocol.dart`, `integration_test/sims_dispatcher.dart`, new `integration_test/support/android_standard_badge_campaign.dart`, new `integration_test/scripts/run_android_standard_badge_completion.dart`, new `integration_test/scripts/android_standard_badge_completion_criteria.dart`, new `integration_test/android_standard_badge_completion_proof_test.dart`, the focused criteria test, Sims manifest rows, and proof binding. No database, production Kotlin, Gradle dependency, plugin registration, recovery worker, relay, FCM, or iOS production file belongs to this plan.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `55638de8c282435f`; the reported stale file was `ios/Flutter/flutter_export_environment.sh`, unrelated to these Android/app-owned anchors. Current source was checked directly.
- TDD query: `python3 graphify-arch/tdd_context.py query "Plan 332 remove ShortcutBadger android standard notification badge AndroidNotificationDetails.number showBadge local_notification_support FlutterNotificationService Pixel emulator tests gates" --profile tdd --budget 700`.
- Review refinement: `python3 graphify-arch/tdd_context.py query "buildConversationNotificationDetails AndroidNotificationDetails number showBadge AndroidNotificationChannel mknoon_messages local_notification_support_test" --profile review --budget 800`.
- Anchors: `FlutterNotificationService`, `local_notification_support.dart`, `flutter_notification_service_test.dart`, `local_notification_support_test.dart`, and `android_notification_completion_scope_contract_test.dart`.
- Reuse rule: execution may reuse these anchors, but current source and the live target matrix must be rediscovered before proof.

## Scope Contract And Guard

In scope:

- Set `showBadge: true` explicitly on both app-owned message channels and `channelShowBadge: true` on the high, silent, and dynamic conversation `AndroidNotificationDetails`. This removes reliance on plugin defaults without changing the intended runtime result.
- Preserve one positive, uncapped `number` per conversation card and omit `number` for zero/null. Direct `2` and group `3` must remain two independent card values; never turn either card into an app-global `5`.
- Preserve stable direct/group notification IDs, InboxStyle history, exact read/policy cancellation, and newer-sibling survival.
- Permanently reject known OEM badge dependencies, native provider/broadcast adapters, the exact vendor-permission set below, and `QUERY_ALL_PACKAGES` in app-owned dependency/native/merged-manifest surfaces.
- Add two independent Sims leaves using the existing `android.e2e.standard` prebuilt dispatcher and Android state guard. Each available target gets a fresh install, fresh disposable scenario/conversation identity, automated notification permission/setup, content-addressed proof, and complete restoration.

Must preserve:

- Per-conversation history and uncapped count -> `test/core/notifications/flutter_notification_service_test.dart::android conversation card carries canonical history and uncapped number`.
- Independent direct/group snapshot totals -> `test/core/notifications/conversation_notification_snapshot_test.dart::bounded direct and group unread projection`.
- Stable direct/group IDs and exact cancellation without `cancelAll` -> `flutter_notification_service_test.dart` stable-ID and exact-cancellation tests.
- Read-zero cancellation and concurrent newer-generation preservation -> the existing direct/group read-projector and reconciliation-wiring tests owned by Plans 330/331.
- Plan 331's global production dependency ban and inactive recovery ownership remain unchanged.
- User/app/channel notification settings remain authoritative in production. Test setup may change only captured disposable-test state and must restore it exactly.

Hard `Do not`:

- Do not add an app-wide Android badge aggregate, cached unread counter, badge reconciler, native gateway, process ticket, local Flutter plugin, AAR, provider write, or vendor broadcast.
- Do not add ShortcutBadger, `flutter_app_badger`, another badge package, or narrow Plan 331's existing dependency ban.
- Do not add or request any Android permission for launcher badging. Do not add `QUERY_ALL_PACKAGES`.
- Do not copy a global total onto every conversation card; launchers that aggregate active notification numbers could overcount it.
- Do not claim that Pixel Launcher renders a numeral, require a screenshot pixel/dot as semantic proof, or claim behavior for an unavailable launcher.
- Do not touch SQLCipher/schema, canonical settlement ordering, FlutterFire/recovery-engine registration, relay/FCM behavior, or iOS production behavior.

Deferred / accepted difference:

- Legacy manufacturer-specific numeric badge rendering is deferred. If compatible OEM hardware becomes available and the product later wants vendor APIs, that is a new TDD plan and a new permission/dependency decision.
- Samsung, Xiaomi, Huawei, Oppo, Vivo, Sony, HTC, and other unavailable OEM device legs are `N/A (target unavailable by project policy)`, not blockers or evidence gaps.
- Launcher/user settings may suppress or restyle the badge. The supported result is correct notification metadata, badge-capable channels, and exact owned-card lifecycle.
- iPhone absolute badge aggregation and remote-card recovery are owned entirely by Plan 333; Plan 332 supplies no shared aggregate or reconciler.

Dependencies:

- Plans 330 and landed portions of 331 own canonical direct/group snapshots, stable card identities, and read/policy cancellation. Plan 332 characterizes and preserves those contracts; it does not reopen their database or recovery architecture.
- Plan 333 is independent of Plan 332 and owns any aggregate/reconciler needed for iOS absolute badge projection.

### Forbidden Manifest Set

The merged debug and release manifests must contain none of these rejected vendor permissions:

```text
com.sec.android.provider.badge.permission.READ
com.sec.android.provider.badge.permission.WRITE
com.htc.launcher.permission.READ_SETTINGS
com.htc.launcher.permission.UPDATE_SHORTCUT
com.sonyericsson.home.permission.BROADCAST_BADGE
com.sonymobile.home.permission.PROVIDER_INSERT_BADGE
com.anddoes.launcher.permission.UPDATE_COUNT
com.majeur.launcher.permission.UPDATE_BADGE
com.huawei.android.launcher.permission.CHANGE_BADGE
com.huawei.android.launcher.permission.READ_SETTINGS
com.huawei.android.launcher.permission.WRITE_SETTINGS
android.permission.READ_APP_BADGE
com.oppo.launcher.permission.READ_SETTINGS
com.oppo.launcher.permission.WRITE_SETTINGS
me.everything.badger.permission.BADGE_COUNT_READ
me.everything.badger.permission.BADGE_COUNT_WRITE
```

## Test Contract

Use zero empty cells. `HEAD` means the source snapshot immediately before Plan 332 execution.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-332-01 | Every app-owned message channel/detail explicitly opts into standard Android badging | `test/core/notifications/android_standard_launcher_badge_scope_contract_test.dart::app-owned notification constructors explicitly pin standard badging`; `local_notification_support_test.dart::both message channels serialize showBadge true` and `::all message details expose channelShowBadge true` | host / current source plus real plugin value objects and method-channel serialization | Policy RED after adding the source contract: effective behavior is already true on HEAD, but constructors rely on external defaults -> both channels and all three detail construction paths contain explicit `true` arguments | Remove an explicit argument or set either property false -> source and behavioral owner red | Direct tests; AUTO `core-host-all` |
| TC-332-02 | Positive direct/group totals remain independent, positive, uncapped per-card numbers; zero/null omits the number; history remains bounded independently | existing snapshot and service tests plus `local_notification_support_test.dart::conversation details keep independent positive numbers and omit zero` | host / direct and `group:` conversation fixtures with totals `2`, `3`, `17`, `0`, and null | GREEN characterization on HEAD; add missing zero/high/silent assertions before production edits -> `2` and `3` remain separate and `17` is not capped to five history lines | Sum sibling cards to `5`, cap number to history length, count a reaction, or emit zero -> named owner red | Focused command; AUTO `core-host-all`, existing `ONE_TO_ONE_TESTS` / `GROUP_TESTS` ownership |
| TC-332-03 | Exact read/cancel removes only the target card; a sibling or newer generation survives; final zero leaves no owned content cards and never requires `cancelAll` | existing `flutter_notification_service_test.dart` exact-cancellation test, `direct_notification_read_projector_test.dart::TC-331-10 read acknowledges exact generation and preserves later sibling`, `group_notification_read_projector_test.dart` zero/race tests, and direct/group reconciliation-wiring suites | host / recording notification service and barrier-controlled direct/group fixtures | GREEN preservation sentinels on HEAD | Replace exact ID cancellation with `cancelAll`, cancel a newer generation, or retain a zero-unread card -> exact owner red | Focused commands; existing `1to1` and `groups` registrations |
| TC-332-04 | Production dependency/native sources and actual merged debug/release manifests stay free of OEM badge adapters, all 16 rejected vendor permissions, and `QUERY_ALL_PACKAGES` | `android_standard_launcher_badge_scope_contract_test.dart::production remains OEM badge adapter free`; existing `android_notification_completion_scope_contract_test.dart`; `scripts/test/android_standard_badge_manifest_contract_test.sh` | host / dependency and native-source census plus XML-parsed Gradle merged manifests | GREEN preservation on HEAD; new contracts must pass before and after the explicit standard-field edit | Add a known badge coordinate/plugin/native bridge, any denied permission, a transitive manifest contribution, or weaken the old ban -> exact test red | Direct Dart/shell commands; shell test registered once in `core-host-all` non-Dart inventory |
| TC-332-05 | The standard proof harness is fail-closed, target-specific, fresh-state, child-build-free, and independently availability-bounded | `test/integration/android_standard_badge_completion_criteria_test.dart`, `integration_test/android_standard_badge_completion_proof_test.dart`, Sims manifest/proof-binding tests, and discovery contract | host / synthetic artifacts, wrong target/source/APK/nonce/settings/cleanup mutations around `run_android_standard_badge_completion.dart` | Causal discovery RED: scenario/action/runner/leaves do not exist -> exactly two leaves consume one `build.android.e2e.standard` artifact and accept only their assigned target receipt | Reuse identity/receipt, accept stale package state, skip permission or setting restoration, build in a child, accept manual actions, or let one missing target suppress the other -> validator red | Direct criteria/manifest/proof/discovery tests; two new capability rows |
| TC-332-06 | USB Pixel proves high-card `number=2`, silent group-card `number=3`, both badge-capable channels, exact `2/3 -> 3 -> zero` owned-card lifecycle, and clean restoration | Sims leaf `notifications.android_standard_badge_completion.physical` | device / Pixel 6 `21071FDF600CSC` API 36, fresh install and disposable identity, real plugin/NotificationManager, raw `dumpsys notification --noredact` | Device-only proof absent on HEAD -> raw records bind exact package/channel/number/notification IDs and cancellation phases; launcher pixels are informational only | Accept global `5`, wrong/stale package, missing channel flag, `cancelAll`, manual action, inherited identity, or dirty cleanup -> receipt red | Pinned physical leaf after rediscovery; `build.android.e2e.standard` dependency |
| TC-332-07 | Available emulator independently proves the same standard metadata and lifecycle with its own fresh identity and receipt | Sims leaf `notifications.android_standard_badge_completion.emulator` | device / `emulator-5554` API 37, fresh install, same attested artifact, distinct disposable identity | Device-only proof absent on HEAD -> same exact raw discriminators and cleanup on the emulator | Reuse the physical identity/receipt, accept existing disabled app state, omit automated permission setup, or accept a wrong target -> receipt red | Pinned emulator leaf after rediscovery; independent policy N/A if unavailable |

### Test Notes

- TC-332-01 is a policy-hardening RED, not a claim that current users lack badge capability. The effective behavior tests are green on HEAD because plugin defaults are currently true.
- TC-332-02 never sums `2 + 3`. Android `number` belongs to one notification record; no app-wide numeric contract exists in this plan.
- TC-332-04 XML-parses Gradle's actual merged debug and release manifests. Grepping only checked-in manifest text would miss transitive permission contributions.
- TC-332-06/07 use the existing Sims runtime config/ack protocol, prebuilt dispatcher, Android app-state guard, ADB capture utilities, and artifact binding. The in-app test action calls app-owned production notification details; it does not post a substitute native notification.
- A Pixel Launcher dot/long-press surface capture may be retained as informational evidence only. The gating assertions are the raw OS records, channel `mShowBadge=true`, exact per-card numbers, lifecycle, target binding, and cleanup.
- No performance test is justified: the production change is constant constructor metadata with no new loop, query, bridge, or background work.

## Implementation Steps

1. Snapshot `git status --short` and preserve all unrelated Plan 331/331a/user work. Add TC-332-01/02/04 host contracts and TC-332-05 harness contracts first. Record that only the explicit-source policy and absent harness are causal REDs; existing runtime metadata, projection, and cancellation tests are preservation GREENs.
2. In `local_notification_support.dart`, add only `showBadge: true` to both channel constants and `channelShowBadge: true` to the high, silent, and dynamic conversation detail constructors. Do not change channel IDs, importance, sound, vibration, category, auto-cancel, history, or `number` logic.
3. Add the production source/dependency denial test and merged-debug/release-manifest shell contract. Pin every permission in Forbidden Manifest Set plus `QUERY_ALL_PACKAGES`; preserve the existing Plan-331 dependency ban. Register the shell contract exactly once without adding any dependency or manifest permission.
4. Extend the existing standard Sims dispatcher/state-guard infrastructure with a nonce/profile-gated standard-badge action and one role-parameterized host runner. Each independent leaf prepares a fresh install and distinct disposable identity, grants notification permission, captures/restores launcher badging state, publishes direct `2` on the high channel and group `3` on the silent channel through the app-owned notification service, captures raw channel/record evidence, cancels direct then group exactly, and proves no owned record remains. Use one central `android.e2e.standard` artifact, zero child builds, zero manual actions, and idempotent cleanup.
5. Run focused GREENs, exact Plan-330/331 preservation, manifest/harness contracts, affected curated gates, justified `core-host-all`, both currently available device leaves, strict analyzer/diff hygiene, and one incremental architecture-graph refresh after the coherent app-owned code change.

## Risks And Blind Spots

- Effective defaults can change in a future plugin upgrade -> TC-332-01 pins app-owned intent explicitly and checks serialized values.
- A device artifact can false-green from an old package/card -> fresh uninstall/state guard plus package/APK/source/run/nonce binding and pre/post owned-record census.
- The emulator currently has notifications disabled for the existing app -> each leaf uses fresh state and automated permission setup; captured settings are restored.
- `number` can be mistaken for a global or guaranteed numeric icon -> exact `2`/`3`, explicit rejection of `5`, and no pixel/numeral gate.
- Exact cancellation can delete a sibling/newer card -> TC-332-03 plus device `2/3 -> 3 -> zero` phases.
- A transitive dependency can silently restore vendor permissions -> TC-332-04 checks resolved merged manifests, not just source manifests.
- Test setup can disturb a personal device setting -> state guard records original app/launcher notification state and restoration failure is a test failure.
- Future OEM work can leak into this closure -> dependency, native-source, and permission denials require an explicit replan rather than silent expansion.

## Gate Cadence

- Per-plan closure: focused host contracts, exact Plan-330/331 preservation sentinels, the affected `1to1` and `groups` curated gates, completeness, the justified `core-host-all` family sweep, and both currently available Android target receipts.
- Do not run `feature-host-all`, `runtime-roots`, or full `host-all`: this plan changes only shared notification metadata plus test/Sims tooling, with no feature settlement owner or runtime-root change. Full `host-all` remains a wave/final-rollout gate under repository policy.
- Run the new merged-manifest shell test directly and register it once for later aggregate discovery; registration does not make full `host-all` a Plan-332 obligation.

## Acceptance Gates

```bash
# Snapshot and establish the honest HEAD baseline.
git status --short
flutter test \
  test/core/notifications/local_notification_support_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/core/notifications/conversation_notification_snapshot_test.dart \
  test/core/notifications/android_notification_completion_scope_contract_test.dart

# After adding tests but before production edits: policy/harness REDs only.
flutter test test/core/notifications/android_standard_launcher_badge_scope_contract_test.dart \
  --plain-name 'app-owned notification constructors explicitly pin standard badging'
flutter test test/integration/android_standard_badge_completion_criteria_test.dart

# Focused GREEN and exact projection/cancellation preservation.
flutter test \
  test/core/notifications/android_standard_launcher_badge_scope_contract_test.dart \
  test/core/notifications/local_notification_support_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/core/notifications/conversation_notification_snapshot_test.dart \
  test/core/notifications/android_notification_completion_scope_contract_test.dart \
  test/core/notifications/direct_notification_read_projector_test.dart \
  test/core/notifications/group_notification_read_projector_test.dart \
  test/features/conversation/application/direct_notification_reconciliation_wiring_test.dart \
  test/features/groups/application/group_notification_reconciliation_wiring_test.dart

# Resolved merged-manifest denial and exact host registration.
bash scripts/test/android_standard_badge_manifest_contract_test.sh
test "$(./scripts/run_host_test_gates.sh core-host-all --list | \
  rg -c 'android_standard_badge_manifest_contract_test\.sh')" -eq 1
bash scripts/test/host_test_gate_batch_contract_test.sh

# Harness registration, fail-closed validation, and discovery.
flutter test \
  test/integration/android_standard_badge_completion_criteria_test.dart \
  test/tool/sims/sims_runtime_dispatch_test.dart \
  test/integration/sims_runtime_dispatcher_protocol_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  test/tool/sims/sims_proof_binding_registry_test.dart
./scripts/test/reliability_simulation_discovery_contract_test.sh
dart tool/sims/sims.dart major --list --format tsv | \
  rg 'notifications\.android_standard_badge_completion\.(physical|emulator)'

# Affected curated and justified family gates.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh core-host-all \
  --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# Rediscover and pin only live targets. Each leaf uses a fresh identity and the
# same central prebuilt artifact; an unavailable leaf receives only policy N/A.
flutter devices --machine
adb devices -l
SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC \
  dart tool/sims/sims.dart major \
  --only notifications.android_standard_badge_completion.physical
SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  dart tool/sims/sims.dart major \
  --only notifications.android_standard_badge_completion.emulator

# Hygiene and coherent app-owned graph closure.
./scripts/check_flutter_analyze_strict.sh
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Device Proof Profile

- Profile: local-only standard Android OS-notification proof. No peer, relay, FCM credential, SQLCipher seed, or OEM adapter is required.
- Boundary proven: the real Flutter notification plugin and Android `NotificationManager` receive the app-owned high/silent details, both channels remain badge-capable, card numbers are independently `2` and `3`, exact cancellation leaves `3` then zero, and fresh state is restored.
- Live matrix observed during planning: USB Pixel 6 `21071FDF600CSC` on Android 16/API 36 and Android emulator `emulator-5554` on Android 17/API 37; both resolve home to `com.google.android.apps.nexuslauncher/.NexusLauncherActivity` and currently return `secure notification_badging=1`.
- Execution setup: rediscover targets; pin each command; use one attested `build.android.e2e.standard` artifact; generate a distinct disposable identity/conversation namespace per leaf; fresh-install the package; automate notification permission and any reversible launcher-setting setup; perform no manual tap; restore/uninstall all test state.
- Registration: `notifications.android_standard_badge_completion.physical` and `.emulator`, each depending on `build.android.e2e.standard` and each owning only its target resource and receipt. One missing target cannot suppress the other.
- Receipt: require exact source/APK/target/run/nonce/identity binding, raw pre/show/first-cancel/final-cancel dumps, both channel flags, exact notification IDs and `2/3 -> 3 -> zero` values, `childBuilds=0`, `manualActions=0`, `validationErrors=[]`, and successful cleanup/restoration.
- Visual Pixel Launcher surface: optional informational capture only. It cannot satisfy or fail the semantic gate by itself.
- Other OEM hardware: `N/A (target unavailable by project policy)` and optional future confidence only.

## Execution Interpretation And Done Criteria

- Expected RED: TC-332-01's explicit-source policy test and TC-332-05's missing action/runner/criteria/leaves fail before production/harness implementation. Do not mislabel already-green standard metadata as a missing behavior.
- Green baseline: effective high-channel badging, per-conversation `number=17`, bounded history, direct/group snapshot totals, stable IDs, exact cancellation, and the existing dependency ban are already green and must stay green.
- Pre-existing dirty tree: execution records `git status --short` and preserves unrelated Plan 331/331a/user changes. Do not normalize graph output or generated iOS environment files as part of this plan.
- Availability: the closure matrix is the USB Pixel plus one selected available Android emulator, each pinned after rediscovery. Additional emulators are optional. If either selected target disappears, only that leaf is exact policy N/A and the remaining leaf still runs; no absent OEM model/version is a blocker or evidence gap.
- Scope drift: a global Android aggregate, DB/schema edit, adapter/plugin/AAR, new permission, native production bridge, relay/FCM dependency, visual numeric guarantee, or iOS production edit stops execution and requires replan.

- [ ] Every app-owned channel/detail explicitly opts into standard Android badging and serialized behavior tests pass.
- [ ] Direct/group card numbers remain independent and uncapped; zero/null omission, bounded history, stable IDs, exact cancellation, and newer-card preservation pass.
- [ ] Source/dependency and actual merged debug/release manifests contain no OEM badge adapter, none of the 16 rejected vendor permissions, and no `QUERY_ALL_PACKAGES`.
- [ ] Both currently available Android leaves pass from fresh, distinct identities with one central artifact, exact raw OS evidence, zero manual actions/child builds, and clean restoration.
- [ ] Unavailable OEM rendering is recorded only as policy N/A/optional follow-up; no global or numeric-pixel claim appears in evidence.
- [ ] Focused, curated, `core-host-all`, analyzer, diff, and incremental Graphify gates pass with semantic outcomes.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First policy RED: add and run `android_standard_launcher_badge_scope_contract_test.dart::app-owned notification constructors explicitly pin standard badging`; it must fail only because explicit app-owned arguments are absent, while behavioral baselines remain green.
- First harness RED: `flutter test test/integration/android_standard_badge_completion_criteria_test.dart`; the action, strict artifact schema, and two capability leaves are intentionally absent.
- Preservation command: the first focused baseline command in Acceptance Gates.
- Manual registration: register the merged-manifest shell contract once under the later `core-host-all` inventory; add the standard dispatcher action, role-parameterized runner, strict criteria/proof binding, and two independent Sims leaves. Add no runtime root or nested package.
- Migration: none. Any database/schema/cached-counter proposal is outside this plan.
- Boundary closure: serial fresh-state proof on each rediscovered available Android target. Other manufacturer devices remain optional.
- Unresolved evidence: none at planning time; target availability is resolved immediately before each leaf.

## Reviewer Findings (2026-08-03)

- Initial verdict: `not-ready`; the former plan made a 16-permission vendor compatibility dependency a prerequisite and overdesigned an app-wide writer that standard Android does not expose.
- Product resolution: the compatibility exception was rejected. The aggregate/reconciler, plugin/AAR, Kotlin bridge, engine tickets, SQLCipher aggregate, vendor settings matrix, and `6 -> 3 -> 0` global bridge proof were removed.
- Critical re-review: current standard behavior is already effective; the remaining work is explicit-default hardening, permanent anti-OEM regression guards, and honest availability-bounded device receipts. No feature/performance/native dependency work is justified.
- Post-update verdict: `ready` for execution. Pixel/emulator proof closes the supported standard contract; absent OEM hardware and legacy numeric rendering are intentionally deferred and cannot block closure.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-03 | planning accepted | plan only | focused existing notification tests `+29`; snapshot test `+1`; live target/launcher/badging census complete | standard behavior exists; no OEM dependency is present | no planning blocker; implementation not started | add policy and harness REDs |
