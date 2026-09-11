The offline preflight record uploaded automatically after networking returned.

Trace `eec02a59-40f7-44c5-9568-34cf7f191518` contains two Flutter caller records: attempt/start at 15:24:10.351 UTC and terminal/preflight_failed with reason `graph_unavailable` at 15:24:10.353 UTC. The then-installed Android build was `1.0.1+111-447d22a1e20fb7ae`, whose call graph was disabled. This verifies persistence and retry of a failed attempt recorded offline; it does not attribute the preflight rejection to the network or claim that audio started.

Wi-Fi was restored at 15:25:04.147870 UTC. The relay durably received the two records at 15:29:53.669 and 15:29:53.674 UTC, approximately289.521 seconds after restoration. The phone's acknowledged-upload timestamp advanced to 15:29:55.627 UTC. The device controller observed zero unacknowledged records and zero drops in the final capture, with no manual flush, restart or reinstall between restoration and acknowledgement.

The exact two event IDs match in all three device archives—offline, restored-before-upload and acknowledged-after-retry—and the sanitized relay projection. The comparison and strict projected events are saved in `offline-preflight-upload-proof.json`; private device archive contents are not copied into this report.

The corrected production operator at 15:36:39 classifies this trace as preflight rejection1/1, with post-preflight technical setup0/0 and a null rate because no eligible post-preflight attempt occurred. It reports a caller terminal, no callee terminal, no mailbox admission, no answer and no media. No rate alert is eligible below five observations. The original projection defect and its exact regression remain documented in `operator-preflight-regression-validation.json`; the fixed projection is in `relay-operator-live-20260908T153639Z.json`.

This is one opted-in lab attempt. It establishes local durability, autonomous bounded retry, server receipt and accurate preflight classification; it does not establish successful audio, both-endpoint completeness, or coverage of nonconsenting/legacy calls.
