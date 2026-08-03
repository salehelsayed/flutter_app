# 330 - Android Group Notification Projection Durability

Status: **CLOSED / PLAN-GREEN / ANDROID-CLOSED (2026-08-03)**; the final adversarial audit reports no remaining P0/P1, and closure uses only receipts produced after exact-event acknowledgement, final keyed-lane repair, and proof-harness counterexample repair
Type: Bug + reliability hardening
Spec: finish the highest-priority missing group text/image/video/voice/reaction notification work after Plan 329, with automated proof only on the connected USB Android and Android emulator
Classification: planned, adversarially reviewed through the final production and proof-harness counterexample passes, and updated with every confirmed gap; the final passes repaired active-import atomicity, durable exact-event reads, foreground/background replay fences, identifier normalization, final eligibility ordering, compose focus fencing, and exact-generation proof vocabulary before current-source closure
Closure tier: host + real SQLCipher + paired Android device
Baseline: clean checkpoint `aba8cbb1d6bb57c524c6539e4e96b09167340e9d` (`signal-grade group notification recovery`)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 22:25 CEST | Evidence Collector | Plan 329 ledger; Android dropped-push service/store; FlutterFire service; direct/group drains | Full recovery without the main runtime needs separate headless Go/SQLCipher composition | Keep it prerequisite-blocked; do not fake closure with WorkManager |
| 2026-08-02 22:45 CEST | Evidence Collector | group message/reaction listeners; show use case; background handler; staged ingestion | Message/reaction persistence can outrun OS-card success and duplicate replay then skips presentation | Specify durable canonical display custody |
| 2026-08-02 23:00 CEST | Evidence Collector | foreground/background policies; iOS projection; ID registry; registration bootstrap | Policy divergence and missing read-zero cancellation confirmed; unstable IDs and broad registration-ordering gap refuted | Specify policy matrix and exact cancellation |
| 2026-08-02 23:11 CEST | Planner | DB v105 registry; repository composition; live devices; curated gates | Reserve DB v106 for encrypted identifier-only outbox; pin Pixel `21071FDF600CSC` + emulator `emulator-5554` | Submit v1 to `$tdd-review` |
| 2026-08-02 23:45 CEST | Critical Review | mutation ordering; migration chain; read/display race; device harness; policy surface census | v1 was `plan-fixes-required`: stage-before-show left a pre-stage crash gap, a count recheck did not close cancel-vs-show, host FFI was not real SQLCipher, and the device row was not executable | Revise marker ordering, keyed serialization, real-device SQLCipher proof, exact device scenario, privacy boundary, cleanup and rollback contracts |
| 2026-08-03 00:10 CEST | Arbiter | revised TC-330-01..19 and closure commands | Core bet confirmed after repairs; prerequisite-blocked headless runtime and named residuals are not represented as closed | Mark revised plan execution-ready and begin causal RED |
| 2026-08-03 00:47 CEST | Final Counterexample Audit | implemented outbox/retry/listener/push/lifecycle surfaces and focused tests | Reopened implementation: future-backoff rows could strand after restart; ordinary logical-delivery duplicates could leave `not_ready` custody; reaction ADD remained non-atomic; legacy transition identity admitted ABA completion; foreground/background policy/copy and keyed-lane wiring were incomplete; account-import/dissolve closure and several promised tests were absent | Add causal counterexamples, repair production paths, then repeat every host/device gate before closure |
| 2026-08-03 03:40 CEST | Implementation Re-audit | durable retry deadlines; logical aliases; atomic reaction mutation; transition authority; foreground/background lane; migration receiver | Every reopened counterexample received a causal test and production repair; focused, migration, curated, family, localization, runtime-root, Sims registry, and Go evidence is green | Run the registered paired-Android capability and preserve harness failures as evidence |
| 2026-08-03 04:40 CEST | Android Closure | final content-addressed artifact on Pixel `21071FDF600CSC` + emulator `emulator-5554` | Primary `groups.notification_projection_durability` capability passed with one central APK, zero child builds, automated A/B exact read cancellation, and localized photo/video/voice reaction projection | Mark the primary capability Android-closed; keep the existing reaction campaign and S2/S8/S9/S10 reruns explicitly pending |
| 2026-08-03 final gap plan | Planner | current visible-card invalidation paths, SQL triggers, listener lifecycle, registry generation CAS, and Firebase background presenter | Durable display custody did not yet rebuild an already-visible shared group card after policy/read/delete/REMOVE transitions; the headless show path also lacked a canonical post-show fence | Prioritize a durable coalesced reconciliation journal, canonical cross-kind rebuild, then generation-fenced background validation |
| 2026-08-03 final critical review | Critical Reviewer | migration v106 triggers; canonical reconciler/DB loaders; listener stop; generic reaction fallback; show/claim ordering | Review reopened five P1 counterexamples: absent rows were treated as deletion, replacement considered messages only, failed native replacement could be falsely completed, authorized generic reactions could bypass the fence, and show ownership was committed after the SQL read window; teardown also failed to await active reconciliation | Add tri-state decisions, message/reaction newest-attention selection, retryable silent re-publication, signed provisional comparands, immediate post-show owner commit, and quiescent stop tests |
| 2026-08-03 final implementation | Implementer | v106 reconciliation outbox/triggers, process signal, canonical loaders/reconciler, listener/bootstrap, background preview/handler/fence, focused suites | Durable policy/read/delete/REMOVE invalidations now wake canonical generation-CAS rebuild; post-show checks retire only exact invalid generations and preserve newer publishers; unknown materialization stays retryable | Repeat focused, curated family, real SQLCipher, and paired Android-only device gates before restoring CLOSED status |
| 2026-08-03 closure audit | Critical Reviewer + Implementer | membership-repair hard deletes, core-layer imports, real-SQLCipher device contract, reaction campaign manifest, DTR-18 and repository-fixture sentinels | Found and fixed five last-mile gap families: an exact displayed reaction could retry forever after a non-tombstoning stale-rejoin delete; a core helper imported a feature policy model; the device proof still expected the retired marker-clearing trigger and raw reaction identity; the five-scenario campaign advertised four assertions; and DB-v106 expansion exposed stale DTR-18/full-schema fixture assumptions. Current-source host gates are green after the repairs | Run only the pinned USB Pixel + Android emulator device matrix, then close and commit |
| 2026-08-03 final adversarial audit | Critical Reviewer | active-import trigger ordering/rollback; read commit/process-death/reaction-only startup | Closure reopened: direct v106 triggers mutate imported reconciliation rows and checksum failure occurs after commit; group read acknowledgement exists only in memory and startup intentionally preserves active reaction cards | Add TC-330-23 trigger-safe rollback-atomic import and TC-330-24 durable per-reaction acknowledgement, then invalidate every receipt affected by those production changes |
| 2026-08-03 exact-event counterexample audit | Critical Reviewer + Implementer | read snapshot/SQL transaction; foreground loaded retry; background pre/post-show fence; push-before-inbox; identifier constraints; shared keyed lane | Repaired exact A acknowledgement without suppressing later B; message/reaction canonical transfer; pending SQLCipher ack lookup; terminal-null crash replay; prior-ack/newer-push ordering; >1024 accepted IDs; whitespace normalization; and policy/decrypt/current-state rechecks inside the final lane. Controlled RED/GREEN tests cover each case; final audit verdict is no remaining P0/P1 | Freeze source; rerun structured host gates and only the pinned USB Android + emulator proofs |
| 2026-08-03 proof-harness closure audit | Critical Reviewer + Implementer | failed projection captures, compose UIAutomator focus, exact read FLOW validator, reaction/media preservation artifacts | Two consecutive pre-send failures proved ADB input could return success before Flutter focus; a later fully correct artifact proved the validator still required legacy `conversation_read` instead of exact-generation `conversation_acknowledged`. Added exact-once focus fencing and a strict acknowledged-generation criterion with legacy rejection; causal RED/GREEN and artifact revalidation are recorded | Repeat projection, reaction, and media campaigns on only the pinned Android pair; close on formal current-source receipts |

## Outcome And Priority Order

1. **P0 — trigger-safe, rollback-atomic active database import.** Bulk account
   import must copy staged logical rows exactly without firing active v106
   reconciliation triggers. Trigger removal/recreation and logical checksum/
   integrity verification remain inside the same SQL transaction so any
   mismatch restores the active target instead of returning failure after a
   destructive commit.
2. **P1 — crash-durable exact-event read acknowledgement.** Marking a group
   read atomically acknowledges every then-existing reaction and the exact
   snapshotted managed `(group, kind, event, generation)` tuple, retains display
   custody until the acknowledgement-aware projector completes it, and
   enqueues canonical reconciliation even when no unread message row changed.
   Push-before-inbox message/reaction rows absorb only their exact tuple; a
   later event remains eligible and generation-CAS preserves its card.
3. **P1 — durable canonical invalidation and cross-kind shared-card rebuild.**
   Coalesce group policy, membership, read/delete, and reaction ADD/REMOVE
   mutations into a SQLCipher reconciliation journal. Rebuild the current
   stable group card from the newest remaining canonical message or eligible
   reaction, or cancel only its exact generation when no attention remains.
   Missing rows without exact terminal evidence are `unknown`, retain custody,
   and retry; they are never equated with deletion.
4. **P1 — generation-fenced Android background publication.** Immediately
   after a successful native show, commit the exact tone/event owners, re-open
   current SQLCipher state read-only, and validate policy plus exact content.
   Retire only the generation just shown; a concurrent newer publisher wins.
   Authorized crypto-outage reaction copy carries a signed provisional
   comparand so it receives the same policy/target/REMOVE fence without
   fabricating decrypted reaction fields.
5. **P1 — durable group display custody with marker-first ordering.** A group
   message is persisted before `maybeShowNotification`; on failure replay
   becomes a duplicate and returns before presentation. A fresh reaction is
   also stored before display, while inbox or pending-row custody can become
   terminal. Add a SQLCipher-backed, identifier-only display outbox and acquire
   its marker after authorization/policy but **before** the canonical message or
   reaction mutation. If marker acquisition fails, abort that mutation so its
   existing relay/inbox/pending owner can retry. Re-project from canonical state
   on cold/resume retry.
6. **P1 — canonical group eligibility.** Live message, live reaction,
   foreground FCM, and Android background FCM disagree on missing group/current
   membership, QA, archive, dissolve, and self-removal. Introduce one Dart
   policy and apply it at every Android/Dart group display boundary. Existing
   Swift rules are a parity sentinel, not an automated iPhone leg.
7. **P1 — exact stale-card cancellation.** Marking the last unread group
   message read updates canonical state but leaves the group's OS card. Resolve
   the existing durable conversation ID and cancel only that card. Serialize
   unread-zero recheck/cancel and every main-runtime presentation for the same
   group through one keyed queue, so a concurrent new show cannot be erased by
   a stale zero observation.
8. **P2 — privacy-bounded reaction target semantics from canonical local
   state.** For an eligible reaction to the local user's target, derive only a
   localized semantic noun (`message`, `photo`, `video`, `voice message`,
   `file`, or `media`) from the stored message and group-owned media. Never
   quote target text. Add no target hint to FCM/APNs or the iOS shared
   projection.
9. **P2 — fail-closed Android proof integrity.** Device automation must wait
   for an enabled, focusable, focused compose editor before exactly one ADB
   injection, reject partial/different/bubble-only text, and validate the
   ordered committed-read -> in-lane unread-zero -> exact acknowledged-
   generation cancellation sequence. A successful shell command or legacy
   kind-wide cancellation marker cannot satisfy closure.

## Signal Research Grounding

Research refreshed 2026-08-02 against Signal's official Android source and
support documentation. Facts observed in Signal:

- [`NotificationStateProvider`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationStateProvider.kt)
  rebuilds notification state from canonical unread messages, attachments,
  reactions, mute state, and notification-profile state. A reaction is
  included only when its actor is not self, its target is outgoing, and it is
  newer than the last reaction-read boundary.
- [`OptimizedMessageNotifier`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/OptimizedMessageNotifier.java)
  defers updates until after a successful database transaction, deduplicates
  work per conversation, and coalesces bursts with a limiter.
- [`DefaultMessageNotifier`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/DefaultMessageNotifier.kt)
  regenerates the current notification state, removes orphaned cards, records
  notification timestamps only after the notification factory returns, and
  checks for cards that should be present but are missing.
- [`NotificationIds`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/NotificationIds.java),
  [`NotificationCancellationHelper`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/NotificationCancellationHelper.java),
  and [`MarkReadReceiver`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/MarkReadReceiver.java)
  use conversation-stable IDs, deliberately surgical cancellation, and a
  canonical notification rebuild after committing reads.
- Signal support states that reaction banners go only to the author of the
  target and deleted/disappeared targets do not retain reactions
  ([Message Reactions](https://support.signal.org/hc/en-us/articles/360039929972-Message-Reactions)).
  It also documents message-content privacy levels, locked-app generic copy,
  and muted-chat reaction suppression
  ([In-App Notification Options](https://support.signal.org/hc/en-us/articles/360043273491-In-App-Notification-Options)).

Plan-330 inference from those facts: our authoritative projection should also
be regenerated from current canonical state, published only after successful
canonical writes, serialized/coalesced per group, and retired surgically. The
SQLCipher display outbox is Mknoon's recovery mechanism for the concrete crash
gap found in its listener; it is not claimed to be copied from Signal. Our
reaction copy is intentionally stricter than Signal's current rich preview:
it exposes only a localized semantic target kind and never the target text or
reaction emoji.

Confirmed but not silently absorbed:

- **Prerequisite-blocked P1:** true headless canonical direct+group fetch.
  WorkManager alone cannot create safe Go callback ownership, writable
  SQLCipher composition, foreground/headless handoff, or canonical processing.
  Owner: a future `CanonicalRecoveryRuntime` architecture plan.
- **Residual P1 outside this group-only contract:** direct-chat display outbox;
  direct background staging has a different notification-suppression contract.
- **Residual P2 at an excluded boundary:** an unanchored group fallback without
  an exact event identity remains conservative, silent, and generic; it cannot
  safely participate in exact acknowledgement or canonical display custody.
- **Deferred P2:** bounded unread history/summary and Android notification
  `number`. Exact unread-zero cancellation lands now; richer card UX remains a
  separate projection.
- **Deferred P2/P3:** durable user-visible registration health and native
  recovery-card localization. Current bootstrap already awaits group context,
  authored-target, and comparand backfills before Firebase/registration;
  stable Android conversation IDs are collision-safe.
- **Out of scope by user direction:** automated iPhone or iOS-simulator work.
- **Closed in the final pass:** already-visible cards are now durably
  reconciled after mute/archive/dissolve/self-removal, read/delete, and reaction
  REMOVE. The owner selects the newest remaining eligible message or reaction
  before exact-generation replacement/cancellation, so one stale reaction is
  never retired by erasing another canonical attention item.

## Problem And Evidence

- Behavior to improve: each eligible incoming group text/image/video/voice
  message and reaction retains local notification custody until an OS card is
  shown or fresh canonical policy says it is terminally suppressed.
- Impact: a transient notification exception can converge timeline/reaction
  state while permanently losing the user's alert.
- Confirmed message root cause: `GroupMessageListener._handleMessage` in
  `lib/features/groups/application/group_message_listener.dart` persists before
  `maybeShowNotification`; ordinary text replay becomes
  `IncomingGroupMessageIgnored`, while media replay may become
  `IncomingGroupMessageDuplicateEnriched`. Both return before presentation, so
  canonical persistence alone cannot retry display.
- Confirmed reaction root cause:
  `_GroupReactionIngressProcessor._maybeNotifyGroupReaction` in
  `group_message_listener_reaction_ingress_processor.dart` has no durable
  display ownership after the reaction mutation is stored.
- Existing coverage: `show_notification_use_case_test.dart` proves provisional
  claim/tone release after a throw and an explicit later retry. Plan 329's
  paired Android campaign proves successful text/reaction delivery and its
  media run proves text/photo/video/voice copy; neither injects display failure.
- Implemented coverage: restart display custody, policy totality, read-zero
  exact cancellation, locally derived reaction-target copy, account-transfer
  ordering, multi-page canonical convergence, and the retry/transition
  counterexamples from both audits now have causal host tests. Durable
  invalidation plus cross-kind rebuilding closes the former visible
  reaction-REMOVE and policy-transition residuals.
- Refuted findings: stable IDs are already owned by
  `DurableConversationNotificationIdRegistry`; initialization awaits group
  projections and notification service before listeners/registration; adding
  a duplicate foreground presenter remains forbidden.
- Unresolved findings: writable headless runtime/handoff, direct-chat display
  custody, conservative silent generic behavior for unanchored group fallback,
  bounded unread history/Android `number`, durable registration health, native
  recovery-card localization, OEM launcher badge behavior, and manual iOS
  parity. None is represented as closed.
- Affected files: migration/version/registry; display and reconciliation outbox
  domain/data/coordinator files; canonical state/reconciler/signal; group
  listener/reaction ingress; policy, push resolvers, and post-show fence;
  notification service/ID registry; bootstrap/lifecycle; focused tests and
  group/device registrations.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: pending the required final incremental refresh;
  the last compact query reported `56dd053aa9916172` and correctly marked the
  changed canonical-state helper stale.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 330 remaining group notification reliability gaps: DroppedPushRecoveryCoordinator MknoonFirebaseMessagingService durable notification display retry outbox headless canonical fetch WorkManager group projection registration readiness unread badge NotificationStateProvider policy" --profile tdd --budget 700`.
- Anchors: `DroppedPushRecoveryCoordinator` ->
  `lib/core/notifications/dropped_push_recovery_coordinator.dart`; group listener
  and reaction ingress -> `lib/features/groups/application/`; background
  presenter -> `lib/features/push/application/background_message_handler.dart`.
- Surfaced proof/gate files: dropped-push, group listener/drain, background
  handler, notification service/ID tests, and curated group lane.
- Graph gaps requiring source search: resolved FlutterFire service, native Go
  ownership, bootstrap backfill ordering, DB v105, and device registration;
  each was verified in current source.
- Reuse rule: anchors may be handed to review/execution; conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- DB v106 `group_notification_display_outbox`, storing only kind, exact event,
  group, target, actor/reaction comparands, timestamps, and retry metadata — no
  text, emoji, media path, group/user name, key, or ciphertext.
- Acquire an eligible message/reaction marker after path-specific authorization
  and group policy but before `saveMessage` / `saveReaction`. The marker table
  has no foreign keys because canonical rows intentionally may not exist yet.
  Marker write failure aborts the canonical mutation and keeps the existing
  relay/inbox/pending custody retryable. Remove only after normal terminal
  suppression or successful presentation; a display throw retains it.
- The pre-mutation marker starts `not_ready` and is promoted to `ready` only
  after the full canonical message/reaction mutation (including message media
  metadata or buffered-reaction promotion) completes. Replay reconciles an
  ignored text duplicate and a media-enriched duplicate with their existing
  marker. Fault injection at the stage/write/ready seams must make
  “canonical eligible event with no marker” unreachable; a not-ready marker is
  never presented as generic copy.
- Retry from current SQLCipher group/message/reaction/media state and current
  lifecycle/viewing/policy. A temporarily missing canonical row is retained for
  later canonical recovery, not terminally cleared. Read/deleted/replaced/
  tombstoned/ineligible state after materialization is terminal. Repository or
  display failure retains custody. Only each drain pass is bounded: no TTL or
  capacity policy may evict a nonterminal marker. At capacity, a new stage
  fails before mutation/ack instead of deleting old custody. Explicit group,
  message, reaction, self-removal, exit, dissolve, and account-migration rules
  clean only canonically terminal rows without crossing ownership.
- Single-flight retry after listener startup, after canonical resume drains,
  and one bounded delayed retry after an in-session failure. No infinite loop.
- One pure policy input/decision: current group + current local member; type `chat|announcement`;
  not muted, archived, dissolved by flag/timestamp, or self-removed. Apply to
  live/replay message, live/replay/buffered reaction,
  `resolveGroupMessageNotificationDisplayEligibility`, ApplicationRoot's
  foreground group-reaction resolver, `groupMessageLocalStateFromRows`,
  `groupReactionLocalStateFromRows`, the foreground fallback helpers, and
  legacy `groupMemberMessageDisplayEligibility`. Path-specific sender-role,
  device, key, target-authorship, and comparand checks remain separate.
- Exact `cancelConversationNotification('group:$groupId')`; consume the
  existing read-commit stream through the same per-conversation presentation
  coordinator used by listener/retry presentation. Inside the keyed operation,
  re-read unread count and cancel only when still zero.
- Reaction descriptors from canonical target kind/group-owned media only for
  Android/Dart paths; private/direct media fails closed and remote payloads
  remain unchanged.
- Background group display failure is recovered when canonical group drains run
  at the next main-runtime startup/resume and acquire/retry the marker. The
  background identity opener stays read-only. After each managed background
  show it performs a current-state policy/content fence and cancels only the
  just-shown generation when invalid; it still does not run writable canonical
  ingestion or enqueue SQL outbox work from Firebase's headless isolate.
- `maybeShowNotification` exposes typed `shown`, `terminalSuppressed`, and
  `contendedRetryable` dispositions. A fresh pending durable claim retains its
  outbox row and retries after the claim window; an already committed claim is
  terminal. SQL transactions never span the OS/plugin call.
- Canonical listener presentations, reconciliation, and read-zero cancellation
  share the keyed coordinator. Foreground unanchored group fallbacks (no
  canonical event ID) and the native deleted-messages recovery card remain
  explicit preservation boundaries, not SQL-outbox participants. The read-only
  Firebase presenter coordinates with foreground work through the durable
  registry's filesystem lock and generation compare-and-swap: an old fence or
  tap may retire only its own generation and cannot erase a newer card.

Must preserve:

- Stable one-card-per-group identity -> existing collision/reopen tests and
  same-group message/reaction sentinel.
- Claims/tone, live/remote dedupe, viewing, private media, sender/role/device/
  key authorization -> existing suites plus TC-330-04/05/06/10.
- Timeline/reaction persistence despite notification failure -> TC-330-02/03.
- Other group/direct cards on read/tap/cancel -> TC-330-08.
- No target copy/media metadata in iOS shared projection -> source sentinel.

Hard `Do not`:

- Do not add a second foreground presenter or couple relay ack to OS-card
  success.
- Do not persist notification plaintext or add target/media hints to remote or
  shared projection payloads.
- Do not quote target message text in reaction notification copy.
- Do not boot Go or writable identity DB from WorkManager/Firebase headless
  engine in this plan.
- Do not use `cancelAll`, allocate a new ID merely to cancel, or cancel another
  conversation.
- Do not automate iPhone/iOS simulator.
- Do not delete QA storage/transport; Plan 311 owns QA deletion. Suppress only
  legacy QA notifications for parity.

Deferred / accepted difference:

- Headless canonical runtime -> future architecture owner.
- Direct display custody -> direct notification follow-up.
- Rich unread history/count -> UX projection follow-up after P1 semantics.
- iOS implementation/proof -> manual-only; Swift source parity is retained.

Dependencies:

- Plan 329's durable event claims, stable ID registry, canonical recovery, and
  paired-Android harness remain foundational.
- Plan 311 owns QA deletion; Plan 324 owns relay rollout. No relay/deployment
  change is introduced.
- DB v106 is a one-way schema floor: rollback is a newly signed build at schema
  v106 or newer. Downgrade opening remains fail-closed; there is no destructive
  table-drop rollback.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-330-01 | DB v106 creates a no-FK identifier-only bounded outbox and upgrades v105 losslessly/idempotently in production callbacks | `test/core/database/migrations/106_group_notification_display_outbox_test.dart` plus `integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart` | host FFI + real `sqflite_sqlcipher` on both Android IDs | causal RED: v106/table absent -> PRAGMA 106, exact schema/indexes, old rows preserved, marker survives close/reopen, callbacks run twice stably | remove registry entry, add plaintext/FK, or skip reopen -> red | focused; exact version-ripple sentinels; AUTO core + explicit `GROUP_TESTS`; pinned Android commands |
| TC-330-02 | not-ready marker is durable before message mutation; stage failure leaves mutation/custody retryable; ready promotion follows media commit; display throw survives ignored/enriched duplicate replay and restart | `handle_incoming_group_message_use_case_test.dart::TC-330-02 display custody is staged before canonical save and ready after media`, its failed-stage twin, plus `group_notification_display_outbox_wiring_test.dart::TC-330-02/04 message replay stages before canonical save and retains a failed display until retry` and logical-alias rows | host failpoints + reopen/ordering log + repository fixture | causal RED: no pre-mutation hook -> stage, save/media, ready, show; every seam retains a recoverable marker and never canonical-without-marker | move stage after save, ready before media, or delete on throw -> red | focused new file; AUTO feature + explicit group gate |
| TC-330-03 | not-ready marker precedes fresh/replayed/buffered reaction mutation; stage failure preserves ingress custody; ready promotion/display failure retains exact transition | `handle_incoming_group_reaction_use_case_test.dart` TC-330-03 mutation tests plus `group_notification_display_outbox_wiring_test.dart::TC-330-03/04 reaction replay stages its transition id before mutation then promotes and completes it` | host reaction comparand + failpoint/ordering log | causal RED: no durable pre-apply seam -> stage before atomic reaction state; ready after apply; retained transition then one show | restore fire-and-forget/post-save stage/early clear -> red | focused files; explicit group gate |
| TC-330-04 | retry re-reads unread/current eligibility; viewed/read/muted/archived/dissolved/self-removed/QA clears, but not-ready/missing canonical state is retained until materialization or explicit terminal cleanup | `group_notification_display_outbox_wiring_test.dart::TC-330-16 current read mute archive dissolve self-removal and QA state terminalize message custody` plus `::missing canonical message retains custody as state unavailable` | host matrix | causal RED: no projector/total policy -> exact dispositions | snapshot enqueue policy or age/cap-clear a missing row -> red | focused; explicit group gate |
| TC-330-05 | reaction retry rejects removed/replaced/tombstoned/wrong target/actor | `group_notification_display_outbox_wiring_test.dart::TC-330-03/16 reaction projection requires exact active transition comparands` plus the atomic actor-scoped REMOVE/cleanup migration tests | host reaction repository | causal RED: no comparand check -> current exact state required | omit reaction id/timestamp -> red | focused; explicit group gate |
| TC-330-06 | same policy across live message/reaction, foreground, Android background message/reaction, legacy helper | `test/features/push/application/group_notification_display_policy_test.dart::canonical group notification display policy` plus listener/resolver/background wiring rows | pure matrix + path fixtures | causal RED: HEAD differs for QA/archive/dissolve/self-remove/membership -> one reason | delete predicate or restore fail-open -> red | focused policy/listener/resolve/background; explicit group gate |
| TC-330-07 | outbox drain is oldest-first, max-batch bounded and single-flight; work arriving during a pass sets one dirty generation; more than one batch survives restart until every row is shown/terminal, never capacity-evicted | `group_notification_display_retry_coordinator_test.dart` TC-330-07 concurrent-trigger, overflow/error, and retryable-disposition rows plus the `TC-330-P1` restart-deadline, oldest-row starvation, and CAS replacement rows | host completers/fake clock + multi-batch rows | causal RED: coordinator absent -> one active pass, one latched follow-up, later lifecycle retains overflow/errors | remove dirty latch/bound or prune eligible rows -> red | focused; explicit group gate |
| TC-330-08 | read commit and new presentation serialize by group; inside the key, fresh zero cancels the exact existing card, while a queued new show remains afterward | `group_notification_read_projector_test.dart::read zero racing new message cannot erase the new group card` | host stream/repo/plugin fakes + controlled keyed queue | causal RED: query-zero/show/cancel race removes new card -> ordered cancel then show; preserve group B/direct | `cancelAll`, allocate-on-cancel, bypass queue, or omit in-key recheck -> red | focused; AUTO core + explicit group gate |
| TC-330-09 | registry lookup finds existing ID without allocating; missing/corrupt owner fails closed | registry test `::lookup finds an existing owner without allocating and missing or corrupt owners stay null` | real temp FS | causal RED: lookup absent -> ID or null/no new files | implement through `resolve` -> file-count red | focused existing; already group gate |
| TC-330-10 | stable ID, claims/tone, viewing/private suppression and unrelated cards preserved | existing registry/tone/show/listener/reaction pipeline/exact-cancel suites | host sentinels | GREEN on HEAD -> remain green | per-event ID, claim release, blanket cancel -> red | exact suites + `groups` |
| TC-330-11 | localized reaction copy names only canonical message/photo/video/voice-message/file/media kind; text content, long/bidi input, unknown/private media cannot leak | `group_reaction_notification_copy_test.dart::group reaction notification semantic copy` + l10n integrity | pure + owner media fixtures | causal RED: generic hard-coded copy -> localized semantic noun without target text | use direct media/raw text/private target or English literal -> red | focused new + ARB/l10n; AUTO feature + explicit group gate |
| TC-330-12 | live, foreground and Android background use same descriptor with no wire change | listener `::reaction uses canonical target`; background `::group reaction uses group-owned descriptor`; foreground equivalent | host repo/DB row/RemoteMessage | causal RED: paths generic/background omits media -> same output | bypass shared builder/wrong media owner -> red | focused existing tests; group gate |
| TC-330-13 | production composition behaviorally owns repository/coordinator/projector; startup and resume invoke retry only after canonical drains; disposal stops events | `group_notification_display_outbox_wiring_test.dart` startup-hold, multi-page ADD/REMOVE, and incomplete-drain rows; `drain_group_offline_inbox_use_case_test.dart::TC-330-13 first-page drain defers projection until continuation exhausts the cursor`; `group_notification_runtime_wiring_test.dart` | host fake drains/coordinator, exact call log | causal RED: symbols/wiring absent -> behavioral order, no post-dispose calls | move retry before recovery or omit dispose -> red | focused new; AUTO feature + explicit group gate |
| TC-330-14 | Android pair preserves two text cards, stable ID, localized reactions to photo/video/voice targets, no duplicates, and exact in-app read cancellation; incoming media-card preservation is a separate S2/S8/S9/S10 leg | `integration_test/group_notification_projection_android_proof_test.dart` driven by `integration_test/scripts/run_group_notification_projection_android.dart`; separate existing S2/S8/S9/S10 runner | USB API36 + emulator API37 | seed/show group A/B, mark A read in-app, assert A gone/B remains; react to photo/video/voice and assert semantic card | host mutations guard internals; device guards OS/plugin | Final current source: projection 5/5, reaction campaign 5/5, and S2/S8/S9/S10 programmatic + OS-card PASS on the pinned pair |
| TC-330-15 | projection readiness before Firebase/registration and sole registry allocator preserved | existing deferred-startup, projection lifecycle, push coordinator, registry tests | host preservation | GREEN/refuted gap -> remain green | reorder Firebase or bypass registry -> red | exact tests + affected families |
| TC-330-16 | pending claim contention is retryable; restart before claim TTL retains row, competitor failure/release or TTL expiry permits one show; committed claim clears terminally | `show_notification_use_case_test.dart::typed claim disposition distinguishes pending from committed` + retry coordinator race | host real temp claim files + fake clock/completers | causal RED: both return void/null -> row is incorrectly deleted | collapse pending/committed or retry pending immediately -> red | exact push + feature tests; explicit group gate |
| TC-330-17 | relay cursor depends on durable marker, not plugin success: stage failure keeps cursor; durable marker + show failure advances cursor and later retry clears | `drain_group_offline_inbox_use_case_test.dart`: `message staging failure keeps the transport cursor retryable`; `durable message staging advances the cursor when display fails and later retry succeeds`; `reaction staging failure keeps the transport cursor retryable`; `durable reaction staging advances the cursor when display fails and later retry succeeds` | host transactional drain + throwing service | causal RED: current show throw withholds cursor -> exact two-arm outcomes | rethrow post-custody show failure or ack failed stage -> red | focused existing; explicit group gate |
| TC-330-18 | terminal cleanup and account migration preserve ownership: exact group/message/reaction cleanup leaves siblings; pending jobs transfer and retry only after receiver canonical projections rebuild | migration/helper tests + `account_migration_receiver_display_custody_test.dart::transferred display custody retries only after projection rebuild` and its projection-failure twin | host SQL transactions + call log | causal RED: new table absent from cleanup/import lifecycle -> exact rows/results | broad delete, omit table inventory, or retry before rebuild -> red | focused core/feature; explicit group gate |
| TC-330-19 | excluded boundaries remain truthful: relay group pushes stay data-only; headless DB stays read-only; unanchored foreground fallback and native deleted-message recovery remain outside SQL custody | Go push payload tests + Dart/Kotlin source/wiring sentinels | Go host + host source contracts | preservation GREEN -> remain green | add provider notification payload, writable headless open, or claim excluded path -> red | exact Go/Dart/Kotlin tests; groups gate |
| TC-330-20 | every durable mutation that can invalidate visible group content coalesces one restart-safe reconciliation row and emits a process-local wake only after mutation; INSERT OR REPLACE, type/dissolve, member delete, read/delete, and reaction REMOVE are covered | `106_group_notification_reconciliation_outbox_test.dart` plus repository/listener wiring suites | host SQLite trigger inventory + fake signal/outbox | causal RED: policy/read/delete/REMOVE changes leave no durable wake -> exact group row survives restart and is drained after canonical recovery | remove a trigger column/INSERT/member-delete arm or signal-before-write -> red | focused migration/repository/listener; core + groups |
| TC-330-21 | reconciliation is tri-state and cross-kind: absence without tombstone is unknown/retryable; exact terminal state rebuilds from the newest eligible unread message or active reaction; failed silent native re-publication retains custody and retries; stop waits for active reconciliation | canonical reconciler, canonical-state DB helper, reconciliation wiring, retry-coordinator and listener lifecycle tests | host controlled rows/generation CAS/completers | causal RED: boolean absence cancels a push-before-inbox card; message-only replacement erases reaction B; first show throw is falsely completed; stop races DB teardown -> unknown retention, newest-attention replacement, second silent show, quiescent stop | collapse unknown/retire, omit active-reaction loader, restore canonical early-return, or complete after dispose -> red | focused core/feature; groups + core/feature families |
| TC-330-22 | every managed headless group generation commits its event/tone owners immediately after native show, then revalidates canonical policy/content; exact invalid generation retires, newer generation survives, and read/cancel errors keep ownership without re-alert | `background_group_notification_post_show_fence_test.dart`, `push_decrypt_preview_test.dart`, and `background_message_handler_test.dart` post-show rows | pure row matrix + real durable registry/claim files + mocked Android plugin | causal RED: policy/REMOVE race remains visible, authorized crypto-outage reaction has no fence, cancel throw releases owners, or stale fence cancels newer publisher -> exact tri-state/generation outcomes | remove comparand, move commit after SQL read, cancel stable ID without generation CAS, or treat read failure as retire -> red | focused push suites; feature + groups; paired Android preservation |
| TC-330-23 | active account import copies a v106 database exactly without firing target triggers, restores every trigger before commit, and rolls back the active target on integrity/checksum divergence | `migration_database_active_importer_test.dart` trigger-derived-row and forced-mismatch cases plus the extended real-SQLCipher outbox proof | host FFI production-equivalent triggers + real SQLCipher on both Android IDs | causal RED: group INSERT/DELETE trigger mutates reconciliation rows and post-commit checksum throws after overwriting target -> exact checksum, triggers preserved, sentinel survives injected mismatch | leave triggers active, validate after transaction, or fail to recreate one trigger -> red | focused account-migration/core; feature/core families; pinned SQLCipher proof |
| TC-330-24 | opening a group atomically acknowledges every then-existing reaction plus the exact snapshotted managed event/generation, retains ready and not-ready display custody until the acknowledgement-aware projector completes it, and enqueues restart-safe reconciliation even for reaction-only/no-op message reads; a later event remains eligible | `group_notification_canonical_state_db_helpers_test.dart`, `group_notification_read_projector_test.dart`, `106_group_notification_reconciliation_outbox_test.dart`, migration/schema and repository signal rows, extended SQLCipher proof | host SQLite transaction/reopen + real SQLCipher | causal RED: message update commits but reaction/exact event remains eligible and no durable row exists -> acknowledged event retires after reopen, pending marker/new event survive | omit acknowledgement column/tuple, delete loaded custody, enqueue outside transaction, or preserve acknowledgement on a later ADD -> red | focused DB/repository/core; groups + core/feature families; pinned SQLCipher proof |
| TC-330-25 | exact read acknowledgement closes every producer race without becoming kind-wide: push-before-inbox message/reaction transfer, terminal-null crash replay, loaded ready retry, foreground pending/canonical lookup, and background pre/post-show validation all suppress A while distinct/newer B survives | canonical-state, display-outbox wiring, read-projector, push preview/fallback/background-handler/post-show-fence, runtime wiring, and real-SQLCipher suites | controlled keyed interleavings + host DB + both Android SQLCipher targets | causal RED: acknowledged prior A either re-alerts or suppresses later B -> exact event retires before show/tone and later B remains eligible | remove exact terminal/comparand match, omit pending table lookup, cache foreground resolver before lane, or treat any acknowledged row as kind-wide -> red | focused push/groups/core; groups + feature/core families; pinned Android preservation |
| TC-330-26 | identifiers accepted by canonical ingress remain readable: message IDs are trimmed before custody/persistence, acknowledgement storage accepts the canonical message-ID domain while row count remains fail-closed at 512, and long/whitespace IDs cannot roll back a conversation read or miss trigger transfer | incoming group-message, canonical-state helper, v106 migration/capacity, background resolver, and SQLCipher proof tests | host transaction + production migration + both Android SQLCipher targets | causal RED: whitespace ID leaves ghost unread; >1024 ID throws inside read transaction -> normalized exact transfer and long-ID read commit | restore raw ingress ID, re-add event-identity 1024 cap, or evict a live tuple at capacity -> red | focused group/core; groups + core/feature families; pinned SQLCipher proof |
| TC-330-27 | Android proof input and read-cancellation evidence are fail-closed: tap then wait for the exact focused editor before one injection; reject partial/different/bubble-only text; require ordered committed read, in-lane unread-zero, and exact `conversation_acknowledged` notification ID while rejecting legacy `conversation_read` | `reaction_notification_proof_support_test.dart`, `group_notification_projection_android_criteria_test.dart`, and the formal projection campaign | host callback interleavings + captured Pixel/emulator artifact | causal RED: unfocused injection is dropped while ADB exits zero; realistic exact-generation artifact is rejected and legacy marker accepted -> focus-fenced exact-once entry and strict artifact acceptance | inject before focus, retry partial input, accept a bubble, loosen reason substring, or drop ID/order checks -> red | focused 84/84; final groups gate; formal paired-Android projection 5/5 |

### Test Notes

- TC-330-02 discriminator: failpoints before stage, after stage, after canonical
  write, after media write, after ready, and after show. It covers both ordinary
  ignored text replay and media-enriched duplicate replay; no seam may leave an
  eligible canonical event without a marker.
- TC-330-03/05 stores transition `event_id` separately from reaction-state
  `reaction_id`, target, actor, timestamp, and tombstone comparands. ADD ->
  REMOVE -> same-emoji ADD must alert the second distinct transition; an older
  completion CAS cannot delete a newer row.
- TC-330-08 seeds cards for group A/B and direct C and controls both
  interleavings: cancel then queued-new-show leaves A's new card; show then
  read-zero cancels A. B/C remain in both.
- TC-330-11/12 derives only a localized noun from `MediaOwnerLane.group`; it
  never reads target text into copy and adds no shared/remote target field.
- TC-330-16 is mandatory because the existing claim API maps pending and
  committed ownership to the same null/normal-return shape.
- TC-330-18 chooses **transferred custody** for account migration. SQL export/
  import inventories the identifier-only rows; retry waits for receiver-side
  canonical projection rebuild and does not run on partially imported state.
- TC-330-20/21 separates `unknown` from `retire`: a push may precede inbox
  materialization, so absence alone never authorizes cancellation. Exact local
  deletion/REMOVE/policy evidence does. Replacement ordering compares canonical
  message and reaction timestamps and preserves privacy-bounded copy.
- TC-330-22 accepts the unavoidable native-show-to-durable-commit crash seam,
  but permits no SQL/plugin work to enlarge it. Once ownership commits, every
  post-show error is keep/retry and never releases the audible/event right.
- TC-330-23 drops and recreates the active database's own trigger definitions
  inside the import transaction; staged schema never supplies executable SQL.
  Logical checksum and quick-check execute before commit so failure restores
  both rows and triggers.
- TC-330-24/25 uses a nullable local-only acknowledgement timestamp on existing
  reaction rows plus a bounded-count identifier-only exact tuple for a managed
  card that has not materialized canonically. The read transaction is the
  ordering boundary: later ADD B replaces canonical state with a fresh NULL,
  while exact A custody remains until an acknowledgement-aware projector
  completes it. Foreground and background checks bind by exact terminal or
  decrypted comparand, never by reaction kind alone.
- TC-330-26 bounds tuple count rather than narrowing the already accepted
  canonical message-ID domain. Ingress trims before marker acquisition and
  persistence, so helper lookup, SQL trigger transfer, registry metadata, and
  foreground/background parsing use one identity.
- TC-330-27 treats shell exit zero as transport acknowledgement only. The
  helper waits for Flutter's exact active editor, injects once, and fails closed
  after any partial/different value. The validator keeps exact ID and ordering
  predicates while requiring the final generation-CAS reason; it does not
  accept the older kind-wide cancellation path.

## Implementation Steps

1. Snapshot `git status --short`; add TC-330-01..19 tests and record exact HEAD
   failures before production edits.
2. First record the checkpoint-existing stale full-chain/runtime-root v104
   expectations, then update all v105-last registry/version sentinels for the
   v106 allocation. Add the host migration and real `sqflite_sqlcipher` Android
   proof (upgrade/fresh/reopen/rerun/interruption/wrong-key/downgrade refusal).
3. Add DB v106 migration, model/helper/repository, no-FK constraints/indexes,
   exact-comparand ready/complete, per-pass bounded load, fail-closed capacity,
   every named terminal cleanup transaction, and account-import inventory.
   Never delete nonterminal custody by age/capacity and never hold SQLCipher
   across plugin/native calls.
4. Add pure policy and replace all named Android/Dart policy branches while
   preserving path-specific authorization/crypto gates.
5. Add the pre-mutation not-ready stage and post-canonical ready seams for
   messages/reactions, including ignored/enriched/buffered replay. Expose typed
   presentation/claim disposition; once the marker is durable, swallow plugin
   failure for cursor progress while retaining the row. Stage failure remains
   an ingestion error. Wire bounded delayed/startup/post-canonical-drain resume
   retries and receiver-post-rebuild retry.
6. Add non-allocating ID lookup, exact cancellation, and one per-group
   presentation coordinator used by listener, retry, and read projector.
7. Add shared localized target-kind copy and wire live/foreground/background from
   canonical group-owned data. Preserve private-media fail-close.
8. Register tests and exact Android Sims scenario; run focused GREEN and
   representative mutations/re-red;
   restore; run migration/preservation/groups/core/feature gates, analyzer,
   diff hygiene, Graphify incremental refresh.
9. Build once; run only pinned USB Android + Android emulator automated proof
   and record APK/source/device provenance.
10. Final-review delta: add the v106 reconciliation journal/triggers and
    process wake; tri-state canonical regeneration with newest message/reaction
    selection, retryable silent re-publication, and quiescent teardown; then add
    the signed provisional reaction comparand and post-show exact-generation
    fence with commit-before-read ordering. Repeat all affected gates and both
    Android proof legs because the earlier artifact predates these repairs.
11. Fourth-review delta: make active import trigger-silent and validation
    rollback-atomic; persist reaction/exact-event acknowledgement, retain
    display custody for acknowledgement-aware projection, and enqueue
    reconciliation in the group-read transaction. Repeat focused/import/
    migration/family gates, both real-SQLCipher legs, and every Android OS-card
    campaign because all earlier receipts predate this repair.
12. Final exact-event delta: snapshot managed metadata inside the shared group
    lane before the read commit; persist/load/consume exact message/reaction
    acknowledgements; bind staged reaction custody to its terminal identity;
    recheck acknowledgement and final canonical policy/decrypt/LWW state inside
    every foreground/background presentation boundary; normalize message IDs
    before custody and accept long canonical IDs without read rollback. Repeat
    all affected host and pinned Android gates from frozen current source.
13. Device-proof delta: reproduce the pre-send focus loss twice, add a
    callback-driven exact-once compose focus fence, then reproduce the stale
    read-flow validator against a behaviorally correct artifact. Require exact
    `conversation_acknowledged` JSON and reject legacy `conversation_read`;
    rerun focused host tests, the curated groups lane, projection, reaction,
    and S2/S8/S9/S10 on the same pinned Android pair.

## Risks And Blind Spots

- Crash after OS show but before claim/outbox completion -> stable group ID
  makes retry an in-place update; committed exact claims suppress. Atomic OS+DB
  exactly-once is impossible; TC-330-02/03/10 guard reachable ordering.
- Crash at canonical custody transfer -> not-ready marker precedes mutation and
  failpoints prove no eligible canonical row can exist markerless; replay makes
  it ready only after full canonical/media application; TC-330-02/03/17.
- Pending claim mistaken for committed -> typed disposition and claim-window
  retry; TC-330-16.
- Stale retry after mute/read/remove -> canonical retry + exact comparand;
  TC-330-04/05/20/21. Reconciliation selects the newest remaining canonical
  message or reaction and mutates only the snapshotted generation, rather than
  broadly cancelling a shared group card.
- Plaintext outbox -> constrained identifier-only schema, canonical copy;
  TC-330-01/11.
- Weakened authorization -> shared policy is group-level only; existing
  sender/device/key gates remain; TC-330-06/10/12.
- Collision/over-cancel -> non-allocating lookup and exact cancel;
  TC-330-08/09.
- Lifecycle / derived-state durability: DB reopen + startup/resume drain;
  TC-330-02/03/07/13.
- Sibling-surface consistency: text/media and reactions share policy/retry but
  keep event-specific comparands; TC-330-02/03/06/12.
- Destructive-action side effects: stale rows clear only themselves and read
  cancellation preserves other cards; TC-330-04/05/08.
- Invariant re-verification: every retry rechecks unread, policy, membership,
  target authorship, reaction and private state; TC-330-04/05/07.
- Queue/cap cleanup loss -> bounds apply to a pass, never live custody; new
  stages fail closed at capacity and exact cleanup preserves siblings;
  TC-330-07/18.
- Background/cross-isolate overclaim -> group data-only push/canonical drain is
  the recovery owner; the read-only headless fence is bounded to current policy
  and its exact generation; TC-330-19/22. The durable registry lock and
  generation CAS, not an isolate-local queue, close stale background
  cancellation against a newer foreground publisher.
- Push-before-inbox absence -> tri-state unknown retains durable custody;
  deletion/REMOVE requires exact terminal evidence; TC-330-21/22.
- Read A versus later B -> acknowledgement matches the exact pending tuple,
  terminal identity, or decrypted canonical id/timestamp; every final
  eligibility/read check and show shares one group-keyed lane; TC-330-24/25.
- Accepted identifier mismatch -> message IDs normalize before custody and the
  exact-ack table bounds live row count without rejecting the canonical ID
  domain; TC-330-26.
- Replacement show ambiguity -> canonical reconciliation silently republishes
  the stable ID while its durable job remains; a native throw cannot be
  mistaken for completed display; TC-330-21.
- Account teardown -> timer/signal retries are tracked and stop waits for
  quiescence; a disposed coordinator never completes custody after an awaited
  projector returns; TC-330-21.
- False device closure from shell/validator drift -> compose injection waits for
  exact focus and occurs once; artifact validation binds ordered read/count/
  exact acknowledged-generation cancellation. Earlier failing captures remain
  evidence rather than being relabelled; TC-330-27.
- OEM launcher numeric badges are not claimed.

## Gate Cadence

- Per-plan: focused TCs, migration-chain/preservation sentinels,
  `./scripts/run_test_gates.sh groups`, justified `core-host-all --dart-only
  --batch-flutter --concurrency 4 --reporter failures-only`, and justified
  `feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter
  failures-only` for the changed core/feature surfaces.
- Do not run full `host-all` for this plan. The Plan-329/330 notification wave
  owns aggregate `host-all` only after this plan and the direct sibling finish;
  final rollout/release owns the last aggregate run.
- Shared tests outside globs run by exact command and remain registered for the
  later wave-level `host-all`.

## Acceptance Gates

```bash
git status --short

# Causal RED before production edits; each exits non-zero for its named reason.
flutter test test/core/database/migrations/106_group_notification_display_outbox_test.dart
flutter test test/features/groups/application/group_notification_display_retry_coordinator_test.dart
flutter test test/features/push/application/group_notification_display_policy_test.dart
flutter test test/core/notifications/group_notification_read_projector_test.dart
flutter test test/features/push/application/group_reaction_notification_copy_test.dart
flutter test test/features/groups/application/group_notification_display_outbox_wiring_test.dart
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart --plain-name 'typed claim disposition distinguishes pending from committed'
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'message staging failure keeps the transport cursor retryable'

# Focused GREEN; exit 0, zero failed tests.
flutter test test/core/database/migrations/106_group_notification_display_outbox_test.dart
flutter test test/features/groups/application/group_notification_display_retry_coordinator_test.dart
flutter test test/features/push/application/group_notification_display_policy_test.dart
flutter test test/core/notifications/group_notification_read_projector_test.dart
flutter test test/features/push/application/group_reaction_notification_copy_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test test/features/push/application/resolve_group_notification_route_target_use_case_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
flutter test test/features/push/application/push_decrypt_preview_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/core/notifications/durable_conversation_notification_id_registry_test.dart
flutter test test/core/notifications/flutter_notification_service_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart
flutter test test/unit/runtime_root_inventory_test.dart
flutter test test/features/groups/application/group_notification_display_outbox_wiring_test.dart
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart
flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart
flutter test test/core/notifications/account_migration_receiver_display_custody_test.dart
flutter test test/core/notifications/group_notification_runtime_wiring_test.dart
flutter test test/core/database/migrations/106_group_notification_reconciliation_outbox_test.dart
flutter test test/core/database/helpers/group_notification_canonical_state_db_helpers_test.dart
flutter test test/core/notifications/group_notification_canonical_reconciler_test.dart
flutter test test/features/groups/application/group_notification_reconciliation_wiring_test.dart
flutter test test/features/push/application/background_group_notification_post_show_fence_test.dart
flutter test test/l10n/l10n_integrity_test.dart
flutter test test/integration/reaction_notification_proof_support_test.dart
flutter test test/core/debug/group_reaction_notification_fixture_test.dart

./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh core-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_test_gates.sh feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only
flutter test test/tool/sims/sims_manifest_test.dart test/tool/sims/sims_proof_binding_registry_test.dart
./scripts/test/reliability_simulation_discovery_contract_test.sh
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental

# Real SQLCipher v105 -> v106 proof, pinned to the allowed Android targets.
flutter test --no-pub -d 21071FDF600CSC integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart
flutter test --no-pub -d emulator-5554 integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart
flutter test --no-pub -d 21071FDF600CSC integration_test/group_exit_intents_sqlcipher_proof_test.dart
flutter test --no-pub -d emulator-5554 integration_test/group_exit_intents_sqlcipher_proof_test.dart
flutter test --no-pub -d 21071FDF600CSC integration_test/group_self_removed_marker_sqlcipher_proof_test.dart
flutter test --no-pub -d emulator-5554 integration_test/group_self_removed_marker_sqlcipher_proof_test.dart
ANDROID_SERIAL=21071FDF600CSC ./android/gradlew -p android :app:connectedReleaseAndroidTest --no-parallel -PenableGroupExitReleaseDiagnosticsProof=true -PdisableGoogleServicesForDisposableProof=true -PandroidApplicationId=com.mknoon.app.pb266proof -Ptarget="$PWD/integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart" -Ptarget-platform=android-arm64
ANDROID_SERIAL=emulator-5554 ./android/gradlew -p android :app:connectedReleaseAndroidTest --no-parallel -PenableGroupExitReleaseDiagnosticsProof=true -PdisableGoogleServicesForDisposableProof=true -PandroidApplicationId=com.mknoon.app.pb266proof -Ptarget="$PWD/integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart" -Ptarget-platform=android-arm64
```

## Device/Relay Proof Profile

- Profile: `os-notification-device-lab`, paired Android; no relay deployment.
- Boundary: real Android publication of two group text cards, stable in-place
  group identity, localized photo/video/voice reaction-target semantics, exact
  read cancellation, and zero duplicates. Incoming photo/video/voice cards are
  the separate S2/S8/S9/S10 preservation leg.
- Live availability: `flutter devices --machine && adb devices -l` -> USB
  Pixel 6 `21071FDF600CSC` API36 + emulator `emulator-5554` API37. iOS targets
  are deliberately unused.
- Required setup: one final-source APK; explicit roles on both Android IDs;
  automated permissions/setup/navigation/actions/shade assertions/cleanup; no
  user taps.
- Two-peer default: USB `21071FDF600CSC` + emulator `emulator-5554`.
- Closure role: required OS-card/cancel evidence. Injected display failure and
  SQL outbox crash semantics close at causal host/SQLCipher tier.
- Registration: add exact `groups.notification_projection_durability` in
  `tool/sims/critical_features.json`, running
  `integration_test/scripts/run_group_notification_projection_android.dart`
  from the centrally prepared `android.production_fcm` APK. Keep existing
  `groups.reaction_notification_campaign` as a preservation scenario. Media
  S2/S8/S9/S10 remains a separate runner whose child-build provenance is
  reported separately, not merged into the new scenario's one-APK claim.
- Discovery: `flutter devices --machine && adb devices -l`; both IDs must be
  listed as Android `device`.
- Exact projection scenario: seed/show cards for groups A/B; navigate to A
  through app UI without tapping its notification; wait for committed unread
  zero; use `dumpsys notification --noredact` to prove A's stable ID is absent
  while B remains. Then react to photo/video/voice targets and assert localized
  semantic nouns, one stable card, and zero duplicates. Setup, permissions,
  navigation, actions, shade assertions, and cleanup are fully automated.
- Historical pre-final capability result: **PASS preservation evidence; not
  current-source closure evidence**. Artifact:
  `build/sims/proofs/groups.notification_projection_durability/capture-1785724334313669-23116/android_group_notification_projection_durability.json`;
  artifact SHA-256
  `c3efd8e0bee4b7dfe4e605a5ba828b6661799ca084953884d1f5c1069a35a0b6`;
  evidence SHA-256
  `b61cdfbfc98705b1f013823fdc7123d8fd26e84824d9413a582e36a0363bf475`.
  The self-validating capture used central `android.production_fcm` APK SHA-256
  `7b11316958654ea29e1029de957afcd2534274993367b1b9bc55649db8985c7f`,
  package `com.mknoon.app`, and `childBuildCount=0`.
- Historical topology and fixture: physical recipient Pixel
  `21071FDF600CSC`, emulator sender `emulator-5554`, actor `Alice`, locale `en`;
  group A `Plan330A-fixture10bd41b7c` / ID SHA-256
  `4561a4d6df7e49bd92b73a10ed2b3b2f1355261024c78229563b1d5804edb31a`;
  group B `Plan330B-a426e0c92f84baab` / ID SHA-256
  `05f8bebcd3961b68fe781770b42a205288dbbe98982672d8be9161fb96a78422`.
  Both were unread-one before in-app navigation; A committed `1 -> 0` while B
  stayed unread-one. A's stable notification ID `1779329386` was cancelled and
  B's distinct ID `1848880051` remained, with zero notification-card taps.
- Historical reaction evidence reused A's stable ID `1779329386`, recorded exactly
  one group-owned attachment each for photo/image, video/video, and voice
  message/audio, validated their content-addressed target receipts and exact
  localized copy, and reported `duplicateCount=0`, `manualTaps=0`, and
  `notificationCardTaps=0`.
- Closure commands (with the same relay/FCM environment used by Plan 329):

  ```bash
  SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  dart tool/sims/sims.dart major --only groups.notification_projection_durability

  SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC \
  SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
  dart tool/sims/sims.dart major --only groups.reaction_notification_campaign

  dart run integration_test/scripts/run_notification_sound_smoke.dart \
    -d emulator-5554,21071FDF600CSC \
    --rows S2,S8,S9,S10 \
    --non-interactive \
    --artifact-dir build/sims/proofs/plan-330-group-media-preservation
  ```

  The first scenario requires one APK/source digest and zero child builds. The
  separate media runner records its own builds and is preservation evidence,
  not provenance for the new semantics.
- Final-current-source projection: **PASS 5/5** in 8m16.441s. Source digest
  `b8290f00a9cfaac84b56c190ee9bc33e09c07e979794075ad1ae632f3917bac6`;
  production-FCM APK SHA-256
  `2cea4ae25b4add38bb3b37dfbc5e7d1beff2664869e276ede60e329d78b4ab32`;
  zero child builds; report SHA-256
  `7af611f4089be4c399e93bfe73075a848e9ccd18eda0314f1676f7abe5b43273`;
  Sims evidence SHA-256
  `ea0a898a65d89eedba4ee3fecd70d1ec515e882368e157ffc7b28f411ff2f433`;
  capture artifact SHA-256
  `75475829fc9fcb1d329f5c9a85b9553c2891404c3186867d17e1692fabd07317`.
- Final-current-source reaction campaign: **PASS 5/5** in 28m05.338s on
  the same APK/pair. Source digest
  `f7fa1216006f263dcba57c3a9bac077b5818ff8a5f756ea7e5376fd670f2ef9f`;
  report SHA-256
  `ce6e362e63e08ddbf800b8ec447cb8426c916b7bb77fc0fb54dcc97b0680e8fc`;
  Sims evidence SHA-256
  `42326cb83736902588dc83aa6bff72205e750d2478ccddc5ba55666f6603cb57`.
- Final S2/S8/S9/S10 preservation: **PASS** for text/photo/video/voice,
  programmatic plus OS-card predicates, one card and zero duplicates per row,
  stable group notification ID `662764818` across 4/4 observations. Summary
  SHA-256
  `cc7c7280ce0431714bdcb4feef70c1cc6830b1d9f97bde08d041c9f333086e5a`.
  Audible confirmation is intentionally `null` under `--non-interactive`;
  shutdown stream warnings occurred only after all evidence was durable.
- Deferred: iPhone manual only; unavailable Android bands are
  `N/A (target unavailable by project policy)`.

## Execution Interpretation And Done Criteria

- Expected RED: missing v106/outbox/policy/read-projector/copy symbols or the
  documented behavior mismatch; compile RED only for intentionally absent
  seams.
- Green sentinel: claims/tone/viewing/private policy, stable IDs, unrelated
  cards, bootstrap ordering, media copy, and existing Android campaign.
- Historical checkpoint characterization after clean `aba8cbb1` found
  `full_migration_chain_test.dart` has four stale expected-v104 assertions
  against actual v105 (lines 1467/1487/1504/1943), and
  `runtime_root_inventory_test.dart` has one stale literal-v104 preservation
  anchor. Plan 330 repaired that required version ripple; the final migration
  chain is 17/17 and runtime-roots is 20/20.
- Environment blocker: none for the Android pair; iOS is non-gating.
- Scope drift: new wire fields, plaintext outbox, headless writable DB/Go,
  `cancelAll`, or relay-ack/display coupling requires re-plan.

- [x] Every in-scope behavior has named test/proof.
- [x] Causal RED, focused GREEN, representative mutation re-red recorded.
- [x] Primary and named Android preservation gates pass on final current source:
  projection 5/5, reaction campaign 5/5, and S2/S8/S9/S10 programmatic + OS
  PASS on the pinned pair.
- [x] Harness registration verified.
- [x] DB v106 real migration, PRAGMA, old rows, run-twice and chain pass on both
  pinned Android targets; all four SQLCipher/release-diagnostic legs pass per
  target.
- [x] Paired Android primary proof passes on final current source using only the
  pinned USB/emulator pair.
- [x] Analyzer has no new issues; source diff hygiene is clean.
- [x] Scope guard respected.

## Handoff

- Host and Android boundaries are closed on final current source. Earlier
  content-addressed artifacts and failed setup/capture attempts remain
  historical evidence only; none is substituted for the final PASS receipts.
- Every Plan-330 test requiring curated group registration is in `GROUP_TESTS`;
  remaining new core/feature tests are covered by their family sweeps. The exact
  `groups.notification_projection_durability` scenario and validator are in the
  Sims manifest.
- The projection capability, Android reaction campaign, and S2/S8/S9/S10
  media-card runner all have final-current-source Android-only receipts with no
  manual or notification-card taps.
- Unresolved: headless runtime/handoff, direct display custody, conservative
  silent generic behavior for unanchored group fallback, durable registration
  health, native recovery-card localization, rich unread history/Android
  `number`, OEM badge behavior, and manual iOS parity.

## Reviewer Findings

Initial `$tdd-review` verdict: **plan-fixes-required**; core bet **confirmed but
under-specified**. Three independent counterexample/boundary/migration reviews
and the five review lenses found these material gaps in v1:

1. **Requirements/testability:** “stage before show” allowed a crash after the
   canonical write but before enqueue. Ordinary ignored duplicates, not only
   media-enriched duplicates, bypass presentation. v1 also lacked exact
   drain-cursor transfer tests.
2. **Correctness/concurrency:** a fresh pending notification claim and an
   already committed claim both looked like normal suppression; deleting a job
   on the former loses custody. Unread recheck and cancel could race either a
   new show or a retry's check/show interval.
3. **Boundary integration:** writable SQL custody cannot honestly include the
   read-only Firebase background isolate, unanchored foreground fallback, or
   native deleted-message recovery card. Every actual foreground/background/
   live/replay/buffered policy boundary needed a wiring test, and relay group
   pushes needed a data-only sentinel.
4. **Migration/lifecycle:** host FFI alone was not real SQLCipher proof. v106
   needed fresh/upgrade/reopen/rerun/interruption/wrong-key/downgrade coverage,
   exact cleanup ownership, account-import semantics, a one-way rollback floor,
   and acknowledgement of five stale-v104 checkpoint tests.
5. **Counterexamples/privacy/operations:** capacity or TTL pruning could pass
   the original bounded-drain tests while deleting live custody; reaction text
   quoting expanded privacy exposure; production wiring/device rows were
   partly source-string or “extend as needed” claims, and the completeness
   command was nonexistent.

Revisions applied in place:

- marker-first `not_ready -> ready` custody with seam failpoints, no-FK schema,
  no live-row eviction, exact reaction transition comparands, and stage-vs-show
  relay cursor rules;
- typed shown/terminal/contended presentation results and pending-claim TTL
  race proof;
- one group-keyed lane for check/show and unread-zero exact cancellation, with
  both controlled interleavings;
- exhaustive policy surface census plus explicit excluded-boundary sentinels;
- real SQLCipher proof on both allowed Android targets, cleanup/import/
  downgrade rules, behavioral lifecycle ordering, localized kind-only reaction
  copy, and literal registered Android proof commands.

Final `$tdd-review` equivalent verdict: **implementation-fixes-required** at
the reviewed snapshot; no P0, five P1/high races. All are mandatory TC-330-20
through TC-330-22 deltas rather than deferred claims:

1. Boolean canonical checks could cancel push-before-inbox content when the row
   had not materialized. The revised contract is `keep / retire / unknown`,
   with exact tombstones/REMOVE/policy as the only terminal absence evidence.
2. Replacement considered only unread messages, so removing reaction A could
   erase still-active reaction B. The revised loader chooses the newest
   privacy-eligible attention item across messages and reactions.
3. A native replacement throw happened after new metadata activation; a later
   canonical early return could then complete custody without re-showing. The
   revised reconciler performs an idempotent silent exact-generation refresh
   while the durable invalidation job exists and retains the job on failure.
4. Authorized generic group-reaction copy on a transient decrypt outage lacked
   a post-show comparand. It now carries only signed/context-validated scope and
   transition identity—never fabricated decrypted emoji/id/timestamp—and is
   fenced for policy, target deletion/private state, and canonical REMOVE.
5. Post-show SQL work enlarged the native-show-to-owner-commit crash window,
   and teardown did not await active reconciliation. Owner commit now directly
   follows native show; retry futures are tracked, stop awaits quiescence, and
   disposal cannot complete custody after an awaited projector returns.

The review considered a single SQL transaction spanning all message/media/
reaction work. It was rejected because existing media/bridge work must not hold
the SQLCipher write lock. The revised two-phase marker is the smaller safe
primitive: durable not-ready custody precedes any canonical mutation, ready is
promoted only after full canonical application, and every failure seam is
explicitly tested.

The final closure audit found and repaired five additional last-mile defects
before accepting the implementation:

1. A stale-rejoin membership-repair hard delete could leave an exactly
   displayed reaction in perpetual `unknown`. Exact retained terminal custody
   now proves the deleted target once existed and permits generation-scoped
   retirement, while a genuinely absent push-before-inbox row stays retryable.
2. A core canonical-state helper imported the feature-layer private-media
   policy model. The helper now owns only its narrow persisted-policy predicate,
   with a parity test and the architecture boundary restored.
3. The real-device SQLCipher proof still expected the retired
   marker-clearing trigger and later expected a raw reaction identity where the
   production helper intentionally stores its bounded identity. The proof now
   validates the durable reconciliation trigger, terminal-marker preservation,
   interrupted-migration repair, and the bounded production identity.
4. The reaction campaign registered five scenarios but its summary and target
   error advertised four. The manifest and runner now enumerate all five,
   including the background-connected recipient.
5. DB-v106 and full-schema fixture expansion exposed stale DTR-18 and
   repository-test setup assumptions. Their exact sentinels now use the current
   bootstrap digest and the production schema constructor.

The subsequent exact-event audit reopened and repaired the remaining
read/display counterexamples: trigger-safe import rollback, push-before-inbox
exact tuples, terminal-null message/reaction crash replay, prior-A versus later-B
background ordering, pending and canonical foreground checks, final policy and
decrypted LWW resolution inside the shared group lane, long accepted IDs, and
whitespace identity normalization. Each received a causal RED before the
production repair. The final read-only reviewer verdict on frozen source is
**no remaining P0/P1** in exact-event acknowledgement or notification replay
closure.

The device-proof audit then found two harness-only counterexamples without
weakening that production verdict. Two runs stopped before their first send
because ADB returned success before Flutter's editor owned focus; a later run
completed every product assertion but the validator rejected the new exact-
generation reason while still accepting the retired kind-wide reason. TC-330-27
adds a bounded exact-focus, single-injection helper and a validator that requires
ordered committed read, in-lane unread zero, exact notification ID, and JSON
`conversation_acknowledged`. The realistic fixtures recorded causal RED, legacy
`conversation_read` is explicitly rejected, and the final formal device run is
5/5 PASS.

## Arbiter Decision

- Final verdict: **CLOSED / PLAN-GREEN / ANDROID-CLOSED**. TC-330-20..27 and
  every confirmed production or proof-harness gap are implemented with causal
  RED/GREEN, a no-P0/P1 final production review, structured current-source host
  gates, eight real-SQLCipher/release legs, and formal projection/reaction/media
  receipts on the pinned Android pair.
- Core bet: **confirmed** for canonical Android/Dart group notification
  projection durability, policy parity, exact foreground read cancellation,
  and privacy-bounded reaction semantics.
- Scope disposition: **keep** the bounded main-runtime/SQLCipher slice;
  **defer** writable headless Go/SQLCipher composition, direct-chat custody,
  rich unread history/count, OEM badge claims, and iOS automation. Immediate
  policy-change and reaction-REMOVE card convergence moved into the final
  canonical-reconciliation implementation rather than remaining residuals.
- Mandatory execution stops: re-plan if marker stage cannot precede every
  canonical mutation/ack, pending vs committed claims cannot be distinguished,
  the read/show lane must span a background isolate, or the Android scenario
  needs manual taps.
- Device disposition: automated closure is only USB Android
  `21071FDF600CSC` plus Android emulator `emulator-5554`; iPhone remains manual.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-02 23:33 CEST | baseline characterization | full migration chain + runtime-root inventory | 32 pass / 5 known stale-v104 failures | Four full-chain expectations and one inventory anchor predate v106 | Treat as explicit version ripple; start causal RED |
| 2026-08-03 | causal RED / mutation | canonical display policy | muted suppression removed: 12 pass / 2 fail; restored: 14/14 | The shared policy suite independently detects the production predicate | Mutation re-red satisfied | Continue focused GREEN |
| 2026-08-03 | focused implementation | outbox, listener, reaction ingress, push, read projector, lifecycle | focused combined 952 pass | Reopened deadline, alias, atomicity, ABA, policy/copy/lane, dissolve, and account-transfer counterexamples are covered | No Plan-330 failure | Run migration and curated gates |
| 2026-08-03 | migration / causal families | DB v106, incoming handlers, wiring, cursor transfer | outbox/migration 13/13; wiring/incoming 91/91; related combined 141/141; full migration chain 17/17; TC-330-17 4/4 | v105 -> v106, terminal markers, exact cleanup, aliases, custody transfer, and receiver ordering are green | Historical v104 ripple resolved | Run registered/family gates |
| 2026-08-03 | final current-source host closure | focused counterexamples, completeness, groups, runtime roots, core, feature, Sims, discovery, analyzer | affected 788/788; completeness 1389/1389; canonical `groups` retry 3903/3903 plus all Go/relay legs; runtime-roots 20/20; `core-host-all` 3000/3000 across 379 paths; `feature-host-all` exit 0 across 825/825 paths with the one known SQLCipher-capability skip; Sims manifest/binding 22/22; discovery PASS; analyzer and diff clean | One unrelated P269 timing failure on the first groups run passed immediately in isolation and on the complete retry; the required failures-only feature reporter emitted no case aggregate, so none is fabricated | No current-source host blocker; full per-plan `host-all` deliberately not run by project cadence | Re-run only affected proof-harness tests/groups after any later harness delta |
| 2026-08-03 | final real SQLCipher | Pixel `21071FDF600CSC` API36 + emulator `emulator-5554` API37 | Per target: display-outbox 1/1, exit-intents 1/1, self-removed marker 1/1, connected release diagnostics 1/1; all 8 legs PASS | Real `sqflite_sqlcipher` v106 migration/reopen/repair behavior and release diagnostics pass on both allowed Android targets; expected downgrade-refusal log is handled | No SQLCipher/device blocker | Run paired OS-card campaigns |
| 2026-08-03 | Android harness counterexamples | paired proof driver/support | `capture-1785718039015470-89483`: Orbit-node timeout; `capture-1785719273485497-94662`: exact-two-card timeout; `capture-1785720215260343-98679`: three parsed cards; `capture-1785721174038533-4265`: transient creator readiness timeout | Repaired Intros -> Inner Circle navigation, spinner-as-accepted race, and id-0 Android auto-group-summary parsing. The last capture was external relay dial/backoff, not a product assertion. | Harness defects repaired; transient external failure superseded | Repeat unchanged primary capability |
| 2026-08-03 04:40 CEST | historical pre-final paired Android proof | content-addressed artifact | `groups.notification_projection_durability` PASS; artifact SHA `c3efd8e0bee4b7dfe4e605a5ba828b6661799ca084953884d1f5c1069a35a0b6`; evidence SHA `b61cdfbfc98705b1f013823fdc7123d8fd26e84824d9413a582e36a0363bf475` | Pixel/emulator, one central APK SHA `7b11316958654ea29e1029de957afcd2534274993367b1b9bc55649db8985c7f`, zero child builds, A exact-cancel/B preserved, three localized reaction target kinds, zero duplicates/manual/card taps | Preservation evidence only because canonical reconciliation and post-show fence changed afterward | Repeat projection, reaction campaign, and S2/S8/S9/S10 on final source |
| 2026-08-03 final exact-event audit | import, DB/read, listener, foreground/background FCM, DTR sentinels | causal REDs for missing exact APIs, prior-A/newer-B, pending ack, terminal-null replay, policy/reaction lane ordering, long ID, and whitespace ID; GREEN batches include 125/125, 55/55, 295/295, 79/79, 143/143, 97/97, 91/91 and clean targeted analyzers | Exact pending/canonical acknowledgement and final eligibility now precede claim/tone/show inside the shared key; final reviewer found no remaining P0/P1 | Earlier receipts invalidated; final host/SQLCipher/Android receipts all postdate the repair | Closed by current-source evidence below |
| 2026-08-03 proof-harness TDD | compose support + projection criteria | focus helper compile RED -> 81/81 GREEN; realistic acknowledged-generation fixture RED while legacy marker falsely passed -> 3/3 GREEN; failed projection artifact then validates exactly | ADB input waits for exact focus and injects once; criteria requires ordered read/count/exact-ID `conversation_acknowledged` and rejects legacy `conversation_read` | Two pre-send focus failures and one stale-validator failure preserved as counterexamples; production behavior unchanged | Run final paired Android campaigns and affected host gate |
| 2026-08-03 final Android closure | projection, reaction, S2/S8/S9/S10 | projection 5/5 in 8m16.441s; reaction 5/5 in 28m05.338s; media text/photo/video/voice programmatic + OS PASS, one card/zero duplicates/stable ID 4/4 | One cached production-FCM APK SHA `2cea4ae25b4add38bb3b37dfbc5e7d1beff2664869e276ede60e329d78b4ab32`; projection evidence SHA `ea0a898a65d89eedba4ee3fecd70d1ec515e882368e157ffc7b28f411ff2f433`; reaction evidence SHA `42326cb83736902588dc83aa6bff72205e750d2478ccddc5ba55666f6603cb57`; media summary SHA `cc7c7280ce0431714bdcb4feef70c1cc6830b1d9f97bde08d041c9f333086e5a` | No iOS, manual input, or card taps; filtered Sims runs are non-release-eligible by mode, not failed capability | Close docs, refresh Graphify, commit |
| 2026-08-03 post-harness host closure | proof support, projection criteria, curated groups, analyzer/diff | focused 84/84; `groups` 3904/3904 with 0 skip/fail plus all four Go invocations and relay toolchain contract; whole-project analyzer clean in 111.8s; diff check clean | Every source/test delta after the earlier family sweeps is covered on final current source; production source did not change after core/feature closure | No blocker; no full `host-all` by project cadence | Refresh Graphify and commit |
