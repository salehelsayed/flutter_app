# 76 - Remove Legacy 1:1 Plaintext Path Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan.md`
- Decomposition date:
  `2026-04-26`
- Decomposition status:
  `local fallback after spawned decomposer no-progressed without leaving the adjacent breakdown artifact`
- Downstream workflow rule:
  detailed planning happens one session at a time; later sessions must be
  refreshed against landed code and tests before execution.

## downstream execution path

- Reuse an existing doc-scoped session plan when safe; otherwise create or
  tighten it with `$implementation-plan-orchestrator`.
- Execute each session with `$implementation-execution-qa-orchestrator`.
- Close each session with `$implementation-closure-audit-orchestrator`.
- Use fresh child-agent contexts for planning, execution, and closure when
  available.
- Continue session by session until this breakdown records a final program
  verdict. A first plan, first accepted session, or first ledger update is not
  pipeline completion.
- Treat this as an implementation-committed rollout for the source plan's
  closure bar: do not downgrade the code/test session to doc-only work while
  outbound 1:1 plaintext send or retry paths remain open.
- Pipeline execution status:
  local fallback after spawned pipeline controller no-progressed without
  leaving a final session verdict. The local fallback executed the single
  session to acceptance and recorded the final program verdict below.

## recommended plan count

- `1`

## overall closure bar

Report `76` is closed only when ordinary outbound 1:1 chat and delete flows can
no longer send, store, persist, or retry legacy v1 plaintext envelopes while the
existing encrypted v2 offline inbox and retry contracts remain functional:

- `MessagePayload` and `MessageDeletionPayload` outbound 1:1 send paths require
  a bridge and recipient ML-KEM public key before direct, local, retry, or relay
  inbox transport.
- Missing `Bridge` or missing recipient ML-KEM key returns
  `SendChatMessageResult.encryptionRequired` before any plaintext envelope is
  built, sent, stored in relay inbox, or persisted as a new outbound
  `wireEnvelope`.
- `sendVoiceMessage` fails before media upload when recipient ML-KEM key
  material is missing, so fail-closed chat behavior cannot create orphaned
  uploads.
- Retry of existing pre-upgrade v1 `chat_message` or `message_deletion`
  `wireEnvelope` rows never replays the stored plaintext to relay inbox or
  direct transport; when safe key material exists, retry re-enters the normal
  encrypted path.
- Encrypted v2 text, edit, quote, media, voice, delete, offline inbox fallback,
  and retry flows remain green.
- Inbound legacy v1 chat and deletion parsing remains intentionally supported
  for old stored rows and mixed-version peers.
- Contact request, introduction/bootstrap behavior, group messaging, relay
  server behavior, and server deployment remain out of scope.

## source of truth

Primary governing docs and gate definitions:

- `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan.md`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-1-plan.md`
- `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`

Current code and tests beat stale prose. `scripts/run_test_gates.sh` is the
executable source of truth for named gates when it differs from prose.

Likely production entry points:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/delete_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/domain/models/message_deletion_payload.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- optional helper:
  `lib/features/conversation/application/outbound_envelope_policy.dart`

Likely direct test entry points:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/delete_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`

Cross-suite stale plaintext expectation audit:

```bash
rg -n "sendChatMessage\\(|editChatMessage\\(|sendVoiceMessage\\(" test lib
```

Every direct success expectation from that audit must either provide bridge plus
recipient ML-KEM key material or intentionally assert fail-closed behavior.

## session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Remove outbound and retry legacy 1:1 plaintext envelopes` | `implementation-ready` | `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/00-INDEX.md` | Implemented and accepted. Ordinary outbound 1:1 chat/edit/delete/voice and retry are encrypted v2 or fail closed; persisted legacy v1 chat/deletion envelopes are not replayed. |

## ordered session breakdown

### Session 1

- Title:
  `Remove outbound and retry legacy 1:1 plaintext envelopes`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-1-plan.md`
- Exact scope:
  - add a small pure outbound envelope classifier, likely
    `outbound_envelope_policy.dart`, that treats serialized v1 or version-less
    `chat_message` and `message_deletion` envelopes as unsafe for outbound
    replay while leaving malformed JSON, unrelated types, and v2 encrypted
    envelopes outside the unsafe set
  - update `sendChatMessage(...)` and `editChatMessage(...)` tests so intended
    success paths pass a bridge plus recipient ML-KEM public key, and add
    explicit missing-bridge or missing-key `encryptionRequired` regressions
  - remove the `MessagePayload.toJson()` outbound fallback for ordinary 1:1
    chat/edit/reply/media sends so plaintext v1 envelopes are never sent,
    stored in relay inbox, or persisted as new outbound `wireEnvelope` rows
  - update delete-for-everyone tests and production code so outbound
    `MessageDeletionPayload` also requires v2 encryption while inbound v1
    deletion parsing remains supported
  - guard `retryFailedMessages` and `retryUnackedMessages` at their existing
    `msg.wireEnvelope` shortcut gates so persisted v1 chat/deletion envelopes
    are never replayed to relay inbox, while encrypted v2 shortcuts keep their
    current behavior
  - add the narrow `sendVoiceMessage` pre-upload missing-key regression and
    fail-closed guard
  - run the source plan's cross-suite audit and convert or classify every
    bridge-less success expectation in tests, shared fakes, wrappers, and
    production send entry points
  - preserve inbound v1 chat/deletion compatibility, contact/bootstrap flows,
    group flows, relay behavior, and encrypted offline inbox fallback
- Why it is its own session:
  the source plan intentionally defines one coherent outbound 1:1 privacy
  slice. The send path, delete path, retry guards, and voice pre-upload guard
  share one closure bar: ordinary 1:1 transport must be encrypted v2 or fail
  closed. Splitting would create misleading half-states where one transport or
  retry path still leaks plaintext while the rollout appears partially closed.
- Likely code-entry files:
  - `lib/features/conversation/application/send_chat_message_use_case.dart`
  - `lib/features/conversation/application/send_voice_message_use_case.dart`
  - `lib/features/conversation/application/delete_message_use_case.dart`
  - `lib/features/conversation/application/retry_failed_messages_use_case.dart`
  - `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
  - `lib/features/conversation/domain/models/message_payload.dart`
  - `lib/features/conversation/domain/models/message_deletion_payload.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/features/share/application/share_batch_delivery_coordinator.dart`
  - `lib/features/feed/presentation/screens/feed_wired.dart`
  - optional new helper:
    `lib/features/conversation/application/outbound_envelope_policy.dart`
- Likely direct tests/regressions:
  - `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/delete_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart`
  - `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `flutter test test/features/conversation/application/send_voice_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `flutter test test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
  - helper/classifier unit tests added for the outbound envelope policy
  - targeted wrapper or integration tests discovered by the stale plaintext
    expectation audit
- Likely named gates:
  - `./scripts/run_test_gates.sh 1to1`
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh completeness-check` if test docs or
    gate-covered tests are changed
- Matrix/closure docs to update when done:
  - required:
    `Test-Flight-Improv/76-remove-legacy-1to1-plaintext-path-plan-session-breakdown.md`
  - update when materially affected:
    `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
  - update only if gate classification changes:
    `Test-Flight-Improv/test-gate-definitions.md`
- Dependency on earlier sessions:
  none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## why this is not fewer sessions

It is already the minimum meaningful split: one implementation-ready session.
The source plan's affected code paths all enforce the same privacy invariant
for ordinary 1:1 outbound envelopes. Reducing below one session would leave no
verified implementation unit for the pipeline.

## why this is not more sessions

Separate chat, delete, retry, and voice sessions would invite unsafe
intermediate states where one outbound or retry route still accepts plaintext
while another route is fixed. The current source plan is narrow enough for one
session because it touches one product boundary, one direct test family, and the
same named 1:1 reliability gate. Any broader work, including inbound v1 sunset,
relay validation, key-exchange redesign, database migration, or group behavior,
is explicitly out of scope and should remain separate.

## pipeline execution notes

- Spawned decomposer no-progressed without leaving the adjacent breakdown
  artifact; this file was created as the required local fallback.
- Spawned pipeline controller no-progressed without leaving a final session
  verdict; the single-session rollout was executed locally from the accepted
  session plan.
- Focused direct verification passed, including send, delete, retry, voice,
  inbound compatibility, contact request, media integration, media retry, and
  performance voice-send coverage.
- The first canonical `1to1` gate rerun exposed two stale retry/recovery smoke
  fixtures with null recipient ML-KEM key material; those fixtures were
  converted to encrypted test setup and the canonical `1to1` gate then passed.
- The first `baseline` run stopped before integration tests because Flutter saw
  multiple connected devices. The canonical baseline gate passed when rerun
  with `FLUTTER_DEVICE_ID=macos`.
- `completeness-check` passed with all test files classified.
- Closure docs were refreshed to make the v2-only outbound/retry privacy
  contract part of maintenance-time 1:1 reliability closure.

## final program verdict

Report `76` is accepted as closed.

Ordinary outbound 1:1 chat, edit, delete, voice, media, offline inbox fallback,
and retry now satisfy the source plan's closure bar: new outbound transport is
encrypted v2 or fail-closed before plaintext can be sent, stored, persisted as
a new outbound `wireEnvelope`, or uploaded as orphaned voice media. Retry
shortcuts do not replay legacy v1 chat/deletion envelopes, while inbound v1
chat and deletion parsing remains intentionally supported.
