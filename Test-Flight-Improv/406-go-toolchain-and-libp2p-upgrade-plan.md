# Plan 406 — Upgrade Go and libp2p while old and new app versions keep talking

Status: DONE 2026-10-08 — merged to main; store build 1.0.1+123 ready (upload pending); production relay v1.11.0 deployed 2026-10-08T16:59:41Z. Open: 24 h relay watch, store rollout. Findings in section 9.
Origin: user request 2026-10-08 — "upgrade to the latest Go while allowing users with multiple versions to talk to one another".

## 1. Problem

We pin Go 1.25.0 everywhere (`go-mknoon/go.mod:3-11`, `go-relay-server/go.mod:3`, `GOTOOLCHAIN` in both Makefiles and about 45 scripts).
The reason is a crash, not a wire incompatibility:

- Go 1.26 changed how `crypto/tls` handles session tickets.
- Our quic-go (app v0.49.0, relay v0.48.2) was written for the old behaviour.
- Built with Go 1.26 or 1.27, the side that ACCEPTS a QUIC connection panics with `crypto/tls bug: where's my session ticket?` and the app dies (SIGABRT).
  The QR contact-add dial hits this every time. `docs/testing/TESTING.md:4159,5087` records that Go 1.27 panics the same way.

Why we cannot stay:

- Go 1.25 got its last security fix (go1.25.14) on 2026-08-19, when Go 1.27.0 came out. `crypto/tls` fixes no longer reach us.
- Both our quic-go versions are affected by CVE-2025-59530 (a crash), fixed only in newer quic-go.

## 2. What the fix needs

quic-go fixed the panic in **v0.57.1** (PR quic-go#5462, issue quic-go#5572). There is no backport to v0.49.
We cannot bump quic-go alone: quic-go v0.53 replaced its `Connection` interface, and go-libp2p pins its own quic-go.
So the real change is a go-libp2p bump.

| Library | App today | Relay today | Target | Note |
|---|---|---|---|---|
| Go | 1.25.0 | 1.25.0 | **1.27.1** | go-libp2p v0.50 needs ≥ 1.26; build Mac needs macOS 13+ |
| go-libp2p | v0.39.1 | v0.38.2 | **v0.50.0** | v0.46.0 is the first that works on Go 1.26 |
| quic-go | v0.49.0 | v0.48.2 | v0.62.0 (via libp2p) | supports Go 1.26 and 1.27 |
| go-libp2p-pubsub | v0.15.0 (fork) | — | **v0.18.0** + our patch | needs go-libp2p ≥ v0.47 |
| go-multiaddr | v0.14.0 (fork) | v0.14.0 | **v0.16.1** + our patch | interface → concrete type (breaking) |
| go-netroute | v0.2.2 (fork) | — | **v0.4.0** + our patch | |
| golang.org/x/mobile | 2024-12-13 | — | latest master (needs Go 1.26) | finds Android SDK `android-36.x` dirs |

Fallback if v0.50.0 blocks us: go-libp2p v0.46.0 on Go 1.26.8. Same steps, smaller API jump, shorter Go support.

## 3. How mixed versions keep working

This is the core of the request. The rule for this plan: **change the libraries, change nothing on the wire that we own.**

1. **Standard protocols stay the same.** QUIC v1, TLS 1.3, Noise, yamux, identify, circuit relay v2 and DCUtR (hole punching) have no documented break between go-libp2p v0.39 and v0.50.
   The only documented break is WebTransport (v0.47+), which we do not use.
2. **libp2p negotiates per connection** (multistream-select). Each side lists what it supports and they pick a common one.
3. **Peers advertise TCP and QUIC.** If one transport fails, the other can still connect.
4. **Our own protocols do not change.** No protocol ID, message format, envelope or relay request changes in this plan. A reviewer rejects any diff that touches them.
5. **We prove it, because upstream does not.** The libp2p interop test matrix only covers go-libp2p v0.46–v0.48 and head. v0.39 is never tested. Section 5 adds our own old-vs-new test.
6. **Roll out in two separate steps** (section 7). The app goes first against today's relay. The relay goes later, after the new app is proven against it. At every moment, each pair of versions in use has been tested.

## 4. Work

### Step 0 — Baseline (no changes)

- New worktree from `main` (never stash /workspace).
- Record green baselines at HEAD: `go test ./...` in `go-mknoon` and `go-relay-server`, `go test -tags integration` in both, `scripts/run_host_test_gates.sh` Go legs.
- Save the current store build (1.0.1+122) APK and IPA as the "old" side for device tests.
- Check: build Mac is on macOS 13+. Check the minimum iOS and Android versions Go 1.27 supports against our deployment targets.

### Step 1 — Red tests first

1. **Panic reproduction (Go test, `go-mknoon/node/`).** Two nodes, node B dials node A directly over QUIC, disconnects, dials again (the second dial uses a session ticket). Assert both dials succeed and node A is alive.
   - Red: run with `GOTOOLCHAIN=go1.27.1` on today's dependencies. Expect the panic.
   - Green: same command after Step 2.
   - Same test in `go-relay-server` against the relay host (the relay also accepts QUIC).
2. **Mixed-version interop harness** (new script `scripts/test/go_mixed_version_interop.sh`, see section 5). It must run red-free on OLD↔OLD before any bump, so we know the harness itself works.

### Step 2 — Bump the app's Go libraries (`go-mknoon`)

1. Re-apply our three forks on the new upstream versions. Keep each patch as small as today.
   - **go-multiaddr → v0.16.1:** re-add the interface-address provider seam from plan 190 (`net/interface_provider.go`, `interface_default_android.go` using `wlynxg/anet`, `interface_default_other.go`, `InterfaceMultiaddrs` calling `currentInterfaceAddrs()`, the `SetInterfaceAddrsProviderForTests` hook). Fixes Android's netlink SELinux denial.
   - **go-netroute → v0.4.0:** re-add `netroute_hook.go` (test failure hook) and the Android `New()` error in `netroute_linux.go`. First check whether v0.4.0 still uses netlink on Android. If it does not, drop that part of the patch. Fix the `go.mod:41-44` comment, which wrongly calls this fork test-only.
   - **go-libp2p-pubsub → v0.18.0:** re-add `limited_conn.go` and its call sites (`comm.go`, `pubsub.go`, `gossipsub.go`, `peer_notify.go`), which let pubsub use relay-circuit connections. First check whether upstream now does this itself. Diff our fork against upstream v0.15.0 to find any other edit we forgot.
   - **stub/gosigar:** check whether go-libp2p v0.50 still pulls gosigar. Remove the stub if not.
2. Update `go.mod`: Go directive, go-libp2p v0.50.0, x/mobile latest, `go mod tidy`.
3. Fix our code for the API changes:
   - `ma.Multiaddr` is now a concrete type. 11 production files use it: `node.go`, `group_inbox.go`, `rendezvous.go`, `nse_inbox.go`, `lan_dial.go`, `connection_diagnostics.go`, `pubsub.go`, `inbox.go`, `relay_selector.go`, `peer_session.go` (+ relay `server_addresses.go`). Replace `== nil` with `len(a) == 0`; never use a multiaddr as a map key (use `.String()`).
   - Stream reset errors: `err == network.ErrReset` → `errors.Is(err, network.ErrReset)`.
   - `autorelay_metrics.go` uses the v0.39 autorelay tracer. Port it to the current one.
   - Identify, observed addresses (`p2p/host/obsaddrs`) and connection manager option changes in `node.go:412-463` and `nse_inbox.go:61`.
   - Note v0.47: `AllAddrs()` now lists every interface address when listening on `0.0.0.0`. Check `AddrsFactory` and our address-visibility tests (plan 190) still filter what we want.
4. `go vet ./...`, `go test ./...`, `go test -tags integration ./...`. The Step 1 panic test turns green.

### Step 3 — Move the toolchain pin

- Replace `go1.25.0` with `go1.27.1` in every active pin. The list (about 45 files) is in the appendix. Do it with one scripted replace, then read the diff.
- Update the contract tests that assert the pin (appendix). Change the expected value; do not loosen the check.
- Pin gomobile to the same x/mobile version as `go.mod` (today it installs `@latest`: `README.md:711`, `android/app/build.gradle.kts:474`).
- `docker/claude-code/Dockerfile:1` → `golang:1.27.1-bookworm`.
- Keep `-ldflags=-checklinkname=0` for Android (still needed for `wlynxg/anet`).

### Step 4 — Build the bindings

- `scripts/ensure_go_ios_bindings.sh` and `ensure_go_android_bindings.sh`. The inputs digest changes, so both rebuild.
- `verify_gomobile_bindings.sh` green. iOS binary gate (`BridgeGenerateIdentity` in the Runner binary) passes.
- Debug and release builds on both platforms, including the iOS notification extension (`nse_lite`).

### Step 5 — Host gates

- Run `graphify-arch/tdd_context.py affected` on the changed Go files and run the named tests first.
- Then `scripts/run_host_test_gates.sh` (Go legs and host-all) and `scripts/run_test_gates.sh`. Known pre-existing reds: only the 13 performance benchmarks.

### Step 6 — Mixed-version interop (section 5) — must be all green before any release.

### Step 7 — Relay (same branch, separate deploy)

The relay's code moves in the same branch as the app, because many pins are shared (sims build env, audio-call fixture, gate runners) and two toolchains side by side would split each of them. The production relay keeps running its current binary until the separate deploy below, so D4 (app first, relay later) is unchanged.

1. Same bumps in `go-relay-server` (go-libp2p v0.50.0, go-multiaddr v0.16.1, Go 1.27.1).
2. **New default rate limit:** go-libp2p v0.42+ limits new connections per IP (1 per 5 s, burst 16). Many phones share one carrier NAT address, so this could block real users. Set `WithConnRateLimiters` explicitly (decision D3).
3. `quic_smoke_test.go` (5 tests), relay integration tests, the Step 1 relay panic test.
4. Interop: run the section 5 matrix against the new relay with OLD and NEW app peers.
5. Deploy with the existing flow (`relay_sftp_put.py` + the deploy script pattern of `deploy_relay_v1109.sh`): check sha, back up the live binary, `install`, restart, check `NRestarts` 3 times. Rollback = reinstall backup + restart.
6. Watch for 24 h: connection counts, reservation counts, `relay_group_inbox_retrieves_total`, error logs, CPU and memory.

## 5. Mixed-version interop test

Use `go-mknoon/cmd/testpeer` built twice:

- **OLD:** from the last commit before Step 2, built with `GOTOOLCHAIN=go1.25.0`.
- **NEW:** from the branch, built with `GOTOOLCHAIN=go1.27.1`.

Also two relays: OLD relay (today's v0.38.2 build) and NEW relay (Step 7 build), both run locally.

For every pair OLD→NEW and NEW→OLD (and NEW→NEW as a control), check:

| # | Path | What passes |
|---|---|---|
| 1 | Direct QUIC dial, twice (session resumption) | both connect; the accepting side does not crash |
| 2 | Direct TCP dial | connects |
| 3 | Relay circuit (OLD relay, then NEW relay) | connects through the relay |
| 4 | Relay → direct upgrade (DCUtR) | upgrade succeeds where it does today on OLD↔OLD |
| 5 | 1:1 message send + ack | received once |
| 6 | Group publish over GossipSub (3 peers: OLD, NEW, NEW) | all members receive, once |
| 7 | Group and 1:1 relay inbox store + retrieve | received |
| 8 | Media upload + download through the relay | bytes match |
| 9 | Identify | each side sees the other's protocols and addresses |

The script exits non-zero on any failure and prints the pair and row.

## 6. Device proof

Phones: Pixel 6 (`21071FDF600CSC`), iPhone 11, iPhone 13, emulators. One side runs the store build 1.0.1+122 (OLD), the other the new build.

For Android↔iOS and Android↔Android, both directions:

- QR contact add (the exact path that crashed).
- 1:1 text, photo, voice note.
- Group text and media with one OLD member.
- Same Wi-Fi (LAN path) and one phone on cellular (relay path).
- App killed on the receiver: push wake still delivers.
- Audio call both ways.

LAN soak: `go.mod:17` says to re-run the FDC-S6 soak on any libp2p bump (decision D2).

## 7. Rollout

1. **App release** (new libraries, today's relay). Normal store rollout. Old and new apps live side by side, which section 5 and section 6 already proved.
2. **Wait** about a week of stable crash and delivery numbers.
3. **Relay upgrade** (Step 7), with the old binary kept for rollback.
4. Rollback: app — ship the previous build number +1 from the old commit. Relay — reinstall the backup binary.

## 8. Decisions (all agreed by the user 2026-10-08)

- **D1 — Go version: 1.27.1.** Supported until Go 1.29 (about Aug 2027). 1.26.8 was rejected: supported only until Go 1.28 (about Feb 2027).
- **D2 — LAN soak: no full FDC-S6 soak.** It needs ≥ 385 sends per platform direction and was built to decide WebSocket retirement, not as a bump check. Replaced by the section 5 matrix plus a short device LAN run (about 50 sends each way). Update the `go-mknoon/go.mod:17` comment to say so.
- **D3 — Relay per-IP rate limit: raise it, do not turn it off.** Set `WithConnRateLimiters` well above carrier NAT load (starting point 20 per second, burst 200) and add a metric for rejected connections.
- **D4 — Order: app first, then relay.** As in section 7.

## 9. Findings during execution

1. **Android QUIC crash in go-libp2p v0.50 (fixed in our netroute fork).** `quicreuse.defaultSourceIPSelectorFn` ignores the error from `netroute.New()` and wraps the nil router anyway, so the first QUIC dial panics. Our Android patch made `New()` return an error, so every QUIC dial on Android would have crashed. The fork now returns a router whose every lookup fails instead (`failingRouter`, `third_party/go-netroute/netroute_hook.go`). Same for the test hook. Red→green: `TestPeerDialsIdentifyLearnedAddr_NoMdnsLane` panicked, now passes.
2. **libp2p logs moved from go-log to `log/slog`** (`gologshim`). Production never set libp2p log levels, and the default is still ERROR, so app logs are unchanged. `node/addr_visibility_denial_test.go` now captures through a process-wide slog handler.
3. **Interface addresses are cached for 1 minute** (`addrs_manager.go:792`). After a Wi-Fi→cellular switch, the announced address set updates within about 65 s (was about 5 s). Peers dialing the stale LAN address fail and fall back to the relay. `TestInterfaceChangeUpdatesAnnouncedSet_NoStaleAddr` budget moved from 16 s to 75 s (measured 60 s).
4. **autorelay no longer uses DNS relay addresses for circuit addresses.** v0.39 kept public or DNS relay addrs, v0.50 keeps only public IPs. Production circuit addresses will use the relay's announced public IPs instead of `mknoun.xyz`. No app code depends on the DNS form. `TestDefaultFlagsKeepPrivateReachability_CircuitPublished` now uses a local relay that announces a public IP, like production; mutation (force public reachability) still turns it red. Device check: one phone on cellular.
5. **gosigar stub removed.** go-libp2p v0.50 no longer pulls `elastic/gosigar`.
6. **Test fakes** gained the new interface methods: `ResetWithError`, `CloseWithError`, `As`.
7. **pubsub fork** re-applied on v0.18.0. Every `network.Connected` check and the outbound `NewStream` in v0.18.0 go through `connectednessSupportsPubSub`/`withLimitedConn`; no new site was missed.
8. **gomobile** is installed by `make gomobile-tools` at the x/mobile version `go.mod` pins, no longer `@latest`.
9. **Environment-only reds** (same on the old code): relay `TestProductionAudioCallDeviceFixture_*` needs Docker; relay `TestRedisAckCustodySurvivesRelayProcessHandoff*` needs git inside the test. Run both on the Mac.
10. **Relay connection rate limit (D3) done.** `go-relay-server/conn_admission.go`: the relay builds libp2p's default resource manager with only the connection rate limiter replaced (IPv4 /32: 20/s, burst 200; IPv6 /56: 20/s, burst 200; /48: 50/s, burst 1000; loopback unlimited) and counts refusals in `relay_conn_admission_rejected_total{reason=rate_limit|per_ip_limit|other}`. Mutation: with libp2p's default limiter the 17th quick connection from one address is refused. Note: the separate cap of 8 open connections per IPv4 address is NOT new (v0.38.2 has it too) and is unchanged.
11. **Mixed-version interop: 56/56 passed** (2026-10-08, container, memory backend). `scripts/test/go_mixed_version_interop.sh`: OLD = `df0490fc5` on go1.25.0, NEW = this branch on go1.27.1; pairs OLD→NEW, NEW→OLD, NEW→NEW, OLD→OLD; each against the OLD and the NEW relay; rows circuit, 1:1 message, relay inbox, group (both directions), media, TCP, QUIC twice. The circuit and TCP rows each start on a fresh pair (a dialer that already knows QUIC addresses reconnects over QUIC). The test relay announces a public-looking IP (finding 4). `--redis-url` runs the relays like production (redis + ack-custody admission); no redis in the container, so that variant is still to run.
13. **Device proof, 2026-10-08 (all passed).** OLD = main `f3ee4cb30` (store 1.0.1+122 code, libgojni go1.25.0) on emulator Pixel_7 "AliceOld"; NEW = `005884b44` (libgojni go1.27.1) on emulator Pixel_8 "BobNew" and on the iPhone 13 (release build `261008164231`, installed over the existing app, identity kept). Driven by Maestro (emulators) and Appium (iPhone); evidence in `docker-ws/beta/wave5/g406/` and `artifacts/beta-20260928/r2o-shots/g406_*`.
    - Contact add: OLD↔NEW Android via the E2E contact-add seed; the iPhone (NEW) scanned both emulators' QR codes (the path that crashed on Go 1.26) — connected on all sides.
    - 1:1 text both ways: OLD↔NEW Android; iPhone↔AliceOld and iPhone↔BobNew ("received via direct connection").
    - Groups: "G406 Mixed" created on OLD with NEW; "G406 iPhone" created on the iPhone with OLD + NEW — invites accepted, every member saw every message.
    - Voice calls: iPhone (NEW) → AliceOld (OLD) and BobNew (NEW) → AliceOld (OLD) — connected both sides, ended cleanly.
    - Media: voice note AliceOld (OLD) → iPhone (NEW) through the relay, played on the iPhone.
    - Killed app: BobNew (NEW) app killed; AliceOld's text woke it via FCM and posted the notification within ~2 s.
    - No Mknoon crash on any device. (Pixel_8's `android.hardware…` service crash loop is the emulator image, not the app.)
    - Not run: an iPhone with the app killed; one phone on real cellular (the iPhone 13 and emulators were on Wi-Fi). The relay path itself was exercised by the voice note.
14. **Hetzner test relay checks, 2026-10-08 (all passed).** New relay (go1.27.1, v0.50.0) on 2.29.62.121 / `2-29-62-121.sslip.io`, production shape (redis, ack-custody admission, TURN, Firebase + APNs VoIP credentials copied from production).
    - Old/new interop against it: 28/28 (`go_mixed_version_interop.sh --relay-addr ...`).
    - Docker/git relay integration tests on the Mac: both PASS (the container reds in finding 9 were environment-only).
    - Android killed-app push through it, both directions (FCM): notification within ~2 s.
    - iPhone 13 (test-relay release build): contact add with AliceH through the test relay (the QR still advertises the production relay as rendezvous; it did not matter), killed-app message push shown on the lock screen, killed-app VoIP call rang via CallKit and connected.
    - One unexplained miss: the first VoIP call attempt did not ring although the relay sent the APNs VoIP push (Apple accepted it); the app was in an unclear background state after a UI swipe, and the relay logged one `call_token_revoke_v1` from the iPhone at that time. The clean retry (app foregrounded, then terminated) rang. Not reproduced.
15. **Production relay v1.11.0 deployed 2026-10-08T16:59:41Z** (user-approved; ahead of the planned week, because the new relay was already proven with old and new clients on the Hetzner test relay). sha `79488697…`, go1.27.1, backup `/usr/local/bin/relay-server.pre-1.11.0-20261008T165940Z` (= v1.10.9 `535d30e6…`), record `docker-ws/deploy_relay_v1110.sh` + `_result.txt`. Checks: active, 0 restarts, 0 panics; push, APNs VoIP, TURN, redis custody admission all enabled; test clients over WSS (circuit, 1:1, inbox, group, media) and QUIC (circuit) passed; a real installed Pixel 6 build (go1.25 bindings) reconnected; `relay_conn_admission_rejected_total` 0. Startup takes ~27 s, spent loading the app-diagnostics store (not the upgrade).
12. **Not covered by the interop test:** DCUtR (relay→direct upgrade) needs real NAT; covered by the in-process hole-punch tests on the new build and by the device run.

## Appendix — files that pin Go 1.25.0

- `go.mod`: `go-mknoon/go.mod:3`, `go-relay-server/go.mod:3`, `tool/call_audio_oracle/go.mod:3` (`go-mknoon/stub/gosigar/go.mod` says 1.24; leave it).
- Makefiles: `go-mknoon/Makefile:11`, `go-relay-server/Makefile:8`.
- Bindings: `scripts/ensure_go_{ios,android,macos}_bindings.sh:11`, `scripts/gomobile_binding_inputs.sh:38,104,112`.
- Gate runners: `scripts/run_host_test_gates.sh` (28 lines, 334–985), `scripts/run_test_gates.sh` (29 lines, 1345–1513), `scripts/mknoon_checks.py:1003`, `scripts/run_original_go_send_wrapper.py:32`.
- Sims: `tool/sims/build_orchestrator.dart:685,866`, `tool/sims/critical_features.json:347,385` (+ `host.go1.25` capability `:358,396,2712`), `integration_test/scripts/run_production_audio_call_sims.dart:20,311-313`, `production_audio_call_local_fixture.dart:7,405`, `ios_group_message_diagnostic_staging.py:1382`, `run_relay_diagnostics_virtual.py:183`.
- Docker: `docker/claude-code/Dockerfile:1`.
- docker-ws: `mint_ios_staging_manifest.sh:62`, `app_diagnostics_build_candidate.sh:17` (relay build), `go_test_316.sh`, `alltests_go_*.sh` (6), `beta/wave4/run_benchmarks_ar.sh:21`. Old `deploy_relay_v17x.sh` files are history; leave them.
- scripts/test helpers: `run_*_go_309/318/320.sh`, `run_ios_nse_native_373.sh:207`, `probe_fcm_*_320.sh`.
- Contract tests that assert the pin: `scripts/test/relay_go_toolchain_contract_test.sh:43`, `host_test_gate_batch_contract_test.sh:357,494`, `relay_ack_custody_rollout_contract_test.sh:79,98-110`, `run_claude_docker_update_contract_test.sh:24`, `production_audio_call_fixture_adapter_contract_test.sh:38,59`, `reliability_simulation_discovery_contract_test.sh:266`, `test/integration/production_audio_call_local_fixture_test.dart:200,280`, `test/integration/android_production_audio_call_campaign_test.dart:1695-1761`, `test/tool/sims/sims_manifest_test.dart:671`.
- Docs: `docs/testing/TESTING.md:609,3471,4159-4163,5087`, `Network-Arch/Issues.md:5`, `Network-Arch/IPV6-Infra-Ops.md:623,731`, `tool/call_audio_oracle/DEPENDENCIES.md:5,55`, comments in `node/lan_dial_test.go:13-15`, `media_lan_test.go:13`, `quic_identify_revalidation_test.go:27`, `benchmark_bridge_concurrency_test.go:34-37`.

## Sources

- quic-go v0.57.1 fix: https://github.com/quic-go/quic-go/releases/tag/v0.57.1, https://github.com/quic-go/quic-go/pull/5462, https://github.com/quic-go/quic-go/issues/5572
- CVE-2025-59530: https://github.com/quic-go/quic-go/security/advisories/GHSA-47m2-4cr7-mhcw
- go-libp2p releases: https://github.com/libp2p/go-libp2p/releases
- go-multiaddr v0.15 migration: https://github.com/multiformats/go-multiaddr/blob/master/v015-MIGRATION.md
- go-libp2p-pubsub releases: https://github.com/libp2p/go-libp2p-pubsub/releases
- libp2p interop matrix: https://github.com/libp2p/test-plans/blob/master/transport-interop/versionsInput.json
- Go release history and support policy: https://go.dev/doc/devel/release
