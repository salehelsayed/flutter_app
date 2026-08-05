# 333 - iPhone Notification Recovery Parity

Status: implemented; host/simulator verified; physical evidence-gated
Type: Bug
Spec: free-text user intent (2026-08-03), plus the iOS badge and exact-remote-card residuals from Plans 329 and 331
Classification: reviewed, tightened, implemented, and post-implementation audited after the 2026-08-04 corrections below
Closure tier: host + pinned iOS simulator XCTest + one availability-bounded physical-iPhone APNs/NSE campaign

## Outcome

On iPhone, a parity-authorized direct or group notification will:

- contribute once to an absolute unread badge when it has a trusted canonical ordinary-message identity;
- keep `content.badge == nil`, so delayed notification presentation cannot overwrite a newer Runner badge;
- retain the exact Apple request identifier needed to remove that remote card after canonical read, delete, policy, or account convergence; and
- converge after runtime-ready, resume, foreground push handling, and existing direct/group notification settlement.

The guarantee is deliberately narrow:

- a request with no trusted canonical event identity is badge-neutral and cannot be retired for an individual-message deletion while another eligible message remains; it is retired only by whole-conversation, zero-eligible, policy, or account convergence;
- an unobserved request is never treated as dismissed merely because it is absent from Notification Center;
- iOS provides no dead-process recovery SLA, Android dropped-message callback, or general silent worker equivalent; and
- existing sanitizer behavior remains privacy-clearing, but this plan does not claim that blank sanitized content suppresses an Apple notification without the restricted filtering entitlement.

## Evidence And Root Cause

- Before implementation, `ios/NotificationService/NotificationService.swift` received the exact `UNNotificationRequest.identifier` but discarded it before the content handler.
- `ios/NotificationService/NotificationPreviewResolver.swift` already derives trusted account, conversation, event, and policy facts for direct/group ordinary and reaction notifications. It clears provider badge metadata and supplies trusted `threadIdentifier` grouping.
- `lib/core/notifications/flutter_notification_service.dart` cancels local Flutter notification IDs. Those IDs do not identify remote APNs requests.
- Before implementation, `lib/app/application_root.dart` started staged-envelope ingest with `unawaited(...)` at runtime-ready and resume, so canonical projection could overtake retained ingress.
- `UNUserNotificationCenter.removeDeliveredNotifications(withIdentifiers:)` is exact-ID-only and has no completion. A second inventory read is useful only after delivery was previously observed; absence cannot distinguish dismissal from a request not yet delivered.
- `UNUserNotificationCenter.setBadgeCount` is available on iOS 16+ and has a completion callback. `UIApplication.shared` is unavailable to extensions, so iOS 13-15 can update the badge only when Runner is active.
- `summaryArgument`/`summaryArgumentCount` are deprecated and ignored on current iOS. Existing trusted `threadIdentifier` is the supported grouping surface, so the prior summary-metadata expansion was removed.
- The relay deliberately permits an identity-free visible fallback when payload size requires omitting `message_id`. It cannot safely provide an unread total and remains unchanged.

## 2026-08-04 TDD Review

The incoming plan's verdict was `plan-fixes-required`. Three independent source-backed reviews found that its declared `ready` state could false-green production.

| Finding | Severity | Correction applied |
|---|---:|---|
| A pre-handler row absent from delivered inventory could be pruned, then delivered later as an orphan card | blocker | Persist `prepared`/`committed`, `observedDelivered`, and `retired` state. Only an observed/selected row confirmed absent may be pruned; exact foreground suppression removes its custody and advances the generation fence. |
| Existing dedupe claims occurred before recovery custody, leaving a crash gap | blocker | The production-used handoff orchestrator atomically decides uniqueness and commits custody before invoking the real content handler. |
| Blank sanitizer output was treated as guaranteed non-delivery without Apple's filtering entitlement | blocker | Keep the privacy sanitizer, remove every non-visibility claim, and retain custody for parity-authorized duplicates that Apple may still deliver. Filtering entitlement work is out of scope. |
| Identity-free fallback was promised individual-delete exactness it cannot prove | high | Limit those rows to conversation-wide, zero-eligible, policy, or account retirement. |
| Lifecycle helper tests did not cover the direct/group production mutation owners | high | Wire the existing notification-service settlement boundary and test the unallocated-cancel path, direct owner, group signal, and account clear. |
| Unsupported future schema was conflated with corruption | high | Preserve unsupported bytes untouched and make no badge/custody claim; only Runner may quarantine corrupt supported-state bytes and rebuild from canonical truth. |
| Cold recovery reused runtime-ready ingress truth and initially covered only Firebase's initial-open path | high | Capture an opaque per-flow boundary, scan staging immediately and before settlement, atomically capture/clear/arm the native APNs open, await strict native routing, and consult Firebase only when native is empty or fails before exact drains. |
| Separate native initial-open consumption and warm-forward arming admitted a tap between the two calls | high | Replace the production sequence with one main-thread native operation that captures the pending payload, clears its slot, arms warm forwarding, and returns the captured payload atomically; do not eagerly arm the production coordinator path. |
| Node-start failure skipped cold-open custody and could strand or overwrite the launch tap | high | Open the same opaque recovery scope on the failed-node path, perform the initial-open handoff, skip network drains, and settle the same handle incomplete. |
| Clearing the native slot before strict Dart routing could lose a valid transferred payload on a retryable route failure | high | Keep a valid transferred payload Dart-owned until strict routing succeeds; retry it without consuming native a second time. Full crash-after-transfer acknowledgment is a separate durability protocol and is intentionally out of scope. |
| A post-watermark NSE event already present in the SQL snapshot was counted once as canonical and again as pending | high | A complete commit absorbs any pending hash present in that canonical identity set regardless of sequence, while preserving post-watermark hashes absent from SQL and their request custody. |
| A young unreadable final staging file was retained on disk but reported as an empty/complete ingest | medium | Carry retained-unreadable final-file count through the staging read result so neither cold scan can claim canonical completeness until it parses or ages out. |
| Badge proof omitted `UNNotificationSettings.badgeSetting` | high | Require `badgeSetting == enabled` in physical preflight; disabled is a permission/environment blocker. |
| Two same-OS iPhones and seven standalone scenarios duplicated one OS boundary | medium | Use one target-bound, multi-phase physical campaign on one discovered iPhone. A second same-band phone is optional confidence only. |
| Cross-language codec, install/device/transport bindings, deprecated summary metadata, and a new seven-scenario producer stack added no required proof | medium | Keep state native-owned; fence by account/generation; reuse trusted thread grouping and the existing APNs/NSE rig. |

Post-implementation review verdict: coherent and sufficient, with no remaining blocker/high/medium production-correctness finding. The design keeps one native state owner, one Dart reconciliation coordinator, and one existing physical capability rather than adding a cross-language codec, provider fork, or background scheduler. Physical closure remains evidence-gated because owner-private APNs/signing/relay inputs are not present in the current shell.

## Graph Grounding

- Compact review query: `python3 graphify-arch/tdd_context.py query "Plan 333 counterexample: exact iOS notification badge and delivered-card recovery seams in NotificationService.swift NotificationPreviewResolver.swift AppDelegate.swift application_root.dart; identify existing canonical unread selectors, lifecycle callers, native bridge and tests" --profile review --budget 800`
- Post-refresh graph fingerprint: `2bcd04d868b7429e`; confidence is anchored and freshness is current.
- Anchors: `NotificationPreviewResolver`, `NotificationService` expiry/handoff, and `_setupIosApnsNotificationOpenBridge`.
- Source verification covered the extension, Runner delegate/channel setup, direct/group canonical snapshots and projectors, production bootstrap, relay APNs builders, Sims target binding, installed iOS SDK headers, and current Xcode target membership.

## Minimal Design Contract

### 1. Native-owned recovery state

One Swift-owned app-group document and stable lock inode are shared by Runner and the NSE. Dart never decodes, hashes, or writes this file.

The bounded v1 state contains only:

- schema version, revision/sequence, active account hash, and account generation;
- canonical badge baseline and pending ordinary-event hashes; and
- request-ID-keyed rows with account/conversation/event domain-separated hashes, ordinary/reaction kind, sequence, `prepared`/`committed`, observed-delivered, and retired state.

It never contains plaintext, title/body, usernames, group names, tokens, keys, provider credentials, device IDs, or transport IDs. A new event is committed with the exact Apple request identifier before the content handler. Account and generation are revalidated in the same transaction.

Atomic replacement creates and protects the temporary file before rename, excludes it from backup, and uses a separate stable flock file. The implementation caps request custody at 512 rows, canonical ordinary hashes at 4,096, and recent event tombstones at 256. Capacity may reject a new request claim or complete canonical commit, but never evicts an owned request row. Rejection is typed and non-partial.

An unsupported future schema is left byte-for-byte untouched and disables state/badge claims. A corrupt v1 file is left untouched by the NSE; Runner may quarantine it, publish canonical badge truth, and begin a fresh v1 file. Pre-333 binaries ignore the sidecar. After downgrade and re-upgrade, the new Runner repairs it from canonical state; rollback never rewrites an unknown version.

### 2. Production handoff and delivery disposition

`NotificationPreviewResult` gains a trusted recovery identity derived only from the parity-authorized projection: account, lane, conversation, optional canonical event, and kind. Existing `threadIdentifier` grouping remains unchanged.

A shared handoff orchestrator used by the real `NotificationService.finish` performs, in order:

1. the atomic uniqueness/custody transaction;
2. preview application or the existing sanitized/passive duplicate policy;
3. unconditional `content.badge = nil`; and
4. the real content-handler call.

Unique ordinary events add one pending badge identity. Reactions, identity-free ordinary events, and duplicates own their request ID but add no badge delta. Rejected, muted, malformed, parity-mismatched, and expiry-before-resolution results have no trusted identity and create no recovery state.

Rows begin `prepared` and become `committed` only after the Apple content-handler call returns. Runner marks a row `observedDelivered` only when the exact identifier appears in delivered inventory. `AppDelegate.willPresent` reports the exact request when the final presentation options are empty; native state then removes only that custody row, preserves its pending unread event, and advances the generation so an older canonical read cannot absorb it. A retired but never-observed row remains retryable; its absence is not proof of delivery or dismissal.

### 3. Badge projection

The absolute badge is:

`canonical eligible direct + group unread count + unresolved unique pending ordinary events`

The canonical selector uses current durable notification policy:

- direct: incoming, unread, non-hidden, non-deleted, nonterminal private media, active nonblocked/nonarchived contact;
- group: incoming, unread, non-cutoff, active private media, active nonmuted/nonarchived/nondissolved/nonremoved group.

Reactions and duplicates are count-neutral. A complete canonical pass resolves pending work at or below its watermark and also removes any post-watermark pending event already proven present in that same canonical SQL snapshot. A post-watermark event absent from the snapshot remains pending. This prevents both loss and canonical-plus-pending double counting, including when the exact value is zero. An incomplete staged/drain pass preserves pending work and cannot publish a guessed lower value. A concurrent NSE commit above the watermark survives and forces the latest absolute value to be reapplied.

On iOS 16+, Runner and NSE share one absolute `setBadgeCount` writer. Its stable writer lock is separate from the short state lock, is acquired off-main, and is held through the completion callback. The content handler is never held waiting for this writer. After completion, a sequence change schedules a latest-state reapply.

On iOS 13-15, the NSE performs no badge write and still hands off `badge=nil`; Runner uses `applicationIconBadgeNumber` on the main thread at activation/reconciliation. Unavailable old-iOS hardware is policy N/A, with the branch covered by native tests.

### 4. Two-phase exact reconciliation

Dart calls the native channel `mknoon/ios_notification_recovery`:

- `beginReconciliation({accountPeerId}) -> {token, watermark}` before loading SQLCipher state;
- `commitReconciliation({token, watermark, accountPeerId, canonicalStateComplete, canonicalBadgeCount, identities})`;
- `retireConversation({accountPeerId, lane, conversationId})`; and
- `clearAccount()`.

There is no remove-all method.

At commit, native code reads delivered inventory, marks exact present rows observed, and prunes a previously observed row already absent from that initial inventory as user-dismissed. It then selects stale rows no newer than the watermark. It may select:

- event-bound ordinary rows whose trusted event is absent from complete canonical state;
- identity-free rows only when their whole conversation has zero eligible events;
- rows explicitly retired by a conversation clear; and
- old-account rows after account cutover.

It exact-removes only selected identifiers that are present now or were previously observed. It then reads inventory again and prunes only selected, observed identifiers confirmed absent. A later request, unrelated request, and unobserved pre-handoff request survive. A foreground-suppressed row is removed from custody without an OS removal attempt.

### 5. Lifecycle and mutation owners

One coalescing Dart coordinator owns begin -> canonical load -> commit. Mutation scopes capture the native token before the canonical mutation; overlapping scopes share that boundary, and the last close commits it. Concurrent passive triggers cause one final reread instead of parallel SQL/native races. Incompleteness is sticky until a globally exhaustive successful pass, while account, clear, and mutation epochs fence stale work.

- Runtime-ready begins before staged ingest but deliberately closes that staging-only pass incomplete; listener readiness alone does not prove cold direct/group exhaustion.
- A successful cold start begins a globally exhaustive scope after node startup/ownership polling, performs the first staged scan, atomically captures/clears the native APNs launch payload while arming warm forwarding, awaits strict native routing, consults Firebase only when native is empty or failed, runs the full direct/group or dropped-owner drains, performs the final staged scan, and settles that same opaque handle. A valid payload transferred out of native remains Dart-owned until strict routing succeeds. Native empty and routed results are terminal/exactly-once; a route failure keeps the pass incomplete and retryable. Overlapping restarted routers cannot cross-settle each other's scopes.
- A failed node start opens the same initial-open recovery boundary, performs the atomic native handoff and conditional Firebase fallback, skips all network drains, and settles that same handle with `canonicalStateComplete=false` before continuing existing group-exit cleanup.
- Resume awaits staged ingest, then the existing direct/group drains and projection retries, then recovery.
- Foreground push recovery runs after the selected direct or group drain/result, never both lanes by default.
- Existing local notification show/replace/cancel settlement triggers canonical reconciliation in `finally`; even an unallocated local-ID cancel schedules reconciliation, but it does not guess a remote Apple request identifier or blindly retire a conversation.
- Conversation read/delete/policy owners remain routed through their current direct/group projectors and notification service rather than gaining parallel schedulers.
- Account clear/cutover uses the exact native state path. Existing `cancelAll` may continue to clear local Flutter cards, but it is not evidence that remote APNs rows were reconciled.
- The aggregate and coordinator are iOS-only and have no Android consumer, dropped-push marker, headless worker, BGTask, or WorkManager path.

## Test Contract

| Case | Required behavior | Causal test / proof | Mutation discriminator |
|---|---|---|---|
| TC-333-01 | Real handoff commits atomic uniqueness + exact custody before handler; unique ordinary alone adds pending; content badge is nil | `IosNotificationRecoveryTests` production-used handoff tests | Move preparation after handler, restore content badge, split dedupe/state, or count reaction/duplicate -> red |
| TC-333-02 | Prepared absence is retained; foreground suppression clears exact custody; observed stale A is exact-removed while newer B and unrelated C survive | `IosNotificationRecoveryTests` inventory/barrier cases | Prune any absent row, remove by thread/all, omit watermark, or prune before readback -> red |
| TC-333-03 | v1 state is crash-safe, concurrent, account/generation fenced, capacity-safe, and version-reversible | Native temp-directory tests for reopen/concurrency/corruption/unsupported/downgrade/account cutover | Rewrite unknown bytes, evict owned row, accept old account, or publish partial state -> red |
| TC-333-04 | Canonical direct+group selector and coalescing two-phase coordinator produce an exact absolute badge, de-duplicate post-watermark canonical events, and preserve unresolved pending on incomplete work | canonical DB helper, Dart bridge/coordinator, and native post-watermark tests | Drop a policy filter, load DB before begin, double-count canonical B, clear unresolved B on incomplete, count reaction, or skip final rerun -> red |
| TC-333-05 | iOS 16+ completion ordering and final reapply prevent regression; iOS 13-15 is Runner-only; every NSE handoff is badge-free | Injected native writer/XCTest | Serialize only submission, call UIKit in extension, wait on handler, or omit latest-state reapply -> red |
| TC-333-06 | Runtime-ready/resume/foreground/cold-open and real direct/group/account mutation owners invoke recovery in the required order; the atomic initial-open handoff also runs in an incomplete failed-node scope | Focused application-root, StartupRouter, native-open bridge, AppDelegate source-order, and `FlutterNotificationService` callback tests, including unallocated cancellation | Restore `unawaited` staging, split capture/clear/arm, consume native cold open before begin, lose a transferred payload on route failure, drain on failed node, recover before lane drain, omit group/direct owner, or use blanket clear as remote proof -> red |
| TC-333-07 | Existing parity, staging, open routing, relay payload, reaction collapse, local notification IDs, and Android behavior remain unchanged | Existing Swift/Dart/Go preservation suites | Trust provider badge/ID, add ordinary collapse, open SQLCipher in NSE, or wire aggregate to Android -> sentinel red |
| TC-333-08 | The existing target-bound `notifications.ios_payload_fast_path` campaign proves real APNs/NSE unique custody with `badge=nil`, final Runner badge convergence, and exact A retirement while an app-local unrelated C survives | Existing signed production APNs/NSE/XCUITest rig, minimally extended in place | Simulator-only injection, disabled badges, a new duplicate capability, reused target manifest, manual action, child build, or dirty cleanup -> proof fails |

### Counterexamples that must stay named

- Reconcile after ledger commit but before content handoff: A is absent and must remain owned; if it later appears it is removed on the next pass.
- Claim post-watermark B and land it in SQL before commit: canonical B contributes once, its request custody survives, and its pending hash no longer adds a second badge. If B is absent from SQL, its pending contribution survives.
- A native APNs cold tap is captured/cleared while warm forwarding is armed in one AppDelegate operation after the cold boundary. Strict native routing finishes first; Firebase `getInitialMessage` is only a fallback for native empty/failure, and whichever path runs finishes before exact drains/settlement.
- If node startup fails, that same initial-open handoff still runs inside an explicitly incomplete scope, no direct/group network drain runs, and the identical opaque handle settles `false`.
- If native transfers a valid payload but strict Dart routing fails, the bridge retains that payload in Dart and retries it without a second native consume.
- A young malformed final staging file is retained for retry and therefore makes both staging scans incomplete; an empty parsed-entry list alone is not canonical exhaustion.
- Foreground delivery: `willPresent` produces no card and must explicitly clear A's prepared custody.
- User-dismissed card: A was previously observed and is now absent, so its row may be pruned without a removal call.
- Individual deletion of identity-free A while another unread B remains: A stays owned; no unsafe guess maps the deletion to A.
- Old Runner/new NSE, new Runner/old NSE, and upgrade -> downgrade -> re-upgrade: unknown versions remain untouched and canonical Runner repair is deterministic.
- Account switch concurrent with an old-account NSE finish: the old commit is rejected or retained only as retired cleanup; it cannot affect the new account badge.

## Scope Guard

Do not:

- add provider-authored `aps.badge`, relay unread totals, or ordinary-message collapse IDs;
- persist plaintext, names, notification copy, tokens, keys, device IDs, or transport IDs;
- parse the native state in Dart or create a Swift/Dart golden codec;
- use `removeAllDeliveredNotifications`, blanket `cancelAll`, thread-only removal, or absence-only pruning as remote-card control;
- open SQLCipher, start Flutter, or perform network I/O in the NSE;
- claim Apple-level suppression without the filtering entitlement;
- add deprecated summary metadata, Android recovery machinery, or a new seven-scenario provider stack; or
- require a currently unavailable OS/hardware band for closure.

Out of scope: Apple filtering-entitlement acquisition, fully offline group-tap replay from the reduced APNs projection, a dead-process delivery SLA, and Android badge/recovery behavior.

## Gate Cadence And Acceptance

Per-plan closure runs focused causal tests, exact preservation sentinels, `1to1`, `groups`, `runtime-roots`, and the justified affected `core-host-all` / `feature-host-all` families. It does not run full `host-all`; that remains a wave/final-rollout gate.

```bash
# Focused Dart causal tests and adjacent preservation.
flutter test --concurrency=1 \
  test/core/database/helpers/canonical_notification_badge_state_db_helpers_test.dart \
  test/core/notifications/ios_notification_recovery_bridge_test.dart \
  test/core/notifications/ios_notification_recovery_wiring_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/features/push/application/push_envelope_staging_test.dart \
  test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
  test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart \
  test/core/lifecycle/handle_app_resumed_phase2_continuation_wiring_test.dart \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  test/features/account_migration/application/account_migration_runtime_network_gate_test.dart \
  test/core/notifications/ios_apns_notification_open_bridge_test.dart \
  test/core/notifications/recent_remote_gate_ios_wiring_test.dart \
  test/core/notifications/local_notification_exact_cancellation_wiring_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart

# Exact source-order and relocation preservation sentinels refreshed for the
# implemented production seams.
flutter test --concurrency=1 \
  test/core/notifications/notification_service_completion_pin_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart

# Pin an actually available simulator before execution.
xcrun simctl list devices available
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,id=DBE8C32E-9F19-4593-860A-B41113791D79' \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:RunnerTests/IosNotificationRecoveryTests \
  -only-testing:RunnerTests/NotificationPreviewResolverTests \
  -only-testing:RunnerTests/ForegroundPushForwardPolicyTests \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests

# Existing physical-harness contracts extended in place.
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test \
  scripts.test.ios_notification_provider_adapter_test \
  scripts.test.ios_notification_relay_fixture_driver_test

# Relay payload preservation; no Plan-333 producer fork.
GOTOOLCHAIN=go1.25.0 go -C go-relay-server test ./... \
  -run 'Test(WakePush_VisibleAlert_NotSilentOnly|BuildReactionPush_SharedBoundedIdentityFixture|RelayNotificationClosure_GroupReactionApnsCollapseIdRemainsPerGroup)$' \
  -count=1
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./cmd/iospayloadproducer -count=1

# Curated/family gates (no per-plan full host-all).
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh core-host-all --dart-only --batch-flutter --concurrency 1 --reporter failures-only
./scripts/run_test_gates.sh feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# Rediscover and pin one available physical iPhone. The prepare/run wrapper must
# bind that same UDID into staging manifest, provider request, signing inputs,
# app/XCTest bundle, and receipt. Badge permission must be enabled.
flutter devices --machine
SIMS_IOS_PHYSICAL_DEVICE_ID=<discovered-iphone-udid> \
  dart tool/sims/sims.dart major --only notifications.ios_payload_fast_path

./scripts/check_flutter_analyze_strict.sh
git diff --check
bash -n scripts/run_test_gates.sh
plutil -lint ios/Runner/Info.plist ios/NotificationService/Info.plist
jq empty tool/sims/critical_features.json
./graphify-arch/refresh_arch_graph.sh --incremental
```

The core family is intentionally serial: four-way execution produced alternating unrelated timing reds in two P2P tests, and both exact files immediately passed alone. Serial execution then exposed and closed the actual Plan-333 source/path sentinels. The feature family remains four-way.

## Device Proof Profile

- Current available matrix (2026-08-04) includes USB iPhones, a booted iOS simulator, a USB Android phone, and an Android emulator. Only one discovered physical iPhone is required because this claim is an APNs/NSE/Notification Center boundary; a second same-OS phone adds no distinct boundary.
- Preflight must prove: exact target binding, signed production app/NSE/XCTest bundle, real APNs provider and relay inputs, notification authorization, alerts enabled, badges enabled, disposable identity, empty recovery state, zero manual actions, and zero child builds.
- The existing `notifications.ios_payload_fast_path` capability remains one campaign with two serial, fresh-install APNs legs and one signed product set: (1) its original automated airplane-mode tap/staged-visibility proof; (2) a recovery leg that proves the provider payload omits badge, delivered A has `content.badge == nil`, the absolute badge reaches one, canonical empty-state retirement removes exact A, an app-local unrelated sentinel C survives, the badge reaches zero, and cleanup is automatic.
- Host/native tests own deterministic NSE/Runner writer overlap, later-watermark B, reaction/duplicate neutrality, mixed versions, identity-free deletion, legacy iOS fallback, and account races. Those causal cases are stronger and cheaper than adding provider barriers or a generalized multi-payload physical stack.
- CoreSimulator accepts explicit `.complete` protection writes but returns `nil` for `FileManager` protection-key reads on its host-backed filesystem. The XCTest therefore accepts only `nil`/`.complete` on simulator while keeping mode `0600` and all behavior strict; its physical-device branch still requires exactly `.complete`. A signed physical run remains the security boundary. Adding the app-wide default-data-protection entitlement is unrelated scope expansion because this handoff explicitly protects every directory/file and post-rename result.
- Missing APNs/signing/relay credentials are an `environment_blocker`, not a PASS. A target absent at execution is `N/A (target unavailable by project policy)` and is not replaced by an unavailable model/version requirement.

## Done Criteria

- [x] Atomic production handoff, disposition race, state/version/account, exact-removal, badge-writer, canonical-selector, coalescing, and production-owner tests pass.
- [x] Later/unrelated/unobserved rows survive; only observed exact stale identifiers are pruned after readback.
- [x] Badge count is exact for direct/group canonical policy, reactions/duplicates are neutral, incomplete convergence preserves pending, and zero is explicit.
- [x] Runtime-ready, resume, foreground, read/delete/policy, failed-node cold-open, and account paths invoke the same iOS-only coordinator without Android ownership.
- [x] Existing NSE parity/sanitizer, direct staging, recent-remote, tap routing, relay shape, local notification, and Android sentinels remain green.
- [ ] One target-bound physical campaign passes when owner-private inputs are available; until then status remains evidence-gated with the blocker recorded.
- [x] Focused/curated/family gates, strict analysis, diff hygiene, and incremental Graphify refresh pass.

## Execution Progress

| Time | Phase | Evidence | Decision / next |
|---|---|---|---|
| 2026-08-04 | review | Graphify review context, three independent source audits, live device/credential preflight | Incoming plan was not ready; corrections above remove unsafe absence pruning and over-engineered scope |
| 2026-08-04 | contract | Native-only state, production handoff transaction, two-phase Dart channel, one physical campaign | Host/native implementation authorized; preserve unrelated Plan 335 worktree changes |
| 2026-08-04 | RED/GREEN | Focused Plan-333/adjacent Dart suite 212/212; final cold-open subset 54/54; source/path sentinels green | Atomic handoff, exact badge/card reconciliation, staging completeness, lifecycle ownership, failed-node release, and retained Dart payload implemented |
| 2026-08-04 | native | Pinned iPhone 16e iOS 26.5 simulator: 94/94 across recovery, preview, foreground policy, and protected bootstrap handoff | Simulator/native closure green; physical protection assertion remains strict and evidence-gated |
| 2026-08-04 | harness | Python 24/24; focused relay and iOS payload-producer Go tests pass; manifest/provider/bootstrap contracts pass | Existing target-bound capability extended in place; no new producer/capability stack |
| 2026-08-04 | curated | `1to1` 2778/2778; `groups` 4050/4050 plus Go tails; runtime-root inventory green; completeness 1418/1418 | Affected curated and inventory gates green; no per-plan full `host-all` |
| 2026-08-04 | family/static | `core-host-all` 3131/3131 across 395 paths; `feature-host-all` 8800 passed + 1 intentional skip across 835 paths; strict analyzer and format/diff/plist/JSON/shell hygiene green | Host/simulator implementation closure complete |
| 2026-08-04 | device | Live targets available, but owner-private APNs/signing/provider/relay inputs are unset | Run the existing two-leg campaign on one pinned physical iPhone when those inputs are available; status remains physical evidence-gated |
