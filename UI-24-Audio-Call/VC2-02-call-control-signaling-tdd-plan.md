# VC2-02 — Call Control, Encrypted Signaling, and Ephemeral Mailbox TDD Plan

**Status:** Proposed  
**Depends on:** VC2-01  
**Blocks:** VC2-03, VC2-04, VC2-05  
**Primary outcome:** One deterministic Dart-owned call session converges across direct, Circuit Relay, ephemeral mailbox, and duplicate wake paths without real media.

## 1. Scope

### In scope

- Call domain model, event grammar, reducer/state machine, fake clock, timers, and shared cleanup.
- Signed ML-KEM/AES-GCM call envelopes and sender/recipient/device binding.
- `call_signal` route over the existing P2P message stream.
- Direct and Circuit Relay signaling adapter.
- Redis-backed ephemeral call mailbox with hard TTL and bounded capacity.
- Opaque contact wake handles and one preferred call endpoint selected by intersecting trusted contact-device authority with relay capability state.
- Android standard-call push capability contract and separate iOS VoIP-token registration contract at the relay boundary.
- Local call-history persistence and conversation projection model.
- Simulated call UI/state harness; no WebRTC audio.

### Out of scope

- Real SDP/ICE, microphone capture, audio routing, Android Telecom, iOS CallKit/PushKit delivery, and external rollout.

## 2. Existing surfaces to extend carefully

- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `lib/app/bootstrap/`
- `lib/features/contacts/domain/models/contact_model.dart`
- `lib/features/conversation/domain/models/conversation_message.dart`
- `go-mknoon/node/inbox.go`
- `go-mknoon/bridge/bridge.go`
- `go-relay-server/inbox.go`
- `go-relay-server/opaque_wake.go`
- `go-relay-server/wake_outcome.go`

The ordinary chat serializer, durable chat outbox, `PendingMessageRetrier`, legacy inbox retention semantics, fail-open in-memory wake/token state, and ordinary iOS notification path must not be broadened to own call events.

## 3. Proposed new surfaces

### Dart domain/application

- `lib/features/call/domain/call_id.dart`
- `lib/features/call/domain/call_state.dart`
- `lib/features/call/domain/call_event.dart`
- `lib/features/call/domain/call_signal.dart`
- `lib/features/call/domain/call_end_reason.dart`
- `lib/features/call/domain/call_session_snapshot.dart`
- `lib/features/call/application/call_coordinator.dart`
- `lib/features/call/application/call_signaling_service.dart`
- `lib/features/call/application/handle_incoming_call_signal.dart`
- `lib/features/call/application/call_endpoint_resolver.dart`
- `lib/features/call/application/call_cleanup_coordinator.dart`
- `lib/features/call/application/call_history_projector.dart`

### Dart infrastructure/data

- `lib/features/call/infrastructure/secure_call_envelope_codec.dart`
- `lib/features/call/infrastructure/p2p_call_transport.dart`
- `lib/features/call/infrastructure/call_mailbox_client.dart`
- `lib/features/call/data/call_history_repository.dart`
- `lib/features/call/data/call_history_repository_impl.dart`

### Relay/Go

- `go-relay-server/call_mailbox.go`
- `go-relay-server/call_mailbox_redis.go`
- `go-relay-server/call_endpoint_registry.go`
- `go-relay-server/call_wake.go`
- Corresponding focused and process-integration tests.
- Additive node/bridge methods for mailbox, endpoint, wake-handle, and VoIP-token actions.

### Tests

- `test/features/call/domain/call_state_machine_test.dart`
- `test/features/call/domain/call_signal_schema_test.dart`
- `test/features/call/application/call_coordinator_test.dart`
- `test/features/call/application/call_race_convergence_test.dart`
- `test/features/call/application/call_endpoint_resolver_test.dart`
- `test/features/call/application/call_cleanup_coordinator_test.dart`
- `test/features/call/infrastructure/secure_call_envelope_codec_test.dart`
- `test/features/call/infrastructure/p2p_call_transport_test.dart`
- `test/features/call/integration/call_direct_mailbox_convergence_test.dart`
- `test/features/call/data/call_history_repository_test.dart`

All proposed names are new paths, not claims that these files currently exist.

## 4. Frozen domain contract

### States

`idle`, `preparing`, `inviting`, `incomingValidating`, `ringing`, `accepted`, `negotiating`, `connected`, `reconnecting`, `ending`, `ended`.

VC2-02 exercises through `accepted` and simulated terminal transitions; VC2-03 activates real `negotiating`, `connected`, and `reconnecting` media behavior.

### Events

- Local: place, answer, decline, cancel, end, timeout, app shutdown, native action.
- Remote: invite, ringing, accept, reject, offer, answer, ice, ice restart, terminate.
- Transport: direct accepted/failed, mailbox stored/retrieved/acked/expired, wake requested.
- Media placeholders: negotiation ready/failed, connected/lost/recovered.

### Reducer rule

A pure reducer returns:

- next immutable snapshot;
- ordered effects to execute;
- ignored/rejected reason;
- whether terminal cleanup must run.

Effects execute outside the reducer and report results as new events. Tests use an injected clock and deterministic ID source.

## 5. State-machine RED matrix

Write failing tests before production state code for at least:

1. Outgoing place → invite → ringing → accept.
2. Incoming invite → validated → system UI presented → ringing → answer.
3. Transport ACK does not transition to ringing.
4. Decline before accept.
5. Caller cancel racing recipient answer; terminal wins.
6. No-answer timeout at 30 seconds.
7. Invite expiry at 45 seconds; history only, never ring.
8. Duplicate invite through direct and mailbox; one session/UI.
9. Duplicate push and mailbox retrieval; one session/UI.
10. Duplicate terminate; one cleanup/history row.
11. Out-of-order answer before accept rejected.
12. Late offer/candidate after terminal ignored.
13. Same-contact glare converges on the canonical tuple.
14. Unrelated second call while active returns busy.
15. Blocked, unknown, wrong-device, unsupported-version, invalid-signature, and malformed envelopes never create a session.
16. App shutdown during every non-terminal state invokes one cleanup effect.
17. Cleanup failure cannot re-open or leave the active-session reference populated.
18. Candidate/effect/event queues enforce configured bounds.
19. Trusted roster device plus matching relay capability resolves; relay-only, roster-only, stale-epoch, unlinked, and ambiguous records fail before session creation.
20. Required Redis call custody/endpoint/wake/token write failure never returns in-memory success.

## 6. Signaling envelope TDD

### RED

Fixtures fail until the codec enforces:

- exact schema/version;
- 128-bit random `call_id`, `call_handle`, and `message_id` grammar;
- sender-sequence monotonicity per sender/device/call;
- recipient account/device equality;
- authenticated transport-peer binding;
- trusted contact-device roster authority intersected with matching signed relay capability/key epoch;
- signature verification;
- ML-KEM/AES-GCM decryption failure behavior;
- expiry and maximum clock skew;
- maximum 96 KiB signal size;
- no SDP or candidate in `invite`;
- fingerprint included and authenticated in `offer`/`answer` fixtures;
- no secrets or identity values in diagnostic output.

### GREEN

- Reuse existing bridge cryptographic primitives through a new generic secure-direct-envelope seam.
- Do not call the chat-specific serializer or persist a call in `messages.wireEnvelope`.
- Keep outer cleartext to version, message ID, random call handle, expiry, crypto fields, and signature.
- Compare decrypted sender and recipient fields with transport and endpoint authority before dispatch.

### Compatibility

Old clients route unknown `call_signal` safely to unknown/no-op handling. New senders must not call an endpoint without `voice_call_v1` capability.

## 7. Incoming router and ACK semantics

### RED

- `IncomingMessageRouter` routes `call_signal` to exactly one call stream.
- Call signals do not enter chat, contact, group, post, or unknown listeners.
- A direct transport ACK does not produce a `ringing` event.
- App-level `ringing` requires successful authenticated policy validation and native-presentation/adoption result; provisional iOS CallKit reporting is not `ringing`.
- Existing router tests remain unchanged and green.

### GREEN

Add a dedicated broadcast stream and listener ownership. If durable receiver confirmation is introduced, define a call-specific confirmation reason; do not silently classify a call as ordinary chat committed ACK.

## 8. Ephemeral call mailbox

### 8.1 Storage contract

Use separate Redis keys and types from durable chat inbox:

- Hard expiration at caller-provided expiry, capped at 45 seconds for invite/pre-connect events.
- Relay-stamped receipt/expiry in every response.
- At most two pending call handles per recipient device.
- At most 64 events and 256 KiB total per call.
- Idempotency by recipient, call handle, message ID, and sender attribution.
- Atomic store, retrieve, acknowledge, cancel, expire, and endpoint revocation.
- Ten-minute replay tombstone without payload content.
- Redis process restart preserves non-expired entries and TTL.
- Expired payload is never returned or pushed.

### 8.2 TDD cases

Go RED tests cover:

- valid store/retrieve/ack;
- duplicate store exact success;
- duplicate ID with changed bytes rejection;
- wrong authenticated sender/recipient;
- malformed peer/call handle/message ID;
- over-size/capacity/rate rejection;
- expiry boundary with injected clock;
- cancel before retrieval;
- retrieve/cancel race;
- Redis process handoff;
- no fallback to in-memory success when durable backend is required;
- push issued only after committed mailbox store;
- push suppressed after expiry/cancel/ack;
- logs and metrics contain no envelope/token/identity labels.

## 9. Preferred call endpoint and wake authority

### Endpoint

A signed `call_endpoint_set_v1` record includes account/device binding, capability versions, platform, expiry, preference epoch, device-key epoch, and opaque routing handle. It is an availability/capability record, not identity or contact authorization.

The caller resolves an endpoint only when:

- the account/device exists in the accepted contact's current trusted roster;
- linked-device authority and device-key epoch are current;
- one unexpired relay record matches the same account/device/capability/key/preference epoch; and
- local contact/block policy still allows calling.

The relay stores one active preferred capability record per account, never manufactures roster authority, and never fans out. Competing updates resolve by signed epoch and exact account authority. Empty, ambiguous, stale, mismatched, unlinked, or relay-only candidates fail closed before `CallSession` creation.

### Wake handle

- Recipient device generates a random per-contact `call_wake_handle_v1`.
- Accepted sender presents it when storing an invite.
- Relay validates current authorization without learning contact display data.
- Recipient native storage maps the opaque value to local contact identity.
- Block/remove rotates or revokes it.
- It is never logged or exposed in diagnostics.
- Wake-handle and endpoint records use separate durable typed Redis state; required writes fail closed rather than succeeding in process memory.

### Token separation

- Android call capability can share the platform FCM token but has an independent capability flag.
- iOS VoIP token is stored in a separate typed field/record from standard notification token.
- iOS calling uses the PushKit/APNs VoIP path; ordinary notification registration and the Notification Service Extension never become a call-delivery fallback.
- Registration, refresh, invalid-token cleanup, and revocation tests must prove one token cannot overwrite the other.
- Required token writes and revocations are durable across process handoff; Redis failure cannot be masked by an in-memory success response.

## 10. Call history

Create a local call-history table through the normal database migration process.

Minimum fields:

- call ID;
- contact account peer ID;
- local direction;
- terminal reason/status;
- started, connected, and ended timestamps where applicable;
- duration derived locally;
- transport route class only if user diagnostics allows it;
- created/updated timestamps.

Do not store SDP, ICE, credentials, crypto material, call handle, push token, or wake handle.

Tests prove one row per call, monotonic terminal projection, missed expired invite behavior, duplicate convergence, contact scoping, and conversation timeline rendering order.

## 11. Composition and lifecycle

Wire one process-wide `CallCoordinator` after identity/contact/database readiness and before call listeners advertise capability.

- Listener registration must be idempotent.
- App resume drains call mailbox independently of chat inbox.
- App pause does not end an active call; native/media plans own active execution.
- App shutdown submits one terminal event.
- Account migration pauses endpoint publication, mailbox actions, and new invites.
- Disposal closes streams and cancels timers without touching shared chat peer connections.

Add source/composition tests rather than relying only on mocks.

## 12. Required gates

### Focused Dart

Run each new file exactly during RED/GREEN, then the complete `test/features/call/**` set.

Preservation:

- `test/core/services/incoming_message_router_test.dart`
- Existing P2P send/ACK tests.
- Existing inbox roundtrip and resume/drain tests.
- Existing contact block and linked-device authority tests.
- Existing notification token/capability tests.

### Curated

- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all` for new feature/data/application tests.
- `core-host-all` only if shared core changes justify it.

### Go

- Exact new mailbox/endpoint/wake tests.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-relay-server`.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-mknoon`.
- Race detector for the new mailbox/registry packages when supported.

No full `host-all` is required until Wave C closure.

## 13. Acceptance criteria

- One Dart-owned state machine passes every transition/race/expiry case with fake time; native lifecycle plans later add only the bounded pre-start handoff record.
- Direct, relay, mailbox, and duplicate wake paths converge on one session.
- Call signaling is signed, encrypted, device-targeted, size-bounded, replay-protected, and versioned.
- `invite` has no SDP; transport ACK never means ringing.
- Ephemeral mailbox enforces hard 45-second expiry, bounded capacity, Redis durability, sender attribution, and rate limits.
- One preferred endpoint is resolved only from the trusted-roster/relay-capability intersection; relay-only authority and multi-device fanout cannot occur.
- Android call capability and durable iOS VoIP token records cannot overwrite ordinary notification registration, and required call-state writes never fail open to memory.
- One local history row is projected per terminal call.
- Existing chat, inbox, push, identity, and migration behavior remains green.
- Feature flags remain default off and no real microphone/native call UI is active.
