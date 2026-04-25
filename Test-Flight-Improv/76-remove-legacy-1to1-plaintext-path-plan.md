# 76 - Remove Legacy 1:1 Plaintext Path Plan

## Final Verdict

Session classification: implementation-ready.

No new skill is needed. Use this plan with `implementation-execution-qa-orchestrator` for implementation, then use `implementation-closure-audit-orchestrator` after the gates pass. The safe scope is outbound-only: stop current app code from sending or retrying legacy v1 plaintext 1:1 chat/control envelopes, while keeping inbound v1 parsing for old stored messages and mixed-version peers.

The plan is safe if the implementation keeps encrypted offline inbox fallback intact. The goal is not to remove inbox fallback; it is to make every 1:1 chat/deletion envelope that reaches direct transport, local transport, retry transport, or relay inbox be v2 encrypted.

## Final Plan

### 1. Real Scope

Remove the legacy outbound v1 plaintext path for ordinary 1:1 user chat messages and 1:1 delete-for-everyone control messages:

- `MessagePayload` outbound send paths must require v2 encryption before transport or relay inbox storage.
- `MessageDeletionPayload` outbound delete-for-everyone paths must require v2 encryption before transport or relay inbox storage.
- Retry paths must not replay a persisted legacy v1 `wireEnvelope` to relay inbox or direct transport.
- `sendVoiceMessage` must fail before media upload when the recipient ML-KEM key is missing, so the fail-closed chat send behavior does not create an orphaned voice upload.
- Existing encrypted v2 direct send, local send, inbox fallback, retry, media, voice, edit, quote, and delete behavior must remain functional.

Keep these areas intentionally unchanged:

- Inbound v1 parsing for `chat_message` and `message_deletion`, so old inbox rows and mixed-version inbound traffic remain readable.
- Contact request / introduction bootstrap behavior, where v1 can still be part of key exchange.
- Group message work, relay server behavior, and server deployment.

### 2. Closure Bar

The work is closed only when all of these are true:

- No current outbound 1:1 chat or delete path can call `sendMessage`, `sendMessageWithReply`, `sendLocalMessage`, or `storeInInbox` with a `version: "1"` `chat_message` or `message_deletion` envelope.
- Missing `Bridge` or missing recipient ML-KEM public key returns `SendChatMessageResult.encryptionRequired` before any plaintext envelope is built, sent, stored in relay inbox, or persisted as a new outbound `wireEnvelope`.
- Voice send with a missing recipient ML-KEM public key returns failure before `media:upload`, direct send, local send, inbox storage, or message persistence.
- Encrypted v2 text, edit, quote, media, voice, delete, offline inbox fallback, and retry flows still pass their existing tests.
- Legacy inbound v1 chat and deletion payloads still parse and deduplicate correctly.
- Retry of existing pre-upgrade v1 `wireEnvelope` rows does not leak the stored plaintext to relay; if a recipient key is available, retry re-encrypts through the normal send path.

### 3. Source of Truth

Source priority for implementation decisions:

1. Current production code and tests.
2. `scripts/run_test_gates.sh`, because it is the executable gate definition.
3. `Test-Flight-Improv/test-gate-definitions.md` for named gate intent.
4. `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` for the 1:1 reliability closure contract.
5. `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md` and `Test-Flight-Improv/74-privacy-preserving-notification-previews.md` for privacy boundary intent, with current code overriding stale doc details.

If a doc and current code disagree, treat the code/tests as the working truth and update docs only in the closure audit.

### 4. Session Classification

Implementation-ready, single session.

This is not a broad architecture redesign. The affected behavior is narrow enough for one implementation session if tests are written first:

- Send path encryption requirement.
- Delete path encryption requirement.
- Retry guard for legacy persisted v1 envelopes.
- Test updates for existing success cases to use a bridge plus recipient key. Use `PassthroughCryptoBridge` only for round-trip behavior tests; use a `FakeBridge` response with opaque ciphertext for plaintext-leak assertions.

### 5. Exact Problem Statement

The relay can still receive readable 1:1 message content when the client falls back to legacy v1 plaintext envelopes.

Current evidence:

- `sendChatMessage` uses `MessagePayload.buildEncryptedEnvelope(...)` only when both `bridge` and `recipientMlKemPublicKey` are present. Otherwise it falls back to `payload.toJson()`.
- `MessagePayload.toJson()` produces a v1 envelope with a plaintext `payload` containing message text, sender peer id, sender username, timestamp, action/edit metadata, quote metadata, and media metadata.
- `deleteMessageForEveryone` has the same pattern: encrypt when bridge/key exist, otherwise fall back to `MessageDeletionPayload.toJson()`.
- `retryFailedMessages` and `retryUnackedMessages` can store an existing `msg.wireEnvelope` directly in relay inbox. If that persisted envelope is a legacy v1 chat/deletion envelope, retry can leak old plaintext even after the send path is fixed.

Expected behavior:

- New outbound 1:1 chat/delete transport is v2 encrypted or blocked with `encryptionRequired`.
- Old inbound v1 payloads remain readable.
- Existing pre-upgrade v1 `wireEnvelope` rows are never replayed to relay.

### 6. Files And Repos To Inspect Next

Production files:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/domain/models/message_deletion_payload.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- Optional new utility: `lib/features/conversation/application/outbound_envelope_policy.dart`

Test files:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`

Gate files:

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Relay repo context already collected:

- `go-relay-server/inbox.go` accepts and stores the raw 1:1 inbox message string. The client must therefore avoid sending plaintext to relay; the relay cannot repair this client-side leak.

### 7. Existing Tests Covering This Area

Existing coverage is useful but currently encodes some legacy success assumptions:

- `send_chat_message_use_case_test.dart` covers direct send, reply send, local send, inbox fallback, message status persistence, retry-oriented `wireEnvelope` handling, media, edit, quote, and many failure cases.
- Several send tests currently call `sendChatMessage` without a bridge/key and expect success. Those tests must be converted to encrypted success setup or split into explicit `encryptionRequired` tests.
- `delete_message_use_case_test.dart` covers delete-for-everyone behavior and must be checked for plaintext fallback expectations.
- `retry_failed_messages_use_case_test.dart` and `retry_unacked_messages_use_case_test.dart` cover relay inbox retry behavior and must gain legacy-v1 replay protection tests.
- `handle_incoming_chat_message_use_case_test.dart` and `handle_incoming_message_deletion_use_case_test.dart` cover inbound parsing. These tests should remain green and protect the inbound compatibility carveout.
- `send_group_invite_use_case_test.dart` provides the nearest precedent: missing recipient ML-KEM key returns `encryptionRequired` and does not send.

### 8. Regression Tests To Add First

Add or update tests before production changes:

1. `sendChatMessage` with no bridge returns `SendChatMessageResult.encryptionRequired`, does not call direct send, local send, inbox storage, or persist a new plaintext `wireEnvelope`.
2. `sendChatMessage` with bridge but no recipient ML-KEM key returns `encryptionRequired` with no transport side effects.
3. Encrypted text send with bridge/key succeeds and the sent JSON has `version: "2"`, an `encrypted` object, and no top-level plaintext `payload`. For leak assertions, use a fake encrypt response whose ciphertext is opaque so the test can also assert the serialized envelope does not contain message text or sender username.
4. Encrypted offline inbox fallback stores only a v2 encrypted envelope. With an opaque fake ciphertext, the stored string must not contain message text or sender username.
5. Edit send with missing key returns `encryptionRequired`; edit send with key still sends encrypted v2.
6. Delete-for-everyone with missing bridge/key returns `encryptionRequired` and does not send or store a v1 deletion tombstone.
7. Delete-for-everyone with bridge/key still sends encrypted v2 and preserves local delete side effects.
8. `retryFailedMessages` with a persisted v1 `chat_message` or `message_deletion` `wireEnvelope` does not call `storeInInbox` with that envelope. Use a fake P2P service that records every `storeInInbox` payload and fails the test if the legacy sentinel appears. If contact key material exists, it should re-enter the full encrypted send/delete retry path.
9. `retryUnackedMessages` with a persisted v1 `chat_message` or `message_deletion` `wireEnvelope` does not call `storeInInbox` with that envelope. Use a fake P2P service that records every `storeInInbox` payload and fails the test if the legacy sentinel appears. It should mark the row failed or otherwise stop the unsafe replay loop without clearing data needed for a later encrypted retry.
10. `sendVoiceMessage` with a missing recipient ML-KEM key returns `SendVoiceMessageResult.sendFailed` before upload. Assert the fake bridge did not receive `media:upload`, P2P send/local/inbox call counts stay zero, and `messageRepo.saved` stays empty.
11. Mixed-version behavior remains explicit: outbound sends are v2-only, while inbound v1 chat and deletion tests remain green. Keep the existing `still accepts V1 plaintext messages for backward compatibility` chat test, and add a deletion equivalent if no clearly named v1 deletion compatibility test exists.

Concrete `send_chat_message_use_case_test.dart` conversion targets:

- Convert these named tests from bridge/key-less success to encrypted success setup: `sanitizes outgoing comment text while preserving safe markers`, `rejects text that becomes empty after sanitization unless attachments exist` for the attachment success branch, `returns success and persists message on successful send`, `removes stale upload_pending placeholder rows before saving final attachments`, `sends GIF-only media with image/gif preserved in the wire envelope`, `sends correct JSON envelope via P2P`, `uses provided messageId and timestamp when passed`, `editChatMessage preserves the original row contract`, `logs CHAT_OUT with delivered status and text preview`, and `emits CHAT_MSG_SEND_TIMING with elapsed outcome and attachment flag`.
- Convert the transport/status tests that still expect a message row after attempted send: `returns sendFailed and persists with failed status when send returns false`, `returns success and persists delivered status when inbox store succeeds`, `returns sendFailed when P2P throws exception`, `returns peerNotFound when discover returns null`, `returns dialFailed when dial returns false`, `flaky discover surfaces peerNotFound when direct discovery loses`, `success with ack sets status to delivered`, `success without ack keeps sent when inbox handoff fails`, `success with empty reply keeps sent when inbox handoff fails`, `unacked direct send hands off to inbox immediately when available`, and the local/relay/reuse path tests in `Phase 3 - relay probe recovery`, `Phase 1 - interactive send path`, `Section 4 - direct-first send with early wireEnvelope persistence`, `Section 4 - inbox call-site regression guard`, and `Section 4 - inbox fallback edge cases`.
- After converting the named cases, run a sweep over this file: any `sendChatMessage(` or `editChatMessage(` test that expects a non-validation send result must either pass `bridge:` plus `recipientMlKemPublicKey:` or intentionally assert `encryptionRequired`.

Cross-suite stale plaintext expectation audit:

```bash
rg -n "sendChatMessage\\(|editChatMessage\\(|sendVoiceMessage\\(" test lib
```

Every result from that command must be classified before implementation is complete:

- Direct `sendChatMessage` / `editChatMessage` success tests must pass `bridge:` plus `recipientMlKemPublicKey:` or be rewritten to assert `SendChatMessageResult.encryptionRequired`.
- Wrapper tests, including voice/share/feed/retry wrappers, must either provide recipient key material to the wrapper or assert the wrapper fails closed before upload/send/inbox.
- Shared test helpers must be updated so integration tests do not silently keep using the old bridge-less plaintext default.
- Production wrappers must pass through recipient ML-KEM key material or explicitly fail closed; do not rely on the removed `sendChatMessage` plaintext fallback.

The audit must include at least these files from the current search output:

- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/core/resilience/c2_ack_drop_test.dart`
- `test/core/resilience/c3_half_open_test.dart`
- `test/shared/fakes/test_user.dart`
- `test/shared/fakes/intro_test_user.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/send_chat_message_no_bg_task_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_no_bg_task_test.dart`
- `test/performance/benchmark_voice_send_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/integration/relay_down_degradation_integration_test.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/share/application/share_batch_delivery_coordinator.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Opaque-ciphertext fake bridge template for no-plaintext assertions:

```dart
const testRecipientMlKemPublicKey = 'recipient-mlkem-public-key';

FakeBridge opaqueMessageEncryptBridge({
  String ciphertext = 'opaque-chat-ciphertext',
}) {
  return FakeBridge(
    initialResponses: {
      'message.encrypt': {
        'ok': true,
        'kem': 'opaque-kem',
        'ciphertext': ciphertext,
        'nonce': 'opaque-nonce',
      },
    },
  );
}
```

Use this fake for envelope leak tests. Do not use `PassthroughCryptoBridge` for no-plaintext assertions because it intentionally copies plaintext into the ciphertext field.

New regression test names to add:

- `send_chat_message_use_case_test.dart`: `returns encryptionRequired when bridge is missing`, `returns encryptionRequired when recipient ML-KEM key is missing`, `sends v2 encrypted envelope without plaintext payload`, `stores v2 encrypted inbox fallback without plaintext`, and `editChatMessage returns encryptionRequired when recipient ML-KEM key is missing`.
- `delete_message_use_case_test.dart`: `deleteMessageForEveryone returns encryptionRequired when recipient ML-KEM key is missing` and `deleteMessageForEveryone sends encrypted v2 deletion when key is present`.
- `retry_failed_messages_use_case_test.dart`: `does not replay persisted v1 chat wireEnvelope to inbox after restart`, `does not replay persisted v1 deletion wireEnvelope to inbox after restart`, and `still stores encrypted v2 wireEnvelope to inbox`.
- `retry_unacked_messages_use_case_test.dart`: `does not replay persisted v1 chat wireEnvelope when coming online`, `does not replay persisted v1 deletion wireEnvelope when coming online`, and `still stores encrypted v2 unacked wireEnvelope to inbox`.
- `send_voice_message_use_case_test.dart`: `returns sendFailed before upload when recipient ML-KEM key is missing`.
- `handle_incoming_message_deletion_use_case_test.dart`: `still accepts V1 plaintext deletions for backward compatibility` if existing v1 deletion coverage remains only implicit through other deletion tests.

### 9. Step-By-Step Implementation Plan

1. Add a small pure helper for outbound envelope classification, likely `outbound_envelope_policy.dart`.
   - Input: serialized JSON envelope string.
   - Output: whether it is an unsafe legacy outbound envelope.
   - Unsafe means `type` is `chat_message` or `message_deletion` and `version` is absent or `"1"`.
   - Non-JSON, unrelated message types, and v2 encrypted envelopes must be treated as not unsafe by this helper.

2. Add unit tests for the helper.
   - Cover v1 chat, v1 deletion, v2 encrypted chat, v2 encrypted deletion, contact request, unrelated type, malformed JSON, and empty string.

3. Update `send_chat_message_use_case_test.dart`.
   - Convert intended success tests to pass a bridge and a recipient ML-KEM key.
   - Add the missing bridge/key `encryptionRequired` tests.
   - Add no-plaintext assertions using an opaque fake encrypt response, not `PassthroughCryptoBridge`, because the passthrough helper intentionally mirrors plaintext into the ciphertext field.

4. Run the cross-suite stale plaintext expectation audit.
   - Use `rg -n "sendChatMessage\\(|editChatMessage\\(|sendVoiceMessage\\(" test lib`.
   - Convert or classify every hit before production changes are considered complete.
   - Update shared fake users/helpers first when many integration tests inherit their send behavior.
   - Do not accept a green targeted unit suite while another suite still expects bridge-less plaintext success.

5. Change `sendChatMessage`.
   - Replace the `payload.toJson()` outbound fallback with an early `encryptionRequired` return when bridge/key are unavailable.
   - Keep current encrypted v2 path and failure handling.
   - Ensure no new outgoing message row is persisted with a plaintext `wireEnvelope`.
   - Keep UI behavior compatible with existing `conversation_wired.dart` handling for `encryptionRequired`.

6. Update `delete_message_use_case_test.dart`.
   - Add missing bridge/key regression coverage.
   - Ensure encrypted delete success remains covered.

7. Change `deleteMessageForEveryone`.
   - Replace `MessageDeletionPayload.toJson()` outbound fallback with `encryptionRequired`.
   - Keep encrypted v2 behavior unchanged when bridge/key exist.
   - Keep inbound deletion fallback untouched.

8. Update `retry_failed_messages_use_case_test.dart`.
   - Add legacy v1 `wireEnvelope` replay tests for chat and deletion.
   - Add encrypted v2 retry assertions for inbox fallback.

9. Change `retryFailedMessages`.
   - Exact guard anchor: in `_retryFailedMessageCandidate`, inside the existing `if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty)` block, compute `final unsafeLegacyEnvelope = isUnsafeLegacyOutboundEnvelope(msg.wireEnvelope!);` before the `try { final stored = await p2pService.storeInInbox(...) }` shortcut.
   - Keep the existing `msg.transport == 'inbox'` crash-recovery branch as a no-send path; it may clear an already-inbox row because it does not replay the envelope.
   - Gate the direct `p2pService.storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` call with `if (!unsafeLegacyEnvelope)`.
   - If `unsafeLegacyEnvelope` is true and `msg.transport != 'inbox'`, skip only the wire-envelope inbox shortcut. Do not mark it delivered and do not clear the `wireEnvelope` in that branch.
   - Prefer re-encrypting through the existing full retry path when enough message data and recipient key material are available.
   - If re-encryption cannot happen, leave the message failed and log only ids/status, never message text.

10. Update `retry_unacked_messages_use_case_test.dart`.
   - Add legacy v1 replay protection.
   - Add v2 envelope still-stores-to-inbox regression coverage.

11. Change `retryUnackedMessages`.
    - Exact guard anchor: after the existing null/empty `wireEnvelope` skip and after the `msg.transport == 'inbox'` crash-recovery branch, compute `final unsafeLegacyEnvelope = isUnsafeLegacyOutboundEnvelope(msg.wireEnvelope!);` immediately before the current `try { final stored = await p2pService.storeInInbox(...) }` block.
    - If `unsafeLegacyEnvelope` is true, do not enter the `storeInInbox` try block.
    - Mark the message failed, or use the existing failure path, so the app does not repeatedly attempt unsafe replay.
    - Preserve enough local state for `retryFailedMessages` to perform a future encrypted full retry.
    - If `unsafeLegacyEnvelope` is false, keep the existing v2 `storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` behavior unchanged.

12. Update `send_voice_message_use_case_test.dart`.
    - Add `returns sendFailed before upload when recipient ML-KEM key is missing`.
    - Assert `bridge.commandLog` does not contain `media:upload`.
    - Assert `p2pService.sendCallCount`, `p2pService.localSendCallCount`, `p2pService.storeInInboxCallCount`, and `messageRepo.saved.length` stay zero.

13. Change `sendVoiceMessage`.
    - Add a narrow pre-upload guard for missing or empty `recipientMlKemPublicKey`.
    - Return `SendVoiceMessageResult.sendFailed` using the existing enum; do not add a new user-facing voice result unless existing UI tests require it.
    - Emit failure timing without message text and without attempting upload.
    - Keep generic non-voice media upload preflight out of scope.

14. Re-run the cross-suite audit and then run direct tests, then named gates.

### 10. Risks And Edge Cases

- Some existing tests and possibly old runtime paths assume 1:1 send can succeed without recipient ML-KEM key. The implementation must distinguish ordinary chat from bootstrap/contact-request flows.
- Pre-upgrade failed/unacked rows can contain v1 plaintext `wireEnvelope`. Retry must not replay those rows to relay.
- Voice sends currently upload before `sendChatMessage` can return `encryptionRequired`. This plan includes only the narrow voice missing-key preflight; generic media attachment upload preflight remains a follow-up.
- Offline inbox fallback is part of the 1:1 reliability contract. Do not remove it; only ensure the stored envelope is encrypted v2.
- Mixed app versions may still send inbound v1. Inbound v1 compatibility must remain until a separate sunset/migration plan exists.
- Logs and telemetry added in this work must not include message text, sender display names, or serialized v1 envelopes.

### 11. Exact Tests And Gates To Run

Direct tests:

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart
```

Gate tests:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

The 1:1 gate currently includes:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/quote_reply_thread_test.dart`

### 12. Known-Failure Interpretation

- A test that expected ordinary 1:1 chat/delete success without bridge/key should be updated unless it is explicitly covering bootstrap/contact-request behavior.
- A test failure showing v1 inbound parse broke is a regression; inbound compatibility is in scope to preserve.
- A test failure showing offline inbox fallback no longer stores encrypted v2 is a regression; inbox fallback must remain.
- A test failure from unrelated dirty generated Xcode/Index/ModuleCache files is not part of this plan.
- If a gate was already red before implementation, capture the failing test names before and after. Do not treat unrelated existing red as closure, but do not ignore any new failure in the files touched by this plan.

### 13. Done Criteria

The implementation is done when:

- All new regression tests fail before production changes and pass after them.
- Direct tests listed above pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh baseline` passes or any unrelated pre-existing failure is documented with evidence.
- `./scripts/run_test_gates.sh completeness-check` passes if test docs or gate-covered tests are changed.
- The final `rg -n "sendChatMessage\\(|editChatMessage\\(|sendVoiceMessage\\(" test lib` audit has no unclassified bridge-less success expectation in tests, shared fakes, or production wrappers.
- Manual code inspection finds no remaining outbound `payload.toJson()` fallback for `MessagePayload` or `MessageDeletionPayload`.
- Manual code inspection finds no retry shortcut that can send/store an unsafe legacy v1 `chat_message` or `message_deletion` envelope.
- Manual code inspection confirms both retry use cases call the shared outbound envelope policy helper at the exact `msg.wireEnvelope` shortcut gates before any direct `storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` call.
- Manual code inspection confirms `sendVoiceMessage` checks recipient ML-KEM key before `uploadMedia(...)`.

### 14. Scope Guard

Do not do these in this session:

- Do not delete `MessagePayload.toJson()`, `MessagePayload.fromJson()`, `MessageDeletionPayload.toJson()`, or inbound v1 parsing.
- Do not change relay server code or EC2 deployment.
- Do not change contact request, introduction, or bootstrap message behavior.
- Do not redesign key exchange, ML-KEM storage, or contact eligibility.
- Do not remove offline inbox fallback.
- Do not migrate or purge old database rows unless tests prove retry safety cannot be achieved without it.
- Do not change group message encryption or group inbox behavior.

### 15. Accepted Differences / Intentionally Out Of Scope

- Inbound legacy v1 chat/delete payloads remain accepted.
- Contact request and introduction flows may still carry bootstrap-readable fields where needed for key exchange.
- Old local database rows may still contain legacy v1 `wireEnvelope`; the implementation only prevents replaying them to relay.
- Generic media attachment key preflight outside `sendVoiceMessage` is deferred.
- Relay can still see routing metadata and ciphertext length/timing. This plan removes message plaintext from relay-visible 1:1 chat/delete envelopes, not all metadata.

### 16. Dependency Impact

- This plan depends on the existing on-device encryption path and recipient ML-KEM key availability.
- It increases the importance of contact/key-exchange reliability because ordinary 1:1 sends now fail closed when key material is missing.
- Future work can sunset inbound v1 only after a separate migration/version-cutoff plan.
- Closure docs should be updated after implementation to state that the 1:1 reliability contract uses encrypted v2 wire envelopes for durable retry and offline inbox fallback.

## Structural Blockers Remaining

No structural blocker remains for implementation.

The main implementation risk is test churn: many existing send-path tests currently exercise success without bridge/key. That is not a design blocker; those tests should be converted to encrypted success setup and paired with explicit `encryptionRequired` regression tests.

## Incremental Details Intentionally Deferred

- Exact UI copy for encryption-required failures, because `conversation_wired.dart` already has a snackbar for this result.
- Generic pre-upload ML-KEM key checks outside `sendVoiceMessage`.
- A database migration to rewrite or purge old v1 `wireEnvelope` rows.
- Removing inbound v1 parsers.
- Relay-side validation that rejects plaintext payloads.

## Accepted Differences Intentionally Left Unchanged

- Inbound old-format message/deletion parsing remains.
- Bootstrap/contact-request v1 behavior remains.
- Group message behavior remains.
- Relay deployment remains unchanged.
- Local developer logs are not audited in this session except for any new logs added by this work.

## Exact Docs/Files Used As Evidence

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/domain/models/message_deletion_payload.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/contacts/application/send_contact_request_use_case.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md`
- `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`
- `go-relay-server/inbox.go`

## Why This Plan Is Safe

The plan removes only outbound/retry plaintext transport for ordinary 1:1 chat/delete envelopes. It does not remove receive compatibility, offline inbox fallback, encrypted retry, media/voice support, or bootstrap flows. The tests force the critical distinction: v2 encrypted envelopes must continue to move through all delivery paths, while v1 plaintext envelopes must never be newly sent or replayed to relay.

Reviewer pass result: sufficient. The only accepted residual risk is existing local data that may still contain old v1 envelopes. That risk is controlled by the retry replay guard in this plan and can be eliminated later with a separate migration/sunset plan.
