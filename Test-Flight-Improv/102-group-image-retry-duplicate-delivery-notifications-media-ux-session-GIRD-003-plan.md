Status: accepted

# GIRD-003 Plan: Recipient Logical Dedupe and Attachment Row Stability

## Planning Progress

- `2026-05-31 18:51 CEST` - Arbiter completed. Files inspected since last update: patched reviewer-pass plan. Decision/blocker: no structural blockers remain; GIRD-003 is execution-ready with host-only closure and GIRD-007 simulator/device deferral explicit. Next action: hand off to execution for GIRD-003 only.
- `2026-05-31 18:51 CEST` - Reviewer completed; Arbiter started. Files inspected since last update: full draft plan. Decision/blocker: sufficient with one incremental adjustment; exact no-message-id fallback preservation commands need to be explicit. Next action: patch that adjustment, then classify final blockers/differences.
- `2026-05-31 18:49 CEST` - Planner completed; Reviewer started. Files inspected since last update: this draft plan content. Decision/blocker: draft covers scope, RED tests, host gates, sender-contract refresh, and proof-profile deferral to GIRD-007. Next action: review for missing proofs, over-broad dedupe, and closure-gate sufficiency.
- `2026-05-31 18:49 CEST` - Evidence Collector completed; Planner started. Files inspected since last update: recipient handler/listener, group/media repositories/helpers, direct recipient/listener/database tests, GIRD-001/GIRD-002 accepted contracts, gate definitions, device inventory, reliability group dry-run. Decision/blocker: no blocker; GIRD-003 remains host-owned, with simulator incident evidence deferred to GIRD-007. Next action: draft the RED-first implementation plan and proof profile.
- `2026-05-31 18:46 CEST` - Evidence Collector started. Files inspected since last update: `implementation-plan-orchestrator/SKILL.md`, breakdown `GIRD-003` row, accepted `GIRD-001`/`GIRD-002` ledger facts, source spec test cases. Decision/blocker: dependencies are accepted and plan path did not exist. Next action: collect current code/test/gate evidence for recipient dedupe, attachment stability, and device/relay proof needs.

## Execution Progress

- `2026-05-31 18:53 CEST` - Contract extracted. Files inspected: this GIRD-003 plan, session breakdown, dirty tree, and existing recipient/listener test names. Decision/blocker: execution contract is concrete and limited to recipient logical dedupe plus attachment row stability; no blocker. Next action: spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- `2026-05-31 18:53 CEST` - Executor spawned. Files assigned: recipient handler/listener production and direct tests only, plus this plan for progress. Command currently running: spawned Executor `019e7ef4-66a6-7901-abf5-560df9861b81` with `model: gpt-5.5`, `reasoning_effort: xhigh`. Decision/blocker: waiting under bounded child rule. Next action: inspect landed evidence after bounded wait.
- `2026-05-31 18:56 CEST` - Executor child closed after bounded no-result wait. Files inspected: handler/listener tests, handler production diff, process list, missing `/tmp/gird-003-execution-final.txt`. Decision/blocker: child produced partial tests but no trustworthy final evidence; local sequential fallback is now active in this already-isolated execution child. Next action: run focused RED locally, then complete the Executor responsibilities and local QA.
- `2026-05-31 18:57 CEST` - Focused RED completed. Files touched/inspected: `handle_incoming_group_message_use_case_test.dart`, `group_message_listener_test.dart`. Commands: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-003"` failed because the reminted media retry returned a second `GroupMessage`; `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GIRD-003"` failed because two stream emissions were observed. Decision/blocker: RED is valid. Next action: implement handler-side logical media retry collapse before duplicate attachment save.
- `2026-05-31 18:58 CEST` - Local Executor implementation completed. Files touched: `lib/features/groups/application/handle_incoming_group_message_use_case.dart`, `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`. Decision/blocker: handler now checks stable-id incoming media retries against recent canonical incoming rows using exact group/sender/transport/text/timestamp/quote/status plus strict media descriptor identity, enriches only the canonical row, and leaves listener behavior unchanged. Next action: run focused GREEN and preservation commands.
- `2026-05-31 18:59 CEST` - Focused GREEN completed. Commands passed: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-003"` and `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GIRD-003"`. Decision/blocker: direct row/attachment and listener notification/emission proof is green. Next action: run required preservation and accepted sender-contract refresh commands.
- `2026-05-31 19:00 CEST` - Preservation and sender-contract refresh completed. Commands passed: handler preservation commands for same-id dedupe, no-message-id exact content dedupe, no-message-id media duplicate, `PGC-007`, and duplicate replay media resave; listener preservation commands for replay notification dedupe and `GP-025 LP013`; sender-contract refresh commands for `send_group_message_use_case_test.dart --plain-name "GIRD-001"`, `handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"`, `group_conversation_wired_test.dart --plain-name "GIRD-002"`, `retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"`, and `pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002"`. Decision/blocker: prior accepted GIRD-001/GIRD-002 behavior is preserved. Next action: run named gate and whitespace check.
- `2026-05-31 19:01 CEST` - Gate and local QA completed. Commands passed: `./scripts/run_test_gates.sh groups` and `git diff --check`. Conditional commands skipped: repository/db/media helper suites because no repository interface, DB helper, migration, or media helper behavior changed; foreground push drain integration skipped because no integration foreground push behavior changed. Decision/blocker: local QA found no blocking issues and no non-blocking follow-ups. Next action: final verdict written.

## Final execution verdict

Verdict: accepted.

Spawned-agent isolation: attempted. Executor `019e7ef4-66a6-7901-abf5-560df9861b81` was spawned with `model: gpt-5.5` and `reasoning_effort: xhigh`, then closed after bounded no-result wait. Local sequential fallback was used by this already-isolated execution child for Executor completion, exact test/gate evidence, and QA review.

Files changed for GIRD-003:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md`

Tests added or updated:

- `GIRD-003 distinct-id group image retry with same media identity keeps one recipient row`
- `GIRD-003 intentional separate image sends with distinct media identity both persist`
- `GIRD-003 reminted group image retry emits and notifies once`

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

## real scope

GIRD-003 changes only recipient-side group message row idempotency and media attachment ownership for incoming group image/media deliveries.

In scope:

- keep same-message-id live pubsub plus group inbox replay as one recipient row and one local notification path
- add focused recipient proof for one logical group image retry arriving under a different stable message id when the duplicate carries strong same-logical-media evidence
- keep media attachments attached to the canonical visible recipient row and prevent a duplicate retry row from moving/replacing the shared attachment under a second message id
- preserve intentional separate successful sends of the same image/content when they do not carry the same exact logical retry evidence
- preserve missing-message-id fallback behavior without broad unsafe content dedupe

Out of scope:

- sender retry ownership already accepted in `GIRD-001` and `GIRD-002`
- relay/native group inbox store idempotency, which remains `GIRD-004`
- media unavailable/loading display semantics, which remain `GIRD-005`
- notification identity/suppression/fallback/tap routing beyond proving the existing listener does not show a second local notification for a recipient duplicate, which remains `GIRD-006`
- incident simulator/device evidence and stable source/matrix closure docs, which remain `GIRD-007`

## closure bar

GIRD-003 is good enough when host tests prove the recipient app collapses the row/attachment shape it owns without hiding intentional separate sends.

Coverage ledger:

| Requirement | Planned proof |
| --- | --- |
| same-message-id live pubsub plus group inbox replay stays one recipient row | Existing same-id handler/listener tests remain green; add `GIRD-003` preservation names only if implementation touches that path. |
| same-message-id replay creates one local notification path | Existing `group_message_listener_test.dart` replay-notification tests remain green; `GIRD-003` listener RED also asserts one notification for the new reminted-id media retry shape. |
| same logical group image retry with distinct stable ids does not create two visible recipient rows | New RED in `handle_incoming_group_message_use_case_test.dart` with two stable ids, same sender/group/text/timestamp/quote, and identical media blob identity; expected second delivery returns `null` and row count remains one. |
| media attachments stay on the correct visible row | Same RED asserts the original/canonical row keeps the attachment and the duplicate id has no moved attachment. |
| intentional separate successful sends survive | New or existing preservation test with distinct stable ids and same text/content hash but different attachment ids and/or separated timestamps persists two rows and two attachment sets. |
| missing/unstable message id fallback is covered without broad content dedupe | Existing no-message-id exact content/timestamp dedupe and media duplicate tests remain green; do not add wider content-hash-only dedupe. |
| accepted sender contracts stay intact | Run `GIRD-001` and `GIRD-002` direct preservation commands listed below. |

## source of truth

- Current code and direct tests win over stale prose.
- Active session contract: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`, session `GIRD-003`.
- Source acceptance context: `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`.
- Gate source: `Test-Flight-Improv/test-gate-definitions.md`; `scripts/run_test_gates.sh` wins if docs and script disagree.
- Accepted dependency contracts: `GIRD-001` and `GIRD-002` plan files plus the breakdown Session Closure Ledger.

## session classification

`implementation-ready`

Dependencies `GIRD-001` and `GIRD-002` are accepted. This is not doc-only work: current recipient tests preserve distinct stable ids broadly, and no proof covers distinct-id same-logical image retry with shared media identity and attachment-row stability.

## exact problem statement

Recipients already dedupe replays that reuse the same `messageId`. They also intentionally preserve two stable message ids with the same text and timestamp. The remaining GIRD-003 gap is a narrower incident shape: one user-intended group image retry can arrive at a recipient under a different stable id while carrying the same media/blob identity. Current behavior can persist two rows, and because `media_attachments.id` is primary-key-replaced by `saveAttachment`, a duplicate row can also move the attachment away from the first visible row.

The fix must make that exact recipient duplicate shape idempotent while preserving clearly intentional separate sends of the same image.

## files and repos to inspect next

Production:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/models/group_message_payload.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart` only if a repository/db helper is added
- `lib/core/database/helpers/media_attachments_db_helpers.dart` only if attachment persistence behavior changes

Tests:

- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` if repository API changes
- `test/core/database/helpers/group_messages_db_helpers_test.dart` if DB helper changes
- `test/core/database/helpers/media_attachments_db_helpers_test.dart` if media helper behavior changes
- `test/features/groups/integration/group_resume_recovery_test.dart` only if the direct handler/listener proof cannot cover replay/catch-up ordering
- `integration_test/foreground_group_push_drain_test.dart` only if execution changes or extends foreground push drain behavior

## existing tests covering this area

- `handle_incoming_group_message_use_case_test.dart` covers same-message-id pubsub/inbox dedupe, duplicate replay quote enrichment, tampered same-id replay preservation, conflict rejection for same ids from another sender, duplicate replay saving missing media, and duplicate replay not resaving media.
- `handle_incoming_group_message_use_case_test.dart` also currently preserves distinct stable message ids with the same content/timestamp (`PGC-007`). That preservation is intentional and must remain for non-logical-retry cases.
- `group_message_listener_test.dart` covers same-id duplicate connection delivery, same-id replay notification dedupe, self-echo reconciliation, and LP013 first-row/notification preservation.
- `group_resume_recovery_test.dart` covers fake-network duplicate same-id deliveries to Bob/Charlie and unread count across duplicate inbox drain.
- `media_attachments_db_helpers_test.dart` proves attachment ids use replace-on-conflict semantics, which is useful but risky for duplicate logical rows because the attachment can move to the later message id if the duplicate is not collapsed before save.

Missing:

- no current test proves a distinct-message-id group image retry with the same exact media/blob identity collapses to one recipient row
- no current listener proof asserts that this distinct-id media retry shape emits and notifies once
- no current proof asserts the original visible row retains its media attachment when a duplicate retry arrives

## regression/tests to add first

Add RED tests before production edits:

1. `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
   - Name: `GIRD-003 distinct-id group image retry with same media identity keeps one recipient row`
   - Arrange first incoming image with `messageId: gird003-original`, `senderId`, `timestamp`, optional empty text, and media descriptor `id: blob-gird003-shared`, normalized `contentHash`, encryption metadata, size, and mime.
   - Arrange second incoming image with `messageId: gird003-reminted`, same group/sender/text/timestamp/quote, and the same media descriptor.
   - Expected RED: second result is `null`, message count stays one, original row remains, duplicate id is absent, `getAttachmentsForMessage(gird003-original)` has the blob, and `getAttachmentsForMessage(gird003-reminted)` is empty. Current code is expected to persist a second row and/or move the blob.

2. `test/features/groups/application/group_message_listener_test.dart`
   - Name: `GIRD-003 reminted group image retry emits and notifies once`
   - Send two listener events with different message ids but the same strong media identity and logical envelope fields.
   - Expected RED: one stream emission, one notification, one unread row, one stored message, attachment on the first/canonical id only.

3. Preservation in `handle_incoming_group_message_use_case_test.dart`
   - Name: `GIRD-003 intentional separate image sends with distinct media identity both persist`
   - Use distinct stable ids and same image content hash if useful, but different attachment ids and a later timestamp or otherwise non-retry evidence.
   - Expected: two rows persist and each row keeps its own attachment.

4. Preservation for unstable/missing ids
   - Keep existing exact no-message-id content/timestamp duplicate tests green.
   - Add a named `GIRD-003` no-message-id media preservation only if production changes touch the existing fallback.

Do not treat one broad assertion as covering all rows. Each acceptance item above must either have one of these tests or an explicit accepted difference.

## step-by-step implementation plan

1. Run the focused RED commands. If all planned distinct-id media retry tests are already green, stop implementation and reclassify the session as stale/already-covered with evidence.
2. Add a small canonical-media-identity comparator inside `handle_incoming_group_message_use_case.dart` or a nearby private helper. The comparator should require exact match on group id, sender id, sanitized text, normalized timestamp, quote id, incoming status, and media identity. Media identity should be based on exact attachment ids plus required verified descriptor fields such as normalized `contentHash`, `mime`, `size`, and encryption metadata. Do not dedupe on text or content hash alone.
3. Before inserting a new stable-id incoming media message, search recent/current group messages for a candidate with the same strict logical retry identity. Prefer an existing repository API such as `getMessagesPage` plus `mediaAttachmentRepo.getAttachmentsForMessages`; add a narrow repository/helper query only if the direct implementation is too broad or inefficient.
4. If a canonical existing row is found, enrich that canonical row with any missing quote/media descriptors via the existing duplicate-enrichment path, return `null`, and do not save a new `GroupMessage`.
5. Ensure `_saveIncomingMediaAttachments` never moves a shared attachment to the duplicate id. Enrichment must target the canonical id only and skip duplicates already attached there.
6. Keep `GroupMessageListener` behavior unchanged where possible. It should naturally avoid second stream emission/notification because `handleIncomingGroupMessage` returns `null` for the duplicate.
7. Run focused GREEN commands. Then run preservation tests for same-id replay, intentional distinct sends, sender contracts, and the named groups gate.
8. Update only this plan file during execution if evidence needs to be recorded by the execution/QA orchestrator. Do not update the source spec, stable matrices, or breakdown ledger; closure audit owns the session ledger and `GIRD-007` owns stable source/matrix reconciliation.

Stop and re-plan if implementation needs any of these:

- a new durable logical-send schema or migration
- a new sender-side wire field such as `clientMessageId`
- Go bridge/native changes
- relay inbox store changes
- broad content-hash-only or text-only dedupe that can collapse intentional sends

## risks and edge cases

- Attachment primary-key replacement can move media from the first visible row to a duplicate row if dedupe happens after `saveAttachment`; collapse must happen before saving duplicate attachments.
- Same image content can be intentionally sent more than once; media identity must not be content-hash-only.
- Missing `messageId` fallback already does exact content/timestamp dedupe; changing it broadly can hide valid messages.
- Quote id, sender transport identity, group id, and membership/re-add windows must keep their current validation order and safety checks.
- GIRD-001 `pending` and same-id own replay repair must remain sender-side behavior and not be reinterpreted as recipient duplicates.
- GIRD-002 restored continuation id reuse should reduce avoidable reminted sender ids, but GIRD-003 must still tolerate recipient duplicate evidence without depending on UI state.

## Device/Relay Proof Profile

Profile for GIRD-003 execution closure: `host-only`.

Reason: this session owns deterministic Flutter recipient row/attachment idempotency under `test/`. It references `integration_test/foreground_group_push_drain_test.dart` only as a conditional supporting direct suite if foreground push drain behavior is changed or extended. It does not claim final simulator, device, real relay, OS notification, or three-user incident closure.

Live availability checks run during planning:

- `flutter devices --machine`: available devices include physical Android `21071FDF600CSC`, physical iOS `00008030-001A6D2801BB802E` and `00008110-00184D622289801E`, booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, plus `macos` and `chrome`.
- `xcrun simctl list devices available`: the same four iOS 26.1 simulators are booted; iOS 26.2 named gap-closure simulators are present but shutdown.
- Reliability dry-run: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list` resolved one-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, two-device `38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and four-device group `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F,1B098DFF-6294-407A-A209-BBF360893485,38FECA55-03C1-4907-BD9D-8E64BF8E3469`.

Execution closure for GIRD-003 does not require a device run. If implementation changes or extends `integration_test/foreground_group_push_drain_test.dart`, run the direct simulator suite as supporting evidence:

```bash
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/foreground_group_push_drain_test.dart
```

Deferred to `GIRD-007`:

- actual three-user group image retry incident simulator proof
- final `$run-flutter-reliability-sims` group acceptance run with fix-as-you-go
- Android foreground/background notification behavior
- iOS foreground/background/notification-open and narrow real APNs/NSE device-context evidence
- final source/matrix closure reconciliation

Final GIRD-007 acceptance should select or add a dedicated scenario, then run:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only <GIRD-007 group image retry incident scenario>
```

Do not use a comma-separated global `FLUTTER_DEVICE_ID` for the final group reliability run; use the bundled resolver.

## exact tests and gates to run

Focused RED/GREEN:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-003"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GIRD-003"
```

Required preservation:

```bash
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "deduplicates by messageId when pubsub and group inbox deliver same message"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "deduplicates identical incoming messages"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "ignores duplicate messages"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "PGC-007 distinct stable message IDs with same content and timestamp both persist"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "duplicate group inbox replay does not resave media"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "replayed duplicate group message does not create a second local notification"
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name "GP-025 LP013 duplicate PubSub delivery preserves first row and notification state"
```

Accepted sender-contract refresh:

```bash
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name "GIRD-001"
flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name "GIRD-001"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "GIRD-002"
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart --plain-name "GIRD-002"
flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart --plain-name "GIRD-002"
```

Conditional if repository/db/media helper APIs change:

```bash
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test test/core/database/helpers/group_messages_db_helpers_test.dart
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart
```

Conditional if foreground push drain integration behavior changes:

```bash
FLUTTER_DEVICE_ID=38FECA55-03C1-4907-BD9D-8E64BF8E3469 flutter test --no-pub -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469 integration_test/foreground_group_push_drain_test.dart
```

Named gate and whitespace:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

## known-failure interpretation

- No known-red exception is documented for the GIRD-003 focused tests or `./scripts/run_test_gates.sh groups`.
- `Test-Flight-Improv/test-gate-definitions.md` documents unrelated `completeness-check` classification failures from 2026-05-28; `completeness-check` is not required for GIRD-003 unless execution adds or reclassifies test inventory files.
- The dirty worktree already contains accepted GIRD-001/GIRD-002 changes and unrelated `scripts/check_reliability_simulation_discovery.sh`. Do not revert unrelated dirty files. If a required command fails because of a pre-existing unrelated change, record the exact failure and isolate it before changing product/test code.
- Reliability simulator `group --list` was a dry-run discovery proof only; it is not a pass/fail execution result for GIRD-003.

## done criteria

- New GIRD-003 RED tests fail before production edits for the distinct-id same-media retry row/notification/attachment shape, unless current code is proven already covered and the session is reclassified.
- Production changes are limited to recipient handler/listener/repository/media helper surfaces needed by the RED tests.
- Distinct-id same-logical group image retry collapses to one recipient row and one local notification path.
- The canonical visible row keeps the media attachment; the duplicate id does not acquire or move it.
- Same-message-id replay dedupe remains green.
- Intentional separate sends remain green.
- GIRD-001 sender in-doubt states and same-id own replay repair remain green.
- GIRD-002 restored media continuation id reuse, upload-pending retry ownership, and already-open sender refresh remain green.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass.
- Any conditional DB/helper/integration commands required by actual file changes pass or are documented with a precise blocker.

## scope guard

Do not:

- add relay/native group inbox idempotency; that is `GIRD-004`
- add media unavailable/loading UI semantics; that is `GIRD-005`
- redesign notification identity, suppression, background fallback, mute, active-group, or tap routing; that is `GIRD-006`
- update stable source/matrix closure docs; that is `GIRD-007`
- add a broad content-hash-only or text/timestamp-only dedupe for stable message ids
- collapse two stable ids that represent intentional separate sends
- add schema, protocol, Go bridge, or sender wire-field changes without stopping and replanning
- change retry owner ordering, restored composer behavior, lifecycle recovery, or GIRD-001 in-doubt sender classification

Overengineering includes adding a generalized logical-send service, durable schema, global dedupe cache, relay contract, or cross-platform notification dedupe in this session.

## accepted differences / intentionally out of scope

- Distinct stable ids with the same text/timestamp remain valid when there is no strong same-logical-media retry evidence. This preserves the existing `PGC-007` architecture.
- Host tests are sufficient for GIRD-003 execution closure because this row owns recipient app row/attachment idempotency. Simulator/device incident acceptance is intentionally deferred to `GIRD-007`.
- Same media content hash alone is not a logical-send identity. Exact blob/attachment identity plus matching message envelope fields is required, or the row must remain distinct.
- Real relay duplicate storage and push fanout idempotency are not closed here.
- Final notification behavior is not closed here, except that the existing local listener path must not emit a second local notification for the duplicate recipient row shape GIRD-003 collapses.

## dependency impact

- `GIRD-004` can align relay/native idempotency with the app-visible recipient logical duplicate definition produced here.
- `GIRD-005` depends on a stable recipient row/media attachment relationship before changing unavailable/loading semantics.
- `GIRD-006` depends on GIRD-003 and GIRD-004 so notification dedupe keys do not stack banners for a duplicate row shape the app should already collapse.
- `GIRD-007` must replay this direct proof as part of incident acceptance and update stable docs/matrices. If GIRD-003 requires schema/protocol work, pause downstream sessions and update the breakdown before GIRD-004+ execution.

## fallback/blocker conditions

- If no safe discriminator exists that separates same-logical media retry from intentional separate sends, stop and mark the session `evidence-gated` with the exact conflicting examples.
- If the only safe fix requires a sender-provided logical id/client id or Go bridge support, stop and replan because that crosses GIRD-003's recipient-only scope and may need a new dependency before `GIRD-004`.
- If conditional simulator/integration evidence becomes required and the named device is unavailable, record the available device inventory and classify the device piece as deferred/supporting rather than silently closing it.

## reviewer sufficiency pass

Verdict: sufficient with one incremental adjustment, now applied.

- Missing files/tests/gates: no structural misses after adding explicit no-message-id fallback preservation commands.
- Stale assumptions: none found; current code/tests and accepted `GIRD-001`/`GIRD-002` closure facts are named as source of truth.
- Overengineering: avoided by rejecting schema/protocol/Go/sender-field changes unless execution stops and replans.
- Decomposition: narrow enough for implementation; the handler proof owns row/attachment idempotency, and listener proof owns one stream/notification path.
- Checklist coverage: every GIRD-003 session bullet maps to a direct RED, preservation command, accepted difference, or GIRD-007 deferral.

## arbiter decision

Final verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- The exact implementation can choose a private handler helper or a narrow repository helper after RED evidence; this is not structural because the plan names stop conditions for schema/protocol/native scope.
- Simulator/device execution is deferred to `GIRD-007`; GIRD-003 keeps only host-side row/attachment/listener proof plus conditional foreground-push direct evidence if that file changes.

Accepted differences intentionally left unchanged:

- Distinct stable ids without strong same-logical-media evidence remain separate.
- Real relay store/push fanout idempotency remains `GIRD-004`.
- Media unavailable semantics remain `GIRD-005`.
- Notification identity/tap/fallback behavior remains `GIRD-006`.
- Stable source/matrix closure and the full incident simulator/device pass remain `GIRD-007`.

Exact docs/files used as evidence:

- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`
- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`

Why the plan is safe to implement now:

- Dependencies are accepted.
- The first implementation action is RED-first and proves the exact distinct-id media retry gap before production edits.
- The scope guard prevents sender, relay, media-placeholder, notification-system, schema, Go, and final-doc drift.
- The closure bar includes direct focused tests, accepted sender-contract refresh, named group gate, whitespace check, and conditional device/integration handling.
