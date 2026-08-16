# 374 - GAP-N08 Production Headless Canonical Recovery Completion

Status: **POST_EXECUTION_AUDIT_CLOSED / N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE / N08 SLICE 1 OF 2 / RECOVERY-WORK CODE-READY / FIXED-WAKE ADMISSION DEFAULT-OFF / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec inputs: GAP-N08, WP-05 and sequencing guidance in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; the unfinished safety-gated tail of Plan 331
Classification: production headless composition and crash-safety completion
Closure tier: host, focused Android native, and availability-bounded Android mechanism proof

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-16 | Planner using `$tdd-plan` | GAP-N08; Plan 331; Plans 371-373; canonical runtime/entrypoint/lease; Android worker/store/scheduler/runtime host; bootstrap direct/group drains | The seven remaining Plan-331 safety seams share one acquisition-to-ACK transaction. Splitting them would leave an unusable graph or activate a worker with incomplete ownership. | Keep one Plan-374 headless-recovery slice; Plan 375 alone owns fixed FCM ingress and presentation. |
| 2026-08-16 | Graph/source grounding | `runUnavailableHeadlessCanonicalRecovery`, `CanonicalRecoveryRuntime`, production bootstrap recovery composition and current tests | Graphify was anchored at the dormant entrypoint/runtime. Source confirms the worker and state machine exist but no UI-neutral production `CanonicalRecoverySession` exists. | Reuse the landed worker/store/scheduler/runtime; add only the missing production graph and adapters. |
| 2026-08-16 | Dependency/gate reviewers | Plan-372 receipt contract; Plan-331A/H0 proofs; curated arrays; Android device policy | Plan 372 is unfinished and no checksum receipt exists. Focused host/native plus one narrow no-Activity Android proof are sufficient; the old credential-dependent 6x2 Plan-331 campaign is not. | Keep execution blocked; freeze proportional gates and defer live FCM/relay/Doze/OEM evidence to WP-07. |
| 2026-08-16 | Independent reviewers using `$tdd-review` | Full draft; identity/DB opener; all typed inbox handlers; Plan-372 state; Dart/native teardown; literal gates/device commands | First review was NOT READY: pre-DB identity claims were impossible, late admitted callbacks could escape settlement, production-store proof was vacuous, and device/gate commands were not causal or portable. | Correct the existing plan in place; do not add another N08 plan or durable owner. |
| 2026-08-16 | Planner/arbiter | Revised authority order, post-fence settlement, exact runner/readiness/rollback, per-selector gates and one-target proof | Three-lens recheck passes the behavioral and executable boundaries. One reviewer requested both available Android classes, but no two-peer/platform-parity claim exists; project cadence favors one pinned target, with the second optional. | Mark contract-ready/prerequisite-blocked and hand the frozen boundary to Plan 375. |
| 2026-08-16 | Independent dependency/contract audit | Committed Plan-372 receipt and public Dart API; Plan-371/370 sentinels; current Graphify/source anchors; test-owner commands; gate inventories; closure outputs | Plan 372 is now committed at `650f8cbe68dfed52a5c66fc53da35915bca53f02`; receipt SHA-256 `9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62` validates. The draft still needed exact API/identity pins, a baseline registration, coherent TC-374-03/04 ownership, honest RED/mutation claims, both gate-runner syntax checks and explicit closure outputs. | Apply those bounded corrections in this file. Keep the plan contract-ready, not execution-ready; execution begins only from a later clean committed planning baseline whose ancestry contains the receipt commit. |

## Problem And Evidence

- Android already persists a deleted-message generation, schedules unique
  expedited/periodic WorkManager work, starts a minimal headless Flutter engine,
  and arbitrates the single native/Go/SQLCipher runtime owner.
- The AOT callback in `lib/main.dart` still calls
  `runUnavailableHeadlessCanonicalRecovery`. That implementation returns
  `retry/headless_composition_unavailable` without opening the identity DB,
  draining either inbox, settling notification state, or acknowledging the
  exact generation.
- `CanonicalRecoveryRuntime` already owns the correct high-level order:
  validate binding/generation, acquire one session, drain direct then group to
  a fixed point, settle durable notification projection, quiesce, close,
  release, resnapshot, and compare-ACK. The missing work is production
  composition, not a second recovery algorithm.
- `ProductionApplicationBootstrap` contains the real direct/group repositories,
  inbox owners and notification settlement seams, but it is a UI/live-runtime
  composition root. Starting it from WorkManager would install UI/Firebase
  listeners and competing owners.
- Plan 331 therefore remains explicitly safety-gated on seven connected seams:
  a UI-neutral graph factory; exact invocation validation; passive role-correct
  identity/migration loading; complete direct replay; complete group replay;
  typed Plan-372 ledger/effect convergence; and ordered teardown.
- Plan-331A/H0 already proves the sole native runtime/engine owner. DB v107 and
  later direct/group custody foundations have landed. Reopening the historical
  health, history, localization or broad real-FCM campaign would duplicate
  completed work without closing the missing production call path.

## Dependency Contract

Plan 372 has executed and its checksum-bound receipt is committed at
`650f8cbe68dfed52a5c66fc53da35915bca53f02` (commit tree
`9d4b46d37a205ea7da1a858dcde8c6f365b29917`; receipt SHA-256
`9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62`).
That receipt transitively binds Plan 371 and the earlier N01-N03 mechanism
receipts; do not replay those full preflights unless the Plan-372 receipt fails
to bind them. Plan 373 is a sibling iOS adapter, not a Plan-374 dependency.
Plan 374 remains contract-ready rather than execution-ready until these
planning bytes are committed and the exact preflight below passes from a clean
worktree.

Before the first TC-374 RED, require:

- `Test-Flight-Improv/evidence/372/README.md` and `README.md.sha256`;
- standalone marker `N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE` and
  transitive marker `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE`;
- exact Plan-372 receipt commit/tree/SHA plus its Base HEAD, Frozen tested tree,
  Dirty snapshot SHA-256 and Graphify
  fingerprint identities, with committed receipt bytes plus independently
  rehashable dirty-snapshot and Graphify-fingerprint artifacts;
- DB current version still `116`;
- exactly one Dart production store for `local_notification_ledger_v1.json`
  using the accepted `NotificationConversationIds/.coordination.lock`, plus
  `LocalNotificationRecordV1` and the exact public registry methods
  `runFinalEffect`, `settleSqlReadyEffect`,
  `listSqlReadyEffectTerminals`, and `upgradeRelayCustodyToSqlReady`, and both
  `INBOX_RECONCILER` and `ANDROID_PUSH_SERVICE` owner values;
- accepted `SQL_READY` acquisition/settlement and phase-preserving
  `RELAY_VERIFIED_UNACKED` upgrade semantics;
- Plan-371 freshness reader/fixture and Plan-370 paired opaque/outcome admission
  still default `false`.

```bash
(
  set -euo pipefail
  receipt='Test-Flight-Improv/evidence/372/README.md'
  checksum='Test-Flight-Improv/evidence/372/README.md.sha256'
  expected_receipt_commit='650f8cbe68dfed52a5c66fc53da35915bca53f02'
  expected_receipt_tree='9d4b46d37a205ea7da1a858dcde8c6f365b29917'
  expected_receipt_sha='9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62'
  expected_base='434d31d16efc506b3a57b1cdec4ebb2f15fcf66a'
  expected_frozen='71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2'
  expected_dirty='45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed'
  expected_graph='8c428eb87b960e70'
  test -f "$receipt"
  test -f "$checksum"
  (cd Test-Flight-Improv/evidence/372 && shasum -a 256 -c README.md.sha256)
  test "$(shasum -a 256 "$receipt" | awk '{print $1}')" = "$expected_receipt_sha"
  test "$(rg -Fxc 'N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE' "$receipt")" -eq 1
  test "$(rg -Fxc 'N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE' "$receipt")" -eq 1

  base="$(awk -F'`' '/\| (Base( and unchanged)? HEAD|Base HEAD) \|/ {print $2; exit}' "$receipt")"
  frozen="$(awk -F'`' '/\| Frozen tested tree \|/ {print $2; exit}' "$receipt")"
  dirty="$(awk -F'`' '/\| (Porcelain-v2 workspace snapshot|Dirty snapshot) SHA-256 \|/ {print $2; exit}' "$receipt")"
  graph="$(awk -F'`' '/\| (Graphify )?[Ff]ingerprint \|/ {print $2; exit}' "$receipt")"
  [[ "$base" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph" =~ ^[0-9a-f]{16}$ ]]
  test "$base" = "$expected_base"
  test "$frozen" = "$expected_frozen"
  test "$dirty" = "$expected_dirty"
  test "$graph" = "$expected_graph"
  git cat-file -e "${base}^{commit}"
  git cat-file -e "${frozen}^{tree}"

  receipt_commit="$(git log -n 1 --format=%H -- "$receipt")"
  test "$receipt_commit" = "$expected_receipt_commit"
  test "$(git rev-parse "${receipt_commit}^{tree}")" = "$expected_receipt_tree"
  git merge-base --is-ancestor "$base" "$receipt_commit"
  cmp -s <(git show "${receipt_commit}:${receipt}") "$receipt"
  cmp -s <(git show "${receipt_commit}:${checksum}") "$checksum"
  git merge-base --is-ancestor "$receipt_commit" HEAD

  dirty_archive='Test-Flight-Improv/evidence/372/workspace-porcelain-v2.txt.gz'
  graph_file='Test-Flight-Improv/evidence/372/graphify-fingerprint.txt'
  test -f "$dirty_archive"
  test -f "$graph_file"
  cmp -s <(git show "${receipt_commit}:${dirty_archive}") "$dirty_archive"
  cmp -s <(git show "${receipt_commit}:${graph_file}") "$graph_file"
  test "$(gzip -dc "$dirty_archive" | shasum -a 256 | awk '{print $1}')" = "$dirty"
  test "$(tr -d '[:space:]' <"$graph_file")" = "$graph"

  rg -Fqx 'const int currentIdentityDatabaseVersion = 116;' \
    lib/core/database/app_database_version.dart

  # Test fixtures and planning prose cannot satisfy production authority. Pin
  # Plan 372's accepted concrete source and public registry transition surface.
  ledger_model='lib/core/notifications/local_notification_ledger.dart'
  ledger_store='lib/core/notifications/local_notification_ledger_store.dart'
  registry='lib/core/notifications/durable_conversation_notification_id_registry.dart'
  test "$(rg -l 'local_notification_ledger_v1\.json' lib | wc -l | tr -d ' ')" -eq 1
  rg -Fqx "  static const String fileName = 'local_notification_ledger_v1.json';" "$ledger_store"
  rg -Fqx '/// shared lock is exactly `NotificationConversationIds/.coordination.lock`.' "$ledger_store"
  rg -Fqx 'final class LocalNotificationRecordV1 {' "$ledger_model"
  rg -Fqx "  relayVerifiedUnacked('RELAY_VERIFIED_UNACKED');" "$ledger_model"
  rg -Fqx "  androidPushService('ANDROID_PUSH_SERVICE')," "$ledger_model"
  rg -Fqx "  inboxReconciler('INBOX_RECONCILER');" "$ledger_model"
  test "$(rg -Fxc '  Future<DurableLocalNotificationEffectResult> runFinalEffect({' "$registry")" -eq 1
  test "$(rg -Fxc '  Future<LocalNotificationRecordV1?> settleSqlReadyEffect({' "$registry")" -eq 1
  test "$(rg -Fxc '  Future<List<LocalNotificationRecordV1>> listSqlReadyEffectTerminals({' "$registry")" -eq 1
  test "$(rg -Fxc '  Future<LocalNotificationRecordV1?> upgradeRelayCustodyToSqlReady({' "$registry")" -eq 1

  flutter test --no-pub \
    test/core/notifications/local_notification_ledger_test.dart \
    --plain-name 'TC-372-01 v1 codec and state machine accept only legal monotonic transitions'
  flutter test --no-pub --concurrency=1 \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    --plain-name 'TC-372-05 one claim owner and deterministic publishing recovery across isolate arrival orders'
  flutter test --no-pub --concurrency=1 \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    --plain-name 'TC-372-06 effect-terminal replay settles direct and group custody once and emits only approved enabled outcome'

  flutter test --no-pub \
    test/core/notifications/app_visibility_snapshot_test.dart \
    --plain-name 'TC-371-01 v1 codec and fresh exact predicate fail toward notification'

  flutter test --no-pub \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    --plain-name 'TC-370-05 opaque outcome uses strict all-relay completion'
  flutter test --no-pub \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    --plain-name 'TC-370-07 production composes one default-off outcome admission and one shared drain callback'
  admission_block="$(
    sed -n \
      '/^const bool kWakeOutcomeCoordinatorAdmissionEnabled = bool.fromEnvironment(/,/^);$/p' \
      lib/core/bridge/p2p_bridge_client.dart
  )"
  test "$(printf '%s\n' "$admission_block" | rg -Fxc 'const bool kWakeOutcomeCoordinatorAdmissionEnabled = bool.fromEnvironment(')" -eq 1
  test "$(printf '%s\n' "$admission_block" | rg -Fxc "  'MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR',")" -eq 1
  test "$(printf '%s\n' "$admission_block" | rg -Fxc '  defaultValue: false,')" -eq 1

  # Execution starts from a clean committed product tree. The historical
  # Plan-372 dirty snapshot is provenance, not permission for current drift.
  test -z "$(git status --porcelain=v1)"
)
```

Plan 372's accepted receipt records the production ledger source and the four
public API names used by the checks above. Their current declarations are in
`durable_conversation_notification_id_registry.dart`; the receipt's
implementation commit and tested tree remain immutable even if a later sibling
plan changes line numbers. If any literal source/API pin changes, independently
review and re-pin the replacement rather than weakening the check to a fixture
or planning-document search. After this preflight, require a clean committed
product baseline and a fresh review-profile Graphify query. Receipt
tree/dirty/graph identities are provenance for Plan 372, not permission to
execute against later overlapping uncommitted product drift.

## Graph Grounding Snapshot

- Query/profile, rerun from committed Plan-372 HEAD
  `650f8cbe68dfed52a5c66fc53da35915bca53f02`:
  `python3 graphify-arch/tdd_context.py query "runUnavailableHeadlessCanonicalRecovery CanonicalRecoveryRuntime ProductionApplicationBootstrap HeadlessCanonicalRecoveryWorker DroppedPushRecoveryStore LocalNotificationRecordV1 DurableConversationNotificationIdRegistry runFinalEffect settleSqlReadyEffect listSqlReadyEffectTerminals upgradeRelayCustodyToSqlReady" --profile review --budget 800 --ensure-fresh`
- Result: `confidence=anchored`, `freshness=current`, fingerprint
  `8c428eb87b960e70`.
- Exact graph anchors: `LocalNotificationRecordV1` at
  `lib/core/notifications/local_notification_ledger.dart:127`,
  `runUnavailableHeadlessCanonicalRecovery` at
  `lib/core/notifications/headless_canonical_recovery_entrypoint.dart:212`, and
  `CanonicalRecoveryRuntime` at
  `lib/core/notifications/canonical_recovery_runtime.dart:117`.
- Exact current production-call marker:
  `lib/main.dart:30` is
  `runRecovery: runUnavailableHeadlessCanonicalRecovery,`. TC-374-07 replaces
  that one line with
  `runRecovery: runProductionHeadlessCanonicalRecovery,`, replaces
  `emergencyShutdown: cleanupUnavailableHeadlessCanonicalRecovery,` with
  `emergencyShutdown: cleanupProductionHeadlessCanonicalRecovery,`, requires
  both old markers zero times and both new markers once, and keeps both
  functions backed by the same
  `ProductionHeadlessCanonicalRecoveryRunner` instance so emergency shutdown
  cannot query or clean a fresh owner.
- Source verification added `lib/main.dart`, production bootstrap direct/group
  drain composition, `CanonicalRuntimeBindingCoordinator`, the Android worker,
  runtime host, lease, recovery store/scheduler and all exact tests below.
- Re-run the review query with `--ensure-fresh` at execution start and after the
  coherent implementation refresh. An unanchored or materially different graph
  is a stop-and-replan condition; a changed fingerprint alone is expected when
  a committed sibling plan legitimately changes the graph.

## Delivery Structure Decision

Plan 374 is the first of exactly two N08 plans:

1. Plan 374 makes the already-landed recovery worker safe and useful for its
   incumbent deleted-batch and periodic reasons.
2. Plan 375 adds strict fixed-FCM ingress, its generic fallback lease and paired
   Android consumer readiness by calling this frozen recovery boundary.

These are different rollback switches: `recoveryWorkEnabled` can safely enable
incumbent recovery without advertising opaque fixed wakes; the paired
`opaque_wake_v1`/`wake_outcome_v1` admission remains false until Plan 375 and
WP-07. Combining both would recreate Plan 331's oversized activation slice.
Splitting Plan 374 further would leave a dead graph factory, partial lane drain,
or unsafe worker. Do not split by direct/group, primary/linked, WorkManager
reason, message/reaction, or host/device proof.

## Authority And Lifecycle Contract

### One UI-neutral production graph

Add one production factory, expected near
`lib/app/bootstrap/production_headless_canonical_recovery.dart`, that returns a
`CanonicalRecoverySession` using the same repositories, crypto, inbox parsers,
ledger/effect owner and P2P implementation as the foreground composition.

The factory must:

- accept only the parsed native invocation binding, generation and reason;
- perform the native/secure binding, marker, coarse migration and linked-role
  fail-closed checks that are possible before the database opens;
- open only an existing identity database/key through the incumbent encrypted
  opener and migration registry. Add a shared `requireExisting`-style guard:
  missing key/database must retry and must never create a key, DB or account;
- after opening, load a passive DB-row plus secure-secret snapshot. Do not call
  `IdentityRepositoryImpl.loadIdentity`, whose projections/binding writes are
  side effects. Derive and compare the exact opaque binding, then load linked
  authority with the DB account peer and select the physical credential;
- load identity and migration authority with no UI, `runApp`,
  `ApplicationRoot`, router, presence, notification-open listener, generic
  Firebase listener, retry timer, or implicit plugin registration;
- select the ordinary primary physical/logical identity or the exact active
  linked transport credential; preparing, partial, corrupt, fail-closed,
  device-drifted or cross-account linked authority returns retry before Go,
  network or notification effects. States discoverable only from SQL must close
  the DB and release the lease; they cannot promise zero DB opens;
- never fall back from a linked role to the account/primary transport key;
- acquire the incumbent native runtime lease before opening SQLCipher and use
  the existing Go runtime host rather than another singleton or engine;
- reuse or extract production composition helpers; it must not copy a second
  direct/group event state machine out of `ProductionApplicationBootstrap`.

### One acquisition-to-ACK transaction

The accepted order is:

1. parse and re-read native/secure binding plus exact durable generation;
2. perform coarse secure migration/role refusal, then acquire the existing sole
   runtime lease;
3. open the existing SQLCipher DB at v116, applying only incumbent migrations;
4. passively load the DB identity/secrets, derive/compare the binding, load
   linked authority against the DB account peer and select the exact physical
   transport; recheck migration and marker before any Go/network work;
5. start a recovery-only node core: no warm/LAN discovery, push restore,
   presence, periodic timers or unrelated live-service owners;
6. drain every direct typed row/page and every group row/page to a fixed point;
7. perform a preliminary custody/ledger settlement;
8. seal all Dart direct/group admission, await every previously admitted live,
   staged, protected and foreground/background drain future, stop the
   `GroupMessageListener`, then perform the authoritative final settlement;
9. prove total pending is zero across direct display, direct reconciliation,
   group display and group reconciliation custody and that Plan-372 has no
   unresolved current record. Only then dispose projection/listener owners;
10. quiesce Go, close SQLCipher and release the lease in that order;
11. re-read binding, marker, migration/role and linked-credential fingerprint,
    then compare-ACK only the exact deleted-batch marker. A periodic sweep
    neither fabricates nor consumes a marker.

Every current typed direct handler is present, including chat message,
reaction, introduction, contact request and mutation/deletion families. Every
group path is present, including legacy group drain and protected bootstrap,
authority and content shapes. Non-notification rows still must reach their
canonical durable handler. A missing nullable handler must retain/retry; it may
not fall through to a generic callback that deletes staged custody.

Plan 374 creates SQL-materialized ledger work only as `INBOX_RECONCILER`. It
never originates `ANDROID_PUSH_SERVICE` or `RELAY_VERIFIED_UNACKED`. The
identity-free fixed wake in Plan 375 also cannot originate either state; it is
only a mailbox recovery signal. A separately authenticated native row from a
future adapter may use the Plan-372 phase-preserving custody upgrade exactly.

Any non-converged page, nonzero total in any of the four custody stores,
pending ledger work, unknown effect, callback,
quiesce failure, database-close failure or lease-release failure retains the
marker and returns retry. A retained DRAINING owner blocks a successor rather
than allowing two writers. A newer generation/account binding always survives
stale completion. A callback admitted after preliminary settlement is awaited
and included in the post-fence total; removing that final check must be a
causal RED. A direct/group callback offered after the seal is synchronously
refused into durable retry: it produces no handler/effect or direct-confirm /
relay ACK, retains the recovery marker, and is recovered by the next owner.

One `ProductionHeadlessCanonicalRecoveryRunner` owns the exact partial graph
from first lease acquisition through returned session. `runRecovery` and
`emergencyShutdown` address that same instance. Every construction cut either
self-cleans in the order above or truthfully retains DRAINING; reported
`databaseClosed`/`leaseReleased` facts come from that instance, not a fresh
lease-state query.

### Readiness and rollback

`recoveryWorkEnabled` remains false until this code-ready composition exists.
Extend the existing binding coordinator/publisher with one typed committed
result (or exact read-back) containing the native binding and actual enabled
bit. The normal supported-account bootstrap reconciles it idempotently after
graph registration; no second readiness coordinator, health monitor, timer or
store is introduced. Enable only when returned binding and flag exactly match.
Transient runtime/ledger errors use the incumbent retry state; they do not
continually republish readiness.

Rollback order is fixed:

1. for same-binding operational rollback, publish the same binding with
   `recoveryWorkEnabled=false`;
2. verify immediate/periodic work are cancelled/idle and no native lease, Go
   host or retained engine remains active;
3. preserve that binding's marker, ledger and SQL custody for warm-app recovery;
4. only then remove/downgrade the production headless entrypoint.

Logout/account switch is different: rotate/retire the binding through the
incumbent native transaction, which intentionally retires the old marker;
Plan-372 ledger/SQL follow their accepted account-rebind cleanup contract.

This bit is independent from the paired opaque-wake capability seam. Plan 374
must not advertise, activate or inject either capability.

## Scope Contract And Guard

In scope:

- the seven missing production headless seams;
- minimal helper extraction from the incumbent bootstrap so foreground and
  headless use the same direct/group/ledger adapters;
- one recovery-only node-core/admission barrier and one exact partial-graph
  runner; these are refinements of incumbent owners, not new runtime services;
- one small shared deleted-batch commit/schedule seam used by the production
  Firebase service and the debug-only device probe;
- activation of existing deleted-batch/periodic work only after graph readiness;
- exact teardown, retry, role, account-cutover and foreground-handoff behavior;
- exact once-only registration of the new production-bootstrap test owner in
  `BASELINE_TESTS`; the file remains selected directly for focused proof too;
- a registered Android-native host row and one narrow automated no-Activity
  device proof.

Explicitly out of scope:

- Plan-375 fixed `{v:"1",w:"1"}` FCM classification, generic fallback card,
  fixed-wake scheduling reason, capability readiness or token re-registration;
- Plan-373 iOS NSE work;
- N09 `MessagingStyle`/Person/conversation styling;
- N11 read, mute, activation, dismiss, badge or cleanup policy changes;
- a DB v117 migration, second ledger/lock/store/worker/scheduler/runtime broker,
  second headless engine, new relay action/protocol or new inbox queue;
- live FCM/provider/relay credentials, Doze/OEM campaigns, capability rollout,
  rich-path retirement, telemetry, cohort operations, release acceptance and
  the historical broad Plan-331 6x2 campaign. Those remain WP-07/N12.

Stop and replan if the implementation needs a UI bootstrap, separate domain
graph, new durable queue/DB version, another runtime owner, or cannot settle
both direct and group custody through the one accepted Plan-372 API.

## Test Contract

| ID | Behavior under test | Exact test owner and fixture | Expected GREEN | Counterexample locked by GREEN | Gate |
|---|---|---|---|---|---|
| TC-374-00 | Plan-372 receipt and finalized ledger/visibility/default-off contracts are durable prerequisites | dependency command above; no new product test | The exact committed receipt/API identities, TC-371-01, TC-370-05, TC-370-07 and default-false source seam pass; any drift stops before RED | accept planning prose, uncommitted receipt, DB-version drift or enabled paired cap -> stop | preflight |
| TC-374-01 | One UI-neutral factory uses only an existing DB/key, then passively qualifies primary or active-linked physical identity before Go/network/effect | new `test/core/bootstrap/production_headless_canonical_recovery_test.dart` with temp encrypted-opener/role fixtures | pre-open malformed secure state opens nothing; missing key/DB never creates; old schema uses incumbent migration; post-open missing/mismatched identity closes/releases with zero Go/network/effect; exact primary/linked reaches one session | create DB/key, call side-effecting `IdentityRepositoryImpl.loadIdentity`, linked fallback, UI bootstrap, or leak a post-open refusal -> red | focused serial |
| TC-374-02 | Every typed direct/group family converges through real adapters; four custody stores and Plan-372 ledger are empty before ACK | same file plus real SQLite/outbox fixture; parameterized current handler census | direct message/reaction/introduction/contact request/mutation and legacy/protected group bootstrap/authority/content all use canonical handlers; direct/group display+reconciliation totals reach zero; SQL work uses `INBOX_RECONCILER`; no duplicate effect | remove any typed handler, allow generic destructive fallback, check ready-only rather than total, skip a store/lane, originate `ANDROID_PUSH_SERVICE`/relay custody, or ACK pending work -> red | focused serial SQLite |
| TC-374-03 | Invocation binding/generation plus migration/role/physical credential are checked before acquisition where possible and again after teardown | exactly one named owner in `test/core/notifications/headless_canonical_recovery_entrypoint_test.dart`; injected runner/authority/teardown barriers | stale input performs zero acquisition; post-open authority mismatch cleans up before Go; same-binding linked credential/role mutation or new generation/account cutover refuses ACK; periodic never consumes a marker | trust WorkRequest input, compare only opaque binding, stale-ACK success, or fabricate periodic marker -> red | focused Dart |
| TC-374-04 | Admission sealing, construction/cancellation crash cuts and exact runner-owned emergency cleanup preserve one owner | exactly one named subprocess/barrier owner in `test/core/bootstrap/production_headless_canonical_recovery_test.dart`; the same test process owns the partial graph, first settlement, callback before/after seal, listener stop, Go quiesce and DB close | seal -> await all admitted work -> final four-store/ledger settlement -> dispose owners -> Go/DB/lease; pre-seal late custody blocks ACK until settled; post-seal offer is synchronously refused to durable retry with no handler/effect/direct-confirm/relay-ACK and retains marker; emergency report comes from same partial instance | accept a post-seal callback, omit final settlement/`GroupMessageListener.stop`, query a new lease in emergency cleanup, release before close, ACK on `finally`, or permit successor behind retained engine -> red | focused serial/process |
| TC-374-05 | Code-ready recovery publication and two distinct retirement modes are exact | update `canonical_runtime_lease_test.dart`; new Kotlin readiness tests | typed native result must echo binding+enabled; same-binding rollback disables/cancels while preserving marker/custody and proves no live owner; logout/switch rotates binding and retires old marker | keep always-false behavior, trust bool-only/wrong binding or flag, add health monitor, preserve old-account marker, delete same-binding marker, or couple opaque cap -> red | focused Dart/Kotlin |
| TC-374-06 | Foreground and headless contenders use one runtime/SQL owner and hand off without loss | exactly one Dart owner in `production_headless_canonical_recovery_test.dart`, plus `GoRuntimeHostTest`, `CanonicalRuntimeLeaseTest` and worker barriers in the native script | exactly one owner/effect; foreground request stops headless at a safe boundary; newer work reruns | two engines/DB writers, force-dispose live owner, or strand new generation behind KEEP -> red | focused Dart/Kotlin race |
| TC-374-07 | The production AOT entrypoint calls the real factory and remains UI/plugin neutral; every recovery path is classified | exactly one named source owner in `test/core/bootstrap/main_bootstrap_boundary_test.dart`; incumbent entrypoint tests remain full-file preservation | `lib/main.dart` contains the exact production run/cleanup lines once each and both unavailable run/cleanup lines zero times; both delegate to the same runner instance; one factory; no `runApp`/ApplicationRoot/generic listener; incumbent foreground recovery remains | leave either dormant callback, construct UI bootstrap, add second scheduler, or omit one reason -> red | focused/source guard |
| TC-374-08 | Real deleted-batch service commit/schedule seam runs WorkManager -> headless Dart -> existing SQLCipher v116 -> ledger/effect -> exact marker settlement without an Activity | extend the debug-only H0 broadcast receiver with a small Dart fixture and one pinned runner; do not use an Activity-backed `integration_test` driver | production service and probe call the same commit/schedule owner; eligible direct/group conversations each converge to their exact private card state; process-death retry resumes; marker exact-ACKs; Activity launch count stays zero | seed store/enqueue directly, fake/create DB, launch Activity/manual tap, ACK before reopen, omit a lane/retry, unpinned target or skip -> red | availability-bounded device |

### Test notes

- First create only the compiling API/type skeleton needed to select the exact
  TC-374-01 semantic assertion. TC-374-01 is the one required initial RED; a
  compile/load/tool/teardown failure is not accepted. Do not later claim eight
  independent assertion REDs unless eight machine-counted artifacts were
  actually captured.
- Parameterize lane and event kind inside TC-374-02 rather than creating four
  modality suites.
- Existing-only DB, SQLite/registry/plugin-global and ownership-race cases run
  serially. Pure parser/readiness/source fixtures may use Flutter concurrency 4.
- Replace, rather than preserve unchanged, the current dormant-entrypoint test
  and the lease test named `opaque install account binding is stable rotates
  and never enables work`; they encode the intentional pre-Plan-374 state.
- Keep the Dart owner map literal: TC-374-01/02/04/06 live once each in
  `production_headless_canonical_recovery_test.dart`; TC-374-03 lives once in
  `headless_canonical_recovery_entrypoint_test.dart`; TC-374-05 lives once in
  `canonical_runtime_lease_test.dart`; and TC-374-07 lives once in
  `main_bootstrap_boundary_test.dart`. The focused commands below count this
  mapping exactly.
- Register `test/core/bootstrap/production_headless_canonical_recovery_test.dart`
  exactly once in `BASELINE_TESTS`. Do not rely on a core-family glob that this
  plan intentionally does not run.
- The device fixture seeds canonical test custody, then invokes a debug-only
  receiver that calls the same production deleted-batch commit/schedule seam as
  Firebase. It must not write the marker or enqueue WorkManager directly. It
  does not require or claim live FCM/relay delivery.

### Required mutation protocol

The table's counterexample column is a design census, not a claim that every
alternative was executed. Execute exactly these five causal mutations, one at
a time, on the otherwise-green implementation; require the named exact owner to
fail semantically; revert; and require its exact GREEN before the next mutation:

1. permit missing-key/database creation -> TC-374-01;
2. remove one parameterized typed group-content handler or replace a four-store
   total with ready-only status -> TC-374-02;
3. trust the initial generation after the post-teardown generation changes ->
   TC-374-03;
4. omit the authoritative post-seal settlement -> TC-374-04;
5. accept recovery readiness by bool without the exact echoed binding ->
   TC-374-05.

Record command, changed line, selected/failure count, non-retained RED hash,
revert identity and restored-GREEN hash for all five. TC-374-06/07/08 remain
causal GREEN/race/source/device proofs and must not be reported as mutation
re-REDs unless additional mutations are genuinely executed.

## Implementation Steps

1. Validate the exact Plan-372 receipt/API identities above and re-run current
   Graphify/source grounding. Record the exact clean execution HEAD/tree
   separately from the Plan-372 tested tree.
2. Add the minimum compiling TC-374-01 skeleton and record the one required
   assertion-owned semantic RED. Author the remaining exact owners before their
   production behavior; do not call compile failures or uncaptured cases REDs.
3. Add the existing-only encrypted-open option and a side-effect-free identity/
   secret snapshot loader shared with the incumbent repositories. Do not create
   a key/DB/account or call the side-effecting identity load path.
4. Extract one reusable, UI-neutral production dependency builder from the
   incumbent bootstrap. Do not instantiate the application bootstrap itself.
5. Implement exact pre-open authority checks, post-open identity/binding/linked
   qualification and the recovery-only node core.
6. Implement the production `CanonicalRecoverySession` adapters for the full
   typed direct/group census and Plan-372 `INBOX_RECONCILER` settlement, including
   total queries for all four SQL custody stores.
7. Add one admission seal/await/dispose boundary and the exact partial-graph
   runner. Freeze the final post-fence settlement, teardown, authority
   resnapshot and compare-ACK ordering with deterministic crash barriers.
8. Replace the unavailable AOT callback with the production runner. Keep the
   unavailable implementation only as a test/fail-closed fallback if useful;
   it must have no production caller.
9. Make `recoveryWorkEnabled` reflect code-ready supported-account composition
   through a typed exact native result, while the
   paired opaque/outcome admission remains false and uninjected.
10. Extract the production deleted-batch commit/schedule seam used by
    `MknoonFirebaseMessagingService` and the debug-only proof receiver.
11. Register the new Dart bootstrap owner exactly once in `BASELINE_TESTS`.
    Add/register the exact Android-native host script and no-Activity scenario;
    extend the existing H0 harness rather than create a second orchestrator.
12. Execute the five isolated mutation re-REDs, then run focused,
    preservation, curated, device and hygiene gates; record a
    checksum-bound receipt with marker
    `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE`.
13. Close the plan, append-only status, index and coverage outputs described
    below without changing production/test bytes after the frozen tested-tree
    capture.

## Risks And Blind Spots

- A copied subset of `ProductionApplicationBootstrap` can silently diverge.
  The shared-helper/caller census and real direct/group fixtures are mandatory.
- WorkManager input can be stale even when the durable store is current. Both
  pre-acquisition and post-teardown binding/role/credential resnapshots are
  required; opaque binding alone cannot detect a linked-role mutation.
- The ordinary encrypted opener creates a key/database when absent. Headless
  recovery must use the explicit existing-only mode or it can fabricate a new
  empty account after loss/corruption.
- Ready-only outbox reads are not convergence. Backoff/deferred/reconciliation
  rows in any one of the four custody stores must retain the marker.
- A callback admitted between preliminary settlement and ingress sealing can
  create new custody. The post-fence total/ledger settlement is authoritative.
- An active linked device uses a different physical transport. Falling back to
  the logical account key reads the wrong mailbox and violates N01.
- `finally` is not proof of safe teardown. A failed close/quiesce/release must
  retain ownership and retry, even if that delays a successor.
- Enabling recovery and enabling fixed wake are separate actions. Coupling them
  would expose clients before Plan 375 is ready.
- A host-green graph can still depend on Activity initialization or fake SQLite.
  The narrow process/device proof is the causal boundary.
- The old Plan-331 real-FCM campaign remains credential-blocked and contains
  unrelated health/history/localization assertions. It is rollout evidence,
  not Plan-374 mechanism evidence.

## Device And Manual Evidence Profile

- Boundary: Android-specific native process ownership and real SQLCipher/plugin
  composition; one automated Android device leg is required.
- Live planning matrix on 2026-08-16: USB Pixel 6
  `21071FDF600CSC` (API 36) and emulator `emulator-5554` (API 37). Execution
  rediscovers rather than hard-codes either ID.
- Required target: one available Android target, emulator preferred for
  deterministic process-death orchestration and USB physical otherwise.
- Driver: debug-only broadcast/H0 harness, zero Activity and zero manual taps;
  every `adb`/Gradle/Flutter operation is scoped through the selected ID.
- Fixture: real existing SQLCipher v116 plus direct/group custody and Plan-372
  ledger; provider-independent deleted-batch injection enters through the exact
  production service commit/schedule seam.
- Not required: iPhone/iOS, two peers, unavailable API bands, live FCM/relay,
  Doze/OEM restriction or human visual review. Those are either irrelevant or
  WP-07/N12 evidence.

## Gate Cadence

Run in this order:

1. prerequisite and default-off preflight;
2. the one assertion-owned TC-374-01 RED, then pure Dart
   parser/readiness/source tests at concurrency 4 and
   existing-DB/SQLite/process ownership tests serially;
3. the five isolated required mutations with an exact semantic failure and
   restored GREEN after each;
4. focused Kotlin worker/store/scheduler/runtime tests and the registered native
   script; the pure-Dart and Gradle legs may run concurrently, but neither may
   overlap a process-global Dart ledger/registry run;
5. exact preservation sentinels;
6. `completeness-check`, then affected `baseline`, `1to1` and `groups` lanes
   serially because they share Flutter/native/relay resources;
7. one disposable build followed by one explicitly discovered Android target;
   a second target is optional parity, not a closure obligation;
8. analyzer, formatting, diff hygiene and one incremental Graphify refresh;
9. freeze evidence, then write closure documentation only.

Do not run `core-host-all`, `feature-host-all` or full `host-all` in Plan 374.
Plan 375 owns the single N07+N08 adapter-wave `host-all` after both adapters are
complete. WP-07 runs the next full host gate at rollout/release closure.

## Acceptance Gates

### 1. Assertion-owned RED

```bash
(
  set -u
  raw="$(mktemp /tmp/plan374-red.XXXXXX)"
  events="$(mktemp /tmp/plan374-red-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  set +e
  flutter test --no-pub --machine \
    test/core/bootstrap/production_headless_canonical_recovery_test.dart \
    --name 'TC-374-01 ' >"$raw"
  status=$?
  set -e
  jq -c 'select(type == "object")' "$raw" >"$events"
  test "$status" -ne 0
  test "$(jq -s '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains("TC-374-01 ")))] | length' "$events")" -eq 1
  selected="$(jq -r -s '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains("TC-374-01 "))) | .test.id' "$events")"
  test "$(jq -s --argjson selected "$selected" '[.[] | select(.type=="testDone" and .testID==$selected and .result=="failure" and .skipped==false)] | length' "$events")" -eq 1
)
```

### 2. Focused Dart GREEN

```bash
# Pure parser/readiness/source owners may run concurrently.
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan374-pure.XXXXXX)"
  events="$(mktemp /tmp/plan374-pure-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  flutter test --no-pub --machine --concurrency=4 \
    test/core/notifications/headless_canonical_recovery_entrypoint_test.dart \
    test/core/notifications/canonical_runtime_lease_test.dart \
    test/core/bootstrap/main_bootstrap_boundary_test.dart \
    --name 'TC-374-(03|05|07) ' >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  for suffix in 03 05 07; do
    label="TC-374-${suffix} "
    test "$(jq -s --arg label "$label" '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg label "$label" '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)

# Existing-DB/SQLite/flock/process owners are selected and counted serially.
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan374-serial.XXXXXX)"
  events="$(mktemp /tmp/plan374-serial-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  flutter test --no-pub --machine --concurrency=1 \
    test/core/bootstrap/production_headless_canonical_recovery_test.dart \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    test/core/notifications/durable_conversation_notification_id_registry_test.dart \
    --name 'TC-374-(01|02|04|06) |TC-372-(05b?|06) ' >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  for label in TC-374-01 TC-374-02 TC-374-04 TC-374-06 \
    TC-372-05 TC-372-05b TC-372-06; do
    test "$(jq -s --arg label "$label " '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg label "$label " '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)
```

The Plan-372 file names/selectors are re-pinned from its accepted receipt; do
not silently keep placeholders if the finalized API names differ.

### 2a. Exact baseline registration

The production bootstrap owner is manually curated because Plan 374 does not
run a broad core family. The direct focused selection above and this baseline
registration are both required.

```bash
(
  set -euo pipefail
  owner='test/core/bootstrap/production_headless_canonical_recovery_test.dart'
  baseline_block="$(
    sed -n '/^readonly BASELINE_TESTS=(/,/^)/p' scripts/run_test_gates.sh
  )"
  test "$(printf '%s\n' "$baseline_block" | rg -Fxc "  \"$owner\"")" -eq 1
  test "$(rg -Fxc "  \"$owner\"" scripts/run_test_gates.sh)" -eq 1
)
```

### 3. Focused Android native registration and execution

Add exactly one later-wave synthetic host item
`scripts/test/run_android_headless_recovery_native_374.sh`. Register it in the
host runner's constant, inventory, predicate, print and execution branches—once
in full host, never in Dart-only/core/feature families.

```bash
(
  set -euo pipefail
  bash -n scripts/test/run_android_headless_recovery_native_374.sh
  log="$(mktemp /tmp/plan374-native-discovery.XXXXXX)"
  dart_only="$(mktemp /tmp/plan374-native-dart-only.XXXXXX)"
  trap 'rm -f "$log" "$dart_only"' EXIT
  ./scripts/run_host_test_gates.sh host-all --dry-run \
    --only scripts/test/run_android_headless_recovery_native_374.sh | tee "$log"
  test "$(rg -c '^ *[0-9]+\. bash scripts/test/run_android_headless_recovery_native_374\.sh$' "$log")" -eq 1
  ./scripts/run_host_test_gates.sh host-all --dart-only --dry-run >"$dart_only"
  ! rg -q 'run_android_headless_recovery_native_374' "$dart_only"
  ./scripts/run_host_test_gates.sh host-all \
    --only scripts/test/run_android_headless_recovery_native_374.sh
)
```

The native script runs the exact selected Kotlin classes
`ProductionHeadlessCanonicalRecovery374Test`,
`HeadlessCanonicalRecoveryWorkerTest`, `DroppedPushRecoveryStoreTest`,
`DroppedPushRecoveryWorkSchedulerTest`, `CanonicalRuntimeLeaseTest`,
`GoRuntimeHostTest`, `MknoonFirebaseMessagingServiceTest`,
`CanonicalRuntimeH0ProbeSourceTest` and
`NativeRuntimeOwnershipSourceTest`. It parses the corresponding JUnit XML,
requires every planned TC-374 method exactly once and all selected tests with
zero failures/errors/skips, then performs compile/merged-manifest/source
contracts. Freeze the exact method/count manifest inside the script after the
tests are authored; Gradle `BUILD SUCCESSFUL` alone is insufficient.

### 4. Exact preservation

```bash
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan374-preservation.XXXXXX)"
  events="$(mktemp /tmp/plan374-preservation-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  flutter test --no-pub --machine --concurrency=1 \
    test/core/notifications/canonical_recovery_runtime_test.dart \
    test/core/notifications/dropped_push_recovery_coordinator_test.dart \
    test/core/notifications/dropped_push_recovery_bridge_test.dart \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    test/core/notifications/app_visibility_snapshot_test.dart \
    --name 'deleted batch converges, closes and releases before exact ack|multi-page direct and group drains exhaust before projection and ack|pending durable projection custody retries after cleanup without ack|account cutover before acquire retires stale work without opening|database close failure retains ownership and forces retry|runtime quiescence failure never closes or transfers ownership|new deletion during drain defeats stale ack and remains pending|account-bound authority reads and acknowledges the exact marker|TC-370-05 opaque outcome uses strict all-relay completion|TC-371-01 ' >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  while IFS= read -r label; do
    test -z "$label" && continue
    test "$(jq -s --arg label "$label" '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg label "$label" '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done <<'EOF'
deleted batch converges, closes and releases before exact ack
multi-page direct and group drains exhaust before projection and ack
pending durable projection custody retries after cleanup without ack
account cutover before acquire retires stale work without opening
database close failure retains ownership and forces retry
runtime quiescence failure never closes or transfers ownership
new deletion during drain defeats stale ack and remains pending
account-bound authority reads and acknowledges the exact marker
TC-370-05 opaque outcome uses strict all-relay completion
TC-371-01
EOF
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)
```

The native suite separately owns the exact scheduler-generation sentinel.
Re-pin Plan-371/372 names from their committed receipts before execution.

### 5. Curated lanes

```bash
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
```

Run these serially. Do not substitute an unsupported batch flag or add feed,
transport, core-host-all or feature-host-all without changed-file evidence.

### 6. Availability-bounded Android proof

```bash
(
  set -euo pipefail
  mkdir -p build/plan374/device build/plan374/apk
  flutter devices --machine >build/plan374/flutter-devices.json
  adb devices -l >build/plan374/adb-devices.txt

  emulator_id="$(awk '$2=="device" && $1 ~ /^emulator-/ {print $1; exit}' build/plan374/adb-devices.txt)"
  usb_id="$(awk '$2=="device" && $1 !~ /^emulator-/ && $0 ~ /(^|[[:space:]])usb:/ {print $1; exit}' build/plan374/adb-devices.txt)"
  target_id="${emulator_id:-$usb_id}"
  if test -z "$target_id"; then
    printf 'N/A (target unavailable by project policy)\n' >build/plan374/device-disposition.txt
    exit 0
  fi

  scripts/run_android_headless_recovery_374.sh \
    --build-only --output build/plan374/apk
  apk='build/plan374/apk/app-plan374-debug.apk'
  test -f "$apk"
  shasum -a 256 "$apk" >build/plan374/apk.sha256

  ANDROID_SERIAL="$target_id" scripts/run_android_headless_recovery_374.sh \
    --device-id "$target_id" --apk "$apk" --skip-build \
    --production-deleted-batch-seam --no-activity --process-death \
    --output build/plan374/device
)
```

The runner extends the existing debug-only H0 broadcast receiver. The receiver
calls the same extracted deleted-batch commit/schedule owner as
`MknoonFirebaseMessagingService`; directly seeding the store or enqueuing work
does not satisfy TC-374-08. Build one immutable disposable APK before the
pinned target run. One discovered Android target is the closure obligation
(emulator preferred for deterministic process death, otherwise USB physical);
a second target is optional parity, not a required campaign. No unavailable
API band may block closure. The receipt binds APK/source/device ID, nonce,
exact scenario count, existing SQLCipher v116, direct and group custody,
per-conversation card facts, ledger/effect, process-death retry, marker ACK,
Activity launch count zero, zero manual taps/skips and cleanup.

### 7. Hygiene and graph

```bash
(
  set -euo pipefail
  dart_paths="$(
    {
      git diff --name-only --diff-filter=ACMRT -- '*.dart'
      git ls-files --others --exclude-standard -- '*.dart'
    } | sort -u
  )"
  while IFS= read -r dart_path; do
    test -z "$dart_path" && continue
    dart format --output=none --set-exit-if-changed "$dart_path"
  done <<EOF
$dart_paths
EOF
  git diff --check
  bash -n scripts/run_test_gates.sh
  bash -n scripts/run_host_test_gates.sh
  bash -n scripts/test/run_android_headless_recovery_native_374.sh
  bash -n scripts/run_android_headless_recovery_374.sh
  flutter analyze
  ./graphify-arch/refresh_arch_graph.sh --incremental
  python3 graphify-arch/tdd_context.py query \
    'Plan 374 production headless canonical recovery factory entrypoint direct group ledger teardown' \
    --profile review --budget 800 --ensure-fresh
)
```

## Execution Interpretation And Done Criteria

- [ ] Plan-372 committed receipt and finalized APIs validate; current execution
      baseline is clean, committed and recorded without treating the Plan-372
      historical dirty snapshot as current execution evidence.
- [ ] TC-374-01 has the one required semantic assertion RED. TC-374-01 through
      TC-374-08 each have their exact causal GREEN, and the five mutations in
      the required mutation protocol independently re-red, are reverted and
      return their exact owners to GREEN. No additional RED/mutation count is
      claimed without a corresponding artifact.
- [ ] One UI-neutral production graph owns direct, group and ledger settlement;
      no second service/store/worker/scheduler/lock/DB migration exists.
- [ ] Every current typed direct/group replay handler is present; all four SQL
      custody totals and the Plan-372 ledger converge, and this slice writes
      only `INBOX_RECONCILER` source ownership.
- [ ] Existing-only DB opening never creates account state. Primary and
      active-linked identities are passively role-correct; post-open refusal
      closes/releases before Go/network/effect.
- [ ] Dart admission is sealed and all callbacks/four custody stores/ledger are
      settled before listener disposal, Go/DB/lease teardown and final
      authority resnapshot/ACK; every failure cut prevents overlapping writers.
- [ ] Existing recovery work is enabled only after accepted readiness and can
      be rolled back independently of fixed-wake capability admission; typed
      native read-back proves binding+enabled state and account rotation remains
      distinct from same-binding rollback.
- [ ] Focused Dart/native and exact preservation pass with exact selected/pass
      counts and zero undeclared skips.
- [ ] The new production-bootstrap test owner occurs exactly once in
      `BASELINE_TESTS` and exactly once in the full test-runner source.
- [ ] Baseline, `1to1` and `groups` curated lanes pass serially.
- [ ] One explicitly discovered Android target runs the bounded automated proof
      from one immutable APK; no available target is policy N/A and a second
      target is optional parity only.
- [ ] No Plan-374 full host/family sweep or credential-dependent real-FCM
      campaign was run or implied.
- [ ] Analyzer, changed+untracked Dart formatting, shell syntax, diff hygiene
      (including both gate runners) and current Graphify review pass.
- [ ] A checksum-bound receipt records marker
      `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE`, base/frozen
      tree/dirty/Graphify identities, exact logs and device disposition.
- [ ] Plan, append-only `STATUS.md`, index receipt row and coverage/GAP-N08
      disposition are closed after the frozen tested-tree capture, without a
      post-freeze production/test/native/script change or an activation,
      full-GAP, A-control-compliance, live, PRD or release overclaim.

The receipt directory also commits `workspace-porcelain-v2.txt.gz` and
`graphify-fingerprint.txt`; the recorded dirty SHA is the decompressed archive
SHA-256 and the fingerprint file contains the exact 16-lowercase-hex value.
Write `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE` once as a
standalone raw receipt line. Plan 375 validates those committed bytes and exact
marker rather than trusting receipt prose.

## Closure Outputs

Capture the frozen tested tree, porcelain-v2 snapshot and current Graphify
fingerprint before editing closure-only documents. The closure transaction then
owns these exact outputs:

- `Test-Flight-Improv/evidence/374/README.md`, its canonical
  `README.md.sha256`, `workspace-porcelain-v2.txt.gz` and
  `graphify-fingerprint.txt`. The README records the one initial RED, five
  mutation re-RED/restored-GREEN pairs, every final gate identity, Android
  target or policy-N/A disposition, source/APK identity, and the standalone raw
  marker exactly once.
- this plan's final status becomes
  `POST_EXECUTION_AUDIT_CLOSED / N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE / N08 SLICE 1 OF 2 / RECOVERY-WORK CODE-READY / FIXED-WAKE ADMISSION DEFAULT-OFF / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE` only after all done criteria pass.
- append, never rewrite, one Plan-374 implementation-closure line and one
  receipt-bound provenance line in `STATUS.md`; both preserve fixed-wake
  default-off, Plan-375 remaining work and the live/PRD/release exclusions.
- replace the existing Plan-374 row in `Test-Flight-Improv/00-INDEX.md` with the
  bounded code-closure disposition and add one `evidence/374/README.md` row
  containing the exact receipt SHA, frozen tree, dirty snapshot, Graphify
  fingerprint and marker.
- update
  `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
  at the top implementation refresh/baseline, GAP-N08 disposition, affected
  A-12/A-13/A-15/A-20/A-27/A-28 rows, WP-05 and closing supersession notes.
  A-14 stays unadvanced because MessagingStyle remains GAP-N09 scope. Keep all
  affected composite controls `Partial` and the paired admission default-off
  unless the completed evidence independently justifies and documents a score
  change; mechanism code-readiness alone is not PRD compliance.

The closure-only plan/status/index/coverage/receipt bytes may postdate the
frozen tree, but the receipt must say so explicitly and prove that they add no
production, test, native, fixture, gate-runner, device-runner or Graphify-source
change.

Meeting these criteria closes the production headless recovery safety gate and
the unfinished Plan-331 mechanism tail. It does not close all GAP-N08, activate
opaque wake, prove live FCM/provider behavior, or make the release eligible.

## Handoff

Plan 375 may start only from Plan 374's committed checksum receipt. It consumes
the frozen production factory/session, exact role-correct identity selection,
marker/scheduler extension point, Plan-372 ledger settlement and device proof.
Plan 375 must not reopen the production graph or create another worker/store;
it owns only strict fixed FCM ingress, generic fallback/presentation lease,
fixed-wake scheduling semantics and paired Android consumer readiness. The
fixed provider bytes carry no event identity, so Plan 375 must not synthesize
`ANDROID_PUSH_SERVICE`, `RELAY_VERIFIED_UNACKED`, correlation, SQL or relay ACK
authority from them. Plan 374 remains the materializing `INBOX_RECONCILER`.
Plan 373 is not a code dependency of Plan 374. Plan 375 does require its single
platform-readiness composition owner before extending Android admission, and
may count the N07+N08 adapter-wave `host-all` only after a checksum-valid
Plan-373 receipt exists.

## Reviewer Findings

Independent review record: **PASS AS A CONTRACT after material in-place
corrections and the committed-dependency audit; this is not an execution-start
attestation for a dirty worktree**.

- Claims and boundary: PASS. The seven Plan-331 seams form one
  acquisition-to-ACK rollback unit. Plan 374 owns only incumbent
  `deletedBatch`/`periodicSweep` and `INBOX_RECONCILER`; Plan 375 owns fixed
  ingress, generic fallback and paired Android consumer readiness. The
  identity-free fixed wake itself owns no event-source state.
- Causal state: PASS. Existing-only DB opening precedes passive identity
  qualification; role/physical authority is resnapshotted. The authoritative
  four-store/ledger check occurs after Dart admission is sealed and callbacks
  are awaited. Emergency cleanup reports the exact partial graph.
- Bypass safety: PASS. All current direct/group typed families must have a
  handler; nullable fallthrough cannot destructively consume custody. UI/live
  bootstrap, rich/fixed ingress, N09/N11 and rollout paths are explicit
  exclusions.
- Gate integrity: PASS after the 2026-08-16 dependency audit. Pure and
  process-global tests are split; TC-374-03/04 have one concrete owner each;
  every planned selector is counted individually; the new bootstrap owner is
  pinned once in `BASELINE_TESTS`; ten exact preservation tests are real;
  Kotlin includes the Firebase service; both gate runners and both new runner
  scripts are syntax-checked; one immutable APK drives the no-Activity proof.
- Evidence honesty: PASS after correction. TC-374-01 alone owns the required
  initial assertion RED; five explicitly enumerated mutations, not every table
  counterexample, own the mutation claim. Closure requires receipt, append-only
  status, index and bounded coverage outputs after the frozen tested tree.
- Operability/economy: PASS. Same-binding rollback differs from account
  rotation, readiness uses typed native read-back, and one Android target is
  sufficient for this non-peer mechanism. Full host is deferred exactly once
  to the completed N07+N08 adapter wave.

## Arbiter Decision

**CONTRACT READY; PLAN-372 RECEIPT VALIDATED; NOT YET LABELED
EXECUTION-READY.** The accepted dependency is commit
`650f8cbe68dfed52a5c66fc53da35915bca53f02`, receipt SHA-256
`9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62`,
and Graphify fingerprint `8c428eb87b960e70`. Commit this corrected planning
contract with the successor-doc freeze, require a clean worktree, and rerun the
exact TC-374-00 preflight before the first RED. Do not create another
headless-foundation plan. Do not expand the device leg to both available
Android classes unless implementation introduces a concrete device-class
counterexample; availability permits targets but does not require redundant
parity. Re-review if the committed intervening tree changes the
ledger/lock/owner API or current source grounding is no longer anchored.

## Execution Progress

| Time | Step | RED evidence | GREEN evidence | Refactor / regression | Evidence path |
|---|---|---|---|---|---|
| 2026-08-16 historical draft | TC-374-00 prerequisite | Plan-372 receipt absent while Plan 371 was in progress | pending at that time | No production execution authorized | Wait for Plan 372 |
| 2026-08-16 dependency/contract re-ground | Plan-372 receipt/API pins; TC-371-01; TC-370-05/07; Graphify/source; gate and closure contract | No product RED; planning audit only | Commit `650f8cbe68dfed52a5c66fc53da35915bca53f02`, tree `9d4b46d37a205ea7da1a858dcde8c6f365b29917`, receipt SHA `9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62`, frozen tree `71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2`, Graphify current/anchored `8c428eb87b960e70`; receipt/API/default-off literal audit PASS; TC-372-01/05/06, TC-371-01, TC-370-05 and TC-370-07 each selected 1/1 and passed | **CONTRACT_READY / DEPENDENCY_VALIDATED**; shared worktree still contains successor planning edits, so no RED is authorized yet | Commit docs-only freeze, prove clean worktree, rerun TC-374-00, then capture the one TC-374-01 semantic RED |
| 2026-08-16 execution: RED and composition | TC-374-00 from committed base `ffe37b71af5759320e677fab5495b5635bd661ea`; TC-374-01 skeleton; production factory, composition helpers, entrypoint swap, readiness, deleted-batch seam, tests, runner scripts | One semantic TC-374-01 assertion RED (machine SHA-256 `c945cfdfaab78daa48f342b3250de742731a18c1286d23f1e74891b4ae478a75`); no compile/load RED claimed | First TC-374-01 GREEN, then focused pure 3/3 and serial 7/7 (with TC-372-05/05b/06) at zero skips; ten preservation sentinels; nine-class/62-method native suite; baseline registration exact | Seven safety seams composed as refinements of incumbent owners; no second worker/store/lock/DB | Device leg |
| 2026-08-16 execution: device iterations | TC-374-08 runner + H0 fixture receiver on discovered `emulator-5554`; disposable `--build-only` APKs | Each failed attempt archived under `build/plan374/device-*`: owner consolidation, stale-cleanup generation race, stale direct correlation (product defect; regression owner added and registered in `BASELINE_TESTS`), `am kill` non-termination (replaced by pinned `run-as kill -9` + registered-job force-drive), API-37 `Registered N jobs:` dump-header parse, Android-16 silent-section autogroup summary classification (`FLAG_AUTOGROUP_SUMMARY`; source-test pin re-pinned to the strengthened app-card invariant) | Final run PASS: seed -> production deleted-batch seam generation 1 -> barrier consumed pid 27972 -> kill -> resumed pid 28068 SUCCESS -> four custody stores 0 -> two exact SETTLED/OS_POSTED `INBOX_RECONCILER` private cards -> exact marker ACK; Activity launches/taps/skips 0; APK SHA `7e1d437a1e0aed77dd2dab011e33b637b0d62f3bb8fd8e1989e56b02aeae8ac6`; result JSON SHA `37c3f812e88604748943d6c7c158e11585b71f0bf156d579d504bc7e461fe98d` | Focused/native/hygiene re-proved after every fix on the final bytes | Mutations and lanes |
| 2026-08-16 execution: mutations, lanes, hygiene | Five required mutations one at a time; curated lanes; analyzer/format/shell/diff; Graphify refresh | Each mutation: exact owner 1 selected / 1 semantic assertion failure; full command/changed-line/hash records in `build/plan374/mutations-final/mutation-report.json` | Byte-restored GREENs 5/5; final-tree focused pure 3/3, serial 7/7, preservation 10/10, zero skips; completeness 1464/1464 (new regression owner classified); baseline final-tree +196/+6/+1; `1to1` 3,340 pass / 10 declared skips plus Go tails; `groups` 4,345 plus Go tails; TC-374-00 revalidated minus the mid-execution clean-tree line; analyzer no issues (99.4s); all changed Dart format-clean; `git diff --check` and four `bash -n` clean; Graphify current/anchored `1072905b3c92a723` (78,599 nodes / 115,965 edges) | One lane catch: the overlay four-path census predated the stale-correlation consolidation and was re-pinned to the equivalent 2-direct + one-shared-projection topology after source verification | Freeze and closure |
| 2026-08-16 closure | Frozen tested state; receipt; plan/status/index/coverage | — | Frozen tested tree `220f71b36ef7617c3b8c0760df99836d185819a1` over base `ffe37b71af5759320e677fab5495b5635bd661ea`; dirty snapshot SHA `943eb5fa86eb41f416bd4c59a80bff3a8eeef883f8df42da383f43315486b3ef`; receipt `Test-Flight-Improv/evidence/374/README.md` SHA `c319f1805bfef45a07b603a38046cbb7b622b763ab090ee5dfc314e409ebca3f` with marker `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE` | Closure bytes postdate and are absent from the frozen tree; no production/test/native/fixture/gate-runner/device-runner/Graphify-source change after the accepted gates | Plan 375 |
