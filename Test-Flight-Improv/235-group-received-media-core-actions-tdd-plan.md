# 235 - Group Received Media Core Actions

Status: execution-ready
Type: New Feature
Spec: free-text intent — add ordinary received-image/video actions to discussion groups without changing announcement or group-delivery semantics
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group conversation screen/wiring, shared viewer, group message/media repositories, group local-deletion migration/helpers/tests, integrity policy, group notification and gate scripts | Discussion groups already support verified media viewing and durable whole-message local tombstones, but expose no received-media Save/Share/Delete-for-me/Info actions. Reply exists and must be reused. Reporting is isolated in plan 245 so it cannot block ordinary actions. | Start the pure capability-policy RED, then execute against the accepted plan-227/230 contracts. |

## Problem And Evidence

- Behavior to improve: for an incoming verified image or video in a `GroupType.chat` conversation, both the bubble context surface and the viewer need Save, Share, Delete for me, Info, and Reply where that action is meaningful.
- Impact: users can open group media but cannot retain it, hand it to the OS, remove it locally, or inspect its safe metadata.
- Confirmed current viewer gap: `_onMediaTap` in `lib/features/groups/presentation/screens/group_conversation_wired.dart:4486` opens `FullScreenImageViewer` with only local paths from the tapped message; `lib/shared/widgets/media/full_screen_image_viewer.dart:19` accepts paths and a video builder, and its app bar exposes only Back/counter actions.
- Confirmed current bubble gap: `lib/features/groups/presentation/screens/group_conversation_screen.dart:927` builds a `MessageContextOverlay` with reaction, Reply, and Copy. There is no received-media Save, Share, Delete-for-me, or Info action.
- Confirmed existing Reply behavior: the overlay supplies Reply only when `canWrite` is true. This plan must route media Reply through that existing callback/quote composer rather than add a second reply protocol.
- Confirmed integrity boundary: `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia` requires completed media with a local path, content hash, and encryption metadata. `group_conversation_wired.dart:4486` already checks that boundary before viewing; every new plaintext-consuming action must preserve it.
- Confirmed local-delete mechanism: `GroupMessageRepository.deleteMessage` delegates to `dbDeleteGroupMessage`; `lib/core/database/helpers/group_messages_db_helpers.dart:739` writes a `group_message_local_deletions` tombstone before deleting the row. Migration 069 owns that table, and `dbInsertGroupMessage` rejects replay of a tombstoned id.
- Confirmed cleanup gap: group failed/terminal media paths explicitly delete attachment rows/files, but ordinary received-message deletion has no dedicated action orchestration. Media attachments have no foreign key that safely performs that cleanup automatically.
- Existing causal preservation evidence: `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` contains `IR-020 tombstone prevents replay save and unread resurrection`; drain/resume suites exercise the same replay invariant.
- Missing coverage: no test can fail for received-media action capability, egress delegation, safe Info metadata, delete confirmation and cleanup, or announcement-lane isolation.
- Refuted finding: an older audit description that group long-press offers reactions only is stale. Current source and `test/features/groups/presentation/group_conversation_screen_test.dart` prove Reply and Copy already exist; this plan extends that overlay without replacing it.
- Unresolved finding: N/A for this bounded lane. Group media reporting has a genuine product/safety evidence gap and is deliberately owned by evidence-gated plan 245 rather than hidden inside ordinary actions.
- Affected production, test, and gate files: group conversation presentation/wiring, a group-media action policy and delete-for-me application seam, typed shared viewer integration from plan 230, group presentation/application/repository tests, and the `GROUP_TESTS` registration in `scripts/run_test_gates.sh`.

## Scope Contract And Guard

In scope:
- Incoming `image` and `video` attachments in `GroupType.chat` only.
- Expose typed per-action capabilities in the bubble context overlay and shared viewer: Save/OS Share require a currently completed verified local copy; Delete for me and privacy-minimized Info remain available for a recognized incoming visual-media message even when its local copy is pending/failed/missing; Reply follows existing `canWrite`. The viewer exists only for displayable verified media.
- Delegate Save/Share to plan 227's `ReceivedMediaEgressService`; do not reimplement native export in the group feature.
- Delegate viewer rendering/action slots to plan 230's typed `MediaViewerItem` contract.
- Reuse the existing Reply callback and quote composer.
- Implement whole-message Delete for me as a confirmed, idempotent, durable-first operation: snapshot target attachment identities; atomically persist the existing local tombstone/delete the message row; keep each now-orphaned attachment row as the durable cleanup journal until its app-owned file is deleted or already absent; then delete that attachment row through the repository so its attachment-scoped secure key/local state is removed. A startup/resume deletion reconciler scans only attachment rows whose group parent is absent and whose message id has a migration-069 local tombstone, so interrupted cleanup resumes without a new schema or timeline resurrection.
- Show privacy-minimized Info metadata already available locally: media kind, byte size when known, sender display identity, sent time, transfer/integrity state, and caption. Do not expose local paths, hashes, encryption keys/nonces, peer-id diagnostics, or relay identifiers.

Must preserve:
- Existing discussion Reply and Copy behavior -> `test/features/groups/presentation/group_conversation_screen_test.dart`; `GREEN sentinel`.
- Tombstoned message replay cannot restore message/unread state -> `group_message_repository_impl_test.dart::IR-020 tombstone prevents replay save and unread resurrection`; causal preservation row.
- Unverified, failed, quarantined, pending, or missing media cannot be viewed or exported -> `GroupMediaIntegrityPolicy` tests plus new action-policy rows.
- Announcement readers keep current reaction/copy-only behavior and announcement writers keep existing admin-only authoring -> `group_conversation_wired_test.dart` announcement sentinels and `send_group_message_use_case_test.dart::returns unauthorized for non-admin in announcement group`.

Hard `Do not`:
- Do not edit Go bridge/node code, group wire fields, pubsub topics, recipient fanout, inbox/retry, encryption, authorization, or libp2p behavior.
- Do not add Delete for everyone, moderation deletion, remote revocation, or any group-control message.
- Do not show these actions in `GroupType.announcement` or `GroupType.qa`; this plan is discussion-only.
- Do not delete a saved/shared external copy, an arbitrary absolute path, another attachment/message, or a pending upload owned by a different operation.
- Do not bypass `GroupMediaIntegrityPolicy` or expose decrypted paths/secrets in UI or logs.
- Do not add a Report action/sink in this plan; plan 245 owns its authority, evidence, retention, offline, and receipt semantics.

Deferred / accepted difference:
- Forward is owned by plan 236; cross-message navigation and batch actions by plan 237; lifecycle/protected restrictions by plan 238.
- Save/Share native OS behavior and cancellation/permission semantics are closed by plan 227. This plan proves group eligibility and delegation only.
- Delete for me removes the whole message, including caption and all attachments, because the existing persistence identity/tombstone is message-scoped. Per-attachment deletion is out of scope.
- Copies already exported outside Mknoon cannot be revoked.
- Report is fully deferred to plan 245 and is not part of this plan's action capability set, tests, gates, or completion claim.

Dependencies:
- Plan 227: `ReceivedMediaEgressService`, typed result/cancellation, and native device proof.
- Plan 230: typed shared media viewer actions/capabilities and legacy-path compatibility.
- Existing migration 069 and `GroupMessageRepository.deleteMessage`; no new database migration is required here.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-235-01 | An incoming image/video in `GroupType.chat` receives exact per-action capabilities: Save/Share only for current verified local media, Delete/Info for the recognized incoming media message, and Reply only when `canWrite`; outgoing/non-media/wrong-group rows get no new lane actions. | `test/features/groups/application/group_received_media_action_policy_test.dart::GMA-01 discussion incoming media capabilities vary safely by action and state` | host unit / table-driven messages, write permission, and attachment states | HEAD compile RED: policy absent -> typed capabilities are exact for completed, pending, failed, missing, mutated, and read-only rows | apply one shared integrity bool to every action or remove incoming/type/group/write guard -> GMA-01 red | `flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'`; add file to `GROUP_TESTS` |
| TC-235-02 | Bubble long-press shows Save, Share, Delete for me, Info, and Reply without removing reaction/copy behavior. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-02 incoming media context exposes core actions and keeps reply copy` | host widget / discussion message fixture | HEAD RED: only reaction/reply/copy are rendered -> all eligible actions invoke their typed callback once | omit an action or replace existing Reply/Copy callbacks -> GMA-02 red | `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GMA-02 incoming media context exposes core actions and keeps reply copy'`; existing `GROUP_TESTS` entry |
| TC-235-03 | The shared viewer presents the same eligible actions for its selected `MediaViewerItem` and updates them when the selected page changes. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-03 viewer actions follow selected verified group media item` | host widget / fake media policy, typed viewer harness from 230 | HEAD RED: viewer receives paths only -> selected item id and exact callbacks/capabilities reach viewer | keep capabilities from the first page after swipe -> GMA-03 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-03 viewer actions follow selected verified group media item'`; existing `GROUP_TESTS` entry |
| TC-235-04 | Save and Share resolve the selected attachment and delegate one eligible request to plan 227; cancel/failure leaves message and original unchanged. | `test/features/groups/application/group_received_media_actions_test.dart::GMA-04 save and share delegate eligible media without mutating source` | host unit / real temp app-owned file + fake egress service | HEAD compile RED: group action seam absent -> destination/result is forwarded once and source bytes/rows survive every result | call native gateway directly or delete source on cancel -> GMA-04 red | `flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 save and share delegate eligible media without mutating source'`; add file to `GROUP_TESTS` |
| TC-235-05 | Media Reply uses the existing quote composer/message id and remains subject to `canWrite`. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-05 media reply reuses existing group quote flow` | host widget / discussion writer and read-only snapshots | HEAD partial GREEN for overlay Reply but no viewer route -> bubble/viewer both seed the same quote id; read-only snapshot never invokes it | create an alternate media-reply send path -> GMA-05 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-05 media reply reuses existing group quote flow'`; existing `GROUP_TESTS` entry |
| TC-235-06 | Confirmed Delete for me hides/tombstones one whole message first, then deletes only each target app-owned file and removes its attachment journal row/key/local state after file success/already-absent; cancel is a no-op. | `test/features/groups/application/delete_group_media_for_me_use_case_test.dart::GMA-06 confirmed delete is durable first scoped journaled and idempotent` | host integration / production repository + secure-key fake over host SQLite and temp app-media tree | HEAD compile RED: use case absent -> cancel changes nothing; confirm hides/tombstones target, preserves journal/key until safe file cleanup, removes only completed target row/key/state, preserves siblings, and repeated invocation succeeds | delete file before tombstone, delete journal/key before file result, broaden ownership, or delete sibling state -> GMA-06 red | `flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart --plain-name 'GMA-06 confirmed delete is durable first scoped journaled and idempotent'`; add file to `GROUP_TESTS` |
| TC-235-07 | Offline/live replay cannot restore a locally deleted media message/unread state, and a fresh startup/resume reconciler finishes only tombstone-backed orphan attachment cleanup after injected failure. | `test/features/groups/integration/group_received_media_delete_replay_test.dart::GMA-07 tombstone blocks replay and orphan attachment journal resumes cleanup` | host integration / production DB helpers over host SQLite, fresh reconciler, inbox fixture, temp files | HEAD RED for orchestration -> post-delete replay is ignored; failure leaves message hidden plus target attachment/file journal; fresh reconcile deletes file then row without touching non-tombstoned/direct/sibling orphans | skip tombstone predicate, delete journal before file, or make cleanup failure restore row -> GMA-07 red | `flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart`; add file to `GROUP_TESTS` |
| TC-235-08 | Info displays only approved local metadata and never secrets/paths. | `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-08 media info redacts path hash key nonce and relay identifiers` | host widget / attachment populated with sentinel secret values | HEAD RED: Info action/sheet absent -> approved labels render; every sentinel secret is absent from widget text and diagnostics | bind raw attachment map or path to the sheet -> GMA-08 red | focused screen test; existing `GROUP_TESTS` entry |
| TC-235-09 | Failed integrity, pending, missing, or file-changed-after-render media cannot Save/Share, while metadata-only Info remains safe/truthful and Delete/Reply keep their independent message permissions. | `test/features/groups/application/group_received_media_actions_test.dart::GMA-09 plaintext egress revalidates while metadata and message actions remain independent` | host unit / verified-then-mutated temp file and state/permission table | HEAD compile RED -> no egress callback crosses the guard; Info contains no plaintext/path secret and allowed message-level callbacks remain exact | trust viewer-time eligibility or disable every action through one stale integrity bool -> GMA-09 red | focused application test; add file to `GROUP_TESTS` |
| TC-235-10 | Announcements remain read-only for members and receive none of the discussion media-action callbacks/routes. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-10 announcement media preserves current reaction copy and authoring rules` | `GREEN sentinel` plus host widget extension / announcement reader/admin fixtures | HEAD existing sentinel GREEN -> remains GREEN and no discussion core-action labels/callbacks appear | remove `GroupType.chat` boundary -> GMA-10 red | existing group wired test; existing `GROUP_TESTS` entry |
| TC-235-11 | Existing migration-069 local-deletion behavior remains replay-safe without a new schema. | `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::IR-020 tombstone prevents replay save and unread resurrection` | `GREEN sentinel` / production repository over host SQLite | GREEN on HEAD -> remains GREEN after action orchestration | bypass `dbUpsertGroupMessageLocalDeletion` -> sentinel red | existing repository test; existing `GROUP_TESTS` entry |

### Test Notes

- TC-235-06/07 treat database durability and filesystem cleanup as an idempotent saga, not an impossible cross-database/filesystem atomic transaction. The existing orphan attachment row is intentionally retained until its file cleanup succeeds and is eligible for reconciliation only when a matching migration-069 group tombstone exists.
- Use sentinel strings resembling a path, content hash, key, nonce, and relay id in TC-235-08/09 so redaction assertions would fail if a raw model/map is rendered or logged.

## Implementation Steps

1. Confirm the accepted plan-227/230 contracts and that plan 245 remains a separate reporting lane; no report evidence is required to execute these ordinary actions.
2. Snapshot `git status --short`; add TC-235-01 first and run the named RED before production edits.
3. Add a pure group received-media capability policy constrained to incoming verified `GroupType.chat` media, then wire typed actions to the existing bubble overlay and plan-230 viewer.
4. Add the group application adapter for plan-227 Save/Share and reuse the existing Reply/quote route; revalidate attachment state/integrity at invocation.
5. Add the confirmed delete-for-me use case around the existing migration-069 tombstone, attachment rows as per-file cleanup journals, and `MediaFileManager` ownership checks. Add a bounded startup/resume reconciler for tombstone-backed group orphans; remove each row only after file deleted/already absent. Make retries idempotent and durable-first without a new migration.
6. Add the privacy-minimized Info model/sheet; keep Report absent and owned by plan 245.
7. Register new headline files in `GROUP_TESTS`; run focused GREEN, mutation re-reds, replay/announcement sentinels, group/feature gates, analyzer, and hygiene.

## Risks And Blind Spots

- Decrypted media egress can be irreversible -> TC-235-01/04/09 gate eligibility and delegate OS behavior to plan 227.
- Delete spans durable database and filesystem state -> TC-235-06/07 prove tombstone-first visibility, attachment-row cleanup journaling, and fresh-process retry rather than claiming cross-resource atomicity.
- Replay may recreate attachment/UI state -> TC-235-07 plus IR-020 verify message, unread, and attachment projections.
- Lifecycle / derived-state durability: no new durable UI state; deletion reuses migration 069 and must survive restart/replay.
- Sibling-surface consistency: bubble and selected viewer item share one capability policy -> TC-235-02/03.
- Destructive-action side effects: TC-235-06 asserts sibling messages/attachments, exported copies, and arbitrary paths survive.
- Invariant re-verification under new transitions: TC-235-09 rechecks state/file integrity at action time, not only viewer-open time.
- Announcement regression through shared group widgets -> TC-235-10 is a hard lane sentinel.

## Acceptance Gates

```bash
# Accepted shared dependency contracts
test -f Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md

# Snapshot before execution; record unrelated changes
git status --short

# First causal RED; expect non-zero because the group action policy does not exist
flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/application/group_received_media_action_policy_test.dart
flutter test test/features/groups/application/group_received_media_actions_test.dart
flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart

# Preservation and registered family gates; expect exit 0
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Shared egress/viewer dependencies remain green
flutter test test/core/media/received_media_egress_service_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-235-01 fails to compile because the group received-media action policy does not exist.
- Green sentinel: IR-020 replay protection, existing Reply/Copy tests, and announcement authorization remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Prerequisite sequencing: implement against the accepted plan-227/230 contracts; if their final symbols differ, refresh references without expanding scope.
- Environment blocker: N/A for this lane plan; native Save/Share device closure belongs to plan 227.
- Scope drift: any Go/libp2p/wire, Delete-for-everyone, Report implementation, announcement, or QA-group change requires a separate accepted plan.

- [ ] Every behavior has a named causal test or justified boundary proof.
- [ ] First RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Durable delete cleans only target app-owned state and replay cannot resurrect it.
- [ ] Bubble/viewer parity and action-time integrity revalidation pass.
- [ ] Announcement and Reply/Copy preservation sentinels pass.
- [ ] `groups` and `feature-host-all` gates pass with semantic outcomes.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/application/group_received_media_action_policy_test.dart --plain-name 'GMA-01 discussion incoming media capabilities vary safely by action and state'`.
- Preservation command: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'`.
- Harness registration: add all new `test/features/groups/**` headline files to `GROUP_TESTS`; `feature-host-all` also discovers them automatically.
- Migration: none; reuse migration 069 `group_message_local_deletions` and its replay guard.
- Boundary closure: host group-policy/orchestration proof; native egress remains plan 227's Android/iOS device obligation.
- Unresolved evidence: none in this bounded plan; Report is intentionally excluded and owned by plan 245.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | accepted plan-227/230 contracts identified; Report split to plan 245 | none in lane | first causal RED |
