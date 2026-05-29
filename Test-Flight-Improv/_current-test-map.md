# Current Test Map

Generated: `2026-04-06`

## Purpose

This is the compact human-facing runbook for the current app test surface.

Use it to answer:

- what tests already protect a feature or user journey
- which command to run first
- whether that coverage belongs to a named gate, a direct suite, a nightly
  pool, or a manual simulator journey

This document is intentionally compact. It is not the full archive and it is
not a file-by-file replacement for the deeper audits under
`Test-Flight-Improv/`.

## Source Of Truth

- For named regression gates, `scripts/run_test_gates.sh` wins.
- For gate rationale and classification, see
  `Test-Flight-Improv/test-gate-definitions.md`.
- For operator-facing gate usage, see
  `Test-Flight-Improv/test-gates-reference.md`.
- For manual simulator journeys, see
  `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`.
- For automated evidence against those journeys, see
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.

## Fast Commands

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh posts
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

For one targeted test:

```bash
flutter test --no-pub <test-file>
```

For a single integration-backed test on a chosen device:

```bash
flutter test -d <device-id> <integration_test-file>
```

## Named Gates

| Gate | Use It When | Command | Canonical Coverage |
|---|---|---|---|
| Baseline | Broad PR safety check | `./scripts/run_test_gates.sh baseline` | Startup routing, QR, offline inbox roundtrip, loading smoke, posts phase 1, group messaging smoke |
| 1:1 Reliability | Shared conversation send, retry, upload, listener, inbox, or feed-originated 1:1 send changes | `./scripts/run_test_gates.sh 1to1` | Text, media, voice, retry, resume, offline inbox, quote/reply |
| Feed / Surface | Feed cards, inline reply, feed-to-conversation handoff | `./scripts/run_test_gates.sh feed` | Feed card flow, expanded/collapsed state, feed color smoke |
| Intro / Reintroduction | Intro send, accept, pass, listener, picker, reintroduction behavior | `./scripts/run_test_gates.sh intro` | Core intro application tests plus wiring, multi-node, and regression coverage |
| Group Messaging | Group send, invite, resume, membership, metadata/photo authority, announcement-adjacent behavior | `./scripts/run_test_gates.sh groups` | Group messaging smoke, admin metadata/photo convergence, resume recovery, edge cases, invite round trip, membership, startup rejoin |
| Posts / Privacy | Posts delivery, replay, presence, privacy filters | `./scripts/run_test_gates.sh posts` | Posts phases 1-5 plus post presence listener |
| Startup / Transport | Resume, reconnect, bootstrap, relay fallback, transport | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` | Background reconnect, WiFi fallback, transport e2e, media stable ID |

## Area Map

| Area / Journey | First Thing To Run | Then Run When Needed | Notes |
|---|---|---|---|
| Startup / bootstrap | `./scripts/run_test_gates.sh baseline` | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` | Baseline catches routing/loading breakage; transport gate catches real reconnect/fallback seams |
| Contact bootstrap / QR | `./scripts/run_test_gates.sh baseline` | `flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart` | Use the direct contact flow when request acceptance or key-exchange behavior changes |
| 1:1 text / media / voice reliability | `./scripts/run_test_gates.sh 1to1` | direct files under `test/features/conversation/integration/` as needed | This is the main shared-pipeline gate; production messaging bugs should usually add a permanent regression here or beside it |
| Feed-originated messaging surfaces | `./scripts/run_test_gates.sh feed` | also run `./scripts/run_test_gates.sh 1to1` if feed can send 1:1 messages | Feed UI regressions can pass while send-path regressions fail, so use both when feed enters the shared 1:1 pipeline |
| Intro / reintroduction | `./scripts/run_test_gates.sh intro` | direct Orbit/Feed follow-up tests when intro changes surface there | `orbit_intros_wiring` and specific `feed_wired` intro follow-up assertions stay outside the frozen gate lists |
| Groups / group recovery | `./scripts/run_test_gates.sh groups` | `cd go-mknoon && go test ./node -run 'TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestFilterDiscoveredGroupMembers_ExcludesNonMembers|TestFilterDiscoveredGroupMembers_AllowsAllWhenMemberSetEmpty'` plus `cd go-mknoon && go test ./bridge -run 'TestGroupPublish_ResponseIncludesTopicPeers'` when live topic peer formation, known-member dialing, warm-retry pacing, discovered-peer membership filtering, or `topicPeers` delivery lag changes; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "publish timeout with inbox success keeps the message successful in UI"`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "10-B acceptance uses real GroupConversationWired sender path for media + resume fallback"` when sender-side publish-timeout fallback, durable media staging, or resume recovery behavior changes; and `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` when admin Members invite-status display, accepted-member `Joined` rendering, or durable `member_joined` overlay behavior changes | Use this for invite, membership, resume, metadata/photo authority, promoted-admin invite propagation, and delivery behavior; the direct Go regressions cover the discovery-loop peer-formation seam before circuit-address wait, pre-relay direct dialing, warm-retry progression, and stale non-member filtering, while the Flutter regressions keep the designed `success_no_peers`, offline-inbox fallback behavior, real sender-path media resume recovery, promoted-admin metadata/photo convergence, accepted-member Members-screen `Joined` display, and C-to-creator delivery after promoted-admin invite pinned |
| Group/profile media metadata | `./scripts/run_test_gates.sh groups` | `flutter test --no-pub test/features/settings/integration/profile_picture_flow_test.dart` | Keep this direct suite in mind when profile media broadcast/download behavior changes |
| Posts / privacy / nearby presence | `./scripts/run_test_gates.sh posts` | direct posts listener/use-case tests as needed | Posts phases 1-5 are the current high-level confidence pack |
| Notifications / deep links | `./scripts/run_test_gates.sh baseline` | `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`; `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`; `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`; `flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart`; `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` when group push open, remote/local dedupe identity, pending-invite recovery, or Orbit intro redirect behavior changes | Keep notification routing as direct suites unless/until gate definitions intentionally widen; pair the group replay-dedupe integration with the `show_notification_use_case` route-payload suppression regression when one visible remote push must not become a second local notification later. The group route-resolution regression still covers receiver-side recovery only; it does not prove sender-side invite delivery or admin-member-list parity |
| Onboarding confidence | run baseline plus direct feature suites | `flutter test --no-pub test/integration/onboarding_golden_path_test.dart` | Useful confidence flow, intentionally kept outside frozen named gates |

## Manual Journey References

| Purpose | Doc |
|---|---|
| Manual two/three-simulator user journeys | `Test-Flight-Improv/50-two-simulator-user-journey-tests.md` |
| Mapping of those journeys to automated evidence | `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md` |
| Group-chat matrix and rule closure | `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` |

## Nightly / Release Pool

These are intentionally outside the named gates because they are heavier,
device-bound, real-stack, or soak-style confidence tests:

- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/group_recovery_e2e_test.dart`
- `integration_test/group_recovery_cli_e2e_test.dart`
- `integration_test/scripts/run_group_invite_status_matrix_sim.dart` (four-iOS-simulator seeded creator-side Members invite-status display proof)
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/relay_chaos_soak_test.dart`
- `integration_test/soak_e2e_test.dart`
- `integration_test/bidi_text_smoke_test.dart`

## Maintenance Rules

- When a production bug escapes, prefer adding one permanent regression test
  rather than broadening smoke by default.
- When a named gate changes, update:
  - `scripts/run_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/test-gates-reference.md`
  - this document
- When a feature gets new direct coverage but no gate changes, update only the
  relevant row here.
- When a user-journey contract changes, update the relevant matrix or audit doc
  in addition to this runbook.
- Do not rewrite the whole `Test-Flight-Improv` archive just because one bug
  added one regression test.
