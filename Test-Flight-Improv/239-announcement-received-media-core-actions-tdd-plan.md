# 239 - Announcement Received-Media Core Actions

Status: execution-ready
Type: Feature Improvement
Spec: free-text intent — local received image/video parity for announcement recipients (Save, Share, Delete for me, and Info) without granting announcement publish permission
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | `graphify-arch` query; `group_model.dart`; `group_conversation_screen.dart`; `group_conversation_wired.dart`; `full_screen_image_viewer.dart`; `group_messages_db_helpers.dart`; announcement integration/widget tests; `go-mknoon/node/pubsub.go` | Announcement readers can receive/open verified media, but the viewer has no action callbacks and the group context overlay exposes only reaction/copy; local-delete tombstones and hard Go publisher authorization already exist | define an announcement-only action adapter over the shared egress/viewer contracts |
| 2026-07-09 | Planner | `received-media-native-egress-foundation` plan 227; current media repository and local file seams; announcement/1:1 ownership boundaries | Save/Share can reuse 227, Delete for me can reuse the existing group tombstone path, and Info is local-only | keep cross-lane Reply and backend Reporting in their separately owned plans |

## Problem And Evidence

- Behavior to improve: a non-admin announcement recipient who opens an incoming image or video needs discoverable Save, Share, Delete for me, and Info actions from both the message and viewer surfaces.
- Impact: the recipient can view downloaded media but cannot intentionally move it outside the app, remove it locally, or inspect its provenance.
- Confirmed current gap: `GroupConversationWired._onMediaTap` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4486` passes only paths/indexes to `FullScreenImageViewer`; that viewer's app bar at `lib/shared/widgets/media/full_screen_image_viewer.dart:60` contains only Back and an item counter.
- Confirmed current gap: `GroupConversationScreen._showMessageContextOverlay` at `lib/features/groups/presentation/screens/group_conversation_screen.dart:930` exposes reaction, reply, and copy flags only; for readers `showReplyAction` is false because reply is coupled to `canWrite` at `:950`.
- Confirmed announcement discriminator and authorization: `GroupType.announcement` and `GroupRole` are durable model fields at `lib/features/groups/domain/models/group_model.dart:2` and `:25`; Flutter send rejects a non-admin at `lib/features/groups/application/send_group_message_use_case.dart:809`; Go independently rejects an unauthorized announcement `group_message` at `go-mknoon/node/pubsub.go:1605` and `isAllowedWriter` at `:1963`.
- Confirmed deletion mechanism: `GroupMessageRepository.deleteMessage` exists at `lib/features/groups/domain/repositories/group_message_repository.dart:71`; `dbDeleteGroupMessage` records a `group_message_local_deletions` tombstone before deleting at `lib/core/database/helpers/group_messages_db_helpers.dart:739`; the existing `IR-020 tombstone prevents replay save and unread resurrection` test proves replay cannot restore the row.
- Confirmed safe-media gate: group media opens only after `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4493`. Action availability must use the same verified attachment, not trust a raw path.
- Existing coverage: `test/features/groups/integration/announcement_happy_path_test.dart::announcement admin can send GIF media and reader receives image/gif read-only` proves receipt; `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` proves the current deliberate reaction/send asymmetry; Go `TestIsAllowedWriter_AnnouncementMemberBlocked` proves the native authorization backstop.
- Missing coverage: no test names received-media core actions, action-to-service wiring, local artifact cleanup, or message Info.
- Refuted findings: Delete for me is not blocked by the group repository or replay model; the missing piece is a normal incoming-message UI/application path. A local delete must still remove the whole message because HEAD has a message tombstone but no attachment-level deletion tombstone.
- Unresolved findings: N/A — every action in this plan has a local or plan-227 typed boundary; Reporting and cross-lane Reply are explicitly out of scope.
- Affected production, test, and gate files: `lib/features/groups/presentation/screens/group_conversation_screen.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, shared viewer/action adapters from plans 227/230, a new announcement delete application seam, announcement action tests, and `scripts/run_test_gates.sh` registration.

## Scope Contract And Guard

In scope:
- Build one typed received-media action description from a persisted `GroupMessage`, its verified `MediaAttachment`, and `GroupModel.type`; render it in the announcement message overflow and the plan-230 typed viewer action surface.
- Route Save and external Share through plan 227's `ReceivedMediaEgressService` using `MediaEgressRequest/Result`; preserve its OS permission, path-validation, duplicate-name, and result semantics.
- Add announcement Delete for me for the entire local message: confirm explicitly, unlink every app-owned attachment artifact, delete attachment/reaction rows, call `GroupMessageRepository.deleteMessage` so the replay tombstone is written, then remove the local UI row. No network event is sent.
- Show Info for sender display name/peer identity, sent time, caption, MIME/type, byte size, dimensions or duration, and current app-local download/integrity state. Do not imply export-history knowledge that is not persisted.

Must preserve:
- Announcement members remain unable to attach, record, quote-reply, or send into the announcement -> `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write` and `::stale writer callbacks cannot bypass read-only announcement mode`.
- Reader reactions remain allowed while compose stays read-only -> `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry`.
- Go rejects non-admin announcement publishing even if Flutter is bypassed -> `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` and `::TestGroupTopicValidator_AnnouncementNonAdminRejected`.
- Local deletion cannot resurrect from inbox/history replay -> existing `IR-020` repository/drain tests plus TC-239-05.

Hard `Do not`:
- Do not change discussion/chat or Q&A group action/send behavior.
- Do not make `canWrite` true, attach a group quote, call `sendGroupMessage`, `group:publish`, or `group:inboxStore` from any recipient action.
- Do not add Delete for everyone, admin retraction, or attachment-only deletion in this plan.
- Do not export an unverified/quarantined/missing file or pass arbitrary absolute paths to native egress.
- Do not add Reporting or cross-lane private-reply/deep-link behavior; those have separate owners and acceptance contracts.

Deferred / accepted difference:
- Delete removes the entire message and all attachments. Per-attachment deletion needs an attachment-level anti-replay contract and is deferred to a separately numbered storage/deletion proposal.
- Reporting is owned by `Test-Flight-Improv/246-announcement-received-media-reporting-tdd-plan.md`; private reply routing is owned by `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md`. Neither blocks these four local actions.
- View-once/disappearing/protected action suppression is owned by plan 242.

Dependencies:
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` supplies `ReceivedMediaEgressGateway/Service` and `MediaEgressRequest/Result`.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies typed `MediaViewerItem` metadata and optional action capabilities/callbacks.
- No database migration and no Go/libp2p production change are permitted by this plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-239-01 | Incoming verified announcement image/video exposes Save, Share, Delete for me, and Info from message and viewer while compose remains absent | `test/features/groups/presentation/announcement_received_media_actions_test.dart::reader sees the same core media actions in message overflow and viewer without write controls` | widget / `WidgetTester`, fake typed viewer item and action callbacks | HEAD group overlay has reaction/copy and viewer has Back only -> both surfaces contain the same four capability-derived core actions and no composer/quote action | remove a core action, couple it back to `canWrite`, or add `onQuoteReply` -> TC-239-01 red | `flutter test test/features/groups/presentation/announcement_received_media_actions_test.dart --plain-name 'reader sees the same core media actions in message overflow and viewer without write controls'`; AUTO (`test/features/**` glob) plus add file to `GROUP_TESTS` |
| TC-239-02 | Save passes the verified stored attachment through plan 227 and renders its semantic success/permission/failure result | `test/features/groups/application/announcement_received_media_action_coordinator_test.dart::save resolves verified group media and delegates one MediaEgressRequest` | application host / fake `ReceivedMediaEgressGateway`, fake resolver | HEAD has no Save coordinator/symbol -> one request contains attachment identity, resolved app-owned path and save destination; no group send occurs | pass `attachment.localPath` without verified/path ownership checks -> TC-239-02 red | `flutter test test/features/groups/application/announcement_received_media_action_coordinator_test.dart --plain-name 'save resolves verified group media and delegates one MediaEgressRequest'`; AUTO plus `GROUP_TESTS` |
| TC-239-03 | External Share uses plan 227 and does not mutate/delete the message or disclose media encryption keys | `test/features/groups/application/announcement_received_media_action_coordinator_test.dart::external share delegates a sanitized egress request and preserves source rows` | application host / fake egress, message/media repositories | HEAD has no Share action -> gateway receives file/caption metadata allowed by 227, source message/attachment rows remain, request contains no key/nonce | serialize `MediaAttachment.toMap()` into share metadata -> TC-239-03 red | `flutter test test/features/groups/application/announcement_received_media_action_coordinator_test.dart --plain-name 'external share delegates a sanitized egress request and preserves source rows'`; AUTO plus `GROUP_TESTS` |
| TC-239-04 | Delete for me removes the selected message, all its app-owned files/attachment/reaction rows, and no sibling message/file | `test/features/groups/application/delete_announcement_message_for_me_test.dart::delete for me cleans one announcement message completely and preserves siblings` | application host integration / temp app-docs directory, in-memory repos with deletion spies | HEAD normal incoming announcement has no delete use case/action -> selected artifacts and rows are gone, sibling state remains, no bridge command occurs | omit file cleanup, attachment cleanup, or target-id scoping -> TC-239-04 red | `flutter test test/features/groups/application/delete_announcement_message_for_me_test.dart --plain-name 'delete for me cleans one announcement message completely and preserves siblings'`; AUTO plus `GROUP_TESTS` |
| TC-239-05 | A deleted incoming announcement cannot resurrect through a duplicate save or group inbox/history replay | `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::IR-020 tombstone prevents replay save and unread resurrection` plus `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::IR-020 local delete tombstone blocks inbox drain and history repair resurrection` | GREEN sentinel / repository + real SQLite fixture already used by suites | GREEN on HEAD -> stays GREEN after action wiring calls the tombstoning delete, not a raw repair delete | replace `deleteMessage` with `deleteMessageForMembershipRepair` or raw row delete -> sentinel red | `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection' && flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-020 local delete tombstone blocks inbox drain and history repair resurrection'`; first file already in `GROUP_TESTS`, second AUTO |
| TC-239-06 | Info shows message/attachment provenance and honest local/download/integrity facts without exposing secret key material | `test/features/groups/presentation/announcement_received_media_info_sheet_test.dart::announcement media info shows sender time dimensions duration size and integrity but no secrets` | widget / typed message+attachment fixtures | HEAD has no message-media Info sheet -> expected labels render; key/nonce and raw private paths never render | build rows from unrestricted `MediaAttachment.toMap()` -> TC-239-06 red | `flutter test test/features/groups/presentation/announcement_received_media_info_sheet_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-239-07 | Reader reaction remains available while all compose/send callbacks remain null | `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` | GREEN sentinel / widget fakes | GREEN on HEAD -> remains GREEN | gate reaction mutation on `_canWrite` or expose compose callback -> sentinel red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`; existing `GROUP_TESTS` |
| TC-239-08 | Native Go authorization still rejects reader/writer announcement message publication | `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` and `::TestGroupTopicValidator_AnnouncementNonAdminRejected` | GREEN sentinel / Go node unit, real envelope validator | GREEN on HEAD -> remains GREEN; no Go production diff expected | return true for non-admin in `isAllowedWriter` or skip validator check -> sentinel red | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestIsAllowedWriter_AnnouncementMemberBlocked -count=1 && GOTOOLCHAIN=go1.25.0 go test ./node -run TestGroupTopicValidator_AnnouncementNonAdminRejected -count=1)`; AUTO (`go test`, manual preservation command) |

### Test Notes

- TC-239-02/03 must use a verified `downloadStatus == done` attachment whose resolved file exists. Add sibling fixtures for integrity-failed, missing, and `upload_pending`; each must omit/disable egress and must not call the gateway.
- TC-239-04 deletion order must preserve enough attachment metadata to unlink files before rows are dropped. Include an external user-owned fixture outside app storage and assert it is not deleted, without claiming the app tracks export history.

## Implementation Steps

1. Snapshot `git status --short`; confirm plans 227 and 230 have accepted interfaces; add TC-239-01 through TC-239-08 before production edits and record the causal failures/sentinels separately.
2. Add an announcement received-media action coordinator that accepts durable message/attachment identities, re-loads current rows, re-checks integrity/path ownership, and delegates Save/Share to `ReceivedMediaEgressService`. Stop-if: implementation would bypass plan 227 or accept an arbitrary path.
3. Thread one typed action/capability model into `GroupConversationScreen` and `MediaViewerItem`; use an overflow/action sheet sized for all actions rather than making the fixed-height `MessageContextOverlay` overflow.
4. Add the whole-message Delete for me use case and wire both surfaces to one confirmation/result flow. Stop-if: a proposed single-attachment delete can be replay-enriched because no attachment tombstone exists.
5. Add the local Info sheet from a deliberately sanitized view model. Keep `canWrite`, `_onQuoteReply`, `_onSend`, `_onAttach`, and recording callbacks unchanged for readers.
6. Add new announcement headline tests to `GROUP_TESTS`, then run focused GREEN, feature/group preservation gates, the Go authorization sentinel, analyzer, and diff hygiene.

## Risks And Blind Spots

- A path-only action API could export quarantined or stale media -> TC-239-02/03 re-load by attachment ID and reuse the group integrity/ownership gate.
- Delete can orphan files or replay-resurrect rows -> TC-239-04/05 assert file, row, sibling and tombstone effects.
- Sibling surfaces could drift as later action plans extend the menu -> TC-239-01 asserts that the same four core actions stay present without coupling them to write permission.
- Lifecycle / derived-state durability: deletion durability is TC-239-05; other action availability is derived from re-loaded durable message/attachment state on each open.
- Sibling-surface consistency: TC-239-01 proves message and viewer derive from one capability set.
- Destructive-action side effects: TC-239-04/05 assert removal and preservation across files, attachment/reaction/message rows and replay.
- Invariant re-verification under new transitions: every action re-loads current attachment state; TC-239-02/03 mutate availability after the menu was opened and must fail closed at invocation.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# First causal RED before production edits; expect non-zero because action callbacks/keys are absent
flutter test test/features/groups/presentation/announcement_received_media_actions_test.dart --plain-name 'reader sees the same core media actions in message overflow and viewer without write controls'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/presentation/announcement_received_media_actions_test.dart test/features/groups/presentation/announcement_received_media_info_sheet_test.dart test/features/groups/application/announcement_received_media_action_coordinator_test.dart test/features/groups/application/delete_announcement_message_for_me_test.dart

# Existing deletion/read-only preservation; expect exit 0
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'

# Named host gates; expect exit 0, new targets selected by groups and AUTO feature glob
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Go authorization preservation; expect package ok
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-239-01 fails because neither announcement surface exposes received-media core actions; TC-239-02/03/06 fail by absent coordinator/symbols.
- Green sentinel: TC-239-05, TC-239-07, and TC-239-08 must remain green.
- Pre-existing dirty tree / known failure: record but do not modify unrelated work; `Test-Flight-Improv/00-INDEX.md` was already dirty during planning and is explicitly outside this plan.
- Environment blocker: plan 227 owns real OS Save/Share proof; this announcement adapter closes on host fakes only after 227 is accepted. Go 1.26.x is a known quic-go hazard, so the command pins `GOTOOLCHAIN=go1.25.0`.
- Scope drift: any same-announcement reader send path, Go/libp2p production diff, attachment-only delete, Report implementation, or cross-lane Reply behavior blocks completion.

- [ ] Every behavior has a named test or justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation and named gates pass with semantic outcomes.
- [ ] New announcement headline tests are present in `GROUP_TESTS`; feature tests remain AUTO-globbed.
- [ ] Plan 227 native egress acceptance evidence is referenced, not duplicated.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/presentation/announcement_received_media_actions_test.dart --plain-name 'reader sees the same core media actions in message overflow and viewer without write controls'`.
- Preservation command: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`.
- Manual registration: add the three new announcement action/application test files and Info test to `GROUP_TESTS`; AUTO feature glob also discovers them.
- Migration: none; existing DB v69 group local-deletion tombstone behavior is reused, and this plan must not change the current DB version.
- Boundary closure: host-only announcement adapter; real iOS/Android Save/Share closure belongs to plan 227.
- Unresolved evidence: none; Reporting is isolated in plan 246 and cross-lane Reply in plan 247.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plans 227 and 230 | contract extraction |
