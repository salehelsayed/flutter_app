# 111 — Test Inventory (Implemented 2026-06-12)

Every test created or contract-updated while implementing
`111-one-to-one-p0-silent-message-loss-tdd-plan.md`, grouped by plan step.
All were landed RED→GREEN on 121-improvements; final sweep: 2,775 Dart tests
green, `go-mknoon make test` green, `go-relay-server go test ./...` green.

Legend: **NEW** = written from scratch · **FLIP** = existing test whose
expectation was deliberately inverted to the new contract · **EXT** = existing
test extended in scope.

---

## Part A — transient decrypt never destroys an ACKed message

### A-1 · `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
1. **NEW** `returns decryptionFailed for Go-shaped INTERNAL_ERROR` — pins the
   cryptographic classification with a real Go error code.
2. **NEW** `returns decryptionDeferred when decrypt fails with BRIDGE_TIMEOUT`
   — transient classification; message NOT saved; `CHAT_MSG_RECEIVE_DECRYPT_DEFERRED`
   flow event asserted.
3. **FLIP** `returns decryptionDeferred when bridge decrypt throws` (was
   `…decryptionFailed…`) — a thrown bridge exception is transient.

### A-2 · `test/features/conversation/application/chat_message_listener_test.dart`
4. **NEW** `maps decryptionDeferred result to decryptionDeferred state` —
   guards the non-exhaustive if-chain (without a branch the new result silently
   falls through to `error`).
5. **NEW** `confirms direct nonce ok=false for decryptionDeferred`.
6. **NEW** `confirms direct nonce ok=false for decryptionFailed` — closes a
   pre-existing coverage gap (the false-confirm was untested).
   *(fake support: `_FakeDecryptBridge` gained a `requests` recorder)*

### A-3 · `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart` (NEW FILE)
Full matrix over `ChatMessageProcessState` → `RecoveredInboxChatDisposition`:
7. **NEW** `stored commits the staged entry`
8. **NEW** `missingMlKemSecret stays retryable with detail`
9. **NEW** `accountMigrationBlocked stays retryable`
10. **NEW** `error stays retryable with detail`
11. **NEW** `decryptionDeferred stays retryable (transient infra failure)`
12. **NEW** `decryptionFailed quarantines instead of rejecting` — **THE P0-A fix**
    (INV-1: the staged entry is the only remaining copy after custody transfer)
13. **NEW** `blockedSender rejects` — product-intent drop, documented content-safe
14. **NEW** `notChatMessage rejects` — pre-custody, no content to lose
15. **NEW** `unknownSender rejects` — mapper runs after the intro-recovery pre-step
16. **NEW** `duplicate rejects` — content already committed under the same id
17. **NEW** `editMissingOriginal rejects` — hidden placeholder persisted first
18. **NEW** `matrix covers every ChatMessageProcessState` — future-state guard

### A-4 · `test/core/database/helpers/inbox_staging_db_helpers_test.dart` (group `quarantine markers`)
19. **NEW** `markQuarantined sets status, increments attempt_count, records reason metadata`
20. **NEW** `getRecoverableEntries excludes quarantined entries`
21. **NEW** `countQuarantinedEntries returns quarantined total` — the minimal
    surfacing hook for the P1 quarantine-UI follow-up.
    *(fake support: `test/shared/fakes/in_memory_inbox_staging_repository.dart`
    gained `markQuarantined` + `countQuarantinedEntries`)*

### A-5 · `test/core/services/p2p_service_impl_test.dart` (group `durable inbox staging`)
22. **NEW** `quarantined disposition keeps entry, marks quarantined, does not delete`
    — first replay-path test ever for a keep-terminal outcome.
23. **NEW** `rejected disposition marks rejected` — first-ever `rejected` pin.
24. **NEW** `retryable past attempt cap transitions to quarantined` — seeded
    `attempt_count: 9`, two drains; second pass quarantines with
    `attempt_cap_exceeded`, entry never deleted.

### A-6 · `handle_incoming_chat_message_use_case_test.dart`
25. **NEW** `BRIDGE_TIMEOUT then successful decrypt on replay stores the message`
    — the user-story integration pin: one slow decrypt no longer loses the message.

### A-7 · `go-mknoon/bridge/bridge_test.go`
26. **FLIP** `TestDecryptMessage_WrongKey` — previously TOLERATED `ok=true`; now
    asserts `ok=false` AND `errorCode == "DECRYPT_FAILED"` (INTERNAL_ERROR
    reserved for panics).

---

## Part C — media death spiral

### C-1 · `go-relay-server/media_test.go`
27. **FLIP** `TestUploadDownloadAutoDelete` → `TestDownloadDoesNotDeleteBlob` —
    after a completed 1:1 download the blob remains on disk AND in the index.
28. **FLIP** `TestDownloadAfterAutoDeleteReturnsNotFound` → `TestRedownloadSucceeds`
    — **the death-spiral kill-shot**: a second download succeeds with identical bytes.
29. **NEW** `TestDeleteAfterDownloadRemovesBlob` — pins the full new lifecycle:
    download → explicit ack-delete → second download NOT FOUND.
30. **FLIP** `TestBackwardCompat` — 1:1 (no allowedPeers) uploads follow the
    ack-based lifecycle; explicit delete still removes.

### C-2 · `test/features/conversation/application/download_media_use_case_test.dart`
31. **NEW** `sends media:delete for the blob after successful commit` — ack fires
    after `updateLocalPath`, payload carries the blob id.
32. **NEW** `media:delete failure does not affect done status` — throw on delete;
    result stays `done`; `MEDIA_ACK_DELETE_FAILED` flow event asserted.
33. **NEW** `no media:delete on failed download`.
    *(fake support: `_FakeBridge` gained `deleteRequests`/`deleteResponse`/
    `throwOnDelete`, kept separate from `sendCallCount`/`lastRequest`;
    `_DelayedBridge` routes `media:delete` to the parent handler)*

### C-3 · `go-mknoon/node/media_test.go`
34. **NEW** `TestDownloadProgressEventsEmitted` — 1 MiB through
    `copyMediaDownloadToFile`: ≥2 ticks at the 256KiB cadence, monotonic
    receivedBytes, final tick == total.
35. **NEW** `TestSlowSteadyDownloadOutlivesWallClock` — chunks every 150 ms
    against a 400 ms idle budget; total duration exceeds the simulated wall
    clock yet succeeds; ≥2 progress ticks (each re-arms the stream deadline).
36. **EXT** `TestPL014MediaMetadataAndProgressEventsDoNotExposeSecrets` —
    deliberately extended with the `media:download_progress` event: exact key
    set `{id, receivedBytes, totalBytes, fromPeerId}` + no-secret-fragment scan.
    *(PL-013 partial-removal pins unchanged; its two
    `copyMediaDownloadToFile` calls updated to the new 5-arg signature)*

### C-4 · `test/core/bridge/go_bridge_client_test.dart`
37. **NEW** `routes media:download_progress to mediaDownloadProgressStream` —
    download events no longer dead-end in an empty switch case.

### C-4 · `test/core/bridge/p2p_bridge_client_test.dart`
38. **NEW** `callP2PMediaDownload honors injected stall budget when no progress arrives`
    — hanging bridge + 120 ms stall budget → `TimeoutException`.
39. **NEW** `callP2PMediaDownload survives past the stall budget while progress events arrive`
    — 500 ms transfer, 150 ms stall budget, 50 ms progress ticks → completes.
40. **NEW** `callP2PMediaDownload absolute ceiling fires even with steady progress`
    — last-resort `maxTimeout` still bounds a never-completing call.
    *(fake support: `_SlowBridge` added)*

### C-5 · `download_media_use_case_test.dart`
41. **NEW** `watchdog timeout preserves the .part file` — native write completes,
    Dart watchdog throws; row `failed` (retry offered), `.part` still on disk.
    *(fake support: `_TimeoutAfterWriteBridge` added)*
42. **NEW** `retry adopts complete .part without bridge call` — pre-placed
    size-matching `.part` is promoted (rename, not copy): zero `media:download`
    sends, `done` committed, relay ack still fired.
43. **NEW** `retry ignores incomplete .part and re-downloads` — size mismatch →
    normal download path (genuine-partial semantics preserved).
44. **FLIP** `PL-013 keeps the staged partial on failed download and retry succeeds`
    (was `…removes partial…`) — Dart side no longer destroys staged bytes on
    transient failure; the Go side still removes its own genuine partials.

### C-6 · `test/features/conversation/application/media_download_slow_transfer_simulator_test.dart` (NEW FILE)
45. **NEW** `slow steady transfer with progress completes; stalled transfer fails
    with typed stall code` — end-to-end policy in fast test time: moving transfer
    outlives a 150 ms stall budget; a stalled one fails with
    `MEDIA_TRANSFER_WATCHDOG_TIMEOUT {reason: stalled_no_progress}` and emits
    `MEDIA_DOWNLOAD_PART_PRESERVED`.

### C-7 · `go-mknoon/integration/media_test.go` (real-relay, `-tags integration`)
46. **FLIP** `TestRelayMediaUploadDownload` — second download must now succeed
    with identical bytes; explicit `MediaDelete` then makes a third download
    fail. (Passes only against the C-1 relay — deployed 2026-06-12.)

---

## Part B — post-restore stale ML-KEM key

### B-1 · `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`
47. **FLIP** `updates existing contact ML-KEM key when signed payload carries a
    different key` (replaced the old `alreadyContact: contact already has a key,
    no overwrite` pin) — result `contactKeyUpdated`, row rotated,
    `mlKemKeyUpdatedTs` set to the signed payload `ts`.
48. **NEW** `ignores key change when payload ts is not newer than last key update`
    — anti-rollback: a replayed OLD signed contact_request cannot restore a stale key.
49. **NEW** `keeps existing key when payload key is identical` — no-op pin,
    `mlKemKeyUpdatedTs` untouched.

### B-3 · `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`
50. **NEW** `sends keyExchangeRetry to contacts in re-announce marker even when
    their key is non-null` — coexists with the long-standing
    `contacts with existing ML-KEM key are skipped` no-marker pin.
51. **NEW** `removes peer from marker only after successful send; partial failure
    retains remainder` — first send fails via `_FailOnNthBridge`; its peerId stays.
52. **NEW** `marker drained empty clears the secure-storage entry`.

### B-2/B-4/B-5/B-6 · `test/features/conversation/application/post_restore_stale_key_recovery_test.dart` (NEW FILE)
Consolidated (deviation from the plan's per-file placement, same coverage):
53. **NEW** (B-2) `restore records re-announce pending marker for all active contacts`
    — blocked contacts excluded. *Note: the plan's separate
    `silent recovery records re-announce pending marker` test was not written;
    `recoverIdentityFromSecureStore` delegates to `restoreIdentityFromMnemonic`
    with the store+repo threaded, so the path is covered transitively — a direct
    pin would still be a worthwhile micro-addition.*
54. **NEW** (B-4) `saveIdentity pushes previous differing ML-KEM secret onto the ring`
55. **NEW** (B-4) `ring is capped at 3, newest first` — 5 saves → `[s4, s3, s2]`
56. **NEW** (B-4) `saveIdentity with identical secret does not grow the ring`
57. **NEW** (B-5) `falls back to ring secret when primary decrypt fails
    cryptographically` — keyed fake bridge proves attempt order
    `[new-secret, old-secret]`, stored, decryptCallCount 2.
58. **NEW** (B-5) `does not try ring on transient (BRIDGE_TIMEOUT) failure` —
    stays `decryptionDeferred`, exactly 1 decrypt call (ring not burned).
59. **NEW** (B-5) `listener passes ring to use case` — `getOwnMlKemSecretKeyRing`
    wiring pin through `ChatMessageListener`.
60. **NEW** (B-6) `message encrypted to pre-restore key decrypts via ring after
    silent recovery` — the same-device story end-to-end: save(old) →
    regenerate(new) → ring holds old → old-key v2 message stored, not quarantined.

### B-1 ripple · `test/features/contact_request/application/contact_request_listener_test.dart`
61. **FLIP** `emits when an existing contact key rotates via a newer signed payload`
    (was `does not emit when existing contact already has ML-KEM key`).
62. **NEW** `does not emit when the key change is a stale replay (anti-rollback)`
    — contact's `mlKemKeyUpdatedTs` in the future → no emit, key unchanged.

### B-4 ripple · `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- Two cache tests (`refreshes the cache after a successful save`, `replaces a
  cached null after saveIdentity`) updated from absolute `readCount == 0` to
  delta assertions: `saveIdentity` now performs one legitimate secure-storage
  read (previous-secret check for the ring); `loadIdentity` afterwards must add
  zero reads. Adaptations, not new pins.

---

## Totals

- **44 brand-new tests**, **8 deliberate contract flips**, **1 extended
  secret-leak pin**, across **3 new test files** and **10 modified ones**
  (Dart + Go node + relay + Go integration).
- Supporting fakes added/extended: `_FakeDecryptBridge.requests`,
  `InMemoryInboxStagingRepository.markQuarantined/countQuarantinedEntries`,
  `_FakeBridge` delete recording, `_DelayedBridge` delete routing,
  `_SlowBridge`, `_TimeoutAfterWriteBridge`, `_KeyedDecryptBridge`,
  `_TimeoutDecryptBridge`.
- Not covered by unit tests (per plan): device-evidence gates 3–4 (real
  Pixel→iPhone >150 MB video; same-device silent-recovery + new-device
  rotation) and the quarantine UI (P1 follow-up; `countQuarantinedEntries`
  is the tested hook).
