Status: accepted; final QA passed

# PREREQ-FUTURE-EPOCH-KEY-REPAIR Plan

## Execution Progress

- 2026-05-01T17:22:35+0200 - Final isolated QA completed. Files inspected: plan, source matrix/inventory/breakdown rows for EK-004/EK-005/ER-004/PREREQ, migration/helper/repository/service, offline drain, key update listener, message listener, bridge diagnostics, UI placeholder state, runtime wiring, focused tests, and current diff. Files changed by QA: added a file-backed close/reopen persistence assertion to `test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart`; updated this plan and the breakdown verdict. Commands passed: `dart format test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart`; `flutter test --no-pub test/core/database/migrations/063_group_pending_key_repairs_test.dart test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart` (`+13`); `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_screen_test.dart test/core/bridge/go_bridge_client_test.dart --name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR|group decryption failure push event reaches diagnostics stream without invoking group message callback'` (`+6`); `cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_EmitsDecryptionFailedEvent$|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery|TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires|GroupTopicValidator|HandleGroupSubscription|GroupKey|KeyRotation' -v`; `./scripts/run_test_gates.sh groups` (`+101`); `./scripts/run_test_gates.sh completeness-check` (`703/703`); `git diff --check`. Decision/blocker: accepted; no blocking QA findings remain. EK-005 and ER-004 are safe as `Covered`; EK-004 remains `Partial` because complete all-family offline replay signature-equivalence is still unproven.
- 2026-05-01T17:06:02+0200 - Executor evidence and source-doc update completed. Files touched: source matrix, test inventory, session breakdown, and this plan. Commands passed after implementation: all focused required Flutter tests, schema/repository/full-chain tests, focused Go diagnostics/epoch regex, full direct owner suites, Go owner regex, `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, and `git diff --check`. Decision/blocker: EK-005 and ER-004 closure bars are met from Executor evidence and moved to `Covered`; EK-004 is narrowed only for future/missing-key replay and remains `Partial`; PREREQ row is `executor_complete`/`qa_pending`, not QA-accepted. Next action: isolated QA Reviewer pass.
- 2026-05-01T16:59:15+0200 - Full direct owner suites and named gates completed green. Commands passed: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` (`+178`), `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart` (`+36`), `flutter test --no-pub test/features/groups/application/*key*_test.dart` (`+49`), `cd go-mknoon && go test ./node -run 'GroupTopicValidator|HandleGroupSubscription|GroupKey|KeyRotation' -v`, `./scripts/run_test_gates.sh groups` (`+101`), `./scripts/run_test_gates.sh completeness-check` (`703/703`), and `git diff --check`. Decision/blocker: no direct, named-gate, or hygiene blocker remains for this Executor pass.
- 2026-05-01T16:54:55+0200 - Core implementation and focused first-pass tests completed. Files touched: migration/helper/model/repository/service, offline drain, key update listener, message listener diagnostic seam, message dedupe replacement, runtime wiring, focused tests. Commands passed: `flutter test --no-pub test/core/database/migrations/063_group_pending_key_repairs_test.dart test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart`, `flutter test --no-pub test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`, focused drain/key-listener/message-listener/UI/bridge tests, `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`, focused Go regex. Decision/blocker: durable pending queue, one-shot repair trigger, retry-after-key-arrival, live diagnostic placeholder, and safe finalization are implemented for the planned scope. Next action: run full direct owner suites, named gates, hygiene, then update matrix/inventory/breakdown only if evidence remains green.
- 2026-05-01T16:42:57+0200 - RED test pass recorded. Files touched: new `063_group_pending_key_repairs` migration/helper/repository tests, focused drain/key-listener/message-listener/UI tests. Command run: `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'`. Decision/blocker: expected RED compile failure confirms missing `group_pending_key_repair_service`, model/repository, and `pendingKeyRepairRepo` drain seam. Next action: implement 063 migration, helper/repository, repair service, and wire owner application seams.
- 2026-05-01T16:36:29+0200 - Executor seam inspection completed. Files inspected: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/application/group_offline_replay_envelope.dart`, `lib/features/groups/application/group_key_update_listener.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/domain/repositories/group_message_repository*.dart`, `lib/core/database/helpers/group_messages_db_helpers.dart`, `lib/core/bridge/go_bridge_client.dart`, direct test files. Decision/blocker: current code has fail-closed placeholder creation but no durable queue, no retry owner, no key-arrival repair callback, and no app-layer diagnostic placeholder listener; persistence migration `063` is required. Next action: add RED migration/helper/repository/application/UI tests for the planned queue and repair lifecycle.
- 2026-05-01T16:31:55+0200 - Executor fresh intake completed. Files inspected: `git status --short`, `lib/main.dart`, `lib/core/database/migrations`, `test/core/database/migrations`. Decision/blocker: worktree is broadly dirty before this Executor pass, including target group docs/code/tests and many unrelated session plan files; do not revert preexisting edits. Current database version is `62`; migrations/tests through `062` are present; no `063` migration/test file exists, so `063_group_pending_key_repairs` is available if this implementation needs a durable queue. Next action: inspect owner seams and add RED tests before production edits.
- 2026-05-01T16:30:23+0200 - contract extracted. Files inspected: plan file, source matrix rows EK-004/EK-005/ER-004, inventory/breakdown references, `lib/main.dart`, migration directories. Decision/blocker: scope is future/missing-key repair lifecycle only; direct tests/gates and non-goals are explicit. Next action: spawn isolated Executor.
- 2026-05-01T16:30:23+0200 - dirty-state and migration-number checks completed. Files inspected: `git status --short`, `lib/main.dart`, `lib/core/database/migrations`, `test/core/database/migrations`. Decision/blocker: tree is broadly dirty from other sessions; current DB version is `62`; migrations/tests through `062` exist; no `063` migration/test file is present, so `063_group_pending_key_repairs` is available if persistence is added. Next action: Executor must re-check before schema edits and stop/renumber if claimed.

## Planning Progress

- 2026-05-01T16:28:15+0200 - Arbiter completed. Files inspected since last update: reviewer-adjusted plan. Decision/blocker: no structural blockers remain; implementation is safe now as a host/fake-network code+tests session with dirty-worktree safeguards. Next action: execute only when a later turn requests implementation.
- 2026-05-01T16:27:15+0200 - Reviewer completed. Files inspected since last update: draft plan, direct owner code/test evidence, bridge diagnostics seam, migration/version evidence, dirty worktree status. Decision/blocker: plan is sufficient with adjustments; repair trigger contract, finalization policy, bridge diagnostic preservation, and queue repository tests were tightened. Next action: run arbiter classification and finalize status.
- 2026-05-01T16:23:06+0200 - Planner completed. Files inspected since last update: source matrix EK-004/EK-005/ER-004 rows, inventory EK-004/EK-005/ER-004 entries, reopened prerequisite row, accepted prerequisite ledger entries, owner application/Go/UI code, direct tests, `scripts/run_test_gates.sh`, and dirty worktree status. Decision/blocker: repo-owned future-epoch repair gaps are implementable as code plus tests; no external fixture blocks host/fake-network implementation. Next action: run reviewer pass.
- 2026-05-01T16:23:06+0200 - Evidence Collector completed. Files inspected since last update: source rows, inventory entries, prerequisite ledger, owner code/tests, gate script, and git status. Decision/blocker: current code has fail-closed evidence but lacks durable queue, repair trigger, retry-after-key-arrival, live placeholder surface, and finalization lifecycle. Next action: draft plan.
- 2026-05-01T16:20:17+0200 - Evidence Collector started. Files inspected since last update: target plan path existence check, `Test-Flight-Improv/Group-Chat-Feature/` listing. Decision/blocker: plan artifact created because the reopened prerequisite row and target path are confirmed. Next action: read source rows EK-005, ER-004, EK-004 blocker notes, inventory/prerequisite docs, and current owner code/tests.

## real scope

This prerequisite owns only future/missing-key group-message repair behavior that blocks EK-005, ER-004, and the EK-004 offline replay equivalence note where future/missing-key paths participate.

Implement a narrow durable repair lifecycle:

- store future/missing-key offline replay envelopes durably instead of finalizing them only as `undecryptable` on first drain
- create one safe visible placeholder for pending repair, with no plaintext/media leakage
- trigger a minimal key-sync/repair request when future/missing-key content is observed
- retry queued replay after the missing key arrives through `GroupKeyUpdateListener`
- finalize safely to `undecryptable` only after retry proves unrecoverable or the queue exhausts its policy
- surface live `group:decryption_failed` diagnostics as a safe placeholder/repair state without normal message delivery

The plan may add a small persistence owner if required for durability. If persistence is added, it must be migration-backed, helper-backed, and tested before application code depends on it.

Minimal repair trigger contract: introduce an injectable application callback or coordinator such as `requestGroupKeyRepair({groupId, keyEpoch, reason, messageId})`. Queue creation and live diagnostics must call it exactly once per pending item/reason window. Production wiring may use existing recovery/drain hooks or a scoped key-repair request, but it must not introduce history repair or receipt sync.

## closure bar

EK-005 can move to `Covered` only if direct evidence proves all four required parts together:

- a durable future-epoch pending queue survives process restart and dedupes repeated replay for the same message
- missing/future key observation triggers a key-sync repair request or equivalent minimal repair signal
- arrival of the missing key retries the queued encrypted replay and replaces the placeholder with the decrypted message when valid
- unrecoverable retry finalizes to a safe placeholder without plaintext, media downloads, duplicate rows, or endless retry loops

ER-004 can move to `Covered` only if direct evidence proves:

- live wrong-key/tampered decryption failures do not emit normal `group_message:received`
- the Flutter app creates a truthful live repair placeholder or pending repair surface from the diagnostic path
- offline missing/future-key replay and live diagnostic failures share the same safe pending/finalized UI states
- finalization is explicit and idempotent

EK-004 must not move to `Covered` from this prerequisite unless execution also proves complete offline replay signature equivalence for every shipped security event family. The expected closure for this session is narrower: remove or narrow only the future/missing-key offline replay blocker if queued replay re-enters the same verified application path before mutation.

## source of truth

Authoritative docs:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- accepted prerequisite plans for `PREREQ-DEVICE-IDENTITY` and `PREREQ-SIGNED-COMMIT-AUDIT`

Authoritative implementation evidence:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `go-mknoon/node/pubsub.go`
- `scripts/run_test_gates.sh`

If docs and code disagree, current code and passing direct tests win. If named gate prose and `scripts/run_test_gates.sh` disagree, `scripts/run_test_gates.sh` wins for runnable gate membership.

## session classification

`implementation-ready`.

The prerequisite row is reopened with `needs_code_and_tests`, and current code confirms the missing pieces are repo-owned. Existing fail-closed placeholders and diagnostics are not enough to close the rows, but they provide safe seams for implementation.

## exact problem statement

Current behavior is safe but incomplete:

- offline replay with a missing future epoch key catches `Missing group replay key`, saves one `status: 'undecryptable'` placeholder, and never decrypts or stores plaintext
- the raw encrypted replay envelope is not durably queued for later retry, so key arrival cannot repair it
- `GroupKeyUpdateListener` saves a new key after `group:updateKey`, but it does not notify or run any pending replay repair owner
- Go live wrong-key/tampered decrypt failures emit `group:decryption_failed` and skip normal delivery, and Flutter forwards that into `groupDiagnosticEventStream`, but no group application listener turns it into a user-visible repair/placeholder lifecycle
- unknown future live epochs are rejected before delivery by the Go validator; this must remain fail-closed unless the implementation adds a privacy-safe diagnostic/recovery signal without exposing raw encrypted blobs

User-visible improvement required: future/missing-key content should appear as pending repair, retry when key material arrives, become the real message if repair succeeds, and become a safe unrecoverable placeholder if repair cannot succeed. Existing security behavior must stay unchanged: no plaintext fallback, no media download before decrypt/validation, no normal live message delivery on decrypt failure, and no unauthorized key update acceptance.

## files and repos to inspect next

Production files expected in scope:

- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/main.dart`
- `go-mknoon/node/pubsub.go`

Likely persistence additions if the executor confirms a new durable queue is needed:

- `lib/core/database/migrations/063_group_pending_key_repairs.dart`
- `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart`
- `lib/features/groups/domain/models/group_pending_key_repair.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart`
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart`
- `test/core/database/migrations/063_group_pending_key_repairs_test.dart`
- `test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart`

Do not touch welcome/key-package admission, broad signed audit architecture, receipts, remote bans/deletes, or history gap repair beyond a minimal key repair signal.

## existing tests covering this area

Current positive evidence:

- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` proves future epoch encrypted replay creates one safe `undecryptable` placeholder, never calls `group.decrypt`, and does not expose plaintext or media.
- The same file proves mixed known-epoch encrypted replay decrypts and persists under each envelope epoch.
- `test/features/groups/presentation/group_conversation_screen_test.dart` proves `undecryptable` placeholders render safe copy and do not expose failed-media retry/delete controls.
- `test/core/bridge/go_bridge_client_test.dart` proves `group:decryption_failed` reaches `groupDiagnosticEventStream` without invoking the normal group message callback.
- `go-mknoon/node/pubsub_decryption_failure_test.go` proves wrong-key/tampered live content emits `group:decryption_failed`.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go` proves unknown future live epochs reject before delivery and old-epoch expiration does not emit ghost messages.
- `test/features/groups/application/group_key_update_listener_test.dart` proves key updates are saved only after `group:updateKey` succeeds and current sends stay on the old epoch while a key update is pending.

Missing coverage:

- no durable future-epoch pending queue test
- no key-sync repair trigger assertion
- no retry-after-key-arrival test
- no live diagnostic placeholder/repair UI test
- no finalization lifecycle test
- no proof that a repaired future/missing-key replay re-enters the same validation/signature path before mutation

## regression/tests to add first

Add failing tests before production edits:

- `drain_group_offline_inbox_use_case_test.dart`: future epoch replay stores a durable pending repair entry, creates one pending placeholder, does not decrypt without the key, and dedupes duplicate relay replay.
- `drain_group_offline_inbox_use_case_test.dart`: after saving the missing key and running the repair owner, the pending row is decrypted through the normal replay path, the placeholder is replaced or updated to the real message, media remains validated, and the pending queue is finalized.
- `group_key_update_listener_test.dart`: a valid direct key update for the missing epoch triggers pending repair retry only after `group:updateKey` and `groupRepo.saveKey` succeed.
- `group_key_update_listener_test.dart`: invalid signature, unauthorized sender, wrong recipient, failed `group:updateKey`, and failed key save do not trigger pending repair retry.
- `group_message_listener_test.dart`: a live `group:decryption_failed` diagnostic creates one repair-pending placeholder/surface, triggers the minimal repair request, and does not add a normal message event or notification.
- `group_conversation_screen_test.dart`: pending repair and finalized undecryptable placeholders render truthful safe copy with no plaintext/media controls.
- `go_bridge_client_test.dart`: diagnostic forwarding remains intact and still does not call the normal group-message callback.
- Go test in `pubsub_decryption_failure_test.go` or `pubsub_key_rotation_grace_test.go`: preserve no-normal-delivery behavior, and if a new future-epoch repair diagnostic is added, prove it contains no plaintext, ciphertext, nonce, raw signature, or private key material.

If the durable queue needs a schema migration, add migration/helper tests before wiring the application layer.

## step-by-step implementation plan

1. Dirty-worktree intake: record `git status --short` before edits. Do not revert or restage unrelated modified or untracked files. If another agent changes any owner file during execution, re-read that file and adapt; stop only if the change invalidates the plan's seam.
2. Add the durable queue behind a small repository/helper boundary. Store only what is needed to retry and finalize: group id, message id or deterministic diagnostic id, sender peer id/transport id if available, payload type, missing key epoch, raw offline replay envelope JSON when available, status, trigger count, attempts, last error, created/updated/finalized timestamps. Do not store decrypted plaintext or media material in this queue.
3. If a new table is used, add migration `063`, import it in `lib/main.dart`, bump the DB version from `62` to `63`, wire it in `onCreate` and `onUpgrade`, and update full migration chain coverage. Stop if the database version has already moved in the dirty worktree; rebase the migration number and update tests before continuing.
4. Change offline drain missing-key handling in `drain_group_offline_inbox_use_case.dart`: instead of treating missing replay key as immediately final, upsert the durable repair entry, create or preserve one pending placeholder row, call the minimal repair trigger, emit a repair flow event, and continue draining. Keep the current no-decrypt/no-media-download behavior.
5. Add a narrow repair runner, likely in the same application area or a small `group_pending_key_repair_service.dart`, that loads pending rows for a group/epoch, retries decrypt through `decryptGroupOfflineReplayEnvelope`, then routes the decrypted payload through the same message/reaction handling path currently used by drain replay. Successful repair must clear/finalize the pending queue and replace/update the placeholder without duplicate rows.
6. Wire `GroupKeyUpdateListener` to call the repair runner after a key is saved and after `GROUP_KEY_UPDATE_LISTENER_SAVED` semantics are true. It must not run repair after decrypt failure, unauthorized sender, invalid signature, wrong recipient, failed `group:updateKey`, or failed key save.
7. Add the minimal key-sync repair trigger. Implement it as a small injectable callback/coordinator and prove it fires once when a new future/missing-key repair item is created. Prefer existing recovery/drain mechanisms over a new protocol; if implementation adds a bridge/Go signal, keep it scoped to a key-repair request and do not add history range/head/hash repair.
8. Extend live diagnostic handling. Subscribe the group app layer to `groupDiagnosticEventStream` or pass a diagnostic stream into `GroupMessageListener`; handle only `group:decryption_failed` and any explicitly added future-epoch key-repair diagnostic. Create one pending placeholder per deterministic diagnostic key, call the minimal repair trigger, and never call the normal message callback or show normal notifications from this diagnostic.
9. Update `GroupConversationScreen` copy/states only for pending repair and finalized undecryptable statuses. Keep failed-media retry/delete actions unavailable for incoming repair placeholders.
10. Preserve Go fail-closed behavior. If `pubsub.go` changes, keep validator/decrypt rejection before normal delivery and add only privacy-safe diagnostics needed by the app repair trigger. Do not expose raw encrypted blobs in logs, flow events, or user-visible errors.
11. Finalization policy: keep items `pending_key` while the required key is still missing; mark `repaired` only after replay succeeds through the normal handler; mark `undecryptable` only after the key exists and decrypt/parse/validation fails, or after a live diagnostic item without a raw envelope exhausts the executor's bounded retry/sweep policy. Re-running finalization must be idempotent.
12. Run the direct tests and gates below. Update source rows/inventory/breakdown only after implementation evidence exists; no source row should be marked `Covered` from plan text alone.

## risks and edge cases

- Duplicate replay: the same relay envelope may arrive more than once before or after key arrival. It must produce one queue row and one visible placeholder/message.
- Restart: pending queue and pending placeholder must survive app restart and retry after key arrival or a recovery sweep.
- Key-update ordering: repair must run only after Go key state and the local key repository are committed.
- Unauthorized key update: rejected key updates must not trigger repair.
- Wrong-key/tampered content: repair should not loop forever; finalization must be safe and idempotent.
- Media replay: repaired media must still pass existing descriptor/hash/size/MIME validation before message or attachment persistence.
- Live diagnostic without raw envelope: the UI may only be able to show pending/finalized safe state until offline replay or another valid source supplies the encrypted replay. Do not invent plaintext or message IDs.
- Privacy: diagnostics and placeholders must not expose group keys, ciphertext, nonce, raw signatures, private keys, media object keys, multiaddrs, or original plaintext.

## exact tests and gates to run

Direct first-pass red/green tests:

- `flutter test --no-pub test/core/database/migrations/063_group_pending_key_repairs_test.dart test/core/database/helpers/group_pending_key_repairs_db_helpers_test.dart` if schema is added
- `flutter test --no-pub test/features/groups/domain/repositories/group_pending_key_repair_repository_impl_test.dart` if a repository impl is added
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart` if schema/version changes
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR future epoch replay queues and repairs after key arrival'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save'`
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR rejected key updates do not trigger pending repair'`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR live decryption failure creates repair placeholder and trigger without normal delivery'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR renders pending and finalized repair placeholders safely'`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group decryption failure push event reaches diagnostics stream without invoking group message callback'`
- `cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_EmitsDecryptionFailedEvent$|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedNonce|TestHandleGroupSubscription_EmitsDecryptionFailedEventForTamperedCiphertext|TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery|TestHandleGroupSubscription_DropsPreviousEpochAfterGraceExpires' -v`

Full direct owner suites after focused tests pass:

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`
- `flutter test --no-pub test/features/groups/application/*key*_test.dart`
- `cd go-mknoon && go test ./node -run 'GroupTopicValidator|HandleGroupSubscription|GroupKey|KeyRotation' -v`

Named gates and hygiene:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check` if any new test file, migration file, or gate-classification doc is added
- `git diff --check`

Device/relay profile:

- Default profile is host/fake-network first; no real device gate is required to make the implementation safe.
- Run `./scripts/run_test_gates.sh group-real-network-nightly` only if implementation adds a real transport requirement or host/fake tests cannot prove the repair trigger. That gate requires `FLUTTER_DEVICE_ID` and uses `MKNOON_RELAY_ADDRESSES`; those env vars are not set in the current shell, so do not block host implementation on them.

## known-failure interpretation

- Treat the broad dirty worktree as preexisting unless an edited file overlaps the executor's changes; do not revert unrelated modifications.
- Existing docs record an unrelated broad application-suite MD-011 future-media replay failure in some previous runs. A focused future/missing-key repair failure in `drain_group_offline_inbox_use_case_test.dart` is blocking for this session; a preexisting unrelated broad-suite failure is not.
- Existing broad Go owner slices may include unrelated peer-mismatch failures. The focused Go regex above must pass; unrelated peer-count/peer-mismatch failures outside the focused repair and decrypt paths should be recorded, not fixed here.
- If migration numbering conflicts because another agent adds migration `063`, stop and renumber this migration before running tests.

## done criteria

- A missing/future-key offline replay creates one durable pending repair record and one safe pending placeholder without decrypting or exposing plaintext.
- A valid key update for the missing epoch retries queued replay only after key state is saved.
- Successful retry replaces or updates the placeholder into the real decrypted message through the normal validation/persistence path.
- Failed retry finalizes exactly once to a safe `undecryptable` state.
- Live decryption failure diagnostics create a safe pending/finalized surface and trigger repair without normal group message delivery.
- Direct Flutter, Go, named gate, migration, and diff hygiene commands required above pass or have precise preexisting unrelated failures recorded.
- Source docs are updated only after evidence exists; plan creation alone does not change EK-005, ER-004, or EK-004 status.

## scope guard

Do not implement or plan:

- welcome/key-package lifecycle or MLS admission work
- broad signed audit work already accepted in `PREREQ-SIGNED-COMMIT-AUDIT`
- receipts or group sync cursor transaction work
- first-class remote ban/delete/tombstone event families
- history range/head/hash gap repair or multi-peer repair source selection
- new transport cryptography or account/device registry semantics
- plaintext recovery, ciphertext exposure in diagnostics, or UI that implies repair succeeded before it actually did

Overengineering for this session includes a general anti-entropy protocol, receipt-backed sync, a multi-source history repair manager, or a new product surface outside the conversation placeholder/repair state.

## accepted differences / intentionally out of scope

- Live diagnostics may not include the raw encrypted envelope. That is acceptable if the app shows a pending/finalized safe placeholder and relies on offline replay/key arrival for actual repair rather than exposing encrypted blobs to Flutter.
- Unknown future live epochs may continue to be rejected before delivery in Go. The prerequisite closes only if future/missing-key content is recoverable through durable replay queue/key-arrival behavior and the live path has truthful repair/placeholder state.
- EK-004 complete row closure remains intentionally out of scope unless execution separately proves all shipped event-family offline replay signature equivalence.

## dependency impact

Closing this prerequisite can unblock EK-005 and ER-004 if the closure bar is met. It can also narrow EK-004's future/missing-key offline replay blocker. It does not close welcome/key-package replay, remote event family replay, receipts, history gap repair, or secret storage blockers.

If the durable queue design changes during execution, revisit downstream prerequisite rows that mention future/missing-key replay behavior before marking any source row `Covered`.

## reviewer notes

Sufficient with adjustments applied.

- Missing files/tests/gates: the draft needed explicit queue helper/repository tests, bridge diagnostic preservation, and rejected-key-update non-trigger coverage; these are now listed.
- Stale or incorrect assumptions: none found. The plan correctly treats current fail-closed placeholder behavior as insufficient for EK-005/ER-004 closure.
- Overengineering risk: the repair trigger was too open-ended. It is now constrained to an injectable callback/coordinator or a scoped key-repair request, with history repair and receipts excluded.
- Decomposition: sufficient. The executor can implement persistence first, then offline queueing, key-arrival retry, live diagnostics, UI, and Go preservation without broad row bleed.
- Minimum needed for sufficiency: explicit finalization policy and migration/version stop conditions, now included.

## arbiter decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details intentionally deferred:

- exact table and column names may change if migration `063` is already taken
- exact placeholder copy can be chosen during implementation as long as it is safe, truthful, and covered by widget tests
- exact repair trigger implementation can be an injectable coordinator, existing recovery/drain hook, or scoped key-repair request as long as direct tests prove it fires once per pending item/reason window and does not become history repair

Accepted differences intentionally left unchanged:

- live diagnostics do not need to expose raw encrypted envelopes to Flutter
- unknown future live epochs may remain validator-rejected before normal delivery
- EK-004 complete row closure remains outside this prerequisite unless separate all-event-family replay equivalence proof is added

Why safe now: the missing behavior is repo-owned, source rows explicitly require code+tests, host/fake-network coverage is sufficient for the first implementation pass, and the plan includes dirty-worktree, migration, closure-bar, and named-gate stop conditions.
