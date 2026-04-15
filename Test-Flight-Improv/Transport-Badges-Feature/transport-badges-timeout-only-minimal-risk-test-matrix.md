# Timeout-Only Minimal-Risk Test Matrix

## Scope

- Proposed change:
  change only `interactiveDirectBudget` in
  `lib/features/conversation/application/send_chat_message_use_case.dart`
  from `4000 ms` to `2000 ms`
- No routing rewrite
- No WiFi-first policy change
- No badge-truth redesign
- No `P2PServiceImpl` / bridge / inbox protocol change

## What This Change Can Improve

- Hanging Go sends fall through faster
- Sender reaches inbox fallback faster
- Worst-case interactive wait gets shorter

## What This Change Does Not Fix

- Same-WiFi still showing `relay`
- Warm Go reuse winning before local WiFi
- Badge truth problems caused by route selection

## Real Blast Radius

- Directly affected:
  - `send_chat_message_use_case.dart`
  - `send_voice_message_use_case.dart`
  - 1:1 image/video final metadata send via `conversation_wired.dart`
  - share-to-contact via `share_batch_delivery_coordinator.dart`
  - feed inline 1:1 reply via `feed_wired.dart`
- Also affected because they import and reuse the same interactive budgets:
  - `introduction_outbound_delivery.dart`
  - `delete_message_use_case.dart`
- Not affected by this exact constant-only change:
  - `send_contact_request_use_case.dart`
  - group send policy in `send_group_message_use_case.dart`
  - settings/posts lower-level transport clients, unless more than the constant
    ends up changing

## Expected Behavior Change

- Acceptable:
  - slow/hanging direct or relay sends may fall through to inbox earlier
  - some formerly `sent via direct/relay after ~3-4s` cases may now become
    `inbox` sooner
- Not acceptable:
  - new duplicate rows
  - new failures on healthy fast direct/relay paths
  - intro/delete regressions
  - voice/image/video send flow regressions
  - any group behavior change

## Exact Must-Run Matrix

### Tier 0: Direct Seam

- `flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart`
- `flutter test --no-pub test/core/resilience/f1_wifi_relay_fallback_test.dart`
- `flutter test --no-pub test/core/resilience/f2_transport_switch_recovery_test.dart`
- `flutter test --no-pub test/core/resilience/c2_ack_drop_test.dart`
- `flutter test --no-pub test/core/resilience/c3_half_open_test.dart`
- `flutter test --no-pub test/core/services/p2p_service_fault_injection_test.dart`

Reason:
these are the closest tests for timeout, ACK loss, half-open send behavior,
truthful transport persistence, and fallback to inbox.

### Tier 1: Direct Callers / Shared Budget Users

- `flutter test --no-pub test/features/conversation/application/send_voice_message_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/application/delete_message_use_case_test.dart`
- `flutter test --no-pub test/features/introduction/application/introduction_outbound_delivery_test.dart`

Reason:
voice reuses `sendChatMessage`, and intro/delete reuse the same interactive
budget constants.

### Tier 2: 1:1 Flow Integrations

- `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart`
- `flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `flutter test --no-pub test/features/conversation/integration/media_attachment_flow_test.dart`
- `flutter test --no-pub test/features/conversation/integration/media_retry_smoke_test.dart`
- `flutter test --no-pub test/features/conversation/integration/voice_message_exchange_test.dart`
- `flutter test --no-pub test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `flutter test --no-pub test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `flutter test --no-pub test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `flutter test --no-pub test/features/conversation/integration/quote_reply_thread_test.dart`
- `flutter test --no-pub test/integration/relay_down_degradation_integration_test.dart`

Reason:
these prove the full 1:1 user flows still work when the direct/relay wait
window is shorter.

### Tier 3: Direct Wrappers

- `flutter test --no-pub test/features/share/application/share_batch_delivery_coordinator_test.dart`
- `flutter test --no-pub test/features/share/integration/share_to_contact_smoke_test.dart`
- `flutter test --no-pub test/features/feed/presentation/screens/feed_wired_test.dart`

Reason:
Share and Feed call `sendChatMessage(...)` directly, so they inherit the shorter
foreground timeout even if their own files are untouched.

### Tier 4: Named Gates

- `./scripts/run_test_gates.sh 1to1`
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport`

Reason:
this gives a repo-native confidence pass across the expected 1:1 and transport
smokes without pretending it is a full-repo proof.

### Tier 5: Device / Simulator Proof

- `FLUTTER_DEVICE_ID=<device-id> flutter test -d <device-id> integration_test/wifi_transport_test.dart`
- `FLUTTER_DEVICE_ID=<device-id> flutter test -d <device-id> integration_test/wifi_relay_fallback_smoke_test.dart`
- `FLUTTER_DEVICE_ID=<device-id> flutter test -d <device-id> integration_test/background_reconnect_test.dart`
- `FLUTTER_DEVICE_ID=<device-id> flutter test -d <device-id> integration_test/transport_e2e_test.dart`
- `FLUTTER_DEVICE_ID=<device-id> flutter test -d <device-id> integration_test/media_stable_id_smoke_test.dart`

Reason:
this is the minimum device-backed check that shorter interactive timeouts do not
break transport orchestration on a real engine-backed run.

## Conditional Widening Rules

Only widen beyond the matrix above if the implementation changes more than the
single timeout constant.

### If any shared transport helper changes

- `flutter test --no-pub test/features/contact_request/application/send_contact_request_use_case_test.dart`
- `flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart`
- `flutter test --no-pub test/features/contact_request/integration/key_exchange_retry_flow_test.dart`
- `flutter test --no-pub test/features/introduction/integration/intro_wiring_smoke_test.dart`

### If `P2PServiceImpl`, inbox semantics, or local discovery changes

- `flutter test --no-pub test/features/settings/application/upload_profile_picture_use_case_test.dart`
- `flutter test --no-pub test/features/settings/integration/profile_picture_flow_test.dart`
- `flutter test --no-pub test/features/posts/improvement/post_delivery_runner_test.dart`
- `flutter test --no-pub test/features/posts/improvement/post_delivery_runner_parallel_test.dart`
- `flutter test --no-pub test/features/posts/improvement/post_follow_on_delivery_test.dart`

### If any group file changes, or any lower shared transport code changes

- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart`

## Ship / No-Ship Rule

### Ship only if all of these are true

- Tier 0 through Tier 5 pass, or device tests are skipped only for documented
  pre-existing environment reasons
- no new failures appear in intro/delete/voice/share/feed
- no unexpected change appears in final transport truth for healthy fast paths
- no group behavior changes are observed

### Do not ship if any of these happen

- a healthy direct/relay path that used to pass now falls to inbox in host
  deterministic tests without an updated explicit expectation
- intro or delete-message regress
- media/voice flows start failing or leaving stuck rows
- transport gate turns red
- device runs show obvious new timeout flake or delayed send UX

## Known Environment Caveats

- `integration_test/background_reconnect_test.dart` may skip on this macOS setup
  after `Failed to foreground app; open returned 1`
- `integration_test/transport_e2e_test.dart` in self-contained mode is useful,
  but it is not the same as a real peer-backed acceptance proof
- `integration_test/wifi_relay_fallback_smoke_test.dart` without a real peer
  fixture is still smoke, not a full same-WiFi proof

## Recommendation

If you want the safest possible experiment, this timeout-only change is the
lowest-risk path worth trying. But it should be treated as:

- a responsiveness tweak
- not a routing fix
- not a badge-truth fix
- only shippable after the matrix above is green
