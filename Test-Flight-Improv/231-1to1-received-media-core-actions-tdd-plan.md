# 231 - 1:1 Received Media Core Actions

Status: execution-ready
Type: Feature Improvement
Spec: free-text intent — direct-chat incoming image/video viewer and bubble parity for Save, Share, Delete for Me, Info, and Reply
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; `conversation_screen.dart`; `conversation_wired.dart`; `message_context_overlay.dart`; `full_screen_image_viewer.dart`; delete use case/tests; viewer/action tests; l10n; plans 227/230 contract | Save/Share/Delete/Info/Reply have source-grounded seams and host closure. Reporting has materially different authority/privacy decisions and is isolated in plan 244. | Author the complete RED set before production edits; keep Report absent until plan 244 is decision-ready. |

## Problem And Evidence

- Behavior to improve: a user viewing or long-pressing an incoming direct-chat image/video must get the same eligible actions: Save to Photos, Save to Files, Share externally, Delete for Me, Info, and Reply.
- Impact: HEAD's viewer is a playback surface only, while the useful existing Delete/Reply actions are hidden behind a message-level long press. The mismatch makes ordinary received-media management undiscoverable.
- Confirmed current gap: `FullScreenImageViewer` accepts paths and an optional video builder only at `lib/shared/widgets/media/full_screen_image_viewer.dart:19`; its app bar contains only Back and the page counter at `:62-79`.
- Confirmed current mechanism: `ConversationScreen.mediaTapHandler` builds the viewer from only the tapped message's completed paths at `lib/features/conversation/presentation/screens/conversation_screen.dart:596-628`; no message/attachment action identity reaches the route.
- Confirmed current mechanism: the long-press overlay exposes Reply/Edit/Copy/Delete only (`lib/features/conversation/presentation/widgets/message_context_overlay.dart:16-39`, `:286-316`). Reply is routed to the quote composer and Delete to the wired layer at `conversation_screen.dart:929-953`.
- Confirmed delete behavior: `_onDeleteMessage` routes incoming rows to `deleteMessageForMe` (`conversation_wired.dart:1868-1902`), and that use case removes the message, reactions, attachment rows, and owned files without a network send (`delete_message_use_case.dart:17-47`, `:435-463`).
- Existing coverage: `conversation_screen_test.dart::long-press on incoming text shows the overlay and backdrop dismisses without side effects`; `::media-only long-press hides copy action`; `conversation_wired_test.dart::incoming rows only offer delete-for-me and cancel`; and `full_screen_image_viewer_test.dart::swipes between GIF and JPEG pages` cover the current partial behavior.
- Missing coverage: no test can fail for viewer/bubble parity, native-egress delegation, media Info, or current-page action identity.
- Refuted findings: "received direct media cannot be deleted" is refuted. Incoming rows already offer Delete for Me through long press (`conversation_wired_test.dart:5839-5883`). The real deletion gaps are discoverability and viewer access, not the underlying local-delete capability.
- Refuted findings: this work does not require a messaging transport change. Save/Share are owned by the transport-free plan 227 gateway, while Delete for Me and Info are local operations.
- Unresolved finding (non-blocking for this plan): HEAD has only contact blocking at `conversation_wired.dart:4196-4337`; no report sink or report localization exists under `lib/`. Plan 244 owns report authority, payload/privacy, retention/side effects, and offline/result decisions; this plan neither renders nor fakes Report.
- Affected production, test, and gate files: plan-230 typed viewer/action APIs; `conversation_screen.dart`; `conversation_wired.dart`; `message_context_overlay.dart`; a new direct-media action controller; three ARBs/generated l10n; focused conversation tests; `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`.

## Scope Contract And Guard

In scope:
- Adapt direct-chat media to plan 230 `MediaViewerItem` values carrying its defined stable attachment/message identity, path/kind, caption, sender/timestamp, availability, and protection fields; resolve additional Info metadata from the persisted direct message/attachment snapshots by those IDs rather than expanding the shared viewer ad hoc.
- Use plan 230's optional action capabilities/callbacks so the viewer action targets the currently visible item after every page change.
- Add the same eligible Save-to-Photos, Save-to-Files, external Share, Delete-for-Me, Info, and Reply entries to the incoming visual-media long-press surface.
- Delegate Save/Share only to plan 227 `ReceivedMediaEgressService` using `MediaEgressRequest/Result`; display typed cancel/denied/missing/failure feedback without changing the source.
- Route Delete for Me through the existing whole-message confirmation/use case; label it as message deletion, not single-attachment deletion.
- Show local Info from persisted metadata without network access.

Must preserve:
- Outgoing delivered/inboxed messages still offer Delete for Everyone -> `test/features/conversation/presentation/screens/conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone`; `GREEN sentinel`.
- Incoming Delete for Me remains local and cleans only owned artifacts -> `test/features/conversation/application/delete_message_use_case_test.dart::deleteMessageForMe removes message reactions attachments and owned files`; `GREEN sentinel`.
- Quote reply still focuses the composer and targets the owning message -> existing `conversation_screen_test.dart` long-press reply coverage plus TC-231-07.
- Page swipe/video behavior supplied by plan 230 remains intact -> `test/shared/widgets/media/full_screen_image_viewer_test.dart`; `GREEN sentinel`.

Hard `Do not`:
- Do not implement internal forwarding (plan 232), shared-media library/batch work (plan 233), or private-media lifecycle policy (plan 234) here.
- Do not add item-only attachment deletion, silently relabel whole-message deletion, or delete a Photos/Gallery/Files copy.
- Do not call P2P, Bridge, relay, inbox, group publish, announcement, or Go code for these actions.
- Do not add a Report action or gateway here; plan 244 owns that separately.
- Do not expose Save/Share for pending, missing, integrity-failed, expired, or protected media; plan 227 is the final eligibility authority.

Deferred / accepted difference:
- Individual attachment deletion while preserving the parent message -> owner future attachment-deletion product plan; this plan deliberately uses the already-correct whole-message Delete for Me contract.
- Conversation-wide media navigation and batch selection -> plan 233.
- Received-media reporting -> plan 244; absence of Report is an accepted staged difference, not a blocker for this action slice.
- Group and announcement surface parity -> plans 235 and 239.

Dependencies:
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` for `ReceivedMediaEgressGateway`, `ReceivedMediaEgressService`, and typed egress results.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` for `MediaViewerItem`, `MediaViewerActionCapabilities`, and the optional current-item action callback.
- `Test-Flight-Improv/244-1to1-received-media-reporting-tdd-plan.md` is a deferred sibling, not an execution dependency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-231-01 | Incoming visual-media long press exposes each eligible core action exactly once; text-only, deleted, missing, and outgoing-policy variants do not gain invalid core actions. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::incoming visual media long press exposes the eligible core action set` | widget host / `WidgetTester`, fake egress and callbacks | HEAD causal RED: overlay has Reply/Delete but no media Save/Share/Info contract -> every core keyed action/count and eligibility assertion passes without forbidding later sibling-owned Forward; Report remains absent pending plan 244 | remove the incoming-visual predicate, duplicate a core key, enable egress for a missing file, or expose an unimplemented Report key -> TC-231-01 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming visual media long press exposes the eligible core action set'`; AUTO (`test/features/**`) + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-231-02 | Viewer and bubble expose the same eligible actions, and a swipe changes every callback target to the current attachment/message. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::viewer and bubble action parity follows the current media page` | widget host / plan-230 fake viewer items | HEAD causal RED: viewer receives paths only and has no actions -> action-key parity holds; after swipe callbacks contain item B/message B, never stale item A | keep the initial item in the callback closure -> TC-231-02 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'viewer and bubble action parity follows the current media page'`; AUTO + both 1:1 arrays as TC-231-01 |
| TC-231-03 | Save to Photos and Save to Files delegate once with exact current metadata and surface success/cancel/denied/missing outcomes truthfully. | `test/features/conversation/application/received_media_action_controller_test.dart::save destinations delegate exact current attachment and preserve source` | application host / fake `ReceivedMediaEgressService`, temp source | HEAD compile RED: controller/action contract absent -> destination/request/result mapping is exact and source bytes/row callback remain unchanged | map Files to Photos, call twice, or delete source on failure -> TC-231-03 red | `flutter test test/features/conversation/application/received_media_action_controller_test.dart --plain-name 'save destinations delegate exact current attachment and preserve source'`; AUTO + add file to both 1:1 arrays |
| TC-231-04 | External Share delegates through plan 227 only and never invokes an internal share picker or messaging transport. | `test/features/conversation/application/received_media_action_controller_test.dart::external share uses native egress and has zero delivery calls` | application host / fake egress + throwing delivery spies | HEAD compile RED -> one `shareExternally` call, typed outcome, zero P2P/ShareBatch calls | route external Share through `ShareTargetPickerWired` or a delivery coordinator -> TC-231-04 red | `flutter test test/features/conversation/application/received_media_action_controller_test.dart --plain-name 'external share uses native egress and has zero delivery calls'`; AUTO + both 1:1 arrays |
| TC-231-05 | Viewer Delete on incoming media closes viewer/menus, presents one Delete-for-Me choice, and removes the whole local message plus owned artifacts. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::viewer delete for incoming media uses delete-for-me and cleans artifacts` | widget/application host / fake repositories and `MediaFileManager` | HEAD causal RED: viewer has no Delete callback -> one local use-case call; message/attachments/owned files removed; sibling rows/files preserved; no delete-for-everyone option | call delete-for-everyone, delete only the attachment row, or skip owned-file cleanup -> TC-231-05 red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'viewer delete for incoming media uses delete-for-me and cleans artifacts'`; existing `ONE_TO_ONE_TESTS`; add/retain in `ONE_TO_ONE_HOST_TESTS` |
| TC-231-06 | Info shows message sender/direction/date plus current attachment MIME, byte size, dimensions or duration, and download/integrity state. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::info sheet describes the current item without reading transport` | widget host / two heterogeneous typed items + persisted message/attachment lookup fake | HEAD causal RED: no Info UI -> stable IDs resolve item A/B local metadata after page change and no key/nonce/raw path is displayed | bind to the first item, trust path identity, expose encryption metadata, or omit video duration -> TC-231-06 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'info sheet describes the current item without reading transport'`; AUTO + both 1:1 arrays |
| TC-231-07 | Reply from bubble or viewer targets the owning message, closes transient UI, and focuses the existing quote composer. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::viewer and bubble reply quote the owning message exactly once` | widget host / callback recorder | HEAD partial RED: bubble path works but viewer path is absent -> both paths produce the same message id once and the quote preview appears | pass attachment id instead of message id or fail to close viewer -> TC-231-07 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'viewer and bubble reply quote the owning message exactly once'`; AUTO + both 1:1 arrays |
| TC-231-08 | Existing sender-authorized Delete for Everyone remains available and keeps its encrypted delivery path unchanged. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone` | `GREEN sentinel` / existing widget fixture | GREEN on HEAD -> remains GREEN after action refactor | gate delete-for-everyone on incoming-media capabilities or route it through local delete -> sentinel red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`; existing `ONE_TO_ONE_TESTS`; retain/add file in `ONE_TO_ONE_HOST_TESTS` |
| TC-231-09 | The 1:1 media action implementation is transport-free. | `test/features/conversation/application/received_media_action_transport_boundary_test.dart::core received-media actions import no bridge p2p relay group announcement or reporting modules` | host source-contract test | HEAD compile RED: target controller absent -> approved files contain only UI/local repository/egress dependencies and Go/relay paths remain equal to the recorded baseline | add a forbidden transport/report import/call or edit a Go/relay path -> TC-231-09 red | `flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart`; AUTO + add file to both 1:1 arrays; baseline status+binary-diff comparison below |
| TC-231-10 | Long localized labels remain reachable on a small screen and Arabic uses RTL without overflow or action loss. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::core media actions stay reachable in German and Arabic small viewports` | widget host / `de` and `ar`, 320x568 viewport | HEAD causal RED: labels/actions absent -> scrollable/reflowed menu exposes every eligible key with no exception | restore fixed action-count height or hardcode English labels -> TC-231-10 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'core media actions stay reachable in German and Arabic small viewports'`; AUTO + both 1:1 arrays; `flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'` existing direct check |

### Test Notes

- TC-231-02/06 must use items from different parent messages, not two attachments of one message, so a stale message-id closure cannot pass.
- TC-231-05 calls the existing whole-message delete contract. The confirmation copy must say that the message and all its attachments are removed from this device.
- TC-231-01 explicitly asserts that Report is absent, preventing this plan from accidentally shipping a no-op, analytics-only, or local-Block substitute before plan 244.

## Implementation Steps

1. Snapshot `git status --short`; record unrelated changes. Add TC-231-01..07 and TC-231-09/10 before production edits; confirm their documented RED reasons.
2. Keep Report absent and plan-244-owned while adapting direct messages/attachments to plan 230 `MediaViewerItem` and action capabilities.
3. Add direct-media action capabilities/callbacks to `ConversationScreen`/`ConversationWired`/`MessageContextOverlay`.
4. Add the local controller that delegates native egress to plan 227, Info to local metadata, Reply to the quote callback, and Delete to the existing whole-message use case. Stop-if any local action requires a Bridge/P2P/report dependency.
5. Add three-locale copy and generated l10n; register new headline tests in both 1:1 arrays.
6. Run focused GREEN, sentinels, named gates, and representative mutation re-reds.

## Risks And Blind Spots

- A page swipe can leave actions bound to stale media -> TC-231-02/06.
- External export is irreversible -> plan 227 owns native safety; UI copy must not promise later revocation.
- Lifecycle / derived-state durability: N/A — core actions are immediate; durable bookmarks/library state belong to plan 228/233.
- Sibling-surface consistency: TC-231-01/02/07 compare bubble and viewer contracts directly.
- Destructive-action side effects: TC-231-05 plus existing delete-use-case coverage assert both removals and sibling preservation.
- Invariant re-verification under new transitions: closing viewer/menu before Reply/Delete rechecks `mounted` and current message existence; TC-231-05/07 cover re-entry and exactly-once behavior.
- Report privacy/authority is not source-resolvable -> plan 244 owns it and TC-231-01 keeps it absent here.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-231-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-231-go-relay-diff.before

# First causal RED; expect non-zero because media action keys/controller are absent
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming visual media long press exposes the eligible core action set'

# Focused GREEN for this bounded action slice; expect exit 0
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/application/received_media_action_controller_test.dart
flutter test test/features/conversation/application/received_media_action_transport_boundary_test.dart

# Preservation; expect exit 0 and named target selection
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene; expect no new issues or whitespace errors
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-231-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-231-go-relay-diff.before
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-231-01 fails because the overlay/viewer lack the new action contract.
- Green sentinel: incoming local delete, outgoing Delete for Everyone, quote reply, and viewer swipe tests remain green.
- Pre-existing dirty tree / known failure: snapshot at execution; do not absorb unrelated changes or pre-existing l10n literal-scan debt into this plan.
- Environment blocker: none for this host slice; reporting decisions live outside its closure bar.
- Scope drift: any forwarding, gallery, schema, group/announcement, transport, relay, or Go edit blocks completion.

- [ ] Every behavior has a named test and honest RED/sentinel disposition.
- [ ] Focused, preservation, and named 1:1/feature gates pass with target discovery.
- [ ] New tests are present in both 1:1 arrays.
- [ ] Representative current-page, eligibility, cleanup, and forbidden-Report mutations re-red.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming visual media long press exposes the eligible core action set'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`.
- Manual registration: add the three new direct-media action files to both `scripts/run_test_gates.sh::ONE_TO_ONE_TESTS` and `scripts/run_host_test_gates.sh::ONE_TO_ONE_HOST_TESTS`; widget/unit files also AUTO-glob into `feature-host-all`.
- Migration: none.
- Boundary closure: host-only lane wiring; plan 227 separately owns Android/iOS egress device proof.
- Unresolved evidence: none for this slice. Reporting decisions are explicitly deferred to evidence-gated plan 244 and do not block implementation.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan and dependencies 227/230 | contract extraction |
