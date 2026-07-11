# 253 - External Share Immediate Media And Upload Progress

Status: accepted — implementation, physical replay, required feature family, and independent QA complete
Type: Bug
Spec: free-text intent plus user screenshot (2026-07-10)
Classification: implemented / accepted
Closure tier: device (host causal closure plus one availability-bounded physical-phone replay)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-10 17:33 CEST | Evidence Collector / Planner | External-share picker/coordinator, 1:1 send and render paths, in-app optimistic upload/progress path, focused tests, gate arrays, Report 55 closure | Both reported symptoms are confirmed in the post-`ShareIntent` Dart path. The blank first frame is an attachment-free message-change publication race; external share has only a blocking spinner and success/failure SnackBars despite the existing byte-progress widget/stream. | Build the RED/GREEN contract around first-publication media and external batch progress. |
| 2026-07-10 17:59 CEST | Planner / Sufficiency Audit | `tdd-plan` tier matrix/template/checklist, graph snapshot, current dirty diff for Plan 236 group forwarding | Initial host-only closure and carry-forward handling were superseded by the independent review: real Go progress arithmetic needs one physical replay, and Plan 236 must commit first. | Apply the reviewed dependency and device-proof contract. |
| 2026-07-10 | Independent Review / Counterexample Audit | `253-review-fixlist.md`, review-profile graph context, current Plan 236 working tree, 1:1/group send funnels, Go/Dart upload progress bridge, picker lifecycle, l10n keys, and both gate arrays | The rendering fix remains sound. The progress contract needed ciphertext clamping, strict late-event rejection, a production-default stream proof, explicit internal upload hooks, lifecycle protection, non-vacuous registration proof, and one physical replay. New ARB strings and duplicate refutations add no value because `share_sending`, `share_send_failed`, and the existing summary keys already cover the UI. | Apply only source-verified tightenings; Plan 236 must be committed before any Plan 253 production edit. |

## Problem And Evidence

- Behavior to improve:
  1. After a user selects an image in the phone's external share sheet and sends
     it to a friend, the first outgoing conversation frame must contain the
     image, not a timestamp-only empty media frame that fills in seconds later.
  2. The external-share flow must show the same byte-based upload progress used
     by in-app media sends, transition truthfully into the sending phase, and
     never place a completion SnackBar over the underlying composer/input.
- Impact: an empty outgoing media frame looks like a failed or lost attachment,
  while `Sent to 1 target.` obscures the composer and provides no feedback during
  the slow part of the operation.
- Confirmed root cause/current gap:
  - The external coordinator uploads and durably copies each file before calling
    `sendChatMessage` at
    `lib/features/share/application/share_batch_delivery_coordinator.dart:470-550`
    (the full current `_sendToContact` method is `:470-573`).
    The upload result therefore already has a usable local attachment; this is
    not a missing-byte or failed-upload case.
  - `MessagePayload.toConversationMessage` deliberately creates the local row
    without its `media` list at
    `lib/features/conversation/domain/models/message_payload.dart:249-273`.
    Every terminal send funnel then calls `messageRepo.saveMessage(message)`
    before `_persistOutgoingMedia(...)` at
    `lib/features/conversation/application/send_chat_message_use_case.dart:1160-1175,1207-1219,1324-1336,2088-2103`, and only the returned value is
    enriched with `copyWith(media: attachments)` at `:1196-1199,:1236-1239,
    :1362-1365,:2145-2148`. `MessageRepositoryImpl.saveMessage` publishes that
    first attachment-free snapshot immediately at
    `lib/features/conversation/domain/repositories/message_repository_impl.dart:126-147`.
  - An already-mounted conversation consumes that message-change event and tries
    to hydrate media at
    `lib/features/conversation/presentation/screens/conversation_wired.dart:1655-1706`.
    Because attachment persistence follows the message publication, the first
    hydration read can be empty. This is the causal race behind the screenshot's
    timestamp-only outgoing frame.
  - The working in-app path avoids the race by constructing optimistic
    attachments with the existing local file path, inserting that media-bearing
    message immediately, then persisting/uploading it at
    `lib/features/conversation/presentation/screens/conversation_wired.dart:2352-2425`.
  - The in-app path also subscribes to `mediaUploadProgressStream`, tracks current
    and completed bytes, and renders `UploadProgressBanner` at
    `lib/features/conversation/presentation/screens/conversation_wired.dart:603-605,661-750,2564-2645` and
    `lib/features/conversation/presentation/screens/conversation_screen.dart:410-414`.
    The reusable view is
    `lib/features/conversation/presentation/widgets/upload_progress_banner.dart:7-105`.
  - External share wires none of that progress. `ShareTargetPickerScreen` accepts
    only `isSending` and covers the picker with a blocking circular spinner at
    `lib/features/share/presentation/screens/share_target_picker_screen.dart:19-51,117-155`.
    `ShareTargetPickerWired._sendSelectedTargets` instead shows floating
    SnackBars on partial failure, pure success, and exception at
    `lib/features/share/presentation/screens/share_target_picker_wired.dart:379-386,392-396,407-414`.
- Existing coverage:
  - `share_target_picker_screen_test.dart::sending state disables actions and shows progress copy`
    pins the current spinner-only state.
  - `share_target_picker_wired_test.dart::successful send dismisses the picker`
    proves route closure but does not reject the success SnackBar.
  - `share_target_picker_wired_test.dart::partial failure keeps only failed targets selected`
    pins retry selection but currently accepts SnackBar feedback.
  - `conversation_wired_test.dart::persists upload_pending attachments before upload starts`
    and `::shows relay upload progress and blocks leaving mid-upload` prove the
    working in-app optimistic/progress behavior.
  - `media_grid_cell_test.dart::127 round-3: own-sent media with a RELATIVE localPath renders (resolved at the render boundary)` proves a hydrated, existing
    sender file renders rather than becoming unavailable.
  - Coordinator encryption/fanout tests prove external media is processed once,
    uploaded independently per target, durably stored, and carried on the wire;
    none observes the first `messageChanges` snapshot or progress UX.
- Missing coverage: no test requires the first outgoing repository event from an
  external media send to contain renderable attachments; no external-share test
  mounts an already-open conversation and inspects its first media frame; and no
  test maps relay upload events into cumulative multi-target progress or rejects
  the post-pop SnackBar.
- Refuted findings:
  - **Not a failed upload or absent durable copy:** `uploadMedia` verifies the
    durable file before returning a `done` attachment at
    `lib/features/conversation/application/upload_media_use_case.dart:415-535`,
    and the screenshot's success summary is emitted only after delivery returns.
  - **Not missing progress infrastructure:** the shared progress stream, byte
    model, banner, in-app 1:1 wiring, and group wiring already exist. The gap is
    external coordinator/picker wiring only.
  - **Not the conversation failure SnackBar:** the screenshot copy is built by
    `ShareTargetPickerWired._buildSummary` at `:501-530`; conversation failure
    SnackBars already use composer-clearing margins elsewhere.
  - **Not fixable with a composer-clearing SnackBar margin:** the success summary
    is posted after the picker pops through the root messenger, so its underlying
    route is arbitrary; removing external-picker SnackBars is the bounded fix.
- Unresolved findings: the causal rendering seam is fully source-grounded after
  `ShareIntent`, but host fakes cannot prove the device event arithmetic or the
  visible OS-share transition. One availability-bounded physical replay is
  therefore required for progress UX while native intake code remains unchanged.
- Affected production, test, and gate files:
  `send_chat_message_use_case.dart`,
  `share_batch_delivery_coordinator.dart`,
  `share_target_picker_wired.dart`,
  `share_target_picker_screen.dart`,
  `upload_progress_banner.dart`, their focused tests, one new external-share
  widget-integration test, and both 1:1 gate arrays for that new test. Existing
  localized keys are reused; no ARB/generated-l10n change is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `0c960e7158dcc386`;
  `freshness=stale:test/features/groups/application/group_received_media_action_policy_test.dart`.
  The stale marker belongs to active received-media/group work; all load-bearing
  conclusions above were verified in current source without refreshing a
  read-only planning graph.
- Initial query / profile:
  `python3 graphify-arch/tdd_context.py query "external OS share media friend target outgoing image empty frame snackbar Sent to 1 target versus in-app image picker upload progress direct chat" --profile tdd --budget 700`
  returned `confidence=broad`.
- Required one-time refinement:
  `python3 graphify-arch/tdd_context.py query "ShareTargetPickerWired ShareBatchDeliveryCoordinator share_target_picker_wired.dart send external SharedMediaFile into ConversationWired image upload progress MediaUploadProgress" --profile tdd --budget 700`
  returned `confidence=anchored`.
- Anchors:
  `ShareTargetPickerWired` ->
  `lib/features/share/presentation/screens/share_target_picker_wired.dart:42`;
  `ShareBatchDeliveryCoordinator` ->
  `lib/features/share/application/share_batch_delivery_coordinator.dart:83`;
  `ConversationWired` ->
  `lib/features/conversation/presentation/screens/conversation_wired.dart:198`.
- Surfaced proof/gate files:
  `test/features/share/presentation/share_target_picker_wired_test.dart`,
  `test/features/share/application/share_batch_delivery_coordinator_test.dart`,
  `scripts/run_test_gates.sh`, and `scripts/run_host_test_gates.sh`.
- Graph gaps requiring source search: the compact graph did not surface the
  exact `Sent to 1 target.` SnackBar, `MessagePayload.toConversationMessage`
  media omission, save-before-attachment publication order, or the shared
  upload-progress widget/stream. Targeted current-source search resolved them;
  the full fallback graph was not needed.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.
- Independent-review query:
  `python3 graphify-arch/tdd_context.py query "Plan 253 counterexamples ShareBatchDeliveryCoordinator deliver progress sentBytes budgetBytes late event send_chat_message_use_case four saveMessage funnels ShareTargetPickerWired SnackBar group send first media publication gate registration" --profile review --budget 800`
  returned `confidence=anchored`, fingerprint `cbf4b6bc9b275d27`, with freshness
  stale only at user-owned `lib/main.dart`. Source verification, not the stale
  graph, established the ciphertext, gate-delegation, lifecycle, and four-funnel
  findings applied in this revision.

## Scope Contract And Guard

In scope:

- Make the first repository change emitted by each of the four terminal 1:1
  media-send funnels
  carry the already-normalized attachment list. Persisted message rows remain
  unchanged; media rows remain in `media_attachments`.
- Add an optional external-batch progress callback to
  `ShareBatchDeliveryCoordinator.deliver`, backed by a delivery-local tracker
  that knows final processed bytes, the active blob ID, completed bytes, target
  count, and `uploading` versus `sending` phase.
- Count progress over post-processing plaintext budget bytes once per selected
  target. Clamp every active upload event to that upload's budget because the Go
  event counts a ciphertext artifact that is 16 bytes larger. Accept events only
  when a non-null active blob ID exactly matches, clear that ID before folding a
  successful manual completion, and ignore duplicate/late final events. This
  stays monotonic across files/targets and also completes under no-event host
  fakes; production Go emits both an initial zero and one or more full-size
  events.
- Feed that callback into `ShareTargetPickerWired` and render the existing
  `UploadProgressBanner` inside `ShareTargetPickerScreen`. Allow the shared
  banner an optional title override so external share can say `Sending...`
  after relay bytes complete while in-app defaults remain unchanged.
- Remove all external-picker SnackBar delivery feedback. Pure success closes
  after the completed progress state. Partial failure, exception, or skipped
  attachments stay on the picker as keyed inline feedback; only failed targets
  remain selected for retry. A skipped-media completion clears successful
  selections and requires explicit close/acknowledgement so retry cannot
  duplicate already-sent siblings.
- Hold `UploadWakeLockController` for ordinary external media delivery and wrap
  the picker in `PopScope(canPop: !_isSending)` so a back gesture cannot discard
  the only progress/outcome surface while cancellation remains unsupported.

Must preserve:

- In-app 1:1 media remains optimistic, renderable, cancellable, wake-lock
  protected, and byte-progress tracked -> TC-07 and TC-08.
- Text-only external shares show the existing non-byte sending state; they must
  not fabricate `0 B / 0 B` upload progress -> TC-10.
- Multi-recipient shares still preprocess once and encrypt/upload separately per
  destination; failures remain target-isolated and failed-only retry keeps the
  original operation identity -> TC-03, TC-06, and existing coordinator/wired
  tests.
- 1:1 attachment encryption, opaque relay MIME, LAN-plus-relay custody, dedup,
  message status, media-row ownership, and relative durable paths stay unchanged
  -> the existing coordinator encryption group and `./scripts/run_test_gates.sh 1to1`.
- The active Plan 236 `deliverGroupMediaForward` source-verification and
  destination-authorization path remains byte-for-byte in behavior and does not
  inherit external progress semantics accidentally -> TC-09.
- Text-only sends do not acquire the media upload wake lock, and every media
  success/failure/exception releases its hold before close or retry -> TC-10 and
  TC-11.

Hard `Do not`:

- Do not special-case one contact by routing external media through
  `ConversationWired` or auto-pressing its composer; that would fork the current
  multi-contact/group delivery contract.
- Do not add a media column to messages, duplicate attachment persistence, bump
  the database, or change SQLCipher migrations.
- Do not change upload encryption, transport ordering, relay custody, LAN media,
  retry policy, operation dedup keys, or target authorization.
- Do not modify native share extensions, `receive_sharing_intent`, iOS/Android
  entry code, or Report 55's share-intent settlement/navigation contract.
- Do not refactor the existing 1:1/group progress trackers into a new global
  architecture. Reuse the visual/state contract and add only a delivery-local
  external-batch tracker.
- Do not remove or repurpose the user-owned Plan 236
  `deliverGroupMediaForward` method, source gate, or its tests while adding the
  optional callback to `deliver`.
- Do not add new l10n keys for existing copy. Use `upload_progress_title` for the
  default banner, `share_sending` for the sending phase, `share_send_failed` for
  exceptions, and the existing `_buildSummary` keys for inline outcomes.

Deferred / accepted difference:

- External-share cancellation is deferred to a follow-up because the current
  coordinator has no cancellation contract; this plan does not fake a Cancel
  button. Owner: future external-share cancellation work.
- Compression/preparation remains an indeterminate `Sending...` state until
  final processed byte counts exist. The determinate bar begins at relay upload;
  no ETA/time estimate is invented from byte events. Owner: future processing
  progress/ETA UX if requested.
- The determinate relay bar can remain at zero while `uploadMedia` performs a
  per-target full-file AES-GCM encryption, because that bridge call exposes no
  progress. For same-WiFi contacts, keep the UI indeterminate through the awaited
  LAN ciphertext transfer and enter determinate `uploading` only immediately
  before relay upload; the LAN leg currently emits no byte events. Owner: future
  preparation/LAN progress.
- Direct received-media forwards that still use `deliver` may gain the same
  truthful progress UI. This is an accepted sibling improvement; group received
  media's new `deliverGroupMediaForward` contract remains excluded.
- External share to a group target retains the pre-persist blank-frame window:
  `send_group_message_use_case.dart:1096` saves a media-free row before the
  bridge call, media appears only in later terminal saves, and
  `group_conversation_wired.dart:1666-1685` reloads/updates from outgoing DB
  changes. This plan's immediate-first-frame fix is explicitly 1:1 only. Owner:
  a follow-up group external-share rendering plan.
- Saving inline media in the 1:1 repository snapshot also means subsequent
  status-flip events can retain that transient media via
  `MessageRepositoryImpl._updatedMessageSnapshot`. Both current consumers are
  tolerant: conversation merges/hydrates it and feed reloads attachments from
  persistence. This source-verified event-shape improvement is accepted; no
  extra consumer refactor or synthetic fake-repository assertion is justified.

Dependencies:

- Current user-owned Plan 236 work has uncommitted changes in
  `share_batch_delivery_coordinator.dart`,
  `share_target_picker_wired_test.dart`, and new group-forward files. By the
  user's 2026-07-10 decision, Plan 236 must be committed before any Plan 253
  production edit; carrying its dirty diff forward is not allowed. Record the
  Plan 236 commit SHA and a GREEN TC-09 baseline in Execution Progress. Re-pin
  all citations in the two Plan-236-touched production files to that commit
  before Step 3. Until then, picker/coordinator citations in this plan refer to
  the current 2026-07-10 pre-253 working tree.
- `mediaUploadProgressStream` continues to emit `{id, sentBytes}` for relay
  uploads, and `uploadMedia` continues to receive the same explicit `blobId` the
  external coordinator minted.
- `MediaFileManager.cacheDocumentsDir` remains seeded at startup so relative
  durable paths resolve synchronously at the render boundary.

## Test Contract

Use zero empty cells. `GREEN sentinel` means the behavior is already correct and
must remain so while the external path is changed.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | The first outgoing repository change for a 1:1 media send contains the normalized attachment and its existing local path in all four terminal funnels. | `test/features/conversation/application/send_chat_message_use_case_test.dart::1:1 media first outgoing change carries renderable attachments in every terminal funnel` | Host application / table of live success, inbox accepted, inbox-full retryable, and terminal failure; in-memory change-source repo, fake encrypted send, existing temp image | HEAD's first event has `media.isEmpty` even though the return value has media -> each table row's first event has exactly the normalized attachment ID/message ID/local path. | Revert the helper at any one funnel to `saveMessage(message)` -> that table row re-reds. | `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name '1:1 media first outgoing change carries renderable attachments in every terminal funnel'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO `feature-host-all`. |
| TC-02 | A 1:1 external image share delivered while its destination conversation is already mounted renders `MediaThumbnailImage` on that message's first visible frame; no timestamp-only/empty media frame appears. | `test/features/share/integration/external_share_media_ux_test.dart::1:1 external image share into an open conversation renders the thumbnail on the first outgoing frame` | Host widget integration / same message+attachment repos for coordinator and mounted `ConversationWired`, real tiny PNG, fake crypto/P2P, attachment-save `Completer` to expose first-publication order | HEAD publishes attachment-free media before the gated attachment save and the first frame has no thumbnail -> GREEN renders the existing local image from inline normalized media before the gate opens. | Omit inline media from the first save or delay enrichment until after attachment persistence -> TC-02 re-reds. | `flutter test test/features/share/integration/external_share_media_ux_test.dart --plain-name '1:1 external image share into an open conversation renders the thumbnail on the first outgoing frame'`; AUTO `feature-host-all`; add path to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`. |
| TC-03 | External batch progress uses post-processing budgets, stays cumulative/monotonic across files and contact/group targets, clamps ciphertext-sized events, rejects unrelated/late IDs, preserves partial bytes on a failed attempt, and orders `uploading` before `sending`. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::external batch progress clamps cumulative bytes and rejects unrelated or late upload ids` | Host application / two processed media fixtures, contact+group targets, injected progress stream, gated internal upload hooks, fake bridge/transport | Progress API is absent on HEAD (intentional compile RED) -> total is `sum(budgetBytes) × target count`; an active `budget+16` event clamps, unrelated IDs do nothing, a just-completed blob's late full event does not double-count, no-event fake success advances manually, and the final successful sequence reaches exactly total. A partially observed failed/throwing upload followed by another target never moves backward and does not receive unobserved bytes. | Remove the per-upload clamp, allow null-ID adoption, clear active ID after completion, discard partial bytes on failure, reset completed bytes per target, or omit `sending` -> TC-03 re-reds. | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'external batch progress clamps cumulative bytes and rejects unrelated or late upload ids'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO `feature-host-all`. |
| TC-03B | The production coordinator default listens to the process-global media upload stream; tests cannot pass only through an injected substitute. | `test/features/share/application/share_batch_delivery_coordinator_test.dart::external batch progress uses the production media upload stream by default` | Host application / coordinator constructed without stream injection, gated real send helper, `emitMediaUploadProgressEvent` with the coordinator-minted blob ID | HEAD lacks progress wiring (intentional compile RED) -> production-default callback advances from the global event and completes. | Default to an isolated/dead stream while leaving the injected seam correct -> TC-03B re-reds. | `flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart --plain-name 'external batch progress uses the production media upload stream by default'`; existing arrays, AUTO `feature-host-all`. |
| TC-04 | The picker renders the shared determinate banner during upload and changes its title to sending without covering the screen with the circular spinner. | `test/features/share/presentation/share_target_picker_screen_test.dart::external media send uses the shared upload banner for upload and sending phases` | Widget / `UploadProgressViewState` plus external phase props | HEAD has no progress prop and only a full-screen circular spinner (intentional compile RED) -> shared banner key, byte label, determinate bar, and phase title render; circular overlay is absent while progress exists. | Ignore the progress prop, always show the spinner, or leave the title `Uploading media` in sending phase -> TC-04 re-reds. | `flutter test test/features/share/presentation/share_target_picker_screen_test.dart --plain-name 'external media send uses the shared upload banner for upload and sending phases'`; AUTO `feature-host-all` (no manual registration). |
| TC-05 | A pure-success external media send reaches completed progress, pops the picker, and never leaks `Sent to 1 target.` or any SnackBar onto the underlying composer/launcher. | `test/features/share/presentation/share_target_picker_wired_test.dart::successful media send closes after progress without a snackbar` | Widget / progress-emitting `Completer`-gated coordinator above a launcher with focused input | HEAD pops then calls `showSnackBar`, so the underlying route contains a SnackBar/summary -> GREEN pops after completion with neither. | Restore either success `showSnackBar` block or pop before the final progress update -> TC-05 re-reds. | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'successful media send closes after progress without a snackbar'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO `feature-host-all`. |
| TC-06 | Partial failure, exception, and skipped-media completion remain truthful inline; failed-only retry selection is preserved and already-sent siblings cannot be duplicated accidentally. | `test/features/share/presentation/share_target_picker_wired_test.dart::partial and skipped external share outcomes stay inline snackbar free and retry safe` | Widget / table of partial-failure, throw, and sent-plus-skipped coordinator results | HEAD renders all summaries in SnackBars and auto-closes sent-plus-skipped -> keyed inline feedback, no `SnackBar`, failed-only selection for partial failure, cleared selection plus explicit close for sent-plus-skipped. | Route feedback back through `ScaffoldMessenger`, retain successful targets on retry, or auto-close a warning -> TC-06 re-reds. | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'partial and skipped external share outcomes stay inline snackbar free and retry safe'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO `feature-host-all`. |
| TC-07 | In-app media keeps its renderable optimistic attachment and persists upload custody before network upload. | Existing `test/features/conversation/presentation/screens/conversation_wired_test.dart::persists upload_pending attachments before upload starts` | `GREEN sentinel` / widget with temp image and ordered fake attachment/upload calls | GREEN on HEAD -> remains GREEN with local path, message ID, size, and save-before-upload order. | Drop the optimistic attachment save or move it after upload -> TC-07 re-reds. | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'persists upload_pending attachments before upload starts'`; existing `ONE_TO_ONE_TESTS`, AUTO `feature-host-all`. |
| TC-08 | In-app 1:1 keeps its current byte banner, leave guard, cancellation affordance, and wake-lock lifecycle. | Existing `test/features/conversation/presentation/screens/conversation_wired_test.dart::shows relay upload progress and blocks leaving mid-upload` | `GREEN sentinel` / widget, gated upload, emitted progress event, fake wake-lock driver | GREEN on HEAD -> remains GREEN while shared banner accepts an optional external title. | Make the new title required, break default copy, or stop subscribing to byte events -> TC-08 re-reds. | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'shows relay upload progress and blocks leaving mid-upload'`; existing `ONE_TO_ONE_TESTS`, AUTO `feature-host-all`. |
| TC-09 | Plan 236's explicit group-media forward denial still performs zero processing, uploads, and deliveries; external progress wiring never bypasses its source gate. | Existing post-Plan-236 `test/features/groups/application/group_media_forward_policy_test.dart::GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator` | `GREEN sentinel` recorded immediately after Plan 236 commit / host application, tampered real file and guarded coordinator | GREEN baseline must be recorded before Plan 253 production edits -> remains GREEN after adding optional progress to `deliver`; `deliverGroupMediaForward` stays separate. | Delegate group forward into ordinary `deliver` or start progress before source verification -> TC-09 re-reds on non-zero work. | `flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator'`; AUTO `feature-host-all`; Plan 236 owns any group-gate registration. |
| TC-10 | Text-only external sends keep the non-byte busy state and do not fabricate an upload banner. | Extend existing `test/features/share/presentation/share_target_picker_screen_test.dart::sending state disables actions and shows progress copy` | `GREEN sentinel` / widget with `isSending=true`, no files/progress | HEAD shows disabled actions and the generic spinner -> remains GREEN and additionally has no `upload-progress-banner` or byte label. | Create `UploadProgressViewState(totalBytes: 0)` for text-only work -> TC-10 re-reds. | `flutter test test/features/share/presentation/share_target_picker_screen_test.dart --plain-name 'sending state disables actions and shows progress copy'`; AUTO `feature-host-all`. |
| TC-11 | Ordinary external media delivery holds the upload wake lock, blocks route pop/back while sending, and releases before success close or any failure/exception retry state; text-only sends take no hold. | `test/features/share/presentation/share_target_picker_wired_test.dart::external media send keeps route and wake lock until delivery settles` | Widget / routed picker, gated media coordinator, `FakeUploadWakeLockDriver`, success/failure/throw table, simulated system back | HEAD has neither hold nor `PopScope`, so back removes the route mid-send -> GREEN leaves the picker mounted with one hold, then releases to zero before close/inline outcome; text-only control stays zero. | Remove `PopScope`, acquire after delivery starts, or omit any release branch -> TC-11 re-reds. | `flutter test test/features/share/presentation/share_target_picker_wired_test.dart --plain-name 'external media send keeps route and wake lock until delivery settles'`; existing arrays, AUTO `feature-host-all`. |
| DP-01 | One physical OS-share replay proves production progress never exceeds 100% or regresses, reaches completion, transitions to localized Sending, and leaves no SnackBar. | `253 physical external multi-media progress replay` | Device/manual boundary proof / one discovered physical phone with a real eligible contact, image+video batch, profile/release build, screen recording | Not executed during planning -> one recorded replay satisfies every observation in the Device/Relay Proof Profile. | Device-observed over-100/backward/stuck progress, missing phase, or SnackBar fails closure even if host tests pass. | Resolve and pin the live device ID; launch with `flutter run --profile -d <PHYSICAL_DEVICE_ID>` (record the expanded command), perform the OS share-sheet recipe once, and attach the recording/result to Execution Progress. |

### Test Notes

- TC-02's attachment repository deliberately blocks its first save after the
  message change has been published. This makes the race deterministic: GREEN
  must come from media on the first message event, not from a favorable async
  attachment query or a later status event.
- TC-03 uses an injected stream for adversarial ordering. For each active upload,
  emit an unrelated ID, a `budgetBytes + 16` ciphertext-sized event, then resolve
  the upload and emit its late final event. Assert strict active-ID acceptance,
  per-upload clamping, clear-before-completion ordering, and exact cumulative
  totals. Add a partial event followed by upload null/throw and a subsequent
  target; the observed partial amount folds into completed so the sequence never
  regresses, but the failed upload never fabricates the remaining bytes. A
  no-event host fake still advances by known budget; device Go is not a no-event
  source because it always emits initial zero and full-size events.
- TC-03B constructs the default coordinator with no injected stream and emits
  through `emitMediaUploadProgressEvent`, closing the production-default seam.
- TC-05 scopes `find.byType(SnackBar)` to the whole app after the picker pop, so
  it catches exactly the screenshot regression where the root ScaffoldMessenger
  paints the share summary over the underlying input.

## Implementation Steps

1. Snapshot `git status --short`. Plan 236 must be committed before any Plan 253
   production edit (user decision, 2026-07-10); do not carry its dirty
   coordinator forward. Record the Plan 236 commit SHA, re-pin picker/coordinator
   citations to that tree, run TC-09 once to establish its GREEN baseline, and
   record a `flutter analyze` exit/output baseline before Step 3. Stop if Plan 236
   is still uncommitted or TC-09 is not GREEN; that is dependency work, not a
   Plan 253 RED. Also record the post-commit implementor census with
   `rg -n "implements ShareBatchDeliveryCoordinator" lib test`.
2. Add TC-01 and TC-02 before production edits. Run their exact RED commands and
   record the attachment-free first event/first frame. Stop-if the first event
   already contains renderable media after Plan 236 lands; re-ground instead of
   fabricating a RED.
3. In `send_chat_message_use_case.dart`, add one narrow helper that saves
   `message.copyWith(media: normalizedAttachments ?? const [])` to the message
   repository. Use it at the four current first-save funnels (live success,
   inbox accepted, inbox-full retryable, terminal failure), while keeping
   `_persistOutgoingMedia` immediately afterward. Do not store media in the
   message DB row or issue a second message save. Stop-if any attachment is not
   normalized to the final message ID before this helper; fix normalization at
   the existing `normalizedAttachments` seam, not in UI.
   Run TC-01, TC-02, TC-07, and TC-08 to GREEN before starting Step 4.
4. Use the Step-1 implementor census and add TC-03 plus TC-03B. Introduce a
   small public immutable progress value and phase enum,
   plus an optional callback on ordinary `ShareBatchDeliveryCoordinator.deliver`.
   Update every implementor/override found by the census. Leave
   `deliverGroupMediaForward` unchanged.
5. Inside `DefaultShareBatchDeliveryCoordinator.deliver`, create a
   delivery-local tracker only after media preprocessing determines final bytes.
   Total actual upload bytes are `sum(processedMedia.budgetBytes) × targets.length`.
   Default its optional test stream seam to `mediaUploadProgressStream`, subscribe
   in a guarded `try/finally`, and cancel on every return/throw. Because blob IDs
   are minted inside `_sendToContact`/`_sendToGroup`, extend those methods and
   their internal test typedefs with delivery-local upload-started/upload-settled
   hooks; do not store mutable progress state on the coordinator instance. Start
   the relay `uploading` phase immediately before each `uploadMedia` call (after
   any awaited LAN leg). Accept an event only when active ID is non-null and
   exactly equal, clamp its `sentBytes` to that upload's `budgetBytes`, and expose
   `completed + current` clamped to total. On successful return, clear the active
   ID/current bytes before adding the known budget; on null/throw, clear the ID
   first and fold only the maximum observed/clamped current bytes into completed
   so the next target cannot make the UI jump backward. Late/duplicate final
   events are then ignored. Report
   `sending` before each message dispatch and retain Plan 236 target exception
   isolation. Run TC-03 and TC-03B to GREEN before Step 6.
6. Add TC-04 through TC-06. Let `UploadProgressBanner` accept an optional title
   override with its current localized title as the default. Add progress/phase
   and keyed inline feedback props to `ShareTargetPickerScreen`; render the
   shared banner in the picker column and suppress the circular overlay only
   while determinate media progress exists. Reuse `upload_progress_title`,
   `share_sending`, `share_send_failed`, and the current summary keys; do not add
   ARB/generated-l10n churn.
7. In `ShareTargetPickerWired`, clear stale progress/feedback on each attempt,
   map the coordinator callback into `UploadProgressViewState`, and guard every
   callback with `mounted`. Delete all three `ScaffoldMessenger`/SnackBar blocks.
   Pure success closes; partial failure/exception stays inline; sent-plus-skipped
   clears successful selection and waits for explicit acknowledgement/close.
   For ordinary media delivery, acquire `UploadWakeLockController` before the
   coordinator call and release it in a `finally` before close/inline outcome;
   text-only sends take no hold. Wrap the route in
   `PopScope(canPop: !_isSending)` so system back cannot abandon the send. Add and
   run TC-11, then run TC-04/TC-05/TC-06/TC-11 to GREEN.
8. Update the two 1:1 arrays for the new TC-02 integration file, run the focused
   files and preservation sentinels, the curated 1:1 lane, the justified
   feature-host family sweep, analyzer comparison, diff hygiene, and the required
   once-only physical replay from the Device/Relay Proof Profile.

## Risks And Blind Spots

- First event carries media before attachment-row persistence finishes -> safe
  because the attachment is already uploaded, durably copied, normalized, and
  renderable. TC-01/TC-02 lock the event shape; existing persistence/encryption
  tests lock durable recovery.
- A global upload event from an in-app send could corrupt external progress ->
  exact active-ID filtering and delivery-local subscription in TC-03.
- Multi-target progress could jump backward or reach 100% after only the first
  target -> processed-byte multiplication and cumulative sequence in TC-03.
- Go reports ciphertext bytes while UI totals use plaintext budgets, and its
  explicit final event may arrive after `uploadMedia` resolves -> per-upload
  clamp plus strict active-ID clear-before-completion ordering in TC-03.
- An injected stream could hide a dead production default -> TC-03B drives
  `emitMediaUploadProgressEvent` with no stream override.
- Two concurrent `deliver` calls could corrupt each other if tracking were stored
  on the coordinator instance -> tracker and upload lifecycle hooks are local to
  each invocation; TC-03 interleaves an unrelated ID.
- Picker pops while a callback is queued -> `mounted` guards plus subscription
  cancellation; TC-05 completes progress and then tears down the route.
- Picker background/back lifecycle could hide the only feedback after SnackBar
  removal -> wake-lock and `PopScope` ownership/release are causal in TC-11.
- Lifecycle / derived-state durability: progress and inline feedback remain
  route-local transient UI; durable message/attachment state is unchanged.
- Sibling-surface consistency: in-app 1:1 and text-only external behavior are
  covered by TC-07/TC-08/TC-10. Direct internal forwards may share ordinary
  `deliver` progress; Plan 236 group forward is separately guarded by TC-09.
- Destructive-action side effects: no delete/cleanup/cancel behavior changes.
  Skipped-media success clears target selection so acknowledgement cannot become
  an accidental duplicate resend (TC-06).
- Invariant re-verification under new transitions: retry starts after inline
  partial feedback, so progress/phase/feedback must reset before the next
  callback and failed-only selection must remain stable (TC-06).

## Gate Cadence

- Per-plan closure: exact TC-01 through TC-11 commands (including TC-03B), the existing/new focused
  share and conversation files, `./scripts/run_test_gates.sh 1to1`, and
  `./scripts/run_host_test_gates.sh feature-host-all`, followed once by the
  physical replay below. No core or performance sweep is justified.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the **Plan 236 + Plan
  253 shared delivery-coordinator dependency wave**, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs: N/A — every new/changed Dart test is
  under `test/features/**`; TC-02 is additionally pinned to both 1:1 arrays.

## Device/Relay Proof Profile

- Why device proof is required: symptom 1 closes causally at the Dart repository/
  widget seam, but symptom 2 depends on production Go events that measure
  ciphertext, async event ordering after a bridge future, the physical OS share
  sheet, and the visible `uploading` -> `sending` transition. Host fixtures make
  those hazards deterministic but cannot alone prove the physical presentation.
- Availability/topology: at execution time resolve live targets with
  `flutter devices --machine`, `adb devices`, and
  `xcrun simctl list devices available`. Use one discovered physical phone;
  prefer a physical Android device because the behavior is not iOS-specific.
  Pin its exact ID in Execution Progress. The sender must already have a real,
  eligible contact. Recipient-screen observation is not required; if live peer
  setup becomes necessary, use the available physical Android + Android emulator
  pair and automate that setup per repository policy.
- Fixture/action: choose an under-limit multi-file batch containing at least one
  image and one video, large enough for progress to be observable. From the
  physical phone's Photos/Files OS share sheet, select Mknoon, choose one real
  contact, and send once. Capture a screen recording plus the pinned build/device
  identity; do not change native share code merely to make this proof easier.
- Required observations: the determinate value never exceeds 100%, never moves
  backward, reaches completion, changes its title to localized `share_sending`
  after relay bytes complete, and closes without any SnackBar over the underlying
  route. An immediate 1:1 thumbnail is supporting device confidence; TC-01/TC-02
  remain the causal closure for that first-frame behavior.
- Failure interpretation: a backward/over-100/stuck value, missing sending phase,
  leaked SnackBar, or route escape while sending is a product failure. Build/app
  launch failure is an environment blocker. If no physical phone exists in the
  resolved live matrix, record `N/A (target unavailable by project policy)`;
  unavailable hardware is not a failed gate and must not be waited on.

## Acceptance Gates

```bash
# Dependency snapshot. Plan 236 must already be committed; record its SHA and
# show/stat in Execution Progress before any Plan 253 production edit.
git status --short
git rev-parse HEAD
git show --stat --oneline <PLAN_236_SHA>

# Establish pre-edit dependency/analyzer baselines; TC-09 must be GREEN here.
flutter test test/features/groups/application/group_media_forward_policy_test.dart \
  --plain-name 'GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator'
flutter analyze --no-congratulate --no-preamble > /tmp/plan-253-analyze-before.txt 2>&1

# Post-236 implementor census; every ordinary deliver override must accept the
# optional callback, while deliverGroupMediaForward remains intact.
rg -n "implements ShareBatchDeliveryCoordinator|deliverGroupMediaForward" lib test

# First causal RED before production edits; expect non-zero because the first
# outgoing message event has an empty media list in all four terminal funnels.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name '1:1 media first outgoing change carries renderable attachments in every terminal funnel'

# User-visible RED; expect non-zero because the open conversation has no
# thumbnail on the first attachment-save-gated frame.
flutter test test/features/share/integration/external_share_media_ux_test.dart \
  --plain-name '1:1 external image share into an open conversation renders the thumbnail on the first outgoing frame'

# Slice-1 GREEN checkpoint before progress API/UI work.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name '1:1 media first outgoing change carries renderable attachments in every terminal funnel'
flutter test test/features/share/integration/external_share_media_ux_test.dart \
  --plain-name '1:1 external image share into an open conversation renders the thumbnail on the first outgoing frame'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'persists upload_pending attachments before upload starts'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'shows relay upload progress and blocks leaving mid-upload'

# Progress REDs; intentional compile/assertion failure until the callback/model,
# tracker, and production-default stream exist.
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'external batch progress clamps cumulative bytes and rejects unrelated or late upload ids'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'external batch progress uses the production media upload stream by default'

# Slice-2 GREEN checkpoint.
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'external batch progress clamps cumulative bytes and rejects unrelated or late upload ids'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart \
  --plain-name 'external batch progress uses the production media upload stream by default'

# UI/lifecycle REDs; expect missing progress props/inline feedback and current
# post-pop SnackBar/back escape/no wake-lock behavior.
flutter test test/features/share/presentation/share_target_picker_screen_test.dart \
  --plain-name 'external media send uses the shared upload banner for upload and sending phases'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'successful media send closes after progress without a snackbar'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'partial and skipped external share outcomes stay inline snackbar free and retry safe'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'external media send keeps route and wake lock until delivery settles'

# Slice-3/focused GREEN; expect exit 0 and zero failed tests.
flutter test test/features/share/presentation/share_target_picker_screen_test.dart \
  --plain-name 'external media send uses the shared upload banner for upload and sending phases'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'successful media send closes after progress without a snackbar'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'partial and skipped external share outcomes stay inline snackbar free and retry safe'
flutter test test/features/share/presentation/share_target_picker_screen_test.dart \
  --plain-name 'sending state disables actions and shows progress copy'
flutter test test/features/share/presentation/share_target_picker_wired_test.dart \
  --plain-name 'external media send keeps route and wake lock until delivery settles'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart
flutter test test/features/share/presentation/share_target_picker_screen_test.dart
flutter test test/features/share/presentation/share_target_picker_wired_test.dart
flutter test test/features/share/integration/external_share_media_ux_test.dart

# Exact preservation sentinels; expect exit 0.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'persists upload_pending attachments before upload starts'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'shows relay upload progress and blocks leaving mid-upload'
flutter test test/features/groups/application/group_media_forward_policy_test.dart \
  --plain-name 'GMF-01R denied dispatch makes zero uploads and zero deliveries through the coordinator'

# Registration proof. Each assertion must find exactly one executable array entry;
# the second old dry-run is forbidden because run_test_gates delegates it to host.
test "$(rg -c '^  "test/features/share/integration/external_share_media_ux_test\.dart"$' scripts/run_test_gates.sh)" -eq 1
test "$(rg -c '^  "test/features/share/integration/external_share_media_ux_test\.dart"$' scripts/run_host_test_gates.sh)" -eq 1
./scripts/run_host_test_gates.sh 1to1 --dry-run | rg 'external_share_media_ux_test.dart'

# Affected curated lane and justified feature family; expect exit 0 and zero failures.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene; compare against the recorded baseline and require no new analyzer
# issues plus no whitespace errors.
flutter analyze --no-congratulate --no-preamble > /tmp/plan-253-analyze-after.txt 2>&1
diff -u /tmp/plan-253-analyze-before.txt /tmp/plan-253-analyze-after.txt
git diff --check

# Availability-bounded DP-01 discovery. Record the resolved physical ID, then
# expand and record the profile launch command before performing the one replay.
flutter devices --machine
adb devices
xcrun simctl list devices available
flutter run --profile -d <PHYSICAL_DEVICE_ID>
```

## Execution Interpretation And Done Criteria

- Expected RED:
  - TC-01 each sampled terminal funnel's first `messageChanges` snapshot has
    `media.isEmpty`.
  - TC-02 first visible external-share message frame has no
    `MediaThumbnailImage` while the attachment save is gated.
  - TC-03/TC-03B lack the progress callback/model/default stream (intentional
    compile RED) and then fail any unclamped, regressing, double-counting, or
    injected-only implementation.
  - TC-04 lacks picker progress props (intentional compile RED).
  - TC-05/TC-06 find the current SnackBar path and missing inline feedback.
  - TC-11 proves current system back can remove the route and no upload wake-lock
    hold exists.
- Green sentinels: TC-07 through TC-10 plus existing coordinator encryption,
  fanout, failed-only retry, and 1:1 gate coverage.
- Pre-existing dirty tree / known failure: active user-owned received-media and
  Plan 236 work includes the coordinator, picker test, group-forward production
  and test files, the index, graph outputs, and unrelated media plans. Plan 236
  must be committed first; preserve all other unrelated/user-owned changes.
- Environment blocker: host tests use temp files/fakes and need no SQLCipher
  fixture. DP-01 uses only a physical phone present in the live matrix; target
  absence is recorded as `N/A (target unavailable by project policy)`, not as an
  environment blocker or failed gate.
- Scope drift: any native share-extension change, DB migration, transport/
  encryption change, progress refactor of in-app/group screens, or weakening of
  Plan 236 source/target gates blocks completion and requires re-plan.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED and focused GREEN are recorded. After compile REDs are resolved,
      a behavioral mutation of TC-03's clamp/late-ID rule and TC-04's spinner/
      phase-title rule is applied one at a time, each test re-reds, and both
      mutations are reverted.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] TC-02 has exactly one executable entry in each 1:1 array; the literal
      per-file `rg -c` assertions pass and the host dry-run lists it.
- [x] The committed Plan 236 SHA is recorded before production edits, citations
      are re-pinned to it, and TC-09 is GREEN both before and after Plan 253.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] DP-01 records its discovered target/build/fixture, screen recording, and
      all progress/SnackBar observations, or the physical leg is explicitly
      `N/A (target unavailable by project policy)` from the resolved live matrix.
- [x] Scope Contract And Guard is respected.

## Historical Handoff (superseded by the accepted closure below)

- First causal RED command:
  `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name '1:1 media first outgoing change carries renderable attachments in every terminal funnel'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'shows relay upload progress and blocks leaving mid-upload'`.
- Manual registration completed:
  `test/features/share/integration/external_share_media_ux_test.dart` to
  `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh` and
  `ONE_TO_ONE_HOST_TESTS` in `scripts/run_host_test_gates.sh`; all other tests
  are already pinned or AUTO-globbed.
- Migration: none.
- Boundary closure: TC-01/TC-02 close first-frame ordering at the post-capture
  `ShareIntent` seam; progress closes with host counterexamples plus DP-01's one
  availability-bounded physical share-sheet replay.
- Unresolved evidence: none. Plan 236 is committed, both registrations are
  complete, the required gates and physical replay pass, and the closure audit
  below is authoritative.

## Execution Progress

### Orchestrator Preflight Contract

- **Source of truth / closure bar:** this plan under repository `AGENTS.md`;
  accept only with TC-01 through TC-11 resolved, both required registrations,
  `1to1`, `feature-host-all`, analyzer/diff hygiene, independent QA, and DP-01
  executed or recorded `N/A (target unavailable by project policy)`.
- **Dependency:** Plan 236 is committed at
  `b1d043eb34a3844ea16c1fd2cdab439ba11368b5`; its ordinary-delivery and
  `deliverGroupMediaForward` seams must remain distinct and TC-09 must pass.
- **Code-entry files:** `send_chat_message_use_case.dart`,
  `upload_progress_banner.dart`, `share_batch_delivery_coordinator.dart`,
  `share_target_picker_screen.dart`, and `share_target_picker_wired.dart`.
- **Regressions:** TC-01 through TC-06 and TC-11 are required causal tests;
  TC-07 through TC-10 are preservation sentinels; DP-01 is the device proof.
- **Direct tests / gates:** every literal command in `## Acceptance Gates`;
  required curated gates are `./scripts/run_test_gates.sh 1to1` and
  `./scripts/run_host_test_gates.sh feature-host-all`. Full `host-all` is
  explicitly excluded by repository cadence.
- **Known-failure interpretation:** no required test/gate failure is accepted
  without focused triage and proof it is allowed and not widened. Analyzer
  closure requires no new issue versus a trustworthy Plan-236 baseline. Physical
  target absence is the sole policy-defined `N/A`, not a failed gate.
- **Done criteria:** the checklist in `## Execution Interpretation And Done
  Criteria`, one independent QA pass with no blockers, and one final incremental
  architecture refresh after accepted app-owned changes.
- **Scope guard / non-goals:** no native share, database, encryption, transport,
  cancellation, global-progress, or group-first-frame redesign; preserve all
  unrelated dirty-tree work.
- **Pre-existing scoped work:** Plan 253 code, focused tests, integration test,
  and both gate registrations already exist uncommitted against Plan 236 HEAD.
  The Executor must recover attribution from the scoped diff and may not rewrite
  unrelated received-media/group-library work.
- **Graph anchors / gaps:** reuse `ShareTargetPickerWired`,
  `ShareBatchDeliveryCoordinator`, and `ConversationWired` from the plan snapshot.
  The affected query additionally surfaced their current importers/callers;
  exact SnackBar text, attachment publication order, and progress-stream
  behavior still require targeted source/test verification.

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 22:12 CEST | exact-commit isolation / clean family start | detached `/tmp/plan-253-executor-c9b1-worktree` at `c9b1ce6cb`; clean base `/tmp/plan-253-executor-b1d0-worktree` at `b1d043eb3` | clean c9b1 focused files pass 137/18/21/16/1 and clean 1:1 passes 1,672; clean analyzer is 1,626 versus base 1,626 with only one line-number shift; exact clean `feature-host-all` is now running | worktree add logs, `/tmp/plan-253-executor-main-vs-c9b1-hashes.log`, five `/tmp/plan-253-executor-clean-c9b1-focused-*.log`, `/tmp/plan-253-executor-clean-c9b1-1to1.log`, both clean analyzer logs and `/tmp/plan-253-executor-clean-analyzer-b1d0-to-c9b1.diff`; family log `/tmp/plan-253-executor-clean-c9b1-feature-host-all.log` | dirty-main failure remains `unrelated-but-required`; clean commit gate is the exact Plan-253 closure proof. No main index/commit mutation by Executor | finish exact clean family gate, then DP-01 build/setup on physical `21071FDF600CSC` plus `emulator-5554` from the c9b1 worktree |
| 2026-07-10 22:40 CEST | clean feature-family classification | detached c9b1 and b1d0 worktrees; feature items 641, 687, and 701 | item 641 passed after the detached worktree used a symlink to the existing ignored iOS fixture; item 687 `background_choice_control_test.dart` fails identically on b1d0 and c9b1 and its settings/l10n paths are unchanged; inventory 688-705 found only item 701 additionally failing | `/tmp/plan-253-executor-clean-c9b1-feature-item-641-symlink-rerun.log`, `/tmp/plan-253-executor-clean-c9b1-feature-host-all-resume-641-symlink.log`, `/tmp/plan-253-executor-clean-b1d0-background-choice-baseline.log`, `/tmp/plan-253-executor-feature-687-unchanged-path-proof.log`, `/tmp/plan-253-executor-clean-c9b1-feature-host-inventory-688.log` | item 687 is a pre-existing but required family-gate blocker; item 701 requires session attribution | compare exact 6b smoke case at b1d0/c9b1 and correct only Plan-253 test isolation if causal |
| 2026-07-10 23:18 CEST | smoke isolation correction / GREEN | `test/features/share/integration/share_to_contact_smoke_test.dart` only, in main and c9b1 evidence worktree | exact 6b passes at b1d0 and fails at c9b1 because the new production wake-lock calls an unfaked plugin; added `FakeUploadWakeLockDriver` reset in setUp/tearDown. Exact 6b and full 11-test smoke pass in both trees; clean 1:1 passes 1,672; format and both diff checks pass | `/tmp/plan-253-executor-clean-b1d0-share-smoke-6b.log`, `/tmp/plan-253-executor-clean-c9b1-share-smoke-6b.log`, four `*-smoke-*-fixed*.log`, `/tmp/plan-253-executor-clean-c9b1-1to1-after-smoke-fix.log` | item 701 is resolved by an in-scope test-harness correction; item 687 remains the sole known family blocker | run availability-bounded DP-01 on the discovered Android pair |
| 2026-07-10 23:34 CEST | DP-01 supporting single-share legs | physical Pixel 6 `21071FDF600CSC`, emulator `emulator-5554`, exact c9b1 production profile APK | automated identities and mutual contacts were provisioned, then exact profile reinstalled. Separate real OS image/video shares each completed; image frames show `Uploading media` then `Sending…`; emulator launched with two unread inbox messages and rendered image/video cards | `/tmp/plan-253-executor-dp01-image-send-recording.mp4`, `/tmp/plan-253-executor-dp01-video-send-recording.mp4`, both contact sheets, `/tmp/plan-253-executor-dp01-emulator-receiver-chat-ui.png` | useful supporting evidence but separate shares do not alone satisfy the required one-batch image+video DP-01 fixture | perform one actual Files/share-sheet multi-select replay |
| 2026-07-10 23:43 CEST | DP-01 combined physical replay PASS | Files by Google multi-select of `plan253_dp01.jpg` + `plan253_dp01.mp4`; system share sheet; MKnoon profile picker; physical-to-emulator relay | one 3.22 KB image+video selection opened the picker as `+1`; captured frames progress monotonically from `Uploading media` `1.3 KB / 4.5 KB` to localized `Sending…` `4.5 KB / 4.5 KB`, never exceeds 100%, completes/pops to the home route, and shows no SnackBar. Emulator renders the combined image+video message at 23:41 via cellular relay | `/tmp/plan-253-executor-dp01-multi-send-recording.mp4`, `/tmp/plan-253-executor-dp01-multi-send-contact-sheet.jpg`, `/tmp/plan-253-executor-dp01-multi-video-contact-sheet-4-8.jpg`, representative extracted frames 052/056/060, `/tmp/plan-253-executor-dp01-multi-after-ui.xml`, `/tmp/plan-253-executor-dp01-emulator-multi-received-ui.png` | DP-01 satisfied; no device blocker remains. Required `feature-host-all` still cannot pass because of pre-existing item 687 | persist Executor Handoff as not ready for acceptance until item 687 is dispositioned or corrected outside Plan 253 |
| 2026-07-11 00:17 CEST | independent QA artifact and scope audit | full plan/contract/handoff, both gate scripts, c9b1-vs-b1d0 scoped diff, focused/mutation/registration/analyzer/1to1/smoke/family logs, DP-01 recording contact sheets and receiver frame | direct evidence supports TC-01–TC-11/TC-03B/TC-09, five focused suites, exact registrations, clean 1to1, equal analyzer baseline, smoke isolation fix, and DP-01; clean item 687 fails the same two assertions on b1d0 and c9b1 while relevant settings/l10n paths are unchanged | all `/tmp/plan-253-executor-*` evidence named in the handoff, especially `clean-c9b1-feature-host-all-resume-641-symlink.log`, `clean-b1d0-background-choice-baseline.log`, `clean-c9b1-feature-host-inventory-688.log`, and DP-01 multi-send artifacts | candidate B1: required `feature-host-all` remains red at item 687; no contract allowance makes a pre-existing failure acceptable. No second blocker identified yet | finish dirty/unattributed-change and exact artifact consistency audit, then persist `### Independent QA Review` |
| 2026-07-11 | superseding closure / required family | blocker fix `f029d131f`; current closure tree through `de0aabfd5` | `./scripts/run_host_test_gates.sh feature-host-all` PASS; all 731 planned commands completed, including item 709 and share items 724–729 | item 709's stale Signal-copy assertions and the reviewed wake-lock smoke isolation are committed; prior causal, 1:1, analyzer, and DP-01 evidence remains valid | B1 cleared; N1 retained as non-blocking historical artifact-name debt | ACCEPTED; maintenance only |

## Historical Execution Result (superseded by the closure audit below)

- **Final verdict:** `blocked`.
- **Blocker class:** `test_or_gate_failure`.
- **Invocation topology:** full `implementation-execution-qa-orchestrator`
  controller with a bounded Executor and a separate independent QA reviewer.
  One materialization retry was used for each child; local sequential fallback
  was not used. No fix pass was opened because the sole correction belongs to
  an unrelated settings/l10n scope outside Plan 253.
- **Files changed:** Plan-253 production/tests/gate content is isolated in
  commit `c9b1ce6cb5b319122ff03816fd69963edeb9d89c` against Plan-236 base
  `b1d043eb34a3844ea16c1fd2cdab439ba11368b5`. The remaining attributable
  working-tree change is
  `test/features/share/integration/share_to_contact_smoke_test.dart`, which
  installs/resets `FakeUploadWakeLockDriver`; this plan contains the persisted
  controller, Executor, QA, and verdict records. Concurrent dirty files remain
  outside the execution scope and were not staged, reset, or rewritten.
- **Tests added/updated:** TC-01 through TC-11 (including TC-03B and TC-09
  baseline/final), Plan-236 compile/forward-flow adaptations, exact TC-02 gate
  registration, and the external-share smoke wake-lock fixture.
- **Evidence ledger — focused and causal:** first-publication omissions re-red
  TC-01/TC-02; strict-ID removal and clamp widening independently re-red TC-03;
  title suppression re-red TC-04; every mutation restored GREEN. TC-01–TC-11,
  TC-03B, TC-09 before/after, registration assertions/dry-run, and the five full
  focused files pass with 137/18/21/16/1 tests. Primary evidence is under
  `/tmp/plan-253-executor-tc*-mutation-red*.log`, the corresponding GREEN logs,
  `/tmp/plan-253-executor-registration-assertions.log`, and
  `/tmp/plan-253-executor-registration-dry-run.log`.
- **Evidence ledger — curated/analyzer/hygiene:** from detached clean c9b1,
  `./scripts/run_test_gates.sh 1to1` passes 1,672 tests after the smoke fix
  (`/tmp/plan-253-executor-clean-c9b1-1to1-after-smoke-fix.log`). The full smoke
  file passes 11 tests. Clean b1d0 and c9b1 analyzers both report the same 1,626
  pre-existing issues, with only a shifted line/timing diff; `git diff --check`
  passes. These are closure-valid no-regression comparisons, not waived new
  diagnostics.
- **Evidence ledger — required family:** in
  `/tmp/plan-253-executor-c9b1-worktree`,
  `./scripts/run_host_test_gates.sh feature-host-all` reaches item 687 and fails
  two assertions in
  `test/features/settings/presentation/widgets/background_choice_control_test.dart`.
  The identical exact test fails on clean b1d0, and relevant settings/l10n paths
  are unchanged by c9b1. Evidence:
  `/tmp/plan-253-executor-clean-c9b1-feature-host-all-resume-641-symlink.log`
  and `/tmp/plan-253-executor-clean-b1d0-background-choice-baseline.log`.
- **Evidence ledger — DP-01:** profile replay on discovered Pixel 6
  `21071FDF600CSC` and emulator `emulator-5554` passes. A real Files/share-sheet
  image+video batch visibly progresses from `Uploading media` 1.3/4.5 KB to
  localized `Sending…` 4.5/4.5 KB, remains monotonic and bounded, closes without
  a SnackBar, and arrives as one combined relay message. Evidence includes
  `/tmp/plan-253-executor-dp01-multi-send-recording.mp4`, both contact sheets,
  final UI dump, and receiver screenshot.
- **QA findings and disposition:** independent QA confirmed the Plan-253 code,
  causal proof, registrations, analyzer comparison, curated lane, smoke fix,
  and device proof. B1 remains blocking because the preflight and governing gate
  provide no allowance for accepting a required red family gate, even when the
  failure is inherited. N1 (stale names for three extracted DP frames) is
  non-blocking because the recording, contact sheets, frames 01–30, UI dump, and
  receiver screenshot provide the required observation.
- **Exact blocker:** required `feature-host-all` does not exit 0 at item 687.
  Correct or formally disposition that test in its owning settings/l10n scope,
  then rerun the complete
  `./scripts/run_host_test_gates.sh feature-host-all` command and invoke a fresh
  independent QA retry. No Plan-253 behavior or device gap remains.
- **Safety:** the implementation is safe as a tested checkpoint but unsafe to
  accept or close while a required family gate is red. Graphify was not refreshed
  again after QA because the orchestrator did not reach acceptance.

### Executor Handoff

- **Executor verdict:** `not_ready_for_independent_QA_acceptance`. Plan 253's
  causal tests, focused suites, curated `1to1`, analyzer comparison, and DP-01
  are GREEN, but the required `feature-host-all` family remains blocked at item
  687 by a pre-existing failure that this plan is not authorized to change.
- **Commit and isolation:** Plan 236 base is
  `b1d043eb34a3844ea16c1fd2cdab439ba11368b5`; Plan 253 production/tests/gate
  commit is `c9b1ce6cb5b319122ff03816fd69963edeb9d89c`. Exact evidence used detached
  worktrees `/tmp/plan-253-executor-b1d0-worktree` and
  `/tmp/plan-253-executor-c9b1-worktree`; the latter now contains only the
  additional uncommitted smoke-test isolation fix described below.
- **Final Executor-owned working-tree changes:**
  `test/features/share/integration/share_to_contact_smoke_test.dart` installs
  and resets `FakeUploadWakeLockDriver` so media smoke cases do not call a real
  plugin, and this plan records the execution ledger/handoff. The main index is
  unchanged and empty. Concurrent Plan-240/group work, index/docs, graph files,
  and all other dirty files remain owner-attributable and untouched.
- **Causal RED/GREEN ledger:** TC-01 and corrected TC-02 mutations re-red and
  restore; TC-03 strict-ID and clamp mutations re-red and restore; TC-04 title
  suppression re-reds and restores. TC-01 through TC-11, TC-03B, TC-09 before
  and after, the five full focused files (137/18/21/16/1), and registration
  checks pass. Primary logs are `/tmp/plan-253-executor-tc01-mutation-red.log`,
  `/tmp/plan-253-executor-tc02-mutation-red-corrected.log`, both TC-03 mutation
  logs, `/tmp/plan-253-executor-tc04-title-mutation-red.log`, the corresponding
  `*-green.log` files, `/tmp/plan-253-executor-registration-assertions.log`,
  and `/tmp/plan-253-executor-registration-dry-run.log`.
- **Curated gate:** clean c9b1 `./scripts/run_test_gates.sh 1to1` passed 1,672
  tests before the harness correction and again afterward at
  `/tmp/plan-253-executor-clean-c9b1-1to1-after-smoke-fix.log`.
- **Smoke regression correction:** the exact 6b case passes at b1d0 and fails at
  c9b1 (`expected 1`, `actual 0`) because the new wake-lock reaches the plugin.
  After the fake-driver reset, exact 6b and the complete 11-test smoke file pass
  in both main and detached evidence trees. Logs:
  `/tmp/plan-253-executor-clean-b1d0-share-smoke-6b.log`,
  `/tmp/plan-253-executor-clean-c9b1-share-smoke-6b.log`, and the four
  `*-smoke-*-fixed*.log` files.
- **Analyzer/hygiene:** clean b1d0 and c9b1 analyzers both report 1,626 existing
  issues; their diff contains only one shifted line and timing. The smoke fix
  compiles in all tests above. Main and detached `git diff --check` pass.
  Evidence: `/tmp/plan-253-executor-clean-b1d0-analyze.txt`,
  `/tmp/plan-253-executor-clean-c9b1-analyze.txt`, and
  `/tmp/plan-253-executor-clean-analyzer-b1d0-to-c9b1.diff`.
- **Required family blocker:** clean c9b1 `feature-host-all` passed items 1-686
  after item 641's ignored iOS fixture was exposed through a symlink, then item
  687 `background_choice_control_test.dart` failed two copy assertions. The
  same test fails identically on clean b1d0 and the relevant settings/l10n paths
  do not differ between b1d0 and c9b1. The original inventory passed every
  other item in 688-705; its item 701 failure is now covered by the corrected
  full smoke file and post-fix 1:1 lane. This is
  `unrelated-but-required`, not waived and not editable under Plan 253.
- **DP-01 PASS:** live targets were physical Pixel 6 `21071FDF600CSC` (API 36)
  and Android emulator `emulator-5554` (API 35). The exact Plan-253 production
  profile APK was built, installed, and used after automated mutual-contact
  provisioning. Files by Google selected one image+video batch, the system
  share sheet chose MKnoon, and the profile picker sent to the eligible contact.
  The fixture files were tiny (3.22 KB selected / 4.5 KB processed total) but
  remained observable in the screen recording.
  The recording shows `Uploading media` at `1.3 KB / 4.5 KB`, then localized
  `Sending…` at `4.5 KB / 4.5 KB`; values are monotonic, never exceed total,
  completion returns to home, and no SnackBar appears. The emulator renders one
  combined image+video message via cellular relay. Evidence is the multi-send
  recording/contact sheets, representative extracted frames, final UI dump,
  and receiver screenshot listed in the final progress row.
- **Remaining uncertainty:** no Plan-253 behavior or device observation remains
  open. Acceptance is blocked solely by the required family gate's inherited
  item 687 until its owner/controller supplies a valid disposition or fix, then
  reruns/resumes `feature-host-all` and assigns independent QA.
- **Graph/index safety:** this Executor did not refresh Graphify, commit, stage,
  amend, or alter the index. The earlier external `## Execution Result` records a
  separate tdd-exec graph refresh; this handoff does not claim or repeat it.

### Independent QA Review

- **Verdict:** `blocked` (`test_or_gate_failure`). **B1 is the only blocking
  finding.** The Plan-253 implementation, focused regressions, registrations,
  analyzer comparison, curated `1to1`, smoke isolation fix, and DP-01 evidence
  are otherwise sufficient and coherent.
- **Scope and behavior audit:** commit `c9b1ce6cb` is attributable against Plan
  236 base `b1d043eb3`; its caller/callee/test seam consistently carries media
  on the four first outgoing publications, tracks strict active upload IDs with
  per-upload clamping and cumulative totals, renders determinate upload/sending
  state, removes external-picker SnackBars, preserves failed-only retry, and
  balances route/wake-lock lifecycle. Current main-worktree overlap in the
  coordinator, wired picker, and `run_test_gates.sh` is concurrent work and was
  excluded through the detached c9b1 evidence tree; the only additional
  Plan-253 change is the attributable smoke-test fake wake-lock reset.
- **Resolved evidence:** TC-01/02/03/04 mutations fail causally and restore;
  TC-01–TC-11, TC-03B, and TC-09 baseline/final pass. The five clean focused
  suites pass 137/18/21/16/1 tests; TC-02 occurs exactly once in each 1:1 array
  and appears in the host dry-run; clean post-smoke-fix `1to1` passes 1,672
  tests; the full smoke file passes 11 tests; b1d0 and c9b1 analyzer outputs are
  equal at 1,626 existing issues with only a line-number/timing diff; diff
  hygiene is clean. Direct inspection of the DP-01 recording/contact sheets,
  final home UI, and receiver frame confirms the combined `+1` image/video
  batch, visible `Uploading media` progress followed by `Sending…` at 4.5 KB /
  4.5 KB, route completion without a SnackBar, and one combined image/video
  message received via cellular relay.
- **B1 — blocking / required family gate remains red:** clean
  `feature-host-all` reaches item 687,
  `test/features/settings/presentation/widgets/background_choice_control_test.dart`,
  where two copy assertions fail. The same two assertions fail on clean
  `b1d043eb3`, and settings/l10n paths are unchanged by `c9b1ce6cb`, so the
  failure is pre-existing and unrelated; however, the preflight contract and
  governing gate contain no allowance for accepting a required gate failure.
  Required disposition: repair/disposition item 687 outside Plan 253, then run
  the complete required family gate to exit 0. Verification:
  `./scripts/run_host_test_gates.sh feature-host-all`. Evidence:
  `/tmp/plan-253-executor-clean-c9b1-feature-host-all-resume-641-symlink.log`
  and `/tmp/plan-253-executor-clean-b1d0-background-choice-baseline.log`.
- **N1 — low / stale artifact names:** the handoff names representative DP-01
  frames `052/056/060`, but those individual files are absent; the recording,
  contact sheets, frames `01`–`30`, UI dump, and receiver screenshot are present
  and sufficient, so this does not weaken DP-01. Required disposition: correct
  the handoff names or retain the referenced frames on the next evidence pass.
  Verification: `ls /tmp/plan-253-executor-dp01-multi-send-*.png`.

## Closure Audit — 2026-07-11 (supersedes the historical blocked result)

- **Final verdict:** `accepted`.
- **Blocker disposition:** `f029d131fc72d0850909eee53499bd3b21b5011c` corrected item 709's two stale Signal-copy assertions and committed the already-reviewed `FakeUploadWakeLockDriver` smoke isolation. The commit is test-only and changes no Plan-253 production behavior.
- **Required family gate:** `./scripts/run_host_test_gates.sh feature-host-all` exited 0 after all 731 planned commands on the closure worktree through `de0aabfd5`. This interactive runner session did not create a standalone log file; the command's final result was `PASS: host tests completed for scope: feature-host-all`.
- **Independent QA retry:** `accepted`. A bounded closure-delta audit verified the test-only item-709 repair in `f029d131f`, the conditional group/announcement lineage in `21b6b54e2`, the test-only `de0aabfd5` delta, and the complete 731-command family pass. B1 is cleared; N1 remains only non-blocking historical artifact-name debt.
- **Preserved evidence:** the original causal/mutation suites, exact registrations, 1,672-test `1to1` pass, analyzer parity, and combined image+video DP-01 recording/contact sheets/UI dump/receiver screenshot remain authoritative. No later production commit changed the native intake, first-publication media, progress accounting, picker lifecycle, or device behavior exercised by DP-01.
- **Graphify:** the original execution already refreshed the Plan-253 production graph. The blocker fix and later Plan-254 acceptance-strengthening commit are test-only, so no additional Plan-253 architecture refresh is required.
- **Maintenance rule:** keep this plan closed unless immediate first-frame media, bounded upload progress, picker lifecycle protection, or external-share delivery regresses.
