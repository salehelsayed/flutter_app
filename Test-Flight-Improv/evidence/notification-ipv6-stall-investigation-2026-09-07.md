# Follow-up: underlying iPhone APNs connection stall

## Current conclusion

The delay is caused by an **idle IPv6 Apple push connection ceasing to receive inbound traffic**, while iOS continues treating it as usable until its 600-second heartbeat plus 35-second grace expires. Reconnection then releases the stored notification. A controlled router experiment now strongly implicates the router's IPv6 filtering or connection-state handling: after adding a temporary IPv6 exposure rule, the same production connection received its idle heartbeat; after removing the rule, that same connection missed its next heartbeat and again showed a 26-byte receive-sequence gap.

The global firewall remained enabled. The exception targeted one iPhone and one TCP port, but the **unexposed sandbox connection also recovered during the rule interval**. This prevents attributing the result solely to an isolated per-port bypass; applying the rule may rebuild broader host/filter state. The exact internal predicate, timeout, or firmware implementation remains unproved. No router WAN/LAN trace or internal state table is available to identify the precise packet-drop mechanism.

Independent controls support this localization: idle IPv4 APNs worked directly through the same Wi-Fi/router/ISP for both 600- and 900-second cycles, and IPv6 worked over a cellular path using the same iPhone 13 and Apple destination as an original-Wi-Fi failure. Fresh IPv6 Apple traffic and correct router-to-phone neighbor addressing also worked within seconds of an older flow's missed heartbeat. No app-owned defect explaining the pre-ingress delay has been reproduced or fixed.

The product requirement remains automatic recovery across environments, without special router configuration. Router access and any proposed temporary configuration test serve diagnosis only.

## New device and packet evidence

All timeline times below are UTC on 7 September 2026. Device text logs display Berlin UTC+2.

- iPhone 11 remained awake on USB. 134 Wi-Fi samples across 14:47:45–14:58:44 show continuous association uptime, unchanged channel, RSSI between −51 and −46 dBm, and successful radio traffic around the media sends. No relevant Wi-Fi roam/disconnection or APNs path transition was recorded.
- APNs explicitly negotiated **server-originated keepalives**, interval 600 seconds and grace 35 seconds. The initial acknowledgment succeeded; the next expected inbound heartbeat did not arrive. This was not a client probe first sent at the 600-second mark.
- iPhone 11's production and development connections repeatedly failed around 14:26:39, 14:37:16, 14:47:53–54, 14:58:31–32, and 15:09:09–18. This pattern predates and outlives the user's media send.
- iPhone 13's development IPv6 APNs route also failed at 14:49:05, 14:59:42, and 15:10:20, approximately 637.5 seconds apart. Its production IPv4 route received keepalive traffic and showed no corresponding failure in the examined window. That IPv4 route was active, so this is not a matched idle-duration experiment.
- A new passive capture uses the device's packet timestamps, correcting the earlier capture's host-read timestamp limitation. The continuous segment ran 15:17:40.803–15:21:22.763 and retained 98 packets. No APNs packet appeared before the first connection closure at 15:19:47.207. Both replacement connections worked immediately.
- On the production IPv6 flow, at **15:19:55.550100**, the server's packet begins at TCP sequence **3420434977**, while the phone's receive position is **3420434951**: a **26-byte gap**. Independent native tcpdump decoding, valid checksums, and the iPhone kernel's `rcv_nxt` record corroborate it. The server responds to the client's close-notify after 27.410 ms and retains coherent TCP state.

The relay timing label is **FCM provider acceptance**, not a captured direct APNs provider response or a device-delivery acknowledgment. Current [provider dispatch](../../go-relay-server/inbox.go) calls Firebase Messaging `Client.Send` at line 1093 and logs `outcome=success` after its nil-error result at line 1127. Device receipt is established separately by APSD and notification records.

The sequence gap establishes that the phone had not accepted that range in order when the later server packet arrived. A missing APNs heartbeat is compatible with its size, but the encrypted/missing record's contents and original transmission time were not observed. The gap does not identify a router drop, and an unseen teardown-time write cannot be entirely excluded. Device pcapd exposes no drop counter, and this capture starts mid-connection.

Both the older and newer sandbox resets arrived after the phone initiated closure. The client's preceding 24-byte TLS record is close-notify. Neither record is evidence that a peer reset initiated the stall or that an ordinary client keepalive was lost.

## Router inspection

The user signed in to the router's normal admin UI. The status page identifies firmware **AR01.05.063.15_082825_735.PC20.20.VF** and uptime **11 days, 18 hours, 41 minutes** at 17:29 local. The configured firewall is enabled. The connection uses native IPv6 alongside DS-Lite for IPv4.

All event categories and all severities were selected. The router exposed nine Wi-Fi events and **no firewall drop or connection-state records**. Both standard and expert views returned the same event set. The diagnostics page offers ping, traceroute, and DNS; it exposes no LAN/WAN packet capture or connection-state table. Absence of a firewall log entry does not exonerate or implicate the firewall.

The admin UI's expert display mode was used to expose these pages, then restored to standard mode. No firewall, Wi-Fi, DNS, port exposure, firmware, or account settings were changed. The first admin session ended while navigating; the user signed in again and subsequent navigation used the normal UI.

## Earlier alternate-uplink control: useful but not fully matched

The successful hotspot control used the same iPhone 11, **iOS 26.5 / 23F77**, IPv6, Wi-Fi/en0, TCP 5223, TLS 1.3, and the same 600+35-second keepalive policy. A push arrived after approximately **571 seconds idle**, on the same connection, and reset its timer.

This supports dependence on the selected network route. It did not observe a complete unattended heartbeat cycle, and the Apple endpoint hashes differ from the failing captures; full backend addresses are redacted. It therefore does not uniquely isolate this router or hold the Apple endpoint constant.

## Product recovery verification

Existing app paths already recover missed messages without requiring another push when the app can execute:

- [Connectivity-restored wiring](../../lib/app/bootstrap/production_application_bootstrap.dart) triggers immediate durable inbox retrieval.
- [Resume handling](../../lib/app/lifecycle/handle_app_resumed.dart) repairs transport and drains missed messages.
- [Notification service](../../ios/NotificationService/NotificationService.swift) begins only after APNs reaches iOS. The actual media notification's extension work took 38 ms.

**21 focused host tests passed** with the repository's pinned Flutter 3.47.2: six connectivity-restoration tests, nine parallel-resume tests, and six dropped-push coordinator tests. They verify durable retrieval without an open conversation, concurrent transport repair, retention after failures, and acknowledgment only after both inbox drains finish. They do not prove OS scheduling or carrier/network parity. Initial execution with the older PATH Flutter failed before assertions because of an incompatible native-hook cache; the pinned toolchain resolved that without cache deletion or source edits.

Apple starts a notification service extension after the notification reaches the device, and iOS does not provide arbitrary guaranteed periodic execution to suspended apps. An app-side retry timer or another push cannot promise prompt banners while this underlying APNs connection is stalled. See [Apple's notification extension documentation](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) and [Apple DTS on background execution limits](https://developer.apple.com/forums/thread/685525). Apple's network guidance requires a persistent APNs connection and permits port 443 fallback when 5223 cannot be reached; a reachable but stalled established connection is a different condition. See [Apple's APNs network requirements](https://support.apple.com/en-gb/102266).

## Latest two photos: fast and delayed while backgrounded

The user's subsequent two-image comparison was observed passively without router, network, app, or phone-state changes. The second notification was pending when the investigation began and arrived at the watchdog time predicted before its arrival.

Times in this table are **Berlin local time (UTC+2)** on 7 September:

| Milestone | First photo `d4c7bc9b…` | Second photo `d4cf1b37…` |
|---|---|---|
| Relay stores message | 17:43:37.808 | 17:48:46.687 |
| Provider accepts push, attempt 1 | 17:43:38.312 | 17:48:47.032 |
| iPhone receives notification | 17:43:38.315 | 17:54:14.639 |
| Banner fully appears | 17:43:39.862 | 17:54:17.254 |
| Provider acceptance to full banner | 1.55 seconds | 330.22 seconds (5 min 30 sec) |
| Notification extension processing | 26 ms | 41 ms |

The first photo arrived while Mknoon's main process was **already suspended**. Its successful push receipt reset the sandbox connection's 600+35-second timer at 17:43:38.316. The second push was submitted approximately 308 seconds after the last successful APNs exchange. No corresponding receipt appeared before the scheduled watchdog.

Before delivery, the OS record predicted a watchdog at **17:54:13.316**. It actually reported `KeepAliveFailed` at **17:54:13.342**, reconnected, and received the stored second notification at 17:54:14.639. Request `AC74-7D9A` carries the second send's APNs timestamp and `LastFromStorage`. First request: `017D-3714`.

The same preexisting APNs connection **C859**, local port 63568, remained in place between the fast receipt and the timeout. Server-aligned APNs timing gives **163 ms** transit for the first notification and **327.717 seconds** for the second, avoiding a relay-versus-phone clock comparison. Relay custody-to-provider intervals were 504 ms and 345 ms respectively; both were accepted on the first attempt.

This comparison supports the user's association with leaving the app idle in the background, while identifying a more specific correlate: **idle time on the Apple push connection**. Background/suspended state by itself cannot explain the pair because the fast notification also arrived in that state. A precise 300-second expiry threshold and the component responsible for any expiry remain unproved.

The live packet capture independently observed the predicted closure/reconnect and incoming encrypted burst. Its syslog stream stopped advancing at 17:51:30, so complete historical OS archives supplied the authoritative notification and presentation records; this collection limitation is recorded. All device and relay captures were stopped after the delayed receipt.

Evidence: [comparison measurements](../../build/notification-last-two-20260907/comparison.json), [combined OS evidence](../../build/notification-last-two-20260907/os/key-evidence.log), [delayed notification OS record](../../build/notification-last-two-20260907/os/pending-receipt-system.log), [relay events](../../build/notification-last-two-20260907/relay/key-events.log), [capture metadata](../../build/notification-last-two-20260907/live/capture-summary.json).

## Further OS audit and full idle-cycle control

The delayed sandbox flow C859 remained explicitly unsuspended and was not offloaded. Its topic filter remained version 8 across delivery and reconnection. The XPC interruption at 15:46:28 belongs to an already-completed DNS lookup's service connection, with no corresponding APNs TCP state change.

At 15:54:13.413, APNs attempted `PCActionShrinkPushKeepAliveInterval`, but its algorithm was already in `MinimumIntervalFallbackState` and retained 600 seconds. This explains why repeated failures did not produce progressively shorter recovery intervals. Lifetime retransmission counters cannot locate when or where loss occurred.

A new passive iPhone 11 capture began before fresh production and sandbox handshakes, addressing the earlier mid-connection capture limitation. The original Wi-Fi and enabled router firewall are unchanged.

For a full alternate-uplink comparison, iPhone 13 joined the Pixel 6's existing hotspot at approximately 16:13 UTC. The Pixel's cellular IPv6 upstream was verified, with its Wi-Fi disabled to prevent Wi-Fi sharing. iPhone 13's old Wi-Fi and new cellular-hotspot sandbox flows use the **exact same Apple destination IPv6 address**. Both use IPv6 over Wi-Fi/en0 and TCP 5223. The new sandbox connection negotiated 600 seconds plus 35 seconds grace. No app message or synthetic push was sent to reset its idle timer.

| Controlled observation (UTC) | Result |
|---|---|
| iPhone 13, original Wi-Fi, sandbox C414 / port 53971 | Request 15:52:53.431378; initial ACK 15:52:53.685903; `KeepAliveFailed` 16:03:28.431898, exactly 635.000520 seconds after request. |
| Same iPhone 13, same Apple IPv6 destination, cellular hotspot C417 / port 62029 | No APNs traffic for 601.286037 seconds; incoming heartbeat 16:23:11.158831; decoded `KeepAliveSucceeded` 16:23:11.166653. Same TCP connection remains open beyond its original failure deadline. |
| iPhone 11, original Wi-Fi, complete production flow / port 63585 | Negotiates 600+35 seconds; no flow packets after initial ACK 16:13:15.651733 until client closes at 16:23:50.590607. `KeepAliveFailed` at 16:23:50.583363. Reconnect works immediately. |
| iPhone 11, original Wi-Fi, complete sandbox flow / port 63586 | Initial ACK 16:15:32.063137; no subsequent flow packets before `KeepAliveFailed` 16:26:06.811791; replacement succeeds 16:26:09.817645. |

The exact endpoint match is grounded in historical flow C414's endpoint hash, the subsequent C415 / port 53974 mapping to a captured raw IPv6 destination, and the hotspot C417 destination. Port 53974 itself ended during the intentional network switch before its watchdog; **the preceding 53971 flow supplies the proven failure**, avoiding an assumption that the interrupted flow had failed.

On the successful cellular connection, the incoming heartbeat is an encrypted **26-byte TLS record**, decoded by APSD as command 13 / `APSProtocolKeepAliveResponse`, message length 4, success YES. The phone immediately acknowledges those 26 bytes. A byte-identical retransmission 218.561 ms later is also acknowledged, and renewed keepalive negotiation succeeds.

On the failing iPhone 11 production connection, complete-lifetime capture again finds a **26-byte unseen server sequence interval**: the server's FIN plus 24-byte close record starts at sequence 3427614868 while the phone still expects 3427614842. No intervening packet from that flow was captured before the phone initiated closure. Windows remain nonzero, including raw 2048 with scale 6. The successful control strongly corroborates the missing-heartbeat interpretation; capture limitations and an unseen teardown-time write prevent treating its encrypted contents as directly observed.

Both phones have contemporaneous screen-on/USB-awake evidence, including iPhone 13 during its earlier exact-endpoint original-Wi-Fi failure. iPhone 11's backlight assertion and nonzero brightness persist through the failed cycle; iPhone 13's backlight/user-active/USB assertions persist during the successful one. iPhone 11 remains on the original SSID throughout. The captures filter for APSD or TCP 5223 and do **not** supply exhaustive ICMPv6 neighbor-discovery evidence or a pcapd drop counter.

The full cellular capture stopped at 16:24:07 UTC; the iPhone 11 full-cycle capture stopped at 16:26:18 UTC. Historical archives were collected only after those captures stopped. iPhone 13 was verified back on the original Wi-Fi at 16:27:35 UTC. Its newly entered hotspot credential was retained: the offered Forget action would also remove that network from other devices through iCloud Keychain, so that confirmation was canceled. No existing saved Wi-Fi network was removed. Pixel 6 was restored and verified with hotspot off, mobile data off, and Wi-Fi connected to the original SSID; its hotspot configuration is unchanged. The automation session was deleted and all owned capture processes exited. [Restoration record](../../build/notification-deeper-20260907/restoration.json).

Evidence: [cellular control](../../build/notification-deeper-20260907/iphone13-cellular-control/findings.md), [matched historical endpoint proof](../../build/notification-deeper-20260907/os/iphone13-matched-endpoint-proof.json), [complete Wi-Fi flow captures](../../build/notification-deeper-20260907/live-full-cycle/packets.jsonl), [current production negotiation](../../build/notification-deeper-20260907/live-full-cycle/production-negotiation.log), [OS alternatives audit](../../build/notification-deeper-20260907/os/findings.md).

The normal router UI's loaded page readers expose no connection-state table, TCP idle timeout, IPv6 drop counters, or packet-capture export. Its session expired before further DOCSIS/LAN status inspection; no additional sign-in was requested for those nondiscriminating counters.

## Neighbor discovery and address-lifetime investigation

The subsequent capture retained all ICMPv6, including kernel-attributed frames, alongside APNs traffic. Six successful router solicitations and phone advertisements target the **exact privacy IPv6 address used by the stalled APNs sockets**, rather than merely the phone's separate DHCPv6 address.

The most discriminating exchange occurred at **16:47:27.472477 UTC**: the router sent a unicast neighbor solicitation to the correct phone MAC and IPv6 target; the phone emitted its solicited advertisement **88 microseconds later**. This was about **5.15 seconds before** the production connection's expected heartbeat. Nevertheless, APNs reported `KeepAliveFailed` at **16:48:07.632962**. The delayed closing server segment again begins **26 bytes beyond** the phone's expected sequence. The sandbox connection separately failed at 16:47:22.197107 after a successful exact-address neighbor exchange at 16:46:00.

A fresh development flow also received Apple data at the same source address/MAC at 16:47:25.219705, only **7.398 seconds before** the stalled production flow's expected heartbeat. Thus forwarded IPv6 data and correct unicast neighbor addressing both worked immediately before that older flow failed.

This materially weakens a simple missing neighbor mapping or nonresponsive phone explanation. It does not prove that the router received/accepted every advertisement, reveal its internal connection state, or distinguish forwarding/filtering upstream of the phone. **Loss of state or filtering specific to the idle TCP flow is a leading remaining hypothesis, not a directly observed firewall verdict.**

The new capture contains **152 distinct router advertisements**, all from one unchanged router configuration. Prefix preferred and valid lifetimes remain 86,400 seconds; router/default-route lifetimes remain 1,800 seconds. A separate historical OS audit found the same fields in 145 advertisements across earlier failure windows, with no address removal or route withdrawal. These are separate capture sets, not a combined count. The phone reuses the same source address successfully after reconnection.

The advertised 3,600,000 ms ReachableTime configures the receiving host's neighbor-reachability parameter; it does not expose the router's own cache timeout. Receiving router advertisements alone is not proof of bidirectional neighbor reachability. See [RFC 4861 section 6.3.4](https://www.rfc-editor.org/rfc/rfc4861#section-6.3.4) and [section 7.3.1](https://www.rfc-editor.org/rfc/rfc4861#section-7.3.1).

An external ICMPv6 probe used the USB-connected Pixel over verified LTE IPv6, with Wi-Fi and hotspot off. A public IPv6 echo control succeeded. Echo requests to the iPhone's exact APNs source received no replies and none appeared in its capture. This is **not APNs-loss localization**: unsolicited inbound echo may be filtered independently. The command combined `-c 3` with `-w 15`; its reply-count/deadline semantics resulted in 15 requests during 16:42:49.297–16:43:04.358 UTC, rather than the intended three. No retries occurred. The router neighbor exchange at 16:42:40 preceded this probe and is not attributed to it. All Pixel settings were restored and verified at 16:48:21 UTC.

The first expanded recorder stopped on a metadata enum-conversion error after preserving one raw packet. The resulting 16:34:27–16:36:49 gap, and a later 0.398-second hardening rollover, are recorded explicitly. The hardened recorder retains raw packets independently of metadata errors; its stable segment reported zero metadata failures. pcapd exposes no transport drop counter, so none is asserted. The decisive near-heartbeat neighbor exchange and both subsequent failures are inside the continuous stable segment. Capture stopped at 16:48:35 UTC, with all owned recorder processes exited.

The normal router admin session expired. A login was requested for a built-in router-origin ping, but the passive exact-address solicitations subsequently supplied the planned neighbor-resolution evidence. No further login is required merely to repeat that probe. The firewall remains enabled. The Mac's BPF capture and local OS log access were denied under current permissions; no privilege or configuration changes were made.

Evidence: [packet facts and capture gaps](../../build/notification-network-localization-20260907/iphone11/key-findings.json), [neighbor capture findings](../../build/notification-network-localization-20260907/iphone11/findings.md), [address-lifetime audit](../../build/notification-network-localization-20260907/os/ipv6-address-lifecycle-findings.md), [external probe and restoration](../../build/notification-network-localization-20260907/pixel-cellular-probe/findings.md).

## IPv4 control through the same router and ISP

The Pixel 6 then shared its existing Vodafone Wi-Fi uplink, with mobile data kept **off throughout**. Live Android state repeatedly verified the actual tethering upstream as `wlan0`; its hotspot supplied IPv4 and link-local IPv6 only. The phone and router were not moved to a different ISP. This first comparison deliberately changed the local access point, added Pixel NAT, and selected IPv4, so those variables must not be treated as isolated individually.

The iPhone 13 sandbox connection (local port 53096, TLS SNI `courier2.sandbox.push.apple.com`) negotiated **900 seconds plus 35 seconds grace**. After **901.921091 seconds with no TCP traffic**, a 26-byte server heartbeat arrived at **17:11:45.293349 UTC**. The phone acknowledged it and APSD recorded `KeepAliveSucceeded` at 17:11:45.300581. The same connection remained open beyond its original watchdog deadline. The independent production connection negotiated 1,800 seconds; its full cycle was outside this bounded leg and is not claimed as tested.

Hotspot sharing was disabled at 17:12:51.692954. Pixel baseline was verified at 17:13:23 with cellular data off, Wi-Fi connected to Vodafone, and hotspot off. iPhone 13 automatically rejoined Vodafone at 17:13:11.258244. Its replacement APNs connections selected **IPv4 directly through the original router**, providing an opportunity to remove the extra access-point/NAT confounds in a final passive cycle. Native IPv6 addresses were also present after restoration; IPv4 selection did not require disabling IPv6 on the phone or router. APSD received an IPv6 resolver result after establishing IPv4 and explicitly ignored that update because it was already connected. This explains retaining these IPv4 connections, without establishing a general IPv4 preference or why the IPv6 DNS result arrived later.

The first 20-minute recorder stopped at its hard limit, 17:15:05.947611. A separately bounded direct-Wi-Fi follow-up began at 17:15:13.448469. Its **7.500858-second early recording gap** is disclosed; the preceding phase preserves the new connections' SYNs and initial keepalive negotiations. No additional network changes occurred.

Both direct-original-Wi-Fi IPv4 connections passed:

| APNs environment | Connection | Negotiated interval | Incoming 26-byte heartbeat (UTC) | APSD result (UTC) |
|---|---|---|---|---|
| Production | Local 49509 → 17.57.146.24:5223 | 600 seconds + 35 grace | 17:23:16.367445 | `KeepAliveSucceeded` 17:23:16.371894 |
| Sandbox | Local 49508 → 17.188.170.199:5223 | 900 seconds + 35 grace | 17:28:15.999347 | `KeepAliveSucceeded` 17:28:16.004736 |

The phone acknowledged these heartbeats after 290 and 365 microseconds respectively, without reconnecting. Production's heartbeat arrived 600.569853 seconds after its initial packet acknowledgment. No timer reset was observed before either heartbeat. Unchanged TCP sequence positions corroborate no intervening application data; the early recorder gap still prevents asserting uninterrupted packet-level silence over each entire interval. The final continuous segment alone covers over eight minutes before production receipt and over thirteen minutes before sandbox receipt.

This direct comparison removes the additional Pixel access point and NAT from the passing path. The same phone, original Wi-Fi, router, and ISP now carry working idle IPv4 APNs sessions; original-network idle IPv6 failures and the same-destination cellular IPv6 pass remain independently recorded above. Address family and Apple destination differ between IPv4 and IPv6, so this does not uniquely identify the router or isolate its firewall.

The final recorder stopped at 17:28:51.158167 UTC, after both original watchdog deadlines, with ten APNs packets and zero metadata errors. Its recorder and syslog processes exited. Settings was backgrounded and the Appium session deleted after collection; Mknoon was not activated. Network settings were already restored before this direct comparison. See the [final cleanup record](../../build/notification-same-isp-20260907/final-cleanup.json).

Evidence: [same-ISP setup and restoration](../../build/notification-network-localization-20260907/pixel-wifi-upstream-feasibility/findings.md), [IPv4 idle-cycle facts](../../build/notification-same-isp-20260907/iphone13/key-findings.json), [Apple environment from TLS SNI](../../build/notification-same-isp-20260907/iphone13/tls-sni-environment-proof.json), [direct Wi-Fi control](../../build/notification-same-isp-20260907/iphone13-direct-ipv4/findings.md), [native IPv6 restoration and IPv4 selection](../../build/notification-same-isp-20260907/ipv6-restoration-proof/findings.md).

## ECN comparison

Incoming Apple packets in the failing iPhone 11 IPv6 capture are Not-ECT, while successful cellular IPv6 and same-ISP IPv4 captures include ECT(0), including their heartbeats. All examined new handshakes negotiate ECN. This is a correlation, not evidence that ECN caused the loss: initial Not-ECT IPv6 data arrives within approximately one measured round trip, and duplicate observations only microseconds apart are capture duplication rather than demonstrated TCP retransmission recovery. No retained incoming original-Wi-Fi capture supplies exact destination parity with the successful iPhone 13 cellular flow. Same-ISP IPv4 preserves ECT(0), so blanket ECN stripping across that WAN is not established. See the [bounded retransmission audit](../../build/notification-network-localization-20260907/ecn-retransmission-audit/findings.md).

## Continued check and narrower diagnostic candidate

Read-only historical collections at approximately 17:54–17:55 UTC found **five more IPv6 APNs keepalive failures on iPhone 11** after 17:29, latest production failure at 17:51:49.253. Reconnection and initial acknowledgments followed. During the same period, iPhone 13 recorded four further IPv4 keepalive successes, no failures, and remained on the original Vodafone Wi-Fi; latest success was 17:53:21.448. These collections took 16–17 seconds each and made no app or network changes. [Updated device evidence](../../build/notification-next-discriminator-20260907/device-status-1754/findings.md).

A further source/platform review confirmed the NSE's mailbox recovery begins after iOS invokes `didReceive`. Independently scheduled background work could retrieve messages before a particular delayed push, but iOS does not promise its timing and the examined APIs expose no APSD socket-reset or watchdog control. This preserves the distinction between opportunistic message recovery and a guaranteed repair of the stalled push connection. [App recovery boundary and Apple references](../../build/notification-next-discriminator-20260907/app-recovery/boundary-note.md).

After renewed normal admin login, the router's **IPv6 Host Exposure** page exposed a narrower candidate than the global firewall switch: MAC address, TCP/UDP protocol, and a single port or port range. There were no existing exposure rules. The page has no remote-address or remote-source-port restriction. Its rule data contains `ServiceName`, `MAC`, `Protocol`, `StartPort`, `EndPort`, `Status`, and `Index`; creation/removal is staged before the separate Apply action.

A diagnostic could therefore target only iPhone 11's current APNs **local ephemeral TCP port**, leaving the global firewall enabled. Destination port 5223 on the phone would be incorrect: Apple uses source port 5223 and the phone uses an ephemeral destination port. Because the rule is MAC-based, an unsuccessful test would also need to account for whether the firmware applies the exception to the exact APNs privacy IPv6 address. The user subsequently approved this single-port test; its execution and restoration are recorded below.

## Authorized single-port IPv6 experiment

The user explicitly approved the prepared rule. A fresh packet capture identified production APNs socket **63626** on iPhone 11, with TLS SNI `courier2.push.apple.com`, source IPv6 `2a02:8070:8880:7480:7d61:770c:7321:2f4c`, and MAC `2e:7a:a2:9c:95:10`. Its previous production flow had failed at 18:08:44.562324; the new flow negotiated 600 seconds at 18:08:49.255646 and acknowledged successfully at 18:08:49.342794. The unexposed sandbox flow 63629 separately started after a failure at 18:12:22.243116.

A DVT network-monitor snapshot initially suggested port 63625, but exposed no TCP-state field and PID -2. It was treated as provisional and superseded by direct packet/OS evidence. The applied rule used **63626**, never that provisional port.

The only added rule was `codex-apns-63626-8a9d`: the iPhone 11 MAC, TCP, and destination port 63626. The global firewall stayed enabled. An independent cleanup watchdog was armed before creation, with an absolute deadline of 18:28:24.775992 UTC. The rule's Apply request ran **18:17:06.743–18:17:07.394**, followed by a persisted-rule reload at **18:17:12.474–18:17:13.996**. The persisted row had exactly the approved fields and backend Index 1. Thus the recorded rule application precedes the observed heartbeat; this is not an inference from a later screenshot alone.

The **same production IPv6 connection** received a 26-byte server heartbeat at **18:18:50.295611**, acknowledged it at 18:18:50.296207, and recorded `KeepAliveSucceeded` at 18:18:50.302548. No reconnect was required. The packet was Not-ECT, so a visible ECT(0) marking was not necessary for this successful IPv6 heartbeat.

The **unexposed sandbox connection also received its 26-byte heartbeat at 18:22:26.565917**, acknowledged it at 18:22:26.566501, and recorded `KeepAliveSucceeded` at 18:22:26.580792. Consequently, this experiment does not isolate a correctly port-scoped firewall bypass: applying a rule may affect broader host/filter state. The subsequent reversal strengthens the router-state interpretation while preserving that distinction.

The cleanup process clicked removal Apply at **18:23:15.214160**, verified an empty persisted rule table after reload at **18:23:23.345570**, and exited successfully. The rule was removed after approximately six minutes, within the 12-minute bound. Root independently rechecked the empty rule table and confirmed the global firewall **On at 18:25:11.040**. No other rules or network settings were changed. [Application timing and persisted rule](../../build/notification-next-discriminator-20260907/router/applied-rule-evidence.json), [cleanup audit](../../build/notification-next-discriminator-20260907/router/approved-exposure.cleanup-audit.jsonl), [restoration verification](../../build/notification-next-discriminator-20260907/router/final-restoration.json).

Following its successful heartbeat, production socket **63626** negotiated another 600-second interval at 18:18:50.315893. The rule was subsequently removed while the same socket and IPv6 endpoints remained in use. Its next server heartbeat did not arrive. iOS recorded **`KeepAliveFailed` at 18:29:25.318541**, then the phone initiated closure at 18:29:25.324885. The server's closing segment at 18:29:25.352075 begins at sequence **3918473503** while the phone still expects **3918473477**: the same **26-byte gap** seen in the untreated failures. No reconnection separates this flow's successful heartbeat under the rule from its failed heartbeat after removal.

| Router configuration | Production IPv6 result |
|---|---|
| Original configuration, before intervention | Repeated failures, including the preceding production flow at 18:08:44.562324 |
| Temporary rule present, global firewall On | Existing port 63626 receives heartbeat at 18:18:50.295611 without reconnecting |
| Rule removed, global firewall On | Same port 63626 misses next heartbeat and fails at 18:29:25.318541 |

This change-and-reversal result is stronger than a network correlation alone. It strongly implicates the router's IPv6 filtering/state path, but the simultaneous improvement of the unexposed connection leaves the exact scope of the rule's side effects unresolved. The experiment does not prove an exact 300-second idle timeout or establish that a permanent exposure rule is an appropriate product fix.

The preflight capture preserved the initial handshakes. Its bounded rollover left an explicitly recorded **8.290847-second capture gap**, 18:12:39.756407–18:12:48.047254, before rule application. The successful heartbeat observations are in the continuous second segment. No app message, app activation, or phone network toggle was used to reset either timer.

The final capture stopped at **18:30:26.557778 UTC**, retaining 379 packets. Both recorder and syslog processes exited, as did the cleanup watchdog. Reconnection after the reversed failure began on new production port 63637 at 18:29:25.535907. No further network intervention was performed.

Evidence: [independent causal audit](../../build/notification-next-discriminator-20260907/causal-audit/findings.md), [verified packet arithmetic](../../build/notification-next-discriminator-20260907/causal-audit/verified-evidence.json), [test context](../../build/notification-exposure-test-20260907/iphone11/test-context.json), [native packet capture](../../build/notification-exposure-test-20260907/iphone11/iphone11-apns-ndp-device-time.pcap), [OS reversal excerpt](../../build/notification-exposure-test-20260907/iphone11/reversal-os-evidence.log), [capture termination](../../build/notification-exposure-test-20260907/iphone11/capture-process.json).

## Remaining discriminator

A simultaneous router LAN/WAN capture or exact firewall state/drop evidence would locate whether the same missing sequence range reaches the router and its LAN. The available router UI does not expose those records.

A **global firewall-off comparison** was not authorized or run. The separately authorized single-port experiment above supplied stronger causal evidence while keeping the global firewall enabled. Its cleanup guard ran successfully and the original empty exposure-rule table was restored.

The delay mechanism is established, and the intervention strongly implicates the router's IPv6 filtering/state handling. Its exact internal packet-drop mechanism has not been identified, and no production fix is claimed. The requirement to work across networks remains unchanged; temporary hotspot use was a diagnostic control, not a product workaround or acceptance criterion.

## Evidence

- [OS radio, power, and heartbeat evidence](../../build/notification-stall-rootcause-20260907/os/rootcause-key-evidence.log)
- [Recurring iPhone 11 failures](../../build/notification-stall-rootcause-20260907/os/apsd-hour-pattern.log)
- [iPhone 13 comparison](../../build/notification-stall-rootcause-20260907/iphone13/findings.md)
- [Independent 26-byte gap audit](../../build/notification-stall-rootcause-20260907/packet/live-26byte-gap-audit.md)
- [Timestamp-correct packet capture](../../build/notification-stall-rootcause-20260907/live/iphone11-apsd-device-time.pcap)
- [Live capture summary](../../build/notification-stall-rootcause-20260907/live/capture-summary.json)
- [Hotspot parity audit](../../build/notification-stall-rootcause-20260907/packet/hotspot-parity-audit.md)
- [Router inspection summary](../../build/notification-stall-rootcause-20260907/router/inspection-summary.json)
- [Focused host test output](../../build/notification-stall-rootcause-20260907/os/focused-recovery-tests.log)
- [Proposed diagnostic and restoration steps](../../build/notification-stall-rootcause-20260907/router/controlled-firewall-diagnostic.md)

Full raw archives remain under `/tmp/notification-stall-rootcause-20260907/`, `/tmp/notification-deeper-20260907/`, `/tmp/notification-network-localization-20260907/`, and `/tmp/notification-same-isp-20260907/`. Selected evidence is retained under the corresponding ignored `build/` directories. All owned device capture processes have stopped.
