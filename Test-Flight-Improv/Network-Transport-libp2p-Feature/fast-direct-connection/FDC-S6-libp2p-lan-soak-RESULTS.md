# FDC-S6 — libp2p-LAN soak / WS-retirement: RESULTS

Status: **instruments + harness landed + host-verified (preconditions ✅); device
soak PENDING — hard-gated on FDC-11 D1 device-proof (still FDC-11's open closure
gate).** No verdict yet: the per-component decision cannot be issued until the
soak runs on real iOS+Android pairs over ≥ 385 sends/platform-
direction (duration floor removed by decision 2026-06-29 — no 14-day soak; the
≥ 385-sample Wilson-LB criterion is the sole gate). This mirrors FDC-S1/S4 (instrumentation landed; numbers filled by the
device campaign).

Parent spike: `FDC-S6-libp2p-lan-soak-ws-retirement-decision.md`. Harness +
parser + per-trial logs live under `fdc-s6-measurement/`.

---

## 1. Instruments landed (observation-only, additive — host-verified)

All inert without `--dart-define=FDC_FLOW_LOG=1`. No send/receive behaviour changed.

| Spike instrument | Where | Signal | Host check |
|---|---|---|---|
| **Precondition** — `'upgraded'→'direct'` label-bucketing lock | `test/core/debug/transport_metrics_test.dart` | RED if the FDC-13 fold is removed | GREEN; mutation-verified RED-able (remove the `case 'upgraded'` arm → exactly 1 test fails) |
| **2 — private-IP discriminator** (net-new) | `lib/core/local_discovery/lan_address_classifier.dart` + `P2P_LAN_PEER_FOUND_REQUEST{peer, lanPrivateIp}` (`p2p_bridge_client.dart`) | per-peer RFC1918/link-local/ULA boolean, computed before emit (raw multiaddr is redacted out of logs) | `lan_address_classifier_test.dart` GREEN; 0 new analyze issues |
| **5 — double-delivery counter** (net-new) | `CHAT_MSG_DOUBLE_DELIVERY{id, kept, dropped}` at the messageId-dedup drop (`handle_incoming_chat_message_use_case.dart`) | `(kept, dropped)` transport-leg pair of every same-id collision | `handle_incoming_chat_message_use_case_test.dart` GREEN (new case) |
| **1 — win leg per send** (reused) | `MSG_RECEIVED_TRANSPORT{from, transport}` (`p2p_service_impl.dart`) | the leg that delivered: `wifi`/`direct`/`relay`/`inbox`/`reuse`/`upgraded` | pre-existing |

**Build flag:** `--dart-define=FDC_FLOW_LOG=1` forces `flowEventLoggingEnabled=true`
(`main.dart`) → the four FDC-S6 events reach logcat/idevicesyslog as
`[FLOW] {json}`. OFF/inert in a normal build.

**LAN-dial gates the soak binary needs ON:** Go `EnableLibp2pLANDial`
(`feature_flags.go`, default false) **AND** the Dart `'p2p_lan_dial'` runtime gate.

---

## 2. Device matrix — PENDING

| Class | Device | OS | Status |
|---|---|---|---|
| Android | — | — | not run (awaiting FDC-11 D1) |
| iOS | — | — | not run (awaiting FDC-11 D1) |
| Cross (Android↔iOS) | — | — | not run |

Real devices only (sim shares the host bonsoir stack). Both arms (LAN-dial ON and
the WS baseline with the gate OFF) must log the SAME lines for a comparable delta.

---

## 3. Soak dataset — TO FILL (one block per platform-direction)

Run `python3 fdc-s6-measurement/scripts/fdc_s6_parse.py --label <dir> [--baseline-file ...] <logs>`
and transcribe. Gate: Wilson 95% LB ≥ 95% over n ≥ 385; failure-delta Newcombe
upper 95% CI ≤ +1.0pp.

| metric (per platform-direction) | A→A | i→i | A↔i |
|---|---|---|---|
| n (same-WiFi sends) | | | |
| libp2p-LAN win-rate (point) | | | |
| libp2p-LAN win-rate (Wilson 95% LB) | | | |
| WS `wifi` win share | | | |
| ambiguous `direct` (WAN/DCUtR, not counted) | | | |
| bonsoir-fed-dial reliability (Wilson 95% LB) | | | |
| failure-rate delta vs WS baseline (Newcombe upper 95% CI) | | | |
| double-delivery rate (and top leg-pair) | | | |

---

## 4. VERDICT — TO FILL (then mirror into the spike's VERDICT block + flip Status)

- **retire-chat?** `<Y/N + which thresholds cleared/missed>`
- **retire-media?** `<N unless FDC-15 device-proven + soak, OR explicit relay-CDN-only acceptance>`
- **keep-bonsoir** = always (iOS entitlement — not measured, permanent).
- **Follow-on plans named (if "retire"):** WS-chat-removal plan (delete the
  `LocalWsServer` chat path + **drop the now-dead `wsPort` TXT advert** — the
  libp2p QUIC/TCP ports are already advertised since FDC-11 — + drop the
  nonce-ACK) / media-over-libp2p (FDC-15) or the recorded relay-CDN-only acceptance.

**Version pin:** go-libp2p `v0.39.1` / quic-go `v0.49.0` (`go-mknoon/go.mod`) — the
soak verdict is pinned to this pair; **re-run the soak on any go-libp2p bump**
(marker comment beside the require line points back here).

---

## 5. Reproduce
```bash
# preconditions (host)
flutter test test/core/debug/transport_metrics_test.dart \
             test/core/local_discovery/lan_address_classifier_test.dart \
             test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
# then the device soak — see fdc-s6-measurement/README.md §Run / §Procedure.
```
