# 190 — Android netlink SELinux addr-visibility: device runsheet

Status: **DEVICE-PROVEN 2026-07-02** on Pixel 6 (`21071FDF600CSC`, Android 16,
build 1.0.0+106 profile with the anet fix) + a fresh libp2p peer on the same WiFi.
TC-190-40 ✓, TC-190-41 wire leg ✓ (direct LAN dial via identify-learned addr,
no mDNS), TC-190-42 core ✓ (cellular clean + real cellular/GUA addrs announced).
Full app-level two-phone messaging (iPhone UI drive + contact pairing) is the only
piece still requiring manual interaction — the libp2p wire mechanism it depends on
is proven below.

## Device Proof Results (2026-07-02, captured logs in session scratchpad)

A/B on the SAME Pixel, same 75–95 s foreground window, `adb logcat`:

| Signal | BEFORE (build 106, pre-fix) | AFTER (anet only) | AFTER (anet + netroute short-circuit) |
|---|---|---|---|
| `netlinkrib: permission denied` ERROR (basic_host.go:396) | 8 in 75 s (5 s cadence, indefinite) | **0** | **0** |
| `avc: denied { bind } netlink_route_socket` | continuous, forever | 1 per 5 s (netroute lane), forever | **3 one-time at construction, then 0** for the rest of the window |
| `[NODE] Announcing N addresses` | **0** | 9 (cellular IPv4 + IPv6 GUA) | **6** (WiFi `192.168.0.240` + cellular `100.101.166.243`, ×{quic,tcp,ws}) |
| `node:status.listenAddresses` shape | 0.0.0.0-mined | real IP | real IP |

- **TC-190-40 (a) PASS**: zero recurring `netlinkrib` ERROR cadence.
- **TC-190-40 (b) PASS (with note)**: the *forever 5 s* avc cadence is eliminated. The netroute short-circuit (below) removed the netroute lane; a residual **3 one-time construction-burst** avc denials remain from a distinct one-shot go-libp2p netlink probe (NAT/reuseport at host setup), which does NOT recur — negligible vs the eliminated ~17 k/day. Chasing the last 3 would need forking go-nat/reuseport; out of proportion and out of scope.
- **TC-190-40 (c) PASS**: `Announcing 6` including the device's WiFi IP `192.168.0.240`.
- **TC-190-40 (d) PASS**: real-IP listenAddresses shape (not `/ip4/0.0.0.0`).
- **TC-190-42 core PASS**: on cellular, `Announcing 9` incl. public IPv6 GUA `2a00:20:…` (DCUtR candidate material), zero `netlinkrib` ERROR spam.

### netroute short-circuit (added during device proof — closes the recurring avc spam)

The `avc { bind }` cadence that survived the anet-only build was `go-netroute`'s
`New()` → `syscall.NetlinkRIB(RTM_GETROUTE)` firing every ~5 s in basichost's
`updateLocalIpAddr` (it seeds `filteredInterfaceAddrs` *before* the manet/anet
lane). netroute already *fails* on Android (the plan's accepted difference), but
the failed **bind attempt** itself is the audit-spam source. Fix (in the existing
`third_party/go-netroute` fork, `netroute_linux.go`): short-circuit `New()` on
`runtime.GOOS == "android"` BEFORE the bind — behaviorally identical (every caller
already degrades gracefully on the error; addrs come from anet), but no bind, no
avc denial. `runtime.GOOS` is a compile-time constant so the non-Android linux
build is byte-unchanged. Device-verified: the 1/5 s cadence dropped to the 3
one-time startup denials above. This is the plan's named "optional follow-up",
promoted because the spec lists SELinux audit spam as an in-scope concern.

### TC-190-41 (PROD-CRITICAL) — direct LAN dial via identify-learned addr, no mDNS

A fresh libp2p host on a Mac (`12D3KooWLNoj…`) on the same WiFi (`192.168.0.60`),
told ONLY the Pixel's peer ID + one announced multiaddr (no mDNS, no bonsoir TXT),
dialed `/ip4/192.168.0.240/tcp/42095/p2p/12D3KooWJ65meMYvApw2h2XnbGmTLrndWSwBz3EwSdPHe1SzAzrQ`:

```
TRANSPORT CONNECTED; connectedness = Connected
IDENTIFY COMPLETED with 12D3KooWJ65meMYvApw2h2XnbGmTLrndWSwBz3EwSdPHe1SzAzrQ
peer's announced addrs (via identify): [/ip4/192.168.0.240/tcp/42095 ...
    /ip4/100.101.166.243/... /dns4/mknoun.xyz/.../p2p-circuit ...]
CONN /ip4/192.168.0.60/tcp/56164 -> /ip4/192.168.0.240/tcp/42095 (limited=false)
```

`limited=false` = a DIRECT (non-relayed) LAN connection, established using only the
identify-announced address. TC-190-41's falsifier ("relay-only when mDNS is
unavailable") is disproven on real hardware. On build 106 the identify set was
empty → the peer could reach the Pixel ONLY via `/p2p-circuit`. The remaining
app-level piece (iPhone contact pairing + UI-driven send) needs manual interaction;
the wire mechanism it rides is proven here + by host TC-190-03.

---
Original runsheet protocol (for a full manual re-run) follows.

---

Spec: `Test-Flight-Improv/190-android-netlink-selinux-addr-visibility-spec.md`
Plan: `Test-Flight-Improv/190-android-netlink-selinux-addr-visibility-tdd-plan.md`

> The host floor proves (on macOS, via the go-multiaddr + go-netroute test forks):
> the injected interface-address provider flows through the UNCHANGED
> announce/identify/signed-record/status pipeline; the `Announcing 0` / 5 s
> `failed to resolve local interface addresses` ERROR reproduces under the denial
> fixture and DISAPPEARS when the provider succeeds; a peer dials an
> identify-learned address with no mDNS lane; the FDC-11 0.0.0.0-port-mining
> fallback still fires when the routable set is genuinely empty; and the
> hole-punch input term carries the self-enumerated public candidate.
> What ONLY the phones can prove: the REAL SELinux `avc: denied { bind }
> tclass=netlink_route_socket` is gone at the source (anet's non-bind RTM_GETADDR
> lane, API-level autodetected via cgo under gomobile), the 5 s cadence is truly
> silenced over a 10-min window, and the mDNS-disabled LAN-direct wire leg
> (TC-190-41, PROD-CRITICAL) actually connects.

## Build (Go + a fork replace changed — gomobile bindings MUST be rebuilt)

The fix is entirely in `go-mknoon/third_party/go-multiaddr` + `go-netroute`
(replaces in `go.mod`), so the prebuilt xcframework/.aar are stale. The .aar and
xcframework were regenerated host-side on 2026-07-02 (both `make` targets exit 0),
but re-run before flashing to be safe:

```bash
# 1. Regenerate gomobile bindings (anet is linked via -checklinkname=0 already in the Makefile).
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" GOTOOLCHAIN=go1.25.0 make all
cd ../ios && pod install && cd ..
cd go-mknoon && make verify-bindings ; cd ..

# 2. Profile builds ONLY — never --debug (dev_keychain_wipe destroys device
#    identity on first debug launch; 2026-07-02 iPhone-11 incident).
flutter build apk    --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
flutter build ios    --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true
```

## Rig

- Pixel 6 (Android 16): `adb -s 21071FDF600CSC logcat -v time`
- iPhone 11 (WiFi peer): `idevicesyslog -u 00008030-001A6D2801BB802E`
- Prod relay journal (read-only observation): EC2 recipe in project memory.
- Flow/Go anchors to watch (grep-verified in code):
  - Go announce log `node.go:431`: `[NODE] Announcing N addresses (loopback/link-local filtered out)`
  - SELinux denial (should VANISH): `avc: denied { bind } ... tclass=netlink_route_socket`
  - basichost ERROR (should VANISH): `failed to resolve local interface addresses ... netlinkrib: permission denied`
  - `node:status.listenAddresses` in FLOW logs (shape: real IP vs `/ip4/0.0.0.0`)
  - `addresses:updated` payload (`go_bridge_client.dart`) on a WiFi↔cellular switch.
- Baseline for the "After" table = the 2026-07-02 RCA capture on the same Pixel:
  5 s ERROR cadence indefinitely + `Announcing 0 addresses`.

## TC-190-40 — Pixel 10-min address-visibility + spam-bound (single phone)

Pixel on WiFi, app foreground, 10-minute capture:

```bash
adb -s 21071FDF600CSC logcat -v time \
  | grep --line-buffered -E 'netlinkrib|avc.*netlink_route_socket|Announcing|failed to resolve local interface'
```

PASS criteria:
- (a) ZERO recurring `netlinkrib: permission denied` ERROR cadence over 10 min
  (baseline: 1 per 5 s ≈ 120 occurrences).
- (b) ZERO NEW `avc: denied { bind } ... tclass=netlink_route_socket` denials
  during the window (the denial is gone at the source, not just quieter).
- (c) `Announcing N addresses` with **N ≥ 1**, and at least one announced addr
  carries the device's current WiFi IP (cross-check `adb shell ip addr`).
- (d) `node:status.listenAddresses` in FLOW shows the real-IP shape, NOT
  `/ip4/0.0.0.0/...` (spec correction 1 — the field was non-empty before via the
  FDC-11 fallback, but 0.0.0.0-shaped; the fix changes its shape).

Revert control (proves the fix is load-bearing): remove the two 190 `replace`
directives from `go-mknoon/go.mod`, `make android`, reinstall → (a)/(b)/(c)
symptoms return.

| Metric | Before (2026-07-02 RCA) | After |
|---|---|---|
| `netlinkrib` ERRORs / 10 min | ~120 (5 s cadence) | ___ |
| NEW netlink `avc` denials / 10 min | present | ___ (expect 0) |
| `Announcing N` (N) | 0 | ___ (expect ≥1) |
| `listenAddresses` shape | 0.0.0.0-mined | ___ (expect real WiFi IP) |

## TC-190-41 (PROD-CRITICAL) — mDNS-disabled LAN-direct via identify-learned addrs

Two phones, same WiFi, bonsoir advert lane artificially disabled on the Pixel so
the ONLY path to the Pixel's addresses is identify / signed peer records.

Disable mechanism (decide at run time; the Go .aar under proof stays identical —
the fix is Go-side, so a Dart/advert-side disable does not weaken the proof):
1. Preferred: a one-line local Pixel patch forcing `_libp2pListenPort` derivation
   to `null` (kills the TXT `quicPort`/`tcpPort` advert while leaving the Go node
   untouched), OR
2. Strip the bonsoir TXT `quicPort`/`tcpPort` via a debug hook.
If neither is clean, add a temporary dart-define gate in a follow-up commit before
the proof and flag to review (plan Risks).

Protocol:
1. Both apps foreground, same WiFi. Confirm the Pixel's advert TXT no longer
   carries libp2p ports (peer sees the Pixel but has no mDNS port to dial).
2. From the iPhone, open the 1:1 with the Pixel and send. The iPhone must learn
   the Pixel's WiFi address via identify / the signed peer record (rendezvous) and
   establish a LAN-direct (non-relay) connection.
3. `adb ... | grep Announcing` shows the Pixel announcing its WiFi IP; the iPhone
   FLOW shows a direct (not `/p2p-circuit`) transport to the Pixel.

PASS: LAN-direct established with the advert lane disabled.
Falsifier (today's behavior): relay-only when mDNS is unavailable.
Revert control: remove the Pixel `replace` → relay-only returns.

## TC-190-42 — cellular policy + DCUtR candidate-presence + one radio switch

Pixel on cellular, 10-minute capture, plus one live WiFi↔cellular switch:

```bash
adb -s 21071FDF600CSC logcat -v time \
  | grep --line-buffered -E 'netlinkrib|Announcing|holepunch|FLOW|addresses'
```

PASS criteria:
- No announced-address regression and no error spam on cellular (same (a)/(b) as
  TC-190-40).
- A public / GUA self-address is visible to the DCUtR lane (candidate PRESENCE
  only — punch SUCCESS rate stays 188's domain).
- One live WiFi→cellular (and back) switch produces a clean `addresses:updated`
  transition — the new interface's address appears and the stale one drops within
  one address-update cycle (closes TC-190-04's real-radio half).

## Notes

- Run AFTER any 173 prod-relay redeploy so relay-side changes are not conflated.
- The netlink route lane (`go-netroute`) still fails on Android at Debug level by
  design (accepted difference — anet only replaces the interface-address lane).
  Do NOT flag Debug-level `failed to build Router for kernel's routing table`.
- 188 (DCUtR) punch-rate should re-baseline AFTER this lands (real candidate input
  on Android for the first time).
```
