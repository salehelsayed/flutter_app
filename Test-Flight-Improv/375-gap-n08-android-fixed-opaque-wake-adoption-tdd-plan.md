# 375 - GAP-N08 Android Fixed Opaque Wake Adoption And Mechanism Closure

Status: **PREREQUISITE_BLOCKED / CONTRACT_READY / INDEPENDENTLY_REVIEWED / N08 SLICE 2 OF 2 / PAIRED ADMISSION DEFAULT-OFF / ADAPTER-WAVE HOST REQUIRED / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec inputs: GAP-N08, WP-05 and sequencing guidance in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; Plans 368, 370, 372, 373 and 374
Classification: Android fixed-wake ingress and existing headless-recovery adoption
Closure tier: focused host/native, affected curated lanes, one availability-bounded Android mechanism proof, and one N07+N08 adapter-wave host aggregate

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-16 | Planner using `$tdd-plan` | GAP-N08; Plans 368/370/372/373/374; Android Firebase service, recovery store/scheduler/worker/bridge; registration coordinator and capability seam | The fixed wake, sound disposition, WorkManager continuation and paired readiness have one rollback/capability boundary. A second service, worker or store would duplicate landed Plan-331/374 ownership. | Keep one final N08 slice over the incumbent native recovery family. |
| 2026-08-16 | Graph/source grounding | `buildOpaqueWakeMessage`, `MknoonFirebaseMessagingService.onDeletedMessages`, `DroppedPushRecoveryStore`, `HeadlessCanonicalRecoveryWorker` | Graphify anchored the provider grammar but native Kotlin needed direct verification. The app owns the only `MESSAGING_EVENT` service and it currently lacks `onMessageReceived`. | Add one strict branch and delegate every nonfixed message to FlutterFire exactly once. |
| 2026-08-16 | Authority reviewers | Plan-372 native-source states; Plan-374 materialization/ACK order; identity-free fixed payload | `{v,w}` contains no authenticated event identity. It cannot create correlation, ledger, SQL, v116 or relay-ACK authority. | Treat it only as a durable mailbox signal with a silent generic disposition; Plan 374 remains the `INBOX_RECONCILER`. |
| 2026-08-16 | Gate/device reviewers | existing Kotlin/Dart tests, host runner, Plan-374 device harness, live target matrix | Extend the one Plan-374 native row and one device runner. Focused Dart/Kotlin/Go plus baseline/1to1/groups are sufficient; one full host belongs at the N07+N08 wave boundary. | Reuse artifacts, run independent focused legs concurrently, serialize shared-state and curated gates. |
| 2026-08-16 | Independent `$tdd-review` | full Plan-375 contract plus Plan-373/374 handoffs, source owners and literal Bash fences | Review exposed event-authority overreach, reverse-order double-sound risk, stale registration cutover, raw relay-health re-registration bypasses, periodic liveness and several non-vacuous gate defects. All were corrected in place without another delivery slice. | PASS; execution remains blocked on committed Plans 373 and 374 receipts. |

## Problem And Evidence

- The relay already emits an exact Android data-only provider request:
  `{"v":"1","w":"1"}`, high priority, TTL 300 seconds and collapse key
  `mailbox`. `TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest`
  captures the decoded request emitted by the real Firebase Admin SDK for all
  22 source-eligible producer fixtures and proves the real-store zero-wake
  controls emit no request. It proves that exact provider shape, not live FCM
  delivery or a byte-for-byte JSON serialization order.
- Android replaces FlutterFire's manifest service with the app-owned
  `MknoonFirebaseMessagingService`, but that class overrides only
  `onDeletedMessages`. Normal messages still enter FlutterFire's rich
  background-Dart path and an exact fixed wake has no consumer.
- The app already has one crash-safe, binding-bound recovery generation store,
  one private localized generic card, one unique expedited scheduler, one
  WorkManager worker, one minimal Flutter engine and one canonical runtime
  protocol. Plan 374 makes their production direct/group/SQL/ledger graph safe.
  Plan 375 must adopt them, not reproduce them.
- The fixed wake is intentionally content-free. FCM message ID, collapse key,
  delivery priority and the recovery generation are transport hints, not event
  identities. They cannot authorize a Plan-372 event record, notification
  correlation, completed outcome, SQL completion or relay custody ACK.
- The existing generic card uses one reserved tag/ID, private lock-screen
  visibility, localized copy and `onlyAlertOnce`. It is the right mailbox-wide
  fallback. N09, not N08, owns `MessagingStyle`, Person/shortcut projection and
  visual presentation expansion.
- The paired `opaque_wake_v1` and `wake_outcome_v1` capabilities are controlled
  by one default-false build seam. Production registration currently does not
  prove a platform consumer/readiness read-back, and linked Android startup has
  no scoped provider-token registration owner.

## Dependency Contract

### Hard implementation prerequisite

No TC-375 RED may run until Plans 373 and 374 have committed checksum-bound
receipts whose source/API contracts still match this plan. Require:

- `Test-Flight-Improv/evidence/374/README.md`, `README.md.sha256`,
  `workspace-porcelain-v2.txt.gz` and `graphify-fingerprint.txt`;
- marker `N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE`;
- valid Base HEAD, Frozen tested tree, Dirty snapshot SHA-256 and Graphify
  fingerprint, plus committed receipt/checksum/artifact bytes;
- the accepted production recovery factory/session, existing-only SQLCipher
  opener, all-handler admission fence, four-store/ledger settlement,
  `INBOX_RECONCILER` ownership, exact teardown/resnapshot/ACK and typed native
  binding/readiness result;
- exactly one existing `DroppedPushRecoveryStore`, scheduler, worker, runtime
  lease/host and `MESSAGING_EVENT` service;
- DB remains v116, Plan-372 ledger/correlation semantics remain frozen, and the
  one paired outcome seam remains default false.

Plan 374 transitively binds Plans 371/372. Plan 368 is a direct wire
prerequisite, so preserve its checksum receipt, committed provenance and exact
Android provider API/test. Plan 373 is a narrow composition prerequisite: its
four committed receipt artifacts must bind the single
`OpaqueWakePlatformConsumerReadiness` owner with iOS supplied and a missing
Android reader returning false. Plan 375 extends that owner; it does not
reimplement iOS readiness. Both receipts are hard prerequisites before any RED,
so the one N07+N08 wave `host-all` is an unconditional Plan-375 closure gate.
Plan 368 predates the four-artifact receipt convention: its accepted evidence
directory contains the README and sibling checksum, while the frozen-tree,
workspace and Graphify identities live inside that README. Validate those two
committed bytes and identities exactly; do not fabricate retroactive artifacts.

```bash
(
  set -euo pipefail
  receipt='Test-Flight-Improv/evidence/374/README.md'
  checksum='Test-Flight-Improv/evidence/374/README.md.sha256'
  test -f "$receipt"
  test -f "$checksum"
  (cd Test-Flight-Improv/evidence/374 && shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE' "$receipt"

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

  receipt_commit374="$(git log -n 1 --format=%H -- "$receipt")"
  test -n "$receipt_commit374"
  git merge-base --is-ancestor "$base" "$receipt_commit374"
  git merge-base --is-ancestor "$receipt_commit374" HEAD
  cmp -s <(git show "${receipt_commit374}:${receipt}") "$receipt"
  cmp -s <(git show "${receipt_commit374}:${checksum}") "$checksum"

  dirty_archive='Test-Flight-Improv/evidence/374/workspace-porcelain-v2.txt.gz'
  graph_file='Test-Flight-Improv/evidence/374/graphify-fingerprint.txt'
  test -f "$dirty_archive"
  test -f "$graph_file"
  cmp -s <(git show "${receipt_commit374}:${dirty_archive}") "$dirty_archive"
  cmp -s <(git show "${receipt_commit374}:${graph_file}") "$graph_file"
  test "$(gzip -dc "$dirty_archive" | shasum -a 256 | awk '{print $1}')" = "$dirty"
  test "$(tr -d '[:space:]' <"$graph_file")" = "$graph"

  # The frozen Plan-374 product/test tree may differ from its receipt commit
  # only by the declared closure artifacts. Re-pin if the accepted receipt
  # uses a narrower layout; never admit product source here.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/374-gap-n08-*|\
      Test-Flight-Improv/375-gap-n08-*|\
      Test-Flight-Improv/evidence/374/*|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Unexpected Plan-374 post-freeze drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(git diff --name-only "$frozen" "$receipt_commit374")

  # After the committed Plan-374 receipt, only the already-authored Plan-375
  # contract/index may move before RED. Any product, test, script, Graphify or
  # other closure drift requires a new prerequisite review.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/375-gap-n08-*) ;;
      *) printf 'Unexpected post-Plan-374 product drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(git diff --name-only "$receipt_commit374" HEAD)

  receipt373='Test-Flight-Improv/evidence/373/README.md'
  checksum373='Test-Flight-Improv/evidence/373/README.md.sha256'
  dirty_archive373='Test-Flight-Improv/evidence/373/workspace-porcelain-v2.txt.gz'
  graph_file373='Test-Flight-Improv/evidence/373/graphify-fingerprint.txt'
  test -f "$receipt373"
  test -f "$checksum373"
  test -f "$dirty_archive373"
  test -f "$graph_file373"
  (cd Test-Flight-Improv/evidence/373 && shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N07_IOS_NSE_OPAQUE_WAKE_ADAPTER_CODE_COMPLETE_IOS_EVIDENCE_DEFERRED' "$receipt373"
  rg -Fq 'OpaqueWakePlatformConsumerReadiness' "$receipt373"
  base373="$(awk -F'`' '/\| (Base( and unchanged)? HEAD|Base HEAD) \|/ {print $2; exit}' "$receipt373")"
  frozen373="$(awk -F'`' '/\| Frozen tested tree \|/ {print $2; exit}' "$receipt373")"
  dirty373="$(awk -F'`' '/\| (Porcelain-v2 workspace snapshot|Dirty snapshot) SHA-256 \|/ {print $2; exit}' "$receipt373")"
  graph373="$(awk -F'`' '/\| (Graphify )?[Ff]ingerprint \|/ {print $2; exit}' "$receipt373")"
  [[ "$base373" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen373" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty373" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph373" =~ ^[0-9a-f]{16}$ ]]
  git cat-file -e "${base373}^{commit}"
  git cat-file -e "${frozen373}^{tree}"
  receipt_commit373="$(git log -n 1 --format=%H -- "$receipt373")"
  test -n "$receipt_commit373"
  git merge-base --is-ancestor "$base373" "$receipt_commit373"
  git merge-base --is-ancestor "$receipt_commit373" "$receipt_commit374"
  git merge-base --is-ancestor "$receipt_commit373" HEAD
  cmp -s <(git show "${receipt_commit373}:${receipt373}") "$receipt373"
  cmp -s <(git show "${receipt_commit373}:${checksum373}") "$checksum373"
  cmp -s <(git show "${receipt_commit373}:${dirty_archive373}") "$dirty_archive373"
  cmp -s <(git show "${receipt_commit373}:${graph_file373}") "$graph_file373"
  test "$(gzip -dc "$dirty_archive373" | shasum -a 256 | awk '{print $1}')" = "$dirty373"
  test "$(tr -d '[:space:]' <"$graph_file373")" = "$graph373"

  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/373-gap-n07-*|\
      Test-Flight-Improv/374-gap-n08-*|\
      Test-Flight-Improv/375-gap-n08-*|\
      Test-Flight-Improv/evidence/373/*|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Unexpected Plan-373 post-freeze drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(git diff --name-only "$frozen373" "$receipt_commit373")

  readiness_sources="$(rg -l 'class OpaqueWakePlatformConsumerReadiness' lib --glob '*.dart')"
  test "$(printf '%s\n' "$readiness_sources" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1
  readiness_source="$(printf '%s\n' "$readiness_sources" | sed -n '1p')"
  rg -Fq 'OpaqueWakePlatformConsumerReadiness' "$readiness_source"
  test -f ios/NotificationService/IosLocalNotificationFinalEffect.swift
  rg -Fq 'IosLocalNotificationFinalEffect' \
    ios/NotificationService/IosLocalNotificationFinalEffect.swift

  rg -Fqx 'const int currentIdentityDatabaseVersion = 116;' \
    lib/core/database/app_database_version.dart
  test "$(rg -l 'class DroppedPushRecoveryStore' \
    android/app/src/main/kotlin/com/mknoon/app | wc -l | tr -d ' ')" -eq 1
  test "$(rg -l 'class HeadlessCanonicalRecoveryWorker' \
    android/app/src/main/kotlin/com/mknoon/app | wc -l | tr -d ' ')" -eq 1
  manifest='android/app/src/main/AndroidManifest.xml'
  test "$(rg -c 'android:name="com\.google\.firebase\.MESSAGING_EVENT"' "$manifest")" -eq 1
  test "$(rg -c 'android:name="\.MknoonFirebaseMessagingService"' "$manifest")" -eq 1
  test "$(rg -c 'tools:node="remove"' "$manifest")" -ge 1

  receipt368='Test-Flight-Improv/evidence/368/README.md'
  checksum368='Test-Flight-Improv/evidence/368/README.md.sha256'
  test -f "$receipt368"
  test -f "$checksum368"
  (cd Test-Flight-Improv/evidence/368 && shasum -a 256 -c README.md.sha256)
  rg -Fqx 'N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE' "$receipt368"
  base368="$(rg -F '| Base and unchanged `HEAD` |' "$receipt368" | rg -o '[0-9a-f]{40}' | tail -n 1)"
  frozen368="$(awk -F'`' '/\| Frozen tested tree \|/ {value=$2} END {print value}' "$receipt368")"
  dirty368="$(awk -F'`' '/\| Porcelain-v2 workspace snapshot SHA-256 \|/ {value=$2} END {print value}' "$receipt368")"
  graph368="$(awk -F'`' '/\| (Graphify fingerprint|Fingerprint) \|/ {value=$2} END {print value}' "$receipt368")"
  [[ "$base368" =~ ^[0-9a-f]{40}$ ]]
  [[ "$frozen368" =~ ^[0-9a-f]{40}$ ]]
  [[ "$dirty368" =~ ^[0-9a-f]{64}$ ]]
  [[ "$graph368" =~ ^[0-9a-f]{16}$ ]]
  git cat-file -e "${base368}^{commit}"
  git cat-file -e "${frozen368}^{tree}"
  receipt_commit368="$(git log -n 1 --format=%H -- "$receipt368")"
  test -n "$receipt_commit368"
  git merge-base --is-ancestor "$base368" "$receipt_commit368"
  git merge-base --is-ancestor "$receipt_commit368" "$receipt_commit373"
  git merge-base --is-ancestor "$receipt_commit368" HEAD
  cmp -s <(git show "${receipt_commit368}:${receipt368}") "$receipt368"
  cmp -s <(git show "${receipt_commit368}:${checksum368}") "$checksum368"
  rg -Fq 'opaqueWakeCapability = "opaque_wake_v1"' \
    go-relay-server/opaque_wake.go
  rg -Fq 'func buildOpaqueWakeMessage(platform string, now time.Time) (*messaging.Message, error)' \
    go-relay-server/opaque_wake.go
  rg -Fq 'func (ps *PushService) mailboxDirty(ctx context.Context, route pushRouteLease) error' \
    go-relay-server/opaque_wake.go

  provider368="$(mktemp /tmp/plan375-provider368.XXXXXX)"
  trap 'rm -f "$provider368"' EXIT
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest$' \
    -count=1 -v) | tee "$provider368"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest ' "$provider368")" -eq 1
  ! rg -q '^[[:space:]]*--- SKIP:' "$provider368"

  flutter test --no-pub \
    test/core/notifications/ios_nse_inbox_projection_test.dart \
    --plain-name 'TC-373-07 one default-off projection and native adapter own fixed wakes'

  flutter test --no-pub \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    --plain-name 'TC-370-05 opaque outcome uses strict all-relay completion'
  flutter test --no-pub \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    --plain-name 'TC-370-07 production composes one default-off outcome admission and one shared drain callback'

  # Execution starts from the committed, receipt-bound Plan-374 product tree.
  # Allowed successor planning bytes above must also be committed before RED.
  test -z "$(git status --porcelain=v1)"
)
```

Re-pin exact Plan-373/374 source/test/API names from their accepted receipts
before the first RED. A changed graph/owner/API or non-allowlisted post-receipt
drift is a stop-and-review condition, not a reason to weaken the preflight.

## Graph Grounding Snapshot

- TDD query:
  `python3 graphify-arch/tdd_context.py query "MknoonFirebaseMessagingService.kt onMessageReceived HeadlessCanonicalRecoveryWorker.kt DroppedPushRecoveryStore.kt DroppedPushRecoveryWorkScheduler.kt buildOpaqueWakeMessage opaque_wake_v1 wake_outcome_v1" --profile tdd --budget 700`
- Result after review refinement: `confidence=anchored`, `freshness=current`,
  fingerprint `a1554310fab6234f`; exact anchors `P2PServiceImpl` and
  `PushRegistrationCoordinator`, with provider/native source verified directly.
- Source verification added the native Kotlin service/store/scheduler/worker,
  manifest, `DroppedPushRecoveryBridge`, `CanonicalRecoveryRuntime`,
  `PushRegistrationCoordinator`, `registerPushToken`, linked runtime startup,
  capability registration and every gate/test named below.
- Native Kotlin is intentionally source-verified because the architecture
  graph does not model every platform callback. Re-run the same focused query
  with `--ensure-fresh` after Plan 374 closes.

## Delivery Structure Decision

N08 needs exactly two implementation plans:

1. Plan 374 completes and safely enables the incumbent deleted-batch/periodic
   headless graph without advertising fixed wakes.
2. Plan 375 adds fixed-wake ingress/sound disposition and Android paired-consumer
   readiness over that frozen graph.

The split is load-bearing: recovery work can roll back independently while
opaque capability advertisement remains off. Plan 375 is still one slice
because its service classifier, marker disposition, worker reason and token
capabilities become safe or unsafe together. Splitting ingress from worker or
readiness would create a route with no consumer or a consumer no route can use.
Do not split by direct/group, primary/linked, permission state, API level,
message/reaction or host/device proof.

## Android Ingress And Recovery Contract

### Exact fixed classifier and rich compatibility

Override `onMessageReceived(RemoteMessage)` in the incumbent app-owned
`MknoonFirebaseMessagingService` and route through one pure classifier:

- fixed only when `RemoteMessage.notification == null` and the data map has
  exactly two String entries, `v == "1"` and `w == "1"`;
- no numeric coercion, subset matching, trimming, aliases or unknown app-owned
  fields;
- every missing/wrong/extra/mixed/rich/notification-bearing message delegates
  to `super.onMessageReceived` exactly once and does not touch the recovery
  store, card or scheduler;
- an exact fixed wake never enters FlutterFire rich staging and never calls
  `super`;
- after classification, missing/corrupt/future/cross-account native binding is
  consumed fail-closed with zero marker, card or schedule. A valid current
  binding may recover a stale already-routed fixed wake even while outbound
  paired admission is default false; build admission governs advertisement,
  not safe parsing of an already-delivered exact fixed signal.

High priority, TTL 300 seconds and `mailbox` collapse are send-side facts proven
by Plan 368. They are not stable content authority at the client and must not
make a valid data-only fixed wake fail after FCM delivery/downgrade. The fixed
payload remains safe to consume when the paired admission is default-off: it
may be a stale already-routed wake during rollback.

### One marker and one honest audible disposition

Generalize, do not replace, `DroppedPushRecoveryStore`:

- the pending record remains binding + positive monotonic generation;
- add a strict trigger kind `DELETED_BATCH | FIXED_WAKE`; a legacy record with
  no kind decodes as `DELETED_BATCH`. Unknown/malformed future kinds retain the
  exact binding/generation as conservative `UNSUPPORTED_PENDING`; they never
  decode as no work or authorize ACK/cancel;
- add one `genericMayHaveAlerted` disposition to the same record. A legacy
  record with no disposition decodes `true`, because the old deletion service
  may already have called `notify`. `DELETED_BATCH` commits `true` before its
  incumbent possibly-audible attempt. A new `FIXED_WAKE` commits `false` only
  when no current same-binding marker has `true`; coalescing a fixed trigger
  may never downgrade an existing audible ambiguity;
- do not add a history, queue, per-event ID, provider ID, synthetic correlation
  or second preference/file. New triggers atomically allocate a newer
  generation and replace the one pending record; the one reserved card still
  coalesces with `onlyAlertOnce`;
- marker/kind/disposition commit happens before notification or scheduling.
  The exact fixed branch uses the incumbent private generic tag/ID but always
  requests a visibly present, explicitly silent notification. The deletion
  branch retains its incumbent possibly-audible behavior. The existing
  serialized after-commit seam prevents exact ACK/cancel from overtaking that
  generation;
- enqueue failure or process death leaves the marker. Any later periodic,
  deleted-batch or fixed-wake WorkRequest adopts the current record's trigger,
  binding and generation and may finish it; WorkRequest input never limits the
  current durable work;
- permission denial, disabled channel, `notify` failure or an ambiguous native
  callback leaves the marker and conservative disposition. No native API
  result is misclassified as an event terminal;
- exact ACK and account/binding rotation remove kind, disposition and marker in
  one incumbent transaction. Same-binding disable preserves them for warm-app
  repair;
- a stale worker/ACK/cancel cannot clear a newer generation or another binding.

The private generic card keeps the incumbent localized channel/tag/ID,
visibility, category and `onlyAlertOnce`. There is no second fixed-wake card or
channel. The identity-free mailbox card cannot be assigned a conversation's
stable notification ID. Because the relay may resubmit a fixed wake throughout
the seven-day outcome-retention window, no bounded local recent-sound horizon
can prove that it represents the same event. The deterministic contract is:

1. every `FIXED_WAKE` generic request is explicitly silent, in every crash/
   retry/order; it never sets `genericMayHaveAlerted` by itself;
2. a fixed-only marker therefore does not force a later canonical event silent.
   Plan 372 keeps its normal exact per-event/tone arbitration, so the canonical
   notification may make the one sound;
3. if a current coalesced deletion marker already says
   `genericMayHaveAlerted=true`, fixed ingress preserves that disposition and
   the Plan-372 final gate retains the incumbent conservative silent behavior;
4. fixed-before-canonical, canonical-before-fixed and overlapped callbacks all
   produce at most one requested sound without guessing an event identity;
5. only after every direct/group page, all four SQL custody stores and the
   Plan-372 ledger converge may the worker compare-ACK the exact marker and
   cancel the reserved generic card. Partial work, process death, newer
   generation or stale ACK retains it.

This closes the fixed-wake A-15 sound race without a correlation, new lock or
global seven-day mute. Brief visual coexistence is promptly coalesced, as the
PRD permits. The incumbent possibly-audible deleted-batch path remains
explicitly classified and is not silently weakened or overclaimed by this
fixed-wake slice.

### Reuse Plan 374 end to end

Add `fixedWake` to the existing native/Dart reason enums and the incumbent
unique immediate WorkManager chain. Do not add another unique-work prefix,
worker, engine, runtime, scheduler or channel.

- Work input remains a wake hint. The worker resnapshots current binding,
  newest generation, trigger kind and audible disposition before engine
  creation and again before completion.
- A stale queued deleted/fixed/periodic reason processes the newest current
  marker using that marker's trigger semantics. Periodic work cannot report a
  marker as periodic success, but it may exact-ACK it after the same fixed-point
  proof; this is the recovery path after immediate enqueue failure.
- At the Plan-372 final-effect boundary, read the current marker disposition
  through the existing Plan-374 bridge. Fixed-only `false` never suppresses the
  canonical tone; preserved deletion `true` retains incumbent conservative
  silence. This may alter only the Android sound flag and may not bypass
  Plan-371 visibility, Plan-372 revision/final-effect checks, event/tone
  ambiguity, stable-ID generation or canonical SQL policy.
- The fixed payload itself creates no Plan-372 record. The Plan-374 Dart drain
  authenticates/decrypts and persists current direct/group rows first, then
  materializes notification custody as `INBOX_RECONCILER`/`SQL_READY` and uses
  Plan 372 normally. It does not originate `ANDROID_PUSH_SERVICE` or
  `RELAY_VERIFIED_UNACKED` from `v`, `w`, FCM message ID, collapse key or
  recovery generation.
- Current FlutterFire rich background events retain their incumbent
  `ANDROID_PUSH_SERVICE` ownership. Plan 375 does not reclassify or retire that
  path.
- Only the normal canonical inbox owners ACK relay rows after durable local
  custody. Neither the Firebase service nor generic marker ACKs relay custody.

### One effective paired admission and one registration owner

Keep `MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR` as the only build admission and
default it to false. Add no second capability, build flag or caller-injected
production override.

The effective platform predicate is:

```text
buildAdmission
AND current platform consumer ready
AND exact current opaque binding read-back
AND qualified physical transport peer
```

For Android, consumer-ready means Plan-374 recovery work is committed enabled,
the Plan-375 fixed branch/readiness version is exact, and the native binding
equals the current secure binding. Missing/stale/future/cross-account/read
failure means false. Extend Plan 373's frozen
`OpaqueWakePlatformConsumerReadiness`; Android supplies one binding/role-epoch
reader and missing platform state stays false. Never leave two readiness
authorities or persist an admission boolean.

The resolver is live, not a constructor boolean: the outcome producer reads it
at each event, the drainer reads it at each kick, and registration reads it
after asynchronous token acquisition and immediately before the bridge send.
All three compare the same binding/role epoch. Constructing while unready and
qualifying later enables all three together; rotation/read failure disables all
three together. The public function-level injected seam may remain for TC-370,
but production composition must not infer readiness from `Platform.isAndroid`
alone.

Reuse exactly one `PushRegistrationCoordinator`:

- ordinary primary startup/refresh/retry remains incumbent behavior. Its exact
  admitted set is `{direct_reaction_v1, group_reaction_v1, opaque_wake_v1,
  wake_outcome_v1}`; while unadmitted it remains the incumbent direct/group
  reaction pair only;
- active-linked Android, while admission is false, starts no new Firebase or
  registration work. When true, after returned-peer qualification and exact
  consumer/binding read-back, role-gate Firebase startup and call the same one
  coordinator. Its exact set is `{opaque_wake_v1, wake_outcome_v1}` only; no
  accepted linked-rich proof exists in this plan, so it must not inherit the
  primary defaults. Preserve one token-refresh subscription and retry owner;
- linked registration uses the qualified physical transport peer for the relay
  route and the logical account peer for migration/account authority. Extend
  the registration use case with that explicit logical-authority input rather
  than accidentally checking the linked physical peer as an account identity;
- preparing/partial/fail-closed/corrupt/cross-account/device-drifted linked
  authority registers zero times and never falls back to the primary key;
- route the persisted-token restore and all three relay-health raw
  `_reregisterStoredPushTokenIfAvailable` paths through one late-installed
  `PushRegistrationCoordinator.retryNow` callback. Before installation the
  startup coordinator owns the initial attempt; afterward no raw bridge
  registration path remains. Cached-token recovery, token refresh and health
  transitions must emit at most one current-policy frame;
- do not call the raw registration closure beside the coordinator, add another
  token listener, register a half-capability set or cache a pre-token readiness
  decision. Before committing any binding/role/readiness epoch mutation, the
  coordinator fences new triggers and joins the in-flight token/retry/send
  attempt. A bridge future held across the cutover may not be treated as
  cancellable after dispatch: if acceptance is ambiguous or already succeeded,
  withdraw or replace that exact old-authority route and verify the current
  capability set/selection before the new epoch reports healthy;
- active-linked reaction wakes remain ineligible until a later accepted
  linked-rich/producer-capability proof. Do not silently advertise reaction
  capability merely to widen fixed selection.

## Rollout And Rollback

Plan 375 implements readiness and tests true-injected behavior but does not turn
the build admission on in production, migrate live routes or deploy a cohort.

Future WP-07 activation order:

1. install/prove the native fixed consumer and Plan-374 recovery read-back;
2. enable the one admission for the selected Android cohort;
3. re-register the same provider token under the exact physical route with
   both capabilities and verify the current exact capability set, opaque route
   selection and invalidation of the stale pre-refresh lease. Same token+
   platform capability refresh may preserve handle/generation; only token or
   platform rotation is required to advance generation;
4. observe live provider/FCM/WorkManager behavior before retiring rich routes.

Future rollback first fences and joins the coordinator's token refresh, retry
and in-flight send owner so no stale callback can republish the pair. It then
re-registers the same token without both capabilities, or authenticated-
unregisters it, and verifies the current exact capability set/route selection
plus stale-lease invalidation. Keep consumer/outcome owners alive until that is
confirmed; only afterward disable/remove consumer projection. New code
continues safely accepting stale exact fixed wakes during rollback. Never put
an old binary behind a still-opaque-capable route.

Plan 375 does not perform activation, live route migration, provider send,
token cohort selection, Doze/OEM campaign, telemetry rollout, rich retirement
or release acceptance.

## Scope Contract And Guard

In scope:

- one exact Android data-only fixed classifier in the incumbent service;
- one trigger-kind/audible-disposition extension of the incumbent marker;
- one `fixedWake` reason on the incumbent scheduler/worker/runtime;
- one fixed-silent/deletion-disposition rule and exact generic-card retirement;
- Android effective consumer read-back and paired capability registration;
- one narrowly role-gated active-linked Android registration hook through the
  incumbent coordinator;
- exact rich-path, account-cutover, crash and rollback preservation;
- extension of the existing Plan-374 native host row and device harness.

Explicitly out of scope:

- a Kotlin/native inbox client, decryption engine, event ledger writer or relay
  ACK owner;
- a second Firebase service, WorkManager worker, scheduler, store, preference
  family, database, coordination lock, notification channel/card family,
  runtime or token coordinator;
- N09 `MessagingStyle`, Person/shortcut/conversation presentation;
- N11 read/mute/activation/dismiss/badge semantics;
- Plan-373 iOS implementation details, N10 global logging, N12 Apple evidence;
- new relay action/protocol/provider bytes, group enumeration or rich-path
  retirement;
- live FCM, provider/Redis, Doze/OEM, token rotation deployment, cohort,
  telemetry, A-control, PRD or release acceptance.

## Test Contract

| ID | Behavior invariant | Primary test owner | Test level / causal fixture | Pre-implementation deficit -> target proof | Mutation family / mandatory counterexample | Gate |
|---|---|---|---|---|---|---|
| TC-375-01 | Exact string data-only `{v:1,w:1}` enters fixed ingress once; every other/rich shape delegates once; invalid binding consumes fixed fail-closed | `android/app/src/test/kotlin/com/mknoon/app/MknoonFirebaseMessagingServiceTest.kt::testTC37501ExactFixedWakeInterceptsAndAllOtherShapesDelegateOnce` | Robolectric real service/RemoteMessage/binding table | HEAD has no `onMessageReceived` override -> exact branch; no fixed payload reaches rich staging; missing/cross-binding does zero marker/card/schedule and zero super | subset match, numeric coercion, accept notification/extra key, call super on fixed or twice on rich, recover under wrong binding -> red | focused native |
| TC-375-02 | One binding/generation trigger/disposition record is atomic, backward compatible and exact-CAS | `DroppedPushRecoveryStoreTest::testTC37502FixedAndDeletedTriggersShareOneCrashSafeAudibleDisposition` | Robolectric SharedPreferences reopen/concurrency/crash cuts | HEAD marker has no kind/disposition -> missing means legacy deletion/may-have-alerted; fixed-only is false; fixed coalescing never downgrades true; unknown kind stays unsupported-pending; newer/account-cutover exact | split edits, reuse generation, decode legacy false, drop unknown, downgrade true, clear fields separately or evict newer/binding-B -> red | focused native |
| TC-375-03 | Fixed wake reuses the exact expedited unique chain and every worker resnapshots/adopts the newest marker | `DroppedPushRecoveryWorkSchedulerTest::testTC37503FixedWakeUsesExistingUniqueExpeditedChain`; `HeadlessCanonicalRecoveryWorkerTest::testTC37503WorkerAdoptsCurrentTriggerAcrossRetryProcessDeathAndPeriodicContinuation` | WorkManager fake clock/process reopen/enqueue failure | no fixed reason -> one reason/current marker; stale fixed/deleted/periodic input processes newer durable work; enqueue failure later converges through periodic | second unique name/worker, trust WorkRequest, periodic ignores/consumes without convergence, failure reports success -> red | focused native |
| TC-375-04 | Identity-free FCM creates no event authority; authenticated SQL materialization remains `INBOX_RECONCILER` | `test/core/bootstrap/production_headless_canonical_recovery_test.dart::TC-375-04 fixed wake carries no event authority and canonical drain remains inbox reconciler`; Plan-372 convergence test | serial real SQLite v116 + real ledger/registry | tempting synthetic event/owner -> marker only; direct/group message/reaction materialize through canonical custody | hash FCM/generation, create `RELAY_VERIFIED_UNACKED`/`ANDROID_PUSH_SERVICE`, ACK before SQL, settle ambiguous -> red | focused serial Dart |
| TC-375-05 | Fixed generic requests are always silent, fixed-only work leaves canonical tone arbitration intact, and exact fixed-point ACK retires only the current card | `test/core/notifications/local_notification_projection_convergence_test.dart::TC-375-05 fixed generic stays silent in both orders while deletion ambiguity is never downgraded`; service/store/worker crash table | serial real ledger/native fake + SQLite; fixed-before-canonical, canonical-before-fixed, overlap, callback ambiguity, coalesced deletion, multi-page/periodic continuation/new generation | audible identity-free fixed can double-sound -> silent generic plus normal exact canonical tone yields at most one requested sound; true deletion disposition persists; exact later retirement | make fixed audible, force canonical silent for fixed-only, downgrade deletion true, synthesize correlation/recent horizon, ACK/cancel before fixed point, periodic strands enqueue failure -> red | focused serial Dart/native |
| TC-375-06 | One live binding/role-epoch readiness resolver gates capabilities, producer and drainer; pair is indivisible/default false | `test/core/notifications/android_opaque_wake_readiness_test.dart::TC-375-06 live Android readback enables and retires one paired admission epoch`; extend TC-370-05/07 and the Go capability matrix with `same-token pair withdrawal invalidates opaque selection without generation advance` | host Dart native-readback fake plus Redis route fixture; construct unready, qualify A, hold bridge send, rotate/read-fail B | constructor bool can half-configure -> producer event, drain kick and last registration-send read one current epoch; mutation fences+joins the held send, and an accepted/ambiguous A frame is withdrawn before B reports healthy | platform/build-only, cached bool, stale A route survives, half pair, producer/drainer divergence, second flag or require generation advance on cap refresh -> red | focused pure Dart + exact Go |
| TC-375-07 | Primary and active-linked use exact capability sets and one coordinator for startup/token-refresh/persisted-token/three health retries | same file `::TC-375-07 primary and linked Android serialize one qualified physical route through every retry`; `test/core/services/p2p_service_impl_test.dart::TC-375-07b persisted token and every relay health retry use the one coordinator`; bootstrap/start-node sentinels | host Dart fake coordinator/role/migration/cached token plus each relay-health transition, held bridge future and cutover barrier | raw re-registration and default linked caps bypass policy -> primary direct+group+pair, linked pair-only, one frame/current epoch; cutover joins or withdraws an accepted stale frame; off/partial zero | primary-key fallback, wrong logical authority, linked reaction caps, raw health register, parallel refresh/retry, stale route, off-mode side effect -> red | focused pure Dart + 1to1 |
| TC-375-08 | One production service/store/scheduler/worker/card path preserves rich behavior and closes on a real no-Activity process | extend Plan-374 native script/runner and manifest contract | source/merged manifest + each available USB/emulator class from one APK, real WorkManager/SQLCipher/ledger | fixed injection currently falls through/unavailable -> exact service seam through process death and marker/card settlement | debug writes store directly, second component/card, Activity/manual tap, fake DB, skip or live-provider claim -> red | native host + device |

Keep this matrix parameterized. Do not create separate direct/group,
message/reaction, API-level or permission-state plans/suites.

Gate 1 owns the sole required pre-implementation assertion RED. During GREEN,
execute and revert one representative mutation for each of the six
load-bearing families named in the done criteria; `-> red` in the table states
the expected result if a listed variant is applied. The remaining variants are
mandatory review counterexamples, not a requirement to manufacture a separate
RED run for every phrase.

## TDD Implementation Sequence

1. Run the dependency/default-off preflight and re-ground the exact Plan-373/
   374 APIs plus the frozen Plan-368 provider boundary.
2. Add only a minimal compiling classifier/test seam, write TC-375-01, and
   capture its assertion-owned RED. A missing class/compile/tool error is not a
   behavioral RED.
3. Implement the exact classifier and extract one shared
   `recordGenericRecoveryTrigger` seam used by `onDeletedMessages`, fixed
   ingress and the debug-only device receiver. Preserve rich delegation; the
   fixed branch requests the one generic card explicitly silent.
4. Extend the incumbent marker with trigger kind and
   `genericMayHaveAlerted` plus exact legacy/future decode/CAS. A fixed trigger
   cannot downgrade a coalesced deletion ambiguity. Add store crash/reopen/
   concurrency barriers before scheduler or notification code changes.
5. Add `fixedWake` to the existing scheduler/worker/Dart reason. Make every
   WorkRequest adopt current durable work, including periodic recovery after
   enqueue failure. Keep all authority resnapshots, settlement, teardown and
   ACK order unchanged.
6. Prove no-synthetic-identity, fixed-before-canonical, canonical-before-fixed,
   overlap, deletion-coalescing, multi-page and periodic-continuation cases
   with real SQLite/ledger/registry tests. Fixed-only work never suppresses the
   exact canonical tone; the generic card cancels only inside the exact marker+
   binding ACK callback.
7. Extend one shared platform-readiness predicate and the one registration
   coordinator. Add logical-account authority input for linked registration,
   then prove primary/linked/off/cutover/refresh races.
8. Extend the existing native host row and device harness; add no second row or
   runner. Register any new shared Dart test exactly once in `ONE_TO_ONE_TESTS`,
   `GROUP_TESTS` and `ONE_TO_ONE_HOST_TESTS` as appropriate.
9. Run focused/preservation/curated/device gates, then the unconditional one
   adapter-wave host gate. Freeze the tested tree and create all four closure
   artifacts with standalone markers
   `N08_ANDROID_FIXED_WAKE_MECHANISM_CODE_COMPLETE` and
   `N07_N08_ADAPTER_WAVE_HOST_ALL_GREEN`.

## Risks And Stop Conditions

- A permissive `{v,w}` subset match can steal a rich message from FlutterFire.
- Treating provider metadata or recovery generation as an event identity can
  produce a false ledger terminal or destructive relay ACK.
- Posting/scheduling before durable marker commit can strand or duplicate the
  generic alert. Clearing by generation without binding can cancel a new
  account's card.
- Sampling a marker or using a recent-sound window cannot identify an event:
  a canonical callback may already be armed, and a relay may resubmit an
  identity-free wake throughout seven-day outcome retention. The fixed generic
  is therefore always silent; fixed-only work leaves canonical tone arbitration
  intact in both orders.
- Trusting WorkRequest reason/generation over the current store can consume a
  superseding wake after process death.
- Making fixed generic audible, forcing every fixed-recovered canonical card
  silent, or downgrading a coalesced deletion ambiguity breaks the deterministic
  sound contract. Cancelling before all four custody stores and ledger settle
  can lose the only visible fallback.
- A platform-only capability predicate exposes Android before the worker is
  ready; a readiness-only producer/drainer split recreates the Plan-370 half
  configuration.
- Linked physical transport is not the logical migration authority. Using one
  ID for both can deny the valid route or register the wrong mailbox.
- If implementing fixed wake requires a new protocol, native inbox/decrypt
  service, event-correlation guess, second store/worker/card family, DB
  migration or duplicated token coordinator, stop and re-review. Do not hide a
  third N08 plan inside implementation.

## Device And Manual Evidence Profile

- Boundary: Android service/WorkManager/process ownership plus real SQLCipher
  and Plan-372/374 effect settlement. Run the same automated proof on each
  available USB-Android and emulator class from one immutable APK; an absent
  class records policy N/A.
- Planning-time matrix: USB Pixel 6 `21071FDF600CSC` (API 36) and emulator
  `emulator-5554` (API 37). Execution must rediscover and pin each available
  USB/emulator class; each absent class records policy N/A. Both classes reuse
  the same immutable APK and isolated per-target evidence directory.
- Extend `scripts/run_android_headless_recovery_374.sh` with `--fixed-wake`.
  The debug receiver must invoke the same production classifier/commit seam;
  direct preference writes or direct WorkManager enqueue do not count.
- Required proof: exact fixed ingress commits/schedules and requests the one
  existing generic notification without sound, one WorkManager chain, no
  Activity, Plan-374 headless direct/group drain, real
  SQLCipher v116, Plan-372 ledger/stable cards, explicitly silent fixed generic
  plus normal canonical-tone behavior in both orders, process-death/periodic
  continuation, exact generic retirement, rich delegation, zero taps/skips and
  cleanup. Device evidence records requested sound/silent flags and notification
  API calls; it does not claim that a microphone proved physical audibility.
- Robolectric owns permission denied, channel disabled and API24/30/34 branches.
  Live Google FCM, priority/TTL/collapse delivery, Doze, OEM restriction and
  token-route rollout are WP-07 evidence, not inferred from injection.
- The two available classes may run concurrently with isolated output and an
  explicit `ANDROID_SERIAL`; this is platform/process parity, not a two-peer
  topology. No iPhone/iOS target is justified.

## Gate Cadence

Run in this order:

1. Plan-373/374/368 dependency, provenance and default-off sentinels;
2. assertion-owned RED;
3. pure Dart, selected Gradle and exact Go provider tests may run concurrently
   because they use distinct artifact roots; never run two Flutter processes
   concurrently in this repo;
4. process-global SQLite/ledger/registry Dart tests serially;
5. exact preservation, then `completeness-check`, `baseline`, `1to1` and
   `groups` serially;
6. one immutable APK and each explicitly rediscovered available USB/emulator
   class, with exact policy N/A for an absent class;
7. after both prerequisite receipts validate, one normal full-host adapter
   wave; no separate core/feature sweep;
8. analyzer, formatting, shell/diff hygiene and incremental Graphify refresh.

Do not run feed, transport, performance, `core-host-all` or `feature-host-all`
without changed-file evidence. Do not repeat the broad Plan-331 real-FCM
campaign. The next full host after this adapter wave belongs to WP-07/final
rollout.

## Acceptance Gates

### 1. Assertion-owned RED

After adding a minimal compiling classifier/test shell, capture one deliberate
assertion failure:

```bash
(
  set -euo pipefail
  rm -rf build/app/test-results/testDebugUnitTest
  set +e
  ./android/gradlew -p android app:testDebugUnitTest \
    --tests 'com.mknoon.app.MknoonFirebaseMessagingServiceTest.testTC37501ExactFixedWakeInterceptsAndAllOtherShapesDelegateOnce'
  status=$?
  set -e
  test "$status" -ne 0
  xml='build/app/test-results/testDebugUnitTest/TEST-com.mknoon.app.MknoonFirebaseMessagingServiceTest.xml'
  test -f "$xml"
  test "$(xmllint --xpath 'string(/testsuite/@tests)' "$xml")" = 1
  test "$(xmllint --xpath 'string(/testsuite/@failures)' "$xml")" = 1
  test "$(xmllint --xpath 'string(/testsuite/@errors)' "$xml")" = 0
  test "$(xmllint --xpath 'string(/testsuite/@skipped)' "$xml")" = 0
)
```

Compile/load/tool failure is not RED. Keep the XML as causal evidence, then
remove the deliberate failing assertion during GREEN.

### 2. Focused Dart GREEN

Pure readiness/registration/source tests:

```bash
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan375-pure.XXXXXX)"
  events="$(mktemp /tmp/plan375-pure-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  flutter test --no-pub --machine --concurrency=4 \
    test/core/notifications/android_opaque_wake_readiness_test.dart \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    test/core/services/p2p_service_impl_test.dart \
    --name 'TC-375-(06|07b?) ' >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  for label in 'TC-375-06 ' 'TC-375-07 ' 'TC-375-07b '; do
    test "$(jq -s --arg label "$label" '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg label "$label" '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type=="testStart" and .test.url!=null)] | length' "$events")" -eq 3
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)
```

Process-global SQLite/ledger/registry tests:

```bash
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan375-serial.XXXXXX)"
  events="$(mktemp /tmp/plan375-serial-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  flutter test --no-pub --machine --concurrency=1 \
    test/core/bootstrap/production_headless_canonical_recovery_test.dart \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    --name 'TC-375-(04|05) ' >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  for label in 'TC-375-04 ' 'TC-375-05 '; do
    test "$(jq -s --arg label "$label" '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg label "$label" '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($label))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type=="testStart" and .test.url!=null)] | length' "$events")" -eq 2
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)
```

Re-pin finalized Plan-374/372 paths after their receipts land; never let a
missing planned test turn this command into a vacuous pass.

### 3. Focused Android native GREEN

Do not register a second host item. Extend
`scripts/test/run_android_headless_recovery_native_374.sh` and its exact method
manifest with TC-375 service/store/scheduler/worker/readiness tests.

```bash
(
  set -euo pipefail
  bash -n scripts/test/run_android_headless_recovery_native_374.sh
  ./scripts/run_host_test_gates.sh host-all \
    --only scripts/test/run_android_headless_recovery_native_374.sh
)
```

The script invokes one Gradle command with exact class selectors, parses only
the selected `TEST-*.xml` files and requires every frozen TC-375 method exactly
once, every post-Plan-374 expected test counted, and failures/errors/skips all
zero. It also runs the merged-manifest/source/build contracts. Re-pin the
post-Plan-374 class totals from its receipt; Gradle `BUILD SUCCESSFUL` alone is
not evidence.

### 4. Exact provider and relay preservation

```bash
(
  set -euo pipefail
  regex='^(TestRelayNotificationClosure_OpaqueWakeRouteSelectionAndLegacyCompatibility|TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest|TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix)$'
  expected="$(mktemp /tmp/plan375-go-expected.XXXXXX)"
  listed="$(mktemp /tmp/plan375-go-listed.XXXXXX)"
  log="$(mktemp /tmp/plan375-go-run.XXXXXX)"
  redis_log="$(mktemp /tmp/plan375-go-redis-cap-refresh.XXXXXX)"
  trap 'rm -f "$expected" "$listed" "$log" "$redis_log"' EXIT
  cat >"$expected" <<'EOF'
TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest
TestRelayNotificationClosure_OpaqueWakeRouteSelectionAndLegacyCompatibility
TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix
EOF
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -list "$regex") \
    | rg '^Test' | sort >"$listed"
  diff -u "$expected" "$listed"
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 \
    go test . -run "$regex" -count=1 -v) | tee "$log"
  test "$(rg -c '^--- PASS: TestRelayNotificationClosure_' "$log")" -eq 3
  rg -Fq -- '--- PASS: TestRelayNotificationClosure_WakeOutcomeCapabilityAndLegacyMatrix/same-token_pair_withdrawal_invalidates_opaque_selection_without_generation_advance' "$log"
  ! rg -q '^[[:space:]]*--- SKIP:' "$log"

  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_PushRouteDirectoryCiphertextAndGenerationContract$/^capability_refresh_crossing_Redis_resolve_is_stale_not_integrity_failure$' \
    -count=1 -v) | tee "$redis_log"
  rg -Fq -- '--- PASS: TestRelayNotificationClosure_PushRouteDirectoryCiphertextAndGenerationContract/capability_refresh_crossing_Redis_resolve_is_stale_not_integrity_failure' "$redis_log"
  ! rg -q '^[[:space:]]*--- SKIP:' "$redis_log"
)
```

The Android provider root is Plan 368's real Firebase Admin SDK HTTP-capture
table: it compares the decoded exact request map for all 22 source-eligible
producer fixtures and exercises real-store zero-request controls. It is not a
single builder-only assertion, raw-JSON ordering claim or live FCM delivery
proof. The relay/provider implementation is unchanged; do not add relay-all or
a Go family sweep.

### 5. Exact Dart and Kotlin preservation

After re-pinning these exact labels from the accepted Plan-372/374 receipts,
run one serial machine-counted bundle:

```bash
(
  set -euo pipefail
  raw="$(mktemp /tmp/plan375-preservation.XXXXXX)"
  events="$(mktemp /tmp/plan375-preservation-events.XXXXXX)"
  trap 'rm -f "$raw" "$events"' EXIT
  names=(
    'TC-370-05 opaque outcome uses strict all-relay completion'
    'TC-370-07 production composes one default-off outcome admission and one shared drain callback'
    'TC-371-01 v1 codec and fresh exact predicate fail toward notification'
    'TC-372-01 v1 codec and state machine accept only legal monotonic transitions'
    'TC-372-06 effect-terminal replay settles direct and group custody once and emits only approved enabled outcome'
    'TC-374-01 '
    'TC-374-02 '
    'TC-374-04 '
    'TC-374-05 '
    'TC-374-07 '
    'deleted batch converges, closes and releases before exact ack'
    'new deletion during drain defeats stale ack and remains pending'
    'pinned FlutterFire background callbacks use one unbounded serial queue'
  )
  regex="$(IFS='|'; printf '%s' "${names[*]}")"
  flutter test --no-pub --machine --concurrency=1 \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    test/core/bootstrap/flutterfire_background_queue_contract_test.dart \
    test/core/notifications/app_visibility_snapshot_test.dart \
    test/core/notifications/local_notification_ledger_test.dart \
    test/core/notifications/local_notification_projection_convergence_test.dart \
    test/core/bootstrap/production_headless_canonical_recovery_test.dart \
    test/core/notifications/canonical_recovery_runtime_test.dart \
    test/core/notifications/dropped_push_recovery_coordinator_test.dart \
    test/core/notifications/canonical_runtime_lease_test.dart \
    test/core/notifications/headless_canonical_recovery_entrypoint_test.dart \
    test/core/bootstrap/main_bootstrap_boundary_test.dart \
    --name "$regex" >"$raw"
  jq -c 'select(type == "object")' "$raw" >"$events"
  for name in "${names[@]}"; do
    test "$(jq -s --arg name "$name" '[.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($name)))] | length' "$events")" -eq 1
    id="$(jq -r -s --arg name "$name" '.[] | select(.type=="testStart" and .test.url!=null and (.test.name|contains($name))) | .test.id' "$events")"
    test "$(jq -s --argjson id "$id" '[.[] | select(.type=="testDone" and .testID==$id and .result=="success" and .skipped==false)] | length' "$events")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type=="testStart" and .test.url!=null)] | length' "$events")" -eq "${#names[@]}"
  test "$(jq -s '[.[] | select(.type=="testDone" and .skipped==true)] | length' "$events")" -eq 0
)
```

The extended native script separately preserves the exact deleted-batch,
periodic, permission, binding-rotation, newest-generation, worker-cleanup,
Firebase-service and merged-manifest methods from the frozen Plan-374 method
manifest. Do not encode a global repository test count.

### 6. Registration and curated lanes

Any new shared Dart owner is registered exactly once in the relevant arrays;
existing files are not duplicated. Prove the one new shared owner before the
curated lanes:

```bash
(
  set -euo pipefail
  array_count() {
    script_path="$1"
    array_name="$2"
    test_path="$3"
    awk -v header="readonly ${array_name}=(" -v wanted="$test_path" '
      $0 == header { inside = 1; next }
      inside && $0 == ")" { inside = 0 }
      inside {
        line = $0
        sub(/^[[:space:]]*"/, "", line)
        sub(/"[[:space:]]*$/, "", line)
        if (line == wanted) count++
      }
      END { print count + 0 }
    ' "$script_path"
  }
  shared='test/core/notifications/android_opaque_wake_readiness_test.dart'
  test "$(array_count scripts/run_test_gates.sh ONE_TO_ONE_TESTS "$shared")" -eq 1
  test "$(array_count scripts/run_test_gates.sh GROUP_TESTS "$shared")" -eq 1
  test "$(array_count scripts/run_host_test_gates.sh ONE_TO_ONE_HOST_TESTS "$shared")" -eq 1

  ./scripts/run_test_gates.sh completeness-check
  ./scripts/run_test_gates.sh baseline
  ./scripts/run_test_gates.sh 1to1
  ./scripts/run_test_gates.sh groups
)
```

Run serially. Baseline is justified by `main.dart`/bootstrap/headless
composition, while both messaging lanes consume the fixed-point graph and
ledger. Do not add feed/transport or unsupported batching flags.

### 7. Availability-bounded Android proof

```bash
(
  set -euo pipefail
  mkdir -p build
  run_root="$(mktemp -d build/plan375.XXXXXX)"
  mkdir -p "$run_root/device" "$run_root/apk"
  printf '%s\n' "$run_root" >build/plan375-latest-run.txt
  flutter devices --machine >"$run_root/flutter-devices.json"
  adb devices -l >"$run_root/adb-devices.txt"

  emulator_id="$(awk '$2=="device" && $1 ~ /^emulator-/ {print $1; exit}' "$run_root/adb-devices.txt")"
  usb_id="$(awk '$2=="device" && $1 !~ /^emulator-/ && $0 ~ /(^|[[:space:]])usb:/ {print $1; exit}' "$run_root/adb-devices.txt")"
  : >"$run_root/targets.tsv"
  if test -n "$emulator_id"; then printf 'emulator\t%s\n' "$emulator_id" >>"$run_root/targets.tsv"; else printf 'N/A (emulator unavailable by project policy)\n' >"$run_root/emulator-disposition.txt"; fi
  if test -n "$usb_id"; then printf 'usb\t%s\n' "$usb_id" >>"$run_root/targets.tsv"; else printf 'N/A (USB Android unavailable by project policy)\n' >"$run_root/usb-disposition.txt"; fi
  if ! test -s "$run_root/targets.tsv"; then
    printf 'N/A (no Android target available by project policy)\n' >"$run_root/device-disposition.txt"
    exit 0
  fi

  apk="$run_root/apk/app-plan375-fixed-wake-debug.apk"
  scripts/run_android_headless_recovery_374.sh \
    --build-only --fixed-wake --apk-output "$apk" \
    --output "$run_root/build"
  test -f "$apk"
  shasum -a 256 "$apk" >"$run_root/apk.sha256"

  pids=''
  while IFS="$(printf '\t')" read -r target_class target_id; do
    (
      ANDROID_SERIAL="$target_id" scripts/run_android_headless_recovery_374.sh \
        --device-id "$target_id" --apk "$apk" --skip-build --fixed-wake \
        --production-fixed-ingress-seam --no-activity --process-death \
        --output "$run_root/device/$target_class"
    ) &
    pids="$pids $!"
  done <"$run_root/targets.tsv"
  device_status=0
  for pid in $pids; do
    if ! wait "$pid"; then device_status=1; fi
  done
  test "$device_status" -eq 0
)
```

The runner records exact target/APK/source/nonce, scenario count, marker/lease
transitions, generic and per-conversation notification IDs/channels/sound
facts, WorkManager attempt, SQLCipher/ledger owners, process-death continuation,
rich-delegate canary, Activity count zero, zero skips/taps and cleanup. Each
unavailable target class is policy N/A; do not wait for a model or API band.

### 8. One N07+N08 adapter-wave host aggregate

This is mandatory for the combined adapter-wave marker, but only after Plan
373 and Plan 374 both have valid committed receipts:

```bash
(
  set -euo pipefail
  for plan in 373 374; do
    receipt="Test-Flight-Improv/evidence/${plan}/README.md"
    checksum="Test-Flight-Improv/evidence/${plan}/README.md.sha256"
    test -f "$receipt"
    test -f "$checksum"
    (cd "Test-Flight-Improv/evidence/${plan}" && shasum -a 256 -c README.md.sha256)
    receipt_commit="$(git log -n 1 --format=%H -- "$receipt")"
    base="$(awk -F'`' '/\| (Base( and unchanged)? HEAD|Base HEAD) \|/ {print $2; exit}' "$receipt")"
    test -n "$receipt_commit"
    [[ "$base" =~ ^[0-9a-f]{40}$ ]]
    git merge-base --is-ancestor "$base" "$receipt_commit"
    git merge-base --is-ancestor "$receipt_commit" HEAD
    cmp -s <(git show "${receipt_commit}:${receipt}") "$receipt"
    cmp -s <(git show "${receipt_commit}:${checksum}") "$checksum"
  done
  rg -Fqx 'N07_IOS_NSE_OPAQUE_WAKE_ADAPTER_CODE_COMPLETE_IOS_EVIDENCE_DEFERRED' \
    Test-Flight-Improv/evidence/373/README.md
  rg -Fqx 'N08_PRODUCTION_HEADLESS_CANONICAL_RECOVERY_CODE_COMPLETE' \
    Test-Flight-Improv/evidence/374/README.md

  dry="$(mktemp /tmp/plan375-wave-dry.XXXXXX)"
  trap 'rm -f "$dry"' EXIT
  ./scripts/run_host_test_gates.sh host-all --dry-run >"$dry"
  test "$(rg -c '^ *[0-9]+\. bash scripts/test/run_ios_nse_native_373\.sh$' "$dry")" -eq 1
  test "$(rg -c '^ *[0-9]+\. bash scripts/test/run_android_headless_recovery_native_374\.sh$' "$dry")" -eq 1

  ./scripts/run_host_test_gates.sh host-all \
    --batch-flutter --concurrency 4 --reporter failures-only
)
```

Both prerequisite receipts are mandatory before Plan-375 RED, so this aggregate
must run once at closure. Do not substitute `--dart-only`; the purpose is to
rediscover both registered native adapters once.

### 9. Hygiene and graph

```bash
(
  set -euo pipefail
  gofmt_diff="$(mktemp /tmp/plan375-gofmt.XXXXXX)"
  trap 'rm -f "$gofmt_diff"' EXIT
  dart_paths="$(
    {
      git diff --name-only --diff-filter=ACMRT -- '*.dart'
      git diff --cached --name-only --diff-filter=ACMRT -- '*.dart'
      git ls-files --others --exclude-standard -- '*.dart'
    } | sort -u
  )"
  while IFS= read -r dart_path; do
    test -z "$dart_path" && continue
    dart format --output=none --set-exit-if-changed "$dart_path"
  done <<EOF
$dart_paths
EOF
  go_paths="$(
    {
      git diff --name-only --diff-filter=ACMRT -- '*.go'
      git diff --cached --name-only --diff-filter=ACMRT -- '*.go'
      git ls-files --others --exclude-standard -- '*.go'
    } | sort -u
  )"
  while IFS= read -r go_path; do
    test -z "$go_path" && continue
    gofmt -d "$go_path"
  done <<EOF >"$gofmt_diff"
$go_paths
EOF
  test ! -s "$gofmt_diff"
  git diff --check
  git diff --cached --check
  bash -n scripts/run_host_test_gates.sh scripts/run_test_gates.sh
  bash -n scripts/test/run_android_headless_recovery_native_374.sh
  bash -n scripts/run_android_headless_recovery_374.sh
  flutter analyze
  ./graphify-arch/refresh_arch_graph.sh --incremental
  python3 graphify-arch/tdd_context.py query \
    'Plan 375 Android exact fixed wake Firebase service silent generic disposition WorkManager paired readiness rich fallback' \
    --profile review --budget 800 --ensure-fresh
)
```

### 10. Closure provenance and repository bookkeeping

After every accepted gate and the final Graphify refresh, freeze the exact
tested product/test/script/fixture/Graphify bytes with an alternate Git index
before changing closure-only documents. Capture the current base `HEAD`, its
tree, the frozen tested tree, the complete porcelain-v2 workspace snapshot and
SHA-256, shared/alternate-index identities, Graphify fingerprint and graph
artifact hashes. The freeze must exclude the later receipt, status, index and
coverage edits; no product/test byte may change after it.

Create and commit all four provenance artifacts:

- `Test-Flight-Improv/evidence/375/README.md`;
- `Test-Flight-Improv/evidence/375/README.md.sha256`;
- `Test-Flight-Improv/evidence/375/workspace-porcelain-v2.txt.gz`, produced
  deterministically with `gzip -n` from the exact captured snapshot;
- `Test-Flight-Improv/evidence/375/graphify-fingerprint.txt`, containing only
  the exact 16-lowercase-hex fingerprint and newline.

The receipt must independently bind and rehash those artifacts, the dependency
receipt commits, the RED XML, every focused/preservation/curated/native/device
result and the unconditional adapter-wave `host-all`. It must record these two
success markers as separate exact standalone raw lines:

```text
N08_ANDROID_FIXED_WAKE_MECHANISM_CODE_COMPLETE
N07_N08_ADAPTER_WAVE_HOST_ALL_GREEN
```

Only after the frozen identities are captured, check the Plan-375 done boxes
and append its execution-progress rows; append the Plan-375 closure lines to
`STATUS.md`; update its plan and evidence rows in
`Test-Flight-Improv/00-INDEX.md`; and update the GAP-N08 implementation status,
counts and percentages in
`UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`.
Rehash the final README, re-run diff/shell hygiene over the closure bytes, stage
only Plan-375 scope, commit it as one plan-specific commit, and require a clean
worktree before looking for the next sequential plan.

## Execution Interpretation And Done Criteria

- [ ] Plan-373/374 committed receipts, artifacts, ancestry and finalized
      source/test/API names validate; post-Plan-374 product drift is empty.
      Plan-368 receipt/provider API/test and Plan-370 default-off sentinels pass.
- [ ] TC-375-01 has the one assertion-owned pre-implementation RED described by
      Gate 1. TC-375-01 through TC-375-08 then have causal GREEN evidence.
      Representative mutations re-red the six load-bearing seams: exact
      classifier, current-marker resnapshot, no synthetic authority, cross-path
      sound policy, paired readiness and linked logical/physical identity. The
      other table mutations remain mandatory review counterexamples, not
      duplicate mutation executions.
- [ ] Exactly one app-owned FCM service intercepts only exact fixed data and
      delegates every nonfixed/rich message to FlutterFire once.
- [ ] One existing binding/generation store owns both trigger kinds and one
      conservative audible disposition; fixed coalescing cannot downgrade an
      incumbent deletion ambiguity, and no second persistent/notification
      family exists.
- [ ] Fixed/deleted/periodic work uses one scheduler/worker/engine/runtime;
      current state wins stale WorkRequest input and failures preserve work.
- [ ] Fixed provider fields mint no event identity, ledger/SQL/outcome or relay
      ACK. Plan-374 canonical SQL materialization remains `INBOX_RECONCILER`.
- [ ] Fixed generic requests are visibly present but explicitly silent in both
      arrival orders; fixed-only work retains normal exact canonical tone
      arbitration. Exact generic retirement happens only after final
      convergence/ACK, and periodic work recovers an enqueue failure.
- [ ] One effective default-false predicate gates both capabilities, outcome
      producer and drainer; primary/active-linked routes use exact logical and
      physical authority through one registration coordinator.
- [ ] Focused Dart/native/Go and exact preservation pass with exact selection,
      success and zero-skip evidence.
- [ ] `completeness-check`, baseline, `1to1` and `groups` pass serially.
- [ ] Each rediscovered available USB-Android/emulator class passes the same
      immutable-APK, no-Activity, process-death fixed-wake proof in isolated
      parallel output; each absent class records exact policy N/A.
- [ ] The unconditional Plan-375 closure run contains one and only one N07+N08
      adapter-wave full host gate and rediscovers both synthetic native items
      once.
- [ ] No core/feature/performance sweep, broad Plan-331 campaign, live FCM/Doze/
      OEM claim, activation or release action is performed.
- [ ] Analyzer, changed+untracked Dart formatting, changed-Go `gofmt` zero-diff,
      both main gate-runner and both Android-runner `bash -n` checks, staged and
      unstaged diff hygiene, and fresh Graphify review pass.
- [ ] The four checksum-bound evidence artifacts exist and rehash. The receipt
      records `N08_ANDROID_FIXED_WAKE_MECHANISM_CODE_COMPLETE` and
      `N07_N08_ADAPTER_WAVE_HOST_ALL_GREEN` as separate standalone raw lines.
- [ ] Plan/progress, `STATUS.md`, `00-INDEX.md` and GAP-N08 coverage/counts are
      updated only after the tested-tree freeze; one Plan-375 commit contains
      exactly the reviewed scope and leaves a clean worktree.

Meeting these criteria completes the second and final GAP-N08 mechanism slice
over Plan 374's already-closed Plan-331 production tail. It does not by itself
enable the paired capability, prove live FCM/provider/Doze/OEM delivery, close
N09 or N11, accept PRD controls, or make a release eligible.

## Handoff

- N09 may add Android `MessagingStyle`/Person/conversation projection over the
  stable private cards; it must not change this ingress/ledger authority.
- N11 owns read, mute, activation, dismiss, badge and cleanup semantics.
- WP-07 owns cohort activation, same-token route replacement/revoke, live
  provider/Redis/FCM/Doze/OEM evidence, rich retirement, telemetry, rollback
  drill, A-control acceptance and release closure.
- N12 retains consolidated Apple device evidence. No third N08 implementation
  slice is warranted; continue the sequence only when a separately scoped next
  plan actually exists.

## Reviewer Findings

Independent `$tdd-review` result: **PASS after material in-place corrections**.

- Claims and boundary: PASS. The identity-free `{v,w}` wake is only a durable
  mailbox trigger. It cannot mint correlation, SQL, v116, ledger state,
  `ANDROID_PUSH_SERVICE`, `RELAY_VERIFIED_UNACKED` or relay ACK authority;
  Plan 374 remains the sole `INBOX_RECONCILER` materializer.
- Causal state and sound safety: PASS. Every fixed generic request is visible
  but explicitly silent, so both fixed-before-canonical and
  canonical-before-fixed request at most one sound without inventing an event
  identity or seven-day global mute. Legacy/deleted-batch audible ambiguity is
  conservative and cannot be downgraded by fixed coalescing. Current durable
  marker state wins stale WorkRequest reasons, including periodic recovery
  after enqueue failure.
- Alternate paths and cutover: PASS. Exact fixed data is consumed only by the
  app-owned service; all other/rich shapes delegate once. Persisted-token
  restore and all three relay-health retries enter the one registration
  coordinator. Binding/role/readiness mutation fences and joins a held send;
  accepted or ambiguous stale routes are withdrawn/replaced before the new
  epoch reports healthy.
- Gate integrity: PASS. Focused pure and process-global Dart legs are split,
  Gradle XML and Go root/subtest results are counted, shared registration is
  exact-once, and all Bash fences parse. One fresh immutable APK drives each
  rediscovered available USB/emulator class in isolated parallel evidence;
  an absent class is policy N/A.
- Operability and economy: PASS. The existing store, card, scheduler, worker,
  graph, ledger seam, registration coordinator, native host row and device
  runner are extended rather than duplicated. Focused/preservation and the
  affected curated lanes precede one N07+N08 wave `host-all`; no core/feature
  duplicate, live-provider campaign or third N08 plan is justified.

## Arbiter Decision

**READY AS A CONTRACT, EXECUTION BLOCKED ON PLANS 373 AND 374.** Plan 375 is the
second and final N08 mechanism slice. Re-review only if either prerequisite
changes the shared readiness owner, production headless graph, ledger/effect
API, registration coordinator or native marker semantics. Do not hide such a
change in an unplanned third N08 slice, second worker/store/card, new protocol,
synthetic event identity or broadened rollout plan.

## Execution Progress

| Time | Step | RED evidence | GREEN evidence | Refactor / regression | Evidence path |
|---|---|---|---|---|---|
| pending | TC-375-00 prerequisite | Committed Plan-373/374 receipts and clean post-Plan-374 product baseline are not yet validated | pending | No production execution authorized | pending |
