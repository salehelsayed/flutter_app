# Phase 7 Resilience Rollout

This runbook covers the Phase 7 rollout toggles, relay capacity limits,
device-failover commands, and rollback path for the libp2p resilience work.

## Enablement

Flutter and bridge rollout flags are injected with `--dart-define` and sent to
`node:start` automatically.

Example:

```bash
flutter test integration_test/multi_relay_failover_test.dart -d <device> \
  --dart-define=MKNOON_RELAY_ADDRESSES=/dns4/relay-a.example/udp/4002/quic-v1/p2p/<peerA>,/dns4/relay-b.example/udp/4002/quic-v1/p2p/<peerB> \
  --dart-define=MKNOON_ENABLE_SHARED_RELAY_BACKEND=true \
  --dart-define=MKNOON_ENABLE_MULTI_RELAY_ROUTING=true \
  --dart-define=MKNOON_ENABLE_RESERVATION_AWARE_HEALTH=true \
  --dart-define=MKNOON_ENABLE_IN_PLACE_RELAY_RECOVERY=true \
  --dart-define=MKNOON_ENABLE_RESUME_GROUP_RECOVERY=true
```

Notes:

- `MKNOON_RELAY_ADDRESSES` must list at least two relay peers for the Phase 7
  device suites. The default WSS + QUIC pair only targets one relay peer and is
  not sufficient for multi-relay failover validation.
- If `MKNOON_RELAY_ADDRESSES` is unset, the app keeps the current production
  default of the existing WSS + QUIC relay addresses.

## Relay Server Limits

The relay server no longer runs with infinite circuit-relay limits. Set these
before starting `go-relay-server`:

```bash
export RELAY_MAX_RESERVATIONS=2048
export RELAY_MAX_CONNECTIONS_PER_PEER=16
export RELAY_MAX_INBOX_MESSAGES_PER_PEER=100
export RELAY_MAX_GROUP_INBOX_MESSAGES=500
```

Shared backend rollout:

```bash
export RELAY_BACKEND=redis
export REDIS_URL=redis://<host>:6379
export REDIS_PREFIX=relay:
```

## Verification

Server and native verification:

```bash
cd go-relay-server && go test ./...
cd go-mknoon && go test ./node ./bridge ./cmd/testpeer
cd go-mknoon && go test -tags integration ./integration
flutter test test/core/resilience/network_failover_test.dart
```

Named Phase 7 device or simulator entry points:

```bash
flutter test integration_test/multi_relay_failover_test.dart -d <device> \
  --dart-define=MKNOON_RELAY_ADDRESSES=<relayA>,<relayB>

flutter test integration_test/relay_chaos_soak_test.dart -d <device> \
  --dart-define=MKNOON_RELAY_ADDRESSES=<relayA>,<relayB>
```

The named wrappers reuse the existing real-stack transport, group-recovery, and
soak harnesses. Run them with external relay orchestration that kills relay A,
brings relay B back, and exercises background or resume churn.

## Rollback

Disable specific resilience slices without reverting code:

```bash
--dart-define=MKNOON_ENABLE_MULTI_RELAY_ROUTING=false
--dart-define=MKNOON_ENABLE_RESERVATION_AWARE_HEALTH=false
--dart-define=MKNOON_ENABLE_IN_PLACE_RELAY_RECOVERY=false
--dart-define=MKNOON_ENABLE_RESUME_GROUP_RECOVERY=false
```

Operational rollback order:

1. Disable `MKNOON_ENABLE_RESERVATION_AWARE_HEALTH` if relay-session telemetry
   is noisy or misleading during rollout.
2. Disable `MKNOON_ENABLE_IN_PLACE_RELAY_RECOVERY` to force the older
   restart-first recovery path.
3. Disable `MKNOON_ENABLE_MULTI_RELAY_ROUTING` to collapse back to the primary
   relay only.
4. Switch `RELAY_BACKEND=memory` if the shared Redis backend must be removed.
5. Lower relay caps only after stabilizing traffic; do not restore infinite
   limits.
