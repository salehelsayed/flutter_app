# Session A Plan: Relay Media Durability And Failover

Status: accepted_with_explicit_follow_up
Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
Breakdown: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`
Session id: A

## Planning Progress

- 2026-06-11 18:15 - Controller local plan fallback wrote the doc-scoped execution contract after the spawned planner produced no intended plan artifact. Evidence source: Session A breakdown and source plan regression list. Decision: execution-safe with no device/relay proof profile; final simulator proof belongs to Session F.

## Execution Progress

- 2026-06-11 15:53 CEST - Phase: owner file inspection started. Files inspected/touched: plan progress only so far. Command/log: starting `sed`/`rg` reads and scoped `git diff -- <Session A owner paths>`. Decision/blocker: pending inspection of pre-existing dirty changes in `go-mknoon/node/media.go`, `go-mknoon/node/media_test.go`, and `go-mknoon/integration/media_test.go`. Next action: map current media store and node download behavior before adding failing-first regressions.
- 2026-06-11 15:53 CEST - Phase: Executor contract extraction started. Files inspected: Session A plan, session breakdown, pre-execution dirty snapshot, and owner-file status. Command/log: `graphify query "Session A direct media relay persistence atomic replacement retention error strings node retry not found not authorized" --budget 1800`; `sed` reads for plan/breakdown/snapshot; `git status --short -- <Session A owner paths>`. Decision/blocker: pending Executor-scoped extraction; graph query was low-signal, plan remains source of truth. Next action: extract exact Session A implementation/test/gate contract before owner-file inspection.
- 2026-06-11 15:53 CEST - Phase: Executor contract extracted. Files inspected: Session A plan `Real Scope`, `Regression Tests To Add First`, `Exact Tests And Gates To Run`, `Done Criteria`, and `Scope Guard`; session breakdown Session A row. Command/log: required focused tests are `go test ./go-relay-server`, `go test ./go-mknoon/node`, `go test -tags=integration ./go-mknoon/integration`, followed by `./scripts/run_test_gates.sh transport` if feasible. Decision/blocker: scope is relay media durability/failover only; do not touch Sessions B-F, Flutter receiver/UI, group/post media, or generic session docs. Next action: inspect current owner-file contents and existing dirty deltas before adding regressions.
- 2026-06-11 16:00 CEST - Phase: local execution fallback started. Files inspected/touched: this plan. Command/log: spawned execution child and nested Executor no-progressed after bounded wait with no code/test/gate evidence beyond plan heartbeats, then were terminated by the parent controller. Decision/blocker: no product blocker yet; fallback is current-session-only and must still add regressions first, run focused Go tests, and perform QA. Next action: inspect Session A owner files and pre-existing dirty deltas before editing.
- 2026-06-11 16:08 CEST - Phase: local Executor implementation completed. Files inspected/touched: `go-relay-server/media.go`, `go-relay-server/media_test.go`, `go-mknoon/node/media.go`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`. Command/log: `gofmt -w` on touched Go files. Decision/blocker: relay sidecars, atomic upload replacement, direct media count alignment, node retry-on-`not found`, terminal `not authorized`, and required regressions are present. Next action: run focused Go tests from the plan.
- 2026-06-11 16:12 CEST - Phase: focused tests run. Files inspected/touched: no new edits. Command/log: workspace-root `go test ./go-relay-server` failed because no root Go module; module-correct `cd go-relay-server && go test ./...` passed in 13.022s; `cd go-mknoon && go test -tags=integration ./integration` passed in 94.084s; `cd go-mknoon && go test ./node -run 'Test(Media|PL013|PL014|IdleTimeout)'` passed in 7.123s. `cd go-mknoon && go test ./node -timeout 2m` failed by timeout; JSON rerun with `-timeout 45s` shows timeout while running `TestRefreshRelaySession_PreservesPubSubMaps`, outside Session A media owner tests. Decision/blocker: Session A media slices pass; broad node package has unrelated timeout evidence at `/tmp/mknoon_session_A_node_timeout.json`. Next action: run required `./scripts/run_test_gates.sh transport` gate.
- 2026-06-11 16:45 CEST - Phase: named transport gate run. Files inspected/touched: no new edits. Command/log: `./scripts/run_test_gates.sh transport` first failed because multiple devices were connected and no device was selected; rerun with `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` exited 0. Evidence included `wifi_relay_fallback_smoke_test.dart`, `transport_e2e_test.dart`, and `media_stable_id_smoke_test.dart` passing; `background_reconnect_test.dart` was skipped by the gate. Decision/blocker: required Session A named gate evidence is sufficient with explicit device selection. Next action: complete local QA and close Session A.
- 2026-06-11 18:49 CEST - Phase: local QA verdict. Files inspected/touched: Session A owner diff and this plan. Command/log: scoped `git diff -- go-relay-server/media.go go-relay-server/media_test.go go-mknoon/node/media.go go-mknoon/node/media_test.go go-mknoon/integration/media_test.go`; test evidence above. Decision/blocker: accepted_with_explicit_follow_up. Session A closure bar is met for relay restart rebuild, unauthorized denial after rebuild, incomplete same-ID replacement preservation, direct count-cap alignment, `not found`/`not authorized` contracts, and later-relay retry on `not found`. Follow-up: broad `cd go-mknoon && go test ./node` still times out in `TestRefreshRelaySession_PreservesPubSubMaps`, outside this session's media owner tests. Next action: update the breakdown ledger and proceed to Session B.
- 2026-06-11 15:51 CEST - Phase: contract extraction started. Files inspected: pre-execution dirty snapshot `/tmp/mknoon_session_A_pre_execution_status.txt`, this Session A plan, session breakdown, and `Test-Flight-Improv/test-gate-definitions.md`. Command/log: `git status --short`, `sed`/`rg` reads, graphify query for Session A relay/media transport context. Decision/blocker: pending contract extraction; existing dirty owner files must be verified and extended, not reverted. Next action: extract exact Session A scope, tests, gates, done criteria, and scope guard before spawning Executor.
- 2026-06-11 15:51 CEST - Phase: contract extracted. Files inspected: this Session A plan lines for Real Scope, Regression Tests, Exact Tests And Gates, Known-Failure Interpretation, Done Criteria, Scope Guard; `Test-Flight-Improv/test-gate-definitions.md` Startup / Transport Gate. Command/log: `go test ./go-relay-server`, `go test ./go-mknoon/node`, `go test -tags=integration ./go-mknoon/integration`, and `./scripts/run_test_gates.sh transport` identified as required evidence. Decision/blocker: execution contract is safe and bounded to `go-relay-server/media.go`, `go-relay-server/main.go`, `go-relay-server/server_bootstrap.go`, `go-mknoon/node/media.go`, and Session A Go tests unless a scoped adjacent doc/test classification change is needed. Next action: spawn isolated Executor with model `gpt-5.5` and reasoning `xhigh`.
- 2026-06-11 15:51 CEST - Phase: Executor spawn starting. Files inspected/touched: this plan only. Command/log: nested Executor worker requested with Session A code-entry files and required tests/gates. Decision/blocker: no blocker; spawned-agent isolation available. Next action: wait for Executor evidence, then spawn QA Reviewer.
- 2026-06-11 15:52 CEST - Phase: Executor running. Files inspected/touched: this plan. Command/log: Executor agent `019eb6f4-78fc-78c3-8d24-bc98260f226c` (`Sagan`) spawned with model `gpt-5.5`, reasoning `xhigh`. Decision/blocker: pending Executor result. Next action: bounded wait for code/test/doc delta and exact test evidence.

## Closure Progress

- 2026-06-11 19:07 CEST - Completion Auditor: verified the landed Session A diff against the closure bar. Closed items: relay sidecar metadata reload, unauthorized denial after reload, incomplete same-ID replacement preservation, count-cap alignment with `maxMessagesPerPeer`, relay `not found`/`not authorized` contract coverage, and client retry on later relay after `not found` while keeping `not authorized` terminal. Evidence: `cd go-relay-server && go test ./...` passed, `cd go-mknoon && go test -tags=integration ./integration` passed, and `cd go-mknoon && go test ./node -run 'Test(Media|PL013|PL014|IdleTimeout)'` passed.
- 2026-06-11 19:07 CEST - Closure Writer: classified Session A as `accepted_with_explicit_follow_up`. The direct media custody and failover contract is accepted; Session B may proceed. Follow-ups are explicit and non-blocking for Session A: broad `cd go-mknoon && go test ./node` times out in `TestRefreshRelaySession_PreservesPubSubMaps`, and the spawned closure child hung while compiling adjacent `go-mknoon/bridge` and `go-mknoon/cmd/testpeer` callers after confirming the targeted Go suites.
- 2026-06-11 19:07 CEST - Closure Reviewer: checked for overclaiming. Final simulator proof, Flutter receiver recovery, local-WiFi fallback, direct retry/replay repair, thumbnail display policy, stable matrix updates, and source-report disposition remain deferred to Sessions B-F. No generic `Test-Flight-Improv/session-*.md` artifact was created.

## Real Scope

Implement only the relay/Go transport custody contract for direct 1:1 media:

- Persist relay media metadata beside uploaded blobs and rebuild in-memory media indexes after relay restart.
- Write same-ID media replacements through staging and atomic rename so incomplete replacements do not destroy the existing blob or metadata.
- Keep direct media count retention from undercutting the direct inbox retention window.
- Preserve media error contracts: media miss stays `not found`; authorization failure stays `not authorized`.
- Update Go client media download behavior to try later eligible relays on `not found` while keeping `not authorized` terminal.

Do not change Flutter receiver cleanup, local-WiFi fallback, retry UI, duplicate replay, thumbnail behavior, simulator scenarios, group media, public post media, encryption protocol, or broad relay storage policy outside the direct media custody contract.

## Closure Bar

Session A is done when:

- Relay media uploaded before a process restart remains downloadable by the authorized recipient after `NewMediaStore` rebuilds from disk.
- Unauthorized peers still cannot download rebuilt media.
- A same-ID upload that fails before writing all bytes leaves the existing blob and metadata downloadable.
- Direct media count pruning cannot evict media earlier than the direct inbox envelope count window, excluding existing TTL and byte-cap residuals.
- Relay tests pin the `not found` and `not authorized` media error strings.
- Go node media download retries later relays on media `not found` and does not retry on `not authorized`.
- Focused Go tests for relay, node, and integration media pass or any pre-existing unrelated failure is documented with evidence.

## Source Of Truth

- Active plan: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Session split and plan path: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`.
- Root-cause report: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Gate definitions: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`.
- Current code and tests win over stale prose if behavior has already moved.

## Session Classification

`implementation-ready`

## Exact Problem Statement

The relay can preserve direct inbox envelopes while losing media lookup metadata across restart, making a delivered 1:1 media message permanently unavailable. The Go client can also stop after the first reachable relay returns media `not found`, even when another eligible relay can serve the blob. Session A fixes those relay/node causes without touching Flutter receiver or UI recovery.

## Files And Repos To Inspect Next

Production:

- `go-relay-server/media.go`
- `go-relay-server/main.go`
- `go-relay-server/server_bootstrap.go`
- `go-mknoon/node/media.go`

Tests:

- `go-relay-server/media_test.go`
- `go-mknoon/node/media_test.go`
- `go-mknoon/integration/media_test.go`

Docs only if test classification changes:

- `Test-Flight-Improv/test-gate-definitions.md`

## Existing Tests Covering This Area

- `go-relay-server/media_test.go` already covers upload/download, post-delete `not found`, unauthorized `not authorized`, peer pruning, and byte-cap pruning, but does not prove restart rebuild, same-ID replacement safety, direct count cap alignment, or corrupt metadata tolerance.
- `go-mknoon/node/media_test.go` already covers upload/download progress and partial output cleanup, but does not prove later-relay retry after application-level media miss.
- `go-mknoon/integration/media_test.go` covers direct relay media paths and should stay green unless expected post-delete behavior is intentionally updated by the implementation.

## Regression Tests To Add First

Add failing regressions before implementation:

- `TestMediaStoreSurvivesRestart` in `go-relay-server/media_test.go`.
- `TestMediaUploadSameIDIncompleteReplacementKeepsExistingBlob` in `go-relay-server/media_test.go`.
- `TestDirectMediaCountCapDoesNotUndercutInboxRetention` in `go-relay-server/media_test.go`.
- Relay error-contract assertions for exact `not found` and `not authorized` strings.
- `TestMediaDownloadTriesNextRelayOnNotFound` in `go-mknoon/node/media_test.go`, with a companion `not authorized` terminal assertion.
- Add corrupt-sidecar tolerance coverage if the implementation introduces sidecar metadata.

## Step-By-Step Implementation Plan

1. Record the pre-execution dirty worktree with `git status --short`; do not revert unrelated user or prior-session changes.
2. Add the Session A failing relay tests and node failover tests first.
3. Implement relay sidecar metadata in `go-relay-server/media.go` with temp-file write, fsync where practical, and rename into place after successful blob upload.
4. Rebuild media indexes in `NewMediaStore` from valid sidecars and ignore corrupt sidecars without preventing startup or unrelated media service.
5. Change same-ID upload handling so replacement blob bytes and metadata are committed only after the full replacement upload succeeds.
6. Align direct media count retention with the direct inbox envelope retention constant while preserving TTL and byte-cap pruning as accepted storage-policy residuals.
7. Refactor `go-mknoon/node/media.go` media download response classification so later relays are tried on `not found` and transient transport failure, while `not authorized` and local validation failure remain terminal.
8. Run focused Go tests, then the named transport gate if the focused tests pass.
9. Update `Test-Flight-Improv/test-gate-definitions.md` only if new tests need classification changes; otherwise defer stable matrix/closure wording to Session F.

## Risks And Edge Cases

- Restart rebuild must not grant access to peers that were not authorized before restart.
- Same-ID replacement must not expose partial replacement bytes or lose the old blob when the upload stream fails.
- Corrupt sidecars must not crash relay startup or block valid media.
- Count-cap alignment must not disable TTL or byte-cap eviction.
- Client failover must not mask authorization errors by trying another relay.
- Partial output cleanup in `go-mknoon/node/media.go` must continue to remove incomplete local downloads.

## Exact Tests And Gates To Run

Focused tests:

```bash
go test ./go-relay-server
go test ./go-mknoon/node
go test -tags=integration ./go-mknoon/integration
```

Named gate:

```bash
./scripts/run_test_gates.sh transport
```

Session A does not require a Flutter device/simulator proof profile. Device-backed 1:1 simulator acceptance is owned by Session F.

## Known-Failure Interpretation

- If a focused Go package fails outside files touched by Session A, record the exact failing test and evidence before deciding whether it blocks this session.
- Do not classify existing dirty-worktree changes outside Session A owner files as Session A regressions unless the focused tests prove they affect relay media custody or Go media download failover.
- If `go test -tags=integration ./go-mknoon/integration` needs local relay/network setup that is unavailable, record the fixture blocker and keep host unit tests as partial evidence only.

## Done Criteria

- All required failing-first regressions are present in Session A test files.
- Implementation is limited to Session A owner files unless closure explicitly accepts a scoped adjacent change.
- Focused Go relay/node/integration tests pass or any blocker is recorded with exact output and owner classification.
- `./scripts/run_test_gates.sh transport` passes or is blocked by an exact pre-existing/fixture issue.
- The session execution result states whether Session B can proceed.

## Scope Guard

Do not implement Flutter receiver orphan adoption, local-WiFi fallback, direct retry UI, duplicate replay repair, video thumbnail fallback, simulator scenario discovery, group media behavior, post media behavior, or encryption/protocol redesign in this session. Do not create generic `Test-Flight-Improv/session-*.md` artifacts.

## Accepted Differences / Intentionally Out Of Scope

- Legacy relay blobs without sidecar metadata after restart may remain an accepted rollout difference unless the implementation can add a narrow safe migration during Session A.
- TTL and byte-cap eviction remain storage-policy residuals; only direct count retention must not undercut the direct inbox count window.
- Final matrix and 1:1 closure docs are deferred to Session F unless Session A adds or reclassifies a gate/test that requires immediate inventory updates.

## Dependency Impact

Session B may proceed after Session A reaches an accepted execution and closure result. If Session A blocks on relay media durability or client failover, later Flutter receiver and retry sessions can still be planned, but final Session F acceptance remains prerequisite-blocked until the relay/media custody blocker is resolved or truthfully recorded.

## QA / Reviewer Expectations

QA must compare the post-execution diff against the pre-execution dirty snapshot and classify any changes outside Session A owner files as intentional, unrelated pre-existing state, or blocking scope drift. QA must verify test output on disk or in the execution notes rather than relying on implementation claims alone.
