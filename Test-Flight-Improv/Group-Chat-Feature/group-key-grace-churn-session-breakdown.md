# Group Key Grace Churn Session Breakdown

Status: closed
Recommended plan count: 1
Source bug: "Key grace handling is still fragile under rapid membership churn"

## Run Mode Snapshot

- Active mode: standard
- Degraded local continuation explicitly allowed: no
- Source proposal/matrix/closure doc path: this bug report in the current user request
- Source status vocabulary: `planned`, `accepted`, `blocked`, `closed`
- Overall closure bar: native group key state must preserve supplied grace metadata and must not generate a second rotation while the current previous-key grace window is still active.
- Final verdict policy: `closed` only after the single session is accepted with focused RED/GREEN evidence and no meaningful residual for the simpler product-safe option.

## Program Scope

Close the native key-grace loss and rapid double-rotation footgun without adding a key ring. Preserve incoming `PrevKey`, `PrevKeyEpoch`, and `GraceDeadline`; block a second generated rotation during active grace.

## Ordered Session Breakdown

| Session | Classification | Dependency | Scope | Likely code-entry files | Likely tests/gates | Plan |
| --- | --- | --- | --- | --- | --- | --- |
| GKGC-001 | closed (was implementation-ready) | none | Preserve joined grace key metadata and reject `group:generateNextKey` while native key state has active grace | `go-mknoon/node/pubsub.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, `go-mknoon/bridge/bridge_generate_next_key_test.go` | `cd go-mknoon && go test ./node -count=1 -run 'TestGroupKeyGraceChurn|TestGK017|TestGK018'`; `cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupGenerateNextKey'` | `group-key-grace-churn-session-GKGC-001-plan.md` |

## Session Ledger

| Session | Status | Plan | Execution verdict | Closure docs touched | Note |
| --- | --- | --- | --- | --- | --- |
| GKGC-001 | closed | `group-key-grace-churn-session-GKGC-001-plan.md` | accepted | `group-key-grace-churn-session-GKGC-001-plan.md`; `group-key-grace-churn-session-breakdown.md` | Native joined-key grace preservation and active-grace generate-next-key rejection closed; reopen only on real regression in the listed gates. |

## Controller Progress

- 2026-05-23: Pipeline intake created for the simpler product-safe option. One session is runnable and dependency-free.
- 2026-05-23 23:37:02 CEST - Closure audit completed for GKGC-001. Files inspected/touched: `group-key-grace-churn-session-GKGC-001-plan.md`, this breakdown, and scoped GKGC code/test hunks. Decision/blocker: execution result was accepted, controller-verified Go/binding gates passed, and no residual implementation item remains for this single-session program.

## Final Program Verdict

closed

GKGC-001 is accepted and closure-audited. The program closure bar is met by preserving supplied native previous-key grace metadata and blocking `group:generateNextKey` during active previous-key grace without adding a key ring. Residual-only items: none for this host-only native session. Accepted out-of-scope differences remain key-ring/multi-key retention, Flutter/UI presentation of `GROUP_KEY_GRACE_ACTIVE`, and device/relay proof.
