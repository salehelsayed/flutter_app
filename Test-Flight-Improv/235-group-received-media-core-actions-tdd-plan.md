# 235 - Group Received Media Core Actions

Status: IMPLEMENTED (both slices) — UI slice c88bf7a39; persistence slice complete: DB v98 journal, atomic delete-prepare, cleanup saga, lifecycle wiring, Android+iOS SQLCipher proofs PASSED; production Delete-for-me LIVE
Type: New Feature
Spec: free-text intent — add ordinary received-image/video actions to discussion groups without changing announcement or group-delivery semantics
Classification: prerequisite-blocked
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group conversation screen/wiring, viewer, repositories, migration 069, integrity policy, gates | Discussion groups have verified viewing and message tombstones, but no received-media Save/Share/Delete-for-me/Info actions. | Build on plans 227/228/230. |
| 2026-07-10 | Planner | plan 228 owner APIs, attachment helpers, group delete helpers | Direct and group message IDs can collide, so every media read/mutation must carry `MediaOwnerLane.group`. | Add collision fixtures. |
| 2026-07-10 | Counterexample review / Replanner | migrations 010/069/081/096, incoming group handler, group delete helper, secure-key store, lifecycle/main wiring, plans 232/236/240 | The former cleanup design is unsafe: a group-owned orphan plus a same-ID tombstone is not proof that Plan 235 created it. A dedicated per-attachment journal, atomic DB prepare step, retry-safe cross-store saga, real lifecycle wiring, and a new SQLCipher migration are required. | Do not execute the persistence slice until plan 232 lands DB v97 and plans 236/240 are rebased away from v98. |

## Audit Disposition

- Verdict on the submitted review: **meaningful and execution-blocking**.
- Core feature bet: confirmed; former restart-cleanup bet: refuted.
- Accepted findings: unsafe orphan inference, non-atomic tombstone/parent deletion, missing failure convergence, missing cold-start/resume/main proof, stale gate path/evidence, and missing shared-overlay sentinel.
- Additional source-backed correction: `_saveIncomingMediaAttachments` currently runs after `msgRepo.saveMessage` even when migration-069 rejects the parent by message ID. Incoming media persistence must therefore verify the exact `(group_id,message_id)` parent and absence of a deletion journal inside the final attachment-write transaction.
- Version decision: preserve plan 232 as DB v97; allocate Plan 235's journal as DB v98; move plan 236's group forwarded marker to v99 and update plan 240's references before implementation. This keeps the already-published v97 contract stable but makes Plan 235's persistence slice sequential after plan 232.

## Problem And Evidence

- For an incoming verified image/video in a `GroupType.chat` conversation, the bubble and viewer need Save, Share, Delete for me, Info, and existing Reply where applicable.
- `_onMediaTap` in `lib/features/groups/presentation/screens/group_conversation_wired.dart` opens `FullScreenImageViewer`; the current group bubble overlay exposes reaction, Reply, and Copy, not the new media actions.
- `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia` is the plaintext boundary. Save/Share must reload and requalify current state immediately before calling `ReceivedMediaEgressService.perform`.
- `dbDeleteGroupMessage` in `lib/core/database/helpers/group_messages_db_helpers.dart` currently upserts the migration-069 tombstone and deletes the parent in separate operations. A forced second-operation failure can leave a live parent with a committed tombstone.
- Migration 010's `media_attachments` has `message_id` but no group ID or deletion-operation identity. Migration 096 adds owner/bookmark/playback state only. Therefore `owner_lane='group' + absent parent + same-ID tombstone` cannot identify a Plan-235 cleanup operation.
- Concrete counterexample: `handleIncomingGroupMessage` awaits a void `msgRepo.saveMessage`, then unconditionally saves media. `dbInsertGroupMessage` may silently reject group B's parent because group A has a same-ID migration-069 tombstone, while group B's attachments are still stored with `owner_lane='group'`. The former reconciler would delete those unrelated rows.
- `message_reactions` is keyed by untyped `message_id`; it cannot be safely deleted when a direct message has the same ID. `group_pending_reactions` does carry exact `group_id` and `message_id` and can be safely removed during confirmed local deletion.
- Secure media keys live outside SQLite and are addressed by attachment ID. Cleanup therefore cannot be one cross-resource transaction; it must use a durable journal and an idempotent file -> key -> DB-finalize saga.
- The real resume boundary is `handleAppResumed` and its `main.dart` injection. A directly instantiated reconciler test is not production wiring proof.
- HEAD already has owner-scoped attachment load/delete APIs. The stale claim that those helpers remain untyped is removed; this plan preserves rather than reimplements Plan 228.

## Scope Contract And Guard

In scope:

- Incoming `image` and `video` attachments in `GroupType.chat` only.
- Typed per-attachment identity from bubble long-press and selected viewer item. Two attachments in one parent must target independently; cross-message library navigation remains Plan 237.
- Save and OS Share through `ReceivedMediaEgressService.perform`. The controller reloads the selected attachment, requires exact `owner_lane='group'` plus exact parent/group identity, reruns completion/integrity/expiry/protection/path eligibility, and builds `ReceivedMediaEgressCandidate` only after qualification.
- Existing Reply callback/quote composer, subject to current `canWrite`.
- Privacy-minimized Info: kind, size when known, sender display identity, sent time, transfer/integrity state, and caption; never path, hash, key, nonce, peer/relay diagnostics.
- Whole-message Delete for me through a dedicated DB prepare operation and per-attachment durable cleanup journal.
- A v98 local-only table `group_media_deletion_journal` with at least: `attachment_id TEXT PRIMARY KEY`, `operation_id TEXT NOT NULL`, `message_id TEXT NOT NULL`, `group_id TEXT NOT NULL`, `operation_intent TEXT NOT NULL CHECK(operation_intent='delete_for_me')`, `normalized_mime TEXT NOT NULL`, nullable `canonical_relative_path TEXT`, `created_at TEXT NOT NULL`, and exact `(group_id, message_id, operation_intent, attachment_id)` plus `(operation_id, attachment_id)` indexes. It has no wire mapping, foreign key, cascade, or inferred backfill. Upgrade starts empty because legacy orphans cannot be classified safely.
- One SQLite transaction for confirmed deletion preparation: verify a live exact `(message_id, group_id)` parent; fail closed on a conflicting same-ID tombstone; snapshot only exact group-owned attachments into journal rows; upsert the exact local tombstone; delete exact `(group_id,message_id)` pending reactions and pending/failed group reaction replay-outbox rows; and delete the parent with both identifiers. Any SQL failure rolls all of those changes back and no file/key I/O starts.
- During that transaction, normalize MIME and snapshot the exact Plan-229 canonical relative path from the same attachment-row version. A noncanonical path is stored as null and never authorizes file deletion. The journal remains safe cleanup authority if a crash-era bypass removes the attachment row while its canonical file/key remains.
- One UUID `operation_id` is generated after confirmation and shared by all attachments in that message delete. Double taps coalesce behind a `(group_id,message_id)` single-flight guard; a call after commit sees the absent/tombstoned parent and is an idempotent no-op. A zero-attachment delete still has one tombstone/parent transaction and no fabricated journal row.
- Post-commit cleanup validates exact intent/tombstone/absent parent and, when present, the attachment tuple `(attachment_id,message_id,owner_lane='group')`; deletes/already-absent only the journal's validated canonical relative path; deletes/already-absent attachment key; then atomically deletes that attachment row if present and the journal row. A mismatch quarantines the operation. A missing attachment row uses the journal MIME/path/key identity rather than guessing or declaring unsafe success.
- Bounded, paged, per-item-isolated reconciliation on cold start and resume. Resume cleanup executes before the account-migration/network early return because it is local-only.
- Incoming group media persistence uses a transaction that verifies the exact `(group_id,message_id)` parent and absence of an active journal at the final attachment-row write, not a pre-write reload. It shares one attachment-scoped lifecycle lock with secure-key mutation, delete cleanup, and download commit. If save commits first, delete snapshots it; if delete commits first, save performs no DB/key side effect. An active journal reserves its attachment ID against re-save/re-parent.
- Download begin/commit and cleanup use the same lifecycle lock and database CAS. Download commit anti-joins active journals before promoting/marking `done`; if deletion won, it removes only its own staged/promoted canonical artifact and cannot restore `local_path`. Cleanup revalidates journal, attachment state, and canonical target inside the lock before final DB deletion.
- Incoming group reactions for an exact locally tombstoned `(group_id,message_id)` are discarded rather than buffered into `group_pending_reactions` or a retry outbox.

Must preserve:

- Discussion Reply and Copy; direct shared-overlay Reply/Edit/Copy/Delete behavior.
- IR-020 tombstone replay protection and unread non-resurrection.
- Plan 228 owner isolation, replay-safe local path/bookmark/playback state, and `unresolved` exclusion.
- Announcement reader/admin behavior and QA exclusion.
- Ordinary `message_reactions` rows are retained and hidden after parent deletion; garbage collection is deferred until reaction rows gain owner/group identity. Exact group pending reactions and exact `pending`/`failed` group reaction replay-outbox rows are deleted transactionally. `stored` outbox rows remain as inert completed-delivery evidence and are never retried; tests lock that disposition.
- The existing fail-closed no-downgrade release floor. A v98 profile must not be reopened by an older supported schema.

Hard `Do not`:

- Do not infer a deletion operation from an orphan, owner lane, or tombstone; only an explicit journal row authorizes cleanup.
- Do not hold a SQLite transaction across file or secure-storage I/O.
- Do not delete by untyped `message_id`, raw absolute path, or attachment ID alone.
- Do not delete direct/unresolved collision rows, ordinary untyped reactions, exported copies, or media from a wrong-group same-ID event.
- Do not add Delete for everyone, Report, moderation/revocation, announcement/QA actions, or any Go/libp2p/wire change.
- Do not call a native egress gateway, sender, share picker, or batch-delivery seam directly from the group UI.

Deferred / accepted difference:

- Forward is Plan 236; library navigation/batch actions Plan 237; protected-media lifecycle restrictions Plan 238; Report Plan 245.
- Delete for me remains whole-message because current group persistence/tombstones are message-scoped.
- Existing untyped ordinary reaction rows may remain as hidden orphans; safe ownership migration is separate work.

Dependencies and sequencing:

- Plan 227: `ReceivedMediaEgressService`, typed results, native device closure.
- Plan 228: DB v96 owner-aware attachments and production migration registries.
- Plan 229: canonical scope + attachment + MIME file-ownership validation used by destructive cleanup.
- Plan 230: typed viewer item/action slots.
- Plan 232: must land DB v97 before Plan 235 appends migration 098.
- Plan 231: shared attachment-index long-press propagation may be reused if already landed; otherwise Plan 235 must coordinate ownership of the shared widget files and cannot implement them concurrently.
- Plan 236 must be rebased from v98 to v99, and Plan 240's v98 references must follow, before Plan 235 is execution-ready.

Parallelism boundary:

- Plan 235 UI policy, Info, viewer/bubble plumbing, and egress adapter tests may be developed in parallel with Plan 232 if they do not edit shared migration or shared overlay files concurrently.
- Plan 235 journal migration, repository/delete preparation, cleanup reconciler, lifecycle wiring, and acceptance cannot begin until Plan 232's v97 is landed.
- Plan 236's migration/persistence work follows completed Plan 235 v98 as v99. Plan 240 follows Plan 236.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | Causal RED / mutation | Gate |
|---|---|---|---|---|---|
| TC-235-01 | Exact incoming discussion-media capabilities vary independently by verified state and `canWrite`; outgoing/non-media/announcement/QA rows get none. | `test/features/groups/application/group_received_media_action_policy_test.dart::GMA-01 discussion incoming media capabilities vary safely by action and state` | host unit / table | Policy absent on HEAD; removing type/lane/state guards re-reds. | add to `GROUP_TESTS` |
| TC-235-02 | Bubble long-press carries the exact attachment index/ID; two attachments in one message invoke the selected Save/Share/Info/Delete/Reply callback once while existing reaction/copy remain. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-02 attachment long press targets one item and preserves reply copy reactions` | host widget | Whole-message-only long press is RED; hard-code index 0 re-reds. | existing entry |
| TC-235-03 | Viewer actions track the selected typed item; reopening with a different parent preserves that attachment identity without adding conversation-wide swipe navigation. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-03 viewer selection and reopen preserve exact attachment identity` | host widget / two items same parent plus separate reopen | Path-only viewer is RED; stale first-page identity re-reds. | existing entry |
| TC-235-04 | Save/Share reload the exact group-owned attachment and parent immediately before `ReceivedMediaEgressService.perform`; pending, missing, mutated/integrity-failed, expired, protected, unresolved, direct-collision, or wrong-group state makes zero egress calls. | `test/features/groups/application/group_received_media_actions_test.dart::GMA-04 egress reloads exact group owner and delegates only currently eligible media` | host unit / temp files + recording service | Controller absent on HEAD; stale viewer metadata or direct gateway call re-reds. | add to `GROUP_TESTS` |
| TC-235-05 | Bubble/viewer Reply reuse the existing quote composer and obey `canWrite`. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-05 media reply reuses existing group quote flow` | host widget | Viewer route absent; alternate sender re-reds. | existing entry |
| TC-235-06 | Migration 098 appends once to both production registries after a complete v97, creates the exact constrained journal/index with empty legacy backfill, supports fresh create/upgrade/rerun, and rejects invalid insert/update intent. | `test/core/database/migrations/098_group_media_deletion_journal_test.dart::GMA-06 v98 journal extends complete v97 production registries safely` plus full-chain test | host migration / production callbacks, fresh and v97 fixtures | Migration absent; removing CHECK/index/one registry arm or inventing orphan backfill re-reds. | `core-host-all`; register in group host inventory |
| TC-235-06D | Real SQLCipher fresh and v97->v98 production paths preserve predecessor data, constraints, journal rows, rerun/reopen behavior, non-empty cipher version, wrong-password rejection, and `user_version=98`; v98->v97 downgrade open fails without changing schema/version/data. | `integration_test/group_media_deletion_journal_sqlcipher_proof_test.dart::GMA-06D real SQLCipher v98 journal upgrade reopen and downgrade refusal` | discovered Android+iOS real-plugin targets / password DB | Host SQLite cannot close this boundary; plaintext/open-downgrade mutation re-reds. | exact device discovery registration |
| TC-235-07 | Confirmed delete preparation is one DB transaction: self-contained journals+tombstone+exact pending-reaction and pending/failed reaction-outbox removal+exact parent delete all commit, or forced failures roll all back before file/key calls. Direct same-ID state, ordinary reactions, and exact `stored` outbox rows survive; later reactions for the tombstoned exact group parent are discarded. | `test/features/groups/application/delete_group_media_for_me_use_case_test.dart::GMA-07 delete prepare is exact group scoped atomic and reaction safe` plus `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart::GMA-07R locally deleted exact group parent cannot refill reaction buffers` | host integration / production DB helpers | Split transaction, omit a retryable queue, delete stored/ordinary evidence, or allow rebuffering re-reds. | add delete test and ensure incoming reaction test is in `GROUP_TESTS` |
| TC-235-08 | Cleanup orders file -> key -> atomic attachment+journal finalize and converges after restart from injected file, key, attachment-row, and journal-row failures. A row-disappears-before-restart fixture safely uses journal MIME/path. One bad item does not block siblings; cancel is zero-op; double-confirm creates one operation ID/transaction. | `test/features/groups/integration/group_received_media_delete_replay_test.dart::GMA-08 self contained journal saga converges per item across every restart boundary` | host integration / canonical media tree + secure-key fake + DB | Remove MIME/path snapshot, reorder a stage, or stop at first error re-reds. | add to `GROUP_TESTS` |
| TC-235-09 | A group-B same-ID parent rejected by group-A tombstone causes zero media saves; wrong-group orphans without journals survive. Forced save-vs-delete and download-vs-cleanup interleavings prove one winner: no unjournaled row/key, restored path, or orphan promoted file. | `test/features/groups/application/handle_incoming_group_message_use_case_test.dart::GMA-09 transactional parent and journal guard closes save delete race` plus `group_received_media_delete_replay_test.dart::GMA-09D journal aware download commit cannot outlive cleanup` | host integration / controllable barriers, lifecycle lock, collisions, staged download | Pre-write reload and journal-blind download commit are RED; remove final guard, lock, anti-join, or loser cleanup re-reds. | register incoming and integration files |
| TC-235-10 | Production cold start invokes bounded reconciliation after DB/repository construction; `handleAppResumed` invokes it before network-gate return; errors are isolated and main wiring injects the real coordinator. | `test/core/lifecycle/group_media_deletion_reconciler_wiring_test.dart::GMA-10 cold start and resume invoke local cleanup with error isolation` and `test/core/lifecycle/handle_app_resumed_group_media_cleanup_test.dart::GMA-10R resume cleanup runs when network recovery is denied` | host lifecycle/wiring | Direct reconciler construction alone cannot pass; remove either callsite or catch re-reds. | add both to `GROUP_TESTS` and `core-host-all` |
| TC-235-11 | Bubble/viewer Save, Share, and Delete reach injected action/delete coordinators; throwing delivery/share-batch seams remain untouched. Cancel yields zero delete operation; one confirm yields exactly one. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-11 wired media actions reach only injected coordinators` | host wired widget / recording + throwing seams | Controller may exist but remain unused on HEAD; UI bypass re-reds. | existing entry |
| TC-235-12 | Info renders only approved fields; paths, hashes, keys, nonces, peer/relay IDs never render or log. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-12 media info redacts storage crypto and transport secrets` | host widget / sentinel secrets | Info absent on HEAD; raw map/model binding re-reds. | existing entry |
| TC-235-13 | Announcements/QA get no new actions; group shared-widget changes leave direct Reply/Edit/Copy/Delete sentinels green. | `group_conversation_wired_test.dart::GMA-13 announcement and qa exclude discussion media actions` plus exact direct sentinels below | GREEN sentinel + host widget | Remove `GroupType.chat` guard or break shared overlay re-reds. | group + `1to1` gates |
| TC-235-14 | IR-020 replay cannot restore message/unread state; exact journal remains the only cleanup authority. | `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::IR-020 tombstone prevents replay save and unread resurrection` | GREEN sentinel | Bypass tombstone or infer orphan cleanup re-reds. | existing entry |

### Failure Semantics

- File delete failure: key, attachment, and journal remain; retry later.
- Key delete failure after file absence: attachment and journal remain; retry treats missing file as complete.
- Final DB failure: attachment and journal delete in one transaction, so both remain; retry treats missing file/key as complete.
- Journal row with a missing attachment: use only its snapshotted normalized MIME and validated canonical relative path for file cleanup plus attachment ID for key cleanup; a null/noncanonical snapshot authorizes no file deletion.
- Parent present, tombstone absent/mismatched, attachment tuple mismatched, non-group owner, non-canonical path, or unknown intent: quarantine/log privacy-safe identifiers and perform no destructive work.
- Reconciler uses a literal bounded page size (100), stable `(created_at, attachment_id)` cursor, and per-item error isolation.

## Implementation Steps

1. Stop if plans 227/228/229/230 are not landed. Coordinate shared attachment-long-press files with Plan 231.
2. Resolve migration order: land Plan 232 v97, rebase Plan 236 to v99 and Plan 240 references, then reserve v98 exclusively for Plan 235. Until then this plan remains prerequisite-blocked.
3. Snapshot status and full-analyzer baseline. Add TC-235-01 and run its causal RED after the named test exists.
4. Add the pure policy, exact attachment identity propagation, viewer/bubble wiring, current-row egress adapter using `ReceivedMediaEgressService.perform`, Reply reuse, and redacted Info.
5. Add migration 098 and exact journal model/helper APIs to both production registries; bump the database version to 98. Add full-chain, constraint-mutation, encrypted fresh/upgrade/reopen, and downgrade-refusal proofs.
6. Add a dedicated transaction helper/repository operation for delete preparation. Do not use the current non-atomic `dbDeleteGroupMessage` sequence as Plan-235 proof. Retain ordinary and stored-outbox evidence; transactionally delete exact pending reactions plus pending/failed outbox rows and reject later buffering.
7. Add the final-write exact-parent/journal transaction and shared attachment lifecycle lock around DB/key save. Add group-A/group-B collisions and a forced save-vs-delete interleaving first.
8. Add self-contained journal cleanup with Plan-229 canonical validation, journal-aware download CAS, and file -> key -> atomic DB-finalize ordering. Inject every failure, missing row, late download promotion, and fresh-process restart.
9. Wire bounded cleanup into real cold start and `handleAppResumed` before its network gate; isolate each invocation's error. Add source/main wiring assertions and behavioral tests.
10. Register every new host test literally in `GROUP_TESTS`, register the SQLCipher proof in exact device discovery, run mutations, focused/preservation/family/device gates, scoped and baseline-qualified full analyzer, and hygiene.

## Gate Cadence

- Per-plan closure: run the focused Plan-235 tests, the curated `groups` lane gate, exact shared 1:1 overlay sentinels, and `core-host-all` because this plan changes the production migration registry and lifecycle wiring.
- Do not run `feature-host-all`, the full curated `1to1` family, or full `host-all` for Plan 235; the exact direct sentinels below cover the shared overlay risk without a redundant lane sweep.
- Full `host-all` runs once after the ordered migration/forwarding wave (`232 → 235 → 236 → 240`) and once at final rollout closure.

## Acceptance Gates

```bash
# Prerequisite/version stop rules
test -f Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md
test -f Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md
test -f Test-Flight-Improv/229-cross-track-media-download-storage-controls-tdd-plan.md
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
test "$(rg -o 'currentIdentityDatabaseVersion[[:space:]]*=[[:space:]]*[0-9]+' lib/core/database/app_database_version.dart | rg -o '[0-9]+$')" -eq 97
test "$(rg -F -c "ProductionMigrationEntry(97, '097_direct_message_forwarded'" lib/core/database/production_migration_registry.dart)" -eq 2
rg -q '099_group_messages_is_forwarded|Migration 099.*is_forwarded|migration 099.*is_forwarded' Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
rg -q 'exclusively owns v99|exclusively owns DB v99' Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
! rg -q '098_group_messages_is_forwarded|exclusively owns v98|Migration 098.*is_forwarded|migration 098.*is_forwarded' Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
rg -qi 'plan 236.*DB v99|DB v99.*group_messages\.is_forwarded' Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md
! rg -qi 'plan 236.*DB v98|DB v98.*group_messages\.is_forwarded' Test-Flight-Improv/240-announcement-received-media-forwarding-tdd-plan.md

# Snapshot before execution
git status --short
dart analyze . > /tmp/plan235-analyze-before.txt 2>&1 || true
rg '^[[:space:]]+(error|warning|info) - ' /tmp/plan235-analyze-before.txt | sed -E 's/:[0-9]+:[0-9]+ - / - /' | sort -u > /tmp/plan235-diagnostics-before.txt || true

# First causal RED, run after creating the test; expect non-zero for missing policy
flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'

# Focused host GREEN
flutter test test/features/groups/application/group_received_media_action_policy_test.dart
flutter test test/features/groups/application/group_received_media_actions_test.dart
flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart --plain-name 'GMA-09D journal aware download commit cannot outlive cleanup'
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GMA-09 transactional parent and journal guard closes save delete race'
flutter test test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart --plain-name 'GMA-07R locally deleted exact group parent cannot refill reaction buffers'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/core/lifecycle/group_media_deletion_reconciler_wiring_test.dart test/core/lifecycle/handle_app_resumed_group_media_cleanup_test.dart

# Migration/full-chain host proof
flutter test test/core/database/migrations/098_group_media_deletion_journal_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Preservation: owner isolation, replay, announcement, shared direct overlay
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart --plain-name 'owner scoped load and delete isolate equal direct and group message ids'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'ordinary replay preserves local viewer state and path while explicit clears win'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'long-press reply on an outgoing message requests focus and sends quotedMessageId'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'edit action prefills the composer and cancel exits edit mode'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'copy action leaves repo, bridge, and p2p collaborators untouched'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'incoming rows only offer delete-for-me and cancel'
flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart --plain-name 'renders reply, edit, copy, then delete in stable keyed order when all actions are enabled'

# Literal GROUP_TESTS registration: each new host file must occur exactly once
for f in \
  test/features/groups/application/group_received_media_action_policy_test.dart \
  test/features/groups/application/group_received_media_actions_test.dart \
  test/features/groups/application/delete_group_media_for_me_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart \
  test/features/groups/integration/group_received_media_delete_replay_test.dart \
  test/core/database/migrations/098_group_media_deletion_journal_test.dart \
  test/core/lifecycle/group_media_deletion_reconciler_wiring_test.dart \
  test/core/lifecycle/handle_app_resumed_group_media_cleanup_test.dart; do
  test "$(rg -F -c "\"$f\"" scripts/run_test_gates.sh)" -eq 1
done
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all

# Real-plugin Android+iOS SQLCipher closure. Use an available supported target
# for each platform (physical, emulator, or simulator); record N/A only when
# `flutter devices --machine` proves that platform family unavailable.
flutter devices --machine > /tmp/plan235-devices.json
: > /tmp/plan235-adb-devices.txt
: > /tmp/plan235-ios-simulators.txt
: > /tmp/plan235-ios-devices.txt
: > /tmp/plan235-ios-xctrace.txt
if command -v adb >/dev/null; then adb devices -l > /tmp/plan235-adb-devices.txt; fi
if command -v xcrun >/dev/null; then xcrun simctl list devices available > /tmp/plan235-ios-simulators.txt; xcrun devicectl list devices > /tmp/plan235-ios-devices.txt 2>&1 || true; xcrun xctrace list devices > /tmp/plan235-ios-xctrace.txt 2>&1 || true; fi
ANDROID_DEVICE_ID="$(jq -r '[.[] | select(.isSupported == true and (.targetPlatform | startswith("android")))][0].id // empty' /tmp/plan235-devices.json)"
IOS_DEVICE_ID="$(jq -r '[.[] | select(.isSupported == true and (.targetPlatform | startswith("ios")))][0].id // empty' /tmp/plan235-devices.json)"
if test -n "$ANDROID_DEVICE_ID"; then rg -F "$ANDROID_DEVICE_ID" /tmp/plan235-adb-devices.txt; flutter test integration_test/group_media_deletion_journal_sqlcipher_proof_test.dart -d "$ANDROID_DEVICE_ID" --plain-name 'GMA-06D real SQLCipher v98 journal upgrade reopen and downgrade refusal'; else jq -e '[.[] | select(.isSupported == true and (.targetPlatform | startswith("android")))] | length == 0' /tmp/plan235-devices.json; fi
if test -n "$IOS_DEVICE_ID"; then (rg -F "$IOS_DEVICE_ID" /tmp/plan235-ios-simulators.txt || rg -F "$IOS_DEVICE_ID" /tmp/plan235-ios-devices.txt || rg -F "$IOS_DEVICE_ID" /tmp/plan235-ios-xctrace.txt); flutter test integration_test/group_media_deletion_journal_sqlcipher_proof_test.dart -d "$IOS_DEVICE_ID" --plain-name 'GMA-06D real SQLCipher v98 journal upgrade reopen and downgrade refusal'; else jq -e '[.[] | select(.isSupported == true and (.targetPlatform | startswith("ios")))] | length == 0' /tmp/plan235-devices.json; fi

# Scoped + baseline-qualified analyzer and hygiene
for target in lib/core/database lib/core/lifecycle lib/core/media lib/features/groups lib/features/conversation/domain/repositories test/core test/features/groups; do dart analyze "$target"; done
dart analyze . > /tmp/plan235-analyze-after.txt 2>&1 || true
rg '^[[:space:]]+(error|warning|info) - ' /tmp/plan235-analyze-after.txt | sed -E 's/:[0-9]+:[0-9]+ - / - /' | sort -u > /tmp/plan235-diagnostics-after.txt || true
comm -13 /tmp/plan235-diagnostics-before.txt /tmp/plan235-diagnostics-after.txt > /tmp/plan235-new-diagnostics.txt
test ! -s /tmp/plan235-new-diagnostics.txt
git diff --check
```

## Device / SQLCipher Proof Profile

- Boundary: real encrypted production create/upgrade registries, journal durability/constraints, reopen/rerun, wrong-password failure, and no-downgrade floor.
- Required targets: one available supported Android target and one available supported iOS target. Physical devices are preferred, but a simulator/emulator that loads the production `sqflite_sqlcipher` plugin closes this schema boundary; a missing platform is recorded N/A only from discovery output.
- Precondition: start with production DB v97 containing representative direct/group/unresolved attachments and state, then upgrade through the actual v98 callback. Separately exercise fresh v98 creation.
- Semantic assertions: non-empty `PRAGMA cipher_version`; exact table/index/check behavior via valid and invalid writes; journal survives close/reopen; wrong password fails; attempted v98->v97 open fails and leaves `user_version`, schema, and rows unchanged.
- Host SQLite proves SQL shape and transaction causality only; it does not substitute for SQLCipher closure.

## Execution Interpretation And Done Criteria

- Expected first RED is causal only after the named policy test is created; an exit 79 for a nonexistent file is not evidence.
- Plan is not execution-ready while DB v98 conflicts with Plan 236 or while Plan 232 v97 is absent.
- UI-only parallel work does not make the plan complete; all persistence, lifecycle, and device rows are required for acceptance.
- Analyzer closure is scoped plus baseline-qualified. Any new issue in an owned file fails even when full-repo baseline is non-zero.
- No Go/libp2p/wire behavior changes are permitted.

- [x] Plan 232 v97 landed; Plan 235 exclusively owns v98; Plan 236/240 version references are rebased.
- [x] Every behavior has a named causal test or justified boundary proof.
- [x] Self-contained journal is the only cleanup authority; wrong-group orphans survive and missing-row cleanup stays canonical/path-safe.
- [x] Delete preparation is atomic and no external I/O occurs before commit.
- [x] File/key/DB failures converge after fresh-process restart with per-item isolation.
- [x] Incoming media final-write requires exact parent/no journal; save/delete and download/cleanup races leave no orphan row, key, path, or file.
- [x] Cold-start, resume-before-network-gate, error-isolation, and production main wiring are proven.
- [x] Bubble/viewer actions reach only injected coordinators; cancel is zero-op and confirm creates exactly one durable operation.
- [x] Pending reactions and pending/failed outbox rows are exact-group deleted; stored outbox/ordinary reactions survive; later reactions are not re-buffered.
- [x] Announcement/QA and direct Reply/Edit/Copy/Delete sentinels pass.
- [x] Every available Android/iOS real-plugin SQLCipher proof, family gate, normalized analyzer contract, and `git diff --check` passes; unavailable families are evidenced N/A. (Android emulator-5554 + iOS iPhone-17-Pro sim GMA-06D PASSED; groups lane 1309 green; core-host-all 298 suites green; zero new analyzer diagnostics in plan-owned files.)

## Handoff

- First RED: `flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'` after adding the test.
- Migration: DB v98 `group_media_deletion_journal`, appended once to plan 228's shared production create/upgrade registries after complete v97; empty upgrade backfill; no supported downgrade.
- Primary persistence discriminator: explicit self-contained journal identity `(attachment_id, operation_id, message_id, group_id, operation_intent, normalized_mime, canonical_relative_path)`, never orphan inference.
- Boundary closure: host causal transaction/saga/race/wiring proof plus availability-bounded Android+iOS real-plugin SQLCipher proof.
- Downstream action required before execution: rebase Plan 236 to DB v99 and Plan 240's dependencies/references accordingly.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 | replanned, not started | plan only | source counterexample audit | Former orphan-journal design refuted; replacement contract defined | Plan 232 v97 and Plan 236/240 version rebase required | resolve migration sequence, then first causal RED |
| 2026-07-10 | 236/240 version rebase DONE | Test-Flight-Improv/236-*, 240-* | all five plan-235 rg gates pass | 236 owns v99 (`099_group_messages_is_forwarded`, complete-v98 predecessor incl. journal); 240 references follow | none | UI-parallel slice |
| 2026-07-10 | CLOSED at plan tier | all | groups lane 1309 GREEN (one load-induced voice-test timeout during a parallel device build; green in isolation and on idle rerun); core-host-all 298 suites GREEN; analyzer diff: 1 new info owned by the in-flight plan-233 session's untracked file, zero in plan-235 files; git diff --check clean; graph refreshed | Android emulator + iOS simulator GMA-06D PASSED | none | commit |
| 2026-07-10 | persistence slice IMPLEMENTED | migration `098_group_media_deletion_journal` (+ both registries, v98 bump); `group_media_deletion_journal_db_helpers` (atomic `dbPrepareGroupMediaDeleteForMe`, paged cursor load, atomic finalize); `DeleteGroupMediaForMeUseCase` (single-flight, one UUID op); `GroupMediaDeletionJournalReconciler` (file→key→DB saga, page 100, per-item isolation, quarantine); guarded final write `dbSaveGroupMediaAttachmentGuarded` + `GroupGuardedMediaAttachmentSave` capability (+ key-write compensation under the new `MediaAttachmentLifecycleLock`); journal anti-join in group `dbCommitMediaDownloadLocalPath`; tombstone reaction discard (`getLocalDeletionGroupId` + `discardedLocallyDeleted`); `handleAppResumed` pre-gate cleanup hook; main.dart cold-start unawaited pass + `defaultGroupMediaDeleteForMeCoordinator` (229 decider pattern) + notification-route/orbit injection — production Delete-for-me is LIVE | GMA-06 GREEN (+ registry-arm/CHECK mutations re-red); full chain 13/13; GMA-07 GREEN incl. forced-rollback + single-flight; GMA-07R GREEN; GMA-08 GREEN (restart convergence, missing-row journal identity, quarantine, orphan survival); GMA-09 GREEN (+ guard-bypass mutation re-red); GMA-09D GREEN (+ journal-blind-commit mutation re-red; direct lane byte-identical); GMA-10/10R GREEN (cleanup BEFORE denied gate, error isolation, main source anchors); Android emulator GMA-06D PASSED (cipher_version, CHECK, rerun, reopen, wrong password, downgrade refusal) | none | iOS proof + groups/core-host lanes + analyzer + commit |
| 2026-07-10 | UI slice IMPLEMENTED (host-green) | policy + egress adapter + delete seam + info sheet (new: `group_received_media_action_policy.dart`, `group_received_media_actions.dart`, `group_media_delete_for_me_coordinator.dart`, `group_media_info_sheet.dart`); group screen/wired; shared overlay/grid/letter-card/viewer + l10n (co-landed in d32abbaaf by the concurrent plan-231 session) | causal RED then GREEN: GMA-01 (policy absent → compile RED); focused GREEN GMA-01/02/02b/03/04/05/11/12/13; 7 mutations re-red (policy type/lane/state guards, hard-coded index 0, stale first-page identity, skipped requalification, wrong-lane reload); full `group_conversation_wired_test.dart` + `group_conversation_screen_test.dart` + 230 viewer/boundary + letter-card + overlay suites GREEN; direct Reply/Edit/Copy/Delete + IR-020 + owner-isolation + replay + announcement sentinels GREEN | TC-235-01/02/03/04/05/11/12/13 closed at host tier. TC-235-06/06D/07/08/09/10 (v98 journal migration, atomic delete prepare, cleanup saga, races, lifecycle wiring, SQLCipher device proof) REMAIN OPEN: DB still v96, plan 232 v97 in flight in a concurrent session | land after plan 232 v97: reserve v98, migration 098 + journal saga + lifecycle wiring, then acceptance |
