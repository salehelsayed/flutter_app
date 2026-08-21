# 394 - Android Notification Residual Lifecycle And Direct Final-Barrier Closure

Status: execution-complete / host-closed
Type: Bug
Spec: post-Plan-393 current-source audit of the trimmed Android-led notification scope
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-21 14:29 CEST | Evidence Collector / Planner | Plan 393; both UI-23 coverage documents; direct/main-group/linked-group conversation owners; `firebaseMessagingBackgroundHandler`; focused tests and gate registrations | The broad Android device/E2E scope is closed. Two null-lifecycle product edges and bounded direct final-barrier coverage remain; no device, relay, DB, or architecture work is justified. | Add the five-row causal/preservation contract, make two literal lifecycle corrections plus one narrow test hook, and close the notification wave with one concurrent final `host-all`. |
| 2026-08-21 14:42 CEST | Reviewer | Plan 394; direct/linked lifecycle callers; direct/group validators; durable event/tone lease; exact tests and gate scripts | Initial verdict `plan-fixes-required`: direct canonical fixture was impossible, reacquisition was vacuous, reaction tone key was wrong, and linked-group null lifecycle was a missed sibling. | Apply only the bounded source-backed deltas and rerun counterexamples. |
| 2026-08-21 14:48 CEST | Arbiter | Revised five-row contract, literal commands, registrations, platform capture and gate cadence | All verified blockers are closed; core bet confirmed; final verdict `ready`. | Execute the two REDs, behavior-identical hook, focused GREEN/mutations, affected lanes, then one concurrent final wave gate. |

## Problem And Evidence

- Behavior to improve: direct and linked-group conversations must mark unread content read only after lifecycle authority is known to be `resumed` and the exact conversation remains tracked; direct nondurable message/reaction notifications need causal coverage for their existing final canonical/visibility barrier and exact claim rollback.
- Impact: on a cold mount where Flutter has not published lifecycle state, both `ConversationWired` and `LinkedGroupConversationWired` currently treat unknown as resumed and can clear unread state without known foreground authority. Separately, the live direct message/reaction final barrier is implemented but the named Plan-393 handler regression exercises only group fallbacks, leaving a future direct bypass or owner leak invisible.
- Confirmed root cause/current gaps: `ConversationWired.initState` at `lib/features/conversation/presentation/screens/conversation_wired.dart:1381-1386` maps nullable `WidgetsBinding.instance.lifecycleState` to `AppLifecycleState.resumed`; `_markAsRead` at `:2444-2455` therefore accepts unknown initial lifecycle when the tracker is exact. `LinkedGroupConversationWired.initState` at `lib/features/groups/presentation/screens/linked_group_conversation_wired.dart:821-831` explicitly treats `null || resumed` as readable, sets the group tracker, and `_reload` marks visible incoming rows at `:996-1008`. Flutter exposes the causal test fixture through `SchedulerBinding.resetInternalState()` at `flutter/lib/src/scheduler/binding.dart:395-403`.
- Existing coverage: `test/features/conversation/presentation/screens/conversation_wired_test.dart:1924-1995` proves direct paused/resumed and missing-tracker behavior; `test/features/groups/presentation/group_conversation_wired_test.dart:10766-10834` proves the linked group inactive/resume transition but not null initialization; `test/features/push/application/background_message_handler_test.dart:203-485` proves direct message/reaction canonical decisions; `:669-879` proves the full nondurable final barrier and rollback only for group; `:1050-1239` preserves one direct message and one direct reaction when canonical authority is unavailable.
- Missing coverage: the direct widget owner has no null-initial-lifecycle or post-mount peer-mismatch row; the linked-group owner has no null-initial-lifecycle row. The handler has no end-to-end direct message/reaction assertion that owners reach `publishing`, a last-moment denial posts zero native cards, and exact event/tone ownership becomes reacquirable.
- Refuted findings: a new final-barrier production mechanism is not required. `authorizeNondurableNativeEntry` already validates direct canonical state and rereads exact visibility at `lib/features/push/application/background_message_handler.dart:1356-1448`; `publishAtNativeBoundary` invokes it at `:1495-1501`. Exact rollback after known pre-native denial is owned inside `DurableNotificationToneLease` at `lib/core/notifications/durable_notification_tone_lease.dart:647-699,1070-1122`; the handler's outer catch is secondary cleanup/reporting, not the primary publishing-state rollback. A new device campaign is also not required: Plans 392-393 already retain the OS/cross-device boundary, and this residual is deterministic lifecycle/decision coverage below that boundary.
- Unresolved findings: none. The review confirmed that the hard-wired direct final validator cannot be deterministically driven to `read` by the existing preview-state fakes; this plan therefore permits exactly one private `@visibleForTesting` validator override, parallel to the incumbent group seam, while keeping the production default byte-for-behavior.
- Affected production, test, and gate files: `lib/features/conversation/presentation/screens/conversation_wired.dart`; `lib/features/groups/presentation/screens/linked_group_conversation_wired.dart`; `lib/features/push/application/background_message_handler.dart` (test hook only); their three primary test files; four preservation fixtures surfaced by the affected lanes in `conversation_wired_change_coalesce_test.dart`, `reaction_notification_pipeline_test.dart`, `production_application_bootstrap_phase_contract_test.dart`, and `background_storage_deadline_test.dart`; the two UI-23 coverage documents; this plan and `Test-Flight-Improv/00-INDEX.md`. Existing registration in `ONE_TO_ONE_TESTS` and `GROUP_TESTS` is preserved; no gate-script edit is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `eeead3133f8b5554`; `stale:ios/Flutter/flutter_export_environment.sh` only, which is outside this Android/host boundary.
- Query / profile: `python3 graphify-arch/tdd_context.py query "ConversationWired initState _appLifecycleState _markAsRead ActiveConversationTracker firebaseMessagingBackgroundHandler authorizeNondurablePublication notification owner release direct message reaction final barrier tests gate registration" --profile tdd --budget 700` (`query_id=4897309ac2c04414`, `evidence_digest=36c3c14831a34c90`).
- Anchors: `_markAsRead` -> `lib/features/conversation/presentation/screens/conversation_wired.dart:2444`; `ActiveConversationTracker` -> `lib/core/notifications/active_conversation_tracker.dart:5`; `firebaseMessagingBackgroundHandler` -> `lib/features/push/application/background_message_handler.dart:728`.
- Surfaced proof/gate files: `test/features/conversation/presentation/screens/conversation_wired_test.dart`; `test/features/push/application/background_message_handler_test.dart`; `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: the linked-group sibling was not surfaced by the compact query; its null lifecycle/read caller, the nullable Flutter binding fixture, exact direct authorizer/lease rollback lines, and curated-array membership were verified in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Change only the two fail-open null lifecycle initializers: use an existing non-resumed `AppLifecycleState` value for direct, and require literal equality to `resumed` for linked group.
- Add one causal null-lifecycle widget row and one peer-mismatch preservation row to the existing direct conversation test file.
- Add one causal null-lifecycle widget row to the existing linked-group test owner.
- Add exactly one private direct post-show validator function variable plus `@visibleForTesting` set/reset functions, mirroring the incumbent group validator seam. The production default remains `_validateBackgroundDirectNotificationAfterShow`; no public API or behavior changes.
- Add one parameterized direct-handler preservation row to the existing background-handler test file: direct message denied by injected canonical-read authority, direct reaction kept canonically then denied by exact visibility, and one direct unknown-visibility control that still posts. The two denial legs must hold their final boundary, prove exact event and tone records reached `publishing`, then assert zero `show`, exact suppression reason, and successful exact owner reacquisition after denial.
- Reconcile the stale earlier N11/final-gate traceability rows and Plan-393 residual wording in both UI-23 documents after GREEN; record Plan 394 as the bounded post-audit closure without changing the trimmed scope.

Must preserve:

- Explicit `resumed` plus the exact tracked direct or linked-group conversation marks the eligible unread rows; paused, null, missing tracker, and a different peer/group do not -> `TC-394-01` through `TC-394-03`.
- Unknown direct canonical authority continues to produce one typed direct message and one typed direct reaction notification; an exception from final visibility fails toward one notification -> `TC-394-04` and `TC-394-05`.
- The already-covered group final barrier and group lifecycle behavior remain unchanged -> existing `TC-393-04` plus the final aggregate gate.
- Plans 392-393 Sims registrations and retained typed, sound, strict, projection, G21, G30, and recovery evidence remain unchanged; this plan does not recapture them.

Hard `Do not`:

- Do not add a lifecycle abstraction, nullable lifecycle API, second read owner, notification framework, new test file, or separate plan per case.
- Do not add any testability surface beyond the one private direct-validator variable and its set/reset pair; do not alter its production default, validator algorithm, or public API.
- Do not change DB v116, SQLCipher, relay/wire/native/FCM code, notification architecture, Sims manifests, build profiles, or device harnesses.
- Do not run S1-S16, payload/G24, typed reaction, strict, projection, recovery, iOS, emulator, or USB-device campaigns.
- Do not pull Apple/release/cohort/OEM/MessagingStyle, third-device bystander, literal Chat-B device, or exhaustive media/flavor work into this plan.

Deferred / accepted difference:

- Apple/release/cohort/OEM and optional exhaustive coverage remain with the owners already recorded in UI-23 §4.15. G24 remains policy-N/A on the available target; none is a Plan-394 blocker.
- Host method-channel/visibility fixtures are the accepted tier for this deterministic pre-native decision and owner-release seam. The already-retained Plan-393 device artifacts continue to own real FCM, process death, and OS-card behavior.

Dependencies:

- Plan 393 is execution-complete and supplies the retained Android device evidence. Plan 394 changes no transport or device contract; its final aggregate run supersedes Plan 393's earlier host snapshot for the resulting tree.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-394-01 | Unknown initial lifecycle cannot mark a direct conversation read; a later explicit resume with the exact tracker can. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::TC-394-01 direct read treats unknown initial lifecycle as non-resumed authority` | Widget host; `WidgetTester`, `InMemoryMessageRepository`, real `ActiveConversationTracker`, and `tester.binding.resetInternalState()` create a genuine null lifecycle. | **Causal RED:** HEAD coerces null to resumed and the post-frame callback consumes unread state. **GREEN:** unread remains 1 while lifecycle is null, then becomes 0 only after explicit `resumed` with the same exact peer. | Temporarily restore `?? AppLifecycleState.resumed`; TC-394-01 must re-red, then revert. | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'TC-394-01 direct read treats unknown initial lifecycle as non-resumed authority'`; existing `ONE_TO_ONE_TESTS` registration at `scripts/run_test_gates.sh:109` plus AUTO `test/features/**` glob. |
| TC-394-02 | A peer that becomes non-exact after mount cannot be marked read by the subsequent resume callback. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::TC-394-02 direct read rechecks the exact peer after resume` | Widget host; mount empty while resumed, transition the mounted route to paused, insert unread state, move the real tracker to another peer, then publish resumed. | **GREEN sentinel:** HEAD already retains unread because `_markAsRead` rereads `tracker.isViewing(_contact.peerId)`; the missing regression becomes explicit. | Temporarily remove the exact-peer predicate at `conversation_wired.dart:2448`; TC-394-02 must red, then revert. | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'TC-394-02 direct read rechecks the exact peer after resume'`; same existing `ONE_TO_ONE_TESTS` and AUTO registration. |
| TC-394-03 | Unknown initial lifecycle cannot activate or mark a linked-group surface read; explicit resume activates the exact group and marks only eligible visible incoming rows. | `test/features/groups/presentation/group_conversation_wired_test.dart::TC-394-03 linked group read treats unknown lifecycle as non-resumed authority` | Widget host; existing `LinkedGroupConversationWired` fakes, real tracker, incoming unread row, and `tester.binding.resetInternalState()`. | **Causal RED:** HEAD treats null as resumed, activates `group:<id>`, and invokes `markVisibleMessagesRead`. **GREEN:** null leaves tracker inactive and mark count 0; explicit resume activates the exact group and marks the one eligible row once. | Temporarily restore `lifecycleState == null || lifecycleState == AppLifecycleState.resumed`; TC-394-03 must re-red, then revert. | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'TC-394-03 linked group read treats unknown lifecycle as non-resumed authority'`; existing `GROUP_TESTS` registration at `scripts/run_test_gates.sh:517` plus AUTO `test/features/**` glob. |
| TC-394-04 | At the last nondurable native boundary, canonical-read denial for a direct message and exact-visible denial for a direct reaction both roll back publishing owners and post zero cards; an unknown visibility exception still posts once. | `test/features/push/application/background_message_handler_test.dart::TC-394-04 nondurable direct final barrier rolls back exact message and reaction owners` | Host application test; one private direct-validator override with production-default reset, typed fallbacks, real temporary `DurableNotificationToneLease`, held validator/visibility readers, flow-event sink, and mocked local-notification channel. Message/read, reaction/visible, and message/visibility-error are three discriminating legs, not a content matrix. | **GREEN sentinel:** source already routes direct canonical and exact visibility through the final authorizer and the lease rolls back known pre-native denial. While each denial is held, the exact event JSON and sole tone sidecar must both say `publishing`; after release it emits exactly `event_claim_ownership_lost_before_show`, makes zero `show` calls, and exact owners are reacquirable. The visibility-error control makes exactly one `show`. | Run four bounded mutations independently and revert each: bypass the direct canonical result (message/read shows), allow the exact-visible result (reaction/visible shows), skip the event `publishing` abort (event reacquisition fails), and skip the tone `publishing` abort (tone reacquisition fails). | `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'TC-394-04 nondurable direct final barrier rolls back exact message and reaction owners'`; existing `GROUP_TESTS` at `scripts/run_test_gates.sh:685` plus AUTO `test/features/**`. Keep this shared file in its incumbent owner. |
| TC-394-05 | Unknown canonical authority must continue to fail toward one managed typed direct message and one managed typed direct reaction notification. | `test/features/push/application/background_message_handler_test.dart::authenticated durable-authority deferral presents the non-durable fallback card (direct message)` and `::authenticated durable-authority deferral presents the non-durable fallback card (direct reaction)` | Host application GREEN sentinels; real empty display-outbox DB fixture, typed fallback, isolated notification registry, known non-suppressing visibility, mocked native channel. | **GREEN sentinel:** both existing tests show exactly one managed typed card; the message row also preserves its existing audible assertion. This row claims unknown canonical authority only; TC-394-04 separately owns unknown visibility. | Temporarily map the direct unknown canonical decision to `read`/deny; at least one named sentinel must red, then revert. | `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'authenticated durable-authority deferral presents the non-durable fallback card (direct message)'` and `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'authenticated durable-authority deferral presents the non-durable fallback card (direct reaction)'`; existing `GROUP_TESTS` plus AUTO registration. |

### Test Notes

- TC-394-01 and TC-394-03 register teardown before mount and restore the binding to `resumed`, so a genuine null fixture cannot contaminate later widget tests. Each asserts repository/callback effects before explicit resume, not a private flag alone.
- TC-394-04's direct-validator override has the same named-argument contract as `_validateBackgroundDirectNotificationAfterShow`; setUp/tearDown must reset it to that production default. The message leg returns `read` while visibility is non-suppressing and must not evaluate visibility. The reaction leg returns `keep`, then its held exact-visibility reader returns `maySuppress: true` exactly once.
- Each TC-394-04 leg sets `debugDefaultTargetPlatformOverride = TargetPlatform.android` before any fixture construction and also constructs `DurableNotificationToneLease(platform: TargetPlatform.android, ...)`, because the lease snapshots its platform and only Android enters `publishing`. It then installs the appropriate message/reaction coordinator resolver plus an isolated notification registry and asserts the validator receives the exact direct peer plus content kind/event identity exactly once. The held visibility reader asserts that same direct identity; an earlier invalid/dedupe exit cannot satisfy the row.
- At each held denial boundary, read the exact event claim path built from `eventClaimsDirectoryName` plus `messageEventClaimFileName` and require `state: publishing`. In the fresh per-leg tone directory require exactly one pending sidecar with `state: publishing`. This defeats the vacuous implementation that never acquired owners.
- After denial, reacquire `new_message` + raw message id or `message_reaction` + `boundedReactionEventIdentity`. The direct-message tone key is the normalized conversation peer; the direct-reaction tone key is the exact `fallback.payload` used at `background_message_handler.dart:1143-1148`, not merely the peer. Release all reacquired owners and delete only the per-leg temporary directory.
- TC-394-05's two existing tests prove unknown canonical authority, not unknown visibility or identical sound assertions. TC-394-04 separately drives a throwing visibility reader and requires one native `show` so fail-toward-notification remains explicit.

## Implementation Steps

1. Snapshot `git status --short` and record all pre-existing Plan-392/393 and documentation changes. Add TC-394-01 and TC-394-03 first; run their exact commands to capture the two independent null-lifecycle REDs.
2. Before authoring TC-394-04, add the one private direct post-show validator variable and visible-for-testing set/reset pair in `background_message_handler.dart`, parallel to the existing group seam, then route the existing direct call through it. Its production default remains the current validator and the validator implementation itself is unchanged. This is a behavior-identical testability step. Stop-if deterministic coverage requires secure-storage/DB replacement, a public runtime API, or another hook.
3. Add TC-394-02/04/05 and verify their honest GREEN-sentinel baselines on behavior-identical HEAD. TC-394-04 explicitly pins each lease to Android before observing `publishing`.
4. Apply the two behavior fixes: in `ConversationWired.initState`, replace only the null-to-resumed fallback with an existing conservative non-resumed lifecycle value (prefer `AppLifecycleState.detached`); in `LinkedGroupConversationWired.initState`, replace only `null || resumed` with literal equality to `resumed`. Keep the fields non-nullable and retain the incumbent exact-tracker checks. Stop-if either fix requires a new lifecycle abstraction, injected lifecycle owner, or API cascade.
5. Complete TC-394-01 through TC-394-05. Run the two lifecycle mutations and TC-394-04's canonical, visibility, event-abort, and tone-abort mutations one at a time; record the expected re-red, restore each byte-for-behavior, and rerun focused GREEN.
6. No harness registration edit is expected. Verify `conversation_wired_test.dart` remains in `ONE_TO_ONE_TESTS`; `group_conversation_wired_test.dart` and `background_message_handler_test.dart` remain in `GROUP_TESTS`; all three remain AUTO-discovered under `test/features/**`.
7. Run the three focused files concurrently, both affected curated lanes (`1to1`, then `groups`), the exact Plan-393 contract census, scoped analysis/hygiene, then the single concurrent final notification-wave `host-all` below. Do not add `core-host-all`, `feature-host-all`, Sims, or device campaigns.
8. After all code/test gates pass, update stale N11/final-gate rows and residual wording in both UI-23 documents, mark Plan 394's execution evidence without rewriting Plan 393 history, update the index entry, refresh the architecture graph once, and run final diff hygiene.

## Risks And Blind Spots

- Flutter binding state can leak between widget tests -> TC-394-01/03 register teardown before mount and explicitly restore `resumed`.
- A superficially correct test could assert suppression without proving ownership -> TC-394-04 holds the real final boundary, verifies exact `publishing` records first, checks the typed branch/disposition, then proves rollback by exact reacquisition.
- Strengthening known-denial behavior could accidentally suppress unknown facts -> TC-394-04's throwing-visibility control and TC-394-05 preserve fail-toward-notification.
- Lifecycle / derived-state durability: TC-394-01/03 prove fresh direct and linked-group mounts with no lifecycle authority remain unread until an actual resume; TC-394-02 proves the direct active peer is re-derived at resume time.
- Sibling-surface consistency: direct, main group, and linked group now share the literal null-false policy under named tests; message/canonical-read and reaction/exact-visible exercise both direct final-authorizer inputs; the existing group barrier stays unchanged.
- Destructive-action side effects: no production delete/cancel or persistent fixture is introduced; TC-394-04 deletes only per-test temporary owner directories after releasing claims.
- Invariant re-verification under new transitions: resume rechecks lifecycle and the current tracker; final entry rechecks current canonical/visibility authority, and the lease rolls back both exact `publishing` owners after known denial.

## Gate Cadence

- Per-plan causal closure: the three exact Dart files run together with Flutter concurrency 2, followed once by the affected curated `1to1` and `groups` lanes, the exact Plan-393 notification census, scoped analysis, formatting, and diff hygiene. No device, Sims, `core-host-all`, or `feature-host-all` rerun is justified.
- Exceptional final aggregate: this small post-audit production change occurs after Plan 393's earlier notification-wave aggregate, so that snapshot cannot certify the resulting tree. As explicitly requested, run `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 2 --reporter failures-only` exactly once after all focused gates pass. Concurrency 2 is the established stable setting; Plan 393 recorded resource-pressure-only failures at 4. Do not raise it or repeat `host-all` during implementation.
- This concurrent `host-all` is the final Android notification dependency-wave checkpoint, not a new per-plan default. Final rollout/release remains separately owned and may run its later independent aggregate when that excluded work begins.
- Shared tests outside feature/core globs: `bash scripts/test/plan393_notification_test_contract_census_test.sh` runs exactly once; no new shared test is added.

## Acceptance Gates

```bash
# Snapshot only; preserve unrelated/user-owned work.
git status --short

# TC-394-01 causal RED before the production edit: expect non-zero because
# null lifecycle is currently coerced to resumed and unread becomes zero.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'TC-394-01 direct read treats unknown initial lifecycle as non-resumed authority'

# TC-394-03 causal RED before the production edit: expect non-zero because
# linked group currently treats null lifecycle as resumed and marks its row.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'TC-394-03 linked group read treats unknown lifecycle as non-resumed authority'

# Focused GREEN after the two lifecycle edits, one test hook, and test additions.
# Expect exit 0, all three exact files selected, and zero failed tests.
flutter test --concurrency=2 --reporter failures-only \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/push/application/background_message_handler_test.dart

# Affected curated production lanes. Expect exit 0, the direct owner selected
# by 1to1, and both linked-group/shared-handler owners selected by groups.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Exact shared registration/preservation census. Expect exit 0 with every
# retained TC-393 owner present exactly as its contract requires.
bash scripts/test/plan393_notification_test_contract_census_test.sh

# Scoped hygiene for the changed production/test directories.
dart format --output=none --set-exit-if-changed \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/groups/presentation/screens/linked_group_conversation_wired.dart \
  lib/features/push/application/background_message_handler.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/push/application/background_message_handler_test.dart
dart analyze lib/features/conversation/presentation/screens
dart analyze lib/features/groups/presentation/screens
dart analyze lib/features/push/application
dart analyze test/features/conversation/presentation/screens
dart analyze test/features/groups/presentation
dart analyze test/features/push/application

# One final notification-wave aggregate, after every focused gate passes.
# Expect exit 0, zero unexpected Flutter failures, and every registered
# Go/relay/native tail green. Do not run this command earlier or more than once.
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 2 --reporter failures-only

# Refresh app-owned topology once after coherent implementation/documentation.
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-394-01 and TC-394-03 are the only causal REDs; each must fail because unread is consumed under a null lifecycle, not due to compilation, fixture setup, or unrelated dirty-tree failure.
- Green sentinels: TC-394-02/04/05, positive resumed/exact direct and linked-group behavior, the existing TC-393 group barrier, and Plan-393 census stay green.
- Pre-existing dirty tree / known failure: Plans 392-393 implementation, both UI-23 documents, index, Graphify outputs, and related notification files are current user-owned work. Record and preserve them; none is an expected test failure.
- Environment blocker: none for this host-only plan. A host resource failure is not hardware policy-N/A; diagnose it. Keep final concurrency at 2 rather than increasing pressure.
- Scope drift: any need for DB/schema, handler behavior change beyond the private default-preserving validator hook, native/relay/wire, device/Sims, new lifecycle/test framework, or excluded cross-platform/release work stops completion pending an explicit plan amendment.

- [x] TC-394-01 records causal RED, focused GREEN, and the resumed-fallback mutation re-red/revert.
- [x] TC-394-02 proves post-mount peer mismatch remains unread, while explicit resumed+exact remains positive.
- [x] TC-394-03 records causal linked-group null-lifecycle RED, focused GREEN, and mutation re-red/revert; explicit resumed+exact marks only the eligible row.
- [x] TC-394-04 proves both direct denial legs first reach exact event/tone `publishing`, then post zero cards and roll back/reacquire exact owners; unknown visibility posts once; canonical, visibility, event-abort, tone-abort, and exact reaction-tone-key mutations independently re-red.
- [x] TC-394-05 preserves one managed typed direct message and one managed typed direct reaction when canonical authority is unknown.
- [x] Existing registration is verified without duplicating the shared handler test into another curated array.
- [x] Focused files, `1to1`, `groups`, exact census, scoped analysis/format/diff hygiene, and the final complete-worktree aggregate proof are green: the concurrency-2 process completed 14,602 Flutter tests, 11 intentional skips, and its first 13 tails; the exact source-equivalent continuation completed tails #1385-#1387 after restoring unchanged ignored worktree prerequisites.
- [x] Both UI-23 documents and the index reconcile the post-audit residual without reopening or claiming excluded Apple/release/OEM/optional work.
- [x] Scope Contract And Guard is respected; no device, migration, relay, or architecture work is introduced.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'TC-394-01 direct read treats unknown initial lifecycle as non-resumed authority'`; second independent RED is the exact TC-394-03 linked-group command in Acceptance Gates.
- Preservation command: `flutter test --concurrency=2 --reporter failures-only test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/push/application/background_message_handler_test.dart`.
- Manual registration: none; preserve `ONE_TO_ONE_TESTS`, `GROUP_TESTS`, and AUTO feature globs.
- Migration: none; DB remains v116.
- Boundary closure: host-only. Plans 392-393 retain the real Android/FCM/OS evidence; no mobile target is used.
- Unresolved evidence: none at planning time. A non-GREEN TC-394-04 on source-identical HEAD beyond a faulty new fixture triggers a plan amendment before any handler behavior edit.

## Independent Review Findings

Initial `$tdd-review` verdict: `plan-fixes-required`; disposition: `apply-plan-fixes`. The revised plan closes every verified finding without adding a new delivery slice:

- **Evidence/bypass:** the direct null fallback was confirmed, and the bypass sweep found the same fail-open null rule in production `LinkedGroupConversationWired`. TC-394-03 and the affected `groups` lane now own that sibling rather than leaving Plan 393's “every direct/group read trigger” claim broader than its proof.
- **Executable direct fixture:** preview-state resolvers cannot force the hard-wired final direct validator to `read`. One private default-preserving validator override, symmetric with the existing group seam, is now the sole allowed test hook; production validation remains unchanged.
- **Non-vacuous rollback:** post-denial reacquisition alone could pass if owners were never acquired. TC-394-04 now holds the actual final boundary, requires exact event and tone records in Android `publishing`, then proves zero native shows, exact suppression, and exact reacquisition. Event and tone abort mutations are independent.
- **Branch discrimination:** message exercises canonical `read` with zero visibility evaluations; reaction exercises canonical `keep` followed by exact-visible denial; a throwing visibility control must still show once. Validator peer/kind/event and visibility identity are asserted, so an earlier invalid/dedupe exit cannot satisfy the test.
- **Exact platform/key contract:** every lease is constructed with `platform: TargetPlatform.android` before the held-state check. Direct message reacquires the peer tone key; direct reaction reacquires its exact `fallback.payload` key.
- **Execution integrity:** the hook lands before its GREEN test is authored; the two lifecycle cases remain the only causal REDs. Existing `ONE_TO_ONE_TESTS`/`GROUP_TESTS` and AUTO registration are reused. Only three focused files, the affected `1to1` and `groups` lanes, one exact census, and one explicitly requested final `host-all` at the established stable concurrency 2 are run; device/Sims and unrelated host families stay excluded.

Review Graphify branch: `python3 graphify-arch/tdd_context.py query "Plan 394 counterexample ConversationWired.initState lifecycleState null resetInternalState _markAsRead exact tracker authorizeNondurableNativeEntry direct message reaction DurableNotificationToneLease owner release ONE_TO_ONE_TESTS GROUP_TESTS host-all concurrency" --profile review --budget 800` -> anchored, fingerprint `eeead3133f8b5554`, `query_id=7335753bd42a466a`, `evidence_digest=2f15dea167af3c8a`; the linked-group sibling was then verified directly because it was absent from the compact result.

Lens disposition after repair: L1 evidence/classification `clear`; L2 causality `clear`; L3 bypass/scope `clear`; L4 command/gate integrity `clear`; L5 boundary/reversibility `clear`. Blind-spot hits B-2/B-3/B-4/B-5/B-6/B-9 are closed above; B-1/B-8/B-10 are N/A for this host-only, non-schema, non-parity change; B-7 is clear because the single hook preserves the current production default.

## Arbiter Decision

Planning-time final verdict: `ready`; core bet `confirmed`; disposition `execute`. Execution is now complete and host-closed. One Plan 394 was sufficient, and no user-owned product or release decision remains inside the trimmed Android-led scope.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-21 | RED / lifecycle closure | Direct and linked-group widget owners | TC-394-01 and TC-394-03 each exited 1 for the intended fail-open lifecycle effect; TC-394-02 remained a HEAD-green exact-peer sentinel. | Direct null lifecycle consumed unread state; linked null lifecycle activated `group:group-1`; all three named tests passed after the two literal fixes. Restoring either fail-open predicate or removing the exact-peer reread independently re-redded and was reverted. | Causal lifecycle contract closed. | Exercise the direct final barrier. |
| 2026-08-21 | Direct final-barrier preservation | Background handler and durable event/tone owners | TC-394-04 and both TC-394-05 sentinels passed; the full handler owner passed 88 tests. | Canonical-read and exact-visible denial each held exact event/tone owners in `publishing`, posted zero cards, and permitted exact reacquisition; unknown authority posted once. Canonical, visibility, event-abort, tone-abort, unknown-authority, and wrong reaction-tone-key mutations independently re-redded and were restored. | Existing production behavior is now causally protected; the only handler production change is the private default-preserving test seam. | Run affected preservation owners and lanes. |
| 2026-08-21 | Affected preservation | Ten scoped production/test files | Focused bundle `+482 ~3`; `1to1` `+3365 ~10`; `groups` `+4614`; Plan-393 census PASS. | Four incumbent fixtures were updated to establish the now-required explicit lifecycle or current validator/default contract. Exact repaired deadline and bootstrap owners passed; scoped format/analyze/diff hygiene and independent counterexample review were clear. | No DB, native, relay, wire, FCM, device, or public API surface changed. | Run the final complete-worktree host aggregate at concurrency 2. |
| 2026-08-21 | Final host closure | Complete isolated resulting tree plus ignored shipped test prerequisites | `host-all --batch-flutter --concurrency 2 --reporter failures-only` passed 14,602 Flutter tests with 11 intentional skips and its first 13 registered Go/relay tails. The disposable worktree then stopped at native tail #1385 only because ignored Gradle/CocoaPods artifacts were absent; after restoring the repository's unchanged ignored artifacts, exact tails #1385-#1387 passed: Plan 371 native contract, Plan 373 iOS NSE 16/16 with three mutation re-reds, and Plan 374/375/393 Android 9 classes / 68 methods. | All 16 registered Go/relay/native tails have green results against identical Plan-394 source. The source-equivalent continuation is recorded instead of repeating the already-green 14,602-test Flutter batch. No device campaign was added or rerun. | Host closure complete; ignored-worktree packaging was diagnosed and did not alter source or semantics. | Done; documentation reconciled, Graphify refreshed once, and the scoped closure is ready to commit. |
