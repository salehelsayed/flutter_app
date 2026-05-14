# GR-014 Session Plan: Late Relay Readiness Resumes Group Discovery

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GR-014`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 06:07:00 CEST | Controller | Source matrix GR-014 row; breakdown row 156; `go-mknoon/node/pubsub.go::groupPeerDiscoveryLoop`, `runGroupDiscoveryCycle`, `dialKnownGroupMembers`, `discoverAndConnectGroupPeers`; existing group discovery, relay recovery, and app resume tests | The source row was `Open` and the breakdown marked GR-014 `needs_repo_evidence` / `evidence-gated`. Production already blocks the group discovery loop on `relayReady`, performs only direct-known-address dialing before readiness, then runs known-member relay-capable discovery immediately after readiness. Existing tests covered direct-before-ready, warm retry, and relay recovery separately, but no exact row-owned proof held `relayReady` open, closed it later, and proved relay-assisted dialing plus live delivery. | Add exact row-owned Go node proof with deterministic fake relay/rendezvous hooks; run focused, adjacent discovery, relay recovery, race, app fake-network, lifecycle, gofmt, and diff hygiene gates. |

## Scope

GR-014 owns native group peer discovery behavior when a group joins while the relay path is not yet ready. The closure bar is that relay-assisted group discovery does not run early, resumes after `relayReady` closes later, and restores live group delivery.

Out of scope: in-place relay refresh topic preservation, watchdog/full restart rejoin, pending retry preservation, and real three-device relay-lab proof. Those are separate GR/GE rows.

## Execution Contract

1. Add a row-named Go test in `go-mknoon/node/pubsub_delivery_test.go`.
2. Join a two-member private group while node A's `relayReady` remains open/unclosed.
3. Prove relay-assisted dialing, rendezvous registration, and rendezvous discovery do not run before readiness.
4. Close `relayReady` later and prove the discovery loop resumes, calls the relay dial path for the known member, runs discovery, and forms a live topic peer.
5. Publish after readiness and prove node B receives the exact group message.
6. Run focused GR-014, adjacent discovery/relay recovery/race selectors, app fake-network/lifecycle selectors, gofmt, and `git diff --check`.
7. Update the source matrix, breakdown ledgers, and this plan with concrete evidence before acceptance.

## Required Gates

| Gate | Command |
|---|---|
| Focused Go proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR014'` from `go-mknoon` |
| Adjacent discovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR014|GroupPeerDiscoveryLoop|GroupDiscovery|KnownGroupMemberDial|GroupDiscoveryCycle'` from `go-mknoon` |
| Adjacent relay recovery proof | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` from `go-mknoon` |
| Race selector | `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR014|GroupPeerDiscoveryLoop|GroupDiscovery|KnownGroupMemberDial'` from `go-mknoon` |
| Fake-network adjacent proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'group discovery remains live across ttl refresh window without manual rejoin'` |
| App recovery adjacent proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` |
| Lifecycle adjacent proof | `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` |
| Hygiene | `gofmt -l go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree already contained prior rollout edits and accepted GR-004 through GR-008 changes. GR-014 scope is limited to `go-mknoon/node/pubsub_delivery_test.go`, this plan, the source matrix row GR-014, and breakdown closure documentation unless focused gates expose a production defect.

## Execution Evidence

- Added `go-mknoon/node/pubsub_delivery_test.go::TestGR014GroupDiscoveryResumesAfterRelayReadyClosesLate`.
- No production code changed for GR-014. Existing `groupPeerDiscoveryLoop` already performs direct-only pre-relay work, waits on `relayReady`, then runs known-member relay-capable discovery and rendezvous discovery.
- The test joins node B and node A to a private group while node A's `relayReady` channel remains open.
- Before closing `relayReady`, it proves the relay dial hook, rendezvous register hook, and rendezvous discover hook were not called.
- After closing `relayReady`, it proves node A emits `group:discovery` step `known_member_dial_success` for node B with `path == relay` and `attemptedDirect == false`, proving the relay-assisted path resumed without preseeded direct addresses.
- The same test proves rendezvous discovery resumed, `PublishGroupMessage` returns the explicit id `gr014-late-relay-ready-message` with at least one live topic peer, and node B receives the exact message text.

## Verification

- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR014'` passed (`ok github.com/mknoon/go-mknoon/node 0.746s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'TestGR014|GroupPeerDiscoveryLoop|GroupDiscovery|KnownGroupMemberDial|GroupDiscoveryCycle'` passed (`ok github.com/mknoon/go-mknoon/node 13.502s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test ./node -run 'RefreshRelaySession|ReconnectRelays|Watchdog|GroupRecovery|RelaySession'` passed (`ok github.com/mknoon/go-mknoon/node 21.383s`).
- `GOCACHE=/private/tmp/codex-go-build-cache GOTMPDIR=/private/tmp/codex-go-tmp go test -race ./node -run 'TestGR014|GroupPeerDiscoveryLoop|GroupDiscovery|KnownGroupMemberDial'` passed (`ok github.com/mknoon/go-mknoon/node 13.228s`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'group discovery remains live across ttl refresh window without manual rejoin'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'watchdog restart rejoins topics and resumes live delivery'` passed (`+1`).
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'rejoins and acknowledges when Go signals group recovery'` passed (`+1`).
- `gofmt -l go-mknoon/node/pubsub_delivery_test.go` passed with no output.
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GR-014 is `Covered` by row-owned Go node evidence proving group discovery waits while `relayReady` is open, resumes relay-assisted known-member dialing and rendezvous discovery after late readiness, and restores live group message delivery. Residual-only: no production code changed; external real-device relay E2E remains covered by later GE rows rather than this row. GR-015 is the next unresolved P0 session in ledger order; no final program verdict was written.
