# Group Active Member Key Material Session Breakdown

Status: closed

## Run Mode Snapshot

- Active mode: standard
- Degraded local continuation allowed: no
- Source proposal / matrix / closure doc: user-reported group chat audit bug "Active members can have incomplete key-distribution material"
- Source status vocabulary: `Open`, `In Progress`, `Closed`, `Blocked`
- Overall closure bar: `GroupJoinTopic` and `GroupUpdateConfig` reject active member config entries that lack usable key-distribution material, with focused TDD proof and no broad protocol redesign.
- Final verdict policy: `closed` when all sessions are accepted and focused tests pass; `still_open` if required implementation or test evidence is blocked.

## Controller Progress

| Time | Phase | Files / Docs | Decision | Next Action |
| --- | --- | --- | --- | --- |
| 2026-05-23 22:26 CEST | intake | `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `lib/features/groups/application/group_config_payload.dart`; `lib/features/groups/domain/models/group_member.dart` | Current bridge only rejects malformed present fields; Dart has partial normalization but still treats member-level `publicKey` alone as deliverable in some paths. Focused Go bridge gate currently compiles. | Plan `GAKM-001`, execute, close, then write final program verdict. |
| 2026-05-23 22:55 CEST | closure audit | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md`; `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-breakdown.md`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go` | `GAKM-001` accepted: on-disk validator/test evidence matches the closure bar and focused gates pass. | Final verdict closed; reopen only on bridge guard regression or protocol-level ML-KEM/key-package semantics change. |

## Recommended Plan Count

1

## Session Ledger

| Session ID | Status | Plan File | Execution Verdict | Closure Docs Touched | Blocker Class | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| GAKM-001 | accepted | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md` | implemented | `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-GAKM-001-plan.md`; `Test-Flight-Improv/Group-Chat-Feature/group-active-member-key-material-session-breakdown.md` | none | Closure audit 2026-05-23 22:55 CEST accepted the bridge-boundary guard. Concrete gates passed: `go test ./bridge -run 'TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial' -count=1`; `go test ./bridge -run 'TestGroupJoinTopic_|TestGroupUpdateConfig_|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys' -count=1`; `git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go`. |

## Ordered Session Breakdown

### GAKM-001 - Active Member Key Material Guard

- Classification: closed
- Scope: Require each active group config member applied through `GroupJoinTopic` or `GroupUpdateConfig` to have usable key-distribution material. Keep existing malformed-field checks and key epoch/key bytes checks unchanged.
- Exact owner files:
  - `go-mknoon/bridge/bridge.go`
  - `go-mknoon/bridge/bridge_test.go`
- Likely supporting fixture file:
  - `go-mknoon/bridge/bridge_generate_next_key_test.go` only if focused bridge selectors reveal another placeholder config fixture.
- Direct tests:
  - Landed bridge tests for device-less members missing `publicKey` or `mlKemPublicKey`.
  - Landed bridge tests for device-backed members with no active usable device.
  - Preserved valid member-level and device-level config paths.
- Gates:
  - `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupUpdateConfig_RejectsIncompleteActiveMemberKeyMaterial' -count=1`
  - `cd go-mknoon && go test ./bridge -run 'TestGroupJoinTopic_|TestGroupUpdateConfig_|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys' -count=1`
  - `git diff --check -- go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/bridge/bridge_generate_next_key_test.go`
- Dependency state: satisfied. Focused compile checks for `go test ./bridge -run TestGroupJoinTopic_RejectsInvalidKeyState -count=1` and `go test ./node -run TestSendGroupMessageReliableStoresExactEnvelopeForActiveRecipients -count=1` passed before this breakdown was created.
- Source doc / matrix updates: this breakdown and the session plan only.
- Scope guard: Do not change Dart invite protocol, key rotation distribution, node config storage, device identity schema, database migrations, or broad group membership semantics.

## Final Program Verdict

Closed. `GAKM-001` is the only session in this breakdown, the ledger records it as accepted, and the concrete focused gates are recorded in both the plan closure audit and the session ledger. Future work should reopen this area only for a real bridge guard regression or an intentional protocol change that makes key-package-only devices a supported substitute for ML-KEM.

## Downstream Execution Path

For each runnable session:

1. Ensure the session plan exists and is execution-safe via `$implementation-plan-orchestrator`.
2. Execute the plan via `$implementation-execution-qa-orchestrator`.
3. Close the session via `$implementation-closure-audit-orchestrator`.
4. Update this session ledger.

After all sessions resolve, run final program acceptance and persist one final verdict.
