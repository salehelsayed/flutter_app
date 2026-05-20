# INTEGRATE-NW-005 Minimal Integration Contract

Status: accepted

Session id: `INTEGRATE-NW-005`

Source row: `NW-005 | Rendezvous rediscovery after membership change does not affect membership truth | P1 | Network, libp2p Topic Mesh, Relay, and Mobile Lifecycle`

Historical source of truth:

- Source matrix: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md`
- Historical accepted plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-005-plan.md`
- Source inventory evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`

Do not recreate or rerun the historical implementation plan. This contract governs only importing and verifying the already-accepted NW-005 row delta into the main checkout.

## Current-Main Classification

NW-005 was partially present in the dirty main integration checkout after current-row import work, but it was not ledger-closed. The exact row-owned test anchors are now present:

- `TestNW005RendezvousRediscoveryUsesCurrentMembershipOnly`
- `NW-005 rejoin publishes current membership as discovery authority after churn`
- `NW-005 stale and fresh rediscovery subscribers do not change membership truth`

Production code stayed untouched for this row. Current main already had broader rendezvous/member filtering behavior and COMPLETE_1 overlap around `GP-011`, `GP-012`, `GM-030`, `GP-008`, `GM-023`, and `GA-022`/`GA-023`/`GA-024`, but those overlaps did not close the exact NW-005 worktree row without the row-owned proof anchors and ledger evidence.

Therefore this row was not `skipped_already_present`. Only the missing meaningful NW-005 row-owned test and documentation delta was accepted.

## Import Scope

Allowed row-owned imports:

- NW-005 Go discovery membership filtering selector in `go-mknoon/node/pubsub_test.go`
- NW-005 Flutter rejoin current-membership authority selector in `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- NW-005 fake-network stale/outsider rediscovery membership-truth selector in `test/features/groups/integration/group_resume_recovery_test.dart`
- one concise `test-inventory.md` row

Not imported: NW-004 relay reconnect, NW-006 disconnect-not-removal semantics, NW-008 duplicate connection paths, NW-009 relay probe failures, runner or criteria scenarios, broader relay shared-state architecture, source docs, COMPLETE_1 docs, UI, notifications, media, Android, physical iOS, macOS app-peer proof, or unrelated worktree changes.

## Verification

Focused checks run:

```sh
(cd go-mknoon && go test ./node -run 'TestNW005' -count=1)
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name 'NW-005'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-005'
gofmt -l go-mknoon/node/pubsub_test.go
dart format --set-exit-if-changed test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
dart analyze test/features/groups/application/rejoin_group_topics_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Affected-row preservation checks run:

```sh
(cd go-mknoon && go test ./node -run 'TestGP011RendezvousDiscoveryFiltersNonMembers|TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember|TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate|TestFilterDiscoveredGroupMembers|TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback' -count=1)
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-003'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'NW-004'
```

Results:

- Go NW-005 selector: PASS (`ok github.com/mknoon/go-mknoon/node 0.589s`)
- NW-005 Flutter rejoin selector: PASS (`+1`)
- NW-005 fake-network selector: PASS (`+1`)
- Go preservation selector bundle: PASS (`ok github.com/mknoon/go-mknoon/node 0.710s`)
- NW-003 resume-recovery preservation selector: PASS (`+1`)
- NW-004 resume-recovery preservation selector: PASS (`+1`)
- `gofmt -l`: PASS with no changed-file output
- Dart format check: PASS (`Formatted 2 files (0 changed)`)
- scoped Dart analyzer: PASS (`No issues found!`)
- pre-ledger `git diff --check`: PASS

Required live proof: none.

The source row marks 3-Party E2E as `N/A`; no simulator, iOS, Android, physical-device, macOS, Chrome, relay app-peer, shared directory, or run-id proof is required or claimed for NW-005.

## Final Execution Verdict

Verdict: `accepted`

NW-005 is accepted in main. The row-owned proof establishes that rendezvous rediscovery affects connectivity only and does not add, remove, authorize, or deliver plaintext outside current group membership after membership churn.

Residual classifications from earlier integration rows are preserved unchanged: non-row `BB-007`, `BB-012`, accepted-row `IR-018` fixture aging, `GM-029`, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, sampled retained-history drain follow-up invariant, sampled `ML-008`, sampled COMPLETE_1 `GI-017`, sampled replay-window residuals `GM-033`/`GK-023`/`GI-019`, drain `GEK003` and `GE-018`, full-listener notification/self-peer-cache failures, strict-analyzer pre-existing infos/warnings, completeness classification failure, and `KE-007`/`KE-009` blocked-conflict records remain for future row-owned/follow-up work.
