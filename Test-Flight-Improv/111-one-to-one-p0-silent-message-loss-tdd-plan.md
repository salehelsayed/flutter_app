# 111 — 1:1 P0 Silent Message Loss (TDD Plan)

Date: 2026-06-11 · Branch: 121-improvements · Status: PLANNED (no code changed)

Source: 5-agent graph-first 1:1 reliability audit (2026-06-11) + 3-agent test-seam recon (same day).
Scope: ONLY the three P0 "messages destroyed silently while the sender sees delivered" bugs:

- **P0-A** — Transient decrypt error (incl. `BRIDGE_TIMEOUT`) terminally rejects an already-ACKed staged message (`bridge.dart:653-668` → `handle_incoming_chat_message_use_case.dart:105-124` → `main.dart:1651-1656` `markRejected`).
- **P0-B** — Post-restore stale ML-KEM key: contacts encrypt to the old public key forever; every v2 message lands on the same terminal-reject path; nothing re-announces the new key (`retry_incomplete_key_exchanges_use_case.dart:48-51` only targets `mlKemPublicKey == null`).
- **P0-C** — Large-media death spiral: Dart 5-min wall-clock timeout (`p2p_bridge_client.dart:722-724`) kills a still-healthy transfer, deletes the `.part`, and the relay one-shot auto-delete (`go-relay-server/media.go:559-565`) destroys the only copy; all retries get "not found".

**Governing invariant (INV-1): once the receiving side has caused custody transfer (relay copy ACK-deleted, or direct `message:confirm ok:true` sent), no code path may destroy that message's content. Allowed terminal states: committed, or quarantined-with-metadata. `rejected` after custody transfer is forbidden.**

Parts are independently landable. Recommended order: **A → C → B** (A is smallest and also de-fangs B's loss path by converting destruction into quarantine; C is self-contained across Dart/Go/relay; B builds on A's quarantine semantics).

---

## Part A — Transient decrypt failure must never destroy an ACKed message

### A.1 Design decision

Split decrypt failure into **transient** vs **cryptographic** at the use-case layer, and make the cryptographic terminal state a **quarantine, not a rejection**:

1. **Classification (Dart-side only for the core fix).** In `handleIncomingChatMessage` (`lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:105-124`):
   - transient = `errorCode == 'BRIDGE_TIMEOUT'`, any thrown bridge exception (current catch at :117-124), and bridge-not-ready → new result `HandleChatMessageResult.decryptionDeferred`.
   - cryptographic = any Go-returned failure (`INVALID_INPUT`, `INTERNAL_ERROR`) → stays `decryptionFailed`.
   - The Go errorCode channel today is only three-valued (`INVALID_INPUT` | `INTERNAL_ERROR` | Dart-synthesized `BRIDGE_TIMEOUT`); wrong-key surfaces as `INTERNAL_ERROR` / "message authentication failed" (`go-mknoon/crypto/decrypt.go:24`, `bridge.go` DecryptMessage L181). An optional Go-side refinement (distinct `DECRYPT_FAILED` code) is Step A-7.
2. **New listener state.** `ChatMessageProcessState.decryptionDeferred` in `chat_message_listener.dart:26-37`. Both existing switches on this enum are exhaustive (compiler-enforced): `_confirmationValueForState` (:242-257, deferred → confirm `ok:false`) and the replay-disposition mapping. ⚠️ The `HandleChatMessageResult` consumer at `chat_message_listener.dart:380-443` is an **if-chain, NOT exhaustive** — a new enum value silently falls through to `error` unless a branch is added (the chain already swallows `unauthorized`/`ignoredEdit` that way).
3. **Extract the inline main.dart closure** (`main.dart:1583-1676`) state→disposition mapping into a testable top-level function `mapChatReplayOutcomeToDisposition(...)` in a new file `lib/features/conversation/application/recovered_inbox_chat_disposition.dart`. Precedent: `resolveUnknownInboxSender` was extracted from this exact closure (`lib/features/introduction/application/resolve_unknown_inbox_sender_use_case.dart`, called at main.dart:1591).
4. **New disposition + staging status `quarantined`.** Extend `RecoveredInboxChatDisposition` (`p2p_service_impl.dart:25`) with `quarantined`; `_applyRecoveredInboxOutcome` (:982-1030) maps it to a new `repo.markQuarantined`. Mapping changes:
   - `decryptionDeferred` → `retryable` (replays on every drain, like `missingMlKemSecret` at main.dart:1621-1626).
   - `decryptionFailed` → `quarantined` (entry KEPT, excluded from replay, reason metadata recorded) — replaces today's `rejected` at main.dart:1651-1656.
   - No schema migration needed: `inbox_staging_entries` already has `status`, `attempt_count`, `last_attempted_at`, `reject_reason_code/detail` (migration 045, `045_inbox_staging_entries.dart:14-29`); `getRecoverableEntries` already filters `status IN ('pending','retryable')` (`inbox_staging_db_helpers.dart:5,50`) so `quarantined` is excluded for free.
5. **Attempt cap on retryable.** `attempt_count` is written but never read today. Cap deferred retries: when marking retryable would push `attempt_count` past `maxInboxReplayAttempts = 10`, mark `quarantined` instead — prevents a permanently-broken message from looping forever, without ever destroying it.
6. **User-visible surfacing of quarantine is OUT OF SCOPE here** (P1 follow-up): this plan guarantees non-destruction + telemetry + a count query, not UI.

### A.2 Red-green steps

#### Step A-1 — RED: errorCode classification in the use case
File: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` (template: 'returns decryptionFailed when bridge decrypt reports failure' at :818-855; fake = in-file `FakeDecryptBridge.decryptResponse`, :257-303).
- `'returns decryptionDeferred when decrypt fails with BRIDGE_TIMEOUT'` — `decryptResponse = {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'}` → expect new result, message NOT saved.
- `'returns decryptionDeferred when bridge decrypt throws'` — use `ThrowingDecryptBridge` (:305-315); flips the existing throw-test expectation at :857-884.
- `'returns decryptionFailed for Go-shaped INTERNAL_ERROR'` — pins crypto classification with a REAL Go code. Also fix fixture drift: existing tests use fictional `'DECRYPT_FAILED'` (:824) that Go never emits — align fixtures to `INTERNAL_ERROR` (keep one `DECRYPT_FAILED` case if Step A-7 lands).
GREEN: add enum value + errorCode discrimination at use case :105-124. Keep `decryptionFailed` for Go-returned failures.

#### Step A-2 — RED: listener state + confirm semantics
File: `test/features/conversation/application/chat_message_listener_test.dart` (fake at :307-323; confirm tests at :706-809).
- `'maps decryptionDeferred result to decryptionDeferred state'` (guards the non-exhaustive if-chain at chat_message_listener.dart:380-443 — without an explicit branch the new result falls through to `error`).
- `'confirms direct nonce ok=false for decryptionDeferred'`.
- `'confirms direct nonce ok=false for decryptionFailed'` — coverage gap pin (today untested even though :242-257 returns false).
GREEN: add `ChatMessageProcessState.decryptionDeferred`, if-chain branch, `_confirmationValueForState` case (compiler forces this one).

#### Step A-3 — RED: extracted disposition mapper (the bug's exact line)
File (new): `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`.
- Full matrix test over `ChatMessageProcessState` → disposition, pinning: `stored→committed`, `missingMlKemSecret/accountMigrationBlocked/error/decryptionDeferred→retryable`, **`decryptionFailed→quarantined`** (THE fix), `blockedSender/notChatMessage/unknownSender/duplicate/editMissingOriginal→rejected` (these are pre-custody or content-safe rejections — document why each is safe in test comments).
- Exhaustive `switch` in the implementation so future states are compiler-forced.
GREEN: create `lib/features/conversation/application/recovered_inbox_chat_disposition.dart`; rewrite the main.dart closure body (:1614-1675) to delegate to it (closure keeps only the unknown-sender intro-recovery pre-step at :1588-1612).

#### Step A-4 — RED: quarantine semantics at DB + repo layer
Files: `test/core/database/helpers/inbox_staging_db_helpers_test.dart` (templates: markRetryable :117, markRejected :140) and `test/shared/fakes/in_memory_inbox_staging_repository.dart` (extend the shared fake in the same step — `implements`-based fakes break on any interface addition, see Caveats).
- `'markQuarantined sets status, increments attempt_count, records reason metadata'`.
- `'getRecoverableEntries excludes quarantined entries'`.
- `'countQuarantinedEntries returns quarantined total'` (the minimal surfacing hook for the P1 UI follow-up).
GREEN: `dbMarkInboxStagingEntryQuarantined` + count helper in `inbox_staging_db_helpers.dart` (mirror :167-178/:215-226), repo method in `InboxStagingRepository` + impl (`inbox_staging_repository_impl.dart`).

#### Step A-5 — RED: service-level disposition application
File: `test/core/services/p2p_service_impl_test.dart`, `group('durable inbox staging')` (:570+; closure injection pattern at :579; `_FakeBridge.whenCommand` :49-60).
- `'quarantined disposition keeps entry, marks quarantined, does not delete'` — first replay-path test ever for a keep-terminal outcome.
- `'rejected disposition marks rejected'` — first-ever `rejected` pin (today zero tests cover it).
- `'retryable past attempt cap transitions to quarantined'` — entry with `attempt_count = 9` replayed twice → second pass quarantines (cap enforcement lives in `_applyRecoveredInboxOutcome` so ALL retryable producers are capped).
GREEN: extend disposition enum + `_applyRecoveredInboxOutcome` (p2p_service_impl.dart:982-1030) with quarantine branch + cap check; emit `INBOX_STAGING_QUARANTINED` flow event with reason + attempt count.

#### Step A-6 — RED: end-to-end transient-then-recover regression
File: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` or a small new `decrypt_transient_recovery_test.dart`.
- `'BRIDGE_TIMEOUT then successful decrypt on replay stores the message'` — FakeBridge `responseSequences['message.decrypt']` = [timeout-shaped failure, success]; first `processIncomingMessage` → deferred; second → stored. This is the user-story test: one slow decrypt no longer loses the message.
GREEN: nothing new if A-1..A-5 are correct (this is the integration pin).

#### Step A-7 — OPTIONAL GREEN+RED (Go): distinct `DECRYPT_FAILED` code
Files: `go-mknoon/bridge/bridge.go` (DecryptMessage, L181 region), `go-mknoon/bridge/bridge_test.go`.
- RED: fix `TestDecryptMessage_WrongKey` (:339-377) — today it TOLERATES `ok=true`; assert `ok=false` AND `errorCode == 'DECRYPT_FAILED'`. Keep `INTERNAL_ERROR` for panics only.
- GREEN: return `DECRYPT_FAILED` from the `mcrypto.DecryptMessage` error branch. Dart classification from A-1 already treats any Go-returned code as cryptographic, so this is observability, not behavior. Requires gomobile rebuild (`make all` + `pod install`) — see Caveats.

#### Step A-8 — REFACTOR
- Delete the dead decoy `lib/core/services/chat_message_listener.dart` (stub with TODOs, zero importers — confirmed in audit).
- `flutter test test/features/conversation test/core/services test/core/database` + `cd go-mknoon && make test` green.

### A.3 Files
Create: `lib/features/conversation/application/recovered_inbox_chat_disposition.dart`, `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`.
Modify: `handle_incoming_chat_message_use_case.dart`, `chat_message_listener.dart` (conversation/application one), `lib/main.dart` (:1583-1676 closure), `p2p_service_impl.dart`, `inbox_staging_db_helpers.dart`, `inbox_staging_repository(_impl).dart`, shared fake, 4 test files. Optional: `go-mknoon/bridge/bridge.go` + test.

---

## Part B — Post-restore stale ML-KEM key

### B.1 Design decisions

Two independent halves. With Part A landed, stale-key messages are **quarantined instead of destroyed** — Part B closes the window and (same-device) recovers content.

**B-(a) Proactive re-announcement — the only remedy for new-device restore.** Reuse the existing signed `contact_request` envelope with `ContactRequestSendIntent.keyExchangeRetry` (`send_contact_request_use_case.dart:37-47`) — it already carries the `mlkem` field inside the Ed25519-signed payload (:99-110) and is already routed/verified end-to-end. No new envelope type.
1. **Receiver gate relax**: `handle_incoming_message_use_case.dart:318-336` currently updates an existing contact's key only when `existingContact.mlKemPublicKey == null` (:325). Change to: update when the verified payload's key **differs**, with anti-rollback — accept only if the signed payload `ts` is strictly newer than the stored contact's last key-update timestamp (track via a reused column; see B-1 RED). The existing `contactKeyUpdated` result + `contactKeyUpdatedStream` broadcast (`contact_request_listener.dart:238-255`) already propagate the update.
2. **Sender trigger**: restore fires nothing today. Add a one-shot **re-announce pending marker** in secure storage (`mlkem_reannounce_pending` = JSON list of contact peerIds, written by `restoreIdentityFromMnemonic` and `recoverIdentityFromSecureStore` on keygen success). Extend `retryIncompleteKeyExchanges` eligibility (:47-50): `mlKemPublicKey == null` **OR peerId ∈ pending marker**; remove each peerId from the marker only after its send succeeds (partial failure keeps the rest). Existing triggers (app resume Step 4, online-transition retrier with 5s debounce + coordinator cooldown) then drain the marker with no new scheduling machinery.

**B-(b) Decrypt fallback ring — same-device recovery.** Keep prior secret key(s) so old-key traffic stays decryptable:
1. **Write point**: `IdentityRepositoryImpl.saveIdentity` (`identity_repository_impl.dart:133-137`) overwrites `identity_ml_kem_secret_key` unconditionally. Before overwriting with a DIFFERENT secret, push the old one onto `identity_ml_kem_secret_key_ring` (JSON list in secure storage, capped at 3, newest first). Highest-value case: `recoverIdentityFromSecureStore` (`recover_identity_from_secure_store_use_case.dart:42-47`) — the old secret is provably present there today and currently destroyed.
2. **Read seam**: `handleIncomingChatMessage` gains optional `List<String> fallbackMlKemSecretKeys` (used at :96-124: try primary, then ring entries in order). `ChatMessageListener` resolves the ring next to `getOwnMlKemSecretKey` (:358-360) via a new injected `getOwnMlKemSecretKeyRing`.
3. Scope guard: 1:1 chat path only. Group decrypt and the push-isolate mirrored secret (`identity_repository_impl.dart:167-185`) do NOT get the ring in this plan (Caveat 5.4). New-device mnemonic restore can never decrypt old traffic (secret never on device) — B-(a) + Part A quarantine are the full remedy there; state this in the doc the user sees.

### B.2 Red-green steps

#### Step B-1 — RED: receiver accepts a changed key from a verified contact_request
File: `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`.
- `'updates existing contact ML-KEM key when signed payload carries a different key'` → result `contactKeyUpdated`, contact row updated.
- `'ignores key change when payload ts is not newer than last key update'` (anti-rollback).
- `'keeps existing key when payload key is identical'` (no-op pin).
GREEN: relax the null-gate at :325 to differs+newer-ts; persist the accepted ts (reuse an existing contact column if available, else add migration 0XX `contacts.ml_kem_key_updated_ts` — decide at implementation after checking the Contact model; if a migration is needed it is a 2-line ALTER following the migration-folder pattern).

#### Step B-2 — RED: restore writes the re-announce marker
Files: `test/features/identity/application/restore_identity_use_case_test.dart` (stubs `callMlKemKeygen` as an injected function — no bridge needed) and `recover_identity_from_secure_store_use_case_test.dart`.
- `'restore records re-announce pending marker for all active contacts'`.
- `'silent recovery records re-announce pending marker'`.
GREEN: write the marker (via `SecureKeyStore`, `FakeSecureKeyStore` in tests) in both restore paths after keygen+save succeed. Keep the marker write OUT of `IdentityRepositoryImpl` (repos shouldn't know about announcement policy).

#### Step B-3 — RED: retry use case drains the marker
File: `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart` (existing fakes: `FakeContactRepository`, `FakeIdentityRepository`, `_FailOnNthBridge`, `FakeP2PService`).
- `'sends keyExchangeRetry to contacts in re-announce marker even when their key is non-null'` — coexists with the existing `'contacts with existing ML-KEM key are skipped'` (:227), which stays valid for the no-marker case.
- `'removes peer from marker only after successful send; partial failure retains remainder'`.
- `'marker drained empty clears the secure-storage entry'`.
GREEN: extend eligibility + marker bookkeeping in `retry_incomplete_key_exchanges_use_case.dart` (new `SecureKeyStore` param — thread through `KeyExchangeRetrier` construction in main.dart; check QRScannerWired/OrbitWired DI chain per project memory).

#### Step B-4 — RED: secret-key ring write
File: `test/features/identity/domain/repositories/` (extend identity repo tests; `FakeSecureKeyStore`).
- `'saveIdentity pushes previous differing ML-KEM secret onto the ring'`.
- `'ring is capped at 3, newest first'`.
- `'saveIdentity with identical secret does not grow the ring'`.
GREEN: ring write in `identity_repository_impl.dart:133-137` region; new secure-storage key `identity_ml_kem_secret_key_ring`; expose `loadMlKemSecretKeyRing()` on the repository (⚠️ breaks `implements`-based `FakeIdentityRepository` — update it in the same step).

#### Step B-5 — RED: decrypt fallback through the ring
Files: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` + `chat_message_listener_test.dart`.
- `'falls back to ring secret when primary decrypt fails cryptographically'` — `FakeBridge.responseSequences['message.decrypt']` = [INTERNAL_ERROR-failure, success]; assert stored + `decryptCallCount == 2`.
- `'does not try ring on transient (BRIDGE_TIMEOUT) failure'` — transient must stay `decryptionDeferred` (Part A) without burning ring attempts.
- Listener: `'passes ring to use case'` wiring pin.
GREEN: `fallbackMlKemSecretKeys` param + loop in the use case; `getOwnMlKemSecretKeyRing` injection in the listener + main.dart wiring (chat listener site only).

#### Step B-6 — RED: end-to-end same-device story
File (new): `test/features/conversation/application/post_restore_stale_key_recovery_test.dart`.
- `'message encrypted to pre-restore key decrypts via ring after silent recovery'` — uses `PassthroughCryptoBridge` (`test/core/bridge/fake_bridge.dart:324-369`) or sequenced responses; simulates: old identity saved → recovery regenerates → ring holds old secret → incoming old-key v2 message → stored, not quarantined.
GREEN: integration pin only.

#### Step B-7 — REFACTOR
- Flow events: `KEY_REANNOUNCE_MARKED`, `KEY_REANNOUNCE_SENT`, `CONTACT_KEY_ROTATED`, `MLKEM_RING_FALLBACK_USED`.
- Full suites: `flutter test test/features/contact_request test/features/identity test/features/conversation`.

### B.3 Files
Create: `test/.../post_restore_stale_key_recovery_test.dart`; possibly migration `0XX_contacts_key_updated_ts.dart`.
Modify: `handle_incoming_message_use_case.dart` (contact_request), `restore_identity_use_case.dart`, `recover_identity_from_secure_store_use_case.dart`, `retry_incomplete_key_exchanges_use_case.dart`, `identity_repository_impl.dart` (+ repo interface), `handle_incoming_chat_message_use_case.dart`, `chat_message_listener.dart`, `main.dart` (DI), `FakeIdentityRepository`/`FakeContactRepository`, 6 test files.

---

## Part C — Media death spiral (large 1:1 video)

### C.1 Design decision

Three coordinated changes; the relay change is the one that removes PERMANENCE, so it lands first.

1. **C-(a) Acknowledgement-based relay deletion.** Remove the 1:1 auto-delete at `go-relay-server/media.go:559-565`. Receiver issues the EXISTING `media:delete` after durable commit. Every hop already exists with zero production callers: `callP2PMediaDelete` (`p2p_bridge_client.dart:759-786`) → `'media:delete'` (`go_bridge_client.dart:124`) → `GoBridge.swift:129`/`GoBridge.kt:105` → `bridge.go MediaDelete:1492` → `node/media.go:503` → relay `handleMediaDelete` (`media.go:568-597`, already authorizes `meta.To == remotePeer`). The existing 7-day TTL sweep (`media.go:21-22, 90-112`) is the backstop for receivers that never ack (old clients) — bounded further by the per-peer caps. **Commit point for the ack**: after `verifyCommittedLocalPath` passes at `download_media_use_case.dart:1437-1450`, fire-and-forget (ack failure must not affect `done` status).
2. **C-(b) Stall-based timeouts replace wall clocks.** Three clocks exist today: Dart `.timeout(5min)` (download :722-724, upload :684-686), Go `MediaTimeout = 5min` total stream deadline (`node/config.go:34`, applied `node/media.go:206,253`), Go `MediaIdleTimeout = 10s` stall reader (`config.go:35`, `media.go:56-88`). Target: progress-aware watchdog in Dart + rolling deadline in Go; Go stall detection becomes the real failure authority.
   - Go: emit `media:download_progress` from `copyMediaDownloadToFile` (`media.go:290-309`), mirroring the upload reader pattern (`media.go:92-142`); make the stream deadline rolling — re-arm `setStreamDeadline` on each progress tick so a slow-but-moving transfer never dies on wall clock.
   - Dart: `callP2PMediaDownload/Upload` get injectable `stallTimeout`/`maxTimeout` params (template: the `httpTimeout`/`transferBytesPerSecondFloor` injection in `account_migration_local_transfer_runtime.dart:193-245`); replace the fixed `.timeout(5min)` with a watchdog reset by matching progress events (EventChannel events arrive concurrently with a pending MethodChannel call — verified). Generous absolute ceiling stays as a last resort (e.g. payload-scaled: `size / 64KiB-per-s floor`, min 5 min).
3. **C-(c) Completed bytes are never destroyed.**
   - On TRANSIENT failure (watchdog/timeout/exception), keep the `.part` — `deleteFailedDownloadArtifacts` (`download_media_use_case.dart:544,584-589`, called :1058,:1467) deletes only on explicit corrupt/invalid outcomes.
   - On retry, **adopt a complete `.part`**: if `'$absolutePath.part'` exists and its size equals `attachment.size`, promote (rename + commit) without calling the bridge — extends `adoptCanonicalFileIfAvailable` (:679-707) which today checks only the canonical path. Go-side truncation (`os.Create`, `node/media.go:291`) then never sees a complete `.part`, so the Go behavior pinned by `TestPL013...` (genuine-partial removal, `media_test.go:464-501`) stays unchanged. True byte-range resume needs relay capabilities that don't exist — out of scope.

### C.2 Red-green steps

#### Step C-1 — RED (relay Go): blob survives download until acked
File: `go-relay-server/media_test.go` (mocknet harness `setupTestEnv` :68-112; helpers `sendMediaReq`/`recvMediaResp` :22-44).
- Rewrite `TestUploadDownloadAutoDelete` (:336-391) → `TestDownloadDoesNotDeleteBlob`: after a completed 1:1 download, blob still on disk + in index.
- Rewrite `TestDownloadAfterAutoDeleteReturnsNotFound` (:736-775) → `TestRedownloadSucceeds`: second download of the same blob succeeds (THE death-spiral kill-shot).
- `TestDeleteAfterDownloadRemovesBlob`: download → `action:"delete"` (existing `TestExplicitDelete` :695-732 stays as-is) → second download NOT FOUND. Pins the new lifecycle.
- Update `TestBackwardCompat` (:961-1002) to the new contract; confirm `TestGroupMediaNoAutoDelete` (:829-877) unaffected; TTL sweep test still reaps old blobs.
GREEN: delete the `if !isGroupMode { media.remove(req.ID) }` block (media.go:559-565). Run: `cd go-relay-server && go test ./...`.

#### Step C-2 — RED (Dart): receiver acks after durable commit
File: `test/features/conversation/application/download_media_use_case_test.dart` (in-file `_FakeBridge` :52-135 — extend to record `media:delete` cmds).
- `'sends media:delete for the blob after successful commit'` — assert fired after `updateLocalPath` with the attachment's blob id.
- `'media:delete failure does not affect done status'` — fake returns `ok:false`/throws for delete; download result still `done`, flow event `MEDIA_ACK_DELETE_FAILED` emitted.
- `'no media:delete on failed download'`.
GREEN: fire-and-forget `callP2PMediaDelete` after :1450 in `download_media_use_case.dart` (also after the adoption commit at :711-714). LAN-received media never uploaded a relay blob — guard on the relay-download path only.

#### Step C-3 — RED (Go node): download progress + rolling deadline
File: `go-mknoon/node/media_test.go` (seams: `stallingReader` :308-328, `slowSteadyReader` :331-359, `newIdleTimeoutReader` tests :377-449).
- `TestDownloadProgressEventsEmitted` — drive `copyMediaDownloadToFile`'s reader; assert `media:download_progress` payload key set EXACTLY `{id, receivedBytes, totalBytes, fromPeerId}` (mirror the secret-leak pin `TestPL014...` :134-223 — note that test asserts an exact key set for upload and will need its scope extended deliberately).
- `TestSlowSteadyDownloadOutlivesWallClock` — slowSteadyReader transfer whose total duration exceeds `MediaTimeout` succeeds because the deadline rolls on progress.
- Existing `TestIdleTimeoutReader_StalledDownloadFails` (:449) keeps stall authority pinned.
GREEN: progress emission in `copyMediaDownloadToFile` (media.go:290-309) on the upload reader's 256KiB/250ms cadence; rolling `setStreamDeadline` re-arm on each tick (media.go:253 region). Run: `cd go-mknoon && make test`.

#### Step C-4 — RED (Dart bridge): progress event plumbing + injectable timeouts
Files: `test/core/bridge/go_bridge_client_test.dart` / `p2p_bridge_client_test.dart`.
- `'routes media:download_progress to mediaDownloadProgressStream'` — 3-line pattern mirror of `media:upload_progress` (`go_bridge_client.dart:658-660`, `bridge.dart:80-96`); today download events dead-end in empty `break` cases (:662-675).
- `'callP2PMediaDownload honors injected stall budget'` — with a short injected watchdog and NO progress events, throws timeout; with periodic progress events past the budget, completes. (Make the watchdog injectable; default behavior preserved.)
GREEN: new broadcast stream + switch case in `go_bridge_client.dart`; watchdog replacing `.timeout(5min)` in `callP2PMediaDownload` (:722-724) and `callP2PMediaUpload` (:684-686), parameters threaded from `downloadMedia`/`uploadMedia` with payload-scaled defaults.

#### Step C-5 — RED (Dart): transient failures keep the `.part`; retry adopts a complete `.part`
File: `test/features/conversation/application/download_media_use_case_test.dart` (templates: `_FailOncePartialDownloadBridge` :158-182 and the PL-013 test at :769).
- `'watchdog timeout preserves the .part file'` — flips today's delete-on-timeout; row `failed`, `.part` still on disk.
- `'retry adopts complete .part without bridge call'` — pre-place `.part` with size == `attachment.size`; retry commits `done`; `_FakeBridge` records ZERO `media:download` sends; `media:delete` ack still fired.
- `'retry ignores incomplete .part and re-downloads'` — size mismatch → normal download path (PL-013 behavior preserved for genuine partials).
GREEN: classification in the catch/failure paths of `download_media_use_case.dart` (:1058, :1464-1468) — only corrupt/invalid outcomes call `deleteFailedDownloadArtifacts`; `.part` adoption added beside `adoptCanonicalFileIfAvailable` (:679-707).

#### Step C-6 — RED: slow-transfer simulator (regression harness)
File (new): `test/features/conversation/application/media_download_slow_transfer_simulator_test.dart` (template: `account_migration_local_transfer_runtime_test.dart:663-772` — injectable short timeouts + delay-injecting fake + typed failure codes + `debugSetFlowEventSink` assertions).
- `'slow steady transfer with progress completes; stalled transfer fails with typed stall code'` — `_FakeBridge.beforeDownloadResponse` delay + injected progress ticks vs none; asserts the full new policy end-to-end in fast test time.
GREEN: integration pin only.

#### Step C-7 — REFACTOR + Go integration
- `go test -tags integration ./integration/...` (external relay; auto-skips when unreachable): update `TestRelayMediaUploadDownload` (:70-77 asserts the OLD second-download-fails contract → now succeeds-until-deleted).
- Rebuild chain after Go changes: `cd go-mknoon && make all && cd ../ios && pod install` (gomobile + Pods; per project memory `flutter run` alone does NOT rebuild Go).
- `flutter test test/features/conversation test/core/bridge` green.

### C.3 Files
Create: `test/.../media_download_slow_transfer_simulator_test.dart`.
Modify: `go-relay-server/media.go` (+ `media_test.go`), `go-mknoon/node/media.go` (+ `media_test.go`, possibly `config.go`), `go-mknoon/integration/media_test.go`, `lib/core/bridge/p2p_bridge_client.dart`, `lib/core/bridge/go_bridge_client.dart`, `lib/core/bridge/bridge.dart` (stream surface — ⚠️ adding abstract members breaks `implements` fakes; prefer a concrete broadcast-stream field with default, see Caveats), `lib/features/conversation/application/download_media_use_case.dart`, `upload_media_use_case.dart` (timeout params), 3-4 test files.

---

## Deliberately out of scope (tracked elsewhere / follow-ups)

- Quarantine UI ("N messages couldn't be delivered securely") — P1 follow-up; this plan delivers non-destruction, telemetry, and a count API only.
- All P1/P2 audit findings (suppressed live-direct notifications, LAN ack-before-commit, relay inbox eviction, unencrypted 1:1 blobs, video thumbnail/mime rendering bugs, voice bugs) — separate plans.
- Sender re-serve of media (`servedByPhone` hardcoded false), relay byte-range resume, relay eviction telemetry.
- Group decrypt and push-isolate adoption of the ML-KEM ring; ring transfer in account-move (move copies the single secret verbatim today).
- Re-decrypt of already-quarantined entries after a ring/key change (synergy step; needs a quarantine sweep trigger).

## Evidence gates (per project closure-bar convention)

1. All new/updated unit suites green: `flutter test` (conversation, contact_request, identity, core/services, core/database, core/bridge), `cd go-mknoon && make test`, `cd go-relay-server && go test ./...`.
2. Go integration with a real relay: `go test -tags integration ./integration/...` including the updated redownload contract.
3. **Device evidence (required before claiming P0-C closed)**: real Pixel→iPhone 1:1 send of a >150 MB video on field Wi-Fi (past the old 5-min wall at ~0.4 MB/s); verify receiver commit, relay blob deleted only after ack, and a mid-transfer app-kill + retry adopting the `.part`.
4. **Device evidence (P0-B)**: same-device silent-recovery scenario (delete DB identity row, relaunch) then receive an old-key message → decrypts via ring; new-device restore → contacts receive keyExchangeRetry and rotate (verify `CONTACT_KEY_ROTATED` on the peer).

## Verified caveats

### 5.1 `implements`-based fakes break on ANY interface addition
Known project failure mode. Touched interfaces: `InboxStagingRepository` (A-4), `IdentityRepository` (B-4), possibly `Bridge` (C-4 stream). For `Bridge`, prefer a concrete `StreamController`-backed field on the abstract class (the existing `mediaUploadProgressStream` at `bridge.dart:80-96` is already concrete — mirror it) so `FakeBridge`/`_FakeBridge` fleets don't break. For repos, update `test/shared/fakes/` + per-feature fakes in the same step as the interface change.

### 5.2 The `HandleChatMessageResult` consumer is NOT compiler-enforced
The if-chain at `chat_message_listener.dart:380-443` silently routes unknown results to `error` (already swallows `unauthorized`/`ignoredEdit`). Step A-2's mapping test is the only guard. Consider converting the chain to an exhaustive switch in the A-8 refactor.

### 5.3 Go rebuild friction
Any go-mknoon change requires `make all` + `pod install` before device/simulator runs; Android needs Go < 1.25 or the patched wlynxg/anet. The relay change (C-1) is a separate DEPLOY — coordinate: new app + old relay keeps working only because old relay auto-deletes (degraded but not worse than today); old app + new relay relies on the 7-day TTL + per-peer caps for cleanup. Sequence relay deploy AFTER app rollout reaches receivers that ack, or accept the bounded storage growth window.

### 5.4 Ring does not cover group or push-preview decrypt
The push isolate reads a MIRRORED single secret (`identity_repository_impl.dart:167-185`); group identity callbacks in main.dart (8 injection sites) keep the single-key getter. Old-key GROUP traffic after silent recovery still fails decrypt (lands in group's own handling, not this plan's quarantine). Documented, not fixed here.

### 5.5 Anti-rollback ts source needs an implementation-time decision
B-1 assumes a per-contact "last key update ts". If no reusable column exists on `contacts`, a tiny migration is required (the plan allows it); without ts tracking, a replayed OLD signed contact_request could roll a contact back to a stale key — do not ship B-(a) without one of the two.

### 5.6 Pre-landing line-number re-check
All file:line references were verified 2026-06-11 against the UNCOMMITTED working tree on 121-improvements (which contains the move-scale and voice-wake-lock work). Re-verify anchors before each session; the recon agent IDs in project memory can be re-run if the tree shifts materially.
