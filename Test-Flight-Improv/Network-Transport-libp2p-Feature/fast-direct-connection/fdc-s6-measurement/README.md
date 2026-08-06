# FDC-S6 measurement harness — libp2p-LAN soak / WS-retirement decision

Device-only soak that produces the dataset the FDC-S6 **per-component verdict**
keys on: the libp2p-LAN chat **win-rate**, the **net-new-failure delta** vs the
bonsoir+WS baseline, **bonsoir-fed-dial reliability**, and the **double-delivery
rate** — on eligible targets from the availability-bounded live matrix, over
**≥ 385 sends per platform-direction** when retirement is being considered.

Results doc this feeds: `../FDC-S6-libp2p-lan-soak-RESULTS.md`.

> **Decision receipt:** FDC-S6 closed on 2026-08-06 with `retire-chat = N`,
> `retire-media = N`, and `keep-bonsoir = always`. The current live matrix did
> not support an admissible full campaign, and the legacy pilots were
> underpowered. These instructions are retained only for an explicitly reopened
> future retirement decision; they are not an automatic next plan.

> Resolve targets at execution time with `flutter devices --machine`,
> `adb devices`, and `xcrun simctl list devices available`. For a non-iOS-
> specific two-peer leg, use the discovered USB Android + Android emulator by
> default. If they cannot share the required L2/mDNS LAN, record the leg
> `N/A (target topology unavailable by project policy)`; do not substitute an
> iPhone or repair an iPhone harness recursively. Use iPhones only for a
> separately justified iOS/parity claim, with automated setup and assertions.

## What it reads (logical outcomes plus diagnostic legs)
All landed in the tree; observation-only; inert without `--dart-define=FDC_FLOW_LOG=1`:

1. **Logical receive outcome** — receiver-side `CHAT_MSG_RECEIVE_STORED`
   includes the committed row's `transport`. This is the denominator for current
   logs and prevents inbox replay or a parallel raw arrival from becoming a
   second logical send.
2. **Raw arrival-leg census** — `MSG_RECEIVED_TRANSPORT`
   `{from, transport}` (`p2p_service_impl.dart`) remains diagnostic. `transport`:
   `wifi` = WS LAN won · `direct` = libp2p (gated below) · `relay`/`inbox` =
   neither LAN leg won · `reuse`/`upgraded` = conn-reuse / DCUtR fold (EXCLUDED
   from a LAN win — not a fresh dial).
3. **Private-IP discriminator (net-new, FDC-S6)** — `P2P_LAN_PEER_FOUND_REQUEST`
   now carries `{peer, lanPrivateIp}` (`p2p_bridge_client.dart` +
   `lan_address_classifier.dart`). The raw multiaddr is **redacted out of the log**
   by `flow_event_emitter`, so the private-IP gate is computed *before* emit and
   carried as a non-sensitive boolean. A clean **libp2p-LAN win** = a `direct` leg
   whose peer was **bonsoir-fed** (a `P2P_LAN_PEER_FOUND_REQUEST` fired) **AND**
   `lanPrivateIp:true`. A bare `direct` without both guards is **ambiguous**
   (could be WAN/DCUtR) and is **not** counted as a LAN win — the spike's ⚠ caveat.
4. **Double-delivery counter (net-new, FDC-S6)** — `CHAT_MSG_DOUBLE_DELIVERY`
   `{id, kept, dropped}` at the messageId-dedup drop
   (`handle_incoming_chat_message_use_case.dart`). Counts collisions keyed by the
   `(kept, dropped)` transport-leg pair.

## Run

Only use this section after an explicit decision to reopen FDC-S6.

```bash
# 0. native libs with the declared toolchain (GOTOOLCHAIN pin — see project memory)
( cd ../../../../go-mknoon && PATH="$HOME/go/bin:$PATH" GOTOOLCHAIN=go1.25.0 make android )  # and: make ios

# 1. build BOTH devices with flow-log ON. The libp2p-LAN lane needs the Go flag
#    EnableLibp2pLANDial AND the Dart 'p2p_lan_dial' runtime gate open.
flutter build apk --profile --target-platform android-arm64 --dart-define=FDC_FLOW_LOG=1
flutter build ipa --profile --dart-define=FDC_FLOW_LOG=1
#    Keep BOTH LAN stacks live (bonsoir+WS AND libp2p-LAN) — within-pair attribution,
#    NOT a sequential A/B (spike Method point 3). The baseline arm = LAN-dial gate OFF.

# 2. per trial: capture on the RECEIVING target(s), then let the automated
#    harness drive setup, permissions, navigation, sends, and assertions.
bash scripts/fdc_s6_capture.sh android <udid> logs/aa pixelA      # Android->Android
bash scripts/fdc_s6_capture.sh ios     <udid> logs/ii iphoneA      # iOS->iOS
#    For the cross pair run both captures at once (Android<->iOS).

# 3. parse one platform-direction's trials → win-rate (Wilson LB), double-delivery,
#    failure rate. Add --baseline-file for the non-inferiority CI.
python3 scripts/fdc_s6_parse.py --label "androidA->androidB" logs/aa/*.log
python3 scripts/fdc_s6_parse.py --label "iA->iB" --baseline-file logs/ii_baseline/*.log logs/ii/*.log
```

Self-test the parser with
`python3 -m unittest scripts/test_fdc_s6_parse.py`. The parser scopes discovery
per trial, prefers stored logical outcomes, and uses a legacy raw-log fallback
only for the checked-in pilots that predate `CHAT_MSG_RECEIVE_STORED`.

## Procedure (per trial)
1. Both eligible targets are foregrounded on the **same WiFi/L2 LAN**, both
   built with the flags above and pinned by explicit IDs.
2. Start `fdc_s6_capture.sh` on the receiver(s).
3. Compose-and-send a batch of 1:1 messages **both directions** (sender↔receiver).
4. Ctrl-C the capture when the batch is acked on both ends.
5. Repeat until the **≥ 385 sends/platform-direction** sample floor is cleared
   (the parser flags UNDERPOWERED below it; duration floor removed by decision
   2026-06-29 — no 14-day soak, the sample floor is the sole gate). Cover
   for every eligible direction required by the explicit parity claim.
6. Run a matched **baseline arm** (LAN-dial gate OFF, same pairs/location/window,
   logging the SAME lines) so the failure-delta has a comparable baseline.
7. **Stop rule:** a setup, permission, file-channel, or topology failure is not a
   transport sample. Exclude it and record the availability-bounded disposition;
   do not keep modifying the iPhone harness inside the campaign. Thin or mixed
   admissible data produces the safe `KEEP` verdict.

## Decision Criteria (the parser checks these; full text in the spike)
- **Retire WS chat** iff, per platform-direction: libp2p-LAN win-rate **Wilson 95%
  LB ≥ 95%** over **n ≥ 385**, bonsoir-fed-dial reliability at the same bar, and
  the **Newcombe 95% CI on [failureRate(ON) − failureRate(baseline)] ≤ +1.0pp**.
  (Duration floor removed by decision 2026-06-29 — no 14-day soak; the ≥ 385-sample
  Wilson-LB criterion is the sole gate. Verdict issues once the sample floor + the
  statistical bars are met, regardless of calendar span.)
- **Retire WS media**: out of scope here — gated behind FDC-15 device-proof+soak
  OR an explicit relay-CDN-only acceptance.
- **bonsoir discovery: KEEP ALWAYS** (iOS entitlement — permanent).
- **Fail-safe**: any miss → KEEP both LAN stacks (the always-safe default).
  A keep decision may close with an incomplete/N/A matrix as long as it records
  the missed retirement gates and does not claim a successful soak.

## Soak precondition (lock the instrument first)
`flutter test test/core/debug/transport_metrics_test.dart` must stay GREEN — it
now includes the net-new `'upgraded'→'direct'` label-bucketing lock (mutation-
verified RED-able). The whole dataset rests on the labels bucketing correctly.

## Known boundary
The win-leg classification uses **bonsoir-fed + lanPrivateIp** as the private-IP
gate (the raw multiaddr can't ride the redacted log). `node:lan_peer_found` (Go)
carries only `{peer, addrCount}` — no address — so there is **no second,
Go-side** private-IP source to cross-check against; the Dart `lanPrivateIp`
boolean is authoritative. If a future need arises to confirm the IP family
Go-side, emit a pre-computed boolean in `lan_dial.go`'s `node:lan_peer_found`
(do NOT log the raw multiaddr).
