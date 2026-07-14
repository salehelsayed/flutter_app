# Plan 234 Session 03 — Atomic Reveal, Expiry, Cleanup, and Restart Convergence

Status: accepted
Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 03
Run mode: implementation-committed gap-closure
Dependencies: Sessions 01 and 02 accepted; v100 is fixed; no migration/v101 is permitted

## Planning Progress

- `2026-07-11 13:00 CEST` — Fresh Evidence Collector grounded the accepted parent fields, replacing message upsert, delivery-only CAS, owner-aware attachment CAS, process-wide attachment lock, storage eviction, download commit, delete, resume, and cold-start seams. No structural blocker.
- `2026-07-11` — Local bounded planning fallback completed after the fresh planner stopped with a grounded but non-reusable intake draft. The SQL CAS, lease, cleanup, clock, race, restart, tests, and gates are frozen below.
- `2026-07-11 13:08 CEST` — **Execution preflight contract tightened from root audit.** Files inspected since the last update: execution-orchestrator contract, current Session-03 plan, accepted Sessions 01-02, source plan, current download/attachment-lock/parent-state seams, gate completeness contract, and dirty baseline. Decision/blocker: the prior draft's in-lock parent callback still left a SQL gap, had no foreground expiry liveness, over-broadened opening/viewing beyond View Once, omitted explicit completeness proof, and described private deletion ambiguously. Those five supplied corrections are now mandatory below; implementation remains blocked until this edit is persisted. Next action: run RED-first against the corrected atomic transaction, scheduler, View Once-only, gate-registration, and truthful hidden-tombstone contract.

## Problem And Evidence

Sessions 01-02 can persist, receive, redact, and explicitly download private media, but private rows still have no lifecycle executor. `MessageRepository.saveMessage` is a replacing upsert and cannot safely claim `available -> opening -> viewing -> consumed/expired`; direct parent state has no lifecycle-specific CAS/query API. Attachment download commit is locked and SQL-conditional, while eviction spans a claim/file/finalize saga and private terminal cleanup does not exist. A timer or read-then-save implementation would permit concurrent opens, clock rollback extension, late download resurrection, stale first-frame callbacks, and partial cleanup that cannot converge after restart.

Session 03 closes that transactional core without changing the v100 schema.

## Scope Contract And Guard

### Direct parent lifecycle authority

Add a narrow typed `DirectPrivateMediaLifecycleRepository` (or equivalently named capability) backed by new helpers in `messages_db_helpers.dart` and production `MessageRepositoryImpl`. It must use SQL conditional updates/transactions, never `saveMessage`, for all lifecycle mutations:

- qualify/read current direct parent lifecycle snapshot;
- claim one `available -> opening` transition only when policy is view-once, current high-water is not expired, and the row remains visible/eligible;
- mark first frame `opening -> viewing` with `revealed_at` and monotonic high-water;
- same-process pre-frame rollback `opening -> available` only for the active ephemeral lease token;
- terminalize `opening|viewing -> consumed` before cleanup;
- atomically advance clock high-water to `max(stored, now)` and transition due disappearing states to `expired` with terminal timestamp in the same transaction/update;
- hide/delete-for-me private rows through a conditional `hidden_at` tombstone transition rather than physically deleting the parent, so replay cannot resurrect them; deletion authority is the durable hidden tombstone, not a false `consumed` or `expired` lifecycle label;
- query bounded interrupted `opening|viewing`, due disappearing, and terminal-with-residual-artifact candidates for cold-start/resume convergence.

All successful repository CAS writes must re-read/emit a current message snapshot through the existing change stream. Zero-row updates are normal race losses and must not be converted to replacing writes.

### Reveal lease and restart truth

Add a reusable `PrivateMediaLifecycleEngine` plus direct adapter/use cases:

- `open` acquires the exact attachment process lock, re-reads direct owner/current attachment and parent, advances high-water/expiry first, and then claims opening. Only one concurrent opener receives an opaque in-process lease token and canonical local path.
- Lease tokens are process-memory authority and are never persisted. Only the exact active token may mark first frame, rollback a proven decode failure before first frame, or terminalize.
- Mark-first-frame uses durable CAS; a callback arriving after consumed/expired/delete is a no-op and never exposes/reopens bytes.
- Explicit close, route exit, background/capture callback, or terminal error claims terminal state before any file/key/path cleanup.
- A restarted process has no lease token. Every persisted `opening` or `viewing` row terminalizes fail closed and is cleaned; it can never restore `available`.
- `opening`/`viewing`, ephemeral leases, first-frame transitions, rollback, and consumed terminalization are **View Once only**. Protected media never enters those states. Disappearing media remains `available` while viewable and expires from `available`; an impossible persisted disappearing `opening`/`viewing` row is corrupt fail-closed recovery input, never a normal transition. View Once never gains a timer.

Session 05 wires the final private route/native UX to these hooks. Session 03 owns the application controller/hooks and causal lifecycle behavior, not platform capture UI.

### Expiry clock

- Inject a millisecond clock for tests; production uses UTC wall time.
- Receiver-local `expires_at` from Session 02 is immutable.
- Every open/sweep/resume evaluates `effectiveNow = max(now, persistedHighWater)` and persists that high-water atomically.
- `effectiveNow >= expiresAt` transitions to expired with no grace.
- A forward jump may expire early; a backward jump cannot lower high-water, extend expiry, or resurrect state.
- Repeated/stale/concurrent sweeps are idempotent; a stale sweep can neither overwrite a newer terminal state nor write a lower high-water.

### Cleanup and race authority

- Durable consumed/expired/delete tombstone claim always precedes cleanup.
- Cleanup is retryable and idempotent. A failure leaves the parent terminal and enough direct attachment metadata to retry on resume/cold start.
- For each exact direct-owned attachment, use the shared `MediaAttachmentLifecycleLock`; re-read parent terminal state plus attachment owner/message identity inside the lock; delete canonical file, staged `.enc`/`.part`, pending upload residue, secure key, bookmark/playback/local-path state, and finally the direct attachment row. Only remove the row after prior cleanup steps succeed.
- Add a narrow repository cleanup operation or adapter that owns the lock and exact owner/id delete. Do not call a second locking method recursively.
- A same-message-ID group or unresolved attachment is never loaded, locked as a direct target, mutated, or deleted.
- Download transfer need not hold the lock, but direct final commit must use one direct-private SQL transaction/conditional helper under the existing attachment lock. That single database authority must atomically advance/check the parent's high-water/expiry and visible non-hidden `available` eligibility **and** conditionally change the exact direct-owned attachment from this download's `downloading` claim to `done` with its local path. A callback/pre-commit read inside the process lock is insufficient. When expiry/delete/consume wins, the transaction commits no path, returns false, and the exact staged/promoted candidate bytes are removed while terminal cleanup remains under the same attachment lock.
- `MediaStorageManager` holds the same process lock across direct eviction claim, file deletion, and path finalize; terminal cleanup and eviction therefore cannot interleave their file/key/row sagas.
- Private Delete-for-me first persists a truthful local hidden tombstone (`hidden_at`/minimal retained parent identity) that is independently terminal for eligibility and replay suppression, without relabeling protected/disappearing content as `consumed` or `expired`; cleanup follows under the attachment lock. Ordinary Delete-for-me remains unchanged.

### Recovery wiring

- Add one bounded, error-isolated local lifecycle reconciliation function for both cold start and resume.
- It runs before the account-migration network gate, like other local committed cleanup, and performs: interrupted opening/viewing terminalization, monotonic due-expiry sweep, then retry of terminal cleanup residue.
- Add a foreground `PrivateMediaExpiryScheduler` (or equivalently narrow timer owner) that queries the next due disappearing expiry, arms/reschedules one timer, runs the same monotonic expiry/cleanup engine when due, and immediately queries the next deadline. Start/re-arm it on cold start and resume, suspend/cancel it on background, and reschedule it when a newly committed incoming disappearing parent is emitted by the existing repository change signal. Open/resume sweeps alone are insufficient foreground liveness.
- Production wiring in `main.dart` must use the same engine/repositories/clock. No network/relay call is introduced.

### Likely owner files

- `lib/core/media/private_media_lifecycle_engine.dart` (new)
- `lib/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart` (new) and production adapter/implementation
- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart` / `_impl.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/core/media/media_storage_manager.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/direct_private_media_lifecycle.dart` (new direct adapter/controller for reveal, cleanup, and bounded recovery)
- `lib/features/conversation/application/private_media_expiry_scheduler.dart` (new)
- `lib/core/lifecycle/handle_app_resumed.dart`
- minimal production cold-start/resume wiring in `lib/main.dart`

### Out of scope

- Any schema/version/migration/v101 change.
- Composer/notification policy already closed by Session 02 except necessary lifecycle-caller preservation.
- Save/Share/Forward/bookmark/library/PiP central action qualification (Session 04).
- Final private viewer presentation, copy, Android/iOS capture protection, and device proof (Session 05).
- Group/announcement lifecycle adapters, Go/libp2p/relay authority, account-wide consumption.

## Test Contract

Author causal REDs before production changes.

1. `test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart`
   - exact conditional transitions and timestamp/high-water writes;
   - zero-row race loss never replaces state;
   - atomic high-water/expiry under stale/backward/concurrent clocks;
   - terminal/delete tombstone query and bounded recovery candidates;
   - ordinary/non-private/outgoing/missing rows fail closed.
2. `test/features/conversation/application/consume_private_media_use_case_test.dart`
   - two concurrent opens yield exactly one lease/path;
   - first frame durably records viewing once;
   - only same token may pre-frame rollback;
   - stale/wrong/post-terminal callback cannot mark, rollback, reveal, or reopen;
   - close/background terminal claim precedes cleanup;
   - protected and unsupported modes cannot use view-once opening.
3. `test/features/conversation/application/private_media_expiry_scheduler_test.dart`
   - boundary `now == expiresAt`, forward jump, backward jump/high-water, duplicate/stale/concurrent sweeps;
   - normal disappearing expiry is `available -> expired`; protected/View Once never join the timer;
   - impossible corrupt disappearing `opening`/`viewing` rows fail closed without legitimizing those transitions;
   - foreground timer queries/arms the next deadline, fires without an app lifecycle transition, reschedules after a newly committed incoming disappearing parent change event, and cancels/re-arms across background/resume;
   - view-once/protected timer N/A.
4. `test/features/conversation/integration/private_media_restart_replay_test.dart`
   - restart from opening or viewing terminalizes consumed and cleans;
   - terminal cleanup failure leaves retryable residue and next run converges;
   - repeated recovery is no-op;
   - replay/duplicate cannot reopen parent or remint a lease.
5. `test/features/conversation/application/private_media_cleanup_race_test.dart`
   - durable terminal claim occurs before file/key delete;
   - download commit losing to expiry removes candidate bytes and cannot restore local path;
   - eviction/delete/expiry serialize on the shared attachment lock;
   - cleanup exception preserves terminal parent + attachment metadata for retry;
   - canonical, staged, pending-upload, secure-key, bookmark/playback/local-path residue disappears after success;
   - same-ID group and unresolved siblings remain byte-for-byte unchanged.
6. Extend `test/features/conversation/application/download_media_use_case_test.dart`
   - direct private final commit uses the atomic cross-table SQL transaction under the attachment lock, not a callback read;
   - pause after the earlier parent read, expire/consume/hide the parent, then resume commit: zero durable path, exact promoted-file cleanup, terminal state unchanged;
   - terminal race loses safely; ordinary direct/group commits preserve behavior.
7. Extend `test/core/media/media_storage_manager_test.dart`
   - whole eviction saga shares lifecycle lock and converges when terminal cleanup wins/loses.
8. Extend `test/features/conversation/application/delete_message_use_case_test.dart`
   - private Delete-for-me persists a hidden terminal tombstone before cleanup, retains a truthful mode/state (never falsely consumed/expired), and replay cannot resurrect;
   - ordinary physical deletion remains unchanged.
9. `test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart`
   - cold start and resume invoke the same local bounded recovery before the network gate;
   - failures are isolated and subsequent lifecycle work continues;
   - no network/relay dependency.
10. Run existing Session-02 composer/send/receive/download/notification and ordinary encrypted round-trip tests as preservation sentinels.
11. Register every new direct/core lifecycle file in both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` as applicable; keep `test-gate-definitions.md` synchronized and prove `./scripts/run_test_gates.sh completeness-check` green.

Representative mutations that must fail: read+save replacing CAS; parent callback read followed by a separate attachment commit; cleanup before terminal claim; rollback with stale token; first-frame after expiry; let protected/disappearing enter View Once opening/viewing; lower high-water on backward clock; reset expiry from stale sweep; omit the foreground timer/reschedule signal; download commit after terminal; unlock between eviction claim/delete/finalize; delete group sibling; delete attachment row before failed file/key cleanup; label protected/disappearing Delete-for-me as consumed/expired; restart opening to available; run recovery after the network gate; omit a new test from either 1:1 inventory/completeness classification.

## Implementation Sequence

1. RED SQL parent CAS/high-water/tombstone/recovery helpers.
2. Implement typed direct lifecycle repository and change-stream emission.
3. RED and implement lease/open/first-frame/rollback/terminal controller.
4. RED and implement monotonic expiry sweep plus foreground next-due scheduling/change-signal rescheduling.
5. RED and implement retryable direct-owner cleanup under the shared attachment lock.
6. Close download commit, eviction, and private-delete interleavings.
7. Wire one bounded cold-start/resume reconciliation pass before network gating.
8. Register every new causal test in both applicable 1:1 arrays and gate definitions; run focused causal tests, exact ordinary/session sentinels, curated `1to1`, host inventory, completeness-check, scoped formatter/analyzer/diff/scope guards, and independent QA.

## Device/Relay Proof Profile

- Profile: `host-only`.
- SQL CAS, fake clocks, process locks, file/key failure injection, restart repository reopen, and lifecycle ordering are deterministically host-testable.
- No native OS, real-network, paired-device, relay, or new SQLCipher schema boundary changes in this session.
- Session 05 owns available-platform proof; unavailable hardware is irrelevant here.

## Acceptance Gates

```bash
git status --short

flutter test test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart
flutter test test/features/conversation/application/consume_private_media_use_case_test.dart
flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart
flutter test test/features/conversation/integration/private_media_restart_replay_test.dart
flutter test test/features/conversation/application/private_media_cleanup_race_test.dart
flutter test test/features/conversation/application/download_media_use_case_test.dart
flutter test test/core/media/media_storage_manager_test.dart
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart

flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart test/features/push/application/push_decrypt_preview_test.dart

./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check

dart format --output=none --set-exit-if-changed lib/core/media/private_media_lifecycle_engine.dart lib/core/database/helpers/messages_db_helpers.dart lib/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart lib/features/conversation/domain/repositories/message_repository.dart lib/features/conversation/domain/repositories/message_repository_impl.dart lib/features/conversation/domain/repositories/media_attachment_repository.dart lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart lib/features/conversation/application/direct_private_media_lifecycle.dart lib/features/conversation/application/private_media_expiry_scheduler.dart lib/features/conversation/application/download_media_use_case.dart lib/core/media/media_storage_manager.dart lib/features/conversation/application/delete_message_use_case.dart lib/core/lifecycle/handle_app_resumed.dart lib/main.dart test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart test/features/conversation/application/consume_private_media_use_case_test.dart test/features/conversation/application/private_media_expiry_scheduler_test.dart test/features/conversation/integration/private_media_restart_replay_test.dart test/features/conversation/application/private_media_cleanup_race_test.dart test/features/conversation/application/download_media_use_case_test.dart test/core/media/media_storage_manager_test.dart test/features/conversation/application/delete_message_use_case_test.dart test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart
dart analyze lib/core/media/private_media_lifecycle_engine.dart lib/core/database/helpers/messages_db_helpers.dart lib/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart lib/features/conversation/domain/repositories/message_repository.dart lib/features/conversation/domain/repositories/message_repository_impl.dart lib/features/conversation/domain/repositories/media_attachment_repository.dart lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart lib/features/conversation/application/download_media_use_case.dart lib/core/media/media_storage_manager.dart lib/features/conversation/application/delete_message_use_case.dart lib/core/lifecycle/handle_app_resumed.dart lib/main.dart
git diff --check
git diff --name-only -- lib/core/database/migrations lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart go-mknoon go-relay-server lib/features/groups lib/features/announcements
```

No device leg, `core-host-all`, `feature-host-all`, or full `host-all` is a Session-03 gate.

## Done Criteria

- [x] Causal REDs precede production changes for parent CAS, lease, expiry, cleanup/restart, and every named interleaving.
- [x] Lifecycle mutations use SQL conditional/CAS operations; no lifecycle path uses replacing `saveMessage`.
- [x] Exactly one concurrent opener receives an ephemeral lease; rollback is same-token/pre-first-frame only; restart opening/viewing terminalizes.
- [x] First-frame/close/background/stale callbacks are monotonic and cannot act after terminalization.
- [x] Expiry atomically persists high-water and never extends/reopens under backward/stale/duplicate sweeps; one foreground timer expires due disappearing rows without requiring open/resume and reschedules on new incoming repository changes.
- [x] Consumed/expired/private-delete terminal claim precedes cleanup; cleanup failure remains retryable and idempotently converges.
- [x] Direct private download final commit atomically checks parent expiry/visibility/eligibility and attachment claim in one DB transaction under the shared lock; eviction, delete, and cleanup use the same lock, and every race loser leaves no bytes/path/key resurrection.
- [x] Direct cleanup removes only exact direct artifacts; same-ID group/unresolved siblings survive.
- [x] Cold start/resume recovery is bounded, local, error-isolated, before network gating, and uses one engine.
- [x] Private Delete-for-me retains a durable hidden tombstone without mislabeling protected/disappearing state as consumed/expired; replay stays suppressed.
- [x] Ordinary/Session-02 behavior remains green; no migration/v101/cross-lane/Go/relay/device scope lands.
- [x] Every new causal test is registered in both applicable 1:1 arrays/gate docs; focused tests, curated `1to1`, host inventory, completeness-check, scoped formatter/analyzer, diff/scope guards, and independent QA pass.

## Execution Preflight

- **Validated:** `2026-07-11 15:32 CEST`; resume classification `in_progress`; invocation topology is isolated Executor followed by a fresh independent QA Reviewer. Degraded local QA is not authorized. Requested GPT-5.5/xhigh controls are unavailable to the spawn API, so the inherited runtime applies and is not acceptance evidence.
- **Source of truth:** this Session-03 contract, subject to repo `AGENTS.md` and the current 1:1/completeness gate definitions.
- **Acceptance bar:** every unchecked Done Criterion above, every exact command in Acceptance Gates, and a fresh independent QA pass must resolve before `accepted`.
- **Implementation ownership:** the direct-private lifecycle SQL/repository, attachment transfer/cleanup repository, download/replay/delete application seams, shared attachment lock/storage eviction, lifecycle engine/recovery, direct path/transfer helpers, their direct tests, and required 1:1 inventory/docs registrations. Scheduler/runtime/main are a previously completed frozen seam except for a compile-required coordinated constructor/wiring correction.
- **Code-entry files:** `messages_db_helpers.dart`; `direct_private_media_lifecycle_repository.dart`; `message_repository_impl.dart`; `media_attachment_repository.dart` and `_impl.dart`; `private_media_lifecycle_engine.dart`; `direct_private_media_lifecycle.dart`; `private_media_expiry_scheduler.dart`; `direct_private_media_path_guard.dart`; `direct_private_media_transfer_registry.dart`; `download_media_use_case.dart`; `media_storage_manager.dart`; `delete_message_use_case.dart`; `handle_app_resumed.dart`; and compile-required `main.dart` wiring. Direct tests are the nine focused Session-03 commands plus the four preservation commands in `Acceptance Gates`.
- **Required remaining RED/counterexample work:** atomic exclusive transfer ownership and restart reclaim; full guarded-key compensation; promotion/commit/cleanup loss; local-ready/failure CAS; replay/write suppression and bounded recovery fairness; MIME/path/integrity drift; private Delete-for-everyone convergence. Existing SQL, lease, expiry, cleanup, restart, scheduler, and lifecycle-wiring regressions remain mandatory preservation proof.
- **Direct tests and named gates:** exactly the commands in `Acceptance Gates`; no device leg, `core-host-all`, `feature-host-all`, or full `host-all`. No required failure is pre-authorized as known or acceptable.
- **Known-failure interpretation:** none. Every required failure starts `pending_triage` and must be focused/classified before a fix or broader rerun.
- **Non-goals/scope guard:** no schema/v101, group/announcement, Go/relay, Session-04 actions, Session-05 viewer/native, or cross-device work. The shared dirty worktree also contains accepted Sessions 01-02, Plan-247 work, reporting decisions, Graphify changes/output, and unrelated rollout artifacts; preserve them and do not attribute them to Session 03.
- **Scoped pre-existing changes:** all source/tests materialized in the controller's `2026-07-11 15:30 CEST` aggregate snapshot `f09c1e73e0afeb24aafb88891d20937b84fae0f42018bbe37ba8d6bb157980fa` are the authorized baseline. Current inspection confirms the six new Session-03 causal files are not yet registered in either 1:1 array or the gate-definition doc; that is an implementation-owned gap, not pre-existing accepted evidence.
- **Reusable evidence:** the recorded 23/23 SQL/engine/restart/cleanup and 14/14 scheduler/runtime passes are trustworthy only for files not invalidated by the remaining Executor diff. All affected evidence and every final named gate still run before acceptance.
- **Graph grounding:** compact architecture queries returned `confidence=broad` and reported stale topology at `lib/main.dart`; they surfaced attachment cleanup/download repository seams but missed the exact Session-03 plan. Treat that as a graph gap, verify current source/tests directly, and run one `affected` query over the final scoped file list before QA/finalization.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 16:11 CEST | final execution verdict persisted | `## Execution Result`; final QA; post-QA Graphify refresh; final evidence ledger | Final verdict `accepted`. Independent final QA accepted with no `B`/`N` findings after `fix_passes=1`; all required direct/sentinel/gate/static/scope evidence is resolved; single incremental refresh passed; no blocker or follow-up remains. | stop and return the accepted handoff to the pipeline controller; closure agent owns breakdown/source-plan closure |
| 2026-07-11 16:10 CEST | post-QA refresh complete / pre-verdict | `./graphify-arch/refresh_arch_graph.sh --incremental`; final status, diff check, and scope guard | Single required refresh exits 0: 36 changed code files, graph 47,313 nodes / 73,533 edges, TDD overlay 1,257 files / 12,295 tests / 951 production targets (`/tmp/plan234-s03/final-graph-refresh.log`). Final status and scope snapshot captured; `git diff --check` exits 0. Scope output remains only authorized pre-existing Session-01/group files. No code/test/gate changed after final QA. | write the durable `## Execution Result` with verdict `accepted`, then record final-verdict progress and stop |
| 2026-07-11 16:09 CEST | final QA accepted / post-QA refresh | final independent QA review; coherent app-owned Session-03 change set | Final QA verdict `accepted`; blocking findings none; non-blocking findings none; B1 resolved after `fix_passes=1`. No degraded fallback. Last evidence: final QA source/log/done-criteria audit. Current command: the single required `./graphify-arch/refresh_arch_graph.sh --incremental`. | require refresh exit 0, capture final status/diff check, then persist `## Execution Result` with final verdict `accepted` |
| 2026-07-11 16:07 CEST | Final independent QA complete | current Session-03 SQL/attachment/restart source and causal tests; first QA `B1`; fix-pass handoff; all named `fix1-*` artifacts; current status/scope attribution | Final QA verdict `accepted`; `B` findings none; `N` findings none. B1 is resolved: one transactional `MAX(stored, now)` advance now preserves unexpired rollback and the `>= expires_at` predicate terminalizes exactly at/after deadline; all guarded attachment mutations retain the same transaction authority. RED failed on both intended counterexamples; final SQL 14/14, scheduler 11/11, download 66/66, restart 2/2, and curated `1to1` 1875/1875 pass. Static evidence and scope attribution are resolved. | return accepted final-QA handoff; controller owns the one post-QA Graphify refresh and `## Execution Result` |
| 2026-07-11 16:04 CEST | Final independent QA active | Session-03 plan; current SQL helper and lifecycle/restart tests; fix-pass diffs; named `fix1-*` evidence | Fresh final Reviewer started after fix pass 1. Last completed command: required skill/repo/plan intake PASS. Current evidence: B1 correction, causal RED/GREEN SQL coverage, restart convergence, gate/static logs, and authorized 15:30 baseline. Decision pending; no gate rerun planned unless evidence is inconsistent. | inspect exact current diffs and every named artifact; verify B1 disposition, scope/attribution, done criteria, and persist final QA verdict |
| 2026-07-11 16:02 CEST | QA fix pass 1 complete / pre-final-QA | SQL helper; SQL/scheduler/download/restart proofs; curated `1to1`; formatter/analyzer/diff; focused affected Graphify/current callers | B1 fixed with RED-first proof. Final SQL, scheduler, download, and restart commands PASS; curated `1to1` PASS 1875/1875; exact formatter PASS 0 changed; analyzer PASS `No issues found`; diff check PASS. Affected query PASS and exact clock/qualifier callers are verified in `main.dart`, repository wiring, media attachment helpers, fixture, and tests. No blocking fix-pass issue remains. | persist fix-pass handoff and spawn a fresh final independent QA Reviewer; refresh Graphify only after no blocking finding |

## Executor Handoff

- **Executor disposition:** implementation and required evidence complete; ready for independent QA. This was isolated-Executor mode with inherited runtime; the requested GPT-5.5/xhigh controls were unavailable to the spawn API. No degraded fallback and no QA fix pass have been used.
- **Authorized baseline:** every file in the controller's `2026-07-11 15:30 CEST` aggregate snapshot `f09c1e73e0afeb24aafb88891d20937b84fae0f42018bbe37ba8d6bb157980fa` is pre-existing materialized work. The prior writer blocker remains resolved; no fresh unattributed mutation was observed.
- **Attributable Executor changes:** registered the six new causal suites in both 1:1 arrays and the gate doc; removed three Session-03 lint findings; mechanically formatted five authorized Session-03 files; replaced two null-check set elements with null-aware elements in the exact private-transfer purge path; updated required test fakes for the current guarded private-save and redacted-delete typed seams; and corrected the older batch-delete sentinel to account for the mandatory current-parent authority re-read. The plan progress/handoff was updated. No schema/version/migration, group/announcement, Go/relay, Session-04/05/06, device, or Plans 238/247/249 work was changed by this Executor.
- **Tests added or updated:** the already-materialized Session-03 causal files were preserved. This Executor updated `handle_incoming_chat_message_use_case_test.dart`, `one_to_one_media_encryption_round_trip_test.dart`, `chat_message_listener_test.dart`, and `direct_media_library_batch_delete_test.dart` only to keep their test doubles/expectations coherent with current production authority; it also removed/format-cleaned lint-only lines in the SQL, consume, cleanup, and delete tests.
- **Focused implementation evidence:** initial causal batch `50/50` PASS (`/tmp/plan234-s03/initial-focused-batch.log`); large seam batch `88/88` PASS (`/tmp/plan234-s03/initial-large-seams.log`); final scoped analyzer reports `No issues found` (`/tmp/plan234-s03/exact-analyze-final.log`).
- **Required evidence ledger:** every command ran from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`; no known failure was accepted.

| Command | Result | Classification / artifact |
|---|---|---|
| `flutter test test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-sql.log` |
| `flutter test test/features/conversation/application/consume_private_media_use_case_test.dart` | exit 0 | `passed`; final affected rerun `/tmp/plan234-s03/post-format-consume.log` |
| `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-scheduler.log` |
| `flutter test test/features/conversation/integration/private_media_restart_replay_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-restart.log` |
| `flutter test test/features/conversation/application/private_media_cleanup_race_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-cleanup.log` |
| `flutter test test/features/conversation/application/download_media_use_case_test.dart` | exit 0 | `passed`; final affected rerun `/tmp/plan234-s03/post-lint-download.log` |
| `flutter test test/core/media/media_storage_manager_test.dart` | exit 0 | `passed`; final affected rerun `/tmp/plan234-s03/post-format-storage.log` |
| `flutter test test/features/conversation/application/delete_message_use_case_test.dart` | exit 0 | `passed`; final affected rerun `/tmp/plan234-s03/post-format-delete.log` |
| `flutter test test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-recovery.log` |
| `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` | exit 0 | `passed` after typed fake fix; `/tmp/plan234-s03/exact-roundtrip-rerun.log` |
| `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` | exit 0 | `passed` after guarded-authority fake fix; `/tmp/plan234-s03/exact-incoming-rerun-2.log` |
| `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-composer.log` |
| `flutter test test/features/push/application/show_notification_use_case_test.dart test/features/push/application/push_decrypt_preview_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-push.log` |
| `./scripts/run_test_gates.sh 1to1` | exit 0 | `passed` after two focused test-only repairs; `/tmp/plan234-s03/exact-1to1-gate-rerun.log` |
| `./scripts/run_host_test_gates.sh 1to1 --list` | exit 0 | `passed`; all six new suites present; `/tmp/plan234-s03/exact-host-list.log` |
| `./scripts/run_test_gates.sh completeness-check` | exit 0 | `passed`, `1164/1164`; `/tmp/plan234-s03/exact-completeness.log` |
| exact scoped `dart format --output=none --set-exit-if-changed ...` | exit 0 | `passed`, 23 files / 0 changes; `/tmp/plan234-s03/exact-format-final.log` |
| exact scoped `dart analyze ...` | exit 0 | `passed`, `No issues found`; `/tmp/plan234-s03/exact-analyze-final.log` |
| `git diff --check` | exit 0 | `passed`; `/tmp/plan234-s03/exact-diff-check-final.log` |
| scope guard command from `Acceptance Gates` | exit 0 | `passed` command; non-empty output is the authorized pre-existing Session-01/group baseline, not Session-03 attribution; `/tmp/plan234-s03/exact-scope-guard-final.log` |
| `git status --short` | exit 0 | `passed` snapshot; shared dirty baseline preserved; `/tmp/plan234-s03/exact-git-status-final.log` |
| `python3 graphify-arch/tdd_context.py affected <16 Session-03 production files> --budget 600` | exit 0 | `passed`; surfaced callers were verified by targeted current-source search; graph remains stale at preflight `lib/main.dart` until the required post-QA incremental refresh |

- **Failure triage dispositions:** initial round-trip, incoming, listener, and batch-delete failures were each reproduced directly before repair. The first/third were unrelated-but-required typed fake drift; incoming was an incomplete Session-03 guarded-save fake; batch-delete was a stale expectation after the necessary authority re-read. The first exact formatter named five authorized files and was resolved mechanically. The first analyzer exited 0 with two infos; both were resolved, and final analyzer output is issue-free.
- **Blocking issues remaining:** none in Executor scope. Independent QA is still mandatory before acceptance.

## Independent QA Review

- **Reviewed:** `2026-07-11 15:53 CEST`; final fresh independent QA retry with `materialization_retries=1`, `fix_passes=0`, inherited runtime, and no degraded local fallback.
- **Final QA verdict:** `blocking_findings`.
- **B1 — blocking / high — backward clock samples prematurely expire unexpired disappearing media.** The frozen contract says `effectiveNow = max(now, persistedHighWater)` and expires only at `effectiveNow >= expiresAt` (Expiry clock and the corresponding Done Criterion). In `lib/core/database/helpers/messages_db_helpers.dart:1151-1165`, the first update instead writes `expired` whenever `nowMs < private_media_clock_high_water_ms`; it has no predicate requiring that high-water to have reached `private_media_expires_at_ms`. Therefore, with high-water `1500`, expiry `5000`, and sampled time `1200`, the row expires even though the contracted effective time is `1500 < 5000`. The causal test encodes the same contradiction at `test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart:207-240` and again across guarded attachment writes at `:420-521`, so its green result does not prove the required behavior.
  - **Required disposition:** preserve the monotonic high-water on rollback and transition to `expired` only when the resulting effective high-water is at or beyond the immutable expiry. Replace the premature-expiry expectations with a RED that proves an unexpired rollback stays `available`, keeps its prior high-water, and expires exactly when a later effective time reaches the deadline. Keep guarded save/begin/local-ready/failure/commit parent qualification atomic under the corrected rule.
  - **Verification commands:** `flutter test test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart`; `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart`; and, because the shared qualifier governs attachment write authority, `flutter test test/features/conversation/application/download_media_use_case_test.dart`.
- **N findings:** none.
- **Evidence consistency:** all nine direct-test artifacts, four sentinel artifacts, curated `1to1`, host inventory, completeness, formatter, analyzer, diff, status, and scope artifacts are present under `/tmp/plan234-s03/`. Inspected tails confirm SQL `14/14`, curated `1to1` `1875/1875`, host discovery, completeness `1164/1164`, formatter `23 files / 0 changed`, analyzer `No issues found`, and clean diff-check outcomes. No required command is missing or reported as an accepted known failure. The sole material inconsistency is semantic: the passing SQL test asserts the behavior rejected by `B1`. No proof was rerun because current source plus the landed causal assertion establish the counterexample; rerunning it would only reproduce the already-recorded green-but-wrong expectation.
- **Scope and attribution:** `B1` is inside Session-03-owned SQL lifecycle authority and its direct causal test; it is not attributable to Plans 238/247/249 or the authorized unrelated baseline. The non-empty scope-guard output names the pre-existing accepted Session-01 database-version/migration registry and group files, consistent with the 15:30 aggregate snapshot. QA changed only this Session-03 plan. Production, tests, gates, breakdown/source closure, and Graphify remained read-only.
- **Other named seam disposition:** bounded source/test/log review did not support an additional `B` or `N` finding for guarded incoming attachment authority, batch-delete current-parent re-read, transfer-token/restart reclaim, secure-key compensation, canonical path/MIME/size integrity, recovery rotation/fairness, or remote-delete/replay convergence. Those passing proofs remain reusable only where the `B1` fix does not invalidate them.
- **Done-criteria disposition:** the required direct and named gate inventory is resolved and the scoped implementation is otherwise coherent, but the atomic monotonic-expiry criterion and its causal RED requirement are not met. Session 03 is not safe to accept until `B1` is fixed, the three affected direct proofs above pass, invalidated formatter/analyzer/diff evidence is refreshed, and a fresh independent QA pass records no blocking finding.

## Fix Pass 1 Handoff

- **Finding addressed:** `B1` from the first independent QA. `fix_passes=1`; no other QA finding existed.
- **RED:** `messages_db_helpers_private_media_lifecycle_test.dart` was changed first so an unexpired rollback (`now=1200`, high-water `1500`, expiry `2000/5000`) must remain `available`, retain high-water, and keep every guarded attachment mutation eligible. The exact suite failed at both intended assertions; `/tmp/plan234-s03/fix1-red-sql.log`.
- **Production correction:** removed the special rollback-expiry update from `dbAdvanceDirectPrivateMediaClockWithinTransaction`. One atomic `MAX(stored, now)` high-water update now feeds the existing `high_water >= expires_at` terminal predicate, so backward time neither lowers the clock nor expires before the immutable deadline.
- **Causal test convergence:** the SQL suite now expires at exact deadline and keeps external terminal emission causal by seeding effective high-water at the deadline. The restart test now consumes/cleans interrupted View Once at rollback time, preserves the unexpired disappearing row/artifact, then expires/cleans it when effective time reaches the deadline and proves the next pass is a no-op.
- **Files changed in fix pass:** `lib/core/database/helpers/messages_db_helpers.dart`; `test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart`; `test/features/conversation/integration/private_media_restart_replay_test.dart`; and this plan only.
- **Affected evidence:**
  - `flutter test test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart` — `passed`; `/tmp/plan234-s03/fix1-green-sql-final.log`.
  - `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart` — `passed`; `/tmp/plan234-s03/fix1-scheduler.log`.
  - `flutter test test/features/conversation/application/download_media_use_case_test.dart` — `passed`; `/tmp/plan234-s03/fix1-download.log`.
  - `flutter test test/features/conversation/integration/private_media_restart_replay_test.dart` — `passed`; `/tmp/plan234-s03/fix1-restart-green.log`.
  - `./scripts/run_test_gates.sh 1to1` — `passed`, 1875/1875; `/tmp/plan234-s03/fix1-1to1-gate-final.log`.
  - exact scoped formatter — `passed`, 23 files / 0 changed; `/tmp/plan234-s03/fix1-format-final.log`.
  - exact scoped analyzer — `passed`, `No issues found`; `/tmp/plan234-s03/fix1-analyze-final.log`.
  - `git diff --check` — `passed`; `/tmp/plan234-s03/fix1-diff-check-final.log`.
  - focused Graphify affected query — `passed`; `/tmp/plan234-s03/fix1-affected.log`. Exact current callers/qualifiers were verified by targeted source search.
- **Disposition:** ready for a fresh final independent QA pass. No blocking issue remains from Executor fix pass 1; no Graphify refresh has run yet.

## Final Independent QA Review

- **Reviewed:** `2026-07-11 16:07 CEST`; fresh final independent Reviewer after `fix_passes=1`, with inherited runtime and no degraded local fallback. Requested GPT-5.5/xhigh controls were unavailable and are neither a blocker nor acceptance evidence. No direct proof was rerun because the current files, artifact chronology, and recorded results are consistent; the expensive curated gate was not duplicated.
- **Final QA verdict:** `accepted`.
- **Blocking findings (`B...`):** none.
- **Non-blocking findings (`N...`):** none.
- **Prior `B1` disposition — resolved.** `lib/core/database/helpers/messages_db_helpers.dart:1146-1175` now advances `private_media_clock_high_water_ms` with `MAX(COALESCE(stored, 0), now)` and expires only on `high_water >= expires_at`; the removed rollback-specific terminal update can no longer expire an unexpired row. The standalone entry is transaction-wrapped at `:1209-1222`, while the shared qualifier at `:1182-1206`, guarded attachment helpers in `lib/core/database/helpers/media_attachments_db_helpers.dart:149-330`, and final commit at `messages_db_helpers.dart:1275-1333` pass the same transaction executor through parent advance/qualification and attachment mutation.
- **Causality verdict:** the proofs are not vacuous. `/tmp/plan234-s03/fix1-red-sql.log` fails only the intended real-SQL counterexamples: the unexpired rollback is wrongly `expired` and the guarded save is wrongly rejected. `test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart:207-255` then proves rollback keeps high-water `1500`, remains `available`, expires at the immutable `2000` deadline, and cannot reopen; `:432-564` drives all five guarded save/begin/local-ready/failure/commit operations against `now=1200`, stored high-water `1500`, and expiry `5000`, asserting both parent and attachment outcomes. `test/features/conversation/integration/private_media_restart_replay_test.dart:15-161` reopens a persisted database, consumes only interrupted View Once at rollback time, retains the unexpired disappearing row and artifact, expires/cleans it exactly at `2000`, and proves a subsequent recovery pass is a no-op.
- **Evidence verdict:** resolved. `/tmp/plan234-s03/fix1-green-sql-final.log` passes `14/14`; `fix1-scheduler.log` passes `11/11`; `fix1-download.log` passes `66/66`; `fix1-restart-green.log` passes `2/2`; and `fix1-1to1-gate-final.log` passes `1875/1875` after the causal restart correction. `fix1-format-final.log` reports 23 files and 0 changes, `fix1-analyze-final.log` reports `No issues found`, and the zero-byte `fix1-diff-check-final.log` records a successful `git diff --check`. `fix1-affected.log` is consistent with the exact current callers inspected in source; it is supporting impact evidence, not a substitute for the semantic review.
- **Invalidated-evidence disposition:** the first QA's green SQL result was invalidated by `B1`; the fix pass replaced it with causal RED/GREEN evidence. The post-fix SQL emission fixture failure and restart failure were both stale expectations, each reproduced and causally corrected before final reruns. B1's SQL, scheduler, download, restart, formatter, analyzer, and diff evidence is fresh, and the full curated gate re-covered the registered 1:1 surface. Initial host inventory and completeness evidence remain reusable because the fix pass changed no inventory, gate script, or gate-definition file.
- **Scope and attribution verdict:** accepted. The fix pass is confined to `messages_db_helpers.dart`, its direct SQL test, the restart test, and this Session-03 plan. Their modification times precede the final direct/gate artifacts. The current non-empty scope-guard output remains the authorized 15:30 Session-01/group baseline recorded in `/tmp/plan234-s03/exact-scope-guard-final.log`; no Session-04/05/06, Plans 238/247/249, schema/version/migration, group/announcement, Go/relay, device, breakdown/source-closure, gate-doc, or Graphify mutation is attributable to this fix or QA. Final QA changed only this plan.
- **Done-criteria verdict:** accepted. The monotonic atomic-expiry criterion, guarded attachment transaction authority, restart convergence, required causal regressions, affected direct proofs, curated gate, and refreshed static evidence are all resolved. The remaining Session-03 criteria retain the first QA's no-finding disposition and unchanged passing evidence. Session 03 is safe for the controller's single post-QA incremental Graphify refresh and final `## Execution Result`.

## Execution Result

- **Final verdict:** `accepted`.
- **Invocation topology:** isolated Executor; one stalled read-only QA materialization followed by a completed fresh initial QA; one local Executor fix pass; one fresh final QA. `materialization_retries=1`, `fix_passes=1`.
- **Independent QA used:** yes. Initial completed QA found blocking `B1`; final fresh QA accepted with no `B` or `N` findings.
- **Local sequential fallback used:** no. Degraded local QA was not authorized and was not used.
- **Requested runtime:** GPT-5.5/xhigh was requested, but spawn controls were unavailable. Inherited runtime was used and is neither a blocker nor acceptance evidence.
- **Files changed:** the authorized 15:30 materialized Session-03 implementation was preserved. This execution closed gaps in `messages_db_helpers.dart`, `download_media_use_case.dart`, the expiry scheduler/direct lifecycle repository/storage/delete formatting surface, both 1:1 gate arrays, and the gate-definition doc; updated the SQL/restart and required preservation test seams; and updated this plan. The single required incremental refresh updated architecture graph/overlay outputs. No schema/version/migration, group/announcement, Go/relay, Session-04/05/06, device, or Plans 238/247/249 work is attributable to this execution.
- **Tests added or updated:** the six already-materialized Session-03 causal suites were registered in both 1:1 inventories. SQL rollback/deadline, guarded attachment eligibility, and restart convergence assertions were causally corrected. Required incoming, round-trip, listener, and batch-delete test doubles/expectations were kept coherent with current typed authority.
- **Evidence ledger:** every command below ran from `/Users/I560101/Project-Sat/mknoon-2/flutter_app`. No known failure was accepted. Session 03 is host-only; no device/relay leg applies.

| Required command | Result | Classification / artifact |
|---|---|---|
| `git status --short` | exit 0 | `passed`; final snapshot `/tmp/plan234-s03/final-status-after-refresh.log` |
| `flutter test test/core/database/helpers/messages_db_helpers_private_media_lifecycle_test.dart` | exit 0, 14/14 | `passed`; `/tmp/plan234-s03/fix1-green-sql-final.log` |
| `flutter test test/features/conversation/application/consume_private_media_use_case_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/post-format-consume.log` |
| `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart` | exit 0, 11/11 | `passed`; `/tmp/plan234-s03/fix1-scheduler.log` |
| `flutter test test/features/conversation/integration/private_media_restart_replay_test.dart` | exit 0, 2/2 | `passed`; `/tmp/plan234-s03/fix1-restart-green.log` |
| `flutter test test/features/conversation/application/private_media_cleanup_race_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-cleanup.log` |
| `flutter test test/features/conversation/application/download_media_use_case_test.dart` | exit 0, 66/66 | `passed`; `/tmp/plan234-s03/fix1-download.log` |
| `flutter test test/core/media/media_storage_manager_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/post-format-storage.log` |
| `flutter test test/features/conversation/application/delete_message_use_case_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/post-format-delete.log` |
| `flutter test test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-recovery.log` |
| `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-roundtrip-rerun.log` |
| `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-incoming-rerun-2.log` |
| `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-composer.log` |
| `flutter test test/features/push/application/show_notification_use_case_test.dart test/features/push/application/push_decrypt_preview_test.dart` | exit 0 | `passed`; `/tmp/plan234-s03/exact-push.log` |
| `./scripts/run_test_gates.sh 1to1` | exit 0, 1875/1875 | `passed`; `/tmp/plan234-s03/fix1-1to1-gate-final.log` |
| `./scripts/run_host_test_gates.sh 1to1 --list` | exit 0 | `passed`; six new suites present; `/tmp/plan234-s03/exact-host-list.log` |
| `./scripts/run_test_gates.sh completeness-check` | exit 0, 1164/1164 | `passed`; `/tmp/plan234-s03/exact-completeness.log` |
| exact scoped `dart format --output=none --set-exit-if-changed ...` | exit 0, 23 files / 0 changed | `passed`; `/tmp/plan234-s03/fix1-format-final.log` |
| exact scoped `dart analyze ...` | exit 0, `No issues found` | `passed`; `/tmp/plan234-s03/fix1-analyze-final.log` |
| `git diff --check` | exit 0 | `passed`; post-refresh `/tmp/plan234-s03/final-diff-check-after-refresh.log` |
| scope guard command from `Acceptance Gates` | exit 0 | `passed` command; output remains only authorized pre-existing Session-01/group files; `/tmp/plan234-s03/final-scope-guard-after-refresh.log` |
| `python3 graphify-arch/tdd_context.py affected ... --budget 600` | exit 0 | `passed`; `/tmp/plan234-s03/fix1-affected.log`; exact callers verified in source |
| `./graphify-arch/refresh_arch_graph.sh --incremental` | exit 0 | `passed` exactly once post-QA; `/tmp/plan234-s03/final-graph-refresh.log` |

- **QA findings and dispositions:** `B1` identified premature expiry on an unexpired backward-clock sample. Fix pass 1 replaced the contradictory green assertion with a causal RED, removed the premature SQL branch, retained atomic guarded attachment qualification, corrected restart/deadline proof, and reran all invalidated evidence. Final QA accepted the disposition. No other QA finding was supported.
- **Blocking issues remaining:** none.
- **Non-blocking follow-ups deferred:** none.
- **Safety conclusion:** Session 03 is safe to consider implementation-complete. SQL lifecycle mutations remain conditional/transactional, high-water is monotonic, expiry occurs only at/after the immutable deadline, reveal/restart/cleanup/download/delete races are causally covered, all required inventories/gates/static guards pass, scope is preserved, and fresh independent QA accepted the final state.

## Closure Audit

- **Closure verdict:** `closed` for Session 03 only. The direct private-media lifecycle core is accepted; overall Plan 234 remains `implementation-in-progress` for Sessions 04-06.
- **What is closed:** transactional direct-parent lifecycle CAS; single-opener lease and monotonic first-frame/terminal callbacks; immutable-deadline expiry with persisted high-water; retryable exact-direct cleanup; guarded download, eviction, and delete races under the shared attachment lock; hidden-tombstone replay suppression; bounded shared cold-start/resume recovery; and foreground expiry scheduling/rescheduling.
- **Accepted evidence:** `B1` was resolved with a causal RED and corrected `MAX(stored, now)`/`high_water >= expires_at` transaction behavior. Final focused results include SQL 14/14, scheduler 11/11, download 66/66, restart 2/2, all remaining required direct and preservation commands, curated `1to1` 1,875/1,875, host inventory 78 with all six new suites, and completeness 1,164/1,164. Scoped formatter, analyzer, diff, and scope guards are green; final independent QA accepted after `fix_passes=1`; exactly one post-QA incremental Graphify refresh passed; no Session-03-owned source or test is newer than that refresh.
- **Residual-only items:** none. There is no Session-03 blocker, deferred fix, or follow-up roadmap.
- **Accepted differences:** this is a host-only, device/install-local lifecycle slice. It deliberately adds no schema/v101 migration, native Android/iOS protection, device proof, Go/libp2p/relay authority, account-wide consume receipt, or Session-04 action/library/egress/PiP enforcement. Sessions 04-06 own those distinct remaining Plan-234 surfaces and do not count as Session-03 residuals.
- **Reopen rule:** reopen Session 03 only for a real regression in its closed lifecycle scope, such as a causal failure or product defect in CAS/lease/expiry/cleanup/restart/download/delete/replay behavior, ordinary-media preservation, or required 1:1 registration. Later-session integration work or documentation drift alone must not reopen it.
- **Maintenance safety:** retain the nine focused lifecycle/race/recovery suites and four preservation commands named in `## Acceptance Gates`, the curated `1to1` gate, 1:1 host inventory, completeness-check, scoped formatter/analyzer, `git diff --check`, and the migration/cross-lane/Go/relay scope guard. These are the maintenance-time stop references for this closed slice.

## Prior Blocked Attempt (Resolved 2026-07-11 15:23 CEST)

- **Final verdict:** `blocked`
- **Invocation topology:** controller with one fresh Executor plus one bounded materialization-retry Executor.
- **Independent QA used:** not performed; the implementation never reached an attributable, evidence-complete handoff.
- **Local sequential fallback used:** no; it cannot solve concurrent external writes.
- **Files changed by this orchestration:** this Session-03 plan only. Neither Executor landed production, test, fixture, gate, or script changes.
- **Tests added or updated:** none attributable to this orchestration. Tests and owner files that appeared or changed during execution remain external shared-worktree materialization.
- **Evidence ledger:** compact Graphify preflight queries completed with `confidence=broad` and stale `lib/main.dart` topology; the pre-materialization focused lifecycle batch passed 40 tests but is stale after later file changes; a six-sample 30-second stability watch passed; the fresh retry's full snapshot then detected independent production-owner mutations before any Executor edit, classified `blocking_failure`.
- **QA findings and dispositions:** QA was correctly not started because the scoped patch/evidence was not stable or attributable.
- **Blocking issues remaining:** all remaining Session-03 implementation and exact acceptance gates listed in the current Executor Handoff, plus independent QA.
- **Non-blocking follow-ups deferred:** none.
- **Blocker class:** `patch_or_merge_failure`.
- **Exact blocker:** other live Codex sessions in this repository continued changing Session-03 tests and production owner files after two isolated Executor snapshots. Root is not authorized to terminate or overwrite those sessions, and continuing would risk lost or misattributed work.
- **Recommended next retry focus:** let the active Session-03 writer finish or explicitly stop it, then resume from a fresh full owner/test snapshot, re-read every newly materialized counterexample, rerun affected focused evidence, complete all named gates, and only then spawn independent QA.
- **Safety verdict:** Session 03 is unsafe to consider complete; no broad gate, Graphify refresh, or acceptance/closure claim was made.
- **Resolution:** the user explicitly authorized termination of every competing Codex session; the controller terminated them, verified only the current app-server remains, observed a stable final hash watch, and reopened this session for a fresh Executor pass.

## Post-Closure Proof Repair — 2026-07-12

- **Reopen evidence:** Plan-247 Session-04 aggregate acceptance repeatedly failed
  `229 download/eviction CAS private timeout late-write authority scrubs then releases cleanup`
  with `cleanupCompleted == 0`; the failure also reproduced once in the exact
  named test. This concrete lifecycle-proof regression satisfied the Session-03
  reopen rule without reopening any accepted product behavior.
- **Root cause:** the fixture passed `transferMaxTimeout: Duration.zero`, so the
  real transfer watchdog could complete `downloadMedia` before the fake finished
  its asynchronous write, durable hide, and retained-cleanup assertion. The same
  zero duration also scheduled the late scrub, allowing authority release before
  the fixture had established terminal cleanup authority.
- **Rejected candidate:** a bounded `100 x 5 ms` reconciliation poll passed local
  stress but independent counterexample review rejected it as probability-based
  rather than causal. It was replaced before QA. Honest correction accounting is
  `post_closure_fix_passes=2`; the historical Session-03 `fix_passes=1` above is
  unchanged.
- **Deterministic repair:** `downloadMedia` now accepts the optional test seam
  `latePrivateTransferScrubDelay`. Its default remains exactly
  `transferMaxTimeout ?? 5 minutes`, and every production caller omits it. The
  fixture no longer zeroes the watchdog; its own post-write `TimeoutException`
  is causal, while only the late scrub is accelerated to zero. The original
  single post-release reconciliation assertion is retained.
- **Final evidence:** exact causal test `10/10`; combined download and cleanup
  `83/83` (full download `68/68`); curated `1to1` `1,963/1,963`; curated groups
  `1,951/1,951` plus both Go sentinels; host inventory `88`; completeness
  `1,179/1,179`; formatter `2` files / `0` changes; scoped analyzer `No issues
  found`; `git diff --check` clean; Graphify `affected` reconciled the shared
  direct/group callers.
- **Independent QA:** `ACCEPTED` with no blocker. QA verified deterministic
  watchdog/scrub ordering, exact-path locked cleanup, source-compatible optional
  argument, and production-default equivalence.
- **Graphify:** exactly one additional post-QA incremental refresh completed:
  `48,201` nodes / `74,809` edges; TDD overlay `1,272` files / `12,419` named
  tests / `959` production targets.
- **Closure disposition:** Session 03 remains `accepted` and closed after this
  bounded proof repair. No product behavior, schema/version, migration,
  group/announcement semantics, Go/relay production, native/device, or later
  Plan-234 session scope changed. Plan-247 Session 04 must use a fresh immutable
  baseline and receives no fix-pass attribution from this upstream repair.
- **Separate Closure Reviewer:** `ACCEPTED` with no documentation blocker. The
  reviewer reconciled the two-file repair, all evidence/counts, honest dual
  fix-pass histories, QA, exactly-one additional refresh, closed Session-03
  status, and the mandatory fresh Plan-247 Session-04 baseline.
