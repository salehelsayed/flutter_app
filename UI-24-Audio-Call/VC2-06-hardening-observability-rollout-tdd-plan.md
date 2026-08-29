# VC2-06 — Voice Calling Hardening, Observability, and Rollout TDD Plan

**Status:** Proposed  
**Depends on:** VC2-03 and every platform plan enabled for beta  
**Primary outcome:** Voice calling meets privacy, recovery, abuse, performance, resource, operational, rollout, and rollback requirements for a bounded beta.

## 1. Scope

### In scope

- ICE restart and network-transition reliability.
- Always-relay IP privacy proof.
- Security, fuzz, replay, malformed input, and trust-boundary testing.
- Relay/TURN invitation, credential, allocation, rate, quota, and load controls.
- Privacy-safe local diagnostics and operational metrics.
- One-way-audio and failed-setup classification.
- 100+ repeated-call resource/leak testing.
- Feature flags, cohort canary, kill switch, release runbook, support diagnostics, and rollback drill.
- Final cross-wave preservation gates and evidence package.

### Out of scope

- New calling capabilities, video, groups, call waiting, cross-device handoff, recording, and broad public launch.

## 2. Hardening invariants

1. No recovery path creates a second call session, PeerConnection, native call, or TURN allocation.
2. Network transitions use a bounded ICE generation and one serialized state owner.
3. Always-relay mode neither signals nor selects host/server-reflexive candidates.
4. No metric, trace, log, crash event, artifact, or support export contains identity, token, credential, SDP, candidate address, call-wake handle, or audio.
5. Rate limits and quotas fail closed without damaging chat/inbox/push service.
6. Every malformed or adversarial input is bounded before expensive work where possible.
7. Every terminal/failure path returns resources to an explicit allowed baseline.
8. The kill switch prevents new call setup independently by platform/path while preserving messaging.
9. Beta enablement requires evidence, not only code or successful happy-path demos.

## 3. Proposed new surfaces

- `lib/features/call/application/call_recovery_policy.dart`
- `lib/features/call/application/call_failure_classifier.dart`
- `lib/features/call/application/call_diagnostics_controller.dart`
- `lib/features/call/domain/call_diagnostics_snapshot.dart`
- `lib/features/call/presentation/screens/call_diagnostics_screen.dart`
- `lib/features/call/infrastructure/call_resource_census.dart`
- `test/features/call/security/`
- `test/features/call/performance/`
- `test/features/call/integration/call_network_transition_test.dart`
- `test/features/call/integration/call_repeated_cleanup_test.dart`
- `go-relay-server/call_rate_limit.go` and focused tests if not completed in VC2-02.
- `go-relay-server/call_metrics.go` and tests.
- `go-relay-server/docs/call-operations.md`.
- `scripts/test/run_voice_call_matrix.sh` or equivalent harness using explicit target IDs.
- `scripts/test/voice_call_privacy_audit.py`.
- `scripts/test/voice_call_resource_audit.py`.

Scripts must redact sensitive values and emit deterministic machine-readable summaries.

## 4. Network transition and ICE restart

### RED matrix

1. Wi-Fi to mobile while connected.
2. Mobile to Wi-Fi while connected.
3. Temporary packet loss under reconnect threshold.
4. Interface disappears during offer/answer.
5. Interface changes during ICE restart.
6. Duplicate native/network callbacks.
7. Old-generation candidates arriving after restart.
8. Remote restart collision.
9. TURN credential near expiry during restart.
10. Direct route lost and TURN becomes required.
11. Always-relay restart cannot fall back to direct.
12. Reconnect exceeds 15 seconds and ends once.
13. Call remains healthy beyond one TURN credential TTL.
14. Credential service fails while current media is healthy, then while a new allocation is required.
15. Shared-secret overlap/blue-green/drain rotation and rollback with already issued credentials.

### GREEN contract

- Debounce interface changes into one coordinator event.
- Increment `ice_generation` exactly once per accepted restart.
- Install a staged unexpired TURN bundle if required before creating the new offer; test PeerConnection ICE-server reconfiguration and allocation refresh/recreation behavior.
- Authenticate restart offer/answer and fingerprint through encrypted signaling.
- Discard old-generation candidates and selected-pair reports.
- Keep UI in `reconnecting` for at most 15 seconds.
- Preserve mute and requested route where still supported.
- On failure, run shared cleanup and classify `reconnect_failed`.
- A healthy current route may continue during bounded credential-mint retries. A required new TURN allocation without valid credentials remains reconnecting only within budget, then fails; **Always relay** never downgrades to direct.

Do not migrate a stable call solely to save TURN bandwidth.

## 5. Always-relay privacy audit

A passing `iceTransportPolicy = relay` setting is necessary but not sufficient.

Automated proof must inspect:

- outbound offer/answer fixtures;
- every outbound candidate batch;
- candidate filter rejection counters;
- selected candidate pair class;
- packet-capture or controlled peer observation where feasible;
- route diagnostics and logs.

Pass conditions:

- no host candidate leaves the adapter;
- no server-reflexive candidate leaves the adapter;
- selected local and remote pair are relay class;
- failure to obtain relay candidates ends explicitly;
- no silent direct fallback after ICE restart;
- normal logs/artifacts contain no candidate addresses.

The audit stores only candidate classes and pass/fail assertions; raw addresses/SDP are transient and excluded from artifacts.

## 6. Security and adversarial tests

### Signaling

- Forged signature, ciphertext, nonce, sender, recipient, device binding, sequence, event type, and fingerprint.
- Unknown/duplicate fields in strict readers.
- Truncated, deeply nested, oversized, invalid UTF-8/base64, and decompression-style payload abuse where applicable.
- Replay before/after terminal tombstone.
- Expiry and clock-skew boundaries.
- Glare manipulation and sequence wrap/overflow.
- Candidate batch overflow and malicious SDP corpus.

### Mailbox/endpoint/wake

- Unauthorized store/retrieve/cancel/ack.
- Wake handle from removed/blocked contact.
- Endpoint preference rollback or stale signed epoch.
- Relay endpoint record absent from the trusted contact-device roster, roster device absent from relay capability state, mismatched key/capability epoch, and ambiguous intersection.
- Token type confusion between standard and VoIP token.
- Redis restart, partial failure, and stale replica/process handoff.
- Required call mailbox/endpoint/wake/VoIP-token write failure cannot report in-memory success.
- Push attempted before durable mailbox commit.
- Push retry after expiry.

### TURN

- Forged, expired, replayed, and over-rate credentials.
- Credential mint amplification.
- Allocation quota exhaustion and stale cleanup.
- Unsupported transport and malformed Allocate requests.
- Static shared secret absent from app, API responses, logs, crash reports, and repository.
- Isolation between call feature disablement and existing relay functions.
- Call beyond credential TTL and allocation refresh/recreation behavior.
- Credential-service outage with healthy current allocation versus required new allocation.
- Shared-secret overlap/blue-green/drain rotation, issued-credential validity, and rollback.

### Native

- Malformed platform-channel events and Intent/APNs payloads.
- Duplicate action/re-entrant callback.
- Exported-component and mutable-PendingIntent review on Android.
- Entitlement/token/topic separation on iOS.
- Locked-device privacy and screenshot/notification content review.

Use fuzz/property tests where deterministic and bounded; preserve minimized regression fixtures for every discovered crash or policy bypass.

## 7. Abuse controls

### Relay call invitation limits

Define separate configurable limits for:

- invitations per authenticated sender per minute/hour;
- invitations to one recipient per sender;
- concurrent pending calls per recipient device;
- mailbox bytes/events;
- endpoint updates and wake-handle failures;
- VoIP/FCM push attempts and retry budget;
- TURN credential minting and concurrent allocations.

Application contact/block policy remains the first product gate. Relay limits are metadata-minimized infrastructure defense, not a replacement for contact authorization.

### Required behavior

- Reject with stable coarse reason and retry-after where safe.
- Never reveal block/contact relationship.
- Do not create mailbox entry or push on rejected admission.
- Metrics use bounded reason labels with no identity dimensions.
- Operators can disable call admission independently of chat inbox/push.

## 8. Observability and diagnostics

### Local diagnostic snapshot

Allowed fields:

- call state;
- coarse terminal/failure reason;
- signaling path class;
- selected route class;
- ICE/DTLS/audio readiness states;
- retry/restart counts;
- timing buckets;
- mute/requested audio route;
- cleanup/resource counters.

Forbidden fields:

- peer/contact/device identifiers;
- call/message/opaque handles;
- SDP/candidate values or IP addresses;
- keys, tokens, credentials, ciphertext;
- audio samples or speech-derived data.

Support export is opt-in, previewable, redacted, bounded, and expires locally.

### Relay/TURN metrics

- admission outcome by bounded reason;
- mailbox store/retrieve/expire/cancel totals;
- push attempt/outcome by platform and bounded reason;
- credential mint/reject totals;
- current TURN allocations and bandwidth buckets;
- allocation auth failures, quota rejection, stale cleanup;
- invite-to-wake and store-to-retrieve histograms.

No high-cardinality identity/call labels.

### Alerts

At minimum:

- TURN allocation/auth failure spike;
- TLS certificate expiry;
- relay allocation port exhaustion;
- call mailbox durable backend unavailable;
- push provider rejection spike;
- stale allocation/mailbox cleanup failure;
- abnormal invite/wake rate;
- call setup/drop regression after rollout change.

## 9. Performance and quality budgets

Measure under named, repeatable topologies and available devices.

Targets from PRD:

- foreground invite-to-ring p95 <= 2 seconds;
- background/locked invite-to-ring p95 <= 5 seconds;
- accept-to-two-way-audio p95 <= 3 seconds;
- reconnecting UI <= 3 seconds after media loss;
- reconnect window <= 15 seconds.

Also record:

- setup success by route class;
- one-way-audio rate;
- unexpected drop rate;
- ICE restart success;
- TURN bandwidth per duration bucket;
- battery/thermal warning observations on repeated calls.

A sample size and device/network topology accompanies every percentile. Do not publish p95 from an insufficient or mixed, unnamed sample.

## 10. One-way-audio detection

One-way-audio classification runs only after product `connected`; connection itself uses transport and sender/receiver-track readiness and never waits for audio bytes or energy.

Detection uses bounded WebRTC statistics and peer health signals, not recorded content:

- selected pair and DTLS remain connected;
- expected sender/receiver tracks remain live;
- RTP/RTCP packet and loss/jitter counters are evaluated over a stable bounded window;
- zero energy or sparse bytes alone are inconclusive because silence, mute, and DTX are valid;
- automated two-way proof injects a known non-speech test signal, while production classification requires corroborating sender-active/receiver-missing evidence or reports `insufficient_signal` rather than a false one-way failure.

Silence alone never triggers reconnect or failure. User-facing behavior is a generic audio-problem indication only after corroborated evidence. Diagnostic metrics report only direction class and coarse reason.

## 11. Resource census and 100+ call loop

Define baseline and allowed delta before running.

Track where available:

- Dart CallCoordinator/session/timer/subscription counts;
- PeerConnections, senders, receivers, tracks, candidate buffers, stats timers;
- Go call-specific streams/goroutines and mailbox operations;
- Android native calls, services, notifications, receivers, wake locks, audio focus;
- iOS CallKit calls, providers/controllers, pending descriptors, audio sessions;
- process file descriptors and memory trend;
- coturn allocations and relay bandwidth sessions.

Run at least 100 mixed calls covering:

- direct, TURN/UDP, TURN/TCP-TLS, and always-relay;
- answer, decline, cancel, no-answer, media failure, reconnect success/failure;
- foreground and available native lifecycle states;
- duplicate and delayed signaling/push;
- process restart cases.

Pass only if:

- every iteration reaches a terminal assertion;
- resource counts return within predeclared deltas;
- no monotonic memory/FD/allocation growth remains unexplained;
- no stale native call/notification/mailbox/TURN allocation survives its bound;
- chat send/receive still works after the loop.

## 12. Feature flags and rollout

### Gates

- capability advertisement;
- outgoing calls;
- incoming calls;
- TURN;
- Android native lifecycle;
- iOS native lifecycle;
- Always relay;
- diagnostics;
- global kill switch.

Every flag defaults off for unsupported/unknown configurations and is testable without a server response.

### Canary sequence

1. Maintainer devices.
2. Internal Android foreground pair.
3. Internal Android/iOS foreground parity.
4. Android native lifecycle canary.
5. iOS physical-device PushKit/CallKit canary.
6. Small opted-in beta subset.
7. Increase only after predefined observation window and success/error thresholds.

Do not expose the phone action to a contact/device without compatible endpoint capability.

### Rollback triggers

Immediate disablement for:

- late/duplicate rings;
- privacy leak;
- static/exposed credential;
- repeated crash or stuck native call;
- material chat/push regression;
- elevated setup/drop/one-way-audio rate;
- TURN/relay overload or abuse;
- App Store/Play policy issue.

Rollback disables new calls first, then platform/route components independently. Existing chat, standard notifications, and history remain available.

## 13. Operations and support runbook

Document and drill:

- feature-flag and kill-switch procedure;
- coturn/relay restart independence;
- TURN REST-secret overlap/blue-green/drain rotation, issued-credential validity, credential-service outage, and APNs credential rotation;
- TLS renewal;
- allocation/mailbox cleanup;
- quota adjustment with safe ceilings;
- alert ownership/escalation;
- privacy-safe support diagnostics;
- beta incident triage by coarse failure reason;
- rollback and recovery verification;
- post-incident evidence retention/deletion.

No runbook includes live secrets or commands that print them.

## 14. Required gates

### Focused

- Exact security, privacy, recovery, metrics, rate, performance, and cleanup tests added by this plan.
- Exact regression fixture for every discovered issue.

### Family/curated

- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all`
- `./scripts/run_host_test_gates.sh core-host-all` when shared core changes justify it.
- Performance family for call performance paths.
- Full Go suites in changed modules.
- Android JVM/instrumentation and iOS RunnerTests/physical-device suites for enabled platforms.

### Final rollout closure

After all focused and affected gates pass:

- Full `host-all` once.
- Complete available-device/network matrix.
- 100+ repeated-call resource run.
- Forced-relay privacy audit.
- TURN UDP/TCP/TLS and expiry/cleanup proof.
- Kill-switch/rollback drill.

## 15. Multica and evidence

Before changing rollout status:

- Record exact enabled platform/cohort and feature flags.
- Link RED/GREEN/preservation/device/network/resource evidence.
- Record unavailable targets as `N/A (target unavailable by project policy)`.
- Record unresolved risks as blockers; do not convert them to assumptions.
- Read back issue status after every write.

## 16. Acceptance criteria

- Network transitions recover or end cleanly within budgets without duplicate sessions.
- Always-relay privacy audit proves no direct candidate egress/selection.
- Security/fuzz/replay/abuse tests fail closed and preserve service availability.
- Call/relay/TURN diagnostics are useful and contain no forbidden data.
- Alerts, quotas, secret rotation, TLS renewal, cleanup, and rollback are operationally owned and tested.
- Long calls, allocation refresh/recreation, ICE restart, credential-mint outage, and REST-secret rotation preserve the declared call/privacy behavior.
- 100+ mixed calls return all measured resources to declared baselines and leave chat functional.
- Platform-specific foreground/background/terminated/locked matrices pass on available required targets.
- Final full host, Go, native, device, network, privacy, and performance gates pass.
- Canary thresholds and observation window pass before cohort expansion.
- Kill switch is proven to stop new calls without breaking chat or standard notifications.
- No acceptance item is inferred from an open port, a UI state, a plan document, or unverified self-report.
