# Integration & E2E Test Coverage Analysis

**Total Tests:** 682 | **Unit:** 582 | **Feature Integration:** 26 | **Full E2E:** 22 | **Lifecycle/Resilience:** 16 | **Database:** 33

---

## Executive Summary

Mature integration and E2E infrastructure with strong fake-based multi-user simulation and meaningful real-stack transport tests. The earlier pass overstated several cross-feature gaps: group invite/join/message, notification deep-link flow, share-to-contact, and profile-picture broadcast are already covered in the current repo. The highest-value remaining gaps are narrow adapter boundaries, one optional golden onboarding path, and a more explicit **change-based regression gate** for high-blast-radius areas such as 1:1 reliability.

---

## Test Infrastructure Quality

### Fakes Available (Excellent)

| Category | Fakes | Quality |
|----------|-------|---------|
| **P2P/Networking** | FakeP2PNetwork, FakeP2PService (2 variants), ChaosP2PNetwork, FakeBridge, LifecycleBridge, FakeLocalP2PService | Excellent |
| **Persistence** | InMemory repos for: Message, Contact, ContactRequest, Group, GroupMessage, MediaAttachment, Post, Introduction | Excellent |
| **User Simulators** | TestUser, GroupTestUser, PostTestUser, IntroTestUser | Excellent |
| **Domain Fakes** | FakeNotificationService, FakePushTokenStore, FakeAudioRecorderService, FakeMediaFileManager, FakeMediaPicker, FakeSecureKeyStore, FakeGroupPubSubNetwork | Excellent |

---

## Feature Integration Coverage

| Feature | Unit | Integration | E2E | Status |
|---------|------|-------------|-----|--------|
| **Conversation** | 27 | 11 | 2 | Excellent |
| **Groups** | 44 | 6 | 2 | Excellent |
| **Posts** | 91 | 0 | 5 | Strong (phase-based E2E plus broad unit-style coverage) |
| **Introduction** | 15 | 3 | 0 | Good |
| **Contact Request** | 9 | 2 | 0 | Good |
| **Feed** | 4 | 3 | 1 | Medium (presentation-heavy, some cross-surface coverage) |
| **Settings** | 5 | 1 | 0 | Medium |
| **Identity** | 4 | 0 | 1 | Medium (startup routing already stronger than first pass suggested) |
| **Contacts** | 6 | 1 | 0 | Medium |
| **Push** | 11 | 0 | 0 | Medium (good unit/open-flow coverage; adapter boundary still light) |
| **QR Code** | 3 | 0 | 0 | Medium (logic + wired UI covered, limited end-to-end wiring) |
| **P2P** | 4 | 0 | 3+ | Good |
| **Share** | 4 | 1 | 0 | Medium |

### Settings Coverage Update - April 28, 2026

Settings now has focused background-choice coverage in addition to the older profile-picture flow:

- `test/features/settings/application/background_preference_use_cases_test.dart` covers missing, `default`, unknown, save, and overwrite behavior for the local background preference.
- `test/features/settings/presentation/widgets/background_choice_control_test.dart` covers selected `Default` UI, tap behavior, accessibility semantics, failed-save copy, and English/German/Arabic localized labels.
- `test/features/settings/presentation/screens/settings_screen_test.dart` and `test/features/settings/presentation/screens/settings_wired_test.dart` cover visible Settings integration, secure-storage save, failed-save honesty, and background-choice flow telemetry.
- `integration_test/settings_background_choice_smoke_test.dart` covers the device-backed representative Feed -> Settings -> close -> reopen smoke for the default background choice.

---

## Conversation Integration Tests (11 — Excellent)

| Test | Scope |
|------|-------|
| `two_user_message_exchange_test` | Bidirectional P2P messaging with full DI |
| `media_attachment_flow_test` | Image/file upload → send → receive → persist |
| `media_retry_smoke_test` | Failed upload recovery with retry |
| `voice_message_exchange_test` | Audio recording → encoding → send → decode |
| `emoji_reaction_exchange_test` | Reaction send/receive with router splitting |
| `send_then_lock_delivery_test` | Lock during send → resume → retry |
| `stuck_sending_recovery_test` | Orphaned messages recovery |
| `offline_inbox_roundtrip_test` | Offline → inbox relay → delivery |
| `quote_reply_thread_test` | Quoted messages with thread context |
| `incomplete_upload_recovery_test` | Partial upload recovery on resume |

## Group Integration Tests (6 — Very Good)

| Test | Scope |
|------|-------|
| `group_messaging_smoke_test` | Multi-user GossipSub publish/subscribe |
| `group_membership_smoke_test` | Join/leave with member list updates |
| `group_startup_rejoin_smoke_test` | Topic re-subscription on restart |
| `group_edge_cases_smoke_test` | Empty groups, single member, races |
| `invite_round_trip_test` | Invite creation → P2P delivery → acceptance |
| `group_resume_recovery_test` | Missed messages on resume + inbox drain |

## Lifecycle & Resilience Tests (16 — Excellent)

- App pause/resume: 4 tests (message transition, retry, edge cases)
- Group recovery on resume: 3 tests (inbox drain, retry, stuck sending)
- Connectivity transitions: 2 tests (WiFi ↔ mobile, background → foreground)
- Message retry: 3 tests (query logic, pause → resume → retry)

## Full E2E Tests (22)

- **Real Bridge / Real Transport:** `conversation_bridge_test`, `voice_message_e2e`, `background_reconnect`
- **Posts Phases:** 5 tests (creation, engagement, privacy, pass-along, pinning)
- **Group Recovery:** 2 tests (cursor-based inbox, CLI recovery)
- **Resilience:** `relay_chaos_soak`, `multi_relay_failover`, `soak_e2e`, `wifi_relay_fallback`, `transport_e2e`
- **Performance:** `feed_performance`, `identity_progress_performance`
- **Smoke:** `loading_states`, `bidi_text`, `media_stable_id`, general startup

---

## Highest-Value Remaining Gaps

### High Priority

1. **Named 1:1 reliability regression gate**
   - The repo has strong individual conversation/media/voice/recovery tests, but they are not yet framed as a single always-run gate for shared messaging reliability changes
   - This is the most important process gap because text smoke can pass while media or voice regress
   - Recommendation: define a required pack covering text, media, voice, offline inbox, retry/recovery, and every active send surface touched by the shared pipeline

2. **Notification adapter boundary**
   - Domain behavior is covered, but direct tests around `flutter_notification_service.dart` / `local_notification_support.dart` are still light
   - Recommendation: add a small adapter-focused test suite

3. **Nearby post presence rejection logic**
   - Existing listener coverage is good, but direct tests for blocked senders, stale snapshots, malformed timestamps, and sender mismatch remain valuable
   - Recommendation: add focused tests around `handle_incoming_post_presence_use_case.dart`

4. **Identity → Contact Request → Messaging golden path**
   - A single top-to-bottom onboarding flow is still useful as a confidence test
   - Recommendation: add only one happy-path integration test, not a new matrix of onboarding permutations

### Medium Priority

5. **Announcement-specific create-group flow**
   - Announcement send/read/reaction coverage exists, but create-group coverage is still mostly chat-focused

6. **Secure-storage plugin boundary**
   - Only worth adding if the team sees real plugin regressions on device

---

## Strengths

- Comprehensive fakes (`TestUser`, `GroupTestUser`, `PostTestUser`) support realistic multi-user simulation
- Excellent lifecycle and resilience coverage
- Full migration chain already tested
- Group invite/join/message flow already covered
- Notification deep-link/open flow already covered
- Share-to-contact flows already covered
- Profile-picture broadcast scenarios are already stronger than the first pass suggested

## Weaknesses

- Adapter/plugin boundaries are lighter than pure domain/use-case layers
- High-risk shared pipelines are not yet enforced as named regression gates in CI
- There is still no single “golden path” onboarding test from identity creation through first message
- QR coverage is stronger at logic and wired-UI layers than at full cross-feature integration
- Push coverage is strong in unit/open-flow logic, lighter in platform-adapter specifics
- Feed integration remains more presentation-oriented than transport/durability-oriented
