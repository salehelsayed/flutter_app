# Smoke Test Strategy for Simulators

## Executive Summary

The app does **not** need a new 18-file smoke framework. The current repo already contains a strong set of startup, loading, QR, messaging, posts, group, transport, and reconnection tests. The smallest effective strategy is to promote a curated set of existing tests into an explicit smoke suite, keep real-stack transport/recovery tests as nightly or pre-release gates, and use fakes selectively rather than forcing a fake-only parallel app.

The important correction is **where to catch regressions**. Small smoke coverage is still right, but high-blast-radius work such as 1:1 reliability needs a named **change-based regression gate**. A generic startup smoke can stay green while text still works and voice/media quietly break.

---

## Existing Test Infrastructure (Reusable)

### Fakes Already Available

| Fake | Location | Purpose |
|------|----------|---------|
| `FakeBridge` | `test/core/bridge/` | Pre-canned bridge responses |
| `FakeSecureKeyStore` | `test/core/secure_storage/` | In-memory key storage |
| `FakeP2PService` | `test/core/services/` | Offline inbox, WiFi/relay |
| `FakeP2PNetwork` | `test/shared/fakes/` | Routes messages between peers |
| `FakeIdentityRepository` | `test/features/identity/` | Identity CRUD |
| `FakeContactRepository` | `test/features/contacts/` | Contact CRUD |
| `FakeContactRequestRepository` | `test/features/contact_request/` | Request CRUD |
| `InMemoryMessageRepository` | `test/shared/fakes/` | Message storage |
| `InMemoryMediaAttachmentRepository` | `test/shared/fakes/` | Media metadata |
| `InMemoryGroupRepository` | `test/shared/fakes/` | Group storage |
| `InMemoryGroupMessageRepository` | `test/shared/fakes/` | Group messages |
| `FakeAudioRecorderService` | `test/shared/fakes/` | Audio without mic |
| `FakeMediaFileManager` | `test/shared/fakes/` | File I/O without FS |
| `TestUser` | `test/shared/fakes/` | Full per-user test stack |
| `GroupTestUser` | `test/shared/fakes/` | Group-specific test user |

### Existing Integration Tests (Reference)

| File | Status |
|------|--------|
| `startup_router_recovery_test.dart` | KEEP in Tier 1 |
| `integration_test/loading_states_smoke_test.dart` | KEEP in Tier 1 as the canonical startup/loading smoke |
| `test/features/loading_states_smoke_test.dart` | TRIAGE separately as widget/render smoke; do not treat as the same gate entry |
| `qr_scanner_wired_test.dart` | KEEP in Tier 1 |
| `offline_inbox_roundtrip_test.dart` | KEEP in Tier 1 |
| `posts_phase1_fake_test.dart` | KEEP in Tier 1 |
| `group_messaging_smoke_test.dart` | KEEP when groups are release scope |
| `media_stable_id_smoke_test.dart` | Tier 2 / release confidence |
| `wifi_relay_fallback_smoke_test.dart` | Nightly / pre-release |
| `transport_e2e_test.dart` | Nightly / pre-release |
| `voice_message_e2e_test.dart` | Device-backed gate, not generic simulator smoke |

---

## Smoke Test Flows (Lean Suite)

### Tier 1: Critical — Run on Every Build (~3-5 min)

| # | Flow | What to Verify |
|---|------|---------------|
| 1 | **Startup Routing & Loading** | App routes correctly through startup / first-time / loading states without hanging |
| 2 | **QR Scan Happy Path** | Scan success reaches the current QR handling path and does not regress wired UI behavior |
| 3 | **Offline Inbox Round Trip** | Message send/receive still works when delivery falls through inbox storage/recovery |
| 4 | **Posts Delivery & Replay** | Posts survive offline/replay behavior and still hydrate correctly |
| 5 | **Group Messaging Smoke** | If groups are in active release scope, group publish/receive still works end-to-end |

### Tier 2: High Priority — Run on Most Builds (~10-15 min)

| # | Flow | What to Verify |
|---|------|---------------|
| 6 | **Contact Request Acceptance** | Request receipt → accept flow → contact persistence still works |
| 7 | **Media Stable ID / Download** | Media attachment IDs, persistence, and receive-side rendering stay stable |
| 8 | **Feed / Conversation Cross-Surface Flow** | Feed opens conversation, optimistic send still works, return path stays stable |
| 9 | **Settings / Recovery Surfaces** | Profile/recovery phrase surfaces still render and persist correctly |

### Tier 3: Regression — Run Before Releases

- `background_reconnect_test`
- `wifi_relay_fallback_smoke_test`
- `transport_e2e_test`
- `voice_message_e2e_test`
- `media_stable_id_smoke_test`
- `group_resume_recovery_test`

---

## Change-Based Regression Gates

Smoke should answer: **does the app still basically boot and complete the core flows?**

Regression gates should answer: **did this specific change break an adjacent capability that shares the same pipeline?**

That distinction matters for messaging reliability. A text-only smoke can pass while shared send/retry/upload changes still break voice or media.

### Example: 1:1 Reliability Gate

Any change that touches the shared 1:1 delivery pipeline should run a named reliability pack rather than relying on generic smoke alone.

#### Coverage Matrix

| Axis | Required Coverage |
|------|-------------------|
| **Payload** | Text, image/media, voice |
| **State** | Online, offline inbox fallback, retry after failure, resume-after-interruption |
| **Surface** | Conversation screen, any other active send surface such as feed inline reply |

#### Candidate Gate Suite

| Test | Why It Belongs |
|------|----------------|
| `two_user_message_exchange_test` | Baseline 1:1 send/receive still works |
| `offline_inbox_roundtrip_test` | Offline inbox fallback still delivers |
| `media_attachment_flow_test` | Media metadata, upload, send, receive, persistence |
| `media_retry_smoke_test` | Failed media send can recover |
| `voice_message_exchange_test` | Voice record/send/receive path still works |
| `incomplete_upload_recovery_test` | Resume/recovery path for partial uploads |
| `send_then_lock_delivery_test` | Lifecycle interruption during send |
| `stuck_sending_recovery_test` | Crash-ish recovery of orphaned sending state |
| `quote_reply_thread_test` | Quoted-message send path still behaves correctly under the shared 1:1 pipeline |

If the app keeps multiple 1:1 send surfaces, the gate should also include at least one test that enters the shared send path from the non-conversation surface most likely to drift, currently feed inline reply.

For Session 1, treat the 9-file definition in `14-regression-test-strategy.md` as the draft authoritative list and patch it during classification rather than rebuilding the gate from scratch.

### Trigger Rules

Run the 1:1 reliability gate automatically when a change touches files in or around these areas:

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- transport/bootstrap code that changes direct send, relay fallback, or inbox drain behavior

### Practical Rule

- Keep smoke small and stable.
- Add a permanent regression test every time production reveals an escaped bug.
- Gate high-risk changes by subsystem, not by adding more generic smoke files.

---

## Mocks Needed for Simulator

### Bridge (Go Native)
Use `FakeBridge` only when the bridge itself is not under test. Do **not** force a blanket fake-only harness when the current test already exercises the real app wiring.

```dart
final bridge = FakeBridge({
  'identity.generate': {'ok': true, 'identity': {'peerId': '...', 'publicKey': '...'}},
  'payload.sign': {'ok': true, 'signature': 'test-sig'},
  'payload.verify': {'ok': true, 'valid': true},
});
```

### P2P Networking
Use `FakeP2PNetwork` / `FakeP2PService` for fast deterministic feature smoke, but keep real transport tests for nightly/pre-release gates.

```dart
final network = FakeP2PNetwork();
final aliceService = FakeP2PService(peerId: 'alice', network: network);
final bobService = FakeP2PService(peerId: 'bob', network: network);
```

### Database
Real SQLCipher in test mode is fine for many flows. Prefer unique DB names/reset helpers instead of creating a second parallel “smoke app.”

---

## Directory Structure

```
integration_test/
├── loading_states_smoke_test.dart
├── posts_phase1_fake_test.dart
├── media_stable_id_smoke_test.dart
├── wifi_relay_fallback_smoke_test.dart
├── transport_e2e_test.dart
└── voice_message_e2e_test.dart

test/
├── features/identity/presentation/screens/startup_router_recovery_test.dart
├── features/qr_code/presentation/screens/qr_scanner_wired_test.dart
├── features/conversation/integration/offline_inbox_roundtrip_test.dart
└── features/groups/integration/group_messaging_smoke_test.dart
```

If new smoke files are added at all, keep them minimal and only for genuinely uncovered flows. Do not create a new `smoke_*` matrix by default.

---

## Test Runner Scripts

```bash
#!/bin/bash
# run_smoke_tests.sh
SUITE=${1:-tier1}

case "$SUITE" in
  tier1)
    flutter test \
      test/features/identity/presentation/screens/startup_router_recovery_test.dart \
      test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
      test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
      integration_test/loading_states_smoke_test.dart \
      integration_test/posts_phase1_fake_test.dart
    ;;
  tier2)
    flutter test \
      integration_test/media_stable_id_smoke_test.dart \
      test/features/contact_request/integration/contact_request_flow_test.dart
    ;;
  release)
    flutter test integration_test/wifi_relay_fallback_smoke_test.dart
    flutter test integration_test/transport_e2e_test.dart
    flutter test integration_test/background_reconnect_test.dart
    ;;
esac
```

---

## Simulator Limitations & Workarounds

| Limitation | Workaround |
|------------|-----------|
| No real microphone on simulator | Use `FakeAudioRecorderService` for deterministic smoke; keep device-backed voice tests for release gating |
| No real camera | Inject scanned QR data or rely on wired UI tests |
| Real network variability | Use fakes for fast smoke, real transport tests as nightly/release gates |
| Bridge coverage cost | Use `FakeBridge` when crypto/bridge behavior is not the purpose of the smoke |
| Firebase / push complexity | Keep push logic mostly at unit/integration boundary unless doing dedicated device validation |

---

## CI/CD Integration

```yaml
# .github/workflows/smoke-tests.yml
on: [pull_request, push]
jobs:
  smoke-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: ./scripts/run_smoke_tests.sh tier1
      - run: ./scripts/run_smoke_tests.sh release
        if: github.event_name == 'push'
```

---

## Checklist Before Shipping

- [ ] Tier 1 is a curated subset of existing tests, not a second parallel test framework
- [ ] High-blast-radius changes use a named subsystem regression gate in addition to smoke
- [ ] 1:1 reliability changes run text + media + voice + retry/recovery coverage
- [ ] Real-stack transport/recovery tests remain in nightly or release gates
- [ ] Device-backed voice tests are not treated as generic simulator smoke
- [ ] Database reset/unique naming is consistent across smoke flows
- [ ] Fakes are used selectively, not as a blanket replacement for all bootstrap behavior
- [ ] Any newly added smoke file covers a genuinely uncovered flow
