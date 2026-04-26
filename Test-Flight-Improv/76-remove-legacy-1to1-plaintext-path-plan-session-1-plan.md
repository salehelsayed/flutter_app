# 76 Session 1 - Remove Outbound and Retry Legacy 1:1 Plaintext Envelopes

## Final verdict

Session classification: implementation-ready.

This session is safe to execute now. Current code still has the exact source
doc seams: ordinary 1:1 chat and delete can fall back to v1 plaintext
serialization, retry can replay persisted v1 `wireEnvelope` strings to relay
inbox, and voice upload can occur before the missing-key failure. The session
must close those outbound/retry paths while preserving inbound v1 parsing and
encrypted v2 offline inbox behavior.

## Final plan

### 1. real scope

Change only ordinary outbound 1:1 chat/delete/voice/retry behavior:

- require bridge plus recipient ML-KEM key before building outbound chat/edit
  envelopes
- require bridge plus recipient ML-KEM key before building delete-for-everyone
  envelopes
- add one pure outbound envelope policy helper to classify legacy v1 chat and
  deletion envelopes as unsafe for outbound replay
- use that helper in failed and unacked retry shortcuts before any direct
  `storeInInbox(msg.contactPeerId, msg.wireEnvelope!)` call
- fail `sendVoiceMessage` before media upload when recipient ML-KEM key is
  missing
- update focused tests and stale bridge-less expectations needed to keep direct
  suites meaningful

Do not change inbound v1 parsing, contact-request/introduction bootstrap,
group messaging, relay server behavior, key exchange architecture, or database
migration policy.

### 2. closure bar

The session is accepted only when:

- no new ordinary outbound 1:1 chat/edit/delete path builds a v1 plaintext
  envelope when bridge/key material is missing
- missing bridge/key returns `SendChatMessageResult.encryptionRequired` before
  send, local send, relay inbox store, or new plaintext `wireEnvelope`
  persistence
- voice missing-key returns `SendVoiceMessageResult.sendFailed` before
  `media:upload`
- failed and unacked retry shortcuts never replay legacy v1 `chat_message` or
  `message_deletion` envelopes to relay inbox
- encrypted v2 direct, local, inbox fallback, delete, and retry shortcuts still
  work
- inbound v1 chat/deletion tests remain green

### 3. source of truth

Source priority:

1. current production code and tests
2. `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan.md`
3. `scripts/run_test_gates.sh`
4. `Test-Flight-Improv/test-gate-definitions.md`
5. `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`

Current code/tests win over stale prose. The source doc's scope guard wins for
product boundaries.

### 4. session classification

`implementation-ready`

### 5. exact problem statement

The client can still expose readable 1:1 content to relay-visible transport
when bridge or recipient ML-KEM key material is unavailable, and retry can
replay old persisted v1 plaintext envelopes. The user-visible contract should
be fail-closed outbound 1:1 privacy: ordinary chat and delete transport is v2
encrypted or refused, while old inbound v1 rows and mixed-version inbound
traffic remain readable.

### 6. files and repos to inspect next

Production:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/outbound_envelope_policy.dart`

Tests:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`

### 7. existing tests covering this area

Existing send/delete/retry suites cover the transport matrix, inbox fallback,
wire-envelope retry, edits, quotes, media, voice, and inbound compatibility.
Some tests still encode bridge-less plaintext success and must be converted to
encrypted success setup or explicit fail-closed expectations.

### 8. regression/tests to add first

Add focused regressions for:

- outbound envelope policy classifies v1 chat/deletion as unsafe and v2 or
  unrelated/malformed envelopes as safe
- missing chat bridge/key returns `encryptionRequired` with no transport or
  persistence side effects
- encrypted chat sends/store v2 without top-level plaintext payload
- missing delete key returns `encryptionRequired`
- encrypted delete sends v2
- failed retry does not replay v1 chat/deletion envelopes
- unacked retry does not replay v1 chat/deletion envelopes
- v2 retry shortcuts still store
- voice missing key fails before upload
- inbound v1 chat/deletion compatibility remains green

### 9. step-by-step implementation plan

1. Add `outbound_envelope_policy.dart` and focused unit coverage.
2. Replace chat outbound plaintext fallback with early
   `encryptionRequired`.
3. Replace delete outbound plaintext fallback with early
   `encryptionRequired`.
4. Import/use the policy helper in failed and unacked retry before
   `storeInInbox` shortcuts.
5. Add the voice pre-upload missing-key guard.
6. Convert focused bridge-less success tests to encrypted setup or
   fail-closed assertions.
7. Run the source doc stale plaintext audit and fix any direct bridge-less
   success expectations in touched suites or shared helpers.
8. Run focused direct tests, then named gates.

### 10. risks and edge cases

- Offline inbox fallback must remain; only its envelope must be v2 encrypted.
- Existing old rows may contain v1 `wireEnvelope`; retry must not clear or
  deliver them as if safely replayed.
- `retryFailedMessages` should still fall through to full encrypted resend
  when contact key material exists.
- `retryUnackedMessages` cannot re-encrypt, so unsafe v1 rows should move to a
  non-replaying failure path rather than loop forever.
- `PassthroughCryptoBridge` is useful for round-trip tests but not for
  no-plaintext ciphertext assertions.

### 11. exact tests and gates to run

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

Audit:

```bash
rg -n "sendChatMessage\\(|editChatMessage\\(|sendVoiceMessage\\(" test lib
```

Named gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh completeness-check
```

### 12. known-failure interpretation

Bridge-less ordinary 1:1 send/delete success expectations are stale unless
they explicitly cover bootstrap/contact-request behavior. Existing unrelated
local build cache or simulator artifacts are not part of this session. Inbound
v1 parse failures, encrypted inbox fallback failures, or retry replay of v1
envelopes are blocking regressions.

### 13. done criteria

- Focused direct tests pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh baseline` passes or unrelated pre-existing red
  is documented.
- `./scripts/run_test_gates.sh completeness-check` passes if docs/gate-covered
  tests changed.
- Final audit has no unclassified bridge-less ordinary 1:1 success expectation.
- Manual inspection finds no outbound `MessagePayload.toJson()` or
  `MessageDeletionPayload.toJson()` fallback used for ordinary 1:1 transport.
- Manual inspection finds both retry use cases guard the wire-envelope shortcut
  before relay inbox store.
- Manual inspection finds `sendVoiceMessage` checks recipient key before
  upload.

### 14. scope guard

Do not delete inbound v1 models/parsers. Do not change relay server code. Do
not change group encryption or group inbox behavior. Do not redesign key
exchange or add a DB migration. Do not remove encrypted offline inbox fallback.

### 15. accepted differences / intentionally out of scope

Inbound v1 remains accepted. Bootstrap/contact-request flows can keep readable
fields required for key exchange. Old local v1 rows can remain stored, but
retry must not replay them. Relay still sees metadata and ciphertext length.

### 16. dependency impact

Future inbound v1 sunset, relay-side plaintext rejection, or old-row migration
work can build on this session, but none of that is required for outbound
plaintext replay closure.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- Generic media attachment key preflight outside `sendVoiceMessage`
- Database migration to purge old v1 `wireEnvelope` rows
- Relay-side validation against plaintext payloads

## Accepted differences intentionally left unchanged

- Inbound v1 compatibility
- Contact/bootstrap behavior
- Group behavior
- Relay deployment

## Exact docs/files used as evidence

- `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan.md`
- `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`

## Why the plan is safe to implement now

The plan changes only outbound/retry enforcement for ordinary 1:1 envelopes and
keeps the encrypted v2 delivery machinery intact. The tests focus on the exact
privacy boundary: v2 encrypted transport continues to work, while v1 plaintext
transport is blocked or skipped.

## Execution result

Final session verdict: accepted.

Implementation landed the planned single-session slice:

- added `lib/features/conversation/application/outbound_envelope_policy.dart`
  to classify legacy v1 or versionless `chat_message` and
  `message_deletion` envelopes as unsafe for outbound replay
- changed ordinary 1:1 chat/edit/delete sends to require bridge plus recipient
  ML-KEM key material before building an outbound envelope
- changed voice send to fail before media upload when recipient ML-KEM key
  material is missing
- changed failed and unacked retry shortcuts so legacy v1 chat/deletion
  `wireEnvelope` rows are not replayed to relay inbox; failed retry can still
  fall through to normal encrypted resend when key material exists
- converted stale direct and integration test fixtures to encrypted v2 success
  setup or explicit fail-closed assertions
- preserved inbound v1 chat/deletion compatibility

Verification evidence:

- focused direct suite:
  `flutter test --concurrency=1 test/features/conversation/application/outbound_envelope_policy_test.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/retry_unacked_messages_use_case_test.dart test/features/conversation/application/send_voice_message_use_case_test.dart test/features/conversation/application/send_voice_message_no_bg_task_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart test/features/contact_request/integration/contact_request_flow_test.dart test/features/conversation/integration/two_user_message_exchange_test.dart test/features/conversation/integration/media_attachment_flow_test.dart test/features/conversation/integration/media_retry_smoke_test.dart test/performance/benchmark_voice_send_test.dart`
  passed with `202` tests
- additional stale-fixture direct suite:
  `flutter test test/features/conversation/application/retry_failed_messages_media_test.dart`
  passed with `8` tests
- repaired combined smoke fixtures:
  `flutter test test/features/conversation/integration/incomplete_upload_recovery_test.dart test/features/conversation/integration/stuck_sending_recovery_test.dart`
  passed with `6` tests
- named gate:
  `./scripts/run_test_gates.sh 1to1` passed with `71` tests
- named gate:
  `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed; the
  first baseline attempt without `FLUTTER_DEVICE_ID` stopped at device
  selection because multiple devices were connected
- named gate:
  `./scripts/run_test_gates.sh completeness-check` passed with `669/669` test
  files classified
- manual inspection found no ordinary outbound `MessagePayload.toJson()` or
  `MessageDeletionPayload.toJson()` fallback, found retry wire-envelope guards
  before relay inbox store, and found the voice recipient-key preflight before
  upload

Closure docs updated:

- `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/00-INDEX.md`
