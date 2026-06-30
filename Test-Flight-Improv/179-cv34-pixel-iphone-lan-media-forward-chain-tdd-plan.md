# 179 - CV-34 Pixel→iPhone 1:1 LAN-media forward-chain self-heal + observability  (Bug)

Status: awaiting-review
Spec: free-text intent (no formal spec) — verified root-cause brief at
`<session-scratchpad>/cv34-forward-chain-rootcause-brief.md` (10-agent verify→refute, refutedCount=0).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-29 | Evidence Collector | p2p_service_impl.dart:455-535/915-962/4195-4251, bonsoir_discovery_service.dart:110-218/300-399, local_p2p_service.dart:90-160, fake_local_p2p_service.dart, bonsoir_discovery_service_contract_test.dart, p2p_service_impl_lan_media_test.dart, run_test_gates.sh, flow_event_emitter.dart | Root cause (HIGH on code mechanism) confirmed + adversarially survived; WHY-empty advertiser branch MEDIUM (no device capture) | build matrix observability-first |
| 2026-06-29 | Planner | (above) + tier-matrix.md, sufficiency-checklist.md, plan-template.md | 5 host TCs + 1 device-proof; `_localNetworkProven` decouple deferred (iOS-watchdog risk, unpinned) | emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-29 | contract extraction (git status --short) | — | baseline: only info.plist + project.pbxproj drift (pre-existing) + 179 plan | scope confirmed; shared tree safe (no git proc/lock) | RED |
| 2026-06-29 | RED tests added | p2p_service_lan_forward_test.dart (new), local_p2p_service_test.dart, fakes (scaffold) | `flutter test` the 2 files → 5 RED (TC-01/02/03a/03b/04), TC-05 GREEN | RED for documented reasons; TC-05 GREEN ⇒ A′ refuted at host level | implement |
| 2026-06-29 | implementation | p2p_service_impl.dart, local_p2p_service.dart, local_discovery_service.dart, bonsoir_discovery_service.dart, disabled_local_discovery_service.dart | empty-skip diagnostic + dedup-clear-on-lost + bounded re-resolve + gate-aware updateLibp2pPorts + isAdvertiseBroadcastGated getter | scoped files only | direct GREEN |
| 2026-06-29 | direct GREEN | (above) | `flutter test p2p_service_lan_forward_test.dart local_p2p_service_test.dart` → +22 All passed | reds now green | preservation |
| 2026-06-29 | interface-impl sweep | +5 inline `_SharedFakeDiscovery` fakes (account_migration/migration tests + 2 integration_test) | added `isAdvertiseBroadcastGated => false`; `flutter analyze` 5 files = No issues | every LocalDiscoveryService impl (8) covered | preservation |
| 2026-06-29 | preservation GREEN | p2p_service_impl_test.dart (FDC-04 TC-04-01/02 count 1→2, 179 re-resolve) | local_discovery dir + p2p_service_impl + lan_media = +276; 3 migration host tests +47 | sentinels green; FDC-04 count update justified (orthogonal re-resolve) | named gates |
| 2026-06-29 | named gates | scripts/run_test_gates.sh (ONE_TO_ONE_TESTS += new file) | `run_test_gates.sh core-host-all` → 265/265 files PASS, exit 0 | gate green | QA |
| 2026-06-29 | QA (independent) | — | `flutter analyze` 0 new (2 pre-existing info); `git diff --check` clean; graphify update + arch refresh done | blocking: none. Device closure (TC-179-D1) remains manual two-phone | hand off |

## Source Of Truth
- Spec / intent: verified root-cause brief (scratchpad) + this plan's Root Cause section.
- Gate definitions: scripts/run_test_gates.sh  (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (no new sim scenario — manual two-phone proof)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (this is the next-free number: 179)

## Session Classification
implementation-ready (host RED→GREEN fully runnable in-env; device closure is a manual two-phone proof, gated on the new diagnostic).

## Exact Problem Statement
1:1 media over the libp2p LAN stream (FDC-15 / CV-34) is **directionally asymmetric**: iPhone→Pixel works end-to-end
(P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}, image committed), but **Pixel→iPhone is blocked** — the Pixel resolves the
iPhone over mDNS (LOCAL_MDNS_PEER_FOUND host:192.168.0.211) yet never forwards it to the Go LAN-direct dial (no
P2P_LAN_PEER_FOUND_REQUEST), the resolved peer carries empty `libp2pAddresses`, the peer flaps FOUND→LOST_RETAINED
~every 20s, and the media send silently falls back to relay-CDN. The user sees a working LAN-fast path one direction
and a slow relay path the other, with **no on-device signal** explaining why.

Root cause (HIGH confidence on the code mechanism): the iPhone's bonsoir advert TXT carries no parseable
`quicPort`/`tcpPort` when the Pixel resolves it, so the Pixel builds empty `libp2pAddresses` and the forward loop drops
the peer at its **first guard** `if (peer.libp2pAddresses.isEmpty) continue;` (p2p_service_impl.dart:935) — and that
skip is **completely silent** (no flow event, never added to the dedup set). The defect is therefore (a) **unobservable**
(can't tell "resolved-but-empty" from "never-resolved" on device), and (b) **non-self-healing** (the Pixel never
re-reads a possibly-healed TXT, and a re-forward is blocked once the iPhone does heal — see INV-2/INV-3).

What must improve:
- The resolved-but-empty skip becomes **observable** on device (Tier-1 keystone — also the prerequisite to pin the
  advertiser branch in the next device run).
- The discoverer (Pixel) **self-heals**: re-resolves an empty-address peer (bounded) and re-forwards once it heals.
- The advertiser (iPhone) **stops destroying a working ported advert** when a gated re-advert is skipped, and retries.

What must stay unchanged (→ preserved-green sentinels):
- The 178 iOS watchdog invariant: while the suspected-denied gate is latched, **no native broadcast (re)start** runs.
- The 178/177/175 fixes themselves; the FDC-15 send-leg + `hasNonCircuitDirectConn` predicate; the working
  iPhone→Pixel direction; all current local_discovery + p2p_service host suites.

## Root Cause (verify → refute confirmed)
Confirmed (survived 3 adversarial lenses — publish-side, gate-and-flag, device-evidence; refutedCount=0):
1. `bonsoir_discovery_service.dart:140-148` `_buildLibp2pAddresses` returns `[]` when `attributes['quicPort']`/`['tcpPort']`
   are absent/unparseable (portless TXT). Sole source of `LocalPeer.libp2pAddresses`.
2. `bonsoir_discovery_service.dart:324-334` commits the empty-address peer **unconditionally** to `_peers` and emits
   `LOCAL_MDNS_PEER_FOUND` regardless of addresses (:344-348).
3. `p2p_service_impl.dart:935` `if (peer.libp2pAddresses.isEmpty) continue;` is the **first** statement of the forward
   loop — **silent**, does **not** add to `_lanDialForwardedPeerIds`, short-circuits **before** the dedup (:936) and the
   `'p2p_lan_dial'` migration gate (:937-944). ⇒ no `callP2PLanPeerFound` → no `lan:peer_found` → relay fallback.
4. WHY the TXT is portless (advertiser-side, MEDIUM — **branch not device-pinned**):
   - **A′ (strongest persistent):** `_resolvedAdvertQuicPort`/`_resolvedAdvertTcpPort` null ⇒ `_maybePublishLibp2pAdvertPorts`
     early-returns at `p2p_service_impl.dart:4221` and never republishes any ports.
   - **B:** `updateLibp2pPorts` (local_p2p_service.dart:116-122) does `stopAdvertising()` (ungated teardown) then
     `startAdvertising()` (broadcast leg gated by the iOS suspected-denied latch, bonsoir:185-193) — a gated re-advert
     **tears down the prior ported advert and re-registers nothing**, and the no-op cache at :108-110 (set *before* the
     stop+start) means the same ports never retry.
   - **A (transient only):** `_localNetworkProven` hold (`p2p_service_impl.dart:4223`, latch set at :476). DOWNGRADED:
     the working iPhone→Pixel direction *proves* this latch opens in steady state, so it explains at most a cold-start window.
   - **C/D:** Pixel stale-cache re-resolve of the old portless handle / Android NsdManager dropping the iOS TXT.

Refuted / do-NOT-re-introduce:
- **`'p2p_lan_dial'` account-migration gate as the blocker** — emits `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED`
  (absent from all logs), is OPEN when `authority==null`, and `:935` short-circuits before it. Not the cause.
- **The ~20s FOUND→LOST_RETAINED flap as a cause** — it is the 20s re-resolve timer within the 30s `LocalPeer.ttl`; a
  symptom that re-exposes the portless TXT, not the cause.
- **Host-shape (.local/dns4 vs ip4)** — the host was numeric `192.168.0.211` → ip4; emptiness is missing ports, not host shape.
- **Per-peer dedup suppressing the *first* forward** — the set is added to only AFTER a non-empty forward (:945); empty
  peers never reach it. (It IS a latent re-forward hazard — fixed by INV-2, not the first-forward blocker.)
- **A nat-status gate** — refuted by plan 175; do not reintroduce.

## Real Scope
In scope:
- Observability: a distinct `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` flow event at `p2p_service_impl.dart:935`.
- Discoverer self-heal in `p2p_service_impl.dart` forward path: clear `_lanDialForwardedPeerIds` on peer-lost; a bounded
  on-demand re-resolve of an empty-address peer (via the existing `discoverLocalPeer`/`resolvePeer` seam).
- Advertiser robustness in `bonsoir_discovery_service.dart` / `local_p2p_service.dart`: make the port re-advert atomic so a
  gated re-advert **never tears down** the prior ported advert, retries once the gate clears, and caches ports only after a
  successful re-register.
- A host characterization-lock for the A′ port-derivation (`listenAddresses` → resolved advert ports).

Out of scope (owning work named in Accepted Differences):
- Decoupling `_maybePublishLibp2pAdvertPorts` from `_localNetworkProven` (sub-cause A) — **device-gated** (iOS-watchdog risk; unpinned).
- DCUtR CV-11/12, FDC-S6 soak/verdict, the FDC-S0 scorecard, NsdManager raw-TXT investigation (sub-cause D).

## Files To Inspect Next
Production:
- `lib/core/services/p2p_service_impl.dart` — `_forwardLanPeersToLibp2pDial` (931-962), the `discoveredPeersStream` listener
  (466-487), `_maybePublishLibp2pAdvertPorts` (4216-4251), `_resolvedAdvertQuicPort/_resolvedAdvertTcpPort` derivation.
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — `startAdvertising` (151-218, broadcastGated 174-193),
  `_markPeerLost` (380-399), resolve commit (311-367), `resolvePeer` (507+), `@visibleForTesting` gate seams (466-480).
- `lib/core/local_discovery/local_p2p_service.dart` — `updateLibp2pPorts` (107-133).
- `lib/core/utils/flow_event_emitter.dart` — `emitFlowEvent` (202), `debugSetFlowEventSink` (38).
Direct tests + integration tests:
- `test/core/services/p2p_service_lan_forward_test.dart` (NEW), `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` (EXTEND).
Dependency-only context: `test/core/services/p2p_service_impl_lan_media_test.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, `test/core/local_discovery/local_p2p_service_test.dart`.

## Existing Tests Covering This Area
- `test/core/services/p2p_service_impl_lan_media_test.dart` — FDC-15 send leg + `hasNonCircuitDirectConn` (exists; does NOT cover the discovery→forward gate).
- `test/core/services/p2p_service_impl_test.dart` — references the forward chain + `libp2pAddresses` (exists; no empty-address/observability/self-heal case).
- `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` — advertise/resolve/178-gate contract (exists; no gated-re-advert teardown case).
- `test/core/local_discovery/local_p2p_service_test.dart` — `updateLibp2pPorts` (exists; no gated/no-op-retry case).
Missing coverage gaps: (a) silent empty-address skip is **unobservable + untested**; (b) dedup never cleared on lost — **untested**;
(c) no re-resolve of an empty peer — **untested**; (d) gated re-advert teardown — **untested**; (e) A′ port-derivation — **untested**.
Already in curated family arrays?: `p2p_service_impl_lan_media_test.dart` + `go_bridge_client_lan_media_test.dart` are in
`ONE_TO_ONE_TESTS` (run_test_gates.sh, FDC-15 block); the contract + local_p2p tests auto-glob into `core-host-all` only.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)
1. `test/core/services/p2p_service_lan_forward_test.dart`::`empty-address resolved peer emits LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR and is not forwarded`
   - Tier: unit/application host (services).
   - Shape/setup: build `P2PServiceImpl` with `_FakeBridge` (mirror p2p_service_impl_lan_media_test.dart) + `FakeLocalP2PService`;
     `debugSetFlowEventSink((p) => recorded.add(p))` in setUp, reset in tearDown. `localP2P.addLocalPeer('iphone', libp2pAddresses: const [])`.
   - RED on HEAD because: the `:935` skip emits nothing; `recorded` contains no `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` → assertion fails.
   - GREEN after fix asserts: `recorded` contains one `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` with `peerId:'iphone'`.
   - Mutation that re-reds: revert the new `emitFlowEvent` at the empty-peer branch → red.
   - Distinct-event discriminator: assert `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` present **AND** `bridge.commandsSent` does **NOT** contain `lan:peer_found`.
2. `test/core/services/p2p_service_lan_forward_test.dart`::`a forwarded peer that drops from the snapshot is re-forwarded when it reappears with addresses`
   - Tier: unit host (services).
   - Shape/setup: `addLocalPeer('iphone', libp2pAddresses:['/ip4/.../udp/4001/quic-v1'])` → first forward; `removeLocalPeer('iphone')`;
     `addLocalPeer('iphone', libp2pAddresses:[...])` again.
   - RED on HEAD because: `_lanDialForwardedPeerIds` is never cleared on removal, so the reappearance is deduped at `:936` → only **one** `lan:peer_found` is sent.
   - GREEN after fix asserts: `bridge.commandsSent.where((c)=>c=='lan:peer_found').length == 2`.
   - Mutation that re-reds: revert the clear-`_lanDialForwardedPeerIds`-on-lost edit → red.
3. `test/core/services/p2p_service_lan_forward_test.dart`::`empty-address peer triggers exactly one bounded re-resolve and forwards once it heals`
   - Tier: unit host (services).
   - Shape/setup: `addLocalPeer('iphone', libp2pAddresses: const [])`; set `localP2P.resolvesTo = LocalPeer('iphone', host, port, libp2pAddresses:[quicAddr])`
     so the fake `discoverLocalPeer` heals on demand; emit a second empty snapshot for the same peer before it heals.
   - RED on HEAD because: an empty peer is skipped silently with no re-resolve → `localP2P.discoverLocalPeerCallCount == 0`.
   - GREEN after fix asserts: `discoverLocalPeerCallCount == 1` (bounded — not re-fired on the second still-empty snapshot), and after the
     heal a `lan:peer_found` for `iphone` is sent. Assert the re-resolve path issues **no advertise** (browse/resolve-only — INV-4 safety).
   - Mutation that re-reds: revert the re-resolve trigger → red (count stays 0).
4. `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart`::`gated re-advert retains the prior ported advert and retries after the gate clears (178 broadcast-skip preserved)`
   - Tier: integration/contract host (factory-faked bonsoir).
   - Shape/setup: `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`; `startAdvertising('me', 54321, quicPort:4001, tcpPort:4002)` (ungated → prior ported advert registered);
     latch `_suspectedDeniedUntil` via the same zero-peer probe path the existing 178 tests use (or the `@visibleForTesting` gate seam at bonsoir:466-480);
     drive a port-update re-advert (`updateLibp2pPorts(quicPort:4001, tcpPort:4003)` through `local_p2p_service`, or the new atomic re-advert directly).
   - RED on HEAD because: `updateLibp2pPorts`→`stopAdvertising()` disposes the prior `_broadcast` and `startAdvertising`'s broadcast leg is
     skipped → the ported advert is **lost**; assert `broadcast().stopCalls == 0` (prior advert retained) → red on HEAD.
   - GREEN after fix asserts: (i) prior advert **retained** while gated (no teardown); (ii) after `_suspectedDeniedUntil=null` + retry, a new
     broadcast is registered carrying `attributes['quicPort']=='4001'` && `attributes['tcpPort']=='4003'`.
   - Mutation that re-reds: revert the atomic-no-teardown re-advert edit → red.
   - Distinct-event discriminator (178 preserved): while gated assert `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` **present** **AND**
     no new `_FakeBonsoirBroadcast.startCalls` increment (native (re)start still skipped) — the watchdog invariant holds.
5. `test/core/services/p2p_service_lan_forward_test.dart`::`a node listenAddresses with LAN quic-v1 + tcp derives non-null advert ports (no :4221 early-return)`
   - Tier: unit host (services). **Characterization-first / DUAL-OUTCOME.**
   - Shape/setup: feed an `addresses:updated` push with a realistic `listenAddresses` carrying `/ip4/192.168.0.211/udp/4001/quic-v1` and a non-ws
     `/ip4/192.168.0.211/tcp/4002`; capture flow events.
   - RED-or-GREEN on HEAD: run on HEAD. **If GREEN** → A′ is refuted at host level (derivation already correct) ⇒ this row is a regression-lock and A′
     becomes a device-gated branch; the mutation below locks it. **If RED** (a valid LAN addr is dropped) → A′ is a real fix; implement the derivation fix.
   - GREEN asserts: `FDC_LAN_ADVERT_PORTS` (or `_DEFERRED` when `_localNetworkProven` false) is emitted with non-negative `quicPort`/`tcpPort` — i.e. the
     `:4221` "both null" early-return is **not** taken.
   - Mutation that re-reds: tighten the listenAddress parser to drop the LAN `/quic-v1` (or revert the derivation fix if RED-on-HEAD) → red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-179-01 observability keystone | flow-event emission (pure) | unit host | p2p_service_lan_forward_test.dart::`empty-address resolved peer emits …SKIPPED_NO_LIBP2P_ADDR and is not forwarded` | `:935` skip is silent; event absent | revert the empty-branch `emitFlowEvent` → red | `flutter test test/core/services/p2p_service_lan_forward_test.dart` ; `./scripts/run_test_gates.sh core-host-all` | AUTO (classify_path:578 core services) for core-host-all; **add to `ONE_TO_ONE_TESTS`** for the 1to1 gate |
| TC-179-02 dedup-clear-on-lost | in-memory state lifecycle | unit host | p2p_service_lan_forward_test.dart::`a forwarded peer that drops … is re-forwarded when it reappears` | `_lanDialForwardedPeerIds` never cleared → reappearance deduped at `:936` (one forward) | revert clear-on-lost → red | same as TC-01 | AUTO + add to `ONE_TO_ONE_TESTS` |
| TC-179-03 re-resolve-on-empty (bounded) | self-heal transition (bounded) | unit host | p2p_service_lan_forward_test.dart::`empty-address peer triggers exactly one bounded re-resolve and forwards once it heals` | empty peer skipped silently; `discoverLocalPeerCallCount==0` | revert re-resolve trigger → red | same as TC-01 | AUTO + add to `ONE_TO_ONE_TESTS` |
| TC-179-04 gated-re-advert no-teardown + retry (178 preserved) | native advert lifecycle under gate | integration/contract host | bonsoir_discovery_service_contract_test.dart::`gated re-advert retains the prior ported advert and retries after the gate clears (178 broadcast-skip preserved)` | `stopAdvertising()` tears down prior `_broadcast`; `startAdvertising` broadcast leg skipped → advert lost | revert atomic-no-teardown re-advert → red | `flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart` ; `./scripts/run_test_gates.sh core-host-all` | AUTO (classify_path:603 local_discovery) → core-host-all (no array change) |
| TC-179-05 A′ port-derivation lock | pure derivation (DUAL-OUTCOME) | unit host | p2p_service_lan_forward_test.dart::`a node listenAddresses with LAN quic-v1 + tcp derives non-null advert ports (no :4221 early-return)` | RED only if a valid LAN addr is dropped; else GREEN-lock (A′ refuted at host) | tighten parser to drop LAN `/quic-v1` (or revert fix) → red | same as TC-01 | AUTO + add to `ONE_TO_ONE_TESTS` |
| TC-179-D1 device closure | OS-boundary / cross-device / real mDNS | device-proof (manual two-phone) | manual rig (CV-08 rig) — Pixel→iPhone media, post-178 build | n/a (real-device proof) | n/a | `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true` (+ iOS); see Device/Relay Proof Profile | MANUAL — no classify_path/`/sims` scenario (two-phone proof, mirrors CV-08) |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** the new in-memory sets (`_lanDialForwardedPeerIds` re-forward state + the re-resolve guard) are
  **transient routing dedup**, not persisted derived UI. On a discovery/process restart they reset to empty, whose correct behavior is
  "re-forward every live peer" — the safe default, already the post-restart path. **N/A (justified):** no persisted derived state to reconstruct;
  the only lifecycle transition that matters (peer lost → reappears) is locked by **TC-179-02**.
- **Sibling-surface consistency:** the empty-address skip + re-resolve is on the **libp2p LAN-dial forward** path. The parallel LAN surface
  (WS/media send-time resolve) already resolves on demand via `discoverLocalPeer` at send time; the new re-resolve must not double-fire with it.
  Locked by **TC-179-03** (bounded ≤1 per empty episode). No other capability gate (react/quote/voice/delete) consumes `libp2pAddresses`.
- **Destructive-action side-effects:** the only "destroy" here is `stopAdvertising()` tearing down the live advert. **TC-179-04** asserts exactly
  what is **not** destroyed (prior ported advert retained when gated) and what is re-registered on retry — i.e. it guards the side-effect directly.
- **Invariant re-verification under new transitions:** **TC-179-04** re-verifies the **178 watchdog invariant** (no native broadcast (re)start while
  the gate is latched) under the *new* no-teardown transition, and **TC-179-03** asserts the re-resolve issues **no advertise** (never reopens the
  latch / forces an ungated broadcast). Both new transitions re-check the pre-transition iOS-safety invariant.

## Invariants (locked by tests)
- INV-1: a resolved peer with empty `libp2pAddresses` is observable (`LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR`) → TC-179-01.
- INV-2: the LAN-dial forward is re-armed after a peer is lost (dedup cleared) → TC-179-02.
- INV-3: an empty-address peer triggers a **bounded (≤1 per empty episode)** re-resolve, never a tight loop → TC-179-03.
- INV-4 (178 preserved): while the suspected-denied gate is latched, **no native broadcast (re)start** occurs — held under the new atomic
  re-advert AND the new re-resolve path → TC-179-04 (+ TC-179-03 advertise-free assertion).
- INV-5: a gated re-advert **never tears down** a previously-registered ported advert, and retries once the gate clears → TC-179-04.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Add TC-179-01..05 RED tests; run focused cmds; confirm each fails for the documented reason (TC-05 may be GREEN-on-HEAD — record that outcome; it
   then becomes the A′ regression-lock and A′ moves to the device-gated follow-up).
2. **Observability (TC-01):** in `_forwardLanPeersToLibp2pDial` (p2p_service_impl.dart:935), before `continue`, `emitFlowEvent('FL', 'LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR', {peerId, host})`.
3. **Dedup-clear-on-lost (TC-02):** in the `discoveredPeersStream` listener (p2p_service_impl.dart:466-487) or at the top of the forward loop, compute
   `_lanDialForwardedPeerIds`-minus-current-snapshot-keys and remove the dropped ids (also clear the re-resolve guard for them). Stop-if: clearing on
   every snapshot churns forwards → guard on actual set-difference, not snapshot identity.
4. **Bounded re-resolve (TC-03):** when the forward loop hits an empty-address peer not already re-resolved this episode, add to a `_lanEmptyReResolvedPeerIds`
   guard and fire one `localP2P.discoverLocalPeer(peerId, timeout: <bounded>)` (fire-and-forget; a heal arrives as a fresh snapshot). Clear the guard on
   peer-lost (step 3) and on a non-empty resolve. Stop-if: re-resolving every snapshot reopens the 20s-flap loop → the guard makes it ≤1 per empty episode.
5. **Advertiser atomic re-advert (TC-04):** replace the `updateLibp2pPorts` stop+start (local_p2p_service.dart:116-117) with an atomic
   `BonsoirDiscoveryService` re-advert that checks the broadcast gate **before** any teardown: when gated, leave the prior `_broadcast` intact + record a
   pending retry; when ungated, stop+start then cache the ports. Move the no-op port cache (local_p2p_service.dart:108-110) to **after** a successful
   re-register so a gated attempt retries. Retry on the next un-gated `startAdvertising`/gate-clear. Stop-if: this risks touching the 178 path → TC-179-04's
   discriminator must keep `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` + zero native (re)start while gated.
6. **A′ derivation (TC-05) — only if RED-on-HEAD:** fix the `listenAddresses`→`_resolvedAdvertQuicPort/_resolvedAdvertTcpPort` derivation so a valid LAN
   `/quic-v1`/non-ws `/tcp` addr yields non-null ports. If GREEN-on-HEAD, ship the test as a lock and record A′ as device-gated (no prod edit).
7. Rerun direct → preservation → named gates. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (lib/ changed; never cwd inside graphify-arch/).

## Risks And Edge Cases
- **Re-resolve ↔ 20s-flap loop** (tight re-resolve storm) → pinned by TC-179-03 bounded guard.
- **Dedup-clear churn** (re-forwarding a still-present peer every snapshot) → pinned by TC-179-02 (set-difference, not snapshot identity).
- **Regressing the 178 iOS watchdog** with the atomic re-advert → pinned by TC-179-04 discriminator (INV-4).
- **Self-resolve own service** — the re-resolve must reuse the existing own-peer skip (bonsoir:307/314); do not re-resolve `_ownPeerId`.
- **A′ uncertainty** — TC-05 is characterization-first; a GREEN-on-HEAD outcome is expected-and-acceptable (it refutes A′ at host level, not a failure).

## Device/Relay Proof Profile
requires manual two-phone device for closure (host suite proves the discoverer self-heal + advertiser no-teardown + observability; the *which-branch*
disambiguation and CV-34-both-ways are device-only).
**PROD-CRITICAL leg:** TC-179-D1 (manual two-phone Pixel→iPhone media over the libp2p LAN stream) is the ONLY path that proves the wire/transport leg
end-to-end. Host unit coverage proves the routing/self-heal logic but does NOT prove the leg — do not treat host GREEN as closure.
Closure scenario (the CV-34-both-ways + FDC-S6 i→A gate): Pixel 6 (`adb -s 21071FDF600CSC`) + iPhone 11 (`00008030-001A6D2801BB802E`), same WiFi, both
apps foreground, post-178 build with `--dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_LIBP2P_LAN_MEDIA=true`. Send Pixel→iPhone media; capture:
- `LOCAL_MDNS_PEER_SKIPPED_NO_LIBP2P_ADDR` on the Pixel ⇒ confirms the empty-address path is the live failure (vs never-resolved).
- iPhone advertiser branch: `FDC_LAN_ADVERT_PORTS` (published) vs `FDC_LAN_ADVERT_PORTS_DEFERRED` (sub-cause A) vs `LOCAL_MDNS_ADVERTISE_SKIPPED_SUSPECTED_DENIED` (sub-cause B) ⇒ selects the WHY-empty branch.
- After self-heal: a Pixel `lan:peer_found` re-forward + `P2P_LAN_MEDIA_SEND_RESPONSE{ok:true}` both directions.
Flip any feature flag ON only AFTER device evidence (EnableLibp2pLANMedia stays dark this phase; also gated on the parked FDC-S6 verdict).
Deferred device work → its own session: the `_localNetworkProven` decouple (sub-cause A), only if the device run shows `FDC_LAN_ADVERT_PORTS_DEFERRED` is the live branch.
Relay defaults if needed: see `/sims` (not used here — manual rig).

## Acceptance Gates  (literal — copy/paste, with expected counts)
NOTE (as-built): TC-179-04 landed in `local_p2p_service_test.dart` (not the bonsoir contract test) because the fix seam is
`LocalP2PService.updateLibp2pPorts` + the new `LocalDiscoveryService.isAdvertiseBroadcastGated` getter — the broadcast-only
re-advert primitive was unnecessary. The 178 watchdog invariant stays locked by the existing contract suite (unchanged, green).
```bash
# RED (before production edits) — must FAIL for the documented reason  [VERIFIED: 5 RED]
flutter test test/core/services/p2p_service_lan_forward_test.dart      # TC-01/02/03a/03b RED; TC-05 GREEN (A′ refuted at host)
flutter test test/core/local_discovery/local_p2p_service_test.dart --plain-name 'TC-179-04'  # RED on HEAD

# Direct GREEN (after fix)  [VERIFIED: +22 All tests passed]
flutter test test/core/services/p2p_service_lan_forward_test.dart test/core/local_discovery/local_p2p_service_test.dart

# Preservation sentinels (must stay green)  [VERIFIED]
flutter test test/core/services/p2p_service_impl_lan_media_test.dart   # FDC-15 send leg unaffected
flutter test test/core/local_discovery/bonsoir_discovery_service_contract_test.dart  # 178 watchdog invariant preserved
flutter test test/core/services/p2p_service_impl_test.dart             # forward-chain + FDC-04 (TC-04-01/02 count 1→2)
./scripts/run_test_gates.sh core-host-all                              # VERIFIED: 265/265 files PASS, exit 0
./scripts/run_test_gates.sh 1to1                                       # ONE_TO_ONE_TESTS incl. new file — expect: all pass

# Hygiene  [VERIFIED]
flutter analyze            # 0 new (2 pre-existing info: p2p_service_impl.dart:3640 curly-braces, local_p2p_service_test.dart:1 dart:async)
git diff --check           # clean

# Post-land graph refresh (lib/ changed)  [DONE]
graphify update . && ./graphify-arch/refresh_arch_graph.sh            # never with cwd inside graphify-arch/
```

## Known-Failure Interpretation
- Expected RED: TC-179-01/02/03/04 before the fix (documented reasons above).
- Expected-PASS-on-HEAD (not a failure): TC-179-05 if host derivation is already correct → records A′ refuted at host level.
- Pre-existing dirty: `info.plist` + `ios/Runner.xcodeproj/project.pbxproj` (unrelated drift — leave; never bundle).
- Environment blocker (NOT product): the two-phone device proof is not runnable in this env; it remains the manual closure step.
- Scope drift (BLOCKING): any change to the 175 vendored bonsoir, the `_localNetworkProven` gate, a nat-status gate, or a feature-flag default flip.

## Done Criteria
- [x] RED added first (TC-179-01/02/03a/03b/04), failed for the documented reason; TC-179-05 recorded as GREEN-lock (A′ refuted at host level).
- [x] Mutation-verified — the RED phase WAS the pre-edit (HEAD) state: reverting any fix re-reds its TC (TC-01 emit, TC-02 dedup-clear, TC-03 re-resolve, TC-04 gate-aware updateLibp2pPorts).
- [x] Direct GREEN (+22) + preservation sentinels (`p2p_service_impl_lan_media`, `local_p2p_service`, `bonsoir` contract = 178 preserved, `p2p_service_impl`) + `core-host-all` (265/265 files) pass. (`1to1` family gate not separately re-run — its members all pass individually; recommend before merge.)
- [x] No DB migration (none needed — N/A).
- [ ] Device closure (manual two-phone) confirms the empty-address path + the live advertiser branch + LAN media both-ways — CV-34-both-ways + FDC-S6 i→A. **(MANUAL — not runnable in this env; remains the closure step.)**
- [x] Every new test's harness-registration done: `ONE_TO_ONE_TESTS += p2p_service_lan_forward_test.dart`; TC-04 in `local_p2p_service_test.dart` auto-globs into core-host-all.
- [x] `flutter analyze` 0 new (2 pre-existing info); `git diff --check` clean; no Scope Guard violations; full + arch graphs refreshed.

## Scope Guard (hard "Do not")
- Do NOT revert/modify the 175 vendored `third_party/bonsoir_darwin` off-main fix, the 177 lan-classifier, or the 178 suspected-denied gate (iOS-only-armed).
- Do NOT decouple `_maybePublishLibp2pAdvertPorts` from `_localNetworkProven` (p2p:4223) — device-gated (iOS 0x8BADF00D watchdog risk; branch unpinned).
- Do NOT re-add a nat-status gate (175 refuted it). Do NOT reintroduce the iOS main-thread DNS-SD block.
- Do NOT flip `EnableLibp2pLANMedia` / `EnableDcutrUpgrade` defaults (device-gated; LAN-media also gated on the parked FDC-S6 verdict). Remember the Dart
  map `defaultValue` is the load-bearing default (flipping only the Go default is a no-op).

## Accepted Differences / Intentionally Out Of Scope
- **`_localNetworkProven` decouple (sub-cause A):** could publish ports without a resolved peer, but the latch exists to avoid the iOS cold-start watchdog
  crash and the working reverse direction proves it opens in steady state. Deferred to a device-gated session, only if the device run shows
  `FDC_LAN_ADVERT_PORTS_DEFERRED` is live.
- **NsdManager-drops-iOS-TXT (sub-cause D):** needs a raw NSD TXT dump on device; investigation, not a host fix.
- **DCUtR CV-11/12, FDC-S6 soak/verdict, FDC-S0 scorecard:** other sessions.

## Dependency Impact
- CV-34-both-ways and FDC-S6 i→A depend on this: the observability keystone (TC-179-01) is the prerequisite that lets the device run pin the advertiser
  branch; the discoverer self-heal closes the Pixel→iPhone direction once the iPhone advert heals.

## Reviewer Findings
(pending sufficiency review)

## Arbiter Decision
(pending) — Structural blockers: … | Deferred details: `_localNetworkProven` decouple (device-gated) | Accepted differences: as above.

## Final Execution Verdict
Verdict: **EXECUTED — host RED→GREEN complete; SHIP-WITH-FOLLOWUPS** (device closure TC-179-D1 pending, manual). |
Files changed: 5 prod (`p2p_service_impl.dart`, `local_p2p_service.dart`, `local_discovery_service.dart` interface, `bonsoir_discovery_service.dart`,
`disabled_local_discovery_service.dart`) + 9 test (new `p2p_service_lan_forward_test.dart`; `local_p2p_service_test.dart` TC-04; 2 fakes scaffolded;
`p2p_service_impl_test.dart` FDC-04 count; +5 inline `_SharedFakeDiscovery` fakes for the interface getter) + `scripts/run_test_gates.sh` registration. |
Tests run (+counts): 5 RED→GREEN (TC-05 GREEN-lock); direct +22; preservation local_discovery+services+lan_media +276, migration host +47; `core-host-all`
265/265 files PASS exit 0; `flutter analyze` 0 new; `git diff --check` clean; graphs refreshed. |
Blocking: none. |
QA verdict: SHIP-WITH-FOLLOWUPS — both must-pass invariants HELD: INV-4 (178 watchdog — bonsoir contract suite green; gate-aware updateLibp2pPorts never
forces a broadcast while latched) and INV-5 (gated re-advert never tears down the prior advert, TC-179-04). Honest deviations: (1) TC-04 home moved
contract-test → `local_p2p_service_test.dart` (the real fix seam is `updateLibp2pPorts`, no broadcast-only primitive needed); (2) the broadcast-only
re-advert primitive was replaced by the simpler `isAdvertiseBroadcastGated` getter (interface +1 method → 8 impls updated); (3) FDC-04 TC-04-01/02 counts
1→2 (the new bounded re-resolve fires orthogonally for the seeded empty-address peer — warm-peer behaviour itself unchanged). |
Non-blocking follow-ups (owner): device closure TC-179-D1 (manual two-phone); `_localNetworkProven` decouple (device-gated session, only if the run shows
`FDC_LAN_ADVERT_PORTS_DEFERRED` is live); NsdManager raw-TXT probe (device); A′ confirmed refuted at host level (no fix owed). TC-05 GREEN-lock stands.
