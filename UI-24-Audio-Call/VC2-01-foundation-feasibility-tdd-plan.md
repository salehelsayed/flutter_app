# VC2-01 — Voice Calling Foundation and Feasibility TDD Plan

**Status:** Proposed  
**Depends on:** PRD v2 approval  
**Blocks:** VC2-02 through VC2-06  
**Primary outcome:** WebRTC builds on supported targets and the existing coturn deployment provides proven short-lived authenticated UDP/TCP/TLS relay service.

## 1. Why this plan exists

Current source has no Flutter WebRTC integration. The verified 2026-08-29 relay baseline has Redis durability and coturn `4.6.3`; UDP STUN works on `3478`, TCP reaches an authentication challenge, and static credentials remain configured. REST-secret issuance/rotation, allocation limits, authenticated relayed media, UDP-blocked TURN/TCP, TURN/TLS on `443`, forced-relay privacy, cleanup, and monitoring are unproved. An open port, STUN response, or authentication challenge is not a production-readiness claim. Building call-control code before these risks are retired would create an unverified architecture dependency.

This plan is complete only when both the client package boundary and production TURN path are exercised.

## 2. Scope

### In scope

- Select and pin the WebRTC Flutter dependency.
- Add a narrow, fakeable CallEngine interface and disabled production adapter seam.
- Prove Android and iOS compilation without exposing call UI.
- Replace app-facing static coturn credentials with short-lived REST credentials.
- Add authenticated `turn_credentials_v1` relay action.
- Configure and prove TURN/UDP, TURN/TCP, and TURN/TLS on 443 or the approved equivalent.
- Define relay allocation port range, firewall, quotas, monitoring, and rollback.
- Add default-off capability and rollout flags.

### Out of scope

- Call state machine, call mailbox, call UI, microphone capture, PushKit, CallKit, Telecom, and beta rollout.

## 3. Existing surfaces to preserve

- `pubspec.yaml`
- `lib/core/bridge/go_bridge_client.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/inbox.go`
- `go-relay-server/main.go`
- `go-relay-server/inbox.go`
- Existing relay metrics and Redis durability.
- Existing standard push-token registration and notification capabilities.

## 4. Proposed new surfaces

Names are proposed; implementation may adjust only with documented evidence.

- `lib/features/call/domain/call_engine.dart`
- `lib/features/call/infrastructure/flutter_webrtc_call_engine.dart`
- `lib/features/call/infrastructure/webrtc_types.dart`
- `lib/features/call/application/voice_call_feature_flags.dart`
- `test/features/call/domain/call_engine_contract_test.dart`
- `test/features/call/infrastructure/flutter_webrtc_build_contract_test.dart`
- `go-relay-server/turn_credentials.go`
- `go-relay-server/turn_credentials_test.go`
- `go-relay-server/turn_credentials_process_integration_test.go`
- `go-mknoon/node/turn_credentials_test.go`
- `go-mknoon/bridge/turn_credentials_bridge_test.go`
- `go-relay-server/docs/turn-operations.md`
- `scripts/test/voice_call_turn_probe.py`

No credential or shared secret may be committed to these files.

## 5. Contract to freeze

### 5.1 CallEngine boundary

The domain/application layer may depend only on a small interface that can:

- create/close an audio-only connection;
- create/set offer and answer;
- add/batch ICE candidates;
- restart ICE;
- enable/disable local audio;
- select supported output routes;
- expose bounded state and privacy-safe statistics events.

Plugin objects, SDP library types, and native handles must not escape the infrastructure adapter.

### 5.2 TURN credential response

`turn_credentials_v1` returns:

- schema/version;
- non-identifying expiry-bound username;
- generated password;
- `ttl_seconds`;
- ordered ICE server URLs;
- server time for skew handling.

It returns no coturn shared secret, static password, peer list, call metadata, or addresses beyond configured ICE server URLs.

Credentials:

- expire after ten minutes;
- are minted only for an authenticated peer;
- are rate-limited;
- are accepted by coturn REST authentication;
- are never logged or persisted in plaintext;
- refresh only while an active or reconnecting call requests them;
- do not define the maximum call duration;
- are prefetched and staged before 70% of lifetime for future allocation refresh/recreation or ICE restart;
- never force a healthy selected pair to migrate only because authentication material aged;
- never permit a static-credential fallback or a direct fallback from **Always relay**.

The frozen lifecycle contract must also define and test:

- whether the chosen coturn configuration accepts allocation refresh after the credential timestamp expires—do not assume it does;
- replacement of the PeerConnection ICE-server configuration before a new allocation or restart;
- bounded retry while current media is healthy when credential minting is unavailable;
- reconnect failure after 15 seconds when a required new allocation cannot obtain valid credentials;
- coordinated shared-secret overlap, blue/green, or drain so issued credentials remain valid through their advertised TTL or are replaced before cutover;
- release/zeroization of superseded credentials and privacy-safe outage/rotation metrics.

## 6. TDD slices

### Slice A — Dependency and adapter boundary

**RED**

1. Add a contract test that imports the proposed CallEngine but fails because it does not exist.
2. Add source/boundary assertions proving call domain code cannot import `flutter_webrtc`.
3. Add tests for adapter disposal idempotency and bounded event streams using a fake plugin facade.

**GREEN**

1. Pin a compatible `flutter_webrtc` version.
2. Implement the interface and minimal adapter without wiring app behavior.
3. Construct and close an audio-only PeerConnection with no media capture in a controlled probe.
4. Keep every feature flag false by default.

**REFACTOR**

- Isolate plugin data conversion and redact SDP/candidates from logs.

### Slice B — Credential grammar and authentication

**RED**

Go tests must fail for:

- unauthenticated request;
- malformed request;
- over-rate request;
- expired username;
- forged password;
- wrong shared secret;
- clock skew outside tolerance;
- long-call replacement requested before 70% lifetime;
- restart rejected when only an expired bundle is available;
- bounded minting outage without static fallback;
- old/new shared-secret cutover and rollback behavior;
- response containing a secret/loggable credential field.

**GREEN**

- Implement coturn REST HMAC credential derivation behind an injected clock and secret provider.
- Add relay action, Go-node client, and bridge JSON contract.
- Zero temporary secret buffers where practical and redact logs.

**REFACTOR**

- Keep credential code independent from call state and push registration.

### Slice C — Deployment and real allocation

**RED evidence**

Capture the current expected failures without exposing credentials:

- no authenticated allocation proof;
- no TURN/TLS listener proof;
- no forced relay candidate;
- no allocation-port/firewall proof.

**GREEN**

1. Configure coturn REST shared-secret mode and rotate away from static app use.
2. Configure realm, TLS certificate, approved 443 routing, and explicit relay port range.
3. Open only required cloud/host firewall ports.
4. Mint a credential through authenticated relay action.
5. Prove allocation and relayed traffic over UDP.
6. Block UDP and prove TCP/TLS relay.
7. Wait/advance time and prove expired credentials fail and allocations clean up.
8. Keep a controlled call active beyond one credential TTL and prove the specified allocation-refresh/recreation behavior.
9. Prove ICE restart uses a staged unexpired bundle; a required restart fails cleanly when minting remains unavailable.
10. Exercise the chosen shared-secret overlap/blue-green/drain rotation and rollback without breaking issued-credential guarantees.
11. Record coarse metrics only.

### Slice D — Build and target compatibility

- Build Android debug artifact with the WebRTC dependency.
- Build iOS simulator artifact without code signing.
- Run on one available Android target and one available iOS simulator to create/close the probe connection.
- A physical iPhone is not required until VC2-05.

### Slice E — Operations and rollback

- Document DNS, ports, certificate renewal, long-call credential lifecycle, credential-service outage, secret overlap/blue-green/drain rotation, quotas, metrics, alerts, allocation cleanup, and rollback.
- Prove relay-server restart and coturn restart are independent.
- Prove disabling TURN credentials leaves existing chat relay and push intact.

## 7. Required tests

### Focused Dart

- `flutter test test/features/call/domain/call_engine_contract_test.dart`
- `flutter test test/features/call/infrastructure/flutter_webrtc_build_contract_test.dart`

### Go

- Exact new TURN credential tests first.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-relay-server`.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-mknoon`.

### Builds

- `flutter build apk --debug`
- `flutter build ios --simulator --no-codesign`

### Preservation

- Existing relay metrics/durability tests.
- Existing push-token registration tests.
- Existing Go bridge JSON compatibility tests.
- `./scripts/run_host_test_gates.sh 1to1` if shared bridge or inbox surfaces change.

Do not run full `host-all` solely for this plan.

## 8. Live proof requirements

The TURN probe must report only:

- protocol attempted;
- authentication accepted/rejected;
- candidate class;
- bytes relayed;
- expiry/cleanup outcome;
- listener/certificate identity;
- duration and coarse failure reason.

It must not print usernames, passwords, shared secrets, tokens, Peer IDs, IP candidates, or SDP.

Required cases:

1. UDP allocation and relayed packet.
2. TCP allocation and relayed packet.
3. TLS allocation on approved 443 path.
4. Forged credential rejected.
5. Expired credential rejected.
6. Allocation disappears after refresh/permission lifetime.
7. Rate and quota rejection is observable.
8. A call remains healthy beyond credential TTL according to the frozen allocation contract.
9. A new allocation/ICE restart uses staged unexpired credentials and fails closed when minting cannot recover within budget.
10. Shared-secret rotation and rollback preserve the advertised validity contract for already issued credentials.

## 9. Acceptance criteria

- WebRTC dependency resolves and builds for supported Android and iOS targets.
- Domain/app code has a fakeable plugin-independent CallEngine boundary.
- No microphone starts and no call UI is exposed.
- Authenticated relay action mints short-lived credentials accepted by coturn.
- UDP, TCP, and TLS relay paths carry real test traffic.
- App ships no static TURN secret or password.
- Relay allocation range, firewall, DNS/TLS, quotas, metrics, long-call behavior, allocation refresh/recreation, minting outage, shared-secret rotation, and rollback are documented and verified.
- Existing libp2p relay, inbox, push, and bridge tests remain green.
- Feature flags remain default off.

## 10. Blockers and stop conditions

Mark the plan blocked rather than bypassing if:

- `flutter_webrtc` cannot build against current Flutter/native toolchains;
- TURN/TLS 443 cannot be safely routed;
- cloud firewall access is unavailable;
- authenticated credentials cannot be minted without exposing a shared secret;
- an existing chat/push relay preservation test regresses.

Do not substitute a STUN response, open socket, or unauthenticated 401 challenge for a completed TURN proof.
