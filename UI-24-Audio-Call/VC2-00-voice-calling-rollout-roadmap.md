# VC2-00 — Mknoon Voice Calling Rollout Roadmap

**Status:** Proposed execution roadmap  
**PRD authority:** `mknoon_1to1_voice_calling_prd_v2.md`  
**Tracking:** Multica `SE-11`  
**Scope:** Audio-only 1-to-1 calling; Android and iOS

## 1. Purpose

This roadmap converts PRD v2 into six independently verifiable delivery plans. It is a sequencing and closure contract, not evidence that calling is implemented.

Where the old `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00..09` plans conflict with PRD v2, this roadmap wins. In particular:

- Keep the deployed coturn process; do not embed Pion TURN in the Go relay.
- Encrypt and authenticate call signaling; do not accept application-layer plaintext.
- Use an ephemeral call mailbox for background/terminated delivery; do not rely on fast-path-only signaling.
- Use Android Telecom/Core-Telecom and iOS PushKit/CallKit for external beta closure.
- Keep canonical call state in Dart after runtime attachment; native code may hold only the bounded pre-start record required by Telecom/CallKit and must reconcile it deterministically.

## 2. Baseline

At roadmap start:

- No production call feature, WebRTC dependency, call tests, CallKit/PushKit, or Android Telecom implementation exists.
- Existing libp2p messaging, encrypted envelopes, inbox recovery, push plumbing, permissions, and audio-note code are reusable but must not be called a call stack.
- Live `relay-server v1.9.0` and coturn exist.
- STUN responds and coturn currently exposes static-credential service on `3478`, but REST-secret minting/rotation, authenticated TURN allocation, relay candidates, TCP/TLS media, TLS/443, allocation limits, forced-relay privacy, credential lifecycle, allocation ports, and load are unproved.
- Generic inbox retention and strict chat custody do not satisfy the 45-second call mailbox contract.

## 3. Dependency graph

```text
VC2-01 Foundation + TURN proof
       |
       v
VC2-02 Call control + encrypted signaling + ephemeral mailbox
       |
       v
VC2-03 Foreground WebRTC audio
       |
       +--------------------+
       v                    v
VC2-04 Android native       VC2-05 iOS native
       +--------------------+
                 |
                 v
VC2-06 Hardening + observability + beta rollout
```

VC2-04 and VC2-05 may proceed in parallel only after VC2-03's foreground call contract and platform adapter interface are frozen.

## 4. Plans and outcomes

| Plan | Outcome | Primary proof |
|---|---|---|
| `VC2-01` | WebRTC builds; coturn has short-lived credentials, explicit long-call/rotation behavior, and proven UDP/TCP/TLS relay | Android/iOS build probes plus real authenticated TURN allocation, expiry/restart/outage/rotation proof |
| `VC2-02` | Deterministic Dart state machine and encrypted direct/mailbox signaling | Fake-clock transition suite, roster/capability endpoint intersection, relay TTL/restart/fail-closed tests, duplicate-path convergence |
| `VC2-03` | Foreground audio chooses direct or TURN correctly and connects without requiring audible bytes | Two Android peers; silent-peer readiness, controlled two-way signal, direct, forced TURN/UDP, UDP-blocked TCP/TLS, route diagnostics |
| `VC2-04` | Android rings and operates correctly in background/terminated/locked states | USB Android plus emulator; Telecom, bounded pre-Dart record/reconciliation, CallStyle, permissions, duplicate/stale push |
| `VC2-05` | iOS rings and operates correctly through PushKit/CallKit | Physical iPhone plus peer; VoIP token, prompt CallKit report/callback completion, bounded pre-Dart reconciliation, actions, audio activation |
| `VC2-06` | Privacy, recovery, metrics, abuse controls, leak proof, canary and rollback | 100+ mixed calls, network transitions, relay-only leak proof, bounded beta metrics |

## 5. Global implementation rules

1. **One canonical state owner after attachment:** Dart `CallCoordinator` owns product state after startup. Native may persist only one bounded pre-start record and ordered actions, then hand them to Dart exactly once with terminal precedence and acknowledgement.
2. **No chat semantic reuse:** cryptographic primitives and transport may be reused; durable chat retry/state must not carry call events. Call mailbox, endpoint, wake, and VoIP-token records use separate durable typed storage and never report fail-open in-memory success.
3. **No static TURN secret:** TURN credentials are short-lived and minted server-side before TURN beta use; long calls, allocation refresh/recreation, ICE restart, minting outage, and shared-secret rotation have explicit tested behavior.
4. **Push is not signaling truth:** direct and mailbox envelopes are authoritative; push only wakes/presents.
5. **No relay-only endpoint authority:** resolve one preferred endpoint by intersecting Mknoon's trusted contact-device roster with the current signed relay capability record; never fan out.
6. **No early application Ringing:** transport ACK and provisional iOS CallKit reporting are not application `ringing`; emit it only after authenticated policy validation and successful native presentation/adoption.
7. **No early microphone:** capture starts only after user acceptance, Dart adoption, and native audio activation.
8. **Silence-safe Connected:** use ICE/DTLS/native-audio/sender/receiver-track readiness, not observed audio bytes or energy. Detect one-way audio separately.
9. **One cleanup path:** every terminal reason converges on the same idempotent Dart/native routine.
10. **Fail closed:** unsupported capability, wrong/unauthorized device, invalid signature, stale invite, durable-store failure, or malformed SDP cannot emit application `ringing` or allocate media.
11. **Dedicated iOS call path:** use distinct durable PushKit VoIP tokens and APNs VoIP delivery, never ordinary iOS notifications or the Notification Service Extension.
12. **Preserve messaging:** call changes may not weaken existing chat, inbox, push, voice-note, or account-migration invariants.

## 6. Work waves

### Wave A — Feasibility and trust boundary

Plan: `VC2-01`

Required before downstream implementation:

- `flutter_webrtc` resolves and builds for current Android and iOS targets.
- A narrow CallEngine abstraction hides plugin APIs from domain tests.
- Coturn uses short-lived REST credentials; no app static credential.
- Real TURN relay candidates are proven over UDP and TCP/TLS.
- Calls longer than the credential TTL, allocation refresh/recreation, ICE restart, credential-service failure, and coordinated REST-secret rotation are proven without privacy downgrade.
- Port range, firewall, DNS/TLS route, quotas, monitoring, and rollback are documented.
- Feature flags default off.

**Stop condition:** If current Flutter/native targets cannot build the selected WebRTC package or TURN/TLS 443 cannot be operated safely, stop and revise architecture before VC2-02.

### Wave B — Deterministic control plane

Plan: `VC2-02`

- State machine and event grammar.
- Signed encrypted call envelope.
- Direct signaling adapter.
- Ephemeral Redis-backed call mailbox with hard TTL and bounded capacity.
- Opaque call wake handles, trusted-roster/relay-capability endpoint intersection, durable token separation, fail-closed Redis behavior, and rate limits.
- Local call-history projection.
- No real microphone or external incoming-call UI yet.

**Stop condition:** No call UI proceeds while duplicate paths, expiry, glare, busy, or terminal races can produce two sessions or revive an ended session.

### Wave C — Foreground media

Plan: `VC2-03`

- Audio-only PeerConnection and audio track.
- Direct-first ICE with TURN gathered concurrently.
- Mute, speaker, Bluetooth, permissions, interruption, diagnostics.
- Foreground outgoing/incoming UI.
- Direct, TURN/UDP, TCP/TLS, and relay-only proof.
- Transport/track-based `connected` readiness for a silent peer; controlled two-way-audio and separate one-way-audio diagnostics.

**Milestone:** Internal foreground demo only. It is not external-beta completion.

### Wave D — Native lifecycle

Plans: `VC2-04`, `VC2-05`

Android and iOS share the Dart contract but own separate native acceptance evidence. One platform may be enabled while the other remains gated off.

Both platforms implement the same bounded native pre-start record, monotonic event sequence, ordered Dart handoff, terminal precedence, adoption acknowledgement, and exactly-once native cleanup. iOS additionally proves that the PushKit callback completes from the CallKit report completion without waiting for Flutter, Go, network connection, or mailbox retrieval.

**Stop condition:** A platform cannot enter external beta until foreground, background, terminated, and locked states pass on available target hardware for that platform.

### Wave E — Hardening and rollout

Plan: `VC2-06`

- Network transition and ICE restart.
- Always-relay privacy verification.
- Security, malformed input, abuse, load, and resource leaks.
- Privacy-safe diagnostics and operational alerts.
- Canary flags, kill switch, rollback, on-call runbook, and beta cohort.

## 7. TDD and gate cadence

Every plan uses RED → GREEN → REFACTOR and records exact commands and artifacts.

Per-plan closure runs:

1. Focused causal tests for files changed by that plan.
2. Exact preservation sentinels named in the plan.
3. The affected curated `1to1` lane where applicable.
4. Only the justified `core-host-all`, `feature-host-all`, native, relay, or performance family for changed surfaces.

Do not run full `host-all` as a default per-plan gate.

Run full `host-all`:

- Once after Wave C completes.
- Once after both enabled native platform plans complete.
- Once at final external-beta closure.

New call tests must be registered in the applicable curated gate without converting every plan into a full-suite obligation.

## 8. Required gate families

### Dart/Flutter

- Exact new `test/features/call/**` paths.
- Existing `test/core/services/incoming_message_router_test.dart` preservation.
- Existing 1-to-1 send/inbox/resume/push preservation tests.
- `./scripts/run_host_test_gates.sh 1to1` after coherent control-plane changes.
- `./scripts/run_host_test_gates.sh feature-host-all` for call feature/UI work.
- `./scripts/run_host_test_gates.sh core-host-all` only when shared core surfaces change.

### Go/libp2p and relay

- Exact Go test names during RED/GREEN.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in each changed Go module at plan closure.
- Redis process-handoff tests for call mailbox and endpoint/token state.
- Redis-unavailable tests proving no in-memory success for required call custody, endpoint, wake, or VoIP-token writes.
- Trusted contact-device roster and relay capability intersection tests.
- Race detector for new concurrent relay components when supported.

### Native

- Android JVM/Robolectric tests under `android/app/src/test`.
- Dedicated Android instrumentation source set only for behavior requiring a device.
- iOS `RunnerTests` on an available simulator for host-testable CallKit/token/state adapters.
- Physical iPhone proof for PushKit delivery and killed/locked CallKit behavior.
- Native pre-start answer/end/cancel/expiry, ordered handoff, process recreation, terminal precedence, and exactly-once cleanup tests on both platforms.
- iOS callback-order proof that CallKit reporting completes PushKit before runtime/network validation finishes.

### Real network/media

- Pin every command to a discovered target ID.
- Record selected ICE pair class without recording addresses.
- Force direct failure and UDP failure independently.
- Prove TURN allocation expiry and cleanup.
- Prove a call beyond credential TTL, allocation refresh/recreation behavior, ICE restart with staged credentials, minting outage, and shared-secret rotation/rollback.

## 9. Available-device policy

Resolve the matrix at execution time with:

- `flutter devices --machine`
- `adb devices`
- `xcrun simctl list devices available`

For non-iOS-specific two-peer behavior, use one USB Android device plus an available Android emulator. Use a physical iPhone only for iOS-specific PushKit/CallKit or explicit Android/iOS parity. Unavailable OS versions are `N/A (target unavailable by project policy)`, not blockers.

## 10. Evidence contract

Each plan must leave:

- RED output proving the new behavior was absent or wrong.
- GREEN output for exact causal tests.
- Preservation-gate output.
- Device IDs and topology, without credentials or personal identifiers.
- Coarse ICE route and timing summaries.
- Relay/TURN deployment version and listener summary with secrets redacted.
- Resource-baseline deltas for leak work.
- Multica comment containing decisions, evidence paths, blockers, and status.

A successful command without a read-back or behavioral assertion is not completion.

## 11. Rollback boundaries

- Every platform and capability has a default-off feature flag.
- Relay actions are additive and old clients/relays fail closed or degrade to call unavailable.
- Coturn credential changes can roll back independently from libp2p relay service.
- REST-secret rotation uses tested overlap/blue-green/drain behavior; an uncoordinated cutover that invalidates issued credentials is not an allowed rollback path.
- Native call registration can be disabled without disabling standard notifications.
- Disabling calls prevents new invites but does not alter chat, inbox, push, media, or existing conversation history.

## 12. Final closure

External beta closure requires all enabled-platform PRD acceptance criteria, a final full `host-all`, native test families, relay/Go suites, real device/network matrix, 100+ mixed-call leak run, privacy review, operational alerts, kill-switch drill, and Multica evidence. Any unavailable or unverified leg remains explicitly open; it is never replaced by plausible output.
