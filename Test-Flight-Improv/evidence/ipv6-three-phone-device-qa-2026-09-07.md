# IPv6 / Happy Eyeballs three-phone device QA — 2026-09-07

## Installed build and scope

Installed `feat/ipv6-happy-eyeballs` commit `d8b919c5b34575d570a78eb5fbbc4203f56f875b` using the production `lib/main.dart` entry point. These were in-place installations; no Mknoon uninstall or account/data reset occurred. Existing user edits to `pubspec.yaml` and `docker-ws/build_store_release_result.txt` were preserved. The paired but non-USB iPhone 17 was excluded.

| Physical USB phone | Explicit target ID | Verified installed version |
| --- | --- | --- |
| iPhone 11, iOS 26.5 | `00008030-001A6D2801BB802E` | `1.0.1`, build `260907203036` |
| iPhone 13, iOS 26.5 | `00008110-00184D622289801E` | `1.0.1`, build `260907203036` |
| Pixel 6, Android 16/API 36 | `21071FDF600CSC` | `1.0.1-d8b919c5b.d2.t260907203036`, versionCode `111` |

All three installations were launched and their installed versions verified. Artifact hashes, signing details, command results and install times are in the ignored `build/ipv6-device-qa-20260907/deploy/` directory, especially `deployment-result.json` and `build-identity.json`.

## Baseline IPv6 proof

Both iPhones used fresh-process IPv6 QUIC connections to `mknoun.xyz`, relay IPv6 `2a05:d016:c4d:7100:ec85:94ed:b90d:e20`, UDP 4002. Phone RVI packet metadata recorded the first server responses 43.682 ms after the iPhone 11 Initial and 40.493 ms after the iPhone 13 Initial. Sustained bidirectional traffic and same-peer relay registrations followed.

Pixel native logs recorded successful relay warmup in 111 ms. Relay NIC metadata independently confirmed bidirectional IPv6 QUIC traffic for its exact observed source address and port at 20:46:37 UTC. The peer association uses the known preserved device identity plus its relay registration; encrypted QUIC packet metadata does not expose peer IDs.

## Media and text UI checks

The preserved Pixel and iPhone 11 accounts were already connected. The iPhone 13 had an empty circle on launch, so its completed checks cover launch, online state and transport connectivity. Its release scanner requires a physical camera scan; no contact records or identities were injected to manufacture an iPhone-to-iPhone media result.

- Pixel → iPhone 11 `TEXT-1`: received with the exact unique text, via inbox. Sender recorded final success in 1,616 ms. The receiver UI and screenshot confirmed receipt.
- Pixel → iPhone 11 `IMAGE-1`: the synthetic blue/white checkerboard image and exact caption rendered correctly. Blob `5adaf3c7-b652-48ef-9f78-09bd54a48212`; sender uploaded media in 289 ms, then recorded message delivery in 664 ms, including a 117 ms ACK wait. The picker converted the 710-byte PNG fixture into a 1,141-byte JPEG. Read-only copies of the sender's saved JPEG and receiver's JPEG were byte-for-byte identical, SHA-256 `f2f7e830b134413263631c88601dec2cd58e9277e463c167e5f9de9374f9f8d1`.
- Pixel → iPhone 11 `IMAGE-FALLBACK`: image and exact caption rendered while the receiver's IPv6 relay traffic was blocked. Relay logs show blob `c9581538-7019-43a4-87d2-df8e5a016f6c` uploaded at 20:49:42.895844 UTC and downloaded by the iPhone 11 at 20:49:43.528806 UTC. The chat message UI reports direct delivery; this is distinct from the media blob's relay retrieval.
- iPhone 11 → Pixel `REPLY-1`: exact reverse text received and screenshot verified, via direct connection.

The UI's “cellular relay” label is not evidence of a mobile-carrier or IP address family. Address-family conclusions above come from packet capture and scoped failure evidence.

## Scoped IPv6 failure and recovery

Each fault uses an isolated relay nftables table, exact test-phone source `/128`, exact relay IPv6 destination, and only TCP 4001/4005 and UDP 4002. An independent relay-local cleanup timer is armed before rule creation, with a 120-second bound. APNs, router settings, other source addresses and other ports are outside the rule scope. Apps are terminated and freshly launched so the result tests new connection establishment.

| Phone | First IPv6 Initial, UTC | First IPv4 Initial, UTC | IPv4 launch after IPv6 | First IPv4 response after IPv6 |
| --- | --- | --- | --- | --- |
| iPhone 11 | 20:49:08.161712 | 20:49:08.357564 | 195.852 ms | 240.435 ms |
| iPhone 13 | 20:52:09.676138 | 20:52:09.894797 | 218.659 ms | 265.079 ms |

For both iPhones the new IPv6 flow received no responses during the fault, the scoped drop counter recorded four UDP packets / 5,312 bytes, and the IPv4 flow was sustained and bidirectional. Both displayed online and registered the same preserved peer identity on the relay.

The iPhone 11 fault table was independently verified absent at 20:50:48.909236 UTC. After a fresh recovery launch, its IPv6 Initial at 20:51:26.342726 received a server response at 20:51:26.388356 (45.630 ms), followed by sustained IPv6 traffic.

## Evidence and limits

Detailed local artifacts live under ignored `build/ipv6-device-qa-20260907/`: `deploy/`, `devices/`, `relay/`, and `ui/`. Receiver screenshots are `ui/iphone11/image-1-received.png` and `image-fallback-received.png`; Pixel action times, sources and screenshots are under `ui/pixel/`. Raw RVI/syslog captures are under `/tmp/ipv6-device-qa-20260907/`.

These tests exercise the three currently connected phones on their current network and a controlled IPv6 black hole. They do not prove every Wi-Fi/carrier environment, long-idle notification latency, all three transports individually on each phone, or an APNs connectivity fix. iOS builds retain development APNs signing; a short background observation cannot substitute for a long-idle APNs test.

## Pixel fallback and final recovery

Pixel's IPv6-only fault was active from 20:54:46.232744 until independently verified removal at 20:56:46.499401 UTC. It was force-stopped and freshly started at 20:55:19 UTC. Relay NIC metadata observed its new IPv6 Initial-sized datagram at 20:55:25.766366 and the new IPv4 flow at 20:55:25.951003: **184.637 ms between server arrivals**. The relay replied over IPv4 at 20:55:25.951533 and logged the preserved Pixel peer connected at 20:55:26.006015. Its new IPv6 flow received no replies. Pixel native logs recorded successful relay warmup in **362 ms**, queue wait zero. The final fault counter included older-flow traffic and is not a count of just the new dial's packets.

These Pixel figures are server arrival times, unlike the iPhone RVI observation times in the table. They demonstrate the fallback sequence but are not identical measurement boundaries. Pixel's device clock was approximately 1.229 seconds ahead of the Mac midpoint in a 74.887 ms RTT measurement; durations within one clock are preferred over subtracting device and relay timestamps.

After removal, Pixel was freshly restarted at 20:58:11 UTC. The relay observed its fresh IPv6 flow at 20:58:17.057815, replied at 20:58:17.058230, and recorded sustained IPv6 traffic. Native warmup returned to 111 ms; the final UI was online.

The iPhone 13 fault table was independently verified absent at 20:53:29.910568 UTC. Its recovery process sent a fresh IPv6 Initial at 20:55:13.460118 and received a response at 20:55:13.503794 (43.676 ms), followed by sustained bidirectional IPv6 traffic.

## Background notification observation

The iPhone 11 was backgrounded at 20:52:25 UTC. Appium reported it suspended at 20:55:40 and again at 20:59:16. Pixel sent the final image at 20:56:52.266857 UTC, after the Pixel fault was already removed. The keyboard changed the exact caption to `IPv6 QA Pixel to iphone-11 Image-Pixel-Fallback d8b919c5b`. Blob `d27e130c-a037-45a6-9fd2-a78b0e74214b`, message prefix `dc04469c`.

The relay logged media upload at 20:56:52.941137, inbox storage at 20:56:53.504191 and push provider success on attempt one at 20:56:53.866376. The push journal omits an event ID, so that association is the isolated send sequence rather than an explicit message-ID join. Server packets associate this upload with Pixel's still-established IPv4 flow; it was **not** an upload during an active fault.

The first Notification Centre screenshot at **20:58:34.160** already contains the exact notification. A second screenshot at 20:59:16 also contains it while the app remains suspended. Mknoon was first reopened at 20:59:27; the image and caption were then verified rendered in the chat at 21:00:33, with “Received via inbox.” Thus **notification receipt before app open passed**. The background interval before sending was about 4 minutes 27 seconds, not a long-idle soak.

Exact arrival latency was not measured. A home-screen screenshot at 20:57:15 had no visible banner, but that does not prove absence from Notification Centre. The accessibility XML omitted the new notification card even though the screenshots show it. An intermediate assistant status interpreted those omissions too strongly; visual review corrected that interpretation. Neither a 102-second delay nor a prompt-delivery claim is justified by these snapshots.

Screenshots: `ui/iphone11/background-notification-first-centre-check.png`, `background-notification-before-open.png`, and `background-image-received.png`.

## Completion and cleanup

All three phones passed installed-version verification, launch/online checks, real IPv6 relay traffic, fresh IPv4 fallback under a scoped IPv6 black hole, and fresh IPv6 recovery. Pixel/iPhone 11 text and media checks passed, including exact JPEG integrity and a background notification before foregrounding. No iPhone 13 media exchange or long-idle notification-latency result is claimed.

All three fault tables were removed by their independent timers. At 20:59:06 UTC the relay nft ruleset contained no tables; cleanup services/timers were inactive with success/status zero. Bounded packet captures stopped cleanly, and both owned Appium sessions were deleted. Only generated test fixture source files were removed; test chat messages and existing user data were retained. No production source changes were made during deployment/testing. The Xcode workspace access-time-only `info.plist` change was restored; the user's original two dirty files remain preserved.

The repository's diagnostic workflow benchmark reported 3/6 historical session navigation gates passing (plan-to-code, broad refinement and branch-first counters failed); no post-edit impact debt exists because this task made no production edits. Those navigation metrics are separate from the live device test results above.
