# 240 - Announcement Received-Media Forwarding

Status: accepted (2026-07-11; orchestrated Executor + fix pass 1 + independent QA; host closure complete)
Type: New Feature
Spec: free-text intent — announcement recipients forward incoming image/video media to allowed contact/group targets with caption and multi-target controls, without bypassing source or destination publish policy
Classification: implemented / accepted
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | `graphify-arch` query; `share_target_picker_wired.dart`; `share_batch_delivery_coordinator.dart`; `send_group_message_use_case.dart`; announcement integration tests; Go group validator | The repo already has multi-select contact/group delivery, caption editing, per-target upload, and send-time group revalidation, but no message/viewer Forward entry or announcement-source request | adapt the existing share flow; do not add another transport or picker |
| 2026-07-09 | Planner | direct/group forwarding plans 232/236 and DB sequencing from current DB v95 | Plan 232 owns direct `isForwarded`/inner provenance and DB v97; plan 236 owns backward-compatible encrypted group `isForwarded` and DB v99. Announcement forwarding can adapt both without a new field/frame | define source eligibility, target-scoped provenance, and no-source-publish discriminators |
| 2026-07-10 | Replanner (version rebase) | plan 235 audit disposition; plan 236 rebase | Plan 235 claimed v98 for its group media deletion journal; plan 236's forwarded marker moved to DB v99 and this plan's references follow. | none — still blocked on plans 232/235/236 landing in order |
| 2026-07-10 | Planner refresh | revised plan 228 owner contract; plans 232/236 destination write seams; announcement source resolver; share provenance/codec boundaries | Announcement source media is local owner `group`; contact destination attachments persist as `direct` via plan 232 and group/announcement destinations as `group` via plan 236. Owner is local DB state only and must never enter Forward provenance or any wire map. | add owner collision/source-destination tests without expanding transport scope |

## Problem And Evidence

- Behavior to improve: a recipient should be able to select an incoming announcement image/video, optionally keep/remove/edit its caption, and forward it to one or more allowed contacts and writable groups.
- Impact: recipients currently have to save and reattach manually (once egress exists), losing context and creating avoidable copies; today there is no in-app Forward action at all.
- Confirmed current mechanism: `ShareTargetPickerWired` loads active contacts and writable groups, supports independent contact/group selection sets, and calls one batch coordinator at `lib/features/share/presentation/screens/share_target_picker_wired.dart:38`, `:115`, and `:315`.
- Confirmed destination-group policy: `_isWritableGroupTarget` rejects archived/dissolved groups, rejects non-admin announcement destinations, requires a current group key, and requires active membership at `lib/features/share/presentation/screens/share_target_picker_wired.dart:256`; `_resolveSelectedTargetsForDelivery` re-loads and revalidates the group at send time at `:391`.
- Confirmed caption mechanism: the picker initializes `_captionController` from `ShareIntent.text` at `lib/features/share/presentation/screens/share_target_picker_wired.dart:107` and builds a trimmed copy at `:465`.
- Confirmed per-target delivery: `DefaultShareBatchDeliveryCoordinator.deliver` processes source media once, then iterates targets at `lib/features/share/application/share_batch_delivery_coordinator.dart:163`; `_sendToContact` mints a new attachment ID and calls encrypted `uploadMedia` per contact at `:279`; `_sendToGroup` mints a new attachment ID, loads destination members as `allowedPeers`, uploads, and calls `sendGroupMessage` at `:382`.
- Confirmed source gap: `GroupConversationScreen` and `FullScreenImageViewer` have no Forward callback/action (`lib/features/groups/presentation/screens/group_conversation_screen.dart:41`; `lib/shared/widgets/media/full_screen_image_viewer.dart:19`). `ShareIntent` represents external input only and carries text/file paths, with no source message policy at `lib/core/services/share_intent_model.dart:1`.
- Confirmed local-owner gap: HEAD attachment repository/helpers resolve by untyped `message_id`; revised plan 228 requires `MediaOwnerLane.group` for announcement source reads, `direct` for contact-destination writes, and `group` for group/announcement-destination writes. Direct/group parent IDs can collide and `unresolved` must remain excluded.
- Confirmed authorization backstops: Flutter refuses non-admin announcement sends before network at `lib/features/groups/application/send_group_message_use_case.dart:809`; Go rejects a non-admin `group_message` at `go-mknoon/node/pubsub.go:1605` and `:1963`.
- Existing coverage: `test/features/share/application/share_batch_delivery_coordinator_test.dart::processes shared media once before fanout across target kinds` covers bounded preprocessing; its media-encryption tests cover encrypted contact upload; `test/features/groups/integration/announcement_new_reader_onboarding_test.dart` proves a reader's text/image/video/voice send attempts are unauthorized with no `group:publish` increase.
- Missing coverage: no group-owner source-to-`ShareIntent` adapter, no announcement reader Forward UI, no caption-mode contract, no explicit blocked-contact filter, no destination direct/group owner handoff, no proof that owner stays out of provenance/wire, no source-announcement-vs-destination event discriminator, and no target-partial-failure retry test for this entry path.
- Refuted findings: this feature does not require a new libp2p protocol, relay endpoint, or group encryption primitive. Existing share and group send paths already cross those boundaries.
- Unresolved findings: N/A — direct marker/provenance ownership is fixed by plan 232 and group marker/wire ownership by plan 236; this plan supplies their accepted inputs but owns neither schema/wire contract.
- Affected production, test, and gate files: announcement message/viewer actions, a group-owner `AnnouncementMediaForwardRequest` resolver into `ShareIntent`, `ShareTargetPickerWired` source-policy inputs, plan-232/236 destination adapters in `DefaultShareBatchDeliveryCoordinator`, announcement/share owner-boundary tests, and `GROUP_TESTS` registration.

## Scope Contract And Guard

In scope:
- Add Forward to eligible incoming announcement image/video actions. Eligibility requires a persisted incoming non-system group message, a `MediaOwnerLane.group` attachment with a displayable verified local file, and lifecycle policy `canForward == true` when plan 242 metadata is present. Same-ID direct and unresolved rows never qualify.
- Convert selected group-owned attachments into an announcement-scoped local forward request containing source group/message/attachment identities, resolved file paths, and one caption mode: keep, remove, or edit. Build a `ShareIntent` only after owner-aware re-load/validation; do not serialize the local owner or source identities into provenance/wire.
- Reuse `ShareTargetPickerWired` search/multi-select UI. Allowed contacts are active and unblocked. Allowed groups remain exactly `_isWritableGroupTarget`: active membership/key, not archived/dissolved, and admin role for announcement destinations.
- Revalidate every selected target immediately before delivery. Keep failed targets selected and report sent/queued/failed per target, matching the existing batch result behavior.
- Process media once for sizing/compression but mint a fresh outgoing message/attachment ID and run the destination upload/encryption path separately for each target. Never reuse another target's media key/nonce or an incoming attachment ID as an outgoing blob ID.
- Reuse plan 236's `GroupMediaForwardRequest` and optional encrypted `isForwarded` field for group destinations. Forwarded metadata contains only the boolean marker; it does not reveal the source group, original sender, message ID, or caption provenance.
- Contact destinations use plan 232's accepted `isForwarded: true` and encrypted-inner provenance slot. Generate an opaque target-scoped operation key for each contact, retain it across failed/queued retry, and never derive it from or serialize the source group, original sender, source message, or attachment identity.
- Destination attachment persistence delegates to the accepted lane owners: plan 232 supplies local `MediaOwnerLane.direct` for contacts; plan 236 supplies local `MediaOwnerLane.group` for chat/announcement groups. There is no `announcement` owner lane, and owner never appears in `ForwardProvenance`, `ShareIntent`, direct/group payloads, outer envelopes, retry wire data, or diagnostics.

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
- Do not put `MediaOwnerLane`, `owner_lane`, or an announcement-owner surrogate into provenance, payloads, envelopes, operation keys, relay metadata, or logs.
- Do not change discussion/chat behavior except through the already-approved plan-236 shared group forwarding contract.

Deferred / accepted difference:
- Direct-message schema/codec/rendering remains owned by plan 232. This adapter must pass its marker and privacy-safe internal provenance inputs but must not edit DB v97 or the direct wire codec.
- Bulk forwarding from the plan-241 library may invoke the same request later, but this plan initially owns one source message's selected image/video attachments.
- Private/protected/view-once denial is finalized by plans 238/242; until those lifecycle states can exist, normal media remains forwardable.

Dependencies:
- `Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md` must land first and supplies DB v96, required local `MediaOwnerLane.direct/group`, unresolved exclusion, owner-aware media APIs, and collision tests.
- `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` must land first and supplies direct `isForwarded`, encrypted-inner provenance, recipient rendering, retry/reopen behavior, and DB v97 `messages.is_forwarded`.
- `Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md` must land first and supplies `GroupMediaForwardRequest`, `GroupMessage.isForwarded`, backward-compatible encrypted payload propagation, and DB v99 `group_messages.is_forwarded`.
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
| TC-240-12 | Source and destination local ownership is exact: announcement source resolves only `group`; contact outputs persist `direct`; group/announcement outputs persist `group`; direct/unresolved source collisions are excluded; owner is absent from provenance/wire | `test/features/share/application/announcement_forward_media_owner_contract_test.dart::announcement forward uses group source direct group destinations and no owner wire field` | application host / recording owner-aware source/destination repositories, literal same-ID collision rows, captured `ShareIntent`, direct/group inner+outer payloads and diagnostics | HEAD compile RED: plan-228 owner contract/announcement adapter absent -> exact owner calls and exclusion pass while every captured serialized surface lacks owner keys/values | use untyped source lookup, pass group owner to contact, invent announcement owner, or serialize owner into provenance/payload -> TC-240-12 red | `flutter test test/features/share/application/announcement_forward_media_owner_contract_test.dart`; AUTO plus `GROUP_TESTS` |

### Test Notes

- TC-240-04 must inspect destination-specific values after the real coordinator loop. A stubbed `sendToContactFn` alone cannot prove per-target ID/encryption behavior.
- TC-240-05 asserts only the boolean marker supported by plan 236. Keys such as `originalSender`, `sourceGroupId`, `sourceMessageId`, and `forwardedFrom` must be absent from decrypted inner payload, retry payload, and emitted event.
- TC-240-07 uses group ID as the shared-result discriminator: target event present and source event absent. Merely asserting one successful result is insufficient.
- TC-240-11 captures the contact call and encrypted-inner payload after the plan-232 codec. The target-scoped operation key must be byte-equal between first attempt/retry for that target, unequal across contacts, and non-equal/non-containing with every source identity fixture.
- TC-240-12 records repository owner arguments separately from serialization. A fake that simply returns prefiltered source media is vacuous; it must fail on missing/wrong owner and include group/direct/unresolved same-ID rows. Owner values must be absent from both encrypted inner and outer wire maps, not merely hidden from UI.
- Contacts and groups can have different delivery outcomes; the picker summary and retained-selection behavior must remain per target.

## Implementation Steps

1. Snapshot `git status --short`; verify plans 228/232/235/236 are accepted and DB v96-v99 owner/model/journal/payload tests are green; add TC-240-01 through TC-240-12 before announcement production edits.
2. Add immutable announcement forward request/caption-mode policy that re-loads source attachments with `MediaOwnerLane.group`, resolves owned paths, and rejects direct/unresolved collisions plus system/outgoing/missing/unverified/lifecycle-denied inputs. Stop-if: adapter would need raw group keys, owner serialization, or a new transport frame.
3. Expose the Forward callback through the shared plan-230 viewer and announcement message action model; open the existing `ShareTargetPickerWired` with the composed `ShareIntent` and forwarding context.
4. Tighten forward target policy for blocked contacts while preserving the existing destination-group checks and send-time revalidation.
5. Thread plan-232 marker/provenance and local direct-owner save into contact delivery; thread plan-236 marker and local group-owner save into group delivery. Keep owner below serialization and do not edit either schema/codec or introduce a third wire contract.
6. Add target-discriminated tests and register the new announcement/share headline suites in `GROUP_TESTS`.
7. Run focused GREEN, the curated `groups` lane gate, exact share/direct dependency sentinels, the Go authorization sentinel, analyzer, and diff hygiene.

## Risks And Blind Spots

- Reusing a processed/uploaded artifact across targets can leak recipient-specific key material -> TC-240-04 locks distinct IDs and encryption metadata.
- Cached picker targets can bypass a demotion/removal -> TC-240-06 forces send-time repo revalidation.
- Source and destination are both group IDs and could be confused -> TC-240-07 asserts destination-present/source-absent commands.
- Forward marker propagation can be lost in offline retry -> TC-240-05 uses both live and replay paths inherited from plan 236.
- Contact forwarding can silently render as an ordinary send or leak/link source identity -> TC-240-11 locks the plan-232 marker and per-target opaque stable key.
- Local owner can cross-read a same-ID row or leak into encrypted/outer provenance -> TC-240-12 locks source/destination owner calls and owner-free serialization.
- Lifecycle / derived-state durability: source and target eligibility are re-loaded on invocation; destination durability remains plan-232 direct retry/reopen and plan-236 group send/replay, with TC-240-11 covering the adapter key across retry.
- Sibling-surface consistency: TC-240-01 uses the one action/capability model shared by bubble and viewer.
- Destructive-action side effects: N/A — forwarding does not delete or alter source state; TC-240-03/07/08 assert preservation.
- Invariant re-verification under new transitions: TC-240-06 rechecks role/key/membership; TC-240-04/12 recheck destination material and local owner per send.

## Gate Cadence

- Individual plan closure runs TC-240 focused tests, exact plan-232/236 and shared-picker dependency sentinels, the curated `groups` lane gate, and the Go authorization sentinel below.
- Do not run `host-all`, `feature-host-all`, or `core-host-all` for Plan 240 closure; none adds causal coverage beyond those selected commands.
- Run full `host-all` once after the forwarding/migration wave is complete, and once again at final media-rollout closure.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal RED before announcement production edits; expect non-zero because Forward action/request is absent
flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/application/announcement_media_forward_request_test.dart test/features/groups/presentation/announcement_received_media_forwarding_test.dart test/features/groups/integration/announcement_received_media_forwarding_test.dart test/features/groups/integration/announcement_media_forward_marker_test.dart test/features/share/presentation/announcement_forward_target_policy_test.dart test/features/share/application/announcement_forward_batch_delivery_test.dart test/features/share/application/announcement_forward_contact_marker_test.dart test/features/share/application/announcement_forward_media_owner_contract_test.dart

# Shared picker/coordinator preservation; expect exit 0
flutter test test/features/share/presentation/share_target_picker_wired_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart

# Direct marker/provenance retry preservation from plan 232; expect exit 0
flutter test test/features/conversation/domain/models/message_payload_test.dart --plain-name 'forward marker is legacy-safe inner-only and carries media plus dedup'
flutter test test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_owner_contract_test.dart --plain-name 'direct and group write seams require stable local ownership'

# Affected curated lane gate; expect new files selected and zero failures
./scripts/run_test_gates.sh groups

# Go publisher authorization remains unchanged; expect package ok
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish' -count=1)

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-240-01/03 fail because no Forward action/request exists; TC-240-04/05/07/11/12 fail on missing forwarding, marker and local-owner integration.
- Green sentinel: TC-240-09 and TC-240-10 stay green; existing share coordinator/picker suites stay green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: no simulator/device is required because real group crypto/wire closure belongs to plan 236 and no wire contract changes here. Go commands must pin 1.25.0.
- Scope drift: new protocol fields beyond plans 232/236, owner on wire/provenance, a third announcement owner, direct/group schema edits, source-announcement publication, or discussion behavior changes block completion.

- [x] Every behavior has a named test or justified inherited proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Plan 232 DB v97 direct marker/retry gates and plan 236 DB v99 group live/replay marker gates are green before adapter acceptance.
- [x] Plan 228 DB v96 owner contract proves group-only source, direct/group destinations, unresolved exclusion and owner-free wire/provenance.
- [x] Per-target encryption/ID and source-absent event discrimination pass.
- [x] New tests are registered in `GROUP_TESTS` and AUTO feature discovery.
- [x] Go publisher sentinels, the curated `groups` gate, and exact share/direct dependency sentinels pass.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'`.
- Preservation command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish' -count=1)`.
- Manual registration: add the eight new announcement/share forwarding test files to `GROUP_TESTS`; AUTO feature glob also discovers them.
- Migration: none in this plan; reuse plan 232 DB v97 `messages.is_forwarded` and plan 236 DB v99 `group_messages.is_forwarded`. Do not allocate another version.
- Boundary closure: host announcement adapter; plan 232 owns direct SQLCipher/inner-payload/retry closure and plan 236 owns real group crypto/live/replay closure.
- Unresolved evidence: none. Execution order is the only prerequisite: plans 232 and 236 before 240.

## Execution Progress

- `2026-07-10T23:49:00+02:00` — Phase: exact B1-B9 command ledger, `pending_triage`. Files inspected: none beyond already-green focused artifacts. Last completed command: exact-command wrapper exited 1 before running tests due to a shell-only unmatched `}` (`/tmp/plan240-fix1/exact-b1-b9-final.log`). Current evidence: full eight-file focused command already passes 10 tests (`/tmp/plan240-fix1/focused-eight-final.log`). Decision: `environment/tooling-related`, no code implication. Next: rerun the same ten exact commands in a syntactically valid sequential shell.
- `2026-07-10T23:57:00+02:00` — Phase: final curated `groups` gate, `pending_triage`. Files inspected: none after the gate exit. Last completed command: `./scripts/run_test_gates.sh groups` exited 1 (`/tmp/plan240-fix1/groups-gate-final.log`). Current evidence: exact B1-B9, shared picker/coordinator, Plan-232, and Plan-236 focused preservation all passed before this gate. Decision: classification pending focused log inspection; no code changes authorized until the failing gate slice is identified and reproduced. Next: inspect the gate summary, run the smallest named failing command, classify session-caused versus pre-existing/environment, then correct only if attributable.
- `2026-07-11T00:01:00+02:00` — Phase: curated gate failure triage resolved. Files inspected: `group_conversation_wired_test.dart:9375` and gate/focused logs; no code touched. Last completed command: exact failing plain-name test exited 0 (`/tmp/plan240-fix1/groups-gate-failure-focused.log`). Current evidence: the gate's sole failure was an unrelated upload-cancel timing expectation under broad parallel load; it passes in isolation and no Plan-240 diff touches that test or upload-cancel seam. Decision: `flaky`, unrelated-but-required; rerun the unchanged canonical gate once for resolved final evidence. Next: rerun `./scripts/run_test_gates.sh groups`; do not change production for the non-reproducing failure.
- `2026-07-11T00:12:00+02:00` — Phase: Executor fix-pass handoff persisted. Files inspected/touched: five Plan-240 app owners, eight TC files, bounded harness/fake, gate registration, plan result. Last completed command: Graphify affected plus source verification exited 0 (`/tmp/plan240-fix1/graphify-affected-final.log`); preceding final groups rerun passed 1,888 Flutter tests plus Go bridge/node. Current evidence: B1-B9 have causal proof, mutation re-red/restored GREEN, analyzer stays at the 1,626 legacy baseline, and diff hygiene is clean. Decision: coherent attributable Executor result; no concrete blocker, no Graphify refresh in Executor. Next: root controller spawns a fresh read-only QA recheck; controller refreshes Graphify once only after QA has no blockers.
- `2026-07-11T00:45:00+02:00` — Phase: independent QA fix-pass 1 recheck. Files inspected: post-fix tracked delta, all ten Plan-240 untracked files, owner-enforcing in-memory fake, current production seams, and every `/tmp/plan240-fix1` artifact. Last completed command: hash/diff/artifact and targeted source verification; no test rerun was needed because the focused, preservation, analyzer, and unchanged broad-gate-rerun artifacts were internally consistent. Current evidence: B1-B9 resolve against their required dispositions; no blocking finding remains; one optional dead-helper cleanup is N1. Decision: QA `pass`. Next: controller performs the one final incremental Graphify refresh, persists the final verdict, and stops.
- `2026-07-11` — Phase: controller finalization. Files inspected/touched: accepted Plan-240 app/test diff, QA recheck, architecture graph outputs, and final plan result. Last completed command: `./graphify-arch/refresh_arch_graph.sh --incremental` exited 0. Current evidence: B1-B9 resolved, independent QA passed, all required evidence is durable, and the architecture graph is refreshed exactly once after QA acceptance. Decision: `accepted`; zero blocking issues. Next: stop and return the persisted verdict.

## Orchestrator Preflight Contract

- **Source of truth and precedence:** repository instructions and current `scripts/run_test_gates.sh`; current source/tests where they disprove stale line references; then this plan as the active behavior/scope contract.
- **Invocation topology:** root controller -> fresh isolated Executor -> fresh independent read-only QA Reviewer; roles never overlap. Fix passes, if QA requires them, use a fresh Executor and a fresh QA pass, with a maximum of three fix passes.
- **Exact tracked worktree baseline:** `e54f8ef11cbaf33167b0194b33b8cfba4fb8cbc4` from `git stash create`; the working tree was not stashed or altered. Diff this object against the later worktree for attributable tracked Plan 240 changes. The eight TC-240 paths were absent; unrelated untracked Plan 237/253/254 and Graphify files remain user-owned.
- **Scope:** add eligible incoming announcement image/video Forward entry; build an immutable announcement-scoped request with keep/remove/edit caption policy and owner-aware revalidation; reuse the existing multi-target picker and destination delivery; filter blocked contacts; allow only currently writable groups including admin-owned announcements; retain failed-only retries; preserve per-target fresh encryption/IDs, direct/group local owners, and source-free forwarded metadata.
- **Acceptance bar:** TC-240-01 through TC-240-12 exist and pass causally; new tests are registered in `GROUP_TESTS`; exact dependency sentinels, curated `groups`, Go authorization, analyzer non-widening, diff hygiene, scope guard, reverse-impact inspection, independent QA, and one final incremental Graphify refresh all resolve.
- **Production owner files:** `lib/features/groups/application/group_media_forward_intent.dart`; `lib/features/groups/application/group_media_forward_policy.dart` and/or one new announcement-specific application file; `lib/features/groups/presentation/screens/group_conversation_wired.dart`; only if current typed wiring requires it, `lib/features/groups/presentation/screens/group_conversation_screen.dart` or shared viewer action files; `lib/features/share/presentation/screens/share_target_picker_wired.dart`; `lib/features/share/application/share_batch_delivery_coordinator.dart`; `scripts/run_test_gates.sh`.
- **Regressions first:** create the eight exact files named in the Acceptance Gates, covering all twelve TC rows. Observe the exact TC-240-01 RED before Plan 240 production edits. Existing plan-236 and share tests remain preservation sentinels.
- **Required direct tests:** the focused eight-file GREEN command; shared picker/coordinator command; exact direct payload marker test; forwarded-media retry roundtrip; exact media owner contract; plan-236 `GMF-08` listener test; group messaging smoke. No additional direct suite is implicitly required.
- **Required named gates:** `./scripts/run_test_gates.sh groups`; pinned Go 1.25 authorization command; `flutter analyze`; `git diff --check`. Per repo cadence, do not run `host-all`, `feature-host-all`, or `core-host-all` for this plan.
- **Known-failure interpretation:** analyzer acceptance is no new diagnostics, not an undocumented blanket waiver. Any nonzero analyzer run requires a current baseline comparison proving no session-caused widening. All other required command failures are blocking unless triaged and explicitly allowed by this plan/repo.
- **Done criteria:** every checklist item in `Execution Interpretation And Done Criteria` resolves; source announcement remains read-only; owner/source identities stay off provenance and wire; IDs/crypto are destination-specific; retry and send-time authorization semantics hold; no Plan 240 schema, Go transport, encryption, or new owner-lane change lands.
- **Non-goals and scope guard:** no migration; no direct/group codec or schema edits; no Go framing, validator, topic, relay, retry-frame, recipient, or encryption change; no source-announcement publication; no discussion behavior change outside the accepted plan-236 forwarding seam; no Plan 241 bulk flow or Plan 238/242 lifecycle implementation.
- **Scoped pre-existing tracked changes to preserve:** Plan 237 changes in `group_received_media_actions.dart`, `group_conversation_wired.dart`, group info/repositories, and group library tests/files; Plan 253 changes in `share_batch_delivery_coordinator.dart`, `share_target_picker_wired.dart`, picker screen/tests, upload progress, and gate scripts; unrelated database/main/conversation/doc/Graphify edits. Only the delta after the baseline object is attributable to this execution.
- **Graph Grounding Snapshot:** prior exact query anchored `GROUP_TESTS`, `group_received_media_actions.dart`, and `DefaultShareBatchDeliveryCoordinator`; `confidence=anchored`; graph freshness reported stale for the already-dirty coordinator. Do not repeat broad grounding. After the coherent scoped diff, run `tdd_context.py affected` for actual changed app files and verify surfaced callers/tests in source.

## Execution Result

- **Final verdict:** `accepted`.
- **Invocation topology:** root controller -> isolated Executor materialization retry -> independent QA -> fresh Executor fix pass 1 -> fresh independent QA recheck -> controller finalization. `fix_passes=1`; `materialization_retries=1`.
- **Independent QA used:** yes; fix-pass-1 recheck passed with zero blockers.
- **Local sequential fallback used:** no.
- **Tracked baseline:** `e54f8ef11cbaf33167b0194b33b8cfba4fb8cbc4`; accepted post-fix tracked snapshot before QA-only doc edits: `790572c70a6aa68e068119271cfee05eb92cd126`.
- **Files changed:** added the announcement request; updated group forwarding policy, wired preview route, share picker/coordinator, and group gate registration; added the bounded test harness and unresolved-owner test-fixture seam. Pre-existing Plan 237/253 changes were preserved and excluded from attribution.
- **Tests added/updated:** all eight named TC-240 files are causal and registered in `GROUP_TESTS`; Plan-236 policy/flow/boundary expectations were updated only for the accepted admin-announcement widening.
- **Blocking issues remaining:** none.
- **Non-blocking follow-ups deferred:** N1 optional removal/relocation of production-visible test conveniences; no behavior, privacy, reliability, or closure impact.

### QA blocker dispositions

- **B1 resolved:** the real reader announcement wired screen opens the existing picker; a fresh group-owner lookup resolves the preview path, and the test asserts preview/caption plus absent compose/reply/quote controls.
- **B2 resolved:** exact picker widgets assert active/blocked contacts, chat/admin/reader/QA/source groups, then mutate contact block and announcement role after selection; only the still-valid chat reaches the coordinator.
- **B3 resolved:** keep/remove/edit flow through `AnnouncementMediaForwardRequest` into real coordinator/contact persistence; source parent, attachment map, and bytes are reread unchanged.
- **B4 resolved:** real coordinator contact+group fanout preprocesses once and produces distinct message/blob/key/nonce/owner rows.
- **B5 resolved:** real group send captures live publish, durable inbox/replay plaintext, persisted marker, and source-free maps.
- **B6 resolved:** exact A-to-B command-log test proves B-only group commands, source-target rejection, and unchanged source rows/bytes.
- **B7 resolved:** exact sent/queued/failed batch result is fed into retained picker state and the retry invokes only the failed contact; sent, queued, and source keys are absent.
- **B8 resolved:** real two-contact coordinator makes contact two fail upload then retry; marker/encrypted-inner/log, distinct opaque target keys, retry-stable failed-target key, fresh retry blob/key/nonce, and source absence are asserted. Removing peer scope made this real test red, then restoration returned GREEN.
- **B9 resolved:** owner-recording source/destination repository captures group source and direct/group saves while same-parent direct/unresolved collisions are excluded; direct/group inner, outer, retry, and diagnostic maps are recursively checked for owner/source fields.

### Evidence ledger

| Command (cwd: repo root unless noted) | Result / classification | Artifact |
|---|---|---|
| exact eight-file TC-240 focused command | exit 0, 10 tests; `passed` | `/tmp/plan240-fix1/focused-eight-final.log` |
| ten exact B1-B9 file/plain-name commands | aggregate exit 0; `passed` | terminal session; individual final artifact above plus named logs below |
| real-boundary peer-scope mutation; restored TC-240-11 rerun | expected nonzero, then exit 0; `passed` | `/tmp/plan240-fix1/mutation-peer-scope-real-boundary-red.log`, `/tmp/plan240-fix1/contact-marker-post-mutation-green.log` |
| shared picker/coordinator command | exit 0, 34 tests; `passed` | `/tmp/plan240-fix1/shared-picker-coordinator-final.log` |
| Plan-236 policy/flow/boundary/group smoke command | exit 0, 95 tests; `passed` | `/tmp/plan240-fix1/plan236-preservation-final.log` |
| current GMF-08 exact plain-name | exit 0; `passed` | `/tmp/plan240-fix1/gmf08-final.log` |
| Plan-232 exact marker, retry, and owner commands | each exit 0; `passed` | `/tmp/plan240-fix1/direct-marker-final.log`, `/tmp/plan240-fix1/direct-retry-final.log`, `/tmp/plan240-fix1/media-owner-final.log` |
| first `./scripts/run_test_gates.sh groups`; exact failed upload-cancel test | gate exit 1; focused exit 0; `flaky` | `/tmp/plan240-fix1/groups-gate-final.log`, `/tmp/plan240-fix1/groups-gate-failure-focused.log` |
| unchanged `./scripts/run_test_gates.sh groups` rerun | exit 0, 1,888 Flutter tests plus Go bridge/node; `passed` | `/tmp/plan240-fix1/groups-gate-rerun-final.log` |
| pinned Go authorization | prior exit 0 reused; no Go/group authorization/bridge diff from baseline; `passed` | `/tmp/plan240/go-authorization.log`, `/tmp/plan240-fix1/go-authorization-reuse-scope.txt` |
| scoped `flutter analyze` | exit 1 only for the same four legacy infos in the large wired file; no new/test diagnostics; `accepted_known_failure` | `/tmp/plan240-fix1/scoped-analyze-final.log` |
| full `flutter analyze` | exit 1, exactly 1,626 legacy diagnostics (same recorded baseline); `accepted_known_failure` | `/tmp/plan240-fix1/flutter-analyze-final.log` |
| `git diff --check` | exit 0; `passed` | `/tmp/plan240-fix1/git-diff-check-final.log` |
| Graphify `affected` on five app files plus targeted source verification | exit 0; `passed` | `/tmp/plan240-fix1/graphify-affected-final.log`, `/tmp/plan240-fix1/graphify-source-verification-final.log` |
| eight `GROUP_TESTS` registration lookups | eight exact matches; `passed` | `/tmp/plan240-fix1/gate-registration-final.log` |
| `./graphify-arch/refresh_arch_graph.sh --incremental` | exit 0 after independent QA acceptance; `passed` | controller console output |

### Failure triage, attribution, and remaining uncertainty

- Session-caused harness issues (MIME fixture, wired async settle, inbox-vs-live capture) were corrected only after `pending_triage`; final focused and broad evidence passes.
- The first broad gate's sole upload-cancel timing failure is unrelated to Plan 240, passed by exact name, and the unchanged canonical rerun passed. No production change was made for it.
- Plan 253 exclusion remains exact: this fix pass did not edit `share_batch_delivery_coordinator_test.dart`, picker-screen progress behavior, or Plan-253 files. The temporary peer-scope mutation was restored byte-for-byte before final evidence. Existing Plan-253 coordinator/picker work was preserved and is exercised by the 34-test shared suite and final groups gate.
- No migration, codec/schema, Go transport, encryption primitive, source-announcement publication, third owner lane, or new retry framework changed. The raw unresolved-owner insertion exists only in the in-memory test fake.
- **QA findings and dispositions:** initial B1-B9 were fixed in one bounded pass and independently rechecked as resolved; N1 is the only optional follow-up.
- **Safety conclusion:** the source announcement remains read-only; owner/source identities remain local and absent from provenance/wire; target authorization is reloaded at send time; destination IDs/crypto are fresh; exact retries, preservation sentinels, curated groups, analyzer non-widening, diff hygiene, impact review, and final graph refresh all resolve. The session is safe to consider complete.

## Independent QA Review — Initial Pass

- **Result:** blockers; fresh Executor fix pass required. No production or test code was edited by QA.
- **Snapshot/attribution:** the nine Plan-240 untracked source/test hashes match the Executor handoff; the scoped tracked files are unchanged from post-Executor snapshot `74f9027b46e66bc06004b31519712c02f229c81d`. Baseline diffs attribute the Plan-240 picker/coordinator/policy/gate hunks cleanly. The seven-line `share_batch_delivery_coordinator_test.dart` delta remains attributable to Plan 253 and outside this review.
- **Evidence accepted:** final focused/shared/groups/Go/GMF-08/group-smoke/direct-marker/direct-retry/owner artifacts have the recorded passing exits; the stale GMF-08 substitution is exact and valid; all changed Dart paths are absent from the final 1,626-diagnostic analyzer output and the scoped analyzer is clean; `git diff --check` is clean; Graphify impact plus QA targeted source verification found the live wired caller and tests; all eight files are in `GROUP_TESTS` and feature AUTO discovery.
- **Counterexample artifact:** exact planned names for TC-240-06/07/08 match no tests and exit 79: `/tmp/plan240/qa-missing-named-tests.log`.

### Blocking findings

- **B1 — high — TC-240-01 does not prove the UI route and the promised picker preview is absent.** `announcement_received_media_forwarding_test.dart:25-47` is a `testWidgets` in name only: it never pumps a widget, invokes Forward, observes a route/request, or checks compose/quote controls. The RED therefore proves only the pure policy change. In production, `group_conversation_wired.dart:4917-4940` opens the picker with a text-only `ShareIntent`, while `share_target_picker_wired.dart:603-609` renders preview paths only from `shareIntent.filePaths`; the announcement media preview promised by TC-240-01 is not supplied. **Required disposition:** implement the safe owner-validated preview handoff and replace this with the promised reader-announcement wired/widget route proof, asserting Forward opens the existing picker with media preview/caption while compose/quote stay absent. **Verify:** `flutter test test/features/groups/presentation/announcement_received_media_forwarding_test.dart --plain-name 'reader opens Forward picker for verified media while announcement compose remains read-only'`.
- **B2 — high — TC-240-02 and TC-240-06 do not exercise the announcement picker or send-time repositories.** `announcement_forward_target_policy_test.dart:30-59` calls two pure policy helpers; it does not build `ShareTargetPickerWired`, enumerate an exact target set, include source exclusion, or mutate a selected announcement/contact before Send. The exact TC-240-06 name is absent. The widened Plan-236 GMF-02 fixture uses a generic discussion-source request and does not cover a blocked contact or demoted announcement target. **Required disposition:** add the two exact announcement-request widget/application tests with active/blocked contacts, chat/admin/reader/QA/source groups, key/member fixtures, and post-selection block/demotion; assert only still-valid targets reach the coordinator. **Verify:** `flutter test test/features/share/presentation/announcement_forward_target_policy_test.dart`.
- **B3 — high — TC-240-03 stops at request getters rather than outgoing caption and source immutability.** `announcement_media_forward_request_test.dart:5-28` checks `composedCaption` strings only. It never builds the outgoing `ShareIntent`, exercises the announcement picker/coordinator caption seam, or re-reads the source message/attachment. **Required disposition:** extend the exact test to prove keep/remove/edit outgoing text through the real announcement seam and unchanged source parent/attachment rows. **Verify:** `flutter test test/features/groups/application/announcement_media_forward_request_test.dart`.
- **B4 — high — TC-240-04 is vacuous for preprocessing, IDs, uploads, and crypto.** `announcement_forward_batch_delivery_test.dart:6-21` hashes two contact IDs and never constructs `DefaultShareBatchDeliveryCoordinator`; it observes no preprocessing count, outgoing message/blob IDs, upload calls, keys, nonces, or group destination. This directly violates the plan note forbidding a helper/stub-only proof. **Required disposition:** implement the named test with the real coordinator loop and upload/encryption capture across contact and group targets; assert preprocessing once and fresh message/blob/key/nonce tuples per target. **Verify:** the exact TC-240-04 plain-name command from the plan.
- **B5 — high — TC-240-05 does not test group marker live/offline/replay or source-free payloads.** `announcement_media_forward_marker_test.dart:6-23` synthesizes `{'isForwarded': operationKey.isNotEmpty}` from the *contact* key helper. It never sends to a group or inspects decrypted inner, retry/inbox, replay, or emitted-event maps. **Required disposition:** adapt the accepted Plan-236 live plus inbox/replay harness for an `AnnouncementMediaForwardRequest`; assert `isForwarded == true` at the group destination and absence of every source identity from inner/retry/event surfaces. **Verify:** `flutter test test/features/groups/integration/announcement_media_forward_marker_test.dart`.
- **B6 — high — TC-240-07 is absent and source-announcement isolation is unproved.** `announcement_received_media_forwarding_test.dart:6-36` only inspects a request object/caption; it records no bridge command and has no test with the plan's exact name. It cannot detect swapping source A into the destination command. **Required disposition:** add the exact command-log integration test using announcement A and destination B; assert B send/publish input exists, every A publish/inbox command is absent, A is not selectable, and source rows/bytes remain unchanged. **Verify:** the exact TC-240-07 plain-name command from the plan.
- **B7 — high — TC-240-08 is absent and failed-only announcement retry is unproved.** The only new assertion is the unused pure helper at `announcement_media_forward_marker_test.dart:25-34`; `retainFailedAnnouncementForwardTargetKeys` has no production caller. Generic picker preservation tests do not prove the announcement source exclusion/result discrimination promised here. **Required disposition:** add the exact named batch/picker test with sent, queued, and failed announcement-forward targets; retry from the retained UI state and assert only failures resend, successful/queued/source targets do not. **Verify:** the exact TC-240-08 plain-name command from the plan.
- **B8 — high — TC-240-11 proves only a hash helper, not marker/payload/retry behavior.** `announcement_forward_contact_marker_test.dart:6-34` never calls the coordinator/contact send codec, captures no `isForwarded`, payload, log, outgoing ID, or crypto metadata, and simulates retry by recomputing a pure function. The mutation proof therefore cannot detect missing coordinator wiring. **Required disposition:** implement the planned real-coordinator two-contact fail-then-retry harness; capture encrypted-inner payload/logs and outgoing media identities; require marker true, per-contact unequal opaque keys, byte-stable failed-target retry key, fresh retry media IDs/crypto, and total source-identity absence. **Verify:** `flutter test test/features/share/application/announcement_forward_contact_marker_test.dart`.
- **B9 — high — TC-240-12 is a constant/helper assertion, not an owner or wire contract.** `announcement_forward_media_owner_contract_test.dart:6-33` calls `sourceOwner`, `announcementForwardDestinationOwner`, and a synthetic diagnostic map. It has no same-ID group/direct/unresolved repository rows, no fail-on-wrong-owner fake, no destination persistence capture, and no direct/group inner/outer/retry/diagnostic payload capture. **Required disposition:** implement the planned owner-aware source/destination harness and serialization captures; prove group-only source qualification, direct/group destination owners, collision/unresolved exclusion, and owner/source absence from every wire/provenance/diagnostic surface. **Verify:** `flutter test test/features/share/application/announcement_forward_media_owner_contract_test.dart`.

### Non-blocking findings

- None. Test-only production helpers (`forTest`, `privacySafeDiagnostic`, `announcementForwardDestinationOwner`, and `retainFailedAnnouncementForwardTargetKeys`) should be removed if the causal replacements make them unnecessary; this cleanup is subordinate to B3/B7/B9 and is not a separate acceptance condition.

## Independent QA Review — Fix Pass 1 Recheck

- **Result:** `pass`; zero blocking findings. QA made no production or test edits and did not refresh Graphify.
- **Identity and attribution:** before this QA-only plan update, the tracked state matched post-fix snapshot `790572c70a6aa68e068119271cfee05eb92cd126`; all ten Plan-240 untracked SHA-256 identities match the Executor handoff. The fix delta from `74f9027b46e66bc06004b31519712c02f229c81d` is confined to the Plan-240 doc, owner-validated preview wiring, the bounded unresolved-owner fake seam, and concurrent Plan-253 doc progress. Plan-253 code/test ownership remains preserved.
- **Artifact audit:** every `/tmp/plan240-fix1` artifact was inspected. The final eight-file run passes all 10 TC-240 tests; shared picker/coordinator passes 34; Plan-236 preservation passes 95; direct marker/retry/owner and GMF-08 pass; the first groups run's sole upload-cancel timing failure passes by exact name and the unchanged canonical groups rerun passes 1,888 Flutter tests plus Go bridge/node. Full analyzer remains exactly 1,626 legacy diagnostics and scoped analysis adds none; diff hygiene, registration, and Graphify impact/source verification are consistent.
- **Reruns:** none. No missing or inconsistent direct proof remained, and the passing unchanged broad-gate rerun was not duplicated.

### Stable blocker dispositions

- **B1 resolved:** `announcement_received_media_forwarding_test.dart` pumps the actual reader `GroupConversationWired`, opens the typed viewer Forward action, reaches `ShareTargetPickerWired`, and asserts the owner-resolved image preview/caption plus absent reply/quote and read-only composer controls. Production performs a fresh group-owner attachment lookup and existence check before constructing preview `filePaths`; dispatch still re-runs the full source gate.
- **B2 resolved:** the two exact picker widget tests enumerate active/blocked contacts and chat/admin-announcement/reader-announcement/QA/source groups, then block and demote selected targets before Send. Only the still-valid chat reaches the coordinator; source exclusion is also enforced again in coordinator delivery.
- **B3 resolved:** keep/remove/edit modes run through `AnnouncementMediaForwardRequest` and the real coordinator/contact persistence seam, yielding exact outgoing text while the source group parent, owner-scoped attachment map, and bytes remain unchanged.
- **B4 resolved:** the real `DefaultShareBatchDeliveryCoordinator` contact+group loop preprocesses once and produces distinct outgoing message IDs, blob/attachment IDs, keys, nonces, and direct/group owner rows.
- **B5 resolved:** the announcement request reaches the real group send seam with `isForwarded == true`; live publish, persisted message, inbox/retry envelope and decrypted plaintext are inspected for the marker and source absence. The green Plan-236 preservation run supplies the inherited replay/event decoding proof.
- **B6 resolved:** the exact source-A/destination-B integration records real group commands, proves destination-B traffic, rejects source A as a target with no A publish/inbox command, and preserves source rows and bytes.
- **B7 resolved:** the exact sent/queued/failed announcement batch test retains and replays only the failed key while excluding sent, queued, and source keys. The green shared picker test `GMF-05 picker retries failed only and leaves queued forward to durable retry` supplies the real retained-UI-state proof on the same unbranched picker result path; B2/B6 supply announcement source exclusion at selection and delivery.
- **B8 resolved:** the real two-contact flow makes the second upload fail then retry, verifies direct `isForwarded` encrypted-inner/log output, unequal target-scoped keys, deterministic failed-target retry identity, fresh retry blob/key/nonce material, and total source absence. Removing peer scope re-reds this test; restoration passes.
- **B9 resolved:** the recording owner repository includes same-parent group/direct/unresolved rows, records group-only source reads and direct/group destination saves, and verifies collision/unresolved exclusion. Captured direct/group inner, outer, retry, and diagnostic surfaces contain neither owner keys nor source identities; the Plan-228 owner sentinel also passes.

### Additional review checks

- Harness assertions exercise real coordinator, picker, repository, upload, crypto, persistence, and command seams where the plan requires them; inherited Plan-232/236 tests cover their owned codec/replay boundaries. No helper-only assertion is used as sole acceptance evidence.
- Preview and dispatch remain owner-scoped; dispatch reloads parent/group/attachment, lifecycle policy, current path, and content hash. Target contact/group repositories are reloaded at send time.
- No migration, transport schema, Go, encryption primitive, source publication, recipient calculation, third owner lane, or retry framework changed. All eight files are registered in `GROUP_TESTS`; the owner fake remains compatible under the full groups gate.
- Graphify impact output was verified against live callers/tests. The final incremental refresh remains controller-owned and was intentionally not run by QA.

### Non-blocking findings

- **N1 — low:** `AnnouncementMediaForwardRequest.forTest`, `sourceOwner`, `privacySafeDiagnostic`, `announcementForwardDestinationOwner`, and `retainFailedAnnouncementForwardTargetKeys` are production-visible test conveniences with no production caller (the latter is used only by TC-240-08). Removing or relocating them would reduce dead API surface, but their behavior is privacy-safe and they do not block Plan 240 acceptance.
