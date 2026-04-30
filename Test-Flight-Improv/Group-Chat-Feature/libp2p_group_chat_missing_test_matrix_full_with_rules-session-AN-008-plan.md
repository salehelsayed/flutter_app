# AN-008 Session Plan: Announcement Media Background-Task Coverage Is Unskipped

## real scope

Source row: `AN-008` - Announcement media background-task coverage is unskipped.

Current source status: `Partial`.

This session owns only the skipped background-task rows in
`test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
that block AN-008 evidence. It is a tests-only session unless an unskipped or
repaired test exposes a real production defect in the existing
`GroupConversationWired` media send background-task contract.

In scope:

- Unskip or replace the AN-008 skipped rows with equivalent active tests.
- Repair stale/brittle widget-test harness logic around gated media upload,
  `bg:begin`, `bg:end`, `group:publish`, and `group:inboxStore` ordering.
- Keep announcement media assertions focused on message id, key epoch, media
  metadata, saved attachments, and replay/inbox metadata.
- Update source matrix, test inventory, and session breakdown evidence after
  passing gates.

Out of scope:

- New announcement product behavior.
- New group media architecture, bridge protocol changes, or inbox retry policy.
- Device-lab proof unless a repaired active test proves the host-side harness
  cannot express the row.
- Broad group send, offline replay, media download, notification, or role-policy
  refactors.

## closure bar

`Covered` is allowed only when all AN-008 skipped rows are active or replaced by
equivalent active tests, and the source row, test inventory, and breakdown
record exact file/test/gate evidence.

The AN-008 skipped rows currently listed in `test-inventory.md` are:

- `bg:begin happens before media upload and bg:end happens after publish and inbox store`
- `bg:end fires on media upload failure early return`
- `bg:end fires when upload throws`
- `announcement media send preserves messageId, key epoch, and media metadata through wired path`
- `order-recording bridge proves no early cleanup`

Minimum closure:

- `flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` runs with no AN-008 `skip: true` rows.
- The active tests prove `bg:begin` starts before media upload, `bg:end` runs on upload null/throw cleanup, announcement media retains message id/key epoch/media metadata through publish and replay/inbox payloads, and the order-recording bridge pins the intended `group:publish`/`group:inboxStore`/`bg:end` ordering.
- Source matrix row `AN-008` moves from `Partial` to `Covered` only with this direct evidence and passing gates.

Keep the row `Partial` or blocked if any skipped row remains skipped for a real
harness or product limitation. Record the exact missing proof instead of
claiming coverage.

## source of truth

- Source row contract: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `AN-008`.
- Session contract: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, row `AN-008`, `needs_tests_only`, `implementation-ready`, no dependency.
- Evidence ledger: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, section `5.9 GroupConversationWired Background Task`.
- Current code and tests win over stale prose.
- `scripts/run_test_gates.sh` wins over gate prose if gate definitions drift.

## session classification

`implementation-ready`.

Reason: the targeted tests already exist and the production send path already
contains `callBgBegin` before upload and `callBgEnd` in `finally`. The initial
work is to repair and unskip existing coverage, not to design new behavior.

## exact problem statement

AN-008 remains `Partial` because the inventory still lists five skipped
background-task tests. The skipped rows leave announcement media send coverage
incomplete for:

- background-task lifecycle around media upload
- upload failure cleanup
- announcement media metadata through the widget/wired path
- bridge operation ordering around publish/inbox store/background cleanup

Relevant repo evidence collected for this plan:

- Normal, unmodified direct suite passes but reports five skips:
  `flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`.
- Focused skipped-row run with `--run-skipped` produced `+2 -3`: the upload
  failure cleanup rows passed; the media success/order rows failed because
  `group:publish` never appeared after the test released the gated upload.
- The failing rows use an `uploadGate` around `uploadMediaFn`; adjacent active
  media/voice/text tests use the same production path and prove background-task
  ordering without that brittle upload gate.
- `sendGroupMessage` intentionally starts publish and inbox store concurrently
  and only blocks on durable inbox when live publish cannot confirm delivery.
  For live peers, it may finalize inbox storage in the background after issuing
  `group:inboxStore`.

The executor must repair tests to match the shipped contract. If a repaired
test shows `bg:end` fires before the `group:inboxStore` command is issued, or
that `bg:end` is missing on cleanup, that is a real defect. If a skipped test
requires waiting for the live-peer `group:inboxStore` response even though the
use case intentionally finalizes that path in the background, replace that test
with an equivalent active order test or leave AN-008 `Partial` with the exact
contract conflict.

## files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge.dart`

Direct test and fake files:

- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `test/shared/fakes/in_memory_media_attachment_repository.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/shared/fakes/fake_upload_wake_lock_driver.dart`

Adjacent announcement/media evidence:

- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Docs to update after execution:

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`

## existing tests covering this area

- `group_conversation_wired_bg_task_test.dart` already has active tests for:
  OS refusal, unmount cleanup, ordinary media upload failure after unmount,
  text-only send, voice send, announcement voice zero-peer send, ordinary text
  with peers/zero peers, and announcement text with peers/zero peers.
- `announcement_happy_path_test.dart` proves an announcement admin can send GIF
  media and a reader receives image/GIF metadata while remaining read-only.
- `announcement_new_reader_onboarding_test.dart` proves a newly joined
  announcement reader receives only post-join admin image/video/voice media
  descriptors and cannot send announcement text/media/voice.
- `group_resume_recovery_test.dart` has widget-path announcement media/voice
  lifecycle proof, including `bg:begin` before `uploadMediaFn`, publish before
  inbox store, and inbox store before `bg:end`; it also proves zero-peer
  announcement media resume recovery keeps media refs intact.

Missing today:

- The five AN-008 skipped rows are not active closure evidence.
- The skipped success/order rows appear stale around the gated upload harness.
- The inventory and source matrix still record AN-008 as `Partial`.

## regression/tests to add first

Prefer repairing existing skipped tests over adding new files.

1. First run the current focused skipped rows with `--run-skipped` to preserve
   the red/green split:

   ```sh
   flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart \
     --run-skipped \
     --name "bg:begin happens before media upload|bg:end fires on media upload failure|bg:end fires when upload throws|announcement media send preserves|order-recording bridge proves"
   ```

2. Remove `skip: true` from the two cleanup rows only after confirming they
   still pass without special harness changes.

3. Repair the three success/order rows before unskipping them:
   - Prefer removing the brittle `uploadGate` from success-path media tests
     where immediate upload is enough to prove `bg:begin` precedes
     `uploadMediaFn` and `bg:end` follows issued bridge send commands.
   - For the order-recording row, use `commandGates` on `group:inboxStore` only
     if the intended contract is to hold the background task until the inbox
     store response. If the shipped live-peer contract is command-issued plus
     background finalization, replace the assertion with an active equivalent
     that proves `group:inboxStore` is issued before `bg:end`.
   - If the executor keeps a gated upload, drive the gate with widget-test-safe
     async plumbing, for example with `tester.runAsync` or a bounded helper that
     waits for the resumed upload future rather than timing out silently.

4. Keep announcement media metadata assertions in the existing row:
   - publish payload `messageId`
   - publish media `id`, `width`, `height`
   - inbox/replay `messageId`
   - inbox/replay `keyEpoch`
   - inbox/replay media `id`, `width`, `height`
   - saved outgoing message `keyGeneration` and `status`
   - saved media attachment id

5. Do not add production changes unless a repaired active test exposes a real
   mismatch with the documented send lifecycle.

## step-by-step implementation plan

1. Open `group_conversation_wired_bg_task_test.dart` and identify all five
   `skip: true` AN-008 rows.

2. Unskip the two cleanup rows that already passed under `--run-skipped`:
   - `bg:end fires on media upload failure early return`
   - `bg:end fires when upload throws`

3. Repair the generic media lifecycle row:
   - Keep `_OrderRecordingBridge` and `operationLog`.
   - Ensure the upload callback logs `uploadMediaFn` and returns a valid
     uploaded attachment.
   - Remove or fix the stale `uploadGate` so the test reaches
     `group:publish`, `group:inboxStore`, and `bg:end`.
   - Assert `bridge:bg:begin` before `uploadMediaFn`, `uploadMediaFn` before
     `bridge:group:publish`, `bridge:group:publish` before
     `bridge:group:inboxStore`, and the intended inbox-store/background-end
     ordering.

4. Repair the announcement media metadata row:
   - Keep the announcement admin group and saved key epoch `7`.
   - Keep the publish/inbox/repository media metadata assertions.
   - Repair only the async harness needed to let the send finish.
   - Remove `skip: true` only after the row passes as an ordinary active test.

5. Repair or replace the order-recording bridge row:
   - First try to make the existing gated `group:inboxStore` proof run.
   - If it reveals that live-peer sends intentionally return before inbox-store
     response, do not force a production behavior change in this session.
   - Replace it with an equivalent active AN-008 order test that proves the
     bridge issues `group:inboxStore` before `bg:end`, and record the accepted
     live-peer background-finalization behavior in the source docs.
   - If the row contract truly requires holding `bg:end` until inbox-store
     response for live peers, stop and mark AN-008 `Partial`/blocked with that
     exact product limitation.

6. Run the direct suite without `--run-skipped` and confirm no AN-008 skips
   remain.

7. Run focused adjacent announcement media gates.

8. Update docs only after tests pass:
   - Change source matrix row `AN-008` to `Covered` only if all closure
     criteria are met.
   - Update `test-inventory.md` section `5.9` to remove the AN-008 skip notes
     and describe active coverage.
   - Update the session breakdown ledger/evidence for AN-008 with exact tests
     and gate results.

## risks and edge cases

- The existing skipped success-path rows can time out before publish because of
  stale upload-gate harness logic rather than product behavior.
- `sendGroupMessage` intentionally lets live-peer inbox-store finalization
  complete in the background after the command is issued. Do not accidentally
  convert that accepted behavior into a broad product change under a tests-only
  row.
- Zero-peer sends are different: durable inbox success is required before
  `successNoPeers`. Do not use live-peer behavior to weaken zero-peer tests.
- Announcement admin write permission must stay unchanged; non-admin
  read-only behavior is covered elsewhere and should not be edited here.
- Upload failure rows must prove cleanup without publishing or inbox storing.
- The direct suite currently resets `UploadWakeLockController` in setup and
  teardown. Keep that isolation intact.

## exact tests and gates to run

Pre-repair diagnostic:

```sh
flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart \
  --run-skipped \
  --name "bg:begin happens before media upload|bg:end fires on media upload failure|bg:end fires when upload throws|announcement media send preserves|order-recording bridge proves"
```

Direct closure gate:

```sh
flutter test --no-pub test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

Focused adjacent announcement/media gates:

```sh
flutter test --no-pub test/features/groups/integration/announcement_happy_path_test.dart \
  --name "announcement admin can send GIF media"
flutter test --no-pub test/features/groups/integration/announcement_new_reader_onboarding_test.dart \
  --name "new reader receives only post-join admin media"
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart \
  --name "10-B acceptance|announcement media send with zero topic peers"
```

Focused aggregate if adjacent gates are green:

```sh
flutter test --no-pub \
  test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart \
  test/features/groups/integration/announcement_happy_path_test.dart \
  test/features/groups/integration/announcement_new_reader_onboarding_test.dart \
  test/features/groups/integration/group_resume_recovery_test.dart
```

Named group gate:

```sh
./scripts/run_test_gates.sh groups
```

Final hygiene:

```sh
git diff --check
```

## known-failure interpretation

- Skipped AN-008 rows are the target, not acceptable known failures.
- A direct suite result with remaining skips in
  `group_conversation_wired_bg_task_test.dart` is not closure evidence.
- If the broad `groups` gate has unrelated pre-existing failures, keep AN-008
  closure tied to the green direct and focused adjacent gates, and record the
  unrelated failure separately with exact file/test names.
- If an active order test fails because the shipped live-peer contract
  finalizes inbox store in the background after issuing `group:inboxStore`, do
  not call that a new regression without reconciling it with
  `send_group_message_use_case.dart`.

## done criteria

- All five AN-008 skipped rows are active or replaced by equivalent active
  tests.
- `group_conversation_wired_bg_task_test.dart` passes without AN-008 skips.
- Announcement media metadata, key epoch, message id, saved media attachment,
  and bridge ordering are pinned by active tests.
- Focused adjacent announcement/media gates pass or any blocker is recorded
  with exact missing proof.
- Source matrix, inventory, and breakdown evidence are updated with exact test
  and gate results.
- AN-008 is not marked `Covered` while any row remains skipped, replaced by a
  weaker non-equivalent test, or blocked by a real harness/product limitation.

## scope guard

- Do not edit source code unless a repaired active test exposes a real defect.
- Do not change `sendGroupMessage` inbox-finalization semantics just to satisfy
  a stale skipped test title.
- Do not add new group media APIs, device-lab harnesses, role policy changes,
  notification changes, or background-task abstractions.
- Do not close other announcement rows (`AN-001` through `AN-007`) from this
  work.
- Do not count adjacent integration coverage as a substitute for unskipping or
  replacing the direct AN-008 skipped rows.

## accepted differences / intentionally out of scope

- Live-peer sends may issue `group:inboxStore` and then let final storage
  reconciliation complete in the background; zero-peer sends must still wait
  for durable inbox success before returning `successNoPeers`.
- Announcement read-only role enforcement is already covered by adjacent tests
  and is not part of AN-008 beyond using an admin announcement group for the
  send path.
- Device or simulator E2E media proof remains outside this tests-only session
  unless host-side active tests cannot express the row.

## dependency impact

AN-008 closure removes a P0 skipped-test blocker from the announcement/media
background-task inventory. Later closure and pipeline sessions may rely on the
updated inventory to treat announcement media widget-path background-task
coverage as active. If AN-008 remains `Partial` or blocked, later sessions must
not borrow its skipped rows as closure evidence.

## reviewer and arbiter notes

Reviewer verdict: sufficient with the explicit tests-only guard. The plan is
row-scoped, names all skipped rows, names direct repairs and gates, and prevents
production-scope expansion unless active tests expose a real defect.

Structural blockers remaining: none for planning.

Incremental details intentionally deferred: exact Dart edit shape for the
upload-gate repair belongs to the execution agent after it reruns the focused
diagnostic.

Accepted differences intentionally left unchanged: live-peer inbox-store
background finalization in `sendGroupMessage` is not automatically a defect for
AN-008; the active order test should match the shipped contract or leave the
row blocked with exact proof.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge.dart`
- `test/shared/fakes/fake_media_file_manager.dart`
- `test/shared/fakes/in_memory_media_attachment_repository.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`

Why the plan is safe to implement now: it starts from existing skipped tests,
keeps changes in the direct test surface, uses adjacent active integration
evidence only as context, and has an explicit stop rule before any production
change.
