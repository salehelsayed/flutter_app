# 372 - GAP-N05 + GAP-N06 Final-Effect Gate And Local Notification Ledger

Status: **POST_EXECUTION_AUDIT_CLOSED / N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE / ONE COMBINED N05+N06 SLICE / CURRENT-DART+SHARED-MECHANISM ONLY / ONE N03-N06 HOST WAVE VERIFIED / DEFAULT-OFF OUTCOME ADMISSION / CROSS-NATIVE ADOPTION OPEN / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec inputs: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §§6, 8 and 9; GAP-N05, GAP-N06 and WP-03 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: execution-ready combined final-effect/ledger implementation slice
Closure tier: host plus existing Flutter plugin fakes; native NSE/FCM adoption remains Plans 373/N08

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Planner using `$tdd-plan` | PRD/GAP N05-N06; Plan 371 contract and moving worktree; `maybeShowNotification`; durable notification ID/content registry; direct/group outboxes, projectors and reconcilers; background handler; v116 outcome owner | N05's final check and N06's record revision must share one effect linearization point. Separate N05 and N06 plans would create either a non-authoritative gate or an unused ledger. | Keep one combined vertical slice; do not create a standalone N05 or N06 plan. |
| 2026-08-15 | Storage/gate verifier | SQLCipher location and v116 registry; App-Group registry/recovery storage; gate arrays and host runner | A DB-v117 ledger would be main-app-only and inaccessible to NSE. Use one additive bounded file-backed logical ledger and keep DB v116. Plan 372 is the one N03-N06 wave boundary, so it owns one aggregate `host-all`, not extra core/feature sweeps. | Freeze the file/state/rollback contract and non-vacuous commands. |
| 2026-08-15 | Dependency verifier | Current Plan-371 source changes and planned receipt marker | Plan 371 is still being implemented; no checksum-bound `evidence/371` receipt exists. Source/API anchors may move before closure. | Keep execution blocked until the exact receipt/tree validates, then re-ground the finalized N04 API before RED. |
| 2026-08-15 | Independent reviewers using `$tdd-review` | Full draft; current registry/claim/tone/SQL owners; canonical binding; direct/group evaluators; literal test/gate commands | The combined boundary passes, but the draft overstated account/native coverage, conflated effect-terminal with SQL-settled state, underspecified ambiguous cancel/recovery, and contained non-runnable selectors/test names. | Apply bounded in-place corrections; do not add a plan, DB migration, lock, scheduler or device harness. |
| 2026-08-15 | Planner/arbiter | Revised plan and exact commands; five review lenses | Claims, causal barriers, bypass classification, crash/rollback state and gate cadence are coherent after correction. Plan 371's future receipt remains the only execution blocker. | Mark contract-ready/prerequisite-blocked; draft Plan 373 only against this frozen contract. |
| 2026-08-16 | Cross-plan reviewer using `$tdd-review` | `RELAY_VERIFIED_UNACKED` native source, relay-to-SQL handoff, TC-372-01/05/06 and receipt contract | A SQL row appearing during `PUBLISHING` cannot prove an OS effect terminal. The final contract now upgrades custody at every non-settled phase while preserving phase/owner/attempt/card state; only `EFFECT_TERMINAL` may replay SQL/v116 and settle. | PASS. Keep the shared transition in Plan 372; Plan 373 consumes it without a second ledger or plan. |
| 2026-08-16 | Dependency re-grounding | Committed Plan-371 receipt/checksum, frozen-tree/ancestry/drift contract, three Plan-370 default-off sentinels, current Graphify TDD query | TC-372-00 passed. Receipt commit `3c7e704e77f9240d62332750db4a6ecd26894b1d`, receipt SHA-256 `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f`, frozen tree `75116f8b1c7cc0cec99f2a72d1410713868d0f23`, dirty snapshot `7f85fe07bd306706895b2a11d5d27431b2bba2405379bfd925db851f94f4fa9b`, and Graphify `a1554310fab6234f` all validate. | Mark execution-ready; rerun the pinned preflight from the clean reviewed planning baseline immediately before causal RED. |

## Problem And Evidence

- Behavior to improve: every Plan-372-adopted authenticated direct/group message or reaction
  presentation, update, cancellation and reconciliation must make its last
  lifecycle/read/delete/policy decision immediately at the serialized OS-effect
  boundary and commit one revisioned local notification state.
- Impact: the current early decision can become stale while claims, tone,
  preview and registry work await. Independent durable owners can each be
  locally correct while a read/deleted event is shown, a newer generation is
  cancelled, or a crash leaves no authoritative recovery owner.
- Confirmed current GAP-N05 cause:
  - `maybeShowNotification` in
    `lib/features/push/application/show_notification_use_case.dart` samples
    visibility near entry and then awaits multiple owners before its native
    callback;
  - `DurableConversationNotificationIdRegistry.replaceContent` serializes
    generation replacement and the native callback under
    `NotificationConversationIds/.coordination.lock`, but it has no current
    visibility/canonical-state/ledger-revision authorizer;
  - `background_message_handler.dart` performs useful direct/group validation
    after showing. A post-show retirement fence cannot prevent the stale alert
    or sound.
- Confirmed current GAP-N06 cause: event/tone claims, stable IDs/content
  generations, v106/v107 display/read/reconciliation custody, v116 completed
  outcomes, iOS request recovery and Android dropped-wake recovery are separate
  stores. No one logical record owns the PRD event/conversation/read/
  presentation/owner/stable-key/lifecycle/revision transition.
- Existing coverage: registry tests prove one file-lock winner and
  generation-safe replace/cancel; direct/group SQL helpers prove exact custody
  completion; Plan 369 proves bounded v116 outcomes; Plan 370 proves the
  default-off wake coordinator; committed Plan 371 provides the one fresh
  visibility reader.
- Missing coverage: final open/background barriers; read/delete/expiry changes
  before effect; main/background/reconciler revision races; crash after prepare,
  during an ambiguous plugin call, and after a ledger terminal but before SQL
  completion; lazy legacy adoption; bounded/future-schema rollback; and a
  production bypass census.
- Refuted finding: a SQLCipher v117 table is not the cross-owner ledger. The
  identity DB lives under the app database directory and is not available to
  the iOS NSE. Adding v117 would create another main-app-only owner and broaden
  account-migration work without satisfying N06.
- Resolved dependency finding: Plan 371's final reader/codec/store APIs and
  checksum-bound receipt are committed. TC-372-00 validates the accepted tree
  and current API grounding; a later material lifecycle/locking drift remains a
  stop-and-replan condition.

## Dependency Contract

Plan 372 is causally downstream of the completed Plan-371 N04 authority, not of
Plan-371 planning prose or an uncommitted implementation tree. Execution
requires all of the following to remain present and valid:

- `Test-Flight-Improv/evidence/371/README.md` and sibling
  `README.md.sha256`;
- exact marker `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE`;
- one frozen tested tree object plus Base/HEAD, dirty-snapshot and Graphify
  identities recorded in the receipt;
- a post-execution audit/closure state whose difference from the frozen tested
  tree contains only Plan-371 evidence/planning/coverage closure documents and
  later Plan-372/373/374/375 planning documents;
- finalized source for one fresh exact `AppVisibilitySnapshot` reader and its
  route/lifecycle authority;
- the Plan-370 outcome capability, producers and drainer still share
  `kWakeOutcomeCoordinatorAdmissionEnabled` and default to `false`.

The accepted Plan-371 dependency identities are pinned as follows:

- receipt commit: `3c7e704e77f9240d62332750db4a6ecd26894b1d`;
- receipt SHA-256:
  `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f`;
- Base HEAD: `9be694a19e4f17973e447f8b98c8167b9881fd74`;
- frozen tested tree: `75116f8b1c7cc0cec99f2a72d1410713868d0f23`;
- dirty snapshot SHA-256:
  `7f85fe07bd306706895b2a11d5d27431b2bba2405379bfd925db851f94f4fa9b`;
- Graphify fingerprint: `a1554310fab6234f`.

Plan 371 transitively binds Plans 370/369 and their N01/N02 predecessors. Do not
repeat all earlier receipt preflights unless the Plan-371 receipt fails to bind
them. N01 S2/B1b, N02 live provider migration, delayed-wake activation, live
Redis/APNs/FCM and release acceptance are not Plan-372 prerequisites.

Run this before authoring any TC-372 RED. It passed during the 2026-08-16
re-grounding and must pass again from the clean reviewed planning baseline:

```bash
(
  set -euo pipefail
  receipt='Test-Flight-Improv/evidence/371/README.md'
  checksum='Test-Flight-Improv/evidence/371/README.md.sha256'
  test -f "$receipt"
  test -f "$checksum"
  (cd Test-Flight-Improv/evidence/371 &&
    shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE' "$receipt"

  base="$(awk -F': ' '/^Base HEAD: / {print $2; exit}' "$receipt")"
  frozen="$(awk -F': ' '/^Frozen tested tree: / {print $2; exit}' "$receipt")"
  dirty="$(awk -F': ' '/^Dirty snapshot SHA-256: / {print $2; exit}' "$receipt")"
  graph="$(awk -F': ' '/^Graphify fingerprint: / {print $2; exit}' "$receipt")"
  [[ "$base" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph" =~ ^[0-9a-f]{16}$ ]]
  test "$base" = '9be694a19e4f17973e447f8b98c8167b9881fd74'
  test "$frozen" = '75116f8b1c7cc0cec99f2a72d1410713868d0f23'
  test "$dirty" = '7f85fe07bd306706895b2a11d5d27431b2bba2405379bfd925db851f94f4fa9b'
  test "$graph" = 'a1554310fab6234f'
  git cat-file -e "${base}^{commit}"
  git cat-file -e "${frozen}^{tree}"

  # A self-consistent uncommitted pair is not durable dependency evidence.
  receipt_commit="$(git log -n 1 --format=%H -- "$receipt")"
  test "$receipt_commit" = '3c7e704e77f9240d62332750db4a6ecd26894b1d'
  git cat-file -e "${receipt_commit}^{commit}"
  git merge-base --is-ancestor "$base" "$receipt_commit"
  cmp -s <(git show "${receipt_commit}:${receipt}") "$receipt"
  cmp -s <(git show "${receipt_commit}:${checksum}") "$checksum"
  test "$(shasum -a 256 "$receipt" | awk '{print $1}')" = \
    'dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f'

  # The receipt/closure commit may add documentation over the tested tree, but
  # it must not contain a second untested product transaction.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/371-gap-n04-*|\
      Test-Flight-Improv/evidence/371/*|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Untested Plan-371 closure drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(git diff --name-only "$frozen" "$receipt_commit")

  # The tested Plan-371 tree may be followed only by durable closure/planning
  # documents before Plan-372 production work starts.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/371-gap-n04-*|\
      Test-Flight-Improv/372-gap-n05-n06-*|\
      Test-Flight-Improv/373-gap-n07-*|\
      Test-Flight-Improv/374-gap-n08-*|\
      Test-Flight-Improv/375-gap-n08-*|\
      Test-Flight-Improv/evidence/371/*|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Unexpected post-371 drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(
    {
      git diff --name-only "$frozen" -- .
      git ls-files --others --exclude-standard
    } | sort -u
  )

  flutter test test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    --plain-name 'TC-370-05 opaque outcome uses strict all-relay completion'
  flutter test \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    --plain-name 'TC-370-07 production composes one default-off outcome admission and one shared drain callback'
  flutter test \
    test/core/notifications/notification_completed_outcome_drain_composition_test.dart \
    --plain-name 'TC-370-07 one persisted outcome drainer coalesces and retains partial relay failure across reopen'
)
```

The parser intentionally consumes the receipt's machine-readable identity
block; do not switch back to presentation-table headings. If that block changes,
stop and re-ground the exact accepted format rather than weakening or bypassing
an identity.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `a1554310fab6234f`; current and anchored at
  the committed final Plan-371 source during the Plan-372 re-grounding pass.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 372 combined GAP-N05 GAP-N06 LocalNotificationRecord final pre-publication lifecycle read delete policy ledger revision CAS maybeShowNotification DurableConversationNotificationIdRegistry direct group reconciler v116" --profile tdd --budget 700`.
- Anchors: `maybeShowNotification` ->
  `lib/features/push/application/show_notification_use_case.dart`;
  `DurableConversationNotificationIdRegistry` ->
  `lib/core/notifications/durable_conversation_notification_id_registry.dart`.
- Surfaced proof/gate files: show-use-case, durable registry, direct/group read
  projectors, projection owners, background handler, v116 outcome, and both
  curated messaging arrays.
- Graph gaps requiring source search: downstream native adapters remain future
  work. Targeted source inspection supplies native handoff evidence when those
  plans execute.
- Reuse rule: execution may reuse these anchors only while the dependency
  preflight and a current `--profile tdd` query still return anchored context.

## Delivery Structure Decision

This is one combined N05+N06 plan because the two gaps share one indivisible
rollback boundary:

1. N06 supplies the durable record, expected revision and recovery state.
2. N05 uses that exact revision at the final serialized effect boundary.
3. The same transition commits the presentation owner/result that recovery and
   optional v116 outcome delivery consume.

A standalone N05 plan would invent a temporary lock/state owner. A standalone
N06 foundation plan would leave a ledger with no authoritative effect adopter.
Do not split by direct/group, message/reaction, main/background isolate, or
platform. Plan 373 and N08 are thin native adapters to this frozen contract,
not more N06 foundation plans.

## Authority And State Contract

### One logical record, separate durable file, one effect lock

Add one identifier-only `LocalNotificationRecordV1` store in the same private
notification namespace as the durable stable-ID/content registry:

- data file: `local_notification_ledger_v1.json`;
- data is separate from `.owner`, `.content-kind`, Plan-371 visibility, iOS
  recovery, Android dropped-wake, tone/event claims and SQL outboxes because
  those projections have different retention and rollback lifetimes;
- all Dart main/background/reconciler effects coordinate through the existing
  `NotificationConversationIds/.coordination.lock`. Evolve the durable
  registry/coordinator with internal unlocked helpers; never recursively call a
  public lock-taking registry method;
- if source constraints make safe reuse of that lock impossible, stop and
  re-review one explicit `ledger -> registry` lock order. Do not silently add a
  second unordered lock.

The envelope contains only:

```text
schemaVersion: 1
storeRevision: positive signed Int64
opaqueBinding: exact canonical `v1:<64-lowercase-hex>` value
claimsSuspended: boolean
records: map<64-lowercase-hex eventCorrelation, LocalNotificationRecordV1>
```

Each record contains the PRD fields plus only the minimum crash state:

```text
eventCorrelation: existing Plan-369 wake correlation digest
conversationDigest: exact Plan-371 AppVisibilityConversationIdentity.digest
producerKind: direct_message | direct_reaction | group_message | group_reaction
sourceCustody: SQL_READY | RELAY_VERIFIED_UNACKED
readState: UNREAD | READ
presentationState:
  NOT_EVALUATED | IN_CHAT | OS_POSTED | SUPPRESSED_POLICY | CANCELLED
presentationOwner:
  MAIN_APP | IOS_NSE | ANDROID_PUSH_SERVICE | INBOX_RECONCILER
notificationId: nullable nonnegative signed 31-bit stable ID
contentGeneration: nullable nonempty exact generation
lastEvaluatedLifecycle: FOREGROUND_ACTIVE | INACTIVE | BACKGROUND | UNKNOWN
visibilityRevision / lifecycleGeneration: positive signed Int64 or null
effectPhase: READY | CLAIMED | PUBLISHING | EFFECT_TERMINAL | SETTLED
attemptKind: POST_OR_UPDATE | CANCEL while CLAIMED/PUBLISHING, otherwise null
effectToken: 64-lowercase-hex while CLAIMED/PUBLISHING, otherwise null
revision: positive signed Int64
createdAtUtc / updatedAtUtc: canonical UTC strings
terminalAtUtc: null before EFFECT_TERMINAL, required afterward
settledAtUtc: null before SETTLED, required at SETTLED
```

- Reuse Plan 369's authenticated event-key selector and physical-recipient
  correlation. Do not hash a bounded display ID or locally remint identity.
- Current Dart owners create only `SQL_READY`. The shared state table also
  freezes the one downstream-native input: `RELAY_VERIFIED_UNACKED` requires an
  exact authenticated physical-recipient/event correlation and a strict
  still-pending relay row. It may never be inferred from APNs/FCM, a card ID,
  raw request ID or unverified provider metadata.
- Reuse the exact `v1:` opaque canonical runtime account/installation binding;
  do not silently strip its version or hash it again. The current coordinator
  is composed only with Android's runtime lease. Extract its secure
  installation/binding resolver into a platform-neutral owner, keep the Android
  lease optional, and publish/read-back the same opaque binding through the
  existing iOS shared Keychain access group for Plan 373. Every ledger read or
  mutation receives the current binding and rejects a mismatch before it may
  suppress or perform an effect.
- Wire one ledger rebind callback beside the incumbent pending-overlay callback
  for startup, account publish/switch and retire/logout. Suspend claims before
  account cleanup; after the secure binding commit, publish one empty store for
  the new binding. Cleanup is best effort: a crash leaves old bytes inert
  because every operation compares the current secure binding.
- Persist no raw peer, group, event, account, route, provider or content bytes;
  fixed disposition codes only may enter logs. `readState` is monotonic, but a
  dismiss/activation cancellation never implies `READ`.
- Freeze a language-neutral fixture even though Plan 372 has only Dart effect
  writers. Plan 373's Swift adapter and N08's Android adapter must consume the
  same bytes/state table rather than redefine it.
- `storeRevision`, record `revision`, content generation and effect token are
  all checked on mutation. Signed-Int64 overflow, unknown enum, unknown key,
  malformed/future schema, binding mismatch or I/O uncertainty grants no
  suppression or completed outcome. A canonical private-file writer plus exact
  known-key validation is sufficient; do not invent a custom duplicate-key JSON
  parser.

### State and effect rules

| Starting authority | Final current facts | Effect/state |
|---|---|---|
| `NOT_EVALUATED`/retry and exact fresh foreground A | exact conversation A, unread/not deleted, current generation/revision | no native post; durably `IN_CHAT/EFFECT_TERMINAL`; SQL A records the terminal while retaining READY, ledger becomes `SETTLED`, then SQL B retires READY; return approved `inChat` only to the already-default-off producer |
| Initial A visible, then background before final gate | fresh final snapshot is background | native post/update once; `OS_POSTED/EFFECT_TERMINAL`, SQL A, `SETTLED`, then exact SQL B retirement |
| Initial background, then exact A visible before final gate | fresh final snapshot is exact A | zero native effect; `IN_CHAT/EFFECT_TERMINAL`, SQL A, `SETTLED`, then exact SQL B retirement |
| Canonical read, deleted, expired or exact incumbent policy suppresses | proof is current at the final gate | zero post; `CANCELLED` or `SUPPRESSED_POLICY` effect-terminal; policy outcome remains unadvertised until N11 |
| Missing/stale/corrupt visibility | no safe suppression proof | treat as notification-eligible; never infer `IN_CHAT` |
| Stale record revision, effect token, notification ID or content generation | newer authority exists | zero effect and retry/consume the newer state |
| Native post/update callback throws or process dies after `PUBLISHING` | OS acceptance is ambiguous | retain `PUBLISHING`; emit no v116 outcome and never audibly replay. Exact active ID plus exact on-disk generation may prove `OS_POSTED`; otherwise issue only a silent same-ID repair or retain custody |
| Native cancel throws after entry | the prior card may still exist | keep the prior `OS_POSTED` presentation state with the exact CANCEL attempt; do not mark `CANCELLED`; retry the same generation silently through reconciliation |
| Ledger is busy/full/unwritable | no durable claim | zero new effect, keep v106/v107 custody and return retryable; do not invent a legacy completed outcome |
| Main/outbox/reconciler canonical lookup is unknown | no materialized authority | zero effect and retry; never turn absence/read failure into suppression |
| Authenticated push arrives before inbox materialization without an exact content-authenticated event/correlation | push/provider ownership is confirmed but event authority is unknown | retain staged push/provider custody and retry; do not create a ledger result or synthetic event |
| Plan-373/N08 adapter has an exact content-authenticated relay row, physical binding and event correlation but no SQL row | source custody is `RELAY_VERIFIED_UNACKED`; relay row remains pending | the native adapter may CAS `READY -> CLAIMED -> PUBLISHING -> EFFECT_TERMINAL` under the shared revision/effect lock, using current binding/visibility and its strict projected policy. It cannot mark `SETTLED`, emit v116 or delete/ACK source custody |
| Main app later materializes the same exact relay correlation in v106/v107 | existing non-settled ledger row is `RELAY_VERIFIED_UNACKED` at any effect phase | first commit the matching v106/v107 row outside the file lock; then under `.coordination.lock` exact-CAS only `sourceCustody` and revisions to `SQL_READY`, preserving phase, owner, attempt/token, presentation, notification ID/generation and terminal timestamps. `READY` may claim normally; `CLAIMED` keeps its owner/60-second recovery; `PUBLISHING` remains ambiguous and cannot delete SQL, emit v116 or settle; only `EFFECT_TERMINAL` may run SQL A and become `SETTLED`, after which SQL B retires exact READY without another effect. Reverse custody transition or mismatch is refused |

Owner values are not inferred from producer kind: current foreground/main
projection writes `MAIN_APP`; the authenticated Android FlutterFire background
owner writes `ANDROID_PUSH_SERVICE`; direct/group reconcilers write
`INBOX_RECONCILER`. `IOS_NSE` is reserved for Plan 373.

There is no SQL/file distributed transaction. The current Dart sequence is:

1. canonical v106/v107 READY custody and legacy claim/generation inputs exist;
2. acquire the incumbent registry coordination lock, validate the current
   secure binding, ledger/content revision and an initial canonical snapshot,
   then durably CAS `READY -> CLAIMED`;
3. prepare the exact content generation and existing event/tone projections,
   then durably arm `PUBLISHING` with attempt kind/token;
4. at a controlled post-`PUBLISHING` barrier, re-read Plan-371 visibility,
   canonical SQL read/delete/expiry/policy facts and every expected revision.
   If they changed, make the exact no-effect transition. If they permit the
   effect, invoke the native callback immediately with no intervening await;
5. persist `EFFECT_TERMINAL` or retain the honest ambiguous attempt, then
   release the file lock;
6. run exact SQL transaction A, which writes/verifies the typed canonical
   terminal and any enabled v116 outcome while retaining the exact READY row;
7. reacquire the lock and CAS the same record to `SETTLED` only after SQL A
   succeeds;
8. run exact SQL transaction B, which deletes that unchanged READY custody and
   atomically enqueues the incumbent reconciliation trigger. Replay from either
   `EFFECT_TERMINAL` or `SETTLED` repeats only the missing idempotent SQL
   handoff/retirement step, never the OS effect. This two-step SQL custody is
   required because group reaction correlations are non-invertible after v106
   deletion and because a process may stop after ledger settlement.

The language-neutral downstream-native variant begins from an exactly verified
`RELAY_VERIFIED_UNACKED` row rather than step 1. It uses the same revision/
effect lock through `EFFECT_TERMINAL`, keeps relay custody untouched and stops
there. Fresh exact visibility or an exact current projected policy may choose a
no-effect result; unknown SQL read/delete/policy never suppresses and fails
toward notification. Only main-app materialization of the same correlation may
first commit matching v106/v107 custody outside the file lock and then CAS
`sourceCustody` to `SQL_READY` under `.coordination.lock`. That CAS preserves
every effect field and phase: `READY` may be claimed normally, `CLAIMED`
respects the incumbent owner and recovery horizon, `PUBLISHING` remains
ambiguous on its existing owner-specific repair path, and only
`EFFECT_TERMINAL` executes steps 6--8 without another audible effect and
settles. The reverse transition is illegal. Plan 372 supplies the transition
vectors/API but no NSE/FCM caller.

Never hold a SQLite transaction while acquiring or holding the file lock. The
single lock order at native publication is registry coordination lock -> event
claim transition -> tone transition -> native effect; provisional claim/tone
reservations may be prepared earlier, but no inverse owner may enter the
registry while holding either lock. Public lock-taking registry methods are
forbidden from the lock-held implementation; use private lock-held helpers.

A crash after step 5 is repaired by replay completing SQL/v116 and settling
without re-alert. A crash in step 4 never lies as `OS_POSTED`. On Android,
active-notification inventory supplies only the stable ID; exact generation is
proved by that ID plus the current on-disk content marker and the mandatory
retire-old -> activate-marker -> show ordering under the same lock. A mismatched
marker cannot terminalize the attempt.

### Bounds, migration and rollback

- Maximum 512 records and seven-day settled retention, matching the existing
  bounded outcome horizon. Prune only expired `SETTLED` rows; a superseded
  non-current generation must finish its effect-terminal/SQL/settled handoff
  before it becomes prune-eligible. Canonical SQL, not historical ledger rows,
  owns unread truth; do not retain every old unread terminal forever. Never
  directly evict `CLAIMED`, `PUBLISHING`, `EFFECT_TERMINAL`, or current
  authority.
- `CLAIMED` uses the incumbent 60-second pending-claim horizon. Recovery of
  `PUBLISHING` runs on the current retry/startup/reconciliation triggers: exact
  active card+marker terminalizes, still-eligible absence receives only a
  silent same-ID repair, and canonical read/delete/expiry terminalizes without
  posting. One inventory-unavailable attempt retains custody for the incumbent
  bounded retry delay; on the next existing trigger, continued inventory
  unavailability cannot strand capacity: an exact current marker plus eligible
  `POST_OR_UPDATE` runs a silent same-ID repair, while read/delete/expiry or a
  pending `CANCEL` retries exact-ID cancellation. Only callback success reaches
  `EFFECT_TERMINAL`; a mismatched marker remains retryable. Ledger-storage
  outage itself retains authority until storage recovers. No new scheduler is
  added and no unresolved attempt is audibly reclaimed.
- No global backfill. Lazily seed/adopt a record only when authenticated typed
  event identity, canonical direct/group custody and exact stable ID/content
  generation agree. Partial legacy evidence remains legacy and wake-required.
- Main-app repair may quarantine one malformed supported-v1 file and rebuild;
  future-version bytes are immutable. A read-only native consumer must never
  quarantine or downgrade bytes.
- Old builds ignore the additive ledger and retain the current stable-ID,
  generation, claim and recovery behavior. Plan 372 must dual-maintain those
  legacy projections until WP-07/N12 records the explicit minimum-client
  retirement gate; it must not delete or repurpose them.
- Account logout/switch suspends claims and rebinds to an empty ledger around
  the canonical secure-binding commit; copied/restored ledger bytes never
  become authoritative without the matching current binding. Do not claim a
  platform backup exclusion that Plan 372 does not natively prove. Account
  migration does not intentionally export/import the file. DB schema and the
  production migration registry remain exactly v116.
- Preserve legacy projections until WP-07/N12 records the explicit minimum-
  client retirement gate; do not invent an unnamed time window.

## Scope Contract And Guard

In scope:

- `LocalNotificationRecordV1`, strict fixture/codec, bounded durable store and
  revisioned state machine;
- the final-effect coordinator inside the incumbent stable-ID/content
  serialization boundary;
- current authenticated direct/group message/reaction main-app, background
  isolate and reconciler presentation/update/cancel paths for which the exact
  Plan-369 physical-installation/event correlation is available before effect;
- the language-neutral `RELAY_VERIFIED_UNACKED -> SQL_READY` transition and
  no-ACK/no-v116/no-SETTLED rules required by downstream Plan-373/N08 adapters;
- exact read/delete/expiry and existing typed policy rereads at that boundary;
- one shared direct row-level tri-state canonical evaluator, reusing
  `directReactionTargetAllowsNotificationDisplay`, plus a generalized name/use
  for the incumbent pure group post-show evaluator. Main, background and
  reconciler owners must not carry divergent hidden/private/deletion rules;
- v106/v107 terminal handoff and existing default-off v116 outcome mapping;
- lazy legacy adoption, crash repair, the cross-platform opaque binding resolver
  and rollback mirrors.

Must preserve:

- stable-ID owner tombstones and content-generation ABA safety;
- message/reaction and direct/group lane isolation;
- tone/event claim ambiguity rules;
- v106/v107 source custody until a durable terminal;
- v116 idempotency and default-off producer/drainer/capability composition;
- generic/social notifications without authenticated event identity remain
  outside the ledger and cannot mint synthetic event IDs;
- notification-tap/initial-launch exact-generation dismissal, route activation
  cleanup and delivered-card read/mute behavior remain N11 compatibility paths;
  global `clearAll`/account-reset cleanup is not an event transition in this
  slice. TC-372-07 classifies these rather than claiming universal cancel
  adoption.

Hard `Do not`:

- Do not add DB v117, a second SQL/file ledger, scheduler, queue, lifecycle
  authority, stable-ID allocator, notification plugin, or activation flag.
- Do not implement NSE inbox retrieval/rendering (Plan 373), Android FCM/
  WorkManager adoption (N08), read-marking rules/activation cleanup/mute-badge
  convergence (N11), or live rollout/device acceptance (N12/WP-07).
- Do not promise mathematically exactly-once OS presentation. The contract is
  one durable owner/CAS plus stable-ID collapse and explicit ambiguous recovery.
- Do not let a native effect, v116 outcome, SQL custody delete, or log imply a
  terminal state that the durable ledger did not record.

Deferred / accepted difference:

- iOS NSE storage/reader/effect adoption -> Plan 373;
- Android service/WorkManager ledger adoption -> N08;
- an authenticated Dart background path that cannot resolve the raw Plan-369
  producer event key, physical installation or group logical-delivery identity
  before effect stays provider/custody-owned and is explicitly deferred; it may
  not substitute a card ID, bounded claim ID or message alias;
- new policy/read/activation semantics and delivered-card cleanup -> N11;
- provider capability activation, rich retirement, live Apple/Android evidence
  and release acceptance -> WP-07/N12.

Consequently Plan 372 may close the N05/current-Dart plus shared N06 mechanism
marker only. GAP-N06/A-27 cross-native closure additionally requires Plan 373
and N08 to adopt the same fixture/state machine; this is a dependency, not an
extra N06 plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-372-00 | Plan 371 is checksum/frozen-tree complete and the paired wake-outcome seam remains default-off | dependency preflight and three exact Plan-370 sentinels | Host / Git objects, committed receipt, real source composition | GREEN at re-grounding: exact identities and all three sentinels validate; rerun before any RED | Remove marker, alter tested tree, or flip one admission consumer -> preflight/sentinel red | Literal dependency gate; no new registration |
| TC-372-01 | One strict identifier-only record/transition contract rejects illegal, stale and privacy-bearing states | `test/core/notifications/local_notification_ledger_test.dart::TC-372-01 v1 codec and state machine accept only legal monotonic transitions` | Host Dart / shared JSON fixture, exhaustive state table including native-source vectors | After a minimal compiling API shell, semantic RED: inert transition logic cannot satisfy vectors -> legal signed-Int64, `SQL_READY` and exact `RELAY_VERIFIED_UNACKED` effect/handoff transitions round-trip; relay-to-SQL upgrade preserves all four non-settled phases; illegal downgrade/relay-settled states fail | Remove revision/source-custody/phase-preservation guard, settle/emit from relay-only custody, accept raw social field/future enum, or conflate `PUBLISHING`, `EFFECT_TERMINAL` and `SETTLED` -> red | New shared core test in both curated arrays and `ONE_TO_ONE_HOST_TESTS`; auto host discovery |
| TC-372-02 | File store and binding lifecycle are atomic, bound, reopen-safe and rollback-safe without DB v117 | same file `::TC-372-02 atomic store binding rebind and bounds preserve current authority and future bytes` | Host Dart / real temp directory, fault-injected rename/fsync, real coordinator with secure/shared-Keychain fakes | No ledger/iOS binding owner -> old-or-new whole file; exact `v1:` comparison; startup/switch/logout rebind; corrupt-v1 repair; future bytes unchanged; only settled pruning; copied/migrated bytes inert; DB 116 | Split fields, rehash binding, skip one rebind trigger, transfer rows, prune unresolved/current, or bump DB -> red | Same shared test plus exact migration/export exclusion; no device/SQL migration gate |
| TC-372-03 | The last visibility decision occurs after durable publication arming and immediately before effect for direct/group message/reaction | `test/core/notifications/local_notification_final_effect_test.dart::TC-372-03 final visibility barrier chooses exactly one in-chat or OS-posted effect`; `show_notification_use_case_test.dart::TC-372-03b early visibility is preparation only and final gate owns the result` | Host Flutter / parameterized four producers, Plan-371 fake reader, post-`PUBLISHING` native-call barrier | Current early snapshot can terminally suppress/go stale -> mutate at the final barrier: A-visible then background posts once; background then A-visible posts zero; no intervening await/post-then-cancel | Decide before barrier, omit one producer, retain early terminal return, accept stale/unknown as in-chat, or await after final read -> red | New shared core test in both curated arrays/host inventory; show-use-case integration in both lanes |
| TC-372-04 | Shared direct/group tri-state evaluators reread read/delete/expiry/current-policy plus record/content generation at the post-`PUBLISHING` barrier | same file `::TC-372-04 final canonical facts and revision CAS prevent resurrection and stale cancellation` | Host Flutter + real SQLite v106/v107 helpers, two controlled owners | Current paths diverge and validate after show -> commit mutation at final barrier: zero show, exact terminal/retry, later sibling/generation survives; unknown retries | Cache SQL facts, omit hidden/private target rule, drop expected ledger/content revision, cancel by conversation only, or map unknown to suppression -> red | Shared test plus exact direct/group read/reconciler sentinels |
| TC-372-05 | Main isolate, Android background isolate and reconciler converge through one lock/owner, including platform-realistic ambiguity | `test/core/notifications/local_notification_projection_convergence_test.dart::TC-372-05 one claim owner and deterministic publishing recovery across isolate arrival orders`; `durable_conversation_notification_id_registry_test.dart::TC-372-05b one coordination lock rejects reentrant and inverse acquisition` | Host Dart / real temp files/flock, spawned isolate, Android-style active-ID inventory plus on-disk marker | Separate stores can disagree -> exactly one normal effect; crash cuts before call/old cancel/marker activation/native return/effect terminal converge; materialization racing a native claim upgrades custody but preserves phase/owner and one effect winner; repeated inventory failure becomes silent same-ID repair/exact cancel through an existing trigger, never fake generation or audible replay | Remove flock/CAS, trust active ID without marker, change phase/owner during custody upgrade, retain inventory-unavailable `PUBLISHING` forever, reenter a public method, invert lock order, or let stale reconciler overwrite g2 -> red | Shared core/convergence tests; serial because process-global/plugin fixtures |
| TC-372-06 | `EFFECT_TERMINAL` replays exact SQL/v116 handoff and becomes `SETTLED` without repeating an OS effect | `local_notification_projection_convergence_test.dart::TC-372-06 effect-terminal replay settles direct and group custody once and emits only approved enabled outcome` | Host Flutter + real SQLite direct/group rows, producer flag on/off, four-phase relay-only-to-SQL upgrade vectors | Existing mapping recognizes mainly `osPosted` -> `IN_CHAT`/`OS_POSTED` map exactly when enabled; policy stays reserved; crashes before/after SQL A, ledger settlement and SQL B converge idempotently with READY revision unchanged; exact effect-terminal relay upgrade settles; upgraded `READY`/`CLAIMED` continue normally and upgraded `PUBLISHING` remains ambiguous with no SQL delete/v116/settle | Delete READY before effect terminal or before settlement, revise retained READY after settlement, prune before settled, emit/settle upgraded `PUBLISHING` or relay-only custody, duplicate v116, ignore flag, or re-alert replay -> red | Shared test plus current direct/group outbox wiring suites; both curated lanes |
| TC-372-07 | Every adopted authenticated production effect resolves the raw correlation and uses the final coordinator with exact owner; exceptions remain explicit | `test/core/notifications/local_notification_ledger_wiring_test.dart::TC-372-07a adopted direct group main background and reconciler effects have one gateway owner and correlation`; `background_message_handler_test.dart::TC-372-07b authenticated background effect authorizes before native entry` | Host source-AST plus composition fakes and real background SQL reader; literal post-Plan-371 census | Current background/raw paths show then validate -> one allowlisted gateway; owner mapping exact; generic/unanchored/tap/activation/global-clear/N07/N08 exceptions cannot synthesize identity | Restore one post-show-only effect, use bounded card/message alias, omit owner, or route an explicit exception into ledger -> red | Shared wiring in both arrays; exact background test in affected lanes |
| TC-372-08 | Legacy generation/tone/recent/recovery projections, lazy re-upgrade and lane/installation isolation survive additive adoption | `local_notification_ledger_test.dart::TC-372-08 legacy projection lazy adoption rebind and future rollback remain safe`; exact preservation bundle | Host real temp files/SQLite/plugin fakes | Old build may overwrite v1 marker without ledger -> new build detects generation mismatch, preserves legacy claim/content files, lazily readopts only exact authority; account rebind empty; no cross-device/lane damage | Remove legacy mirror, treat old marker as current ledger, share correlation across physical devices, cancelAll, or reuse sibling generation -> red | Focused test plus exact 12-test bundle and one N03-N06 wave `host-all` |

### Test Notes

- TC-372-03 uses one table over four authenticated producer kinds. The
  discriminator is native effect count plus exact final presentation state;
  `IN_CHAT` and `OS_POSTED` are not interchangeable successes.
- TC-372-04 changes canonical state only after construction has reached a
  controlled post-`PUBLISHING` pre-callback barrier. A mutation before that
  point, or a post-show cancellation, is not the required RED/GREEN proof.
- TC-372-05 cuts after claim, old-card cancel, marker activation, native entry,
  native return and effect-terminal persistence. Android proof uses active ID
  plus the real disk marker, never a fake generation returned by the OS.
- TC-372-07 must regenerate its literal caller census from the accepted
  Plan-371 tree. Notification-open route dedupe, mailbox-wide recovery and
  unanchored social alerts are classified, not silently migrated.
- TC-372-01/06 freeze the downstream-native relay-custody transition only. No
  NSE/FCM fetch, decrypt, renderer or capability is added here; Plan 373/N08
  must independently prove that their row is content-authenticated and remains
  un-ACKed before invoking it.

## Implementation Steps

1. Re-run TC-372-00 and record the pinned Plan-371 receipt SHA,
   base/frozen/dirty/Graphify identities and exact current N04 reader symbols.
   Stop if an identity changes, a sentinel fails or non-document drift exists
   after its frozen tree.
2. Refresh Graphify TDD context. Regenerate the production effect/cancel census
   from source and pin the authenticated adopters plus explicit generic/N07/N08
   exclusions in TC-372-07 before editing production.
3. Add the shared v1 fixture, minimal compiling record/API shell and TC-372-01
   assertion. Keep the shell deliberately inert, then record one selected
   semantic assertion RED; missing-symbol/compile/load/tool failure is not
   causal RED. Freeze both `SQL_READY` and exact `RELAY_VERIFIED_UNACKED`
   vectors; the latter has no production caller in Plan 372.
4. Add the separate bounded ledger file and atomic store beside the durable
   content registry. Factor the exact versioned opaque binding resolver for all
   mobile runtimes, add the ledger-rebind callback/shared-iOS-Keychain
   projection, and reuse the existing coordination lock. Add supported-v1
   repair, future-schema preservation, capacity/TTL and binding tests. Keep
   DB/migration version 116.
5. Evolve the durable content registry/coordinator with one non-reentrant final
   effect API and private lock-held helpers. Inside its existing lock, compare
   record/content revisions, persist `CLAIMED`/`PUBLISHING`, repeat visibility
   and canonical-state reads at the last barrier, then invoke the callback with
   no intervening await. Publish `EFFECT_TERMINAL` or retain the exact
   post/update/cancel ambiguity. Stop if implementation reenters a public
   registry method, inverts registry->claim->tone order, or overlaps a SQLite
   transaction with the file lock.
6. Move `maybeShowNotification`'s same-chat result to the final authorizer. The
   early snapshot may only guide non-authoritative preparation; it cannot
   terminally suppress. Adopt direct/group message/reaction projection,
   replacement and cancellation paths.
7. Extract the one direct tri-state evaluator and generalize/reuse the incumbent
   group evaluator across main/background/reconciler readers. Move authenticated
   background validation before effect. After their existing SQL mutation
   commits, current read/delete/policy projectors enter the ledger coordinator
   without holding a SQL transaction, advance the exact record revision and
   conditionally cancel the exact generation. Leave unanchored generic/social,
   tap/activation and global-clear paths explicitly classified and
   outcome-ineligible.
8. Sequence custody honestly: `EFFECT_TERMINAL`, SQL transaction A
   (terminal/v116 while retaining READY), `SETTLED`, then SQL transaction B
   (exact READY retirement plus reconciliation). Add replay repair at every
   process cut, the exact relay-only-to-SQL upgrade vector, and
   platform-realistic `PUBLISHING` recovery. Relay-only custody can reach effect
   terminal but never ACK/v116/settle before upgrade; ambiguous cancel retains
   prior `OS_POSTED` until the exact cancel succeeds.
9. Preserve legacy ID/content/tone/claim/recovery mirrors, lazy re-upgrade and
   binding-mismatch rollback behavior through the explicit WP-07/N12 retirement
   gate. Add no global backfill, native renderer or activation.
10. Register new shared tests exactly once in `ONE_TO_ONE_TESTS`, `GROUP_TESTS`
    and `ONE_TO_ONE_HOST_TESTS`. Run focused and preservation bundles, then the
    curated `1to1` and `groups` lanes serially.
11. Run the single N03-N06 aggregate `host-all` with batched Flutter concurrency
    four. Do not also run `core-host-all` or `feature-host-all`. Refresh the
    architecture graph, run analyzer/format/hygiene, audit final-source bypasses,
    then create a checksum-bound Plan-372 receipt.

## Risks And Blind Spots

- Cross-store atomicity fiction -> TC-372-05/06 retain SQL custody until a
  durable ledger terminal and replay the handoff; there is no SQL/file commit
  claim.
- Relay-only native authority spoof -> the shared transition accepts only the
  exact typed physical-recipient/event correlation and remains unacknowledged/
  unsettled; Plan 373/N08 own content-authentication tests and the later main-
  app SQL upgrade must match the same correlation.
- Re-entrant/deadlocking registry work -> one incumbent effect lock, internal
  unlocked helpers and explicit stop condition; no unordered second lock.
- OS callback ambiguity -> `PUBLISHING` is not success. Android recovery uses
  active stable ID plus the exact disk marker; absence permits only silent
  same-ID repair, and cancel ambiguity retains prior `OS_POSTED`.
- Read/delete or visibility changes during construction -> TC-372-03/04 place
  mutations at the final barrier and assert zero stale effect/newer damage.
- One stable conversation card with multiple event rows -> replacement
  terminalizes the prior current generation without deleting sibling event
  history; TC-372-04/05 cover both arrival orders.
- Account/reinstall ambiguity -> every operation compares the current exact
  `v1:` secure binding; copied/restored bytes are inert and cleanup need not be
  cross-store atomic.
- Future binary/rollback -> future schema is immutable and legacy projections
  remain dual-maintained through the named WP-07/N12 retirement gate.
- Ledger exhaustion -> only expired settled/superseded rows prune; current and
  unresolved rows never evict; custody remains retryable and no false outcome
  is emitted.
- Sibling-surface consistency -> TC-372-07 covers only exact-correlation
  main/Android-background/reconciler adopters and classifies the rest; N07/N08
  remain required cross-native adapters.
- Destructive-action side effects -> exact notification ID, generation, event
  correlation and record revision are all required; `cancelAll` is forbidden.

## Gate Cadence

- Per-plan causal closure: exact dependency preflight; focused TC-372 Dart
  tests; exact registry/read/outbox preservation; affected curated `1to1` and
  `groups` lanes; analyzer/format/hygiene/Graphify.
- Parallelism: isolated focused Dart files use `--concurrency=4`. Registry,
  plugin-channel, real-SQLite and isolate/flock cases run in one serial bundle.
  The two curated lanes run serially because their Flutter/relay/Go resources
  overlap.
- Aggregate exception: Plan 372 completes the planned N03-N06 dependency wave,
  so it runs the one wave-level full `host-all` after all per-plan gates. This is
  not a default per-plan sweep. `--batch-flutter --concurrency 4` is used to
  bound runtime.
- Do not also run core/feature family sweeps; the aggregate host run subsumes
  them. Plan 373 must not repeat full host-all. Final WP-07 runs it once again.
- Device/native: none. N05's current Flutter effect boundary is causally proved
  with native/plugin fakes; iOS NSE and Android service real adapters are N07/
  N08, and physical Apple acceptance is N12.

## Acceptance Gates

```bash
# 0. Snapshot only. Plan 371 is committed; before RED the worktree may contain
# only the reviewed successor-planning documents allowlisted by TC-372-00.
git status --short

# 1. Run the exact Dependency Contract subshell above. It must pass before RED.

# 2. After authoring TC-372-01, its fixture and only the minimal compiling API
# shell, prove one selected semantic assertion RED. Missing-symbol/file,
# compile/load/tool/teardown failure is not RED.
plan372_gate_dir="$(mktemp -d "${TMPDIR:-/tmp}/plan372-gates.XXXXXX")"
set +e
flutter test test/core/notifications/local_notification_ledger_test.dart \
  --machine \
  --plain-name 'TC-372-01 v1 codec and state machine accept only legal monotonic transitions' \
  >"$plan372_gate_dir/red.json" 2>"$plan372_gate_dir/red.stderr"
red_status=$?
set -e
test "$red_status" -ne 0
red_name='TC-372-01 v1 codec and state machine accept only legal monotonic transitions'
test "$(jq -s --arg name "$red_name" '[.[] | objects | select(.type == "testStart" and (.test.name | contains($name)))] | length' "$plan372_gate_dir/red.json")" -eq 1
red_id="$(jq -r -s --arg name "$red_name" '[.[] | objects | select(.type == "testStart" and (.test.name | contains($name)))][0].test.id' "$plan372_gate_dir/red.json")"
test "$(jq -s --argjson id "$red_id" '[.[] | objects | select(.type == "testDone" and .testID == $id and .result == "failure" and .skipped == false)] | length' "$plan372_gate_dir/red.json")" -eq 1

# 3. Focused isolated tests. Six exact named owners must each select once and
# finish success/non-skipped; TC-372-04/05/06 stay in the serial bundle below.
flutter test --concurrency=4 --machine \
  test/core/notifications/local_notification_ledger_test.dart \
  test/core/notifications/local_notification_final_effect_test.dart \
  test/core/notifications/local_notification_ledger_wiring_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  --name 'TC-372-(01|02|03|07a|08)' \
  >"$plan372_gate_dir/focused.json"
focused_names=(
  'TC-372-01 v1 codec and state machine accept only legal monotonic transitions'
  'TC-372-02 atomic store binding rebind and bounds preserve current authority and future bytes'
  'TC-372-03 final visibility barrier chooses exactly one in-chat or OS-posted effect'
  'TC-372-03b early visibility is preparation only and final gate owns the result'
  'TC-372-07a adopted direct group main background and reconciler effects have one gateway owner and correlation'
  'TC-372-08 legacy projection lazy adoption rebind and future rollback remain safe'
)
for name in "${focused_names[@]}"; do
  test "$(jq -s --arg name "$name" '[.[] | objects | select(.type == "testStart" and (.test.name | contains($name)))] | length' "$plan372_gate_dir/focused.json")" -eq 1
done
test "$(jq -s '([.[] | objects | select(.type == "testStart" and (.test.name | contains("TC-372-"))) | .test.id]) as $ids | [$ids[] as $id | if ([.[] | objects | select(.type == "testDone" and .testID == $id and .result == "success" and .skipped == false)] | length) == 1 then empty else $id end] | length' "$plan372_gate_dir/focused.json")" -eq 0
test "$(jq -s '[.[] | objects | select(.type == "testStart" and (.test.name | contains("TC-372-")))] | length' "$plan372_gate_dir/focused.json")" -eq 6

# 4. Process-global/plugin/flock/SQLite convergence stays serial.
flutter test --concurrency=1 --machine \
  test/core/notifications/local_notification_projection_convergence_test.dart \
  test/core/notifications/durable_conversation_notification_id_registry_test.dart \
  test/features/push/application/background_message_handler_test.dart \
  --name 'TC-372-(04|05|06|07b)' \
  >"$plan372_gate_dir/serial.json"
serial_names=(
  'TC-372-04 final canonical facts and revision CAS prevent resurrection and stale cancellation'
  'TC-372-05 one claim owner and deterministic publishing recovery across isolate arrival orders'
  'TC-372-05b one coordination lock rejects reentrant and inverse acquisition'
  'TC-372-06 effect-terminal replay settles direct and group custody once and emits only approved enabled outcome'
  'TC-372-07b authenticated background effect authorizes before native entry'
)
for name in "${serial_names[@]}"; do
  test "$(jq -s --arg name "$name" '[.[] | objects | select(.type == "testStart" and (.test.name | contains($name)))] | length' "$plan372_gate_dir/serial.json")" -eq 1
done
test "$(jq -s '([.[] | objects | select(.type == "testStart" and (.test.name | contains("TC-372-"))) | .test.id]) as $ids | [$ids[] as $id | if ([.[] | objects | select(.type == "testDone" and .testID == $id and .result == "success" and .skipped == false)] | length) == 1 then empty else $id end] | length' "$plan372_gate_dir/serial.json")" -eq 0
test "$(jq -s '[.[] | objects | select(.type == "testStart" and (.test.name | contains("TC-372-")))] | length' "$plan372_gate_dir/serial.json")" -eq 5

# 5. Exact preservation bundle; twelve selected IDs, twelve matched successes,
# zero skips. Registry/plugin/SQLite owners make this intentionally serial.
flutter test --concurrency=1 --machine \
  test/core/notifications/flutter_notification_service_test.dart \
  test/core/notifications/direct_notification_read_projector_test.dart \
  test/core/notifications/group_notification_read_projector_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/core/notifications/direct_group_notification_lane_isolation_test.dart \
  test/core/notifications/notification_completed_outcome_correlation_test.dart \
  test/core/database/migrations/116_notification_completed_outcome_outbox_test.dart \
  --name 'Android native boundary runs after registry retirement and directly wraps show|message-read cancellation cannot overtake a concurrent reaction replacement|exact conversation cancellation uses the existing id without cancelAll or allocation|TC-331-10 read acknowledges exact generation and preserves later sibling|new presentation racing read zero is cancelled after show and preserves siblings|startup zero-unread cannot cancel a headless event not yet canonical|TC-369-03 only an approved completed effect carries an outcome|reaction native-attempt error preserves fail-closed exact ownership|shows notification when app is backgrounded|same ids remain notification kind and peer scoped|TC-369-04 wake correlation byte contract is canonical and installation local|TC-369-01 v116 outcome outbox is additive bounded and empty' \
  >"$plan372_gate_dir/preservation.json"
test "$(jq -s '[.[] | objects | select(.type == "testStart" and .test.url != null)] | length' "$plan372_gate_dir/preservation.json")" -eq 12
test "$(jq -s '([.[] | objects | select(.type == "testStart" and .test.url != null) | .test.id]) as $ids | [.[] | objects | select(.type == "testDone" and (.testID as $id | ($ids | index($id)) != null) and .result == "success" and .skipped == false)] | length' "$plan372_gate_dir/preservation.json")" -eq 12
test "$(jq -s '[.[] | objects | select(.type == "testDone" and .skipped == true)] | length' "$plan372_gate_dir/preservation.json")" -eq 0

# 6. New shared owners appear exactly once in all three required inventories.
shared_tests=(
  test/core/notifications/local_notification_ledger_test.dart
  test/core/notifications/local_notification_final_effect_test.dart
  test/core/notifications/local_notification_projection_convergence_test.dart
  test/core/notifications/local_notification_ledger_wiring_test.dart
)
one_to_one="$(sed -n '/^readonly ONE_TO_ONE_TESTS=(/,/^)/p' scripts/run_test_gates.sh)"
groups="$(sed -n '/^readonly GROUP_TESTS=(/,/^)/p' scripts/run_test_gates.sh)"
host_one_to_one="$(sed -n '/^readonly ONE_TO_ONE_HOST_TESTS=(/,/^)/p' scripts/run_host_test_gates.sh)"
for test_path in "${shared_tests[@]}"; do
  test "$(printf '%s\n' "$one_to_one" | grep -Fxc "  \"$test_path\"")" -eq 1
  test "$(printf '%s\n' "$groups" | grep -Fxc "  \"$test_path\"")" -eq 1
  test "$(printf '%s\n' "$host_one_to_one" | grep -Fxc "  \"$test_path\"")" -eq 1
done

# 7. Affected curated lanes run serially.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# 8. The one N03-N06 aggregate host wave; do not also run core/feature host.
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# 9. Hygiene. Include tracked changes plus untracked nonignored Dart files.
changed_dart="$plan372_gate_dir/changed-dart.txt"
{
  git diff --name-only -- '*.dart'
  git diff --cached --name-only -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u >"$changed_dart"
if test -s "$changed_dart"; then
  xargs dart format --output=none --set-exit-if-changed <"$changed_dart"
fi
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py query \
  'Plan 372 final GAP-N05 GAP-N06 ledger effect gate bypass rollback tests' \
  --profile review --budget 800 --ensure-fresh
```

Do not run the two curated lanes or host-all concurrently. Isolated focused
files may use concurrency four; the serial bundle deliberately does not.

## Execution Interpretation And Done Criteria

- Expected RED: exactly one authored TC-372-01 test assertion fails because the
  record/codec/state machine is absent. File/load/tool/teardown failure is not
  accepted.
- Green sentinel: final-gate barrier tests prove both direction changes and
  effect counts; preservation remains 12/12 with zero skips.
- Execution baseline: Plan 371 is committed and checksum-bound. TC-372-00
  passed with only reviewed Plans 372--375/index planning documents over the
  frozen tree; commit those planning documents and begin production RED from a
  clean worktree.
- Environment blocker: none at re-grounding. Plan 372 has no device/relay/
  external-service gate.
- Scope drift: DB v117, a second/unordered effect lock, new scheduler, native
  renderer, synthetic generic event identity, activation or failure to preserve
  legacy projections stops execution for review.

- [x] TC-372-00 validates the exact Plan-371 receipt/tree and default-off seam.
- [x] Every TC-372-01 through TC-372-08 behavior has a named causal proof.
- [x] One semantic RED and representative mutation re-reds are recorded and
      reverted.
- [x] Final visibility and canonical-state mutations produce the exact effect/
      ledger result for all four producer kinds.
- [x] Crash/replay tests never conflate `PUBLISHING`, `EFFECT_TERMINAL` and
      `SETTLED`; Android proof never invents an OS generation field.
- [x] SQL custody remains through effect terminal and ledger settlement; SQL A
      records/verifies terminal/v116, and idempotent SQL B retires exact READY
      without another effect or revision drift.
- [x] Exact relay-verified unacknowledged custody may reach effect terminal but
      cannot ACK/v116/settle until same-correlation SQL materialization upgrades
      it; replay then performs zero second audible effect.
- [x] New shared tests are registered exactly once in all required arrays.
- [x] Both curated lanes and the single N03-N06 wave host-all pass.
- [x] Analyzer, changed-Dart format, diff hygiene and refreshed Graphify are
      clean.
- [x] No device/live/native-adapter/release or full PRD completion is claimed.

## Handoff

- First causal RED: TC-372-01 block in Acceptance Gates after the test, fixture
  and minimal compiling inert API shell are authored.
- Preservation: exact twelve-test bundle plus default-off Plan-370 sentinels.
- Manual registration: four shared Dart tests exactly once in
  `ONE_TO_ONE_TESTS`, `GROUP_TESTS` and `ONE_TO_ONE_HOST_TESTS`; no synthetic
  native/device row.
- Migration: no DB migration; DB remains v116. One additive bounded
  installation-local file uses lazy evidence-exact adoption, exact secure
  binding comparison and preserves legacy projections/future bytes. Copied
  bytes are inert; no unproved OS-backup exclusion is claimed.
- Boundary closure: host current-app final-effect/ledger mechanism plus the one
  N03-N06 aggregate host wave. NSE/FCM consumers and device evidence are
  downstream.
- Success marker after execution/audit only:
  `N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE`.
- Receipt: create `Test-Flight-Improv/evidence/372/README.md` plus sibling
  checksum. Include the marker above as a standalone raw line so successor
  `rg -Fqx` preflights are unambiguous. Bind the marker, Plan-371 dependency
  receipt, base HEAD, frozen tested tree, dirty snapshot SHA-256, Graphify
  fingerprint, exact focused/preservation/curated/aggregate-host results, the exact
  `RELAY_VERIFIED_UNACKED -> SQL_READY` phase-preserving upgrade matrix and its
  no-ACK/no-v116/no-SETTLED-until-effect-terminal rule,
  and the DB-v116/no-activation assertions.
- Downstream literal contract: the receipt must also contain every following
  value as its own standalone raw line so successor `rg -Fqx` checks cannot be
  satisfied by a heading, code fragment or paraphrase:

  ```text
  N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE
  local_notification_ledger_v1.json
  NotificationConversationIds/.coordination.lock
  IOS_NSE
  RELAY_VERIFIED_UNACKED
  phase-preserving
  DB v116
  default-off
  ```

  These literals bind the inherited marker, file/lock/state vocabulary and
  language-neutral native handoff. In particular, `IOS_NSE` records a reserved
  owner/vector for Plan 373; it does not claim a Swift adopter in Plan 372.
- Successor-verifiable receipt artifacts: also archive the exact normalized
  porcelain-v2 input as `workspace-porcelain-v2.txt.gz` and the exact 16-hex
  Graphify identity as `graphify-fingerprint.txt`; their rehashed bytes must
  equal the two README fields. Record the exact Dart production ledger source,
  basename/coordination-lock owner and public transition API names so Plans
  373/374 cannot satisfy dependency checks with fixtures or planning prose.
- Meaning of marker: one logical record/current exact-correlation Dart effect
  boundary is code-complete. GAP-N06/A-27 is not cross-native-complete until
  Plan 373 and N08 adopt the same contract; the marker also does not claim N11
  policy/read convergence, delayed-wake activation, live/PRD acceptance or
  release.
- Next plan: Plan 373 consumes this exact receipt and adds the iOS NSE adapter;
  it does not redesign the ledger or rerun full host-all.

## Reviewer Findings

Independent `$tdd-review` result: **PASS after bounded in-place corrections**.

- Evidence truth and classification: PASS. The current early visibility sample,
  post-show background validation, split durable owners, Android-only binding
  composition and direct canonical-predicate divergences are source-confirmed.
  The committed Plan-371 receipt and pinned dependency preflight now pass.
- Test causality: PASS. RED is compile-valid and assertion-specific; the final
  visibility/canonical mutations occur after durable publication arming;
  crash cuts distinguish pre-entry, ambiguous post/update, ambiguous cancel,
  effect terminal and SQL-settled state; owner and effect count discriminate
  sibling paths.
- Bypass and scope safety: PASS. Exact-correlation main, Android-background and
  reconciler adopters are named. Generic/unanchored alerts, tap/activation,
  global clear, iOS NSE and Android-native recovery are explicit exceptions
  with downstream owners rather than synthetic ledger identities.
- Gate integrity: PASS. Three dependency sentinel names match current tests;
  focused and serial bundles select their exact owners; preservation uses
  `--name` and runs 12/12 serially; both curated lanes remain sequential and the
  one wave-level host-all replaces redundant family sweeps.
- Boundary/reversibility: PASS. The ledger is a separate bounded file under the
  incumbent coordination lock; v1 metadata/claims stay rollback projections;
  DB remains v116; binding mismatch makes stale/copied bytes inert; only settled
  rows prune; native ambiguity never authorizes an audible replay.
- Native-source handoff: PASS after counterexample repair. Matching SQL custody
  upgrades only `sourceCustody`/revisions under the existing lock and preserves
  `READY`, `CLAIMED`, `PUBLISHING` or `EFFECT_TERMINAL` exactly. In particular,
  an upgraded `PUBLISHING` row remains ambiguous and cannot emit v116, delete
  SQL custody or settle merely because materialization completed.

Rejected expansions: a standalone N05 plan, a standalone/second N06 plan, DB
v117, a second lock/ledger, custom JSON parser, scheduler, native renderer,
device harness, per-platform modality plan, or extra core/feature sweep. None
improves the one ledger/effect rollback boundary.

## Arbiter Decision

Proceed with exactly one combined N05+N06 implementation plan; Plan 371's
checksum-bound receipt now validates. Plan 372 owns the shared logical ledger and
its current exact-correlation Dart effect adopters; Plan 373 and N08 remain
thin platform adapters required for cross-native GAP-N06/A-27 closure. The only
success marker is
`N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE`, with the paired outcome
admission still default-off and no live/PRD/release claim.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-15 | planning | plan only | Plan-371 receipt lookup -> absent while implementation is active | Current dirty Plan-371 tree is not accepted dependency evidence | **PREREQUISITE_BLOCKED** | Wait for Plan-371 execution/audit receipt, then run TC-372-00 |
| 2026-08-16 | dependency re-grounding | plan only | TC-372-00 checksum/identity/ancestry/drift proof plus three exact Plan-370 default-off sentinels -> PASS; Graphify TDD query -> current/anchored `a1554310fab6234f` | Committed receipt `3c7e704e77f9240d62332750db4a6ecd26894b1d`, SHA-256 `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f`, frozen tree and machine-readable identities all pinned | **EXECUTION_READY**; no environment blocker | Commit reviewed planning baseline, confirm clean worktree, rerun TC-372-00, then author the minimal inert API shell and causal TC-372-01 RED |
| 2026-08-16 | causal RED and current-Dart implementation | Ledger codec/store/state machine; incumbent registry lock; final-effect coordinator; direct/group/background/reconciler adopters | Exact TC-372-01 selected once and assertion-failed (JSON `06baef9305459af29a41e5177c023f144873f734f5f260a58709868fab8fe9a9`); focused 6/6, serial 5/5, preservation 12/12 and exact shared registration then passed | One strict identifier-only v1 file, one incumbent flock, fresh final barrier, phase-aware crash recovery and current exact-correlation adoption | None | Execute serial counterexample mutations and curated lanes |
| 2026-08-16 | counterexample proof | Revision CAS; PUBLISHING recovery; SETTLED terminal enumeration | Three isolated mutations semantically re-RED TC-372-01/05/06, were reverted, and each exact owner returned GREEN | Stale revision, audible ambiguity replay and lost SQL-B recovery are causally rejected | None | Run affected curated lanes and aggregate wave gate |
| 2026-08-16 | curated preservation | Current 1to1/group notification owners, projections and gate inventories | `1to1` 3,330 PASS / 10 declared skips plus tails; `groups` 4,334 PASS / 0 skips plus tails | All four adopted producer kinds converge through one final gateway; generic/activation/global-clear exceptions remain classified and outcome-ineligible | None | Run the one N03-N06 aggregate `host-all` |
| 2026-08-16 | aggregate diagnostic and bounded repair | Account migration compatibility; ignored vendor inventory; DTR-18 hashes; route/flock/group harness sentinels | First full sweep's 19 failures were fully classified; one real Android/no-shared-store promotion regression was repaired at `supportsScope`; deterministic hygiene/sentinel issues passed 41/41, 58/58, 42/42 and exact group harness 2/2 | No failure was waived. Semantic flock bounds stayed unchanged; the two group repairs only interleave real async filesystem work with bounded pumps | None | Rerun the complete aggregate gate on the repaired final tree |
| 2026-08-16 | N03-N06 host wave and hygiene | 1,362 Flutter paths plus host items 1363-1376; 72 changed Dart files; full analyzer; graph | Final `host-all` 14,288 PASS / 11 declared skips / 0 failures and every tail PASS (SHA-256 `3c453e6d6cddce70ba787475e52fe0f0568944a975299ff5c000635f15df1895`); show owner 56/56; format/analyzer/static hygiene clean; Graphify current/anchored `8c428eb87b960e70` | **ONE N03-N06 HOST WAVE VERIFIED**; no redundant core/feature sweep or device/native-adopter claim | None | Freeze the exact tested tree and bind closure evidence |
| 2026-08-16 | post-execution audit closed | 78-path frozen implementation plus checksum receipt and successor-verifiable provenance archive | Frozen tree `71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2`; workspace SHA-256 `45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed`; receipt SHA-256 `9da08053f6a6034b002376ccc348834ca2576b0761e77be72386e5ec1dec4a62` | **N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE** for the current Dart/shared mechanism; SQL A -> SETTLED -> SQL B and relay-to-SQL phase preservation are bound | iOS NSE/Android native adoption, live/activation/full PRD/release remain downstream | Commit Plan 372 only, validate its receipt from clean HEAD, then execute Plan 373 |
