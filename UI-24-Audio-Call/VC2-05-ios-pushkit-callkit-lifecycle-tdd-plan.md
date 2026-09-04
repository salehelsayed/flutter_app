# VC2-05 — iOS PushKit and CallKit Lifecycle TDD Plan

**Status:** Implementation complete and frozen-source automated gates green; current exact-source iPhone outgoing reaches Pixel incoming presentation and ringing, while automated Answer/connect and the remaining availability-bounded physical/release closure are pending
**Depends on:** VC2-03  
**May run parallel with:** VC2-04  
**Primary outcome:** iOS receives real VoIP pushes and presents/operates one CallKit call correctly in foreground, background, terminated, and locked states.

## 1. Current baseline

At plan authoring, iOS had:

- Standard APNs/Firebase registration and notification callbacks in `AppDelegate.swift`.
- Notification Service Extension and notification recovery plumbing.
- RunnerTests for notification, app visibility, bridge, privacy, and recovery behavior.
- Microphone usage text.

It did not have PushKit registration, a VoIP token model, CallKit provider/controller, VoIP/audio background modes for calling, CallKit audio activation, or a real incoming-call push service.

## 2. Scope

### In scope

- Distinct PushKit VoIP token registration, refresh, relay storage, invalidation, and revocation.
- Direct APNs VoIP push provider path at the relay.
- Strict opaque VoIP payload and local contact-handle resolution.
- `CXProvider`, `CXCallController`, actions, updates, end reasons, and audio activation/deactivation.
- Foreground, background, terminated, and locked-device behavior.
- Cold Flutter/Go runtime handoff with one pending native descriptor.
- iOS entitlements, background modes, provisioning requirements, RunnerTests, simulator host tests, and physical-iPhone proof.

### Out of scope

- Android, video, system Contacts exposure, PSTN, Siri intents, Call Directory, call waiting, and multi-device ringing.

## 3. Proposed native and relay surfaces

### iOS

- `ios/Runner/MknoonVoipPushRegistry.swift`
- `ios/Runner/MknoonCallKitController.swift`
- `ios/Runner/MknoonCallNativeBridge.swift`
- `ios/Runner/PendingNativeCallStore.swift`
- `ios/Runner/OpaqueCallContactResolver.swift`
- `ios/Runner/VoipPayloadParser.swift`
- Focused tests in `ios/RunnerTests/`.

Existing files likely changed:

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- Runner entitlements and Xcode project membership.
- Dart bootstrap/platform-channel composition.

### Relay

- `go-relay-server/apns_voip_push.go`
- `go-relay-server/apns_voip_push_test.go`
- VoIP-token typed storage/Redis tests, invalid-token cleanup, capability and rate-limit handling.

Do not route VoIP pushes through the Notification Service Extension. It is not the CallKit/PushKit entry point.

## 4. Token and push contract

### Separate token authority

- PushKit VoIP token is a distinct typed record from ordinary APNs/FCM token.
- It is bound to authenticated account/device identity, app environment, bundle VoIP topic, capability version, and expiry/refresh epoch.
- Updating/removing a VoIP token cannot overwrite or delete the standard notification token.
- App logout/account migration/device replacement revokes the token.
- APNs invalid-token responses remove only the exact stale VoIP token generation.
- VoIP token and call-wake state are durable typed Redis records; required writes/revocations fail closed and never report in-memory-only success.
- Ordinary iOS notifications and the Notification Service Extension are never fallback call-delivery mechanisms.

### APNs VoIP provider

- Uses approved APNs authentication and `.voip` topic.
- Sends only for a committed, current call-mailbox invite and valid wake handle.
- Uses appropriate VoIP push type/priority/expiration.
- Never logs token, payload secret, Peer ID, contact name, SDP, ICE, or TURN credential.
- Retries only retryable provider outcomes within invite expiry; stale pushes are dropped.
- Provider response is measured with coarse status categories.

No APNs key, certificate private key, team credential, or token is committed to the repository or evidence.

## 5. Opaque VoIP payload

Strict versioned payload contains only:

- schema/version;
- random call UUID/handle;
- expiry;
- opaque contact handle;
- mailbox retrieval reference or encrypted blob reference;
- no readable Peer ID, name, conversation ID, SDP, ICE address, or TURN credential.

### Native local lookup

- App maintains a protected local mapping from recipient-issued opaque contact handle to current local contact display data.
- Mapping is updated only after accepted-contact verification.
- Block/remove revokes mapping and relay authorization.
- Native may report a generic **Mknoon call** immediately if lookup is unavailable, then update CallKit after authenticated mailbox retrieval.
- Invalid/unknown/expired data ends any provisionally reported call promptly, never emits application `ringing`, and never starts media.

## 6. CallKit ownership contract

- One `CXProvider` for the process.
- One random `UUID` maps to one call handle, pending descriptor, and Dart session.
- Native reports incoming call promptly in the PushKit callback and completes the callback within the OS budget.
- Dart CallCoordinator remains canonical product-state owner after runtime attachment.
- Before attachment, native persists only one protected, versioned, bounded record containing call UUID/handle, expiry, opaque references, presentation status, monotonic event sequence, pending action/terminal reason, and handoff acknowledgement.
- CallKit actions persist as bounded native events and deliver in order exactly once after Flutter attachment.
- Native and Dart terminal requests converge on one CallKit end and one shared cleanup.

Terminal/provider-reset/authenticated-cancel/expiry events dominate pending answer or presentation. A pre-start answer is intent only: no SDP, ICE, microphone, or media starts until Dart validates/adopts the call and CallKit activates audio. Dart acknowledges the highest consumed native sequence plus adoption/terminal cleanup; native deletes the record exactly once and replays only unacknowledged events after process recreation.

Supported actions:

- answer;
- end/decline;
- mute;
- audio activated;
- audio deactivated;
- provider reset;
- route/interruption notification;
- remote cancel/update.

## 7. PushKit and payload RED tests

Host-testable tests fail until:

1. VoIP token registration sends a typed token record distinct from standard token.
2. Duplicate token update is idempotent.
3. Token rotation revokes only the old generation.
4. Exact payload grammar accepts a valid fixture.
5. Unknown/duplicate keys, malformed UUID, stale expiry, oversized value, or missing handle rejects.
6. Payload never exposes readable sender/contact/SDP fields.
7. Duplicate VoIP push maps to one pending descriptor/CallKit UUID.
8. Canceled/acked mailbox invite suppresses or promptly ends presentation.
9. Blocked/unknown sender after retrieval cannot remain ringing.
10. AppDelegate standard notification handling remains unchanged.
11. Notification Service Extension never claims the VoIP call path.
12. Logs/errors redact payload and token values.
13. CallKit report completion invokes the PushKit completion handler before delayed Flutter startup or mailbox retrieval finishes.
14. Post-report authentication failure ends CallKit promptly without application `ringing` or media.
15. Durable VoIP-token/wake persistence failure cannot succeed in memory or fall back to ordinary notification delivery.

Relay Go tests cover APNs request headers/topic, payload bound, expiration, retry classification, invalid-token cleanup, rate limits, token separation, Redis restart, and redaction.

## 8. CallKit lifecycle TDD

RunnerTests fail before production wiring for:

1. Report one incoming call and return successful presentation event.
2. Duplicate report adopts existing UUID.
3. Answer action persists before Flutter startup and delivers once afterward.
4. Decline/end action ends CallKit once and submits one terminal event.
5. Remote cancel before answer ends ringing and clears descriptor.
6. Dart end and CallKit end race converge.
7. Provider reset ends every native descriptor and tells Dart once.
8. Expired descriptor on cold launch never restores a call.
9. Busy second call is rejected without a second CallKit call.
10. Contact-name update uses only local opaque mapping.
11. Audio does not start before `provider(_:didActivate:)` and user answer.
12. Audio deactivation/interruption serializes into CallCoordinator.
13. Process recreation adopts one pending descriptor.
14. Every terminal path clears pending store and native references.
15. Existing AppDelegate, app-visibility, notification-recovery, and Go-bridge tests remain green.
16. Answer then remote cancel/expiry before Flutter attachment resolves terminally and is not revived.
17. Dart adoption consumes ordered native events once, acknowledges the highest sequence, and deletes the descriptor exactly once.

## 9. Audio-session contract

- CallKit controls activation/deactivation timing.
- Configure play-and-record/voice-chat mode only for an accepted active call.
- WebRTC audio starts after CallKit activation and microphone permission.
- Mute action reconciles with actual local track state.
- Support receiver, speaker, wired, Bluetooth, interruption, media-services reset, and route change.
- Do not configure a permanent call audio session during app startup or ringing.
- Cleanup deactivates/releases call audio without breaking ordinary notification sounds or later voice notes.

## 10. App lifecycle and cold runtime

### Push callback

1. Parse strict bounded payload.
2. Verify expiry and local opaque-handle shape.
3. Persist minimal protected native descriptor.
4. Report CallKit with random UUID promptly.
5. Invoke the PushKit completion handler from the `reportNewIncomingCall` completion. Do not wait for Flutter, Go, network connection, or mailbox retrieval.
6. In parallel with CallKit processing, start/adopt Flutter/Go runtime through the established single-runtime ownership seam and retrieve/decrypt/validate the mailbox invite.
7. Intersect authenticated contact-device authority with the matching relay capability epoch. On success, update local caller name, adopt the native record, and submit application `incomingPresented`; otherwise end CallKit promptly with an approved reason and no media.

This ordering follows Apple's [Responding to VoIP Notifications from PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit) guidance: report the incoming call while connection work continues in parallel.

### Answer from terminated state

- Persist answer intent first.
- Start/adopt runtime once.
- Deliver action to CallCoordinator once.
- Obtain credentials, exchange SDP/ICE, and start WebRTC only after CallKit audio activation.
- If setup fails, end CallKit and cleanup; never leave a phantom system call.

## 11. Entitlements and provisioning

Required review/proof:

- Push Notifications entitlement.
- Background modes include `voip` and `audio` in addition to any existing modes.
- Correct VoIP APNs topic/environment.
- Keychain/App Group access for the minimal opaque-contact/native descriptor data if used.
- Runner and test targets retain correct entitlements without granting the Notification Service Extension unnecessary VoIP authority.
- Release/profile archive resolves capabilities and provisioning.

Source assertions alone are insufficient; inspect built entitlements/profile where possible without exposing signing material.

## 12. Physical-device matrix

A physical iPhone is required for PushKit/CallKit delivery claims. Resolve available targets immediately before execution and pin exact IDs.

Automated or tightly scripted cases:

1. Foreground incoming/outgoing.
2. Background app.
3. Process terminated but app remains eligible for VoIP delivery.
4. Locked device.
5. Duplicate and delayed VoIP push.
6. Remote cancel before answer.
7. Answer/decline/end from lock screen.
8. Microphone permission denied.
9. Bluetooth/wired/speaker route changes.
10. Network transition during call.
11. App/runtime crash during ringing and active call.
12. APNs invalid-token cleanup on controlled fixture.
13. Repeated calls and provider resets.

A simulator may prove CallKit host behavior but cannot replace real PushKit delivery evidence.

## 13. Required gates

### iOS host

Use the established serial RunnerTests command on an available simulator, focusing first on new call test classes, then `RunnerTests`.

Preserve:

- `IosNotificationRecoveryTests`
- `IosNseMailboxWakeCoordinatorTests`
- `NotificationServiceConfigurationTests`
- `IosReceiverBootstrapHandoffTests`
- `IosAppVisibilitySnapshotTests`
- `GoBridgeCriticalTaskTests`

### Dart

- Exact iOS platform-channel/call adapter tests.
- All VC2-02/VC2-03 signaling, state, media, and cleanup tests.
- `./scripts/run_host_test_gates.sh 1to1`
- `./scripts/run_host_test_gates.sh feature-host-all`
- `core-host-all` only if shared core/notification surfaces changed.

### Relay

- Exact APNs VoIP provider/token tests.
- `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` in `go-relay-server`.

### Device

Physical-iPhone PushKit/CallKit matrix with redacted evidence. Do not claim completion from simulator-only success.

## 14. Security and App Store policy gates

- VoIP pushes correspond only to real current call invitations.
- Every VoIP push results in prompt CallKit report or documented immediate invalid termination.
- No use of PushKit for ordinary messages or silent maintenance.
- No readable caller identity or SDP in APNs payload.
- Provider credentials and device tokens never enter logs/artifacts.
- Revoked/blocked wake handles cannot trigger a lasting ring.
- App privacy disclosure and App Store capability justification are updated before beta submission.

## 15. Acceptance criteria

- Distinct VoIP token registration, rotation, revocation, Redis durability, and APNs invalidation work without affecting standard notifications.
- Real VoIP push presents one CallKit call in foreground, background, terminated, and locked states on an available physical iPhone.
- Duplicate/stale/canceled pushes cannot create duplicate or late ringing.
- PushKit callback completion never waits for Flutter, Go, network connection, or mailbox retrieval; post-report validation failure ends provisional CallKit promptly.
- Answer, decline, end, mute, route change, remote cancel, provider reset, and process recreation converge once.
- Pre-start answer/end/cancel/expiry reconciles through ordered native events, terminal precedence, Dart acknowledgement, and exactly-once descriptor/CallKit cleanup.
- Local contact display comes from protected opaque-handle mapping; push exposes no readable identity/SDP.
- WebRTC audio starts only after answer, permission, and CallKit audio activation.
- Every terminal path ends CallKit and clears native/Dart/media resources.
- Existing standard APNs/FCM, Notification Service Extension, app visibility, and recovery tests remain green.
- iOS call feature remains separately kill-switchable.

## 16. Execution evidence (2026-08-31)

### Implemented

- The Runner owns the strict opaque VoIP payload parser, protected one-call pending journal, local opaque-contact resolver, CallKit provider/audio lifecycle, PushKit registry, and Flutter native bridge.
- PushKit completion is coupled to the CallKit reporting callback. Legacy required-report callbacks and the iOS 26.4+ `PKVoIPPushMetadata.mustReport` callback fail closed through CallKit without starting Flutter ringing or media for rejected pushes.
- VoIP token update, rotation, invalidation, epoch compare-and-swap, corrupt-state handling, and capability rollback are implemented independently from the standard notification token path.
- Initial iOS callability now tolerates the native enable-to-PushKit race without weakening fail-closed behavior: a persisted invalidation waits on one bounded deadline for a strictly newer valid generation, while timeout, malformed state, close, and later invalidation still revoke exact known authority.
- Dart owns native-event adoption/acknowledgement, call-authority validation, cold-start reconciliation, signaling composition, and rollback cleanup.
- Dart and the Go relay now share the exact endpoint canonical JSON field order used for Ed25519 signing and verification. This removes a production-only `CALL_UNAUTHORIZED` failure that previously occurred before any endpoint Redis mutation.
- The one-scan contact flow now backfills call-wake authority as soon as a verified reciprocal installs the missing ML-KEM key. Bootstrap installs the contact-key forwarder before the listener, reconciles issuance, retries only a genuinely pending distribution, and refreshes outgoing-call availability only after a strictly newer verified grant is durably stored. Callback failures remain best-effort and cannot reject an otherwise valid contact message.
- Call-wake grant distribution now binds a UUIDv4 `cwr` receipt to signed/encrypted `cwh` delivery. The sender deliberately skips LAN for this operation, and mailbox/inbox custody cannot prove receiver installation. Only an exact direct ACK that returns the optional `callWakeReceipt` after secure receiver persistence marks the grant distributed; receipt-free legacy ACKs remain wire-compatible but unproven.
- Offline reuse is limited to current, durably proven grants. Pending and legacy-unproven records stay on the strict retry path; durable receipt proof version 1 is cleared by rotation, revocation, or any transition back to pending, and the receiver cache publishes a grant only after persistence succeeds. Issuance retains its one-day nominal lifetime while rotating before less than 10 minutes 45 seconds of setup/control headroom remains.
- Shutdown paths withdraw call-wake publication and fence late republish. Production outgoing calls require an exact-contact strict-receipt preflight before invite dispatch.
- iOS cold-start attachment is strict: malformed or throwing native `attach` results abort startup before VoIP-token or endpoint publication. The shared Android lifecycle path retains its existing non-strict compatibility behavior.
- The relay owns Redis-backed VoIP token authority, APNs provider submission, invalid-token cleanup, exact token/epoch revocation, bounded payload construction, and redacted provider outcomes.
- CallKit route and interruption notifications persist ordered native events and fail closed on journal-write failure. Answer followed by expiry across process recreation preserves terminal precedence, fences acknowledgement, prevents revival, and deletes the pending record exactly once.
- Debug/Profile resolve the sandbox APNs environment and Release resolves production. Automatic archive/export signing avoids inherited identity conflicts, and `scripts/verify_ios_voip_signing.sh` verifies the final signed Runner entitlement without disclosing signing material.
- Runner's privacy manifest declares the durably retained PushKit token as a linked, nontracking Device ID used solely for App Functionality. The Notification Service Extension continues to declare no collected data.
- Both checked-in public privacy-policy sources disclose separate ordinary-notification and PushKit VoIP tokens, direct Apple APNs/PushKit processing, opaque current-call-only payloads, linked pseudonymous routing identity, nontracking use, and separate token retention.

### Automated evidence

- The seven VC2-05 RunnerTests classes now contain 73 tests. A post-fix focused lifecycle/bridge run passed 34/34, including notification-driven route/interruption/media-reset behavior and answer-to-expiry recreation precedence, on the pinned available simulator.
- Full iOS RunnerTests preservation suite: 229/229 tests passed serially on the same pinned simulator after the final native lifecycle changes, covering all 73 VC2-05 tests.
- The iOS 26.4+ metadata delegate selector compiles and is present in the built Runner binary.
- A pinned no-install physical-device Debug build succeeded; the signing verifier reported `environment=development`, and no VC2-05 source, signing, or provisioning warning was emitted.
- Focused Dart lifecycle/token/rollback suite: 40/40 tests passed. A post-fix adapter/composition preservation run passed 78/78, including strict iOS startup abort with zero token or endpoint publication and Android compatibility sentinels.
- Post-device-debug causal suites passed 26/26 across the endpoint-authority client and iOS VoIP-token coordinator. They include persisted-invalidation-to-new-token startup, historical valid-then-invalidated waiter reset, timeout/late-event CAS revocation, and an exact relay-order endpoint canonicalization contract. The matching Go canonical-byte sentinel passed, scoped analysis reported no issues, and formatting plus `git diff --check` were clean.
- Host gates: post-fix `1to1` passed 184/184 commands; post-fix `feature-host-all` passed 891/891 commands with zero failures; `core-host-all` passed 439/439 commands.
- The core lane exposed and then preserved two intentional cross-feature contract changes: CallKit's required `UIBackgroundModes.audio` no longer serves as an iOS PiP proxy, and the DTR-18 reviewed bootstrap hash now covers the VC2-05 composition at the same app-owned boundary. Both exact contracts pass.
- Relay gate: `GOTOOLCHAIN=go1.25.0 go test ./... -count=1` passed in `go-relay-server`. A direct Redis-outage causal test also proves registration, rotation, epoch revoke, provider-generation cleanup, and generic revoke fail closed without ordinary-push fallback or secret-bearing errors, while the pre-outage generation survives recovery.
- On an explicitly authorized iPhone, a fresh Debug build installed and launched, and the final signed Runner passed `scripts/verify_ios_voip_signing.sh` with the development environment. Redacted durable evidence then showed a present, non-invalidated PushKit token, the expected VoIP topic, and native call capability enabled. The sandbox relay simultaneously held exactly one live iOS VoIP token, one sender wake authorization, one signed endpoint, and one endpoint-device binding. No raw token, wake handle, peer ID, or signing-key material entered this document.
- Swift parsing, plist/project lint, signing-verifier syntax, Graphify affected-path review/incremental refresh, and `git diff --check` passed for the implementation batches.
- A fresh automatic Release archive succeeded. Its expected intermediate development signature (`aps-environment=development`, `get-task-allow=true`) was correctly rejected by the signing verifier because its bundled Release environment is production.
- Offline App Store Connect-method export then succeeded without provisioning updates, submission, upload, or App Store validation. The exported IPA has bundled `MknoonVoipEnvironment=production`, signed `aps-environment=production`, and `get-task-allow=false`; `scripts/verify_ios_voip_signing.sh`, strict deep signature validation, and all 41 individually enumerated nested signature checks passed.
- Focused native privacy/configuration proof passed 8/8 and the Dart privacy/public-policy contract passed 2/2. In the final exported IPA, Runner and embedded NotificationService privacy manifests byte-match current source; Runner has exactly one linked, nontracking Device ID/App Functionality row, while NotificationService has zero collected-data rows.

#### Continuation evidence (2026-09-01)

- The immediate call-wake backfill helper has 6 focused tests. The real one-scan integration regression passed 1/1 and proves: compact QR without `cwh`, verified reciprocal ML-KEM installation, reconcile, pending-only retry, signed/encrypted `cwh` delivery, durable receiver storage, and pending-state clearance. The combined causal suite passed 138 tests and scoped analysis reported no issues.
- Post-repair iOS focused native coverage passed 76/76 and the full RunnerTests preservation suite passed 232/232. Relay `go test ./...` passed; the endpoint-authority lane passed 8/8 and its combined Dart/Go causal lane passed 26/26. The curated `1to1` host gate remained green at 184/184.
- Current-tree `feature-host-all` passed 9,886 tests with 11 skips and zero failures. Current-tree `core-host-all` passed 3,638 Dart tests plus the profile/release renderer manifest and dropped-push recovery manifest contracts. The core run exposed two stale DTR-18 reviewed hashes and a missing `test/core/bootstrap/**` gate classification; the reviewed same-owner hashes were updated, completeness now reports 1,541/1,541 files classified, and the final full lane is green.
- Graphify affected-path analysis and incremental refresh completed for each coherent app-owned batch. The final all-changed-path audit covered all 22 pending paths, left zero impact debt, and the incremental architecture refresh completed; `git diff --check` and gate-script syntax also pass.
- A diagnostic physical `integration_test` invocation cleared the disposable app identities on both authorized phones. The earlier redacted PushKit registration proof remains valid historical evidence, but the current physical matrix requires fresh iPhone onboarding and re-pairing with the fresh Pixel identity before call delivery can be claimed.
- The trusted Pixel/iPhone pairing was restored and a real offline call exposed a strict sender/relay expiry-boundary mismatch: the sender used the full 45-second maximum while the Pixel clock was approximately 1.5 seconds ahead of the relay. Production senders now use a 40-second default with 5 seconds of headroom while every native, relay, and payload-parser 45-second security ceiling remains unchanged. Focused Dart coverage passed 18/18 and scoped analysis reported no issues.
- The Go mailbox bridge and Dart mailbox client now preserve only the exact closed call-control error vocabulary, including `CALL_EXPIRY_INVALID`; unknown or secret-bearing errors still collapse to the generic failure. The rebuilt Android binding produced the expected fixed-shape physical diagnostic before the expiry repair, and the pinned Go bridge package passed afterward.
- On an authorized iPhone, Runner was naturally backgrounded while leaving the app process eligible. The trusted Pixel then recorded `mailbox_store=true` and `direct_send=false`; the sandbox relay's APNs `sent` counter advanced while authentication, provider, and server error counters remained zero. The protected native journal subsequently showed schema 1, `phase=preStart`, `direction=incoming`, `presented=true`, terminal `expired`, and the exact event sequence `[presented, expired]`. This earlier-build run is physical proof of APNs receipt, PushKit parsing/persistence, CallKit presentation, and bounded expiry in normal background state; it is not promoted to current frozen-source Answer/connect evidence. No raw token, call handle, wake handle, peer ID, payload, or signing material was recorded.
- Repeated authorized physical pre-answer cancellation produced one CallKit presentation followed by one `remoteCancelled` terminal per attempt, preserving terminal precedence without duplicate ringing.
- PushKit now emits a closed fixed-shape diagnostic vocabulary for delegate policy, capability state, parser outcome, presentation result, and required-compliance completion. The focused registry suite passed 18/18 and the current full serial RunnerTests suite passed 244/244 on the pinned available simulator. Current pinned-Go relay and bridge gates pass, the scoped Dart analysis/signing verifier/format/diff checks pass, and the current `1to1` host gate passes 184/184 commands.
- Current-tree `feature-host-all` passed 897/897 commands and `core-host-all` passed 442/442 commands. The first core run exposed a reviewed DTR-18 normalized bootstrap-inventory hash drift caused by VC2-05 composition at the same app-owned boundary, not an owner move or core shim; only that test sentinel and its rationale changed, its exact suite passed 3/3, and the full 442-command core rerun passed.
- Live comparison showed the non-invalidated 32-byte development PushKit token, environment, and topic agree with every live relay iOS VoIP row, and one current row also matches the native refresh generation. Later provider-accepted pushes sent after a tool-induced process termination produced neither a fresh PushKit diagnostic nor a new protected descriptor and are deliberately **not** counted as device-delivery or terminated-state evidence. A manual user launch is required to clear possible iOS force-quit suppression before one bounded foreground/background discriminator and any eligible-termination test.
- All local `.p8` files under `APPLE/` are now mode `0600`, ignored, and removed from the Git index; the supplied sandbox campaign key remains locally available for this authorized run. Because these credentials previously existed in repository history, untracking is not retroactive remediation: every still-valid key must be rotated/revoked, including the campaign key after the run, before release closure.
- The physical startup failure was isolated from PushKit itself: runs that omitted the sandbox relay build input selected the shipped legacy relay and received closed `CALL_CONTROL_UNSUPPORTED` bridge failures. Supplying the authorized sandbox relay input produced `CALL_CAPABILITY_ADVERTISEMENT_RESULT stage=ready outcome=ready` and `CALL_SIGNALING_START_RESULT outcome=ready enabled=true started=true graphPresent=true outgoingAvailable=true`. The sandbox relay input is therefore a required campaign precondition, not an APNs credential or messaging-notification substitute.
- Native PushKit diagnostics exposed a late-listener race in which a durable token update could occur after a stale read but before EventChannel subscription. The authority now installs the listener and replays its latest snapshot atomically, serializes later updates, and clears canceled generations. The native registry suite passed 23/23, including pre-listen update replay before live rotation; the matching Dart stale-read/rotation sentinel also passes.
- A real outgoing probe first reached the Pixel and returned ringing signaling, but the iPhone presented that return wake as a new incoming call. The generated signaling handle was correct; native outgoing ownership was simply registered after invite transmission, during accepted-media creation. `CallControlEffectExecutor` now stores the signaling context, awaits native outgoing registration, and only then emits `outgoingInviteReady`; denial or exceptions purge context and send no invite. The causal executor suite passed 11/11, the combined executor/composition run passed 56/56, scoped analysis was clean, and production no longer defers registration to media creation.
- The first post-registration physical probe kept the iPhone in **Dialing** while only the Pixel displayed the incoming call, proving the false self-incoming presentation was removed. The Pixel produced no audible ringtone, so ringtone behavior remains a separate pending device row. Pixel `ringing` and `accept` signals were delivered, but iOS then recorded `terminal=nativeFailure`: legacy PushKit compliance had successfully re-reported the already-presented outgoing UUID and the generic busy-race path incorrectly terminalized it.
- An exact native RED reproduced that physical drop: a successful same-handle return-wake report appended `nativeFailure` and failed with exit 65. Production now preserves only a presented, nonterminal outgoing descriptor whose UUID and authenticated call handle exactly match the return wake; unrelated busy calls retain the existing fail-closed behavior. The exact test is green, both already-exists and successful same-handle report sentinels pass, and the complete CallKit lifecycle class passes 37/37. A corrected physical build is installed with PushKit registration enabled and the call graph ready; the immediate-answer continuity rerun remains pending.

#### Continuation evidence (2026-09-02)

- The answered outgoing continuity rerun exposed and repaired three separate lifecycle faults without weakening native ownership. iOS route parsing now uses the canonical Dart vocabulary (`system_default`, `earpiece`, and `wired_headset`); CallKit audio activation has a short bounded readiness retry; and diagnostics report only closed enum values for audio stages, call-state transitions, outgoing native registration, and terminal cleanup. The matching Android adapter, iOS wrapper, production-composition, controller, and WebRTC tests pass with scoped analysis clean.
- A strict native RED reproduced a connected outgoing call expiring at its original presentation deadline after process recreation. `PendingNativeCallStore` now persists an optional, atomic `connectedAtMs` marker; the CallKit controller records it before reporting connected and both scheduled and cold/attach expiry paths refuse to expire that descriptor. The focused native lifecycle/store batch passed 49/49, and the current complete serial `RunnerTests` gate passes 257/257 on the pinned available simulator.
- On an earlier pre-final-receipt build, an automated iPhone-to-Pixel call reached `connected` on both peers and remained connected beyond the former 45-second cutoff. A verified Pixel `End` action returned both peers to their normal app surfaces with no lingering incoming or active-call controls. This run remains diagnostic history rather than current frozen-source acceptance evidence.
- An immediate second call initially failed closed with `descriptorConflict`, then exposed a retained-terminal cleanup self-deadlock. Outgoing registration was executing inside the coordinator effect tail while terminal replay attempted to dispatch back onto that tail; moving exact retained cleanup before `coordinator.placeCall` removed that cycle. The physical retry then exposed a second cycle: terminal reconciliation owned the native lifecycle adapter tail while media cleanup queued system-default route reset and deactivation back onto the same tail, hit the 2-second deadline, and permanently memoized `call_media` failure. Only the exact bound retained terminal now treats those two already-terminal native commands as local idempotent release; live calls, non-default routing, WebRTC close, and microphone-lease release remain strict terminal-ACK gates.
- The exact adapter-tail RED is green. Preservation coverage passes Android adapter 48/48, iOS wrapper 13/13, cleanup coordinator 6/6, audio controller 20/20, media owner 8/8, call coordinator 22/22, and the production ordering/privacy sentinels. Graphify affected-path analysis and incremental refresh completed for each coherent repair batch.
- That earlier corrected build then completed two consecutive automated iPhone-to-Pixel calls without restarting either app between them. For each call, the Pixel watcher waited for the exact native `presented=true` event before tapping Answer once; Pixel exposed `Connected` and `End`, while iPhone recorded `adoptionCompletion/success/none` and reached `connected`. Pixel ended each call from verified accessibility bounds. The second registration contained no `descriptorConflict`, `terminalDispatchRejected`, or `terminalCleanupPending`, and both peers returned idle after the final hangup. These runs guided the later repairs but are not current frozen-source Answer/connect proof.
- A same-UUID CallKit report race was reproduced and fixed with exact in-flight/completed coalescing. The lifecycle class passes 42/42, and the complete serial `RunnerTests` gate passes 258/258. Before the final receipt/build freeze, two physical Pixel-to-iPhone attempts each produced exactly one CallKit report, one system-ringtone start/stop lifecycle, and no duplicate-report or `nativeFailure` terminal.
- Native Android decline/end actions now normalize to canonical signaling types before terminal reduction. The state-machine class passes 53/53 and the effect executor passes 11/11. A physical Pixel `End` action subsequently emitted one delivered `terminate`; iPhone reduced `remoteTerminate`, and both peers reported terminal cleanup `ready`.
- Android incoming ringtone ownership is now process-singleton and exact-call bound. Strict REDs covered the missing playback owner, answer/terminal cleanup, expired eligibility, pre-answer media activation, answer-during-start cleanup, partial wake ownership, notification-channel overlap, and answered-call foreground demotion. The final implementation uses the actual default ringtone with ringtone audio attributes, looping playback, a partial playback wake lock, a second eligibility check after startup, and a versioned silent high-importance notification channel. Incoming media cannot activate before durable Answer association, while outgoing activation remains unchanged. Answered audio deactivation now enters an explicit `INACTIVE` foreground mode that stops the ringer and retains the ongoing End-only notification; stale `START_RINGING` and duplicate inactive commands cannot restore Answer/Decline or restart playback. The exact seven-class native batch passes 74/74, and the complete Android call package passes 108/108 tests across 11 suites. Android `lintDebug` reached dependency analysis but is currently blocked in four third-party plugin lint-model tasks because Jetifier rejects Byte Buddy class-file version 68; app compilation and the exact native call suites are green.
- On the pre-final-source physical build, the Android watcher expanded the Pixel notification shade, located the real `Answer` node, and tapped its bounds once. Pixel recorded ringtone `start/playing`, then `lifecycle/stopped` on durable answer and progressed through incoming validation, ringing, accepted, negotiating, and connected; iPhone progressed through dialing, ringing, accepted, negotiating, and connected. Pixel then ended through Telecom, delivered `terminate=true`, iPhone reduced `remoteTerminate`, both cleanup results were `ready`, and a final Pixel accessibility dump contained no Answer, Decline, End, or Connected controls. Because later receipt and lifecycle repairs changed the frozen source, this is retained only as historical diagnostic evidence.

#### Frozen-source closure evidence (2026-09-02)

- Formatting covered 127 files and changed one; scoped analysis across 21 changed-path groups reported no issues. Focused Dart preservation passed 518/518 feature/call tests, 274/274 contact-request tests, 104/104 exact helper/composition/store tests, and 237/237 bridge/listener tests.
- Focused Go node/bridge tests passed under `-race`; iOS `RunnerTests` passed 258/258; the Android native call package passed 108/108; and relay `go test ./...` passed.
- Frozen host sweeps passed 3,085 tests with 3 skips in `1to1` and 9,972 tests with 11 skips in `feature-host-all`. `core-host-all` completed its Flutter batch 3,670/3,670 and passed the Android renderer manifest contract. Its dropped-push tail had one transient aggregate exit; both the exact script and exact host-gate invocation subsequently passed.
- The DTR reviewed-hash drift was audited as the legitimate VC2-05 bootstrap-composition change at the existing app-owned boundary; the exact DTR plus migration rerun passed 3/3. Graphify affected-path review finished with zero pending impact debt, and the incremental architecture graph refresh completed.
- Current Go bindings and Flutter builds are installed on the authorized iPhone and Pixel. Repeated exact-source iPhone outgoing probes reached Pixel incoming validation and presentation: invite delivery reported `direct=true` and `mailbox=true`, Pixel reported `presented=true`, and its ringing ACK reported `direct=true` and `mailbox=true`. No-answer expiry then performed terminal cleanup. This proves current-source routing, incoming presentation, ringing signaling, and no-answer cleanup only; automated Pixel Answer/connect remains pending.

### Remaining closure evidence

Implementation and frozen-source automated verification are complete, but this plan is not eligible for full physical-delivery or release closure until all of the following external/device evidence is recorded:

1. Current exact-source physical proof stops at iPhone outgoing, Pixel validation/presentation/ringing ACK, and no-answer terminal cleanup. The automated Pixel Answer/connect/end leg must still pass on this frozen build; earlier connected runs remain diagnostic history. The other availability-bounded rows are eligible terminated-process delivery without force-quit suppression, locked delivery, lock-screen answer/decline/end, delayed APNs duplicate delivery, microphone denial, available route changes, network transition, and ringing/active crash recovery. Same-UUID report coalescing is exact-test proven. Provider reset remains deterministic native evidence unless a reliable physical trigger is available; Bluetooth/wired rows are `N/A (target unavailable by project policy)` when those accessories are absent.
2. The frozen Pixel build has deterministic native coverage for process-singleton ringtone playback, ringtone-usage audio policy, and answer/terminal stop ownership, but a person has not yet confirmed that ringtone acoustically. “Human-heard audible ringtone” therefore remains an explicit physical observation row rather than being inferred from diagnostics.
3. The embedded Appium Android connector cannot attach because its MCP process lacks `ANDROID_HOME`/`ANDROID_SDK_ROOT`. ADB/device tooling and Dart VM automation remain usable, but they have not yet completed the current exact-source Pixel Answer/connect leg. Physical XCUITest/WebDriverAgent build-for-testing succeeds, while execution remains blocked because the host has Developer Tools automation disabled and enabling it requires macOS administrator authorization. Until that host setting is changed, unattended physical-iPhone lock-screen Answer/Decline/End cannot be claimed.
4. Real sandbox provider submission and physical background receipt are recorded above. For each remaining APNs-dependent row, correlate a fresh native diagnostic or protected descriptor with the bounded probe window; APNs HTTP 200/`sent` alone is provider acceptance and must never be relabeled as device delivery. Secrets and raw device tokens must not enter this document or test logs.
5. The checked-in public privacy policies are updated and contract-protected. Before beta submission, the privacy owner must reconcile the implemented `PrivacyInfo.xcprivacy` PushKit Device ID declaration with App Store Connect App Privacy and capability review notes. Tracking remains false and the stated purpose is App Functionality, subject to the complete app-wide disclosure review.
6. TURN is an external VC2-01 infrastructure dependency. Its absence does not block PushKit receipt, CallKit presentation, decline/cancel, or lifecycle convergence, but it prevents a strong claim of forced-relay or cross-network answered-media continuity until deployed TURN evidence is separately authorized and recorded.
7. Rotate/revoke every still-valid APNs authentication key that previously entered repository history, including the sandbox campaign key after this run. Ignored local copies cannot satisfy release credential hygiene by themselves.
