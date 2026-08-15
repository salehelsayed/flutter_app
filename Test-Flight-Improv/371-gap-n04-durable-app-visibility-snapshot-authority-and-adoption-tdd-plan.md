# 371 - GAP-N04 Durable App Visibility Snapshot Authority And Adoption

Status: **POST_EXECUTION_AUDIT_CLOSED / N04 APP VISIBILITY AUTHORITY FOUNDATION CODE COMPLETE / HOST+NATIVE+AVAILABLE-ANDROID VERIFIED / N04 FOUNDATION ONLY / NOT N03-COMPLETE / NOT LIVE-ACCEPTED / NOT RELEASE-ELIGIBLE**
Type: Modification
Spec inputs: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §§6 and 8, A-21/A-22/A-23/A-24 and AC-01 through AC-04; §9, A-28 and AC-06/AC-07 are downstream N05 prerequisites, not Plan-371 closure claims; GAP-N04 / WP-03 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`
Classification: execution-ready single GAP-N04 authority/current-adopter slice
Closure tier: host/native plus one availability-bounded Android device lifecycle proof; Apple device acceptance remains GAP-N12

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-15 | Evidence Collector | Plans 369/370 commits and checksum-bound receipts; worktree; N03 capability/admission composition | Plan 370 commit `b90455347f64bd102056bc13d62d89fe5e379cb9` is the clean successor baseline and directly contains Plan 369 commit `ddf4b1459187b074128213e72b8456bd44e39cef`. Both receipts, committed receipt blobs, markers, and frozen trees validate. | Pin one execution baseline plus both receipt identities; never edit the receipts. |
| 2026-08-15 | Executor | Reviewed Plan-371 planning transaction; clean-worktree requirement | The five allowlisted planning documents were preserved in docs-only commit `9be694a19e4f17973e447f8b98c8167b9881fd74`, whose direct parent is the accepted Plan-370 commit and whose tree has no product/test/native/script drift. | Re-freeze execution at the docs-only commit before authoring RED. |
| 2026-08-15 | Planner using `$tdd-plan` | Graphify TDD context; `ActiveConversationTracker`; `maybeShowNotification`; root lifecycle/route observer; direct/group/linked routes; native lifecycle/storage seams; gates and device matrix | GAP-N04 has one authority, one rollback/failure policy, and one current Flutter adoption boundary. Splitting by foundation/platform/adopter would create unused or inconsistent state. | Write one bounded Plan 371 and register its shared tests in both affected curated lanes. |
| 2026-08-15 | Native boundary verifier | `AppDelegate`, `MainActivity`, iOS App Group recovery store, Android manifest/store precedent, Runner/NSE build membership | iOS needs real cross-process atomic storage and a required-reason privacy manifest; Android is one process today and needs one synchronously committed whole-value store. | Prove both codecs/stores natively; do not adopt NSE/FCM rendering in N04. |
| 2026-08-15 | Independent reviewers using `$tdd-review` | Full draft plus route-open, protected-group replay/SQLite, presence timer, iOS lifecycle/storage/privacy, Android Gradle/instrumentation, registration and availability contracts | Core one-plan bet is sound. The first draft conflated route-stack dedupe with notification suppression, under-proved protected staging, left native boot/failure/duplicate-transition semantics ambiguous, and contained vacuous/static gate commands. | Apply the bounded redlines in place; add no plan, DB, renderer, ledger, or scheduler. |
| 2026-08-15 | Planner/arbiter | Revised contract and every executable fence; exact dependency preflight; eight preservation sentinels; Graphify review context | All three independent lenses pass after in-place fixes. Dependency preflight passes, bash fences parse, and the current preservation bundle is 8 selected / 8 matched successes / 0 skips. | Mark execution-ready; begin only with TC-371-00 then the assertion RED. |

## Problem And Evidence

- Behavior to improve: a notification may be suppressed only when one current,
  fresh authority proves `FOREGROUND_ACTIVE` and the exact frontmost local
  conversation. Chat B, a non-chat route, inactive/background state, or any
  unknown/stale state must notify.
- Impact: the current mounted-screen tracker can remain active after the app is
  covered or backgrounded. That can turn a required recovery notification into
  a persistence-only event.
- Confirmed current gap:
  - `ActiveConversationTracker` at
    `lib/core/notifications/active_conversation_tracker.dart:5-49` stores only
    one in-memory normalized string; it has no lifecycle, freshness, native
    projection, boot identity, or atomic revision.
  - production constructs separate direct and group trackers at
    `lib/app/bootstrap/production_application_bootstrap.dart:5639` and `:5997`;
    they are not one notification authority;
  - `maybeShowNotification` at
    `lib/features/push/application/show_notification_use_case.dart:70-129`
    samples a lifecycle getter and tracker once, with no freshness contract;
  - notification-facing production getters still use `null => resumed` in
    bootstrap and `application_root.dart:2750-2751`;
  - direct and ordinary-group routes set a tracker during mount and clear only
    on disposal. A pushed chat/settings/modal can leave the covered route
    apparently visible. Linked-group improves lifecycle clearing but still
    treats null as resumed and is not top-route aware;
  - raw notification-presentation bypasses remain in the foreground
    group-reaction resolver, unanchored-group fallback, group canonical
    reconciler, and protected group display staging. Notification-open route
    dedupe is a separate process-local route-stack identity predicate and must
    not be migrated to freshness-based suppression eligibility.
- Existing coverage: `show_notification_use_case_test.dart` proves the coherent
  `resumed + exact tracker` happy path; direct private-media route tests prove
  one root `RouteObserver`; Plans 369/370 prove durable outcomes and the bounded
  relay coordinator. None proves a fresh cross-runtime visibility record.
- Missing coverage: corrupt/stale/reboot/clock-rollback state, route coverage
  and restoration, delayed route-versus-pause ordering, atomic native storage,
  cross-runtime key parity, and real Android lifecycle callbacks.
- Confirmed highest-risk native fact: iOS Runner and NSE are separate processes
  and share the existing App Group, while Android MainActivity, FCM service, and
  WorkManager currently declare no separate `android:process`.
- Affected production/test/gate files are limited to the new visibility owner,
  the existing root lifecycle/route composition, current direct/group
  notification decision callers, thin iOS/Android stores and lifecycle writers,
  focused tests, and gate registration. There is no DB migration, relay change,
  new notification ledger, or new rendering pipeline.

## Dependency Contract

Plan 371 uses one docs-only execution baseline over the frozen Plan-370
implementation predecessor:

- Plan 371 reviewed planning commit / current execution baseline:
  `9be694a19e4f17973e447f8b98c8167b9881fd74`, tree
  `d31e890195b200444076cf14dfb664f54559cc06`;
- its direct parent and Plan 370 implementation commit:
  `b90455347f64bd102056bc13d62d89fe5e379cb9`, tree
  `8d386473c747f1318945124f7c94b797843a46e0`;
- Plan 370's direct parent and Plan 369 closure commit:
  `ddf4b1459187b074128213e72b8456bd44e39cef`, tree
  `e24ba92b8c6d65ec24cb40d7ee2b4297075c02f1`;
- Plan 369 receipt SHA-256
  `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c`,
  frozen tree `61e1b1935a022e7ad0f54d207549903a728e9b86`, marker
  `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE`;
- Plan 370 receipt SHA-256
  `14af6bddc18cda365b1bda36bc69d1c0d23b5f7106dc6f9f72e04641eada0b04`,
  frozen tree `79664ab276372316833a03de0c90c3423c6129f4`, marker
  `N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE`.

The receipts freeze their tested dirty trees but cannot self-bind their later
closure commits, so both commit SHAs and both receipt identities are pinned.
Plan 370 transitively preserves N02 and N01 mechanism receipts; duplicate
Plan-366/367/368 preflights are not required. N01 S2/B1b, N02 live provider
migration, N03 activation, live provider/Redis, and release acceptance are not
Plan-371 prerequisites.

The N03 paired capability/producer/drainer seam must remain default `false`.
Plan 371 does not emit `inChat` or `suppressedPolicy`, advertise
`opaque_wake_v1`/`wake_outcome_v1`, or turn on delayed wake.

```bash
(
  set -euo pipefail
  p371docs='9be694a19e4f17973e447f8b98c8167b9881fd74'
  p369='ddf4b1459187b074128213e72b8456bd44e39cef'
  p370='b90455347f64bd102056bc13d62d89fe5e379cb9'
  r369='8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c'
  r370='14af6bddc18cda365b1bda36bc69d1c0d23b5f7106dc6f9f72e04641eada0b04'

  test "$(git rev-parse HEAD)" = "$p371docs"
  test "$(git rev-parse "${p371docs}^")" = "$p370"
  test "$(git rev-parse "${p371docs}^{tree}")" = \
    'd31e890195b200444076cf14dfb664f54559cc06'
  test "$(git rev-parse "${p370}^")" = "$p369"
  test "$(git rev-parse "${p369}^")" = \
    '8d86501e46f1a06e724daf8009cd3bf0f807578c'
  test "$(git rev-parse "${p369}^{tree}")" = \
    'e24ba92b8c6d65ec24cb40d7ee2b4297075c02f1'
  test "$(git rev-parse "${p370}^{tree}")" = \
    '8d386473c747f1318945124f7c94b797843a46e0'

  # The clean execution baseline differs from Plan 370 only by the reviewed
  # planning transaction enumerated below.
  test "$(git diff --name-only "$p370..$p371docs" | sort)" = "$(printf '%s\n' \
    STATUS.md \
    Test-Flight-Improv/00-INDEX.md \
    Test-Flight-Improv/370-gap-n03-authenticated-bounded-wake-outcome-coordinator-tdd-plan.md \
    Test-Flight-Improv/371-gap-n04-durable-app-visibility-snapshot-authority-and-adoption-tdd-plan.md \
    UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md | sort)"

  # The accepted execution tree may coexist only with these planning docs.
  # Any product, test, native, fixture, or script drift invalidates the pin.
  while IFS= read -r changed; do
    test -z "$changed" && continue
    case "$changed" in
      STATUS.md|\
      Test-Flight-Improv/00-INDEX.md|\
      Test-Flight-Improv/370-gap-n03-authenticated-bounded-wake-outcome-coordinator-tdd-plan.md|\
      Test-Flight-Improv/371-gap-n04-durable-app-visibility-snapshot-authority-and-adoption-tdd-plan.md|\
      UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md) ;;
      *) printf 'Unexpected baseline drift: %s\n' "$changed" >&2; exit 1 ;;
    esac
  done < <(
    {
      git diff --name-only
      git diff --cached --name-only
      git ls-files --others --exclude-standard
    } | sort -u
  )

  test "$(shasum -a 256 Test-Flight-Improv/evidence/369/README.md |
    awk '{print $1}')" = "$r369"
  test "$(shasum -a 256 Test-Flight-Improv/evidence/370/README.md |
    awk '{print $1}')" = "$r370"
  (cd Test-Flight-Improv/evidence/369 &&
    shasum -a 256 -c README.md.sha256)
  (cd Test-Flight-Improv/evidence/370 &&
    shasum -a 256 -c README.md.sha256)

  test "$(git show "${p369}:Test-Flight-Improv/evidence/369/README.md" |
    shasum -a 256 | awk '{print $1}')" = "$r369"
  test "$(git show "${p370}:Test-Flight-Improv/evidence/370/README.md" |
    shasum -a 256 | awk '{print $1}')" = "$r370"
  rg -Fqx 'N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE' \
    Test-Flight-Improv/evidence/369/README.md
  rg -Fqx 'N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE' \
    Test-Flight-Improv/evidence/370/README.md
  git cat-file -e \
    '61e1b1935a022e7ad0f54d207549903a728e9b86^{tree}'
  git cat-file -e \
    '79664ab276372316833a03de0c90c3423c6129f4^{tree}'
)
```

Stop if the exact baseline has changed in product/test/native/script files. A
docs-only planning commit may be re-frozen explicitly; do not silently weaken
the preflight.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `1cd2db6f3341312b`; current and anchored.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "GAP-N04 AppVisibilitySnapshot ActiveConversationTracker maybeShowNotification application_root RouteObserver AppDelegate MainActivity fail stale exact visible conversation" --profile tdd --budget 700`
- Independent counterexample query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 371 GAP-N04 AppVisibilitySnapshot counterexamples freshness heartbeat lifecycle generation route observer maybeShowNotification native iOS Android bypass gate device" --profile review --budget 800`; it returned the same current anchored fingerprint.
- Anchors: `maybeShowNotification` ->
  `lib/features/push/application/show_notification_use_case.dart:70`;
  `ActiveConversationTracker` ->
  `lib/core/notifications/active_conversation_tracker.dart:5`; root lifecycle
  and the existing route observer were verified in source.
- Surfaced proof/gate files: `show_notification_use_case_test.dart`, both
  curated messaging arrays, root/route tests, and core host discovery.
- Graph gap: native targets and several generated/project-membership relations
  were absent from the architecture graph. Targeted Swift/Kotlin/manifest/pbx
  inspection supplied that evidence; the full fallback graph was unnecessary.

## Authority Contract

### One record and one decision

`AppVisibilitySnapshotV1` contains only:

```text
schemaVersion: 1
revision: positive signed 64-bit integer
lifecycleGeneration: positive signed 64-bit integer
lifecycle: FOREGROUND_ACTIVE | INACTIVE | BACKGROUND
visibleConversationDigest: lowercase 64-hex or null
updatedMonotonicMs: nonnegative signed 64-bit integer
bootSession: nonempty platform-local discriminator
```

- Persist no raw peer, group, username, route payload, account ID, event ID, or
  provider value. Logs contain only fixed disposition codes.
- Canonical conversation digest bytes are shared across Dart/Swift/Kotlin:
  SHA-256 of UTF-8 domain `mknoon/app-visibility/v1`, one zero byte, one lane
  byte (`0x01` direct, `0x02` group), then LP32BE length plus the UTF-8
  normalized local ID. Direct IDs are trimmed; group route/message anchors
  normalize to the exact `group:<groupId>` owner before hashing. Empty,
  malformed, noncanonical, or ambiguous input is not suppressible.
- Freeze shared JSON conformance vectors in
  `test/shared/fixtures/app_visibility_snapshot_v1.json`, including direct,
  group, anchored group, Unicode, empty, wrong-lane, and delimiter adversaries.
  Dart/Swift/Kotlin must agree on digest preimage bytes, digest bytes, decoded
  fields, bounds, and dispositions; byte-canonical JSON serialization is not a
  requirement. Values outside signed 64-bit bounds and revision overflow are
  ineligible and cannot be rewritten as v1.
  XCTest resolves that one repository fixture relative to `#filePath`; Gradle
  adds `test/shared/fixtures` as the JVM test-resource source and loads the same
  resource. Do not maintain Swift/Kotlin copies.
- Suppression eligibility is exactly:
  supported/decoded record, current boot session, nonnegative age strictly less
  than **90 seconds**, `FOREGROUND_ACTIVE`, non-null digest, and exact digest
  match. Exactly 90 seconds is stale. Missing/corrupt/truncated/future-schema,
  I/O failure, boot mismatch, monotonic rollback/future timestamp, invalid
  revision, null key, and key mismatch all mean **notify**.
- Renew unchanged foreground state every **60 seconds** through the incumbent
  `SetPresenceUseCase` heartbeat callback. The local refresh occurs before and
  independently of relay presence publication, including when the relay call
  is unavailable/unsupported. This reuses one existing timer; it does not add a
  scheduler or background service. A delayed heartbeat simply makes the record
  stale and therefore safe.

The 90/60 constants are the one engineering bound the PRD delegates to N04.
They cap crash-without-callback suppression while avoiding a high-frequency
App-Group fsync loop. Any execution-time reason to choose a different bound is a
contract change requiring this table and all three runtime vectors/tests to be
updated before RED; it is not a tunable rollout flag.

### Single owner and transition ordering

- Add one production `AppVisibilityAuthority`. It owns the in-memory immediate
  fail-safe state, serializes native bridge work, exposes the pure snapshot
  predicate, and is the only input to notification visibility decisions.
- Native code owns lifecycle, monotonic time, boot identity, revisioning, and
  persistence. Flutter publishes/clears only the normalized conversation
  digest and the lifecycle generation it observed.
- Launch, inactive, background, and resume transitions clear the visible key.
  Resume writes `FOREGROUND_ACTIVE + null`; Flutter republishes the current top
  route only after activation is observed.
- Route/heartbeat writes are compare-and-set against the native lifecycle
  generation and are accepted only while the native record is still
  `FOREGROUND_ACTIVE`. A delayed Flutter route write can never overwrite a
  newer pause/background transition.
- The root `ApplicationRoot` lifecycle callback invalidates the Dart authority
  synchronously before launching existing async resume/pause work. Native
  lifecycle callbacks persist the same transition synchronously.
- One native write replaces the whole record and advances both revision and,
  when applicable, lifecycle generation. On an atomic-write failure the old
  complete record may remain on disk, but the current-process decision is
  marked ineligible; no cached active value is a failure fallback. A separate
  iOS reader cannot observe an invalidation that never reached storage, so the
  old record is an explicitly bounded lease and can remain eligible only until
  the strict 90-second freshness boundary. The plan does not claim impossible
  cross-process notification of total storage failure.
- A future-schema record is immutable to a v1 writer: lifecycle and route
  writes fail closed without replacing its bytes. Missing/corrupt v1 may be
  reset only by an explicit native lifecycle transition. An old binary ignores
  this additive record and therefore reverts to legacy behavior; rollback does
  not inherit N04 fail-notify guarantees.
- Behavioral rollback may disable/remove N04 writers and readers, but it keeps
  the Runner/NSE `PrivacyInfo.xcprivacy` resources and their existing `E174.1`/
  `C617.1` declarations. Keep `35F9.1` for either target for as long as its code
  still accesses system uptime or boot time; privacy compliance is not a feature
  flag.
- Cold start, logout/account replacement, teardown, and authority disposal
  invalidate visible state before other cleanup. This does not alter SQL read
  state or notification cards.

### One route topology

- Reuse and generalize the single root observer currently named
  `directPrivateMediaRouteObserver`; do not add a second Navigator or
  `RouteObserver`. Its private-media behavior and scope remain intact.
- Add one small route-visibility binding used by direct, ordinary-group, and
  linked-group screens. It registers a route -> digest with the one authority.
  Push/cover/remove/replace/non-chat clears the covered key; pop restores the
  current underlying conversation; dispose cannot clear a newer route.
- The same route registry also exposes a process-local **current top-route
  identity** query. Notification-open dedupe uses this identity, not the fresh
  `maySuppress` predicate: a background tap on already-stacked A must not push a
  duplicate A before resume republishes the visibility lease, while covered A
  under settings is not considered the current top route.
- Existing direct/group `ActiveConversationTracker` instances remain named
  compatibility state only for N11 visible-read behavior and direct P2P
  rewarm/keepalive. This plan creates one **notification-suppression** authority;
  it does not silently redefine those compatibility consumers. No notification
  presentation/cancellation path may consult a legacy tracker. Preserve the
  direct-only `activePeerId` behavior so `group:*` never reaches either the
  keepalive or network-change rewarm path. Do not redesign read marking.

### Platform projections

- iOS: add one Foundation-only shared
  `ios/NotificationService/IosAppVisibilitySnapshot.swift` and one Runner
  coordinator. Use the existing App Group, stable `flock` inode, temp write,
  file fsync, atomic rename, directory fsync, exclusion from backup, and
  complete-until-first-authentication protection. Observe UIApplication and
  UIScene active/inactive/background notifications because Runner uses a scene
  delegate. `NotificationService` is a file-system-synchronized project group,
  so its source/resource joins that target without a duplicate manual build-file
  entry. Add explicit Runner source/resource membership; RunnerTests imports the
  Runner module with `@testable import Runner` rather than compiling the shared
  source a third time.
- The iOS boot provider is exact and injectable: obtain
  `KERN_BOOTTIME` with public `sysctl([CTL_KERN, KERN_BOOTTIME])` and encode only
  `ios:<tv_sec>:<tv_usec>` for Runner/NSE equality. Use
  `ProcessInfo.systemUptime` only for age. Either provider failing makes the
  snapshot ineligible; neither value is logged or sent off-device.
- Coalesce UIApplication and UIScene callbacks by semantic state. A duplicate
  active callback cannot advance lifecycle generation or clear a route CAS
  published between the two callbacks. Map resign/deactivate to `INACTIVE`,
  enter-background to `BACKGROUND`, enter-foreground to `INACTIVE`, and
  become/did-activate to `FOREGROUND_ACTIVE + null`; cold-start invalidation is
  installed before Flutter can publish a route. Rename is the reader-visible
  iOS commit point: pre-rename failure preserves the incumbent; post-rename
  directory-fsync failure reports durability uncertainty to the writer while
  readers consistently observe the renamed complete record.
- iOS monotonic/boot access uses the System Boot Time required-reason category
  for elapsed-time decisions only and never leaves the device. Add target
  `PrivacyInfo.xcprivacy` resources: Runner declares System Boot Time `35F9.1`
  plus its already-used Disk Space `E174.1`; NotificationService declares
  System Boot Time `35F9.1` plus its already-used File Timestamp `C617.1`.
  Validate source plists and built-bundle presence. This is target-complete for
  touched Runner/NSE APIs, not a whole-app privacy-manifest closure; existing
  Share Extension UserDefaults inventory remains a WP-07 release-audit item.
- Android: add one app-private `AtomicFile` containing one whole JSON blob under
  one process lock; do not use split preferences or an `apply()`/`commit()`
  cache whose failed disk write can expose uncommitted active bytes.
  `MainActivity` writes launch/resume/pause/stop and exposes the route/refresh
  channel. Persist each transition before `super` exposes it to Flutter. Use
  `SystemClock.elapsedRealtime`
  and `Settings.Global.BOOT_COUNT`; inability to read the boot count is
  ineligible. Encode boot identity as `android:<BOOT_COUNT>` solely for equality.
  A manifest sentinel freezes the current no-`android:process`
  assumption for MainActivity, FCM, and WorkManager; a future separate process
  must upgrade this store to explicit cross-process atomic locking.
- Android commit success is verified, not inferred from
  `AtomicFile.finishWrite()` (which returns no status): under the one process
  lock, call `startWrite`, write, perform a throwing `FileDescriptor.sync`, call
  `finishWrite`, then `openRead`/decode and compare the exact expected record and
  revision. A pre-finish exception calls `failWrite`; any write/sync/promotion/
  readback exception or mismatch marks current-process eligibility false.
- Budget one N04-specific debug proof flag: configure `AndroidJUnitRunner` and
  the AndroidX runner/rules dependencies independently from the unrelated PB266
  release-proof flag, require the exact disposable application ID plus disabled
  Google services when that flag is true, and compile both debug app and debug
  Android-test Kotlin before any device run. This is a build/test switch, not a
  production visibility rollout flag.
- N04 supplies/test-locks Swift/Kotlin readers and the shared predicate contract
  but does not make NotificationService, FirebaseMessagingService, or
  WorkManager render/suppress. N07/N08 adopt the record once their exact event
  identity and final-effect owners exist.

Primary native contracts were checked against Apple privacy-manifest guidance
and Android's API-24 `Settings.Global.BOOT_COUNT` contract. Execution must use
the frozen APIs/reasons above, not a device fingerprint or wall clock.

## Scope Contract And Guard

In scope:

- one versioned visibility record, codec/digest/predicate, authority, bridge,
  freshness renewal, root lifecycle owner, and one root route topology;
- current Flutter direct/group message/reaction/fallback/reconcile presentation
  decisions consuming the one authority, while open-route dedupe consumes the
  separate current-top-route query from the same route registry;
- protected group message/reaction display custody staged independently of an
  early visibility sample, then decided by the canonical projection owner;
- thin iOS/Android atomic stores, lifecycle writers/readers, privacy resources,
  and focused native/device proof.

Must preserve:

- Plan 369 canonical display completion still returns
  `terminalWithoutOutcome` for same-chat suppression; no `inChat` outcome;
- Plan 370's combined capability, producers, and drainer remain default-off;
- direct-only P2P warm/keepalive never receives a group key;
- existing private-media route observer generation/current-route behavior;
- background/covered notification-open dedupe does not stack a duplicate route;
- chat B and non-chat routes notify for A, and unanchored fallback remains
  event-outcome-ineligible;
- mute/read/delete/private-media/remote-announcement checks retain their current
  owners and order except for replacing the visibility input.

Hard `Do not`:

- Do not add a DB/SQLCipher migration, `LocalNotificationRecord`, outcome row,
  event ledger, second lifecycle tracker, second route observer, new scheduler,
  service, worker, or native rendering pipeline.
- Do not implement N05's final serialized pre-publication re-read/CAS or its
  open/background-during-build barriers.
- Do not mark read, activate chat-open cleanup, cancel delivered cards, change
  mute/badge policy, or emit `inChat`/`suppressedPolicy`; those remain N11/N05.
- Do not alter NSE content handoff, FCM/WorkManager notification output, provider
  payloads, relay code, capabilities, or live rollout.
- Do not use raw conversation identifiers, wall clock for age/freshness,
  process-local Dart `Stopwatch`, or failure fallback to `null => resumed`.
  `KERN_BOOTTIME` is permitted only as the same-boot equality discriminator;
  it never computes freshness.
- Do not migrate the media-receive background-task lifecycle lease, intro/posts/
  contact-request notification policy, or route-open dedupe into conversation
  suppression semantics.

Deferred / accepted differences:

- N05: final effect-boundary snapshot/read/delete/policy/revision recheck and
  generation CAS; N04 exposes the reader but does not claim A-28/AC-06/AC-07 or
  those open/background-during-build races.
- N06: shared event/read/presentation ledger and cross-owner final-effect state.
- N07: iOS NSE consumes the visibility reader after authenticated identity
  resolution and before content handoff; N12 owns real Apple device states.
- N08: FCM service/WorkManager consume the Android reader with their inbox and
  final-effect owner. The mailbox-wide dropped-push recovery card is not treated
  as a conversation card in N04.
- N11: read predicate adoption, exact activation cleanup, mute/badge/dismiss and
  stable-generation card retirement.
- WP-07/N12: capabilities, live provider/Redis, APNs/FCM, physical-iPhone
  lifecycle/presentation/privacy evidence, shared-wave/final release gates.

Dependencies: Plan 371 consumes N01's canonical event/display custody through
Plan 369 and the current Plan-370 composition baseline. It has no semantic
dependency on Redis/provider success. N05/N06/N07/N08/N11 consume its frozen
reader/digest/freshness contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-371-00 | Exact Plan-369/370 commit/receipt chain is present and the paired N03 capability/producer/drainer seam remains default-off | dependency preflight above; three exact Plan-370 preservation tests | Host / Git objects, committed blobs, real source composition | GREEN prerequisite sentinel -> same identities and default-off behavior | Flip default or detach one producer/drainer from the shared flag -> exact Plan-370 sentinel red | Literal preflight plus preservation command below; no new registration |
| TC-371-01 | All runtimes share the exact v1 record/key codec and only a fresh active exact key is eligible | `test/core/notifications/app_visibility_snapshot_test.dart::TC-371-01 v1 codec and fresh exact predicate fail toward notification`; Swift/Kotlin tests consume `app_visibility_snapshot_v1.json` | Host Dart + XCTest + JVM; fixed vectors/injected clocks | Causal RED: no snapshot type, digest contract, boot/freshness predicate, or fixture -> supported v1 exact A is eligible; B/non-chat/unknown/corrupt/future/rollback/boot mismatch/age 90s are not | Accept `<= 90s`, use raw/prefix key, remove lane/domain/boot check, or treat decode failure active -> TC-371-01 red in all runtimes | New Dart file in both curated arrays and `ONE_TO_ONE_HOST_TESTS`; native commands below; auto core/host-all discovery |
| TC-371-02 | One authority serializes lifecycle/route/heartbeat projection; delayed route writes cannot beat pause; the incumbent presence cadence refreshes locally before and independently of relay publication | `app_visibility_authority_test.dart::TC-371-02a lifecycle generation and projection failure are fail-notify`; `set_presence_use_case_test.dart::TC-371-02b foreground cadence refreshes visibility before a hanging failed or unsupported relay call` | Host Dart / fake native store and clock, controlled completers, real `SetPresenceUseCase` under `fake_async` | Causal RED: no authority/native generation/CAS/callback -> launch/resume/pause/route races converge to newest lifecycle; immediate and 60s ticks refresh first; pause/dispose stops them; failed writes/readbacks are ineligible | Remove generation CAS, retain cached active, move refresh after awaited relay work, or keep ticking after pause/dispose -> red | New authority file in both curated arrays and `ONE_TO_ONE_HOST_TESTS`; exact presence suite plus focused concurrency-4 bundle |
| TC-371-03 | One root route registry follows direct/group/non-chat cover/pop/replace/remove, restores only the frontmost route, gives open-dedupe non-fresh top-route identity, and never marks read/cancels a card merely on a route/lifecycle transition | `test/core/notifications/app_visibility_route_binding_test.dart::TC-371-03 one root route owner clears covered chats and restores only the frontmost conversation`; `TC-371-03a backgrounded direct or group A tap before republish does not stack A`; `TC-371-03b covered A is not top route and pop restores A` in `app_root_notification_open_test.dart` | Host Flutter widget / real Navigator, incumbent observer and real open/reconcile fakes | Causal RED: mounted trackers remain active under covers and freshness was proposed for open dedupe -> visibility clears correctly, but backgrounded already-top A remains deduped; covered A is not; transition causes zero read/cancel | Add a second observer, omit route transition/dispose guards, use `maySuppress` for open dedupe, or cancel/mark-read on route mutation -> red | New route file in both curated arrays and `ONE_TO_ONE_HOST_TESTS`; exact open-router and private-media observer suites |
| TC-371-04 | Every canonical main-app presentation uses one snapshot input: fresh exact direct/group suppress; stale/unknown/inactive/B/non-chat notify; same-chat stays outcome-free | `test/features/push/application/show_notification_use_case_test.dart::TC-371-04 one fresh visibility decision gates direct and group presentation without minting outcome` | Host Flutter / fake authority, real presentation result | Causal RED: API accepts raw tracker+lifecycle and cannot express freshness -> exact matrix and `terminalWithoutOutcome` | Restore `resumed && tracker.isViewing`, accept unknown/stale, or return `inChat` -> red | Existing file already in both curated arrays; focused selector and later wave host-all |
| TC-371-05 | All ten `maybeShowNotification` producers and four classified raw presentation decisions use the sole suppression authority; protected message/reaction custody is staged before visibility and projected later | `app_visibility_snapshot_wiring_test.dart::TC-371-05a production has one suppression owner and no notification tracker lifecycle bypass`; real `handleProtectedGroupContentReplay` + SQLite/outbox cases in `group_notification_visibility_staging_test.dart::TC-371-05b protected message and reaction stage before the canonical visibility decision` | Host source-AST plus real protected replay/SQLite/outbox, parameterized message/reaction and two visibility states | Causal RED: raw bypasses and early builder drops exist -> visible-at-stage then background-before-projection retains READY and OS-posts/completes with zero outcome; exact-visible-at-projection completes `terminalWithoutOutcome`; neither emits `inChat` | Restore one raw bypass, return null from either protected builder, drop either READY insert, or decide at staging -> red | Wiring file in both curated arrays/host inventory; protected integration owner in `GROUP_TESTS`; exact focused runtime command |
| TC-371-06 | iOS Runner/NSE share atomic v1 storage; boot identity and duplicate UIApplication/UIScene transitions are deterministic; privacy resources are complete | `IosAppVisibilitySnapshotTests::testTC37106AtomicSnapshotLifecycleAndPrivacyContract`; `::testTC37106DuplicateUIApplicationAndUISceneActiveDoesNotClearInterleavedRouteCAS`; Dart privacy contract | Simulator XCTest + built Runner/NSE bundles; shared fixture via `#filePath`, injected uptime/KERN_BOOTTIME/store faults | Causal RED: no store/coordinator/manifests -> same-boot parity, changed-boot/rollback/provider faults ineligible, pre/post-rename semantics explicit, duplicate callbacks coalesce, future schema preserved, manifests present | Omit boot tuple/source coalescing/fsync/protection/reason, rewrite future bytes, or let duplicate active clear route -> red | Privacy Dart file in both arrays/host inventory; conditional available-simulator XCTest; generic Runner/NSE build and bundle lint; later native host runner |
| TC-371-07 | Android stores one verified AtomicFile value; MainActivity ordering uses elapsed time + boot count; debug instrumentation and one-process assumption are build-locked | `AppVisibilitySnapshotStoreTest::TC-371-07 v1 store is atomic fresh and fail-notify`; `MainActivityAppVisibilityTest::TC-371-07 lifecycle and stale route CAS preserve newest state` | Host JVM/Robolectric / real AtomicFile, shared fixture, fake boot/elapsed plus injected write/sync/promotion/readback faults | Causal RED: no store/channel/debug runner/pause-stop writers -> old-or-new verified record, future bytes preserved, transitions persist before Flutter exposure, stale route loses, every fault/mismatch is ineligible | Skip explicit sync/readback, use split/cache-backed values, omit lifecycle/boot/CAS, rewrite future bytes, or tie instrumentation to PB266 -> red | Exact JVM plus debug/debugAndroidTest compile; later host-all native runner registration |
| TC-371-08 | Real Android lifecycle callbacks, disk reopen, and route CAS produce the same safe record on each currently available USB Android and emulator | `AppVisibilityLifecycleInstrumentationTest::TC-371-08a seed lifecycle and durable record`; host force-stop; `::TC-371-08b reopen disk and reject stale route`, through `run_app_visibility_android_e2e.sh` | Device / disposable `com.mknoon.app.visibilityproof`, Google services disabled, two instrumentation phases, real `BOOT_COUNT`/elapsed time | Device-only causal proof -> build/install once; seed/lifecycle phase passes; host force-stops exact proof package; second process reloads disk; all zero-skip | Remove transition/generation/durable reopen or target validation -> device proof red | One 1to1 + one group discovery row for one scenario; run independently on each rediscovered available USB Android and emulator, recording policy N/A per absent class |
| TC-371-09 | N03 defaults/outcomes, open-route behavior, compatibility read state, direct P2P keepalive+network rewarm, private-media route continuity, and sibling independence remain intact | exact Plan-370 bundle; private-media observer; active-peer keepalive; `p2p_service_impl_test.dart::TC-371-09 group top route never warms direct transport on network change`; `app_root_notification_open_test.dart`; sibling sentinel; TC-371-03 zero-read/cancel assertions | Host Flutter / incumbent owners and real open/reconcile fakes | GREEN sentinels -> no capability activation, group warm, duplicate route, read mutation, route-triggered card cancellation, or sibling sharing | Expose group route to either direct consumer, use suppression freshness for open dedupe, cancel/read on lifecycle, replace observer, or share state -> red | Focused TC-371-09 plus exact preservation bundle and already-curated affected owners; later wave host registration |

### Test Notes

- TC-371-01 uses exact boundary samples at 89,999 ms and 90,000 ms, a
  fresh-looking uptime under a different boot session, Unicode/length framing,
  direct/group lane swaps, and anchored group routes.
- TC-371-02 releases a stale route write only after native pause commits. The
  discriminator is a final `BACKGROUND + null` record and zero suppressibility,
  not merely a rejected Future. Its second arm instantiates the real
  `SetPresenceUseCase` under `fake_async`: initial and 60-second local refresh
  happen before a hanging/failed/unsupported relay call; pause/dispose stops it.
- TC-371-03 covers direct -> group and group -> non-chat -> pop; it does not
  create modality-specific route infrastructure. Open dedupe reads current
  top-route identity, never freshness eligibility.
- TC-371-05 freezes a classified census rather than a broad substring ban. The
  ten `maybeShowNotification` call sites are bootstrap direct/group, background
  fallback anchored direct/group, direct message, direct reaction, group
  reaction ingress, and the three group-listener presentation sites. The four
  additional presentation decisions are the app-root group-reaction resolver,
  unanchored group fallback, group canonical view/replacement checks, and both
  protected display builders. Route-open dedupe and group-media background-task
  ownership are explicitly excluded because they answer different questions;
  intro/posts/contact-request paths have no conversation-suppression contract.
- TC-371-05b drives both protected message and reaction through real replay and
  SQLite/outbox. `visible at stage -> background before projection` must retain
  READY custody, post the OS card, complete custody, and emit zero outcome while
  N03 is off. `fresh exact at projection` completes
  `terminalWithoutOutcome`. Neither arm emits `inChat`.
- TC-371-08 is one scenario run independently on each available USB Android and
  emulator after one shared APK build. It is not a two-peer test and performs no
  user-tap/manual step; an absent target class is recorded as policy N/A.

## Implementation Steps

1. Re-run TC-371-00, `git status --short`, device discovery, and the Graphify
   TDD query. Stop if product/test/native/script source differs from the pinned
   baseline or either receipt/default sentinel fails.
2. Add `app_visibility_snapshot_v1.json`, the named test, and only the minimum
   production declarations needed to compile with a fail-notify placeholder.
   Record one exact selected assertion RED; a compile/load/tool/teardown error,
   missing test, or zero selection is not RED.
3. Add the Dart v1 value/codec/digest/predicate and one
   `AppVisibilityAuthority`/platform bridge. Freeze 90s/60s in one constants
   owner and serialize writes/reads with lifecycle-generation CAS. Stop if this
   requires a DB, worker, second timer, or raw identifier.
4. Reuse the incumbent root lifecycle callback and root RouteObserver. Add one
   route binding to direct, ordinary-group, and linked-group routes. Preserve
   the legacy trackers only for their non-notification compatibility consumers.
5. Replace the visibility parameters of `maybeShowNotification` with the one
   authority reader and migrate the classified presentation census. Remove the
   raw group-reaction prefilter, adopt the authority in unanchored fallback and
   canonical reconcile, and make protected group message/reaction custody
   staging visibility-independent. Preserve notification-open on the registry's
   non-fresh top-route query; add no lifecycle/route-triggered card cancellation.
6. Add the iOS shared file/coordinator, AppDelegate wiring, correct target membership,
   focused XCTest, and target privacy manifests. Preserve NotificationService
   content resolution/handoff behavior.
7. Add the Android AtomicFile store/channel/MainActivity transitions,
   ordinary debug instrumentation configuration, JVM/Robolectric tests,
   manifest sentinel, two-phase instrumentation test, and one lean device runner.
   Preserve FCM/WorkManager notification behavior.
8. Register five new shared Dart files in `ONE_TO_ONE_TESTS`, `GROUP_TESTS`, and
   `ONE_TO_ONE_HOST_TESTS`; register the protected runtime file in `GROUP_TESTS`.
   Register one native host runner exactly once in later `host-all`, including
   dedicated predicate, dry-run print, and execution dispatch branches so it is
   invoked with `bash`, never passed to `flutter test`. Register
   the Android device runner in reliability discovery for both affected lanes
   and prove one expanded scenario/row—not duplicate modality rows.
9. Run focused Dart at concurrency 4, native unit/compile legs, representative
   mutations serially, exact preservation, then curated `1to1` and `groups`
   serially. Build the disposable Android proof APKs once, then run the
   physical/emulator legs concurrently with isolated target/result directories
   when both are available; record policy N/A for either absent class.
10. Run analyzer/format/diff/privacy/project-membership hygiene and one
    incremental Graphify refresh. Bind a checksum receipt and append status/
    index/coverage implementation disposition only after every required gate.

Stop-if conditions:

- native notification rendering must change to make a test pass -> reassign to
  N07/N08 rather than widening Plan 371;
- final native publication/read/delete/policy state is needed -> N05/N06/N11;
- Android gains a separate process -> add a reviewed cross-process lock/commit
  protocol around the AtomicFile before continuing;
- the 90s/60s contract proves operationally unsafe -> update the plan and all
  runtime vectors before production edits, not as an ad hoc config surface.

## Risks And Blind Spots

- Stale foreground survives a crash/reboot -> strict 90s age, boot discriminator,
  native transition invalidation, and TC-371-01/06/07/08.
- Delayed route write resurrects foreground after pause -> lifecycle-generation
  CAS and TC-371-02/07/08.
- Covered A or disposed A clears/restores the wrong route -> one root observer,
  route identity/generation, and TC-371-03.
- A bypass still uses tracker + lifecycle -> exact production census/source-AST
  guard plus TC-371-05.
- Early visible-at-stage decision loses protected group recovery if background
  happens before projection -> stage independently, then central decision in
  TC-371-05.
- Flutter/native digest drift -> one fixture consumed in all runtimes and
  TC-371-01.
- iOS torn App-Group writes or missing privacy declaration -> TC-371-06 plus
  built-bundle `plutil` checks.
- A duplicate UIApplication/UIScene active transition clears an interleaved
  Flutter route -> semantic transition coalescing in TC-371-06.
- Android multiprocess cache unsafety -> current manifest sentinel; any future
  `android:process` is a stop condition.
- Local refresh accidentally depends on relay presence -> fake relay failure in
  TC-371-02; callback executes before network work.
- Existing trackers accidentally become a second notification authority ->
  TC-371-05 forbids notification consumers, while TC-371-09 preserves direct
  keepalive/read compatibility.
- Lifecycle / derived-state durability: native whole-record reopen, boot and
  cold-start cases in TC-371-06/07/08.
- Sibling-surface consistency: direct/group/message/reaction are parameters of
  TC-371-04/05; no per-modality infrastructure.
- Destructive-action side effects: invalidation removes only visibility
  eligibility; TC-371-09 proves it does not mark read, delete outcomes, cancel
  cards, or change sibling state.
- Invariant re-verification under transitions: every route/heartbeat update
  rechecks native lifecycle generation; every read rechecks boot/age/schema.

## Gate Cadence

- Parallelize independent Dart owners inside one `flutter test
  --concurrency=4` invocation. Mutations, Xcode/Gradle builds, and curated
  scripts remain serial because they share mutable files or build caches. After
  one Android proof build, physical/emulator phases may run concurrently because
  every adb command and result directory is target-pinned and isolated.
- Per-plan closure: prerequisite/default sentinels; exact focused Dart bundle;
  focused Swift/Kotlin unit and compile; exact preservation; curated `1to1` and
  `groups`; two single-device Android runs; analyzer/format/diff/Graphify.
- No per-plan `core-host-all`, `feature-host-all`, or full `host-all`: the new
  core tests are explicitly in both affected curated arrays, the native surface
  has exact compile/unit/device gates, and exact reverse-dependency sentinels
  cover the reused core/root seams. This is the leaner sufficient cadence.
- Add one executable `scripts/test/run_app_visibility_native_371.sh` covering
  the exact JVM/Android compile and available-simulator XCTest/Runner+NSE
  build/privacy contracts. Register its dedicated bash dispatch exactly once in
  the non-Dart `host-all` tail, then execute only that registered item with
  `host-all --only <path>` in Plan 371. This proves registration and execution
  without running a host sweep.
- Run `./scripts/run_host_test_gates.sh host-all` once after the N03-N06 shared
  lifecycle/ledger/final-effect dependency wave is complete, then once at final
  WP-07/release closure. Registration under later `host-all` does not make it a
  Plan-371 execution obligation.
- Shared tests outside feature/core globs: the native host runner is registered
  for later `host-all`; device instrumentation is registered in reliability
  discovery and remains outside host-all.

## Device/Relay Proof Profile

- Profile: one Android native lifecycle scenario, independently repeated on the
  currently available USB Android and Android emulator; no relay/provider/
  two-peer behavior.
- Boundary being proven: actual Activity lifecycle callbacks, real Android
  `BOOT_COUNT`/elapsed time, synchronous private-store commits, stale route CAS,
  and force-stop/reopen. Host/Robolectric tests cannot alone prove these APIs.
- Live availability check:
  `flutter devices --machine; adb devices -l; xcrun simctl list devices available`.
  Planning observed USB Pixel 6 `21071FDF600CSC` (API 36), Android emulator
  `emulator-5554` (API 37), and available iPhone simulators. Re-resolve at
  execution; do not pin an unavailable version/model.
- Required setup: build/install one disposable
  `com.mknoon.app.visibilityproof` debug app/test pair with Google services
  disabled. Each runner validates its `ANDROID_SERIAL`, executes the seed/
  lifecycle phase, force-stops only the disposable package, then invokes the
  reopen phase and asserts exact tests/zero skips. No taps, account, relay,
  provider, or network. Run the two isolated target legs concurrently when both
  classes are currently available.
- Two-peer default: N/A — no peer interaction. The user's physical-Android plus
  Android-emulator rule is satisfied by running the one native scenario on both;
  an iPhone is not introduced.
- Closure role: required Plan-371 Android boundary evidence. Real Apple
  APNs/NSE/lifecycle presentation remains registered for GAP-N12 and is not
  replaced by this proof.
- The runner requires `--device-id`, exports and validates that exact
  `ANDROID_SERIAL`, and scopes every adb/install/instrumentation/force-stop call
  to it; there is no hidden second endpoint.
- Registration: `scripts/check_reliability_simulation_discovery.sh`
  `classify_path` records `scripts/run_app_visibility_android_e2e.sh` once for
  1to1 and once for group, both expanding the single
  `app_visibility_lifecycle` scenario.
- Discovery command: exact `--records-tsv` and `--checks-tsv` counts below ->
  one classified runner and one expanded `app_visibility_lifecycle` check in
  each of `1to1` and `group`.
- Closure command: the two explicit runner commands below -> instrumentation
  test passes with zero skips on each available Android target.
- Deferred device work: iOS simulator supplies compile/XCTest safety now;
  physical-iPhone foreground/inactive/background/suspended/terminated/locked/
  before-first-unlock/force-quit and actual NSE presentation remain GAP-N12.

## Acceptance Gates

```bash
# Baseline, dependencies, tools, and live availability.
set -euo pipefail
git status --short
command -v jq >/dev/null
command -v plutil >/dev/null
plan371_gate_dir="$(mktemp -d /tmp/plan371-gates.XXXXXX)"
flutter devices --machine >"$plan371_gate_dir/flutter-devices.json"
adb devices -l >"$plan371_gate_dir/adb-devices.txt"
xcrun simctl list devices available >"$plan371_gate_dir/ios-simulators.txt"

# Run the full TC-371-00 dependency preflight from Dependency Contract here.

# After the test plus compile-only fail-notify declarations exist, prove the
# selected test itself assertion-fails. Load/compile/tool/teardown errors do not
# count as RED.
(
  set -uo pipefail
  red_status=0
  flutter test test/core/notifications/app_visibility_snapshot_test.dart \
    --plain-name 'TC-371-01 v1 codec and fresh exact predicate fail toward notification' \
    --file-reporter "json:$plan371_gate_dir/red.json" || red_status=$?
  set -e
  red_name='TC-371-01 v1 codec and fresh exact predicate fail toward notification'
  test "$(jq -s --arg name "$red_name" '[.[] | select(.type == "testStart" and (.test.name | contains($name)))] | length' "$plan371_gate_dir/red.json")" -eq 1
  red_test_id="$(jq -r -s --arg name "$red_name" '[.[] | select(.type == "testStart" and (.test.name | contains($name)))][0].test.id' "$plan371_gate_dir/red.json")"
  test "$red_test_id" != null
  test "$(jq -s --argjson id "$red_test_id" '[.[] | select(.type == "testDone" and .testID == $id and .result == "failure" and .skipped == false)] | length' "$plan371_gate_dir/red.json")" -eq 1
  test "$red_status" -ne 0
)

# Focused Flutter GREEN: eleven exact behaviors across five new shared owners, one
# new group runtime owner, and four affected existing owners; bounded
# concurrency, exact success, zero skips.
(
  set -euo pipefail
  flutter test --concurrency=4 \
    test/core/notifications/app_visibility_snapshot_test.dart \
    test/core/notifications/app_visibility_authority_test.dart \
    test/core/notifications/app_visibility_route_binding_test.dart \
    test/core/notifications/app_visibility_snapshot_wiring_test.dart \
    test/core/notifications/ios_app_visibility_privacy_manifest_contract_test.dart \
    test/core/notifications/app_root_notification_open_test.dart \
    test/core/services/p2p_service_impl_test.dart \
    test/features/push/application/set_presence_use_case_test.dart \
    test/features/push/application/show_notification_use_case_test.dart \
    test/features/groups/integration/group_notification_visibility_staging_test.dart \
    --name 'TC-371-(01|02a|02b|03 |03a|03b|04|05a|05b|06|09)' \
    --file-reporter "json:$plan371_gate_dir/focused.json"
  expected_prefixes=(
    TC-371-01 TC-371-02a TC-371-02b TC-371-03 TC-371-03a
    TC-371-03b TC-371-04 TC-371-05a TC-371-05b TC-371-06 TC-371-09
  )
  for prefix in "${expected_prefixes[@]}"; do
    selected="$(jq -r -s --arg prefix "$prefix " '[.[] | select(.type == "testStart" and (.test.name | contains($prefix)))] | length' "$plan371_gate_dir/focused.json")"
    test "$selected" -eq 1
    test_id="$(jq -r -s --arg prefix "$prefix " '[.[] | select(.type == "testStart" and (.test.name | contains($prefix)))][0].test.id' "$plan371_gate_dir/focused.json")"
    test "$(jq -s --argjson id "$test_id" '[.[] | select(.type == "testDone" and .testID == $id and .result == "success" and .skipped == false)] | length' "$plan371_gate_dir/focused.json")" -eq 1
  done
  test "$(jq -s '[.[] | select(.type == "testStart" and (.test.name | contains("TC-371-")))] | length' "$plan371_gate_dir/focused.json")" -eq 11
)

# One exact native host contract. It always runs the two named JVM tests,
# compileDebugKotlin + compileDebugAndroidTestKotlin under the N04 disposable
# proof flag/application ID, generic Runner and NSE
# simulator builds, source/bundle privacy lint, and fixture-membership guards.
# Its Gradle compile/device-build legs pass exactly
# -PenableAppVisibility371Proof=true,
# -PandroidApplicationId=com.mknoon.app.visibilityproof, and
# -PdisableGoogleServicesForDisposableProof=true.
# The runner writes to PLAN371_NATIVE_RESULT_DIR when supplied and otherwise
# creates its own temporary result directory, so later unfiltered host-all is
# self-contained. It resolves XCTest availability from
# `xcrun simctl list devices available -j` with jq (first available iPhone UDID),
# never from a planning-time ID or a parenthesized-name text parser.
# It runs the exact two-method XCTest owner only when a simulator is rediscovered;
# otherwise it records the simulator leg as policy N/A. Every executed native
# test must have exact pass and zero-skip assertions in the retained log.
PLAN371_NATIVE_RESULT_DIR="$plan371_gate_dir/native-host" \
  ./scripts/run_host_test_gates.sh host-all \
    --only scripts/test/run_app_visibility_native_371.sh

# Exact preservation sentinels; eight selected, zero skips.
(
  set -euo pipefail
  flutter test --concurrency=4 \
    test/core/bridge/p2p_bridge_client_wake_outcome_test.dart \
    test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
    test/core/notifications/notification_completed_outcome_drain_composition_test.dart \
    test/features/conversation/presentation/screens/direct_private_media_route_observer_wiring_test.dart \
    test/core/services/active_peer_keepalive_use_case_test.dart \
    test/core/notifications/app_root_notification_open_test.dart \
    test/features/groups/integration/group_multi_device_convergence_test.dart \
    --name '(TC-370-05 opaque outcome uses strict all-relay completion|TC-370-07 production composes one default-off outcome admission and one shared drain callback|TC-370-07 one persisted outcome drainer coalesces and retains partial relay failure across reopen|production registers and scopes one stable private-media observer|TC-183-08: null / group: active peer → zero pings|active group notification route can be skipped without stacking|active 1:1 conversation route is skipped when its tracker is viewing that peer|same-user multi-device convergence mute, unread, and local notifications stay device-local across joined sibling devices)$' \
    --file-reporter "json:$plan371_gate_dir/preservation.json"
  test "$(jq -s '[.[] | select(.type == "testStart" and .test.url != null)] | length' "$plan371_gate_dir/preservation.json")" -eq 8
  test "$(jq -s '([.[] | select(.type == "testStart" and .test.url != null) | .test.id]) as $ids | [.[] | select(.type == "testDone" and (.testID as $id | ($ids | index($id)) != null) and .result == "success" and .skipped == false)] | length' "$plan371_gate_dir/preservation.json")" -eq 8
  test "$(jq -s '[.[] | select(.type == "testDone" and .skipped == true)] | length' "$plan371_gate_dir/preservation.json")" -eq 0
)

# Exact registration before curated/device execution. The curated script has no
# truthful groups --list mode, so inspect the named arrays rather than launching
# a gate accidentally.
array_has_path() {
  local script="$1" array="$2" path="$3"
  awk -v header="readonly ${array}=(" -v needle="\"${path}\"" '
    $0 == header { inside = 1; next }
    inside && /^\)/ { exit }
    inside {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == needle) count++
    }
    END { exit(count == 1 ? 0 : 1) }
  ' "$script"
}
shared_curated=(
  test/core/notifications/app_visibility_snapshot_test.dart
  test/core/notifications/app_visibility_authority_test.dart
  test/core/notifications/app_visibility_route_binding_test.dart
  test/core/notifications/app_visibility_snapshot_wiring_test.dart
  test/core/notifications/ios_app_visibility_privacy_manifest_contract_test.dart
  test/core/notifications/app_root_notification_open_test.dart
  test/features/push/application/set_presence_use_case_test.dart
)
for path in "${shared_curated[@]}"; do
  array_has_path scripts/run_test_gates.sh ONE_TO_ONE_TESTS "$path"
  array_has_path scripts/run_test_gates.sh GROUP_TESTS "$path"
  array_has_path scripts/run_host_test_gates.sh ONE_TO_ONE_HOST_TESTS "$path"
done
array_has_path scripts/run_test_gates.sh GROUP_TESTS \
  test/features/groups/integration/group_notification_visibility_staging_test.dart

./scripts/run_host_test_gates.sh core-host-all --dry-run \
  >"$plan371_gate_dir/core-dry-run.txt"
for path in "${shared_curated[@]}"; do
  case "$path" in test/core/*)
    test "$(rg -F -c "'$path'" "$plan371_gate_dir/core-dry-run.txt")" -eq 1 ;;
  esac
done
./scripts/run_host_test_gates.sh host-all --dry-run \
  >"$plan371_gate_dir/host-all-dry-run.txt"
test "$(rg -F -c 'bash scripts/test/run_app_visibility_native_371.sh' "$plan371_gate_dir/host-all-dry-run.txt")" -eq 1
./scripts/run_host_test_gates.sh host-all --dart-only --dry-run \
  >"$plan371_gate_dir/host-all-dart-only-dry-run.txt"
! rg -F 'scripts/test/run_app_visibility_native_371.sh' \
  "$plan371_gate_dir/host-all-dart-only-dry-run.txt"

./scripts/check_reliability_simulation_discovery.sh --records-tsv \
  >"$plan371_gate_dir/records.tsv"
./scripts/check_reliability_simulation_discovery.sh --checks-tsv \
  >"$plan371_gate_dir/checks.tsv"
for category in 1to1 group; do
  test "$(awk -F '\t' -v c="$category" '$1 == c && $2 == "runner" && $3 == "scripts/run_app_visibility_android_e2e.sh" { n++ } END { print n + 0 }' "$plan371_gate_dir/records.tsv")" -eq 1
  test "$(awk -F '\t' -v c="$category" '$1 == c && $2 == "scripts/run_app_visibility_android_e2e.sh" && $3 == "app_visibility_lifecycle" { n++ } END { print n + 0 }' "$plan371_gate_dir/checks.tsv")" -eq 1
done

# Curated lanes are affected by direct and group adopters. Run serially once.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Availability-bounded Android boundary. Build once, rediscover generic target
# classes, then run isolated device legs concurrently when both exist.
flutter devices --machine >"$plan371_gate_dir/flutter-devices-final.json"
adb devices -l >"$plan371_gate_dir/adb-devices-final.txt"
./scripts/run_app_visibility_android_e2e.sh \
  --build-only \
  --artifact-dir "$plan371_gate_dir/android-proof-apks"
physical_id="$(awk '$2 == "device" && $1 !~ /^emulator-/ && $0 ~ /(^|[[:space:]])usb:/ { print $1; exit }' "$plan371_gate_dir/adb-devices-final.txt")"
emulator_id="$(awk '$2 == "device" && $1 ~ /^emulator-/ { print $1; exit }' "$plan371_gate_dir/adb-devices-final.txt")"
physical_pid=''
emulator_pid=''
for target_kind in physical emulator; do
  if [ "$target_kind" = physical ]; then target_id="$physical_id"; else target_id="$emulator_id"; fi
  if [ -z "$target_id" ]; then
    printf 'N/A (target unavailable by project policy): Android %s\n' "$target_kind" \
      >>"$plan371_gate_dir/device-disposition.txt"
    continue
  fi
  ./scripts/run_app_visibility_android_e2e.sh \
    --device-id "$target_id" \
    --artifact-dir "$plan371_gate_dir/android-proof-apks" \
    --result-dir "$plan371_gate_dir/android-$target_kind" \
    --scenario app_visibility_lifecycle &
  if [ "$target_kind" = physical ]; then physical_pid="$!"; else emulator_pid="$!"; fi
done
device_status=0
for pid in "$physical_pid" "$emulator_pid"; do
  test -z "$pid" && continue
  wait "$pid" || device_status=1
done
test "$device_status" -eq 0

# Changed-source hygiene, analyzer, graph, and immutable receipt inputs.
while IFS= read -r path; do
  test -z "$path" || dart format --output=none --set-exit-if-changed "$path"
done < <(
  {
    git diff --name-only \
      9be694a19e4f17973e447f8b98c8167b9881fd74 -- '*.dart'
    git ls-files --others --exclude-standard -- '*.dart'
  } | sort -u
)
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

For five representative mutations, record the exact named owner going
red and revert before continuing:

1. accept age `== 90s` or remove boot check -> TC-371-01;
2. let a stale route update overwrite pause -> TC-371-02/07;
3. restore one raw tracker/lifecycle bypass or protected-stage visibility drop ->
   TC-371-05;
4. split the iOS record, remove boot/source coalescing, or omit one iOS
   transition -> TC-371-06;
5. replace Android AtomicFile with cache-backed/split state or omit one Android
   transition/generation fence -> TC-371-07/08.

Do not run mutations concurrently with any other gate. Record semantic failure,
not only exit status.

## Execution Interpretation And Done Criteria

- Expected RED: after the TC-371-01 test and compile-only fail-notify
  declarations exist, the named test selects exactly once and assertion-fails
  because fresh active exact A remains ineligible. A compile/load/tool/teardown
  error, missing file/test, or zero selection is invalid evidence.
- Green sentinel: fresh active exact A suppresses; every unsafe state notifies;
  B/non-chat stay isolated; same-chat produces no outcome; N03 admission stays
  off; direct P2P and private-media route behavior remain.
- Pre-existing dirty tree / known failure: execution begins from clean docs-only
  commit `9be694a19...`, whose direct parent is Plan 370 `b904553...`. Record all
  unrelated dirt before RED and do not absorb it.
- Environment blocker: each unavailable target class is `N/A (target
  unavailable by project policy)`, not a product failure. At planning time a
  USB Android, emulator, and iPhone simulators are available. N04 requires no physical
  iPhone or unavailable Android API band.
- Scope drift: any DB, relay, provider, native render, final-effect ledger,
  read/cleanup/mute, second observer, or second scheduler change blocks closure
  and requires reassignment/replan.

- [x] TC-371-00 dependencies, commit ancestry, receipts, markers, trees, and
      three N03 default-off sentinels pass.
- [x] Every TC-371-01 through TC-371-09 behavior has the named proof with zero
      skips and correct discriminator.
- [x] One genuine causal RED and all five representative mutation re-reds
      are recorded and reverted.
- [x] Dart/Swift/Kotlin digest preimages/digests and decoded vector dispositions
      agree; every unsafe state fails toward notification.
- [x] One root lifecycle/route authority is production-composed; all current
      Flutter notification decisions use it; protected group staging is not
      visibility-filtered.
- [x] iOS Runner/NSE atomic-store, membership, generic compile/build, privacy
      plists and built-bundle presence pass; focused XCTest passes on an
      available simulator or is recorded policy N/A.
- [x] Android unit/compile and real lifecycle instrumentation pass on the
      rediscovered USB Android and emulator when available.
- [x] Both curated lanes pass; no per-plan core/feature/full host sweep runs.
- [x] Exact array/dry-run/discovery checks register every shared/group-only Dart
      owner, the one native host runner, and both expanded device categories.
- [x] Analyzer, changed-Dart formatting, `git diff --check`, privacy lint, and
      incremental Graphify refresh are clean.
- [x] No N03 capability/outcome activation, native rendering, N04 PRD/live/
      release acceptance, or downstream-gap completion is claimed.

## Handoff

- First causal RED command: the TC-371-01 `flutter test --plain-name` block in
  Acceptance Gates after authoring the named test.
- Preservation command: the eight-test exact bundle in Acceptance Gates plus the
  Plan-371 registration checks.
- Manual registration: add five new shared Dart owners plus the affected
  presence/open owners to both curated arrays and the host 1to1 inventory; add
  one protected group owner to `GROUP_TESTS`, one native host runner to later
  `host-all`, and one Android device runner to both reliability categories. No
  per-modality/device rows.
- Migration: N/A — no Flutter DB/SQLCipher schema. iOS adds one versioned atomic
  App-Group file and Android one versioned AtomicFile. Missing/corrupt v1 fails
  notify, future bytes remain unchanged, and old binaries ignore the additive
  record and therefore retain legacy behavior rather than N04 safety.
- Boundary closure: focused host/native plus the same one-scenario Android
  lifecycle proof on the live USB Android and emulator. iOS real-device
  acceptance is deferred to GAP-N12 by policy.
- Success marker after execution/audit only:
  `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE`. It means one fresh
  authority and current Flutter adoption are code-complete, not full GAP-N04,
  N03/live/PRD/release acceptance;
  N07/N08 still adopt the shared readers in native final-effect lanes.
- Aggregate gate: one N03-N06 wave `host-all` after N06, then final WP-07.
- Unresolved evidence: physical-iPhone/NSE and Android FCM/WorkManager consumer
  adoption are explicitly owned by N07/N08/N12, not missing Plan-371 work.
- Checksum-bound receipt:
  `Test-Flight-Improv/evidence/371/README.md`, SHA-256
  `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f`,
  frozen tested tree `75116f8b1c7cc0cec99f2a72d1410713868d0f23`,
  Graphify `a1554310fab6234f`.

## Reviewer Findings

Independent `$tdd-review` result: **PASS after bounded in-place corrections**.

Post-execution source/counterexample review also passes. It found one material
account-replacement invalidation omission; strengthened TC-371-05a captured a
semantic RED, the root/StartupRouter order was repaired, and the exact runtime,
whole owner, focused, preservation, both curated, analyzer, Android, hygiene,
and Graphify gates were green again before the final tree freeze. No other
release-blocking defect was found.

- Claims and boundaries: PASS. Fresh notification suppression, process-local
  route-open dedupe, N11 compatibility trackers, N05 final-effect races, and
  N07/N08 native rendering are distinct contracts; Plan 371 owns only the first
  plus its shared platform projection.
- Causal proof: PASS. The revised matrix drives the actual presence timer, real
  protected replay plus SQLite/outbox, duplicate iOS lifecycle events,
  verifiable Android AtomicFile commit/readback, two-phase device reopen, P2P
  network rewarm, and zero read/card-cancel side effects.
- Alternate paths: PASS. The ten `maybeShowNotification` callers and four raw
  presentation decisions are classified literally; open routing, media
  background-task ownership, intro/posts/contact-request, NSE, FCM and
  WorkManager are not over-migrated.
- Gates and non-vacuity: PASS. RED joins its own failed `testDone`; focused GREEN
  joins eleven exact IDs to success; preservation is 8/8/0; array and discovery
  membership are exact; the native shell runner is both registered and executed
  through one filtered host item; device targets are rediscovered by class.
- Operability and rollback: PASS. Future schemas are preserved, failures expire
  toward notification, privacy resources survive rollback, native admission is
  not activated, and unavailable device classes are policy N/A.

Rejected expansions: a second N04 plan, DB migration, second route/lifecycle
owner, per-platform rollout slice, new timer/service, native renderer adoption,
per-plan host-family/full-host sweep, and physical-iPhone gate. None is needed to
make this N04-owned foundation executable or safer.

## Arbiter Decision

Proceed with exactly **one** N04 implementation plan. Its real rollback boundary
is the versioned visibility authority plus current Flutter adoption; iOS and
Android are thin projections of that same contract, not separate deliverables.
The plan may issue only
`N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE`. Full GAP-N04/PRD
acceptance remains dependency-composed through N05/N07/N08/N11/N12 and does not
justify another N04-owned plan. Execute the focused/native/preservation and two
affected curated lanes specified here, with concurrency only at the isolated
Dart/device seams; defer the one full host sweep to the N03-N06 wave boundary.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-15 | not started | planning documents only | Dependency preflight PASS; 8/8 preservation PASS; bash/diff hygiene PASS | Independently reviewed execution contract | No implementation started | Run TC-371-00, then author TC-371-01 assertion RED |
| 2026-08-15 | clean baseline re-freeze | Plan 371 dependency contract only | Docs-only commit `9be694a19` verified as the direct child of Plan 370 `b90455347`; tree `d31e890195b200444076cf14dfb664f54559cc06`; only the five allowlisted planning paths differ | Clean implementation baseline established without discarding the reviewed handoff | None | Re-run TC-371-00, then author TC-371-01 assertion RED |
| 2026-08-16 | assertion RED and implementation | Shared fixture; Dart authority/route/adopters; iOS/Android stores and coordinators; focused owners | Exact TC-371-01 selected once and assertion-failed; implementation then reached focused 11/11, native JVM/XCTest/compile/privacy, and five serial mutation REDs | One strict cross-runtime v1 snapshot and one current Flutter presentation authority | None | Run preservation, curated lanes, and available-device proof |
| 2026-08-16 | preservation and counterexample repair | Current notification adopters plus affected test fixtures and account cutover | Preservation 8/8; deterministic group-fixture omissions repaired; final review found and semantically re-red account invalidation before repair | Account replacement/erase now invalidates before cleanup; no second suppression authority | None | Rerun all affected final-tree gates |
| 2026-08-16 | post-execution audit closed | 80-path frozen implementation plus checksum receipt | Focused 11/11; StartupRouter 26/26; `1to1` 3,302 + tails; `groups` 4,303 + tails; native host; Pixel 6 + emulator; analyzer/hygiene/Graphify all PASS | Receipt SHA-256 `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f`; frozen tree `75116f8b1c7cc0cec99f2a72d1410713868d0f23`; marker `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE` | Full GAP-N04/live/PRD/release acceptance remains downstream | Commit Plan 371 only; then validate the next sequential plan against this receipt |
