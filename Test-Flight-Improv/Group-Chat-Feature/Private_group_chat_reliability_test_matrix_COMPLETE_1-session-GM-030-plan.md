# GM-030 Implementation Plan

Status: accepted

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-11 18:23:46 CEST | Planner completed | This GM-030 plan draft | Draft verdict: GM-030 is tests-only unless the exact row-owned Go discovery regression fails. It is not evidence-only because no exact GM-030 proof exists. | Run Reviewer on scope, proof sufficiency, gates, and stop rules. |
| 2026-05-11 18:24:45 CEST | Reviewer started | This GM-030 plan draft; mandatory section checklist; Go discovery test seams | Reviewer checking whether the plan is sufficient as-is or needs adjustment for proof strength, selector coverage, formatting, and stop rules. | Patch any structural or material gaps, then record reviewer verdict. |
| 2026-05-11 18:25:13 CEST | Reviewer completed | This GM-030 reviewer-adjusted plan | Sufficient with adjustments already applied: stricter B/D connectedness proof, event-total helper allowance, `gofmt`, and direct discovery-address selector coverage. No structural blocker remains. | Run Arbiter; classify adjustments and finalize execution-ready status if no structural blocker remains. |
| 2026-05-11 18:25:29 CEST | Arbiter started | Reviewer findings; this GM-030 reviewer-adjusted plan | Reviewer adjustments are incremental details, not structural blockers. | Finalize arbiter classification and execution-ready plan if no new blocker appears. |
| 2026-05-11 18:25:48 CEST | Arbiter completed | Final GM-030 plan; reviewer findings; mandatory output checklist | No structural blockers remain. GM-030 is execution-ready as tests-only-first work, with code changes allowed only if the exact row regression fails. | Hand off for execution; do not edit source matrix, breakdown closure rows, or final program verdict in this planning pass. |

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-05-11 18:27:22 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-030-plan.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/node.go`; `git status --short` | Scope is GM-030 only: add exact Go regression first; do not change production unless the regression fails; run focused Go selector and `git diff --check`; race/Flutter gates are conditional only. Worktree is dirty from prior sessions, including adjacent Go discovery files, and those changes must be preserved. | Spawn isolated Executor with `model: gpt-5.5` and `reasoning_effort: xhigh`. |
| 2026-05-11 18:28:00 CEST | Executor spawning | This plan file | Spawning Executor child via local `codex exec`; child must touch only `go-mknoon/node/pubsub_test.go` and this GM-030 plan unless the exact regression exposes a real product gap. | Wait for Executor result and inspect repo evidence. |
| 2026-05-11 18:27:59 CEST | Executor spawn retry | `codex exec --help`; this plan file | First child command failed before agent materialization because this `codex exec` build does not accept `-a` on the exec subcommand. No code or test files were touched by that failed spawn. | Relaunch Executor with supported noninteractive flags. |
| 2026-05-11 18:28:55 CEST | Executor started | This plan file; `git status --short`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/node.go` | Executor scope confirmed: GM-030 test-first change only, preserve dirty prior-session Go/Flutter/doc work, no production edits unless the new regression fails and proves a GM-030 product gap. | Add `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` in `go-mknoon/node/pubsub_test.go`. |
| 2026-05-11 18:30:12 CEST | Executor files touched | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Added `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter`, added test-only discovery counter helper, and ran `gofmt -w go-mknoon/node/pubsub_test.go`. No production files touched by GM-030 Executor. | Run required focused Go selector. |
| 2026-05-11 18:30:21 CEST | Go focused selector started | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Running required selector: `cd go-mknoon && go test ./node -run 'TestGM030|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate|TestFilterDiscoveredGroupMembers|TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestGM023|TestGM027|TestGM028' -count=1`. | Record result and decide whether production code is needed. |
| 2026-05-11 18:30:44 CEST | Go focused selector finished | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Passed: `ok github.com/mknoon/go-mknoon/node 0.973s`. GM-030 passed as tests-only evidence, so no production code change is needed; race and Flutter gates are not triggered. | Run `git diff --check`. |
| 2026-05-11 18:30:53 CEST | Diff check started | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Running required `git diff --check`. | Record result and complete Executor handoff if clean. |
| 2026-05-11 18:31:07 CEST | Diff check finished | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Passed: `git diff --check` produced no output. | Record Executor completed. |
| 2026-05-11 18:31:07 CEST | Executor completed | `go-mknoon/node/pubsub_test.go`; this GM-030 plan | GM-030 landed as tests-only evidence. Production Go discovery/config code was not touched by this Executor, so race selector was skipped; Flutter code was not touched, so Flutter gates were skipped. No blockers. | Hand off to QA Reviewer; do not write QA verdict here. |
| 2026-05-11 18:32:03 CEST | QA Reviewer spawning | Executor result; `go-mknoon/node/pubsub_test.go`; this GM-030 plan | Spawning separate QA Reviewer child via local `codex exec`; QA must verify scope adherence, exact GM-030 behavior, required command evidence, and conditional gate skips. | Wait for QA result and then write final execution verdict. |
| 2026-05-11 18:33:25 CEST | QA Reviewer started | `/tmp/gm030-executor-result.txt`; `go-mknoon/node/pubsub_test.go`; this GM-030 plan; `git status --short` | Verifying GM-030-only scope, exact scenario fidelity, required command evidence, and conditional gate skips without source, matrix, closure, or verdict edits. | Rerun the focused selector plus formatting and diff validation. |
| 2026-05-11 18:33:25 CEST | QA Reviewer completed | `/tmp/gm030-executor-result.txt`; `go-mknoon/node/pubsub_test.go`; this GM-030 plan | No blocking issues found. Exact GM-030 test exists and matches the required scenario; focused selector passed; `gofmt -l go-mknoon/node/pubsub_test.go` was clean after Executor gofmt evidence; `git diff --check` was clean; race and Flutter gates are not required because GM-030 did not touch production Go discovery/config or Flutter group config code. | Return QA result to controller. |
| 2026-05-11 18:34:07 CEST | Final verdict written | Executor result; QA result; this GM-030 plan | Final execution verdict: accepted. Required regression and gates are complete, no blocking issues remain, no non-blocking follow-ups were deferred, and source matrix/breakdown closure rows remain untouched by request. | Ready for later closure pass. |

## real scope

Own exactly GM-030: membership mutation must refresh the Go group discovery allowed-member filter so that, after D is added and C is removed, rendezvous results containing B/C/D/X only permit current active transport peers B and D.

This plan is tests-only by default. Add one exact Go discovery regression in `go-mknoon/node/pubsub_test.go`. Do not change production code unless that exact regression fails and points to a real product gap in current-config storage, active dial-target selection, or rendezvous filtering.

This session does not edit the source matrix, the session breakdown closure entries, final program verdicts, or unrelated product/test files during planning.

## closure bar

GM-030 is good enough when an exact row-owned proof shows all of the following in one scenario:

- A previous config can include admin/B/C, then the current config replaces it with admin/B/D through `UpdateGroupConfig`.
- `activeGroupMemberDialTargets`, `countRemoteGroupMembers`, and `expectedConnectedGroupMembers` use only the current active remote set B/D.
- `RendezvousDiscover` returns B/C/D/X.
- `discoverAndConnectGroupPeers` emits `ignoredNonMembers == 2`, `totalFound == 4`, and `newPeers == 2`.
- B and D become `network.Connected` through the discovery path; removed C and never-member X stay disconnected and never appear in eligible discovery results.

The source row should remain `Open` until a later closure pass records exact GM-030 evidence.

## source of truth

1. Current code and direct tests win over stale prose.
2. Source row GM-030 in `Private_group_chat_reliability_test_matrix_COMPLETE_1.md` defines the scenario and expected behavior.
3. Breakdown row/session GM-030 in `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` defines the active session path and says row-owned evidence is missing.
4. `go-mknoon/node/pubsub.go` is authoritative for Go discovery filtering and dial target behavior.
5. `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` define named Flutter gates; Go module selectors are direct row gates outside that Flutter gate script.
6. Adjacent GM-027/GM-028/GM-029 evidence is authoritative only for its own rows and overlap risks; it does not close GM-030.

## session classification

`implementation-ready`

Determination: `tests-only` first. This is not evidence-only because `go test ./node -list 'GM030|GM-030'` produced no GM-030 test names and the source/breakdown rows remain open/evidence-gated. It is not planned as code-and-tests because the inspected Go path already builds the allowed set from the stored current config before filtering rendezvous peers.

If the new test fails, execution may become code-and-tests, but only for the failing GM-030 seam.

## exact problem statement

The repo lacks exact proof that a membership mutation updates the Go discovery allowlist used by rendezvous results. The user-visible risk is that a removed member or unknown peer can be dialed after a group roster changes, while a newly added active member may be omitted from discovery recovery.

The behavior that must improve is proof coverage for the current membership filter. The behavior that must stay unchanged is current active member discovery, generic nonmember filtering, invalid-peer filtering, active-device preference, and Flutter membership/config version handling from GM-027 through GM-029.

## files and repos to inspect next

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/multi_relay_test.go`
- `go-mknoon/node/node_test.go`

Conditional only if the Go regression fails due stale or malformed configs crossing the Flutter/Go boundary:

- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/group_membership_config_version_producers_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## existing tests covering this area

- `TestFilterDiscoveredGroupMembers_ExcludesNonMembers` proves the helper filters one nonmember from a supplied allowlist.
- `TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse` proves generic discovery filtering after self/already-connected removal.
- `TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate` proves a removed peer is not dialed after `UpdateGroupConfig`, but it does not cover the row's simultaneous added D/current B/D allowlist or B/C/D/X rendezvous result.
- `TestGM023GroupPeerDiscoveryUsesActiveDeviceAfterInactiveShadow` proves active-device preference and inactive shadow exclusion.
- `TestGM027InvalidDeviceLessPeerIDDoesNotInflateGroupTargets` and `TestGM028EmptyPeerIDDoesNotInflateDiscoveryOrPublishPreflight` prove malformed/blank peer IDs do not inflate counts.
- GM-029 Dart proof covers monotonic membership config convergence but did not touch Go and does not exercise `ignoredNonMembers`.

Missing: one exact GM-030 test that combines current config mutation, added D, removed C, rendezvous B/C/D/X, and event/dial assertions.

## regression/tests to add first

Add `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` in `go-mknoon/node/pubsub_test.go`.

Test contract:

1. Start admin with a `testEventCollector`, plus B, C, D, and X local nodes.
2. Decode all peer IDs and create old config admin/B/C.
3. Install old config, then call `admin.UpdateGroupConfig` with current config admin/B/D.
4. Assert current dial targets and expected counts are exactly B and D.
5. Hook `admin.rendezvousDiscoverHook` for `groupRendezvousNamespace(groupId)` to return B, C, D, and X `peer.AddrInfo` values with addrs.
6. Call `admin.discoverAndConnectGroupPeers(groupId)`.
7. Assert the discovery event reports `totalFound == 4`, `newPeers == 2`, and `ignoredNonMembers == 2`.
8. Wait/assert B and D become `network.Connected` through the discovery path; assert C and X remain not connected.

If this passes against current code, stop product edits and classify execution as tests-only evidence. If it fails, patch only the failing seam.

## step-by-step implementation plan

1. Before editing, inspect `git status --short` and any existing diffs in `go-mknoon/node/pubsub.go` and `go-mknoon/node/pubsub_test.go`; preserve unrelated prior accepted changes.
2. Add the exact GM-030 Go regression described above and any tiny test helper needed to assert the discovery event totals.
3. Run the focused non-race Go selector. Treat a failing GM-030 assertion as the only trigger for product code changes.
4. If the test passes unchanged, do not edit production code. Record tests-only evidence in this plan file for the execution pass.
5. If the test fails because the current config is not replacing stale membership, inspect `UpdateGroupConfig`, `cloneGroupConfig`, and config normalization only.
6. If the test fails because the allowlist includes stale/unknown peers, inspect `activeGroupMemberDialTargets`, `activeGroupMemberDialTargetSet`, and `filterDiscoveredGroupMembers` only.
7. Run `gofmt -w` on any changed Go files.
8. If the test fails because Flutter emits stale configs into Go, inspect the conditional Flutter producer/listener files and keep any Dart patch narrowly tied to config refresh.
9. After any production Go discovery change, rerun both non-race and race Go selectors.
10. After any Flutter group config change, rerun the listed GM-029 producer/listener/smoke selectors and the Group Messaging Gate.
11. Stop after GM-030 proof and validation. Do not advance into GM-031 known-member dial targets, GA-023 revoked-device allowlists, GP-011 generic rendezvous filtering, or source matrix closure.

## risks and edge cases

- A stale group config could leave removed C in Go after Dart updates local membership.
- The helper's empty-allowlist behavior allows all peers; GM-030 must ensure a current non-empty B/D allowlist is built when a config exists.
- Discovered peers may connect at the libp2p network level without joining the group topic. GM-030 should assert dial/connectedness for allowed peers and no network connection for C/X, not require topic mesh readiness.
- Existing cooldown/in-flight dial state can hide a real dial. Use fresh local nodes/group IDs and avoid pre-dialing C/X.
- Active-device and invalid-peer filtering must remain intact for GM-023/GM-027/GM-028.

## exact tests and gates to run

Required focused Go selector after adding the test:

```bash
cd go-mknoon && go test ./node -run 'TestGM030|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate|TestFilterDiscoveredGroupMembers|TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestGM023|TestGM027|TestGM028' -count=1
```

Required if `go-mknoon/node/pubsub.go`, `go-mknoon/node/node.go`, or other Go discovery/config production code is touched:

```bash
cd go-mknoon && go test -race ./node -run 'TestGM030|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate|TestFilterDiscoveredGroupMembers|TestGL005PrivateGroupDiscoveryFiltersNonMembersBeforeDialUse|TestGroupDiscovery_UsesDiscoveredAddressesBeforeRelayFallback|TestGM023|TestGM027|TestGM028' -count=1
```

Required formatting after Go edits:

```bash
gofmt -w go-mknoon/node/pubsub_test.go
```

Required if Flutter group config producers/listeners are touched:

```bash
flutter test --no-pub test/features/groups/application/group_membership_config_version_producers_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-029'
./scripts/run_test_gates.sh groups
```

Always run:

```bash
git diff --check
```

`./scripts/run_test_gates.sh completeness-check` is only required if execution adds, removes, renames, or reclassifies Flutter/Dart test files. It is not required for a Go-only test addition.

## known-failure interpretation

- A failure in `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` blocks closure.
- A failure in adjacent Go selectors blocks closure if it involves discovery filtering, active dial targets, expected counts, config normalization, or event reporting touched by GM-030.
- A broad Flutter `groups` gate failure is relevant only if execution touches Flutter group config code or the failure is attributable to GM-030 changes.
- Existing dirty files from GM-024/GM-025/GM-027/GM-028/GM-029 are not GM-030 evidence and must not be reverted.
- A pre-existing unrelated failure can be treated as residual only with exact command/log attribution and passing GM-030 focused evidence.

## done criteria

- The exact GM-030 Go regression exists and either passes unchanged as tests-only evidence or drives a minimal code fix before passing.
- If it passes unchanged, no production code is edited and the plan records tests-only evidence.
- If it fails, only the failing GM-030 seam is patched.
- Required Go selector passes; race selector passes if Go production discovery/config code is touched.
- Conditional Flutter selectors/gates pass if Flutter group config code is touched.
- `git diff --check` passes.
- No source matrix row, breakdown closure entry, or final program verdict is edited in the implementation pass unless the user separately asks for closure.

## scope guard

Non-goals:

- GM-031 known-member dial target behavior.
- GA-023 revoked-device allowed-set behavior.
- GP-011 generic rendezvous filtering closure.
- GE-009 partition-heal behavior.
- Flutter UI/member-list display changes.
- Group key rotation, invite, contact, media, notification, or durable inbox behavior.
- Broad membership model rewrites or new config schemas.
- Strict Flutter libp2p peer-ID decoding beyond existing GM-027 accepted differences.

Overengineering would include adding new discovery subsystems, changing rendezvous protocol shape, changing event payload schemas beyond test-only assertion needs, or rewriting shared membership persistence for this row.

## accepted differences / intentionally out of scope

- No simulator or multi-party Flutter device proof is required by default for this Go discovery-filter row; direct Go fake-network proof is the narrowest exact evidence.
- The helper behavior where an empty allowed-member set allows all peers stays unchanged unless the exact GM-030 test proves the current config unexpectedly produces an empty allowlist.
- Current active-device preference and invalid/blank peer exclusion from GM-023/GM-027/GM-028 remain separate accepted behavior, not reimplemented here.
- Source matrix and session breakdown closure are intentionally left for a later closure pass.

## dependency impact

GM-031, GA-023, GP-011, and broader partition/recovery rows can use GM-030 only as evidence that current membership mutations feed rendezvous discovery filtering. They still need their own row-owned tests for known-member dialing, revoked devices, generic rendezvous filtering, and partition healing.

If GM-030 exposes a product bug, later rows that depend on active discovery membership should wait until the narrow GM-030 fix and gates are accepted. If GM-030 lands as tests-only evidence, later rows can proceed without carrying a workaround for D-added/C-removed rendezvous allowlists.

## reviewer findings

Reviewer verdict: sufficient with adjustments.

Missing files, tests, regressions, or gates: no structural omissions after adding explicit `gofmt`, direct discovery-address selector coverage, and a stricter B/D connectedness assertion.

Stale or incorrect assumptions: none found. The plan treats current code as evidence of likely behavior but does not call the row covered without exact proof.

Overengineering: none. The plan avoids new discovery architecture, Flutter work by default, simulator proof by default, and source matrix closure.

Decomposition: sufficient. One exact Go regression owns the row; production edits are allowed only if that regression fails.

Minimum needed for sufficiency: already applied in the reviewer adjustments.

## arbiter decision

Structural blockers: none.

Incremental details: reviewer requested stricter B/D connectedness proof, a small event-total helper allowance, `gofmt`, and direct discovery-address selector coverage. These are applied.

Accepted differences: no simulator proof, no Flutter proof by default, no generic GP-011 closure, no GM-031 known-member dial closure, and no source matrix/breakdown closure edits in this planning pass.

Stop rule result: stop. No new structural blocker remains after reviewer adjustment.

## Final verdict

Final execution verdict: `accepted`.

GM-030 landed as tests-only evidence. `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` now proves the old admin/B/C to current admin/B/D mutation, B/C/D/X rendezvous response, B/D-only active dial target set, `totalFound == 4`, `newPeers == 2`, `ignoredNonMembers == 2`, B/D connectedness, and C/X non-connectedness.

Production code was not changed by GM-030 because the exact regression passed. The required focused Go selector passed in Executor and QA, `gofmt`/`gofmt -l` are clean, and `git diff --check` passed. The Go race selector and Flutter gates were not required because GM-030 did not touch Go production discovery/config code or Flutter group config code.

Blocking issues remaining: none. Non-blocking follow-ups deferred: none. This plan is ready for a later closure pass; source matrix rows, breakdown closure rows, closure ledger, and final program verdict were intentionally not edited here.

## Final plan

Add `TestGM030MembershipMutationUpdatesDiscoveryAllowedMemberFilter` to `go-mknoon/node/pubsub_test.go`. The test must install old admin/B/C config, replace it with current admin/B/D config, return B/C/D/X from rendezvous, and prove only B/D are eligible/dialed while C and X are ignored with `ignoredNonMembers == 2`.

Run the focused Go selector and `git diff --check`; run the Go race selector only if Go production discovery/config code is touched; run Flutter GM-029/group gates only if Flutter group config code is touched.

## Structural blockers remaining

None.

## Incremental details intentionally deferred

- No broad Go package sweep is required by default beyond the focused selector unless execution touches production discovery code in a broader way.
- No Flutter `groups` gate is required for a Go-only test addition.
- No `completeness-check` is required unless Dart/Flutter test inventory changes.

## Accepted differences intentionally left unchanged

- Empty allowlist means allow-all at helper level unless GM-030 proves the current config produces an empty allowlist unexpectedly.
- Simulator, real-device, and multi-party Flutter proof are not default requirements for this Go discovery-filter row.
- GP-011, GM-031, GA-023, and GE-009 remain separate rows.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-027-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-028-plan.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GM-029-plan.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/multi_relay_test.go`
- `go-mknoon/node/node_test.go`
- `lib/features/groups/application/group_config_payload.dart`
- `lib/features/groups/application/add_group_member_use_case.dart`
- `lib/features/groups/application/remove_group_member_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`

## Why the plan is safe or unsafe to implement now

Safe to implement now. The plan is row-scoped, proof-first, uses existing Go fake-network seams, preserves the dirty worktree, has conditional code-edit rules, names exact selectors and race conditions, and explicitly excludes later membership/discovery rows and closure-doc edits.
