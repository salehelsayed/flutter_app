# Group Active Device Config Validation Session Breakdown

Status: closed
Recommended plan count: 1
Source bug: "Active device config validation is still too weak"

## Run Mode Snapshot

- Active mode: standard
- Degraded local continuation explicitly allowed: no
- Source proposal/matrix/closure doc path: this bug report in the current user request
- Source status vocabulary: `planned`, `accepted`, `blocked`, `closed`
- Overall closure bar: native group config admission must reject active device entries that cannot dial, publish, or validate messages because required device identity fields are missing or the active device transport peer id is not a valid libp2p peer id.
- Final verdict policy: `closed` only after the single session is accepted with focused RED/GREEN evidence and no meaningful residual for the active-device admission boundary.

## Program Scope

Close the native active-device config footgun at join/update/refresh validation time. Keep the implementation minimal and compatible with existing account-id based legacy no-device fixtures unless the session plan proves a narrower safe legacy tightening.

## Ordered Session Breakdown

| Session | Classification | Dependency | Scope | Likely code-entry files | Likely tests/gates | Plan |
| --- | --- | --- | --- | --- | --- | --- |
| GADC-001 | implementation-ready | none | Reject malformed active device entries during `JoinGroupTopic`, `UpdateGroupConfig`, and `RefreshJoinedGroupStateIfNewer`; preserve inactive/revoked historical device tolerance and legacy no-device compatibility unless safely narrowed | `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/bridge/bridge_test.go` | `cd go-mknoon && go test ./node -count=1 -run 'TestGroupConfigActiveDeviceValidation|TestActiveGroupInboxRecipients|TestGroupTopicValidator'`; `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupJoinTopic|TestSV009|TestGroupUpdateConfig'` | `group-active-device-config-validation-session-GADC-001-plan.md` |

## Session Ledger

| Session | Status | Plan | Execution verdict | Closure docs touched | Note |
| --- | --- | --- | --- | --- | --- |
| GADC-001 | closed | `group-active-device-config-validation-session-GADC-001-plan.md` | accepted | `group-active-device-config-validation-session-GADC-001-plan.md`; `group-active-device-config-validation-session-breakdown.md` | Active-device config admission closed for join/update/refresh and bridge join/update failure mapping; legacy no-device libp2p strictness and inactive/revoked historical-device strictness remain accepted out of scope. |

## Controller Progress

- 2026-05-24: Pipeline intake created. One session is runnable and dependency-free; scope is native active-device admission validation with explicit legacy compatibility review.
- 2026-05-24: GADC-001 executor landed focused Go code/tests in `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/bridge/bridge.go`, and `go-mknoon/bridge/bridge_test.go`.
- 2026-05-24: QA reviewer verdict accepted with no blocking findings.
- 2026-05-24: Controller reran and passed `cd go-mknoon && go test ./node -count=1 -run 'TestGroupConfigActiveDeviceValidation|TestActiveGroupInboxRecipients|TestGroupTopicValidator'`.
- 2026-05-24: Controller reran and passed `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupJoinTopic|TestSV009|TestGroupUpdateConfig'`.
- 2026-05-24: Controller reran and passed `git diff --check` scoped to touched Go/generated paths, `scripts/ensure_go_ios_bindings.sh`, `scripts/ensure_go_macos_bindings.sh`, `bash scripts/ensure_go_android_bindings.sh`, and `scripts/verify_gomobile_bindings.sh all`.
- 2026-05-24: Matrix check found no matching row in `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`; no matrix row was invented.

## Final Program Verdict

closed

GADC-001 is accepted and closed for active-device config admission only. The closed behavior is limited to rejecting malformed active device entries before native group state is accepted through `JoinGroupTopic`, `UpdateGroupConfig`, and `RefreshJoinedGroupStateIfNewer`, plus bridge preflight failure responses for the same malformed active-device join/update inputs.

Maintenance-time safety is defined by the passed focused node and bridge Go gates plus binding verification evidence above. Legacy no-device account-like `PeerId` tolerance remains intentionally out of scope, and inactive/revoked historical devices remain tolerated as residual-only compatibility behavior.
