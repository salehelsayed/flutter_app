# Answered physical-device calls, 2026-09-08 UTC

Both runs used the existing Pixel/iPhone-11 lab contact pair without resetting app data. The Pixel observer APK SHA-256 was `c95cdf319c6521fdf4bc09437da8bfdb7d8b59687b23ddedde5e96da4ebafe1e`. These are the packages installed before the final readiness/native presentation refinements; a final-build repeat remains separate.

| Run | Direction/surface | UI commands started (UTC) | Stop receipt |
| --- | --- | --- | --- |
| background-a2i-05 | Android to background iPhone; native CallKit banner | Start 11:46:39.086; answer 11:46:41.377; end 11:48:12.472 | caller, complete |
| foreground-i2a-fsi-03 | iPhone to Android; native notification shade, full-screen permission enabled | Start 11:49:45.789; answer 11:49:46.926; end 11:50:12.815 | callee, complete |

For **both** stop receipts, accepted, connected, terminal, active call surface, structural media ready, relay-only transport, local audio enabled, inbound audio RTP, and outbound audio RTP are true. Selected relay transport is `turn_udp`. This proves signaling and bidirectional RTP transport from the Pixel observer; it does not measure human-perceived sound quality. `wakeAuthorityReady` is false in both receipts and is not used to infer transport failure.

Timestamp caveat: the harness originally stamped each command before executing it, so those timestamps are command starts, not exact taps. Successful returns confirm completion. WDA commands can take several seconds; current helper additionally records completedAt.

Automation findings: native iOS CallKit wraps the visible lab caller name in Unicode bidirectional format marks; normalization preserves exact lab identity matching. Android's native notification uses the privacy label `MKnoon caller`; action is bound to the newly harness-started pinned lab call plus visible native MKnoon application and a less-than-30-second window. Full-screen permission did not automatically open a full-screen Activity while the Pixel was unlocked; the notification Answer action worked. Both calls ended via the visible in-app End button, followed by terminal stop receipts. No raw phone logs, screenshots, or unrelated UI contents are included here.
