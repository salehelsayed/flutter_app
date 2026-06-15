# 1:1 Message Reliability Audit - Codex Run

Date: 2026-06-11
Workspace: `/Users/I560101/Project-Sat/mknoon-2/flutter_app`
Mode: read-only reliability audit plus this report file
Model target from skill: `gpt-5.5`
Reasoning effort target from skill: `xhigh`

Note: the parent session model/effort was not independently visible to this agent. The skill preference was followed where available by using `gpt-5.5`/`xhigh` explorer agents for the parallel audit slices.

## Executive Verdict

Full direct 1:1 reliability should not be treated as closed for text + media + voice + notifications + hostile/network-edge conditions.

The core host-side 1:1 gate is real and passed in this audit. The current receive pipeline also has materially stronger relay behavior than the older destructive inbox path: retrieve-pending entries are staged locally before ACK delete, and direct chat confirm is deferred until after local staging.

The remaining blockers are not "no tests exist." They are narrower and more important:

- High severity source-verified bugs remain around sender identity trust, local WiFi sender trust, partial media persistence, share-to-contact durable intent, voice temp-file recovery, and direct media relay custody/retry.
- Several closure-critical tests are split across named Dart gates, optional simulator runners, and manual Go module tests. The named `1to1` gate passing is necessary but not sufficient for full release confidence.
- The June 11 media-unavailable report supersedes the older broad closure statement for the media slice until its TDD plan and simulator closure pass.

## Scope

Audited surfaces:

- Direct 1:1 outbound send, durable intent, local/direct/relay/inbox fallback, retry, and sender-visible status.
- Direct 1:1 inbound receive, decrypt/validate, duplicate handling, staging, ACK/delete/confirm, media persistence, notifications, and lifecycle drains.
- Direct media and voice upload/download/retry through local WiFi, relay media, and pending upload recovery.
- Relay server inbox/media custody, caps, TTL, and direct sender identity boundaries.
- Existing host, Go, simulator, and gate definitions relevant to 1:1 reliability.

Out of scope:

- Code fixes.
- Full device execution of all reliability simulator rows.
- Group/post reliability except where shared relay/media behavior affects 1:1.

## Reliability Invariant Matrix

| Invariant | Status | Static Evidence | Dynamic Evidence | Required Follow-up |
|---|---|---|---|---|
| Durable outbound intent before external side effects | confirmed_bug | Share contact send calls `sendChatMessage` without `messageId`/`timestamp` at `lib/features/share/application/share_batch_delivery_coordinator.dart:335-347`; `sendChatMessage` only pre-persists `wireEnvelope` when `messageId != null` at `lib/features/conversation/application/send_chat_message_use_case.dart:348-354`; external inbox store can happen before first durable save at `lib/features/conversation/application/send_chat_message_use_case.dart:937-947` and save occurs at `lib/features/conversation/application/send_chat_message_use_case.dart:1549-1564`. | `./scripts/run_test_gates.sh 1to1` passed, but this share default path is not covered by the frozen gate. | Pre-create durable outgoing rows for share-to-contact, require `updateWireEnvelope` to update an existing row, and add a default coordinator durability test. |
| Honest sender success/status | confirmed_bug | Sender records inbox-delivered after store success while relay cap/TTL can later drop old pending messages: `lib/features/conversation/application/send_chat_message_use_case.dart:817-861`, `go-relay-server/backend_memory.go:144-176`, `go-relay-server/inbox.go:23-27`. Direct media also has prior-art source-verified false success/custody issues in `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md:36-64`. | Host `1to1` passed; direct simulator execution not run, only listed. | Define sender status as "accepted for custody" vs recipient-visible delivery, add cap/TTL expiry handling, and close the June 11 media custody plan. |
| Receiver durable staging before ACK/delete/confirm | confirmed_bug | Relay inbox path stages before ACK at `lib/core/services/p2p_service_impl.dart:1138-1186`; direct path stages before confirm at `lib/core/services/p2p_service_impl.dart:761-814`. But message/media persistence is not atomic: message saves at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:310`, attachments save later at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:326-337`. | `1to1` and Go inbox tests passed; no injected attachment-write failure gate exists. | Keep staging-before-ACK, but make message+attachments atomic or make duplicate replay repair missing attachments before rejecting. |
| Attachment/message coherence | confirmed_bug | Incoming media can save the message row before attachment rows, then duplicate replay returns before media parsing at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:190-210` and `:310-337`; duplicate confirmation returns true at `lib/features/conversation/application/chat_message_listener.dart:242-247`. | Not covered by current passing gate. | Add a failing partial-persist replay test, then repair/retry missing attachment rows or use a transaction. |
| Retry idempotency | confirmed_bug | Manual failed-media retry checks `File(localPath)` directly at `lib/features/conversation/application/retry_failed_messages_use_case.dart:430-443`; DB media paths are relative by contract at `lib/core/media/media_file_manager.dart:11-14`; the retry path from conversation passes no `MediaFileManager` at `lib/features/conversation/presentation/screens/conversation_wired.dart:2149-2158`. | Frozen `1to1` passed; existing media retry smoke does not cover this relative path. | Thread `MediaFileManager` into manual retry and preserve stable blob IDs; update relative-path reupload tests. |
| Duplicate safety | confirmed_bug | Confirmed: same-ID duplicate exits before missing media repair at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:190-210`. Risk: stream listener does not serialize `_onMessage` around read-before-write duplicate checks at `lib/features/conversation/application/chat_message_listener.dart:114-116`, `:238-240`. | Current duplicate tests are sequential; no concurrent duplicate barrier test was run. | Add missing-media duplicate repair and a concurrent duplicate test that asserts one event and one notification. |
| Ordering stability | confirmed_gap | Page and full contact loads order only by timestamp at `lib/core/database/helpers/messages_db_helpers.dart:64-79` and `:115-120`; summaries already use a stronger tie-breaker elsewhere. | No targeted same-timestamp pagination/order gate was run. | Add deterministic tie-breakers to message loads and cursor tests for equal timestamps. |
| Transport fallback | confirmed_bug | Direct media download opens one media stream and returns on the first non-OK relay response at `go-mknoon/node/media.go:413-445`; relay media can return `not found` at `go-relay-server/media.go:394-397`. Local WiFi direct accepts JSON sender fields without identity binding at `lib/core/local_discovery/local_ws_server.dart:259-290`. | Reliability-sim `1to1 --list` planned transport/media rows but did not execute them. | Add multi-relay media failover on `not found`/transient failure, and authenticate local direct sender identity. |
| Relay/inbox durability | confirmed_bug | Text inbox retrieve-pending/ACK is covered by source and Go tests. Media store metadata is process-memory only at `go-relay-server/media.go:45-62`, store metadata is not rebuilt from disk at `go-relay-server/media.go:131-142`, and 1:1 media auto-deletes after first download at `go-relay-server/media.go:440-445`. | `go test ./...` in `go-relay-server` passed. It does not make media metadata shared/durable. | Persist/share relay media metadata or make clients retry alternate custody; close the June 11 media plan. |
| Lifecycle recovery | confirmed_bug | Resume drains and retry paths exist, but voice optimistic attachments persist recorder temp paths from `lib/core/media/record_audio_recorder_service.dart:227-230` through `lib/features/conversation/presentation/screens/conversation_wired.dart:2617-2629` and `_persistOptimisticAttachments` preserves that path at `lib/features/conversation/presentation/screens/conversation_wired.dart:3190-3209`. | `1to1` passed including send-then-lock coverage, but no voice temp cleanup/retry test exists. | Copy voice recordings to durable pending upload storage before marking upload-pending. |
| Notification/deep-link correctness | confirmed_gap | Notification-open prepare drains direct routes before opening, but real app handler coverage remains optional in prior docs. Foreground direct push drains and returns `drained` at `lib/features/push/application/handle_foreground_remote_message_use_case.dart:53-59`; recovered replay suppresses notifications at `lib/main.dart:1583-1587`; fallback no-ops unless `notificationNeeded` at `lib/features/push/application/background_push_notification_fallback.dart:146-154`. | Reliability-sim listed notification rows only; no real handler execution in this run. | Add real app foreground/off-conversation direct push tests and make intended alert policy explicit. |
| Security/freshness/authenticity | confirmed_bug | Direct relay store trusts `req.From` instead of `remotePeer` at `go-relay-server/inbox.go:1355-1392`; local WiFi trusts JSON `from`/`to` at `lib/core/local_discovery/local_ws_server.dart:259-290`; handler validates only sender string agreement and known contact at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:150-188`. | No hostile client tests were run. | Enforce `from == remotePeer` on relay direct store and cryptographically bind sender/recipient/freshness in direct envelopes. |
| Observability and operator proof | observability_gap | Flow events exist, but there is no closed-loop user/operator signal for inbox cap/TTL expiry, media not-found failover, simulator silent skip counts, or forged sender rejection. | Gate output was useful but verbose; reliability-sim was dry-run only. | Add per-message custody/expiry/media-unavailable telemetry and gate summaries for executed/skipped critical rows. |
| Gate coverage | confirmed_gap | `scripts/run_test_gates.sh:17-26` defines a nine-file host `1to1` gate; reliability-sim is separate at `scripts/run_test_gates.sh:462-466`; `all` does not include simulator execution or Go module tests at `scripts/run_test_gates.sh:475-483`; Dart completeness checks only Dart test trees at `scripts/run_test_gates.sh:400-428`. | `1to1`, Dart completeness, and two Go module runs passed; simulator rows were listed only. | Promote a release-critical 1:1 simulator subset and Go module tests into the release gate contract or document them as required companion gates. |

## Graphify Queries Used

Graphify was used before raw source browsing, per project instructions. Queries included:

- `graphify query "direct 1:1 message reliability send receive ack retry delivery notifications local discovery relay inbox media tests" --budget 6000`
- `graphify query "direct conversation send chat message use case p2p message stream incoming listener ack delete retry pending retrier" --budget 6000`
- `graphify query "1:1 offline inbox relay restart resume app killed duplicate ordering stale pending failed message recovery" --budget 6000`
- `graphify query "1:1 notifications deep link tap open conversation missed delivery media download lifecycle background foreground" --budget 6000`
- `graphify query "1:1 reliability tests gates integration simulator two user message exchange offline inbox media retry smoke" --budget 6000`
- `graphify explain "PendingMessageRetrier"`
- `graphify query "send_chat_message_use_case.dart PendingMessageRetrier retryFailedMessages retryUnackedMessages wireEnvelope durable outgoing status" --budget 5000`
- `graphify query "handle_incoming_chat_message_use_case.dart chat_message_listener.dart duplicate unknownSender missingMlKemSecret confirmation nonce notification" --budget 5000`
- `graphify query "messages_db_helpers.dart timestamp order pagination id primary key duplicate loadMessagesForContact" --budget 5000`
- `graphify query "prepare_notification_open_use_case.dart notification route target direct chat conversation drain offline inbox 1:1" --budget 5000`
- `graphify query "go-relay-server inbox media store retrieve_pending ack delete MediaStore not found maxMessagesPerPeer" --budget 5000`

The graph was useful for orientation but sparse/noisy for several concepts, so source, tests, scripts, and prior docs were read directly after the graph step.

## Tests And Gates Run

Passed:

- `./scripts/run_test_gates.sh completeness-check`
  - Result: PASS, `822/822` Dart test files classified.
- `./scripts/run_test_gates.sh 1to1`
  - Result: PASS, `00:09 +74: All tests passed!`
- `(cd go-relay-server && go test ./...)`
  - Result: PASS, `ok github.com/mknoon/relay-server (cached)`.
- `(cd go-mknoon && go test ./node)`
  - Result: PASS, `ok github.com/mknoon/go-mknoon/node 435.418s`.
- `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh 1to1 --list`
  - Result: discovery PASS/dry-run only. It resolved simulator devices and listed 20 planned 1:1 reliability commands. No simulator commands were executed.

Mis-run and superseded:

- `go test ./go-relay-server ./go-mknoon/node` from repo root failed because this repo does not have a root Go module for those package paths. The module-root Go runs above supersede this.

Not run in this audit:

- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh reliability-sim 1to1 --continue-on-failure`
- Individual device scripts from the 20-command reliability-sim plan.

## Confirmed Bugs

### 1. Direct relay inbox trusts client-supplied sender

Severity: high

For direct `action=store`, relay reads `remotePeer` but stores `req.From` if supplied: `go-relay-server/inbox.go:1355-1392`. A custom relay client can claim another sender identity. Flutter then validates sender string consistency and known-contact state, but there is no relay-enforced sender binding in this path.

Failing test to add:

- `go-relay-server/inbox_test.go`: intruder opens inbox protocol, sends `action=store,to=recipient,from=trustedSender`, and relay must reject it with recipient inbox empty.

### 2. Local WiFi direct path trusts JSON sender

Severity: high

The local WebSocket path accepts `from`, `to`, and `content` from any connected WebSocket JSON and ACKs before emitting the message: `lib/core/local_discovery/local_ws_server.dart:259-290`. The common handler later checks sender agreement and known contact, not a session-bound or signed local identity.

Failing test to add:

- `test/core/local_discovery/local_ws_server_test.dart`: unauthenticated LAN client sends `from=trustedPeer`; server must not ACK or emit `LocalChatMessage` unless identity is bound.

### 3. Partial media persist can poison recovered replay

Severity: high

Incoming handling saves the message before attachments: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:310` and `:326-337`. If attachment persistence throws, replay is marked retryable; the next replay sees the message ID as duplicate and exits before repairing attachment metadata at `:190-210`. Production maps duplicate to rejected at `lib/main.dart:1663-1667`.

Failing test to add:

- Stage a recovered media chat, force attachment save to throw after message save, replay twice, and assert the row is not terminally rejected as duplicate and media is eventually repaired or remains retryable.

### 4. Share-to-contact can send externally before durable sender row exists

Severity: high

`DefaultShareBatchDeliveryCoordinator._sendToContact` calls `sendChatMessage` without a pre-created `messageId`/`timestamp`: `lib/features/share/application/share_batch_delivery_coordinator.dart:335-347`. In that mode `sendChatMessage` generates an ID internally at `lib/features/conversation/application/send_chat_message_use_case.dart:259-263`, skips pre-transport `wireEnvelope` persistence because `messageId == null` at `:348-354`, and can perform direct/inbox side effects before the first local save at `:937-947` and `:1549-1564`.

Failing test to add:

- `test/features/share/application/share_batch_delivery_coordinator_test.dart`: execute the real default contact path and assert a durable sending row plus `wireEnvelope` exists before any direct/inbox send is attempted.

### 5. Voice upload recovery persists recorder temp paths

Severity: high

Recorder output defaults to temp storage at `lib/core/media/record_audio_recorder_service.dart:227-230`. Conversation voice optimistic media persists `localPath: recording.filePath` at `lib/features/conversation/presentation/screens/conversation_wired.dart:2617-2629`, and `_persistOptimisticAttachments` marks it `upload_pending` without copying to durable storage at `:3190-3209`.

Failing test to add:

- Voice send with an interrupted upload, delete the original temp file, then resume retry. The pending upload must still resolve to a durable app-owned file.

### 6. Manual failed-media retry cannot resolve relative pending paths

Severity: medium

Manual failed-media retry calls `retryFailedMessage` without `MediaFileManager`: `lib/features/conversation/presentation/screens/conversation_wired.dart:2149-2158`. The reupload helper directly checks `File(localPath).existsSync()` at `lib/features/conversation/application/retry_failed_messages_use_case.dart:430-443`, while stored media paths are relative by design at `lib/core/media/media_file_manager.dart:11-14`.

Failing test to add:

- Update media reupload retry coverage so a relative pending upload path resolves through `MediaFileManager` and reuses the same blob ID.

### 7. Direct media relay custody remains fragile

Severity: high

This is carried forward from the June 11 media-unavailable report and source-verified here:

- Media metadata is in-memory only: `go-relay-server/media.go:45-62`.
- Store adds metadata only to memory structures: `go-relay-server/media.go:131-142`.
- Download returns `not found` when metadata is missing: `go-relay-server/media.go:394-397`.
- 1:1 media auto-deletes after the first download: `go-relay-server/media.go:440-445`.
- Client media download returns after the first non-OK relay response rather than trying later relays: `go-mknoon/node/media.go:413-445`.

The existing June 11 plan is still the right owning artifact: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.

## Confirmed Coverage Gaps

1. Real bridge crypto/user-visible 1:1 proof is outside the frozen `1to1` gate. The main two-user host test uses fake/pass-through crypto; real bridge/device proof is separate.
2. The reliability simulator 1:1 pool is discoverable but not executed by the named `1to1` gate or `all` gate.
3. Go relay/node tests are outside Dart completeness and outside `run_test_gates.sh all`.
4. Notification-open real app handlers remain optional/manual relative to 1:1 closure.
5. Foreground direct push drain can be silent off-conversation; current tests cover drain and fallback behavior separately, but not the user-visible alert policy for this path.
6. Default share-to-contact durable intent has no focused test because existing share tests can inject a send function instead of executing `_sendToContact`.
7. Same-timestamp message ordering and id-divergent duplicate semantics remain prior-art open gaps and are still source-plausible.

## Observability Gaps

- No sender-visible distinction between "relay accepted custody" and "recipient durably displayed message."
- No clear local diagnostic when media is unavailable because a relay instance lost metadata, auto-deleted a 1:1 blob, or the client stopped after one relay returned `not found`.
- No gate-level assertion that reliability-sim critical rows actually executed instead of listing or skipping.
- No explicit telemetry for forged direct sender rejection because the current relay/local paths do not reject those cases.
- No concise operator view tying `wireEnvelope`, inbox entry ID, ACK/delete, replay disposition, media blob ID, and final UI visibility together for a single message.

## Unverified Risks

1. Concurrent same-ID inbound events may bypass read-before-write duplicate detection because stream processing is async and not serialized around `processIncomingMessage`: `lib/features/conversation/application/chat_message_listener.dart:114-116`, `:238-240`, and duplicate check at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:190-210`.
2. Inbox cap/TTL can outlive sender delivered state: sender persists delivered after inbox store, but relay caps/TTL can evict/expire older entries later.
3. Conversation optimistic save failure logs and continues toward transport: `lib/features/conversation/presentation/screens/conversation_wired.dart:1698-1715`. Normal conversation send passes an ID so `wireEnvelope` update is attempted, but `dbUpdateWireEnvelope` ignores update row count at `lib/core/database/helpers/messages_db_helpers.dart:822-839`.
4. Direct v1/plaintext compatibility and missing signed freshness remain security risks from the June 6 report. This audit confirmed adjacent sender-binding bugs but did not execute a full protocol downgrade/freshness matrix.

## Refuted Or Narrowed Findings

- "No 1:1 tests exist" is refuted. The named `1to1` gate exists and passed in this run.
- "Automatic offline inbox drain destructively deletes before local persistence" is narrowed/refuted for the current automatic path. Current source uses retrieve-pending, stages locally, then ACKs: `lib/core/services/p2p_service_impl.dart:1138-1186`. Legacy destructive retrieve still exists and should stay out of direct chat recovery paths.
- "Direct libp2p confirm always happens before local durability" is narrowed. Direct staging happens before confirm at `lib/core/services/p2p_service_impl.dart:761-814`, but confirm still precedes final replay/message+attachment commit, so media partial-persist remains a real bug.

## Concrete Failing Tests To Add

1. `go-relay-server/inbox_test.go`: direct store rejects forged `from` when `req.From != remotePeer`.
2. `test/core/local_discovery/local_ws_server_test.dart`: unauthenticated WebSocket sender spoof is rejected and not ACKed.
3. `test/features/share/application/share_batch_delivery_coordinator_test.dart`: default contact path pre-persists durable outgoing intent and `wireEnvelope` before transport.
4. `test/core/services/p2p_service_impl_test.dart`: staged recovered media chat with attachment save failure remains retryable or repairs on replay, never rejected as duplicate.
5. `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`: same-ID replay repairs missing media rows when the message row exists without attachments.
6. `test/features/conversation/application/chat_message_listener_test.dart`: concurrent same-ID inbound events produce one DB row, one stream event, and one notification.
7. `test/features/conversation/presentation/screens/conversation_wired_test.dart`: voice pending upload is copied to durable pending storage before upload/retry.
8. `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`: manual failed-media retry resolves relative paths through `MediaFileManager`.
9. `go-relay-server/media_test.go`: relay media metadata survives restart or reports a non-success custody state that clients can recover from.
10. `go-mknoon/node/media_test.go`: media download tries another relay after `not found`/transient failure.
11. `test/features/push/application/handle_foreground_remote_message_use_case_test.dart` plus fallback coverage: foreground direct drain while off-conversation either displays an alert or records explicit intentional silence.
12. Message DB pagination/order test: equal timestamps remain stable across pages with an ID/created-at tie-breaker.
13. Real bridge 1:1 crypto/device test: two real identities exchange encrypted text/media and reject forged/downgraded payloads.

## Recommended Implementation Sessions

1. Sender identity and local direct authentication
   - Enforce `from == remotePeer` for relay direct store.
   - Bind local WiFi direct messages to an authenticated local peer/session.
   - Add hostile-client tests before implementation.

2. Media atomicity and recovery
   - Make inbound message+attachment persistence atomic or duplicate-repairable.
   - Complete the June 11 media-unavailable TDD plan.
   - Add media relay failover and unavailable retry UI wiring.

3. Durable outbound intent and status honesty
   - Fix share-to-contact pre-persistence.
   - Make `updateWireEnvelope` fail or recover when no row is updated.
   - Clarify inbox custody vs recipient-visible status and cap/TTL expiry behavior.

4. Voice and failed-media retry durability
   - Copy voice recordings to durable pending upload storage.
   - Route manual retry through `MediaFileManager`.
   - Preserve stable blob IDs through all retry paths.

5. Gate and observability hardening
   - Promote required Go tests and a small critical reliability-sim subset into release closure.
   - Add no-silent-skip summaries.
   - Add per-message custody/replay/media diagnostics.

## Evidence To Pull From Devices And Relay

Run before claiming full closure:

- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`
- `./scripts/run_test_gates.sh reliability-sim 1to1 --continue-on-failure`
- `dart run integration_test/scripts/run_transport_e2e.dart -d <device-id>`
- `dart run integration_test/scripts/run_media_message_journey_e2e.dart -d <device-id>`
- `dart run integration_test/scripts/run_notification_open_ui_smoke.dart -d <device-id>`
- `dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -d <device-id> -p ios`

Collect:

- Relay inbox `store`, `retrieve_pending`, `ack`, cap/TTL eviction, and forged-sender rejection logs.
- Relay media upload/download/not-found/auto-delete/failover logs.
- Client flow events for `messageId`, `wireEnvelope`, inbox `entryId`, ACK timing, replay disposition, media blob ID, and final UI visibility.
- Simulator skip/execution counts for every selected reliability-sim row.

## Process Notes

- Dirty `graphify-out` and many dirty worktree files existed before this report. They were not reverted.
- This audit created only this report file.
- Subagent slices covered outbound durability, inbound/notification/lifecycle, media/voice, relay/transport/security, and tests/gates. Source line ranges used for high-severity findings were rechecked directly in the parent session before writing this report.

## Open Questions

1. Should direct 1:1 relay store enforce `from == remotePeer` exactly like group-store spoof protection?
2. Is local WiFi direct intended to be trusted-LAN only, or must it meet the same sender/recipient/freshness guarantees as relay/libp2p direct chat?
3. Should foreground 1:1 FCM-triggered drains show a local/in-app alert when the app is resumed but not viewing that conversation?
4. What user-visible status should replace or refine `delivered` when a relay has accepted inbox custody but the recipient may be offline past retention or over cap?
