# FDC-10 — Durable inbox (Redis) + relay pool — OPS RUNBOOK

Status: ops-gated. The from-repo code surface (durability-visibility + default pool) is
implemented and host-green. The steps below are the **deploy/provisioning actions** that make
durability actually live. The live relay env (`.env`/secrets) is gitignored, so the live effect
is **unverifiable from-repo** — these steps + the `relay_backend_durable` gauge are how ops
confirms it.

> **Ordering gate (proposal §9):** FDC-10 durability MUST be live in production **before**
> FDC-03 (P0-2, generalized concurrent inbox / inbox-write-volume increase) ramps to production
> traffic. Raising inbox volume into a restart-losable in-memory store widens the blast radius of
> a relay bounce. The FDC-03 *code* may land/host-test first; only its production volume ramp is
> gated on this runbook being executed.

---

## 0. What changed in code (from-repo, already merged on this branch)

- **`go-relay-server`**
  - `backendConfig.IsDurable()` — `true` only for the Redis backend.
  - `backendStartupSummary(cfg)` — boot log line `backend=<kind> durable=<bool> prefix=<prefix>`
    (logged by `main.go` as `Control-plane: ...`).
  - `relay_backend_durable` Prometheus gauge (`metrics.go`) set at boot via
    `setBackendDurabilityGauge(backendCfg)` — `1` durable (redis), `0` in-memory.
  - **No code default change**: `RELAY_BACKEND` unset still selects the in-memory backend
    (local-dev/test default — INV-1). Durability is an **env**, never a code-default flip.
- **`go-mknoon/node`**
  - `DefaultRelayAddresses()` returns the default relay peer over **both WSS + QUIC** (one peer,
    two transports). Consumed at the node nil-default seam, the recovery-warm fallback, and
    `buildRelaySelector`. This removes the single-*transport* SPOF today, before relay #2 exists.

Nothing below requires a client rebuild **for transport redundancy** — that ships in the default
pool already. A client rebuild is only needed to add a **second relay peer** (step 5).

---

## 1. Provision Redis (custody SPOF — harden it)

1. Stand up a **managed Redis** (or a hardened self-managed instance) reachable from every relay
   front-end. Prefer a managed offering with automated failover.
2. Enable **persistence** (AOF `appendonly yes`, or RDB snapshots, ideally both). Redis is now the
   single custody store for inbox + push tokens + rendezvous + group inbox; an unpersisted Redis
   restart re-introduces exactly the data-loss this plan removes.
3. Restrict network access (VPC/security-group) to the relay front-ends only; require AUTH/TLS.

> **Known SPOF (flagged):** the front-end pool does NOT remove the Redis SPOF. Redis HA /
> clustering / persistence-tuning is an ops-hardening follow-up, out of FDC-10's code scope.

---

## 2. Set the backend env on EVERY relay front-end

On each front-end box (identical values for `REDIS_URL` + `REDIS_PREFIX` so they share custody):

```
RELAY_BACKEND=redis
REDIS_URL=redis://<user>:<pass>@<host>:6379/0      # or rediss:// for TLS
REDIS_PREFIX=relay:prod:                           # PER-ENV prefix — see below
```

- `REDIS_PREFIX` is normalized to end in `:` (`loadBackendConfigFromEnv`). **Use a distinct prefix
  per environment** (`relay:prod:`, `relay:staging:`) to avoid cross-env key collisions in a
  shared Redis. Same env ⇒ same prefix on all front-ends.
- A redis backend with an empty `REDIS_URL` **fails loudly** at boot
  (`REDIS_URL is required when RELAY_BACKEND=redis`) — locked by
  `TestNewControlPlaneStores_RedisRequiresURL`. It will NOT silently fall back to memory.
- **Mixed pool hazard:** one redis front-end + one memory front-end splits custody. Ensure *every*
  front-end has `RELAY_BACKEND=redis` and the SAME `REDIS_URL`/prefix.

---

## 3. Run ≥2 stateless front-ends sharing the one Redis

Run two (or more) relay-server processes/instances, all pointed at the same Redis. Because the
backend is shared, a deposit on front-end A is retrievable from front-end B exactly once
(deposit-once / retrieve-from-any) — proven host-side by
`failover_test.go::TestTwoRelayServers_SharedInboxBackend` and across processes by
`redis_failover_integration_test.go::TestRedisControlPlaneSharedAcrossProcesses`. A single
front-end bounce therefore does not interrupt custody.

---

## 4. VERIFY durability is actually live (the recurring pain — now machine-checkable)

On **every** front-end:

```
curl -s http://<relay-host>:2112/metrics | grep '^relay_backend_durable'
# EXPECTED on a durable box:
#   relay_backend_durable 1
```

`relay_backend_durable 0` (or absent) ⇒ that box booted on the in-memory backend (env unset /
typo) and is **silently losing custody on restart**. Treat as a launch-blocker.

Also confirm the boot log line:

```
Control-plane: backend=redis durable=true prefix=relay:prod:
```

**Alerting:** add a Prometheus alert `relay_backend_durable < 1` (per-instance) — this is the only
detection for a deploy that silently regressed to memory.

---

## 5. (Later) Provision relay #2 — extend the pool to a second PEER

Transport redundancy ships today (WSS+QUIC to one peer). Multi-*peer* redundancy is a deploy-time
append once a second relay host with a **distinct peerID/host** exists:

1. Provision relay #2 (its own identity key ⇒ distinct peerID; its own DNS/host). Point it at the
   **same Redis** (steps 1–3) so the two front-ends share custody.
2. Add relay #2's WSS + QUIC multiaddrs to the client pool, either by:
   - appending them to `DefaultRelayAddresses()` in `go-mknoon/node/config.go` (then rebuild the
     client), **or**
   - injecting them at runtime via `NodeConfig.RelayAddresses` (no client rebuild).
3. **Do NOT invent a fake relay #2 peerID/host in code** — it must be a real provisioned identity.
   Until then the shipped default stays the single-peer WSS+QUIC pool (accepted difference).

The client already fails over across relay peers (`TestInboxStore_TriesSecondRelayWhenFirstFails`)
and both land in the same shared Redis, so a second peer is purely additive.

---

## 6. (Optional) Smoke the durability proof against the live Redis

If a live/staging Redis URL is reproducible in CI, run the cross-process durability proof:

```
cd go-relay-server && go test -tags integration -run TestRedisControlPlaneSharedAcrossProcesses ./...
```

(The committed proof uses miniredis; pointing it at a real Redis is an ops convenience, not a gate.)

---

## 7. Rollback

To revert durability (e.g. Redis incident), unset `RELAY_BACKEND` (or set `=memory`) and restart
the front-ends. The code default is memory, so this is a pure env change. **Caveat:** rolling back
to memory re-introduces restart-loss; only do so if Redis itself is the outage, and do NOT do it
while FDC-03's inbox-volume ramp is live.

---

## Checklist

- [ ] Redis provisioned, persistence enabled, network-restricted.
- [ ] `RELAY_BACKEND=redis` + `REDIS_URL` + per-env `REDIS_PREFIX` on **every** front-end.
- [ ] ≥2 front-ends sharing the one Redis.
- [ ] `relay_backend_durable 1` on every front-end (`curl :2112/metrics`).
- [ ] Prometheus alert on `relay_backend_durable < 1`.
- [ ] (Later) relay #2 provisioned + its WSS+QUIC added to the client pool.
- [ ] Confirmed durability live BEFORE FDC-03 inbox-volume ramps to prod traffic.
