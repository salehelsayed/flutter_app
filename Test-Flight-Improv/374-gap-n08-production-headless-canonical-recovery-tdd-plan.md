# 374 - GAP-N08 Production Headless Canonical Recovery Completion

Status: **PREREQUISITE_BLOCKED / CONTRACT_READY / INDEPENDENTLY_REVIEWED / N08 SLICE 1 OF 2 / RECOVERY-WORK DEFAULT-OFF UNTIL READY / FIXED-WAKE ADMISSION DEFAULT-OFF / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
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

Execution is blocked until Plan 372 has executed and produced a committed,
checksum-bound receipt. Plan 372 transitively binds Plan 371 and the earlier
N01-N03 mechanism receipts; do not replay those full preflights unless the
Plan-372 receipt fails to bind them. Plan 373 is a sibling iOS adapter, not a
Plan-374 dependency.

Before the first TC-374 RED, require:

- `Test-Flight-Improv/evidence/372/README.md` and `README.md.sha256`;
- standalone marker `N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE` and
  transitive marker `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE`;
- valid Base HEAD, Frozen tested tree, Dirty snapshot SHA-256 and Graphify
  fingerprint identities, with committed receipt bytes plus independently
  rehashable dirty-snapshot and Graphify-fingerprint artifacts;
- DB current version still `116`;
- exactly one Dart production store for `local_notification_ledger_v1.json`
  using the accepted `NotificationConversationIds/.coordination.lock`, plus
  the exact Plan-372 codec/transition API and both `INBOX_RECONCILER` and
  `ANDROID_PUSH_SERVICE` owner values;
- accepted `SQL_READY` acquisition/settlement and phase-preserving
  `RELAY_VERIFIED_UNACKED` upgrade semantics;
- Plan-371 freshness reader/fixture and Plan-370 paired opaque/outcome admission
  still default `false`.

```bash
(
  set -euo pipefail
  receipt='Test-Flight-Improv/evidence/372/README.md'
  checksum='Test-Flight-Improv/evidence/372/README.md.sha256'
  test -f "$receipt"
  test -f "$checksum"
  (cd Test-Flight-Improv/evidence/372 && shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE' "$receipt"
  rg -Fq 'N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE' "$receipt"

  base="$(awk -F'`' '/\| (Base( and unchanged)? HEAD|Base HEAD) \|/ {print $2; exit}' "$receipt")"
  frozen="$(awk -F'`' '/\| Frozen tested tree \|/ {print $2; exit}' "$receipt")"
  dirty="$(awk -F'`' '/\| (Porcelain-v2 workspace snapshot|Dirty snapshot) SHA-256 \|/ {print $2; exit}' "$receipt")"
  graph="$(awk -F'`' '/\| (Graphify )?[Ff]ingerprint \|/ {print $2; exit}' "$receipt")"
  [[ "$base" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph" =~ ^[0-9a-f]{16}$ ]]
  git cat-file -e "${base}^{commit}"
  git cat-file -e "${frozen}^{tree}"

  receipt_commit="$(git log -n 1 --format=%H -- "$receipt")"
  test -n "$receipt_commit"
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

  # Test fixtures and planning prose cannot satisfy the production-authority
  # check. Plan 372's receipt must pin the accepted Dart source/API names.
  mapfile_path="$(rg -l 'local_notification_ledger_v1\.json' lib | head -n 2)"
  test "$(printf '%s\n' "$mapfile_path" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1
  ledger_source="$(printf '%s\n' "$mapfile_path" | sed -n '1p')"
  rg -Fq 'NotificationConversationIds/.coordination.lock' "$ledger_source"
  test "$(rg -l 'INBOX_RECONCILER' lib/core/notifications | wc -l | tr -d ' ')" -eq 1
  test "$(rg -l 'ANDROID_PUSH_SERVICE' lib/core/notifications | wc -l | tr -d ' ')" -eq 1

  flutter test --no-pub \
    test/core/notifications/local_notification_ledger_test.dart \
    --plain-name 'TC-372-01 v1 codec and state machine accept only legal monotonic transitions'
  flutter test --no-pub --concurrency=1 \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    --name 'TC-372-05 |TC-372-06 '

  flutter test --no-pub \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    --plain-name 'TC-370-05 opaque outcome uses strict all-relay completion'

  # Execution starts from a committed product tree. Planning against the
  # current dirty Plan-371 implementation is explicitly not evidence.
  test -z "$(git status --porcelain=v1)"
)
```

Plan 372's receipt must record the exact production ledger source and public
API names used by the checks above. If its implementation chooses a different
file layout, mechanically re-pin those literal names and independently review
the replacement; never weaken the check to a fixture or planning-document
search. After this preflight, require a clean committed product baseline and a
fresh review-profile Graphify query. Receipt tree/dirty/graph identities are
provenance for Plan 372, not permission to execute against later overlapping
uncommitted product drift.

## Graph Grounding Snapshot

- Query/profile:
  `python3 graphify-arch/tdd_context.py query "Plan 374 production headless canonical recovery completion runUnavailableHeadlessCanonicalRecovery ProductionCanonicalRecoveryGraphFactory HeadlessCanonicalRecoveryWorker DroppedPushRecoveryStore CanonicalRecoveryRuntime Plan 372 local notification ledger" --profile tdd --budget 700`
- Result: `confidence=anchored`; fingerprint `3c1aa59babe873f4`;
  freshness reported one stale group-listener input because Plan 371 is being
  implemented concurrently.
- Exact anchors: `runUnavailableHeadlessCanonicalRecovery` in
  `lib/core/notifications/headless_canonical_recovery_entrypoint.dart` and
  `CanonicalRecoveryRuntime` in
  `lib/core/notifications/canonical_recovery_runtime.dart`.
- Source verification added `lib/main.dart`, production bootstrap direct/group
  drain composition, `CanonicalRuntimeBindingCoordinator`, the Android worker,
  runtime host, lease, recovery store/scheduler and all exact tests below.
- Re-run this query with `--ensure-fresh` after Plan 372 closes. An unanchored or
  materially different graph is a stop-and-replan condition.

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

| ID | Behavior under test | RED owner and fixture | Expected GREEN | Required mutation/counterexample | Gate |
|---|---|---|---|---|---|
| TC-374-00 | Plan-372 receipt and finalized ledger/visibility/default-off contracts are durable prerequisites | dependency command above; no new product test | Missing/uncommitted/invalid receipt stops before RED; valid receipt re-grounds exact APIs | accept planning prose, uncommitted receipt, DB-version drift or enabled paired cap -> stop | preflight |
| TC-374-01 | One UI-neutral factory uses only an existing DB/key, then passively qualifies primary or active-linked physical identity before Go/network/effect | new `test/core/bootstrap/production_headless_canonical_recovery_test.dart` with temp encrypted-opener/role fixtures | pre-open malformed secure state opens nothing; missing key/DB never creates; old schema uses incumbent migration; post-open missing/mismatched identity closes/releases with zero Go/network/effect; exact primary/linked reaches one session | create DB/key, call side-effecting `IdentityRepositoryImpl.loadIdentity`, linked fallback, UI bootstrap, or leak a post-open refusal -> red | focused serial |
| TC-374-02 | Every typed direct/group family converges through real adapters; four custody stores and Plan-372 ledger are empty before ACK | same file plus real SQLite/outbox fixture; parameterized current handler census | direct message/reaction/introduction/contact request/mutation and legacy/protected group bootstrap/authority/content all use canonical handlers; direct/group display+reconciliation totals reach zero; SQL work uses `INBOX_RECONCILER`; no duplicate effect | remove any typed handler, allow generic destructive fallback, check ready-only rather than total, skip a store/lane, originate `ANDROID_PUSH_SERVICE`/relay custody, or ACK pending work -> red | focused serial SQLite |
| TC-374-03 | Invocation binding/generation plus migration/role/physical credential are checked before acquisition where possible and again after teardown | extend entrypoint/runtime tests with barriers | stale input performs zero acquisition; post-open authority mismatch cleans up before Go; same-binding linked credential/role mutation or new generation/account cutover refuses ACK; periodic never consumes a marker | trust WorkRequest input, compare only opaque binding, stale-ACK success, or fabricate periodic marker -> red | focused Dart |
| TC-374-04 | Admission sealing, construction/cancellation crash cuts and exact runner-owned emergency cleanup preserve one owner | new real-process test plus runtime/lease barriers after partial graph, first settlement, callback before/after seal, listener stop, Go quiesce and DB close | seal -> await all admitted work -> final four-store/ledger settlement -> dispose owners -> Go/DB/lease; pre-seal late custody blocks ACK until settled; post-seal offer is synchronously refused to durable retry with no handler/effect/direct-confirm/relay-ACK and retains marker; emergency report comes from same partial instance | accept a post-seal callback, omit final settlement/`GroupMessageListener.stop`, query a new lease in emergency cleanup, release before close, ACK on `finally`, or permit successor behind retained engine -> red | focused serial/process |
| TC-374-05 | Code-ready recovery publication and two distinct retirement modes are exact | update `canonical_runtime_lease_test.dart`; new Kotlin readiness tests | typed native result must echo binding+enabled; same-binding rollback disables/cancels while preserving marker/custody and proves no live owner; logout/switch rotates binding and retires old marker | keep always-false behavior, trust bool-only/wrong binding or flag, add health monitor, preserve old-account marker, delete same-binding marker, or couple opaque cap -> red | focused Dart/Kotlin |
| TC-374-06 | Foreground and headless contenders use one runtime/SQL owner and hand off without loss | production graph test plus `GoRuntimeHostTest`, `CanonicalRuntimeLeaseTest` and worker barriers | exactly one owner/effect; foreground request stops headless at a safe boundary; newer work reruns | two engines/DB writers, force-dispose live owner, or strand new generation behind KEEP -> red | focused Dart/Kotlin race |
| TC-374-07 | The production AOT entrypoint calls the real factory and remains UI/plugin neutral; every recovery path is classified | update `main_bootstrap_boundary_test.dart`, entrypoint test and source-census test | no call to unavailable runner; one factory; no `runApp`/ApplicationRoot/generic listener; incumbent foreground recovery remains | leave dormant call, construct UI bootstrap, add second scheduler, or omit one reason -> red | focused/source guard |
| TC-374-08 | Real deleted-batch service commit/schedule seam runs WorkManager -> headless Dart -> existing SQLCipher v116 -> ledger/effect -> exact marker settlement without an Activity | extend the debug-only H0 broadcast receiver with a small Dart fixture and one pinned runner; do not use an Activity-backed `integration_test` driver | production service and probe call the same commit/schedule owner; eligible direct/group conversations each converge to their exact private card state; process-death retry resumes; marker exact-ACKs; Activity launch count stays zero | seed store/enqueue directly, fake/create DB, launch Activity/manual tap, ACK before reopen, omit a lane/retry, unpinned target or skip -> red | availability-bounded device |

### Test notes

- First create only the compiling API/type skeleton needed to select a semantic
  TC-374 assertion; a compile/load/tool failure is not an accepted RED.
- Parameterize lane and event kind inside TC-374-02 rather than creating four
  modality suites.
- Existing-only DB, SQLite/registry/plugin-global and ownership-race cases run
  serially. Pure parser/readiness/source fixtures may use Flutter concurrency 4.
- Replace, rather than preserve unchanged, the current dormant-entrypoint test
  and the lease test named `opaque install account binding is stable rotates
  and never enables work`; they encode the intentional pre-Plan-374 state.
- The device fixture seeds canonical test custody, then invokes a debug-only
  receiver that calls the same production deleted-batch commit/schedule seam as
  Firebase. It must not write the marker or enqueue WorkManager directly. It
  does not require or claim live FCM/relay delivery.

## Implementation Steps

1. Validate Plan 372 and re-run current Graphify/source grounding. Record the
   exact execution HEAD/tree separately from the Plan-372 tested tree.
2. Add the TC-374-01/03/07 compiling skeleton and record assertion-owned REDs.
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
11. Add/register the exact Android-native host script and no-Activity scenario;
    extend the existing H0 harness rather than create a second orchestrator.
12. Run focused, preservation, curated, device and hygiene gates; record a
    checksum-bound receipt with marker
    `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE`.

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
2. assertion-owned RED, then pure Dart parser/readiness/source tests at
   concurrency 4 and existing-DB/SQLite/process ownership tests serially;
3. focused Kotlin worker/store/scheduler/runtime tests and the registered native
   script; the pure-Dart and Gradle legs may run concurrently, but neither may
   overlap a process-global Dart ledger/registry run;
4. exact preservation sentinels;
5. `completeness-check`, then affected `baseline`, `1to1` and `groups` lanes
   serially because they share Flutter/native/relay resources;
6. one disposable build followed by one explicitly discovered Android target;
   a second target is optional parity, not a closure obligation;
7. analyzer, formatting, diff hygiene and one incremental Graphify refresh.

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
      baseline is recorded without treating this moving Plan-371 worktree as
      evidence.
- [ ] TC-374-01 through TC-374-08 each have an assertion-owned RED and causal
      GREEN; every listed mutation independently re-reds and is reverted.
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
- [ ] Baseline, `1to1` and `groups` curated lanes pass serially.
- [ ] One explicitly discovered Android target runs the bounded automated proof
      from one immutable APK; no available target is policy N/A and a second
      target is optional parity only.
- [ ] No Plan-374 full host/family sweep or credential-dependent real-FCM
      campaign was run or implied.
- [ ] Analyzer, changed+untracked Dart formatting, shell syntax, diff hygiene
      and current Graphify review pass.
- [ ] A checksum-bound receipt records marker
      `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE`, base/frozen
      tree/dirty/Graphify identities, exact logs and device disposition.

The receipt directory also commits `workspace-porcelain-v2.txt.gz` and
`graphify-fingerprint.txt`; the recorded dirty SHA is the decompressed archive
SHA-256 and the fingerprint file contains the exact 16-lowercase-hex value.
Write `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE` once as a
standalone raw receipt line. Plan 375 validates those committed bytes and exact
marker rather than trusting receipt prose.

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

Independent `$tdd-review` result: **PASS after material in-place corrections**.

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
- Gate integrity: PASS. Pure and process-global tests are split; every planned
  selector is counted individually; ten exact preservation tests are real;
  Kotlin includes the Firebase service; shell fences parse under macOS Bash
  3.2; one immutable APK drives the no-Activity proof.
- Operability/economy: PASS. Same-binding rollback differs from account
  rotation, readiness uses typed native read-back, and one Android target is
  sufficient for this non-peer mechanism. Full host is deferred exactly once
  to the completed N07+N08 adapter wave.

## Arbiter Decision

**READY AS A CONTRACT, EXECUTION BLOCKED ON PLAN 372.** Do not create another
headless-foundation plan. Do not expand the device leg to both available
Android classes unless implementation introduces a concrete device-class
counterexample; availability permits targets but does not require redundant
parity. Re-review only if Plan 372 changes the ledger/lock/owner API or current
source grounding is no longer anchored.

## Execution Progress

| Time | Step | RED evidence | GREEN evidence | Refactor / regression | Evidence path |
|---|---|---|---|---|---|
| pending | TC-374-00 prerequisite | Plan-372 receipt absent while Plan 371 is in progress | pending | No production execution authorized | pending |
