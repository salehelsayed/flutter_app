# Group Inbox Store Transient Recovery Session Breakdown

Status: closed
Recommended plan count: 1
Source bug: group inbox store lacks transient relay recovery/retry and transient classifier is too narrow.

## Run-Mode Snapshot

- Active mode: `standard`
- Degraded local continuation explicitly allowed: no
- Source proposal, matrix, or closure doc path: none; source evidence is the user bug statement for 2026-05-23 plus current code in `go-mknoon/node/group_inbox.go`.
- Source row/status vocabulary: doc-local single-session vocabulary: `unresolved`, `accepted`, `accepted_with_explicit_follow_up`, `blocked`, `skipped_due_to_dependency`.
- Overall closure bar: `GroupInboxStore` must perform one transient recovery/retry path equivalent to retrieve after connect/open stream/write/read EOF/reset/timeout/deadline/no-address style failures, while preserving existing relay iteration, non-transient errors, request shape, recipient derivation, and stream cleanup.
- Final verdict policy: write `closed` only after `GISTR-001` is accepted with focused host Go test evidence; write `still_open` if code or focused tests remain missing or blocked. Do not use `accepted_with_explicit_follow_up` for the core bug.
- Dirty worktree at artifact creation: existing unrelated product/test edits are present, including `go-mknoon/node/group_inbox.go` and `go-mknoon/node/group_inbox_test.go`. Executors must preserve unrelated changes and record a fresh `git status --short` before code execution.

## Program Scope

Fix one Go node reliability gap: group inbox store should use the same transient relay recovery shape that group inbox retrieve already uses, and the shared transient classifier should recognize the broader set of stream setup and frame IO failures seen during relay churn.

Out of scope: Flutter/Dart send UX, relay-server storage semantics, recipient ACL policy, push content, native bridge APIs, database migrations, generated gomobile artifacts, and broad libp2p retry architecture.

## Session Ledger

| Session | Status | Classification | Scope | Plan | Blocker |
| --- | --- | --- | --- | --- | --- |
| GISTR-001 | accepted | implementation-ready | Add group inbox store transient recover/retry plus broaden the shared transient classifier | `group-inbox-store-transient-recovery-session-GISTR-001-plan.md` | none |

## Ordered Session Breakdown

### GISTR-001 - Store Transient Recovery And Classifier

- Dependency state: none; runnable now.
- Exact scope: update `go-mknoon/node/group_inbox.go` so `GroupInboxStore` retries the store operation once after a transient relay stream failure, using `recoverGroupInboxRelayStream` before retry. Broaden `isTransientGroupInboxRelayStreamError` so it covers connect/open stream/dial/reset/timeout/deadline/no addresses/write/read EOF style failures.
- Likely code-entry files: `go-mknoon/node/group_inbox.go`.
- Likely direct tests: `go-mknoon/node/group_inbox_test.go`.
- Existing evidence: retrieve path already calls `groupInboxRetrieveOnce`, classifies transient errors, runs `recoverGroupInboxRelayStream`, then retries once. Store path directly calls `rs.ForEach` and has no equivalent recover/retry wrapper.
- Tests to add first: a store transient EOF/reset retry test that observes one recovery hook call and two store attempts, plus classifier table coverage for connect/open stream/dial/reset/timeout/deadline/no addresses/write/read EOF errors.
- Supporting existing regressions: store request shape, relay fallback order, all-relay failure, non-OK relay response, and stream reset/close behavior.
- Named gates: host-only Go node focused gates listed in the session plan.
- Closure docs to update: this breakdown ledger and final verdict only.

## Downstream Execution Path

1. Planning: reuse `Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-GISTR-001-plan.md` when it remains execution-safe; otherwise refresh only that plan path with `$implementation-plan-orchestrator` using `model: gpt-5.5` and `reasoning_effort: xhigh`.
2. Execution: run `$implementation-execution-qa-orchestrator` for `GISTR-001` only, using the plan file as the contract. Require `model: gpt-5.5` and `reasoning_effort: xhigh`.
3. Closure: run `$implementation-closure-audit-orchestrator` for `GISTR-001`, then update this ledger with final execution verdict, docs touched, and blocker class if any. Require `model: gpt-5.5` and `reasoning_effort: xhigh`.
4. Final acceptance: after the one session is resolved, run final program closure against this breakdown only. Persist exactly one final program verdict from `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`.

## Host-Only Proof Profile

- Profile: `host-only`
- Live device availability check: not required; this is Go node stream/retry behavior covered by host tests.
- Required closure evidence: focused `go test` commands from the session plan.
- Supporting evidence only: broader Flutter, simulator, paired-device, real-network, and multi-relay device-lab gates are not required for this one bug.
- Environment variables: none required.

## Controller Progress

- 2026-05-23: Artifact intake created for one current bug only. Breakdown and doc-scoped plan are the only owned write paths for this controller turn.
- 2026-05-23: GISTR-001 executed and accepted. Added focused RED tests for store transient retry, recovery failure, non-transient relay errors, relay fallback before recovery, and classifier coverage. Implemented one-shot store recovery wrapper in `go-mknoon/node/group_inbox.go`. Focused Go gates and diff hygiene passed. Optional `go test ./node -count=1 -run 'GroupInbox'` was stopped after more than one minute with no output and was not required closure evidence.

## Final Program Verdict

Verdict: `closed`

Evidence:

- `cd go-mknoon && go test ./node -count=1 -run 'TestGISTR001GroupInboxStoreRetriesAfterTransientRelayEOF|TestGISTR001GroupInboxStoreDoesNotRetryWhenRecoveryFails|TestGISTR001GroupInboxStoreDoesNotRecoverNonTransientRelayError|TestGISTR001GroupInboxStoreUsesNextRelayBeforeRecovery|TestGISTR001TransientClassifierCoversRelaySetupAndIOFailures'`
- `cd go-mknoon && go test ./node -count=1 -run 'TestGI002GroupInboxStoreSendsGroupStoreRequestShape|TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess|TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail|TestGI007GroupInboxStoreReturnsRelayNonOKError|TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream|TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF'`
- `git diff --check -- go-mknoon/node/group_inbox.go go-mknoon/node/group_inbox_test.go Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-GISTR-001-plan.md`

Closure rationale: the store path now preserves existing relay iteration and application-error behavior while adding the same bounded transient recover-and-retry path already used by retrieve.
