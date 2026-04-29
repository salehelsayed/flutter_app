# Group Onboarding And Crypto Test Coverage Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- Supporting docs:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
  - `Network-Arch/Resilient-libp2p-TDD-Plan.md`
- Decomposition date:
  `2026-04-29`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must refresh against landed code before execution
  - this rollout is test-coverage closure work, but sessions may include narrow product/test-harness code changes when existing behavior cannot be asserted safely without them
  - do not count fixture skips, sender-only success, pending receiver evidence, or fake/passthrough crypto as closure for real-crypto, real-network, simulator, or ciphertext rows

## downstream execution path

- Sessions should run, in breakdown order, through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Run `GON-015` only after the runnable row-owned sessions before it are resolved or have a truthful persisted blocker.
- After `GON-015`, run the pipeline's final whole-program acceptance/closure pass and persist one final program verdict in this breakdown artifact.
- Allowed final program verdicts for this rollout are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`. A verdict is not trustworthy if any source TC remains silently unmapped.

## recommended plan count

- `15`
- The smallest safe split is:
  - `14` implementation or evidence sessions grouped by coherent test seam and direct regression family
  - `1` closure/gate session for TC-21, closure-reference updates, matrix truth, and final verdict preparation
- Source test case coverage:
  - TC-1 through TC-34 are all mapped exactly once as primary ownership
  - TC-10 is treated as mostly covered at the Go/node decrypt boundary, with only app-boundary supplementation if current repo evidence still needs it
  - TC-19 is mapped as a recovery-contract session because the source doc records fake-network evidence as partial and real bridge/GossipSub recovery as still open
- Session disposition counts:
  - `implementation-ready`: `14`
  - `closure-only`: `1`
  - `stale/already-covered`: `0`
  - `blocked_by_policy_decision`: `0` at decomposition time; plans may record a real blocker if TC-24, TC-31, TC-32, or TC-33 cannot derive the current product contract from code and existing docs

## overall closure bar

`Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md` stays `still_open` until all of the following are true at the same time:

- every source TC-1 through TC-34 is either implemented as automated proof or explicitly mapped to existing automated proof with file-level evidence
- new-member onboarding covers post-join media, reaction fan-out, quoted replies with missing pre-join parents, add/send race determinism, no-backfill preservation, and foreground-push media recovery
- TC-13 and TC-26 prove real ML-KEM/AES-256-GCM group onboarding with `GoBridgeClient` or equivalent live Go bridge evidence, without pre-saving or fixture-injecting Bob's accepted group key
- TC-9 through TC-11 are closed only by tests that observe real encrypted payloads, bridge crypto results, or existing Go/node decrypt-boundary evidence; fake-network plaintext listener tests remain supplemental
- simulator sufficiency is satisfied by receiver-visible evidence for TC-17, TC-20, TC-25, and TC-27 through TC-34; sender publish success, timeline length alone, rotation execution alone, or pending receiver results do not count
- at least one real-network group scenario is wired into a recurring nightly or pre-release gate and fails clearly when its required fixture is unavailable
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`, and this breakdown tell the same truthful story about covered, residual, and fixture-gated evidence

## source of truth

Primary governing docs:

- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`

Current repo facts that materially affected decomposition:

- The standard `groups` gate is host-side fake-network coverage: `group_messaging_smoke_test.dart`, `group_resume_recovery_test.dart`, `group_edge_cases_smoke_test.dart`, `invite_round_trip_test.dart`, `group_membership_smoke_test.dart`, and `group_startup_rejoin_smoke_test.dart`.
- `announcement_happy_path_test.dart` and `foreground_group_push_drain_test.dart` are currently optional/manual direct suites, not frozen named gate members.
- `integration_test/group_recovery_cli_e2e_test.dart`, `integration_test/group_recovery_e2e_test.dart`, and `integration_test/multi_relay_failover_test.dart` are nightly/release or fixture-gated evidence, not normal `groups` gate proof.
- Existing group application tests cover many direct seams, including send, listener, inbox drain, invites, member add/remove, key rotation, reactions, retry, and startup rejoin.
- Existing Go tests cover ML-KEM, group AES-GCM, group envelope/signature, node decrypt failure, key-rotation grace, relay, and multi-relay pieces, but the source doc requires integrated group-onboarding evidence for new-member key acceptance and decrypt.
- Existing paired simulator harnesses use filesystem signals and must be reused or extended for new simulator rows rather than replaced by a new orchestration framework.

## source test case inventory

| TC | Primary session | Source area | Disposition |
| --- | --- | --- | --- |
| `TC-1` | `GON-001` | New-member discussion text/no-backfill | preserve and consolidate existing coverage |
| `TC-2` | `GON-001` | New-member discussion image | covered fake-network/app-layer |
| `TC-3` | `GON-001` | New-member discussion video | covered fake-network/app-layer |
| `TC-4` | `GON-001` | New-member discussion voice | covered fake-network/app-layer |
| `TC-5` | `GON-002` | Announcement new-reader media/no-backfill | covered fake-network/app-layer; partial for simulator/real-network |
| `TC-6` | `GON-001` | History-backfill policy | covered but preserve in new suite |
| `TC-7` | `GON-004` | Multi-add same epoch | covered fake-network/app-layer |
| `TC-8` | `GON-004` | Fake-network rejoin epoch correctness | covered fake-network/passthrough |
| `TC-9` | `GON-006` | Retained old key cannot decrypt post-rotation ciphertext | covered at real-bridge app boundary |
| `TC-10` | `GON-006` | Wrong/corrupt ciphertext graceful failure | covered at Go/node boundary |
| `TC-11` | `GON-006` | Replay boundary for duplicate encrypted envelope/nonce | covered as app-layer `messageId` replay convergence |
| `TC-12` | `GON-006` | Membership-event signature verification | covered by Go envelope validation plus app authorization |
| `TC-13` | `GON-005` | Integrated real-crypto first-add onboarding | covered at real-bridge app boundary |
| `TC-14` | `GON-007` | Existing-member discussion image fan-out | covered fake-network/app-layer |
| `TC-15` | `GON-007` | Existing-member discussion video fan-out | covered fake-network/app-layer |
| `TC-16` | `GON-007` | Existing-member discussion voice fan-out | covered fake-network/app-layer |
| `TC-17` | `GON-010` | New member joins over real GossipSub | partial; strict paired-run criteria guard added |
| `TC-18` | `GON-010` | Three-party real fan-out with media | partial; strict paired-run criteria guard added |
| `TC-19` | `GON-014` | Partition/heal durable inbox recovery | covered fake-network; partial for real-network simulator |
| `TC-20` | `GON-010` | Group plus Announcement real-network recovery matrix | partial; strict G-row criteria guard added |
| `TC-21` | `GON-015` | Recurring gate sufficiency | covered gate wiring; configured fixture execution required for pass |
| `TC-22` | `GON-003` | Reaction fan-out to newly-added member | covered fake-network/app-layer |
| `TC-23` | `GON-003` | Quoted reply to pre-join parent | covered fake-network/widget |
| `TC-24` | `GON-004` | Add/send epoch race deterministic contract | covered fake-network/app-layer |
| `TC-25` | `GON-008` | Foreground push drains new-member media | covered foreground-drain direct integration |
| `TC-26` | `GON-005` | Real-crypto re-add after rotation | covered at real-bridge app boundary |
| `TC-27` | `GON-011` | True two-simulator Discussion journey | partial |
| `TC-28` | `GON-011` | True two-simulator Announcement permissions/media journey | partial |
| `TC-29` | `GON-009` | Admin add/remove with stale notification denial | covered host-side; partial for paired simulator UI |
| `TC-30` | `GON-012` | Full group media matrix on simulator | partial; host retry/media recovery revalidated |
| `TC-31` | `GON-009` | OS-level group notification/deep-link journey | partial with host-side route denial and background/terminated route sequencing |
| `TC-32` | `GON-013` | Relay/libp2p failover and replay ordering | partial; strict relay fixture guard plus local relay/recovery proofs |
| `TC-33` | `GON-013` | Same-account multi-device simulator consistency | partial; host same-account oracle revalidated |
| `TC-34` | `GON-012` | Failure/recovery UI flows on simulator | partial; host retry/media failure UI revalidated |

## session ledger

| Session ID | Source TCs | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- |
| `GON-001` | `TC-1`, `TC-2`, `TC-3`, `TC-4`, `TC-6` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-001-plan.md` | none | `accepted` |
| `GON-002` | `TC-5` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-002-plan.md` | none | `accepted` |
| `GON-003` | `TC-22`, `TC-23` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-003-plan.md` | `GON-001` if it creates shared onboarding helpers | `accepted` |
| `GON-004` | `TC-7`, `TC-8`, `TC-24` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-004-plan.md` | `GON-001` if it creates shared onboarding helpers | `accepted` |
| `GON-005` | `TC-13`, `TC-26` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-005-plan.md` | none | `accepted` |
| `GON-006` | `TC-9`, `TC-10`, `TC-11`, `TC-12` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-006-plan.md` | none | `accepted` |
| `GON-007` | `TC-14`, `TC-15`, `TC-16` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-007-plan.md` | none | `accepted` |
| `GON-008` | `TC-25` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-008-plan.md` | `GON-001` if it creates shared media assertions | `accepted` |
| `GON-009` | `TC-29`, `TC-31` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-009-plan.md` | none | `accepted` |
| `GON-010` | `TC-17`, `TC-18`, `TC-20` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-010-plan.md` | none | `accepted_with_device_lab_residual` |
| `GON-011` | `TC-27`, `TC-28` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-011-plan.md` | `GON-010` if it tightens shared paired-harness pass criteria | `accepted_with_simulator_residual` |
| `GON-012` | `TC-30`, `TC-34` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-012-plan.md` | none | `accepted_with_simulator_residual` |
| `GON-013` | `TC-32`, `TC-33` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-013-plan.md` | none | `accepted_with_device_lab_residual` |
| `GON-014` | `TC-19` | `implementation-ready` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-014-plan.md` | none | `accepted_with_real_network_residual` |
| `GON-015` | `TC-21`, final closure | `closure-only` | `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-015-plan.md` | all prior runnable sessions | `accepted_with_explicit_follow_up` |

## ordered session breakdown

### Session GON-001

- Title:
  `Discussion new-member media onboarding and no-backfill proof`
- Session id:
  `GON-001`
- Source TCs:
  `TC-1`, `TC-2`, `TC-3`, `TC-4`, `TC-6`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-001-plan.md`
- Exact scope:
  - add or consolidate a deterministic discussion-group onboarding suite proving a newly-added Bob receives only post-join text/image/video/voice and never pre-join history
  - preserve the existing future-only no-backfill policy while extending it to the new media boundary
  - assert media descriptors, download trigger behavior, and FLOW evidence where the product already emits it
- Ownership:
  - tests, narrow helper extraction if needed
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/domain/models/group_message_payload.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_messaging_smoke_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md` if a new direct suite needs classification
- Closure result:
  - accepted on `2026-04-29`
  - landed `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - broader gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - metadata check run: `./scripts/run_test_gates.sh completeness-check` still reports unrelated pre-existing unmatched `integration_test/settings_background_choice_smoke_test.dart`; the new onboarding suite is classified
  - gate classification updated in `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` as an optional/manual direct suite, without widening the frozen `groups` gate
  - source doc and `20-group-discussion-reliability-closure-reference.md` now record TC-1, TC-2, TC-3, TC-4, and TC-6 fake-network/app-layer evidence

### Session GON-002

- Title:
  `Announcement new-reader media onboarding`
- Session id:
  `GON-002`
- Source TCs:
  `TC-5`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-002-plan.md`
- Exact scope:
  - prove an announcement reader added after an initial admin post receives post-join admin media and does not receive the pre-join post
  - cover the supported announcement media set without overclaiming unsupported video or voice behavior
  - keep reader compose blocked and existing announcement reaction evidence intact
- Ownership:
  - tests, narrow helper extraction if needed
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/models/group_model.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - direct suite plus `./scripts/run_test_gates.sh groups` when shared group behavior changes
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`, `Test-Flight-Improv/test-gate-definitions.md`
- Closure result:
  - accepted on `2026-04-29`
  - landed `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - gate classification updated in `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` as an optional/manual direct suite, without widening the frozen `groups` gate
  - source doc and `21-announcement-reliability-closure-reference.md` now record TC-5 fake-network/app-layer evidence while preserving the real-network/real-crypto residuals

### Session GON-003

- Title:
  `New-member reactions and quoted missing-parent context`
- Session id:
  `GON-003`
- Source TCs:
  `TC-22`, `TC-23`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-003-plan.md`
- Exact scope:
  - prove a newly-added member receives another member's post-join reaction exactly once
  - prove a post-join quoted reply that references a pre-join parent preserves `quotedMessageId`, does not backfill the parent, and renders the established missing-parent fallback
- Ownership:
  - tests and narrow UI/assertion glue if existing fallback is not directly asserted for group quotes
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_reaction_roundtrip_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- Closure result:
  - accepted on `2026-04-29`
  - extended `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - TC-22 evidence: Bob, added after a pre-join message, receives Charlie's post-join reaction through the listener/reaction repository path and has no reaction state for the pre-join message
  - TC-23 evidence: Bob receives the post-join quoted reply with `quotedMessageId` preserved, does not receive the pre-join parent, and the group conversation UI renders `Message unavailable`
  - source doc and `20-group-discussion-reliability-closure-reference.md` now record the fake-network/app-layer and widget evidence

### Session GON-004

- Title:
  `New-member epoch convergence, rejoin, and add-send race contract`
- Session id:
  `GON-004`
- Source TCs:
  `TC-7`, `TC-8`, `TC-24`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-004-plan.md`
- Exact scope:
  - prove multi-recipient create/add convergence for Bob and Charlie on the observable current epoch
  - preserve fake-network rejoin-after-leave current-epoch behavior and absence-window no-backfill
  - derive and pin the current product contract for admin-add/member-send overlap; if repo behavior is genuinely nondeterministic, record a blocker instead of accepting a flaky test
- Ownership:
  - tests, narrow deterministic sequencing guard if existing behavior already implies one contract
- Likely code-entry files:
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/invite_round_trip_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Docs to update when done:
  - source doc open-question resolution, this breakdown ledger, discussion closure reference
- Closure result:
  - accepted on `2026-04-29`
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-004-plan.md`
  - extended `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - focused rejoin verification passed: `flutter test test/features/groups/integration/group_membership_smoke_test.dart --name "removed member can be re-added with current state and resumes send/receive"`
  - TC-7 evidence: Bob and Charlie share the same latest fake-network epoch and receive the same post-add message with that `keyGeneration`
  - TC-8 evidence: existing re-add test proves epoch 2 current-state rejoin and no removed-period backfill in the fake-network/passthrough layer
  - TC-24 evidence: staged-but-unsubscribed Bob does not receive the racing message, then receives the first post-subscription message exactly once while member lists converge
  - source doc open question for same-epoch add/send behavior now records the fake-network subscribe-effective contract while leaving real-network divergence to later simulator sessions

### Session GON-005

- Title:
  `Real-crypto first-add and re-add onboarding decrypt proof`
- Session id:
  `GON-005`
- Source TCs:
  `TC-13`, `TC-26`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-005-plan.md`
- Exact scope:
  - add fixture-backed real Go bridge evidence that Bob receives a group key through the group invite/key-acceptance path and decrypts a subsequent group message
  - add the re-add-after-rotation proof: Bob decrypts the current epoch after re-add, receives no absence-window messages, and stale retained epoch material cannot decrypt current ciphertext
  - ensure fixture absence does not count as closure for the audit or recurring gate
- Ownership:
  - integration tests, harness wiring, minimal bridge/test helper changes
- Likely code-entry files:
  - `lib/core/bridge/go_bridge_client.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `lib/features/groups/application/group_invite_listener.dart`
  - `lib/features/groups/application/group_key_update_listener.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `integration_test/group_real_crypto_onboarding_test.dart`
  - `integration_test/group_recovery_cli_e2e_test.dart`
  - `integration_test/scripts/run_group_recovery_e2e.dart`
  - `integration_test/benchmark_encryption_harness.dart` for lower-level reference only
- Likely named gates:
  - nightly/release pool or new pre-release fixture-backed group crypto gate
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, discussion closure reference
- Closure result:
  - accepted on `2026-04-29`
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-008-plan.md`
  - extended `integration_test/foreground_group_push_drain_test.dart`
  - direct verification passed: `flutter test integration_test/foreground_group_push_drain_test.dart -d macos`
  - evidence: foreground group push drains a targeted image media inbox item into the group timeline exactly once across repeated pushes, preserves the descriptor, triggers one `media:download`, and emits notification text `Alice: Photo`
  - residual: direct foreground-router/inbox integration only; OS background/terminated push and paired-simulator media delivery remain outside this session
- Closure result:
  - accepted on `2026-04-29`
  - landed `integration_test/group_real_crypto_onboarding_test.dart`
  - direct verification passed: `flutter test integration_test/group_real_crypto_onboarding_test.dart -d macos`
  - gate classification updated in `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` as Nightly / Release Pool evidence, without widening the frozen host-side `groups` gate
  - TC-13 evidence: Alice/Bob identities and ML-KEM keys are generated through `GoBridgeClient`; Bob receives a production encrypted group invite, accepts it through `handleIncomingGroupInvite`, and decrypts a subsequent real bridge `group.encrypt` ciphertext with Bob's accepted group key
  - TC-26 evidence: after Bob removal and local key/group cleanup, the test generates a real next group key with `group.keygen`, advances the bridge state with `group:updateKey`, re-sends the production encrypted invite, verifies Bob decrypts the re-add ciphertext with the accepted current key, and verifies retained old key material cannot decrypt that ciphertext
  - residual: this is fixture-light real-bridge crypto/app invite acceptance evidence, not full two-node live GossipSub or simulator delivery proof

### Session GON-006

- Title:
  `Ciphertext security, replay boundary, and membership-event signature evidence`
- Session id:
  `GON-006`
- Source TCs:
  `TC-9`, `TC-10`, `TC-11`, `TC-12`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-006-plan.md`
- Exact scope:
  - prove removed Bob's retained old epoch key cannot decrypt post-rotation ciphertext
  - truthfully map existing wrong/corrupt ciphertext evidence and add app-boundary supplementation only if still missing
  - pin the replay boundary as nonce rejection or messageId/content dedupe, matching current product behavior
  - add a membership-system-event signed-envelope assertion or truthfully map existing Go envelope plus app admin-authorization evidence
- Ownership:
  - Go/node tests, Flutter app-boundary tests where appropriate, docs truth alignment
- Likely code-entry files:
  - `go-mknoon/crypto/group.go`
  - `go-mknoon/internal/group_envelope.go`
  - `go-mknoon/node/group.go`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/group_membership_event_watermark.dart`
- Likely direct tests/regressions:
  - `go-mknoon/crypto/group_test.go`
  - `go-mknoon/internal/group_envelope_test.go`
  - `go-mknoon/node/pubsub_decryption_failure_test.go`
  - `go-mknoon/node/pubsub_key_rotation_grace_test.go`
  - `test/features/groups/application/group_message_listener_signature_test.dart`
- Likely named gates:
  - relevant `go test` package commands plus `./scripts/run_test_gates.sh groups` if Flutter listener behavior changes
- Docs to update when done:
  - source doc, this breakdown ledger, discussion closure reference, matrix docs if replay/signature rows are referenced
- Closure result:
  - accepted on `2026-04-29`
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-006-plan.md`
  - added `TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature` in `go-mknoon/node/pubsub_test.go`
  - direct verification passed: `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey')`
  - corrupt-ciphertext verification passed: `(cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_EmitsDecryptionFailedEvent')`
  - replay-boundary verification passed: `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - TC-9 evidence: `integration_test/group_real_crypto_onboarding_test.dart` retains Bob's old key and verifies it cannot decrypt the new re-add/current-epoch ciphertext
  - TC-10 evidence: Go node tests emit `group:decryption_failed` for wrong local key, tampered nonce, and tampered ciphertext without emitting `group_message:received`
  - TC-11 evidence: current replay boundary is Flutter app-layer `messageId`/content dedupe, not nonce-cache rejection; pubsub+inbox duplicate and tampered-timestamp replay tests preserve one message row
  - TC-12 evidence: Go rejects forged signed `members_added` envelopes at the topic validator boundary, while app-layer listener tests reject unauthorized decoded membership events

### Session GON-007

- Title:
  `Existing-member discussion media fan-out`
- Session id:
  `GON-007`
- Source TCs:
  `TC-14`, `TC-15`, `TC-16`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-007-plan.md`
- Exact scope:
  - prove existing discussion members receive image, video, and voice fan-out through the live group path with intact descriptors
  - avoid duplicating new-member onboarding assertions from `GON-001`
- Ownership:
  - tests, narrow helper extraction if media builders are duplicated
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/models/group_message_payload.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_media_fanout_test.dart`
  - `integration_test/media_message_journey_e2e_test.dart` for existing simulator image reference
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Docs to update when done:
  - source doc, this breakdown ledger, discussion closure reference
- Closure result:
  - accepted locally on `2026-04-29` with real-network simulator residuals
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-014-plan.md`
  - tightened `test/features/groups/integration/group_resume_recovery_test.dart` from two missed split-window messages to three, matching TC-19
  - direct verification passed: `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"`
  - residual: real bridge/GossipSub simulator partition-heal recovery remains owned by the simulator/relay rows
- Closure result:
  - accepted on `2026-04-29`
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-007-plan.md`
  - added `test/features/groups/integration/group_media_fanout_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_media_fanout_test.dart`
  - gate classification updated in `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` as an optional/manual direct suite, without widening the frozen `groups` gate
  - TC-14/TC-15/TC-16 evidence: existing Bob and Charlie receive Alice's bridge-backed image, video, and voice/audio messages with sender message ids and persisted descriptors intact
  - residual: this is fake-network/app-layer evidence; live Go GossipSub and simulator media delivery remain later-session work

### Session GON-008

- Title:
  `Foreground push drains new-member media`
- Session id:
  `GON-008`
- Source TCs:
  `TC-25`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-008-plan.md`
- Exact scope:
  - extend foreground group push drain coverage from text to at least one representative post-join media item for a newly-added member
  - prove exactly-once insertion, media descriptor preservation, in-app notification behavior, and media-download trigger parity with live delivery
- Ownership:
  - integration test and narrow push-drain helper changes
- Likely code-entry files:
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
- Likely direct tests/regressions:
  - `integration_test/foreground_group_push_drain_test.dart`
  - `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
  - `integration_test/foreground_group_push_simulator_alice_harness.dart`
  - `integration_test/foreground_group_push_simulator_bob_harness.dart`
- Likely named gates:
  - optional/manual direct suite today; nightly/pre-release fixture-backed gate if promoted
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, discussion closure reference

### Session GON-009

- Title:
  `Group notification, deep-link, stale access, and admin removal simulator boundaries`
- Session id:
  `GON-009`
- Source TCs:
  `TC-29`, `TC-31`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-009-plan.md`
- Exact scope:
  - prove admin add/remove simulator behavior including membership propagation, route exit/access denial, blocked sends, no post-removal notifications, and stale notification/deep-link denial
  - extend group invite and group-message notification-open coverage across the required foreground/background/terminated states where the existing harness can support them
  - keep mute, active-conversation suppression, removed group, and dissolved group cases truthful if they need separate fixture support
- Ownership:
  - simulator/integration tests, route-target tests, narrow notification routing changes if missing behavior is exposed
- Likely code-entry files:
  - `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/core/notifications/notification_route_dispatch.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- Likely direct tests/regressions:
  - `integration_test/notification_open_ui_smoke_test.dart`
  - `integration_test/scripts/run_notification_open_ui_smoke.dart`
  - `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - paired group simulator harness extensions
- Likely named gates:
  - optional/manual direct suites today; simulator matrix or nightly/pre-release for full OS-state proof
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, discussion and announcement closure references
- Closure result:
  - accepted on `2026-04-29`
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-009-plan.md`
  - extended `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
  - strengthened `test/features/groups/application/group_message_listener_test.dart`
  - direct verification passed: `flutter test test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
  - direct verification passed: `flutter test test/features/groups/application/group_message_listener_test.dart`
  - evidence: stale removed-group notification route resolves `missing` after local cleanup; self-removal emits `groupRemovedStream`, leaves the group once, deletes local group access, and later group traffic creates neither a message row nor a local notification
  - residual: paired-simulator route exit, blocked-send UI, no-removed-user push at the OS layer, and background/terminated stale-tap UI denial remain outside this host-side session

### Session GON-010

- Title:
  `Real-network group onboarding, three-party fan-out, recovery matrix, and harness pass criteria`
- Session id:
  `GON-010`
- Source TCs:
  `TC-17`, `TC-18`, `TC-20`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-010-plan.md`
- Exact scope:
  - add a real GossipSub new-member-joins row to the paired simulator harnesses with text, image, and voice post-join delivery plus pre-join exclusion
  - add or map a three-party real-network fan-out row with receiver-visible delivery for both Bob and Charlie
  - add the Group plus Announcement real-network recovery matrix: group catch-up, announcement catch-up, and exactly-once live+inbox overlap
  - tighten existing G2/G4/G5/G7/G8 pass criteria so pending or missing receiver evidence cannot pass
- Ownership:
  - simulator harnesses and orchestrator scripts; narrow application fixes only if receiver-visible assertions expose a real bug
- Likely code-entry files:
  - `integration_test/group_smoke_alice_harness.dart`
  - `integration_test/group_smoke_bob_harness.dart`
  - `integration_test/scripts/run_routing_smoke_e2e.dart`
  - `integration_test/group_recovery_e2e_test.dart`
  - `integration_test/scripts/run_group_recovery_e2e.dart`
- Likely direct tests/regressions:
  - paired simulator smoke scripts with explicit devices
  - `integration_test/group_recovery_cli_e2e_test.dart`
  - `integration_test/group_recovery_e2e_test.dart`
- Likely named gates:
  - nightly/release pool or new pre-release simulator matrix
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, discussion and announcement closure references
- Closure result:
  - accepted locally on `2026-04-29` with device-lab residuals
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-010-plan.md`
  - added `integration_test/scripts/routing_smoke_group_criteria.dart`
  - added `test/integration/routing_smoke_group_criteria_test.dart`
  - tightened `integration_test/scripts/run_routing_smoke_e2e.dart`
  - direct verification passed: `flutter test test/integration/routing_smoke_group_criteria_test.dart`
  - static verification passed with infos only: `dart analyze integration_test/scripts/run_routing_smoke_e2e.dart integration_test/scripts/routing_smoke_group_criteria.dart`
  - evidence: G2 now requires 5/5 Bob receipts; G4 requires recovered Bob `e2eMs`; G5 rejects pending or missing receiver timeline entries; G7 requires Bob pre/post-rotation receipts; G8 requires Bob receipt in addition to Alice publish success
  - residual: TC-17 real GossipSub mid-conversation new-member join, TC-18 three-party real media fan-out, and the full TC-20 Group + Announcement real-network recovery matrix still require explicit paired/three-device simulator execution

### Session GON-011

- Title:
  `True two-simulator Discussion and Announcement UI journeys`
- Session id:
  `GON-011`
- Source TCs:
  `TC-27`, `TC-28`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-011-plan.md`
- Exact scope:
  - prove a full two-simulator Discussion journey with invite/accept, bidirectional text, group list visibility, unread/read transitions, restart, and catch-up
  - prove a full two-simulator Announcement journey with admin text/media/voice where supported, reader receive/react, blocked reader compose, and no stranded optimistic reader bubble
- Ownership:
  - simulator harnesses and focused UI assertions
- Likely code-entry files:
  - `integration_test/group_smoke_alice_harness.dart`
  - `integration_test/group_smoke_bob_harness.dart`
  - `integration_test/scripts/run_routing_smoke_e2e.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_list_wired.dart`
- Likely direct tests/regressions:
  - paired group simulator harness rows
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`
- Likely named gates:
  - nightly/release pool or simulator matrix
- Docs to update when done:
  - source doc, this breakdown ledger, discussion and announcement closure references
- Closure result:
  - accepted locally on `2026-04-29` with simulator journey residuals
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-011-plan.md`
  - widened Alice-side waits for `bob_identity.json` in `integration_test/routing_smoke_alice_harness.dart`
  - widened the matching group Alice wait in `integration_test/group_smoke_alice_harness.dart`
  - attempted paired run: `dart run integration_test/scripts/run_routing_smoke_e2e.dart -d 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`
  - attempted run result: failed before scenario execution because Alice timed out waiting for `bob_identity.json` while Bob was still building/starting; the timeout fix was applied after observing this failure
  - static verification passed with infos only: `dart analyze integration_test/routing_smoke_alice_harness.dart integration_test/group_smoke_alice_harness.dart`
  - residual: TC-27 full Discussion UI journey and TC-28 Announcement permissions/media journey still require a completed paired simulator run with receiver-visible assertions

### Session GON-012

- Title:
  `Simulator group media matrix and failure/recovery UI states`
- Session id:
  `GON-012`
- Source TCs:
  `TC-30`, `TC-34`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-012-plan.md`
- Exact scope:
  - prove supported group Discussion and Announcement media types on simulator, including stable descriptors, downloads/renders, retry recovery, and post-restart visibility
  - prove simulator-visible publish failure, inbox-store failure, zero-peer sends, upload failure, rapid pause/resume, and restart-with-pending group send/media states settle truthfully
- Ownership:
  - simulator tests, fake failure injection hooks, narrow UI state fixes if exposed
- Likely code-entry files:
  - `integration_test/media_message_journey_e2e_test.dart`
  - `integration_test/media_stable_id_smoke_test.dart`
  - `integration_test/scripts/run_media_message_journey_e2e.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  - `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- Likely direct tests/regressions:
  - simulator media journey scripts
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `test/features/groups/application/recover_stuck_sending_group_messages_use_case_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - direct suites plus nightly/release simulator matrix for device-context rows
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, closure references
- Closure result:
  - accepted locally on `2026-04-29` with simulator media-matrix residuals
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-012-plan.md`
  - no production behavior changes were required; this session reclassified and revalidated existing host-side recovery coverage
  - direct verification passed: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - direct verification passed: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - direct verification passed: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
  - residual: TC-30 and TC-34 still require fixture-backed simulator coverage for the full media matrix and visible recovery journeys

### Session GON-013

- Title:
  `Relay/libp2p failover, replay ordering, and same-account multi-device simulator consistency`
- Session id:
  `GON-013`
- Source TCs:
  `TC-32`, `TC-33`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-013-plan.md`
- Exact scope:
  - prove direct-to-relay fallback, relay down, multi-relay failover, partition heal, duplicate live+inbox delivery, and out-of-order durable replay with receiver-visible assertions
  - prove same-account multi-device convergence for sent history and membership while preserving declared device-local unread, mute, and notification behavior
  - fixture absence must fail clearly for closure runs rather than silently passing as coverage
- Ownership:
  - fixture-backed simulator/integration tests and harness scripts
- Likely code-entry files:
  - `integration_test/multi_relay_failover_test.dart`
  - `integration_test/group_multi_device_real_harness.dart`
  - `integration_test/scripts/run_group_multi_device_real.dart`
  - `go-mknoon/node/relay_selector.go`
  - `go-mknoon/node/group_inbox.go`
- Likely direct tests/regressions:
  - `integration_test/multi_relay_failover_test.dart`
  - `integration_test/group_multi_device_real_harness.dart`
  - `go test ./go-mknoon/node/...`
  - `go test ./go-mknoon/integration/...`
- Likely named gates:
  - nightly/release pool, relay fixture matrix
- Docs to update when done:
  - source doc, this breakdown ledger, `Test-Flight-Improv/test-gate-definitions.md`, discussion closure reference, network plan docs if touched
- Closure result:
  - accepted locally on `2026-04-29` with relay/same-account simulator residuals
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-013-plan.md`
  - added `MKNOON_REQUIRE_MULTI_RELAY=true` strict fixture mode to `integration_test/multi_relay_failover_test.dart`
  - classified `test/features/groups/integration/group_multi_device_convergence_test.dart` as an optional direct suite and documented `run_group_multi_device_real.dart` as Nightly / Release Pool orchestration evidence
  - direct verification passed from `go-mknoon`: `go test ./node -run 'Test.*Relay|Test.*Inbox|Test.*Rendezvous|Test.*MediaUpload|Test.*ProfileDownload'`
  - direct verification passed: `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "temporary partition replays missed backlog in cursor order and resumes live delivery after heal"`
  - direct verification passed: `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "same message is not duplicated if both pubsub and group inbox deliver it"`
  - direct verification passed: `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart`
  - expected missing-fixture verification failed with the intended message after pinning a device: `flutter test integration_test/multi_relay_failover_test.dart --dart-define=MKNOON_REQUIRE_MULTI_RELAY=true -d macos`
  - residual: full live relay outage/failover replay and same-account two-device simulator execution require configured device-lab fixtures

### Session GON-014

- Title:
  `Partition-heal durable group inbox recovery contract`
- Session id:
  `GON-014`
- Source TCs:
  `TC-19`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-014-plan.md`
- Exact scope:
  - add or tighten a focused partition/heal test proving dropped live group delivery later recovers through durable inbox drain and resumed live delivery arrives exactly once
  - keep the fake-network hook proof separate from any real-network simulator proof owned by `GON-010`/`GON-013`
  - if current fake-network coverage already fully satisfies TC-19's file-level request, update the source doc and ledger with exact evidence instead of adding duplicate tests
- Ownership:
  - fake-network integration tests and direct inbox/listener tests
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/shared/fakes/fake_group_pubsub_network.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_partition_heal_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`
- Docs to update when done:
  - source doc, this breakdown ledger, discussion closure reference

### Session GON-015

- Title:
  `Recurring gate sufficiency and final closure reconciliation`
- Session id:
  `GON-015`
- Source TCs:
  `TC-21`, final closure
- Session classification:
  `closure-only`
- Intended plan file:
  `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-015-plan.md`
- Exact scope:
  - wire at least one real-network group scenario into a recurring nightly or pre-release gate, or update the existing nightly/release classification so the fixture-backed command fails clearly when unavailable
  - update `test-gate-definitions.md` and `scripts/run_test_gates.sh` only when the implementation evidence requires gate/script changes
  - reconcile source doc TC statuses, discussion closure reference, announcement closure reference, this breakdown ledger, and final program verdict
- Ownership:
  - gate docs/scripts and closure documentation; no product behavior work unless needed for gate correctness
- Likely code-entry files:
  - `scripts/run_test_gates.sh`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- Likely direct tests/regressions:
  - `./scripts/run_test_gates.sh completeness-check`
  - affected named gate commands
  - fixture-backed nightly/pre-release command documented by the accepted sessions
- Likely named gates:
  - completeness-check plus the new or updated recurring group real-network gate
- Docs to update when done:
  - source doc, this breakdown ledger, gate definitions, discussion closure reference, announcement closure reference
- Closure result:
  - accepted locally on `2026-04-29` with explicit device-lab follow-up
  - landed `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-GON-015-plan.md`
  - added `./scripts/run_test_gates.sh group-real-network-nightly`, requiring `FLUTTER_DEVICE_ID` and strict `MKNOON_REQUIRE_MULTI_RELAY=true`
  - classified previously unmatched `integration_test/settings_background_choice_smoke_test.dart` as optional/manual so test inventory completeness is green
  - verification passed: `bash -n scripts/run_test_gates.sh`
  - verification passed: `./scripts/run_test_gates.sh completeness-check`
  - expected missing-fixture verification failed with the intended message: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh group-real-network-nightly`
  - residual: configured relay addresses and paired/multi-device simulator fixtures are still required for passing device-lab closure of the remaining simulator rows

## final program verdict

- Verdict: `accepted_with_explicit_follow_up`
- Date: `2026-04-29`
- Source doc: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- Basis:
  - every source TC-1 through TC-34 is mapped to a session and classified truthfully
  - all local sessions GON-001 through GON-015 have accepted ledger states
  - host/fake-network/app-boundary/Go-node coverage was added or revalidated where local execution can prove the contract
  - recurring gate wiring now exists for one strict real-network group scenario
  - `./scripts/run_test_gates.sh completeness-check` reports `683/683` classified files
- Explicit follow-up:
  - run configured paired-simulator and relay/device-lab commands for TC-17, TC-18, TC-20, TC-27, TC-28, TC-30, TC-31, TC-32, TC-33, and TC-34 before claiming full simulator closure
  - run `FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relay1,relay2,...> ./scripts/run_test_gates.sh group-real-network-nightly` in the recurring release/nightly environment

## decomposition review

- Evidence collector:
  - The source doc is a coverage audit, not a product feature spec. Most sessions should add or classify tests, but simulator/security sessions may expose narrow code or harness defects that must be fixed before the tests can be trustworthy.
  - The current `groups` gate is fake-network host-side coverage; real-network, real-crypto, relay, multi-device, and simulator claims must stay distinct.
  - Existing lower-level crypto and node tests are real evidence for primitives and some decrypt failures, but they do not close integrated onboarding decrypt flows.
- Closure mapper:
  - The closure target is not "all tests exist somewhere"; it is TC-by-TC truthful evidence with no overclaiming from skips, fake crypto, sender-only publish success, or permissive harness pass criteria.
  - Final closure must update both group and announcement closure references because the source spans Discussion and Announcement.
- Session splitter:
  - Sessions are grouped by coherent test seam and gate family rather than one plan per TC, because the source TCs share helpers and recurring gates.
  - Simulator rows are split into real-network onboarding/recovery, UI journeys, media/failure UI, relay/multi-device, and fake partition-heal to avoid one unreviewable simulator megasession.
- Reviewer:
  - The largest risk is that sessions `GON-010` through `GON-013` could grow too broad during implementation. Their plans must narrow each accepted pass to receiver-visible assertions and may persist explicit residual follow-ups for device-lab breadth that cannot run locally.
  - The second risk is falsely closing security rows through fake-network Dart listener tests; `GON-006` must keep ciphertext visibility as the acceptance boundary.
- Arbiter:
  - No structural blocker exists at decomposition time.
  - Accepted differences: TC-10 may close mostly by existing Go/node evidence; TC-19 may close as fake-network recovery evidence only if the source doc is updated truthfully to leave real-network recovery under `GON-010`/`GON-013`.
  - Required splits are already reflected in separate sessions for new-member media, announcement media, real crypto, security boundaries, push/notifications, simulator journeys, relay/multi-device, and final gate closure.
