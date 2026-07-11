# 231 - 1:1 Received Media Core Actions

Status: implemented (host-green)
Type: Feature Improvement
Spec: free-text intent — direct-chat incoming image/video viewer and bubble parity for Save, Share, Delete for Me, Info, and Reply
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; `conversation_screen.dart`; `conversation_wired.dart`; `message_context_overlay.dart`; `full_screen_image_viewer.dart`; delete use case/tests; viewer/action tests; l10n; plans 227/230 contract | Save/Share/Delete/Info/Reply have source-grounded seams and host closure. Reporting has materially different authority/privacy decisions and is isolated in plan 244. | Author the complete RED set before production edits; keep Report absent until plan 244 is decision-ready. |
| 2026-07-10 | Planner | revised plan 228 owner-lane/read-delete contract; `delete_message_use_case.dart` attachment calls; direct action/viewer fixtures | Direct actions must carry `MediaOwnerLane.direct`; whole-message cleanup must call owner-aware attachment APIs and preserve same-message-ID group and unresolved rows/files. | Add owner-recording action fixtures and a real collision deletion case before execution. |
| 2026-07-10 | Counterexample Reviewer / Planner | implemented plan-227 service API/policy boundary; `LetterCard`/`MediaGrid` gestures; one-message viewer construction; wired transport imports/calls; current owner-aware deletion test/gates | PLAN FIXES REQUIRED: egress API/authority was stale, bubble identity was message-wide, cross-message swipe exceeded this slice, import-only transport proof was vacuous, and deletion owner-scoping was already complete under a differently named sentinel. | Rebase controller, identity, wired bypass, deletion evidence and gate contracts before execution. |

## Problem And Evidence

- Behavior to improve: a user viewing or long-pressing an incoming direct-chat image/video must get the same eligible actions: Save to Photos, Save to Files, Share externally, Delete for Me, Info, and Reply.
- Impact: HEAD's viewer is a playback surface only, while the useful existing Delete/Reply actions are hidden behind a message-level long press. The mismatch makes ordinary received-media management undiscoverable.
- Confirmed current gap: `FullScreenImageViewer` accepts paths and an optional video builder only at `lib/shared/widgets/media/full_screen_image_viewer.dart:19`; its app bar contains only Back and the page counter at `:62-79`.
- Confirmed current mechanism: `ConversationScreen.mediaTapHandler` builds the viewer from only the tapped message's completed paths at `lib/features/conversation/presentation/screens/conversation_screen.dart:596-628`; no message/attachment action identity reaches the route.
- Confirmed identity gap: `LetterCard` installs one full-row `VoidCallback` long press (`lib/features/conversation/presentation/widgets/letter_card.dart:838`), while `MediaGrid` propagates an attachment index only for taps (`lib/shared/widgets/media/media_grid.dart:14`). A two-attachment bubble cannot tell the action layer which attachment was pressed.
- Confirmed current mechanism: the long-press overlay exposes Reply/Edit/Copy/Delete only (`lib/features/conversation/presentation/widgets/message_context_overlay.dart:16-39`, `:286-316`). Reply is routed to the quote composer and Delete to the wired layer at `conversation_screen.dart:929-953`.
- Confirmed delete behavior: `_onDeleteMessage` routes incoming rows to `deleteMessageForMe` (`conversation_wired.dart:1868-1902`), and that use case removes the message, reactions, attachment rows, and owned files without a network send (`delete_message_use_case.dart:17-47`, `:435-463`).
- Confirmed dependency state: plan 228 owner-aware direct cleanup is already implemented in `cleanupDeletedMessageArtifacts` (`delete_message_use_case.dart:442-460`). The current collision sentinel is `delete_message_use_case_test.dart::delete for me cleanup preserves same id group and unresolved media` at `:151`; Plan 231 must preserve and strengthen it rather than schedule owner-scoping again.
- Confirmed egress contract: `ReceivedMediaEgressService.perform` accepts `requestId`, `MediaEgressDestination` and `List<ReceivedMediaEgressCandidate>` (`lib/core/media/received_media_egress_service.dart:27`). Plan 227 deliberately leaves incoming/completion/integrity/expiry/protection qualification to lane adapters; the service validates only bounded identity/MIME/file/path structure.
- Confirmed boundary-test limitation: `conversation_wired.dart` legitimately imports and uses Bridge, P2P and send use cases for existing messaging behavior. A controller-only or forbidden-import assertion cannot detect a new media-action handler that bypasses the controller and invokes an existing delivery seam.
- Existing coverage: `conversation_screen_test.dart::long-press on incoming text shows the overlay and backdrop dismisses without side effects`; `::media-only long-press hides copy action`; `conversation_wired_test.dart::incoming rows only offer delete-for-me and cancel`; and `full_screen_image_viewer_test.dart::swipes between GIF and JPEG pages` cover the current partial behavior.
- Missing coverage: no test can fail for attachment-specific bubble identity, same-message viewer identity, different-message reopen identity, current-row egress requalification, viewer/bubble-to-wired controller use, native-egress delegation, media Info, unresolved-row exclusion, or non-default sibling state/file preservation during direct deletion.
- Refuted findings: "received direct media cannot be deleted" is refuted. Incoming rows already offer Delete for Me through long press (`conversation_wired_test.dart:5839-5883`). The real deletion gaps are discoverability and viewer access, not the underlying local-delete capability.
- Refuted findings: this work does not require a messaging transport change. Save/Share are owned by the transport-free plan 227 gateway, while Delete for Me and Info are local operations.
- Unresolved finding (non-blocking for this plan): HEAD has only contact blocking at `conversation_wired.dart:4196-4337`; no report sink or report localization exists under `lib/`. Plan 244 owns report authority, payload/privacy, retention/side effects, and offline/result decisions; this plan neither renders nor fakes Report.
- Affected production, test, and gate files: plan-230 typed viewer/action APIs; `MediaGrid`/`MediaGridCell`/`LetterCard` attachment-long-press propagation; `conversation_screen.dart`; `conversation_wired.dart`; `message_context_overlay.dart`; a new direct-media action controller/eligibility qualifier; three ARBs/generated l10n; focused controller/screen/wired/delete tests; `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`.

## Scope Contract And Guard

In scope:
- Adapt direct-chat media to plan 230 `MediaViewerItem` values carrying `MediaOwnerLane.direct`, stable attachment/message identity, path/kind, caption, sender/timestamp, availability, and protection display fields. Viewer metadata is presentation state, never egress authority. Missing or `unresolved` ownership yields no action-bearing item.
- Use plan 230's optional action capabilities/callbacks so the viewer action targets the currently visible item after every page change.
- Add `onMediaLongPress(int visualIndex)` from `MediaGridCell` through `MediaGrid` and `LetterCard`. Long-pressing a media cell opens attachment-specific media actions; long-pressing the remaining row keeps the existing whole-message context behavior. Two attachments in one message must never collapse to “first attachment.”
- Keep a direct viewer bounded to the tapped message's eligible attachments. Swiping proves attachment identity changes within that one parent message; conversation-wide navigation remains plan 233. A separate close/reopen/controller test proves different-message identity without creating a cross-message viewer list.
- Freeze a controller input to stable `DirectReceivedMediaActionIdentity(messageId, attachmentId)`, not a path/MIME/protection snapshot. Immediately before Save/Share, reload the current parent message and `MediaOwnerLane.direct` attachment row, require the exact attachment ID and current incoming/live message, then apply a fail-closed direct-lane qualifier for completion/file presence, integrity, expiry and protection. Plan 234 may supply future durable private-media policy; Plan 231 does not invent its storage, and absence of a qualifying current row/policy decision denies egress.
- Construct exactly one `ReceivedMediaEgressCandidate(attachmentId, storedPath, mime)` from the qualified current row and call `ReceivedMediaEgressService.perform(requestId:, destination:, selection: [candidate])` for Photos, Files or Share. Display typed cancel/denied/missing/failure feedback without changing the source. No `MediaEgressRequest` is constructed by the lane and no nonexistent `shareExternally` service method is claimed.
- Route Delete for Me through the existing whole-message confirmation/use case, label it as message deletion rather than single-attachment deletion, and preserve a same-message-ID group attachment plus unresolved legacy rows/files. Owner-aware direct cleanup is a completed dependency and remains a strengthened `GREEN sentinel`, not Plan-231 production work.
- Show local Info from persisted metadata without network access.

Must preserve:
- Outgoing delivered/inboxed messages still offer Delete for Everyone -> `test/features/conversation/presentation/screens/conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone`; `GREEN sentinel`.
- Incoming Delete for Me remains local and cleans only direct-owned artifacts -> `test/features/conversation/application/delete_message_use_case_test.dart::delete for me cleanup preserves same id group and unresolved media`; strengthened `GREEN sentinel` with non-default sibling viewer state and both sibling paths.
- Plan 228 owner/bookmark/playback state for the same-ID group sibling and unresolved rows remains byte-for-byte unchanged during a direct delete -> TC-231-05.
- Quote reply still focuses the composer and targets the owning message -> existing `conversation_screen_test.dart` long-press reply coverage plus TC-231-07.
- Page swipe/video behavior supplied by plan 230 remains intact -> `test/shared/widgets/media/full_screen_image_viewer_test.dart`; `GREEN sentinel`.

Hard `Do not`:
- Do not implement internal forwarding (plan 232), shared-media library/batch work (plan 233), or private-media lifecycle policy (plan 234) here.
- Do not add item-only attachment deletion, silently relabel whole-message deletion, or delete a Photos/Gallery/Files copy.
- Do not call P2P, Bridge, relay, inbox, group publish, announcement, or Go code for these actions.
- Do not add a Report action or gateway here; plan 244 owns that separately.
- Do not expose or dispatch Save/Share for pending, downloading, evicted, missing, integrity-failed, expired, protected, deleted-parent, outgoing, wrong-attachment, or unresolved media. The direct controller/lane qualifier is policy authority; plan 227 is only the final structural path/MIME/file authority.
- Do not infer owner from `message_id`, default an omitted owner to direct, expose `unresolved` items, or call an untyped attachment load/delete/failure seam.
- Do not use viewer/caption/path metadata as action authority, call `ReceivedMediaEgressGateway` from UI/lane code, invoke ShareTargetPicker/delivery/send from external Share, or broaden the viewer across parent messages.

Deferred / accepted difference:
- Individual attachment deletion while preserving the parent message -> owner future attachment-deletion product plan; this plan deliberately uses the already-correct whole-message Delete for Me contract.
- Conversation-wide media navigation and batch selection -> plan 233.
- Received-media reporting -> plan 244; absence of Report is an accepted staged difference, not a blocker for this action slice.
- Group and announcement surface parity -> plans 235 and 239.

Dependencies:
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` for `ReceivedMediaEgressService.perform`, `ReceivedMediaEgressCandidate`, destinations and typed results. The raw gateway remains foundation-internal and is not a lane dependency.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` for `MediaViewerItem`, `MediaViewerActionCapabilities`, and the optional current-item action callback.
- Revised `Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md` must land first for `MediaOwnerLane.direct`, unresolved-row exclusion, and owner-aware per-message load/delete APIs.
- `Test-Flight-Improv/244-1to1-received-media-reporting-tdd-plan.md` is a deferred sibling, not an execution dependency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-231-01 | Attachment-specific long press on eligible incoming direct-owned visual media exposes each core action exactly once; text/row long press keeps existing message actions, while deleted, unresolved-owner and outgoing variants gain no invalid media action. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::attachment long press exposes direct media actions without replacing row context` | widget host / two-attachment message, direct/group/unresolved item matrix, action callbacks | HEAD causal RED: `LetterCard` has only one row-wide long press -> long-pressing cell A/B records its exact index/attachment; long-pressing non-media row space retains current Reply/Delete/Copy policy; unresolved calls zero controller callbacks; Report remains absent | wire one row callback to every cell, default unresolved to direct, duplicate a core key, replace message context, or expose Report -> TC-231-01 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'attachment long press exposes direct media actions without replacing row context'`; AUTO (`test/features/**`) + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-231-02 | Bubble and viewer expose the same eligible actions for two attachments in one message, and a swipe changes every target attachment while retaining the same owning message/direct lane. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::same message bubble and viewer parity follows selected attachment` | widget host / one message with heterogeneous attachment A/B, plan-230 typed viewer, strict identity recorder | HEAD causal RED: viewer receives paths only and bubble lacks attachment long press -> action-key parity holds; cell A/B and page A/B callbacks carry attachment A/B respectively, the same parent message and `direct`, never a stale initial attachment | retain initial attachment in closure, use grid index against an unfiltered list, change parent on swipe, or omit/flip owner -> TC-231-02 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'same message bubble and viewer parity follows selected attachment'`; AUTO + both 1:1 arrays as TC-231-01 |
| TC-231-02R | Closing and reopening from different messages reconstructs action identity from the newly selected message/attachment; no conversation-wide swipe list is introduced. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::viewer reopen switches parent identity without cross message navigation` | widget/controller host / message A and message B with distinct attachment IDs plus route/controller recorder | HEAD causal RED: typed route identity absent -> open A/action/close/open B/action records `(msgA,attA)` then `(msgB,attB)`; each viewer contains only its parent's items; fresh controller re-read returns B, never cached A | cache the first parent, concatenate conversation media, or key by path/index -> TC-231-02R red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'viewer reopen switches parent identity without cross message navigation'`; AUTO + both 1:1 arrays |
| TC-231-03 | Photos/Files Save and Share reload and qualify the current direct parent/attachment immediately before egress, construct one current-row candidate, call `ReceivedMediaEgressService.perform` once, and surface typed outcomes truthfully. | `test/features/conversation/application/received_media_action_controller_test.dart::egress reloads current direct row and delegates one qualified candidate` | application host / mutable message+owner-aware attachment repositories, recording service, temp source and lane qualifier | HEAD compile RED: controller absent -> stale eligible viewer identity succeeds only while the current row remains incoming/live/done/present/integrity-valid/unexpired/unprotected; destination maps exactly and source bytes/rows remain unchanged | construct candidate from viewer path/MIME, skip parent/row reload, map Files to Photos, call twice, or mutate source -> TC-231-03 red | `flutter test test/features/conversation/application/received_media_action_controller_test.dart --plain-name 'egress reloads current direct row and delegates one qualified candidate'`; AUTO + add file to both 1:1 arrays |
| TC-231-03N | Pending/downloading, missing-file, integrity-failed, expired, protected, deleted/outgoing-parent, wrong-attachment and unresolved/wrong-owner states produce a typed denial with zero egress-service calls. | `test/features/conversation/application/received_media_action_controller_test.dart::current row policy denies every ineligible direct egress state` | application host / table-driven mutable current rows, file fixtures and recording qualifier/service | HEAD compile RED -> each state is distinguished at the lane boundary; service call count stays zero; stale viewer capabilities/path cannot override current truth | trust `MediaViewerProtection`, fall back to passed path/MIME, default missing qualifier/owner to allow/direct, or defer denial to native service -> TC-231-03N red | `flutter test test/features/conversation/application/received_media_action_controller_test.dart --plain-name 'current row policy denies every ineligible direct egress state'`; AUTO + both 1:1 arrays |
| TC-231-04 | External Share maps to `MediaEgressDestination.share` through the same `perform` call and never invokes an internal picker, delivery coordinator, send function or P2P operation. | `test/features/conversation/application/received_media_action_controller_test.dart::external share performs native egress with zero delivery calls` | application host / recording service + throwing ShareBatch/send/P2P spies | HEAD compile RED -> exactly one `perform(requestId, share, [currentCandidate])` call, typed outcome and zero delivery calls | add a `shareExternally` fiction, route through `ShareTargetPickerWired`/delivery, or call raw gateway -> TC-231-04 red | `flutter test test/features/conversation/application/received_media_action_controller_test.dart --plain-name 'external share performs native egress with zero delivery calls'`; AUTO + both 1:1 arrays |
| TC-231-05 | Viewer Delete closes viewer/menus, presents one Delete-for-Me choice and invokes the existing whole-message direct cleanup; the current strengthened owner-collision sentinel remains green. | `test/features/conversation/application/delete_message_use_case_test.dart::delete for me cleanup preserves same id group and unresolved media`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::viewer delete invokes existing direct whole message cleanup` | strengthened `GREEN sentinel` plus causal widget host / real DB v96 collision, owner-recording wired callback, non-default sibling bookmark/playback and group+unresolved file paths | Use-case sentinel is GREEN on HEAD because plan 228 already typed cleanup; viewer test is causal RED -> direct parent/rows/owned files are removed, while byte-identical same-ID group and unresolved rows with non-default state and both files survive; no Delete for Everyone or item-only deletion | weaken fixture to defaults/no unresolved path, delete by message ID, call Delete for Everyone, or delete only selected attachment -> TC-231-05 red | exact commands below; retain delete test in both 1:1 arrays and add `conversation_wired_test.dart` to `ONE_TO_ONE_HOST_TESTS` |
| TC-231-06 | Info shows owning message sender/direction/date plus selected attachment MIME, byte size, dimensions or duration, and current download/integrity state. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::info follows selected attachment within one message without transport reads` | widget host / one message with two heterogeneous typed items + persisted lookup fake | HEAD causal RED: no Info UI -> attachment A/B local metadata changes after page selection while parent metadata stays fixed; no key/nonce/raw path is displayed | bind to first attachment, trust path identity, expose encryption metadata, change parent, or omit video duration -> TC-231-06 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'info follows selected attachment within one message without transport reads'`; AUTO + both 1:1 arrays |
| TC-231-07 | Reply from bubble or viewer targets the owning message, closes transient UI, and focuses the existing quote composer. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::viewer and bubble reply quote the owning message exactly once` | widget host / callback recorder | HEAD partial RED: bubble path works but viewer path is absent -> both paths produce the same message id once and the quote preview appears | pass attachment id instead of message id or fail to close viewer -> TC-231-07 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'viewer and bubble reply quote the owning message exactly once'`; AUTO + both 1:1 arrays |
| TC-231-08 | Existing sender-authorized Delete for Everyone remains available and keeps its encrypted delivery path unchanged. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone` | `GREEN sentinel` / existing widget fixture | GREEN on HEAD -> remains GREEN after action refactor | gate delete-for-everyone on incoming-media capabilities or route it through local delete -> sentinel red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`; existing `ONE_TO_ONE_TESTS`; retain/add file in `ONE_TO_ONE_HOST_TESTS` |
| TC-231-09 | Egress has one exact production call site: only `received_media_action_controller.dart` may call `ReceivedMediaEgressService.perform`; UI files invoke callbacks/controller only, raw gateway use is absent, and existing wired transport call sites stay on an explicit pre-plan allowlist. | `test/features/conversation/application/received_media_action_transport_boundary_test.dart::received media egress call sites and wired transport baseline are exact` | host source-contract / exact file and symbol/callsite allowlists, controller import allowlist and recorded existing wired send/P2P method inventory | HEAD compile RED: controller/callsite absent -> exactly one service `perform` call in controller; zero gateway/channel/ShareTargetPicker/ShareBatch calls in media-action files; `ConversationWired`'s pre-existing Bridge/P2P/send imports/calls match the allowlist with no new action-handler delivery call; Go/relay baseline unchanged | assert imports only, add second perform/raw gateway, call existing send seam from action handler, or broaden allowlist after implementation -> TC-231-09 red | `flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart --plain-name 'received media egress call sites and wired transport baseline are exact'`; AUTO + both 1:1 arrays; status/binary baseline below |
| TC-231-09W | Bubble and viewer Save/Share traverse the real screen-to-wired-to-controller seam and cannot bypass it through delivery APIs. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::bubble and viewer media egress use controller with zero delivery calls` | widget/application host / real ConversationScreen/Wired callbacks, recording egress service, mutable current repo, throwing send/P2P/ShareBatch/picker seams | HEAD causal RED: UI/controller wiring absent -> bubble attachment long press and current viewer action each reach controller once with exact identity/destination; delivery spies remain zero/throw-free; stale row denial reaches no egress or delivery | leave controller unused, call sender/picker directly from either surface, or pass first attachment identity -> TC-231-09W red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'bubble and viewer media egress use controller with zero delivery calls'`; existing `ONE_TO_ONE_TESTS`; add file to `ONE_TO_ONE_HOST_TESTS` |
| TC-231-10 | Long localized labels remain reachable on a small screen and Arabic uses RTL without overflow or action loss. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::core media actions stay reachable in German and Arabic small viewports` | widget host / `de` and `ar`, 320x568 viewport | HEAD causal RED: labels/actions absent -> scrollable/reflowed menu exposes every eligible key with no exception | restore fixed action-count height or hardcode English labels -> TC-231-10 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'core media actions stay reachable in German and Arabic small viewports'`; AUTO + both 1:1 arrays; `flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'` existing direct check |

### Test Notes

- TC-231-01/02 propagate the visual attachment index after the same image/video filtering used for tap/viewer construction. A cell long press must win gesture targeting over the row detector without disabling the row-wide message context outside media.
- TC-231-02/06 deliberately use two attachments from one message because HEAD's viewer is message-bounded. TC-231-02R separately closes stale different-message identity by closing/reopening and recreating/reusing the controller against mutable repositories; no test may concatenate conversation history into the viewer.
- TC-231-03/03N pass only stable IDs into the controller. The recording egress service must receive the path and MIME from the reloaded row, not from the viewer item. “Expired/protected” is supplied by the direct-lane qualifier contract; durable private-media storage/lifecycle remains plan 234.
- TC-231-05 reuses the already owner-aware whole-message delete contract. Strengthen its existing fixture before using it as evidence: seed non-zero bookmark/playback values on the same-ID group and unresolved rows, give both sibling rows distinct local paths/files, compare raw rows byte-for-byte, and assert neither sibling file path is deleted. The confirmation copy must say that the message and all its attachments are removed from this device.
- TC-231-09 freezes the pre-change wired transport callsite inventory before production edits. Existing Bridge/P2P/send imports are allowed only at their named baseline methods; they are not blanket permission for media-action handlers. TC-231-09W is the behavioral discriminator that proves the controller is actually wired.
- TC-231-01 explicitly asserts that Report is absent, preventing this plan from accidentally shipping a no-op, analytics-only, or local-Block substitute before plan 244.

## Implementation Steps

1. Snapshot `git status --short`; record unrelated changes and the exact existing `ConversationWired` transport callsite allowlist. Add the new causal rows before production edits; run the existing deletion sentinel first as GREEN under its real test name, then strengthen its fixture without changing production behavior.
2. Keep Report absent and plan-244-owned while adapting direct messages/attachments to plan 230 `MediaViewerItem` and action capabilities.
3. Add attachment-specific long-press/index propagation through `MediaGridCell`/`MediaGrid`/`LetterCard`, preserving the existing row-long-press behavior. Build message-bounded typed viewer items and close/reopen identity without conversation-wide navigation.
4. Add the local controller with stable-ID input, immediate current parent/direct-row reload, fail-closed direct-lane qualification, and the exact `ReceivedMediaEgressService.perform(... selection: [ReceivedMediaEgressCandidate(...)])` call. Route Info to current local metadata, Reply to the quote callback, and Delete to the existing whole-message use case. Do not edit owner scoping inside `delete_message_use_case.dart`; it is already complete. Stop-if any action trusts viewer path/policy, defaults ownership, or requires a delivery/P2P/report dependency.
5. Wire bubble/viewer callbacks through `ConversationWired` to the controller and prove throwing delivery seams are untouched. Add the exact callsite/allowlist source contract; do not use import-only assertions for the transport-owning wired file.
6. Add three-locale copy and generated l10n; register new headline tests and `conversation_wired_test.dart` in both 1:1 arrays.
7. Run focused GREEN, strengthened deletion and existing preservation sentinels, named gates, and representative stale-row/identity/bypass mutations.

## Risks And Blind Spots

- Attachment/page/reopen changes can leave actions bound to stale media -> TC-231-01/02/02R/06.
- Viewer capability metadata can become stale before irreversible egress -> TC-231-03/03N reload current durable direct state immediately before service invocation.
- External export is irreversible -> plan 227 owns native safety; UI copy must not promise later revocation.
- Lifecycle / derived-state durability: TC-231-02R/03 reconstruct identity and eligibility from current repositories after viewer/controller reopen; durable library navigation remains plan 233.
- Sibling-surface consistency: TC-231-01/02/07 compare bubble and viewer contracts directly.
- Destructive-action side effects: TC-231-05's strengthened existing sentinel asserts direct removals and byte-identical preservation of same-ID group/unresolved rows, non-default viewer state and both files.
- Invariant re-verification under new transitions: closing viewer/menu before Reply/Delete rechecks `mounted` and current message existence; TC-231-05/07 cover re-entry and exactly-once behavior.
- Wired-layer bypass through existing transport dependencies -> TC-231-09 pins exact call sites/allowlist and TC-231-09W drives both UI surfaces with throwing delivery seams.
- Report privacy/authority is not source-resolvable -> plan 244 owns it and TC-231-01 keeps it absent here.

## Gate Cadence

- Per-plan closure runs the focused controller/widget/wired tests, exact shared/deletion/l10n sentinels, and the curated `./scripts/run_test_gates.sh 1to1` lane gate. These tests cover the direct-chat production surface without a feature-tree sweep.
- Do not run `feature-host-all`, `core-host-all`, or full `host-all` as Plan 231 acceptance. Full `host-all` runs once after the complete core-actions wave, and again at final received-media rollout closure; the wave runner owns that aggregate evidence.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-231-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-231-go-relay-diff.before

# First causal RED; expect non-zero because media action keys/controller/owner contract are absent
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'attachment long press exposes direct media actions without replacing row context'

# Existing owner-aware deletion baseline is already GREEN; this exact target
# must select and pass before its non-default-state/file fixture is strengthened.
flutter test test/features/conversation/application/delete_message_use_case_test.dart --plain-name 'delete for me cleanup preserves same id group and unresolved media'

# Focused GREEN for this bounded action slice; expect exit 0
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/application/received_media_action_controller_test.dart
flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart --plain-name 'received media egress call sites and wired transport baseline are exact'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'viewer delete invokes existing direct whole message cleanup'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'bubble and viewer media egress use controller with zero delivery calls'
flutter test test/features/conversation/application/delete_message_use_case_test.dart --plain-name 'delete for me cleanup preserves same id group and unresolved media'

# Preservation; expect exit 0 and named target selection
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'
./scripts/run_test_gates.sh 1to1

# Hygiene; expect no new issues or whitespace errors
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-231-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-231-go-relay-diff.before
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-231-01 fails because media cells lack attachment-specific long press and the overlay/viewer lack the new action/identity contract. The existing deletion command is GREEN baseline evidence, not causal RED.
- Green sentinel: strengthened incoming direct cleanup, outgoing Delete for Everyone, quote reply, row context and message-bounded viewer swipe tests remain green.
- Pre-existing dirty tree / known failure: snapshot at execution; do not absorb unrelated changes or pre-existing l10n literal-scan debt into this plan.
- Environment blocker: none for this host slice; reporting decisions live outside its closure bar.
- Scope drift: any forwarding, gallery, schema, group/announcement, transport, relay, or Go edit blocks completion.

- [x] Every behavior has a named test and honest RED/sentinel disposition.
- [x] Save/Share reload current message/direct attachment, deny every stale/ineligible matrix state, and call exactly one service `perform` with one current-row candidate.
- [x] Bubble long press and message-bounded viewer target the selected attachment; close/reopen switches parent identity without adding conversation-wide navigation.
- [x] Source callsite inventory and behavioral throwing-spy tests prove both UI surfaces use the controller and no delivery/share-picker bypass.
- [x] The existing deletion sentinel uses its real name and non-default group/unresolved state plus two preserved sibling file paths.
- [x] Focused, preservation, and the curated 1:1 gate pass with target discovery; no feature-wide or full-host sweep is required per plan.
- [x] New tests and `conversation_wired_test.dart` are present in both 1:1 arrays.
- [x] Representative current-page owner (grid first-cell identity), unresolved eligibility, Files→Photos destination, and same-ID sibling cleanup mutations re-red; Report absence is a standing TC-231-01 assertion.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'attachment long press exposes direct media actions without replacing row context'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`.
- Manual registration: add the three new direct-media action files to `scripts/run_test_gates.sh::ONE_TO_ONE_TESTS` for per-plan selection and to `scripts/run_host_test_gates.sh::ONE_TO_ONE_HOST_TESTS` for later wave-level inventory; add existing `conversation_wired_test.dart` to `ONE_TO_ONE_HOST_TESTS` (it is already in `ONE_TO_ONE_TESTS`). Per-plan closure does not run `feature-host-all`.
- Migration: none.
- Boundary closure: host-only lane wiring; plan 227 separately owns Android/iOS egress device proof.
- Unresolved evidence: none for this slice. Reporting decisions are explicitly deferred to evidence-gated plan 244 and do not block implementation.

## Reviewer Findings

- Verdict received 2026-07-10: `plan-fixes-required`; the user-visible action gap and host closure remain confirmed.
- Accepted API/authority correction: lane code now reloads current direct state, applies current lane eligibility, constructs `ReceivedMediaEgressCandidate`, and calls `ReceivedMediaEgressService.perform`. Plan 227 remains structural egress authority, not message/protection authority.
- Accepted identity correction: media-cell long press carries attachment index; swipe parity is tested with two attachments in one message; different-parent identity is closed by viewer/controller reopen without taking plan 233's conversation-wide navigation.
- Accepted bypass correction: exact source callsites and an allowlisted existing wired transport baseline are paired with bubble/viewer-to-wired tests using recording egress and throwing delivery seams.
- Accepted stale-evidence correction: owner-aware direct deletion is already implemented. TC-231-05 now uses the real existing sentinel name, strengthens non-default sibling state/files, removes duplicate production work, and requires `conversation_wired_test.dart` in the host 1:1 gate.
- Qualified scope: Plan 231 freezes a fail-closed protection/expiry qualifier but does not invent private-media persistence or lifecycle; Plan 234 remains its owner.
- Planner disposition: all value-adding findings are incorporated; the revised plan is execution-ready after dependencies 227/228/230.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 | baseline | sentinel + `/tmp/plan-231-go-relay-*.before` | deletion sentinel GREEN under its real name; go/relay status+diff snapshots empty | 3 live sessions on tree noted; wired transport callsite inventory recorded (p2pService 16, bridge 25, send/edit/deleteFns 1 each, downloadMediaFn 2, prepareEncryptedMediaArtifactFn 4) | none | strengthen sentinel |
| 2026-07-10 | sentinel strengthened | `delete_message_use_case_test.dart` | GREEN | same-ID group + unresolved rows now carry non-default bookmark/playback and distinct paths/files; both sibling paths asserted un-deleted | none | author RED set |
| 2026-07-10 | RED | 3 new test files + wired test additions | first causal RED command failed (contract absent on HEAD) | compile RED recorded for TC-231-01 | none | production |
| 2026-07-10 | production | controller, sheets, screen, wired, grid-cell key, reaction-bar fit, 3 ARBs + gen-l10n | — | ADAPTED to parallel plan-235 session's already-landed shared surfaces (MediaViewerAction.reply/info, MediaGrid.onLongPressItem, MediaGridCell.onLongPress, LetterCard.onMediaLongPress, MessageContextOverlay save/share/info) — bubble media actions ride the shared context overlay instead of a new sheet, matching the group lane's UX | none | green + mutations |
| 2026-07-10 | GREEN + mutations | all | all focused files GREEN; 4 mutations re-red (unresolved-owner default, Files→Photos mapping, grid first-cell identity, cross-lane cleanup deletion) and reverted | TC-231-10 caught a real pre-existing 320px ReactionBar overflow (fires on ANY overlay at 320dp); fixed with FittedBox scale-down in `reaction_bar.dart` | none | gates |
| 2026-07-10 | acceptance | gates | `./scripts/run_test_gates.sh 1to1` GREEN (1562 tests, exit 0); preservation sentinels GREEN (outgoing delete-for-everyone, delete suite, both viewer suites, overlay/reaction suites, l10n integrity); go/relay cmp clean; `git diff --check` clean; analyze: no new issues (`prefer_function_declarations_over_variables` on `mediaTapHandler` pre-exists at HEAD:596) | wired transport inventory unchanged post-edit | none | close + commit |

### Execution Notes

- Shared-surface convergence: plan 235 (group lane) executed in a parallel session and landed the exact propagation/typed-viewer extensions this plan needed. Plan 231 consumed them rather than duplicating: the direct bubble menu is the shared `MessageContextOverlay` with Save/Share/Info entries targeted at the pressed attachment (key parity with the group lane), Save opens a new `DirectMediaSaveDestinationSheet` (Photos/Files → exact `MediaEgressDestination` mapping), and Info renders through the new `DirectReceivedMediaInfoSheet`.
- New production files: `lib/features/conversation/application/received_media_action_controller.dart` (single `perform` call site; stable-ID input; current-row reload; fail-closed direct-lane qualifier; typed denials) and `lib/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart` (destination chooser + info sheet, presentation-only).
- The default 1:1 media viewer is now the plan-230 `FullScreenTypedMediaViewer` (message-bounded typed items, `MediaOwnerLane.direct`, capabilities save/share/reply/info/delete); the injected `mediaViewerBuilder` test seam keeps the legacy path-based construction.
- Viewer/bubble Delete routes through `_onDeleteMediaMessage` → the existing whole-message sheet with new media-labeled prompt copy (`conversation_delete_media_message_prompt`, 3 locales); the use case was not touched.
