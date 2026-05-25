# GAKM-001 - Active Member Key Material Guard Plan

Status: closed

## Planning Progress

| Time | Role | Files inspected since last update | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-23 22:34 CEST | intake | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-breakdown.md`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `/Users/I560101/.codex/skills/implementation-plan-orchestrator/SKILL.md` | Session GAKM-001 and intended plan path confirmed. No intake blocker. | Start Evidence Collector role. |
| 2026-05-23 22:36 CEST | local plan fallback | `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `lib/features/groups/application/group_config_payload.dart`; `lib/features/groups/domain/models/group_member.dart`; explorer fixture report | Spawned planner no-progressed after bounded wait and progress request. Breakdown entry is execution-safe, so local artifact-only fallback produced this execution-ready TDD plan. | Spawn fresh execution agent. |

## Execution Progress

| Time | Phase | Files inspected or touched | Decision / blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-23 22:41 CEST | contract extraction complete | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md`; `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-breakdown.md`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `go-mknoon/bridge/bridge_generate_next_key_test.go` | Scope, source of truth, owner files, RED tests, required selectors, `gofmt`, `git diff --check`, done criteria, and scope guard extracted. Existing unrelated bridge edits detected and must be preserved. | Spawn Executor with `gpt-5.5` / `model_reasoning_effort=xhigh`. |
| 2026-05-23 22:41 CEST | Executor spawning | `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go` | Starting isolated Executor child for TDD implementation. | Await Executor result, then run QA Reviewer. |
| 2026-05-23 22:42 CEST | Executor spawn retry | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md` | First child invocation failed before starting because `codex exec` rejected misplaced `-a`; no GAKM tests or production edits were made. Current phase remains Executor spawn. | Retry Executor with corrected `codex exec` invocation using `--dangerously-bypass-approvals-and-sandbox`. |
| 2026-05-23 22:43 CEST | Executor start / contract extracted | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md`; `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-breakdown.md`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `go-mknoon/bridge/bridge_generate_next_key_test.go` | Scope guard, RED tests, required selectors, and existing unrelated dirty bridge edits confirmed. No blocker. | Add RED incomplete active member key-material bridge tests before production validation changes. |
| 2026-05-23 22:44 CEST | Executor child no-progress / local fallback start | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md`; `go-mknoon/bridge/bridge_test.go` | Spawned Executor exceeded bounded wait after adding only this visible progress row; no GAKM tests or production validator changes landed, and no child process remains. | Continue sequentially in local fallback: add RED tests first, run focused selector, then implement minimal validator. |
| 2026-05-23 22:50 CEST | RED proof | `go-mknoon/bridge/bridge_test.go` | Focused GAKM tests failed before production validation: invalid join/update configs returned `ok=true` for missing member ML-KEM, missing public key, active device without ML-KEM, and revoked-only device cases. Duplicate partial test definitions from the no-progress child were reconciled into one focused test set. | Implement the smallest bridge validator guard and rerun focused tests. |
| 2026-05-23 22:51 CEST | implementation | `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go` | Added bridge-only active member key-distribution checks, preserving malformed-material precedence. Updated valid bridge fixtures with ML-KEM material and kept key-package-only devices invalid because current distribution paths still require ML-KEM. | Run required gates and diff check. |
| 2026-05-23 22:52 CEST | GREEN proof | `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `go-mknoon/bridge/bridge_generate_next_key_test.go` | Required gates passed: `go test ./bridge -run 'TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial' -count=1`; `go test ./bridge -run 'TestGroupJoinTopic_|TestGroupUpdateConfig_|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys' -count=1`; `git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go`. | Proceed to closure review. |

## Execution Result

Verdict: implemented

- `GroupJoinTopic` now rejects active group config members with no usable key-distribution material before joining or refreshing native group state.
- `GroupUpdateConfig` now rejects the same incomplete active member material before replacing stored config.
- Valid legacy member-level material and valid active device material remain accepted by focused bridge tests.
- Key-package-only devices remain invalid in this release because the current key distribution/encrypt path still requires `mlKemPublicKey`.

## Closure Audit

Verdict: closed / accepted for `GAKM-001` as of 2026-05-23 22:55 CEST.

- Closed: bridge validation now rejects active members that lack both legacy member-level `publicKey` + `mlKemPublicKey` and a usable active device before `GroupJoinTopic` or `GroupUpdateConfig` mutates native group state.
- Evidence: on-disk validator and focused tests were rechecked, and the required gates passed: `go test ./bridge -run 'TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial' -count=1`; `go test ./bridge -run 'TestGroupJoinTopic_|TestGroupUpdateConfig_|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys' -count=1`; `git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go`.
- Residual-only: node-side duplicate validation and future key-package-only delivery semantics remain intentionally out of scope; revisit only if the protocol makes key packages a true substitute for ML-KEM or the bridge guard regresses.

## Device/Relay Proof Profile

Host-only. This session changes Go bridge validation and uses Go host tests only. No simulator, device, relay, multi-relay, or OS notification fixture is required.

## Real Scope

Change only the Go bridge config validator so `GroupJoinTopic` and `GroupUpdateConfig` reject active members without usable key-distribution material.

In scope:
- Require every active member entry to have either:
  - device-less legacy material: non-empty `member.PublicKey` and `member.MlKemPublicKey`; or
  - at least one active device with non-empty `deviceId`, `transportPeerId`, `deviceSigningPublicKey`, and `mlKemPublicKey`.
- Preserve existing malformed-key checks.
- Add focused bridge tests and update only fixtures that are supposed to remain valid under the stricter contract.

Out of scope:
- Dart invite protocol changes.
- Node storage changes.
- Key rotation distribution logic.
- Database migrations.
- Requiring key-package material as a substitute for ML-KEM.
- Broad membership or role semantics.

## Closure Bar

The bridge must reject incomplete active member key material before native config state is joined, refreshed, or updated, while valid legacy member-level and device-level configs still pass existing behavior.

## Source Of Truth

- `go-mknoon/bridge/bridge.go` is authoritative for FFI boundary validation.
- `go-mknoon/node/group.go` defines member/device fields.
- Dart helpers in `lib/features/groups/application/group_config_payload.dart` and `lib/features/groups/domain/models/group_member.dart` inform expected deliverable material but do not replace bridge validation.
- Existing bridge tests define accepted JSON response shapes.

## Session Classification

`closed`

## Pre-Implementation Problem Statement (Closed)

`validateBridgeGroupConfigMemberKeyMaterial` currently rejects malformed present fields, but allows active members with empty `PublicKey`, empty `MlKemPublicKey`, or no usable active device. Such members can be accepted into Go config state while key distribution or invite/key-update encryption cannot reliably target them.

User-visible improvement: malformed or incomplete group configs fail at the bridge boundary instead of making a user appear added while they cannot receive current group key material.

Must stay unchanged: valid configs, existing explicit malformed-field errors, group key epoch/key byte validation, already-joined refresh, and node-level membership uniqueness behavior.

## Files And Repos To Inspect Next

- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/bridge/bridge_generate_next_key_test.go` only if a focused selector reveals a placeholder fixture.

## Existing Tests Covering This Area

- `TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys` covers malformed present key fields.
- `TestGroupJoinTopic_WithInviteData`, `TestGroupJoinTopic_AlreadyJoinedIsIdempotent`, BB-008/RA-015 bridge tests cover valid config acceptance and already-joined refresh.
- `TestGroupUpdateConfig_*` covers basic update-config validation.

Pre-implementation missing coverage, now closed:
- `TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial` and `TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial` now reject active members with missing distribution material.

## Regression / Tests To Add First

Add failing tests before production code:

- `TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial`
  - member with no devices and missing `mlKemPublicKey` -> `INVALID_JOIN_MATERIAL`
  - member with no devices and missing `publicKey` -> `INVALID_JOIN_MATERIAL`
  - member with devices but no active usable device -> `INVALID_JOIN_MATERIAL`
  - assert invalid group state is not stored.

- `TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial`
  - same core invalid cases -> `INVALID_INPUT`
  - assert invalid update does not replace an existing valid config.

Also include one valid device-backed member case if existing tests do not already cover it after fixture updates.

## Step-By-Step Implementation Plan

1. Add the two failing bridge tests.
2. Run focused new tests and confirm they fail for the current permissive validator.
3. Update `validateBridgeGroupConfigMemberKeyMaterial` with minimal helpers:
   - active device check: status empty/`active` and no `revokedAt`
   - usable device check: active plus non-empty `deviceId`, `transportPeerId`, `deviceSigningPublicKey`, and `mlKemPublicKey`
   - member-level fallback check: no usable active devices and both member-level `PublicKey` and `MlKemPublicKey` non-empty
4. Keep malformed checks before or alongside missing-material checks so explicit malformed reasons remain useful.
5. Update only bridge test fixtures that should be valid under the stricter material contract by adding `mlKemPublicKey` to hand-built members or adding a valid active device.
6. Run focused bridge selectors, gofmt, and diff check.
7. Record execution result in this plan.

## Risks And Edge Cases

- Existing tests may use hand-built config members with only `publicKey`; update fixtures only where the test is not about missing key material.
- Device configs with revoked-only devices should not satisfy active material.
- A device with key package but no `mlKemPublicKey` should remain invalid in this session because current encrypt paths still use ML-KEM.
- Error precedence should remain missing field -> key epoch/key bytes -> member material for `GroupJoinTopic`.

## Exact Tests And Gates To Run

Required:

```bash
cd go-mknoon
go test ./bridge -run 'TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial' -count=1
go test ./bridge -run 'TestGroupJoinTopic_|TestGroupUpdateConfig_|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys' -count=1
```

Formatting/check:

```bash
gofmt -w go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go
git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go
```

Supporting compile sanity if broad bridge package fails:

```bash
cd go-mknoon
go test ./bridge -run TestGroupJoinTopic_RejectsInvalidKeyState -count=1
```

## Known-Failure Interpretation

The worktree has unrelated dirty files, including prior bridge key validation and node pubsub reliable-send/already-joined changes. Do not revert them. If broad `go test ./bridge` fails on relay/network-style tests or unrelated node package state, classify separately and rely on the focused selectors above for this session.

## Done Criteria

- New tests fail before implementation and pass after.
- `GroupJoinTopic` and `GroupUpdateConfig` reject incomplete active member material with existing error-code conventions.
- Existing focused join/update bridge tests pass after fixture updates.
- `gofmt` and `git diff --check` pass for touched files.
- Session ledger records accepted closure with concrete evidence.

## Scope Guard

Do not:
- Change public Dart APIs.
- Add database migrations.
- Rework key-package semantics.
- Modify key rotation distribution.
- Change node `GroupConfig` structs.
- Broaden into admin signature verification or config epochs.

## Accepted Differences / Intentionally Out Of Scope

Node-side duplicate validation would be defense-in-depth but is not required for this bridge-boundary bug. Key-package-only delivery may become valid under a future protocol, but current send/encrypt paths still require ML-KEM, so this session requires `mlKemPublicKey`.

## Dependency Impact

This guard improves reliability for invite, add/re-add, and rotation flows by preventing configs that cannot receive key material. Later key-package protocol work must revisit the usable-device predicate if key packages become a true substitute for ML-KEM.
