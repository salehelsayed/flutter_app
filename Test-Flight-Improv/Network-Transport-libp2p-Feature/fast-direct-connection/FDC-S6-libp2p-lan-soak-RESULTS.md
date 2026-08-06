# FDC-S6 — libp2p-LAN soak / WS-retirement: RESULTS

Status: **CLOSED — conservative keep decision (2026-08-06): retire-chat = N /
retire-media = N / keep-bonsoir = always.** The retirement evidence bar was not
met. This is not a successful soak claim: the existing cross-platform pilots are
underpowered, there is no matched WS baseline, and the availability-bounded
Android pair cannot share an L2 LAN. The fail-safe therefore keeps both chat
transports and creates no WS-removal plan or automatic Plan 341.

Parent spike: `FDC-S6-libp2p-lan-soak-ws-retirement-decision.md`. Harness,
parser, and the admitted legacy pilot logs live under `fdc-s6-measurement/`.

---

## 1. Measurement integrity

The host precondition passed on 2026-08-06:

```text
flutter test test/core/debug/transport_metrics_test.dart \
  test/core/local_discovery/lan_address_classifier_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
124 tests passed
```

The campaign audit corrected two measurement defects before re-reading the
legacy logs:

- `CHAT_MSG_RECEIVE_STORED` now carries the committed row's `transport`, so a
  logical receive outcome can be counted without treating replay-prone raw
  arrival legs as independent sends.
- `fdc_s6_parse.py` now scopes bonsoir/private-IP discovery to each trial,
  treats stored outcomes as authoritative when present, retains a documented
  legacy raw-log fallback, and validates Wilson/Newcombe calculations. Its
  three Python unit tests pass.

These are observation-only changes. They do not change send, receive, dedup, or
transport selection behavior.

---

## 2. Availability-bounded matrix and stop receipt

The live matrix was resolved with `flutter devices --machine`, `adb devices`,
and `xcrun simctl list devices available` on 2026-08-06.

| Direction | Resolved targets | Disposition |
|---|---|---|
| A→A | USB Pixel 6 `21071FDF600CSC` (Android 16/API 36, Wi-Fi `192.168.0.240/24`) + `emulator-5554` (Android 17/API 37, NAT `10.0.2.15/24`, `wlan0` down) | **N/A (target topology unavailable by project policy).** The required default Android pair cannot share an L2/mDNS LAN; no send count is admitted. |
| i→i | USB iPhone 11 `00008030-001A6D2801BB802E` + USB iPhone 13 `00008110-00184D622289801E` (both iOS 26.5) | **Not admitted.** Host UI automation is disabled and the disposable profile file-channel did not reach identity export. Those are harness-boundary observations, not transport results; the attempt was stopped rather than repaired recursively. |
| A↔i | Historical Pixel/iPhone pilots already in `fdc-s6-measurement/logs/pilot*` | **Admitted only as legacy pilot evidence.** No new iPhone run was added. |

The iOS setup attempts and the zero-line Android topology probe are excluded
from all rates below. No unavailable device/version is recorded as an
environment blocker, evidence gap, or failed transport gate.

---

## 3. Existing pilot dataset re-parsed at current HEAD

The table deliberately separates the two cross-platform directions. Legacy
logs lack `CHAT_MSG_RECEIVE_STORED`; the parser therefore used its raw-log
fallback and trial-local discovery markers. This makes the numbers useful for
the keep decision, but not sufficient to authorize retirement.

| metric | A→A | i→i | A→i legacy | i→A legacy |
|---|---|---|---|---|
| logical sends | N/A | not admitted | 107 | 97 |
| clean libp2p-LAN wins | — | — | 54/107 (50.5%) | 0/97 |
| win-rate Wilson 95% LB | — | — | 41.1% | 0.0% |
| bonsoir-fed reliability | — | — | 54/54; LB 93.4% | 0/0; N/A |
| ambiguous `direct` legs | — | — | 53 | 84 |
| WS `wifi` logical wins | — | — | 0 | 13 |
| matched-baseline Newcombe upper CI | N/A | N/A | N/A — no baseline | N/A — no baseline |
| double delivery | — | — | 1/107 = 0.9%; `direct+inbox` | 10/97 = 10.3%; `wifi+direct` 9, `direct+wifi` 1 |

Both cross directions are below the required 385 sends. A→i also misses the
95% lower-bound bar even in the bonsoir-fed subset (93.4%); i→A lacks the
trial-local discovery evidence needed to certify its raw `direct` legs. The
10.3% i→A collision rate is a meaningful cost signal, but it is not permission
to remove the proven WS path.

---

## 4. Verdict

- **retire-chat = N.** Required sample floors, platform directions, and matched
  baseline non-inferiority evidence are absent. The spike's explicit
  thin-or-mixed-data fail-safe applies: keep the ranked race and receiver
  `messageId` dedup.
- **retire-media = N.** LAN media remains a separate component; there is no
  retirement-grade matched soak and no recorded relay-CDN-only acceptance.
- **keep-bonsoir = always.** Discovery remains separate from chat-envelope and
  media transport.
- **Follow-on plan = none.** Do not author a WS-chat-removal plan and do not
  treat this receipt as Plan 341.
- **Telemetry-gated work remains telemetry-gated.** Connection single-flight,
  relay-classification cleanup, cross-FFI cancellation, DCUtR changes, and
  timing retuning are unchanged by this decision.

Version context: go-libp2p `v0.39.1` / quic-go `v0.49.0`. A future retirement
attempt must be explicitly reopened and must resolve a new live matrix first;
it is not an automatic roadmap successor.

---

## 5. Reproduce the admitted pilot summaries

```bash
python3 fdc-s6-measurement/scripts/fdc_s6_parse.py \
  --label existing-a2i \
  fdc-s6-measurement/logs/pilot*_a2i/*.log

python3 fdc-s6-measurement/scripts/fdc_s6_parse.py \
  --label existing-i2a \
  fdc-s6-measurement/logs/pilot*_i2a/*.log

python3 -m unittest \
  fdc-s6-measurement/scripts/test_fdc_s6_parse.py
```
