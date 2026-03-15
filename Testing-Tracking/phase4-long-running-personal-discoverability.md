# Phase 4 Long-Running Personal Discoverability

This runbook records the regression gates for
`Network-Arch/Long-Running-Personal-Discoverability-TDD-Plan.md` Phase 4.

## Automated Gates

Go coverage for the personal rendezvous refresh and recovery paths:

```bash
cd go-mknoon
go test ./node -run 'PersonalRendezvousRefresh|RefreshRelaySession|ReconnectRelays_WatchdogRestart'
go test -tags integration ./integration -run 'PersonalNamespaceRefresh|PersonalNamespaceRecovery'
```

Flutter coverage for the long-running symptom layer:

```bash
flutter test test/core/services/p2p_service_fault_injection_test.dart
flutter test test/core/lifecycle/background_reconnect_smoke_test.dart
dart run integration_test/scripts/run_transport_e2e.dart -d <device> --phase4-only
```

The focused device or simulator gate above is the repo-local real-stack proof
for the Flutter symptom layer. It deliberately reproduces stale discoverability by
unregistering the CLI peer's personal namespace while keeping both peers online,
then requires Flutter to:

- observe a real discoverability miss before the send
- run `handleAppResumed()` on the live stack instead of only a direct health ping
- persist the recovered send with a non-`inbox` transport
- deliver that recovered send to the CLI peer without restarting either side

Expected evidence from the real-stack gate:

- the Flutter app returns to `online` after resume recovery
- the stale discoverability miss is reproduced before the recovered send
- the recovered send stays on a live-path transport instead of dropping
  straight to inbox
- the CLI peer receives that recovered send while both peers stay up
- no node or simulator restart is required between the degraded interval and
  the recovered live send

For a longer mixed-traffic confirmation after the focused Phase 4 gate passes:

```bash
dart run integration_test/scripts/run_soak_e2e.dart -d <device> --duration 5m
```

## Supplemental Manual TTL Scenario

The repo-local device gate above reproduces the user-visible symptom in minutes.
For exact TTL-clock validation, keep the Go short-TTL tests as the primary
automated proof and use this manual scenario only as supplemental confidence:

Suggested manual scenario:

1. Start two simulators, or one simulator plus the CLI peer, against a
   short-TTL test relay.
2. Leave both peers idle past the shortened personal registration TTL.
3. Bring one app to foreground and send in both directions without restarting
   either side.
4. Capture transport evidence from the app logs or persisted messages.

Expected result:

- the first post-idle interactive send uses the live relay path again
- persisted outgoing rows show a non-`inbox` live-path transport for the
  recovered send
- `transport=inbox` appears only when the live send actually fails
- restarting the app or simulator is not required to regain live delivery
