# Group Inbox Store Transient Recovery GISTR-001 Plan

Status: accepted

## Real Scope

Implement one focused Go node fix: make `GroupInboxStore` recover and retry once after transient relay stream failures, and broaden the shared transient classifier used by group inbox relay recovery.

Files in implementation scope:

- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`

Docs in closure scope:

- `Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-GISTR-001-plan.md`

## Closure Bar

The session is accepted only when focused host tests prove:

- `GroupInboxStore` retries once after a transient relay stream failure.
- The retry happens only after `recoverGroupInboxRelayStream` succeeds.
- Recovery failure returns the original store error without a second store attempt.
- Non-transient relay/application errors are not retried through recovery.
- `isTransientGroupInboxRelayStreamError` classifies connect/open stream/dial/reset/timeout/deadline/no addresses/write/read EOF style failures as transient.
- Existing group inbox store relay fallback, request shape, non-OK response, and stream cleanup behavior remain green.

## Source Of Truth

Authoritative order when sources disagree:

1. Current worktree code in `go-mknoon/node/group_inbox.go`.
2. Existing tests in `go-mknoon/node/group_inbox_test.go`.
3. This plan and the adjacent breakdown.

Current evidence:

- `GroupInboxStore` builds a relay selector and performs store work directly inside `rs.ForEach`.
- `groupInboxRetrieve` already wraps `groupInboxRetrieveOnce` with transient classification, `recoverGroupInboxRelayStream`, and one retry.
- `isTransientGroupInboxRelayStreamError` currently recognizes EOF/deadline and a narrow `read response` message subset.

## Session Classification

`implementation-ready`

No source-matrix dependency or device-lab prerequisite is required.

## Exact Problem Statement

During relay churn, the group inbox retrieve path can recover from transient stream failures by reconnecting relays and retrying once. The store path does not use that recovery path, so a transient connect/open stream/write/read EOF/reset/timeout/deadline/no-address failure can surface as a durable store failure even though a reconnect and retry could succeed. The classifier is also too narrow because it mostly recognizes `read response` failures, leaving setup and write-side stream failures unrecovered.

## Device/Relay Proof Profile

- Profile: `host-only`
- Live device availability check: not required.
- Required closure evidence: local Go host tests under `go-mknoon/node`.
- Relay fixture: in-process libp2p relay/test hosts only; no external relay address or mobile simulator is required.
- `FLUTTER_DEVICE_ID`: not applicable.
- `MKNOON_RELAY_ADDRESSES`: not applicable.

## Dirty Worktree Scope Note

The workspace is already dirty, including product/test changes outside this session. Do not revert unrelated files. Before execution, record `git status --short`; after execution, verify new or modified files are limited to `go-mknoon/node/group_inbox.go`, `go-mknoon/node/group_inbox_test.go`, and the two doc paths named above.

## Existing Tests Covering This Area

- `TestGI002GroupInboxStoreSendsGroupStoreRequestShape`
- `TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess`
- `TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail`
- `TestGI007GroupInboxStoreReturnsRelayNonOKError`
- `TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream`
- `TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF`

## TDD Plan

### RED

Add focused failing tests before production changes:

1. `TestGISTR001GroupInboxStoreRetriesAfterTransientRelayEOF`: in-process relay handler closes the first stream before response, succeeds on second; set `groupInboxRecoverHook`, assert one recover call, two store requests, and successful store.
2. `TestGISTR001GroupInboxStoreDoesNotRetryWhenRecoveryFails`: first store attempt hits a transient read/write EOF; recovery hook returns an error; assert the original store error is returned and only one request reaches the relay.
3. `TestGISTR001GroupInboxStoreDoesNotRecoverNonTransientRelayError`: relay returns a non-OK group store response; assert no recovery hook call and no retry.
4. `TestGISTR001TransientClassifierCoversRelaySetupAndIOFailures`: table-test wrapped errors for connect to relay, open inbox stream, dial failure, stream reset, timeout, deadline, no addresses, write request EOF/reset, and read response EOF/reset.

### GREEN

Implement the narrowest production fix:

1. Extract the current store relay operation into a private helper, for example `groupInboxStoreOnce`, preserving request construction, recipient derivation, relay selector iteration, stream deadlines, `finishStream`, and existing error messages where practical.
2. Make `GroupInboxStore` call the helper once, classify the returned error, run `recoverGroupInboxRelayStream` for transient errors, and retry the helper once when recovery succeeds.
3. Keep validation and active-recipient derivation before retry so a bad config does not repeat or trigger relay recovery.
4. Broaden `isTransientGroupInboxRelayStreamError` with case-insensitive message checks for setup and IO failures: `connect to relay`, `open inbox stream`, `dial`, `no addresses`, `reset`, `timeout`, `deadline`, `eof`, `write request`, `read response`, and closely related stream-closed variants.
5. Preserve non-transient application failures, including `group inbox store failed: ...`, without recovery retry.

### REFACTOR

1. Remove duplicate store/retrieve transient classification strings only if it keeps the file simpler.
2. Keep helper names private and local to `group_inbox.go`.
3. Run `gofmt` on touched Go files.
4. Avoid broad retry frameworks, new goroutines, new node fields, or changes outside group inbox store/retrieve helpers.

## Exact Tests And Gates To Run

Focused RED/GREEN gate:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGISTR001GroupInboxStoreRetriesAfterTransientRelayEOF|TestGISTR001GroupInboxStoreDoesNotRetryWhenRecoveryFails|TestGISTR001GroupInboxStoreDoesNotRecoverNonTransientRelayError|TestGISTR001TransientClassifierCoversRelaySetupAndIOFailures'
```

Existing focused regression gate:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGI002GroupInboxStoreSendsGroupStoreRequestShape|TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess|TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail|TestGI007GroupInboxStoreReturnsRelayNonOKError|TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream|TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF'
```

Diff hygiene:

```bash
git diff --check -- go-mknoon/node/group_inbox.go go-mknoon/node/group_inbox_test.go Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-GISTR-001-plan.md
```

Optional package confidence if focused gates are green and time permits:

```bash
cd go-mknoon && go test ./node -count=1 -run 'GroupInbox'
```

## Scope Guard

Do not edit Flutter/Dart files, bridge APIs, relay-server code, database helpers, UI, generated native bindings, pubsub publish semantics, group recipient derivation policy, push notification payloads, or external relay configuration. Do not introduce unbounded retry loops or sleep-based timing. Do not weaken stream cleanup or mask relay application errors as transient transport failures.

## Known-Failure Interpretation

Existing dirty-worktree failures outside the named focused gates should be recorded but must not expand this session. If a focused gate fails because of unrelated pre-existing edits, capture the exact failing test and stack, then stop for closure classification instead of broadening product scope.

## Done Criteria

- New GISTR-001 tests fail before production changes or are documented as already covered by current dirty worktree behavior.
- Production changes are limited to `go-mknoon/node/group_inbox.go`.
- Test changes are limited to `go-mknoon/node/group_inbox_test.go`.
- Focused RED/GREEN and existing regression gates pass, or any failure is classified with exact evidence.
- `git diff --check` passes for touched files.
- Breakdown ledger records `GISTR-001` as `accepted` only after execution and closure evidence exists.

## Execution Progress

- RED: `cd go-mknoon && go test ./node -run 'TestGroupInboxStoreRetriesAfterTransientRelayEOF|TestIsTransientGroupInboxRelayStreamErrorCoversStoreAndDialFailures' -count=1` failed before production changes because `GroupInboxStore` returned after the transient EOF and the classifier missed connect/open/write/deadline cases.
- GREEN: implemented `groupInboxStore` plus `groupInboxStoreOnce` in `go-mknoon/node/group_inbox.go`, preserving validation/recipient derivation before retry and re-reading the host inside each store attempt.
- GREEN: broadened `isTransientGroupInboxRelayStreamError` for connect/open stream/dial/no-address/write/read EOF/reset/timeout/deadline failures while leaving `group inbox store failed: ...` application errors non-transient.
- REFACTOR: ran `gofmt` on `node/group_inbox.go` and `node/group_inbox_test.go`.
- Verification passed:
  - `cd go-mknoon && go test ./node -count=1 -run 'TestGISTR001GroupInboxStoreRetriesAfterTransientRelayEOF|TestGISTR001GroupInboxStoreDoesNotRetryWhenRecoveryFails|TestGISTR001GroupInboxStoreDoesNotRecoverNonTransientRelayError|TestGISTR001GroupInboxStoreUsesNextRelayBeforeRecovery|TestGISTR001TransientClassifierCoversRelaySetupAndIOFailures'`
  - `cd go-mknoon && go test ./node -count=1 -run 'TestGI002GroupInboxStoreSendsGroupStoreRequestShape|TestGI005GroupInboxStoreRetriesRelaysInOrderAndStopsOnSuccess|TestGI006GroupInboxStoreReturnsErrorAfterAllRelaysFail|TestGI007GroupInboxStoreReturnsRelayNonOKError|TestGI008GroupInboxStoreResetsFailedStreamAndClosesSuccessfulStream|TestGroupInboxRetrieveWithCursorResult_RetriesAfterTransientRelayEOF'`
  - `git diff --check -- go-mknoon/node/group_inbox.go go-mknoon/node/group_inbox_test.go Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-inbox-store-transient-recovery-session-GISTR-001-plan.md`
- Optional `cd go-mknoon && go test ./node -count=1 -run 'GroupInbox'` was stopped after more than one minute with no output; it was not required closure evidence for this host-only session.

## Final Verdict

Accepted. The scoped bug is fixed with focused TDD coverage and no blocker remains for this session.
