**Yes—IPv6-related problems can affect both text messaging and audio calls in libp2p.** The strongest evidence concerns **failed connections, slow fallback, incorrect address handling, and incomplete IPv6 support across the whole connection path**—not IPv6 inherently producing worse audio.

For Mknoon, my recommendation is **keep IPv4 and IPv6 enabled, prefer a working direct connection, and maintain reliable relay fallback**. Do not force IPv6 everywhere, but do not disable it globally either. Go-libp2p already includes mechanisms for handling mixed IPv4/IPv6 connectivity. ([Go Packages][1])

I checked public project documentation and issue trackers on **13 September 2026**. This is upstream research, not confirmation that these problems exist in your current Mknoon build. Several reports are historical; an issue remaining open does not prove that every current version reproduces it.

## 1. What other projects have actually encountered

The effects on Mknoon below are my assessment of the reported failure mechanism, not results from testing your app.

| Project and report                            | What was reported and its status                                                                                                                                                                                                                                                                             | Relevance to text messaging and audio                                                                                                                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Go-libp2p / IPFS Kubo — issue #2466**       | A node could be considered publicly reachable because IPv4 worked, even though IPv6 was not reachable. Opened August 2023; still marked open. ([GitHub][2])                                                                                                                                                  | **Both:** the app could select an unusable direct address or make the wrong decision about needing a relay.                                                                                                   |
| **Go-libp2p — issue #2068**                   | A hole-punching measurement campaign raised concerns about IPv6 success rates. The authors explicitly left the cause unresolved: measurement problems, network behavior, or a libp2p issue. Opened February 2023; still open. ([GitHub][3])                                                                  | **Both:** direct connection establishment needs testing. This is **not** sufficient evidence to claim that IPv6 is generally less reliable or to quote a universal failure rate.                              |
| **Libp2p Universal Connectivity — issue #64** | Two browser peers could each connect to the relay using IPv6, but could not establish the relayed connection or subsequent WebRTC connection to each other. IPv4 worked without other changes. Opened May 2023; still open. ([GitHub][4])                                                                    | **Both:** “connected to the relay” does not necessarily mean “able to exchange messages or establish a call with another user.”                                                                               |
| **Go-libp2p / IPFS — issues #356 and #2659**  | Reports cover advertising deprecated temporary IPv6 addresses and incorrect handling of link-local addresses and interface zones. Both remain open. ([GitHub][5])                                                                                                                                            | **Both:** peers may try unsuitable addresses. Particularly relevant to your local Wi-Fi feature and address refresh behavior.                                                                                 |
| **Pion ICE — issue #742**                     | IPv6 link-local candidate gathering omitted the interface zone when binding sockets. This caused repeated failed binds and high CPU usage during connection initiation. **Fixed by PR #744, merged 26 November 2024.** ([GitHub][6])                                                                         | **Call setup:** a concrete example of an IPv6 implementation bug causing expensive connection attempts. Relevant only where the affected Pion stack is actually used; not automatically a Flutter WebRTC bug. |
| **Jitsi Meet — issue #8943**                  | On a native IPv6-only network without NAT64, users could join a meeting but received no audio or video. The report identified supporting endpoints without IPv6 addresses. Opened April 2021; closed with a `wontfix` label. This is historical, not a claim about today’s hosted service. ([github.com][7]) | **Audio specifically:** successful call signaling can coexist with a completely broken media path.                                                                                                            |
| **RustDesk Server — issue #544**              | After IPv4 and IPv6 were both added to DNS, the reported setup used IPv6 but failed to establish direct peer-to-peer connections; sessions used the relay instead. Opened April 2025; still open. RustDesk is a comparable P2P project, not evidence of a libp2p defect. ([GitHub][8])                       | **Fallback and cost:** a functioning relay can preserve service even when the preferred direct path fails.                                                                                                    |

**The recurring lesson is that IPv6 support must work end to end—not merely on the client’s interface or the relay’s listening socket.**

## 2. The main drawbacks—and how they affect Mknoon

### A. Having an IPv6 address does not mean another peer can reach it

A device can have a globally routable IPv6 address while its router or firewall still blocks unsolicited incoming traffic. IPv6 does not remove the need to handle firewall restrictions. The go-libp2p/Kubo reachability report shows why a single “this peer is public” flag can be misleading across address families. ([RFC Editor][9])

**For text:** the first message may remain pending while the app tries an unreachable direct address.

**For calls:** the invitation or connection setup may stall, or the app may unnecessarily fail instead of taking the relay path.

Those are application-level consequences of selecting a path that cannot connect. My recommendation is to judge reachability by the relevant address and transport, rather than assuming that success over IPv4 proves IPv6 works.

There is an important improvement here: **AutoNAT v2 supports testing individual addresses**, and go-libp2p has an implementation. Therefore, the older report should not be interpreted as “libp2p has no solution.” Check which version and behavior your app actually uses before adding anything new. ([GitHub][10])

### B. Broken IPv6 can delay a perfectly usable IPv4 connection

A network can advertise IPv6 availability while traffic over that path fails. An application that tries IPv6 and waits for a long timeout before trying IPv4 makes the whole service appear unreliable. This is the problem that *Happy Eyeballs*—staggered connection attempts across address families—is designed to reduce. ([RFC Editor][11])

Go-libp2p’s documented default dialer already uses Happy Eyeballs-style ranking for TCP and QUIC. For public addresses, its documented IPv6-to-IPv4 staggering includes a **250-millisecond delay**, rather than waiting for a complete IPv6 timeout. It also has IPv6 and UDP black-hole detection, which can suppress repeatedly unsuccessful paths while periodically probing again. These are connection-attempt mechanisms, not guarantees about total call setup time. ([Go Packages][1])

**For text:** poor fallback becomes a delayed first message or reconnect.

**For calls:** the same delay is more visible because someone is waiting for the other phone to ring or for audio to start.

**What I would check in Mknoon:** whether custom address filtering, reconnect logic, or sequential dialing prevents the existing libp2p mechanisms from doing their job. I would not start by writing another connection-selection system.

### C. IPv4-only and IPv6-only peers may not share a direct path

Two users can both have internet access but lack a compatible direct connection to each other. A relay reachable by both sides can provide the application-level connection; for WebRTC, the standards explicitly address mixed IPv4/IPv6 situations through TURN support. ([libp2p][12])

**For text:** a reachable libp2p circuit relay can keep messaging working even when direct connectivity is unavailable.

**For audio:** the correct fallback depends on how the actual voice traffic is transported. This is where it is important not to treat all things called “relay” as interchangeable.

#### A libp2p relay is not automatically a WebRTC media relay

When voice uses a separate WebRTC connection, libp2p may successfully carry the invitation and answer while WebRTC’s own connection checks fail. A libp2p circuit relay and a TURN server are different protocols; operating the former does not automatically provide the latter’s media-relaying capability. ([libp2p][12])

For Mknoon, there are two cases to distinguish:

| Actual audio implementation                                              | What IPv6 problems can affect                                                                                                                  |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Voice traffic travels through libp2p itself**                          | Connection establishment and the ongoing path carrying audio, including any circuit-relay fallback.                                            |
| **Libp2p carries signaling; a separate WebRTC connection carries voice** | Libp2p problems can prevent invitation/answer delivery, while separate IPv6/ICE/TURN problems can prevent audio even after signaling succeeds. |

This distinction explains why **a successful text-message test is not enough to validate calls**. Jitsi’s historical report is a concrete example of a successful “join” experience without working media. ([github.com][7])

### D. Temporary addresses and local-only addresses require careful handling

IPv6 devices may have several addresses, including temporary addresses and link-local addresses. A link-local address also depends on the local network interface; it is not a general internet address. The libp2p reports document problems with both deprecated-address advertisement and interface-zone handling. ([GitHub][5])

For your local Wi-Fi feature, I would keep **LAN discovery addresses separate from internet-advertised addresses**, and refresh usable addresses when the device changes networks.

For calls, address refresh must also avoid unnecessarily tearing down a functioning session. WebRTC’s transport specification specifically distinguishes deprecated addresses used for new connections from addresses already used by an ongoing connection. **Temporary IPv6 addresses are not themselves a bug, and their becoming deprecated does not automatically mean an active call must end.** ([RFC Editor][13])

### E. Packet-size problems can produce “connected, but data stalls”

A secondary IPv6 failure mode involves path MTU discovery—the process of learning how large packets can be along a route. Blocking the necessary ICMPv6 “Packet Too Big” messages can create connections that complete their initial handshake but stall when transferring data. ([RFC Editor][14])

This is worth considering when small exchanges work but larger transfers or particular transports fail. **I would investigate fallback, reachability, and media-path selection first**, rather than assuming MTU is the cause of ordinary call problems.

## 3. A particularly important indirect risk: relay limits

An IPv6 direct-connection failure may push more sessions onto your relay. That can expose a relay configuration problem that looks like an IPv6 problem.

The go-libp2p circuit-relay implementation’s default limits are **two minutes and 128 KiB of relayed data per direction, per relayed connection**. Deployments can override them, so these are not necessarily your settings. ([GitHub][15])

**My assessment:** when actual audio is carried through a circuit subject to these defaults, continuous voice traffic can hit a limit that a short text exchange never reaches. That could produce the misleading symptom:

> “Messages work, and the call starts, but the call later cuts off.”

This is **not an inherent IPv6 limitation**. It is a fallback-path issue that becomes visible when direct connectivity fails. Checking your existing relay configuration is more useful than blaming the IP version.

## 4. Should you disable IPv6?

**No—not as a general fix.**

For your iOS app, Apple requires compatibility with IPv6-only networks and explicitly warns about IPv4-specific APIs and hardcoded IP addresses. That requirement does not mean every server must be native IPv6-only; DNS64/NAT64 can provide access to IPv4 services. But low-level networking and IP literals require deliberate testing. ([Apple Developer][16])

I would use this policy for Mknoon:

**Support both families.** Keep IPv4 and IPv6 paths available where the device and network support them. Do not publish an IPv6 DNS record for infrastructure that does not actually serve the required traffic over IPv6. Apple specifically documents how a misleading IPv6 deployment can pass a translated local test yet fail on a native IPv6 network. ([Apple Developer][17])

**Preserve fast fallback.** Use the existing libp2p dialing mechanisms, with a usable relay route. Treat a network-specific IPv6 failure as a path failure—not a reason to disable IPv6 for every user. ([Go Packages][1])

**Validate messaging and audio independently.** For messaging, I would require recipient acknowledgments, safe retries, and no duplicate delivery during reconnection. For calls, I would require actual bidirectional media flow before treating the session as fully established. These are proposed application acceptance criteria, not claims about what your current implementation lacks.

**Keep diagnostics specific.** Record the selected address family, transport, direct-versus-relay route, and failure stage. For calls, separately record signaling success, media-path establishment, and ongoing media health. That gives you evidence for distinguishing “IPv6 dial failed” from “call answered, but audio transport failed.”

## 5. The targeted tests I would prioritize

These are proposed tests for Mknoon—not claims that any particular scenario currently fails.

| Test scenario                                       | Text-message acceptance check                                                 | Audio-call acceptance check                                                           |
| --------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **Healthy IPv4 and IPv6**                           | Delivery and acknowledgment work over either selected family.                 | Bidirectional audio works; record the selected path.                                  |
| **IPv6 advertised but silently broken; IPv4 works** | Delivery falls back without waiting for a long failed attempt.                | Calling does not remain stuck on IPv6.                                                |
| **Native IPv6-only network**                        | Discovery, relay access, and messaging work without hidden IPv4 dependencies. | Actual audio works, not merely invitation and answer.                                 |
| **IPv6-only with DNS64/NAT64**                      | Server names and the app’s low-level dialing paths work correctly.            | Media connectivity is tested separately from signaling.                               |
| **One peer IPv4-only, the other IPv6-only**         | A compatible relay path delivers messages.                                    | The appropriate media fallback carries audio both ways.                               |
| **Wi-Fi → mobile data during use**                  | Pending messages recover without duplication.                                 | The call recovers, or reports loss clearly rather than remaining falsely “connected.” |
| **Direct traffic blocked; relay required**          | Messaging remains reliable through the relay.                                 | A sustained call survives the configured duration and data limits.                    |
| **Same Wi-Fi with IPv6 link-local discovery**       | Local addresses are interpreted on the correct interface.                     | Local calling works without assuming those addresses are internet-reachable.          |

For comparison, I would measure **message acknowledgment time, call setup time, time to first received audio, call drops, and relay usage**, split by IPv4/IPv6 and direct/relayed paths. Those measurements would establish whether IPv6 actually hurts your users rather than relying on upstream anecdotes.

### Bottom line

**The most credible IPv6 risks for Mknoon are delayed or failed connection setup, unsuitable advertised addresses, and fallback paths that have not been tested as thoroughly as the direct path. Calls need extra scrutiny because successful signaling does not prove successful audio.**

I would keep IPv6, retain IPv4 and relay fallback, and prioritize **broken-IPv6 fallback, mixed-family peers, and sustained relay-only calls** in your tests. The evidence supports hardening those paths—not removing IPv6 or changing your architecture.

[1]: https://pkg.go.dev/github.com/libp2p/go-libp2p/p2p/net/swarm "swarm package - github.com/libp2p/go-libp2p/p2p/net/swarm - Go Packages"
[2]: https://github.com/libp2p/go-libp2p/issues/2466 "autonat: provide different reachability states and callbacks for IPv6 and IPv4 · Issue #2466 · libp2p/go-libp2p · GitHub"
[3]: https://github.com/libp2p/go-libp2p/issues/2068 "holepunch: low IPv6 success rate · Issue #2068 · libp2p/go-libp2p · GitHub"
[4]: https://github.com/libp2p/universal-connectivity/issues/64 "Browser to browser connectivity not established with IPv6 · Issue #64 · libp2p/universal-connectivity · GitHub"
[5]: https://github.com/libp2p/go-libp2p/issues/356 "Don't accounce deprecated addresses to the network · Issue #356 · libp2p/go-libp2p · GitHub"
[6]: https://github.com/pion/ice/issues/742 "ipv6: trying to listen on link-local addresses without interface · Issue #742 · pion/ice · GitHub"
[7]: https://github.com/jitsi/jitsi-meet/issues/8943 "meet.jit.si: On an IPv6-only network, without any IPv4 connectivity or NAT64, no calls can be performed · Issue #8943 · jitsi/jitsi-meet · GitHub"
[8]: https://github.com/rustdesk/rustdesk-server/issues/544 "Peer 2 Peer not working if IPv6 is used · Issue #544 · rustdesk/rustdesk-server · GitHub"
[9]: https://www.rfc-editor.org/rfc/rfc6092.html "www.rfc-editor.org"
[10]: https://github.com/libp2p/specs/blob/master/autonat/autonat-v2.md "specs/autonat/autonat-v2.md at master · libp2p/specs · GitHub"
[11]: https://www.rfc-editor.org/rfc/rfc8305.html "www.rfc-editor.org"
[12]: https://libp2p.io/docs/circuit-relay/ "Circuit Relay | libp2p"
[13]: https://www.rfc-editor.org/rfc/rfc8835.html "RFC 8835: Transports for WebRTC"
[14]: https://www.rfc-editor.org/rfc/rfc8201.html "www.rfc-editor.org"
[15]: https://github.com/libp2p/go-libp2p/blob/master/p2p/protocol/circuitv2/relay/resources.go "go-libp2p/p2p/protocol/circuitv2/relay/resources.go at master · libp2p/go-libp2p · GitHub"
[16]: https://developer.apple.com/support/ipv6/ "Supporting IPv6-only Networks - Support - Apple Developer"
[17]: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/NetworkingOverview/UnderstandingandPreparingfortheIPv6Transition/UnderstandingandPreparingfortheIPv6Transition.html?from=20423&from_column=20423&utm_source=chatgpt.com "Supporting IPv6 DNS64/NAT64 Networks"
