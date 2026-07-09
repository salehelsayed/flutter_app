# 240 - Announcement Received-Media Forwarding

Status: execution-ready
Type: New Feature
Spec: free-text intent — announcement recipients forward incoming image/video media to allowed contact/group targets with caption and multi-target controls, without bypassing source or destination publish policy
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | `graphify-arch` query; `share_target_picker_wired.dart`; `share_batch_delivery_coordinator.dart`; `send_group_message_use_case.dart`; announcement integration tests; Go group validator | The repo already has multi-select contact/group delivery, caption editing, per-target upload, and send-time group revalidation, but no message/viewer Forward entry or announcement-source request | adapt the existing share flow; do not add another transport or picker |
| 2026-07-09 | Planner | direct/group forwarding plans 232/236 and DB sequencing from current DB v95 | Plan 232 owns direct `isForwarded`/inner provenance and DB v97; plan 236 owns backward-compatible encrypted group `isForwarded` and DB v98. Announcement forwarding can adapt both without a new field/frame | define source eligibility, target-scoped provenance, and no-source-publish discriminators |

## Problem And Evidence

- Behavior to improve: a recipient should be able to select an incoming announcement image/video, optionally keep/remove/edit its caption, and forward it to one or more allowed contacts and writable groups.
- Impact: recipients currently have to save and reattach manually (once egress exists), losing context and creating avoidable copies; today there is no in-app Forward action at all.
- Confirmed current mechanism: `ShareTargetPickerWired` loads active contacts and writable groups, supports independent contact/group selection sets, and calls one batch coordinator at `lib/features/share/presentation/screens/share_target_picker_wired.dart:38`, `:115`, and `:315`.
- Confirmed destination-group policy: `_isWritableGroupTarget` rejects archived/dissolved groups, rejects non-admin announcement destinations, requires a current group key, and requires active membership at `lib/features/share/presentation/screens/share_target_picker_wired.dart:256`; `_resolveSelectedTargetsForDelivery` re-loads and revalidates the group at send time at `:391`.
- Confirmed caption mechanism: the picker initializes `_captionController` from `ShareIntent.text` at `lib/features/share/presentation/screens/share_target_picker_wired.dart:107` and builds a trimmed copy at `:465`.
- Confirmed per-target delivery: `DefaultShareBatchDeliveryCoordinator.deliver` processes source media once, then iterates targets at `lib/features/share/application/share_batch_delivery_coordinator.dart:163`; `_sendToContact` mints a new attachment ID and calls encrypted `uploadMedia` per contact at `:279`; `_sendToGroup` mints a new attachment ID, loads destination members as `allowedPeers`, uploads, and calls `sendGroupMessage` at `:382`.
- Confirmed source gap: `GroupConversationScreen` and `FullScreenImageViewer` have no Forward callback/action (`lib/features/groups/presentation/screens/group_conversation_screen.dart:41`; `lib/shared/widgets/media/full_screen_image_viewer.dart:19`). `ShareIntent` represents external input only and carries text/file paths, with no source message policy at `lib/core/services/share_intent_model.dart:1`.
- Confirmed authorization backstops: Flutter refuses non-admin announcement sends before network at `lib/features/groups/application/send_group_message_use_case.dart:809`; Go rejects a non-admin `group_message` at `go-mknoon/node/pubsub.go:1605` and `:1963`.
- Existing coverage: `test/features/share/application/share_batch_delivery_coordinator_test.dart::processes shared media once before fanout across target kinds` covers bounded preprocessing; its media-encryption tests cover encrypted contact upload; `test/features/groups/integration/announcement_new_reader_onboarding_test.dart` proves a reader's text/image/video/voice send attempts are unauthorized with no `group:publish` increase.
- Missing coverage: no source-message-to-`ShareIntent` adapter, no announcement reader Forward UI, no caption-mode contract, no explicit blocked-contact filter, no direct/group forward-marker handoff, no source-announcement-vs-destination event discriminator, and no target-partial-failure retry test for this entry path.
- Refuted findings: this feature does not require a new libp2p protocol, relay endpoint, or group encryption primitive. Existing share and group send paths already cross those boundaries.
- Unresolved findings: N/A — direct marker/provenance ownership is fixed by plan 232 and group marker/wire ownership by plan 236; this plan supplies their accepted inputs but owns neither schema/wire contract.
- Affected production, test, and gate files: announcement message/viewer actions, a new `AnnouncementMediaForwardRequest` adapter into `ShareIntent`, `ShareTargetPickerWired` source-policy inputs, `DefaultShareBatchDeliveryCoordinator` forwarding metadata handoff, announcement/share tests, and `GROUP_TESTS` registration.

## Scope Contract And Guard

In scope:
- Add Forward to eligible incoming announcement image/video actions. Eligibility requires a persisted incoming non-system message, a displayable verified local file for every selected attachment, and lifecycle policy `canForward == true` when plan 242 metadata is present.
- Convert selected attachments into an announcement-scoped forward request containing source group/message/attachment identities, resolved file paths, and one caption mode: keep, remove, or edit. Build a `ShareIntent` only after re-loading and validating those rows.
- Reuse `ShareTargetPickerWired` search/multi-select UI. Allowed contacts are active and unblocked. Allowed groups remain exactly `_isWritableGroupTarget`: active membership/key, not archived/dissolved, and admin role for announcement destinations.
- Revalidate every selected target immediately before delivery. Keep failed targets selected and report sent/queued/failed per target, matching the existing batch result behavior.
- Process media once for sizing/compression but mint a fresh outgoing message/attachment ID and run the destination upload/encryption path separately for each target. Never reuse another target's media key/nonce or an incoming attachment ID as an outgoing blob ID.
- Reuse plan 236's `GroupMediaForwardRequest` and optional encrypted `isForwarded` field for group destinations. Forwarded metadata contains only the boolean marker; it does not reveal the source group, original sender, message ID, or caption provenance.
- Contact destinations use plan 232's accepted `isForwarded: true` and encrypted-inner provenance slot. Generate an opaque target-scoped operation key for each contact, retain it across failed/queued retry, and never derive it from or serialize the source group, original sender, source message, or attachment identity.

Must preserve:
- Source announcement stays read-only and receives no new local/outgoing message -> TC-240-07 and existing `announcement_new_reader_onboarding_test` unauthorized-send assertions.
- Destination authorization is rechecked at send time -> existing picker tests plus TC-240-02/06.
- Group transport/pubsub/inbox/retry semantics and member recipient calculation remain unchanged -> plan 236 sentinels and TC-240-09.
- Direct marker, legacy decode, encrypted-inner privacy, recipient rendering, and retry/reopen semantics remain plan 232's contract -> TC-240-11 plus plan-232 TC-232-07/10/11.
- Caption is a newly composed outgoing value; the source message and attachment rows are unchanged -> TC-240-03/08.

Hard `Do not`:
- Do not call `sendGroupMessage`, `group:publish`, or `group:inboxStore` for the source announcement group.
- Do not permit a reader to select the source announcement or any other announcement where the current role is not admin.
- Do not change Go framing, group topic names, validator roles, recipient calculation, relay custody, retry payloads, or encryption algorithms.
- Do not reuse incoming blob IDs, encryption keys/nonces, content ownership, or sender attribution across destinations.
- Do not put source group/sender/message/attachment IDs into the direct provenance slot, operation key, outer envelope, diagnostics, or recipient marker.
- Do not change discussion/chat behavior except through the already-approved plan-236 shared group forwarding contract.

Deferred / accepted difference:
- Direct-message schema/codec/rendering remains owned by plan 232. This adapter must pass its marker and privacy-safe internal provenance inputs but must not edit DB v97 or the direct wire codec.
- Bulk forwarding from the plan-241 library may invoke the same request later, but this plan initially owns one source message's selected image/video attachments.
- Private/protected/view-once denial is finalized by plans 238/242; until those lifecycle states can exist, normal media remains forwardable.

Dependencies:
- `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` must land first and supplies direct `isForwarded`, encrypted-inner provenance, recipient rendering, retry/reopen behavior, and DB v97 `messages.is_forwarded`.
- `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` must land first and supplies `GroupMediaForwardRequest`, `GroupMessage.isForwarded`, backward-compatible encrypted payload propagation, and DB v98 `group_messages.is_forwarded`.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies the typed viewer Forward capability/callback.
- This plan allocates no migration and introduces no new wire contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-240-01 | Read-only announcement recipient sees Forward on eligible incoming image/video and reaches the existing target picker without gaining compose/quote actions | `test/features/groups/presentation/announcement_received_media_forwarding_test.dart::reader opens Forward picker for verified media while announcement compose remains read-only` | widget / `WidgetTester`, picker-route spy | HEAD has no Forward action/request -> picker opens with preview/caption, compose/quote controls remain absent | gate Forward on `canWrite` or pass `onQuoteReply` -> TC-240-01 red | `flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'`; AUTO plus add to `GROUP_TESTS` |
| TC-240-02 | Picker offers active unblocked contacts, writable chat groups and admin-owned announcement groups, but excludes blocked contacts and non-writable announcements | `test/features/share/presentation/announcement_forward_target_policy_test.dart::announcement forward lists only allowed contact and group targets` | widget/application host / contact+group repos, role/key/member fixtures | HEAD generic picker includes active contacts without an announcement-source policy and has no forward entry -> expected target set is exact | include blocked contact or remove announcement-admin condition -> TC-240-02 red | `flutter test test/features/share/presentation/announcement_forward_target_policy_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-240-03 | Keep/remove/edit caption modes create the intended outgoing text without mutating source caption/message | `test/features/groups/application/announcement_media_forward_request_test.dart::caption modes preserve remove or replace source caption deterministically` | unit/application host / immutable request fixture | HEAD request type absent -> each mode yields exact `ShareIntent.text`; source object remains equal | always seed picker with source text or trim an explicitly kept caption to null -> TC-240-03 red | `flutter test test/features/groups/application/announcement_media_forward_request_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-240-04 | Multi-target forward preprocesses once but mints distinct outgoing IDs and destination encryption/upload metadata per target | `test/features/share/application/announcement_forward_batch_delivery_test.dart::multi-target forward processes once and creates distinct encrypted attachment identities per destination` | application host / real coordinator with fake bridge/uploader and contact/group fakes | HEAD coordinator can batch external shares but has no forward request/marker; test initially fails to compile/assert forward inputs -> one preprocessing call, one independent upload/send per target, unique message/blob/key/nonce tuples | hoist uploaded attachment or attachment ID outside the target loop -> TC-240-04 red | `flutter test test/features/share/application/announcement_forward_batch_delivery_test.dart --plain-name 'multi-target forward processes once and creates distinct encrypted attachment identities per destination'`; AUTO plus `GROUP_TESTS` |
| TC-240-05 | Group destinations receive plan-236 `isForwarded == true` through live and offline/replay paths, with no original source identity | `test/features/groups/integration/announcement_media_forward_marker_test.dart::announcement source forward reaches group destination with boolean marker and no source attribution` | host integration / fake group pubsub + inbox replay harness from plan 236 | HEAD lacks forward marker/request -> destination marker true after send/replay; serialized payload has no source group/sender/message keys | drop marker from retry/inbox payload or add source identity fields -> TC-240-05 red | `flutter test test/features/groups/integration/announcement_media_forward_marker_test.dart`; AUTO plus `GROUP_TESTS`; DB/wire implementation inherited from 236 |
| TC-240-06 | A group selected while writable is dropped/fails before send if membership/key/role changes, while still-valid targets deliver | `test/features/share/presentation/announcement_forward_target_policy_test.dart::send-time revalidation removes a demoted announcement target and preserves valid targets` | widget/application host / mutable group repo, coordinator spy | HEAD generic revalidation exists but no forward flow assertion -> demoted target omitted with truthful result; valid contact/chat target called once | deliver cached `GroupModel` without `_resolveSelectedTargetsForDelivery` -> TC-240-06 red | `flutter test test/features/share/presentation/announcement_forward_target_policy_test.dart --plain-name 'send-time revalidation removes a demoted announcement target and preserves valid targets'`; AUTO plus `GROUP_TESTS` |
| TC-240-07 | Forwarding from announcement A to a writable chat group B emits target-B commands only and never publishes into source A | `test/features/groups/integration/announcement_received_media_forwarding_test.dart::reader forward sends only to selected destination and never publishes to source announcement` | host integration / command-log bridge with groupId discriminator | HEAD has no forward flow -> destination B `group:sendReliable`/publish input present, source A publish/inbox absent, source rows unchanged | accidentally use source group from request as destination -> TC-240-07 red | `flutter test test/features/groups/integration/announcement_received_media_forwarding_test.dart --plain-name 'reader forward sends only to selected destination and never publishes to source announcement'`; AUTO plus `GROUP_TESTS` |
| TC-240-08 | Partial batch failure leaves failed targets selected for retry and never re-sends successful targets on the retry pass | `test/features/share/application/announcement_forward_batch_delivery_test.dart::partial failure reports per target and retry selection contains failures only` | application/widget host / deterministic target result fake | HEAD existing picker behavior is generic but no announcement forward integration -> sent/queued/failed counts and retained selections are exact | retain all selected targets or collapse per-target result to global failure -> TC-240-08 red | `flutter test test/features/share/application/announcement_forward_batch_delivery_test.dart --plain-name 'partial failure reports per target and retry selection contains failures only'`; AUTO plus `GROUP_TESTS` |
| TC-240-09 | Go still rejects any non-admin attempt to publish a group message into an announcement destination | `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` and `::TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish` | GREEN sentinel / Go node unit, real envelope authorization | GREEN on HEAD -> remains GREEN; no Go production edit expected | allow writer/reader role or bypass `isAllowedWriter` -> sentinel red | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestIsAllowedWriter_AnnouncementMemberBlocked -count=1 && GOTOOLCHAIN=go1.25.0 go test ./node -run TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish -count=1)`; AUTO Go preservation command |
| TC-240-10 | Legacy/non-forwarded group media still decodes as `isForwarded == false` and discussion sends are unchanged | plan-236 `test/features/groups/application/group_message_listener_test.dart::GMF-08 live forwarded marker roundtrips with legacy false fallback` plus `test/features/groups/integration/group_messaging_smoke_test.dart` | GREEN sentinel / plan-236 host fixture and existing group smoke | GREEN after 236 -> remains GREEN during announcement adapter work | default absent marker to true or alter ordinary group request creation -> sentinel red | `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'GMF-08 live forwarded marker roundtrips with legacy false fallback' && flutter test test/features/groups/integration/group_messaging_smoke_test.dart`; AUTO / existing `GROUP_TESTS` |
| TC-240-11 | Every contact destination receives plan-232 `isForwarded == true` and a distinct opaque target-scoped operation key that survives retry without exposing source identity | `test/features/share/application/announcement_forward_contact_marker_test.dart::contact forward marker and opaque per-target key survive retry without source attribution` | application host / real coordinator with two contact targets, one fail-then-retry sender, payload/log capture | HEAD announcement adapter has no provenance; after 232 generic direct forwarding exists but cannot identify this source flow -> each contact receives marker true and its own stable retry key; outgoing id/crypto stay fresh; source group/sender/message/attachment values are absent | derive key from source ID, reuse one key across contacts, drop marker, or remint key on retry -> TC-240-11 red | `flutter test test/features/share/application/announcement_forward_contact_marker_test.dart`; AUTO plus `GROUP_TESTS`; DB/wire/rendering proof inherited from 232 |

### Test Notes

- TC-240-04 must inspect destination-specific values after the real coordinator loop. A stubbed `sendToContactFn` alone cannot prove per-target ID/encryption behavior.
- TC-240-05 asserts only the boolean marker supported by plan 236. Keys such as `originalSender`, `sourceGroupId`, `sourceMessageId`, and `forwardedFrom` must be absent from decrypted inner payload, retry payload, and emitted event.
- TC-240-07 uses group ID as the shared-result discriminator: target event present and source event absent. Merely asserting one successful result is insufficient.
- TC-240-11 captures the contact call and encrypted-inner payload after the plan-232 codec. The target-scoped operation key must be byte-equal between first attempt/retry for that target, unequal across contacts, and non-equal/non-containing with every source identity fixture.
- Contacts and groups can have different delivery outcomes; the picker summary and retained-selection behavior must remain per target.

## Implementation Steps

1. Snapshot `git status --short`; verify plans 232/236 are accepted and their DB v97/v98 model/payload tests are green; add TC-240-01 through TC-240-11 before announcement production edits.
2. Add immutable announcement forward request/caption-mode policy that re-loads source message and attachments, resolves owned paths, and rejects system/outgoing/missing/unverified/lifecycle-denied inputs. Stop-if: adapter would need raw group keys or a new transport frame.
3. Expose the Forward callback through the shared plan-230 viewer and announcement message action model; open the existing `ShareTargetPickerWired` with the composed `ShareIntent` and forwarding context.
4. Tighten forward target policy for blocked contacts while preserving the existing destination-group checks and send-time revalidation.
5. Thread plan-232 marker plus opaque target-scoped retry-stable provenance into contact delivery and plan-236 forwarding metadata into group delivery. Do not edit either schema/codec or introduce a third wire contract.
6. Add target-discriminated tests and register the new announcement/share headline suites in `GROUP_TESTS`.
7. Run focused GREEN, group/share preservation, Go auth sentinel, feature-host-all, analyzer, and diff hygiene.

## Risks And Blind Spots

- Reusing a processed/uploaded artifact across targets can leak recipient-specific key material -> TC-240-04 locks distinct IDs and encryption metadata.
- Cached picker targets can bypass a demotion/removal -> TC-240-06 forces send-time repo revalidation.
- Source and destination are both group IDs and could be confused -> TC-240-07 asserts destination-present/source-absent commands.
- Forward marker propagation can be lost in offline retry -> TC-240-05 uses both live and replay paths inherited from plan 236.
- Contact forwarding can silently render as an ordinary send or leak/link source identity -> TC-240-11 locks the plan-232 marker and per-target opaque stable key.
- Lifecycle / derived-state durability: source and target eligibility are re-loaded on invocation; destination durability remains plan-232 direct retry/reopen and plan-236 group send/replay, with TC-240-11 covering the adapter key across retry.
- Sibling-surface consistency: TC-240-01 uses the one action/capability model shared by bubble and viewer.
- Destructive-action side effects: N/A — forwarding does not delete or alter source state; TC-240-03/07/08 assert preservation.
- Invariant re-verification under new transitions: TC-240-06 rechecks role/key/membership after selection; TC-240-04 rechecks independent destination material per send.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal RED before announcement production edits; expect non-zero because Forward action/request is absent
flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/application/announcement_media_forward_request_test.dart test/features/groups/presentation/announcement_received_media_forwarding_test.dart test/features/groups/integration/announcement_received_media_forwarding_test.dart test/features/groups/integration/announcement_media_forward_marker_test.dart test/features/share/presentation/announcement_forward_target_policy_test.dart test/features/share/application/announcement_forward_batch_delivery_test.dart test/features/share/application/announcement_forward_contact_marker_test.dart

# Shared picker/coordinator preservation; expect exit 0
flutter test test/features/share/presentation/share_target_picker_wired_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart

# Direct marker/provenance retry preservation from plan 232; expect exit 0
flutter test test/features/conversation/domain/models/message_payload_test.dart --plain-name 'forward marker is legacy-safe inner-only and carries media plus dedup'
flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart

# Named gates; expect new files selected and zero failures
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Go publisher authorization remains unchanged; expect package ok
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish' -count=1)

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-240-01 and TC-240-03 fail because no Forward action or announcement request exists; TC-240-04/05/07/11 fail on missing forwarding context/marker integration.
- Green sentinel: TC-240-09 and TC-240-10 stay green; existing share coordinator/picker suites stay green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: no simulator/device is required because real group crypto/wire closure belongs to plan 236 and no wire contract changes here. Go commands must pin 1.25.0.
- Scope drift: new protocol fields beyond plans 232/236, direct/group schema edits, source-announcement publication, source-derived provenance, or discussion behavior changes block completion.

- [ ] Every behavior has a named test or justified inherited proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Plan 232 DB v97 direct marker/retry gates and plan 236 DB v98 group live/replay marker gates are green before adapter acceptance.
- [ ] Per-target encryption/ID and source-absent event discrimination pass.
- [ ] New tests are registered in `GROUP_TESTS` and AUTO feature discovery.
- [ ] Go publisher sentinels, `groups`, and `feature-host-all` pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'`.
- Preservation command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish' -count=1)`.
- Manual registration: add the seven new announcement/share forwarding test files to `GROUP_TESTS`; AUTO feature glob also discovers them.
- Migration: none in this plan; reuse plan 232 DB v97 `messages.is_forwarded` and plan 236 DB v98 `group_messages.is_forwarded`. Do not allocate another version.
- Boundary closure: host announcement adapter; plan 232 owns direct SQLCipher/inner-payload/retry closure and plan 236 owns real group crypto/live/replay closure.
- Unresolved evidence: none. Execution order is the only prerequisite: plans 232 and 236 before 240.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plans 232 and 236 | contract extraction |
