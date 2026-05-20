# INTEGRATE-ML-003 Worktree-To-Main Integration Contract

Status: accepted

## Row Contract

- Source row: `ML-003`
- Scenario: Add an offline member and prove replay delivery after first reconnect.
- Active mode: standard integration.
- This is import/reconcile/verify work only. It is not gap-closure mode and not a new implementation rollout.
- Reuse the original worktree implementation plan and closure evidence as historical source-of-truth; do not recreate, rewrite, or rerun that implementation plan.

## Historical Evidence To Reuse

- Source matrix row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Source row plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-003-plan.md`
- Source closure status: accepted.
- Source focused evidence:
  - `flutter test --plain-name "ML-003" test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart`
  - criteria/discovery tests
  - direct supporting group suites
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh completeness-check`
  - historical exact-relay iOS 26.2 four-device `private_offline_add` proof with run id `1778525877154`.

## Exact Worktree Changed-File Inventory

Meaningful ML-003 row-owned files from the historical plan and closure evidence:

- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `integration_test/group_multi_device_real_harness.dart`

Source matrix, source breakdown, source test-inventory edits, and source closure docs are historical evidence only and must not be copied as implementation output.

## Main Compatibility And Duplicate Check

- Main did not contain the ML-003 row selector, `private_offline_add` criteria requirement, or supported offline Dana invite/replay/live proof path before this integration pass.
- Existing COMPLETE_1 row `GM-003` provided nearby offline-add support but did not close ML-003 because it was not the row-owned private offline-add proof and did not preserve the source worktree ML-003 contract.
- Existing COMPLETE_1 rows `GK-024`, `GK-023`, and `GP-026` overlap replay membership windows, removed-window replay filtering, and live-plus-inbox dedupe. Their behavior was preserved while importing ML-003 replay entitlement checks.
- Existing COMPLETE_1 rows `GE-016` and `GM-029` overlap membership version and convergence semantics through `lastMembershipEventAt`, `configVersionOverride`, and `groupConfigStateHash`.
- Existing accepted worktree rows `ML-001` and `ML-002` were preserved; no duplicate `private_abc_create` or `private_online_add` proof was imported.

## Integration Actions Completed

1. Inspected the source row entry, historical plan, source closure evidence, exact changed-file inventory, and COMPLETE_1 overlaps before applying ML-003 changes.
2. Imported only the missing ML-003-owned replay entitlement, accepted-invite drain, offline Dana proof, criteria, harness, runner, and focused tests needed for the row.
3. Preserved already-present COMPLETE_1 and prior accepted worktree coverage instead of duplicating or relabeling it.
4. Added main-only compatibility fixes needed for the imported row to run against current main:
   - late Dana restores the exact preflight identity material in the live harness,
   - the live runner re-reads a verdict file if process exit races verdict observation,
   - Dana starts the pending invite listener before startup relay inbox drain can dispatch the invite,
   - accepted invite materialization preserves source config-version membership timestamps for replay lower-bound checks.
5. Stopped before accepting the row when live proof run `1778995893554` exposed a COMPLETE_1 compatibility conflict in the final criteria hash contract.
6. Resolved the conflict without relaxing hash policy:
   - `members_added` system payloads now use the authoritative Dana membership event timestamp instead of a fresh sender-local timestamp,
   - accepted pending invite materialization now preserves the invite config version as `lastMembershipEventAt`,
   - ML-003 criteria now rejects private offline-add hash divergence as non-converged config,
   - fixed-date replay smoke tests now pass an explicit retention clock so historical fixture timestamps do not expire under the production retention window.
7. Preserved the ML-003 late-add replay behavior and the COMPLETE_1 strict version/hash convergence contracts for `GE-016` and `GM-029`.

## Verification Evidence

- `dart format --set-exit-if-changed lib/features/groups/application/handle_incoming_group_invite_use_case.dart integration_test/group_multi_party_device_real_harness.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` PASS (`Formatted 5 files (0 changed)`).
- `dart analyze lib/features/groups/application/handle_incoming_group_invite_use_case.dart integration_test/group_multi_party_device_real_harness.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` PASS (`No issues found!`).
- `flutter test --no-pub --plain-name "ML-003" test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` PASS (`+7`).
- `flutter test --no-pub --plain-name "GM-003" test/features/groups/integration/group_messaging_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` PASS (`+7`).
- `flutter test --no-pub --plain-name "GK-023" test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` PASS (`+1`).
- `flutter test --no-pub --plain-name "GK-024" test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` PASS (`+1`).
- `flutter test --no-pub --plain-name "GP-026" test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart` PASS (`+2`).
- `flutter test --no-pub --plain-name "GE-016" test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart` PASS (`+3`).
- `flutter test --no-pub --plain-name "GM-029" test/features/groups/application/group_membership_config_version_producers_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart` PASS (`+6`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart` PASS (`+209`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+170`).
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios` lists `private_offline_add`.

## Superseded Blocking Live Proof

Latest live command:

```sh
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_offline_add -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C,CD5929A6-EA0A-421D-A6D3-55BD707E0F76
```

Result: blocked. Shared directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_add_qQCveI`; run id `1778995893554`.

Functional ML-003 proof succeeded inside the role verdicts:

- Dana accepted the supported pending invite and joined.
- Dana drained offline replay on first reconnect.
- Dana received `aliceAfterDanaOfflineAdd` and `bobAfterDanaOfflineAdd`.
- Dana did not persist the pre-add message.
- Dana received `aliceLiveAfterDanaDrain` without manual restart.
- Dana proof flags include `storedPendingInvite`, `acceptedPendingInvite`, `joinedViaGroupJoinWithConfig`, `drainedOfflineInbox`, `preAddMessageAbsent`, `receivedAlicePostAddReplay`, `receivedBobPostAddReplay`, `replayPersistedExactlyOnce`, and `liveAfterDrainWithoutRestart`.

The orchestrator still failed final criteria validation because the role verdicts disagreed on `groupConfigStateHash`:

- Alice: `7336709b939a95cc29fa34e56bb2f6290f964c7fa8db53d8b401dd977cfc1ee4`
- Bob and Charlie: `339cf310d6a788ab8d8307e97ef5bad6522e3376f6ca186139fc63aed6abb69a`
- Dana: `0a5d4783391668e584fdc047533e7b3b1306f10ab47213347d3a6d5d80c08c92`

This failure is superseded by fresh proof run `1779036469856` after the hash producer/timestamp reconciliation below.

## Conflict Mapping

Worktree ML-003 row contract:

- `private_offline_add` must prove offline Dana accepts/joins, drains A/B post-add replay, excludes pre-add replay, and then receives live delivery.
- The historical criteria accepted the row only when private role verdicts also passed the shared convergence checks, including matching `groupConfigStateHash`.

Main COMPLETE_1 row contracts affected:

- `GM-003`: offline add and catch-up behavior for Dana.
- `GK-024`: late-joining member must skip pre-join replay before decrypt/key repair.
- `GK-023`: removed-window replay filtering and membership-window replay behavior.
- `GP-026`: live-plus-inbox replay dedupe.
- `GE-016`: concurrent membership/version convergence, including deterministic role/version agreement in real proof.
- `GM-029`: config-version monotonicity through `lastMembershipEventAt`, `configVersionOverride`, and producer watermark/config-version consistency.

Policy decision:

- Strict `groupConfigStateHash` equality remains required for ML-003 because the hash represents the authoritative converged group config snapshot.
- The divergence in run `1778995893554` was not expected or harmless. It came from inconsistent membership event watermark inputs: the harness published a fresh `members_added` timestamp to recipients while Alice used Dana's authoritative `joinedAt`, and Dana's accepted invite materialization did not persist the invite config version as the local membership watermark.
- The fix aligns all roles on the same authoritative final config snapshot while preserving ML-003 replay lower-bound semantics. No scenario-specific hash relaxation was added.

Resolved proof:

- Fresh live run id: `1779036469856`.
- Shared directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_add_laVsyI`.
- Result: `private_offline_add proof passed: private_offline_add verdicts valid for alice, bob, charlie, dana`.
- Alice, Bob, Charlie, and Dana all reported `groupConfigStateHash` `73d22cbe801e2194daea80b0c56a9dfbe5763179d3aaad20077451882f3a482e`.
- Dana proof flags were all true for `storedPendingInvite`, `acceptedPendingInvite`, `joinedViaGroupJoinWithConfig`, `drainedOfflineInbox`, `preAddMessageAbsent`, `receivedAlicePostAddReplay`, `receivedBobPostAddReplay`, `replayPersistedExactlyOnce`, and `liveAfterDrainWithoutRestart`.

## Integration Result

Verdict: `accepted`

Accepted into main for ML-003:

- row-owned replay envelope recipient entitlement support,
- row-owned accept/drain self-recipient propagation,
- row-owned accepted-invite membership timestamp materialization,
- row-owned direct tests, fake-network smoke, criteria tests, runner support, and live harness support.
- compatibility fix preserving invite config version as the accepted-invite membership watermark,
- harness fix using the authoritative Dana `joinedAt` timestamp for `members_added` publication,
- criteria coverage proving private offline-add hash divergence remains a failure,
- fixed-date replay smoke fixture clock updates that preserve production retention behavior while keeping historical replay rows stable.

Skipped duplicate or out-of-row work:

- Source worktree matrix, source breakdown, source test-inventory edits, and source closure docs were not copied.
- COMPLETE_1 documentation was not modified.
- Existing GM-003, GK-024, GK-023, GP-026, GE-016, GM-029, ML-001, and ML-002 coverage was preserved rather than duplicated or relabeled.
- No ML-004+, removal/re-add, key-epoch, media, notification, security, observability, stress, or broader lifecycle work was imported.

## Resolution Applied

ML-003 is accepted with strict hash equality preserved. The accepted policy is option 1 from the original resolution contract: make all roles stamp and serialize the same authoritative membership config version in `private_offline_add` without weakening replay lower-bound filtering.

The row remains scoped to ML-003. Do not continue with `INTEGRATE-ML-004` in this resolving pass; the integration pipeline can resume from `INTEGRATE-ML-004` in a later pass.

## Final Status Rule

This session is exactly:

- `accepted` because row-owned ML-003 behavior is imported, strict `groupConfigStateHash` equality is preserved, affected COMPLETE_1 rows `GM-003`, `GK-024`, `GK-023`, `GP-026`, `GE-016`, and `GM-029` passed focused verification, the full criteria suite and groups gate passed, and fresh iOS 26.2 run `1779036469856` passed with matching role hashes and Dana's late-add replay proof intact.
