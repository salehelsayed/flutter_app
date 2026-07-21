# 268 - Group Media Keep-In-Chat-Only Composer

Status: execution-ready
Type: Bug
Spec: free-text intent — group-chat media must always use Keep in chat; Protected view, View once, and Set an expiry remain 1:1-only
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-21 20:54 CEST | Evidence Collector | anchored Graphify context; `group_private_media_policy.dart`; `group_conversation_screen.dart`; `group_conversation_wired.dart`; `send_group_message_use_case.dart`; focused group tests and gate arrays | HEAD deliberately exposes the full private-media picker in group and announcement composers even though ordinary already represents Keep in chat | verify the ordinary path and challenge the claimed failure mechanism |
| 2026-07-21 21:00 CEST | Refute pass | attachment add/remove paths; production mounts; ordinary/private wired tests; group MIME policy; direct composer; forward/retry paths | ordinary media itself is GREEN; the confirmed stall is a selected private policy surviving a second attachment, after which the selector disappears and Send silently returns | separate fresh authoring removal from legacy receive/retry compatibility |
| 2026-07-21 21:04 CEST | Planner | causal seams, breaking tests, `GROUP_TESTS`, `ONE_TO_ONE_TESTS`, TDD tier/gate references | remove group/announcement private authoring, force every fresh group composer send to ordinary, and retain existing private-row compatibility | begin with TC-268-01, TC-268-02, and TC-268-09 RED |
| 2026-07-21 21:18 CEST | Blocking sufficiency check + independent challenge | full nine-row contract; legacy payload/viewer/lifecycle/cleanup suites; upload failure restoration; literal gates/registrations | initial legacy-compatibility and failure-re-entry proof gaps were blocking; TC-268-08/09 and exact gates close both, and re-audit found no remaining checklist blocker | hand off execution-ready plan; recommend `$tdd-review` before implementation |
| 2026-07-21 21:38 CEST | `$tdd-review` adversarial worker + main verification | review-profile Graphify context; all composer authoring/state/snapshot seams; production upload-failure projection; obsolete wired private-authoring tests; exact legacy retry bodies and registrations | initial verdict `plan-fixes-required`: UI-only deletion could satisfy the causal suite, TC-268-09's text/quote discriminator was impossible, its fixture skipped the production projection branch, three removed-constructor tests were out of range, and TC-268-04 inferred retry from titles | apply only the five source-backed corrections, then re-run the five lenses and counterexample sweep |
| 2026-07-21 21:40 CEST | Review re-audit | revised nine-row contract and exact commands; ordinary conversion of GPL-03H's unique wired foreground post-upload CAS sentinel | all five lenses clear after retaining GPL-03H as ordinary rather than incorrectly retiring it; no material blocker remains; verdict `ready` | hand off the reviewed execution-ready plan |
| 2026-07-21 22:22 CEST | Critical fix-list audit | anchored Graphify review context; current composer helpers, projection transaction, fake bridge, and gate registrations | kept only compile-completeness, projection-fidelity, oracle, mutation-attribution, and lean-baseline corrections; current `flutter analyze` is clean | execute steps 1-4 as the first compile-complete TDD slice |

## Problem And Evidence

- Behavior to improve: every newly composed, supported media attachment in a
  discussion group or announcement must send as ordinary Keep in chat. The
  group composer must expose no Protected view, View once, or expiry selector;
  those choices remain available only in 1:1 chat.
- Impact: HEAD can put the group composer into a hidden nonordinary state. A
  user can choose a private mode for one visual attachment, add a second item,
  see the selector disappear, and then tap Send with no upload, publication,
  or feedback.
- Confirmed root cause: `_GroupPrivateMediaSelector` is mounted at
  `lib/features/groups/presentation/screens/group_conversation_screen.dart:330-335`
  and maps the full picker vocabulary at `:1444-1518`. Production wires its
  mutable policy at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:2763-2800`
  and `:7859-7867`. `_attemptAddPendingMedia` appends a second item without
  clearing that policy at `:1255-1266`; the one-item eligibility predicate then
  becomes false at
  `lib/features/groups/domain/models/group_private_media_policy.dart:57-67`,
  hiding the selector, while `_onSend` silently returns at
  `group_conversation_wired.dart:2812-2825`.
- Confirmed ordinary mechanism: `GroupPrivateMediaPolicy.ordinary()` is
  standard and unprotected at
  `lib/features/groups/domain/models/group_private_media_policy.dart:103-107`;
  `toWireExtras()` emits no private fields at `:269-277`.
  `sendGroupMessage` already defaults to ordinary at
  `lib/features/groups/application/send_group_message_use_case.dart:1161-1164`,
  and ordinary initial upload bypasses private qualification at `:1092-1109`.
- Existing coverage: the focused command
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage'`
  passed on planning HEAD and proves the ordinary row reaches durable `sent`.
  The focused command
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'group private media sheet commits through real wired action'`
  also passed and confirms that the unwanted group picker is active in the real
  wired surface.
- Missing coverage: no test currently says group/announcement composers have
  no private options, no causal test exercises select-private -> add-second ->
  silent Send, no source contract prevents a UI-only deletion from leaving the
  authoring API/state/snapshot policy alive, no production-projection
  fail->restore->resend test rejects a restored private policy or duplicate
  parent, and the ordinary preservation test does not yet assert absence of all
  four private wire fields.
- Refuted findings: the default ordinary/Keep-in-chat upload path is not broken
  in the host harness; ordinary uploads do not enter private qualification.
  Removing only the visible selector is also insufficient because mutable
  policy currently enters through widget initialization/update and composer
  failure restoration at `group_conversation_wired.dart:789-790`, `:1093-1096`,
  and `:3665-3765`.
- Unresolved findings: the user's exact device sequence and flow events were
  not supplied, so linkage of the observed run to the confirmed two-attachment
  stall is unresolved. This does not block the requested product correction:
  the plan removes every fresh group-private composer state and proves the
  ordinary send boundary. If supported ordinary media still fails after GREEN,
  a group-media reliability follow-up owns capture of the exact
  `GROUP_CONV_FL_*`/`GROUP_SEND_MSG_*` events before further transport changes.
- Affected production, test, and gate files:
  `lib/features/groups/presentation/screens/group_conversation_screen.dart`,
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `test/features/groups/presentation/group_conversation_screen_test.dart`,
  `test/features/groups/presentation/group_conversation_wired_test.dart`,
  `test/features/groups/presentation/group_private_media_viewer_test.dart`,
  `test/features/groups/presentation/announcement_private_media_capabilities_test.dart`,
  `test/features/groups/integration/external_share_group_media_liveness_test.dart`,
  `test/features/groups/integration/group_private_media_cleanup_replay_test.dart`,
  `test/features/groups/application/group_private_media_preupload_boundary_test.dart`,
  `test/features/groups/application/group_private_media_retry_qualification_test.dart`,
  `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart`,
  `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart`,
  `test/features/groups/integration/announcement_private_media_lifecycle_test.dart`,
  `test/features/share/application/share_batch_delivery_coordinator_test.dart`,
  `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart`,
  `test/features/conversation/presentation/screens/conversation_wired_test.dart`,
  and `scripts/run_test_gates.sh` for verified existing registration only.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `91972ddb41168f7f`;
  `stale:scripts/host_git_push.sh`. The stale path is outside this app-owned
  behavior; every load-bearing conclusion above was verified in current source.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "group chat media send defaults to keep in chat while protected view, view once, and expiry options are one-to-one only" --profile tdd --budget 700`
  returned `confidence=broad`; the one permitted refinement was
  `python3 graphify-arch/tdd_context.py query "GroupPrivateMediaPolicy group media composer attachment send keepInChat protected viewOnce expiry policy picker" --profile tdd --budget 700`
  and returned `confidence=anchored`.
- Anchors: `viewOnce` ->
  `lib/features/groups/domain/models/group_private_media_policy.dart:121`;
  `GroupPrivateMediaPolicy` -> policy, send-use-case, group screen, and wired
  screen files named above.
- Surfaced proof/gate files:
  `group_private_media_policy_test.dart`,
  `group_conversation_wired_test.dart`, and the `GROUP_TESTS` registrations in
  `scripts/run_test_gates.sh:348-366,561-592`.
- Graph gaps requiring source search: the compact graph did not identify the
  second-attachment stale-policy transition, the positive group-picker tests,
  production route defaults, or direct-only picker sentinels; targeted current
  source inspection supplied those facts. No device failure trace was present.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Remove the group/announcement composer policy chip and picker wiring while
  leaving the attachment preview and normal ComposeArea intact.
- Make every fresh group composer message use
  `const GroupPrivateMediaPolicy.ordinary()` through optimistic persistence,
  upload, final dispatch, failure restoration, and composer re-entry ->
  TC-268-01/02/03/09.
- Preserve the existing failed-media continuation identity when the production
  upload-retry projection reports a terminal failure: the restored draft must
  replace its original failed parent/attachment on resend, not create a second
  authored row -> TC-268-09.
- Cover discussion groups and writable announcements, plus gallery, camera
  photo, and camera video paths that converge through
  `_attemptAddPendingMedia`; preserve the already-ordinary voice and
  forward/share paths.
- Replace tests that positively require group private authoring with the
  keep-in-chat-only production contract.

Must preserve:

- Ordinary group upload/persistence/wire behavior -> TC-268-03.
- Voice recording, external share, and internal forward destinations remain
  ordinary group media with no private wire fields -> TC-268-06.
- Existing private group/announcement rows remain decodable, viewable,
  cleanable, and exactly retryable without being relabeled ordinary ->
  TC-268-04/08.
- The 1:1 composer retains Keep in chat, Protected view, View once, and the
  exact 1-hour/1-day/7-day expiry choices -> TC-268-05.
- Announcement read-only and current-admin send authorization remains
  unchanged; only fresh private-mode selection is removed -> TC-268-01/07.

Hard `Do not`:

- Do not delete the v101 policy columns, `GroupPrivateMediaPolicy`, receive
  parser, lifecycle engine, viewer, cleanup, notification redaction, or native
  protection used by already-stored/incoming private rows.
- Do not globally reject nonordinary input in `sendGroupMessage`, disable
  `productionGroupPrivateMediaAvailability`, or weaken exact legacy retry
  qualification; those changes would strand durable private rows.
- Do not reinterpret an existing protected/view-once/expiring group row as
  ordinary, leak its bytes into ordinary actions, or mint a replacement row.
- Do not modify the 1:1 `ComposeArea`, shared private picker, direct policy, Go,
  relay, native platform code, database schema, or wire vocabulary.

Deferred / accepted difference:

- Group document attachments remain unsupported: the current attach sheet has
  gallery/camera/record-video only and `GroupMediaMimePolicy` admits
  image/video/audio MIME types. Adding a document picker or widening MIME policy
  needs a separate product/security plan; owner: future group-attachment work.
- Exact device-only failure attribution remains a follow-up only if the
  supported ordinary-media contract is still broken after this plan's GREEN;
  owner: group-media reliability follow-up with captured flow events.

Dependencies:

- The existing ordinary policy/wire contract in
  `group_private_media_policy.dart` and the existing durable ordinary upload
  path in `group_conversation_wired.dart`/`send_group_message_use_case.dart`.
- The legacy private receive/retry stack remains a compatibility dependency,
  not an authoring dependency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-268-01 | A staged visual in either an active discussion group or writable announcement shows no group private selector and sends as ordinary Keep in chat; the group composer exposes no hidden private-authoring API, mutable state, or snapshot field | `test/features/groups/presentation/group_conversation_wired_test.dart::P268 production chat and announcement media send ordinary without a private selector`; `::P268 group composer source has no private authoring API or mutable policy state` | widget host plus source contract / `WidgetTester`, fake picker/bridge/media manager, in-memory group/identity/message repositories, one valid image per group type; exact source slices for the screen authoring API and wired constructor/state/snapshot | Causal RED on HEAD: the selector is visible and the source contract finds the authoring props/selector plus `widget.privateMediaPolicy`, `_privateMediaPolicy`, and the snapshot policy -> GREEN: attachment preview and Send remain, selector/sheet/options and those authoring-only symbols are absent, while each sent row plus every emitted publish/reliable/replay map is ordinary with every private wire key absent | restore the selector, authoring props, mutable constructor/state, or snapshot policy -> TC-268-01 source contract red; pass nonordinary policy at either group-type send boundary -> TC-268-01 runtime/wire oracle red | exact two focused commands in Acceptance Gates; existing `GROUP_TESTS` entry at `scripts/run_test_gates.sh:366`, AUTO feature-host glob |
| TC-268-02 | Adding a second supported attachment can never leave a hidden private mode that stalls Send; the fresh message uploads and persists ordinary | `test/features/groups/presentation/group_conversation_wired_test.dart::P268 second group attachment cannot inherit a hidden private mode or stall send` | widget/host integration / fake picker, bridge, media manager, in-memory repositories, two valid image fixtures | Causal RED on HEAD: commit Protected on the first item, add the second, selector disappears, then `_onSend` makes zero upload/publish calls -> GREEN: both attachments upload, one parent reaches `sent`, policy is ordinary, and all four private wire keys are absent | pass a nonordinary policy at the optimistic or final send boundary -> TC-268-02 wire oracle red; restoring only a dormant authoring prop/state/snapshot field is owned by TC-268-01's source contract | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P268 second group attachment cannot inherit a hidden private mode or stall send'`; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-268-03 | A normal single group attachment retains the existing durable Keep-in-chat send behavior and cannot replace a parent mutated while its wired foreground upload is in flight | `test/features/groups/presentation/group_conversation_wired_test.dart::ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage`; convert `::GPL-03H wired private upload cannot replace a parent drifted while upload is in flight` to `::P268 ordinary wired upload cannot replace a parent drifted while upload is in flight` | GREEN sentinels / fake bridge and media manager with in-memory message/media repositories; gated uploader and concurrent durable-parent mutation | GREEN sentinel on HEAD: parent pre-persists, upload completes, final row is `sent`; extend it with ordinary saved-policy and emitted reliable/publish/replay wire-absence assertions. Adapted GPL-03H mutates the ordinary parent during upload and the exact post-upload CAS prevents attachment replacement and every reliable/publish/inbox call | pass a private policy into the optimistic/final call or emit policy extras for ordinary -> successful TC-268-03 sentinel red; delete the post-upload exact parent/attachment check at `group_conversation_wired.dart:2523-2548` -> converted CAS sentinel red | exact two focused commands in Acceptance Gates; existing `GROUP_TESTS`, AUTO feature-host glob |
| TC-268-04 | Already-authored discussion and announcement private rows keep strict send/live/offline decoding and execute their exact initial-upload, incomplete-upload, failed-message, and inbox retry qualifications; this plan changes fresh composer authority only | `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart::GPL-04 private policy roundtrips send retry live and offline without local lifecycle leakage`; `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart::APL-03 current admin policy matches send live offline retry qualification and legacy paths`; `test/features/groups/application/group_private_media_preupload_boundary_test.dart::GPL-03A private parent is durable and requalified immediately before initial and retry upload`; `test/features/groups/application/group_private_media_retry_qualification_test.dart::GPL-03G private failed retry cannot replace a parent drifted during attachment await`; `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart::APL-02R announcement private inbox retry requalifies the current admin role` | GREEN sentinel / host integration with fake bridge and in-memory group/message/media repositories for both group types, including revoked roles, changed durable parents, and an attachment-read race | GREEN sentinel on HEAD -> remains GREEN after composer removal; payload fixtures retain exact encrypted-inner policy and live/offline decode, while the three retry sentinels execute allowed/denied retry boundaries and preserve one exact durable parent without local lifecycle leakage | delete either legacy policy codec/authorization path, disable a private retry globally, bypass immediate requalification, replace a drifted parent, or relabel incoming private rows ordinary -> TC-268-04 red | exact five focused commands in Acceptance Gates; existing `GROUP_TESTS` entries at `scripts/run_test_gates.sh:566,568-569,588`, AUTO feature-host glob |
| TC-268-05 | Protected view, View once, and exact expiry choices remain available and sendable in 1:1 only | `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::sheet uses consequence-led labels, title, and duration chips`; `::view-once and exact disappearing durations emit typed policy`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::selected private policy reaches the injected send seam` | GREEN sentinel / direct ComposeArea widget and wired 1:1 fake media/send fixtures | GREEN sentinel on HEAD -> remains GREEN; direct picker still exposes all modes/durations and selected Protected reaches the direct send seam | remove/change direct selector modes or normalize the direct policy to ordinary -> TC-268-05 red | exact three focused `flutter test ... --plain-name ...` commands in Acceptance Gates; `conversation_wired_test.dart` is in `ONE_TO_ONE_TESTS` at `scripts/run_test_gates.sh:83`; both files AUTO feature-host glob |
| TC-268-06 | Group voice recording, external image share, and internal media forwarding to a group remain Keep in chat even though they bypass the visual-attachment composer selector | `test/features/groups/presentation/group_conversation_wired_test.dart::successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion`; `test/features/groups/integration/external_share_group_media_liveness_test.dart::external image share to an open group conversation surfaces the message with its thumbnail while mounted`; `test/features/share/application/share_batch_delivery_coordinator_test.dart::GMF-03 group origin forward reencrypts independently and keeps provenance local` | GREEN sentinel / widget and application host integration with fake recorder, bridge, P2P/media services, and in-memory repositories | GREEN sentinel on HEAD -> remains GREEN with added assertions that each destination group row is ordinary and its publish/reliable/replay maps omit every private-policy wire key | route any sibling path through mutable group-composer policy, pass a nonordinary policy, or emit private fields for ordinary -> TC-268-06 red | exact three focused commands in Acceptance Gates; existing `GROUP_TESTS` entries at `scripts/run_test_gates.sh:366,516,520`, AUTO feature-host glob |
| TC-268-07 | Announcement authorization stays asymmetric: current admins retain media/voice compose controls while readers cannot compose, attach, record, or send | `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write`; `::announcement admin sees mic button for voice recording`; TC-268-01's writable-announcement send | GREEN sentinel / production wired widget with in-memory announcement roles and fake recorder | GREEN sentinel on HEAD -> remains GREEN; reader has read-only copy and null callbacks/no controls, while admin can stage/send ordinary visual media and start voice recording | weaken `canWrite`, expose any reader callback/control, or remove admin attach/record/send capability -> TC-268-07 red | exact two focused commands in Acceptance Gates plus TC-268-01; existing `GROUP_TESTS` entry at `scripts/run_test_gates.sh:366`, AUTO feature-host glob |
| TC-268-08 | Existing private group/announcement media remains truthfully openable and protected, then lifecycle cleanup removes only exact private artifacts without resurrection | `test/features/groups/presentation/group_private_media_viewer_test.dart::GPL-11 viewer is privacy minimized denies PiP and shows truthful platform copy`; `test/features/groups/presentation/announcement_private_media_capabilities_test.dart::APL-04 reader sees one generic open path without compose thumbnail reactions or egress`; `test/features/groups/integration/group_private_media_cleanup_replay_test.dart::GPL-08 cleanup is scoped durable and replay cannot resurrect private media`; `test/features/groups/integration/announcement_private_media_lifecycle_test.dart::APL-05 announcement view once commits before cleanup and stays consumed after settle` | GREEN sentinel / protected viewer widget plus real-SQLite lifecycle fixtures with exact files, attachment rows, keys, and ordinary/direct siblings | GREEN sentinel on HEAD -> remains GREEN; group viewer is minimized/protected, announcement reader retains one open path, terminal private bytes/rows/keys are removed, placeholders and unrelated siblings survive, and replay cannot resurrect media | remove legacy viewer/open wiring, expose private egress, delete ordinary/direct siblings, skip exact cleanup, or allow terminal replay -> TC-268-08 red | exact four focused commands in Acceptance Gates; existing `GROUP_TESTS` entries at `scripts/run_test_gates.sh:578,582,589,590`, AUTO feature-host glob |
| TC-268-09 | A terminal projected media-upload failure cannot restore hidden private composer state; the media-only draft resends ordinary into the same durable parent, while the existing ordinary text/attachment/quote restoration remains intact | `test/features/groups/presentation/group_conversation_wired_test.dart::P268 projected media failure restores ordinary and resends the same parent`; existing `::ordinary media upload failure persists failed parent state and restores composer and quote` | causal widget/host integration plus GREEN sentinel / fake picker, current group key, projection-enabled terminal-failure repository, two-outcome uploader (first null, second valid attachment), bridge/media manager, one media-only draft; existing in-memory quoted-parent fixture remains separate | Causal RED on HEAD: with no caption/quote, conditionally commit Protected, fail the first upload through the production projection branch, and observe restored private state; current projected restoration also lacks continuation, so resend can mint a second ID -> GREEN: restored media-only draft has no selector/private state, second send reuses the exact parent ID/timestamp, leaves exactly one authored `sent` ordinary row and one finalized attachment, and emits no private wire keys; the separate existing ordinary fixture remains GREEN for text/attachment/quote restoration | restore snapshot private policy or omit projected-terminal continuation tracking; mutate resend to a new ID/timestamp or leave the failed attachment orphaned -> TC-268-09 red | exact two focused commands in Acceptance Gates; existing `GROUP_TESTS` entry at `scripts/run_test_gates.sh:366`, AUTO feature-host glob |

### Test Notes

- TC-268-02 uses one deliberate HEAD discriminator: if the forbidden group
  selector exists, the test commits Protected before adding the second item.
  TC-268-01 independently requires that selector to be absent at GREEN. This
  lets the unchanged TC-268-02 test reach the current silent-return mechanism
  on HEAD and the ordinary two-item send on GREEN without treating selector
  presence as acceptable.
- TC-268-01's source contract closes the UI-only counterexample left by the
  conditional discriminators. It forbids only authoring symbols in exact
  screen/constructor/state/snapshot slices; persisted
  `message.privateMediaPolicy` receive/view/retry references remain explicitly
  allowed. Each forbidden seam is an independent mutation target.
- TC-268-09 deliberately uses a media-only draft for its HEAD discriminator.
  Private eligibility rejects captions and quotes, and both transitions
  already normalize the policy, so combining them could never expose restored
  private state. The existing ordinary text/attachment/quote restoration test
  stays separate and unchanged.
- TC-268-09 uses a `CountingGroupMessageRepository` test subtype that also
  implements `GroupUploadRetryProjectionRepository`, so the existing
  `messageRepo` injection exercises the production interface-discovery path.
  Before returning a terminal result, the fake must persist the target
  attachment as `upload_failed` with its projected retry count and the parent
  as `failed` in the same fake repositories. Inject the helper's `mediaRepo`
  (widget `mediaAttachmentRepo`) and `mediaFileManager`; continuation acceptance
  and replacement require those durable states and dependencies. Its resend
  oracle requires the original parent ID/timestamp, exactly one authored row,
  one finalized replacement
  attachment, and no stale failed attachment; a second successful row is not
  sufficient.
- TC-268-09 must collect both HEAD observations before asserting: capture the
  restored private selector/policy, perform the resend, then gather parent ID,
  timestamp, row, and attachment evidence. An early selector assertion must
  not abort before the missing-continuation failure is exercised.
- TC-268-02 and the successful ordinary half of TC-268-03 inspect the fake
  bridge's raw reliable/publish payloads and decode replay plaintext from the
  `group:inboxStore` envelope's `ciphertext` (the fake `group.encrypt` returns
  its plaintext as ciphertext). They assert every member of
  `GroupPrivateMediaPolicy.wireKeys` is absent from every emitted map; an
  unavailable map is N/A, never inferred. The CAS-drift half of TC-268-03
  instead requires zero reliable/publish/inbox calls.
- TC-268-03 converts GPL-03H rather than deleting it. Its gated foreground
  upload is the only wired proof that a parent drift after upload start cannot
  be overwritten or published; GPL-03A/GPL-03G exercise different initial or
  retry seams. Removing only its private constructor input preserves that
  atomicity for the now-universal ordinary path.
- Gallery images, gallery videos, camera photos, and camera videos all become
  `PendingComposerMedia` and enter `_attemptAddPendingMedia`; the policy/send
  branch has no picker-source or MIME discriminator after that point. TC-268-02
  injects at this common boundary, so four redundant picker-source variants are
  N/A for this policy change; existing picker/processing tests retain source
  fidelity ownership.
- TC-268-06 extends the existing sibling-path tests rather than inventing new
  flows. Each extension asserts the saved group policy and every available
  destination publish/reliable/replay map; unavailable map types are N/A for
  that fixture, not inferred from a different path.
- Production-critical host leg: TC-268-01/02 drive the production wired group
  surface through the real `sendGroupMessage` path into a fake bridge and
  inspect durable rows plus wire maps. This plan makes no real-relay,
  cross-device, or delivery claim, so a device/relay proxy would add no closure
  value.
- Announcement voice uses the same post-authorization record/send seam as the
  discussion voice leg in TC-268-06. TC-268-07 separately proves the role
  discriminator (admin present, reader absent), and TC-268-01 proves an
  announcement destination persists ordinary media; no group-type-specific
  private-policy branch remains to duplicate.
- TC-268-04 and TC-268-08 divide legacy compatibility deliberately: payload,
  authorization, live/offline decode, and executed retries in TC-268-04;
  viewer/open and exact cleanup/replay behavior in TC-268-08. GPL-04/APL-03 do
  not themselves invoke retry despite their names, so GPL-03A/GPL-03G/APL-02R
  are exact required sentinels. The broad groups gate supplements these named
  tests but does not substitute for them.

## Implementation Steps

1. Snapshot `git status --short` and `flutter analyze`, preserving the unrelated
   existing Docker/iOS changes. Before editing, run the three composer
   sentinels that this plan changes or relies on directly: the ordinary durable
   send, current `GPL-03H wired private upload cannot replace a parent drifted
   while upload is in flight`, and ordinary upload-failure restoration tests.
   Record and reconcile any baseline failure. Then add both TC-268-01 proofs,
   TC-268-02, and the new projected media-only TC-268-09 proof before
   production edits; record all causal failures. Keep the existing ordinary
   text/attachment/quote restoration test under its current name.
2. In `group_conversation_screen.dart`, remove the authoring-only
   `privateMediaComposerEligible`, `privateMediaPolicy`, and
   `onPrivateMediaPolicyChanged` inputs, the composer selector block, shared
   picker import, `_GroupPrivateMediaSelector`, and its conversion helpers.
   Keep all received-private card/viewer code. Stop-if: any removed symbol is
   required to render an existing incoming private row.
3. In `group_conversation_wired.dart`, remove fresh-composer private eligibility,
   selection, mutable state, constructor/update plumbing (including the
   `_resetForGroupChange` assignment), and snapshot restore plumbing. Capture
   `const GroupPrivateMediaPolicy.ordinary()` for every fresh `_onSend`,
   optimistic parent, and final dispatch. When a terminal
   `GroupUploadRetryProjectionRepository` result restores the composer, track
   the same continuation already tracked by fallback restoration so the second
   send reuses the parent ID/timestamp and replaces its failed attachment. Keep
   manual/automatic retries reading the persisted parent policy. Stop-if: the
   change requires relabeling, deleting, or denying an already-durable private
   row; replan that compatibility boundary instead.
4. Replace the obsolete positive group-picker tests at
   `group_conversation_screen_test.dart:275-507` and
   `group_conversation_wired_test.dart:3915-4235` with the Plan-268 production
   contract. Explicitly retire the fresh-private qualification constructor
   tests `GPL-03A-W` at `:4259` and `GPL-03A-R` at `:4331`; exact
   application-level GPL-03A retains their legacy initial/retry qualification
   boundary. Convert `GPL-03H` at `:4399` to TC-268-03's ordinary wired
   foreground-upload drift sentinel by removing its private constructor input
   and asserting ordinary policy; do not delete its gated upload, durable
   mutation, no-publication, and one-row checks. Preserve the adjacent
   `GPL-11V` incoming-viewer source contract and all payload, lifecycle,
   notification, viewer, and announcement-role suites. In the shared screen
   pump helper, remove the three authoring parameters and pass-throughs
   (`privateMediaComposerEligible`, `privateMediaPolicy`, and
   `onPrivateMediaPolicyChanged`) but keep receive-side `privateMediaEnabled`.
   In the wired `buildWidget` helper, remove only `privateMediaPolicy` and its
   pass-through; keep `privateMediaAvailability`, which still gates legacy
   receive/retry behavior. Steps 2-4 are one compile-complete slice: neither
   composer test file is a valid GREEN checkpoint after production removal
   until this helper/test surgery is complete.
5. Extend the ordinary wired sentinel and the three TC-268-06 sibling tests
   with exact saved-policy/wire-absence assertions. Run TC-268-09's separate
   production-projection fail-then-same-parent-resend proof without weakening
   the existing ordinary failure/restoration sentinel. Run all five exact
   TC-268-04 sentinels plus TC-268-05/08 without editing legacy/direct
   production.
6. No harness change is required while the new causal tests stay in
   `group_conversation_wired_test.dart`; it is already a literal `GROUP_TESTS`
   member and AUTO-globbed by feature-host. If execution instead creates a new
   test file, add that exact path to `GROUP_TESTS` and verify selection before
   claiming GREEN.
7. Run focused GREEN, compatibility/preservation commands, the curated groups
   lane, analyzer, and whitespace hygiene. Refresh the architecture graph once
   after the coherent app-owned implementation change.

## Risks And Blind Spots

- A UI-only deletion could leave hidden mutable state or restore it after an
  upload failure -> TC-268-01's source contract rejects the constructor/state/
  snapshot residue, TC-268-02 asserts the multi-attachment send boundary, and
  TC-268-09 asserts projected failure restoration and resend wire output.
- A projection-backed terminal failure could restore the draft but omit
  continuation tracking, so the apparent resend leaves a failed parent and
  mints a second successful row -> TC-268-09 requires the same ID/timestamp,
  one authored row, and replacement rather than orphaned failed attachments.
- Normalizing fresh authoring could accidentally discard GPL-03H with its
  obsolete private constructor input, leaving wired post-upload parent drift
  unguarded -> TC-268-03 converts that test to ordinary and still kills the
  exact parent/attachment CAS mutation.
- Removing the shared group policy model would corrupt or expose already-stored
  private rows -> TC-268-04 keeps codec/retry/live/offline behavior GREEN and
  TC-268-08 keeps viewer/cleanup/replay behavior GREEN.
- Lifecycle / derived-state durability for fresh policy is N/A after the
  mutable group policy and `_GroupComposerSnapshot` field are removed: there
  is no nonordinary fresh derived state to reconstruct. TC-268-02 guards the
  initial multi-attachment boundary; TC-268-09 proves failure re-entry/resend;
  durable legacy private state remains governed by TC-268-04/08.
- Sibling-surface consistency: TC-268-01 covers discussions and announcements;
  TC-268-05 preserves 1:1. Gallery/camera converge through the edited staging
  seam; TC-268-06 proves voice, external share, and internal forward group
  destinations remain ordinary. Documents remain the explicit deferred
  difference.
- Destructive-action side effects are preservation-only: no cleanup code is in
  scope, while TC-268-08 asserts exact private artifact removal plus placeholder
  and unrelated-sibling preservation. Any cleanup diff is scope drift.
- Invariant re-verification under new transitions: TC-268-02 covers selection,
  second attachment, selector disappearance on HEAD, Send, persistence, and
  wire output; TC-268-09 rechecks ordinary and parent identity after the real
  projected-failure restoration/re-entry branch; the separate ordinary
  text/attachment/quote sentinel guards fallback restoration; TC-268-03 covers
  the ordinary one-item path.

## Gate Cadence

- Per-plan closure: TC-268-01/02/09 causal tests, TC-268-03/04/05/06/07/08 exact
  sentinels, both composer widget files, and
  `./scripts/run_test_gates.sh groups`.
  The curated groups lane already owns every changed group test file, so a
  separate `feature-host-all` sweep is not required for this plan.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Group Media Composer
  Contract wave containing Plan 268 is complete, and once at final media
  rollout/release closure.
- Shared tests outside feature/core globs: N/A — every named Dart test is under
  `test/features/**`; the direct 1:1 sentinels run by exact command because they
  are outside the affected groups lane.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated changes.
git status --short
flutter analyze

# Untouched-tree baseline for the composer sentinels changed or relied on by
# this plan. Expect exit 0; stop and reconcile any failure before authoring RED.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'GPL-03H wired private upload cannot replace a parent drifted while upload is in flight'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary media upload failure persists failed parent state and restores composer and quote'

# First causal RED before production edits: expect non-zero because the
# production group/announcement selector is present on HEAD.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 production chat and announcement media send ordinary without a private selector'

# Authoring-boundary RED before production edits: expect non-zero because HEAD
# still exposes screen props/selector and wired constructor/state/snapshot
# policy. This prevents selector-only deletion from satisfying the plan.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 group composer source has no private authoring API or mutable policy state'

# Multi-item causal RED before production edits: expect non-zero because the
# selected private policy survives the second attachment and Send no-ops.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 second group attachment cannot inherit a hidden private mode or stall send'

# Projected-failure causal RED before production edits: use a media-only draft
# so Protected is eligible on HEAD. Expect non-zero because terminal projection
# restores private state and omits same-parent continuation tracking.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 projected media failure restores ordinary and resends the same parent'

# Causal GREEN after the compile-complete steps 2-4 slice: re-run the same four
# contracts; expect exit 0, absent authoring symbols, ordinary durable/wire
# assertions, exact projected-failure parent reuse, and zero failed tests.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 production chat and announcement media send ordinary without a private selector'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 group composer source has no private authoring API or mutable policy state'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 second group attachment cannot inherit a hidden private mode or stall send'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 projected media failure restores ordinary and resends the same parent'

# Existing fallback restoration preservation: expect exit 0; nonempty text,
# one attachment, and quote remain restored after an ordinary upload failure.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary media upload failure persists failed parent state and restores composer and quote'

# Affected composer files: expect exit 0 and zero failed tests.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_screen_test.dart

# Ordinary and legacy-private payload preservation: expect exit 0; the first
# two prove ordinary sent/wire behavior and foreground-upload drift atomicity,
# then discussion and announcement fixtures preserve exact policy plus
# live/offline decoding.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'P268 ordinary wired upload cannot replace a parent drifted while upload is in flight'
flutter test test/features/groups/integration/group_private_media_payload_roundtrip_test.dart \
  --plain-name 'GPL-04 private policy roundtrips send retry live and offline without local lifecycle leakage'
flutter test test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart \
  --plain-name 'APL-03 current admin policy matches send live offline retry qualification and legacy paths'

# Exact legacy-private retry execution: expect exit 0; incomplete uploads,
# failed-message retries, and announcement inbox retries requalify current
# durable policy/roles and never replace a drifted parent.
flutter test test/features/groups/application/group_private_media_preupload_boundary_test.dart \
  --plain-name 'GPL-03A private parent is durable and requalified immediately before initial and retry upload'
flutter test test/features/groups/application/group_private_media_retry_qualification_test.dart \
  --plain-name 'GPL-03G private failed retry cannot replace a parent drifted during attachment await'
flutter test test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart \
  --plain-name 'APL-02R announcement private inbox retry requalifies the current admin role'

# Legacy private viewer and exact cleanup preservation: expect exit 0; private
# open remains protected/minimized, exact terminal artifacts disappear,
# unrelated siblings/placeholders survive, and replay cannot resurrect bytes.
flutter test test/features/groups/presentation/group_private_media_viewer_test.dart \
  --plain-name 'GPL-11 viewer is privacy minimized denies PiP and shows truthful platform copy'
flutter test test/features/groups/presentation/announcement_private_media_capabilities_test.dart \
  --plain-name 'APL-04 reader sees one generic open path without compose thumbnail reactions or egress'
flutter test test/features/groups/integration/group_private_media_cleanup_replay_test.dart \
  --plain-name 'GPL-08 cleanup is scoped durable and replay cannot resurrect private media'
flutter test test/features/groups/integration/announcement_private_media_lifecycle_test.dart \
  --plain-name 'APL-05 announcement view once commits before cleanup and stays consumed after settle'

# Other group-destination media ingress: expect exit 0; saved group rows are
# ordinary and their available publish/reliable/replay maps contain no private keys.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion'
flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart \
  --plain-name 'external image share to an open group conversation surfaces the message with its thumbnail while mounted'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'GMF-03 group origin forward reencrypts independently and keeps provenance local'

# Announcement authorization preservation: expect exit 0; readers expose no
# compose callbacks/controls, while admins retain media/voice authoring.
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'non-admin in announcement group cannot write'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'announcement admin sees mic button for voice recording'

# 1:1-only option preservation: expect exit 0; all direct modes/durations remain
# and a selected direct Protected policy reaches its send seam.
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart \
  --plain-name 'sheet uses consequence-led labels, title, and duration chips'
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart \
  --plain-name 'view-once and exact disappearing durations emit typed policy'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'selected private policy reaches the injected send seam'

# Curated affected lane: expect exit 0, zero failed tests, and both conversation
# files plus every TC-268-04/06/08 group preservation file selected through
# GROUP_TESTS.
./scripts/run_test_gates.sh groups

# Group-only scope guard: expect no direct/shared picker production diff.
git diff --exit-code -- \
  lib/features/conversation \
  lib/shared/widgets/private_media_policy_picker_sheet.dart

# Hygiene: expect no new analyzer issues and no whitespace errors.
flutter analyze
git diff --check

# After the coherent app-owned implementation, refresh once; expect exit 0.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-268-01 finds the current production group selector;
  its source contract also finds the hidden authoring API/state/snapshot;
  TC-268-02 reaches the current hidden-private-policy silent return and records
  no upload/publication; TC-268-09 uses an eligible media-only private draft,
  fails through terminal projection, and exposes both restored private state
  and missing same-parent continuation.
- A causal RED is valid only when the named test loads, runs, and its recorded
  output shows the precommitted behavioral oracle. No-match, load, or compile
  failures do not count as RED.
- Green sentinel: TC-268-03 proves ordinary composer media still sends and its
  wired upload cannot overwrite a concurrently drifted parent;
  TC-268-04 keeps legacy private payload paths and three executed retry paths
  compatible; TC-268-05 keeps every 1:1 option; TC-268-06 keeps
  voice/share/forward group destinations ordinary; TC-268-07 preserves
  announcement roles; TC-268-08 preserves legacy private viewer/cleanup
  behavior. TC-268-09 turns GREEN only after projected restoration resends the
  exact original parent ordinary with no failed attachment orphan, while the
  existing ordinary text/attachment/quote restoration test stays GREEN.
- Pre-existing dirty tree / known failure: planning baseline contains unrelated
  modifications in `docker-ws/deploy_all_phones.sh`,
  `docker-ws/run_fresh_all_phones.sh`, and `info.plist`, plus untracked
  `docker-ws/deploy_iphones_only.sh`,
  `docker-ws/run_fresh_three_phones.sh`, and
  `docker-ws/run_fresh_three_phones_result.txt`. They are user-owned and outside
  Plan 268. The two focused planning probes passed, and the 2026-07-21 review
  baseline reported `flutter analyze` with `No issues found`.
- Environment blocker: none; host-only decision/UI behavior needs no device,
  simulator, SQLCipher, native callback, real crypto, or relay fixture.
- Scope drift: any proposed schema/wire deletion, global private-send denial,
  document-picker work, direct-composer change, or failure that persists with an
  ordinary policy blocks completion and requires a separate diagnosis.

- [ ] Every behavior has a named test or justified proof.
- [ ] Causal RED and focused GREEN are recorded. Two bounded mutation checks
      also re-red: omit projected-terminal continuation tracking -> TC-268-09;
      remove the post-upload parent/attachment CAS -> converted TC-268-03.
- [ ] Preservation and named gates pass with semantic outcomes.
- [ ] Existing AUTO/`GROUP_TESTS` registration is verified; any new-file
      fallback registration is implemented and selected.
- [ ] No migration or device/relay proof is required.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P268 production chat and announcement media send ordinary without a private selector'`.
- UI-only false-fix guard:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'P268 group composer source has no private authoring API or mutable policy state'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'selected private policy reaches the injected send seam'`;
  run TC-268-03, TC-268-04, TC-268-06, and TC-268-08 alongside it for group
  compatibility.
- Manual registration: none while causal tests remain in the already-curated
  `group_conversation_wired_test.dart`; add an exact `GROUP_TESTS` path only if
  execution creates a new file.
- Migration: none.
- Boundary closure: host-only; no simulator/device/relay claim.
- Unresolved evidence: exact user-device flow events are absent. Post-GREEN
  recurrence with an ordinary policy opens a separate group-media reliability
  diagnosis; it does not authorize speculative transport edits in this plan.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
