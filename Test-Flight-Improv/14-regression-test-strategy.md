# Regression Test Strategy

**Goal:** Catch future breakage with the tests already in the repo, plus a small number of targeted missing regressions
**Model:** Small baseline on every PR + named subsystem regression gates + heavier nightly / release confidence tests

---

## Executive Summary

The repo already has enough test infrastructure to build a practical regression strategy. The main gap is **not** “write many more smoke tests.” The real gap is that high-blast-radius changes are not always forced through the right existing suites.

The safest lean model is:

1. Run a small **baseline gate** on every PR
2. Run a **change-based regression gate** when shared pipelines change
3. Keep real transport / recovery / device-backed tests in **nightly or release** gates
4. Add **one permanent regression test** for every production bug that escapes

This strategy keeps the suite understandable while still catching failures like “text still sends, but voice or media broke after a reliability change.” The current correction is that the gates are **not fully frozen yet**: they still need a one-time inventory pass so every important existing test is either assigned to a gate, marked nightly-only, or intentionally left out with a reason.

---

## Regression Model

| Layer | Purpose | When to Run |
|------|---------|-------------|
| **Baseline Gate** | Catch broad app breakage quickly | Every PR |
| **Subsystem Regression Gates** | Catch neighboring failures in shared pipelines | When that subsystem changes |
| **Nightly / Release Gate** | Catch real transport / resume / device issues | Nightly, pre-release, or before risky merges |

---

## Sufficiency Boundary

For this repo, a planning session is **sufficient** when it is good enough to safely execute the next session without hidden structural gaps. It does **not** need to pre-resolve every individual test classification question.

### Session 1 Is Sufficient When

- deliverables are fixed
- the reference source of truth is fixed
- the execution order is fixed
- the scope guard is fixed
- the bulk-classification policy is fixed
- the completeness-check step is fixed
- the explicit decision points are fixed
- no reviewer is finding a new **structural category** of missing work

### Structural Category vs Incremental Detail

| Type | Examples |
|------|----------|
| **Structural blocker** | missing directory class such as `test/core/services/`, wrong source of truth, wrong deliverable path, wrong execution order, missing completeness policy |
| **Incremental detail** | one more candidate test file, a likely alternate gate placement, wording cleanup, a better note in the reference doc |

Additional review rounds are only justified for **structural blockers**. Once reviews only surface incremental details, Session 1 should proceed.

### Bulk-Classification Policy

Session 1 does **not** need to individually gate-assign every one of the repo’s 500+ tests.

The completeness check should explicitly classify:

- `integration_test/` files
- cross-feature integration tests under `test/`
- `test/core/services/`
- `test/core/lifecycle/`
- `test/core/resilience/`
- other service, transport, or orchestration tests that sit between unit tests and full integration/device flows

Feature-local unit/widget tests under `test/features/<feature>/` that do not cross feature boundaries are implicitly covered by feature-level test runs and do not need individual gate assignment in Session 1.

---

## What We Already Have

### 1. Baseline Gate Candidates

| Test | Coverage |
|------|----------|
| `startup_router_recovery_test.dart` | Startup routing / recovery path does not hang or misroute |
| `qr_scanner_wired_test.dart` | QR scan wiring still works |
| `offline_inbox_roundtrip_test.dart` | 1:1 offline inbox send / receive still works |
| `loading_states_smoke_test.dart` | Loading / startup smoke |
| `posts_phase1_fake_test.dart` | Posts creation / delivery / replay still works |
| `group_messaging_smoke_test.dart` | Group publish / receive flow when groups are in release scope |

### 2. Existing Subsystem Regression Coverage

| Gate | Existing Tests | What It Already Covers |
|------|----------------|------------------------|
| **1:1 Reliability** | `two_user_message_exchange_test.dart`, `offline_inbox_roundtrip_test.dart`, `media_attachment_flow_test.dart`, `media_retry_smoke_test.dart`, `voice_message_exchange_test.dart`, `incomplete_upload_recovery_test.dart`, `send_then_lock_delivery_test.dart`, `stuck_sending_recovery_test.dart`, `quote_reply_thread_test.dart` | Text, media, voice, retry, resume, offline inbox, quote/reply behavior |
| **Feed / Conversation Surface** | `feed_card_flow_test.dart`, `expanded_collapsed_card_test.dart` | Feed card orchestration and state transitions |
| **Groups / Recovery** | `group_messaging_smoke_test.dart`, `group_resume_recovery_test.dart`, `invite_round_trip_test.dart`, `group_membership_smoke_test.dart` | Group send / receive / recovery plus invite/bootstrap policy locks such as future-only new-member history, offline re-invite replay, unread correctness across duplicate/retry recovery, mixed-content text preservation through delivery plus notification preview, member-list convergence after offline membership churn, and the large-attachment overflow/compress contract that leaves no broken pending state |
| **Posts / Privacy** | `posts_phase1_fake_test.dart`, `post_presence_listener_test.dart` | Posts flow plus key presence listener validation |
| **Contact / Onboarding** | `contact_request_flow_test.dart` | Request acceptance and contact creation |
| **Startup / Transport Confidence** | `background_reconnect_test.dart`, `wifi_relay_fallback_smoke_test.dart`, `transport_e2e_test.dart`, `media_stable_id_smoke_test.dart` | Resume, transport fallback, real-stack orchestration, media ID stability |

### 3. What This Means

- The repo already has strong regression **building blocks**
- The weak point is **gate definition and trigger discipline**
- Shared-path changes currently rely too much on people remembering which neighboring tests to run

---

## Gate Definition Rules

Before the gate script is written, the repo needs one classification pass across the current test inventory.

### Rules

1. **Use explicit file lists, not folder shortcuts**
   - `flutter test test/features/conversation/integration` is too broad and can silently include files that are not actually part of the gate definition
   - Every gate should name each file explicitly
2. **Classify every high-value existing test**
   - Each candidate should end up in one of these buckets:
     - always-run gate
     - nightly / release-only gate
     - optional/manual reference test
     - intentionally out of gate
   - Feature-local unit/widget tests can stay implicitly covered by feature-level runs unless they cross feature boundaries or service/orchestration layers
3. **Do not hide red tests by omission**
   - If an existing test is currently failing, document it as a known failure instead of dropping it from the gate definition without explanation
4. **Startup / Transport gates are device-aware**
   - The gate definition must document a `--device <id>` requirement or equivalent
   - Session 1 does **not** need full simulator/device automation; a pass-through flag or documented manual command is enough
5. **Run a completeness check before freezing the gates**
   - After classification, diff all `*_test.dart` files under `test/` and `integration_test/` against the combined gate lists
   - Every remaining file should be intentionally classified as nightly-only, optional/manual, performance-only, or explicitly out of gate with a reason
6. **Start from the current gate lists in this file as the draft**
   - Session 1 should treat the definitions below as the initial draft and patch them during classification
   - It should not start the gate inventory from scratch unless a draft section is proven wrong

### Current Inventory Still To Classify or Revalidate

These files are visible in the current repo and should be explicitly evaluated during the gate-definition pass:

| Area | Files to Classify |
|------|-------------------|
| **Conversation integration** | `emoji_reaction_exchange_test.dart` |
| **Feed integration** | `feed_color_smoke_test.dart` |
| **Groups integration** | `group_edge_cases_smoke_test.dart`, `invite_round_trip_test.dart`, `group_membership_smoke_test.dart`, `group_startup_rejoin_smoke_test.dart` |
| **Posts integration** | `posts_phase2_fake_test.dart`, `posts_phase3_fake_test.dart`, `posts_phase4_fake_test.dart`, `posts_phase5_fake_test.dart` |
| **Startup / transport draft-gate validation** | `background_reconnect_test.dart`, `media_stable_id_smoke_test.dart`, `wifi_relay_fallback_smoke_test.dart`, `transport_e2e_test.dart` |
| **Duplicate / canonical-path decision** | `integration_test/loading_states_smoke_test.dart` and `test/features/loading_states_smoke_test.dart` must be classified separately; current draft keeps the `integration_test/` file as the canonical baseline smoke |
| **Core services triage** | `test/core/services/` (23 test files plus helper fake) including `pending_message_retrier_test.dart`, `pending_message_retrier_stuck_sending_test.dart`, `pending_message_retrier_upload_ordering_test.dart`, `incoming_message_router_test.dart`, `incoming_message_router_posts_test.dart`, `incoming_message_router_profile_test.dart`, `p2p_service_impl_test.dart`, `p2p_service_fault_injection_test.dart`, `p2p_service_stop_race_test.dart`, `p2p_service_addresses_updated_test.dart`, `contact_request_listener_test.dart`, `pending_post_delivery_retrier_test.dart` |
| **Core resilience triage** | `test/core/resilience/` (8 files) including `f1_wifi_relay_fallback_test.dart`, `f2_transport_switch_recovery_test.dart`, `network_failover_test.dart`, `network_chaos_test.dart`, `soak_test.dart` |
| **Core lifecycle triage** | `test/core/lifecycle/` (15 files) including `pause_resume_retry_smoke_test.dart`, `app_lifecycle_recovery_test.dart`, `background_reconnect_smoke_test.dart`, `handle_app_resumed_upload_ordering_test.dart`, `handle_app_resumed_group_recovery_test.dart` |
| **Cross-feature integration triage** | `test/features/introduction/integration/intro_wiring_smoke_test.dart`, `test/features/introduction/integration/introduction_multi_node_test.dart`, `test/features/introduction/integration/introduction_smoke_test.dart`, `test/features/contact_request/integration/key_exchange_retry_flow_test.dart`, `test/features/settings/integration/profile_picture_flow_test.dart`, `test/features/share/integration/share_to_contact_smoke_test.dart`, `test/integration/notification_deeplink_integration_test.dart`, `test/integration/rapid_lock_unlock_integration_test.dart`, `test/integration/relay_down_degradation_integration_test.dart` |
| **Device / transport / soak / misc integration** | `smoke_test.dart`, `conversation_bridge_test.dart`, `wifi_transport_test.dart`, `voice_message_e2e_test.dart`, `group_recovery_e2e_test.dart`, `group_recovery_cli_e2e_test.dart`, `multi_relay_failover_test.dart`, `relay_chaos_soak_test.dart`, `soak_e2e_test.dart`, `bidi_text_smoke_test.dart`, `feed_performance_test.dart`, `identity_progress_performance_test.dart` |

The point of this pass is not to force all of these into an always-run gate. The point is to make sure none of them are forgotten.

---

## Regressions We Still Need to Add

| # | Regression to Add | Priority | Why It Matters |
|---|-------------------|----------|----------------|
| 1 | **Feed inline reply → durable 1:1 send regression** | HIGH | Current 1:1 coverage is strongest from the conversation screen; feed-originated send durability is the clearest remaining gap |
| 2 | **Named 1:1 reliability gate in CI** | HIGH | Existing text/media/voice/retry tests already exist, but they need to run together automatically when the shared pipeline changes |
| 3 | **Notification adapter boundary tests** | HIGH | Good domain coverage exists, but direct notification wiring coverage is still light |
| 4 | **Blocked / stale / malformed post presence cases** | HIGH | Existing presence coverage is meaningful, but the rejection matrix is still incomplete |
| 5 | **Announcement-specific create → send → read → react happy path** | MEDIUM | Behavior exists, but evidence is still split across multiple files |
| 6 | **One onboarding golden path** | MEDIUM | Identity → contact request → first message remains useful as a concise confidence flow |

### Do Not Add By Default

- Do **not** add more generic smoke tests unless a real top-level flow is still uncovered
- Do **not** create duplicate tests that only restate existing conversation, group, or posts behavior from a slightly different angle
- Do **not** push every regression into `integration_test/` if a deterministic `test/` integration already proves it

---

## Named Regression Gates

### 1. Baseline Gate

Run on every PR:

- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `integration_test/loading_states_smoke_test.dart`
- `integration_test/posts_phase1_fake_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart` when groups are active release scope

Current draft decision:
- `integration_test/loading_states_smoke_test.dart` is the canonical baseline loading smoke
- `test/features/loading_states_smoke_test.dart` is a lighter widget/render smoke and must be classified separately during Session 1

### 2. 1:1 Reliability Gate

Run when changes touch shared 1:1 messaging code such as:

- send
- retry
- upload
- listener / receive
- offline inbox
- feed-originated 1:1 send entry points

Run:

- `test/features/conversation/integration/two_user_message_exchange_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/media_retry_smoke_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/quote_reply_thread_test.dart`

Coverage rule:

| Axis | Required Coverage |
|------|-------------------|
| **Payload** | Text, media, voice |
| **State** | Online, offline inbox, retry, resume-after-interruption |
| **Surface** | Conversation screen plus any other active send surface |

Current draft decision:
- the 1:1 Reliability Gate currently includes **9** tests, including `quote_reply_thread_test.dart`
- Session 1 should keep or reclassify that file intentionally, but it should not rediscover the 8-vs-9 question by accident

### 3. Feed / Surface Gate

Run when feed cards, feed composer, inline reply, or feed-to-conversation handoff changes:

- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`
- plus the **1:1 Reliability Gate** if feed can trigger message sending

### 4. Group Messaging Gate

Run when group send, receive, retry, resume, invite, or announcement behavior changes:

- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart` when onboarding / invite / membership entry flows are involved

### 5. Posts / Privacy Gate

Run when posts delivery, nearby presence, privacy filters, or replay behavior changes:

- `integration_test/posts_phase1_fake_test.dart`
- `integration_test/posts_phase2_fake_test.dart`
- `integration_test/posts_phase3_fake_test.dart`
- `integration_test/posts_phase4_fake_test.dart`
- `integration_test/posts_phase5_fake_test.dart`
- `test/features/posts/phase3/post_presence_listener_test.dart`

### 6. Startup / Transport Gate

Run when bridge, resume, transport fallback, reconnect, or app bootstrap changes:

- `integration_test/background_reconnect_test.dart`
- `integration_test/wifi_relay_fallback_smoke_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/media_stable_id_smoke_test.dart` if media path / persistence changed

Current draft decision:
- Session 1 only needs to document the device requirement clearly
- Full `--device <id>` automation can remain a follow-up if the reference doc and raw commands are explicit

### 7. Nightly / Release Confidence Pool

These tests are valuable, but they should be explicitly classified as nightly/release-only unless Session 1 decides otherwise:

- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/relay_chaos_soak_test.dart`
- `integration_test/soak_e2e_test.dart`
- `integration_test/bidi_text_smoke_test.dart`
- `integration_test/feed_performance_test.dart`
- `integration_test/identity_progress_performance_test.dart`

---

## What to Run When

### 1. When Creating a New Feature

Minimum requirement:

| Requirement | Why |
|-------------|-----|
| Unit / use-case tests for the new logic | Proves the feature contract directly |
| One happy-path integration test | Proves orchestration, not just isolated logic |
| One boundary or failure-path test | Proves the new flow does not collapse on first error |
| Baseline Gate | Catches broad unrelated regressions |
| Relevant subsystem gate if the feature touches shared code | Protects neighboring capabilities |

Practical rule:

- If the new feature is isolated, run its direct tests plus the Baseline Gate
- If the new feature touches messaging, groups, posts, startup, transport, or notifications, also run that subsystem gate

### 2. When Improving an Existing Feature

Minimum requirement:

| Requirement | Why |
|-------------|-----|
| Direct tests for the feature being improved | Confirms intended behavior still works |
| Relevant subsystem gate | Catches neighboring paths that share the same pipeline |
| Baseline Gate | Catches broad app breakage |

Examples:

- Improving 1:1 reliability means running the **full 1:1 Reliability Gate**, not just text-message tests
- Improving feed inline messaging means running the **Feed / Surface Gate** and the **1:1 Reliability Gate**
- Improving group recovery means running the **Group Messaging Gate** and possibly the **Startup / Transport Gate**

### 3. When Fixing a Bug

Minimum requirement:

| Requirement | Why |
|-------------|-----|
| Add one regression test that reproduces the bug | Prevents the bug from returning silently |
| Run the direct suite containing the bug fix | Confirms the fix works |
| Run the relevant subsystem gate | Protects nearby behavior |
| Run the Baseline Gate | Catches broad breakage introduced during the fix |

Escaped-bug rule:

- Every production bug should leave behind a permanent regression test
- If the bug involved data loss, retry, resume, transport, media, or voice, add both:
  - the lowest-layer deterministic test
  - one orchestration test above it

---

## Suggested Run Commands

These commands are the intended explicit-file model. Session 1 should freeze the final gate file lists after the classification pass.

### Planned Gate Reference Artifacts

- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

Recommended format for `test-gate-definitions.md`:
- one markdown table per gate
- exact file paths
- trigger rules
- nightly/manual/out-of-gate classifications
- known failures / temporary exclusions with reasons

### Baseline Gate

```bash
flutter test \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  integration_test/loading_states_smoke_test.dart \
  integration_test/posts_phase1_fake_test.dart
```

### 1:1 Reliability Gate

```bash
flutter test \
  test/features/conversation/integration/two_user_message_exchange_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  test/features/conversation/integration/media_attachment_flow_test.dart \
  test/features/conversation/integration/media_retry_smoke_test.dart \
  test/features/conversation/integration/voice_message_exchange_test.dart \
  test/features/conversation/integration/incomplete_upload_recovery_test.dart \
  test/features/conversation/integration/send_then_lock_delivery_test.dart \
  test/features/conversation/integration/stuck_sending_recovery_test.dart \
  test/features/conversation/integration/quote_reply_thread_test.dart
```

### Feed / Surface Gate

```bash
flutter test \
  test/features/feed/integration/feed_card_flow_test.dart \
  test/features/feed/integration/expanded_collapsed_card_test.dart \
  test/features/feed/integration/feed_color_smoke_test.dart
```

### Group Messaging Gate

```bash
flutter test \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  test/features/groups/integration/group_resume_recovery_test.dart \
  test/features/groups/integration/group_edge_cases_smoke_test.dart \
  test/features/groups/integration/invite_round_trip_test.dart \
  test/features/groups/integration/group_membership_smoke_test.dart \
  test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

### Posts / Privacy Gate

```bash
flutter test \
  integration_test/posts_phase1_fake_test.dart \
  integration_test/posts_phase2_fake_test.dart \
  integration_test/posts_phase3_fake_test.dart \
  integration_test/posts_phase4_fake_test.dart \
  integration_test/posts_phase5_fake_test.dart \
  test/features/posts/phase3/post_presence_listener_test.dart
```

### Startup / Transport Gate

```bash
# Target interface after Session 1; the initial script may leave this as a
# documented TODO/manual invocation so long as the raw commands are recorded.
./scripts/run_test_gates.sh startup_transport --device <device>
```

Raw equivalent:

```bash
flutter test integration_test/background_reconnect_test.dart -d <device>
flutter test integration_test/wifi_relay_fallback_smoke_test.dart -d <device>
flutter test integration_test/transport_e2e_test.dart -d <device>
```

### Known Failure Handling

If any currently assigned test is red while the gates are being defined:

- keep it in the reference inventory
- document it as a known failure
- do not silently remove it from the intended gate without a reason

### Completeness Check

Before Session 1 is considered done:

- compare all `*_test.dart` files under `test/` and `integration_test/` with the combined gate/reference lists
- verify every unmatched integration/cross-feature/service/orchestration file is intentionally categorized
- allow feature-local unit/widget tests to remain implicitly covered by feature-level test runs
- record any unresolved stragglers in `Test-Flight-Improv/test-gate-definitions.md`

### Review Exit Rule

If you use separate planner/reviewer/arbiter passes:

- allow at most one planner pass
- allow at most one reviewer pass
- allow one arbiter pass only if the review still claims the plan is insufficient

Stop and execute Session 1 when the arbiter finds no new structural category of missing work. Do **not** loop again just because more individual files could be discussed.

---

## Review Checklist

- [ ] Baseline Gate runs on every PR
- [ ] Shared-path changes trigger the matching subsystem gate
- [ ] Every escaped production bug adds a permanent regression test
- [ ] New features have at least one happy-path test and one failure-path test
- [ ] Improvements to shared messaging run text + media + voice + retry coverage
- [ ] Device / transport tests stay in nightly or release gates unless the change is transport-critical
- [ ] The team adds targeted regressions before adding broad new smoke files

---

## Verdict

**The repo already has enough tests to support a strong regression strategy.** The missing piece is operational discipline: define named gates, run them based on blast radius, and add one permanent regression for each escaped bug. That is the simplest way to get higher confidence without overengineering the test architecture.
