# VC-03 — STUN/TURN embedded in go-relay-server  (New Feature)

Status: accepted (post /tdd-review)
Spec: free-text intent (no formal spec) — grounded in `Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-00-roadmap.md` (story row VC-03, NAT-plane decision, metrics table row "TURN allocations, active relayed calls, relayed bytes", rules 1/2/3/4/6)

---

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-13 | Evidence Collector | go-relay-server/{go.mod,main.go,server_config.go,metrics.go,inbox.go,inbox_test.go,inbox_presence_test.go}, go-mknoon/{node/inbox.go,node/inbox_presence_test.go,bridge/bridge.go,bridge/bridge_presence.go,Makefile}, lib/core/bridge/{go_bridge_client.dart,p2p_bridge_client.dart}, lib/core/services/p2p_service_impl.dart, android/.../GoBridge.kt, scripts/{run_test_gates.sh,run_host_test_gates.sh,check_reliability_simulation_discovery.sh} | all anchors re-verified on HEAD `new-orbit`; pion/turn/v2 v2.1.6 confirmed indirect at go-relay-server/go.mod:111 | hand to Planner |
| 2026-07-13 | Planner | (this document) | pion/turn **v2 kept** (see Decision below); creds via new additive inbox action; move-gate on Dart fetch | draft catalog + matrix |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | EC2 redeploy + live probe | | (runbook R1–R9) | live gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

---

## Source Of Truth
- Spec / intent: `VC-00-roadmap.md` (same dir) — story map row VC-03, DECISION RECORD ("TURN (VC-03) is therefore **not optional**"), collision map (VC-01 shares `go-relay-server/main.go`), the 7 cross-session rules.
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose). Relay Go gates: `run_relay_notification_go_gate` :860-863, `run_relay_all_go_gate` :865-868 (both `GOTOOLCHAIN=go1.25.0`); the `all` gate runs both bridge and relay-all Go hooks (:1149-1158).
- Host Go synthetic-path pattern to copy: `scripts/run_host_test_gates.sh:144-184` (constants) + `print_command_for_path`/`run_path` branches (:394-466).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (classify_path :71+; every `integration_test/*.dart` must classify or the script FAILS); `./scripts/run_test_gates.sh completeness-check` (classify_path at run_test_gates.sh:870; proof-suffix auto-branch :1036-1039).
- Numbering / index: VC-00 rule 7 — feature subdirectories are NOT indexed in `Test-Flight-Improv/00-INDEX.md`; this plan lives only here as VC-03.
- Redeploy procedure of record: `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md:141-150` (cross-compile + scp + `sudo install` + `systemctl restart`) — the operational flow actually used, per the relay-ops grounding digest.
- House style: `Test-Flight-Improv/Network-Transport-libp2p-Feature/fast-direct-connection/FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md` (structure only; its pass counts are stale — VC-00 rule 6: capture green baselines at execution start).

---

## Session Classification
**implementation-ready** — every seam is grounded with re-verified file:line anchors; the server half closes with Go host tests (mocknet / 127.0.0.1 in-process TURN server, no device needed); the client half closes with Dart host tests plus one single-party Android device/emulator proof; the deployment half closes with the literal EC2 runbook in this plan (VC-00 rule 2). No DB migration, no UI, no iOS rig dependency for closure (iOS native dispatch lands as code; its device evidence is deferred-not-waived per VC-00 rule 1).

---

## Exact Problem Statement

The VC epic's media plane is `flutter_webrtc` P2P (VC-00 decision record). WebRTC ICE requires (a) a **STUN** server so peers learn their server-reflexive addresses and (b) a **TURN** relay for the pairs that cannot punch — and the roadmap is explicit that DCUtR/hole-punching literature figures (~70% network-wide, ≈0% symmetric-CGNAT cellular↔cellular) make TURN **not optional** (VC-00 DECISION RECORD, last bullet). Today the product has **neither**: there is zero TURN/STUN executing code in `go-relay-server` (verified: `grep -rn 'pion' --include='*.go' go-relay-server` → 0 hits), and no public STUN/TURN endpoint exists on mknoun.xyz. Without VC-03, VC-05 (first audio call) has no ICE servers at all and every cross-NAT call fails.

Who experiences it: every future caller whose peer sits behind NAT — i.e. effectively all real-world 1:1 calls. Why it matters now: VC-03 is on the MVP critical path (VC-03 → VC-04 → VC-05, VC-00 story map) and is independent of VC-01/VC-02, so it can land first.

**What must improve:** the deployed relay at mknoun.xyz serves STUN+TURN on UDP 3478 with ephemeral HMAC credentials mintable by any authenticated app peer via a new additive relay-protocol action, consumable from Dart through the existing bridge conventions, observable via `relay_` Prometheus metrics, and bounded by abuse limits.

**What must stay unchanged → preserved-green sentinels:** every existing relay behavior — inbox store/retrieve/ack, presence, push, rendezvous, media — byte-identical for non-TURN requests (NET-REL-07 additive-action contract, `go-relay-server/NOTES.md:114-121`); the full relay Go suite (`go test ./... -count=1`); the Dart `1to1` gate; the bridge cmd-map polarity pins (`test/core/bridge/go_bridge_client_test.dart`, `p2p_bridge_client_test.dart`).

---

## Root Cause (verify → refute confirmed)

New feature, so "root cause" = **verified absence + verified seams**:

- **No TURN/STUN code executes anywhere in the relay**: zero `pion` imports in any `go-relay-server/*.go` (re-verified by grep on HEAD). The pion stack is present only as **indirect** module-graph entries pulled by libp2p v0.38.2 — `github.com/pion/turn/v2 v2.1.6` at `go-relay-server/go.mod:111`, `pion/stun v0.6.1` at `:108`, `pion/ice/v2 v2.3.37` at `:98` (all re-verified).
- **Service-wiring seam**: `go-relay-server/main.go` is a flat `package main`; subsystems start from `main()` — protocol handlers registered at main.go:131-139 (`HandleInboxStream(s, inbox, groupInbox, h, presence)` at :135), the Prometheus HTTP server precedent for "extra listener started from main()" at main.go:229-236 (`:2112/metrics`).
- **Action-dispatch seam**: `HandleInboxStream` (inbox.go:2033) switches on `req.Action` (inbox.go:2066+), `default:` → `{"status":"ERROR","error":"Unknown action: X"}` (inbox.go:2276-2277). Additive actions are backward-compatible by contract (NOTES.md:114-121). New arms follow the FDC-08 named-handler rule (delegating case → named func; nolint comment at inbox.go:2027-2032, `presence_get → handlePresenceGet` precedent at inbox.go:2270-2274).
- **Env-config seam**: `server_config.go` — `loadServerConfigFromEnv()` (:71-96) with `envStrOrDefault`/`envIntOrDefault` and `DefaultServerConfig()` (:57-67, DNS `mknoun.xyz` :60, IP `13.60.15.36` :61).
- **Metrics seam**: package-level `promauto` vars with `relay_` prefix in `metrics.go` (`relay_connections_active` :10-13; enable/durability gauge precedent `relay_backend_durable` :20-23, set at boot from main.go).
- **Bridge seam (Go)**: gomobile-exported string-in/string-out JSON funcs (`go-mknoon/bridge/bridge.go:1-11` protocol doc); exact template = `go-mknoon/bridge/bridge_presence.go` (`PresenceGet`/`PresenceSet`: nodeMu singleton, `errJSON("NOT_INITIALIZED", …)`, `okJSON`).
- **Node client seam (Go)**: `go-mknoon/node/inbox.go` — client `inboxRequest`/`inboxResponse` structs (:28-69, additive omitempty fields), relay-selector rollover pattern `RelayPresenceLookup` (:325+) incl. "any received reply — even Unknown action — is definitive" semantics.
- **Dart bridge seam**: `lib/core/bridge/go_bridge_client.dart` `_CmdSpec` map (`'relay:presence_get': _CmdSpec('relayPresenceGet', true)` at :128); helper convention `callP2PRelayPresence` at `lib/core/bridge/p2p_bridge_client.dart:229-286` (flow events, 5s timeout, unknown-action degrade); native dispatch `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:119` (`"relayPresenceGet" -> runOnBackground({ GoMknoon.presenceGet(args ?: "") }, result)`) + `ios/Runner/GoBridge.swift` twin.
- **Move-gate seam (VC-00 rule 4)**: `_allowsAccountNetworkSideEffects` at `lib/core/services/p2p_service_impl.dart:555-572` (re-verified on HEAD: signature :555, closing brace :572 — the digest's cite was correct; an earlier draft's ":554-571 correction" was itself the off-by-one), called FIRST-LINE by every network primitive (e.g. `lookupRelayPresence` gate at :5114 with token `'p2p_get_presence'`).

**Refuted / do-NOT-re-introduce** (from the relay-ops digest's adversarial pass):
- ~~"go-relay-server/go.mod has zero pion modules"~~ — **REFUTED**. Carry the correction: pion/turn/v2 v2.1.6 is ALREADY in the module graph as an indirect libp2p dep; promoting it to direct adds **no new supply-chain source**. What survives: zero pion **imports** in relay source.
- Do NOT cite the dormant LiveKit plans (`Voice-Video-Call-LiveKit-Feature/`) as design input — superseded by VC-00, and they misspell the production domain (`mknoon.xyz`; it is `mknoun.xyz`, server_config.go:60).
- Do NOT plan a repo-side firewall/IaC edit — verified absence: no security-group/UFW/IaC config exists anywhere in the repo; opening UDP ports is a manual EC2 operator step (runbook R5, marked NEW).
- Do NOT cite `/dns4/mknoun.xyz/tcp/4005` as an "announced" relay address — the announce set (main.go:55-59) is wss `/dns4/…/tcp/4001/wss`, plain-TCP `/ip4/13.60.15.36/tcp/4005` (:57), and quic `/dns4/…/udp/4002/quic-v1`; the dns4-TCP form is dialable but is NOT announced.

---

## Real Scope

**In scope (VC-03):**
1. **Dependency decision — keep `pion/turn/v2 v2.1.6`, promote to direct.** Justification: (a) it is already pinned in the module graph via libp2p v0.38.2 (`go.mod:111`) — promotion edits one `go.mod` line, adds zero new modules/checksums; (b) libp2p's own `pion/ice/v2 v2.3.37` depends on turn/v2, so v2 keeps ONE pion TURN version in the binary (no skew); (c) v2's API covers everything VC-03 needs: `turn.NewServer`/`turn.ServerConfig` (Realm, AuthHandler, PacketConnConfigs), `turn.GenerateAuthKey`, `turn.RelayAddressGeneratorPortRange`, and `turn.NewClient` for the probe. Upgrading to turn/v4 would add two NEW modules (`pion/turn/v4`, `pion/stun/v3`) and a second TURN stack beside libp2p's pinned v2; v4's only material gain (the per-allocation `EventHandler` callback field, added v4.1.0) is deferred to VC-09 hardening (see Accepted Differences).
2. **Embedded STUN+TURN server** — new `go-relay-server/turn_server.go`, started from `main()` after the metrics server (precedent main.go:229-236): one UDP listener (default `:3478`, serves STUN Binding and TURN on the same socket, which pion/turn does natively), relay-port-range allocator (`turn.RelayAddressGeneratorPortRange` wrapped in a **counting/capping generator** — see metrics + limits), realm + public/relay IP from env. **Kill-switch (VC-00 rule 3): `TURN_SHARED_SECRET` unset (or `TURN_ENABLED=0`) ⇒ TURN server not started, credentials action answers `TURN_DISABLED`, gauge `relay_turn_enabled=0`** — mirroring the "push disabled" no-op pattern (inbox.go:108-117) and the boot-time `relay_backend_durable` gauge. **Gauge set-site is pinned to ONE place: `NewTurnCredentialIssuer` (issuer construction) sets `relay_turn_enabled` to 1 or 0; `main()` only logs.** Test envs that never run `main()` (mocknet via `setupInboxStreamEnv`) therefore exercise the real set path, and TC-05 must prove the set (not the zero default) by setting the gauge to 1 before constructing the disabled issuer.
3. **Config** — new `go-relay-server/turn_config.go` following server_config.go conventions (`envStrOrDefault`/`envIntOrDefault`, defaults from `DefaultServerConfig()`): `TURN_SHARED_SECRET` (required to enable), `TURN_UDP_PORT`=3478, `TURN_REALM`=`mknoun.xyz` (ServerDNS), `TURN_PUBLIC_IP`=ServerIP4 (13.60.15.36), `TURN_MIN_RELAY_PORT`/`TURN_MAX_RELAY_PORT`=49152/65535, `TURN_CRED_TTL_SECONDS`=600, `TURN_MAX_ACTIVE_ALLOCATIONS`=64, `TURN_CRED_MINTS_PER_PEER_PER_MINUTE`=6.
4. **Ephemeral credentials (TURN REST pattern)** — new `go-relay-server/turn_credentials.go`: `username = "<expiryUnix>:<peerId>"`, `credential = base64std(HMAC-SHA1(sharedSecret, username))`; server AuthHandler parses username, rejects expired/forged/malformed, returns `turn.GenerateAuthKey(username, realm, credential)`.
5. **New additive relay action `turn_credentials_get`** — new `case` in `HandleInboxStream`'s switch delegating to named `handleTurnCredentialsGet` (FDC-08 named-handler rule); binds the minted username to the **authenticated stream peer** (`s.Conn().RemotePeer()`, anti-spoof — same trust move as the `store` attribution comment at inbox.go:2072-2075 and `presence_set`); response = additive omitempty fields on `inboxResponse` (`turnUsername`, `turnCredential`, `turnTtlSeconds`, `turnUris`) so every other action's reply stays byte-identical (NET-REL-07, presence-fields precedent inbox.go:1988-1994). Per-peer mint rate limit lives here. `HandleInboxStream` signature gains a `*TurnCredentialIssuer` param (presence precedent — signature threaded through main.go:135 and the single test env constructor `setupInboxStreamEnv`, inbox_test.go:86).
6. **Go bridge command + node client** — `go-mknoon/node/turn.go`: `(n *Node) TurnCredentialsGet()` using the relay-selector rollover of `RelayPresenceLookup` (node/inbox.go:325+), old relay's `Unknown action` → `Unsupported:true` (never an error — NET-REL-07); additive `turnUsername`/`turnCredential`/`turnTtlSeconds`/`turnUris` fields on the client `inboxResponse` (node/inbox.go:53-69). `go-mknoon/bridge/bridge_turn.go`: exported `TurnCredentialsGet(paramsJSON string) string` copying `bridge_presence.go` exactly (recover→`INTERNAL_ERROR`, nil node→`NOT_INITIALIZED`, `okJSON{ok, username, credential, ttlSeconds, uris, unsupported}`).
7. **Dart client** — `go_bridge_client.dart`: `'turn:credentials': _CmdSpec('turnCredentialsGet', true)` (+ the standard "native dispatch + gomobile rebuild land with device closure" comment convention, :125-141); native cases `"turnCredentialsGet" -> runOnBackground({ GoMknoon.turnCredentialsGet(args ?: "") }, result)` in `GoBridge.kt` (precedent :119) and the `GoBridge.swift` twin; `p2p_bridge_client.dart`: `callP2PTurnCredentials(Bridge)` copying `callP2PRelayPresence` (:229-286 — flow events, 5s timeout, unknown-action → `{'unsupported': true}` degrade); domain model `lib/features/p2p/domain/models/turn_credentials.dart`; `P2PService.fetchTurnCredentials()` on the abstract (`lib/core/services/p2p_service.dart`) + `P2PServiceImpl` impl that (a) calls `_allowsAccountNetworkSideEffects('p2p_turn_credentials')` **first-line** (VC-00 rule 4; precedent :5114) and (b) caches creds in RAM until 80% of TTL (clock.now()-based, mirroring `_presenceCache` :175-176 + read-time eviction :5121-5132) so VC-05's ICE gathering does not re-mint per call attempt. Fakes updated: `test/shared/fakes` `FakeP2PService` gains a stubbable `fetchTurnCredentials`.
8. **Prometheus metrics** (metrics.go conventions): `relay_turn_enabled` (gauge 0/1), `relay_turn_credentials_issued_total`, `relay_turn_auth_failures_total`, `relay_turn_allocations_total`, `relay_turn_allocations_active` (gauge), `relay_turn_relayed_bytes_total{direction="rx"|"tx"}` (CounterVec, label precedent `relay_stream_errors_total{proto,kind}` metrics.go:250-253). Allocation counters + byte counters + the **global active-allocation cap** are implemented in the counting `RelayAddressGenerator` wrapper: `AllocatePacketConn` = one allocation (count, cap-check, gauge inc), the wrapped `net.PacketConn`'s `ReadFrom`/`WriteTo` count relayed bytes, its `Close` decrements the gauge.
9. **Rate/abuse limits**: per-peer credential-mint rate limit (token bucket per authenticated peerId at the action), global `TURN_MAX_ACTIVE_ALLOCATIONS` cap at the allocator, TTL-bounded creds (10 min). **Bandwidth cost documented** in `go-relay-server/NOTES.md` (new TURN appendix): a relayed call costs the relay **~2× the media bitrate** (rx + tx) — ≈80 kbps per relayed Opus audio call (40 kbps codec), ≈2–5 Mbps per relayed video call; plus the SG/port-range requirements. **Capacity decision (the ship criterion for the cap): `TURN_MAX_ACTIVE_ALLOCATIONS=64` bounds worst-case relayed load to ~64 × 2.5 Mbps ≈ 160 Mbps ≤ the EC2 instance's NIC/egress budget — accepted for MVP; revisit the cap (and per-username accounting) before VC-05 GA.**
10. **EC2 redeploy + live verification** (VC-00 rule 2) — the literal runbook in this plan (section "EC2 Redeploy & Live Verification"): build linux binary per the 142 flow, systemd env drop-in (NEW), security-group UDP openings (NEW, manual op), live probe `TestTurnLiveProbe_EndToEnd` (creds fetched over libp2p from the deployed relay → pion client allocates at `mknoun.xyz:3478` → relays a packet), metrics scrape, rollback with the retained previous binary.
11. **Harness registration** (VC-00 rule 6): new relay Go tests all named `^TestTurn` and run by the existing `run_relay_all_go_gate` (`all` gate, run_test_gates.sh:1156) **plus** three NEW synthetic Go paths in `run_host_test_gates.sh` host-all (pattern :144-184) so they run per-change; the device proof registers in `check_reliability_simulation_discovery.sh` classify_path; the 4 gate docs updated together (rule 6).

**Out of scope (owning story):**
- `flutter_webrtc`, ICE agent config, actually USING the creds in a call → **VC-05**.
- `call_*` signaling envelopes → **VC-04**.
- Any circuit-relay limit change (`go-relay-server/limits.go`) → **VC-01** owns limits.go; VC-03 must not touch it.
- Call-invite push types (`extractChatPushMetadata` etc.) → **VC-06/VC-07**.
- Per-username allocation accounting / turn v4 `EventHandler` callbacks, TURN-over-TCP/TLS (443) fallback, "always relay" privacy toggle → **VC-09**.

---

## Files To Inspect Next

**Production (created):** `go-relay-server/turn_config.go`, `turn_credentials.go`, `turn_server.go`; `go-mknoon/node/turn.go`; `go-mknoon/bridge/bridge_turn.go`; `lib/features/p2p/domain/models/turn_credentials.dart`.
**Production (edited):** `go-relay-server/go.mod` (promote pion/turn/v2 to direct), `main.go` (start TURN + thread issuer into the inbox handler closure :135), `inbox.go` (new action case + additive response fields + `HandleInboxStream` signature), `metrics.go` (six `relay_turn_*` vars), `NOTES.md` (TURN appendix); `go-mknoon/node/inbox.go` (additive client response fields); `lib/core/bridge/go_bridge_client.dart` (cmd map), `lib/core/bridge/p2p_bridge_client.dart` (helper), `lib/core/services/p2p_service.dart` + `p2p_service_impl.dart` (gated fetch + cache); `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`, `ios/Runner/GoBridge.swift` (dispatch cases).
**Harness (edited):** `scripts/run_host_test_gates.sh` (3 synthetic Go paths), `scripts/check_reliability_simulation_discovery.sh` (device-proof case), plus the rule-6 doc quartet: `scripts/run_test_gates.sh` is NOT edited (relay tests ride `run_relay_all_go_gate`) but `test-gate-definitions.md`, `test-gates-reference.md`, `_current-test-map.md` gain the host-all synthetic-path rows.
**Direct tests (created):** `go-relay-server/turn_credentials_test.go`, `turn_action_test.go`, `turn_server_test.go`, `turn_live_probe_test.go`; `go-mknoon/node/turn_credentials_client_test.go`; `go-mknoon/bridge/bridge_turn_test.go`; `test/core/bridge/p2p_bridge_client_turn_test.dart`; `test/core/services/p2p_service_impl_turn_credentials_test.dart`; `integration_test/turn_credentials_live_proof_test.dart`.
**Direct tests (edited):** `test/core/bridge/go_bridge_client_test.dart` (cmd-map pin entry), `go-relay-server/inbox_test.go` (`setupInboxStreamEnv` signature), test fakes.
**Dependency-only context (not edited):** `go-relay-server/inbox_presence_test.go` (mocknet env + raw-JSON-keys schema-lock template :44-67), `go-mknoon/node/inbox_presence_test.go` (fake-relay stream-handler client-test template :20-70), `go-relay-server/server_bootstrap.go`, `limits.go` (VC-01's — read-only), `bridge_presence.go`.

---

## Existing Tests Covering This Area

| Test | Covers | Status |
|---|---|---|
| `go-relay-server/protocol_contract_test.go` | inbox action wire contract incl. unknown-action ERROR shape | exists — preservation sentinel (the additive action must not change it) |
| `go-relay-server/inbox_test.go` (+ `setupInboxStreamEnv` :86) | full 1:1 inbox behavior over mocknet | exists — sentinel; env constructor gains the issuer param |
| `go-relay-server/inbox_presence_test.go` | additive-action + raw-JSON-keys schema-lock precedent | exists — template, stays green |
| `go-relay-server/metrics_test.go` | metric names/labels | exists — extended pattern for `relay_turn_*` |
| `go-relay-server/push_payload_closure_test.go` (`^TestRelayNotificationClosure_`) | push contract (curated 1to1/groups gate hook) | exists — sentinel, untouched |
| `test/core/bridge/go_bridge_client_test.dart` (`payloadCmds` pin, :163-211) | cmd→MethodChannel map | exists — gains the `turn:credentials` row (RED first) |
| `test/core/bridge/p2p_bridge_client_test.dart` | bridge helper contracts + flag polarity | exists — sentinel, untouched |
| TURN server / creds / action / Dart fetch | — | **MISSING — the entire VC-03 surface. All rows below are new.** |

Missing coverage gaps: everything TURN (this plan). Already in curated family arrays?: `go_bridge_client_test.dart` and `p2p_bridge_client_test.dart` are in `ONE_TO_ONE_TESTS` (run_test_gates.sh:66-67) — the cmd-map RED lands inside an already-registered file.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Where a brand-new symbol makes a test **compile-RED**, that is stated explicitly and paired with a **behavioral mutation** for GREEN-phase re-red verification. Tests that only touch existing symbols are **behavior-RED** on HEAD (preferred).

### Relay: credentials + auth (`go-relay-server/turn_credentials_test.go`)
1. `TestTurnCred_MintFormatAndHmac` (TC-01)
   - Tier: unit (Go host, pure function, injected `now`)
   - Shape: `mintTurnCredentials(peerId, ttl, secret, now)` → assert `username == "<now+ttl unix>:<peerId>"` and `credential == base64std(HMAC-SHA1(secret, username))` recomputed independently in the test.
   - RED on HEAD because: compile-RED — `mintTurnCredentials` does not exist (no TURN code in the relay; grep-verified absence).
   - GREEN asserts: exact TURN-REST format; deterministic under fixed `now`.
   - Mutation that re-reds: swap HMAC input to peerId-only (drop expiry from the MAC) → recomputed credential mismatches → RED.
2. `TestTurnCred_AuthHandlerAcceptsValidCred` (TC-02)
   - Tier: unit. Shape: mint, then call the `turn.AuthHandler` func with (username, realm, srcAddr); expect `key == turn.GenerateAuthKey(username, realm, credential)`, ok=true.
   - RED on HEAD because: compile-RED — no auth handler exists.
   - Mutation: make the handler return ok=true without HMAC verification — then TC-03's forged case flips (paired).
3. `TestTurnCred_AuthHandlerRejectsExpiredForgedMalformed` (TC-03)
   - Tier: unit. Shape: three sub-cases — (a) expiry in the past, (b) valid expiry + wrong HMAC, (c) username without `:`; each must return ok=false AND bump `relay_turn_auth_failures_total` (delta-read via `prometheus/testutil`, before/after — package vars are global).
   - RED on HEAD because: compile-RED (no handler, no metric var).
   - GREEN asserts: all three rejected; failures counter +3.
   - Mutation that re-reds: remove the `expiry < now` check → sub-case (a) authenticates → RED.
4. `TestTurnCred_MintRateLimitPerPeer` (TC-09)
   - Tier: unit. Shape: issuer with limit 6/min; 6 mints for peer A succeed, 7th returns rate-limited; peer B unaffected; window rollover (injected clock) re-allows.
   - RED on HEAD because: compile-RED (no issuer).
   - Mutation: key the bucket globally instead of per-peer → peer B's mint fails after A's 6 → RED.

### Relay: the additive action (`go-relay-server/turn_action_test.go`, mocknet env of inbox_test.go:86 / raw-keys technique of inbox_presence_test.go:44-67)
5. `TestTurnAction_BindsCredsToAuthenticatedPeer` (TC-04)
   - Tier: integration (in-process mocknet, real streams).
   - Shape: sender host opens `InboxProtocol` stream to server, sends `{"action":"turn_credentials_get","to":"someone-else","from":"spoofed"}`; decode response.
   - RED on HEAD because: **behavior-RED, compiles on HEAD** — the dispatch default answers `{"status":"ERROR","error":"Unknown action: turn_credentials_get"}` (inbox.go:2276-2277); the test asserts `status=="OK"`.
   - GREEN asserts: `status=="OK"`; `turnUsername` suffix == the **stream's** authenticated remote peer id (spoofed `from`/`to` ignored); `turnTtlSeconds==600`; `turnUris` contains `turn:mknoun.xyz:3478?transport=udp` AND `stun:mknoun.xyz:3478`; credential HMAC-verifies against the test secret; delta-read `relay_turn_credentials_issued_total` +1 via `prometheus/testutil` (before/after the action — same delta technique as TC-03, so the issued-counter contract has a host-tier proof and is not R8-only).
   - Mutation that re-reds: mint from `req.From` instead of `s.Conn().RemotePeer()` → suffix assertion RED (anti-spoof lock).
6. `TestTurnAction_DisabledWithoutSecret` (TC-05)
   - Tier: integration. Shape: env with issuer disabled (no secret); action returns `{"status":"ERROR","error":"TURN_DISABLED"}`; `relay_turn_enabled` gauge reads 0. **Gauge technique: the test first sets `relay_turn_enabled` to 1, then constructs the disabled issuer (the pinned single set-site) and asserts it reads 0 — proving the constructor sets the gauge, not that the package default is zero.**
   - RED on HEAD because: behavior-RED — HEAD answers `Unknown action: …`, not `TURN_DISABLED`.
   - Mutation: make the disabled issuer mint anyway → status OK → RED. (This is the **kill-switch revert-path lock**, VC-00 rule 3.)
7. `TestTurnAction_NonTurnResponsesOmitTurnKeys` (TC-06)
   - Tier: integration. Shape: run `store` + `presence_get` through the env; decode responses into `map[string]json.RawMessage`; assert none of `turnUsername|turnCredential|turnTtlSeconds|turnUris` appear (NET-REL-07 byte-identity via omitempty; schema-lock technique of inbox_presence_test.go:44-67).
   - RED on HEAD because: compile-RED only if it references new symbols — write it against raw JSON keys so it **passes trivially on HEAD and is the preservation lock after** (declared preserved-green, not RED; listed here for completeness). Preserved-green sentinel.
   - Mutation that re-reds: drop `omitempty` from one turn field → key appears in a `store` response → RED.

### Relay: the embedded server (`go-relay-server/turn_server_test.go`)
8. `TestTurnServer_AllocateAndRelayEcho_WithMintedCreds` (TC-07) — **the in-process E2E**
   - Tier: integration (real UDP on 127.0.0.1:0, in-process `turn.NewServer`, `turn.NewClient` from the same pinned pion/turn v2).
   - Shape: start server with test secret + relay range on loopback; mint creds; pion client `Allocate()`; the allocated relay conn `WriteTo`s a second UDP socket first (**pion/turn v2 mints the TURN permission implicitly on this first send — the v2 client exports no `CreatePermission`; do not look for that symbol**), then the second socket sends a packet back to the relayed address; assert echo round-trip; delta-assert `relay_turn_allocations_total +1`, `relay_turn_allocations_active` 1 while held and **0 after client close**, `relay_turn_relayed_bytes_total{rx|tx} > 0`. Also `SendBindingRequest()` (STUN) returns a mapped address — same listener serves STUN.
   - RED on HEAD because: compile-RED — `startTurnServer` does not exist.
   - GREEN asserts: allocation + STUN + relay + full metric lifecycle.
   - Mutation that re-reds: remove the gauge `Dec()` in the wrapped conn `Close` → active stays 1 after close → RED (destructive-action lock).
9. `TestTurnServer_RejectsForgedCreds` (TC-08)
   - Tier: integration. Shape: same server; client with `credential="forged"` — `Allocate()` errors; `relay_turn_auth_failures_total` delta ≥1.
   - RED on HEAD because: compile-RED. Mutation: paired with TC-02's (auth handler pass-through) → forged allocation succeeds → RED.
10. `TestTurnServer_GlobalAllocationCap` (TC-10)
    - Tier: integration. Shape: server with `TURN_MAX_ACTIVE_ALLOCATIONS=1`; first client allocates OK; second client's `Allocate()` fails; after first closes, a third succeeds (cap releases — invariant re-verification after the release transition).
    - RED on HEAD because: compile-RED. Mutation: remove the cap-check in `AllocatePacketConn` → second allocation succeeds → RED.
11. `TestTurnServer_ConfigFromEnv` (TC-11)
    - Tier: unit. Shape: `t.Setenv` overrides for every `TURN_*` var → parsed struct fields; no-env → defaults (3478, realm mknoun.xyz, public IP 13.60.15.36, range 49152-65535, ttl 600, cap 64, mints 6/min, **disabled** when secret empty); invalid range (min>max) → error/disabled.
    - RED on HEAD because: compile-RED. Mutation: flip the default-disabled polarity (enable with empty secret) → RED.
12. `TestTurnServer_MetricsRegistered` (TC-12)
    - Tier: unit (metrics_test.go pattern). Shape: assert all six `relay_turn_*` collectors exist with exact names + the `direction` label on the bytes CounterVec.
    - RED on HEAD because: compile-RED (vars absent). Mutation: rename a metric → RED. (Locks the Grafana/scrape contract.)

### Relay: live probe (`go-relay-server/turn_live_probe_test.go`) — PROD-CRITICAL
13. `TestTurnLiveProbe_EndToEnd` (TC-21)
    - Tier: live-relay probe (deployed EC2; **operator/agent-run inside the redeploy runbook, never a CI/host gate** — redeploy-adjacent verification is an explicit operator action, 173 plan:160).
    - Shape: `t.Skip` unless `TURN_LIVE_PROBE=1`. (1) libp2p client host dials `/ip4/13.60.15.36/tcp/4005/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (the **announced** plain-TCP addr, main.go:57; pinned relay peer id from run_test_gates.sh:568); (2) sends `turn_credentials_get`, gets creds — **no secret needed by the probe**; (3) `turn.NewClient` against `mknoun.xyz:3478` with the returned creds: STUN binding, `Allocate()`, then one relayed packet echo — relay conn `WriteTo`s the second local UDP socket first (implicit permission mint, same v2 semantics as TC-07), second socket replies to the relayed address; (4) prints the allocation for the metrics-scrape cross-check (runbook R8).
    - RED on HEAD because: behavior-RED against the **deployed** relay — pre-deploy the action answers `Unknown action` and nothing listens on UDP 3478 (probe fails at step 2/3). This is the VC-00 rule-2 live gate.
    - GREEN asserts: end-to-end creds→STUN→allocate→relay against production. **This is the single PROD-CRITICAL leg — unit/in-process coverage is NOT sufficient on its own to close VC-03.**
    - Mutation that re-reds: run it against a rolled-back binary (runbook R9) → fails again — doubling as the rollback verification.

### Node client (`go-mknoon/node/turn_credentials_client_test.go`, template node/inbox_presence_test.go:20-70)
14. `TestTurnCredentialsGet_SendsActionAndDecodes` (TC-13)
    - Tier: integration (fake relay = local libp2p host with a scripted `InboxProtocol` handler).
    - Shape: fake relay captures the request and replies `{"status":"OK","turnUsername":"1700000000:peer","turnCredential":"abc","turnTtlSeconds":600,"turnUris":["turn:mknoun.xyz:3478?transport=udp","stun:mknoun.xyz:3478"]}`; call `n.TurnCredentialsGet()`.
    - RED on HEAD because: compile-RED — `TurnCredentialsGet` does not exist on Node.
    - GREEN asserts: request frame had `action=="turn_credentials_get"`; result decodes all four fields; `Unsupported==false`.
    - Mutation that re-reds: send `action:"presence_get"` instead → captured-action assertion RED.
15. `TestTurnCredentialsGet_OldRelayUnknownActionDegradesUnsupported` (TC-14)
    - Tier: integration. Shape: fake relay replies `{"status":"ERROR","error":"Unknown action: turn_credentials_get"}`.
    - RED on HEAD because: compile-RED.
    - GREEN asserts: no error thrown; `Unsupported==true`, empty creds (NET-REL-07 — a reply is definitive, no rollover spam; mirrors `parsePresenceSetResponse` semantics node/inbox.go:391-405).
    - Mutation: map unknown-action to a returned error → RED.

### Go bridge (`go-mknoon/bridge/bridge_turn_test.go`, bridge_test.go conventions)
16. `TestTurnCredentialsBridge_NotInitializedAndShape` (TC-15)
    - Tier: unit. Shape: call exported `TurnCredentialsGet("")` with nil singleton → JSON `{ok:false, errorCode:"NOT_INITIALIZED"}` (exact envelope of bridge_presence.go).
    - RED on HEAD because: compile-RED — export absent. Mutation: return a bare error string instead of the errJSON envelope → JSON decode assertion RED.

### Dart (host)
17. `test/core/bridge/go_bridge_client_test.dart` — add `'turn:credentials': 'turnCredentialsGet'` to the `payloadCmds` pin map (:163-211) (TC-16)
    - Tier: unit (widget-free host).
    - RED on HEAD because: **behavior-RED** — `GoBridgeClient` has no `turn:credentials` `_CmdSpec`, so `send()` rejects the unknown cmd; the generated map-iteration test fails.
    - GREEN asserts: cmd routes to MethodChannel method `turnCredentialsGet` with payload JSON.
    - Mutation that re-reds: remove the `_CmdSpec` entry → RED. Registration: file already in `ONE_TO_ONE_TESTS` (run_test_gates.sh:66) + auto-glob.
18. `test/core/bridge/p2p_bridge_client_turn_test.dart::callP2PTurnCredentials parses creds and degrades unknown-action to unsupported` (TC-17)
    - Tier: unit. Shape: fake `Bridge` returning (a) ok envelope → map with username/credential/ttlSeconds/uris; (b) `{status:'ERROR', error:'Unknown action: turn_credentials_get'}` → `{'unsupported': true}` and no throw (pattern of callP2PRelayPresence :246-263).
    - RED on HEAD because: compile-RED — helper absent.
    - Mutation: make unknown-action throw → sub-case (b) RED.
19. `test/core/services/p2p_service_impl_turn_credentials_test.dart::fetchTurnCredentials is move-gated FIRST (no bridge call when denied)` (TC-18)
    - Tier: unit. Shape: `P2PServiceImpl` with a denying `AccountMigrationNetworkGate`; call `fetchTurnCredentials()`.
    - RED on HEAD because: compile-RED — method absent on the interface/impl.
    - GREEN asserts: returns null; **zero** bridge invocations recorded; `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED` flow event with `operation=='p2p_turn_credentials'` (captured via `captureFlowEvents` — the distinct-event discriminator vs. a mere network failure, which would emit no BLOCKED event).
    - Mutation that re-reds: move the gate call after the bridge call → bridge-invocation count ≥1 under denial → RED. (VC-00 rule 4 lock.)
20. `…::cached creds are reused within 80% of TTL and re-fetched after` (TC-19)
    - Tier: unit. Shape: allowing gate; fake bridge counts calls; `withClock` fixed time — two fetches inside 0.8×ttl → 1 bridge call; advance past 0.8×ttl → second bridge call (read-time eviction, `_presenceCache` pattern :5121-5132).
    - RED on HEAD because: compile-RED.
    - GREEN asserts: cache lifecycle above; **derived-state durability**: the cache is RAM-only by design — after a simulated service re-construction (new impl instance) the fetch re-mints (reconstructs from the relay, no stale reuse).
    - Mutation that re-reds: cache without expiry check → second-window fetch returns stale (bridge calls stay 1) → RED.

### Device proof (`integration_test/turn_credentials_live_proof_test.dart`, `@Tags(['device'])`)
21. `::VC-03 device fetches live TURN creds through the real bridge` (TC-20)
    - Tier: device-proof (real `GoBridgeClient`, real Go bridge AAR, live relay mknoun.xyz — post-deploy only).
    - Shape: start node with the app-default relay addresses (`/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…`, run_test_gates.sh:568); call the Dart fetch; assert username suffix == this device's peerId, `uris` contains `turn:mknoun.xyz:3478?transport=udp`, ttl>0; **wire-encoding lock (device side, no secret available): credential is non-empty and decodes as valid standard base64, and username parses as `<futureUnixSeconds>:<ownPeerId>` with the expiry strictly in the future** — locking the encoding from the device without needing an allocation (allocation-from-device is VC-05's ICE proof).
    - RED on HEAD because: behavior-RED pre-implementation (unknown cmd) and pre-deploy (old relay → `unsupported`); GREEN only after code + gomobile rebuild + EC2 redeploy — by design (rule 2 sequencing).
    - Mutation that re-reds: any of TC-16/17/18's mutations, exercised end-to-end.
    - Runs on **both** the USB Android device and one emulator (single-party; no orchestrator needed — see Execution Environment).

---

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 cred mint format | pure logic | unit Go | `turn_credentials_test.go::TestTurnCred_MintFormatAndHmac` | compile-RED (symbol absent) | drop expiry from HMAC input | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestTurn' -count=1)` | pkg member of `run_relay_all_go_gate` (`all` gate, run_test_gates.sh:1156) + NEW host-all synthetic path `GO_RELAY_TURN` |
| TC-02 auth accepts valid | pure logic | unit Go | `…::TestTurnCred_AuthHandlerAcceptsValidCred` | compile-RED | handler skips HMAC verify (pairs TC-03/08) | same | same |
| TC-03 auth rejects expired/forged/malformed + metric | pure logic + metric | unit Go | `…::TestTurnCred_AuthHandlerRejectsExpiredForgedMalformed` | compile-RED | remove expiry check | same | same |
| TC-04 action binds to authenticated peer | wire + anti-spoof + `relay_turn_credentials_issued_total` delta +1 | integration Go (mocknet) | `turn_action_test.go::TestTurnAction_BindsCredsToAuthenticatedPeer` | behavior-RED: HEAD answers `Unknown action: turn_credentials_get` (inbox.go:2276-2277) | mint from `req.From` instead of stream peer | same | same |
| TC-05 disabled ⇒ TURN_DISABLED (kill-switch) | env gate | integration Go | `…::TestTurnAction_DisabledWithoutSecret` | behavior-RED: HEAD answers `Unknown action` | disabled issuer mints anyway | same | same |
| TC-06 NET-REL-07 byte-identity (PRESERVED) | additive schema | integration Go | `…::TestTurnAction_NonTurnResponsesOmitTurnKeys` | n/a — green on HEAD, locks the omitempty contract after | drop one `omitempty` | same | same |
| TC-07 allocate+STUN+relay echo + metric lifecycle | UDP E2E | integration Go (127.0.0.1) | `turn_server_test.go::TestTurnServer_AllocateAndRelayEcho_WithMintedCreds` | compile-RED | remove gauge Dec in conn Close | same | same |
| TC-08 forged creds can't allocate | auth E2E | integration Go | `…::TestTurnServer_RejectsForgedCreds` | compile-RED | TC-02 mutation end-to-end | same | same |
| TC-09 per-peer mint rate limit | abuse limit | unit Go | `turn_credentials_test.go::TestTurnCred_MintRateLimitPerPeer` | compile-RED | global instead of per-peer bucket | same | same |
| TC-10 global allocation cap (+release re-check) | abuse limit | integration Go | `turn_server_test.go::TestTurnServer_GlobalAllocationCap` | compile-RED | remove cap check in AllocatePacketConn | same | same |
| TC-11 env config defaults/overrides/disabled | config | unit Go | `…::TestTurnServer_ConfigFromEnv` | compile-RED | enable with empty secret | same | same |
| TC-12 metric names/labels | metrics contract | unit Go | `…::TestTurnServer_MetricsRegistered` | compile-RED | rename a metric | same | same |
| TC-13 node client sends action + decodes | client wire | integration Go (fake relay) | `go-mknoon/node/turn_credentials_client_test.go::TestTurnCredentialsGet_SendsActionAndDecodes` | compile-RED | send wrong action name | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TurnCredentials' -count=1)` | NEW synthetic path `GO_NODE_TURNCRED` in run_host_test_gates.sh (pattern :144-184) |
| TC-14 old relay ⇒ unsupported, no throw | forward-compat | integration Go | `…::TestTurnCredentialsGet_OldRelayUnknownActionDegradesUnsupported` | compile-RED | map unknown-action to error | same | same |
| TC-15 bridge export envelope | FFI contract | unit Go | `go-mknoon/bridge/bridge_turn_test.go::TestTurnCredentialsBridge_NotInitializedAndShape` | compile-RED | bare string instead of errJSON | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TurnCredentialsBridge' -count=1)` | NEW synthetic path `GO_BRIDGE_TURNCRED` in run_host_test_gates.sh |
| TC-16 Dart cmd map | bridge routing | unit Dart | `test/core/bridge/go_bridge_client_test.dart::turn:credentials calls turnCredentialsGet with payload JSON` | behavior-RED: unknown cmd rejected by `_CmdSpec` map | remove the map entry | `./scripts/run_test_gates.sh 1to1` (capture green baseline at execution start) | already in `ONE_TO_ONE_TESTS` (run_test_gates.sh:66); AUTO-glob core-host-all |
| TC-17 helper parse + unsupported degrade | client parsing | unit Dart | `test/core/bridge/p2p_bridge_client_turn_test.dart::callP2PTurnCredentials parses creds and degrades unknown-action to unsupported` | compile-RED (helper absent) | unknown-action throws | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (glob, `test/core/bridge/`); verify `./scripts/run_test_gates.sh completeness-check` |
| TC-18 move gate first-line (rule 4) | account-migration safety | unit Dart | `test/core/services/p2p_service_impl_turn_credentials_test.dart::fetchTurnCredentials is move-gated FIRST (no bridge call when denied)` | compile-RED (method absent) | gate after bridge call | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (glob, `test/core/services/`) |
| TC-19 cred cache TTL lifecycle | derived-state | unit Dart | `…::cached creds are reused within 80% of TTL and re-fetched after` | compile-RED | cache without expiry check | same | AUTO (glob) |
| TC-20 device fetches live creds (real bridge) | device + live relay | device-proof | `integration_test/turn_credentials_live_proof_test.dart::VC-03 device fetches live TURN creds through the real bridge` | behavior-RED pre-code/pre-deploy (unknown cmd / unsupported) | TC-16/17/18 mutations end-to-end | `flutter test integration_test/turn_credentials_live_proof_test.dart -d <serial>` (post-deploy) | run_test_gates.sh proof auto-branch (:1036-1039) + NEW classify_path case in check_reliability_simulation_discovery.sh (`record "1to1" … "test"`); verify both scripts |
| TC-21 live probe E2E vs deployed EC2 (**PROD-CRITICAL**) | production wire leg | live-relay probe | `go-relay-server/turn_live_probe_test.go::TestTurnLiveProbe_EndToEnd` | behavior-RED pre-deploy (Unknown action; nothing on UDP 3478) | run against rolled-back binary (R9) | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 TURN_LIVE_PROBE=1 go test -run '^TestTurnLiveProbe' -count=1 -v)` — runbook R7, operator action, never a CI gate | env-guarded skip by default; documented as runbook step R7 (deliberate non-gate, 173 plan:160 precedent) |
| PRESERVE relay suite | full module | gate | `go test ./... -count=1` (go-relay-server) | n/a (green) | n/a | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` — capture green baseline at execution start | existing `run_relay_all_go_gate` (`all` gate :1156) + `make test` |
| PRESERVE Dart 1:1 + bridge pins | cmd map, service | gate | existing `go_bridge_client_test.dart` / `p2p_bridge_client_test.dart` / `p2p_service_impl_test.dart` suites | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` — capture green baseline at execution start | already in `ONE_TO_ONE_TESTS` |
| PRESERVE unknown-action contract | wire contract | gate | `go-relay-server/protocol_contract_test.go` | n/a (green) | n/a | inside relay `./...` run above | existing |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** two derived states exist. (a) Dart cred cache — RAM-only by design (creds are short-TTL secrets; persisting them would be a liability, not durability); reconstruction is a re-fetch — **TC-19** asserts re-fetch after expiry and after impl re-construction. (b) TURN allocations — in-memory per RFC 5766 (clients refresh); a relay restart drops them and the **ICE-restart recovery is VC-09's row**, documented not silently assumed. Additionally the kill-switch state is re-derived from env at every boot (TC-05/11).
- **Sibling-surface consistency:** the new network primitive gets the same `_allowsAccountNetworkSideEffects` first-line gate as ALL its siblings (`p2p_send_message` :2339, `p2p_get_presence` :5114, `p2p_peer_ping` :5212 …) — **TC-18** test-locks it; the relay action gets the same additive omitempty schema discipline as `presence_get` — **TC-06**; the bridge export gets the same errJSON envelope as every sibling — **TC-15**.
- **Destructive-action side-effects:** allocation teardown — **TC-07** asserts `relay_turn_allocations_active` returns to 0 and the relay port is freed (third allocation in **TC-10** succeeds after release), i.e. what is removed (allocation, port, gauge count) and what is preserved (server keeps serving; metrics totals monotone).
- **Invariant re-verification under new transitions:** (a) cap-release transition — **TC-10** re-verifies a fresh allocation succeeds *and* the cap still holds for a fourth concurrent one; (b) disabled→enabled env transition — **TC-05 + TC-11** lock both polarities and TC-06 proves the enabled path leaves every non-TURN action byte-identical; (c) cache-expiry transition — **TC-19** re-verifies a full re-mint (not a partial stale merge).

---

## Invariants (locked by tests)

- INV-1 **Creds bind to the authenticated stream peer; caller-supplied identities are ignored** → TC-04 (+ device-side TC-20 username==own peerId).
- INV-2 **Expired or forged credentials never authenticate, and every rejection is counted** → TC-03, TC-08.
- INV-3 **Kill-switch: no secret ⇒ no TURN listener, action answers TURN_DISABLED, `relay_turn_enabled`=0; revert path = restart without env** → TC-05, TC-11 (VC-00 rule 3).
- INV-4 **Non-TURN relay behavior is byte-identical (NET-REL-07 additive contract)** → TC-06 + preserved relay suite.
- INV-5 **Allocation lifecycle is observable and bounded: totals monotone, active gauge returns to 0, global cap enforced, per-peer mints rate-limited** → TC-07, TC-09, TC-10, TC-12.
- INV-6 **The new client primitive is move-gated first-line** → TC-18 (VC-00 rule 4).
- INV-7 **Old-relay forward-compat: unknown action degrades to `unsupported`, never a thrown error** → TC-14, TC-17.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

---

## Step-By-Step Implementation Plan

0. **Snapshot** `git status --short` (dirty-tree preservation — do not revert/absorb unrelated dirt); capture green baselines: relay `go test ./... -count=1` pass count, `./scripts/run_test_gates.sh 1to1`, `core-host-all` (VC-00 rule 6 — never hardcode counts).
1. **RED — per-slice, not one batch.** Author each slice's RED rows immediately before its GREEN step, using the matching Acceptance-Gates RED command as the per-slice failure proof: TC-11 before Step 3; TC-01/02/03/09 before Step 4; TC-12 before Step 5; TC-07/08/10 before Step 6; TC-04/05/06 before Step 7 (TC-06 must be GREEN already — preservation lock); TC-13/14/15 before Step 8; TC-16..19 before Step 9. Record each failure reason (compile-RED vs `Unknown action` vs unknown-cmd) as it fires. Rationale: downstream client tests (TC-13..20) depend on interface shapes Steps 3-7 may still adjust — batch-authoring the whole catalog up front would invite a mid-plan test-rewrite wave if Step 6's stop-if fires.
2. **go.mod promotion**: move `github.com/pion/turn/v2 v2.1.6` from the indirect block to `require` proper in `go-relay-server/go.mod`; `go mod tidy` must produce **zero go.sum changes** (version already pinned) — if go.sum churns, STOP and investigate skew before proceeding.
3. **`turn_config.go`** (TC-11 green): `TurnConfig` struct + `loadTurnConfigFromEnv(serverCfg)` with the defaults in Real Scope §3, `Enabled` false when secret empty.
4. **`turn_credentials.go`** (TC-01/02/03/09 green): `mintTurnCredentials`, `TurnCredentialIssuer` (secret, ttl, per-peer token buckets, injected clock), `authHandler()` returning a `turn.AuthHandler` closure that validates and returns `turn.GenerateAuthKey(username, realm, credential)`; failure paths bump `relay_turn_auth_failures_total`.
5. **`metrics.go` additions** (TC-12 green): the six `relay_turn_*` promauto vars, `relay_` prefix + Help text per convention.
6. **`turn_server.go`** (TC-07/08/10 green): `startTurnServer(cfg, issuer)` — `net.ListenPacket("udp4", ":<port>")`, `turn.NewServer(turn.ServerConfig{Realm, AuthHandler: issuer.authHandler(), PacketConnConfigs: []turn.PacketConnConfig{{PacketConn: listener, RelayAddressGenerator: newCountingAllocator(inner, cfg.MaxActiveAllocations)}}})` where `inner` = `turn.RelayAddressGeneratorPortRange{RelayAddress: cfg.PublicIP, Address: "0.0.0.0", MinPort, MaxPort}`; the counting allocator wraps `AllocatePacketConn` (cap check + counters) and the returned conn (bytes + gauge Dec on Close). Stop-if: pion/turn v2's server API surface deviates from this sketch on the pinned version → adjust the wrapper seam, do NOT upgrade the module to route around it (that is a replan).
7. **`inbox.go` + `main.go` wiring** (TC-04/05 green, TC-06 stays green): additive `inboxResponse` fields; `case "turn_credentials_get": resp = handleTurnCredentialsGet(s.Conn().RemotePeer(), turnIssuer)` (named handler, FDC-08 rule); thread `*TurnCredentialIssuer` through `HandleInboxStream` (update main.go:135 closure + `setupInboxStreamEnv` inbox_test.go:86 — the single test constructor; the env's disabled-issuer constructor sets the gauge to 0 via the same set-site); `main()` builds cfg+issuer (`NewTurnCredentialIssuer` is the **single `relay_turn_enabled` set-site** — main() never touches the gauge), `startTurnServer` when enabled, logs `[TURN] serving STUN/TURN on :3478 (realm mknoun.xyz)` or `[TURN] disabled (TURN_SHARED_SECRET unset)` (bracketed-prefix log convention).
8. **Node + bridge (Go)** (TC-13/14/15 green): `go-mknoon/node/turn.go` `TurnCredentialsGet()` (relay-selector rollover, definitive-reply semantics); additive response fields in `go-mknoon/node/inbox.go:53-69`; `go-mknoon/bridge/bridge_turn.go` export.
9. **Dart** (TC-16/17/18/19 green): cmd-map entry, `callP2PTurnCredentials`, `TurnCredentials` model, `P2PService.fetchTurnCredentials()` abstract + gated/cached impl, fake updates. Then native dispatch: `GoBridge.kt` + `GoBridge.swift` cases.
10. **Gomobile rebuild + device leg**: `cd go-mknoon && make android` (Makefile:40-42, GOTOOLCHAIN-pinned) → `android/app/libs/GoMknoon.aar`; run TC-20 pre-deploy expecting the documented `unsupported` RED; it closes post-deploy (step 13). iOS: `make ios` where a macOS rig exists; otherwise the Swift dispatch case lands code-reviewed and device evidence is **deferred-not-waived** (VC-00 rule 1).
11. **Harness registration** (VC-00 rule 6): three synthetic Go paths in `run_host_test_gates.sh` (`GO_RELAY_TURN_TEST="go-relay-server/turn_server.go"` + `GO_RELAY_TURN_RUN='^TestTurn'` with `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run "$GO_RELAY_TURN_RUN" -count=1)`; `GO_NODE_TURNCRED_TEST` + RUN `'TurnCredentials'`; `GO_BRIDGE_TURNCRED_TEST` + RUN `'TurnCredentialsBridge'`) — each needs the matcher func + `print_command_for_path` AND `run_path` branches (:394-466); classify_path case in `check_reliability_simulation_discovery.sh` for the proof test; update `test-gate-definitions.md` + `test-gates-reference.md` + `_current-test-map.md` together. Verify: `./scripts/run_host_test_gates.sh host-all --list | grep -i turn`, `./scripts/run_test_gates.sh completeness-check`, `./scripts/check_reliability_simulation_discovery.sh`.
12. **DEPLOY GO/STOP checkpoint** (recorded as its own Execution Progress row before R1): all host gates + registration checks green at their execution-start baselines; VC-01 coordination confirmed (whose relay tree is HEAD — one redeploy per landed story); R0 preflight output reviewed. Only an explicit GO recorded in Execution Progress authorizes Step 13.
13. **EC2 redeploy + live verification** — runbook R1–R9 below (rule 2). Coordinate with VC-01: land on the current committed relay tree; one redeploy per landed story, never a combined untested binary (VC-00 collision map).
14. **Re-run** direct GREEN → preservation → named gates → mutation re-RED spot-checks (one per INV) → hygiene.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| Credential spoofing (mint for someone else) | TC-04 (authenticated-stream binding) + TC-20 (device sees own peerId) |
| Open-relay abuse (anyone allocates forever) | TC-03/08 (auth), TC-09 (mint rate), TC-10 (global cap), 10-min TTL (TC-01/11) |
| Relay bandwidth blowout — each relayed call ≈ 2× media bitrate through EC2 | documented in NOTES.md appendix (step 9 of scope); **capacity bound: `TURN_MAX_ACTIVE_ALLOCATIONS=64` caps worst-case relayed load at ~64 × 2.5 Mbps ≈ 160 Mbps ≤ instance egress — the cap IS the MVP capacity decision, revisit before VC-05 GA**; `relay_turn_relayed_bytes_total` + Grafana make it observable (TC-07/12); alert thresholds are ops follow-up (VC-09) |
| pion/turn version skew vs libp2p's pinned pion stack | dependency decision (keep v2.1.6); go.sum-unchanged check in Step 2 |
| UDP 3478 / relay range blocked by EC2 security group (silent live failure) | runbook R5 (manual SG op) + R7 live probe fails loudly if unreachable |
| Relay restart drops active allocations mid-call | RFC-inherent; ICE-restart recovery owned by VC-09 (documented, not waived) |
| `HandleInboxStream` signature change ripples | single test constructor `setupInboxStreamEnv` (inbox_test.go:86) + main.go:135 — both named in Step 7; full relay suite is the sentinel |
| Go 1.26 toolchain panic (quic-go) | every Go command in this plan pins `GOTOOLCHAIN=go1.25.0` (VC-00 rule 6) |
| Wake-token gate interaction | none — `turn_credentials_get` is not a store/push path; wake-token gate (wake_token_store.go:34) untouched |
| Metrics global-var test flake (parallel tests sharing counters) | counter assertions are **delta-reads** (before/after) per test shape TC-03/04/08; gauge assertions (TC-05 reads 0 after a forced 1, TC-07 active 1→0, TC-10) are **absolute** — those tests must NOT use `t.Parallel()` and must run against a freshly-constructed issuer/server so the gauge state is theirs |

---

## Device/Relay Proof Profile

**Requires device + live relay for closure** (not host-only): host tiers close the code contract; VC-00 rule 2 makes the deployed-relay live probe (TC-21) and rule 1 makes the Android device leg (TC-20) part of Done.

- Closure scenario: runbook R7 (live probe) + `flutter test integration_test/turn_credentials_live_proof_test.dart -d <androidSerial>` and `-d <emulatorId>` post-deploy.
- Deferred device work → iOS: `GoBridge.swift` dispatch case lands in this story; CallKit-era device evidence belongs to VC-07's macOS/iPhone session (deferred-not-waived — the proof test prints the iOS recipe and is run only on the Android matrix here).
- Relay defaults: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (run_test_gates.sh:568).

---

## Execution Environment  (VC-00 rule 1 — restated)

The implementing AI agent runs the full loop end-to-end on a **USB-connected Android device + Android emulator(s)**. iOS simulators/devices are NOT part of this rig.

```bash
# 1. Discover devices (USB device serial + emulator id)
adb devices                      # e.g. 21071FDF600CSC (USB), emulator-5554

# 2. Host tiers (no device needed) — Go + Dart RED/GREEN loops
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestTurn' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TurnCredentials' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TurnCredentialsBridge' -count=1)
flutter test test/core/bridge/go_bridge_client_test.dart test/core/bridge/p2p_bridge_client_turn_test.dart test/core/services/p2p_service_impl_turn_credentials_test.dart

# 3. Rebuild the Go bridge AAR after Go changes (required before any device leg)
(cd go-mknoon && make android)   # GOTOOLCHAIN-pinned in the Makefile; outputs android/app/libs/GoMknoon.aar

# 4. Device legs (single-party — VC-03 needs no two-party orchestrator; run the
#    SAME proof on both rig members, POST-DEPLOY only):
flutter test integration_test/turn_credentials_live_proof_test.dart -d 21071FDF600CSC
flutter test integration_test/turn_credentials_live_proof_test.dart -d emulator-5554
# USB device on cellular/hotspot is optional here (cred fetch is network-agnostic);
# the different-networks requirement bites in VC-05's ICE proof, not VC-03.

# 5. Two-party convention (NOT used by VC-03; recorded for uniformity, VC-00 rule 1):
#    orchestrators take -d <serialA>,<serialB>, e.g.
#    dart integration_test/scripts/run_1to1_device_real.dart --scenario <id> -d 21071FDF600CSC,emulator-5554

# 6. iOS boundary: deferred-not-waived — GoBridge.swift case lands code-only; the proof
#    test prints the iOS run recipe and Android evidence closes this story (VC-07 owns iOS device proof).
```

---

## EC2 Redeploy & Live Verification  (VC-00 rule 2 — restated; this story is NOT done until R7 passes against the deployed instance)

Grounded in the digest-verified 142 flow (`142-relay-media-push-payload-too-large-tdd-plan.md:141-150`; systemd unit `relay-server`, README.md:1-39; SSH key `../se.pem`, user `ubuntu@mknoun.xyz`). Steps absent from any repo runbook are marked **NEW**. Deploy-timing rule: one relay change per deploy (173 plan:156); coordinate with VC-01's redeploy — whichever lands second builds on the other's committed tree.

```bash
# R0 (NEW) — on-box preflight: inspect live env (repo cannot see it — relay-ops digest gap)
ssh -i se.pem ubuntu@mknoun.xyz 'systemctl cat relay-server; ls /etc/systemd/system/relay-server.service.d/ 2>/dev/null'

# R1 — cross-compile (repo root)
cd go-relay-server && GOOS=linux GOARCH=amd64 go build -o relay-server-linux-amd64 .

# R2 (NEW) — retain rollback artifact BEFORE overwrite (previous binary kept — rule 2)
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo cp /usr/local/bin/relay-server /usr/local/bin/relay-server.prev-vc03'

# R3 — ship + install (the 142 flow)
scp -i ../se.pem relay-server-linux-amd64 ubuntu@mknoun.xyz:/tmp/relay-server
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /tmp/relay-server /usr/local/bin/relay-server'

# R4 (NEW) — TURN env via systemd drop-in (documented unit sets only FIREBASE_SERVICE_ACCOUNT, README.md:21)
ssh -i ../se.pem ubuntu@mknoun.xyz "sudo mkdir -p /etc/systemd/system/relay-server.service.d && \
  printf '[Service]\nEnvironment=TURN_SHARED_SECRET=%s\n' \"\$(openssl rand -hex 32)\" | \
  sudo tee /etc/systemd/system/relay-server.service.d/turn.conf >/dev/null && sudo chmod 600 /etc/systemd/system/relay-server.service.d/turn.conf && sudo systemctl daemon-reload"
# (defaults suffice for port/realm/IP/range; record the secret in the ops vault, NOT in the repo)

# R5 (NEW, MANUAL OPERATOR STEP) — EC2 security group: no IaC exists in the repo (verified absence).
# In the AWS console / aws-cli for the instance's SG, add inbound rules:
#   UDP 3478        0.0.0.0/0   (STUN/TURN control)
#   UDP 49152-65535 0.0.0.0/0   (TURN relay allocation range)
# Verification (on-box listener + from-outside reachability):
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo ss -ulpn | grep -E ":3478"'   # listener up after R6
# From the workstation, R7's STUN binding leg is the definitive outside-in check.

# R6 — restart + sanity (the 142 flow) + TURN boot log
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo systemctl restart relay-server && systemctl is-active relay-server && /usr/local/bin/relay-server version'
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 80 --no-pager | grep -E "TURN|METRICS"'
# ASSERTIVE check (non-zero exit on miss — do not tick R6 by eyeball):
ssh -i ../se.pem ubuntu@mknoun.xyz 'journalctl -u relay-server -n 80 --no-pager | grep -q "\[TURN\] serving"'
# expect: "[TURN] serving STUN/TURN on :3478 (realm mknoun.xyz)"

# R7 — LIVE PROBE (the rule-2 gate; PROD-CRITICAL leg TC-21; needs NO secret — creds come from the action)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 TURN_LIVE_PROBE=1 go test -run '^TestTurnLiveProbe' -count=1 -v)
# expect: PASS — creds fetched over libp2p from the deployed relay, STUN binding OK,
#         allocation OK at mknoun.xyz:3478, one packet relayed end-to-end.

# R8 — metrics scrape shows the probe's allocation (:2112 is localhost-only by SG policy — scrape on-box)
ssh -i ../se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep -E "^relay_turn"'
# ASSERTIVE checks (each exits non-zero on miss — the Done checkbox may not be ticked by inference):
ssh -i ../se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep -q "^relay_turn_enabled 1"'
ssh -i ../se.pem ubuntu@mknoun.xyz "curl -s localhost:2112/metrics | awk '/^relay_turn_credentials_issued_total/{f=1; exit (\$2>=1)?0:1} END{if(!f) exit 1}'"
ssh -i ../se.pem ubuntu@mknoun.xyz "curl -s localhost:2112/metrics | awk '/^relay_turn_allocations_total/{f=1; exit (\$2>=1)?0:1} END{if(!f) exit 1}'"
# expect: relay_turn_enabled 1; relay_turn_credentials_issued_total >= 1;
#         relay_turn_allocations_total >= 1; relay_turn_relayed_bytes_total{...} > 0

# R9 — ROLLBACK (if any of R6–R8 fail): previous binary retained in R2
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo install /usr/local/bin/relay-server.prev-vc03 /usr/local/bin/relay-server && sudo systemctl restart relay-server && systemctl is-active relay-server'
# (the committed go-relay-server/relay-server-linux-amd64 is the de-facto second-layer rollback artifact)
# Optional kill-switch-only rollback (keeps new binary, disables TURN — INV-3):
ssh -i ../se.pem ubuntu@mknoun.xyz 'sudo rm /etc/systemd/system/relay-server.service.d/turn.conf && sudo systemctl daemon-reload && sudo systemctl restart relay-server'
```

---

## Metrics Ownership  (VC-00 metrics table row: "TURN allocations, active relayed calls, relayed bytes | VC-03 pion/turn hooks | relay Prometheus")

| Metric | Vehicle (this plan) | Named test / runsheet step |
|---|---|---|
| TURN allocations (total) | `relay_turn_allocations_total` (counting allocator) | TC-07; live: R8 |
| Active relayed allocations (proxy for active relayed calls until VC-09 adds per-call labels) | `relay_turn_allocations_active` gauge | TC-07 (1→0 lifecycle), TC-10; live: R8 |
| Relayed bytes | `relay_turn_relayed_bytes_total{direction}` | TC-07; live: R8 |
| Auth failures (abuse signal) | `relay_turn_auth_failures_total` | TC-03, TC-08 |
| Credential mints (client adoption signal) | `relay_turn_credentials_issued_total` | TC-04; live: R8 |
| TURN enabled (ops kill-switch visibility) | `relay_turn_enabled` gauge | TC-05/11; live: R6/R8 |

Name/label contract locked by TC-12. Grafana panel additions ride the existing dashboard JSONs (ops follow-up, non-blocking; access per `Testing-Tracking/Grafana.md`).

---

## Working Piece On Close

A demonstrable, self-contained capability exists when VC-03 closes — nothing about it depends on any other VC story:

1. **The production relay at `mknoun.xyz:3478/udp` serves STUN and TURN.** Anyone on the team can prove it in one command: runbook R7 (`TURN_LIVE_PROBE=1 go test -run '^TestTurnLiveProbe'`) fetches ephemeral creds over the live libp2p relay protocol, gets a STUN mapped address, allocates a TURN relay, and echoes a packet through it — end-to-end against EC2, no local secret required.
2. **Any app peer can mint working credentials through the full production stack**: Dart `fetchTurnCredentials()` → `turn:credentials` bridge cmd → gomobile → `Node.TurnCredentialsGet()` → live relay `turn_credentials_get` action — proven on the USB Android device AND the emulator (TC-20), move-gated, cached, and forward-compatible with old relays.
3. **The rollout is observable and reversible**: `relay_turn_*` metrics live on :2112 (R8 scrape shows the probe's allocation), abuse-bounded (per-peer mint rate, global allocation cap, 10-min TTL), and kill-switchable (drop the env drop-in → TURN off, relay otherwise byte-identical; previous binary retained).

VC-05 builds on this by passing `uris` + creds straight into `RTCPeerConnection.iceServers`; VC-04 needs nothing from it. This piece is comfortable to build on because its contract is locked by TC-04/05/06 (wire), TC-16/17/18/19 (client API), and TC-21 (production).

---

## Acceptance Gates  (LITERAL — copy/paste; counts: capture green baseline at execution start, VC-00 rule 6)

```bash
# RED (before production edits) — each must FAIL for its documented reason
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestTurn' -count=1)          # compile-RED / Unknown action
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TurnCredentials' -count=1)         # compile-RED
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run 'TurnCredentialsBridge' -count=1) # compile-RED
flutter test test/core/bridge/go_bridge_client_test.dart --plain-name 'turn:credentials calls turnCredentialsGet with payload JSON'  # unknown cmd

# Direct GREEN (after implementation) — same four commands, 0 fail, plus:
flutter test test/core/bridge/p2p_bridge_client_turn_test.dart
flutter test test/core/services/p2p_service_impl_turn_credentials_test.dart

# Preservation sentinels (capture green baselines at execution start; must match at close)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)     # full relay module
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Registration verification (VC-00 rule 6)
./scripts/run_host_test_gates.sh host-all --list | grep -i turn         # 3 synthetic Go paths present
./scripts/run_test_gates.sh completeness-check                          # new Dart tests all classify
./scripts/check_reliability_simulation_discovery.sh                     # proof test classified, no unclassified candidates

# Device legs (post-deploy; serials from `adb devices`)
flutter test integration_test/turn_credentials_live_proof_test.dart -d <androidSerial>
flutter test integration_test/turn_credentials_live_proof_test.dart -d <emulatorId>

# Live gate (rule 2) — runbook R7 + R8
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 TURN_LIVE_PROBE=1 go test -run '^TestTurnLiveProbe' -count=1 -v)
ssh -i se.pem ubuntu@mknoun.xyz 'curl -s localhost:2112/metrics | grep -E "^relay_turn"'

# Hygiene
flutter analyze            # 0 new (repo baseline: scripts/check_flutter_analyze_baseline.sh)
git diff --check
(cd go-relay-server && make lint)   # gofmt + go vet + golangci-lint --new-from-rev
```

---

## Known-Failure Interpretation

- **Expected RED (pre-implementation):** all `^TestTurn*`/`TurnCredentials*` commands and the Dart cmd-map/new-file tests, each for the reason documented in its catalog row.
- **Expected RED (post-implementation, pre-deploy):** TC-20 device proof (`unsupported` from the old deployed relay) and TC-21 live probe — these close only after runbook R6; they are sequencing, not product failures.
- **Environment blocker (NOT product):** no USB device / no emulator (`adb devices` empty) blocks TC-20 only; `se.pem` absent or no SG access blocks R2–R9 only — record and hand to the operator, do not fake.
- **Pre-existing dirty tree:** snapshot at Step 0 (`git status --short`, currently substantial on `new-orbit`); never revert/absorb/reformat unrelated dirt (257-plan convention).
- **Scope drift (BLOCKING):** any failure in `limits.go`-adjacent circuit tests (VC-01 territory), push closure tests (`^TestRelayNotificationClosure_`), or presence tests means VC-03 leaked outside its seams — stop and fix, do not migrate those tests.
- **go.sum churn at Step 2** = version-skew alarm, not a formality — STOP.

---

## Done Criteria

- [ ] RED catalog added first; every row failed for its documented reason (compile-RED rows re-verified behaviorally via their mutations after GREEN).
- [ ] Mutation-verified: each INV-1..7 mutation re-reds its named test.
- [ ] Direct GREEN + preservation sentinels (relay `./...`, `1to1`, `core-host-all`, `feature-host-all`) match execution-start baselines.
- [ ] pion/turn/v2 v2.1.6 direct in go.mod with zero go.sum churn.
- [ ] Harness registration done & verified: 3 synthetic Go paths listed by `host-all --list`; `completeness-check` green; discovery script green; gate docs quartet updated (rule 6).
- [ ] Gomobile AAR rebuilt (`make android`); TC-20 green on USB device AND emulator (rule 1) — fetch-only by design; device-side TURN allocation is VC-05's ICE proof.
- [ ] **EC2 redeployed per runbook; R7 live probe green against mknoun.xyz:3478; R8 metrics scrape shows the allocation; rollback binary retained (rule 2).**
- [ ] Kill-switch verified live-adjacent: `relay_turn_enabled` gauge correct in R8; disabled path test-locked (TC-05).
- [ ] **Rule-2 rider recorded for successor stories**: every subsequent relay redeploy runbook (VC-01, VC-04+) must include the R8 assertive one-liner `curl -s localhost:2112/metrics | grep -q "^relay_turn_enabled 1"` as a post-restart check until VC-09 lands a Grafana alert on `relay_turn_enabled==0` — a deleted `turn.conf` drop-in or dropped SG rule is otherwise silent with all repo gates green.
- [ ] Bandwidth-cost appendix added to `go-relay-server/NOTES.md` (~2× media bitrate per relayed call + SG/port documentation).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; `make lint` clean; no Scope Guard violations.

---

## Scope Guard (hard "Do not")

- Do NOT touch `go-relay-server/limits.go` or any circuit-relay resource limit — **VC-01** owns it (collision map: coordinate the shared `main.go` edits and sequence the redeploys, one per landed story).
- Do NOT add `call_*` envelope types, router cases, or any `lib/features/call/` code — **VC-04/VC-05**.
- Do NOT add flutter_webrtc, ICE agent config, or any consumer of the creds beyond the fetch API — **VC-05**.
- Do NOT touch push metadata extraction, `buildPushMessage`, or APNs/FCM paths — **VC-06/VC-07**.
- Do NOT upgrade pion/turn to v3/v4 or bump any other module; do NOT add pion deps to go-mknoon (the probe client lives in go-relay-server, which already has turn/v2 pinned).
- Do NOT refactor `HandleInboxStream`'s inherited switch (named-handler rule only — one delegating case).
- Do NOT run the live probe or redeploy inside any test gate (operator action only, 173 plan:160).
- Do NOT commit the TURN shared secret, `se.pem`, or any live-env values to the repo.

---

## Accepted Differences / Intentionally Out Of Scope

- **Per-username active-allocation accounting** is approximated (per-peer *mint* rate limit + global allocation cap) because pion/turn **v2** lacks per-allocation username callbacks; exact per-username caps arrive with a turn/v4 upgrade if VC-09 hardening needs them — deliberate trade for zero new supply-chain modules.
- **TURN-over-TCP/TLS:443 fallback** (for UDP-hostile networks) deferred to VC-09 — UDP 3478 covers the MVP matrix; the config surface (port/realm/IP env) is forward-compatible.
- **Creds fetch is not wired into any caller** — VC-05 consumes `fetchTurnCredentials()`; shipping it inert is the client-side kill-switch posture (rule 3): no runtime behavior change until VC-05.
- **`relay_turn_allocations_active` proxies "active relayed calls"** until VC-09 adds call-scoped metrics — one allocation ≈ one relayed party.
- **iOS device evidence deferred-not-waived** — Swift dispatch lands, VC-07's rig proves it (rule 1).
- **Metrics :2112 exposure** stays as-is (localhost/SG-private per production-stack-layer-audit recommendation); scrapes go over ssh.

---

## Dependency Impact

- **VC-05 (foreground audio call) depends on this** — contract: `P2PService.fetchTurnCredentials()` returns `{username, credential, ttlSeconds, uris}` or null (gate-denied/unsupported/unreachable); `uris` = `["turn:mknoun.xyz:3478?transport=udp", "stun:mknoun.xyz:3478"]` feed `RTCPeerConnection.iceServers` verbatim. VC-05 must handle null (STUN-less direct-only attempt or user-visible failure).
- **VC-09 (reliability/metrics hardening) depends on this** — extends `relay_turn_*` metrics and owns the "always relay" privacy toggle + ICE-restart-after-relay-bounce behavior + possible turn/v4 upgrade.
- **VC-01 collision** — shared `go-relay-server/main.go` service wiring + the one-redeploy-per-story rule: whichever of VC-01/VC-03 lands second rebases onto the other's committed relay tree (VC-00 collision map). **Rule-2 rider (post-VC-03 closure): every later relay redeploy runbook — VC-01 included if it deploys after this story — appends the R8 post-restart assert `curl -s localhost:2112/metrics | grep -q "^relay_turn_enabled 1"` until VC-09's Grafana alert on `relay_turn_enabled==0` exists, so an ops-layer TURN regression cannot pass silently.**
- No migration, no schema change, no l10n, no feature-flag file edits (`feature_flags.go`/`p2p_bridge_client.dart` flag map untouched — the TURN kill-switch is relay-env-side, so no polarity-pin rebase for VC-02).

---

## Reviewer Findings

**(/tdd-review verdict, applied 2026-07-13)**

Dimension scores (all "strong"): goal-clarity 86, compartmentalization 78, anti-drift 87, define-good 84, goal-verification 82. Assessment counts: 0 material, 5 moderate, 6 nits — all applied. Salvaged factual-verifier findings: 20/22 claim clusters confirmed on source; 2 refuted details + 2 minor cite drifts — all applied. Domain verifier (VC-09 salvage): 10/10 claims confirmed, 0 material errors (pion/turn v2.1.6 API, TURN-REST pattern, counting-allocator seam, zero-go.sum-churn, EC2 1:1-NAT pattern all source/pkg-verified).

Applied fixes:
- **Moderate (assessment)**: capacity criterion added (64-allocation cap ≈ 160 Mbps worst case named as the MVP capacity decision — Real Scope §9 + Risks); Step 1 rewritten from batch-RED to per-slice RED authoring folded into Steps 3-9; `relay_turn_enabled` set-site pinned to `NewTurnCredentialIssuer` with TC-05 proving the set (1→0) not the zero default; TC-04 now delta-asserts `relay_turn_credentials_issued_total` +1 (host-tier proof, no longer R8-only); rule-2 rider added for successor relay redeploys (post-restart `relay_turn_enabled 1` assert until VC-09's Grafana alert).
- **Nits (assessment)**: fetch-only boundary stated in Done Criteria; DEPLOY GO/STOP checkpoint inserted as Step 12; gauge-vs-counter delta-read caveat (no `t.Parallel()`); payloadCmds cite unified to :163-211; R6/R8 made assertive (`grep -q`/awk exit codes); TC-20 gains the device-side wire-encoding lock (base64std credential + `<futureUnix>:<ownPeerId>` parse).
- **Salvaged verifier corrections (source-verified this session)**: `_allowsAccountNetworkSideEffects` cite restored to `p2p_service_impl.dart:555-572` — the digest was right and the plan's earlier ":554" "correction" was itself the off-by-one; TC-21 dial addr corrected to `/ip4/13.60.15.36/tcp/4005` (the actually-announced plain-TCP multiaddr, main.go:57 — `/dns4/mknoun.xyz/tcp/4005` is dialable but NOT in the announce set, and a do-not-reintroduce note added); server_config cites fixed (`loadServerConfigFromEnv` :71-96, ServerDNS :60); TC-07/TC-21 reworded to drop the nonexistent exported v2 client `CreatePermission` — pion/turn v2 mints permissions implicitly on the relay conn's first `WriteTo`; v4 `EventHandler` field name singularized.
- **Contract locks (epic adjudication)**: L3 naming (`turn_credentials_get` / `turn:credentials`) confirmed consistent throughout — this plan is the canonical owner; L4/L1/L2/L6/L7 surfaces untouched by this plan (no limits.go edits, no call_* envelopes, no hole-punch assertions); L5 satisfied as written (no new family array — cmd-map pin rides `ONE_TO_ONE_TESTS`, proof test rides the discovery classify + proof auto-branch).

## Arbiter Decision

Structural blockers: **none**. | Deferred details: exact pion/turn v2 server-config internals may shift within the pinned version — Step 6 carries the stop-if (verified low-probability: the domain pass confirmed every Step-6 symbol on tag v2.1.6); SG rule mechanics are operator-side (R5); live SG state unverifiable from repo (R0/R7 cover it loudly). | Accepted differences: per-username allocation caps (v2 lacks the v4 `EventHandler` callback — approximated by mint rate + global cap), TURN-over-TCP/TLS:443 fallback → VC-09, iOS device evidence deferred-not-waived → VC-07, `relay_turn_allocations_active` as active-calls proxy → VC-09, relay-restart allocation loss (RFC 5766) with ICE-restart recovery → VC-09. One verifier conflict adjudicated: the factual pass says the v2 client exports no `CreatePermission`, the domain pass claimed it does — plan reworded to implicit-permission-on-first-send semantics, which is correct under either reading and matches pion's canonical udp client example.

## Final Execution Verdict

Verdict: (pending — awaiting-review) | Files changed: — | Tests run (+counts): — | Blocking: — | QA verdict: — | Non-blocking follow-ups (owner): Grafana TURN panel (ops), turn/v4 evaluation ("VC-09"), TURN-over-TLS:443 (VC-09).
