# Current Test Map

Updated: `2026-07-15`

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
- For the critical-feature umbrella, `./scripts/run_test_gates.sh sims ...`
  and the repo-owned typed manifest/planner win; the `$sims` skill only
  delegates to that CLI.
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
# Safe pre-major-update default; inspect before executing.
.claude/skills/sims/scripts/run_with_devices.sh --list
./scripts/run_test_gates.sh sims major --list

# Faster/deeper diagnostic reliability modes (not release-green by themselves).
./scripts/run_test_gates.sh sims smoke --list
./scripts/run_test_gates.sh sims full --list

./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh posts
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Current Plan-258 status: the orchestration/cache/scheduler/device-resolution
stack and all active campaign drivers are implemented. The logical `major`
plan has 26 active rows, six declared reusable device build profiles, and 11
device/campaign consumers. Live preflight—not missing-driver placeholders—now
decides whether each campaign can run: absent policy-bounded topology is `N/A`,
while missing provider, relay, signing, staging, or disposable-iOS-receiver
attestation is `BLOCKED`. Android campaigns restore the exact pre-run APK,
private app data, permissions, process, and relevant OS state before PASS. The
Android recorder and performance campaign reuse the centrally prepared
`android.e2e.standard` APK through an acknowledged runtime tuple; performance
keeps four strict budgets: FEED average build `<8 ms`, FEED build p99 `<24 ms`,
FEED worst build `<100 ms`, and production Go `node:status` MethodChannel p99
`<50 ms`. This is implementation readiness, not a fabricated clean-major or
unrun live PASS. The iOS-simulator group multi-party adapter remains conditional
on relay configuration and four disposable/restore-safe simulators.
Two future VC-02 capabilities remain inactive and do not participate in or
block the current major gate.
Use `--list` to inspect the logical plan, not as proof that live preflight
passed.

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
| Sims Major | Before a major update or release candidate, and after repairing any failure found by a provisional sims run | `.claude/skills/sims/scripts/run_with_devices.sh` (no mode defaults to `major`), or `./scripts/run_test_gates.sh sims major` | Deduplicated registered critical capabilities across analyzer, Dart host, full Go, native, nested packages, reliability/device campaigns, capture-owned validation, and critical performance. This is the only sims mode eligible for release green |
| Baseline | Broad PR safety check | `./scripts/run_test_gates.sh baseline` | Startup routing, QR, offline inbox roundtrip, loading smoke, posts phase 1, group messaging smoke |
| 1:1 Reliability | Shared conversation send, retry, upload, listener, inbox, or feed-originated 1:1 send changes | `./scripts/run_test_gates.sh 1to1` | Text, media, voice, retry, resume, offline inbox, quote/reply |
| Feed / Surface | Feed cards, inline reply, feed-to-conversation handoff | `./scripts/run_test_gates.sh feed` | Feed card flow, expanded/collapsed state, feed color smoke |
| Intro / Reintroduction | Intro send, accept, pass, listener, picker, reintroduction behavior | `./scripts/run_test_gates.sh intro` | Core intro application tests plus wiring, multi-node, and regression coverage |
| Group Messaging | Group send, invite, resume, membership, metadata/photo authority, announcement-adjacent behavior | `./scripts/run_test_gates.sh groups` | Group messaging smoke, admin metadata/photo convergence, recovery-save feedback, resume recovery, edge cases, invite round trip, membership, startup rejoin |
| Posts / Privacy | Posts delivery, replay, presence, privacy filters | `./scripts/run_test_gates.sh posts` | Posts phases 1-5 plus post presence listener |
| Startup / Transport | Resume, reconnect, bootstrap, relay fallback, transport | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` | Background reconnect, WiFi fallback, transport e2e, media stable ID |

## Area Map

| Area / Journey | First Thing To Run | Then Run When Needed | Notes |
|---|---|---|---|
| Major-update / release confidence | `$sims` or `./scripts/run_test_gates.sh sims major --list` | Execute the unfiltered `major`; `--simultaneous` may reduce safe wall time; after an authorized `--fix-as-you-go` / `--only <stable-id>` / `--resume` loop, run one separate clean `major` | `major` is capability-deduplicated and typed. Only `PASS` or a policy-valid unavailable-target `N/A` satisfies a mandatory row. `full`, `smoke`, filtered, continued, retried, and resumed runs are diagnostic, not release green. Six reusable device profiles serve 11 active device/campaign rows; compatible consumers share their central artifact and no child runner may rebuild. Live targets, credentials/configuration, state-safety policy, and cache contents decide actual builds and verdicts, so the report is authoritative. All active rows have automated drivers; configuration or target blockers remain visible rather than becoming a false PASS. |
| Startup / bootstrap | `./scripts/run_test_gates.sh baseline` | `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` | Baseline catches routing/loading breakage; transport gate catches real reconnect/fallback seams |
| Contact bootstrap / QR | `./scripts/run_test_gates.sh baseline` | `flutter test --no-pub test/features/contact_request/integration/contact_request_flow_test.dart` | Use the direct contact flow when request acceptance or key-exchange behavior changes |
| 1:1 text / media / voice reliability | `./scripts/run_test_gates.sh 1to1` | direct files under `test/features/conversation/integration/` as needed | This is the main shared-pipeline gate; production messaging bugs should usually add a permanent regression here or beside it |
| Feed-originated messaging surfaces | `./scripts/run_test_gates.sh feed` | also run `./scripts/run_test_gates.sh 1to1` if feed can send 1:1 messages | Feed UI regressions can pass while send-path regressions fail, so use both when feed enters the shared 1:1 pipeline |
| Intro / reintroduction | `./scripts/run_test_gates.sh intro` | direct Orbit/Feed follow-up tests when intro changes surface there | `orbit_intros_wiring` and specific `feed_wired` intro follow-up assertions stay outside the frozen gate lists |
| Groups / group recovery | `./scripts/run_test_gates.sh groups` | `cd go-mknoon && go test ./node -run 'TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeCircuitAddressWait|TestGroupPeerDiscoveryLoop_DialsKnownMembersBeforeRelayReadyWhenDirectAddrsKnown|TestGroupPeerDiscoveryLoop_RetriesMissingThirdPeerDuringWarmWindow|TestGroupPeerDiscoveryLoop_UsesWarmRetryImmediatelyAfterPartialInitialRecovery|TestPublishGroupMessage_ReturnsPeerCountPositive_WhenPeersConnected|TestGroupDiscoveryLoop_BacksOffRepeatedDialFailures|TestGroupDiscoveryLoop_DedupesConcurrentPeerDials|TestFilterDiscoveredGroupMembers_ExcludesNonMembers|TestFilterDiscoveredGroupMembers_AllowsAllWhenMemberSetEmpty'` plus `cd go-mknoon && go test ./bridge -run 'TestGroupPublish_ResponseIncludesTopicPeers'` when live topic peer formation, known-member dialing, warm-retry pacing, discovered-peer membership filtering, or `topicPeers` delivery lag changes; `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`; `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "publish timeout with inbox success keeps the message successful in UI"`; `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "10-B acceptance uses real GroupConversationWired sender path for media + resume fallback"` when sender-side publish-timeout fallback, durable media staging, or resume recovery behavior changes; and `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` when admin Members invite-status display, accepted-member `Joined` rendering, durable `member_joined` overlay behavior, or group-details recovery-save feedback changes | Use this for invite, membership, resume, metadata/photo authority, recovery-save feedback, promoted-admin invite propagation, and delivery behavior; the direct Go regressions cover the discovery-loop peer-formation seam before circuit-address wait, pre-relay direct dialing, warm-retry progression, and stale non-member filtering, while the Flutter regressions keep the designed `success_no_peers`, offline-inbox fallback behavior, real sender-path media resume recovery, promoted-admin metadata/photo convergence, accepted-member Members-screen `Joined` display, group details Save waiting/copy/avatar atomicity, and C-to-creator delivery after promoted-admin invite pinned |
| Announcement private media (Plan 242) | `./scripts/run_test_gates.sh groups` | Run the exact eight Plan-242 files registered in `GROUP_TESTS` as one focused `flutter test --no-pub` aggregate | Reuses Plan 238's durable lifecycle and pins current-admin send/receive authority, encrypted-inner-only policy, reader capability denial, generic notification copy, and non-resurrecting terminal/integrity metadata; ordinary announcement and shared-adapter sentinels remain separate preservation coverage |
| Received-media reporting disposition (Plans 244/245) | Run the exact existing preservation commands in the two canonical plans; no reporting-specific test path exists | `./scripts/run_test_gates.sh 1to1` and `./scripts/run_test_gates.sh groups` only when relevant source changes require the broader lane gates | Accepted intentional non-goal: Report, its backend/gateway/outbox/receipt/UI, and any external provisioning gate remain absent. The existing sentinels preserve ordinary actions plus accurately scoped QR/contact Block, invite Accept/Decline, notification-only Mute, and Leave. Plan 246 records the same disposition separately for Track-3/Wave-3. |
| Group/announcement media batch forwarding (Plans 250/251) | Run the exact nine-file focused aggregate registered in `GROUP_TESTS` | `./scripts/run_test_gates.sh groups`, then justified `feature-host-all` and `core-host-all`; run the exact Plan-241 Go writer sentinels from `test-gate-definitions.md` | Shared draft/preflight/delivery plus a one-statement group/member/key-generation authorization snapshot; Plan 250 adds the opt-in discussion-library surface and Plan 251 adds announcement selection, target-policy, opaque-provenance, and source-preservation proof. No per-plan full `host-all` or new device/native leg |
| Go libp2p host fast paths | `./scripts/run_host_test_gates.sh host-all --only go-mknoon/node/libp2p_refactor_contract_test.go`; `./scripts/run_host_test_gates.sh host-all --only go-mknoon/bridge/bridge_entrypoint_contract_test.go` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node -run 'TestGroupDialKnownMembersRunsBoundedParallel|TestDiscoverAndConnectGroupPeersRunsBoundedParallel|TestRunGroupDiscoveryCycleBoundsGlobalGroupDialConcurrency|TestRelaySelectorFanOutRunsDistinctRelaysInParallel' -count=1`; rerun existing group/bridge/dispatcher Go regressions when startup, group peer dialing, relay fan-out, dispatcher pressure, or bridge group handlers change | Host-only coverage for plan 220: startup in-progress/rollback, source-shape budgets, bounded group and relay parallelism, dispatcher queue shape, and bridge entrypoint helper contracts |
| Group/profile media metadata | `./scripts/run_test_gates.sh groups` | `flutter test --no-pub test/features/settings/integration/profile_picture_flow_test.dart` | Keep this direct suite in mind when profile media broadcast/download behavior changes |
| Posts / privacy / nearby presence | `./scripts/run_test_gates.sh posts` | direct posts listener/use-case tests as needed | Posts phases 1-5 are the current high-level confidence pack |
| Notifications / deep links | `./scripts/run_test_gates.sh baseline` | `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`; `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`; `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`; `flutter test --no-pub test/features/push/application/show_notification_use_case_test.dart`; `flutter test --no-pub test/features/push/application/resolve_group_notification_route_target_use_case_test.dart` when group push open, remote/local dedupe identity, pending-invite recovery, or Orbit intro redirect behavior changes | Keep notification routing as direct suites unless/until gate definitions intentionally widen; pair the group replay-dedupe integration with the `show_notification_use_case` route-payload suppression regression when one visible remote push must not become a second local notification later. The group route-resolution regression still covers receiver-side recovery only; it does not prove sender-side invite delivery or admin-member-list parity |
| 1:1 reaction notifications (Plan 256) | `flutter test --no-pub test/features/conversation/integration/reaction_notification_pipeline_test.dart`; `flutter test --no-pub test/features/push/application/background_message_handler_test.dart`; `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -count=1 -run 'Reaction|Forbidden' ./...)` | Run the exact Swift resolver gate, Android background-crypto plugin/Kotlin gate, `./scripts/run_test_gates.sh 1to1`, then `feature-host-all` and `core-host-all`; use `run_1to1_reaction_notification_device.dart` only with explicit live targets and staging/provider manifests | Host/platform contracts cover typed ciphertext-only push, trusted local context, author eligibility, deterministic identity, atomic dedupe/tone, staging/replay, route, and message-only unread preservation. TC-00 and TC-07 artifacts pass; TC-07 also requires acknowledged synthetic cleanup plus exact candidate/local-APK restoration. TC-13/14/16 fail closed with exit 78 until bounded staging automation evidence is supplied; do not relabel them passed or N/A while their required targets are available. |
| Group/announcement reaction notifications (Plan 257) | `flutter test --no-pub test/integration/group_reaction_notification_device_criteria_test.dart`; the Plan-257 group payload/send/remove/roundtrip/notification/Orbit files registered in `GROUP_TESTS`; pinned Go/Kotlin/Swift commands from the plan | Run `./scripts/run_test_gates.sh groups`, justified feature/core host sweeps, then `run_group_reaction_notification_device.dart --scenario <id> --sender <explicit-id> --recipient <explicit-id> --artifact-dir <dir> --staging-manifest <json>` | Five rows are discovery-registered and fail closed. Android has real candidate build/install, identity/contact/group staging, UIAutomator shade/tap, relay/FCM, killed-process, SQLCipher, and exact stored-ADD redrive orchestration. Physical iOS has repo-owned identity/membership/target staging, E2E/normal candidate provenance, four XCUITest selectors, `idevicesyslog`, relay/APNs, card/tap, and local-state capture. Neither platform has an accepted live artifact: closure is configuration-blocked pending a valid redacted staging manifest and working relay/provider credentials, not blocked on a missing automation seam. |
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

The sims manifest may own a cleaned executable capability backed by one of
these files without making the entire historical pool part of every mode.
`sims major` selects mandatory critical capabilities; `sims full` selects the
cleaned registered reliability/device inventory, including typed blockers; the legacy `reliability-sim`
pool is not a substitute for either contract.

- `integration_test/smoke_test.dart`
- `integration_test/conversation_bridge_test.dart`
- `integration_test/wifi_transport_test.dart`
- `integration_test/voice_message_e2e_test.dart`
- `integration_test/one_to_one_reaction_notification_proof_test.dart` plus `integration_test/scripts/run_1to1_reaction_notification_device.dart` (Plan 256 TC-00/07/13/14/16; live closure scenarios require explicit staging/provider evidence)
- `integration_test/group_announcement_reaction_notification_proof_test.dart` plus `integration_test/scripts/run_group_reaction_notification_device.dart` (Plan 257 TC-13/14/15/16; five explicit config-gated rows, with live artifacts still open)
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
- When a critical capability, build profile, device criterion, dependency, or
  resource lock changes, update the repo sims manifest/contracts and keep the
  `major`, `full`, and `smoke` descriptions truthful. Never grant release green
  to a filtered or partial run.
- When a feature gets new direct coverage but no gate changes, update only the
  relevant row here.
- When a user-journey contract changes, update the relevant matrix or audit doc
  in addition to this runbook.
- Do not rewrite the whole `Test-Flight-Improv` archive just because one bug
  added one regression test.
