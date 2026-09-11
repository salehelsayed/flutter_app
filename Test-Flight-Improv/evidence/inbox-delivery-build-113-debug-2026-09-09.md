# Inbox delivery warning in iOS 1.0.1 (113)

## Finding

Build 113's app diagnostics extended the cleartext outer `chat_message`
envelope with `diagnosticTraceId`. Protected direct-text inbox custody accepts
exactly `type`, `version`, `id`, `senderPeerId`, and `encrypted`. The added
field therefore causes `CUSTODY_INELIGIBLE`, even though encryption succeeds
and the relay is reachable.

Separately, the conversation UI assigned `transport: 'inbox'` when retaining
an envelope-backed failed send for automatic retry. That produced an inbox
icon without an accepting relay receipt, alongside the delivery-delayed
snackbar. The icon was not proof of delivery or custody.

## Observed evidence

- Read-only live diagnostics for iOS `1.0.1+113` contained four outgoing
  message attempts between 07:52:43 and 07:55:04 UTC on 2026-09-09. Encryption
  succeeded; each attempt's two inbox stores failed. The attempts ended as
  failed with local message persistence and without delivery acknowledgment.
- Two successful message attempts in the same report were incoming messages,
  not successful sends of those four outgoing messages.
- The relay metrics snapshot contained 16 protected-inbox `ineligible`
  outcomes, zero `rejected_full`, zero backend `failed`, and zero `disabled`.
  These are aggregate counters, not individually attributed request records.
- The strict relay protocol test reproduces rejection of a valid UUID in the
  outer envelope. The same message identity and ciphertext acquire protected
  custody and its legacy shadow when the outer field is absent.
- `TC-192-02` reproduced the premature inbox icon before the UI change.

Endpoint diagnostics are correlated evidence; this investigation did not
establish receipt of those messages on the recipient's device. No live
messages were sent, no app was reinstalled, and no relay service was changed.
Private collector records and message content are not included here.

## Changes

- `MessagePayload.buildEncryptedEnvelope` restores the established outer
  envelope shape. Diagnostic IDs remain in encrypted inner content.
- Four outgoing envelope-builder call sites stop passing outer diagnostics.
- `_settleRetriableOrdinaryMessage` preserves the actual transport instead of
  inventing inbox acceptance.
- Payload, UI, and relay regressions cover the protocol shape and the
  acceptance-dependent inbox icon.

## Compatibility and current-build workaround

The relay protocol and relay implementation are unchanged. Clients using the
established envelope format, including older clients and recipients, remain
compatible. Recipient upgrades are not required by this fix.

In build 113, disabling app diagnostics causes `traceForOperation` to return
null and prevents the outer field on **new** sends. Already-authored queued
messages retain immutable serialized envelopes; their retry drain reuses
those bytes. Neither that setting change nor the new builder automatically
repairs already-queued messages. No queue mutation or migration was performed.

At the user's subsequent request, the corrected iOS client was built as
`1.0.1 (114)`. The exported IPA and both extensions pass distribution-signature
and version checks, production APNs is present, and the native Go bridge is
verified. The artifact is
`build/releases/1.0.1+114/mknoon-1.0.1-114.ipa`, with SHA-256
`aa41b3449ab1fb04b4aa0fc8dec91b348fb9aef76e21bf023a538ef54057b097`.
Build provenance and verification receipts are beside the IPA. Build 113's
prior IPA was preserved. Build 114 has not been uploaded or installed.

The Google Play Android App Bundle was also subsequently built as `1.0.1`
with version code `114`:
`build/releases/1.0.1+114/mknoon-1.0.1-114.aab`. SHA-256:
`d4c1726fd8f963f5cda864f2990665de40d520dd2ba88ffe38f5ec79bdfc6932`.
Bundletool validation, JAR signature verification, and ZIP integrity checks
pass. Its upload-signing certificate matches build 113. The manifest uses
`com.mknoon.app`, release mode, minimum SDK 24, and target SDK 36. All three
native ABIs contain the pinned Go 1.25.0 bridge. The prior Android bundle was
preserved, and no Play upload was performed. Android provenance and the
verification receipt are beside the AAB.

## Validation

- Payload model suite: 58 passed.
- Offline-send UI suite: 20 passed, including the regression failing before
  the fix and passing after it.
- Protected-custody diagnostic-envelope protocol regression: passed.
- Full send-use-case suite: 192 passed. An existing diagnostics assertion
  initially expected the unsupported outer field; it now checks the exact
  envelope keys and verifies the diagnostic UUID in the encryption input.
- Existing custody-eligibility protocol suite: passed, preserving acceptance
  of the established message format and rejection of unsupported shapes.
- Total Dart coverage: 270 passed across the three exact suites.
- Changed-path impact checks and incremental architecture graph refresh:
  complete. Task-scoped `git diff --check`: clean.
- Navigation workflow benchmark: 5/7, with a document-to-code handoff miss
  and a measured raw-read gap of 13 against a target of 10. These are workflow
  compliance misses; changed-path coverage is full with no pending impact debt.

Commands used the pinned Flutter 3.47.2 SDK:

```sh
.fvm/flutter_sdk/bin/flutter test --no-pub test/features/conversation/domain/models/message_payload_test.dart --reporter expanded
.fvm/flutter_sdk/bin/flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart --reporter expanded
.fvm/flutter_sdk/bin/flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart --reporter expanded
# From go-relay-server/:
go test ./... -run '^(TestAckCustodyDiagnosticMetadataMustStayInsideCiphertext|TestRelayNotificationClosure_AckCustodyEligibilityIsNarrow)$' -count=1
```

## Code anchors

- `lib/features/conversation/domain/models/message_payload.dart`:
  `buildEncryptedEnvelope`, `toInnerJson`.
- `lib/features/conversation/presentation/screens/conversation_wired.dart`:
  `_settleRetriableOrdinaryMessage`.
- `lib/features/conversation/presentation/widgets/letter_card.dart`:
  `_resolvedStatusIcon`.
- `go-relay-server/ack_custody.go`:
  `extractAckCustodyDedupeKeyForRecipient`.
- `go-relay-server/ack_custody_protocol_test.go`:
  `TestAckCustodyDiagnosticMetadataMustStayInsideCiphertext`.
- `lib/core/diagnostics/app_diagnostics.dart`: `traceForOperation`.
- `lib/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart`:
  immutable `entry.wireEnvelope` replay.

Graph navigation context: `e3d47f6d34d5474a` / `754cd336483308bc` (send/UI),
`12f564d0336b4c81` / `a8c00341ceeed5be` (relay admission), and
`240cda6d08df4942` / `928cc0fe0dc6ad41` (payload). Changed-path impact query:
`b18aa534f36d4730`; send-test follow-up: `6437ad3994b2459a`.
