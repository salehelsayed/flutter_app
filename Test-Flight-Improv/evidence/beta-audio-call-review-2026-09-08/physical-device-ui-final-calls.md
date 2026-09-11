# Final package device QA, 2026-09-08 UTC

Android observer APK SHA-256: `71adf39af59d352bf5b56a0168e23344c2e889bfe8c12b1293de1433064fa666`. Root installed and launched the final iOS profile at 11:58:23 UTC. Existing pinned Pixel/iPhone-11 lab contacts and app data preserved. FSI permission remained enabled.

| Run | Action completion times (UTC) | Pixel observer result |
| --- | --- | --- |
| final-a2i-01 | Android start 11:59:10.663; background iOS CallKit answer 11:59:37.664; Android End 12:00:23.833 | PASS: outgoing, ringing, accepted, connected, terminal; structural media, relay-only TURN UDP, local audio, inbound RTP and outbound RTP all true |
| final-i2a-01 | iOS start 12:00:30.140; Android control wait expired 12:00:57.450 | No incoming call observed: empty stateSequence and null callBindingSha256. No answer or end action. |
| final-i2a-02 | iOS start 12:01:39.618; foreground Android Answer 12:01:42.692 | FAIL: ringing, accepted, terminal; never connected; no RTP. No hang-up action was made. The foreground in-app Answer control was reached without opening notifications. |

These results do not constitute final two-direction acceptance. The reverse failure requires causal inspection. The observer's top-level `success=true` means the read-only observation command completed; it is not a call-success assertion. All observers were stopped and further device actions paused after preserving the failure. Decline/retry remains pending.

Raw phone logs and full UI snapshots are excluded from this report. Sanitized action completion records and individual observer receipts are stored beside this file.
