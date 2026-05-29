# Relay Backward-Compatibility Constraint — Cross-Cutting Safety Rail

Prepared on: 2026-05-29
Status: Constraint (binding on every relay-touching change)
Tracking ID: NET-REL-07

## Why this doc exists

The relay is a **shared, single-host server whose address + peer ID are hard-coded
into every shipped app binary** (`go-mknoon/node/config.go:11,15`). There is no
version negotiation, no rolling/blue-green deploy, and no app-version gating — the
relay is `systemctl restart`-ed in place on `mknoun.xyz`. Therefore **any breaking
relay change hits 100% of un-updated clients instantly and silently.** This doc is
the binding compatibility rule for NET-REL-02 (relay/NAT), NET-REL-03 (springboard,
indirectly), and NET-REL-04 (relay metrics) — and for any future "make the relay
faster/better" work.

The user requirement that motivates it: **we must not break un-updated users'
chat experience before they update.**

## How compatibility actually works (verified)

- **Protocol IDs are exact-match strings, no negotiation.** Relay serves
  `/mknoon/inbox/1.0.0` (`go-relay-server/inbox.go:24`), `/canvas/rendezvous/1.0.0`
  (`rendezvous.go:16`), `/mknoon/media/1.0.0` (`media.go:19`), and circuit-relay-v2
  hop (`main.go:72-74`). Clients mirror these in `go-mknoon/node/config.go:21-25`.
  `protocol_version_test.go` proves there is NO fallback — opening an old version
  string against a node serving a new one simply fails.
- **Compatibility = constant protocol-ID strings + lenient JSON.** No client struct
  uses `DisallowUnknownFields`, so `json.Unmarshal` ignores unknown keys and
  zero-fills missing optional fields. Rendezvous protobuf parsing explicitly skips
  unknown field numbers (`go-mknoon/node/rendezvous.go:335,372,463`). This is what
  makes **additive-only changes safe in both directions.**
- **There is no relay-side version/capability handshake** and no
  `forbidden_field_classifier` compat mechanism (that file is a push-privacy guard,
  test-only). The relay's own `version = "1.5.1"` (`main.go:25`) is log-only and
  invisible to clients.

## SAFE vs BREAKING taxonomy (grounded in parsing code)

### ✅ SAFE for un-updated clients
- Add a **new** protocol ID / stream handler (old clients never dial it).
- Add a **new optional** request field (relay sees zero value) or response field
  (old clients ignore unknown keys).
- Add a **new `action`/`type`** value (old clients never send it).
- Add Prometheus metrics, logging, or relax limits (`metrics.go`, `limits.go`).
- Add fields to Redis records (`backend_redis.go`) — decoders tolerate/skip.
- **NET-REL-04's proposed 1:1-vs-group circuit metric falls here — safe.**

### ❌ BREAKING for un-updated clients
- Change/bump any served **protocol-ID string** (`…/1.0.0` → `…/1.1.0`). Single most
  dangerous change.
- Rename/remove/retype an **existing request or response field** — especially
  `groupMessages` (`inbox.go:1233` ↔ client `group_inbox.go:44`), `messages`,
  `status`, `hasMore`, `acked`, `nextCursor`. Old clients silently get empty/zero.
- Change **`status` string values** (`OK`/`ERROR`/`NO_MESSAGES`) — clients exact-match
  them (`inbox.go:121,194`).
- **Tighten validation** old clients violate (new required fields, stricter caps).
- Change **rendezvous protobuf field numbers / enum values / framing**.
- Change the **4-byte length framing** or shrink `MaxFrameLen` below 128 KB
  (`config.go:62`).
- Rename/remove **push `data` map keys** (`inbox.go:273-456`: `type`, `sender_id`,
  `kem`, `ciphertext`, `nonce`, `envelope_version`, `groupId`, `message_id`) — breaks
  notification decryption/routing on installed apps.
- Rename Redis record fields or `REDIS_PREFIX` — **orphans in-flight offline messages**
  (storage shape == wire shape for queued messages).

## Storage note

- `RELAY_BACKEND=memory` loses all in-flight inbox/rendezvous state on restart
  regardless of code change (clients tolerate it as `NO_MESSAGES`, but undelivered
  offline messages are lost). Redis backend persists; treat its record schema with the
  same additive-only discipline as the wire protocol.

## Rules for any relay-touching change

1. **Treat protocol-ID strings, `status`/action/response-key names, push `data` keys,
   and Redis record field names as FROZEN.** Only add, never rename/remove/retype.
2. **Additive-only** for every protocol and storage change.
3. **For a genuinely breaking change, use the multi-relay migration path** (already
   supported client-side via `buildRelaySelector` + shared Redis backend): stand up a
   new relay/protocol, ship it in new app builds, and retire the old relay only after
   telemetry shows old-app traffic has drained. Never flip the live relay.
4. **Add a relay-side contract test** mirroring `protocol_version_test.go` that pins
   the served protocol IDs AND the JSON response key names / `status` values, so an
   accidental rename fails CI. (This is itself a "must BUILD" item — it does not exist
   today; `go-relay-server` has no such test, and no `metrics_test.go`.)

## Test guarantee for compatibility

A change is only proven non-breaking if an **old-client contract test** passes against
the new relay. Concretely (BUILD):
- A relay-side test that asserts the exact set of served protocol IDs and response
  JSON keys/`status` values is unchanged (frozen-contract snapshot).
- An old-client simulation: drive the relay with the **current** client request shapes
  (`go-mknoon/node/inbox.go`, `group_inbox.go`, `rendezvous.go`) and assert successful
  parse of responses — run this against any relay change before deploy.
- NEGATIVE CONTROL: a deliberately renamed field/`status`/protocol-ID must make the
  contract test FAIL (proving the test actually guards the contract).

## References

- Relay: `go-relay-server/inbox.go`, `rendezvous.go`, `media.go`, `main.go`,
  `backend_redis.go`, `backend_memory.go`, `server_bootstrap.go`, `README.md` (single-host
  restart-in-place deploy).
- Client: `go-mknoon/node/config.go` (frozen relay addr + protocol IDs), `inbox.go`,
  `group_inbox.go` (the `groupMessages` key mapping), `rendezvous.go` (unknown-field
  skip), `protocol_version_test.go` (the de-facto contract test, exact-match/no-negotiation).
- Cross-ref: **NET-REL-04** (relay metric is additive = safe), **NET-REL-02** (relay is
  circuit-v2 only), **NET-REL-06** (test doctrine).
