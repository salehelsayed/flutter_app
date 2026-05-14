# GP-012 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-012 | Rendezvous discovery handles invalid peer IDs safely | P1 | Covered | needs_tests_only |

## Gap Classification

GP-012 is repo-owned and runnable. Adjacent GA-022 coverage proves malformed
config peers do not crash discovery, but the source row remains `Open` and
lacks exact GP-012 evidence for the combined rendezvous/config contract:
invalid entries are skipped and a valid member is still attempted.

## Implementation Plan

1. Add an exact GP-012 Go regression in `go-mknoon/node/pubsub_test.go`.
2. Seed the group config with one valid member plus invalid legacy and device
   transport peer IDs.
3. Make rendezvous return one invalid `peer.ID` and one valid member.
4. Run `discoverAndConnectGroupPeers` and verify discovery counters, skipped
   invalid entries, no peerstore import for the invalid ID, and direct attempt
   of the valid member.
5. Run focused, adjacent, selected race, named groups, and diff hygiene gates.

## Acceptance Bar

- GP-012 source matrix row is `Covered`.
- Exact evidence proves malformed config and invalid rendezvous peer IDs are
  skipped without panic.
- Exact evidence proves a valid discovered member is still attempted.
- No production behavior change is required unless the exact test exposes a
  repo-owned implementation gap.

## Execution Evidence

- Added `go-mknoon/node/pubsub_test.go::TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember`.
- The test seeds invalid config peer IDs in both the legacy member peer field
  and active-device `TransportPeerId`, returns one invalid rendezvous peer plus
  one valid member from rendezvous, then runs `discoverAndConnectGroupPeers`.
- The test proves discovery completes without panic, `discover_result` reports
  `totalFound == 2`, `newPeers == 1`, `ignoredNonMembers == 1`, and
  `ignoredInvalidConfigPeers == 2`, the valid member is connected, and the
  invalid discovered peer is not imported into the peerstore.
- `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- `cd go-mknoon && go test ./node -run 'TestGP012RendezvousDiscoverySkipsInvalidPeerIDsAndDialsValidMember' -count=1` passed (`ok node 0.583s`).
- `cd go-mknoon && go test ./node -run 'TestGP012|TestGA022|TestGP011|filterDiscovered|discoverAndConnectGroupPeers|GroupDiscovery' -count=1` passed (`ok node 3.938s`).
- `cd go-mknoon && go test ./node ./internal ./crypto -run 'TestGP012|TestGA022|TestGP011|filterDiscovered|discoverAndConnectGroupPeers|GroupDiscovery' -count=1` passed (`ok node 3.620s`, `ok internal 1.193s`, `ok crypto 0.934s`).
- `cd go-mknoon && go test -race ./node -run 'TestGP012|TestGA022|TestGP011|filterDiscovered|GroupDiscovery' -count=1` passed (`ok node 3.546s`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-012 is now `Covered` by exact row-owned native proof. No
production code change was required because current discovery filtering already
skips invalid config and rendezvous peer IDs safely once exact coverage exists.
Residual-only: none for GP-012. Continue from GI-034, the next unresolved row
in ordered ledger order.
