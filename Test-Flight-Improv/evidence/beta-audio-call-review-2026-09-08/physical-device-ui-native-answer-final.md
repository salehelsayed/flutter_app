# Final native-answer package physical-device proof

Recorded 2026-09-08, UTC. **PASS for both answered directions, decline cleanup, and a successful fresh retry.** Existing USB Pixel and iPhone 11 lab contacts were used; app data was preserved. This document adds final repaired-package evidence and does not replace earlier failed attempts.

Build binding:
- Android observer APK SHA-256: `cf02f315392ba12d42af5ea93b11264303bcfdc052c57563550cc9d906919085`.
- iPhone 11 profile Runner tree SHA-256, supplied by the installing root agent: `c96f88495b044f12ea24137887aea24ec61f0e6dd1f48bfd7ab44d5832cecd0d`; installed/launch reported at 12:17:48 UTC. See the adjacent final build manifest for production build provenance.
- Android full-screen intent permission remained enabled throughout. No permission change was made by this UI harness.

| Run | Direction and answer/decline surface | Caller start verified | Action completed | End completed | Result |
| --- | --- | --- | --- | --- | --- |
| native-answer-i2a-01 | iPhone → foreground Pixel; in-app Answer | 12:22:14.673 | Answer 12:22:16.974 | Pixel End 12:23:02.079 | Accepted, connected, both RTP directions, terminal |
| native-answer-a2i-01 | Android → background iPhone; native CallKit banner Answer | 12:23:14.765 | Answer 12:23:29.030 | Pixel End 12:24:20.628 | Accepted, connected, both RTP directions, terminal |
| native-answer-decline-i2a-01 | iPhone → foreground Pixel; in-app Decline | 12:24:31.165 | Decline 12:24:33.480 | Terminal stop receipt | Ringing → terminal; never accepted/connected, as expected |
| native-answer-retry-i2a-01 | Fresh iPhone → foreground Pixel retry; in-app Answer | 12:24:49.674 | Answer 12:24:52.371 | Pixel End 12:25:24.336 | Accepted, connected, both RTP directions, terminal |

For all three answered-call **stop receipts**, acceptedObserved, connectedObserved, terminalObserved, activeCallSurfaceObserved, structuralMediaReadyObserved, relayOnlyObserved, localAudioEnabledObserved, inboundAudioRtpObserved, and outboundAudioRtpObserved are true. Selected relay transport is `turn_udp`. Each receipt independently binds to the final observer APK hash and a fresh run/nonce. The decline receipt has ringingObserved and terminalObserved true, with acceptedObserved and connectedObserved false. A separate fresh retry then passed the same complete media assertions.

The strengthened helper required the expected lab identity, a live Calling/Ringing state, and Cancel/End control after each Start tap. The direction reversal before the decline run encountered the previous call's terminal notice: waitedForTerminalNotice=true, followed by verified Calling + Cancel. This confirms that the helper now waits for the six-second notice to clear instead of treating an underlying Start tap as a call start. It does not retroactively prove the cause of the earlier unconfirmed tap.

All call actions used freshly observed UI controls. Pixel answers/decline were performed in the foreground app without opening the notification shade. iPhone was backgrounded before its incoming leg, and its native CallKit Accept/Answer call button was used. Both phones returned to the exact lab conversation with enabled Start and no Answer/Decline/End controls at 12:25:29 UTC. All observers were stopped. Control was handed to root for normal Android APK restoration and observer-file cleanup; no redundant observer run is required for that package restoration.

Proof scope: these are physical-device signaling, UI, bidirectional audio-RTP transport, relay selection, and cleanup observations from the Pixel's read-only observer. They do not measure human-perceived sound quality or exhaustive carrier/network coverage. The standalone wakeAuthorityReady field remains false in these receipts and is not used to claim media failure or readiness completion. The background iPhone leg directly demonstrated incoming CallKit presentation and an answered connection.

Privacy: this report and copied receipts/actions contain fixed states, timestamps, build hashes, and pseudonymous run bindings. No tokens, call handles, encrypted envelopes, ICE candidates, audio recordings, message contents, raw phone logs, or screenshots are included. Complete hierarchy snapshots remain local-only under /tmp for debugging and were not copied to the report directory. In observer receipts, top-level success=true means the observation command completed; the explicit call/media assertions above determine the call result.
